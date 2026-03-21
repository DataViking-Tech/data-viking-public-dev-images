#!/usr/bin/env python3
"""Merge Gas Town hooks into Claude Code settings.json.

Usage: merge_claude_hooks.py <settings_path> <gt_home>
"""
import json
import os
import sys


def hook_entry(command, matcher=None):
    """Create a Claude Code hook entry in nested format."""
    entry = {'hooks': [{'type': 'command', 'command': command}]}
    if matcher:
        entry['matcher'] = matcher
    return entry


def gt_cmd(gt_home, cmd):
    """Wrap a gt command with cd to GASTOWN_HOME so it works from any cwd."""
    return f'cd {gt_home} && {cmd}'


def build_gastown_hooks(gt_home):
    """Build the gastown hooks dict for a given gt_home."""
    def gc(cmd):
        return gt_cmd(gt_home, cmd)

    return {
        'SessionStart': [hook_entry(gc('gt prime --hook 2>/dev/null || true'))],
        'PreCompact': [hook_entry(gc('gt prime --hook 2>/dev/null || true'))],
        'UserPromptSubmit': [hook_entry(gc('gt mail check --inject 2>/dev/null || true'))],
        'PreToolUse': [
            hook_entry(gc('gt tap guard pr-workflow 2>/dev/null || true'), 'Bash(gh pr create*)'),
            hook_entry(gc('gt tap guard pr-workflow 2>/dev/null || true'), 'Bash(git checkout -b*)'),
            hook_entry(gc('gt tap guard pr-workflow 2>/dev/null || true'), 'Bash(git switch -c*)'),
            hook_entry(gc('gt tap guard mayor-edit 2>/dev/null || true'), 'Edit'),
            hook_entry(gc('gt tap guard mayor-edit 2>/dev/null || true'), 'Write'),
        ],
        'Stop': [hook_entry(gc('gt costs record 2>/dev/null || true'))],
    }


def merge_hooks(settings, gastown_hooks):
    """Merge gastown hooks into settings dict, avoiding duplicates.

    Checks both flat {command: ...} and nested {hooks: [{command: ...}]} formats
    when detecting existing commands.
    """
    existing_hooks = settings.get('hooks', {})
    for event, new_entries in gastown_hooks.items():
        if event not in existing_hooks:
            existing_hooks[event] = []
        # Gather commands already present in both flat and nested formats
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
    return settings


def merge_claude_hooks(settings_path, gt_home):
    """Read settings.json, merge gastown hooks, write back."""
    if os.path.exists(settings_path):
        with open(settings_path) as f:
            settings = json.load(f)
    else:
        settings = {}

    gastown_hooks = build_gastown_hooks(gt_home)
    settings = merge_hooks(settings, gastown_hooks)

    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)


def main():
    if len(sys.argv) != 3:
        print(f'Usage: {sys.argv[0]} <settings_path> <gt_home>', file=sys.stderr)
        sys.exit(1)
    settings_path = sys.argv[1]
    gt_home = sys.argv[2]
    merge_claude_hooks(settings_path, gt_home)


if __name__ == '__main__':
    main()
