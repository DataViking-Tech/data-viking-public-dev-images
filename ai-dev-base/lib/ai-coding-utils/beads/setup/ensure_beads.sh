#!/usr/bin/env bash
# Ensure beads is initialized in the current workspace.
# Called from devcontainer postCreateCommand (via image LABEL).
# Idempotent: skips if .beads/ already exists or bd is not installed.
set -euo pipefail

if ! command -v bd >/dev/null 2>&1; then
  exit 0
fi

# When Gas Town is enabled, beads are managed centrally at ~/gt/<rig>/.beads/
# Skip project-level beads init to avoid a second Dolt instance on the same port.
if [ "${GASTOWN_ENABLED:-false}" = "true" ] && command -v gt >/dev/null 2>&1; then
  exit 0
fi

if [ -d .beads ]; then
  exit 0
fi

prefix=$(basename "$PWD")
echo "y" | bd init --prefix "$prefix" --skip-hooks -q 2>/dev/null || true
