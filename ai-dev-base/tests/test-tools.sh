#!/bin/bash
set -e

echo "========================================="
echo "Testing ai-dev-base Image Tools"
echo "========================================="
echo ""

# Track failures
FAILURES=0

# Test function
test_command() {
    local name="$1"
    local command="$2"
    local expected_pattern="$3"

    echo -n "Testing $name... "

    if output=$(eval "$command" 2>&1); then
        if [ -n "$expected_pattern" ]; then
            if echo "$output" | grep -iq "$expected_pattern"; then
                echo "✓ PASS"
                return 0
            else
                echo "✗ FAIL (unexpected output)"
                echo "  Expected pattern: $expected_pattern"
                echo "  Got: $output"
                FAILURES=$((FAILURES + 1))
                return 1
            fi
        else
            echo "✓ PASS"
            return 0
        fi
    else
        echo "✗ FAIL (command failed)"
        echo "  Output: $output"
        FAILURES=$((FAILURES + 1))
        return 1
    fi
}

# Test GitHub CLI
test_command "GitHub CLI (gh)" "gh --version" "gh version"

# Test Docker CLI
test_command "Docker CLI" "docker --version" "Docker version"

# Test Docker Compose plugin
test_command "Docker Compose" "docker compose version" "Docker Compose"

# Test Doppler CLI
test_command "Doppler CLI" "doppler --version" "v[0-9]"

# Test Claude CLI
test_command "Claude CLI" "claude --version" "claude"

# Test Beads
test_command "Beads (bd)" "bd --version" "bd version"

# Test uv
test_command "uv" "uv --version" "uv"

# Test bun
test_command "Bun" "bun --version" "[0-9]"

# Test Gastown
test_command "Gastown (gt)" "gt --version" "gt version"

# Test tmux
test_command "tmux" "tmux -V" "tmux"

# Test OpenAI Codex CLI
test_command "OpenAI Codex CLI" "codex --version || which codex" ""

# Test Wrangler CLI (outputs version number only, e.g., "4.63.0")
test_command "Wrangler CLI" "wrangler --version" "[0-9]"

# Test Python and ai-coding-utils modules
echo -n "Testing ai-coding-utils modules... "
if python3 -c "import slack; import beads" 2>/dev/null; then
    echo "✓ PASS"
else
    echo "✗ FAIL (modules not importable)"
    FAILURES=$((FAILURES + 1))
fi

# Test dev-infra components
echo -n "Testing dev-infra components... "
if [ -f /opt/dev-infra/credential_cache.sh ] && \
   [ -f /opt/dev-infra/directories.sh ] && \
   [ -f /opt/dev-infra/python_venv.sh ] && \
   [ -f /opt/dev-infra/git_hooks.sh ] && \
   [ -f /opt/dev-infra/setup/project_setup.sh ] && \
   [ -f /opt/dev-infra/secrets/manager.py ]; then
    echo "✓ PASS"
else
    echo "✗ FAIL (missing components)"
    FAILURES=$((FAILURES + 1))
fi

# Test auto-source script
echo -n "Testing auto-source script... "
if [ -f /etc/profile.d/ai-dev-utils.sh ]; then
    if bash -n /etc/profile.d/ai-dev-utils.sh 2>/dev/null; then
        echo "✓ PASS"
    else
        echo "✗ FAIL (syntax error)"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo "✗ FAIL (file missing)"
    FAILURES=$((FAILURES + 1))
fi

# Test PYTHONPATH
echo -n "Testing PYTHONPATH... "
if echo "$PYTHONPATH" | grep -q "/opt/ai-coding-utils"; then
    echo "✓ PASS"
else
    echo "✗ FAIL (PYTHONPATH not set correctly)"
    FAILURES=$((FAILURES + 1))
fi

# Summary
echo ""
echo "========================================="
if [ $FAILURES -eq 0 ]; then
    echo "All tests passed! ✓"
    echo "========================================="
    exit 0
else
    echo "$FAILURES test(s) failed! ✗"
    echo "========================================="
    exit 1
fi
