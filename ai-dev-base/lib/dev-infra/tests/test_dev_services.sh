#!/bin/bash
# Tests for dev-services.sh
# Runs in temp directories with mock binaries to avoid side effects.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_SERVICES="$SCRIPT_DIR/../setup/dev-services.sh"

TESTS_RUN=0
TESTS_PASSED=0

assert_success() {
  local test_name="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "  PASS: $test_name"
}

assert_failure() {
  local test_name="$1"
  local details="${2:-}"
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "  FAIL: $test_name"
  if [ -n "$details" ]; then
    echo "    $details"
  fi
}

# Create mock binaries that record calls
setup_mocks() {
  MOCK_BIN=$(mktemp -d)
  MOCK_LOG=$(mktemp)

  # Mock gt
  cat > "$MOCK_BIN/gt" << 'MOCK'
#!/bin/bash
echo "gt $*" >> "$MOCK_LOG"
case "$1" in
  daemon)
    case "$2" in
      status) exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  up|down) exit 0 ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "$MOCK_BIN/gt"
  # Inject MOCK_LOG into the mock
  sed -i "s|\$MOCK_LOG|$MOCK_LOG|g" "$MOCK_BIN/gt"

  # Mock bd
  cat > "$MOCK_BIN/bd" << 'MOCK'
#!/bin/bash
echo "bd $*" >> "$MOCK_LOG"
case "$1" in
  daemon)
    case "$2" in
      status) exit 0 ;;
      start) exit 0 ;;
      stop) exit 0 ;;
    esac
    ;;
  migrate) exit 0 ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "$MOCK_BIN/bd"
  sed -i "s|\$MOCK_LOG|$MOCK_LOG|g" "$MOCK_BIN/bd"

  # Mock git
  cat > "$MOCK_BIN/git" << 'MOCK'
#!/bin/bash
echo "git $*" >> "$MOCK_LOG"
exit 0
MOCK
  chmod +x "$MOCK_BIN/git"
  sed -i "s|\$MOCK_LOG|$MOCK_LOG|g" "$MOCK_BIN/git"

  export MOCK_BIN MOCK_LOG
}

cleanup_mocks() {
  rm -rf "$MOCK_BIN" "$MOCK_LOG"
}

# Create a minimal gastown home directory
setup_gastown_home() {
  local gt_home=$(mktemp -d)
  mkdir -p "$gt_home/mayor"
  echo '{"type":"town"}' > "$gt_home/mayor/town.json"
  mkdir -p "$gt_home/.beads"
  mkdir -p "$gt_home/daemon"
  mkdir -p "$gt_home/deacon"
  echo "$gt_home"
}

echo "========================================"
echo "Testing dev-services.sh"
echo "========================================"

# -----------------------------------------------------------
# Test 1: No arguments prints usage and exits non-zero
# -----------------------------------------------------------
echo ""
echo "Test 1: No arguments prints usage"
output=$(bash "$DEV_SERVICES" 2>&1 || true)
exit_code=0
bash "$DEV_SERVICES" >/dev/null 2>&1 || exit_code=$?
if [ $exit_code -ne 0 ] && echo "$output" | grep -q "Usage:"; then
  assert_success "No arguments prints usage and exits non-zero"
else
  assert_failure "No arguments prints usage and exits non-zero" "exit=$exit_code output=$output"
fi

# -----------------------------------------------------------
# Test 2: Unknown subcommand prints usage and exits non-zero
# -----------------------------------------------------------
echo ""
echo "Test 2: Unknown subcommand prints usage"
output=$(bash "$DEV_SERVICES" foobar 2>&1 || true)
exit_code=0
bash "$DEV_SERVICES" foobar >/dev/null 2>&1 || exit_code=$?
if [ $exit_code -ne 0 ] && echo "$output" | grep -q "Usage:"; then
  assert_success "Unknown subcommand prints usage and exits non-zero"
else
  assert_failure "Unknown subcommand prints usage and exits non-zero" "exit=$exit_code"
fi

# -----------------------------------------------------------
# Test 3: --help prints usage and exits zero
# -----------------------------------------------------------
echo ""
echo "Test 3: --help prints usage"
output=$(bash "$DEV_SERVICES" --help 2>&1)
exit_code=$?
if [ $exit_code -eq 0 ] && echo "$output" | grep -q "Usage:"; then
  assert_success "--help prints usage and exits zero"
else
  assert_failure "--help prints usage and exits zero" "exit=$exit_code"
fi

# -----------------------------------------------------------
# Test 4: start skips gastown services when GASTOWN_ENABLED=false
# -----------------------------------------------------------
echo ""
echo "Test 4: start skips gastown services when disabled"
setup_mocks
GT_HOME=$(setup_gastown_home)
(
  export GASTOWN_ENABLED=false
  export GASTOWN_HOME="$GT_HOME"
  PATH="$MOCK_BIN:$PATH" bash "$DEV_SERVICES" start 2>/dev/null
)
# gt and bd should NOT have been called
if [ ! -s "$MOCK_LOG" ] || ! grep -q "^gt " "$MOCK_LOG" 2>/dev/null; then
  assert_success "Start skips gastown services when GASTOWN_ENABLED=false"
else
  assert_failure "Start skips gastown services when GASTOWN_ENABLED=false" "gt was called: $(cat "$MOCK_LOG")"
fi
rm -rf "$GT_HOME"
cleanup_mocks

# -----------------------------------------------------------
# Test 5: start calls gt up when gastown is enabled
# -----------------------------------------------------------
echo ""
echo "Test 5: start calls gt up when enabled"
setup_mocks
GT_HOME=$(setup_gastown_home)
(
  export GASTOWN_ENABLED=true
  export GASTOWN_HOME="$GT_HOME"
  PATH="$MOCK_BIN:$PATH" bash "$DEV_SERVICES" start 2>/dev/null
)
if grep -q "^gt up" "$MOCK_LOG" 2>/dev/null; then
  assert_success "Start calls gt up when gastown is enabled"
else
  assert_failure "Start calls gt up when gastown is enabled" "Mock log: $(cat "$MOCK_LOG" 2>/dev/null)"
fi
rm -rf "$GT_HOME"
cleanup_mocks

# -----------------------------------------------------------
# Test 6: stop calls gt down when gastown is enabled
# -----------------------------------------------------------
echo ""
echo "Test 6: stop calls gt down when enabled"
setup_mocks
GT_HOME=$(setup_gastown_home)
(
  export GASTOWN_ENABLED=true
  export GASTOWN_HOME="$GT_HOME"
  PATH="$MOCK_BIN:$PATH" bash "$DEV_SERVICES" stop 2>/dev/null
)
if grep -q "^gt down" "$MOCK_LOG" 2>/dev/null; then
  assert_success "Stop calls gt down when gastown is enabled"
else
  assert_failure "Stop calls gt down when gastown is enabled" "Mock log: $(cat "$MOCK_LOG" 2>/dev/null)"
fi
rm -rf "$GT_HOME"
cleanup_mocks

# -----------------------------------------------------------
# Test 7: status reports all five services
# -----------------------------------------------------------
echo ""
echo "Test 7: status reports all services"
setup_mocks
GT_HOME=$(setup_gastown_home)
output=$(
  export GASTOWN_ENABLED=true
  export GASTOWN_HOME="$GT_HOME"
  PATH="$MOCK_BIN:$PATH" bash "$DEV_SERVICES" status 2>/dev/null
) || true  # status exits non-zero when services are stopped
has_all=true
for svc in credentials beads-daemon gastown watchdog notifier; do
  if ! echo "$output" | grep -q "$svc"; then
    has_all=false
    break
  fi
done
if [ "$has_all" = true ]; then
  assert_success "Status reports all five services"
else
  assert_failure "Status reports all five services" "Output: $output"
fi
rm -rf "$GT_HOME"
cleanup_mocks

# -----------------------------------------------------------
# Test 8: stop handles missing PID files gracefully
# -----------------------------------------------------------
echo ""
echo "Test 8: stop handles missing PID files"
setup_mocks
GT_HOME=$(setup_gastown_home)
(
  export GASTOWN_ENABLED=true
  export GASTOWN_HOME="$GT_HOME"
  # Ensure no PID files exist
  rm -f "$GT_HOME/.daemon_watchdog.pid"
  PATH="$MOCK_BIN:$PATH" bash "$DEV_SERVICES" stop 2>/dev/null
)
exit_code=$?
if [ $exit_code -eq 0 ]; then
  assert_success "Stop handles missing PID files gracefully"
else
  assert_failure "Stop handles missing PID files gracefully" "exit=$exit_code"
fi
rm -rf "$GT_HOME"
cleanup_mocks

# -----------------------------------------------------------
# Test 9: stop terminates process by PID file
# -----------------------------------------------------------
echo ""
echo "Test 9: stop terminates watchdog by PID file"
GT_HOME=$(setup_gastown_home)
# Start a sleep process as a mock watchdog
sleep 300 &
mock_pid=$!
echo "$mock_pid" > "$GT_HOME/.daemon_watchdog.pid"
(
  export GASTOWN_ENABLED=true
  export GASTOWN_HOME="$GT_HOME"
  # Need real gt/bd in PATH for the gastown stop function,
  # but the key thing we're testing is the watchdog PID kill.
  # Use a mock gt that does nothing for gt down.
  MOCK_BIN2=$(mktemp -d)
  cat > "$MOCK_BIN2/gt" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$MOCK_BIN2/gt"
  cat > "$MOCK_BIN2/bd" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$MOCK_BIN2/bd"
  PATH="$MOCK_BIN2:$PATH" bash "$DEV_SERVICES" stop 2>/dev/null
  rm -rf "$MOCK_BIN2"
)
# Check that the mock watchdog process was killed
if ! kill -0 "$mock_pid" 2>/dev/null; then
  assert_success "Stop terminates watchdog process via PID file"
else
  kill "$mock_pid" 2>/dev/null || true
  assert_failure "Stop terminates watchdog process via PID file" "Process $mock_pid still running"
fi
# PID file should be removed
if [ ! -f "$GT_HOME/.daemon_watchdog.pid" ]; then
  assert_success "Stop removes watchdog PID file"
else
  assert_failure "Stop removes watchdog PID file" "PID file still exists"
fi
rm -rf "$GT_HOME"

# -----------------------------------------------------------
# Test 10: start is idempotent (no errors on double-start)
# -----------------------------------------------------------
echo ""
echo "Test 10: start is idempotent"
setup_mocks
GT_HOME=$(setup_gastown_home)
(
  export GASTOWN_ENABLED=true
  export GASTOWN_HOME="$GT_HOME"
  PATH="$MOCK_BIN:$PATH" bash "$DEV_SERVICES" start 2>/dev/null
  PATH="$MOCK_BIN:$PATH" bash "$DEV_SERVICES" start 2>/dev/null
)
exit_code=$?
if [ $exit_code -eq 0 ]; then
  assert_success "Start is idempotent (no errors on double-start)"
else
  assert_failure "Start is idempotent (no errors on double-start)" "exit=$exit_code"
fi
rm -rf "$GT_HOME"
cleanup_mocks

# -----------------------------------------------------------
# Test 11: restart calls stop then start
# -----------------------------------------------------------
echo ""
echo "Test 11: restart calls stop then start"
setup_mocks
GT_HOME=$(setup_gastown_home)
(
  export GASTOWN_ENABLED=true
  export GASTOWN_HOME="$GT_HOME"
  PATH="$MOCK_BIN:$PATH" bash "$DEV_SERVICES" restart 2>/dev/null
)
has_down=false
has_up=false
if grep -q "^gt down" "$MOCK_LOG" 2>/dev/null; then has_down=true; fi
if grep -q "^gt up" "$MOCK_LOG" 2>/dev/null; then has_up=true; fi
if [ "$has_down" = true ] && [ "$has_up" = true ]; then
  # Verify down comes before up
  down_line=$(grep -n "^gt down" "$MOCK_LOG" | head -1 | cut -d: -f1)
  up_line=$(grep -n "^gt up" "$MOCK_LOG" | head -1 | cut -d: -f1)
  if [ "$down_line" -lt "$up_line" ]; then
    assert_success "Restart calls stop (gt down) before start (gt up)"
  else
    assert_failure "Restart calls stop (gt down) before start (gt up)" "down at line $down_line, up at line $up_line"
  fi
else
  assert_failure "Restart calls stop then start" "has_down=$has_down has_up=$has_up"
fi
rm -rf "$GT_HOME"
cleanup_mocks

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
  echo "All tests passed!"
  exit 0
else
  echo ""
  echo "Some tests failed"
  exit 1
fi
