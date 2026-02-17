#!/bin/bash
# Validate devcontainer.metadata label on a built image
# Usage: ./tests/validate-metadata.sh <image:tag>
#
# This runs on the HOST (not inside the container) because
# devcontainer.metadata is a Docker image LABEL, not a file.

set -euo pipefail

IMAGE="${1:?Usage: $0 <image:tag>}"

FAILURES=0

pass() { echo "✓ PASS  $1"; }
fail()  { echo "✗ FAIL  $1"; FAILURES=$((FAILURES + 1)); }

echo "========================================="
echo "Validating devcontainer.metadata"
echo "Image: ${IMAGE}"
echo "========================================="
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
    exit 1
fi

pass "devcontainer.metadata label exists"

# Validate JSON is parseable — catches the trailing-comma bug at source
if ! echo "$METADATA" | jq empty 2>/dev/null; then
    fail "devcontainer.metadata is not valid JSON"
    echo ""
    echo "Raw label value:"
    echo "$METADATA"
    exit 1
fi

pass "JSON is valid"

# Validate it's an array with exactly 1 element (parent only)
ARRAY_LEN=$(echo "$METADATA" | jq 'length')
if [ "$ARRAY_LEN" -eq 1 ]; then
    pass "Array has 1 element (single metadata entry)"
else
    fail "Array expected 1 element, got ${ARRAY_LEN}"
fi

ENTRY='.[0]'

# remoteUser
REMOTE_USER=$(echo "$METADATA" | jq -r "${ENTRY}.remoteUser // empty")
if [ "$REMOTE_USER" = "vscode" ]; then
    pass "remoteUser = vscode"
else
    fail "remoteUser expected 'vscode', got '${REMOTE_USER}'"
fi

# containerEnv.CLAUDE_CONFIG_DIR
CLAUDE_DIR=$(echo "$METADATA" | jq -r "${ENTRY}.containerEnv.CLAUDE_CONFIG_DIR // empty")
if [ -n "$CLAUDE_DIR" ]; then
    pass "containerEnv.CLAUDE_CONFIG_DIR = ${CLAUDE_DIR}"
else
    fail "containerEnv.CLAUDE_CONFIG_DIR is missing"
fi

# mounts (>= 2)
MOUNTS_LEN=$(echo "$METADATA" | jq "${ENTRY}.mounts | length")
if [ "$MOUNTS_LEN" -ge 2 ]; then
    pass "mounts has ${MOUNTS_LEN} entries"
else
    fail "mounts expected >= 2 entries, got ${MOUNTS_LEN}"
fi

# extensions (>= 7)
EXT_LEN=$(echo "$METADATA" | jq "${ENTRY}.customizations.vscode.extensions | length")
if [ "$EXT_LEN" -ge 7 ]; then
    pass "extensions has ${EXT_LEN} entries (>= 7)"
else
    fail "extensions expected >= 7 entries, got ${EXT_LEN}"
fi

# postCreateCommand
POST_CMD=$(echo "$METADATA" | jq -r "${ENTRY}.postCreateCommand // empty")
if [ -n "$POST_CMD" ]; then
    pass "postCreateCommand is set"
else
    fail "postCreateCommand is missing"
fi

# Summary
echo ""
echo "========================================="
if [ $FAILURES -eq 0 ]; then
    echo "All metadata checks passed! ✓"
    echo "========================================="
    exit 0
else
    echo "${FAILURES} check(s) failed! ✗"
    echo "========================================="
    exit 1
fi
