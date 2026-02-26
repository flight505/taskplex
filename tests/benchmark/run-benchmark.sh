#!/usr/bin/env bash
# run-benchmark.sh — Orchestrates TaskPlex vs Superpowers benchmark
#
# Usage:
#   ./run-benchmark.sh [options]
#
# Options:
#   --stories <file>       Story suite JSON (default: stories/sample-stories.json)
#   --plugins <list>       Comma-separated plugin list (default: taskplex,superpowers)
#   --story-ids <ids>      Comma-separated story IDs to run (default: all)
#   --tiers <tiers>        Comma-separated tiers to run (default: all)
#   --output <dir>         Output directory (default: results/run-<timestamp>)
#   --dry-run              Validate setup without executing Claude
#   --skip-install         Skip npm install in worktree (use existing node_modules)
#   --timeout <seconds>    Per-story timeout (default: 300)
#   --verbose              Show detailed progress output
#   --help                 Show this help
#
# Prerequisites:
#   - claude CLI installed and authenticated
#   - jq, git, bc available
#   - Plugin directories accessible (for --plugin-dir)
#
# Output structure:
#   results/run-<timestamp>/
#   ├── meta.json            (run configuration)
#   ├── traces/              (per-story trace files)
#   │   ├── S001-taskplex-trace.json
#   │   ├── S001-superpowers-trace.json
#   │   └── ...
#   ├── results/             (per-story result files)
#   │   ├── S001-taskplex-result.json
#   │   └── ...
#   ├── scores/              (per-story DQ scores)
#   │   ├── S001-taskplex-score.json
#   │   └── ...
#   └── summary.json         (aggregate comparison)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCHMARK_ROOT="$SCRIPT_DIR"
DEFAULT_STORIES="$BENCHMARK_ROOT/stories/sample-stories.json"

# ─────────────────────────────────────────────
# Defaults
# ─────────────────────────────────────────────

STORIES_FILE="$DEFAULT_STORIES"
PLUGINS="taskplex,superpowers"
STORY_IDS=""
TIERS=""
OUTPUT_DIR=""
DRY_RUN=false
SKIP_INSTALL=false
TIMEOUT=300
VERBOSE=false

# ─────────────────────────────────────────────
# CLI Parsing
# ─────────────────────────────────────────────

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --stories)    STORIES_FILE="$2"; shift 2 ;;
    --plugins)    PLUGINS="$2"; shift 2 ;;
    --story-ids)  STORY_IDS="$2"; shift 2 ;;
    --tiers)      TIERS="$2"; shift 2 ;;
    --output)     OUTPUT_DIR="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --skip-install) SKIP_INSTALL=true; shift ;;
    --timeout)    TIMEOUT="$2"; shift 2 ;;
    --verbose)    VERBOSE=true; shift ;;
    --help|-h)    usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ─────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────

log() { echo "[benchmark] $*"; }
log_verbose() { [ "$VERBOSE" = true ] && echo "[benchmark] $*" || true; }
log_error() { echo "[benchmark] ERROR: $*" >&2; }

# ─────────────────────────────────────────────
# Dependency Check
# ─────────────────────────────────────────────

check_deps() {
  local missing=0
  for cmd in jq git bc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log_error "Missing required command: $cmd"
      missing=1
    fi
  done

  if ! command -v claude >/dev/null 2>&1; then
    if [ "$DRY_RUN" = false ]; then
      log_error "Missing 'claude' CLI — required for live runs (use --dry-run to validate without it)"
      missing=1
    else
      log "Warning: 'claude' CLI not found (OK for --dry-run)"
    fi
  fi

  if [ ! -f "$STORIES_FILE" ]; then
    log_error "Stories file not found: $STORIES_FILE"
    missing=1
  fi

  if [ "$missing" -eq 1 ]; then
    exit 1
  fi
}

# ─────────────────────────────────────────────
# Story Filtering
# ─────────────────────────────────────────────

get_filtered_stories() {
  local filter="."

  # Filter by story IDs
  if [ -n "$STORY_IDS" ]; then
    local id_array
    id_array=$(echo "$STORY_IDS" | tr ',' '\n' | jq -R . | jq -s .)
    filter="$filter | select(.id as \$id | $id_array | index(\$id))"
  fi

  # Filter by tiers
  if [ -n "$TIERS" ]; then
    local tier_array
    tier_array=$(echo "$TIERS" | tr ',' '\n' | jq -R . | jq -s .)
    filter="$filter | select(.tier as \$t | $tier_array | index(\$t))"
  fi

  jq -c "[.stories[] | $filter]" "$STORIES_FILE"
}

# ─────────────────────────────────────────────
# Plugin Directory Resolution
# ─────────────────────────────────────────────

resolve_plugin_dir() {
  local plugin_name="$1"

  # Check marketplace structure first (we're inside taskplex submodule)
  local marketplace_root
  marketplace_root="$(cd "$BENCHMARK_ROOT/../../../.." && pwd)"

  case "$plugin_name" in
    taskplex)
      local dir="$marketplace_root/taskplex"
      if [ -d "$dir/.claude-plugin" ]; then
        echo "$dir"
        return 0
      fi
      ;;
    superpowers)
      # Look for Superpowers in common locations
      local sp_locations=(
        "$HOME/.claude/plugins/cache/superpowers"
        "$HOME/.claude/plugins/cache/jesseduffield/superpowers"
        "$marketplace_root/../superpowers"
      )
      for loc in "${sp_locations[@]}"; do
        if [ -d "$loc" ]; then
          echo "$loc"
          return 0
        fi
      done

      # Try to find via installed_plugins.json
      local installed="$HOME/.claude/plugins/installed_plugins.json"
      if [ -f "$installed" ]; then
        local sp_path
        sp_path=$(jq -r '.plugins | to_entries[] | select(.key | test("superpowers")) | .value.cachePath // empty' "$installed" 2>/dev/null | head -1)
        if [ -n "$sp_path" ] && [ -d "$sp_path" ]; then
          echo "$sp_path"
          return 0
        fi
      fi
      ;;
  esac

  log_error "Cannot resolve plugin directory for: $plugin_name"
  return 1
}

# ─────────────────────────────────────────────
# Worktree Management
# ─────────────────────────────────────────────

create_worktree() {
  local project_name="$1"
  local story_id="$2"
  local plugin_name="$3"
  local worktree_base="${TMPDIR:-/tmp}/benchmark-worktrees"

  mkdir -p "$worktree_base"
  local worktree_dir="$worktree_base/${story_id}-${plugin_name}-$$"

  # Copy project (not git worktree — sample projects aren't git repos)
  local project_src="$BENCHMARK_ROOT/projects/$project_name"
  if [ ! -d "$project_src" ]; then
    log_error "Project directory not found: $project_src"
    return 1
  fi

  cp -R "$project_src" "$worktree_dir"

  # Initialize a fresh git repo so stories can make commits
  (
    cd "$worktree_dir"
    git init -q
    git add -A
    git commit -q -m "Initial state for benchmark"
  )

  echo "$worktree_dir"
}

cleanup_worktree() {
  local worktree_dir="$1"
  if [ -d "$worktree_dir" ]; then
    rm -rf "$worktree_dir"
    log_verbose "Cleaned up worktree: $worktree_dir"
  fi
}

# ─────────────────────────────────────────────
# npm Install (if needed)
# ─────────────────────────────────────────────

install_deps() {
  local worktree_dir="$1"
  if [ "$SKIP_INSTALL" = true ]; then
    log_verbose "Skipping npm install (--skip-install)"
    return 0
  fi

  if [ -f "$worktree_dir/package.json" ]; then
    log_verbose "Installing dependencies in $worktree_dir"
    (cd "$worktree_dir" && npm install --silent 2>/dev/null) || {
      log "Warning: npm install failed in $worktree_dir (continuing anyway)"
    }
  fi
}

# ─────────────────────────────────────────────
# Build Story Prompt
# ─────────────────────────────────────────────

build_prompt() {
  local story_json="$1"

  local title description acceptance_criteria
  title=$(echo "$story_json" | jq -r '.title')
  description=$(echo "$story_json" | jq -r '.description')
  acceptance_criteria=$(echo "$story_json" | jq -r '.acceptance_criteria | map("- " + .) | join("\n")')

  local test_cmd build_cmd typecheck_cmd
  test_cmd=$(echo "$story_json" | jq -r '.test_command // "npx vitest run"')
  build_cmd=$(echo "$story_json" | jq -r '.build_command // "npx tsc --noEmit"')
  typecheck_cmd=$(echo "$story_json" | jq -r '.typecheck_command // "npx tsc --noEmit"')

  cat <<PROMPT
## Task

$title

## Description

$description

## Acceptance Criteria

$acceptance_criteria

## Verification Commands

- Tests: $test_cmd
- Build: $build_cmd
- Typecheck: $typecheck_cmd

## Instructions

1. Read the relevant source files to understand the current state
2. Implement the changes described above
3. Ensure ALL acceptance criteria are met
4. Run the verification commands and fix any failures
5. Commit your changes with a descriptive message
PROMPT
}

# ─────────────────────────────────────────────
# Execute Story (Headless Claude)
# ─────────────────────────────────────────────

execute_story() {
  local story_json="$1"
  local plugin_name="$2"
  local worktree_dir="$3"
  local trace_file="$4"
  local result_file="$5"

  local story_id tier
  story_id=$(echo "$story_json" | jq -r '.id')
  tier=$(echo "$story_json" | jq -r '.tier')

  local start_time
  start_time=$(date +%s)

  log "  Executing $story_id ($tier) with $plugin_name..."

  # Build prompt
  local prompt
  prompt=$(build_prompt "$story_json")

  local exit_code=0
  local session_file="$OUTPUT_DIR/sessions/${story_id}-${plugin_name}-session.txt"
  mkdir -p "$(dirname "$session_file")"

  if [ "$DRY_RUN" = true ]; then
    # Dry run: validate everything without calling Claude
    log_verbose "  [DRY-RUN] Would execute in: $worktree_dir"
    log_verbose "  [DRY-RUN] Plugin: $plugin_name"
    log_verbose "  [DRY-RUN] Prompt length: ${#prompt} chars"

    # Generate synthetic trace for dry-run validation
    generate_dry_run_trace "$story_json" "$plugin_name" "$trace_file"
    generate_dry_run_result "$story_json" "$plugin_name" "$result_file" 0 0
    return 0
  fi

  # Resolve plugin directory
  local plugin_dir
  plugin_dir=$(resolve_plugin_dir "$plugin_name") || {
    log_error "  Cannot find plugin '$plugin_name' — skipping"
    generate_error_result "$story_json" "$plugin_name" "$result_file" "plugin_not_found"
    return 1
  }

  # Execute Claude headless with plugin
  local claude_exit=0
  env -u CLAUDECODE timeout "$TIMEOUT" claude -p "$prompt" \
    --cwd "$worktree_dir" \
    --plugin-dir "$plugin_dir" \
    --dangerously-skip-permissions \
    --output-format json \
    > "$session_file" 2>&1 || claude_exit=$?

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))

  # Parse session output for trace events
  parse_session_to_trace "$session_file" "$story_id" "$plugin_name" "$trace_file"

  # Collect results (test pass, git commits, etc.)
  collect_results "$story_json" "$plugin_name" "$worktree_dir" "$result_file" "$duration" "$claude_exit"

  log "  Completed $story_id with $plugin_name (${duration}s, exit=$claude_exit)"
}

# ─────────────────────────────────────────────
# Trace Generation
# ─────────────────────────────────────────────

parse_session_to_trace() {
  local session_file="$1"
  local story_id="$2"
  local plugin_name="$3"
  local trace_file="$4"

  # Initialize trace structure
  local events="[]"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Parse JSON session output for tool calls and skill invocations
  if [ -f "$session_file" ] && [ -s "$session_file" ]; then
    # Count tool uses (each tool_use block in the session)
    local tool_count=0
    tool_count=$(grep -c '"type":"tool_use"' "$session_file" 2>/dev/null || echo "0")

    # Detect skill invocations
    local skills_found
    skills_found=$(grep -oE '"(taskplex-tdd|taskplex-verify|systematic-debugging|using-taskplex|using-superpowers|test-driven-development|verification-before-completion|brainstorming)"' "$session_file" 2>/dev/null | sort -u | tr -d '"' || echo "")

    # Detect agent dispatches
    local agents_found
    agents_found=$(grep -oE '"(implementer|validator|spec-reviewer|code-reviewer|reviewer|merger)"' "$session_file" 2>/dev/null | sort -u | tr -d '"' || echo "")

    # Detect test executions
    local test_runs=0
    test_runs=$(grep -c '"vitest\|npm test\|npx vitest' "$session_file" 2>/dev/null || echo "0")

    # Build events array
    events="[]"

    # Add skill events
    if [ -n "$skills_found" ]; then
      for skill in $skills_found; do
        events=$(echo "$events" | jq --arg ts "$timestamp" --arg s "$skill" --arg sid "$story_id" --arg p "$plugin_name" \
          '. + [{"timestamp": $ts, "event": "skill_invoked", "story_id": $sid, "plugin": $p, "data": {"skill": $s}}]')
      done
    fi

    # Add agent events
    if [ -n "$agents_found" ]; then
      for agent in $agents_found; do
        events=$(echo "$events" | jq --arg ts "$timestamp" --arg a "$agent" --arg sid "$story_id" --arg p "$plugin_name" \
          '. + [{"timestamp": $ts, "event": "agent_dispatched", "story_id": $sid, "plugin": $p, "data": {"agent": $a}}]')
      done
    fi

    # Add test execution events
    if [ "$test_runs" -gt 0 ]; then
      events=$(echo "$events" | jq --arg ts "$timestamp" --arg sid "$story_id" --arg p "$plugin_name" --argjson count "$test_runs" \
        '. + [{"timestamp": $ts, "event": "test_executed", "story_id": $sid, "plugin": $p, "data": {"count": $count}, "phase": "pre_completion"}]')
    fi

    # Add tool use summary
    events=$(echo "$events" | jq --arg ts "$timestamp" --arg sid "$story_id" --arg p "$plugin_name" --argjson count "$tool_count" \
      '. + [{"timestamp": $ts, "event": "summary", "story_id": $sid, "plugin": $p, "data": {"total_tool_calls": $count}}]')
  fi

  # Write trace file
  jq -n \
    --arg sid "$story_id" \
    --arg plugin "$plugin_name" \
    --arg ts "$timestamp" \
    --argjson events "$events" \
    '{story_id: $sid, plugin: $plugin, started_at: $ts, events: $events}' \
    > "$trace_file"
}

generate_dry_run_trace() {
  local story_json="$1"
  local plugin_name="$2"
  local trace_file="$3"

  local story_id
  story_id=$(echo "$story_json" | jq -r '.id')

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local expected_skills
  expected_skills=$(echo "$story_json" | jq -r '.expected_skills // []')

  # Generate trace with expected skills
  local events="[]"
  for skill in $(echo "$expected_skills" | jq -r '.[]' 2>/dev/null); do
    events=$(echo "$events" | jq --arg ts "$timestamp" --arg s "$skill" --arg sid "$story_id" --arg p "$plugin_name" \
      '. + [{"timestamp": $ts, "event": "skill_invoked", "story_id": $sid, "plugin": $p, "data": {"skill": $s}}]')
  done

  # Add a test_executed event (assume it would happen)
  events=$(echo "$events" | jq --arg ts "$timestamp" --arg sid "$story_id" --arg p "$plugin_name" \
    '. + [{"timestamp": $ts, "event": "test_executed", "story_id": $sid, "plugin": $p, "data": {"count": 1}, "phase": "pre_completion"}]')

  jq -n \
    --arg sid "$story_id" \
    --arg plugin "$plugin_name" \
    --arg ts "$timestamp" \
    --argjson events "$events" \
    '{story_id: $sid, plugin: $plugin, started_at: $ts, events: $events, dry_run: true}' \
    > "$trace_file"
}

# ─────────────────────────────────────────────
# Result Collection
# ─────────────────────────────────────────────

collect_results() {
  local story_json="$1"
  local plugin_name="$2"
  local worktree_dir="$3"
  local result_file="$4"
  local duration="$5"
  local claude_exit="$6"

  local story_id tier
  story_id=$(echo "$story_json" | jq -r '.id')
  tier=$(echo "$story_json" | jq -r '.tier')

  # Count commits made by the agent
  local commit_count=0
  if [ -d "$worktree_dir/.git" ]; then
    commit_count=$(cd "$worktree_dir" && git log --oneline | wc -l | tr -d ' ')
    # Subtract the initial commit
    commit_count=$((commit_count > 0 ? commit_count - 1 : 0))
  fi

  # Check if tests pass
  local tests_pass=false
  local test_cmd
  test_cmd=$(echo "$story_json" | jq -r '.test_command // "npx vitest run"')
  if [ -d "$worktree_dir/node_modules" ]; then
    (cd "$worktree_dir" && eval "$test_cmd" >/dev/null 2>&1) && tests_pass=true
  fi

  # Check if typecheck passes
  local typecheck_pass=false
  local typecheck_cmd
  typecheck_cmd=$(echo "$story_json" | jq -r '.typecheck_command // "npx tsc --noEmit"')
  if [ -d "$worktree_dir/node_modules" ]; then
    (cd "$worktree_dir" && eval "$typecheck_cmd" >/dev/null 2>&1) && typecheck_pass=true
  fi

  # Detect TDD patterns in git history
  local tdd_observed=false
  if [ -d "$worktree_dir/.git" ] && [ "$commit_count" -ge 2 ]; then
    local first_commit_files
    first_commit_files=$(cd "$worktree_dir" && git log --reverse --oneline --name-only | head -20)
    if echo "$first_commit_files" | grep -q "test\|spec\|\.test\.\|\.spec\."; then
      tdd_observed=true
    fi
  fi

  # Check for human intervention (errors, retries)
  local human_intervention=false
  local error_count=0
  if [ "$claude_exit" -ne 0 ]; then
    error_count=1
  fi

  jq -n \
    --arg sid "$story_id" \
    --arg tier "$tier" \
    --arg plugin "$plugin_name" \
    --argjson duration "$duration" \
    --argjson claude_exit "$claude_exit" \
    --argjson commit_count "$commit_count" \
    --argjson tests_pass "$tests_pass" \
    --argjson typecheck_pass "$typecheck_pass" \
    --argjson tdd_observed "$tdd_observed" \
    --argjson human_intervention "$human_intervention" \
    --argjson error_count "$error_count" \
    '{
      story_id: $sid,
      tier: $tier,
      plugin: $plugin,
      duration_seconds: $duration,
      claude_exit_code: $claude_exit,
      metrics: {
        commit_count: $commit_count,
        tests_pass: $tests_pass,
        typecheck_pass: $typecheck_pass,
        tdd_applicable: true,
        tdd_sequence_observed: $tdd_observed,
        human_intervention: $human_intervention,
        error_count: $error_count,
        errors_recovered: 0
      }
    }' > "$result_file"
}

generate_dry_run_result() {
  local story_json="$1"
  local plugin_name="$2"
  local result_file="$3"
  local duration="${4:-0}"
  local exit_code="${5:-0}"

  local story_id tier
  story_id=$(echo "$story_json" | jq -r '.id')
  tier=$(echo "$story_json" | jq -r '.tier')

  jq -n \
    --arg sid "$story_id" \
    --arg tier "$tier" \
    --arg plugin "$plugin_name" \
    --argjson dur "$duration" \
    '{
      story_id: $sid,
      tier: $tier,
      plugin: $plugin,
      duration_seconds: $dur,
      claude_exit_code: 0,
      dry_run: true,
      metrics: {
        commit_count: 0,
        tests_pass: false,
        typecheck_pass: false,
        tdd_applicable: true,
        tdd_sequence_observed: false,
        human_intervention: false,
        error_count: 0,
        errors_recovered: 0
      }
    }' > "$result_file"
}

generate_error_result() {
  local story_json="$1"
  local plugin_name="$2"
  local result_file="$3"
  local error_type="$4"

  local story_id tier
  story_id=$(echo "$story_json" | jq -r '.id')
  tier=$(echo "$story_json" | jq -r '.tier')

  jq -n \
    --arg sid "$story_id" \
    --arg tier "$tier" \
    --arg plugin "$plugin_name" \
    --arg err "$error_type" \
    '{
      story_id: $sid,
      tier: $tier,
      plugin: $plugin,
      duration_seconds: 0,
      claude_exit_code: 1,
      error: $err,
      metrics: {
        commit_count: 0,
        tests_pass: false,
        typecheck_pass: false,
        tdd_applicable: false,
        tdd_sequence_observed: false,
        human_intervention: false,
        error_count: 1,
        errors_recovered: 0
      }
    }' > "$result_file"
}

# ─────────────────────────────────────────────
# Summary Generation
# ─────────────────────────────────────────────

generate_summary() {
  local run_dir="$1"
  local scores_dir="$run_dir/scores"
  local summary_file="$run_dir/summary.json"

  if [ ! -d "$scores_dir" ] || [ -z "$(ls -A "$scores_dir" 2>/dev/null)" ]; then
    log "No scores to summarize"
    return 0
  fi

  # Aggregate per plugin
  local plugins_json="{}"
  for plugin in $(echo "$PLUGINS" | tr ',' ' '); do
    local count=0 dq_sum="0"
    local d_sum="0" c_sum="0" a_sum="0" e_sum="0"

    for score_file in "$scores_dir"/*-"$plugin"-score.json; do
      [ -f "$score_file" ] || continue
      count=$((count + 1))
      dq_sum=$(echo "$dq_sum + $(jq -r '.scores.dq' "$score_file")" | bc)
      d_sum=$(echo "$d_sum + $(jq -r '.scores.discipline' "$score_file")" | bc)
      c_sum=$(echo "$c_sum + $(jq -r '.scores.correctness' "$score_file")" | bc)
      a_sum=$(echo "$a_sum + $(jq -r '.scores.autonomy' "$score_file")" | bc)
      e_sum=$(echo "$e_sum + $(jq -r '.scores.efficiency' "$score_file")" | bc)
    done

    if [ "$count" -gt 0 ]; then
      local dq_mean d_mean c_mean a_mean e_mean
      dq_mean=$(echo "scale=4; $dq_sum / $count" | bc)
      d_mean=$(echo "scale=4; $d_sum / $count" | bc)
      c_mean=$(echo "scale=4; $c_sum / $count" | bc)
      a_mean=$(echo "scale=4; $a_sum / $count" | bc)
      e_mean=$(echo "scale=4; $e_sum / $count" | bc)

      plugins_json=$(echo "$plugins_json" | jq \
        --arg p "$plugin" \
        --argjson n "$count" \
        --arg dq "$dq_mean" \
        --arg d "$d_mean" \
        --arg c "$c_mean" \
        --arg a "$a_mean" \
        --arg e "$e_mean" \
        '. + {($p): {stories_scored: $n, mean_DQ: ($dq|tonumber), mean_discipline: ($d|tonumber), mean_correctness: ($c|tonumber), mean_autonomy: ($a|tonumber), mean_efficiency: ($e|tonumber)}}')
    fi
  done

  jq -n \
    --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg stories "$STORIES_FILE" \
    --argjson plugins "$plugins_json" \
    --argjson dry_run "$DRY_RUN" \
    '{
      generated_at: $ts,
      stories_file: $stories,
      dry_run: $dry_run,
      plugins: $plugins
    }' > "$summary_file"

  log "Summary written to: $summary_file"

  # Print summary to terminal
  echo ""
  echo "═══════════════════════════════════════════"
  echo "  Benchmark Summary"
  echo "═══════════════════════════════════════════"
  echo ""

  for plugin in $(echo "$PLUGINS" | tr ',' ' '); do
    local data
    data=$(echo "$plugins_json" | jq --arg p "$plugin" '.[$p] // empty')
    if [ -n "$data" ]; then
      local n dq d c a e
      n=$(echo "$data" | jq '.stories_scored')
      dq=$(echo "$data" | jq '.mean_DQ')
      d=$(echo "$data" | jq '.mean_discipline')
      c=$(echo "$data" | jq '.mean_correctness')
      a=$(echo "$data" | jq '.mean_autonomy')
      e=$(echo "$data" | jq '.mean_efficiency')
      printf "  %-15s  DQ=%.4f  D=%.4f  C=%.4f  A=%.4f  E=%.4f  (n=%d)\n" \
        "$plugin" "$dq" "$d" "$c" "$a" "$e" "$n"
    fi
  done

  echo ""
  echo "  Full results: $run_dir"
  echo "═══════════════════════════════════════════"
}

# ─────────────────────────────────────────────
# Main Loop
# ─────────────────────────────────────────────

main() {
  check_deps

  # Set output directory
  if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$BENCHMARK_ROOT/results/run-$(date +%Y%m%d-%H%M%S)"
  fi
  mkdir -p "$OUTPUT_DIR"/{traces,results,scores,sessions}

  # Write run metadata
  jq -n \
    --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg stories "$STORIES_FILE" \
    --arg plugins "$PLUGINS" \
    --arg story_ids "$STORY_IDS" \
    --arg tiers "$TIERS" \
    --argjson timeout "$TIMEOUT" \
    --argjson dry_run "$DRY_RUN" \
    '{
      started_at: $ts,
      stories_file: $stories,
      plugins: ($plugins | split(",")),
      story_filter: {ids: $story_ids, tiers: $tiers},
      timeout_seconds: $timeout,
      dry_run: $dry_run
    }' > "$OUTPUT_DIR/meta.json"

  # Get filtered stories
  local stories
  stories=$(get_filtered_stories)
  local story_count
  story_count=$(echo "$stories" | jq 'length')
  local plugin_list
  plugin_list=$(echo "$PLUGINS" | tr ',' ' ')
  local plugin_count
  plugin_count=$(echo "$plugin_list" | wc -w | tr -d ' ')

  local total_runs=$((story_count * plugin_count))
  log "Starting benchmark run:"
  log "  Stories: $story_count"
  log "  Plugins: $PLUGINS"
  log "  Total runs: $total_runs"
  log "  Output: $OUTPUT_DIR"
  if [ "$DRY_RUN" = true ]; then
    log "  Mode: DRY RUN (no Claude execution)"
  fi
  echo ""

  local completed=0
  local failed=0

  # Iterate stories × plugins
  for i in $(seq 0 $((story_count - 1))); do
    local story
    story=$(echo "$stories" | jq -c ".[$i]")
    local story_id
    story_id=$(echo "$story" | jq -r '.id')
    local project
    project=$(echo "$story" | jq -r '.target_project')

    log "[$((i + 1))/$story_count] Story $story_id ($project)"

    for plugin_name in $plugin_list; do
      local trace_file="$OUTPUT_DIR/traces/${story_id}-${plugin_name}-trace.json"
      local result_file="$OUTPUT_DIR/results/${story_id}-${plugin_name}-result.json"
      local score_file="$OUTPUT_DIR/scores/${story_id}-${plugin_name}-score.json"

      # Create isolated worktree
      local worktree_dir
      worktree_dir=$(create_worktree "$project" "$story_id" "$plugin_name") || {
        log_error "  Failed to create worktree for $story_id/$plugin_name"
        generate_error_result "$story" "$plugin_name" "$result_file" "worktree_failed"
        failed=$((failed + 1))
        continue
      }

      # Install dependencies
      install_deps "$worktree_dir"

      # Execute story
      if execute_story "$story" "$plugin_name" "$worktree_dir" "$trace_file" "$result_file"; then
        # Score the run
        if [ -f "$trace_file" ] && [ -f "$result_file" ]; then
          "$BENCHMARK_ROOT/score.sh" "$trace_file" "$result_file" > "$score_file" 2>/dev/null || {
            log "  Warning: scoring failed for $story_id/$plugin_name"
          }
        fi
        completed=$((completed + 1))
      else
        failed=$((failed + 1))
      fi

      # Clean up worktree
      cleanup_worktree "$worktree_dir"
    done
  done

  echo ""
  log "Benchmark complete: $completed/$total_runs succeeded, $failed failed"

  # Generate summary
  generate_summary "$OUTPUT_DIR"
}

# ─────────────────────────────────────────────
# Entry Point
# ─────────────────────────────────────────────

main "$@"
