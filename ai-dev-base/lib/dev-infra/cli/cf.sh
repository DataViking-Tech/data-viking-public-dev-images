#!/usr/bin/env bash
# cf — Cloudflare API v4 wrapper for AI agents.
# Requires CLOUDFLARE_API_TOKEN (or fetches from Doppler).
# Optionally uses CLOUDFLARE_ACCOUNT_ID for account-scoped endpoints.
#
# Usage: cf {workers|worker-detail|routes|dns|zones} [args...]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_dop-helpers.sh"
_require_cmd curl
_require_cmd jq
_load_registry

_resolve_cf_creds() {
  if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
    local project="${CF_PROJECT:-}"
    local config="${CF_CONFIG:-prd}"
    [ -z "$project" ] && _die "CLOUDFLARE_API_TOKEN not set and CF_PROJECT not configured"
    CLOUDFLARE_API_TOKEN=$(_dop_get "$project" "$config" "CLOUDFLARE_API_TOKEN") \
      || _die "Failed to fetch CLOUDFLARE_API_TOKEN from Doppler"
  fi
  if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
    local project="${CF_PROJECT:-}"
    local config="${CF_CONFIG:-prd}"
    if [ -n "$project" ]; then
      CLOUDFLARE_ACCOUNT_ID=$(_dop_get "$project" "$config" "CLOUDFLARE_ACCOUNT_ID" 2>/dev/null) || true
    fi
  fi
}

_cf_api() {
  local endpoint="$1"
  curl -s "https://api.cloudflare.com/client/v4${endpoint}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
}

case "${1:-}" in
  workers)
    _resolve_cf_creds
    [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ] && _die "CLOUDFLARE_ACCOUNT_ID required for workers endpoint"
    _cf_api "/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/scripts" \
      | jq -r '.result[]? | "\(.id) modified=\(.modified_on // "unknown")"'
    ;;
  worker-detail)
    _resolve_cf_creds
    [ -z "${2:-}" ] && _usage "Usage: cf worker-detail <worker_name>"
    [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ] && _die "CLOUDFLARE_ACCOUNT_ID required"
    _cf_api "/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/scripts/$2" \
      | jq '.result // .errors'
    ;;
  routes)
    _resolve_cf_creds
    [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ] && _die "CLOUDFLARE_ACCOUNT_ID required for routes"
    _cf_api "/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/routes" \
      | jq -r '.result[]? | "\(.pattern) -> \(.script)"'
    ;;
  dns)
    _resolve_cf_creds
    zone_id="${2:-${CLOUDFLARE_ZONE_ID:-}}"
    [ -z "$zone_id" ] && _die "Usage: cf dns <zone_id> or set CLOUDFLARE_ZONE_ID"
    type_filter=""
    if [ "${3:-}" = "--type" ] && [ -n "${4:-}" ]; then
      type_filter="&type=$4"
    fi
    _cf_api "/zones/${zone_id}/dns_records?per_page=100${type_filter}" \
      | jq -r '.result[]? | "\(.type) \(.name) -> \(.content)"'
    ;;
  zones)
    _resolve_cf_creds
    _cf_api "/zones?per_page=50" \
      | jq -r '.result[]? | "\(.id) \(.name) status=\(.status)"'
    ;;
  --help|-h)
    cat <<'EOF'
Usage: cf {workers|worker-detail|routes|dns|zones} [args...]

Commands:
  workers                   List Workers scripts
  worker-detail <name>      Show details for a specific worker
  routes                    List Workers routes
  dns <zone_id> [--type X]  List DNS records for a zone
  zones                     List all zones

Environment:
  CLOUDFLARE_API_TOKEN    API token (or fetched from Doppler)
  CLOUDFLARE_ACCOUNT_ID   Account ID (or fetched from Doppler)
  CLOUDFLARE_ZONE_ID      Default zone ID for dns command
  CF_PROJECT              Doppler project for credential lookup
  CF_CONFIG               Doppler config (default: prd)
EOF
    ;;
  *)
    _usage "Usage: cf {workers|worker-detail|routes|dns|zones} [args...]"
    ;;
esac
