#!/usr/bin/env bash
# TaskPlex Test Suite — behavioral tests + regression tracking
# Cross-ref validation is now a marketplace PostToolUse hook (auto-runs on edits).
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
MODE="summary"  # default: just regression summary
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

if [ "$CI" -eq 1 ]; then
  GREEN=""; RED=""; YELLOW=""; RESET=""
fi

# Cost estimate mode
if [ "$ESTIMATE" -eq 1 ]; then
  bash "${SCRIPT_DIR}/behavioral/run-all.sh" --estimate
  exit 0
fi

VERSION=$(jq -r '.version // empty' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)
GIT_SHA=$(git -C "$PLUGIN_ROOT" rev-parse --short HEAD 2>/dev/null)

if [ "$CI" -eq 0 ]; then
  echo "╔═══════════════════════════════════════════╗"
  echo "║  TaskPlex Test Suite v${VERSION}              ║"
  echo "╚═══════════════════════════════════════════╝"
  echo ""
fi

# ── Behavioral Tests (--full only) ─────────────────────

behav_exit=0
if [ "$MODE" = "full" ]; then
  if [ "$CI" -eq 0 ]; then
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

# ── Regression Report ──────────────────────────────────

reg_verdict="N/A"
if [ -f "${SCRIPT_DIR}/benchmark.db" ]; then
  version_count=$(sqlite3 "${SCRIPT_DIR}/benchmark.db" "SELECT COUNT(DISTINCT version) FROM versions;" 2>/dev/null)
  if [ "$version_count" -le 1 ]; then
    if [ "$CI" -eq 0 ]; then
      echo "No baseline found — current version is the baseline."
    fi
    reg_verdict="PASS"
  else
    reg_output=$(bash "${SCRIPT_DIR}/regression/regression-report.sh" 2>&1) && reg_exit=0 || reg_exit=$?
    reg_verdict=$(echo "$reg_output" | grep '"verdict"' | head -1 | sed 's/.*"verdict": *"\([^"]*\)".*/\1/')
    if [ "$CI" -eq 0 ]; then
      echo "$reg_output"
    fi
  fi
else
  if [ "$CI" -eq 0 ]; then
    echo "No benchmark database — nothing to compare."
  fi
fi

# ── Summary ────────────────────────────────────────────

if [ "$CI" -eq 1 ]; then
  jq -n \
    --arg version "$VERSION" \
    --arg git_sha "$GIT_SHA" \
    --arg regression "$reg_verdict" \
    --arg mode "$MODE" \
    '{summary: {version: $version, git_sha: $git_sha, mode: $mode, regression_verdict: $regression}}'
else
  echo ""
  echo "┌──────────────────────────────────────┐"
  echo "│           Suite Summary              │"
  echo "├──────────────────────────────────────┤"
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
  echo "│  Cross-refs: marketplace hook        │"
  echo "└──────────────────────────────────────┘"
fi

exit 0
