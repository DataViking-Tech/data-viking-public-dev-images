#!/usr/bin/env bash
# dop — Doppler CLI wrapper for AI agents.
# Provides a simplified interface to common Doppler operations.
#
# Usage: dop {me|projects|configs|secrets|get} [args...]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_dop-helpers.sh"
_require_cmd doppler

case "${1:-}" in
  me)
    # Show current Doppler auth identity
    doppler me
    ;;
  projects)
    # List all accessible projects
    doppler projects
    ;;
  configs)
    # List configs for a project: dop configs <project>
    [ -z "${2:-}" ] && _usage "Usage: dop configs <project>"
    doppler configs --project "$2"
    ;;
  secrets)
    # List secret names for a project/config: dop secrets <project> <config>
    [ -z "${2:-}" ] && _usage "Usage: dop secrets <project> <config>"
    [ -z "${3:-}" ] && _usage "Usage: dop secrets <project> <config>"
    doppler secrets --project "$2" --config "$3" --no-include-dynamic-secrets
    ;;
  get)
    # Get a single secret value: dop get <project> <config> <key>
    [ -z "${2:-}" ] && _usage "Usage: dop get <project> <config> <key>"
    [ -z "${3:-}" ] && _usage "Usage: dop get <project> <config> <key>"
    [ -z "${4:-}" ] && _usage "Usage: dop get <project> <config> <key>"
    _dop_get "$2" "$3" "$4"
    ;;
  --help|-h)
    cat <<'EOF'
Usage: dop {me|projects|configs|secrets|get} [args...]

Commands:
  me                          Show current Doppler auth identity
  projects                    List all accessible projects
  configs <project>           List configs for a project
  secrets <project> <config>  List secret names for a project/config
  get <project> <config> <key>  Get a single secret value
EOF
    ;;
  *)
    _usage "Usage: dop {me|projects|configs|secrets|get} [args...]"
    ;;
esac
