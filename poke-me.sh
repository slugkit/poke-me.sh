#!/usr/bin/env bash
#
# poke-me.sh — send a push notification via the poke-me API using a publish key.
#
# Two targets:
#   channel broadcast   POST /api/v1/publish              (--channel)
#   BYOA subject unicast POST /api/v1/apps/{app}/notify    (--app + --user)
#
# Requires: curl, jq.

set -euo pipefail

VERSION="0.1.0"
DEFAULT_BASE_URL="https://push-me.io"

die() { printf 'poke-me: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
poke-me.sh — send a push notification via the poke-me API using a publish key.

USAGE
  poke-me.sh --channel REF --title T --body B [options]          # channel broadcast
  poke-me.sh --app APP --user EXTERNAL_ID --title T --body B ...  # BYOA unicast

TARGET (exactly one)
  -c, --channel REF     channel slug or uuid  → POST /api/v1/publish
      --app APP         app slug or uuid      \
  -u, --user ID         external user id       } → POST /api/v1/apps/APP/notify

MESSAGE
  -t, --title TEXT      notification title   (required unless --silent)
  -b, --body TEXT       notification body    (required unless --silent)
  -p, --priority LEVEL  low | normal | high | critical   (default: normal)
      --url URL         tap-action URL
      --extras JSON     a JSON object, e.g. '{"screen":"inbox"}'
      --silent          content-available push (no title/body shown)

AUTH & ENDPOINT
  -k, --key KEY         publish key (pk_…).   Default: $POKEME_API_KEY
      --base-url URL    API base URL.         Default: $POKEME_BASE_URL
                                              or https://push-me.io

OTHER
  -n, --dry-run         print the request and exit without sending
  -v, --verbose         print request/response details
  -h, --help            show this help
      --version         print the version

EXAMPLES
  export POKEME_API_KEY=pk_live_...
  poke-me.sh -c acme/news -t "Deploy done" -b "v1.4.2 is live"
  poke-me.sh --app lazy-sudoku -u rc-user-42 -t "Re: your feedback" -b "Fixed!"
EOF
}

# --- defaults ---------------------------------------------------------------
KEY="${POKEME_API_KEY:-}"
BASE_URL="${POKEME_BASE_URL:-$DEFAULT_BASE_URL}"
CHANNEL="" APP="" USER_ID=""
TITLE="" BODY="" PRIORITY="" URL="" EXTRAS=""
SILENT=false DRY_RUN=false VERBOSE=false
have_title=false have_body=false

# --- parse args -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--channel)  CHANNEL="${2:?--channel needs a value}"; shift 2 ;;
    --app)         APP="${2:?--app needs a value}"; shift 2 ;;
    -u|--user)     USER_ID="${2:?--user needs a value}"; shift 2 ;;
    -t|--title)    TITLE="${2?--title needs a value}"; have_title=true; shift 2 ;;
    -b|--body)     BODY="${2?--body needs a value}"; have_body=true; shift 2 ;;
    -p|--priority) PRIORITY="${2:?--priority needs a value}"; shift 2 ;;
    --url)         URL="${2:?--url needs a value}"; shift 2 ;;
    --extras)      EXTRAS="${2:?--extras needs a value}"; shift 2 ;;
    --silent)      SILENT=true; shift ;;
    -k|--key)      KEY="${2:?--key needs a value}"; shift 2 ;;
    --base-url)    BASE_URL="${2:?--base-url needs a value}"; shift 2 ;;
    -n|--dry-run)  DRY_RUN=true; shift ;;
    -v|--verbose)  VERBOSE=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    --version)     printf 'poke-me.sh %s\n' "$VERSION"; exit 0 ;;
    --)            shift; break ;;
    -*)            die "unknown option: $1 (try --help)" ;;
    *)             die "unexpected argument: $1 (try --help)" ;;
  esac
done

# --- validate ---------------------------------------------------------------
command -v curl >/dev/null || die "curl is required"
command -v jq   >/dev/null || die "jq is required"

[[ -n "$KEY" ]] || die "no publish key: pass --key or set POKEME_API_KEY"

# exactly one target
if [[ -n "$CHANNEL" && ( -n "$APP" || -n "$USER_ID" ) ]]; then
  die "choose one target: --channel OR (--app and --user)"
fi
if [[ -n "$CHANNEL" ]]; then
  mode="publish"
elif [[ -n "$APP" || -n "$USER_ID" ]]; then
  [[ -n "$APP"     ]] || die "--user requires --app"
  [[ -n "$USER_ID" ]] || die "--app requires --user"
  mode="notify"
else
  die "no target: pass --channel, or --app and --user (try --help)"
fi

if [[ "$SILENT" == false ]]; then
  [[ "$have_title" == true ]] || die "--title is required (or use --silent)"
  [[ "$have_body"  == true ]] || die "--body is required (or use --silent)"
fi

if [[ -n "$PRIORITY" ]]; then
  case "$PRIORITY" in
    low|normal|high|critical) ;;
    *) die "invalid --priority '$PRIORITY' (low|normal|high|critical)" ;;
  esac
fi

if [[ -n "$EXTRAS" ]]; then
  echo "$EXTRAS" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || die "--extras must be a JSON object"
fi

# --- build request ----------------------------------------------------------
base="${BASE_URL%/}"
if [[ "$mode" == "publish" ]]; then
  url="$base/api/v1/publish"
else
  url="$base/api/v1/apps/$APP/notify"
fi

body='{}'
add()     { body=$(printf '%s' "$body" | jq --arg k "$1" --arg v "$2" '. + {($k): $v}'); }
add_json() { body=$(printf '%s' "$body" | jq --arg k "$1" --argjson v "$2" '. + {($k): $v}'); }

[[ "$mode" == "publish" ]] && add channel_ref "$CHANNEL"
[[ "$mode" == "notify"  ]] && add external_user_id "$USER_ID"
[[ "$have_title" == true ]] && add title "$TITLE"
[[ "$have_body"  == true ]] && add body "$BODY"
[[ -n "$PRIORITY" ]] && add priority "$PRIORITY"
[[ -n "$URL"      ]] && add url "$URL"
[[ "$SILENT" == true ]] && add_json silent true
[[ -n "$EXTRAS"   ]] && add_json extras "$EXTRAS"

# --- dry run ----------------------------------------------------------------
if [[ "$DRY_RUN" == true ]]; then
  printf 'POST %s\n' "$url"
  printf 'X-API-Key: %s…\n' "${KEY:0:8}"
  printf '%s\n' "$body" | jq .
  exit 0
fi

# --- send -------------------------------------------------------------------
[[ "$VERBOSE" == true ]] && { printf 'POST %s\n' "$url" >&2; printf '%s\n' "$body" | jq . >&2; }

response=$(curl -sS -X POST "$url" \
  -H "X-API-Key: $KEY" \
  -H 'content-type: application/json' \
  -H 'accept: application/json' \
  --data "$body" \
  -w $'\n%{http_code}') || die "request failed (network/curl error)"

http_code="${response##*$'\n'}"
resp_body="${response%$'\n'*}"

[[ "$VERBOSE" == true ]] && printf 'HTTP %s\n%s\n' "$http_code" "$resp_body" >&2

if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
  msg=$(printf '%s' "$resp_body" | jq -r '.error // .detail // .title // .message // empty' 2>/dev/null || true)
  die "HTTP $http_code${msg:+: $msg}"
fi

# success summary
id=$(printf '%s' "$resp_body" | jq -r '.id // empty' 2>/dev/null || true)
sent_at=$(printf '%s' "$resp_body" | jq -r '.sent_at // empty' 2>/dev/null || true)
devices=$(printf '%s' "$resp_body" | jq -r '.devices // empty' 2>/dev/null || true)

printf 'sent'
[[ -n "$id"      ]] && printf ' · id=%s' "$id"
[[ -n "$devices" ]] && printf ' · devices=%s' "$devices"
[[ -n "$sent_at" ]] && printf ' · sent_at=%s' "$sent_at"
printf '\n'
