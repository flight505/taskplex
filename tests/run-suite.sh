#!/usr/bin/env bash
# US-011: Test Orchestrator — Full Suite Command
# Runs structural tests, optionally behavioral, records to benchmark.db, generates regression report
# Usage: bash tests/run-suite.sh [--full] [--ci] [--estimate]
# Exit 0: PASS | Exit 1: FAIL/WARN
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# Parse args
MODE="structural"  # default: structural only
CI=0
ESTIMATE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --full)     MODE="full"; shift ;;
    --ci)       CI=1; shift ;;
    --estimate) ESTIMATE=1; shift ;;
    *)          shift ;;
  esac
done

# In CI mode: suppress color, no prompts
if [ "$CI" -eq 1 ]; then
  GREEN=""
  RED=""
  YELLOW=""
  RESET=""
  MODE="structural"  # CI never runs behavioral
fi

# Cost estimate mode
if [ "$ESTIMATE" -eq 1 ]; then
  bash "${SCRIPT_DIR}/behavioral/run-all.sh" --estimate
  exit 0
fi

VERSION=$(jq -r '.version // empty' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)
GIT_SHA=$(git -C "$PLUGIN_ROOT" rev-parse --short HEAD 2>/dev/null)

# ── Phase 1: Structural Tests ──────────────────────────

if [ "$CI" -eq 0 ]; then
  echo "╔═══════════════════════════════════════════╗"
  echo "║  TaskPlex Test Suite v${VERSION}              ║"
  echo "╚═══════════════════════════════════════════╝"
  echo ""
fi

struct_output=$(bash "${SCRIPT_DIR}/structural/run-all.sh" 2>&1) && struct_exit=0 || struct_exit=$?

if [ "$CI" -eq 0 ]; then
  echo "$struct_output"
  echo ""
fi

# Record structural results
struct_results=$(ls -t "${SCRIPT_DIR}/structural/results"/structural-*.json 2>/dev/null | head -1)
if [ -n "$struct_results" ]; then
  bash "${SCRIPT_DIR}/regression/record-results.sh" "$struct_results" > /dev/null 2>&1 || true
fi

# ── Phase 2: Behavioral Tests (--full only) ─────────────

behav_exit=0
if [ "$MODE" = "full" ]; then
  if [ "$CI" -eq 0 ]; then
    echo ""
    echo "=== Behavioral Tests ==="
    echo ""
    echo "  Behavioral suites make real Claude API calls."
    bash "${SCRIPT_DIR}/behavioral/run-all.sh" --estimate 2>&1 | sed 's/^/  /'
    echo ""
    printf "  Proceed? [y/N] "
    read -r answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
      echo "  Skipped behavioral tests."
    else
      behav_output=$(bash "${SCRIPT_DIR}/behavioral/run-all.sh" --yes 2>&1) && behav_exit=0 || behav_exit=$?
      echo "$behav_output"
      echo ""

      # Record behavioral results
      behav_results=$(ls -t "${SCRIPT_DIR}/behavioral/results"/behavioral-*.json 2>/dev/null | head -1)
      if [ -n "$behav_results" ]; then
        bash "${SCRIPT_DIR}/regression/record-results.sh" "$behav_results" > /dev/null 2>&1 || true
      fi
    fi
  fi
fi

# ── Phase 3: Regression Report ──────────────────────────

if [ -f "${SCRIPT_DIR}/benchmark.db" ]; then
  # Check if there's a baseline to compare against
  version_count=$(sqlite3 "${SCRIPT_DIR}/benchmark.db" "SELECT COUNT(DISTINCT version) FROM versions;" 2>/dev/null)
  if [ "$version_count" -le 1 ]; then
    if [ "$CI" -eq 0 ]; then
      echo ""
      echo "No baseline found — recording current version as baseline."
    fi
    reg_verdict="PASS"
    reg_exit=0
  else
    reg_output=$(bash "${SCRIPT_DIR}/regression/regression-report.sh" 2>&1) && reg_exit=0 || reg_exit=$?
    reg_verdict=$(echo "$reg_output" | grep '"verdict"' | head -1 | sed 's/.*"verdict": *"\([^"]*\)".*/\1/')
    if [ "$CI" -eq 0 ]; then
      echo ""
      echo "$reg_output"
    fi
  fi
else
  if [ "$CI" -eq 0 ]; then
    echo ""
    echo "No baseline found — recording current version as baseline."
  fi
  reg_verdict="N/A"
  reg_exit=0
fi

# ── Summary ─────────────────────────────────────────────

# Parse counts from JSON result file (avoids ANSI color issues with grep)
if [ -n "$struct_results" ] && [ -f "$struct_results" ]; then
  struct_pass=$(jq -r '.summary.passed // 0' "$struct_results")
  struct_fail=$(jq -r '.summary.failed // 0' "$struct_results")
  struct_total=$(jq -r '.summary.total // 0' "$struct_results")
else
  struct_pass=0
  struct_fail=0
  struct_total=0
fi

if [ "$CI" -eq 1 ]; then
  # CI: JSON-only output
  jq -n \
    --arg version "$VERSION" \
    --arg git_sha "$GIT_SHA" \
    --argjson struct_pass "$struct_pass" \
    --argjson struct_fail "$struct_fail" \
    --argjson struct_total "$struct_total" \
    --arg regression "$reg_verdict" \
    --arg mode "$MODE" \
    '{
      summary: {
        version: $version,
        git_sha: $git_sha,
        mode: $mode,
        structural: {passed: $struct_pass, failed: $struct_fail, total: $struct_total},
        regression_verdict: $regression
      }
    }'
else
  echo ""
  echo "┌──────────────────────────────────────┐"
  echo "│           Suite Summary              │"
  echo "├──────────────────────────────────────┤"
  printf "│  Structural:  %d/%d passed" "$struct_pass" "$struct_total"
  if [ "$struct_fail" -gt 0 ]; then
    printf "  ${RED}(%d failed)${RESET}" "$struct_fail"
  fi
  echo "          │"
  if [ "$MODE" = "full" ]; then
    printf "│  Behavioral:  (see above)            │\n"
  fi
  printf "│  Regression:  %s" "$reg_verdict"
  case "$reg_verdict" in
    PASS) printf "  ${GREEN}✓${RESET}" ;;
    WARN) printf "  ${YELLOW}⚠${RESET}" ;;
    FAIL) printf "  ${RED}✗${RESET}" ;;
  esac
  echo "                        │"
  echo "└──────────────────────────────────────┘"
fi

# Exit code: structural failures → fail
if [ "$struct_exit" -ne 0 ]; then
  exit 1
fi
exit 0
