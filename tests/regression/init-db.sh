#!/usr/bin/env bash
# US-009: Version Tracking Database — init-db.sh
# Creates tests/benchmark.db with benchmark schema (idempotent)
# Usage: bash tests/regression/init-db.sh
# Exit 0: success | Exit 1: failure
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DB="${PLUGIN_ROOT}/tests/benchmark.db"

if ! command -v sqlite3 > /dev/null 2>&1; then
  echo "ERROR: sqlite3 not found — required for benchmark database" >&2
  exit 1
fi

sqlite3 "$DB" <<'SQL'
-- Plugin versions indexed per benchmark run
CREATE TABLE IF NOT EXISTS versions (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  version   TEXT    NOT NULL,
  timestamp INTEGER NOT NULL,
  git_sha   TEXT
);

-- Structural layer results (per suite: manifests, scripts, cross-refs)
CREATE TABLE IF NOT EXISTS structural_results (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  version   TEXT    NOT NULL,
  test_name TEXT    NOT NULL,
  passed    INTEGER NOT NULL,
  failures  TEXT
);

-- Behavioral layer results (per suite: hooks, skill-triggers, agents)
CREATE TABLE IF NOT EXISTS behavioral_results (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  version   TEXT    NOT NULL,
  suite     TEXT    NOT NULL,
  test_name TEXT    NOT NULL,
  passed    INTEGER NOT NULL,
  score     REAL,
  cost_usd  REAL
);

-- DQ scores from story-level evaluation (dimensions: discipline, correctness, autonomy, efficiency)
CREATE TABLE IF NOT EXISTS dq_scores (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  version   TEXT    NOT NULL,
  story_id  TEXT    NOT NULL,
  dimension TEXT    NOT NULL,
  score     REAL
);
SQL

echo "Initialized: ${DB}"
sqlite3 "$DB" '.schema'
