#!/bin/bash
# Test script for knowledge-db.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/knowledge-db.sh"

TEST_DB="/tmp/taskplex-test-$$.db"
PASSED=0
FAILED=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAILED=$((FAILED + 1))
  fi
}

cleanup() {
  rm -f "$TEST_DB"
}
trap cleanup EXIT

echo "=== Testing knowledge-db.sh ==="
echo ""

# Test 1: init_knowledge_db creates tables
echo "Test 1: Schema creation"
init_knowledge_db "$TEST_DB"
TABLE_COUNT=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
assert_eq "Creates 5 tables" "5" "$TABLE_COUNT"

# Test 2: insert_learning + query_learnings
echo "Test 2: Insert and query learnings"
insert_learning "$TEST_DB" "US-001" "run-1" "Project uses barrel exports in src/index.ts" '["src/index.ts"]'
insert_learning "$TEST_DB" "US-002" "run-1" "Badge component accepts variant prop" '["src/components"]'
LEARNING_COUNT=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM learnings;")
assert_eq "Inserted 2 learnings" "2" "$LEARNING_COUNT"

QUERY_RESULT=$(query_learnings "$TEST_DB" 10)
RESULT_LINES=$(echo "$QUERY_RESULT" | wc -l | tr -d ' ')
assert_eq "Query returns 2 results" "2" "$RESULT_LINES"

# Test 3: insert_error + query_errors
echo "Test 3: Error history"
insert_error "$TEST_DB" "US-003" "run-1" "test_failure" "Jest: 2 tests failed" 1
insert_error "$TEST_DB" "US-003" "run-1" "code_error" "TypeError: undefined" 2
ERRORS=$(query_errors "$TEST_DB" "US-003")
ERROR_LINES=$(echo "$ERRORS" | wc -l | tr -d ' ')
assert_eq "Query returns 2 errors" "2" "$ERROR_LINES"

# Test 4: resolve_errors
echo "Test 4: Resolve errors"
resolve_errors "$TEST_DB" "US-003"
RESOLVED=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM error_history WHERE story_id='US-003' AND resolved=1;")
assert_eq "Both errors resolved" "2" "$RESOLVED"

# Test 5: insert_decision + query_decisions
echo "Test 5: Decisions"
insert_decision "$TEST_DB" "US-001" "run-1" "implement" "sonnet" "" "First attempt, standard story"
DECISIONS=$(query_decisions "$TEST_DB" "US-001")
assert_eq "Decision recorded" "implement|sonnet||First attempt, standard story" "$DECISIONS"

# Test 6: Run lifecycle
echo "Test 6: Run lifecycle"
insert_run "$TEST_DB" "run-1" "taskplex/feature-x" "sequential" "sonnet" 5
update_run "$TEST_DB" "run-1" 4 1
RUN_COMPLETED=$(sqlite3 "$TEST_DB" "SELECT completed FROM runs WHERE id='run-1';")
assert_eq "Run completed count" "4" "$RUN_COMPLETED"

# Test 7: migrate_knowledge_md
echo "Test 7: Knowledge.md migration"
TEST_MD="/tmp/taskplex-test-knowledge-$$.md"
cat > "$TEST_MD" <<'EOF'
## Codebase Patterns

## Environment Notes

## Recent Learnings
- [US-010] This project uses pnpm for package management
- [US-011] Config files are in src/config/
EOF
TEST_DB2="/tmp/taskplex-test-migrate-$$.db"
init_knowledge_db "$TEST_DB2"
migrate_knowledge_md "$TEST_DB2" "$TEST_MD"
MIGRATED=$(sqlite3 "$TEST_DB2" "SELECT COUNT(*) FROM learnings WHERE source='migration';")
assert_eq "Migrated 2 entries" "2" "$MIGRATED"

# Idempotency check
migrate_knowledge_md "$TEST_DB2" "$TEST_MD"
MIGRATED2=$(sqlite3 "$TEST_DB2" "SELECT COUNT(*) FROM learnings WHERE source='migration';")
assert_eq "Migration is idempotent" "2" "$MIGRATED2"

rm -f "$TEST_DB2" "$TEST_MD"

# Test 8: SQL injection safety (single quotes in content)
echo "Test 8: SQL injection safety"
insert_learning "$TEST_DB" "US-099" "run-1" "Don't use single 'quotes' in SQL" '[]'
SAFE_COUNT=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM learnings WHERE story_id='US-099';")
assert_eq "Handles single quotes safely" "1" "$SAFE_COUNT"

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ $FAILED -eq 0 ] && exit 0 || exit 1
