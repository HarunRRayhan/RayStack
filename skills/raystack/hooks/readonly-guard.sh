#!/usr/bin/env bash
# RayStack read-only guard: PreToolUse hook that blocks mutating cloud/DB commands.
# stdin: PreToolUse JSON (Claude/Codex/Cursor `.tool_input.command`, Grok `.toolInput.command`). Exit 0 = allow, exit 2 = block (reason on stderr).
# Source this file to call guard_check "<cmd>" directly (0 = allow, 1 = block, reason in GUARD_REASON).
# shortcut: token heuristics, not a sandbox; aliases/functions/scripts can evade; pair with read-only credentials
# Accepted out-of-scope evasions: `echo <b64> | base64 -d | sh`, scripts/functions/aliases, other-language SDKs,
#   and a package runner hidden inside one quoted word (`sh -c "npx x"`) that names no monitored CLI.
# This guard is a seatbelt, not a boundary: always run reviews with read-only credentials.
# Design: a command that mentions a monitored CLI must be exactly
#   [NAME=literal ...] <cli> args... [| <filter> args ...]...
# and the CLI's verb must be on that CLI's read allow-list. Everything else is denied.
# SQL: one statement per command, no comments (--, /*, and # for MySQL/usql); every `name(` must be on a read-only function list.
# Unquoted glob/redirect chars ([ ] ( ) * ? ! < >) and braces deny anywhere; mongosh/cqlsh/clickhouse/snowsql/sqlcmd/bq,
#   deploy tools and pg_dump/pg_restore always deny. Names match on `-`/`/` boundaries too (aws-cdk, amazon/aws-cli).
# Package runners (npx, bunx, uvx, pnpm/yarn dlx, npm exec, pipx run) and docker/podman run deny anywhere.

GUARD_REASON=""
KEYS_ONLY=0
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
# Lower-case only names/verbs/SQL; flags keep their case (-S vs -s, -X vs -x).
_lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

_NAMES='aws gcloud az kubectl oc terraform tofu terragrunt helm railway wrangler redis-cli bq psql mysql mariadb sqlite3 sqlcmd mongosh clickhouse-client cqlsh snowsql usql pgcli mycli awscli pulumi cdk sam serverless sls eksctl flyctl fly doctl heroku vercel netlify supabase dropdb createdb mysqladmin vc ntl cdktf dropuser createuser pg_restore pg_dump pg_dumpall sst amplify copilot'
# `-` and `/` are boundaries, so hyphen/slash-joined names count too (aws-cdk, netlify-cli, amazon/aws-cli).
_MENTION="(^|[^a-z0-9_.])(${_NAMES// /|})([^a-z0-9_.]|\$)"
_SQL_CLIS=' psql mysql mariadb sqlite3 usql pgcli mycli '
_UNSUPPORTED=' mongosh cqlsh clickhouse-client snowsql sqlcmd bq pulumi cdk sam serverless sls eksctl flyctl fly doctl heroku vercel netlify supabase dropdb createdb mysqladmin vc ntl cdktf dropuser createuser pg_restore pg_dump pg_dumpall sst amplify copilot '
_FILTERS=' jq head tail grep sort uniq wc cut column tr '
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
    # No container inspect: Config.Env can hold secrets.
    " "|"ps "*|"images "*|"version "*|"info "*|"image ls"|"image inspect"|"system df"|"compose ps"|"compose ls"|"compose images") return 0 ;;
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
  local lc strip q="" ch tok="" intok=0 ops=0 tilde=0 i j n base name f w
  local -a TOK ARGS
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
      '['|']'|'('|')'|'*'|'?'|'!'|'<'|'>') _deny "unquoted glob/redirect character '$ch' during review"; return 1 ;;
      ' '|$'\t'|'|'|';'|'&'|$'\n')
        [ $intok = 1 ] && TOK+=("$tok")
        tok=""; intok=0
        case "$ch" in
          ' '|$'\t') ;;
          '|') TOK+=("$PIPE") ;;
          *) ops=1 ;;
        esac ;;
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
    name=$(_lc "${TOK[i]##*/}")
    case "$name" in
      npx|pnpx|bunx|uvx) _deny "package runners are not allowed during a review"; return 1 ;;
      npm|pnpm|yarn|bun)
        # Read allow-list; npm accepts prefixes and aliases (exe, innit, c), and yarn/pnpm/bun run a
        # package.json script for any verb they don't know, so they only get --version.
        case "$name $(_lc "${TOK[i + 1]:-}") $(_lc "${TOK[i + 2]:-}")" in
          *" --version "|"npm -v ") continue ;;
          "npm ls "*|"npm list "*|"npm view "*|"npm outdated "*|"npm why "*|"npm explain "*) continue ;;
          "npm audit "*) f=' fix '
             for ((j = i + 1; j < n; j++)); do
               [ "${TOK[j]}" = "$PIPE" ] && break
               _in "$(_lc "${TOK[j]}")" "$f" && { _deny "$name audit fix not allowed during review"; return 1; }
             done
             continue ;;
        esac
        _deny "$name ${TOK[i + 1]:-} is not on the read allow-list"; return 1 ;;
      pipx|uv) f=' run ' ;;
      # A shell (or env) runs a string or a command these checks never see.
      sh|bash|zsh|dash|ksh|mksh|fish|csh|tcsh|busybox|env) _deny "$name not allowed during review"; return 1 ;;
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
  [[ "$strip" =~ $_MENTION ]] || return 0
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
  case "$base" in
    aws|gcloud|az|kubectl|oc|terraform|tofu|terragrunt|helm|railway|wrangler|redis-cli) ;;
    *) _in "$base" "$_UNSUPPORTED" && { _deny "$base client not supported in read-only review"; return 1; }
       _in "$base" "$_SQL_CLIS" || { _shape; return 1; } ;;
  esac
  ARGS=()
  for ((i = i + 1; i < n; i++)); do
    [ "${TOK[i]}" = "$PIPE" ] && break
    ARGS+=("${TOK[i]}")
  done
  KEYS_ONLY=0
  _eval_cli "$base" "${ARGS[@]}" || return 1
  if [ $KEYS_ONLY = 1 ] && { [ "$(_lc "${TOK[i + 1]:-}")" != jq ] || [ "${TOK[i + 2]:-}" != keys ] || { [ $((i + 3)) -lt "$n" ] && [ "${TOK[i + 3]}" != "$PIPE" ]; }; }; then
    _deny "railway variables only as: railway variables --json | jq 'keys'"; return 1
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
