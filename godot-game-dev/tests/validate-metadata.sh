#!/bin/bash
# Validate devcontainer.metadata label on a built image
# Usage: ./tests/validate-metadata.sh <image:tag>
#
# This runs on the HOST (not inside the container) because
# devcontainer.metadata is a Docker image LABEL, not a file.

set -euo pipefail

IMAGE="${1:?Usage: $0 <image:tag>}"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "${GREEN}✓${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo "Validating devcontainer.metadata for: ${IMAGE}"
echo ""

# Ensure image is available locally (pull if needed)
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Image not found locally, pulling..."
    docker pull "$IMAGE"
fi

# Extract the devcontainer.metadata label
METADATA=$(docker inspect --format '{{index .Config.Labels "devcontainer.metadata"}}' "$IMAGE")

if [ -z "$METADATA" ] || [ "$METADATA" = "<no value>" ]; then
    fail "devcontainer.metadata label is missing"
    echo ""
    echo -e "${RED}Failed: 1${NC}"
    exit 1
fi

pass "devcontainer.metadata label exists"

# Validate JSON is parseable
if ! echo "$METADATA" | jq empty 2>/dev/null; then
    fail "devcontainer.metadata is not valid JSON"
    echo ""
    echo "Raw label value:"
    echo "$METADATA"
    echo ""
    echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Failed: $((TESTS_FAILED + 1))${NC}"
    exit 1
fi

pass "JSON is valid"

# Core regression test: array must have >= 2 elements (parent + child)
ARRAY_LEN=$(echo "$METADATA" | jq 'length')

if [ "$ARRAY_LEN" -ge 2 ]; then
    pass "Array has ${ARRAY_LEN} elements (parent + child metadata preserved)"
else
    fail "Array has only ${ARRAY_LEN} element(s) — parent metadata was likely lost (trailing-comma bug?)"
fi

echo ""
echo "Parent metadata checks (index 0):"

# Parent: remoteUser
REMOTE_USER=$(echo "$METADATA" | jq -r '.[0].remoteUser // empty')
if [ "$REMOTE_USER" = "vscode" ]; then
    pass "remoteUser = vscode"
else
    fail "remoteUser expected 'vscode', got '${REMOTE_USER}'"
fi

# Parent: containerEnv.CLAUDE_CONFIG_DIR
CLAUDE_DIR=$(echo "$METADATA" | jq -r '.[0].containerEnv.CLAUDE_CONFIG_DIR // empty')
if [ -n "$CLAUDE_DIR" ]; then
    pass "containerEnv.CLAUDE_CONFIG_DIR = ${CLAUDE_DIR}"
else
    fail "containerEnv.CLAUDE_CONFIG_DIR is missing"
fi

# Parent: mounts (>= 2)
MOUNTS_LEN=$(echo "$METADATA" | jq '.[0].mounts | length')
if [ "$MOUNTS_LEN" -ge 2 ]; then
    pass "mounts has ${MOUNTS_LEN} entries"
else
    fail "mounts expected >= 2 entries, got ${MOUNTS_LEN}"
fi

# Parent: spot-check extensions
for ext in "Anthropic.claude-code" "ms-python.python"; do
    HAS_EXT=$(echo "$METADATA" | jq --arg e "$ext" '.[0].customizations.vscode.extensions | map(select(. == $e)) | length')
    if [ "$HAS_EXT" -ge 1 ]; then
        pass "parent extension ${ext} present"
    else
        fail "parent extension ${ext} missing"
    fi
done

echo ""
echo "Child metadata checks (index 1):"

# Child: geequlim.godot-tools
HAS_GODOT=$(echo "$METADATA" | jq '.[1].customizations.vscode.extensions | map(select(. == "geequlim.godot-tools")) | length')
if [ "$HAS_GODOT" -ge 1 ]; then
    pass "child extension geequlim.godot-tools present"
else
    fail "child extension geequlim.godot-tools missing"
fi

# Summary
echo ""
echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
if [ "$TESTS_FAILED" -gt 0 ]; then
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
    exit 1
else
    echo "All metadata checks passed!"
    exit 0
fi
