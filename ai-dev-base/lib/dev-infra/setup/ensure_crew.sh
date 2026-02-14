#!/usr/bin/env bash
# Ensure crew members are configured from .devcontainer/crew.json.
# Called from devcontainer postCreateCommand (via image LABEL).
# Idempotent: skips members that already exist.
set -euo pipefail

# Requires gastown to be enabled and initialized
if [ "${GASTOWN_ENABLED:-true}" = "false" ] || ! command -v gt >/dev/null 2>&1; then
  exit 0
fi

GASTOWN_HOME="${GASTOWN_HOME:-$HOME/gt}"

# Gastown must be initialized first (ensure_gastown.sh runs before us)
if [ ! -f "$GASTOWN_HOME/mayor/town.json" ]; then
  exit 0
fi

# Determine the rig name (same logic as ensure_gastown.sh)
if [ -d .git ]; then
  rig_name=$(basename "$PWD" | tr -- '-. ' '_')
else
  exit 0
fi

# Verify the rig is registered
if ! (cd "$GASTOWN_HOME" && gt rig list 2>/dev/null) | grep -q "$rig_name"; then
  exit 0
fi

# Look for crew config
crew_file=".devcontainer/crew.json"
if [ ! -f "$crew_file" ]; then
  exit 0
fi

# Get existing crew members for this rig
existing_crew=$(cd "$GASTOWN_HOME" && gt crew list --rig "$rig_name" 2>/dev/null || true)

# Parse crew members from JSON
# Supports: {"crew": [{"name": "x"}, ...]} or {"crew": ["x", ...]} or [{"name": "x"}, ...]
crew_members=()
if command -v python3 >/dev/null 2>&1; then
  while IFS= read -r name; do
    [ -n "$name" ] && crew_members+=("$name")
  done < <(python3 -c "
import json, sys
with open('$crew_file') as f:
    data = json.load(f)
if isinstance(data, list):
    members = data
elif isinstance(data, dict) and 'crew' in data:
    members = data['crew']
else:
    sys.exit(0)
for m in members:
    if isinstance(m, str):
        print(m)
    elif isinstance(m, dict) and 'name' in m:
        print(m['name'])
" 2>/dev/null)
fi

# Add each crew member (idempotent - skip if already exists)
for member in "${crew_members[@]}"; do
  if echo "$existing_crew" | grep -q "$member"; then
    continue
  fi
  (cd "$GASTOWN_HOME" && gt crew add "$member" --rig "$rig_name") 2>/dev/null || true
done
