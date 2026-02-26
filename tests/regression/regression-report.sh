#!/usr/bin/env bash
# US-010: Flip-Centered Regression Report
# Compares current vs baseline version results; outputs PASS/WARN/FAIL verdict
# Usage: bash tests/regression/regression-report.sh [--baseline <version>]
# Exit 0: PASS | Exit 1: FAIL or WARN | Exit 2: error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DB="${PLUGIN_ROOT}/tests/benchmark.db"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# Parse args
BASELINE_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) BASELINE_ARG="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ ! -f "$DB" ]; then
  echo "ERROR: ${DB} not found — run init-db.sh first" >&2
  exit 2
fi

if ! command -v sqlite3 > /dev/null 2>&1; then
  echo "ERROR: sqlite3 not found" >&2
  exit 2
fi

if ! command -v jq > /dev/null 2>&1; then
  echo "ERROR: jq not found" >&2
  exit 2
fi

# Get current version (latest in DB)
CURRENT=$(sqlite3 "$DB" "SELECT version FROM versions ORDER BY timestamp DESC LIMIT 1;" 2>/dev/null)
if [ -z "$CURRENT" ]; then
  echo "No data in database yet — run record-results.sh first."
  exit 0
fi

# Get baseline version
if [ -n "$BASELINE_ARG" ]; then
  BASELINE="$BASELINE_ARG"
else
  BASELINE=$(sqlite3 "$DB" \
    "SELECT version FROM versions WHERE version != '${CURRENT}' ORDER BY timestamp DESC LIMIT 1;" \
    2>/dev/null)
fi

echo "=== Regression Report: v${CURRENT} vs baseline ==="
if [ -z "$BASELINE" ]; then
  echo "  No baseline version available — first run, no comparison."
  echo ""

  # Just report current results
  struct_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM structural_results WHERE version='${CURRENT}';" 2>/dev/null)
  behav_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM behavioral_results WHERE version='${CURRENT}';" 2>/dev/null)
  echo "  Current v${CURRENT}: ${struct_count} structural, ${behav_count} behavioral results"

  jq -n \
    --arg current "$CURRENT" \
    --arg baseline "" \
    '{current_version: $current, baseline_version: $baseline,
      flips: {regressions: [], improvements: [], unchanged: []},
      verdict: "PASS", note: "First run — no baseline to compare"}'
  exit 0
fi

echo "  Comparing v${CURRENT} against baseline v${BASELINE}"
echo ""

# ─────────────────────────────────────────────
# Structural flips
# ─────────────────────────────────────────────
echo "Structural tests:"

struct_regressions=""
struct_improvements=""
struct_unchanged=""

# Query latest row per test per version for structural
struct_flips=$(sqlite3 "$DB" -separator '|' "
SELECT c.test_name, b.passed, c.passed
FROM (
  SELECT test_name, passed FROM structural_results
  WHERE version='${CURRENT}' AND rowid IN (
    SELECT MAX(rowid) FROM structural_results WHERE version='${CURRENT}' GROUP BY test_name
  )
) c
JOIN (
  SELECT test_name, passed FROM structural_results
  WHERE version='${BASELINE}' AND rowid IN (
    SELECT MAX(rowid) FROM structural_results WHERE version='${BASELINE}' GROUP BY test_name
  )
) b ON c.test_name = b.test_name
ORDER BY c.test_name;
" 2>/dev/null)

if [ -z "$struct_flips" ]; then
  echo "  (no structural data for both versions)"
else
  while IFS='|' read -r test_name was now; do
    [ -z "$test_name" ] && continue
    if [ "$was" = "1" ] && [ "$now" = "0" ]; then
      printf "  ${RED}↘ REGRESSION${RESET} structural/%s (was: pass → now: fail)\n" "$test_name"
      struct_regressions="${struct_regressions}|${test_name}"
    elif [ "$was" = "0" ] && [ "$now" = "1" ]; then
      printf "  ${GREEN}↗ improvement${RESET} structural/%s (was: fail → now: pass)\n" "$test_name"
      struct_improvements="${struct_improvements}|${test_name}"
    else
      struct_unchanged="${struct_unchanged}|${test_name}"
    fi
  done <<EOF
$struct_flips
EOF
fi

# ─────────────────────────────────────────────
# Behavioral flips
# ─────────────────────────────────────────────
echo ""
echo "Behavioral tests:"

behav_regressions=""
behav_improvements=""
behav_unchanged=""

behav_flips=$(sqlite3 "$DB" -separator '|' "
SELECT c.suite || '/' || c.test_name, b.passed, c.passed
FROM (
  SELECT suite, test_name, passed FROM behavioral_results
  WHERE version='${CURRENT}' AND rowid IN (
    SELECT MAX(rowid) FROM behavioral_results WHERE version='${CURRENT}' GROUP BY suite, test_name
  )
) c
JOIN (
  SELECT suite, test_name, passed FROM behavioral_results
  WHERE version='${BASELINE}' AND rowid IN (
    SELECT MAX(rowid) FROM behavioral_results WHERE version='${BASELINE}' GROUP BY suite, test_name
  )
) b ON c.suite || '/' || c.test_name = b.suite || '/' || b.test_name
ORDER BY c.suite, c.test_name;
" 2>/dev/null)

if [ -z "$behav_flips" ]; then
  echo "  (no behavioral data for both versions)"
else
  while IFS='|' read -r test_key was now; do
    [ -z "$test_key" ] && continue
    if [ "$was" -gt 0 ] 2>/dev/null && [ "$now" = "0" ]; then
      printf "  ${RED}↘ REGRESSION${RESET} %s (was: %s passing → now: 0)\n" "$test_key" "$was"
      behav_regressions="${behav_regressions}|${test_key}"
    elif [ "$was" = "0" ] && [ "$now" -gt 0 ] 2>/dev/null; then
      printf "  ${GREEN}↗ improvement${RESET} %s (was: 0 → now: %s passing)\n" "$test_key" "$now"
      behav_improvements="${behav_improvements}|${test_key}"
    else
      behav_unchanged="${behav_unchanged}|${test_key}"
    fi
  done <<EOF
$behav_flips
EOF
fi

# ─────────────────────────────────────────────
# Verdict computation
# ─────────────────────────────────────────────

# Count flips (strip leading | and count remaining)
count_items() {
  local list="$1"
  if [ -z "$list" ]; then echo 0; return; fi
  echo "$list" | tr '|' '\n' | grep -c . || echo 0
}

n_struct_reg=$(count_items "$struct_regressions")
n_struct_imp=$(count_items "$struct_improvements")
n_behav_reg=$(count_items "$behav_regressions")
n_behav_imp=$(count_items "$behav_improvements")
n_total_reg=$((n_struct_reg + n_behav_reg))
n_total_imp=$((n_struct_imp + n_behav_imp))
net=$((n_total_imp - n_total_reg))

VERDICT="PASS"
if [ "$n_struct_reg" -gt 0 ]; then
  VERDICT="FAIL"
elif [ "$n_behav_reg" -gt "$n_behav_imp" ]; then
  VERDICT="WARN"
fi

echo ""
echo "───────────────────────────────────────────"
if [ "$net" -ge 0 ]; then
  printf "  Net: ${GREEN}+${n_total_imp} improvements${RESET} / ${RED}-${n_total_reg} regressions${RESET}\n"
else
  printf "  Net: ${RED}+${n_total_imp} improvements / -${n_total_reg} regressions${RESET}\n"
fi

case "$VERDICT" in
  PASS) printf "  Verdict: ${GREEN}✓ PASS${RESET}\n" ;;
  WARN) printf "  Verdict: ${YELLOW}⚠ WARN${RESET} (behavioral net-negative)\n" ;;
  FAIL) printf "  Verdict: ${RED}✗ FAIL${RESET} (structural regression detected)\n" ;;
esac
echo ""

# Build JSON arrays from pipe-delimited strings
build_json_array() {
  local items="$1"
  if [ -z "$items" ]; then echo "[]"; return; fi
  echo "$items" | tr '|' '\n' | grep -v '^$' | jq -R . | jq -s .
}

struct_reg_arr=$(build_json_array "$struct_regressions")
struct_imp_arr=$(build_json_array "$struct_improvements")
struct_unch_arr=$(build_json_array "$struct_unchanged")
behav_reg_arr=$(build_json_array "$behav_regressions")
behav_imp_arr=$(build_json_array "$behav_improvements")

all_reg=$(echo "[$struct_reg_arr, $behav_reg_arr]" | jq 'add // []')
all_imp=$(echo "[$struct_imp_arr, $behav_imp_arr]" | jq 'add // []')

jq -n \
  --arg current "$CURRENT" \
  --arg baseline "$BASELINE" \
  --argjson regressions "$all_reg" \
  --argjson improvements "$all_imp" \
  --argjson struct_unch "$struct_unch_arr" \
  --arg verdict "$VERDICT" \
  '{
    current_version: $current,
    baseline_version: $baseline,
    flips: {
      regressions: $regressions,
      improvements: $improvements,
      unchanged: $struct_unch
    },
    verdict: $verdict
  }'

case "$VERDICT" in
  PASS) exit 0 ;;
  *)    exit 1 ;;
esac
