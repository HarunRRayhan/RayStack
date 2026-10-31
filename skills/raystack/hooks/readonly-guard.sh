#!/usr/bin/env bash
# RayStack read-only guard: PreToolUse hook that blocks mutating cloud/DB commands.
# stdin: PreToolUse JSON (Claude/Codex/Cursor `.tool_input.command`, Grok `.toolInput.command`). Exit 0 = allow, exit 2 = block (reason on stderr).
# Source this file to call guard_check "<cmd>" directly (0 = allow, 1 = block, reason in GUARD_REASON).
# shortcut: token heuristics, not a sandbox; aliases/functions/scripts can evade; pair with read-only credentials
# Accepted out-of-scope evasions: scripts run by path, functions/aliases, other-language SDKs.
# This guard is a seatbelt, not a boundary: always run reviews with read-only credentials.
# Design: a command that mentions a monitored CLI must be exactly
#   [NAME=literal ...] <cli> args... [| <filter> args ...]...
# and the CLI's verb must be on that CLI's read allow-list. Everything else is denied.
# SQL: one statement per command, no comments (--, /*, and # for MySQL/usql); every `name(` must be on a read-only function list.
# Unquoted glob/redirect chars ([ ] ( ) * ? ! < >), braces and a word-start # deny anywhere; mongosh/cqlsh/clickhouse/snowsql/sqlcmd/bq,
#   deploy tools and pg_dump/pg_restore always deny. Names match on `-`/`/` boundaries too (aws-cdk, amazon/aws-cli).
# Any word that is a shell, env, ssh/scp/sftp/mosh, or a package runner (npx pnpx bunx uvx) denies.
# Allow-lists, checked on every word: npm ls/list/view/outdated/audit (no fix)/why/explain; yarn/pnpm/bun --version;
#   composer audit --no-plugins --no-scripts, bundle-audit check, pip-audit (-r needs --disable-pip plus --no-deps or
#   --require-hashes), each with listed flags only (no repo plugins, scripts or package builds). Any audit
#   (npm audit too) takes the cloud-CLI shape below: one call, only filters after a pipe, no ; && || or redirects.
#   Scanners take the same shape, as the bare name, with listed flags only: gitleaks dir|git (--redact and
#   -c <this skill>/references/gitleaks.toml required, -f json, -r - only, --log-level info|warn|error|fatal), semgrep scan (--metrics off --disable-version-check, --config p/ or r/ only, --json into the documented jq filter),
#   osv-scanner scan (--no-call-analysis=go required, --format json, no image), zizmor --offline, actionlint -shellcheck= -pyflakes= (flags
#   before files), hadolint (-f json). No output files, fixes or repo configs. checkov and trivy deny in every form.
#   docker/podman/nerdctl ps, images, image ls, version, info, system df, stats --no-stream,
#   logs --tail N<=200, compose ps|ls|images|logs|config --services/--volumes (no flags before the subcommand,
#   no NAME=value, export or set anywhere in the command).
# Secret-ish cloud ops (secret, password, token, credential, keys list, ...) deny unless on a metadata list;
#   ops that return env vars, user data or passwords (lambda config, ecs task defs, launch templates) deny outright.
# gh (runs on the user's full GitHub token): bare `gh` only; api is GET on repos/... or user with -q/--jq, --paginate,
#   -X/--method GET; read subcommands repo view, pr list|view, run list|view (no --log), workflow list|view,
#   release list, secret list, auth status, with -R/--repo --json -L/--limit -b/--branch -q/--jq only.
# kubectl/oc describe only for nodes, services, ingress, events and namespaces (workloads print env values).

GUARD_REASON=""
KEYS_ONLY=0
# gitleaks must use the config shipped beside this guard, or it loads the scanned repo's .gitleaks.toml.
_GITLEAKS_CONF=$(cd "$(dirname "${BASH_SOURCE[0]}")/../references" 2>/dev/null && printf '%s/gitleaks.toml' "$(pwd -P)")
P=()
PIPE=$'\001'

_deny() { GUARD_REASON="$1"; return 1; }
_shape() { _deny "unsupported command shape during review"; }
_no() { _deny "$1 is not on the read allow-list"; }
# _secret_op "<cli path verb>": 0 (and GUARD_REASON set) when the op may print secrets and is not allow-listed.
_secret_op() {
  case "$_SECRET_OK" in *"|$1|"*) return 1 ;; esac
  [[ "$1" =~ $_SECRET_OP ]] || return 1
  _deny "$1 may print secrets or credentials"; return 0
}
_in() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
# _in_list <word> <newline-separated list>: exact whole-line match.
_in_list() { local l; while IFS= read -r l; do [ "$1" = "$l" ] && return 0; done <<< "$2"; return 1; }
# Lower-case only names/verbs/SQL; flags keep their case (-S vs -s, -X vs -x).
_lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

_NAMES='gh gitleaks semgrep osv-scanner zizmor actionlint hadolint checkov trivy aws gcloud az kubectl oc terraform tofu terragrunt helm railway wrangler redis-cli bq psql mysql mariadb sqlite3 sqlcmd mongosh clickhouse-client cqlsh snowsql usql pgcli mycli awscli pulumi cdk sam serverless sls eksctl flyctl fly doctl heroku vercel netlify supabase dropdb createdb mysqladmin vc ntl cdktf dropuser createuser pg_restore pg_dump pg_dumpall sst amplify copilot'
# `-` and `/` are boundaries, so hyphen/slash-joined names count too (aws-cdk, netlify-cli, amazon/aws-cli).
_MENTION="(^|[^a-z0-9_.])(${_NAMES// /|})([^a-z0-9_.]|\$)"
_SQL_CLIS=' psql mysql mariadb sqlite3 usql pgcli mycli '
_UNSUPPORTED=' mongosh cqlsh clickhouse-client snowsql sqlcmd bq pulumi cdk sam serverless sls eksctl flyctl fly doctl heroku vercel netlify supabase dropdb createdb mysqladmin vc ntl cdktf dropuser createuser pg_restore pg_dump pg_dumpall sst amplify copilot '
_FILTERS=' jq head tail grep sort uniq wc cut column tr '
# The only jq filter semgrep JSON may go through (references/scanners.md): error count, rule, file and line, never the matched text.
_SEMGREP_JQ='{errors: (.errors|length), results: [.results[] | {check_id, path, line: .start.line}]}'
_LONGFLAGS=' --raw-output --compact-output --count --ignore-case --unique --reverse --numeric-sort '
# No KUBECONFIG (or --kubeconfig): a kubeconfig can run exec credential plugins.
_ENV_OK=' AWS_PROFILE AWS_REGION AWS_DEFAULT_REGION AWS_PAGER PGOPTIONS PGHOST PGPORT PGUSER PGDATABASE PGSSLMODE CLOUDSDK_CORE_PROJECT CLOUDSDK_CONFIG NO_COLOR '
_AWS_VF='--profile --region --output --query --endpoint-url --color --ca-bundle --cli-read-timeout --cli-connect-timeout --cli-binary-format'
_AWS_BF='--debug --no-paginate --no-sign-request --no-verify-ssl --no-cli-pager --no-cli-auto-prompt --version --help'
_GC_VF='--project --account --format --filter --limit --zone --region --subscription --output -o --query --resource-group -g --name -n --location -l --page-size --sort-by'
_GC_BF='--quiet -q --help --version --verbose'
_KUBE_VF='-n --namespace --context --cluster --user -s --server --as --as-group --request-timeout --certificate-authority --client-certificate --client-key --cache-dir -v'
_KUBE_BF='--insecure-skip-tls-verify --help --warnings-as-errors'
_REDIS_VF='-h -p -a -n -u --user --pass --sni --cacert --cert --key -r -i -d -t -s'
_REDIS_BF='-c --tls --raw --no-raw -e --no-auth-warning --insecure'
_AWS_READ='^(describe|list|get|head|search|lookup|filter|batch-get|validate|simulate|estimate|scan|query|select|tail|wait)(-|$)'
_GC_READ='^(list|describe|show|get|get-iam-policy|read)$'
# Ops that look like they print secrets or credentials deny unless on the metadata-only list below.
_SECRET_OP='(secret|password|passwd|token|credential|login|keys? list|list-keys|access-details|connection-string|decrypt|api-key|private-key|print-|ssh-public-key)'
_SECRET_OK='|aws kms list-keys|aws kms describe-key|aws kms list-aliases|aws kms get-key-rotation-status|aws kms get-key-policy|aws iam list-access-keys|aws iam get-access-key-last-used|aws secretsmanager list-secrets|aws secretsmanager describe-secret|aws ssm describe-parameters|aws iam get-credential-report|aws iam get-login-profile|aws iam get-account-password-policy|gcloud secrets list|gcloud secrets describe|az keyvault secret list|az keyvault list|'
_GC_GROUPS=' compute instances disks images snapshots networks subnets firewall-rules routers addresses instance-templates instance-groups forwarding-rules backend-services url-maps zones regions machine-types operations projects project iam service-accounts roles keys sql databases backups users flags run services revisions jobs executions functions pubsub topics subscriptions storage buckets objects container clusters node-pools logging logs sinks metrics config configurations auth accounts dns managed-zones record-sets kms keyrings secrets versions artifacts repositories builds triggers app deployments monitoring policies organizations folders billing scheduler tasks queues redis memcache spanner bigtable firestore dataflow dataproc composer eventarc vm group resource account tag network vnet subnet nsg rule public-ip nic lb container blob queue table file webapp functionapp appservice plan aks nodepool acr repository keyvault secret key certificate role assignment definition ad user sp app monitor activity-log log-analytics workspace server db elastic-pool postgres mysql flexible-server cosmosdb lock policy provider feature deployment sub disk image snapshot vmss extension identity zone record-set eventhubs servicebus namespace topic apim cdn front-door '
_KUBE_READ='^(get|describe|logs|top|explain|version|api-resources|api-versions|cluster-info|events)$'
_REDIS_READ='^(info|get|mget|scan|ttl|pttl|type|exists|strlen|llen|scard|zcard|hlen|hget|hgetall|smembers|lrange|zrange|memory|slowlog|latency|dbsize|ping|keys|object|xinfo|xlen)$'
_SQL_WORD='(^|[^a-z0-9_])(insert|update|delete|drop|alter|truncate|create|grant|revoke|reindex|vacuum|copy|merge|call|do|comment|lock|cluster|refresh|import|load|replace|rename|attach|detach|system|source|into|set role)([^a-z0-9_]|$)'
_SQL_START='^(select|explain|show|with|describe|desc)([^a-z0-9_]|$)'
# Every `word(` in a statement must be one of these read-only functions or SQL keywords.
_SQL_FN_OK=' count sum avg min max coalesce nullif greatest least round abs lower upper length trim substring to_char extract cast date_trunc age now current_date current_timestamp array_agg string_agg json_agg jsonb_agg row_number rank dense_rank lag lead pg_size_pretty pg_total_relation_size pg_relation_size pg_table_size pg_indexes_size pg_database_size pg_stat_get_live_tuples version current_setting has_table_privilege exists in any all filter over as from where and or not on using join when then else select explain '
# sqlite pragmas: `pragma x(arg)` also sets values, so only read pragmas, and the arg form only for table/index lookups.
_PRAGMA_RO='^pragma ([a-z_]+\.)?((table_info|table_xinfo|index_list|index_info|index_xinfo|foreign_key_list)\([a-z0-9_ "]+\)|database_list|table_list|user_version|schema_version|page_count|page_size|freelist_count|integrity_check|quick_check|compile_options|function_list|collation_list|encoding|journal_mode)$'

# _walk N "<value flags>" "<bool flags>" args...: fill P with the first N non-flag words.
# Flags before the path is complete must be known, else deny; only listed value flags eat a word.
_walk() {
  local n=$1 vf=$2 bf=$3 nm; shift 3; P=()
  while [ $# -gt 0 ] && [ ${#P[@]} -lt "$n" ]; do
    case "$1" in
      -*) nm=${1%%=*}
          if _in "$nm" "$vf"; then [ "$nm" = "$1" ] && shift
          elif ! _in "$nm" "$bf"; then _deny "unknown flag before subcommand: $1"; return 1; fi ;;
      *) P+=("$(_lc "$1")") ;;
    esac
    shift
  done
  return 0
}

# _flags_ok "<value flags>" "<bool flags>" args...: every word is a listed flag; value flags take =v or the next word.
_flags_ok() {
  local vf=$1 bf=$2 nm; shift 2
  while [ $# -gt 0 ]; do
    nm=${1%%=*}
    if _in "$nm" "$vf"; then [ "$nm" = "$1" ] && { [ $# -gt 1 ] && [ "${2#-}" = "$2" ] || return 1; shift; }
    elif [ "$nm" != "$1" ] || ! _in "$1" "$bf"; then return 1; fi
    shift
  done
  return 0
}

# _scan_args "<value flags>" "<bool flags>" args...: like _flags_ok, but bare words are paths (SP) and each
# flag lands in SF as `flag` or `flag=value`; LATE=1 when a flag follows a path. Only values may hold spaces.
_scan_args() {
  local vf=$1 bf=$2 nm; shift 2; SF=(); SP=(); LATE=0
  while [ $# -gt 0 ]; do
    nm=${1%%=*}
    case "$nm" in *[[:space:]]*) return 1 ;; esac
    if [ "${1#-}" = "$1" ] || [ "$1" = - ]; then SP+=("$1")
    else
      [ ${#SP[@]} = 0 ] || LATE=1
      if _in "$nm" "$vf"; then
        if [ "$nm" = "$1" ]; then
          [ $# -gt 1 ] && { [ "${2#-}" = "$2" ] || [ "$2" = - ]; } || return 1
          SF+=("$1=$2"); shift
        else SF+=("$1"); fi
      elif [ "$nm" = "$1" ] && _in "$1" "$bf"; then SF+=("$1")
      else return 1; fi
    fi
    shift
  done
  return 0
}
# _has <prefix>: some SF entry starts with it. _vals <flag> <regex>: every value given to <flag> matches.
_has() { local w; for w in "${SF[@]}"; do case "$w" in "$1"*) return 0 ;; esac; done; return 1; }
_vals() { local w; for w in "${SF[@]}"; do case "$w" in "$1="*) [[ "${w#*=}" =~ ^($2)$ ]] || return 1 ;; esac; done; return 0; }

# _tail_ok args...: a --tail N with N <= 200 is present (bounded log reads).
_tail_ok() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --tail) [[ "${2:-}" =~ ^[0-9]{1,3}$ ]] && [ "$2" -le 200 ] && return 0 ;;
      --tail=*) [[ "${1#*=}" =~ ^[0-9]{1,3}$ ]] && [ "${1#*=}" -le 200 ] && return 0 ;;
    esac
    shift
  done
  return 1
}

# _docker_ok <docker|podman|nerdctl|*-compose> words...: 0 when the call is a listed read subcommand.
# No flag may come before the subcommand (global flags pick other daemons or configs).
_docker_ok() {
  local base=$1 w; shift
  case "$base" in *-compose) set -- compose "$@" ;; esac
  case "${1:-}" in -*) _deny "$base flag before subcommand: $1"; return 1 ;; esac
  case "$(_lc "${1:-} ${2:-}")" in
    # No container or image inspect: Config.Env can hold secrets.
    " "|"ps "*|"images "*|"version "*|"info "*|"image ls"|"system df"|"compose ps"|"compose ls"|"compose images") return 0 ;;
    "logs "*|"compose logs") _tail_ok "$@" && return 0
      _deny "$base logs only with --tail N (N at most 200)"; return 1 ;;
    "stats "*) case " $* " in *" --no-stream "*) return 0 ;; esac ;;
    # config prints interpolated secrets: only the service or volume names.
    "compose config")
      shift 2; [ $# -gt 0 ] || { _deny "docker compose config only with --services or --volumes"; return 1; }
      for w in "$@"; do
        case "$w" in --services|--volumes) ;; *) _deny "docker compose config only with --services or --volumes"; return 1 ;; esac
      done
      return 0 ;;
  esac
  _no "$base ${1:-} ${2:-}"
}

# _tf_only <name=value> args...: every -name/--name flag in args is exactly that value, and one exists.
_tf_only() {
  local want=$1 key=${1%%=*} w nm found=1; shift
  for w in "$@"; do
    case "$w" in -*) nm=${w#-}; nm=${nm#-}
      case "$nm" in "$key"|"$key"=*) [ "$nm" = "$want" ] || return 1; found=0 ;; esac ;;
    esac
  done
  return $found
}

# _eval_cli <cli> args...: 0 = read-only, 1 = block (GUARD_REASON set).
_eval_cli() {
  local cli="$1" a b w nm seen=0; shift
  case "$cli" in
    kubectl|oc|helm|terraform|tofu|terragrunt)
      # _walk stops at the verb; these flags load executables/credentials or move state anywhere
      # in argv. Go flags take one or two dashes, so match with the dashes stripped.
      for w in "$@"; do
        case "$w" in -*) nm=${w#-}; nm=${nm#-}
          case "$nm" in config*|kubeconfig*|plugin*|migrate-state*|force-copy*|post-renderer*|terragrunt-tfpath*|tf-path*|exec*|token*)
            _deny "$cli flag ${w%%=*} not allowed during review"; return 1 ;;
          esac ;;
        esac
      done ;;
  esac
  case "$cli" in
    aws)
      _walk 2 "$_AWS_VF" "$_AWS_BF" "$@" || return 1
      a="${P[0]:-}"; b="${P[1]:-}"
      [ -z "$b" ] && [ "$a" != configure ] && return 0
      _secret_op "aws $a $b" && return 1
      # The CLI accepts unique prefixes of long flags (--w for --with-decryption).
      for w in "$@"; do
        w=${w%%=*}
        case "$w" in --?*) ;; *) continue ;; esac
        for nm in --with-decryption --include-value --include-values --cli-input-json --cli-input-yaml --generate-cli-skeleton; do
          [ "$w" != "$nm" ] && [[ "$nm" == "$w"* ]] && { _deny "aws flag $w is an abbreviation of $nm"; return 1; }
        done
      done
      # Env vars, user data and passwords: no --query or flag filters them reliably, so deny outright.
      case "$a $b" in
        "ssm get-parameter"*|"cognito-idp describe-user-pool-client"|"lambda get-function"|"lambda get-function-configuration"|"lambda list-functions"|"lambda list-versions-by-function"|"ecs describe-task-definition"|"ec2 describe-launch-template-versions"|"ec2 get-launch-template-data"|"glue get-connection"|"glue get-connections")
          _deny "aws $a $b prints env vars, user data or secrets"; return 1 ;;
        "ec2 describe-instance-attribute") [[ "$(_lc "$*")" == *userdata* ]] && { _deny "aws $a $b userData can hold secrets"; return 1; } ;;
      esac
      [ "$a $b" = "configure get" ] && [[ "$(_lc "$*")" =~ $_SECRET_OP ]] && { _deny "aws configure get prints credentials"; return 1; }
      case "$a $b" in
        "s3 ls"|"logs start-query"|"logs stop-query"|"logs get-query-results"|"configure list"|"configure get"|"configure list-profiles") return 0 ;;
      esac
      [ "$a" != s3 ] && [ "$a" != configure ] && [[ "$b" =~ $_AWS_READ ]] && return 0
      _no "aws $a $b" ;;
    gcloud|az)
      # Exact path: known group words, then a read verb; unknown words or write verbs deny.
      b=""
      while [ $# -gt 0 ]; do
        case "$1" in
          -*) nm=${1%%=*}
              if _in "$nm" "$_GC_VF"; then [ "$nm" = "$1" ] && shift
              elif ! _in "$nm" "$_GC_BF"; then _deny "unknown flag before verb: $1"; return 1; fi ;;
          *) w=$(_lc "$1")
             if [[ "$w" =~ $_GC_READ ]] && [ $seen -gt 0 ]; then
               _secret_op "$cli$b $w" && return 1
               return 0
             elif [ $seen = 0 ] && [[ "$w" =~ ^(version|info)$ ]]; then return 0
             elif _in "$w" "$_GC_GROUPS"; then seen=$((seen + 1)); b="$b $w"
             else _deny "$cli path word '$w' is not on the read allow-list"; return 1; fi ;;
        esac
        shift
      done
      [ $seen = 0 ] && return 0
      _no "$cli command" ;;
    kubectl|oc)
      _walk 1 "$_KUBE_VF" "$_KUBE_BF" "$@" || return 1
      a="${P[0]:-}"
      if [ "$a" = get ]; then
        # Flag allow-list: no --raw (any API path), -f/-k/-R (files), -w (watch loops).
        set -- "$@" ""
        while [ $# -gt 1 ]; do
          w=$1; nm=""
          case "$w" in
            -o|--output) nm=$2; shift ;;
            -o=*|--output=*) nm=${w#*=} ;;
            -o?*) nm=${w#-o} ;;
          esac
          case "$w:$nm" in
            -o*:?*|--output*:?*) case "$nm" in json|yaml|wide|name|jsonpath=*|custom-columns=*) ;; *) _deny "$cli get -o $nm not allowed during review"; return 1 ;; esac
                                 shift; continue ;;
          esac
          case "$w" in
            -n?*|-l?*|-A|--all-namespaces|--show-labels|--no-headers) ;;
            -*) nm=${w%%=*}
                _in "$nm" "-l --selector --field-selector --sort-by $_KUBE_VF $_KUBE_BF" || { _deny "$cli get flag $nm not allowed during review"; return 1; } ;;
          esac
          [[ "$(_lc "$w")" =~ (^|[,/])secrets?([/,.?]|$) ]] && { _deny "$cli get secret prints secret values"; return 1; }
          shift
        done
      fi
      # describe prints literal env values for workloads: only kinds without pod templates.
      if [ "$a" = describe ]; then
        _walk 2 "$_KUBE_VF" "$_KUBE_BF" "$@" || return 1
        w=${P[1]:-}; w=${w%%/*}; w=${w%%.*}
        _in "$w" "node nodes no service services svc ingress ingresses ing event events ev namespace namespaces ns" && return 0
        _deny "$cli describe ${P[1]:-} not allowed during review (env values)"; return 1
      fi
      [ -z "$a" ] || [[ "$a" =~ $_KUBE_READ ]] && return 0
      if [ "$a" = auth ] || [ "$a" = config ]; then
        _walk 2 "$_KUBE_VF" "$_KUBE_BF" "$@" || return 1
        case "$a ${P[1]:-} $* " in "config view "*" --raw"*) _deny "$cli config view --raw prints credentials"; return 1 ;; esac
        case "$a ${P[1]:-}" in "auth can-i"|"config view"|"config get-contexts") return 0 ;; esac
      fi
      _no "$cli $a" ;;
    terraform|tofu|terragrunt)
      _walk 1 "-chdir" "-help -version" "$@" || return 1
      a="${P[0]:-}"
      case "$a" in
        # No show or state show: they print attribute values, sensitive ones included.
        ''|validate|providers|version|graph) return 0 ;;
        # init must not touch the backend; plan must not take the state lock.
        init) _tf_only backend=false "$@" && return 0
              _deny "$cli init only with -backend=false during review"; return 1 ;;
        plan) _tf_only lock=false "$@" && return 0
              _deny "$cli plan only with -lock=false during review"; return 1 ;;
        fmt) case " $* " in *" -check "*) return 0 ;; esac ;;
        state) _walk 2 "-chdir" "-help" "$@" || return 1
               [ "${P[1]:-}" = list ] && return 0 ;;
      esac
      _no "$cli $a" ;;
    helm)
      _walk 1 "-n --namespace --kube-context" "--help" "$@" || return 1
      case "${P[0]:-}" in
        # No template: --validate and --dry-run=server reach the cluster.
        ''|version|search) return 0 ;;
        # Table output only: -o json/yaml includes release values.
        list|ls|status|history) case " $* " in *" -o"*|*" --output"*) _deny "helm ${P[0]} -o not allowed during review"; return 1 ;; esac
                                # status prints release notes, which can hold secrets.
                                [ "${P[0]}" != status ] || case " $* " in *" --hide-notes "*) ;; *) _deny "helm status only with --hide-notes"; return 1 ;; esac
                                return 0 ;;
        # get values/all/manifest/notes/hooks can print secrets.
        get) _walk 2 "-n --namespace --kube-context --revision" "--help" "$@" || return 1
             [ "${P[1]:-}" = metadata ] && return 0 ;;
      esac
      _no "helm ${P[*]}" ;;
    railway)
      case " $* " in *" --set"*) _deny "railway --set"; return 1 ;; esac
      _walk 1 "" "--help --version" "$@" || return 1
      a="${P[0]:-}"
      case "$a" in
        ''|status|logs|list|whoami|service) return 0 ;;
        # Values only as names: guard_check requires the output piped into exactly `jq 'keys'`.
        variable|variables) _walk 2 "-s --service -e --environment" "--json" "$@" || return 1
                            case " $* " in *" --kv"*) _deny "railway variables --kv prints values"; return 1 ;; esac
                            case " $* " in *" --json "*) ;; *) _deny "railway variables only as: railway variables --json | jq 'keys'"; return 1 ;; esac
                            case "${P[1]:-}" in ''|list) KEYS_ONLY=1; return 0 ;; esac ;;
      esac
      _no "railway $a" ;;
    wrangler)
      _walk 3 "--env -e --config -c" "--help --version -v" "$@" || return 1
      case "${P[*]}" in
        ''|whoami|tail|"tail "*|"deployments list"|"versions list"|"d1 list"|"d1 info "*|"r2 bucket list"|"kv namespace list"|"kv key list"|"kv key list "*|"kv key get "*) return 0 ;;
      esac
      _no "wrangler ${P[*]}" ;;
    redis-cli)
      _walk 1 "$_REDIS_VF" "$_REDIS_BF" "$@" || return 1
      a="${P[0]:-}"
      [ -z "$a" ] && return 0
      for w in "$@"; do [ "$(_lc "$w")" = reset ] && { _deny "redis-cli reset"; return 1; }; done
      [[ "$a" =~ $_REDIS_READ ]] && return 0
      if [ "$a" = client ] || [ "$a" = config ]; then
        _walk 2 "$_REDIS_VF" "$_REDIS_BF" "$@" || return 1
        case "$a ${P[1]:-}" in "client list"|"config get") return 0 ;; esac
      fi
      _no "redis-cli $a" ;;
    gh)
      a=$(_lc "${1:-}"); b=$(_lc "${2:-}")
      if [ "$a" = api ]; then
        shift; b=""
        while [ $# -gt 0 ]; do
          case "$1" in
            -q|--jq) [ $# -gt 1 ] || { _deny "gh api $1 needs a value"; return 1; }; w=$2; shift ;;
            -q?*|--jq=*) w=${1#-q}; w=${w#--jq}; w=${w#=} ;;
            --paginate) w="" ;;
            -X|--method) [ $# -gt 1 ] && [ "$(_lc "$2")" = get ] || { _deny "gh api only with method GET"; return 1; }; shift ;;
            -X?*|--method=*) nm=${1#-X}; nm=${nm#--method}
                             [ "$(_lc "${nm#=}")" = get ] || { _deny "gh api only with method GET"; return 1; } ;;
            # -f/-F/--field/--raw-field/--input switch to POST; -H/--hostname and the rest are not reads we need.
            -*) _deny "gh api flag ${1%%=*} not allowed during review"; return 1 ;;
            *) [ -z "$b" ] || { _deny "gh api takes one endpoint"; return 1; }; b=$1 ;;
          esac
          [[ "$(_lc "${w:-}")" =~ (^|[^a-z0-9_])env([^a-z0-9_]|$) ]] && { _deny "gh api --jq env prints the environment"; return 1; }
          w=""; shift
        done
        [[ "$b" =~ ^(repos/[^[:space:]]+|user)$ ]] || { _deny "gh api only on repos/... or user"; return 1; }
        case "/$b/" in */../*|*/logs/*) _deny "gh api path $b not allowed during review"; return 1 ;; esac
        return 0
      fi
      case "$a $b" in
        "repo view"|"pr list"|"pr view"|"run list"|"run view"|"workflow list"|"workflow view"|"release list"|"secret list"|"auth status") shift 2 ;;
        *) _no "gh $a $b"; return 1 ;;
      esac
      # No --log (run output), -t/--show-token, --web or templates: only these flags; bare words are numbers or names.
      _scan_args "-R --repo --json -L --limit -b --branch -q --jq" "" "$@" || { _deny "gh $a $b flag not on the read allow-list"; return 1; }
      for w in "${SF[@]}"; do
        case "$w" in -q=*|--jq=*) [[ "$(_lc "${w#*=}")" =~ (^|[^a-z0-9_])env([^a-z0-9_]|$) ]] && { _deny "gh --jq env prints the environment"; return 1; } ;; esac
      done
      return 0 ;;
    *) _sql_check "$cli" "$@" ;;
  esac
}

# SQL clients: positive flag allow-list; exactly one statement, only from argv, and a plain read.
_sql_check() {
  local cli="$1" sf="" vf="" bf="" st="" ns=0 np=0 nm w
  # Per-client value flags: a boolean flag listed as taking a value would swallow the next word (-U -e ...).
  local pg_vf="-h -U -d -p --host --port --username --dbname" my_vf="-u -h -P -D --host --port --user --database --protocol --ssl-mode"
  shift
  case "$cli" in
    psql) sf="-c --command"; vf=$pg_vf; bf="-W -w -X -A -t -q -x --csv --json" ;;
    pgcli) vf=$pg_vf; bf="-W -w" ;;
    mysql|mariadb|mycli) sf="-e --execute"; vf=$my_vf; bf="-U --safe-updates -p -B -N -t --batch --skip-column-names --table" ;;
    usql) sf="-c --command"; bf="-q -J -C --json --csv" ;;
    sqlite3) bf="-readonly -json -csv -header -noheader -line -list -column" ;;
  esac
  while [ $# -gt 0 ]; do
    w="$1"
    case "$w" in
      -*) nm=${w%%=*}
          if _in "$nm" "$sf"; then
            ns=$((ns + 1))
            if [ "$nm" = "$w" ]; then st="${2:-}"; [ $# -gt 1 ] && shift; else st="${w#*=}"; fi
          elif [ "${w#--}" = "$w" ] && _in "${w:0:2}" "$sf" && [ ${#w} -gt 2 ]; then ns=$((ns + 1)); st="${w:2}"
          elif _in "$nm" "$vf"; then [ "$nm" = "$w" ] && [ $# -gt 1 ] && shift
          elif [ "${w#--}" = "$w" ] && _in "${w:0:2}" "$vf" && [ ${#w} -gt 2 ]; then :
          elif ! _in "$nm" "$bf"; then _deny "$cli flag $w is not on the read allow-list"; return 1; fi ;;
      *) np=$((np + 1)); [ "$cli" = sqlite3 ] && [ $np = 2 ] && st="$w" ;;
    esac
    shift
  done
  # psql/mysql run every -c/-e in turn, so more than one could hide a write.
  [ $ns -le 1 ] || { _deny "$cli: only one statement per command"; return 1; }
  if [ "$cli" = sqlite3 ]; then
    [ $np = 2 ] || { _deny "sqlite3 needs exactly: db statement"; return 1; }
  elif [ $np -gt 1 ]; then _deny "$cli: too many positional arguments"; return 1; fi
  [ $ns = 0 ] && [ "$cli" != sqlite3 ] && return 0
  _sql_stmt "$cli" "$st"
}

_sql_stmt() {
  local s rest pre
  s=$(_lc "$2"); s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"; s="${s%;}"
  # Comments can hide the gap between a function name and `(` (name--<newline>()); MySQL also uses #.
  case "$s" in *\;*|*/\**|*--*) _deny "$1 statement has multiple statements or comments"; return 1 ;; esac
  case "$1:$s" in mysql:*\#*|mariadb:*\#*|mycli:*\#*|usql:*\#*) _deny "$1 statement has a # comment"; return 1 ;; esac
  if [[ "$s" =~ ^pragma ]]; then
    [[ "$s" =~ $_PRAGMA_RO ]] && return 0
    _deny "sqlite pragma is not on the read allow-list"; return 1
  fi
  [[ "$s" =~ $_SQL_START ]] || { _deny "$1 statement is not a plain read"; return 1; }
  if [[ " $s " =~ $_SQL_WORD ]]; then _deny "SQL write statement (${BASH_REMATCH[2]})"; return 1; fi
  # Each `(` follows an operator/`(`/`,` (grouping) or a bare word on the read-only function list.
  rest="$s"
  while [[ "$rest" == *"("* ]]; do
    pre=${rest%%(*}; rest=${rest#*(}
    pre="${pre%"${pre##*[![:space:]]}"}"
    case "$pre" in ''|*[\(,=\<\>+*/\|-]) continue ;; esac
    if [[ "$pre" =~ (^|[^a-z0-9_.])([a-z_][a-z0-9_]*)$ ]] && _in "${BASH_REMATCH[2]}" "$_SQL_FN_OK"; then continue; fi
    _deny "function not on read-only list (${pre##*[^a-z0-9_.\"]})"; return 1
  done
  return 0
}

# Filter args: per-filter flag shapes; positionals capped (jq/grep one pattern, tr two sets, else none).
_filter_ok() {
  local f=$1 max=0 np=0; shift
  case "$f" in jq|grep) max=1 ;; tr) max=2 ;; esac
  while [ $# -gt 0 ]; do
    case "$f:$1" in
      head:-n|tail:-n) [[ "${2:-}" =~ ^[0-9]+$ ]] || return 1; shift ;;
      head:-*|tail:-*) [[ "$1" =~ ^-n?[0-9]+$ ]] || return 1 ;;
      cut:-[fdc]|column:-s) [ $# -gt 1 ] || return 1; shift ;;
      cut:-[fdc]?*|column:-s?*|column:-t) ;;
      jq:-*) [[ "$1" =~ ^-[rjacnseSCM]+$ ]] || _in "$1" "$_LONGFLAGS" || return 1 ;;
      grep:-*|sort:-*|uniq:-*|wc:-*)
        [[ "$1" =~ ^-[a-zA-Z0-9]+$ ]] || _in "$1" "$_LONGFLAGS" || return 1
        [ "$f" = sort ] && [[ "$1" =~ ^-[^-]*[oT] ]] && return 1 ;;
      tr:-*) [[ "$1" =~ ^-[dscC]+$ ]] || return 1 ;;
      *:-*) return 1 ;;
      *) np=$((np + 1)); [ $np -le $max ] || return 1
         # jq `env` dumps every secret in the environment into the transcript.
         [ "$f" = jq ] && [[ "$(_lc "$1")" =~ (^|[^a-z0-9_])env([^a-z0-9_]|$) ]] && return 1 ;;
    esac
    shift
  done
  return 0
}

guard_check() {
  local lc strip q="" ch tok="" intok=0 ops=0 tilde=0 i j n base name f w vf bf seen audit=0 LATE=0 sgjq=0
  local -a TOK ARGS SF SP
  GUARD_REASON=""
  case "$1" in
    *\\*|*'`'*|*\$*) _deny "dynamic command during review"; return 1 ;;
  esac

  # Quote-aware tokenizer: `|` outside quotes becomes a PIPE marker; other operators are noted.
  TOK=()
  for ((i = 0; i < ${#1}; i++)); do
    ch=${1:i:1}
    if [ -n "$q" ]; then
      if [ "$ch" = "$q" ]; then q=""; else tok+=$ch; fi
      continue
    fi
    case "$ch" in
      \"|\') q=$ch; intok=1 ;;
      '{'|'}') _deny "brace expansion/group during review"; return 1 ;;
      # Unquoted glob/extglob/history characters (bash and zsh) could expand to any CLI name.
      # `<`/`>` too: zsh numeric ranges (sqlite<3-3>) and redirections.
      # `^`: zsh EXTENDED_GLOB negation (^x matches every other file name).
      '['|']'|'('|')'|'*'|'?'|'!'|'<'|'>'|'^') _deny "unquoted glob/redirect character '$ch' during review"; return 1 ;;
      ' '|$'\t'|'|'|';'|'&'|$'\n')
        [ $intok = 1 ] && TOK+=("$tok")
        tok=""; intok=0
        case "$ch" in
          ' '|$'\t') ;;
          '|') TOK+=("$PIPE") ;;
          *) ops=1 ;;
        esac ;;
      # A word-start `#` starts a shell comment the checks below would not see; mid-word it is a zsh EXTENDED_GLOB operator.
      '#') _deny "unquoted # during review"; return 1 ;;
      *) [ $intok = 0 ] && [ "$ch" = '~' ] && tilde=1
         tok+=$ch; intok=1 ;;
    esac
  done
  [ $intok = 1 ] && TOK+=("$tok")

  lc=$(_lc "$1"); strip=${lc//[\"\']/}
  # Package runners fetch and execute any tool (npx aws-cdk deploy); container CLIs are a read allow-list.
  n=${#TOK[@]}
  for ((i = 0; i < n; i++)); do
    # Prefixes catch CLI abbreviations; --cli-input-* and skeletons can smuggle the same options.
    case "${TOK[i]}" in --with-d*|--include-v*|--cli-in*|--generate-cli*) _deny "${TOK[i]%%=*} not allowed during review"; return 1 ;; esac
    # zsh expands a leading `=` (=composer is the path of composer), so it names the same CLI.
    name=$(_lc "${TOK[i]##*/}"); name=${name#=}
    case "$name" in
      python*|pypy*|py)
        # `.` is not a _MENTION boundary (docs/aws.md), so `-m awscli.clidriver` is caught here.
        for ((j = i + 1; j < n; j++)); do
          [ "${TOK[j]}" = "$PIPE" ] && break
          w=""
          if [[ "${TOK[j]}" =~ ^-[A-Za-z]*m$ ]]; then w=${TOK[j + 1]:-}
          elif [[ "${TOK[j]}" =~ ^-[A-Za-z]*m(.+)$ ]]; then w=${BASH_REMATCH[1]}; fi
          [[ "$(_lc "$w")" =~ ^(${_NAMES// /|})(\.|$) ]] && { _deny "python -m $w during review"; return 1; }
        done
        continue ;;
      npx|pnpx|bunx|uvx) _deny "package runners are not allowed during a review"; return 1 ;;
      npm|pnpm|yarn|bun)
        # Read allow-list; npm accepts prefixes and aliases (exe, innit, c), and yarn/pnpm/bun run a
        # package.json script for any verb they don't know, so they only get --version.
        case "$name $(_lc "${TOK[i + 1]:-}") $(_lc "${TOK[i + 2]:-}")" in
          *" --version "|"npm -v ") continue ;;
          "npm ls "*|"npm list "*|"npm view "*|"npm outdated "*|"npm why "*|"npm explain "*) continue ;;
          "npm audit "*) audit=1
             [ "${TOK[i]}" = npm ] || { _deny "npm audit only as the bare command name"; return 1; }
             for ((j = i + 1; j < n; j++)); do
               [ "${TOK[j]}" = "$PIPE" ] && break
               case "$(_lc "${TOK[j]}")" in fix|--fix*) _deny "$name audit fix not allowed during review"; return 1 ;;
                 *[[:space:]]*) _deny "$name audit argument with whitespace"; return 1 ;; esac
             done
             continue ;;
        esac
        _deny "$name ${TOK[i + 1]:-} is not on the read allow-list"; return 1 ;;
      composer|bundle|bundle-audit|pip-audit)
        # Dependency audits only: the audit verb first, then listed flags; every other verb runs code or writes.
        # No `bundle audit`: Bundler loads the repo-local plugin index for it.
        # A path (./vendor/bin/composer, bin/pip-audit) or `=name` runs a repo-local or other binary.
        [ "${TOK[i]}" = "$name" ] || { _deny "$name only as the bare command name"; return 1; }
        j=$((i + 1))
        case "$name $(_lc "${TOK[j]:-}")" in
          "composer audit") j=$((j + 1))
            vf='-f --format --abandoned --ignore-severity'
            bf='--locked --no-dev --ignore-unreachable --no-plugins --no-scripts -n --no-interaction --no-ansi --ansi -q --quiet -v -vv -vvv' ;;
          # update/download and --update pull the advisory DB; -o writes a file.
          "bundle-audit check") j=$((j + 1))
            vf='-F --format -i --ignore --gemfile-lock'
            bf='-q --quiet -v --verbose' ;;
          # No --fix, -o (writes a file), --cache-dir or a project path (builds it).
          "pip-audit "*)
            vf='-r --requirement -f --format -s --vulnerability-service --ignore-vuln --timeout'
            bf='-l --local --strict --skip-editable --no-deps --require-hashes --disable-pip --desc --aliases -v --verbose' ;;
          *) _deny "$name ${TOK[j]:-} is not on the read allow-list"; return 1 ;;
        esac
        ARGS=()
        for ((; j < n; j++)); do
          [ "${TOK[j]}" = "$PIPE" ] && break
          ARGS+=("${TOK[j]}")
        done
        _flags_ok "$vf" "$bf" "${ARGS[@]}" || { _deny "$name audit flag not on the read allow-list"; return 1; }
        # Composer plugins/scripts and pip-installed requirements are repo-controlled code.
        # Exact per-word matches: a quoted word could hold several flags ("--no-plugins --no-scripts").
        seen=' '
        for w in "${ARGS[@]}"; do
          case "$w" in
            *[[:space:]]*) _deny "$name audit argument with whitespace"; return 1 ;;
            --no-plugins|--no-scripts|--disable-pip|--no-deps|--require-hashes) seen+="$w " ;;
            # Every spelling _flags_ok lets through; -rX and --req abbreviations are denied there.
            -r|-r=*|--requirement|--requirement=*) seen+="-r " ;;
          esac
        done
        if [ "$name" = composer ] && { ! _in --no-plugins "$seen" || ! _in --no-scripts "$seen"; }; then
          _deny "composer audit only with --no-plugins --no-scripts"; return 1
        fi
        if [ "$name" = pip-audit ] && _in -r "$seen" && { ! _in --disable-pip "$seen" || { ! _in --no-deps "$seen" && ! _in --require-hashes "$seen"; }; }; then
          _deny "pip-audit -r only with --disable-pip and --no-deps or --require-hashes"; return 1
        fi
        audit=1; continue ;;
      gitleaks|semgrep|osv-scanner|zizmor|actionlint|hadolint)
        # Scanners: the read form only, with no output file, fix or repo config. A path or `=name` runs another binary.
        [ "${TOK[i]}" = "$name" ] || { _deny "$name only as the bare command name"; return 1; }
        j=$((i + 1))
        case "$name $(_lc "${TOK[j]:-}")" in
          "gitleaks dir"|"gitleaks git") j=$((j + 1)); vf='-f -r --log-level -c --config'; bf='--redact --no-banner' ;;
          "semgrep scan") j=$((j + 1)); vf='--config --metrics --severity'; bf='--disable-version-check --json --quiet' ;;
          "osv-scanner scan") j=$((j + 1)); vf='--format --no-call-analysis'; bf='-r --no-resolve --offline --download-offline-databases' ;;
          "zizmor "*) vf='--format'; bf='--offline --no-config' ;;
          "actionlint "*) vf='-shellcheck -pyflakes -format'; bf='-oneline' ;;
          "hadolint "*) vf='-f'; bf='' ;;
          *) _deny "$name ${TOK[j]:-} is not on the read allow-list"; return 1 ;;
        esac
        ARGS=()
        for ((; j < n; j++)); do
          [ "${TOK[j]}" = "$PIPE" ] && break
          ARGS+=("${TOK[j]}")
        done
        _scan_args "$vf" "$bf" "${ARGS[@]}" || { _deny "$name flag not on the read allow-list"; return 1; }
        case "$name" in
          gitleaks) { _has --redact && _vals -f json && _vals -r -; } || { _deny "gitleaks only with --redact, -f json and -r - (stdout)"; return 1; }
            # A repo config can redact almost nothing; only RayStack's config, compared as a string.
            seen=0
            for w in "${SF[@]}"; do
              case "$w" in -c=*|--config=*) if [ "${w#*=}" = "$_GITLEAKS_CONF" ] && [ "$seen" = 0 ]; then seen=1; else seen=2; fi ;; esac
            done
            [ "$seen" = 1 ] && [ -n "$_GITLEAKS_CONF" ] || { _deny "gitleaks only with -c $_GITLEAKS_CONF"; return 1; }
            # trace and debug logs print findings unredacted.
            _vals --log-level 'info|warn|error|fatal' || { _deny "gitleaks --log-level only info, warn, error or fatal"; return 1; } ;;
          # No --config means repo .semgrep.yml; metrics or version checks phone home.
          # A local p/ or r/ dir would be read as rules: data, not code.
          semgrep) { _has --config= && _vals --config '[pr]/[A-Za-z0-9._-]+' && _has --metrics=off && _vals --metrics off && _has --disable-version-check; } ||
            { _deny "semgrep scan only with --config p/ or r/, --metrics off and --disable-version-check"; return 1; }
            # Plain text and raw JSON print the matched line, which can be a secret: --json into the documented jq only.
            _has --json || { _deny "semgrep scan only with --json piped to the documented jq filter"; return 1; }
            sgjq=1 ;;
          # `scan image` pulls and unpacks container images.
          # Go call analysis is on by default and needs the go toolchain; --call-analysis is not listed.
          osv-scanner) { _vals --format json && _has --no-call-analysis= && _vals --no-call-analysis go && [ "$(_lc "${SP[0]:-}")" != image ]; } ||
            { _deny "osv-scanner scan only with --no-call-analysis=go, --format json and paths"; return 1; } ;;
          zizmor) { _has --offline && _vals --format json; } || { _deny "zizmor only with --offline and --format json"; return 1; } ;;
          # Go flag parsing stops at the first file, so later flags would be files; unset checkers run binaries.
          actionlint) { [ $LATE = 0 ] && _has -shellcheck= && _vals -shellcheck '' && _has -pyflakes= && _vals -pyflakes ''; } ||
            { _deny "actionlint only with -shellcheck= -pyflakes= before any file"; return 1; } ;;
          hadolint) _vals -f json || { _deny "hadolint only with -f json"; return 1; } ;;
        esac
        audit=1; continue ;;
      # D-006: no read-only form; the human runs them.
      checkov|trivy) _deny "$name is not allowed during review: list its commands for the human to run"; return 1 ;;
      pipx|uv) f=' run ' ;;
      # A shell (or env) runs a string or a command these checks never see.
      sh|bash|zsh|dash|ksh|mksh|fish|csh|tcsh|busybox|env|ssh|scp|sftp|mosh) _deny "$name not allowed during review"; return 1 ;;
      docker|podman|nerdctl|docker-compose|podman-compose)
        # DOCKER_HOST, COMPOSE_FILE and friends point the read at another daemon or file.
        for w in "${TOK[@]}"; do
          [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || _in "$w" "export declare typeset set" || continue
          _deny "env assignment with $name not allowed during review"; return 1
        done
        f='' ;;
      *) continue ;;
    esac
    ARGS=()
    for ((j = i + 1; j < n; j++)); do
      [ "${TOK[j]}" = "$PIPE" ] && break
      ARGS+=("${TOK[j]}")
    done
    if [ -z "$f" ]; then _docker_ok "$name" "${ARGS[@]}" || return 1; continue; fi
    # shortcut: any later word in the pipe segment counts (npm ls x denies), fail closed.
    for w in "${ARGS[@]}"; do
      _in "$(_lc "$w")" "$f" && { _deny "package runners are not allowed during a review"; return 1; }
    done
  done
  # RayStack's own skill names (report paths like reviews/...-aws-billing-review.md) are not CLI mentions.
  for name in aws-billing-review aws-security-review aws-bottleneck-review; do strip=${strip//$name/ }; done
  [[ "$strip" =~ $_MENTION ]] || [ $audit = 1 ] || return 0
  if [ -n "$q" ] || [ $ops = 1 ]; then _shape; return 1; fi
  [ $tilde = 0 ] || { _deny "leading ~ in a word during review"; return 1; }

  n=${#TOK[@]}; i=0
  while [ "$i" -lt "$n" ] && [[ "${TOK[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    name=${TOK[i]%%=*}
    _in "$name" "$_ENV_OK" || { _deny "env var $name is not allowed"; return 1; }
    [ "$name" = AWS_PAGER ] && [ -n "${TOK[i]#*=}" ] && { _deny "AWS_PAGER must be empty"; return 1; }
    i=$((i + 1))
  done
  [ "$i" -lt "$n" ] || { _shape; return 1; }
  base=$(_lc "${TOK[i]##*/}")
  # A path, `=gh` or `GH` (case-insensitive filesystems) could run another binary on the same token.
  [ "$base" != gh ] || [ "${TOK[i]}" = gh ] || { _deny "gh only as the bare command name"; return 1; }
  case "$base" in
    gh|aws|gcloud|az|kubectl|oc|terraform|tofu|terragrunt|helm|railway|wrangler|redis-cli) ;;
    # Audit words were checked in the loop above; here only the shape is enforced.
    npm|composer|bundle|bundle-audit|pip-audit|gitleaks|semgrep|osv-scanner|zizmor|actionlint|hadolint) [ $audit = 1 ] || { _shape; return 1; } ;;
    *) _in "$base" "$_UNSUPPORTED" && { _deny "$base client not supported in read-only review"; return 1; }
       _in "$base" "$_SQL_CLIS" || { _shape; return 1; } ;;
  esac
  ARGS=()
  for ((i = i + 1; i < n; i++)); do
    [ "${TOK[i]}" = "$PIPE" ] && break
    ARGS+=("${TOK[i]}")
  done
  KEYS_ONLY=0
  case "$base" in npm|composer|bundle|bundle-audit|pip-audit|gitleaks|semgrep|osv-scanner|zizmor|actionlint|hadolint) ;; *) _eval_cli "$base" "${ARGS[@]}" || return 1 ;; esac
  if [ $KEYS_ONLY = 1 ] && { [ "$(_lc "${TOK[i + 1]:-}")" != jq ] || [ "${TOK[i + 2]:-}" != keys ] || { [ $((i + 3)) -lt "$n" ] && [ "${TOK[i + 3]}" != "$PIPE" ]; }; }; then
    _deny "railway variables only as: railway variables --json | jq 'keys'"; return 1
  fi
  if [ $sgjq = 1 ]; then
    j=$((i + 2)); [ "${TOK[j]:-}" = -r ] && j=$((j + 1))
    if [ "$(_lc "${TOK[i + 1]:-}")" != jq ] || ! _in_list "${TOK[j]:-}" "$_SEMGREP_JQ" || { [ $((j + 1)) -lt "$n" ] && [ "${TOK[j + 1]}" != "$PIPE" ]; }; then
      _deny "semgrep output only through the documented jq filter (references/scanners.md)"; return 1
    fi
  fi

  # Remaining segments: each must be `| <filter> args` with vetted args and no further CLI mention.
  while [ "$i" -lt "$n" ]; do
    f=$(_lc "${TOK[i + 1]:-}")
    _in "$f" "$_FILTERS" || { _shape; return 1; }
    ARGS=()
    for ((j = i + 2; j < n; j++)); do
      [ "${TOK[j]}" = "$PIPE" ] && break
      [[ " $(_lc "${TOK[j]}") " =~ $_MENTION ]] && { _shape; return 1; }
      ARGS+=("${TOK[j]}")
    done
    i=$j
    _filter_ok "$f" "${ARGS[@]}" || { _deny "$f argument not allowed during review"; return 1; }
  done
  return 0
}

_guard_main() {
  local input cmd
  input=$(cat)
  [ -n "$input" ] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    echo "RayStack review is read-only: jq not installed" >&2
    return 2
  fi
  if ! cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // .toolInput.command // empty' 2>/dev/null); then
    echo "RayStack review is read-only: could not parse hook input" >&2
    return 2
  fi
  [ -n "$cmd" ] || return 0
  guard_check "$cmd" && return 0
  echo "RayStack review is read-only: $GUARD_REASON" >&2
  return 2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then _guard_main; exit $?; fi
