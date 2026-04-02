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

# Test Gas City
test_command "Gas City (gc)" "gc version" "gc version"

# Test Dolt
test_command "Dolt" "dolt version" "[0-9]"

# Test tmux
test_command "tmux" "tmux -V" "tmux"

# Test OpenAI Codex CLI
test_command "OpenAI Codex CLI" "codex --version || which codex" ""

# Test Wrangler CLI (outputs version number only, e.g., "4.63.0")
test_command "Wrangler CLI" "wrangler --version" "[0-9]"

# Test PostgreSQL client
test_command "PostgreSQL client (psql)" "psql --version" "psql"

# Test Playwright/Chromium system dependencies
test_command "Playwright deps (libglib2.0-0)" "dpkg -s libglib2.0-0" "Status: install ok installed"

# Test Python and ai-coding-utils modules
echo -n "Testing ai-coding-utils modules... "
if python3 -c "import slack; import beads" 2>/dev/null; then
    echo "✓ PASS"
else
    echo "✗ FAIL (modules not importable)"
    FAILURES=$((FAILURES + 1))
fi

# Test CLI wrappers (existence and syntax only — no live API calls)
test_command "CLI wrapper (dop)" "which dop && bash -n /opt/dev-infra/cli/dop.sh" ""
test_command "CLI wrapper (supa-query)" "which supa-query && bash -n /opt/dev-infra/cli/supa-query.sh" ""
test_command "CLI wrapper (dagster-cloud)" "which dagster-cloud && bash -n /opt/dev-infra/cli/dagster-cloud.sh" ""
test_command "CLI wrapper (dbx)" "which dbx && bash -n /opt/dev-infra/cli/dbx.sh" ""
test_command "CLI wrapper (cf)" "which cf && bash -n /opt/dev-infra/cli/cf.sh" ""
test_command "CLI wrapper (cf-r2)" "which cf-r2 && bash -n /opt/dev-infra/cli/cf-r2.sh" ""
test_command "CLI wrapper (kafka-rest)" "which kafka-rest && bash -n /opt/dev-infra/cli/kafka-rest.sh" ""
test_command "CLI wrapper (gmail)" "which gmail && bash -n /opt/dev-infra/cli/gmail.sh" ""

# Test dev-services command
echo -n "Testing dev-services command... "
if [ -x /usr/local/bin/dev-services ] && dev-services --help >/dev/null 2>&1; then
    echo "✓ PASS"
else
    echo "✗ FAIL (dev-services not available)"
    FAILURES=$((FAILURES + 1))
fi

# Test dev-infra components
echo -n "Testing dev-infra components... "
if [ -f /opt/dev-infra/credential_cache.sh ] && \
   [ -f /opt/dev-infra/directories.sh ] && \
   [ -f /opt/dev-infra/python_venv.sh ] && \
   [ -f /opt/dev-infra/env_hydrate.sh ] && \
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

# --- Permissions tests ---
echo ""
echo "========================================="
echo "Testing Permissions"
echo "========================================="
echo ""

# Test /workspaces exists and is accessible
echo -n "Testing /workspaces exists... "
if [ -d /workspaces ]; then
    echo "✓ PASS"
else
    echo "✗ FAIL (/workspaces does not exist)"
    FAILURES=$((FAILURES + 1))
fi

# Test vscode can create directories in /workspaces
# Note: on bind mounts, /workspaces may be root-owned; we test writeability not ownership
echo -n "Testing vscode write access to /workspaces... "
TEST_DIR="/workspaces/.permissions-test-$$"
if [ "$(whoami)" = "vscode" ]; then
    if mkdir -p "$TEST_DIR" 2>/dev/null && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
        echo "✓ PASS"
    else
        echo "✗ FAIL (vscode cannot create directories in /workspaces)"
        FAILURES=$((FAILURES + 1))
    fi
else
    # Running as root — verify by switching to vscode
    if su -c "mkdir -p $TEST_DIR" vscode 2>/dev/null && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
        echo "✓ PASS"
    else
        echo "✗ FAIL (vscode cannot create directories in /workspaces)"
        FAILURES=$((FAILURES + 1))
    fi
fi

# Test /home/vscode/.claude ownership
echo -n "Testing /home/vscode/.claude ownership... "
if [ -d /home/vscode/.claude ]; then
    CLAUDE_OWNER=$(stat -c '%U:%G' /home/vscode/.claude)
    if [ "$CLAUDE_OWNER" = "vscode:vscode" ]; then
        echo "✓ PASS"
    else
        echo "✗ FAIL (owned by $CLAUDE_OWNER, expected vscode:vscode)"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo "✗ FAIL (/home/vscode/.claude does not exist)"
    FAILURES=$((FAILURES + 1))
fi

# Test /home/vscode/.claude permissions (should be 700)
echo -n "Testing /home/vscode/.claude permissions... "
if [ -d /home/vscode/.claude ]; then
    CLAUDE_PERMS=$(stat -c '%a' /home/vscode/.claude)
    if [ "$CLAUDE_PERMS" = "700" ]; then
        echo "✓ PASS"
    else
        echo "✗ FAIL (permissions $CLAUDE_PERMS, expected 700)"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo "- SKIP (directory missing)"
fi

# Test git safe.directory is configured
echo -n "Testing git safe.directory... "
if git config --system --get-all safe.directory 2>/dev/null | grep -q '\*'; then
    echo "✓ PASS"
else
    echo "✗ FAIL (git safe.directory='*' not set in system config)"
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
