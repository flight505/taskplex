#!/usr/bin/env bash
# US-009: Version Tracking Database — record-results.sh
# Imports structural and/or behavioral JSON result files into benchmark.db
# Usage: bash tests/regression/record-results.sh <result-file...>
# Exit 0: success | Exit 1: failure
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DB="${PLUGIN_ROOT}/tests/benchmark.db"
PLUGIN_JSON="${PLUGIN_ROOT}/.claude-plugin/plugin.json"

if ! command -v sqlite3 > /dev/null 2>&1; then
  echo "ERROR: sqlite3 not found — required for benchmark database" >&2
  exit 1
fi

if ! command -v jq > /dev/null 2>&1; then
  echo "ERROR: jq not found — required for JSON parsing" >&2
  exit 1
fi

# Initialize DB if it does not exist
if [ ! -f "$DB" ]; then
  bash "${SCRIPT_DIR}/init-db.sh" > /dev/null
fi

# Get plugin version and current git SHA as fallbacks
PLUGIN_VERSION=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
GIT_SHA=$(git -C "$PLUGIN_ROOT" rev-parse HEAD 2>/dev/null | head -c 40)

if [ $# -eq 0 ]; then
  echo "Usage: record-results.sh <result-file...>" >&2
  echo "No result files provided — nothing to record." >&2
  exit 0
fi

imported=0
skipped=0

for file in "$@"; do
  # Glob may not match — skip non-existent files gracefully
  if [ ! -f "$file" ]; then
    echo "  skip: $file (not found)"
    skipped=$((skipped + 1))
    continue
  fi

  # Validate JSON
  if ! jq . "$file" > /dev/null 2>&1; then
    echo "  skip: $file (invalid JSON)" >&2
    skipped=$((skipped + 1))
    continue
  fi

  suite=$(jq -r '.suite // empty' "$file")
  if [ -z "$suite" ]; then
    echo "  skip: $file (missing .suite field)" >&2
    skipped=$((skipped + 1))
    continue
  fi

  # Use version from file if present, else fall back to plugin.json
  version=$(jq -r '.version // empty' "$file")
  [ -z "$version" ] && version="$PLUGIN_VERSION"

  # Use git_sha from file if present, else fall back to HEAD
  file_sha=$(jq -r '.git_sha // empty' "$file")
  [ -z "$file_sha" ] && file_sha="$GIT_SHA"

  timestamp=$(jq -r '.timestamp // 0' "$file")
  total=$(jq -r '.summary.total // 0' "$file")
  passed_count=$(jq -r '.summary.passed // 0' "$file")
  failed_count=$(jq -r '.summary.failed // 0' "$file")
  cost=$(jq -r '.summary.cost_usd // 0' "$file")

  # Upsert version record (one row per unique version — first seen wins)
  sqlite3 "$DB" "INSERT OR IGNORE INTO versions (version, timestamp, git_sha) VALUES ('${version}', ${timestamp}, '${file_sha}');"

  case "$suite" in
    structural*)
      # Structural suites: one summary row (test_name = suite label)
      pass_flag=0
      [ "$failed_count" -eq 0 ] && pass_flag=1
      failures_str="${failed_count} check(s) failed out of ${total}"
      [ "$pass_flag" -eq 1 ] && failures_str=""
      sqlite3 "$DB" "INSERT INTO structural_results (version, test_name, passed, failures) VALUES ('${version}', '${suite}', ${pass_flag}, '${failures_str}');"
      echo "  recorded structural '${suite}' for v${version} (${passed_count}/${total} checks passed)"
      ;;
    *)
      # Behavioral suites: one summary row per file (test_name = suite label)
      score=0
      if [ "$total" -gt 0 ]; then
        score=$(echo "$passed_count $total" | awk '{printf "%.4f", $1/$2}')
      fi
      sqlite3 "$DB" "INSERT INTO behavioral_results (version, suite, test_name, passed, score, cost_usd) VALUES ('${version}', '${suite}', '${suite}', ${passed_count}, ${score}, ${cost});"
      echo "  recorded behavioral '${suite}' for v${version} (${passed_count}/${total} passed, score=${score}, cost=\$${cost})"
      ;;
  esac

  imported=$((imported + 1))
done

echo ""
echo "Done: ${imported} file(s) imported, ${skipped} skipped."
