#!/bin/bash
# Test decision-call.sh module (without live Claude calls)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/taskplex-test-decision-$$"
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

# Setup test environment
mkdir -p "$TEST_DIR/.claude"
cd "$TEST_DIR"

# Mock globals that taskplex.sh normally sets
PROJECT_DIR="$TEST_DIR"
PRD_FILE="$TEST_DIR/prd.json"
KNOWLEDGE_DB="$TEST_DIR/knowledge.db"
CONFIG_FILE="$TEST_DIR/.claude/taskplex.config.json"
EXECUTION_MODEL="sonnet"
EFFORT_LEVEL=""
RUN_ID="test-run"
TIMEOUT_CMD="timeout"
command -v gtimeout > /dev/null 2>&1 && TIMEOUT_CMD="gtimeout"

# Mock functions
log() { :; }
emit_event() { :; }

# Source dependencies
source "$SCRIPT_DIR/scripts/knowledge-db.sh"
init_knowledge_db "$KNOWLEDGE_DB"

source "$SCRIPT_DIR/scripts/decision-call.sh"

# Create prd.json
cat > "$PRD_FILE" <<'EOF'
{
  "branchName": "taskplex/test",
  "userStories": [
    {"id": "US-001", "title": "Simple", "status": "pending", "attempts": 0, "acceptanceCriteria": ["Works"], "priority": 1},
    {"id": "US-002", "title": "Failed", "status": "pending", "attempts": 2, "last_error": "TypeError", "last_error_category": "code_error", "acceptanceCriteria": ["A","B","C"], "priority": 2}
  ]
}
EOF

echo "=== Testing decision-call.sh ==="
echo ""

# Test 1: Disabled decision calls returns defaults
echo "Test 1: Disabled returns defaults"
DECISION_CALLS_ENABLED="false"
RESULT=$(decision_call "US-001")
assert_eq "Returns default model" "implement|sonnet|" "$RESULT"

# Test 2: Missing story returns defaults
echo "Test 2: Missing story returns defaults"
DECISION_CALLS_ENABLED="true"
RESULT=$(decision_call "US-999")
assert_eq "Returns defaults for missing story" "implement|sonnet|" "$RESULT"

# Note: Testing with live Claude calls would require mocking claude CLI.
# The above tests verify the fallback paths. Live decision calls are tested
# in the integration smoke test (Task 10).

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ $FAILED -eq 0 ] && exit 0 || exit 1
