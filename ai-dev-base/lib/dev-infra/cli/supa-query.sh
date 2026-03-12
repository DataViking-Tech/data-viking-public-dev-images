#!/usr/bin/env bash
# supa-query — Execute SQL against Supabase via psql.
# Fetches DATABASE_URL from Doppler if not already set.
#
# Usage: supa-query "SQL string"
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_dop-helpers.sh"
_require_cmd psql
_load_registry

[ -z "${1:-}" ] && _usage "Usage: supa-query \"SQL string\""

# Resolve DATABASE_URL: env var first, then Doppler
if [ -z "${DATABASE_URL:-}" ]; then
  project="${SUPA_PROJECT:-}"
  config="${SUPA_CONFIG:-prd}"
  [ -z "$project" ] && _die "DATABASE_URL not set and SUPA_PROJECT not configured. Set DATABASE_URL or SUPA_PROJECT."
  DATABASE_URL=$(_dop_get "$project" "$config" "DATABASE_URL") || _die "Failed to fetch DATABASE_URL from Doppler"
fi

psql "$DATABASE_URL" -c "$1"
