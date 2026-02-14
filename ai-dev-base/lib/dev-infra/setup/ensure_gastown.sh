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
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

# Check if gastown hooks are already merged (any gt command in Stop as sentinel)
if [ -f "$CLAUDE_SETTINGS" ] && python3 -c "
import json, sys
with open('$CLAUDE_SETTINGS') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
stop_hooks = hooks.get('Stop', [])
for entry in stop_hooks:
    for h in entry.get('hooks', []):
        if 'gt costs record' in h.get('command', ''):
            sys.exit(0)
    # Also check flat format (legacy)
    if 'gt costs record' in entry.get('command', ''):
        sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
  exit 0
fi

mkdir -p "$HOME/.claude"
python3 -c "
import json, os

settings_path = '$CLAUDE_SETTINGS'

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

# Claude Code hooks schema: each event maps to an array of matcher objects,
# each containing a 'hooks' array of {type, command} entries.
def hook_entry(command, matcher=None):
    entry = {'hooks': [{'type': 'command', 'command': command}]}
    if matcher:
        entry['matcher'] = matcher
    return entry

# Wrap gt commands with cd to GASTOWN_HOME so they work from any cwd
gt_home = '$GASTOWN_HOME'
def gt_cmd(cmd):
    return f'cd {gt_home} && {cmd}'

gastown_hooks = {
    'SessionStart': [hook_entry(gt_cmd('gt prime --hook 2>/dev/null || true'))],
    'PreCompact': [hook_entry(gt_cmd('gt prime --hook 2>/dev/null || true'))],
    'UserPromptSubmit': [hook_entry(gt_cmd('gt mail check --inject 2>/dev/null || true'))],
    'PreToolUse': [
        hook_entry(gt_cmd('gt tap guard pr-workflow 2>/dev/null || true'), 'Bash(gh pr create*)'),
        hook_entry(gt_cmd('gt tap guard pr-workflow 2>/dev/null || true'), 'Bash(git checkout -b*)'),
        hook_entry(gt_cmd('gt tap guard pr-workflow 2>/dev/null || true'), 'Bash(git switch -c*)'),
        hook_entry(gt_cmd('gt tap guard mayor-edit 2>/dev/null || true'), 'Edit'),
        hook_entry(gt_cmd('gt tap guard mayor-edit 2>/dev/null || true'), 'Write')
    ],
    'Stop': [hook_entry(gt_cmd('gt costs record 2>/dev/null || true'))]
}

# Collect all existing commands per event to avoid duplicates
existing_hooks = settings.get('hooks', {})
for event, new_entries in gastown_hooks.items():
    if event not in existing_hooks:
        existing_hooks[event] = []
    # Gather commands already present (check both flat and nested formats)
    existing_cmds = set()
    for entry in existing_hooks[event]:
        if 'command' in entry:
            existing_cmds.add(entry['command'])
        for h in entry.get('hooks', []):
            existing_cmds.add(h.get('command', ''))
    for new_entry in new_entries:
        cmd = new_entry['hooks'][0]['command']
        if cmd not in existing_cmds:
            existing_hooks[event].append(new_entry)

settings['hooks'] = existing_hooks

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>/dev/null || true
