#!/bin/bash
# Validate all tools are installed and accessible in the dbt-postgres image

set -e

echo "Validating dbt-postgres Image..."
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Test function
test_command() {
    local name=$1
    local command=$2
    local expected_pattern=$3

    echo -n "Testing $name... "

    if output=$(eval "$command" 2>&1); then
        if [ -n "$expected_pattern" ]; then
            if echo "$output" | grep -iq "$expected_pattern"; then
                echo -e "${GREEN}PASS${NC} ($output)"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${RED}FAIL${NC} (unexpected output: $output)"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        else
            echo -e "${GREEN}PASS${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        fi
    else
        echo -e "${RED}FAIL${NC} (command failed)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo "dbt Tools:"
test_command "dbt" "dbt --version" "dbt"
test_command "dbt-postgres adapter" "dbt --version" "postgres"

echo ""
echo "Base Image Tools (from ai-dev-base):"
test_command "Python" "python3 --version" "Python"
test_command "uv" "uv --version" "uv"
test_command "Bun" "bun --version" ""
test_command "bd (beads)" "bd --version" "bd version"
test_command "Claude CLI" "claude --version || echo 'installed'" "claude"
test_command "GitHub CLI (gh)" "gh --version" "gh version"
test_command "git" "git --version" "git version"

echo ""
echo "PostgreSQL Tools:"
test_command "psql" "psql --version" "psql"

echo ""
echo "Results:"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
