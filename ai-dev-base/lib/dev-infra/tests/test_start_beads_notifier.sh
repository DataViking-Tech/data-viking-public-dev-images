#!/bin/bash
# Tests for start_beads_notifier.sh
# Runs in temp directories to avoid side effects.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_NOTIFIER="$SCRIPT_DIR/../setup/start_beads_notifier.sh"

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

echo "========================================"
echo "Testing start_beads_notifier.sh"
echo "========================================"

# -----------------------------------------------------------
# Test 1: Exits cleanly when python3 is not available
# -----------------------------------------------------------
echo ""
echo "Test 1: Exits cleanly when python3 is not available"
WORK_DIR=$(mktemp -d)
(
  cd "$WORK_DIR"
  # Run with a PATH that excludes python3
  PATH="/usr/bin:/bin" bash "$START_NOTIFIER" 2>/dev/null
)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  assert_success "Exits cleanly when python3 is not installed"
else
  assert_failure "Exits cleanly when python3 is not installed" "exit code: $EXIT_CODE"
fi
rm -rf "$WORK_DIR"

# -----------------------------------------------------------
# Test 2: Exits cleanly when .beads/ directory doesn't exist
# -----------------------------------------------------------
echo ""
echo "Test 2: Exits cleanly when .beads/ directory doesn't exist"
WORK_DIR=$(mktemp -d)
(
  cd "$WORK_DIR"
  bash "$START_NOTIFIER" 2>/dev/null
)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  assert_success "Exits cleanly when .beads/ doesn't exist"
else
  assert_failure "Exits cleanly when .beads/ doesn't exist" "exit code: $EXIT_CODE"
fi
rm -rf "$WORK_DIR"

# -----------------------------------------------------------
# Test 3: Exits cleanly when no Slack config is present
# -----------------------------------------------------------
echo ""
echo "Test 3: Exits cleanly when no Slack config is present"
WORK_DIR=$(mktemp -d)
(
  cd "$WORK_DIR"
  mkdir -p .beads
  # No slack_config.yaml, no .secrets/slack_webhook, no SLACK_WEBHOOK_URL
  unset SLACK_WEBHOOK_URL
  bash "$START_NOTIFIER" 2>/dev/null
)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  assert_success "Exits cleanly when no Slack config is present"
else
  assert_failure "Exits cleanly when no Slack config is present" "exit code: $EXIT_CODE"
fi
rm -rf "$WORK_DIR"

# -----------------------------------------------------------
# Test 4: Exits cleanly when daemon already running (valid PID)
# -----------------------------------------------------------
echo ""
echo "Test 4: Exits cleanly when daemon already running (valid PID)"
WORK_DIR=$(mktemp -d)
(
  cd "$WORK_DIR"
  mkdir -p .beads
  touch .beads/slack_config.yaml
  # Write our own PID (guaranteed to be running)
  echo $$ > .beads/slack_notifier.pid
  bash "$START_NOTIFIER" 2>/dev/null
)
EXIT_CODE=$?
# The script should exit 0 without trying to start a new daemon
if [ $EXIT_CODE -eq 0 ]; then
  assert_success "Exits cleanly when daemon already running"
else
  assert_failure "Exits cleanly when daemon already running" "exit code: $EXIT_CODE"
fi
rm -rf "$WORK_DIR"

# -----------------------------------------------------------
# Test 5: Cleans up stale PID file
# -----------------------------------------------------------
echo ""
echo "Test 5: Cleans up stale PID file"
WORK_DIR=$(mktemp -d)
(
  cd "$WORK_DIR"
  mkdir -p .beads
  # Use a PID that definitely doesn't exist
  echo 999999 > .beads/slack_notifier.pid
  # No config so it won't try to launch
  unset SLACK_WEBHOOK_URL
  bash "$START_NOTIFIER" 2>/dev/null
)
# Stale PID file should have been removed
if [ ! -f "$WORK_DIR/.beads/slack_notifier.pid" ]; then
  assert_success "Cleans up stale PID file"
else
  assert_failure "Cleans up stale PID file" "PID file still exists"
fi
rm -rf "$WORK_DIR"

# -----------------------------------------------------------
# Test 6: Detects slack_config.yaml as valid config
# -----------------------------------------------------------
echo ""
echo "Test 6: Detects slack_config.yaml as valid config"
WORK_DIR=$(mktemp -d)
# Create a mock python3 that records it was called with --daemon
MOCK_BIN=$(mktemp -d)
cat > "$MOCK_BIN/python3" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"--daemon"* ]]; then
  echo "DAEMON_STARTED" > "$WORK_DIR/.beads/daemon_started"
fi
exit 0
MOCK
chmod +x "$MOCK_BIN/python3"
(
  cd "$WORK_DIR"
  export WORK_DIR
  mkdir -p .beads
  touch .beads/slack_config.yaml
  unset SLACK_WEBHOOK_URL
  PATH="$MOCK_BIN:$PATH" bash "$START_NOTIFIER" 2>/dev/null
)
if [ -f "$WORK_DIR/.beads/daemon_started" ]; then
  assert_success "Starts daemon when slack_config.yaml exists"
else
  assert_failure "Starts daemon when slack_config.yaml exists" "Daemon was not started"
fi
rm -rf "$WORK_DIR" "$MOCK_BIN"

# -----------------------------------------------------------
# Test 7: Detects SLACK_WEBHOOK_URL env var as valid config
# -----------------------------------------------------------
echo ""
echo "Test 7: Detects SLACK_WEBHOOK_URL env var as valid config"
WORK_DIR=$(mktemp -d)
MOCK_BIN=$(mktemp -d)
cat > "$MOCK_BIN/python3" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"--daemon"* ]]; then
  echo "DAEMON_STARTED" > "$WORK_DIR/.beads/daemon_started"
fi
exit 0
MOCK
chmod +x "$MOCK_BIN/python3"
(
  cd "$WORK_DIR"
  export WORK_DIR
  mkdir -p .beads
  # No config file, but env var is set
  export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST"
  PATH="$MOCK_BIN:$PATH" bash "$START_NOTIFIER" 2>/dev/null
)
if [ -f "$WORK_DIR/.beads/daemon_started" ]; then
  assert_success "Starts daemon when SLACK_WEBHOOK_URL is set"
else
  assert_failure "Starts daemon when SLACK_WEBHOOK_URL is set" "Daemon was not started"
fi
rm -rf "$WORK_DIR" "$MOCK_BIN"

# -----------------------------------------------------------
# Test 8: Detects .secrets/slack_webhook as valid config
# -----------------------------------------------------------
echo ""
echo "Test 8: Detects .secrets/slack_webhook as valid config"
WORK_DIR=$(mktemp -d)
MOCK_BIN=$(mktemp -d)
cat > "$MOCK_BIN/python3" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"--daemon"* ]]; then
  echo "DAEMON_STARTED" > "$WORK_DIR/.beads/daemon_started"
fi
exit 0
MOCK
chmod +x "$MOCK_BIN/python3"
(
  cd "$WORK_DIR"
  export WORK_DIR
  mkdir -p .beads .secrets
  echo "https://hooks.slack.com/services/TEST" > .secrets/slack_webhook
  unset SLACK_WEBHOOK_URL
  PATH="$MOCK_BIN:$PATH" bash "$START_NOTIFIER" 2>/dev/null
)
if [ -f "$WORK_DIR/.beads/daemon_started" ]; then
  assert_success "Starts daemon when .secrets/slack_webhook exists"
else
  assert_failure "Starts daemon when .secrets/slack_webhook exists" "Daemon was not started"
fi
rm -rf "$WORK_DIR" "$MOCK_BIN"

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
