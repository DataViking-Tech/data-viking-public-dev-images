#!/usr/bin/env bash
# Ensure gastown is initialized in the current container.
# Called from devcontainer postCreateCommand (via image LABEL).
# Idempotent: skips workspace init if town.json already exists,
# skips hook merge if hooks are already present.
set -euo pipefail

# Skip gastown setup if disabled via env var (default: enabled)
# Downstream containers can set GASTOWN_ENABLED=false in devcontainer.json containerEnv
if [ "${GASTOWN_ENABLED:-true}" = "false" ] || ! command -v gt >/dev/null 2>&1; then
  exit 0
fi

GASTOWN_HOME="${GASTOWN_HOME:-$HOME/gt}"

# Fix ownership if the directory was created by a Docker volume mount (root-owned)
if [ -d "$GASTOWN_HOME" ] && [ "$(stat -c '%u' "$GASTOWN_HOME" 2>/dev/null)" != "$(id -u)" ]; then
  sudo chown -R "$(id -u):$(id -g)" "$GASTOWN_HOME" 2>/dev/null || true
fi

# Initialize HQ workspace if not already present
if [ ! -f "$GASTOWN_HOME/mayor/town.json" ]; then
  gt install "$GASTOWN_HOME" --name dev-town --git 2>/dev/null || true
fi

# Register project as a rig under the HQ (idempotent).
# Rig infrastructure lives under $GASTOWN_HOME/<rig>/, keeping project root clean.
if [ -d .git ]; then
  rig_name=$(basename "$PWD" | tr -- '-. ' '_')
  git_url=$(git remote get-url origin 2>/dev/null || true)
  if [ -n "$git_url" ]; then
    if ! (cd "$GASTOWN_HOME" && gt rig list 2>/dev/null) | grep -q "$rig_name"; then
      (cd "$GASTOWN_HOME" && gt rig add "$rig_name" "$git_url" --local-repo "$PWD") 2>/dev/null || true
    fi

    # Write rig env file so shell sessions set BEADS_DIR correctly.
    # Without this, bd auto-discovers .beads/ in the project directory
    # instead of using the rig's beads at $GASTOWN_HOME/<rig>/.beads/.
    _rig_beads="$GASTOWN_HOME/$rig_name/.beads"
    if [ -d "$_rig_beads" ] || mkdir -p "$_rig_beads" 2>/dev/null; then
      echo "export BEADS_DIR=\"$_rig_beads\"" > "$GASTOWN_HOME/.rig_env"
    fi
    unset _rig_beads
  fi
fi

# Ensure gastown runtime files are in .gitignore
for entry in .events.jsonl .runtime/; do
  if [ -f .gitignore ]; then
    grep -qx "$entry" .gitignore 2>/dev/null || echo "$entry" >> .gitignore
  elif [ -d .git ]; then
    echo "$entry" > .gitignore
  fi
done

# Merge gastown hooks into Claude Code settings.json (idempotent)
python3 "$(dirname "$0")/merge_claude_hooks.py" "$HOME/.claude/settings.json" "$GASTOWN_HOME" 2>/dev/null || true
