#!/usr/bin/env bash
# dagster-cloud — Dagster Cloud API wrapper for AI agents.
# Uses Dagster Cloud GraphQL API. Requires DAGSTER_CLOUD_API_TOKEN and
# DAGSTER_CLOUD_URL (or fetches them from Doppler).
#
# Usage: dagster-cloud {repos|runs|run-logs} [args...]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_dop-helpers.sh"
_require_cmd curl
_require_cmd jq
_load_registry

# Resolve Dagster Cloud credentials
_resolve_dagster_creds() {
  if [ -z "${DAGSTER_CLOUD_API_TOKEN:-}" ]; then
    local project="${DAGSTER_PROJECT:-}"
    local config="${DAGSTER_CONFIG:-prd}"
    [ -z "$project" ] && _die "DAGSTER_CLOUD_API_TOKEN not set and DAGSTER_PROJECT not configured"
    DAGSTER_CLOUD_API_TOKEN=$(_dop_get "$project" "$config" "DAGSTER_CLOUD_API_TOKEN") \
      || _die "Failed to fetch DAGSTER_CLOUD_API_TOKEN from Doppler"
  fi
  if [ -z "${DAGSTER_CLOUD_URL:-}" ]; then
    local project="${DAGSTER_PROJECT:-}"
    local config="${DAGSTER_CONFIG:-prd}"
    [ -z "$project" ] && _die "DAGSTER_CLOUD_URL not set and DAGSTER_PROJECT not configured"
    DAGSTER_CLOUD_URL=$(_dop_get "$project" "$config" "DAGSTER_CLOUD_URL") \
      || _die "Failed to fetch DAGSTER_CLOUD_URL from Doppler"
  fi
}

_graphql() {
  local query="$1"
  curl -s -X POST "${DAGSTER_CLOUD_URL}/graphql" \
    -H "Content-Type: application/json" \
    -H "Dagster-Cloud-Api-Token: ${DAGSTER_CLOUD_API_TOKEN}" \
    -d "{\"query\": \"$query\"}"
}

case "${1:-}" in
  repos)
    _resolve_dagster_creds
    _graphql "{ repositoriesOrError { ... on RepositoryConnection { nodes { name location { name } } } } }" \
      | jq -r '.data.repositoriesOrError.nodes[] | "\(.location.name) / \(.name)"'
    ;;
  runs)
    _resolve_dagster_creds
    limit="${2:-10}"
    _graphql "{ runsOrError(limit: $limit) { ... on Runs { results { runId status pipelineName startTime endTime } } } }" \
      | jq -r '.data.runsOrError.results[] | "\(.runId[:8]) \(.status) \(.pipelineName) start=\(.startTime // "n/a")"'
    ;;
  run-logs)
    _resolve_dagster_creds
    [ -z "${2:-}" ] && _usage "Usage: dagster-cloud run-logs <run_id>"
    _graphql "{ logsForRun(runId: \\\"$2\\\") { ... on EventConnection { events { message timestamp level } } } }" \
      | jq -r '.data.logsForRun.events[] | "\(.timestamp) [\(.level)] \(.message)"' | tail -50
    ;;
  --help|-h)
    cat <<'EOF'
Usage: dagster-cloud {repos|runs|run-logs} [args...]

Commands:
  repos                List code locations and repositories
  runs [limit]         List recent pipeline runs (default: 10)
  run-logs <run_id>    Show logs for a specific run (last 50 events)

Environment:
  DAGSTER_CLOUD_API_TOKEN  API token (or fetched from Doppler)
  DAGSTER_CLOUD_URL        Dagster Cloud instance URL (or fetched from Doppler)
  DAGSTER_PROJECT          Doppler project for credential lookup
  DAGSTER_CONFIG           Doppler config (default: prd)
EOF
    ;;
  *)
    _usage "Usage: dagster-cloud {repos|runs|run-logs} [args...]"
    ;;
esac
