#!/usr/bin/env bash
# gmail — Gmail search stub for AI agents.
# NOT YET IMPLEMENTED — requires OAuth2 flow that isn't suitable for CLI.
# Placeholder so skills can reference it without breaking.
#
# Usage: gmail {search} [args...]
set -uo pipefail

case "${1:-}" in
  search)
    echo "gmail search is not yet implemented."
    echo "This requires OAuth2 credentials which are not available in CLI mode."
    echo "Check the Google Workspace admin console or use the Gmail web UI."
    exit 1
    ;;
  --help|-h)
    cat <<'EOF'
Usage: gmail {search} [args...]

Commands:
  search [query] [--max N]    Search Gmail (NOT YET IMPLEMENTED)

Note: Gmail integration requires OAuth2 and is not yet implemented.
EOF
    ;;
  *)
    echo "Usage: gmail {search} [args...]" >&2
    echo "Note: Gmail integration is not yet implemented." >&2
    exit 1
    ;;
esac
