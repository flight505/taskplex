#!/bin/bash
# Test validate-result.sh hook
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/taskplex-test-validate-$$"
PASSED=0
FAILED=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $desc (expected: $expected, actual: $actual)"
    FAILED=$((FAILED + 1))
  fi
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Setup test project
mkdir -p "$TEST_DIR/.claude"
cd "$TEST_DIR"

echo "=== Testing validate-result.sh ==="
echo ""

# Test 1: stop_hook_active=true exits cleanly
echo "Test 1: Prevents infinite loops"
EXIT_CODE=0
echo '{"agent_type":"implementer","stop_hook_active":true}' | bash "$SCRIPT_DIR/hooks/validate-result.sh" > /dev/null 2>&1 || EXIT_CODE=$?
assert_eq "stop_hook_active=true exits 0" "0" "$EXIT_CODE"

# Test 2: Non-implementer exits cleanly
echo "Test 2: Non-implementer passthrough"
EXIT_CODE=0
echo '{"agent_type":"validator","stop_hook_active":false}' | bash "$SCRIPT_DIR/hooks/validate-result.sh" > /dev/null 2>&1 || EXIT_CODE=$?
assert_eq "validator agent exits 0" "0" "$EXIT_CODE"

# Test 3: No config = no validation = exit 0
echo "Test 3: No config passthrough"
EXIT_CODE=0
echo '{"agent_type":"implementer","stop_hook_active":false}' | bash "$SCRIPT_DIR/hooks/validate-result.sh" > /dev/null 2>&1 || EXIT_CODE=$?
assert_eq "No config exits 0" "0" "$EXIT_CODE"

# Test 4: Passing validation
echo "Test 4: Passing validation"
cat > "$TEST_DIR/.claude/taskplex.config.json" <<'EOF'
{
  "typecheck_command": "echo 'all good'",
  "validate_on_stop": true
}
EOF
EXIT_CODE=0
echo '{"agent_type":"implementer","stop_hook_active":false}' | bash "$SCRIPT_DIR/hooks/validate-result.sh" > /dev/null 2>&1 || EXIT_CODE=$?
assert_eq "Passing typecheck exits 0" "0" "$EXIT_CODE"

# Test 5: Failing validation blocks agent
echo "Test 5: Failing validation"
cat > "$TEST_DIR/.claude/taskplex.config.json" <<'EOF'
{
  "typecheck_command": "echo 'error TS2345: type mismatch' >&2; exit 1",
  "validate_on_stop": true
}
EOF
EXIT_CODE=0
RESULT=$(echo '{"agent_type":"implementer","stop_hook_active":false}' | bash "$SCRIPT_DIR/hooks/validate-result.sh" 2>/dev/null) || EXIT_CODE=$?
assert_eq "Failing typecheck exits 2" "2" "$EXIT_CODE"

# Check that output contains block decision
DECISION=$(echo "$RESULT" | jq -r '.decision // empty' 2>/dev/null)
assert_eq "Output has decision:block" "block" "$DECISION"

# Test 6: validate_on_stop=false disables
echo "Test 6: Disabled validation"
cat > "$TEST_DIR/.claude/taskplex.config.json" <<'EOF'
{
  "typecheck_command": "exit 1",
  "validate_on_stop": false
}
EOF
EXIT_CODE=0
echo '{"agent_type":"implementer","stop_hook_active":false}' | bash "$SCRIPT_DIR/hooks/validate-result.sh" > /dev/null 2>&1 || EXIT_CODE=$?
assert_eq "validate_on_stop=false exits 0" "0" "$EXIT_CODE"

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ $FAILED -eq 0 ] && exit 0 || exit 1
