# TaskPlex v2.0 Smart Scaffold Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add hook-based intelligence (decision calls, SubagentStart/Stop hooks, SQLite knowledge store) to TaskPlex while keeping bash as the infrastructure layer.

**Architecture:** Bash scripts source a new `knowledge-db.sh` helper for SQLite operations. Two new hook scripts (`inject-knowledge.sh`, `validate-result.sh`) replace inline context brief generation and the separate validator step. A `decision-call.sh` module provides per-story decision calls via 1-shot Opus invocations. All new features are opt-in with backward-compatible defaults.

**Tech Stack:** Bash 3.2+, SQLite3 (system-installed), jq, Claude CLI (`claude -p`)

**Design doc:** `docs/plans/2026-02-17-v2-smart-scaffold-design.md`

---

## Task 1: SQLite Knowledge Store — Helper Script

**Files:**
- Create: `scripts/knowledge-db.sh`
- Create: `tests/test-knowledge-db.sh`

This is the foundation. All other v2.0 components depend on it.

**Step 1: Create the SQLite helper script**

Create `scripts/knowledge-db.sh` with these functions:
- `init_knowledge_db()` — create tables if not exist
- `migrate_knowledge_md()` — one-time migration from knowledge.md
- `insert_learning()` — add a learning row
- `insert_error()` — add an error_history row
- `insert_decision()` — add a decisions row
- `insert_run()` / `update_run()` — run lifecycle
- `query_learnings()` — get top-N learnings by effective confidence (with decay)
- `query_errors()` — get error history for a story
- `query_file_patterns()` — get file patterns matching a glob

```bash
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
  while IFS= read -r line; do
    # Extract story_id and content from "- [US-001] learning text"
    local story_id content
    story_id=$(echo "$line" | sed -n 's/^- \[\([^]]*\)\] .*/\1/p')
    content=$(echo "$line" | sed -n 's/^- \[[^]]*\] //p')

    if [ -n "$content" ]; then
      sqlite3 "$db" "INSERT INTO learnings (story_id, content, confidence, source) VALUES ('${story_id:-unknown}', '$(echo "$content" | sed "s/'/''/g")', 0.8, 'migration');"
    fi
  done < <(grep '^- \[' "$md_file")
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
    SELECT content, story_id,
      ROUND(confidence * POWER(0.95, julianday('now') - julianday(created_at)), 3) AS eff_confidence
    FROM learnings
    $where_clause
    HAVING eff_confidence > 0.3
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
```

**Step 2: Make it executable**

Run: `chmod +x scripts/knowledge-db.sh`

**Step 3: Write the test script**

Create `tests/test-knowledge-db.sh`:

```bash
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
TABLE_COUNT=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")
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
```

**Step 4: Run tests to verify**

Run: `chmod +x tests/test-knowledge-db.sh && bash tests/test-knowledge-db.sh`
Expected: All 8+ assertions pass.

**Step 5: Commit**

```bash
git add scripts/knowledge-db.sh tests/test-knowledge-db.sh
git commit -m "feat: add SQLite knowledge store helper (knowledge-db.sh)

- Schema: learnings, file_patterns, error_history, decisions, runs
- Confidence decay at 5%/day (entries expire after ~30 days)
- One-time idempotent migration from knowledge.md
- SQL injection safety via single-quote escaping
- Test suite with 8 assertions"
```

---

## Task 2: SubagentStart Hook — Knowledge Injection

**Files:**
- Create: `hooks/inject-knowledge.sh`
- Modify: `hooks/hooks.json`
- Create: `tests/test-inject-knowledge.sh`

**Depends on:** Task 1 (knowledge-db.sh)

**Step 1: Create the hook script**

Create `hooks/inject-knowledge.sh`:

```bash
#!/bin/bash
# inject-knowledge.sh — SubagentStart hook
# Injects context from SQLite knowledge store into agent spawn.
# Replaces generate_context_brief() from taskplex.sh.
#
# Input: JSON on stdin with agent_id, agent_type
# Output: JSON on stdout with hookSpecificOutput.additionalContext
# Exit 0 always (never blocks agent creation)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/knowledge-db.sh" 2>/dev/null || true

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Extract fields
AGENT_TYPE=$(echo "$HOOK_INPUT" | jq -r '.agent_type // ""' 2>/dev/null)
AGENT_ID=$(echo "$HOOK_INPUT" | jq -r '.agent_id // ""' 2>/dev/null)

# Find project root (look for prd.json)
PROJECT_DIR="$(pwd)"
PRD_FILE="$PROJECT_DIR/prd.json"
CONFIG_FILE="$PROJECT_DIR/.claude/taskplex.config.json"

# Determine knowledge DB path
KNOWLEDGE_DB="$PROJECT_DIR/knowledge.db"
if [ -f "$CONFIG_FILE" ]; then
  CONFIGURED_DB=$(jq -r '.knowledge_db // ""' "$CONFIG_FILE" 2>/dev/null)
  if [ -n "$CONFIGURED_DB" ]; then
    KNOWLEDGE_DB="$PROJECT_DIR/$CONFIGURED_DB"
  fi
fi

# If no DB exists, try migration from knowledge.md then bail
if [ ! -f "$KNOWLEDGE_DB" ]; then
  if [ -f "$PROJECT_DIR/knowledge.md" ]; then
    init_knowledge_db "$KNOWLEDGE_DB" 2>/dev/null || true
    migrate_knowledge_md "$KNOWLEDGE_DB" "$PROJECT_DIR/knowledge.md" 2>/dev/null || true
  else
    # No knowledge store at all — exit cleanly with no context
    echo '{}'
    exit 0
  fi
fi

# If no PRD, nothing to inject
if [ ! -f "$PRD_FILE" ]; then
  echo '{}'
  exit 0
fi

# Find the in_progress story
STORY_ID=$(jq -r '.userStories[] | select(.status == "in_progress") | .id' "$PRD_FILE" 2>/dev/null | head -1)

if [ -z "$STORY_ID" ]; then
  echo '{}'
  exit 0
fi

# Build context brief
CONTEXT=""

# 1. Story details
STORY_JSON=$(jq --arg id "$STORY_ID" '.userStories[] | select(.id == $id)' "$PRD_FILE" 2>/dev/null)
CONTEXT="${CONTEXT}# Context Brief for ${STORY_ID}
Generated by TaskPlex knowledge injection hook

## Story Details
\`\`\`json
${STORY_JSON}
\`\`\`

"

# 2. Run check_before_implementing commands
CHECK_CMDS=$(jq -r --arg id "$STORY_ID" \
  '.userStories[] | select(.id == $id) | .check_before_implementing // [] | .[]' \
  "$PRD_FILE" 2>/dev/null)

if [ -n "$CHECK_CMDS" ]; then
  CONTEXT="${CONTEXT}## Pre-Implementation Check Results
"
  while IFS= read -r cmd; do
    if [ -n "$cmd" ]; then
      CHECK_OUTPUT=$(eval "$cmd" 2>&1 || echo "(command returned non-zero)")
      CONTEXT="${CONTEXT}### \`${cmd}\`
\`\`\`
${CHECK_OUTPUT}
\`\`\`

"
    fi
  done <<< "$CHECK_CMDS"
fi

# 3. Dependency diffs
DEP_IDS=$(jq -r --arg id "$STORY_ID" \
  '.userStories[] | select(.id == $id) | .depends_on // [] | .[]' \
  "$PRD_FILE" 2>/dev/null)

if [ -n "$DEP_IDS" ]; then
  CONTEXT="${CONTEXT}## Dependency Story Changes
"
  while IFS= read -r dep_id; do
    if [ -n "$dep_id" ]; then
      DEP_COMMIT=$(git log --oneline --grep="feat($dep_id)" -1 --format="%H" 2>/dev/null)
      if [ -n "$DEP_COMMIT" ]; then
        DEP_DIFF=$(git diff "${DEP_COMMIT}^".."${DEP_COMMIT}" --stat 2>/dev/null || echo "(diff not available)")
        CONTEXT="${CONTEXT}### ${dep_id} (commit: ${DEP_COMMIT:0:8})
\`\`\`
${DEP_DIFF}
\`\`\`

"
      fi
    fi
  done <<< "$DEP_IDS"
fi

# 4. Relevant learnings from SQLite (with confidence decay)
RELATED_TO=$(jq -r --arg id "$STORY_ID" \
  '.userStories[] | select(.id == $id) | .related_to // [] | .[]' \
  "$PRD_FILE" 2>/dev/null)
DEPENDS_ON=$(jq -r --arg id "$STORY_ID" \
  '.userStories[] | select(.id == $id) | .depends_on // [] | .[]' \
  "$PRD_FILE" 2>/dev/null)

# Build tags filter from related_to and depends_on
TAGS_JSON="["
FIRST=true
for tag in $RELATED_TO $DEPENDS_ON $STORY_ID; do
  if [ "$FIRST" = true ]; then
    FIRST=false
  else
    TAGS_JSON="${TAGS_JSON},"
  fi
  TAGS_JSON="${TAGS_JSON}\"${tag}\""
done
TAGS_JSON="${TAGS_JSON}]"

LEARNINGS=$(query_learnings "$KNOWLEDGE_DB" 10 "$TAGS_JSON" 2>/dev/null)

if [ -n "$LEARNINGS" ]; then
  CONTEXT="${CONTEXT}## Project Knowledge (from previous stories)
"
  while IFS='|' read -r content story_id confidence; do
    CONTEXT="${CONTEXT}- [${story_id}] (confidence: ${confidence}) ${content}
"
  done <<< "$LEARNINGS"
  CONTEXT="${CONTEXT}
"
fi

# 5. Error history (if retry)
STORY_ATTEMPTS=$(echo "$STORY_JSON" | jq -r '.attempts // 0' 2>/dev/null)
if [ "$STORY_ATTEMPTS" -gt 1 ]; then
  ERRORS=$(query_errors "$KNOWLEDGE_DB" "$STORY_ID" 2>/dev/null)
  if [ -n "$ERRORS" ]; then
    CONTEXT="${CONTEXT}## Previous Error History
"
    while IFS='|' read -r category message attempt resolved; do
      local status="unresolved"
      [ "$resolved" = "1" ] && status="resolved"
      CONTEXT="${CONTEXT}- Attempt ${attempt}: [${category}] ${message} (${status})
"
    done <<< "$ERRORS"
    CONTEXT="${CONTEXT}
"
  fi

  # Include last_error and retry_hint from PRD
  LAST_ERROR=$(echo "$STORY_JSON" | jq -r '.last_error // empty' 2>/dev/null)
  if [ -n "$LAST_ERROR" ]; then
    CONTEXT="${CONTEXT}## Previous Failure Context
Last error: ${LAST_ERROR}
Please address this issue and try again.

"
  fi
fi

# Escape the context for JSON output
ESCAPED_CONTEXT=$(echo "$CONTEXT" | jq -Rs '.' 2>/dev/null)

# Output hook response
cat <<HOOK_OUTPUT
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": ${ESCAPED_CONTEXT}
  }
}
HOOK_OUTPUT

exit 0
```

**Step 2: Make it executable**

Run: `chmod +x hooks/inject-knowledge.sh`

**Step 3: Add hook entry to hooks.json**

Add to the `hooks` array in `hooks/hooks.json`, after the existing PostToolUse destructive blocker entry (line 9) and before the monitor hooks:

```json
{
  "event": "SubagentStart",
  "matcher": "implementer|validator",
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/hooks/inject-knowledge.sh",
  "description": "Inject knowledge store context into agent spawn"
}
```

**Step 4: Write the test script**

Create `tests/test-inject-knowledge.sh`:

```bash
#!/bin/bash
# Test inject-knowledge.sh hook
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/taskplex-test-hook-$$"
PASSED=0
FAILED=0

assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -qF "$expected"; then
    echo "  PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $desc (expected to contain: $expected)"
    FAILED=$((FAILED + 1))
  fi
}

assert_valid_json() {
  local desc="$1" json="$2"
  if echo "$json" | jq empty 2>/dev/null; then
    echo "  PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $desc (invalid JSON)"
    FAILED=$((FAILED + 1))
  fi
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Setup test project
mkdir -p "$TEST_DIR/.claude"
cd "$TEST_DIR"

# Create minimal prd.json
cat > "$TEST_DIR/prd.json" <<'EOF'
{
  "branchName": "taskplex/test",
  "userStories": [
    {
      "id": "US-001",
      "title": "Test Story",
      "status": "in_progress",
      "attempts": 1,
      "acceptanceCriteria": ["It works"],
      "check_before_implementing": ["echo 'check output here'"],
      "depends_on": [],
      "related_to": ["src/api"]
    }
  ]
}
EOF

# Create knowledge DB with test data
source "$SCRIPT_DIR/scripts/knowledge-db.sh"
init_knowledge_db "$TEST_DIR/knowledge.db"
insert_learning "$TEST_DIR/knowledge.db" "US-000" "run-0" "Project uses TypeScript" '["src/api"]'

# Initialize git for dependency diff tests
git init "$TEST_DIR" > /dev/null 2>&1
git -C "$TEST_DIR" add -A > /dev/null 2>&1
git -C "$TEST_DIR" commit -m "init" > /dev/null 2>&1

echo "=== Testing inject-knowledge.sh ==="
echo ""

# Test 1: Hook produces valid JSON
echo "Test 1: Valid JSON output"
RESULT=$(echo '{"agent_id":"test-1","agent_type":"implementer"}' | bash "$SCRIPT_DIR/hooks/inject-knowledge.sh")
assert_valid_json "Output is valid JSON" "$RESULT"

# Test 2: Output contains additionalContext
echo "Test 2: Contains additionalContext"
HAS_CONTEXT=$(echo "$RESULT" | jq -r '.hookSpecificOutput.additionalContext // empty')
assert_contains "Has context" "Context Brief for US-001" "$HAS_CONTEXT"

# Test 3: Context includes pre-implementation checks
echo "Test 3: Pre-implementation check results"
assert_contains "Has check output" "check output here" "$HAS_CONTEXT"

# Test 4: Context includes learnings
echo "Test 4: Knowledge injection"
assert_contains "Has learning" "Project uses TypeScript" "$HAS_CONTEXT"

# Test 5: No PRD = empty output
echo "Test 5: No PRD graceful fallback"
TEMP_PRD="$TEST_DIR/prd.json"
mv "$TEMP_PRD" "${TEMP_PRD}.bak"
EMPTY_RESULT=$(echo '{"agent_type":"implementer"}' | bash "$SCRIPT_DIR/hooks/inject-knowledge.sh")
assert_valid_json "Empty output is valid JSON" "$EMPTY_RESULT"
mv "${TEMP_PRD}.bak" "$TEMP_PRD"

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ $FAILED -eq 0 ] && exit 0 || exit 1
```

**Step 5: Run tests**

Run: `chmod +x tests/test-inject-knowledge.sh && bash tests/test-inject-knowledge.sh`
Expected: All assertions pass.

**Step 6: Commit**

```bash
git add hooks/inject-knowledge.sh hooks/hooks.json tests/test-inject-knowledge.sh
git commit -m "feat: add SubagentStart knowledge injection hook

- inject-knowledge.sh queries SQLite for relevant learnings
- Runs check_before_implementing commands, captures output
- Includes dependency diffs from completed stories
- Injects error history on retry attempts
- Added to hooks.json with matcher for implementer|validator
- Graceful fallback: exits cleanly if no DB or PRD exists"
```

---

## Task 3: SubagentStop Hook — Inline Validation

**Files:**
- Create: `hooks/validate-result.sh`
- Modify: `hooks/hooks.json`
- Create: `tests/test-validate-result.sh`

**Independent of Tasks 1-2** (can be implemented in parallel).

**Step 1: Create the validation hook script**

Create `hooks/validate-result.sh`:

```bash
#!/bin/bash
# validate-result.sh — SubagentStop hook
# Runs inline validation (typecheck/build/test) after implementer finishes.
# If validation fails, blocks agent with error details so it can self-heal.
#
# Input: JSON on stdin with agent_id, agent_type, agent_transcript_path, stop_hook_active
# Output: JSON on stdout with decision:"block" and reason (if failing)
# Exit 0 = allow agent to stop normally
# Exit 2 = block agent, inject reason (agent continues fixing)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Extract fields
AGENT_TYPE=$(echo "$HOOK_INPUT" | jq -r '.agent_type // ""' 2>/dev/null)
STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.agent_transcript_path // ""' 2>/dev/null)

# Prevent infinite validation loops
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Only validate implementer agents
if [ "$AGENT_TYPE" != "implementer" ]; then
  exit 0
fi

# Find project config
PROJECT_DIR="$(pwd)"
CONFIG_FILE="$PROJECT_DIR/.claude/taskplex.config.json"

# Check if validation is enabled
if [ -f "$CONFIG_FILE" ]; then
  VALIDATE_ON_STOP=$(jq -r '.validate_on_stop // true' "$CONFIG_FILE" 2>/dev/null)
  if [ "$VALIDATE_ON_STOP" = "false" ]; then
    exit 0
  fi
fi

# Read validation commands from config
TYPECHECK_CMD=""
BUILD_CMD=""
TEST_CMD=""

if [ -f "$CONFIG_FILE" ]; then
  TYPECHECK_CMD=$(jq -r '.typecheck_command // ""' "$CONFIG_FILE" 2>/dev/null)
  BUILD_CMD=$(jq -r '.build_command // ""' "$CONFIG_FILE" 2>/dev/null)
  TEST_CMD=$(jq -r '.test_command // ""' "$CONFIG_FILE" 2>/dev/null)
fi

# If no validation commands configured, pass through
if [ -z "$TYPECHECK_CMD" ] && [ -z "$BUILD_CMD" ] && [ -z "$TEST_CMD" ]; then
  exit 0
fi

# Run validation commands and collect failures
FAILURES=""

if [ -n "$TYPECHECK_CMD" ]; then
  TYPECHECK_OUTPUT=$(eval "$TYPECHECK_CMD" 2>&1)
  TYPECHECK_EXIT=$?
  if [ $TYPECHECK_EXIT -ne 0 ]; then
    FAILURES="${FAILURES}Typecheck failed (exit $TYPECHECK_EXIT):
${TYPECHECK_OUTPUT}

"
  fi
fi

if [ -n "$BUILD_CMD" ]; then
  BUILD_OUTPUT=$(eval "$BUILD_CMD" 2>&1)
  BUILD_EXIT=$?
  if [ $BUILD_EXIT -ne 0 ]; then
    FAILURES="${FAILURES}Build failed (exit $BUILD_EXIT):
${BUILD_OUTPUT}

"
  fi
fi

if [ -n "$TEST_CMD" ]; then
  TEST_OUTPUT=$(eval "$TEST_CMD" 2>&1)
  TEST_EXIT=$?
  if [ $TEST_EXIT -ne 0 ]; then
    FAILURES="${FAILURES}Tests failed (exit $TEST_EXIT):
${TEST_OUTPUT}

"
  fi
fi

# Extract learnings from transcript and save to SQLite (best-effort)
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  source "$SCRIPT_DIR/scripts/knowledge-db.sh" 2>/dev/null || true

  PRD_FILE="$PROJECT_DIR/prd.json"
  KNOWLEDGE_DB="$PROJECT_DIR/knowledge.db"
  if [ -f "$CONFIG_FILE" ]; then
    CONFIGURED_DB=$(jq -r '.knowledge_db // ""' "$CONFIG_FILE" 2>/dev/null)
    [ -n "$CONFIGURED_DB" ] && KNOWLEDGE_DB="$PROJECT_DIR/$CONFIGURED_DB"
  fi

  if [ -f "$KNOWLEDGE_DB" ] && [ -f "$PRD_FILE" ]; then
    # Find current story
    STORY_ID=$(jq -r '.userStories[] | select(.status == "in_progress") | .id' "$PRD_FILE" 2>/dev/null | head -1)
    RUN_ID="${TASKPLEX_RUN_ID:-unknown}"

    # Try to extract learnings from the transcript's last JSON block
    # The implementer outputs structured JSON as its last response
    LEARNINGS=$(grep -o '"learnings"[[:space:]]*:[[:space:]]*\[.*\]' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 | jq -r '.[].[]' 2>/dev/null || true)

    if [ -n "$LEARNINGS" ] && [ -n "$STORY_ID" ]; then
      while IFS= read -r learning; do
        if [ -n "$learning" ]; then
          insert_learning "$KNOWLEDGE_DB" "$STORY_ID" "$RUN_ID" "$learning" 2>/dev/null || true
        fi
      done <<< "$LEARNINGS"
    fi
  fi
fi

# If all validations passed, allow agent to stop
if [ -z "$FAILURES" ]; then
  exit 0
fi

# Validation failed — block agent with error details
# Truncate to avoid overwhelming the agent
TRUNCATED_FAILURES=$(echo "$FAILURES" | head -c 2000)

# Escape for JSON
ESCAPED_REASON=$(echo "$TRUNCATED_FAILURES" | jq -Rs '.' 2>/dev/null)

cat <<BLOCK_OUTPUT
{
  "decision": "block",
  "reason": ${ESCAPED_REASON}
}
BLOCK_OUTPUT

exit 2
```

**Step 2: Make it executable**

Run: `chmod +x hooks/validate-result.sh`

**Step 3: Add hook entry to hooks.json**

Add to the `hooks` array in `hooks/hooks.json`, after the inject-knowledge entry:

```json
{
  "event": "SubagentStop",
  "matcher": "implementer",
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/hooks/validate-result.sh",
  "description": "Inline validation — block agent if checks fail"
}
```

**Step 4: Write the test script**

Create `tests/test-validate-result.sh`:

```bash
#!/bin/bash
# Test validate-result.sh hook
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/taskplex-test-validate-$$"
PASSED=0
FAILED=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $desc (expected: $expected, actual: $actual)"
    FAILED=$((FAILED + 1))
  fi
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Setup test project
mkdir -p "$TEST_DIR/.claude"
cd "$TEST_DIR"

echo "=== Testing validate-result.sh ==="
echo ""

# Test 1: stop_hook_active=true exits cleanly
echo "Test 1: Prevents infinite loops"
EXIT_CODE=0
echo '{"agent_type":"implementer","stop_hook_active":true}' | bash "$SCRIPT_DIR/hooks/validate-result.sh" > /dev/null 2>&1 || EXIT_CODE=$?
assert_eq "stop_hook_active=true exits 0" "0" "$EXIT_CODE"

# Test 2: Non-implementer exits cleanly
echo "Test 2: Non-implementer passthrough"
EXIT_CODE=0
echo '{"agent_type":"validator","stop_hook_active":false}' | bash "$SCRIPT_DIR/hooks/validate-result.sh" > /dev/null 2>&1 || EXIT_CODE=$?
assert_eq "validator agent exits 0" "0" "$EXIT_CODE"

# Test 3: No config = no validation = exit 0
echo "Test 3: No config passthrough"
EXIT_CODE=0
echo '{"agent_type":"implementer","stop_hook_active":false}' | bash "$SCRIPT_DIR/hooks/validate-result.sh" > /dev/null 2>&1 || EXIT_CODE=$?
assert_eq "No config exits 0" "0" "$EXIT_CODE"

# Test 4: Passing validation
echo "Test 4: Passing validation"
cat > "$TEST_DIR/.claude/taskplex.config.json" <<'EOF'
{
  "typecheck_command": "echo 'all good'",
  "validate_on_stop": true
}
EOF
EXIT_CODE=0
echo '{"agent_type":"implementer","stop_hook_active":false}' | bash "$SCRIPT_DIR/hooks/validate-result.sh" > /dev/null 2>&1 || EXIT_CODE=$?
assert_eq "Passing typecheck exits 0" "0" "$EXIT_CODE"

# Test 5: Failing validation blocks agent
echo "Test 5: Failing validation"
cat > "$TEST_DIR/.claude/taskplex.config.json" <<'EOF'
{
  "typecheck_command": "echo 'error TS2345: type mismatch' >&2; exit 1",
  "validate_on_stop": true
}
EOF
EXIT_CODE=0
RESULT=$(echo '{"agent_type":"implementer","stop_hook_active":false}' | bash "$SCRIPT_DIR/hooks/validate-result.sh" 2>/dev/null) || EXIT_CODE=$?
assert_eq "Failing typecheck exits 2" "2" "$EXIT_CODE"

# Check that output contains block decision
DECISION=$(echo "$RESULT" | jq -r '.decision // empty' 2>/dev/null)
assert_eq "Output has decision:block" "block" "$DECISION"

# Test 6: validate_on_stop=false disables
echo "Test 6: Disabled validation"
cat > "$TEST_DIR/.claude/taskplex.config.json" <<'EOF'
{
  "typecheck_command": "exit 1",
  "validate_on_stop": false
}
EOF
EXIT_CODE=0
echo '{"agent_type":"implementer","stop_hook_active":false}' | bash "$SCRIPT_DIR/hooks/validate-result.sh" > /dev/null 2>&1 || EXIT_CODE=$?
assert_eq "validate_on_stop=false exits 0" "0" "$EXIT_CODE"

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ $FAILED -eq 0 ] && exit 0 || exit 1
```

**Step 5: Run tests**

Run: `chmod +x tests/test-validate-result.sh && bash tests/test-validate-result.sh`
Expected: All 7 assertions pass.

**Step 6: Commit**

```bash
git add hooks/validate-result.sh hooks/hooks.json tests/test-validate-result.sh
git commit -m "feat: add SubagentStop inline validation hook

- validate-result.sh runs typecheck/build/test after implementer finishes
- Blocks agent (exit 2) with error details for self-healing
- stop_hook_active flag prevents infinite validation loops
- Extracts learnings from transcript to SQLite (best-effort)
- Configurable via validate_on_stop and validation commands in config
- Graceful passthrough when no validation commands configured"
```

---

## Task 4: Decision Call Module

**Files:**
- Create: `scripts/decision-call.sh`
- Create: `tests/test-decision-call.sh`

**Depends on:** Task 1 (knowledge-db.sh for query_learnings, query_errors)

**Step 1: Create the decision call module**

Create `scripts/decision-call.sh`:

```bash
#!/bin/bash
# decision-call.sh — 1-shot decision call for per-story orchestration
# Sourced by taskplex.sh. Uses Opus to decide action/model/effort per story.
#
# Requires: KNOWLEDGE_DB, PRD_FILE, RUN_ID (set by taskplex.sh)
# Requires: knowledge-db.sh already sourced

# Make a decision call for a story
# Args: $1=story_id
# Output: "action|model|effort" (pipe-separated)
# Fallback: "implement|$EXECUTION_MODEL|$EFFORT_LEVEL" on any error
decision_call() {
  local story_id="$1"

  # Check if decision calls are enabled
  if [ "$DECISION_CALLS_ENABLED" != "true" ]; then
    echo "implement|${EXECUTION_MODEL}|${EFFORT_LEVEL}"
    return 0
  fi

  local story_json
  story_json=$(jq --arg id "$story_id" '.userStories[] | select(.id == $id)' "$PRD_FILE" 2>/dev/null)

  if [ -z "$story_json" ]; then
    log "DECISION" "Story $story_id not found in PRD, using defaults"
    echo "implement|${EXECUTION_MODEL}|${EFFORT_LEVEL}"
    return 0
  fi

  # Gather context for decision
  local attempts last_error last_category retry_hint criteria_count
  attempts=$(echo "$story_json" | jq -r '.attempts // 0')
  last_error=$(echo "$story_json" | jq -r '.last_error // "none"')
  last_category=$(echo "$story_json" | jq -r '.last_error_category // "none"')
  retry_hint=$(echo "$story_json" | jq -r '.retry_hint // "none"')
  criteria_count=$(echo "$story_json" | jq -r '.acceptanceCriteria | length')

  # Get knowledge summary
  local knowledge_summary=""
  if [ -f "$KNOWLEDGE_DB" ]; then
    knowledge_summary=$(query_learnings "$KNOWLEDGE_DB" 10 2>/dev/null | head -10)
  fi

  # Get error patterns
  local error_patterns=""
  if [ -f "$KNOWLEDGE_DB" ]; then
    error_patterns=$(query_errors "$KNOWLEDGE_DB" "$story_id" 2>/dev/null)
  fi

  # Build prompt
  local prompt_file="/tmp/taskplex-decision-$$-${story_id}.md"
  cat > "$prompt_file" <<DECISION_PROMPT
You are a task orchestrator deciding how to handle the next story.

## Story
$(echo "$story_json" | jq '.')

## History
- Attempts: ${attempts}
- Last error category: ${last_category}
- Last error: ${last_error}
- Retry hint from agent: ${retry_hint}

## Knowledge Summary
${knowledge_summary:-No learnings available yet.}

## Error Patterns
${error_patterns:-No error history for this story.}

## Decision Required
Respond with JSON only, no other text:
{
  "action": "implement" | "skip" | "rewrite",
  "model": "sonnet" | "opus" | "haiku",
  "effort_level": "" | "low" | "medium" | "high",
  "reasoning": "one sentence"
}

Rules:
- First attempt with 0 errors: action=implement, model based on complexity
- Simple stories (1-2 criteria): model=haiku, effort=""
- Standard stories (3-5 criteria): model=sonnet, effort=""
- Complex stories (5+ criteria): model=opus if configured, effort=high
- After 1 failed attempt: consider model upgrade
- After 2+ failed attempts with same category: action=skip or rewrite
- env_missing or dependency_missing: always action=skip
- If last_error suggests fundamental issue: action=rewrite
DECISION_PROMPT

  # Make the 1-shot call
  local result
  result=$($TIMEOUT_CMD 30 claude -p "$(cat "$prompt_file")" \
    --model "${DECISION_MODEL:-opus}" \
    --output-format json \
    --max-turns 1 \
    --no-session-persistence 2>/dev/null) || {
    log "DECISION" "Decision call failed for $story_id, using defaults"
    rm -f "$prompt_file"
    echo "implement|${EXECUTION_MODEL}|${EFFORT_LEVEL}"
    return 0
  }

  rm -f "$prompt_file"

  # Parse the JSON response
  local action model effort reasoning
  action=$(echo "$result" | jq -r '.result // "" | if type == "string" then (try fromjson catch {}) else . end | .action // "implement"' 2>/dev/null)
  model=$(echo "$result" | jq -r '.result // "" | if type == "string" then (try fromjson catch {}) else . end | .model // "'$EXECUTION_MODEL'"' 2>/dev/null)
  effort=$(echo "$result" | jq -r '.result // "" | if type == "string" then (try fromjson catch {}) else . end | .effort_level // ""' 2>/dev/null)
  reasoning=$(echo "$result" | jq -r '.result // "" | if type == "string" then (try fromjson catch {}) else . end | .reasoning // "default"' 2>/dev/null)

  # Validate action
  case "$action" in
    implement|skip|rewrite) ;;
    *) action="implement" ;;
  esac

  # Validate model
  case "$model" in
    sonnet|opus|haiku) ;;
    *) model="$EXECUTION_MODEL" ;;
  esac

  # Effort levels only valid for opus
  if [ "$model" != "opus" ]; then
    effort=""
  fi

  # Record decision in SQLite
  if [ -f "$KNOWLEDGE_DB" ]; then
    insert_decision "$KNOWLEDGE_DB" "$story_id" "$RUN_ID" "$action" "$model" "$effort" "$reasoning" 2>/dev/null || true
  fi

  log "DECISION" "$story_id: action=$action model=$model effort=$effort ($reasoning)"

  # Emit decision event to monitor
  emit_event "decision.made" "{\"action\":\"$action\",\"model\":\"$model\",\"effort\":\"$effort\",\"reasoning\":\"$(echo "$reasoning" | tr '"' "'")\"}" "$story_id" 2>/dev/null || true

  echo "${action}|${model}|${effort}"
}
```

**Step 2: Make it executable**

Run: `chmod +x scripts/decision-call.sh`

**Step 3: Write unit test**

Create `tests/test-decision-call.sh`:

```bash
#!/bin/bash
# Test decision-call.sh module (without live Claude calls)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/taskplex-test-decision-$$"
PASSED=0
FAILED=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $desc (expected: $expected, actual: $actual)"
    FAILED=$((FAILED + 1))
  fi
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Setup test environment
mkdir -p "$TEST_DIR/.claude"
cd "$TEST_DIR"

# Mock globals that taskplex.sh normally sets
PROJECT_DIR="$TEST_DIR"
PRD_FILE="$TEST_DIR/prd.json"
KNOWLEDGE_DB="$TEST_DIR/knowledge.db"
CONFIG_FILE="$TEST_DIR/.claude/taskplex.config.json"
EXECUTION_MODEL="sonnet"
EFFORT_LEVEL=""
RUN_ID="test-run"
TIMEOUT_CMD="timeout"
command -v gtimeout > /dev/null 2>&1 && TIMEOUT_CMD="gtimeout"

# Mock functions
log() { :; }
emit_event() { :; }

# Source dependencies
source "$SCRIPT_DIR/scripts/knowledge-db.sh"
init_knowledge_db "$KNOWLEDGE_DB"

source "$SCRIPT_DIR/scripts/decision-call.sh"

# Create prd.json
cat > "$PRD_FILE" <<'EOF'
{
  "branchName": "taskplex/test",
  "userStories": [
    {"id": "US-001", "title": "Simple", "status": "pending", "attempts": 0, "acceptanceCriteria": ["Works"], "priority": 1},
    {"id": "US-002", "title": "Failed", "status": "pending", "attempts": 2, "last_error": "TypeError", "last_error_category": "code_error", "acceptanceCriteria": ["A","B","C"], "priority": 2}
  ]
}
EOF

echo "=== Testing decision-call.sh ==="
echo ""

# Test 1: Disabled decision calls returns defaults
echo "Test 1: Disabled returns defaults"
DECISION_CALLS_ENABLED="false"
RESULT=$(decision_call "US-001")
assert_eq "Returns default model" "implement|sonnet|" "$RESULT"

# Test 2: Missing story returns defaults
echo "Test 2: Missing story returns defaults"
DECISION_CALLS_ENABLED="true"
RESULT=$(decision_call "US-999")
assert_eq "Returns defaults for missing story" "implement|sonnet|" "$RESULT"

# Note: Testing with live Claude calls would require mocking claude CLI.
# The above tests verify the fallback paths. Live decision calls are tested
# in the integration smoke test (Task 10).

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ $FAILED -eq 0 ] && exit 0 || exit 1
```

**Step 4: Run tests**

Run: `chmod +x tests/test-decision-call.sh && bash tests/test-decision-call.sh`
Expected: Both assertions pass. (Live decision call testing deferred to smoke test.)

**Step 5: Commit**

```bash
git add scripts/decision-call.sh tests/test-decision-call.sh
git commit -m "feat: add 1-shot decision call module

- decision-call.sh provides per-story orchestration decisions
- Calls Opus with story context, knowledge summary, error patterns
- Returns action|model|effort (pipe-separated)
- Falls back to v1.2.1 defaults on any error (timeout, parse failure)
- Records decisions to SQLite for audit trail
- Configurable via decision_calls config field"
```

---

## Task 5: Orchestrator Integration — Wire New Components into taskplex.sh

**Files:**
- Modify: `scripts/taskplex.sh` (multiple sections)

**Depends on:** Tasks 1-4

This is the largest task — it connects all the new modules to the main loop.

**Step 1: Add new config fields to `load_config()`**

In `scripts/taskplex.sh`, after line 502 (`CONFLICT_STRATEGY="abort"`), add new defaults:

```bash
  DECISION_CALLS_ENABLED=true
  DECISION_MODEL="opus"
  KNOWLEDGE_DB_PATH="knowledge.db"
  VALIDATE_ON_STOP=true
  MODEL_ROUTING="auto"
```

In the config file reading block (after line 523, `CONFLICT_STRATEGY=...`), add:

```bash
    DECISION_CALLS_ENABLED=$(jq -r '.decision_calls // true' "$CONFIG_FILE")
    DECISION_MODEL=$(jq -r '.decision_model // "opus"' "$CONFIG_FILE")
    KNOWLEDGE_DB_PATH=$(jq -r '.knowledge_db // "knowledge.db"' "$CONFIG_FILE")
    VALIDATE_ON_STOP=$(jq -r '.validate_on_stop // true' "$CONFIG_FILE")
    MODEL_ROUTING=$(jq -r '.model_routing // "auto"' "$CONFIG_FILE")
```

After line 536, add logging for new fields:

```bash
  [ "$DECISION_CALLS_ENABLED" = "true" ] && log "INIT" "Decision calls: enabled (model: $DECISION_MODEL)"
  log "INIT" "Knowledge DB: $KNOWLEDGE_DB_PATH"
  [ "$VALIDATE_ON_STOP" = "true" ] && log "INIT" "Inline validation: enabled"
```

**Step 2: Source new modules and initialize DB**

After line 448 (`KNOWLEDGE_FILE="$PROJECT_DIR/knowledge.md"`), add:

```bash
KNOWLEDGE_DB="$PROJECT_DIR/$KNOWLEDGE_DB_PATH"
```

But `KNOWLEDGE_DB_PATH` isn't loaded until `load_config()` runs. So instead, after line 897 (`load_config`), add:

```bash
# Set computed paths after config is loaded
KNOWLEDGE_DB="$PROJECT_DIR/$KNOWLEDGE_DB_PATH"

# Source v2.0 modules
source "$SCRIPT_DIR/knowledge-db.sh"
source "$SCRIPT_DIR/decision-call.sh"

# Initialize knowledge DB (create schema, migrate from knowledge.md)
init_knowledge_db "$KNOWLEDGE_DB"
if [ -f "$KNOWLEDGE_FILE" ] && [ ! -f "${KNOWLEDGE_DB}.migrated" ]; then
  log "INIT" "Migrating knowledge.md to SQLite..."
  migrate_knowledge_md "$KNOWLEDGE_DB" "$KNOWLEDGE_FILE"
  touch "${KNOWLEDGE_DB}.migrated"
  log "INIT" "Migration complete"
fi

# Export run ID for hook scripts
export TASKPLEX_RUN_ID="$RUN_ID"
```

**Step 3: Add decision call to main sequential loop**

After line 1526 (the `emit_event "story.start"` line), add the decision call block:

```bash
  # === v2.0: Decision Call ===
  DECISION_RESULT=$(decision_call "$CURRENT_STORY")
  DECISION_ACTION=$(echo "$DECISION_RESULT" | cut -d'|' -f1)
  DECISION_MODEL_PICK=$(echo "$DECISION_RESULT" | cut -d'|' -f2)
  DECISION_EFFORT=$(echo "$DECISION_RESULT" | cut -d'|' -f3)

  # Handle skip/rewrite decisions
  if [ "$DECISION_ACTION" = "skip" ]; then
    log "DECISION" "Decision: skip $CURRENT_STORY"
    update_story_status "$CURRENT_STORY" "skipped"
    log_progress "$CURRENT_STORY" "SKIPPED" "Decision call recommended skip"
    emit_event "story.skipped" "{\"reason\":\"decision_call\"}" "$CURRENT_STORY"
    continue
  fi

  # Apply model routing from decision call
  STORY_MODEL="$EXECUTION_MODEL"
  STORY_EFFORT="$EFFORT_LEVEL"
  if [ "$MODEL_ROUTING" = "auto" ]; then
    STORY_MODEL="$DECISION_MODEL_PICK"
    STORY_EFFORT="$DECISION_EFFORT"
  fi

  # Set effort env var for this story (Opus 4.6 only)
  if [ -n "$STORY_EFFORT" ] && [ "$STORY_MODEL" = "opus" ]; then
    export CLAUDE_CODE_EFFORT_LEVEL="$STORY_EFFORT"
  else
    unset CLAUDE_CODE_EFFORT_LEVEL
  fi
```

**Step 4: Use STORY_MODEL in claude -p invocation**

Replace the `--model "$EXECUTION_MODEL"` on line 1557 with `--model "$STORY_MODEL"`.

This appears in two places in the main loop:
1. Line 1557: main `claude -p` call
2. Line ~1639: retry `claude -p` call

Both should use `$STORY_MODEL` instead of `$EXECUTION_MODEL`.

**Step 5: Update `extract_learnings()` to use SQLite**

Replace the body of `extract_learnings()` (lines 173-226) to write to SQLite instead of knowledge.md:

```bash
extract_learnings() {
  local story_id="$1"
  local agent_output="$2"

  # Parse learnings array from structured JSON output
  local learnings
  learnings=$(echo "$agent_output" | jq -r '
    (if .result then (.result | if type == "string" then (try fromjson catch {}) else . end) else . end) |
    .learnings // [] | .[]
  ' 2>/dev/null)

  if [ -z "$learnings" ]; then
    learnings=$(echo "$agent_output" | grep -o '"learnings"[[:space:]]*:[[:space:]]*\[.*\]' | head -1 | jq -r '.[]' 2>/dev/null)
  fi

  if [ -z "$learnings" ]; then
    log "KNOWLEDGE" "No learnings found in agent output for $story_id"
    return 0
  fi

  # Write to SQLite (primary) and knowledge.md (backward compat)
  local added=0
  while IFS= read -r learning; do
    if [ -z "$learning" ]; then
      continue
    fi

    # Insert into SQLite
    if [ -f "$KNOWLEDGE_DB" ]; then
      insert_learning "$KNOWLEDGE_DB" "$story_id" "$RUN_ID" "$learning" 2>/dev/null || true
      added=$((added + 1))
    fi
  done <<< "$learnings"

  if [ "$added" -gt 0 ]; then
    log "KNOWLEDGE" "Added $added learnings from $story_id to knowledge DB"
  fi
}
```

**Step 6: Update `handle_error()` to record to SQLite**

After line 1183 (`log_progress "$story_id" "FAILED"...`), add:

```bash
  # Record error in SQLite knowledge store
  if [ -f "$KNOWLEDGE_DB" ]; then
    insert_error "$KNOWLEDGE_DB" "$story_id" "$RUN_ID" "$category" "$(echo "$output" | head -c 200)" "$attempts" 2>/dev/null || true
  fi
```

**Step 7: Mark errors resolved on story completion**

After line 1728 (`update_story_status "$CURRENT_STORY" "completed"`), add:

```bash
    # Mark errors as resolved in SQLite
    if [ -f "$KNOWLEDGE_DB" ]; then
      resolve_errors "$KNOWLEDGE_DB" "$CURRENT_STORY" 2>/dev/null || true
    fi
```

**Step 8: Update `generate_context_brief()` to be fallback-only**

At the top of `generate_context_brief()` (line 265), add:

```bash
  # v2.0: This function is now a fallback. The SubagentStart hook (inject-knowledge.sh)
  # handles context injection automatically. This only runs if hooks aren't installed.
  log "CONTEXT" "Using fallback context brief generation (hook preferred)"
```

**Step 9: Record run in SQLite**

After the existing `emit_run_start` call (line 1102), add:

```bash
# Record run in SQLite
if [ -f "$KNOWLEDGE_DB" ]; then
  local total_stories
  total_stories=$(jq '[.userStories[]] | length' "$PRD_FILE" 2>/dev/null || echo "0")
  insert_run "$KNOWLEDGE_DB" "$RUN_ID" "$BRANCH_NAME" "$PARALLEL_MODE" "$EXECUTION_MODEL" "$total_stories" 2>/dev/null || true
fi
```

**Step 10: Update run on completion**

In the `emit_run_end()` function (around line 1058), add SQLite update:

```bash
  # Update run in SQLite
  if [ -f "$KNOWLEDGE_DB" ]; then
    update_run "$KNOWLEDGE_DB" "$RUN_ID" "$completed" "$skipped" 2>/dev/null || true
  fi
```

**Step 11: Verify no syntax errors**

Run: `bash -n scripts/taskplex.sh`
Expected: No output (clean parse).

**Step 12: Commit**

```bash
git add scripts/taskplex.sh
git commit -m "feat: integrate v2.0 modules into orchestrator

- Source knowledge-db.sh and decision-call.sh at startup
- Initialize SQLite DB, auto-migrate from knowledge.md
- Add decision call between story selection and agent spawn
- Model routing: decision call picks model/effort per story
- extract_learnings() writes to SQLite instead of knowledge.md
- handle_error() records to SQLite error_history
- resolve_errors() on story completion
- Record/update run lifecycle in SQLite
- Export TASKPLEX_RUN_ID for hook scripts
- New config: decision_calls, decision_model, knowledge_db,
  validate_on_stop, model_routing"
```

---

## Task 6: Update Agent Prompts

**Files:**
- Modify: `agents/implementer.md`
- Modify: `scripts/prompt.md`

**Depends on:** Task 3 (SubagentStop hook — agents need to know about inline validation)

**Step 1: Update implementer.md**

In `agents/implementer.md`, replace the "Context Brief" section (lines 21-29) with:

```markdown
## Context Injection

Context is automatically injected by the SubagentStart hook. It includes:
- The story details and acceptance criteria
- Results of pre-implementation checks (grep output for existing code)
- Git diffs from completed dependency stories
- Codebase patterns and learnings from previous stories (SQLite knowledge store)
- Previous failure context and error history (if this is a retry)

**Use this information.** It saves you from redundant exploration.
```

After the "Quality Requirements" section (line 57), add:

```markdown
## Inline Validation

After you finish, your changes will be validated automatically by the SubagentStop hook. It runs the project's typecheck, build, and test commands. If validation fails:
- You will receive the error details as your next instruction
- Fix the issues in this same session (you have full context of your work)
- The validation will run again after you finish fixing

This means you do NOT need to run typecheck/build/test yourself — the hook handles it. Focus on implementation quality.
```

**Step 2: Update prompt.md**

In `scripts/prompt.md`, replace the "Context Brief" section (lines 5-14) with:

```markdown
## Context Injection

Context is automatically injected before this prompt. It includes:
- Story details and acceptance criteria from prd.json
- Results of `check_before_implementing` commands (existing code detection)
- Git diffs from completed dependency stories
- Codebase patterns and learnings from previous stories
- Previous failure context and error history (if this is a retry)

**Use this information.** It saves you from redundant exploration.
```

After the "Verification" section (line 75), add:

```markdown
## Inline Validation

After you finish, your changes are validated automatically by the SubagentStop hook. If validation fails, you will receive the errors and should fix them in this same session. You do not need to manually run typecheck/build/test commands — the hook handles this.
```

**Step 3: Commit**

```bash
git add agents/implementer.md scripts/prompt.md
git commit -m "feat: update agent prompts for v2.0 hook-based workflow

- Replace 'Context Brief' with 'Context Injection' (hook-based)
- Add 'Inline Validation' section explaining SubagentStop self-healing
- Agents no longer need to run typecheck/build/test manually"
```

---

## Task 7: Wizard Updates — New Config Fields

**Files:**
- Modify: `commands/start.md`

**Depends on:** Task 5 (new config fields exist)

**Step 1: Add v2.0 questions to Checkpoint 6**

In `commands/start.md`, after the existing monitor question block (around line 325), add a new question block:

```markdown
**After monitor question, ask about v2.0 intelligence features:**

Use AskUserQuestion:

Question: "Enable Smart Scaffold intelligence features? (decision calls cost ~$0.03/story via Opus)"
- Header: "Intelligence"
- multiSelect: false
- Options:
  - Label: "Full intelligence (Recommended)" | Description: "Decision calls + knowledge store + inline validation — ~$0.03/story overhead"
  - Label: "Knowledge store only" | Description: "SQLite knowledge + inline validation, no decision calls — $0 overhead"
  - Label: "Classic mode" | Description: "Exact v1.2.1 behavior — no decision calls, no inline validation, no SQLite"

For intelligence:
- "Full intelligence" → decision_calls: true, validate_on_stop: true, model_routing: "auto"
- "Knowledge store only" → decision_calls: false, validate_on_stop: true, model_routing: "fixed"
- "Classic mode" → decision_calls: false, validate_on_stop: false, model_routing: "fixed"
```

Update the config JSON template to include new fields:

```json
{
  "max_iterations": "[parsed from Q1]",
  "iteration_timeout": "[parsed from Q2]",
  "execution_mode": "[parsed from Q3]",
  "execution_model": "[parsed from Q4]",
  "effort_level": "[parsed from Q4]",
  "branch_prefix": "taskplex",
  "parallel_mode": "[parsed from Q5]",
  "max_parallel": "[parsed from Q5]",
  "worktree_setup_command": "[from Q5 follow-up]",
  "conflict_strategy": "abort",
  "decision_calls": "[from intelligence question]",
  "decision_model": "opus",
  "knowledge_db": "knowledge.db",
  "validate_on_stop": "[from intelligence question]",
  "model_routing": "[from intelligence question]"
}
```

**Step 2: Commit**

```bash
git add commands/start.md
git commit -m "feat: add v2.0 intelligence config to wizard

- New question at Checkpoint 6 for Smart Scaffold features
- Three modes: full intelligence, knowledge only, classic (v1.2.1)
- Config template includes decision_calls, validate_on_stop, model_routing"
```

---

## Task 8: Report Enrichment — SQLite-Backed Statistics

**Files:**
- Modify: `scripts/taskplex.sh` (`generate_report()` function)

**Depends on:** Task 5 (SQLite integration)

**Step 1: Enrich generate_report() with SQLite data**

In `scripts/taskplex.sh`, find `generate_report()` (starts around line 800). After the existing "Branch Status" section (around line 886), add:

```bash
  # === v2.0: SQLite Knowledge Store Statistics ===
  if [ -f "$KNOWLEDGE_DB" ]; then
    cat >> "$report_file" <<EOF

## Intelligence Report (v2.0)
EOF

    # Decision breakdown
    local decision_count
    decision_count=$(sqlite3 "$KNOWLEDGE_DB" "SELECT COUNT(*) FROM decisions WHERE run_id = '$RUN_ID';" 2>/dev/null || echo "0")
    if [ "$decision_count" -gt 0 ]; then
      cat >> "$report_file" <<EOF

### Decision Calls
- Total decisions: $decision_count
EOF
      sqlite3 "$KNOWLEDGE_DB" "
        SELECT action, model, COUNT(*) as count
        FROM decisions WHERE run_id = '$RUN_ID'
        GROUP BY action, model ORDER BY count DESC;
      " 2>/dev/null | while IFS='|' read -r action model count; do
        echo "- $action ($model): $count" >> "$report_file"
      done
    fi

    # Learnings
    local learning_count
    learning_count=$(sqlite3 "$KNOWLEDGE_DB" "SELECT COUNT(*) FROM learnings WHERE run_id = '$RUN_ID';" 2>/dev/null || echo "0")
    cat >> "$report_file" <<EOF

### Knowledge Store
- Learnings extracted this run: $learning_count
- Total active learnings: $(sqlite3 "$KNOWLEDGE_DB" "SELECT COUNT(*) FROM learnings WHERE ROUND(confidence * POWER(0.95, julianday('now') - julianday(created_at)), 3) > 0.3;" 2>/dev/null || echo "0")
EOF

    # Error patterns
    local error_count
    error_count=$(sqlite3 "$KNOWLEDGE_DB" "SELECT COUNT(*) FROM error_history WHERE run_id = '$RUN_ID';" 2>/dev/null || echo "0")
    if [ "$error_count" -gt 0 ]; then
      cat >> "$report_file" <<EOF

### Error Patterns
EOF
      sqlite3 "$KNOWLEDGE_DB" "
        SELECT category, COUNT(*) as count, SUM(resolved) as resolved
        FROM error_history WHERE run_id = '$RUN_ID'
        GROUP BY category ORDER BY count DESC;
      " 2>/dev/null | while IFS='|' read -r category count resolved; do
        echo "- $category: $count total, $resolved resolved" >> "$report_file"
      done
    fi
  fi
```

**Step 2: Verify no syntax errors**

Run: `bash -n scripts/taskplex.sh`
Expected: No output (clean parse).

**Step 3: Commit**

```bash
git add scripts/taskplex.sh
git commit -m "feat: enrich completion report with SQLite statistics

- Decision call breakdown (action, model, count)
- Learnings extracted this run and total active
- Error pattern analysis (category, count, resolved)"
```

---

## Task 9: Version Bump and Plugin Manifest

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `CLAUDE.md`

**Step 1: Bump plugin version to 2.0.0**

In `.claude-plugin/plugin.json`, change line 3:
```json
"version": "2.0.0",
```

Update description to mention v2.0 features:
```json
"description": "Resilient autonomous development with Smart Scaffold intelligence: 1-shot decision calls, SubagentStart/Stop hooks, SQLite knowledge store, inline validation with agent self-healing, and model routing. Successor to SDK Bridge.",
```

**Step 2: Update CLAUDE.md version header**

In `CLAUDE.md`, update line 3:
```
**Version 2.0.0** | Last Updated: 2026-02-17
```

**Step 3: Update version history in CLAUDE.md**

Add a v2.0.0 entry at the top of the "Version History" section (before v1.2.1):

```markdown
### v2.0.0 (2026-02-17)

**Smart Scaffold Architecture — Hook-Based Intelligence:**

**Added:**
- `scripts/knowledge-db.sh` — SQLite knowledge store helpers (schema, CRUD, confidence decay, migration)
- `scripts/decision-call.sh` — 1-shot Opus decision calls for per-story model/effort routing
- `hooks/inject-knowledge.sh` — SubagentStart hook: queries SQLite, runs pre-checks, injects context
- `hooks/validate-result.sh` — SubagentStop hook: runs typecheck/build/test, blocks agent on failure for self-healing
- `tests/` — Test suite for knowledge-db, inject-knowledge, validate-result, decision-call
- SQLite knowledge store (`knowledge.db`): learnings, file_patterns, error_history, decisions, runs tables
- Confidence decay at 5%/day (stale learnings auto-expire after ~30 days)
- One-time idempotent migration from `knowledge.md` to SQLite
- Model routing: decision call picks haiku/sonnet/opus per story based on complexity and history
- Enriched completion report with decision breakdown, knowledge stats, error patterns

**Changed:**
- `scripts/taskplex.sh` — sources v2.0 modules, decision call in main loop, SQLite integration
- `hooks/hooks.json` — added SubagentStart (inject-knowledge) and SubagentStop (validate-result) hook entries
- `agents/implementer.md` — updated for hook-based context injection and inline validation
- `scripts/prompt.md` — updated for hook-based workflow
- `commands/start.md` — added intelligence configuration question at Checkpoint 6
- `extract_learnings()` — writes to SQLite instead of knowledge.md
- `handle_error()` — records to SQLite error_history
- `generate_report()` — includes SQLite-backed intelligence report

**New Config Fields:**
- `decision_calls` (bool, default true) — enable 1-shot decision calls
- `decision_model` (string, default "opus") — model for decision calls
- `knowledge_db` (string, default "knowledge.db") — SQLite knowledge store path
- `validate_on_stop` (bool, default true) — enable SubagentStop inline validation
- `model_routing` (string, default "auto") — "auto" (decision call picks) or "fixed" (use execution_model)

**Backward Compatible:**
- Setting `decision_calls: false, validate_on_stop: false` gives exact v1.2.1 behavior
- Wizard offers "Classic mode" option for full backward compatibility
- knowledge.md auto-migrated to SQLite on first run
```

**Step 4: Commit**

```bash
git add .claude-plugin/plugin.json CLAUDE.md
git commit -m "chore: bump version to 2.0.0 — Smart Scaffold architecture

- Plugin manifest updated to v2.0.0
- CLAUDE.md version header and history updated
- Description reflects v2.0 intelligence features"
```

---

## Task 10: Integration Smoke Test

**Files:**
- Create: `tests/test-integration.sh`

**Depends on:** All previous tasks

This verifies the full flow works end-to-end (without live Claude calls — mocks the `claude` command).

**Step 1: Write the integration test**

Create `tests/test-integration.sh`:

```bash
#!/bin/bash
# Integration smoke test for TaskPlex v2.0
# Tests the full flow with a mock claude command
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

TABLE_COUNT=$(sqlite3 "$TEST_DIR/knowledge.db" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")
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

# Test 3: Hook scripts are executable
echo "Test 3: Hook scripts executable"
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
bash -n "$SCRIPT_DIR/scripts/decision-call.sh" 2>/dev/null

# Test 6: New config fields have defaults
echo "Test 6: Config defaults"
# Source relevant parts to check defaults
source "$SCRIPT_DIR/scripts/knowledge-db.sh"
# We can't run load_config without the full taskplex.sh environment,
# but we can check the script contains the new defaults
assert_contains "decision_calls default" "DECISION_CALLS_ENABLED=true" "$SCRIPT_DIR/scripts/taskplex.sh"
assert_contains "knowledge_db default" "KNOWLEDGE_DB_PATH=" "$SCRIPT_DIR/scripts/taskplex.sh"

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ $FAILED -eq 0 ] && exit 0 || exit 1
```

**Step 2: Run integration test**

Run: `chmod +x tests/test-integration.sh && bash tests/test-integration.sh`
Expected: All assertions pass.

**Step 3: Run all test suites**

Run: `bash tests/test-knowledge-db.sh && bash tests/test-inject-knowledge.sh && bash tests/test-validate-result.sh && bash tests/test-decision-call.sh && bash tests/test-integration.sh`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add tests/test-integration.sh
git commit -m "test: add integration smoke test for v2.0

- Verifies SQLite schema creation and migration
- Verifies CRUD operations work end-to-end
- Checks hook scripts exist and are registered
- Validates all scripts parse without syntax errors
- Confirms new config defaults are present"
```

---

## Summary of All Tasks

| Task | Description | Files | Dependencies |
|------|------------|-------|-------------|
| 1 | SQLite knowledge store helper | `scripts/knowledge-db.sh`, `tests/test-knowledge-db.sh` | None |
| 2 | SubagentStart knowledge injection hook | `hooks/inject-knowledge.sh`, `hooks/hooks.json`, `tests/test-inject-knowledge.sh` | Task 1 |
| 3 | SubagentStop inline validation hook | `hooks/validate-result.sh`, `hooks/hooks.json`, `tests/test-validate-result.sh` | None |
| 4 | Decision call module | `scripts/decision-call.sh`, `tests/test-decision-call.sh` | Task 1 |
| 5 | Orchestrator integration | `scripts/taskplex.sh` | Tasks 1-4 |
| 6 | Agent prompt updates | `agents/implementer.md`, `scripts/prompt.md` | Task 3 |
| 7 | Wizard config updates | `commands/start.md` | Task 5 |
| 8 | Report enrichment | `scripts/taskplex.sh` | Task 5 |
| 9 | Version bump + CLAUDE.md | `.claude-plugin/plugin.json`, `CLAUDE.md` | Tasks 1-8 |
| 10 | Integration smoke test | `tests/test-integration.sh` | All |

**Parallelizable:** Tasks 1, 3 can run in parallel. Tasks 2, 4 can run in parallel after Task 1. Tasks 6, 7, 8 can run in parallel after Task 5.

**Total new files:** 8 (4 scripts + 4 tests)
**Modified files:** 6 (taskplex.sh, hooks.json, implementer.md, prompt.md, start.md, plugin.json, CLAUDE.md)
**Estimated commits:** 10
