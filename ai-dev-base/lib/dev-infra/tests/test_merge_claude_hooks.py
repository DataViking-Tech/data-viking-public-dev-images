#!/usr/bin/env python3
"""Unit tests for merge_claude_hooks.py"""
import json
import os
import sys
import tempfile
import unittest

# Add setup dir to path so we can import the module directly
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'setup'))
from merge_claude_hooks import (
    build_gastown_hooks,
    gt_cmd,
    hook_entry,
    merge_claude_hooks,
    merge_hooks,
)


class TestHookEntry(unittest.TestCase):
    def test_basic_entry_has_nested_hooks(self):
        entry = hook_entry('echo hello')
        self.assertEqual(entry['hooks'], [{'type': 'command', 'command': 'echo hello'}])
        self.assertNotIn('matcher', entry)

    def test_entry_with_matcher(self):
        entry = hook_entry('echo hello', matcher='Bash(git*)')
        self.assertEqual(entry['matcher'], 'Bash(git*)')
        self.assertEqual(entry['hooks'][0]['command'], 'echo hello')

    def test_hook_type_is_command(self):
        entry = hook_entry('any command')
        self.assertEqual(entry['hooks'][0]['type'], 'command')


class TestGtCmd(unittest.TestCase):
    def test_wraps_with_cd(self):
        result = gt_cmd('/home/user/gt', 'gt prime')
        self.assertEqual(result, 'cd /home/user/gt && gt prime')

    def test_preserves_flags(self):
        result = gt_cmd('/gt', 'gt prime --hook 2>/dev/null || true')
        self.assertEqual(result, 'cd /gt && gt prime --hook 2>/dev/null || true')


class TestBuildGastownHooks(unittest.TestCase):
    def setUp(self):
        self.gt_home = '/fake/gt'
        self.hooks = build_gastown_hooks(self.gt_home)

    def test_has_required_events(self):
        for event in ('SessionStart', 'PreCompact', 'UserPromptSubmit', 'PreToolUse', 'Stop'):
            self.assertIn(event, self.hooks)

    def test_all_gt_commands_start_with_cd(self):
        for event, entries in self.hooks.items():
            for entry in entries:
                for h in entry.get('hooks', []):
                    cmd = h.get('command', '')
                    if 'gt ' in cmd:
                        self.assertTrue(cmd.startswith('cd '),
                                        f'{event} command not wrapped: {cmd}')

    def test_pretooluse_entries_have_matchers(self):
        for entry in self.hooks['PreToolUse']:
            self.assertIn('matcher', entry, f'PreToolUse entry missing matcher: {entry}')

    def test_stop_has_costs_record(self):
        cmds = [h['command'] for e in self.hooks['Stop'] for h in e.get('hooks', [])]
        self.assertTrue(any('gt costs record' in c for c in cmds))

    def test_session_start_has_prime(self):
        cmds = [h['command'] for e in self.hooks['SessionStart'] for h in e.get('hooks', [])]
        self.assertTrue(any('gt prime' in c for c in cmds))

    def test_mayor_edit_guard_for_edit_and_write(self):
        edit_found = False
        write_found = False
        for entry in self.hooks['PreToolUse']:
            matcher = entry.get('matcher', '')
            for h in entry.get('hooks', []):
                if 'mayor-edit' in h.get('command', ''):
                    if matcher == 'Edit':
                        edit_found = True
                    if matcher == 'Write':
                        write_found = True
        self.assertTrue(edit_found, 'mayor-edit guard missing for Edit')
        self.assertTrue(write_found, 'mayor-edit guard missing for Write')

    def test_uses_provided_gt_home(self):
        cmds = []
        for entries in self.hooks.values():
            for entry in entries:
                for h in entry.get('hooks', []):
                    cmds.append(h.get('command', ''))
        self.assertTrue(all(self.gt_home in c for c in cmds),
                        'Not all commands reference the provided gt_home')


class TestMergeHooks(unittest.TestCase):
    def setUp(self):
        self.gt_home = '/fake/gt'
        self.gastown_hooks = build_gastown_hooks(self.gt_home)

    def test_merge_into_empty_settings(self):
        settings = {}
        result = merge_hooks(settings, self.gastown_hooks)
        self.assertIn('hooks', result)
        self.assertIn('Stop', result['hooks'])

    def test_no_duplicates_on_second_merge(self):
        settings = {}
        merge_hooks(settings, self.gastown_hooks)
        merge_hooks(settings, self.gastown_hooks)
        stop = settings['hooks']['Stop']
        costs_count = sum(
            1 for e in stop for h in e.get('hooks', [])
            if 'gt costs record' in h.get('command', '')
        )
        self.assertEqual(costs_count, 1)

    def test_preserves_existing_hooks(self):
        settings = {
            'hooks': {
                'Stop': [{'hooks': [{'type': 'command', 'command': 'echo custom'}]}]
            }
        }
        merge_hooks(settings, self.gastown_hooks)
        stop = settings['hooks']['Stop']
        custom_found = any(
            'echo custom' in h.get('command', '')
            for e in stop for h in e.get('hooks', [])
        )
        gastown_found = any(
            'gt costs record' in h.get('command', '')
            for e in stop for h in e.get('hooks', [])
        )
        self.assertTrue(custom_found, 'Existing hook was removed')
        self.assertTrue(gastown_found, 'Gastown hook not added')

    def test_skips_duplicate_flat_format_commands(self):
        """Handles legacy flat {command: ...} entries when deduplicating."""
        cmd = f'cd {self.gt_home} && gt costs record 2>/dev/null || true'
        settings = {
            'hooks': {
                'Stop': [{'command': cmd}]  # flat format (legacy)
            }
        }
        merge_hooks(settings, self.gastown_hooks)
        stop = settings['hooks']['Stop']
        costs_count = sum(
            1 for e in stop for h in e.get('hooks', [])
            if 'gt costs record' in h.get('command', '')
        )
        # The flat entry is not counted as nested, but the new nested entry
        # should not be added because the command is already in existing_cmds
        self.assertEqual(costs_count, 0, 'Duplicate was added despite flat-format entry')


class TestMergeClaudeHooks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.settings_path = os.path.join(self.tmp, '.claude', 'settings.json')
        os.makedirs(os.path.dirname(self.settings_path))
        self.gt_home = '/fake/gt'

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_creates_settings_when_absent(self):
        path = os.path.join(self.tmp, 'new_settings.json')
        merge_claude_hooks(path, self.gt_home)
        self.assertTrue(os.path.exists(path))
        with open(path) as f:
            data = json.load(f)
        self.assertIn('hooks', data)

    def test_reads_and_preserves_existing_settings(self):
        existing = {'theme': 'dark', 'hooks': {}}
        with open(self.settings_path, 'w') as f:
            json.dump(existing, f)
        merge_claude_hooks(self.settings_path, self.gt_home)
        with open(self.settings_path) as f:
            data = json.load(f)
        self.assertEqual(data.get('theme'), 'dark')

    def test_writes_valid_json(self):
        merge_claude_hooks(self.settings_path, self.gt_home)
        with open(self.settings_path) as f:
            data = json.load(f)  # would raise if invalid JSON
        self.assertIsInstance(data, dict)

    def test_idempotent_on_second_call(self):
        merge_claude_hooks(self.settings_path, self.gt_home)
        merge_claude_hooks(self.settings_path, self.gt_home)
        with open(self.settings_path) as f:
            data = json.load(f)
        stop = data.get('hooks', {}).get('Stop', [])
        costs_count = sum(
            1 for e in stop for h in e.get('hooks', [])
            if 'gt costs record' in h.get('command', '')
        )
        self.assertEqual(costs_count, 1)


if __name__ == '__main__':
    unittest.main()
