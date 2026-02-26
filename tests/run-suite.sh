#!/usr/bin/env bash
# TaskPlex Test Suite — thin wrapper
# Delegates to marketplace-level test suite when available (test-results/taskplex/run-tests.sh)
# Falls back to basic structural checks when running standalone
# Usage: bash tests/run-suite.sh [--ci]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MARKETPLACE_SUITE="$(cd "${PLUGIN_ROOT}/.." 2>/dev/null && pwd)/test-results/taskplex/run-tests.sh"

CI_FLAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ci) CI_FLAG="--ci"; shift ;;
    *)    shift ;;
  esac
done

# Prefer marketplace-level suite if available
if [ -f "$MARKETPLACE_SUITE" ]; then
  exec bash "$MARKETPLACE_SUITE" $CI_FLAG
fi

# Fallback: basic structural checks (for standalone repo / CI)
echo "TaskPlex Standalone Checks"
PASS=0; FAIL=0

check() {
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $1 ${*:2}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $1 ${*:2}"
    FAIL=$((FAIL + 1))
  fi
}

# JSON validity
check jq empty "$PLUGIN_ROOT/.claude-plugin/plugin.json"
check jq empty "$PLUGIN_ROOT/hooks/hooks.json"

# Shell syntax
for f in "$PLUGIN_ROOT"/scripts/*.sh "$PLUGIN_ROOT"/hooks/*.sh; do
  [ -f "$f" ] || continue
  check bash -n "$f"
done

# Knowledge-db functional tests
source "$PLUGIN_ROOT/scripts/knowledge-db.sh"
TEST_DB="/tmp/taskplex-fallback-test-$$.db"
init_knowledge_db "$TEST_DB"
TABLE_COUNT=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
if [ "$TABLE_COUNT" -eq 6 ]; then echo "  PASS: knowledge-db creates 6 tables"; PASS=$((PASS + 1)); else echo "  FAIL: expected 6 tables, got $TABLE_COUNT"; FAIL=$((FAIL + 1)); fi
rm -f "$TEST_DB"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
