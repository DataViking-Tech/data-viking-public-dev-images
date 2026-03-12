#!/usr/bin/env bash
# dbx — Databricks REST API wrapper for AI agents.
# Requires DATABRICKS_HOST and DATABRICKS_TOKEN (or fetches from Doppler).
#
# Usage: dbx {warehouses|jobs|job-status} [args...]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_dop-helpers.sh"
_require_cmd curl
_require_cmd jq
_load_registry

_resolve_dbx_creds() {
  if [ -z "${DATABRICKS_HOST:-}" ]; then
    local project="${DBX_PROJECT:-}"
    local config="${DBX_CONFIG:-prd}"
    [ -z "$project" ] && _die "DATABRICKS_HOST not set and DBX_PROJECT not configured"
    DATABRICKS_HOST=$(_dop_get "$project" "$config" "DATABRICKS_HOST") \
      || _die "Failed to fetch DATABRICKS_HOST from Doppler"
  fi
  if [ -z "${DATABRICKS_TOKEN:-}" ]; then
    local project="${DBX_PROJECT:-}"
    local config="${DBX_CONFIG:-prd}"
    [ -z "$project" ] && _die "DATABRICKS_TOKEN not set and DBX_PROJECT not configured"
    DATABRICKS_TOKEN=$(_dop_get "$project" "$config" "DATABRICKS_TOKEN") \
      || _die "Failed to fetch DATABRICKS_TOKEN from Doppler"
  fi
}

_dbx_api() {
  local endpoint="$1"
  curl -s -X GET "https://${DATABRICKS_HOST}${endpoint}" \
    -H "Authorization: Bearer ${DATABRICKS_TOKEN}"
}

case "${1:-}" in
  warehouses)
    _resolve_dbx_creds
    _dbx_api "/api/2.0/sql/warehouses" \
      | jq -r '.warehouses[]? | "\(.id) \(.name) state=\(.state) size=\(.cluster_size)"'
    ;;
  jobs)
    _resolve_dbx_creds
    limit="${2:-20}"
    _dbx_api "/api/2.1/jobs/list?limit=$limit" \
      | jq -r '.jobs[]? | "\(.job_id) \(.settings.name)"'
    ;;
  job-status)
    _resolve_dbx_creds
    [ -z "${2:-}" ] && _usage "Usage: dbx job-status <run_id>"
    _dbx_api "/api/2.1/jobs/runs/get?run_id=$2" \
      | jq '{run_id: .run_id, state: .state, job_id: .job_id, start_time: .start_time, end_time: .end_time}'
    ;;
  --help|-h)
    cat <<'EOF'
Usage: dbx {warehouses|jobs|job-status} [args...]

Commands:
  warehouses          List SQL warehouses and their states
  jobs [limit]        List jobs (default: 20)
  job-status <run_id> Show status of a specific job run

Environment:
  DATABRICKS_HOST     Databricks workspace hostname (or fetched from Doppler)
  DATABRICKS_TOKEN    Personal access token (or fetched from Doppler)
  DBX_PROJECT         Doppler project for credential lookup
  DBX_CONFIG          Doppler config (default: prd)
EOF
    ;;
  *)
    _usage "Usage: dbx {warehouses|jobs|job-status} [args...]"
    ;;
esac
