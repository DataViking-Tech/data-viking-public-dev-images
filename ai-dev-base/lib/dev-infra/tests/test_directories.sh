#!/bin/bash
# Tests for directories.sh - create_directories_from_file()
# Runs in temp directories to avoid side effects.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../components/directories.sh"

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
  local details="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "  FAIL: $test_name"
  if [ -n "$details" ]; then
    echo "  $details"
  fi
}

echo "========================================"
echo "Testing directories.sh"
echo "========================================"

# -----------------------------------------------------------
# Test 1: Creates directories from config file
# -----------------------------------------------------------
echo ""
echo "Test 1: Creates directories from config file"
WORK_DIR=$(mktemp -d)
printf '.secrets\nlogs\noutputs\n' > "$WORK_DIR/directory_config.txt"
(cd "$WORK_DIR" && create_directories_from_file "$WORK_DIR" "$WORK_DIR/directory_config.txt") > /dev/null

PASS=true
for d in .secrets logs outputs; do
  if [ ! -d "$WORK_DIR/$d" ]; then
    PASS=false
    break
  fi
done
if $PASS; then
  assert_success "Creates all directories from config file"
else
  assert_failure "Creates all directories from config file" \
    "Missing directories in $WORK_DIR"
fi
rm -rf "$WORK_DIR"

# -----------------------------------------------------------
# Test 2: Adds directories to .gitignore with section header
# -----------------------------------------------------------
echo ""
echo "Test 2: Adds directories to .gitignore with section header"
WORK_DIR=$(mktemp -d)
printf '.secrets\nlogs\noutputs\n' > "$WORK_DIR/directory_config.txt"
(cd "$WORK_DIR" && create_directories_from_file "$WORK_DIR" "$WORK_DIR/directory_config.txt") > /dev/null

PASS=true
if [ ! -f "$WORK_DIR/.gitignore" ]; then
  PASS=false
elif ! grep -qxF "# Project directories (added by dev-infra)" "$WORK_DIR/.gitignore" 2>/dev/null; then
  PASS=false
elif ! grep -qx '.secrets/' "$WORK_DIR/.gitignore" 2>/dev/null; then
  PASS=false
elif ! grep -qx 'logs/' "$WORK_DIR/.gitignore" 2>/dev/null; then
  PASS=false
elif ! grep -qx 'outputs/' "$WORK_DIR/.gitignore" 2>/dev/null; then
  PASS=false
fi
if $PASS; then
  assert_success "Creates .gitignore with section header and directory entries"
else
  assert_failure "Creates .gitignore with section header and directory entries" \
    "Contents: $(cat "$WORK_DIR/.gitignore" 2>/dev/null || echo 'file missing')"
fi
rm -rf "$WORK_DIR"

# -----------------------------------------------------------
# Test 3: Does not duplicate entries on second run
# -----------------------------------------------------------
echo ""
echo "Test 3: Does not duplicate entries on second run"
WORK_DIR=$(mktemp -d)
printf '.secrets\nlogs\n' > "$WORK_DIR/directory_config.txt"
(cd "$WORK_DIR" && create_directories_from_file "$WORK_DIR" "$WORK_DIR/directory_config.txt") > /dev/null
(cd "$WORK_DIR" && create_directories_from_file "$WORK_DIR" "$WORK_DIR/directory_config.txt") > /dev/null

SECRETS_COUNT=$(grep -cx '.secrets/' "$WORK_DIR/.gitignore" 2>/dev/null || echo 0)
LOGS_COUNT=$(grep -cx 'logs/' "$WORK_DIR/.gitignore" 2>/dev/null || echo 0)
HEADER_COUNT=$(grep -cxF "# Project directories (added by dev-infra)" "$WORK_DIR/.gitignore" 2>/dev/null || echo 0)
if [ "$SECRETS_COUNT" -eq 1 ] && [ "$LOGS_COUNT" -eq 1 ] && [ "$HEADER_COUNT" -eq 1 ]; then
  assert_success "Does not duplicate entries or header on second run"
else
  assert_failure "Does not duplicate entries or header on second run" \
    ".secrets/ count: $SECRETS_COUNT, logs/ count: $LOGS_COUNT, header count: $HEADER_COUNT"
fi
rm -rf "$WORK_DIR"

# -----------------------------------------------------------
# Test 4: Preserves existing .gitignore content
# -----------------------------------------------------------
echo ""
echo "Test 4: Preserves existing .gitignore content"
WORK_DIR=$(mktemp -d)
printf 'node_modules/\n*.log\n' > "$WORK_DIR/.gitignore"
printf '.secrets\nlogs\n' > "$WORK_DIR/directory_config.txt"
(cd "$WORK_DIR" && create_directories_from_file "$WORK_DIR" "$WORK_DIR/directory_config.txt") > /dev/null

PASS=true
if ! grep -qx 'node_modules/' "$WORK_DIR/.gitignore" 2>/dev/null; then
  PASS=false
fi
if ! grep -qx '\*.log' "$WORK_DIR/.gitignore" 2>/dev/null; then
  PASS=false
fi
if ! grep -qx '.secrets/' "$WORK_DIR/.gitignore" 2>/dev/null; then
  PASS=false
fi
if $PASS; then
  assert_success "Preserves existing .gitignore content while adding new entries"
else
  assert_failure "Preserves existing .gitignore content while adding new entries" \
    "Contents: $(cat "$WORK_DIR/.gitignore")"
fi
rm -rf "$WORK_DIR"

# -----------------------------------------------------------
# Test 5: Skips entries already in .gitignore
# -----------------------------------------------------------
echo ""
echo "Test 5: Skips entries already in .gitignore"
WORK_DIR=$(mktemp -d)
printf 'logs/\n' > "$WORK_DIR/.gitignore"
printf '.secrets\nlogs\n' > "$WORK_DIR/directory_config.txt"
(cd "$WORK_DIR" && create_directories_from_file "$WORK_DIR" "$WORK_DIR/directory_config.txt") > /dev/null

LOGS_COUNT=$(grep -cx 'logs/' "$WORK_DIR/.gitignore" 2>/dev/null || echo 0)
if [ "$LOGS_COUNT" -eq 1 ] && grep -qx '.secrets/' "$WORK_DIR/.gitignore" 2>/dev/null; then
  assert_success "Skips entries already present in .gitignore"
else
  assert_failure "Skips entries already present in .gitignore" \
    "logs/ count: $LOGS_COUNT, Contents: $(cat "$WORK_DIR/.gitignore")"
fi
rm -rf "$WORK_DIR"

# -----------------------------------------------------------
# Test 6: Handles empty lines in config file
# -----------------------------------------------------------
echo ""
echo "Test 6: Handles empty lines in config file"
WORK_DIR=$(mktemp -d)
printf '\n.secrets\n\nlogs\n\n' > "$WORK_DIR/directory_config.txt"
(cd "$WORK_DIR" && create_directories_from_file "$WORK_DIR" "$WORK_DIR/directory_config.txt") > /dev/null

PASS=true
if [ ! -d "$WORK_DIR/.secrets" ] || [ ! -d "$WORK_DIR/logs" ]; then
  PASS=false
fi
if ! grep -qx '.secrets/' "$WORK_DIR/.gitignore" 2>/dev/null; then
  PASS=false
fi
if ! grep -qx 'logs/' "$WORK_DIR/.gitignore" 2>/dev/null; then
  PASS=false
fi
if $PASS; then
  assert_success "Handles empty lines in config file correctly"
else
  assert_failure "Handles empty lines in config file correctly" \
    "Contents: $(cat "$WORK_DIR/.gitignore" 2>/dev/null || echo 'missing')"
fi
rm -rf "$WORK_DIR"

# -----------------------------------------------------------
# Test 7: Adds blank line separator before section header
# -----------------------------------------------------------
echo ""
echo "Test 7: Adds blank line separator before section header"
WORK_DIR=$(mktemp -d)
printf 'node_modules/' > "$WORK_DIR/.gitignore"  # No trailing newline
printf '.secrets\n' > "$WORK_DIR/directory_config.txt"
(cd "$WORK_DIR" && create_directories_from_file "$WORK_DIR" "$WORK_DIR/directory_config.txt") > /dev/null

# The section header should not be on the same line as existing content
if grep -qxF "# Project directories (added by dev-infra)" "$WORK_DIR/.gitignore" 2>/dev/null; then
  assert_success "Adds blank line separator before section header"
else
  assert_failure "Adds blank line separator before section header" \
    "Contents: $(cat "$WORK_DIR/.gitignore")"
fi
rm -rf "$WORK_DIR"

# -----------------------------------------------------------
# Test 8: No .gitignore modification when all entries exist
# -----------------------------------------------------------
echo ""
echo "Test 8: No .gitignore modification when all entries already exist"
WORK_DIR=$(mktemp -d)
printf '# Project directories (added by dev-infra)\n.secrets/\nlogs/\n' > "$WORK_DIR/.gitignore"
printf '.secrets\nlogs\n' > "$WORK_DIR/directory_config.txt"
BEFORE=$(cat "$WORK_DIR/.gitignore")
(cd "$WORK_DIR" && create_directories_from_file "$WORK_DIR" "$WORK_DIR/directory_config.txt") > /dev/null
AFTER=$(cat "$WORK_DIR/.gitignore")

if [ "$BEFORE" = "$AFTER" ]; then
  assert_success "No .gitignore modification when all entries already exist"
else
  assert_failure "No .gitignore modification when all entries already exist" \
    "File was modified. Before: $BEFORE, After: $AFTER"
fi
rm -rf "$WORK_DIR"

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
