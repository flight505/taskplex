#!/bin/bash
# Test inject-knowledge.sh hook
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/taskplex-test-hook-$$"
PASSED=0
FAILED=0

assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -qF "$expected"; then
    echo "  PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $desc (expected to contain: $expected)"
    FAILED=$((FAILED + 1))
  fi
}

assert_valid_json() {
  local desc="$1" json="$2"
  if echo "$json" | jq empty 2>/dev/null; then
    echo "  PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $desc (invalid JSON)"
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

# Create minimal prd.json
cat > "$TEST_DIR/prd.json" <<'EOF'
{
  "branchName": "taskplex/test",
  "userStories": [
    {
      "id": "US-001",
      "title": "Test Story",
      "status": "in_progress",
      "attempts": 1,
      "acceptanceCriteria": ["It works"],
      "check_before_implementing": ["echo 'check output here'"],
      "depends_on": [],
      "related_to": ["src/api"]
    }
  ]
}
EOF

# Create knowledge DB with test data
source "$SCRIPT_DIR/scripts/knowledge-db.sh"
init_knowledge_db "$TEST_DIR/knowledge.db"
insert_learning "$TEST_DIR/knowledge.db" "US-000" "run-0" "Project uses TypeScript" '["src/api"]'

# Initialize git for dependency diff tests
git init "$TEST_DIR" > /dev/null 2>&1
git -C "$TEST_DIR" add -A > /dev/null 2>&1
git -C "$TEST_DIR" commit -m "init" > /dev/null 2>&1

echo "=== Testing inject-knowledge.sh ==="
echo ""

# Test 1: Hook produces valid JSON
echo "Test 1: Valid JSON output"
RESULT=$(echo '{"agent_id":"test-1","agent_type":"implementer"}' | bash "$SCRIPT_DIR/hooks/inject-knowledge.sh")
assert_valid_json "Output is valid JSON" "$RESULT"

# Test 2: Output contains additionalContext
echo "Test 2: Contains additionalContext"
HAS_CONTEXT=$(echo "$RESULT" | jq -r '.hookSpecificOutput.additionalContext // empty')
assert_contains "Has context" "Context Brief for US-001" "$HAS_CONTEXT"

# Test 3: Context includes pre-implementation checks
echo "Test 3: Pre-implementation check results"
assert_contains "Has check output" "check output here" "$HAS_CONTEXT"

# Test 4: Context includes learnings
echo "Test 4: Knowledge injection"
assert_contains "Has learning" "Project uses TypeScript" "$HAS_CONTEXT"

# Test 5: No PRD = empty output
echo "Test 5: No PRD graceful fallback"
TEMP_PRD="$TEST_DIR/prd.json"
mv "$TEMP_PRD" "${TEMP_PRD}.bak"
EMPTY_RESULT=$(echo '{"agent_type":"implementer"}' | bash "$SCRIPT_DIR/hooks/inject-knowledge.sh")
assert_valid_json "Empty output is valid JSON" "$EMPTY_RESULT"
mv "${TEMP_PRD}.bak" "$TEMP_PRD"

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ $FAILED -eq 0 ] && exit 0 || exit 1
