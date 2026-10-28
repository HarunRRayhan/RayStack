#!/usr/bin/env bash
# RayStack read-only guard: PreToolUse hook that blocks mutating cloud/DB commands.
# stdin: PreToolUse JSON (Claude/Codex/Cursor `.tool_input.command`, Grok `.toolInput.command`). Exit 0 = allow, exit 2 = block (reason on stderr).
# Source this file to call guard_check "<cmd>" directly (0 = allow, 1 = block, reason in GUARD_REASON).
# shortcut: token heuristics, not a sandbox; aliases/functions/scripts can evade; pair with read-only credentials
# Accepted out-of-scope evasions: `echo <b64> | base64 -d | sh`, scripts/functions/aliases, other-language SDKs.
# This guard is a seatbelt, not a boundary: always run reviews with read-only credentials.
# Design: a command that mentions a monitored CLI must be exactly
#   [NAME=literal ...] <cli> args... [| <filter> args ...]...
# and the CLI's verb must be on that CLI's read allow-list. Everything else is denied.
# SQL: one statement per command, no comments (--, /*, and # for MySQL/usql); every `name(` must be on a read-only function list.
# Unquoted glob/redirect chars ([ ] ( ) * ? ! < >) and braces deny anywhere; mongosh/cqlsh/clickhouse/snowsql/sqlcmd/bq always deny.

GUARD_REASON=""
KEYS_ONLY=0
P=()
PIPE=$'\001'

_deny() { GUARD_REASON="$1"; return 1; }
_shape() { _deny "unsupported command shape during review"; }
_no() { _deny "$1 is not on the read allow-list"; }
_in() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
# Lower-case only names/verbs/SQL; flags keep their case (-S vs -s, -X vs -x).
_lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

_NAMES='aws gcloud az kubectl oc terraform tofu terragrunt helm railway wrangler redis-cli bq psql mysql mariadb sqlite3 sqlcmd mongosh clickhouse-client cqlsh snowsql usql pgcli mycli awscli pulumi cdk sam serverless sls eksctl flyctl fly doctl heroku vercel netlify supabase dropdb createdb mysqladmin'
# `-` and `/` are boundaries, so hyphen/slash-joined names count too (aws-cdk, netlify-cli, amazon/aws-cli).
_MENTION="(^|[^a-z0-9_.])(${_NAMES// /|})([^a-z0-9_.]|\$)"
_SQL_CLIS=' psql mysql mariadb sqlite3 usql pgcli mycli '
_UNSUPPORTED=' mongosh cqlsh clickhouse-client snowsql sqlcmd bq pulumi cdk sam serverless sls eksctl flyctl fly doctl heroku vercel netlify supabase dropdb createdb mysqladmin '
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

# _docker_sub i: index of the docker/podman subcommand after TOK[i], skipping global flags and their values.
_docker_sub() {
  local k=$(($1 + 1))
  while [[ "${TOK[k]:-}" == -* ]]; do
    _in "${TOK[k]}" "-c --config --context -H --host -l --log-level --tlscacert --tlscert --tlskey --connection --url --identity" && k=$((k + 1))
    k=$((k + 1))
  done
  echo "$k"
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
      # Reads that print secret values.
      case "$a $b" in "secretsmanager "*get-secret-value) _deny "aws $a $b prints secret values"; return 1 ;; esac
      if [ "$a" = ssm ] && [[ "$b" == get-parameter* ]]; then
        case " $* " in *" --with-decryption"*) _deny "aws ssm --with-decryption prints secret values"; return 1 ;; esac
      fi
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
               [ "$w" = list ] || case "$b" in *" keyvault secret") _deny "$cli keyvault secret $w prints secret values"; return 1 ;; esac
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
        for w in "$@"; do
          [[ "$(_lc "$w")" =~ (^|,)secrets?([/,.]|$) ]] && { _deny "$cli get secret prints secret values"; return 1; }
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
        ''|show|validate|providers|version|graph) return 0 ;;
        # init must not touch the backend; plan must not take the state lock.
        init) _tf_only backend=false "$@" && return 0
              _deny "$cli init only with -backend=false during review"; return 1 ;;
        plan) _tf_only lock=false "$@" && return 0
              _deny "$cli plan only with -lock=false during review"; return 1 ;;
        fmt) case " $* " in *" -check "*) return 0 ;; esac ;;
        state) _walk 2 "-chdir" "-help" "$@" || return 1
               case "${P[1]:-}" in list|show) return 0 ;; esac ;;
      esac
      _no "$cli $a" ;;
    helm)
      _walk 1 "-n --namespace --kube-context" "--help" "$@" || return 1
      case "${P[0]:-}" in ''|list|ls|status|history|version|template|search|get|show) return 0 ;; esac
      _no "helm ${P[0]}" ;;
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
  local lc strip q="" ch tok="" intok=0 ops=0 tilde=0 i j n base name f
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
  # Package runners and container runs fetch and execute any tool (npx aws-cdk deploy, docker run amazon/aws-cli).
  n=${#TOK[@]}
  for ((i = 0; i < n; i++)); do
    case "$(_lc "${TOK[i]##*/}")" in
      npx|bunx|uvx) _deny "package runners are not allowed during a review"; return 1 ;;
      pnpm|yarn) f=' dlx ' ;;
      npm) f=' exec x ' ;;
      bun) f=' x ' ;;
      pipx|uv|docker|podman) f=' run ' ;;
      *) continue ;;
    esac
    # shortcut: any later word in the pipe segment counts (docker logs run denies), fail closed.
    for ((j = i + 1; j < n; j++)); do
      [ "${TOK[j]}" = "$PIPE" ] && break
      _in "$(_lc "${TOK[j]}")" "$f" && { _deny "package runners are not allowed during a review"; return 1; }
    done
  done
  # docker compose config/convert prints interpolated secrets: only --services or --volumes.
  if [[ "$strip" =~ docker|podman ]]; then
    f=0
    for ((i = 0; i < n; i++)); do
      name=$(_lc "${TOK[i]##*/}")
      if [ "$name" = docker-compose ] || [ "$name" = podman-compose ] || { { [ "$name" = docker ] || [ "$name" = podman ]; } && [ "$(_lc "${TOK[$(_docker_sub "$i")]:-}")" = compose ]; }; then f=1
      elif [ $f = 1 ] && { [ "$name" = config ] || [ "$name" = convert ]; }; then
        f=2
        for ((j = i + 1; j < n; j++)); do
          case "${TOK[j]}" in --services|--volumes) f=3 ;; "$PIPE") break ;; *) f=2; break ;; esac
        done
        [ $f = 3 ] || { _deny "docker compose $name only with --services or --volumes"; return 1; }
        f=1
      fi
    done
  fi
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
