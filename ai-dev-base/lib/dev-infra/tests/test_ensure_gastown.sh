#!/bin/bash
# Tests for ensure_gastown.sh
# Runs in a temp directory to avoid side effects.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENSURE_GASTOWN="$SCRIPT_DIR/../setup/ensure_gastown.sh"
START_GASTOWN="$SCRIPT_DIR/../setup/start_gastown_services.sh"

TESTS_RUN=0
TESTS_PASSED=0

assert_success() {
  local test_name="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "✓ PASS: $test_name"
}

assert_failure() {
  local test_name="$1"
  local details="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "✗ FAIL: $test_name"
  if [ -n "$details" ]; then
    echo "  $details"
  fi
}

assert_contains() {
  local substring="$1"
  local string="$2"
  local test_name="$3"

  TESTS_RUN=$((TESTS_RUN + 1))

  if [[ "$string" == *"$substring"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "✓ PASS: $test_name"
  else
    echo "✗ FAIL: $test_name"
    echo "  Expected to contain: $substring"
    echo "  Actual: $string"
  fi
}

assert_file_exists() {
  local file="$1"
  local test_name="$2"

  TESTS_RUN=$((TESTS_RUN + 1))

  if [ -f "$file" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "✓ PASS: $test_name"
  else
    echo "✗ FAIL: $test_name"
    echo "  File does not exist: $file"
  fi
}

echo "========================================"
echo "Testing ensure_gastown.sh"
echo "========================================"

# -----------------------------------------------------------
# Test 1: Skips when gt is not installed
# -----------------------------------------------------------
echo ""
echo "Test 1: Skips when gt is not installed"
WORK_DIR=$(mktemp -d)
(
  cd "$WORK_DIR"
  # Run with a PATH that has no gt
  PATH="/usr/bin:/bin" bash "$ENSURE_GASTOWN" 2>/dev/null
)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  assert_success "Exits cleanly when gt is not installed"
else
  assert_failure "Exits cleanly when gt is not installed" "exit code: $EXIT_CODE"
fi
rm -rf "$WORK_DIR"

# -----------------------------------------------------------
# Test 2: Adds .events.jsonl and .runtime/ to .gitignore
# -----------------------------------------------------------
echo ""
echo "Test 2: Adds gastown entries to .gitignore"
if command -v gt >/dev/null 2>&1; then
  WORK_DIR=$(mktemp -d)
  FAKE_GT_HOME=$(mktemp -d)
  # Create minimal town structure so gt install step is skipped
  mkdir -p "$FAKE_GT_HOME/mayor"
  echo '{}' > "$FAKE_GT_HOME/mayor/town.json"
  (
    cd "$WORK_DIR"
    git init -q .
    git remote add origin https://example.com/test/repo.git 2>/dev/null || true
    echo "existing_entry" > .gitignore
    GASTOWN_HOME="$FAKE_GT_HOME" HOME="$FAKE_GT_HOME" bash "$ENSURE_GASTOWN" 2>/dev/null || true
  )
  PASS=true
  if ! grep -qx '.events.jsonl' "$WORK_DIR/.gitignore" 2>/dev/null; then
    PASS=false
  fi
  if ! grep -qx '.runtime/' "$WORK_DIR/.gitignore" 2>/dev/null; then
    PASS=false
  fi
  if ! grep -qx 'existing_entry' "$WORK_DIR/.gitignore" 2>/dev/null; then
    PASS=false
  fi
  if $PASS; then
    assert_success "Adds .events.jsonl and .runtime/ to existing .gitignore"
  else
    assert_failure "Adds .events.jsonl and .runtime/ to existing .gitignore" \
      "Contents: $(cat "$WORK_DIR/.gitignore" 2>/dev/null)"
  fi
  rm -rf "$WORK_DIR" "$FAKE_GT_HOME"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "⊘ SKIP: Test 2 (gt CLI not installed)"
fi

# -----------------------------------------------------------
# Test 3: Does not duplicate .gitignore entries
# -----------------------------------------------------------
echo ""
echo "Test 3: Does not duplicate .gitignore entries"
if command -v gt >/dev/null 2>&1; then
  WORK_DIR=$(mktemp -d)
  FAKE_GT_HOME=$(mktemp -d)
  mkdir -p "$FAKE_GT_HOME/mayor"
  echo '{}' > "$FAKE_GT_HOME/mayor/town.json"
  (
    cd "$WORK_DIR"
    git init -q .
    git remote add origin https://example.com/test/repo.git 2>/dev/null || true
    printf '.events.jsonl\n.runtime/\n' > .gitignore
    GASTOWN_HOME="$FAKE_GT_HOME" HOME="$FAKE_GT_HOME" bash "$ENSURE_GASTOWN" 2>/dev/null || true
  )
  EVENTS_COUNT=$(grep -cx '.events.jsonl' "$WORK_DIR/.gitignore" 2>/dev/null || echo 0)
  RUNTIME_COUNT=$(grep -cx '.runtime/' "$WORK_DIR/.gitignore" 2>/dev/null || echo 0)
  if [ "$EVENTS_COUNT" -eq 1 ] && [ "$RUNTIME_COUNT" -eq 1 ]; then
    assert_success "Does not duplicate .gitignore entries"
  else
    assert_failure "Does not duplicate .gitignore entries" \
      ".events.jsonl count: $EVENTS_COUNT, .runtime/ count: $RUNTIME_COUNT"
  fi
  rm -rf "$WORK_DIR" "$FAKE_GT_HOME"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "⊘ SKIP: Test 3 (gt CLI not installed)"
fi

# -----------------------------------------------------------
# Test 4: Creates .gitignore in a git repo with no .gitignore
# -----------------------------------------------------------
echo ""
echo "Test 4: Creates .gitignore in a git repo with no .gitignore"
if command -v gt >/dev/null 2>&1; then
  WORK_DIR=$(mktemp -d)
  FAKE_GT_HOME=$(mktemp -d)
  mkdir -p "$FAKE_GT_HOME/mayor"
  echo '{}' > "$FAKE_GT_HOME/mayor/town.json"
  (
    cd "$WORK_DIR"
    git init -q .
    git remote add origin https://example.com/test/repo.git 2>/dev/null || true
    GASTOWN_HOME="$FAKE_GT_HOME" HOME="$FAKE_GT_HOME" bash "$ENSURE_GASTOWN" 2>/dev/null || true
  )
  if [ -f "$WORK_DIR/.gitignore" ] && grep -qx '.events.jsonl' "$WORK_DIR/.gitignore"; then
    assert_success "Creates .gitignore with gastown entries"
  else
    assert_failure "Creates .gitignore with gastown entries" \
      "File exists: $([ -f "$WORK_DIR/.gitignore" ] && echo yes || echo no)"
  fi
  rm -rf "$WORK_DIR" "$FAKE_GT_HOME"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "⊘ SKIP: Test 4 (gt CLI not installed)"
fi

# -----------------------------------------------------------
# Test 5: Rig name normalizes special characters
# -----------------------------------------------------------
echo ""
echo "Test 5: Rig name normalizes special characters"
# This tests the normalization logic: tr '-. ' '_'
# We test the bash expression directly since full rig registration
# depends on gt infrastructure.
INPUT="my-cool.project name"
NORMALIZED=$(echo "$INPUT" | tr -- '-. ' '_')
if [ "$NORMALIZED" = "my_cool_project_name" ]; then
  assert_success "Rig name normalizes dashes, dots, spaces to underscores"
else
  assert_failure "Rig name normalizes dashes, dots, spaces to underscores" \
    "Expected: my_cool_project_name, Got: $NORMALIZED"
fi

# -----------------------------------------------------------
# Test 6: Merges hooks into settings.json in correct nested format
# -----------------------------------------------------------
echo ""
echo "Test 6: Merges hooks into settings.json in nested format"
if command -v gt >/dev/null 2>&1; then
  WORK_DIR=$(mktemp -d)
  FAKE_GT_HOME=$(mktemp -d)
  FAKE_HOME=$(mktemp -d)
  mkdir -p "$FAKE_GT_HOME/mayor"
  echo '{}' > "$FAKE_GT_HOME/mayor/town.json"
  (
    cd "$WORK_DIR"
    git init -q .
    GASTOWN_HOME="$FAKE_GT_HOME" HOME="$FAKE_HOME" bash "$ENSURE_GASTOWN" 2>/dev/null || true
  )
  SETTINGS="$FAKE_HOME/.claude/settings.json"
  if [ -f "$SETTINGS" ]; then
    # Verify the nested hook format: hooks[event][n].hooks[m].command
    VALID=$(python3 -c "
import json, sys
with open('$SETTINGS') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
# Check Stop event has the gt costs record command in nested format
stop = hooks.get('Stop', [])
found_costs = False
for entry in stop:
    for h in entry.get('hooks', []):
        if 'gt costs record' in h.get('command', ''):
            found_costs = True
            if h.get('type') != 'command':
                sys.exit(1)
if not found_costs:
    sys.exit(1)
# Check SessionStart has gt prime
start = hooks.get('SessionStart', [])
found_prime = False
for entry in start:
    for h in entry.get('hooks', []):
        if 'gt prime' in h.get('command', ''):
            found_prime = True
if not found_prime:
    sys.exit(1)
sys.exit(0)
" 2>&1 && echo "OK" || echo "FAIL")
    if [ "$VALID" = "OK" ]; then
      assert_success "Hooks merged in correct nested format"
    else
      assert_failure "Hooks merged in correct nested format" \
        "Settings content: $(cat "$SETTINGS")"
    fi
  else
    assert_failure "Hooks merged in correct nested format" "settings.json not created"
  fi
  rm -rf "$WORK_DIR" "$FAKE_GT_HOME" "$FAKE_HOME"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "⊘ SKIP: Test 6 (gt CLI not installed)"
fi

# -----------------------------------------------------------
# Test 7: Hook deduplication on second run
# -----------------------------------------------------------
echo ""
echo "Test 7: Hook deduplication on second run"
if command -v gt >/dev/null 2>&1; then
  WORK_DIR=$(mktemp -d)
  FAKE_GT_HOME=$(mktemp -d)
  FAKE_HOME=$(mktemp -d)
  mkdir -p "$FAKE_GT_HOME/mayor"
  echo '{}' > "$FAKE_GT_HOME/mayor/town.json"
  (
    cd "$WORK_DIR"
    git init -q .
    # Run twice to test deduplication
    GASTOWN_HOME="$FAKE_GT_HOME" HOME="$FAKE_HOME" bash "$ENSURE_GASTOWN" 2>/dev/null || true
    GASTOWN_HOME="$FAKE_GT_HOME" HOME="$FAKE_HOME" bash "$ENSURE_GASTOWN" 2>/dev/null || true
  )
  SETTINGS="$FAKE_HOME/.claude/settings.json"
  if [ -f "$SETTINGS" ]; then
    COUNT=$(python3 -c "
import json
with open('$SETTINGS') as f:
    data = json.load(f)
stop = data.get('hooks', {}).get('Stop', [])
count = 0
for entry in stop:
    for h in entry.get('hooks', []):
        if 'gt costs record' in h.get('command', ''):
            count += 1
print(count)
" 2>&1)
    if [ "$COUNT" = "1" ]; then
      assert_success "Hooks not duplicated on second run"
    else
      assert_failure "Hooks not duplicated on second run" \
        "gt costs record appears $COUNT times in Stop hooks"
    fi
  else
    assert_failure "Hooks not duplicated on second run" "settings.json not created"
  fi
  rm -rf "$WORK_DIR" "$FAKE_GT_HOME" "$FAKE_HOME"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "⊘ SKIP: Test 7 (gt CLI not installed)"
fi

# -----------------------------------------------------------
# Test 8: Preserves existing hooks in settings.json
# -----------------------------------------------------------
echo ""
echo "Test 8: Preserves existing hooks in settings.json"
if command -v gt >/dev/null 2>&1; then
  WORK_DIR=$(mktemp -d)
  FAKE_GT_HOME=$(mktemp -d)
  FAKE_HOME=$(mktemp -d)
  mkdir -p "$FAKE_GT_HOME/mayor"
  echo '{}' > "$FAKE_GT_HOME/mayor/town.json"
  # Pre-populate settings.json with an existing hook
  mkdir -p "$FAKE_HOME/.claude"
  cat > "$FAKE_HOME/.claude/settings.json" << 'EOF'
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo custom-hook"
          }
        ]
      }
    ]
  }
}
EOF
  (
    cd "$WORK_DIR"
    git init -q .
    GASTOWN_HOME="$FAKE_GT_HOME" HOME="$FAKE_HOME" bash "$ENSURE_GASTOWN" 2>/dev/null || true
  )
  SETTINGS="$FAKE_HOME/.claude/settings.json"
  PRESERVED=$(python3 -c "
import json, sys
with open('$SETTINGS') as f:
    data = json.load(f)
stop = data.get('hooks', {}).get('Stop', [])
found_custom = False
found_gastown = False
for entry in stop:
    for h in entry.get('hooks', []):
        if 'echo custom-hook' in h.get('command', ''):
            found_custom = True
        if 'gt costs record' in h.get('command', ''):
            found_gastown = True
if found_custom and found_gastown:
    print('OK')
else:
    print(f'custom={found_custom} gastown={found_gastown}')
" 2>&1)
  if [ "$PRESERVED" = "OK" ]; then
    assert_success "Preserves existing hooks while adding gastown hooks"
  else
    assert_failure "Preserves existing hooks while adding gastown hooks" \
      "Result: $PRESERVED"
  fi
  rm -rf "$WORK_DIR" "$FAKE_GT_HOME" "$FAKE_HOME"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "⊘ SKIP: Test 8 (gt CLI not installed)"
fi

# -----------------------------------------------------------
# Test 9: PreToolUse hooks include matcher field
# -----------------------------------------------------------
echo ""
echo "Test 9: PreToolUse hooks include matcher field"
if command -v gt >/dev/null 2>&1; then
  WORK_DIR=$(mktemp -d)
  FAKE_GT_HOME=$(mktemp -d)
  FAKE_HOME=$(mktemp -d)
  mkdir -p "$FAKE_GT_HOME/mayor"
  echo '{}' > "$FAKE_GT_HOME/mayor/town.json"
  (
    cd "$WORK_DIR"
    git init -q .
    GASTOWN_HOME="$FAKE_GT_HOME" HOME="$FAKE_HOME" bash "$ENSURE_GASTOWN" 2>/dev/null || true
  )
  SETTINGS="$FAKE_HOME/.claude/settings.json"
  if [ -f "$SETTINGS" ]; then
    RESULT=$(python3 -c "
import json, sys
with open('$SETTINGS') as f:
    data = json.load(f)
pre = data.get('hooks', {}).get('PreToolUse', [])
if len(pre) < 3:
    print(f'expected >= 3 entries, got {len(pre)}')
    sys.exit(0)
# Each PreToolUse entry should have a matcher
for entry in pre:
    if 'matcher' not in entry:
        print('missing matcher')
        sys.exit(0)
print('OK')
" 2>&1)
    if [ "$RESULT" = "OK" ]; then
      assert_success "PreToolUse hooks have matcher fields"
    else
      assert_failure "PreToolUse hooks have matcher fields" "$RESULT"
    fi
  else
    assert_failure "PreToolUse hooks have matcher fields" "settings.json not created"
  fi
  rm -rf "$WORK_DIR" "$FAKE_GT_HOME" "$FAKE_HOME"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "⊘ SKIP: Test 9 (gt CLI not installed)"
fi

# -----------------------------------------------------------
# Test 10: Commands are wrapped with cd to GASTOWN_HOME
# -----------------------------------------------------------
echo ""
echo "Test 10: Commands wrapped with cd to GASTOWN_HOME"
if command -v gt >/dev/null 2>&1; then
  WORK_DIR=$(mktemp -d)
  FAKE_GT_HOME=$(mktemp -d)
  FAKE_HOME=$(mktemp -d)
  mkdir -p "$FAKE_GT_HOME/mayor"
  echo '{}' > "$FAKE_GT_HOME/mayor/town.json"
  (
    cd "$WORK_DIR"
    git init -q .
    GASTOWN_HOME="$FAKE_GT_HOME" HOME="$FAKE_HOME" bash "$ENSURE_GASTOWN" 2>/dev/null || true
  )
  SETTINGS="$FAKE_HOME/.claude/settings.json"
  if [ -f "$SETTINGS" ]; then
    RESULT=$(python3 -c "
import json, sys
with open('$SETTINGS') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
for event, entries in hooks.items():
    for entry in entries:
        for h in entry.get('hooks', []):
            cmd = h.get('command', '')
            if 'gt ' in cmd and not cmd.startswith('cd '):
                print(f'{event}: {cmd}')
                sys.exit(0)
print('OK')
" 2>&1)
    if [ "$RESULT" = "OK" ]; then
      assert_success "All gt commands wrapped with cd to GASTOWN_HOME"
    else
      assert_failure "All gt commands wrapped with cd to GASTOWN_HOME" \
        "Unwrapped command: $RESULT"
    fi
  else
    assert_failure "All gt commands wrapped with cd to GASTOWN_HOME" "settings.json not created"
  fi
  rm -rf "$WORK_DIR" "$FAKE_GT_HOME" "$FAKE_HOME"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "⊘ SKIP: Test 10 (gt CLI not installed)"
fi

# -----------------------------------------------------------
# Test 11: start_gastown_services.sh runs credential cache setup
# -----------------------------------------------------------
echo ""
echo "Test 11: start_gastown_services.sh sources credential_cache.sh"
WORK_DIR=$(mktemp -d)
# Create a mock /opt/dev-infra/credential_cache.sh
FAKE_OPT=$(mktemp -d)
mkdir -p "$FAKE_OPT/dev-infra/setup"
# Create a credential_cache.sh that records what services are set up
cat > "$FAKE_OPT/dev-infra/credential_cache.sh" << 'MOCKEOF'
setup_credential_cache() {
  echo "CRED_SERVICES_CALLED: $*"
  return 0
}
verify_credential_propagation() {
  return 0
}
MOCKEOF
# Copy start_gastown_services.sh to use our mock path
sed "s|/opt/dev-infra|$FAKE_OPT/dev-infra|g" "$START_GASTOWN" > "$FAKE_OPT/dev-infra/setup/start_gastown_services.sh"
chmod +x "$FAKE_OPT/dev-infra/setup/start_gastown_services.sh"
# Run without gt available (to skip gastown services, just test cred setup)
OUTPUT=$(PATH="/usr/bin:/bin" bash "$FAKE_OPT/dev-infra/setup/start_gastown_services.sh" 2>&1)
if echo "$OUTPUT" | grep -q "CRED_SERVICES_CALLED: github cloudflare claude"; then
  assert_success "start_gastown_services.sh runs credential setup with defaults"
else
  assert_failure "start_gastown_services.sh runs credential setup with defaults" \
    "Output: $OUTPUT"
fi
rm -rf "$WORK_DIR" "$FAKE_OPT"

# -----------------------------------------------------------
# Test 12: CREDENTIAL_CACHE_SERVICES env var overrides defaults
# -----------------------------------------------------------
echo ""
echo "Test 12: CREDENTIAL_CACHE_SERVICES env var overrides defaults"
FAKE_OPT=$(mktemp -d)
mkdir -p "$FAKE_OPT/dev-infra/setup"
cat > "$FAKE_OPT/dev-infra/credential_cache.sh" << 'MOCKEOF'
setup_credential_cache() {
  echo "CRED_SERVICES_CALLED: $*"
  return 0
}
MOCKEOF
sed "s|/opt/dev-infra|$FAKE_OPT/dev-infra|g" "$START_GASTOWN" > "$FAKE_OPT/dev-infra/setup/start_gastown_services.sh"
chmod +x "$FAKE_OPT/dev-infra/setup/start_gastown_services.sh"
OUTPUT=$(CREDENTIAL_CACHE_SERVICES="github cloudflare" PATH="/usr/bin:/bin" bash "$FAKE_OPT/dev-infra/setup/start_gastown_services.sh" 2>&1)
if echo "$OUTPUT" | grep -q "CRED_SERVICES_CALLED: github cloudflare"; then
  assert_success "CREDENTIAL_CACHE_SERVICES env var overrides default services"
else
  assert_failure "CREDENTIAL_CACHE_SERVICES env var overrides default services" \
    "Output: $OUTPUT"
fi
rm -rf "$FAKE_OPT"

# -----------------------------------------------------------
# Test 13: GASTOWN_ENABLED=false skips ensure_gastown.sh entirely
# -----------------------------------------------------------
echo ""
echo "Test 13: GASTOWN_ENABLED=false skips ensure_gastown.sh"
if command -v gt >/dev/null 2>&1; then
  WORK_DIR=$(mktemp -d)
  FAKE_GT_HOME=$(mktemp -d)
  FAKE_HOME=$(mktemp -d)
  mkdir -p "$FAKE_GT_HOME/mayor"
  echo '{}' > "$FAKE_GT_HOME/mayor/town.json"
  (
    cd "$WORK_DIR"
    git init -q .
    git remote add origin https://example.com/test/repo.git 2>/dev/null || true
    GASTOWN_ENABLED=false GASTOWN_HOME="$FAKE_GT_HOME" HOME="$FAKE_HOME" bash "$ENSURE_GASTOWN" 2>/dev/null || true
  )
  # When disabled, no .gitignore entries should be added and no settings.json created
  SETTINGS="$FAKE_HOME/.claude/settings.json"
  if [ ! -f "$SETTINGS" ] && ! grep -qx '.events.jsonl' "$WORK_DIR/.gitignore" 2>/dev/null; then
    assert_success "GASTOWN_ENABLED=false skips ensure_gastown.sh"
  else
    assert_failure "GASTOWN_ENABLED=false skips ensure_gastown.sh" \
      "settings.json exists: $([ -f "$SETTINGS" ] && echo yes || echo no), gitignore has gastown: $(grep -c '.events.jsonl' "$WORK_DIR/.gitignore" 2>/dev/null || echo 0)"
  fi
  rm -rf "$WORK_DIR" "$FAKE_GT_HOME" "$FAKE_HOME"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "⊘ SKIP: Test 13 (gt CLI not installed)"
fi

# -----------------------------------------------------------
# Test 14: GASTOWN_ENABLED=false skips gastown services but runs cred cache
# -----------------------------------------------------------
echo ""
echo "Test 14: GASTOWN_ENABLED=false skips gastown services but runs credential cache"
FAKE_OPT=$(mktemp -d)
mkdir -p "$FAKE_OPT/dev-infra/setup"
cat > "$FAKE_OPT/dev-infra/credential_cache.sh" << 'MOCKEOF'
setup_credential_cache() {
  echo "CRED_SERVICES_CALLED: $*"
  return 0
}
verify_credential_propagation() {
  return 0
}
MOCKEOF
sed "s|/opt/dev-infra|$FAKE_OPT/dev-infra|g" "$START_GASTOWN" > "$FAKE_OPT/dev-infra/setup/start_gastown_services.sh"
chmod +x "$FAKE_OPT/dev-infra/setup/start_gastown_services.sh"
# Run with GASTOWN_ENABLED=false - should still run cred cache but skip gt up
OUTPUT=$(GASTOWN_ENABLED=false PATH="/usr/bin:/bin" bash "$FAKE_OPT/dev-infra/setup/start_gastown_services.sh" 2>&1)
if echo "$OUTPUT" | grep -q "CRED_SERVICES_CALLED: github cloudflare claude"; then
  assert_success "Credential cache still runs when gastown disabled"
else
  assert_failure "Credential cache still runs when gastown disabled" \
    "Output: $OUTPUT"
fi
rm -rf "$FAKE_OPT"

# -----------------------------------------------------------
# Test 15: GASTOWN_ENABLED unset (default) allows normal operation
# -----------------------------------------------------------
echo ""
echo "Test 15: GASTOWN_ENABLED unset (default) allows normal ensure_gastown.sh"
if command -v gt >/dev/null 2>&1; then
  WORK_DIR=$(mktemp -d)
  FAKE_GT_HOME=$(mktemp -d)
  FAKE_HOME=$(mktemp -d)
  mkdir -p "$FAKE_GT_HOME/mayor"
  echo '{}' > "$FAKE_GT_HOME/mayor/town.json"
  (
    cd "$WORK_DIR"
    git init -q .
    git remote add origin https://example.com/test/repo.git 2>/dev/null || true
    # Explicitly unset GASTOWN_ENABLED to test default behavior
    unset GASTOWN_ENABLED
    GASTOWN_HOME="$FAKE_GT_HOME" HOME="$FAKE_HOME" bash "$ENSURE_GASTOWN" 2>/dev/null || true
  )
  SETTINGS="$FAKE_HOME/.claude/settings.json"
  if [ -f "$SETTINGS" ] && grep -qx '.events.jsonl' "$WORK_DIR/.gitignore" 2>/dev/null; then
    assert_success "Default (unset) GASTOWN_ENABLED allows normal operation"
  else
    assert_failure "Default (unset) GASTOWN_ENABLED allows normal operation" \
      "settings.json exists: $([ -f "$SETTINGS" ] && echo yes || echo no), gitignore has gastown: $(grep -c '.events.jsonl' "$WORK_DIR/.gitignore" 2>/dev/null || echo 0)"
  fi
  rm -rf "$WORK_DIR" "$FAKE_GT_HOME" "$FAKE_HOME"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "⊘ SKIP: Test 15 (gt CLI not installed)"
fi

# -----------------------------------------------------------
# Test 16: Creates .rig_env with BEADS_DIR after rig registration
# -----------------------------------------------------------
echo ""
echo "Test 16: Creates .rig_env with BEADS_DIR after rig registration"
if command -v gt >/dev/null 2>&1; then
  WORK_DIR=$(mktemp -d)
  FAKE_GT_HOME=$(mktemp -d)
  FAKE_HOME=$(mktemp -d)
  mkdir -p "$FAKE_GT_HOME/mayor"
  echo '{}' > "$FAKE_GT_HOME/mayor/town.json"
  (
    cd "$WORK_DIR"
    git init -q .
    git remote add origin https://example.com/test/repo.git 2>/dev/null || true
    GASTOWN_HOME="$FAKE_GT_HOME" HOME="$FAKE_HOME" bash "$ENSURE_GASTOWN" 2>/dev/null || true
  )
  RIG_NAME=$(basename "$WORK_DIR" | tr -- '-. ' '_')
  RIG_ENV="$FAKE_GT_HOME/.rig_env"
  if [ -f "$RIG_ENV" ] && grep -q "BEADS_DIR=" "$RIG_ENV" && grep -q "$RIG_NAME/.beads" "$RIG_ENV"; then
    assert_success "Creates .rig_env with BEADS_DIR pointing to rig beads"
  else
    assert_failure "Creates .rig_env with BEADS_DIR pointing to rig beads" \
      "rig_env exists: $([ -f "$RIG_ENV" ] && echo yes || echo no), content: $(cat "$RIG_ENV" 2>/dev/null || echo '<none>')"
  fi
  rm -rf "$WORK_DIR" "$FAKE_GT_HOME" "$FAKE_HOME"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "⊘ SKIP: Test 16 (gt CLI not installed)"
fi

# -----------------------------------------------------------
# Test 17: .rig_env creates rig .beads directory
# -----------------------------------------------------------
echo ""
echo "Test 17: .rig_env rig .beads directory is created"
if command -v gt >/dev/null 2>&1; then
  WORK_DIR=$(mktemp -d)
  FAKE_GT_HOME=$(mktemp -d)
  FAKE_HOME=$(mktemp -d)
  mkdir -p "$FAKE_GT_HOME/mayor"
  echo '{}' > "$FAKE_GT_HOME/mayor/town.json"
  (
    cd "$WORK_DIR"
    git init -q .
    git remote add origin https://example.com/test/repo.git 2>/dev/null || true
    GASTOWN_HOME="$FAKE_GT_HOME" HOME="$FAKE_HOME" bash "$ENSURE_GASTOWN" 2>/dev/null || true
  )
  RIG_NAME=$(basename "$WORK_DIR" | tr -- '-. ' '_')
  if [ -d "$FAKE_GT_HOME/$RIG_NAME/.beads" ]; then
    assert_success "Rig .beads directory is created"
  else
    assert_failure "Rig .beads directory is created" \
      "Directory $FAKE_GT_HOME/$RIG_NAME/.beads does not exist"
  fi
  rm -rf "$WORK_DIR" "$FAKE_GT_HOME" "$FAKE_HOME"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "⊘ SKIP: Test 17 (gt CLI not installed)"
fi

# -----------------------------------------------------------
# Test 18: PreToolUse hooks include mayor-edit guard for Edit/Write
# -----------------------------------------------------------
echo ""
echo "Test 18: PreToolUse hooks include mayor-edit guard for Edit/Write"
if command -v gt >/dev/null 2>&1; then
  WORK_DIR=$(mktemp -d)
  FAKE_GT_HOME=$(mktemp -d)
  FAKE_HOME=$(mktemp -d)
  mkdir -p "$FAKE_GT_HOME/mayor"
  echo '{}' > "$FAKE_GT_HOME/mayor/town.json"
  (
    cd "$WORK_DIR"
    git init -q .
    GASTOWN_HOME="$FAKE_GT_HOME" HOME="$FAKE_HOME" bash "$ENSURE_GASTOWN" 2>/dev/null || true
  )
  SETTINGS="$FAKE_HOME/.claude/settings.json"
  if [ -f "$SETTINGS" ]; then
    RESULT=$(python3 -c "
import json, sys
with open('$SETTINGS') as f:
    data = json.load(f)
pre = data.get('hooks', {}).get('PreToolUse', [])
found_edit = False
found_write = False
for entry in pre:
    matcher = entry.get('matcher', '')
    for h in entry.get('hooks', []):
        if 'mayor-edit' in h.get('command', ''):
            if matcher == 'Edit':
                found_edit = True
            if matcher == 'Write':
                found_write = True
if found_edit and found_write:
    print('OK')
else:
    print(f'edit={found_edit} write={found_write}')
" 2>&1)
    if [ "$RESULT" = "OK" ]; then
      assert_success "PreToolUse hooks include mayor-edit guard for Edit and Write"
    else
      assert_failure "PreToolUse hooks include mayor-edit guard for Edit and Write" "$RESULT"
    fi
  else
    assert_failure "PreToolUse hooks include mayor-edit guard for Edit and Write" "settings.json not created"
  fi
  rm -rf "$WORK_DIR" "$FAKE_GT_HOME" "$FAKE_HOME"
else
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "⊘ SKIP: Test 18 (gt CLI not installed)"
fi

# Summary
echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Tests run: $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $((TESTS_RUN - TESTS_PASSED))"

if [ $TESTS_RUN -eq $TESTS_PASSED ]; then
  echo ""
  echo "✓ All tests passed!"
  exit 0
else
  echo ""
  echo "✗ Some tests failed"
  exit 1
fi
