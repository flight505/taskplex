#!/usr/bin/env bash
# US-009: Version Tracking Database — query-history.sh
# Retrieves all benchmark results for a given TaskPlex version as JSON
# Usage: bash tests/regression/query-history.sh <version>
# Exit 0: success | Exit 1: failure
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DB="${PLUGIN_ROOT}/tests/benchmark.db"

if ! command -v sqlite3 > /dev/null 2>&1; then
  echo "ERROR: sqlite3 not found" >&2
  exit 1
fi

if ! command -v jq > /dev/null 2>&1; then
  echo "ERROR: jq not found" >&2
  exit 1
fi

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: query-history.sh <version>" >&2
  echo "       query-history.sh 3.1.0" >&2
  exit 1
fi

if [ ! -f "$DB" ]; then
  echo "ERROR: ${DB} not found — run init-db.sh first" >&2
  exit 1
fi

# Check version exists
version_row=$(sqlite3 "$DB" "SELECT version, timestamp, git_sha FROM versions WHERE version='${VERSION}' LIMIT 1;" 2>/dev/null)

# Emit combined JSON using sqlite3 JSON mode (-json flag available in sqlite3 3.38+)
# Fall back to manual JSON construction for compatibility
structural_json=$(sqlite3 "$DB" -separator '|' \
  "SELECT test_name, passed, COALESCE(failures,'') FROM structural_results WHERE version='${VERSION}' ORDER BY rowid;" 2>/dev/null)

behavioral_json=$(sqlite3 "$DB" -separator '|' \
  "SELECT suite, test_name, passed, COALESCE(score,0), COALESCE(cost_usd,0) FROM behavioral_results WHERE version='${VERSION}' ORDER BY rowid;" 2>/dev/null)

dq_json=$(sqlite3 "$DB" -separator '|' \
  "SELECT story_id, dimension, COALESCE(score,0) FROM dq_scores WHERE version='${VERSION}' ORDER BY story_id, dimension;" 2>/dev/null)

# Build JSON output with jq
structural_arr="[]"
if [ -n "$structural_json" ]; then
  structural_arr=$(echo "$structural_json" | awk -F'|' '{
    printf "{\"test_name\":\"%s\",\"passed\":%s,\"failures\":\"%s\"}", $1, $2, $3
  }' | jq -s '.')
fi

behavioral_arr="[]"
if [ -n "$behavioral_json" ]; then
  behavioral_arr=$(echo "$behavioral_json" | awk -F'|' '{
    printf "{\"suite\":\"%s\",\"test_name\":\"%s\",\"passed\":%s,\"score\":%s,\"cost_usd\":%s}\n", $1, $2, $3, $4, $5
  }' | jq -s '.')
fi

dq_arr="[]"
if [ -n "$dq_json" ]; then
  dq_arr=$(echo "$dq_json" | awk -F'|' '{
    printf "{\"story_id\":\"%s\",\"dimension\":\"%s\",\"score\":%s}\n", $1, $2, $3
  }' | jq -s '.')
fi

# Extract version metadata
git_sha=""
timestamp=0
if [ -n "$version_row" ]; then
  git_sha=$(echo "$version_row" | cut -d'|' -f3)
  timestamp=$(echo "$version_row" | cut -d'|' -f2)
fi

jq -n \
  --arg version "$VERSION" \
  --arg git_sha "$git_sha" \
  --argjson timestamp "$timestamp" \
  --argjson structural "$structural_arr" \
  --argjson behavioral "$behavioral_arr" \
  --argjson dq "$dq_arr" \
  '{
    version: $version,
    git_sha: $git_sha,
    timestamp: $timestamp,
    structural: $structural,
    behavioral: $behavioral,
    dq_scores: $dq
  }'
