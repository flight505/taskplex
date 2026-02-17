#!/bin/bash
# Integration smoke test for TaskPlex v2.0
# Tests the full flow with module sourcing and DB operations
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/taskplex-integration-$$"
PASSED=0
FAILED=0

assert_exists() {
  local desc="$1" path="$2"
  if [ -e "$path" ]; then
    echo "  PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $desc (file not found: $path)"
    FAILED=$((FAILED + 1))
  fi
}

assert_contains() {
  local desc="$1" expected="$2" file="$3"
  if grep -qF "$expected" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $desc (expected '$expected' in $file)"
    FAILED=$((FAILED + 1))
  fi
}

assert_gt() {
  local desc="$1" value="$2" threshold="$3"
  if [ "$value" -gt "$threshold" ]; then
    echo "  PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $desc (expected >$threshold, got $value)"
    FAILED=$((FAILED + 1))
  fi
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "=== TaskPlex v2.0 Integration Smoke Test ==="
echo ""

# Setup test project
mkdir -p "$TEST_DIR/.claude"
cd "$TEST_DIR"
git init > /dev/null 2>&1
git commit --allow-empty -m "init" > /dev/null 2>&1

# Test 1: Schema creation and migration
echo "Test 1: SQLite schema + migration"
source "$SCRIPT_DIR/scripts/knowledge-db.sh"
init_knowledge_db "$TEST_DIR/knowledge.db"
assert_exists "knowledge.db created" "$TEST_DIR/knowledge.db"

TABLE_COUNT=$(sqlite3 "$TEST_DIR/knowledge.db" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
assert_gt "Has 5 tables" "$TABLE_COUNT" 4

# Create and migrate knowledge.md
cat > "$TEST_DIR/knowledge.md" <<'EOF'
## Codebase Patterns

## Environment Notes

## Recent Learnings
- [US-001] Uses pnpm for deps
EOF
migrate_knowledge_md "$TEST_DIR/knowledge.db" "$TEST_DIR/knowledge.md"
MIGRATED=$(sqlite3 "$TEST_DIR/knowledge.db" "SELECT COUNT(*) FROM learnings WHERE source='migration';")
assert_gt "Migrated entries" "$MIGRATED" 0

# Test 2: Insert and query operations
echo "Test 2: CRUD operations"
insert_learning "$TEST_DIR/knowledge.db" "US-010" "run-1" "Test learning" '["test"]'
insert_error "$TEST_DIR/knowledge.db" "US-010" "run-1" "test_failure" "Jest failed" 1
insert_decision "$TEST_DIR/knowledge.db" "US-010" "run-1" "implement" "sonnet" "" "first attempt"
insert_run "$TEST_DIR/knowledge.db" "run-1" "test-branch" "sequential" "sonnet" 3

LEARNING_COUNT=$(sqlite3 "$TEST_DIR/knowledge.db" "SELECT COUNT(*) FROM learnings;")
assert_gt "Has learnings" "$LEARNING_COUNT" 1

ERROR_COUNT=$(sqlite3 "$TEST_DIR/knowledge.db" "SELECT COUNT(*) FROM error_history;")
assert_gt "Has errors" "$ERROR_COUNT" 0

DECISION_COUNT=$(sqlite3 "$TEST_DIR/knowledge.db" "SELECT COUNT(*) FROM decisions;")
assert_gt "Has decisions" "$DECISION_COUNT" 0

# Test 3: Hook scripts are executable
echo "Test 3: Hook scripts exist"
assert_exists "inject-knowledge.sh exists" "$SCRIPT_DIR/hooks/inject-knowledge.sh"
assert_exists "validate-result.sh exists" "$SCRIPT_DIR/hooks/validate-result.sh"

# Test 4: Hook scripts in hooks.json
echo "Test 4: hooks.json configuration"
assert_contains "SubagentStart hook registered" "inject-knowledge.sh" "$SCRIPT_DIR/hooks/hooks.json"
assert_contains "SubagentStop hook registered" "validate-result.sh" "$SCRIPT_DIR/hooks/hooks.json"

# Test 5: taskplex.sh parses without errors
echo "Test 5: Script syntax validation"
bash -n "$SCRIPT_DIR/scripts/taskplex.sh" 2>/dev/null
PARSE_EXIT=$?
if [ $PARSE_EXIT -eq 0 ]; then
  echo "  PASS: taskplex.sh parses cleanly"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: taskplex.sh has syntax errors"
  FAILED=$((FAILED + 1))
fi

bash -n "$SCRIPT_DIR/scripts/knowledge-db.sh" 2>/dev/null
KB_EXIT=$?
if [ $KB_EXIT -eq 0 ]; then
  echo "  PASS: knowledge-db.sh parses cleanly"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: knowledge-db.sh has syntax errors"
  FAILED=$((FAILED + 1))
fi

bash -n "$SCRIPT_DIR/scripts/decision-call.sh" 2>/dev/null
DC_EXIT=$?
if [ $DC_EXIT -eq 0 ]; then
  echo "  PASS: decision-call.sh parses cleanly"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: decision-call.sh has syntax errors"
  FAILED=$((FAILED + 1))
fi

# Test 6: New config fields have defaults
echo "Test 6: Config defaults in taskplex.sh"
assert_contains "decision_calls default" "DECISION_CALLS_ENABLED=true" "$SCRIPT_DIR/scripts/taskplex.sh"
assert_contains "knowledge_db default" 'KNOWLEDGE_DB_PATH="knowledge.db"' "$SCRIPT_DIR/scripts/taskplex.sh"
assert_contains "validate_on_stop default" "VALIDATE_ON_STOP=true" "$SCRIPT_DIR/scripts/taskplex.sh"
assert_contains "model_routing default" 'MODEL_ROUTING="auto"' "$SCRIPT_DIR/scripts/taskplex.sh"

# Test 7: Plugin manifest version
echo "Test 7: Plugin manifest"
PLUGIN_VERSION=$(jq -r '.version' "$SCRIPT_DIR/.claude-plugin/plugin.json")
if [ "$PLUGIN_VERSION" = "2.0.0" ]; then
  echo "  PASS: Plugin version is 2.0.0"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: Plugin version is $PLUGIN_VERSION (expected 2.0.0)"
  FAILED=$((FAILED + 1))
fi

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ $FAILED -eq 0 ] && exit 0 || exit 1
