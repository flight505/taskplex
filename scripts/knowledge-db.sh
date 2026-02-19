#!/bin/bash
# knowledge-db.sh — SQLite knowledge store helpers
# Sourced by taskplex.sh and hook scripts
# Requires: sqlite3, jq

# Initialize the knowledge database with schema
# Args: $1 = database path
init_knowledge_db() {
  local db="$1"
  if [ -z "$db" ]; then
    echo "ERROR: init_knowledge_db requires database path" >&2
    return 1
  fi

  sqlite3 "$db" <<'SQL'
CREATE TABLE IF NOT EXISTS learnings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  story_id TEXT NOT NULL,
  run_id TEXT,
  content TEXT NOT NULL,
  confidence REAL DEFAULT 1.0,
  tags TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  source TEXT DEFAULT 'agent'
);

CREATE TABLE IF NOT EXISTS file_patterns (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path_glob TEXT NOT NULL,
  pattern_type TEXT NOT NULL,
  description TEXT NOT NULL,
  source_story TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS error_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  story_id TEXT NOT NULL,
  run_id TEXT,
  category TEXT NOT NULL,
  message TEXT,
  attempt INTEGER DEFAULT 1,
  resolved INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS decisions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  story_id TEXT NOT NULL,
  run_id TEXT,
  action TEXT NOT NULL,
  model TEXT,
  effort_level TEXT,
  reasoning TEXT,
  tokens_used INTEGER,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY,
  branch TEXT NOT NULL,
  mode TEXT DEFAULT 'sequential',
  model TEXT,
  total_stories INTEGER,
  completed INTEGER DEFAULT 0,
  skipped INTEGER DEFAULT 0,
  started_at TEXT DEFAULT (datetime('now')),
  ended_at TEXT
);
SQL
}

# Migrate knowledge.md to SQLite (one-time, idempotent)
# Args: $1 = database path, $2 = knowledge.md path
migrate_knowledge_md() {
  local db="$1"
  local md_file="$2"

  if [ ! -f "$md_file" ]; then
    return 0
  fi

  # Check if migration already happened
  local count
  count=$(sqlite3 "$db" "SELECT COUNT(*) FROM learnings WHERE source = 'migration';" 2>/dev/null)
  if [ "$count" -gt 0 ]; then
    return 0  # Already migrated
  fi

  # Parse knowledge.md entries (lines starting with "- [")
  local learning_lines
  learning_lines=$(grep '^- \[' "$md_file" || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Extract story_id and content from "- [US-001] learning text"
    local story_id content
    story_id=$(echo "$line" | sed -n 's/^- \[\([^]]*\)\] .*/\1/p')
    content=$(echo "$line" | sed -n 's/^- \[[^]]*\] //p')

    if [ -n "$content" ]; then
      sqlite3 "$db" "INSERT INTO learnings (story_id, content, confidence, source) VALUES ('${story_id:-unknown}', '$(echo "$content" | sed "s/'/''/g")', 0.8, 'migration');"
    fi
  done <<< "$learning_lines"
}

# Insert a learning into the database
# Args: $1=db, $2=story_id, $3=run_id, $4=content, $5=tags_json (optional)
insert_learning() {
  local db="$1" story_id="$2" run_id="$3" content="$4" tags="${5:-null}"
  local escaped_content
  escaped_content=$(echo "$content" | sed "s/'/''/g")

  sqlite3 "$db" "INSERT INTO learnings (story_id, run_id, content, tags) VALUES ('$story_id', '$run_id', '$escaped_content', '$tags');"
}

# Insert an error into history
# Args: $1=db, $2=story_id, $3=run_id, $4=category, $5=message, $6=attempt
insert_error() {
  local db="$1" story_id="$2" run_id="$3" category="$4" message="$5" attempt="${6:-1}"
  local escaped_msg
  escaped_msg=$(echo "$message" | sed "s/'/''/g" | head -c 500)

  sqlite3 "$db" "INSERT INTO error_history (story_id, run_id, category, message, attempt) VALUES ('$story_id', '$run_id', '$category', '$escaped_msg', $attempt);"
}

# Mark errors as resolved for a story
# Args: $1=db, $2=story_id
resolve_errors() {
  local db="$1" story_id="$2"
  sqlite3 "$db" "UPDATE error_history SET resolved = 1 WHERE story_id = '$story_id' AND resolved = 0;"
}

# Insert a decision record
# Args: $1=db, $2=story_id, $3=run_id, $4=action, $5=model, $6=effort, $7=reasoning
insert_decision() {
  local db="$1" story_id="$2" run_id="$3" action="$4" model="$5" effort="$6" reasoning="$7"
  local escaped_reasoning
  escaped_reasoning=$(echo "$reasoning" | sed "s/'/''/g")

  sqlite3 "$db" "INSERT INTO decisions (story_id, run_id, action, model, effort_level, reasoning) VALUES ('$story_id', '$run_id', '$action', '$model', '$effort', '$escaped_reasoning');"
}

# Insert a run record
# Args: $1=db, $2=run_id, $3=branch, $4=mode, $5=model, $6=total_stories
insert_run() {
  local db="$1" run_id="$2" branch="$3" mode="$4" model="$5" total="$6"
  sqlite3 "$db" "INSERT OR IGNORE INTO runs (id, branch, mode, model, total_stories) VALUES ('$run_id', '$branch', '$mode', '$model', $total);"
}

# Update run completion stats
# Args: $1=db, $2=run_id, $3=completed, $4=skipped
update_run() {
  local db="$1" run_id="$2" completed="$3" skipped="$4"
  sqlite3 "$db" "UPDATE runs SET completed = $completed, skipped = $skipped, ended_at = datetime('now') WHERE id = '$run_id';"
}

# Query top-N learnings with confidence decay (5%/day)
# Args: $1=db, $2=limit (default 10), $3=tags_filter (optional JSON array string)
query_learnings() {
  local db="$1" limit="${2:-10}" tags_filter="${3:-}"

  local where_clause=""
  if [ -n "$tags_filter" ]; then
    # Build WHERE clause matching any tag in the filter
    # tags_filter is a JSON array like '["src/api","US-001"]'
    local tag_conditions=""
    for tag in $(echo "$tags_filter" | jq -r '.[]' 2>/dev/null); do
      if [ -n "$tag_conditions" ]; then
        tag_conditions="$tag_conditions OR "
      fi
      tag_conditions="${tag_conditions}tags LIKE '%$(echo "$tag" | sed "s/'/''/g")%'"
    done
    if [ -n "$tag_conditions" ]; then
      where_clause="WHERE ($tag_conditions)"
    fi
  fi

  sqlite3 -separator '|' "$db" "
    SELECT content, story_id, eff_confidence FROM (
      SELECT content, story_id,
        ROUND(confidence * POWER(0.95, julianday('now') - julianday(created_at)), 3) AS eff_confidence
      FROM learnings
      $where_clause
    )
    WHERE eff_confidence > 0.3
    ORDER BY eff_confidence DESC
    LIMIT $limit;
  " 2>/dev/null
}

# Query error history for a story
# Args: $1=db, $2=story_id
query_errors() {
  local db="$1" story_id="$2"
  sqlite3 -separator '|' "$db" "
    SELECT category, message, attempt, resolved
    FROM error_history
    WHERE story_id = '$story_id'
    ORDER BY created_at DESC
    LIMIT 5;
  " 2>/dev/null
}

# Get decision history for a story
# Args: $1=db, $2=story_id
query_decisions() {
  local db="$1" story_id="$2"
  sqlite3 -separator '|' "$db" "
    SELECT action, model, effort_level, reasoning
    FROM decisions
    WHERE story_id = '$story_id'
    ORDER BY created_at DESC
    LIMIT 3;
  " 2>/dev/null
}

# Get summary statistics for report
# Args: $1=db, $2=run_id (optional, all runs if empty)
query_stats() {
  local db="$1" run_id="${2:-}"

  local run_filter=""
  if [ -n "$run_id" ]; then
    run_filter="WHERE run_id = '$run_id'"
  fi

  echo "=== Knowledge Store Statistics ==="
  echo "Total learnings: $(sqlite3 "$db" "SELECT COUNT(*) FROM learnings $run_filter;")"
  echo "Active learnings (confidence > 0.3): $(sqlite3 "$db" "SELECT COUNT(*) FROM learnings WHERE ROUND(confidence * POWER(0.95, julianday('now') - julianday(created_at)), 3) > 0.3;")"
  echo "Total errors recorded: $(sqlite3 "$db" "SELECT COUNT(*) FROM error_history $run_filter;")"
  echo "Resolved errors: $(sqlite3 "$db" "SELECT COUNT(*) FROM error_history WHERE resolved = 1 $( [ -n "$run_id" ] && echo "AND run_id = '$run_id'" );")"
  echo "Decisions made: $(sqlite3 "$db" "SELECT COUNT(*) FROM decisions $run_filter;")"

  if [ -n "$run_id" ]; then
    echo ""
    echo "=== Error Breakdown (this run) ==="
    sqlite3 -column -header "$db" "
      SELECT category, COUNT(*) as count, SUM(resolved) as resolved
      FROM error_history WHERE run_id = '$run_id'
      GROUP BY category ORDER BY count DESC;
    "

    echo ""
    echo "=== Decision Breakdown (this run) ==="
    sqlite3 -column -header "$db" "
      SELECT action, model, COUNT(*) as count
      FROM decisions WHERE run_id = '$run_id'
      GROUP BY action, model ORDER BY count DESC;
    "
  fi
}
