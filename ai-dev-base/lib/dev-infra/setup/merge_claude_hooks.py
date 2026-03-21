#!/usr/bin/env python3
"""Merge gastown hooks into Claude Code settings.json (idempotent).

Usage: merge_claude_hooks.py <settings_path> <gastown_home>

Exits 0 on success or if hooks are already present. Exits 1 on error.
"""
import json
import os
import sys


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <settings_path> <gastown_home>", file=sys.stderr)
        sys.exit(1)

    settings_path = sys.argv[1]
    gt_home = sys.argv[2]

    if os.path.exists(settings_path):
        with open(settings_path) as f:
            settings = json.load(f)
    else:
        settings = {}

    # Check sentinel: if gt costs record hook is already present, nothing to do.
    hooks = settings.get('hooks', {})
    for entry in hooks.get('Stop', []):
        for h in entry.get('hooks', []):
            if 'gt costs record' in h.get('command', ''):
                return
        # Also check flat format (legacy)
        if 'gt costs record' in entry.get('command', ''):
            return

    # Claude Code hooks schema: each event maps to an array of matcher objects,
    # each containing a 'hooks' array of {type, command} entries.
    def hook_entry(command, matcher=None):
        entry = {'hooks': [{'type': 'command', 'command': command}]}
        if matcher:
            entry['matcher'] = matcher
        return entry

    # Wrap gt commands with cd to GASTOWN_HOME so they work from any cwd
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

    os.makedirs(os.path.dirname(settings_path), exist_ok=True)
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)


if __name__ == '__main__':
    main()
