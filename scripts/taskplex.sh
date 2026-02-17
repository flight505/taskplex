#!/bin/bash
# TaskPlex - Long-running AI agent loop with process management
# Usage: ./taskplex.sh [max_iterations]

set -e

# ============================================================================
# Logging Functions (must be defined before any usage)
# ============================================================================

# Structured logging function with timestamp and prefix
log() {
  local prefix="$1"
  local message="$2"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%S)] [$prefix] $message" >&2
}

# ============================================================================
# Process Management & Cleanup
# ============================================================================

# Global variable to track current Claude process
CURRENT_CLAUDE_PID=""

# Cleanup function - called on any exit (normal, interrupt, error)
cleanup() {
  local exit_code=$?

  log "CLEANUP" "Cleanup triggered (exit code: $exit_code)"

  # Only clean up OUR child process, not others
  if [ -n "$CURRENT_CLAUDE_PID" ]; then
    log "CLEANUP" "Checking if Claude process $CURRENT_CLAUDE_PID is running..."
    if ps -p "$CURRENT_CLAUDE_PID" > /dev/null 2>&1; then
      log "CLEANUP" "Terminating Claude process $CURRENT_CLAUDE_PID..."
      echo ""
      echo "⚠️  Shutting down this TaskPlex instance..."

      # Try graceful termination first
      kill -TERM "$CURRENT_CLAUDE_PID" 2>/dev/null || true
      sleep 2

      # Force kill if still running
      if ps -p "$CURRENT_CLAUDE_PID" > /dev/null 2>&1; then
        log "CLEANUP" "Process still running, force killing..."
        kill -9 "$CURRENT_CLAUDE_PID" 2>/dev/null || true
      else
        log "CLEANUP" "Process terminated gracefully"
      fi
    else
      log "CLEANUP" "Claude process already terminated"
    fi
  else
    log "CLEANUP" "No active Claude process to clean up"
  fi

  # Emit run end to monitor (if running)
  if type emit_run_end >/dev/null 2>&1; then
    emit_run_end 2>/dev/null || true
  fi

  # Stop monitor if we started it
  if [ -f "$PROJECT_DIR/.claude/taskplex-monitor.pid" ]; then
    MONITOR_PID=$(cat "$PROJECT_DIR/.claude/taskplex-monitor.pid" 2>/dev/null)
    if [ -n "$MONITOR_PID" ] && kill -0 "$MONITOR_PID" 2>/dev/null; then
      log "CLEANUP" "Monitor still running (PID: $MONITOR_PID) — leaving it for review"
    fi
  fi

  # Clean up temp files from this process
  rm -f /tmp/taskplex-$$-*.txt /tmp/taskplex-$$-*.md /tmp/taskplex-parallel-$$-*.json /tmp/taskplex-prompt-$$-*.md /tmp/taskplex-context-$$-*.md

  # Clean up parallel worktrees if in parallel mode
  if [ "$PARALLEL_MODE" = "parallel" ] && type cleanup_all_worktrees >/dev/null 2>&1; then
    cleanup_all_worktrees
  fi

  # Clean up THIS instance's PID file only (per-branch)
  if [ -f "$PRD_FILE" ]; then
    BRANCH_NAME=$(jq -r '.branchName // "unknown"' "$PRD_FILE" 2>/dev/null || echo "unknown")
    PID_FILE="$PROJECT_DIR/.claude/taskplex-${BRANCH_NAME}.pid"
    log "CLEANUP" "Checking for PID file: $PID_FILE"
    if [ -f "$PID_FILE" ]; then
      log "CLEANUP" "Removing PID file: $PID_FILE"
      rm -f "$PID_FILE"
    fi
  fi

  log "CLEANUP" "Cleanup complete"
  exit $exit_code
}

# Register cleanup on ALL exit scenarios
log "INIT" "Registering signal handlers (EXIT, INT, TERM, HUP)"
trap cleanup EXIT INT TERM HUP

# Trim progress.txt file if it exceeds size limit
trim_progress() {
  local max_size=512000  # 500KB limit

  if [ ! -f "$PROGRESS_FILE" ]; then
    return 0
  fi

  local current_size=$(wc -c < "$PROGRESS_FILE" 2>/dev/null || echo "0")

  if [ "$current_size" -gt "$max_size" ]; then
    log "INIT" "Progress file exceeds ${max_size} bytes, trimming old entries..."

    # Keep last 200 lines (operational log is compact now)
    local temp_file=$(mktemp)
    tail -200 "$PROGRESS_FILE" > "$temp_file" && mv "$temp_file" "$PROGRESS_FILE"

    log "INIT" "Progress file trimmed: $(wc -c < "$PROGRESS_FILE") bytes remaining"
  fi
}

# ============================================================================
# Knowledge Architecture (v1.1)
# ============================================================================

# NOTE: KNOWLEDGE_FILE is set after PROJECT_DIR in the Configuration section below.

# Write operational log entry (Layer 1: orchestrator-only)
log_progress() {
  local story_id="$1"
  local event="$2"
  local details="$3"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%S)] [$story_id] $event - $details" >> "$PROGRESS_FILE"
}

# Trim knowledge.md to max 100 lines (Layer 2: orchestrator-curated)
trim_knowledge() {
  if [ ! -f "$KNOWLEDGE_FILE" ]; then
    return 0
  fi

  local line_count=$(wc -l < "$KNOWLEDGE_FILE" 2>/dev/null || echo "0")

  if [ "$line_count" -gt 100 ]; then
    log "KNOWLEDGE" "knowledge.md exceeds 100 lines ($line_count), trimming oldest entries..."

    # Keep "## Codebase Patterns" and "## Environment Notes" sections (top),
    # trim oldest entries from "## Recent Learnings" (bottom)
    local temp_file=$(mktemp)

    # Find where "## Recent Learnings" starts
    local learnings_line=$(grep -n "^## Recent Learnings" "$KNOWLEDGE_FILE" | head -1 | cut -d: -f1)

    if [ -n "$learnings_line" ]; then
      # Keep everything before Recent Learnings + last entries to fit 100 lines
      local header_lines=$((learnings_line - 1))
      local available_lines=$((100 - header_lines - 1))  # -1 for the section header itself

      # Header sections
      head -"$header_lines" "$KNOWLEDGE_FILE" > "$temp_file"
      echo "## Recent Learnings" >> "$temp_file"

      # Keep newest learnings (from bottom)
      local learnings_start=$((learnings_line + 1))
      tail -n +"$learnings_start" "$KNOWLEDGE_FILE" | tail -"$available_lines" >> "$temp_file"
    else
      # No sections found, just keep last 100 lines
      tail -100 "$KNOWLEDGE_FILE" > "$temp_file"
    fi

    mv "$temp_file" "$KNOWLEDGE_FILE"
    log "KNOWLEDGE" "knowledge.md trimmed to $(wc -l < "$KNOWLEDGE_FILE") lines"
  fi
}

# Extract learnings from structured agent output (v2.0: writes to SQLite, backward compat to knowledge.md)
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

# Add environment/dependency warning to knowledge.md
add_knowledge_warning() {
  local story_id="$1"
  local category="$2"
  local error_msg="$3"

  if [ ! -f "$KNOWLEDGE_FILE" ]; then
    cat > "$KNOWLEDGE_FILE" <<'KNOWLEDGE_INIT'
## Codebase Patterns

## Environment Notes

## Recent Learnings
KNOWLEDGE_INIT
  fi

  # Add warning to Environment Notes section
  local warning="- [$story_id] ($category) $error_msg"

  # Check for duplicate
  if ! grep -qF "$error_msg" "$KNOWLEDGE_FILE" 2>/dev/null; then
    # Insert after "## Environment Notes" line
    local env_line=$(grep -n "^## Environment Notes" "$KNOWLEDGE_FILE" | head -1 | cut -d: -f1)
    if [ -n "$env_line" ]; then
      local temp_file=$(mktemp)
      head -"$env_line" "$KNOWLEDGE_FILE" > "$temp_file"
      echo "$warning" >> "$temp_file"
      tail -n +"$((env_line + 1))" "$KNOWLEDGE_FILE" >> "$temp_file"
      mv "$temp_file" "$KNOWLEDGE_FILE"
    else
      echo "$warning" >> "$KNOWLEDGE_FILE"
    fi
    log "KNOWLEDGE" "Added $category warning for $story_id"
  fi
}

# Generate per-story context brief (Layer 3: ephemeral)
# v2.0: This function is now a fallback. The SubagentStart hook (inject-knowledge.sh)
# handles context injection automatically. This only runs if hooks aren't installed.
generate_context_brief() {
  local story_id="$1"
  local retry_context="${2:-}"
  local brief_file="/tmp/taskplex-context-$$-${story_id}.md"

  log "CONTEXT" "Using fallback context brief generation (hook preferred)"

  cat > "$brief_file" <<BRIEF_HEADER
# Context Brief for $story_id
Generated by TaskPlex orchestrator at $(date -u +%Y-%m-%dT%H:%M:%S)

BRIEF_HEADER

  # 1. Story details from prd.json
  echo "## Story Details" >> "$brief_file"
  echo '```json' >> "$brief_file"
  jq --arg id "$story_id" '.userStories[] | select(.id == $id)' "$PRD_FILE" >> "$brief_file" 2>/dev/null
  echo '```' >> "$brief_file"
  echo "" >> "$brief_file"

  # 2. Run check_before_implementing commands, capture results
  local check_cmds
  check_cmds=$(jq -r --arg id "$story_id" '
    .userStories[] | select(.id == $id) | .check_before_implementing // [] | .[]
  ' "$PRD_FILE" 2>/dev/null)

  if [ -n "$check_cmds" ]; then
    echo "## Pre-Implementation Check Results" >> "$brief_file"
    while IFS= read -r cmd; do
      if [ -n "$cmd" ]; then
        echo "### \`$cmd\`" >> "$brief_file"
        echo '```' >> "$brief_file"
        eval "$cmd" >> "$brief_file" 2>&1 || echo "(command returned non-zero)" >> "$brief_file"
        echo '```' >> "$brief_file"
        echo "" >> "$brief_file"
      fi
    done <<< "$check_cmds"
  fi

  # 3. Git diffs from completed dependency stories
  local dep_ids
  dep_ids=$(jq -r --arg id "$story_id" '
    .userStories[] | select(.id == $id) | .depends_on // [] | .[]
  ' "$PRD_FILE" 2>/dev/null)

  if [ -n "$dep_ids" ]; then
    echo "## Dependency Story Changes" >> "$brief_file"
    while IFS= read -r dep_id; do
      if [ -n "$dep_id" ]; then
        # Find the commit for this dependency
        local dep_commit
        dep_commit=$(git log --oneline --grep="feat($dep_id)" -1 --format="%H" 2>/dev/null)
        if [ -n "$dep_commit" ]; then
          echo "### $dep_id (commit: ${dep_commit:0:8})" >> "$brief_file"
          echo '```' >> "$brief_file"
          git diff "${dep_commit}^".."${dep_commit}" --stat >> "$brief_file" 2>/dev/null || echo "(diff not available)" >> "$brief_file"
          echo '```' >> "$brief_file"
          echo "" >> "$brief_file"
        else
          echo "### $dep_id — no commit found" >> "$brief_file"
          echo "" >> "$brief_file"
        fi
      fi
    done <<< "$dep_ids"
  fi

  # 4. Relevant knowledge from knowledge.md
  if [ -f "$KNOWLEDGE_FILE" ]; then
    echo "## Project Knowledge" >> "$brief_file"
    cat "$KNOWLEDGE_FILE" >> "$brief_file"
    echo "" >> "$brief_file"
  fi

  # 5. Previous failure context (if retry)
  if [ -n "$retry_context" ]; then
    echo "## Previous Failure Context" >> "$brief_file"
    echo "$retry_context" >> "$brief_file"
    echo "" >> "$brief_file"
  fi

  echo "$brief_file"
}

# Parse structured agent output and extract fields
parse_agent_output() {
  local output="$1"

  # Try to extract the structured JSON from the output
  # The agent outputs it as the last JSON block in its response
  local structured
  structured=$(echo "$output" | jq -r '
    if .result then
      .result | if type == "string" then . else (. | tostring) end
    else
      . | tostring
    end
  ' 2>/dev/null)

  # Try to extract JSON block from text output
  if [ -n "$structured" ]; then
    # Look for the last JSON object containing "story_id"
    echo "$structured" | grep -o '{[^}]*"story_id"[^}]*}' | tail -1 2>/dev/null || echo "{}"
  else
    echo "{}"
  fi
}

# Extract retry_hint from structured output
get_retry_hint() {
  local output="$1"
  local structured
  structured=$(parse_agent_output "$output")
  echo "$structured" | jq -r '.retry_hint // empty' 2>/dev/null
}

# ============================================================================
# Authentication Check
# ============================================================================

# Check authentication (OAuth preferred, API key as fallback)
if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  # OAuth authentication (primary - Max subscribers)
  unset ANTHROPIC_API_KEY ANTHROPIC_ADMIN_KEY
  echo "✓ Using Claude Code OAuth authentication"

elif [ -n "$ANTHROPIC_API_KEY" ]; then
  # API key fallback
  echo "✓ Using Anthropic API Key authentication"
  echo "💡 Tip: Max subscribers can use 'claude setup-token' for better rate limits"

else
  # No authentication found
  echo "Error: No authentication configured"
  echo ""
  echo "TaskPlex requires authentication:"
  echo ""
  echo "Recommended: OAuth Token (Claude Max subscribers)"
  echo "  1. Run: claude setup-token"
  echo "  2. export CLAUDE_CODE_OAUTH_TOKEN='your-token'"
  echo ""
  echo "Alternative: API Key"
  echo "  1. Get from: https://console.anthropic.com/settings/keys"
  echo "  2. export ANTHROPIC_API_KEY='your-key'"
  echo ""
  exit 1
fi

# ============================================================================
# Timeout Command Detection
# ============================================================================

# Detect which timeout command is available (GNU coreutils)
# macOS with Homebrew coreutils: gtimeout
# Linux: timeout
if command -v gtimeout &> /dev/null; then
  TIMEOUT_CMD="gtimeout"
elif command -v timeout &> /dev/null; then
  TIMEOUT_CMD="timeout"
else
  echo "Error: timeout command not found (GNU coreutils required)"
  echo ""
  echo "Install coreutils:"
  echo "  macOS: brew install coreutils"
  echo "  Linux: sudo apt-get install coreutils"
  echo ""
  exit 1
fi

# ============================================================================
# Configuration
# ============================================================================

MAX_ITERATIONS=${1:-10}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Plugin root is parent of scripts directory
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Work in the user's project directory (current working directory)
PROJECT_DIR="$(pwd)"
PRD_FILE="$PROJECT_DIR/prd.json"
PROGRESS_FILE="$PROJECT_DIR/progress.txt"
ARCHIVE_DIR="$PROJECT_DIR/archive"
LAST_BRANCH_FILE="$PROJECT_DIR/.last-branch"
CONFIG_FILE="$PROJECT_DIR/.claude/taskplex.config.json"
KNOWLEDGE_FILE="$PROJECT_DIR/knowledge.md"

# Validate PRD file
validate_prd() {
  if [ ! -f "$PRD_FILE" ]; then
    log "ERROR" "prd.json not found at $PRD_FILE"
    echo "" >&2
    echo "TaskPlex requires a valid prd.json file in the project root." >&2
    echo "Run 'claude /prd-generator' to create one." >&2
    echo "" >&2
    exit 1
  fi

  # Validate JSON syntax
  if ! jq empty "$PRD_FILE" 2>/dev/null; then
    log "ERROR" "prd.json is not valid JSON"
    log "ERROR" "File: $PRD_FILE"
    exit 1
  fi

  # Validate required fields
  local user_stories_count=$(jq -r '.userStories | length' "$PRD_FILE" 2>/dev/null || echo "0")
  if [ "$user_stories_count" -eq 0 ]; then
    log "ERROR" "prd.json must contain a userStories array with at least one entry"
    exit 1
  fi

  local branch_name=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null)
  if [ -z "$branch_name" ]; then
    log "ERROR" "prd.json must contain a branchName field"
    exit 1
  fi

  log "INIT" "PRD validation passed: $user_stories_count stories found"
}

# Load configuration from JSON config file
load_config() {
  # Default values
  ITERATION_TIMEOUT=900
  EXECUTION_MODE="foreground"
  EXECUTION_MODEL="sonnet"
  EFFORT_LEVEL=""
  BRANCH_PREFIX="taskplex"
  MAX_RETRIES_PER_STORY=2
  MERGE_ON_COMPLETE=false
  MAX_TURNS=200
  TEST_COMMAND=""
  BUILD_COMMAND=""
  TYPECHECK_COMMAND=""
  PARALLEL_MODE="sequential"
  MAX_PARALLEL=3
  WORKTREE_DIR=""
  WORKTREE_SETUP_COMMAND=""
  CONFLICT_STRATEGY="abort"
  DECISION_CALLS_ENABLED=true
  DECISION_MODEL="opus"
  KNOWLEDGE_DB_PATH="knowledge.db"
  VALIDATE_ON_STOP=true
  MODEL_ROUTING="auto"

  # Load from config file if it exists
  if [ -f "$CONFIG_FILE" ]; then
    log "INIT" "Reading configuration from $CONFIG_FILE"

    ITERATION_TIMEOUT=$(jq -r '.iteration_timeout // 900' "$CONFIG_FILE")
    EXECUTION_MODE=$(jq -r '.execution_mode // "foreground"' "$CONFIG_FILE")
    EXECUTION_MODEL=$(jq -r '.execution_model // "sonnet"' "$CONFIG_FILE")
    EFFORT_LEVEL=$(jq -r '.effort_level // ""' "$CONFIG_FILE")
    BRANCH_PREFIX=$(jq -r '.branch_prefix // "taskplex"' "$CONFIG_FILE")
    MAX_RETRIES_PER_STORY=$(jq -r '.max_retries_per_story // 2' "$CONFIG_FILE")
    MERGE_ON_COMPLETE=$(jq -r '.merge_on_complete // false' "$CONFIG_FILE")
    MAX_TURNS=$(jq -r '.max_turns // 200' "$CONFIG_FILE")
    TEST_COMMAND=$(jq -r '.test_command // ""' "$CONFIG_FILE")
    BUILD_COMMAND=$(jq -r '.build_command // ""' "$CONFIG_FILE")
    TYPECHECK_COMMAND=$(jq -r '.typecheck_command // ""' "$CONFIG_FILE")
    PARALLEL_MODE=$(jq -r '.parallel_mode // "sequential"' "$CONFIG_FILE")
    MAX_PARALLEL=$(jq -r '.max_parallel // 3' "$CONFIG_FILE")
    WORKTREE_DIR=$(jq -r '.worktree_dir // ""' "$CONFIG_FILE")
    WORKTREE_SETUP_COMMAND=$(jq -r '.worktree_setup_command // ""' "$CONFIG_FILE")
    CONFLICT_STRATEGY=$(jq -r '.conflict_strategy // "abort"' "$CONFIG_FILE")
    DECISION_CALLS_ENABLED=$(jq -r 'if .decision_calls == false then "false" elif .decision_calls == true then "true" else "true" end' "$CONFIG_FILE")
    DECISION_MODEL=$(jq -r '.decision_model // "opus"' "$CONFIG_FILE")
    KNOWLEDGE_DB_PATH=$(jq -r '.knowledge_db // "knowledge.db"' "$CONFIG_FILE")
    VALIDATE_ON_STOP=$(jq -r 'if .validate_on_stop == false then "false" elif .validate_on_stop == true then "true" else "true" end' "$CONFIG_FILE")
    MODEL_ROUTING=$(jq -r '.model_routing // "auto"' "$CONFIG_FILE")

    log "INIT" "Configuration loaded from $CONFIG_FILE"
  else
    log "INIT" "No config file found, using defaults"
  fi

  # Log key configuration values
  log "INIT" "Iteration timeout: ${ITERATION_TIMEOUT}s ($(($ITERATION_TIMEOUT / 60)) minutes)"
  log "INIT" "Execution mode: $EXECUTION_MODE"
  log "INIT" "Execution model: $EXECUTION_MODEL"
  [ -n "$EFFORT_LEVEL" ] && log "INIT" "Effort level: $EFFORT_LEVEL"
  log "INIT" "Parallel mode: $PARALLEL_MODE"
  [ "$PARALLEL_MODE" = "parallel" ] && log "INIT" "Max parallel: $MAX_PARALLEL"
  [ "$DECISION_CALLS_ENABLED" = "true" ] && log "INIT" "Decision calls: enabled (model: $DECISION_MODEL)"
  log "INIT" "Knowledge DB: $KNOWLEDGE_DB_PATH"
  [ "$VALIDATE_ON_STOP" = "true" ] && log "INIT" "Inline validation: enabled"
}

# Update story status in prd.json
update_story_status() {
  local story_id="$1"
  local new_status="$2"
  local error_msg="${3:-}"
  local error_category="${4:-}"

  if [ ! -f "$PRD_FILE" ]; then
    log "ERROR" "Cannot update story status: prd.json not found"
    return 1
  fi

  TEMP_PRD=$(mktemp)

  if [ "$new_status" = "in_progress" ]; then
    # Set status to in_progress and increment attempts
    jq --arg id "$story_id" --arg status "$new_status" '
      .userStories |= map(
        if .id == $id then
          .status = $status |
          .attempts = (.attempts // 0) + 1
        else . end
      )
    ' "$PRD_FILE" > "$TEMP_PRD" && mv "$TEMP_PRD" "$PRD_FILE"

  elif [ "$new_status" = "completed" ]; then
    # Set status to completed, passes to true, clear errors
    jq --arg id "$story_id" --arg status "$new_status" '
      .userStories |= map(
        if .id == $id then
          .status = $status |
          .passes = true |
          .last_error = null |
          .last_error_category = null
        else . end
      )
    ' "$PRD_FILE" > "$TEMP_PRD" && mv "$TEMP_PRD" "$PRD_FILE"

  elif [ "$new_status" = "skipped" ]; then
    # Set status to skipped, preserve error information
    jq --arg id "$story_id" --arg status "$new_status" \
       --arg error "$error_msg" --arg category "$error_category" '
      .userStories |= map(
        if .id == $id then
          .status = $status |
          .last_error = (if $error != "" then $error else .last_error end) |
          .last_error_category = (if $category != "" then $category else .last_error_category end)
        else . end
      )
    ' "$PRD_FILE" > "$TEMP_PRD" && mv "$TEMP_PRD" "$PRD_FILE"

  else
    log "ERROR" "Unknown status: $new_status"
    rm -f "$TEMP_PRD"
    return 1
  fi

  log "STATUS" "Story $story_id set to $new_status"
}

# Get next eligible task (incomplete, dependencies satisfied, not skipped)
get_next_task() {
  if [ ! -f "$PRD_FILE" ]; then
    log "ERROR" "Cannot get next task: prd.json not found"
    return 1
  fi

  # Use jq to find the first incomplete story with all dependencies satisfied
  # sorted by priority (lowest number = highest priority)
  local next_task
  next_task=$(jq -r '
    # First, get all stories for dependency checking
    .userStories as $all_stories |

    # Filter to incomplete, non-skipped stories
    .userStories[] |
    select(.passes == false and .status != "skipped") |

    # Check if all dependencies are satisfied
    select(
      # No dependencies, or empty array, or all deps have passes=true
      (.depends_on == null) or
      (.depends_on | length == 0) or
      (
        .depends_on | all(. as $dep_id |
          $all_stories | map(select(.id == $dep_id and .passes == true)) | length > 0
        )
      )
    ) |

    # Return ID with priority for sorting
    {id: .id, priority: .priority}
  ' "$PRD_FILE" | jq -s 'sort_by(.priority) | .[0].id // empty' 2>/dev/null)

  if [ -z "$next_task" ]; then
    # Check if there are any incomplete stories at all
    local incomplete_count
    incomplete_count=$(jq '[.userStories[] | select(.passes == false and .status != "skipped")] | length' "$PRD_FILE")

    if [ "$incomplete_count" -eq 0 ]; then
      # All stories complete or skipped
      return 1
    else
      # Stories exist but all are blocked by dependencies
      log "ERROR" "All remaining stories are blocked by unmet dependencies"
      return 2
    fi
  fi

  echo "$next_task"
  return 0
}

# Setup git branch - create or checkout the branch from prd.json
setup_branch() {
  local branch_name
  branch_name=$(jq -r '.branchName // empty' "$PRD_FILE")

  if [ -z "$branch_name" ]; then
    log "ERROR" "No branchName found in prd.json"
    return 1
  fi

  # Get current branch
  local current_branch
  current_branch=$(git branch --show-current 2>/dev/null || echo "")

  if [ "$current_branch" = "$branch_name" ]; then
    log "INIT" "Already on branch: $branch_name"
    return 0
  fi

  # Check if branch exists locally
  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    # Branch exists - check it out
    log "INIT" "Checking out existing branch: $branch_name"
    if git checkout "$branch_name" 2>&1; then
      log "INIT" "Switched to branch: $branch_name"
      return 0
    else
      log "ERROR" "Failed to checkout branch: $branch_name"
      return 1
    fi
  else
    # Branch doesn't exist - create it
    log "INIT" "Creating new branch: $branch_name"
    if git checkout -b "$branch_name" 2>&1; then
      log "INIT" "Created and switched to branch: $branch_name"
      return 0
    else
      log "ERROR" "Failed to create branch: $branch_name"
      return 1
    fi
  fi
}

# Commit story changes
commit_story() {
  local story_id="$1"
  local story_title="$2"

  if [ -z "$story_id" ] || [ -z "$story_title" ]; then
    log "ERROR" "commit_story requires story_id and story_title"
    return 1
  fi

  # Check if there are any changes to commit
  if [ -z "$(git status --porcelain)" ]; then
    log "COMMIT" "No changes to commit for $story_id"
    return 0
  fi

  # Stage tracked file changes (implementer should have staged, but fallback)
  # Use git add -u (update tracked files) as safety - don't use git add -A which could commit secrets
  if ! git diff --cached --quiet 2>/dev/null; then
    log "COMMIT" "Files already staged by implementer"
  else
    log "COMMIT" "Staging tracked file changes (fallback)"
    git add -u
  fi

  # Commit with conventional commit format
  local commit_msg="feat($story_id): $story_title"

  if git commit -m "$commit_msg" 2>&1; then
    log "COMMIT" "Committed: $commit_msg"
    return 0
  else
    log "ERROR" "Failed to commit changes for $story_id"
    return 1
  fi
}

# Merge feature branch to main
merge_to_main() {
  local branch_name
  branch_name=$(jq -r '.branchName // empty' "$PRD_FILE")

  local project_name
  project_name=$(jq -r '.project // "TaskPlex"' "$PRD_FILE")

  local description
  description=$(jq -r '.description // ""' "$PRD_FILE")

  if [ -z "$branch_name" ]; then
    log "ERROR" "No branchName found in prd.json"
    return 1
  fi

  # Check merge_on_complete config
  if [ "$MERGE_ON_COMPLETE" != "true" ]; then
    log "MERGE" "Merge skipped (merge_on_complete is false in config)"
    log "MERGE" "Feature branch '$branch_name' is ready for manual merge"
    return 0
  fi

  # Get current branch
  local current_branch
  current_branch=$(git branch --show-current 2>/dev/null || echo "")

  if [ "$current_branch" != "$branch_name" ]; then
    log "ERROR" "Not on expected branch. Current: $current_branch, Expected: $branch_name"
    return 1
  fi

  # Checkout main branch
  log "MERGE" "Checking out main branch..."
  if ! git checkout main 2>&1; then
    log "ERROR" "Failed to checkout main branch"
    log "MERGE" "Staying on branch: $branch_name"
    git checkout "$branch_name" 2>/dev/null
    return 1
  fi

  # Merge with --no-ff to preserve feature branch history
  local merge_msg="feat: $project_name - $description"
  log "MERGE" "Merging $branch_name into main with --no-ff..."

  if git merge --no-ff "$branch_name" -m "$merge_msg" 2>&1; then
    log "MERGE" "✓ Successfully merged $branch_name into main"
    return 0
  else
    # Merge conflict
    log "ERROR" "Merge conflict detected!"
    log "MERGE" "Branch '$branch_name' has conflicts with main"
    log "MERGE" "Please resolve conflicts manually:"
    echo "  1. git status (see conflicted files)" >&2
    echo "  2. Edit files to resolve conflicts" >&2
    echo "  3. git add <resolved-files>" >&2
    echo "  4. git commit" >&2
    echo "" >&2
    # Abort merge to leave clean state
    git merge --abort 2>/dev/null
    # Go back to feature branch
    git checkout "$branch_name" 2>/dev/null
    return 1
  fi
}

# Generate completion report at end of execution
generate_report() {
  local report_file="$PROJECT_DIR/.claude/taskplex-report.md"
  local feature_name branch_name date_str

  feature_name=$(jq -r '.project // "TaskPlex"' "$PRD_FILE")
  branch_name=$(jq -r '.branchName // "unknown"' "$PRD_FILE")
  date_str=$(date +%Y-%m-%d)

  # Calculate elapsed time
  local elapsed_seconds=$(($(date +%s) - START_TIME))
  local elapsed_minutes=$((elapsed_seconds / 60))

  # Count stories by status
  local total_stories completed_stories skipped_stories blocked_stories
  total_stories=$(jq '[.userStories[]] | length' "$PRD_FILE")
  completed_stories=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE")
  skipped_stories=$(jq '[.userStories[] | select(.status == "skipped")] | length' "$PRD_FILE")
  blocked_stories=$(jq '[.userStories[] | select(.passes == false and .status != "skipped")] | length' "$PRD_FILE")

  # Get branch commit count (commits on feature branch not in main)
  local commit_count
  if git rev-parse --verify main > /dev/null 2>&1; then
    commit_count=$(git rev-list --count main..HEAD 2>/dev/null || echo "0")
  else
    commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
  fi

  # Ensure .claude directory exists
  mkdir -p "$PROJECT_DIR/.claude"

  # Generate report
  cat > "$report_file" <<EOF
# TaskPlex Completion Report
**Feature:** $feature_name
**Branch:** $branch_name
**Date:** $date_str

## Summary
- Stories completed: $completed_stories/$total_stories
- Stories skipped: $skipped_stories/$total_stories
- Stories blocked: $blocked_stories/$total_stories
- Execution mode: $PARALLEL_MODE
- Total time: $elapsed_minutes minutes

## Completed Stories
EOF

  # Add completed stories
  jq -r '.userStories[] | select(.passes == true) | "- ✅ \(.id): \(.title) (\(.attempts // 1) attempt\(if .attempts != 1 then "s" else "" end))"' "$PRD_FILE" >> "$report_file"

  # Add skipped stories section if any
  if [ "$skipped_stories" -gt 0 ]; then
    cat >> "$report_file" <<EOF

## Skipped Stories
EOF
    jq -r '.userStories[] | select(.status == "skipped") | "- ⏭️ \(.id): \(.title)\n  - Category: \(.last_error_category // "unknown")\n  - Error: \(.last_error // "No error message")\n  - Action needed: Review and fix manually"' "$PRD_FILE" >> "$report_file"
  fi

  # Add blocked stories section if any
  if [ "$blocked_stories" -gt 0 ]; then
    cat >> "$report_file" <<EOF

## Blocked Stories
EOF
    jq -r '.userStories[] | select(.passes == false and .status != "skipped") | "- 🔴 \(.id): \(.title)\n  - Status: \(.status // "pending")\n  - Dependencies: \(if .depends_on then (.depends_on | join(", ")) else "None" end)"' "$PRD_FILE" >> "$report_file"
  fi

  # Add branch status section
  cat >> "$report_file" <<EOF

## Branch Status
- Branch \`$branch_name\` is ready for review
- $commit_count commits on branch
EOF

  # Add merge command if on feature branch
  local current_branch
  current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
  if [ "$current_branch" = "$branch_name" ]; then
    cat >> "$report_file" <<EOF
- Merge command: \`git checkout main && git merge --no-ff $branch_name\`
EOF
  else
    cat >> "$report_file" <<EOF
- Already merged to main
EOF
  fi

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
    local active_learnings
    active_learnings=$(sqlite3 "$KNOWLEDGE_DB" "SELECT COUNT(*) FROM learnings WHERE ROUND(confidence * POWER(0.95, julianday('now') - julianday(created_at)), 3) > 0.3;" 2>/dev/null || echo "0")
    cat >> "$report_file" <<EOF

### Knowledge Store
- Learnings extracted this run: $learning_count
- Total active learnings: $active_learnings
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

  log "INIT" "Completion report generated: $report_file"
  echo ""
  echo "📝 Report generated: $report_file"
}

# Validate PRD before proceeding
validate_prd

# Load configuration
load_config

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

# Export effort level as env var for Claude CLI (Opus 4.6 adaptive reasoning)
if [ -n "$EFFORT_LEVEL" ] && [ "$EXECUTION_MODEL" = "opus" ]; then
  export CLAUDE_CODE_EFFORT_LEVEL="$EFFORT_LEVEL"
  log "INIT" "CLAUDE_CODE_EFFORT_LEVEL=$EFFORT_LEVEL (Opus 4.6 adaptive reasoning)"
fi

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "taskplex/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^taskplex/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$KNOWLEDGE_FILE" ] && cp "$KNOWLEDGE_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"

    # Reset progress file for new run
    echo "# TaskPlex Operational Log" > "$PROGRESS_FILE"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%S)] [INIT] New run started" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# TaskPlex Operational Log" > "$PROGRESS_FILE"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%S)] [INIT] New run started" >> "$PROGRESS_FILE"
fi

# ============================================================================
# Per-Branch Instance Check
# ============================================================================

# Extract branch name from PRD for per-branch PID file
BRANCH_NAME=$(jq -r '.branchName // "unknown"' "$PRD_FILE" 2>/dev/null || echo "unknown")
INSTANCE_PID_FILE="$PROJECT_DIR/.claude/taskplex-${BRANCH_NAME}.pid"

log "INIT" "Branch: $BRANCH_NAME"
log "INIT" "Instance PID file: $INSTANCE_PID_FILE"

# Check if TaskPlex is already running on THIS branch
if [ -f "$INSTANCE_PID_FILE" ]; then
  EXISTING_PID=$(cat "$INSTANCE_PID_FILE")
  log "INIT" "Found existing PID file with PID: $EXISTING_PID"
  if ps -p "$EXISTING_PID" > /dev/null 2>&1; then
    echo "❌ Error: TaskPlex already running on branch '$BRANCH_NAME' (PID: $EXISTING_PID)"
    echo "This prevents duplicate work on the same feature."
    echo ""
    echo "Options:"
    echo "  - Wait for it to finish"
    echo "  - Stop it: kill $EXISTING_PID"
    echo "  - View logs: tail -f .claude/taskplex.log"
    exit 1
  else
    # Stale PID file, remove it
    log "INIT" "PID $EXISTING_PID not running, removing stale PID file"
    rm -f "$INSTANCE_PID_FILE"
  fi
fi

# Save our PID for this branch
log "INIT" "Saving our PID ($$) to $INSTANCE_PID_FILE"
mkdir -p "$(dirname "$INSTANCE_PID_FILE")"
echo $$ > "$INSTANCE_PID_FILE"

# Setup git branch (US-006)
setup_branch || {
  log "ERROR" "Failed to setup git branch"
  exit 1
}

# ============================================================================
# Monitor Integration (v1.3)
# ============================================================================

# Detect monitor port from config or environment
MONITOR_PORT="${TASKPLEX_MONITOR_PORT:-}"

# Check if monitor is running
if [ -n "$MONITOR_PORT" ]; then
  if curl -s --connect-timeout 1 "http://localhost:${MONITOR_PORT}/health" > /dev/null 2>&1; then
    log "INIT" "Monitor detected on port $MONITOR_PORT"
  else
    log "INIT" "Monitor port set ($MONITOR_PORT) but server not responding — events will be skipped"
    MONITOR_PORT=""
  fi
elif [ -f "$PROJECT_DIR/.claude/taskplex-monitor.pid" ]; then
  # Check default port if PID file exists
  if curl -s --connect-timeout 1 "http://localhost:4444/health" > /dev/null 2>&1; then
    MONITOR_PORT="4444"
    log "INIT" "Monitor auto-detected on port $MONITOR_PORT"
  fi
fi

# Generate run ID for this execution
RUN_ID="$$-$(date +%s)"

# Fire-and-forget event emission — never blocks execution
emit_event() {
  local event_type="$1"
  local payload="$2"
  local story_id="${3:-}"
  local wave="${4:-}"
  local batch="${5:-}"

  # Only emit if monitor is running
  [ -z "$MONITOR_PORT" ] && return 0

  curl -s -X POST "http://localhost:${MONITOR_PORT}/api/events" \
    -H "Content-Type: application/json" \
    -d "{
      \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
      \"source\": \"orchestrator\",
      \"event_type\": \"${event_type}\",
      \"run_id\": \"${RUN_ID}\",
      \"story_id\": ${story_id:+\"$story_id\"}${story_id:-null},
      \"wave\": ${wave:-null},
      \"batch\": ${batch:-null},
      \"payload\": ${payload}
    }" > /dev/null 2>&1 &
}

# Create run record in monitor
emit_run_start() {
  [ -z "$MONITOR_PORT" ] && return 0

  local total_stories
  total_stories=$(jq '[.userStories[]] | length' "$PRD_FILE" 2>/dev/null || echo "0")

  curl -s -X POST "http://localhost:${MONITOR_PORT}/api/runs" \
    -H "Content-Type: application/json" \
    -d "{
      \"id\": \"${RUN_ID}\",
      \"started_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
      \"mode\": \"${PARALLEL_MODE}\",
      \"model\": \"${EXECUTION_MODEL}\",
      \"branch\": \"${BRANCH_NAME}\",
      \"total_stories\": ${total_stories},
      \"config\": $(cat "$CONFIG_FILE" 2>/dev/null || echo '{}')
    }" > /dev/null 2>&1 &
}

# Update run record on completion
emit_run_end() {
  [ -z "$MONITOR_PORT" ] && return 0

  local completed skipped
  completed=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE" 2>/dev/null || echo "0")
  skipped=$(jq '[.userStories[] | select(.status == "skipped")] | length' "$PRD_FILE" 2>/dev/null || echo "0")
  local elapsed=$(($(date +%s) - START_TIME))

  curl -s -X PATCH "http://localhost:${MONITOR_PORT}/api/runs/${RUN_ID}" \
    -H "Content-Type: application/json" \
    -d "{
      \"ended_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
      \"completed\": ${completed},
      \"skipped\": ${skipped}
    }" > /dev/null 2>&1 &

  # Update run in SQLite
  if [ -f "$KNOWLEDGE_DB" ]; then
    update_run "$KNOWLEDGE_DB" "$RUN_ID" "$completed" "$skipped" 2>/dev/null || true
  fi

  emit_event "run.end" "{\"completed\":${completed},\"skipped\":${skipped},\"elapsed_s\":${elapsed}}"
}

# ============================================================================
# Parallel Mode Setup (v1.2)
# ============================================================================

if [ "$PARALLEL_MODE" = "parallel" ]; then
  log "INIT" "Sourcing parallel execution module"
  source "$SCRIPT_DIR/parallel.sh"
fi

# ============================================================================
# Main Execution Loop
# ============================================================================

# Record start time for elapsed time calculation in report (US-009)
START_TIME=$(date +%s)

echo "Starting TaskPlex - Max iterations: $MAX_ITERATIONS"
echo "Branch: $BRANCH_NAME"
echo "Model: $EXECUTION_MODEL$([ -n "$EFFORT_LEVEL" ] && echo " (effort: $EFFORT_LEVEL)")"
echo "Mode: $PARALLEL_MODE$([ "$PARALLEL_MODE" = "parallel" ] && echo " (max $MAX_PARALLEL concurrent)")"
echo "PID: $$"
echo "Timeout: ${ITERATION_TIMEOUT}s per iteration"
[ -n "$MONITOR_PORT" ] && echo "Monitor: http://localhost:${MONITOR_PORT}"

# Emit run.start event to monitor
emit_run_start
emit_event "run.start" "{\"mode\":\"$PARALLEL_MODE\",\"model\":\"$EXECUTION_MODEL\",\"branch\":\"$BRANCH_NAME\"}"

# Record run in SQLite
if [ -f "$KNOWLEDGE_DB" ]; then
  total_stories_count=$(jq '[.userStories[]] | length' "$PRD_FILE" 2>/dev/null || echo "0")
  insert_run "$KNOWLEDGE_DB" "$RUN_ID" "$BRANCH_NAME" "$PARALLEL_MODE" "$EXECUTION_MODEL" "$total_stories_count" 2>/dev/null || true
fi

# ============================================================================
# Error Categorization and Retry Logic (US-004)
# ============================================================================

# Get max retries for a given error category (bash 3.2 compatible, no declare -A)
get_max_retries() {
  local category="$1"
  case "$category" in
    env_missing)        echo 0 ;;
    test_failure)       echo 2 ;;
    timeout)            echo 1 ;;
    code_error)         echo 2 ;;
    dependency_missing) echo 0 ;;
    *)                  echo 1 ;;  # unknown and any other
  esac
}

# Function to categorize errors based on exit code and output
# Returns error category: env_missing, test_failure, timeout, code_error, dependency_missing, unknown
categorize_error() {
  local exit_code=$1
  local output=$2

  # Timeout (exit code 124 from timeout command)
  if [ "$exit_code" -eq 124 ]; then
    echo "timeout"
    return
  fi

  # Environment/credentials missing
  if echo "$output" | grep -iqE 'API key|token|credentials|ECONNREFUSED|environment variable'; then
    echo "env_missing"
    return
  fi

  # Dependency missing (npm, python modules, etc.)
  if echo "$output" | grep -iqE 'npm ERR|ModuleNotFoundError|cannot find module'; then
    echo "dependency_missing"
    return
  fi

  # Test failure
  if echo "$output" | grep -iqE 'FAIL|test.*failed|assertion'; then
    echo "test_failure"
    return
  fi

  # Code error (syntax, type, lint errors)
  if echo "$output" | grep -iqE 'SyntaxError|TypeError|error TS|lint'; then
    echo "code_error"
    return
  fi

  # Unknown category
  echo "unknown"
}

# Function to handle errors with category-specific retry logic
# Args: iteration, story_id, exit_code, output
# Returns: 0=skip, 1=abort, 2=retry
handle_error() {
  local iteration=$1
  local story_id=$2
  local exit_code=$3
  local output=$4

  # Categorize the error
  local category=$(categorize_error "$exit_code" "$output")

  echo "" >&2
  log "ERROR" "Iteration $iteration failed with category: $category"

  # Get current attempts for this story
  local attempts=$(jq -r --arg id "$story_id" '.userStories[] | select(.id == $id) | .attempts // 0' "$PRD_FILE")

  # Get max retries for this category
  local max_retries=$(get_max_retries "$category")

  # Log to operational log (Layer 1)
  log_progress "$story_id" "FAILED" "$category (attempt $attempts/$max_retries)"

  # Record error in SQLite knowledge store
  if [ -f "$KNOWLEDGE_DB" ]; then
    insert_error "$KNOWLEDGE_DB" "$story_id" "$RUN_ID" "$category" "$(echo "$output" | head -c 200)" "$attempts" 2>/dev/null || true
  fi

  # Emit story.failed to monitor
  local error_excerpt_monitor=$(echo "$output" | head -c 100 | tr '\n' ' ' | tr '"' "'")
  emit_event "story.failed" "{\"error_category\":\"$category\",\"error_message\":\"$error_excerpt_monitor\",\"attempt\":$attempts,\"max_retries\":$max_retries}" "$story_id"

  # Add warning to knowledge.md for env/dependency failures (Layer 2)
  if [ "$category" = "env_missing" ] || [ "$category" = "dependency_missing" ]; then
    local error_excerpt=$(echo "$output" | head -c 150 | tr '\n' ' ')
    add_knowledge_warning "$story_id" "$category" "$error_excerpt"
  fi

  # Update story with error details
  if [ -n "$story_id" ] && [ -f "$PRD_FILE" ]; then
    TEMP_PRD=$(mktemp)
    # Extract first 200 chars of error for last_error field
    local error_excerpt=$(echo "$output" | head -c 200 | tr '\n' ' ')
    jq --arg id "$story_id" \
       --arg category "$category" \
       --arg error "$error_excerpt" '
      .userStories |= map(
        if .id == $id then
          .last_error = $error |
          .last_error_category = $category
        else . end
      )
    ' "$PRD_FILE" > "$TEMP_PRD" && mv "$TEMP_PRD" "$PRD_FILE"
  fi

  # Check if we should retry or skip
  if [ "$attempts" -gt "$max_retries" ]; then
    # Exceeded max retries for this category
    log "ERROR" "Attempts ($attempts) exceeded max retries ($max_retries) for category $category"
    log "ERROR" "Marking story $story_id as skipped"

    # Mark as skipped
    update_story_status "$story_id" "skipped"

    # Emit story.skipped to monitor
    emit_event "story.skipped" "{\"reason\":\"max_retries_exceeded\",\"error_category\":\"$category\"}" "$story_id"

    if [ "$EXECUTION_MODE" = "foreground" ]; then
      # Show interactive prompt even when skipping
      echo ""
      echo "⚠️  Story $story_id failed ($category)"
      echo "Attempts: $attempts, Max retries: $max_retries"
      echo ""
      echo "Options:"
      echo "  1. Skip story and continue (recommended)"
      echo "  2. Retry anyway (override max retries)"
      echo "  3. Abort TaskPlex execution"
      echo ""
      read -p "Choice (1-3): " choice

      case $choice in
        1)
          echo "Skipping story, continuing to next..."
          return 0
          ;;
        2)
          echo "Retrying despite max retries..."
          return 2
          ;;
        3)
          echo "Aborting TaskPlex execution"
          return 1
          ;;
        *)
          echo "Invalid choice, skipping story..."
          return 0
          ;;
      esac
    else
      # Background mode - auto-skip
      return 0
    fi
  fi

  # Retries remaining
  if [ "$EXECUTION_MODE" = "foreground" ]; then
    # Interactive mode - ask user
    local remaining=$((max_retries - attempts + 1))
    echo ""
    echo "⚠️  Iteration $iteration failed ($category)"
    echo "Attempts: $attempts, Retries remaining: $remaining"
    echo ""
    echo "Options:"
    echo "  1. Skip story and continue"
    echo "  2. Retry with context from this attempt"
    echo "  3. Abort TaskPlex execution"
    echo ""
    read -p "Choice (1-3): " choice

    case $choice in
      1)
        echo "Skipping story, continuing to next..."
        update_story_status "$story_id" "skipped"
        return 0
        ;;
      2)
        echo "Retrying with error context..."
        return 2
        ;;
      3)
        echo "Aborting TaskPlex execution"
        return 1
        ;;
      *)
        echo "Invalid choice, retrying..."
        return 2
        ;;
    esac
  else
    # Background mode - auto-retry if retries remain
    log "ERROR" "⚠️  Iteration $iteration failed ($category). Retrying ($attempts/$max_retries)..."
    return 2
  fi
}

# Function to run validator agent after story implementation
# Args: story_id
# Returns: 0=validation passed, 1=validation failed
run_validator() {
  local story_id=$1

  log "VALIDATE-$story_id" "Starting validation..."

  # Get story details from PRD
  local story_json=$(jq --arg id "$story_id" '.userStories[] | select(.id == $id)' "$PRD_FILE")
  local story_title=$(echo "$story_json" | jq -r '.title')
  local acceptance_criteria=$(echo "$story_json" | jq -r '.acceptanceCriteria[]')

  # Build validator prompt
  local validator_prompt="# Validation Task

Story ID: $story_id
Story Title: $story_title

## Acceptance Criteria

$(echo "$story_json" | jq -r '.acceptanceCriteria | to_entries | map("\(.key + 1). \(.value)") | .[]')

## Test Commands

$(if [ -n "$TEST_COMMAND" ]; then echo "Test command: $TEST_COMMAND"; fi)
$(if [ -n "$TYPECHECK_COMMAND" ]; then echo "Typecheck command: $TYPECHECK_COMMAND"; fi)
$(if [ -n "$BUILD_COMMAND" ]; then echo "Build command: $BUILD_COMMAND"; fi)

## Your Task

Verify each acceptance criterion above. For each criterion:
1. Run any verification commands specified in the criterion
2. Check that the expected outcome is met
3. Report pass/fail

Output your result as JSON in this format:
{
  \"story_id\": \"$story_id\",
  \"validation_result\": \"pass\" or \"fail\",
  \"criteria_results\": [
    {\"criterion\": \"...\", \"result\": \"pass\", \"details\": \"...\"}
  ],
  \"test_suite_result\": \"pass\" or \"fail\" or \"not_configured\"
}
"

  # Use shorter timeout for validation (1/3 of iteration timeout)
  local validation_timeout=$((ITERATION_TIMEOUT / 3))

  # Run validator agent
  VALIDATOR_OUTPUT=$($TIMEOUT_CMD $validation_timeout claude -p "$validator_prompt" \
    --output-format json \
    --no-session-persistence \
    --agent validator \
    --agents-dir "$PLUGIN_ROOT/agents" \
    2>&1)

  local validator_exit=$?

  # Check if validator ran successfully
  if [ $validator_exit -ne 0 ]; then
    log "VALIDATE-$story_id" "Validator failed to run (exit code: $validator_exit)"
    log "VALIDATE-$story_id" "Output: $VALIDATOR_OUTPUT"
    return 1
  fi

  # Parse validation result from JSON output
  # Try multiple JSON paths since the output structure may vary
  local validation_result=""
  validation_result=$(echo "$VALIDATOR_OUTPUT" | jq -r '.result.validation_result // empty' 2>/dev/null)

  # Fallback: try top-level field
  if [ -z "$validation_result" ]; then
    validation_result=$(echo "$VALIDATOR_OUTPUT" | jq -r '.validation_result // empty' 2>/dev/null)
  fi

  # Fallback: extract from JSON-like content within the result text
  if [ -z "$validation_result" ]; then
    # Look for "validation_result": "pass" as a standalone JSON key-value in the output
    # Use jq to safely extract from any embedded JSON object
    validation_result=$(echo "$VALIDATOR_OUTPUT" | jq -r '
      .. | objects | .validation_result // empty
    ' 2>/dev/null | head -1)
  fi

  # Last resort: if validator output contains clear pass/fail signals but not in JSON
  if [ -z "$validation_result" ]; then
    # Check the overall exit code and presence of failure indicators
    local fail_count=$(echo "$VALIDATOR_OUTPUT" | grep -c '"result"[[:space:]]*:[[:space:]]*"fail"' 2>/dev/null || echo "0")
    if [ "$fail_count" -gt 0 ]; then
      validation_result="fail"
    else
      # Assume pass if validator ran successfully and no fail signals
      log "VALIDATE-$story_id" "Could not parse structured result, assuming pass based on exit code"
      validation_result="pass"
    fi
  fi

  log "VALIDATE-$story_id" "Validation result: $validation_result"

  # Log validation result (Layer 1: operational log)
  log_progress "$story_id" "VALIDATED" "$validation_result"

  # Emit story.validated to monitor
  local passed_bool="false"
  [ "$validation_result" = "pass" ] && passed_bool="true"
  emit_event "story.validated" "{\"passed\":$passed_bool}" "$story_id"

  if [ "$validation_result" = "pass" ]; then
    log "VALIDATE-$story_id" "Validation passed ✓"
    return 0
  else
    log "VALIDATE-$story_id" "Validation failed ✗"
    return 1
  fi
}

# ============================================================================
# Parallel Mode — Wave-Based Execution (v1.2)
# ============================================================================

if [ "$PARALLEL_MODE" = "parallel" ]; then
  run_parallel_loop
  PARALLEL_EXIT=$?

  # Generate completion report
  generate_report

  if [ $PARALLEL_EXIT -eq 0 ]; then
    echo ""
    echo "TaskPlex completed all tasks (parallel mode)!"
    merge_to_main
    exit 0
  else
    INCOMPLETE_COUNT=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE")
    if [ "$INCOMPLETE_COUNT" -eq 0 ]; then
      echo ""
      echo "TaskPlex completed all tasks (parallel mode)!"
      merge_to_main
      exit 0
    fi

    SKIPPED_COUNT=$(jq '[.userStories[] | select(.status == "skipped")] | length' "$PRD_FILE")
    echo ""
    echo "TaskPlex finished with $SKIPPED_COUNT skipped stories (parallel mode)"
    echo "Check $PROGRESS_FILE for details"
    exit 1
  fi
fi

# ============================================================================
# Sequential Mode — Original Execution Loop
# ============================================================================

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  TaskPlex Iteration $i of $MAX_ITERATIONS"
  echo "═══════════════════════════════════════════════════════"

  # Emit iteration.start to monitor
  emit_event "iteration.start" "{\"iteration\":$i,\"max_iterations\":$MAX_ITERATIONS}"

  # Trim progress.txt if it exceeds size limit (US-008)
  trim_progress

  # Get next eligible story (respects dependencies)
  # Capture exit code without set -e aborting on non-zero return
  GET_NEXT_EXIT=0
  CURRENT_STORY=$(get_next_task) || GET_NEXT_EXIT=$?

  if [ $GET_NEXT_EXIT -eq 1 ]; then
    # No incomplete stories remain (all complete or skipped)
    log "ITER-$i" "All stories complete or skipped"

    # Check if truly all complete (not just skipped)
    INCOMPLETE_COUNT=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE")
    if [ "$INCOMPLETE_COUNT" -eq 0 ]; then
      echo ""
      echo "✓ TaskPlex completed all tasks!"
      echo "Completed at iteration $i of $MAX_ITERATIONS"

      # Generate completion report (US-009)
      generate_report
      emit_run_end

      # Merge to main if configured (US-006)
      merge_to_main

      exit 0
    else
      # Some skipped, partial completion
      SKIPPED_COUNT=$(jq '[.userStories[] | select(.status == "skipped")] | length' "$PRD_FILE")
      echo ""
      echo "⚠️  TaskPlex finished with $SKIPPED_COUNT skipped stories"
      echo "Check $PROGRESS_FILE for details"

      # Generate completion report (US-009)
      generate_report
      emit_run_end

      exit 1
    fi
  elif [ $GET_NEXT_EXIT -eq 2 ]; then
    # All remaining stories blocked by dependencies
    log "ITER-$i" "All remaining stories are blocked by unmet dependencies"
    break
  fi

  log "SELECT" "Next eligible story: $CURRENT_STORY"

  # Mark story as in progress
  update_story_status "$CURRENT_STORY" "in_progress"

  # Log story start (Layer 1: operational log)
  STORY_START_TIME=$(date +%s)
  STORY_TITLE_LOG=$(jq -r --arg id "$CURRENT_STORY" '.userStories[] | select(.id == $id) | .title' "$PRD_FILE" 2>/dev/null)
  STORY_PRIORITY=$(jq -r --arg id "$CURRENT_STORY" '.userStories[] | select(.id == $id) | .priority // 0' "$PRD_FILE" 2>/dev/null)
  STORY_ATTEMPTS=$(jq -r --arg id "$CURRENT_STORY" '.userStories[] | select(.id == $id) | .attempts // 1' "$PRD_FILE" 2>/dev/null)
  log_progress "$CURRENT_STORY" "STARTED" "$STORY_TITLE_LOG"

  # Emit story.start to monitor
  emit_event "story.start" "{\"title\":\"$STORY_TITLE_LOG\",\"priority\":$STORY_PRIORITY,\"attempt\":$STORY_ATTEMPTS}" "$CURRENT_STORY"

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

  # Generate context brief (Layer 3: ephemeral)
  CONTEXT_BRIEF_FILE=$(generate_context_brief "$CURRENT_STORY")
  log "IMPL-$CURRENT_STORY" "Context brief generated: $CONTEXT_BRIEF_FILE"

  # Emit context.generated to monitor
  HAS_DEPS=$(jq -r --arg id "$CURRENT_STORY" '.userStories[] | select(.id == $id) | if (.depends_on // [] | length) > 0 then "true" else "false" end' "$PRD_FILE" 2>/dev/null)
  HAS_CHECKS=$(jq -r --arg id "$CURRENT_STORY" '.userStories[] | select(.id == $id) | if (.check_before_implementing // [] | length) > 0 then "true" else "false" end' "$PRD_FILE" 2>/dev/null)
  emit_event "context.generated" "{\"has_deps\":$HAS_DEPS,\"has_checks\":$HAS_CHECKS,\"has_retry_context\":false}" "$CURRENT_STORY"

  # Build the full prompt: context brief + agent instructions
  FULL_PROMPT_FILE=$(mktemp)
  cat "$CONTEXT_BRIEF_FILE" > "$FULL_PROMPT_FILE"
  echo "" >> "$FULL_PROMPT_FILE"
  echo "---" >> "$FULL_PROMPT_FILE"
  echo "" >> "$FULL_PROMPT_FILE"
  cat "$SCRIPT_DIR/prompt.md" >> "$FULL_PROMPT_FILE"

  # Run fresh Claude agent with the taskplex prompt
  # Each iteration has clean context (no -c flag) to prevent context rot

  # Use temp file to capture output while tracking PID
  TEMP_OUTPUT="/tmp/taskplex-$$-$i.txt"
  log "IMPL-$CURRENT_STORY" "Starting Claude process, output to: $TEMP_OUTPUT"
  log "IMPL-$CURRENT_STORY" "Timeout: ${ITERATION_TIMEOUT}s"

  # Run with timeout
  $TIMEOUT_CMD $ITERATION_TIMEOUT claude -p "$(cat "$FULL_PROMPT_FILE")" \
    --output-format json \
    --no-session-persistence \
    --model "$STORY_MODEL" \
    --agent implementer \
    --agents-dir "$PLUGIN_ROOT/agents" \
    --max-turns "$MAX_TURNS" \
    > "$TEMP_OUTPUT" 2>&1 &

  # Track PID for cleanup
  CURRENT_CLAUDE_PID=$!
  log "ITER-$i" "Claude process started with PID: $CURRENT_CLAUDE_PID"

  # Wait for completion
  EXIT_CODE=0
  ERROR_OCCURRED=0
  if wait $CURRENT_CLAUDE_PID; then
    log "ITER-$i" "Claude process completed successfully"
  else
    EXIT_CODE=$?
    ERROR_OCCURRED=1
    if [ $EXIT_CODE -eq 124 ]; then
      # Timeout (exit code 124 from timeout command)
      log "ITER-$i" "Claude process timed out (exit code 124)"
    else
      log "ITER-$i" "Claude process exited with code $EXIT_CODE"
    fi
  fi

  # Read output and cleanup temp files
  OUTPUT=$(cat "$TEMP_OUTPUT" 2>/dev/null || echo '{"error": "Failed to read output"}')
  rm -f "$TEMP_OUTPUT" "$CONTEXT_BRIEF_FILE" "$FULL_PROMPT_FILE"
  CURRENT_CLAUDE_PID=""
  log "ITER-$i" "Claude process cleanup complete"

  # Handle errors (timeout, code errors, env issues, etc.)
  if [ $ERROR_OCCURRED -eq 1 ]; then
    handle_error $i "$CURRENT_STORY" "$EXIT_CODE" "$OUTPUT"
    RETRY=$?

    if [ $RETRY -eq 1 ]; then
      # User chose abort
      echo "Aborting TaskPlex execution"
      exit 1
    elif [ $RETRY -eq 2 ]; then
      # Retry with context (and extended timeout for timeout category)
      RETRY_CATEGORY=$(categorize_error "$EXIT_CODE" "$OUTPUT")
      log_progress "$CURRENT_STORY" "RETRY" "$RETRY_CATEGORY, injecting error context"

      # Emit story.retry to monitor
      emit_event "story.retry" "{\"error_category\":\"$RETRY_CATEGORY\",\"attempt\":$STORY_ATTEMPTS}" "$CURRENT_STORY"

      # Build retry context from error output + retry_hint from structured output
      RETRY_HINT=$(get_retry_hint "$OUTPUT")
      RETRY_CONTEXT="Previous attempt failed with error category: $RETRY_CATEGORY

Error excerpt:
$(echo "$OUTPUT" | head -c 500)
$(if [ -n "$RETRY_HINT" ]; then echo ""; echo "Agent retry hint: $RETRY_HINT"; fi)

Please address the issue and try again."

      # Generate context brief with retry context (Layer 3)
      RETRY_BRIEF_FILE=$(generate_context_brief "$CURRENT_STORY" "$RETRY_CONTEXT")

      # Build the full retry prompt
      RETRY_PROMPT_FILE=$(mktemp)
      cat "$RETRY_BRIEF_FILE" > "$RETRY_PROMPT_FILE"
      echo "" >> "$RETRY_PROMPT_FILE"
      echo "---" >> "$RETRY_PROMPT_FILE"
      echo "" >> "$RETRY_PROMPT_FILE"
      cat "$SCRIPT_DIR/prompt.md" >> "$RETRY_PROMPT_FILE"

      # For timeout category, use extended timeout (1.5x)
      if [ "$RETRY_CATEGORY" = "timeout" ]; then
        RETRY_TIMEOUT=$((ITERATION_TIMEOUT * 3 / 2))
        echo "Retrying iteration $i with extended timeout (${RETRY_TIMEOUT}s)..."
      else
        RETRY_TIMEOUT=$ITERATION_TIMEOUT
        echo "Retrying iteration $i with error context..."
      fi

      TEMP_OUTPUT="/tmp/taskplex-$$-$i-retry.txt"
      $TIMEOUT_CMD $RETRY_TIMEOUT claude -p "$(cat "$RETRY_PROMPT_FILE")" \
        --output-format json \
        --no-session-persistence \
        --model "$STORY_MODEL" \
        --agent implementer \
        --agents-dir "$PLUGIN_ROOT/agents" \
        --max-turns "$MAX_TURNS" \
        > "$TEMP_OUTPUT" 2>&1 &

      CURRENT_CLAUDE_PID=$!
      if wait $CURRENT_CLAUDE_PID; then
        OUTPUT=$(cat "$TEMP_OUTPUT" 2>/dev/null)
        rm -f "$TEMP_OUTPUT" "$RETRY_PROMPT_FILE" "$RETRY_BRIEF_FILE"
        CURRENT_CLAUDE_PID=""
        log "ITER-$i" "Retry completed successfully"
      else
        echo "⚠️  Retry also failed. Skipping story."
        rm -f "$TEMP_OUTPUT" "$RETRY_PROMPT_FILE" "$RETRY_BRIEF_FILE"
        CURRENT_CLAUDE_PID=""
        continue
      fi
    else
      # Skip this story (retry=0), continue to next iteration
      echo "Iteration $i complete (error, skipped). Continuing..."
      sleep 2
      continue
    fi
  fi

  # Extract result from JSON output
  RESULT=$(echo "$OUTPUT" | jq -r '.result // empty' 2>/dev/null || echo "$OUTPUT")

  # Display result
  echo "$RESULT"

  # Extract learnings from structured agent output (Layer 2: knowledge.md)
  extract_learnings "$CURRENT_STORY" "$OUTPUT"

  # Emit knowledge.update to monitor
  KNOWLEDGE_SIZE=$(wc -l < "$KNOWLEDGE_FILE" 2>/dev/null || echo "0")
  emit_event "knowledge.update" "{\"learnings_count\":0,\"knowledge_size\":$KNOWLEDGE_SIZE}" "$CURRENT_STORY"

  # Run validator agent to verify acceptance criteria (US-007)
  VALIDATION_PASSED=0
  if [ "$CURRENT_STORY" != "unknown" ]; then
    if run_validator "$CURRENT_STORY"; then
      VALIDATION_PASSED=1
      log "VALIDATE-$CURRENT_STORY" "✓ All acceptance criteria verified"
    else
      VALIDATION_PASSED=0
      log "VALIDATE-$CURRENT_STORY" "✗ Validation failed"

      # Treat validation failure like any other error
      VALIDATION_ERROR="Validator reported that acceptance criteria are not met. Review the implementation."

      # Handle validation error through standard error categorization
      handle_error $i "$CURRENT_STORY" 1 "$VALIDATION_ERROR"
      ERROR_HANDLING_RESULT=$?

      if [ $ERROR_HANDLING_RESULT -eq 0 ]; then
        # Skip this story
        log "VALIDATE-$CURRENT_STORY" "Skipping story after validation failure"
        continue
      elif [ $ERROR_HANDLING_RESULT -eq 1 ]; then
        # Abort
        log "VALIDATE-$CURRENT_STORY" "Aborting TaskPlex after validation failure"
        exit 1
      elif [ $ERROR_HANDLING_RESULT -eq 2 ]; then
        # Retry requested - loop will continue to next iteration
        log "VALIDATE-$CURRENT_STORY" "Retrying story after validation failure"
        continue
      fi
    fi
  fi

  # Only commit and mark complete if validation passed
  if [ "$VALIDATION_PASSED" -eq 1 ]; then
    # Commit changes after successful validation (US-006)
    # The agent stages files, script commits them
    if [ "$CURRENT_STORY" != "unknown" ]; then
      STORY_TITLE=$(jq -r --arg id "$CURRENT_STORY" '.userStories[] | select(.id == $id) | .title' "$PRD_FILE")
      if [ -n "$STORY_TITLE" ]; then
        commit_story "$CURRENT_STORY" "$STORY_TITLE"
      fi
    fi
  fi

  # Check for completion signal
  if echo "$RESULT" | grep -q "<promise>COMPLETE</promise>"; then
    # Mark current story as completed if validation passed
    if [ "$CURRENT_STORY" != "unknown" ] && [ "$VALIDATION_PASSED" -eq 1 ]; then
      update_story_status "$CURRENT_STORY" "completed"

      # Mark errors as resolved in SQLite
      if [ -f "$KNOWLEDGE_DB" ]; then
        resolve_errors "$KNOWLEDGE_DB" "$CURRENT_STORY" 2>/dev/null || true
      fi

      # Log completion with duration (Layer 1: operational log)
      STORY_ELAPSED=$(($(date +%s) - STORY_START_TIME))
      STORY_ATTEMPTS=$(jq -r --arg id "$CURRENT_STORY" '.userStories[] | select(.id == $id) | .attempts // 1' "$PRD_FILE" 2>/dev/null)
      log_progress "$CURRENT_STORY" "COMPLETED" "${STORY_ATTEMPTS} attempt(s), ${STORY_ELAPSED}s"

      # Emit story.complete to monitor
      emit_event "story.complete" "{\"attempts\":$STORY_ATTEMPTS,\"elapsed_s\":$STORY_ELAPSED}" "$CURRENT_STORY"
    fi

    # Check if ALL stories are complete
    INCOMPLETE_COUNT=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE")
    if [ "$INCOMPLETE_COUNT" -eq 0 ]; then
      echo ""
      echo "✓ TaskPlex completed all tasks!"
      echo "Completed at iteration $i of $MAX_ITERATIONS"

      # Generate completion report (US-009)
      generate_report
      emit_run_end

      # Merge to main if configured (US-006)
      merge_to_main

      exit 0
    fi

    # Some stories still incomplete, continue
    log "ITER-$i" "Story $CURRENT_STORY completed, but more stories remain"
  fi

  # Check for errors
  if echo "$OUTPUT" | jq -e '.is_error' > /dev/null 2>&1; then
    ERROR_MSG=$(echo "$OUTPUT" | jq -r '.result // "Unknown error"')
    echo "⚠ Warning: Iteration $i encountered an error: $ERROR_MSG"
    echo "Continuing to next iteration..."
  fi

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "TaskPlex reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."

# Generate completion report (US-009)
generate_report
emit_run_end

exit 1
