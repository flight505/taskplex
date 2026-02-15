#!/bin/bash
# TaskPlex Parallel Execution — Wave-based worktree parallelism
# Sourced conditionally by taskplex.sh when parallel_mode=parallel
#
# Requires: git worktree support, jq, bash 3.2+
# No associative arrays — uses space-separated lists for bash 3.2 compat

# ============================================================================
# Wave Computation (Phase 1)
# ============================================================================

# Partition stories into topological waves based on depends_on
# Input: $PRD_FILE (global)
# Output: JSON array of waves to stdout
compute_waves() {
  jq '
    # Build completed set
    (.userStories | map(select(.passes == true or .status == "skipped")) | map(.id)) as $done |

    # Remaining stories (not done)
    [.userStories[] | select(.passes != true and .status != "skipped")] as $remaining |

    # Recursive wave assignment
    def assign_waves(stories; done; wave_num):
      if (stories | length) == 0 then []
      else
        # Stories whose deps are all in $done
        [stories[] | select(
          (.depends_on // []) | length == 0 or
          ((.depends_on // []) | all(. as $d | done | any(. == $d)))
        )] as $ready |

        if ($ready | length) == 0 then
          # Remaining stories are blocked — put them in a final wave anyway
          [{"wave": wave_num, "stories": [stories[].id]}]
        else
          ($ready | map(.id)) as $ready_ids |
          [stories[] | select(.id as $id | $ready_ids | any(. == $id) | not)] as $next_stories |
          [{"wave": wave_num, "stories": $ready_ids}] +
            assign_waves($next_stories; done + $ready_ids; wave_num + 1)
        end
      end;

    assign_waves($remaining; $done; 0)
  ' "$PRD_FILE"
}

# Split a wave into conflict-free batches based on related_to overlap
# Batches are capped at $MAX_PARALLEL
# Input: wave JSON (stdin), PRD_FILE (global), MAX_PARALLEL (global)
# Output: JSON array of batches (each batch is an array of story IDs)
split_wave_by_conflicts() {
  local wave_json="$1"

  echo "$wave_json" | jq --argjson max "$MAX_PARALLEL" --slurpfile prd "$PRD_FILE" '
    . as $story_ids |
    $prd[0].userStories as $all |

    # Build related_to map: story_id -> [related targets]
    [
      $story_ids[] as $sid |
      ($all[] | select(.id == $sid)) as $story |
      {id: $sid, related: ($story.related_to // [])}
    ] as $entries |

    # Check if two stories conflict (share a related_to target)
    def conflicts(a; b):
      ($entries[] | select(.id == a) | .related) as $ra |
      ($entries[] | select(.id == b) | .related) as $rb |
      ($ra | any(. as $r | $rb | any(. == $r)));

    # Greedy batch assignment
    reduce $story_ids[] as $sid (
      [];  # accumulator: array of batches (each batch is array of IDs)
      . as $batches |
      # Find first batch where this story has no conflicts and batch is not full
      (
        [range($batches | length)] |
        map(select(
          . as $bi |
          ($batches[$bi] | length) < $max and
          ($batches[$bi] | all(. as $existing | conflicts($existing; $sid) | not))
        )) | .[0]
      ) as $target_batch |
      if $target_batch != null then
        .[$target_batch] += [$sid]
      else
        . + [[$sid]]
      end
    )
  '
}

# ============================================================================
# Worktree Lifecycle (Phase 2)
# ============================================================================

# Create a worktree for a story
# Args: story_id, feature_branch, worktree_base_dir
create_worktree() {
  local story_id="$1"
  local feature_branch="$2"
  local worktree_base="$3"

  local story_branch="${feature_branch}-${story_id}"
  local worktree_dir="${worktree_base}/${story_id}"

  log "WORKTREE" "Creating worktree for $story_id at $worktree_dir"

  # Create worktree with new branch forked from feature branch
  if ! git worktree add -b "$story_branch" "$worktree_dir" "$feature_branch" 2>&1; then
    log "ERROR" "Failed to create worktree for $story_id"
    return 1
  fi

  log "WORKTREE" "Worktree created: $worktree_dir (branch: $story_branch)"
  echo "$worktree_dir"
}

# Run setup command in a worktree (e.g., npm install)
# Args: worktree_dir
setup_worktree() {
  local worktree_dir="$1"

  if [ -z "$WORKTREE_SETUP_COMMAND" ]; then
    return 0
  fi

  log "WORKTREE" "Running setup in $worktree_dir: $WORKTREE_SETUP_COMMAND"

  if ! (cd "$worktree_dir" && eval "$WORKTREE_SETUP_COMMAND") 2>&1; then
    log "ERROR" "Worktree setup failed in $worktree_dir"
    return 1
  fi

  log "WORKTREE" "Setup complete for $worktree_dir"
}

# Clean up a single worktree and its branch
# Args: story_id, worktree_dir, story_branch
cleanup_worktree() {
  local story_id="$1"
  local worktree_dir="$2"
  local story_branch="$3"

  log "WORKTREE" "Cleaning up worktree for $story_id"

  if [ -d "$worktree_dir" ]; then
    git worktree remove --force "$worktree_dir" 2>/dev/null || true
  fi

  # Delete the story branch (it's been merged or is no longer needed)
  if git show-ref --verify --quiet "refs/heads/$story_branch" 2>/dev/null; then
    git branch -D "$story_branch" 2>/dev/null || true
  fi

  log "WORKTREE" "Cleaned up $story_id"
}

# Emergency cleanup — kill all parallel agents, remove all worktrees
cleanup_all_worktrees() {
  log "CLEANUP" "Emergency parallel cleanup triggered"

  # Kill all tracked parallel agent PIDs
  if [ -n "$PARALLEL_PIDS" ]; then
    for pid in $PARALLEL_PIDS; do
      if ps -p "$pid" > /dev/null 2>&1; then
        log "CLEANUP" "Killing parallel agent PID: $pid"
        kill -TERM "$pid" 2>/dev/null || true
      fi
    done

    # Wait briefly, then force kill stragglers
    sleep 2
    for pid in $PARALLEL_PIDS; do
      if ps -p "$pid" > /dev/null 2>&1; then
        kill -9 "$pid" 2>/dev/null || true
      fi
    done
  fi

  # Remove all worktrees under the worktree base directory
  if [ -n "$WORKTREE_BASE" ] && [ -d "$WORKTREE_BASE" ]; then
    log "CLEANUP" "Removing worktree directory: $WORKTREE_BASE"

    # List and remove each worktree properly
    git worktree list --porcelain 2>/dev/null | grep "^worktree " | while read -r _ wt_path; do
      case "$wt_path" in
        "$WORKTREE_BASE"/*)
          log "CLEANUP" "Removing worktree: $wt_path"
          git worktree remove --force "$wt_path" 2>/dev/null || true
          ;;
      esac
    done

    # Clean up any remaining dirs
    rm -rf "$WORKTREE_BASE" 2>/dev/null || true
  fi

  # Prune stale worktree references
  git worktree prune 2>/dev/null || true

  # Clean up story branches
  git branch --list "${BRANCH_NAME}-US-*" 2>/dev/null | while read -r branch; do
    branch=$(echo "$branch" | tr -d ' *')
    if [ -n "$branch" ]; then
      log "CLEANUP" "Removing story branch: $branch"
      git branch -D "$branch" 2>/dev/null || true
    fi
  done

  log "CLEANUP" "Parallel cleanup complete"
}

# ============================================================================
# Parallel Execution Core (Phase 3)
# ============================================================================

# Process tracking — space-separated lists (bash 3.2 compatible)
PARALLEL_PIDS=""
PARALLEL_STORIES=""
PARALLEL_DIRS=""
PARALLEL_OUTPUTS=""
PARALLEL_BRANCHES=""

# Helper: get the Nth item from a space-separated list
# Args: list_string, index (0-based)
list_get() {
  local list="$1"
  local idx="$2"
  echo "$list" | tr ' ' '\n' | sed -n "$((idx + 1))p"
}

# Helper: count items in a space-separated list
list_count() {
  local list="$1"
  if [ -z "$list" ]; then
    echo 0
  else
    echo "$list" | tr ' ' '\n' | wc -l | tr -d ' '
  fi
}

# Spawn a parallel agent in a worktree
# Args: story_id, worktree_dir, prompt_file
# Sets: appends to PARALLEL_PIDS, PARALLEL_STORIES, PARALLEL_DIRS, PARALLEL_OUTPUTS
spawn_parallel_agent() {
  local story_id="$1"
  local worktree_dir="$2"
  local prompt_file="$3"

  local output_file="/tmp/taskplex-parallel-$$-${story_id}.json"

  log "PARALLEL" "Spawning agent for $story_id in $worktree_dir"

  # Pre-expand prompt content to avoid race condition with file deletion
  local prompt_content
  prompt_content=$(cat "$prompt_file")

  # Run claude in the worktree directory
  (
    cd "$worktree_dir" && \
    $TIMEOUT_CMD "$ITERATION_TIMEOUT" claude -p "$prompt_content" \
      --output-format json \
      --no-session-persistence \
      --model "$EXECUTION_MODEL" \
      --agent implementer \
      --agents-dir "$PLUGIN_ROOT/agents" \
      --max-turns "$MAX_TURNS" \
      > "$output_file" 2>&1
  ) &

  local pid=$!

  # Append to tracking lists
  if [ -z "$PARALLEL_PIDS" ]; then
    PARALLEL_PIDS="$pid"
    PARALLEL_STORIES="$story_id"
    PARALLEL_DIRS="$worktree_dir"
    PARALLEL_OUTPUTS="$output_file"
  else
    PARALLEL_PIDS="$PARALLEL_PIDS $pid"
    PARALLEL_STORIES="$PARALLEL_STORIES $story_id"
    PARALLEL_DIRS="$PARALLEL_DIRS $worktree_dir"
    PARALLEL_OUTPUTS="$PARALLEL_OUTPUTS $output_file"
  fi

  log "PARALLEL" "Agent for $story_id spawned with PID: $pid"
}

# Wait for all parallel agents to complete
# Args: timeout_seconds
# Returns: 0 if all succeeded, 1 if any failed
wait_for_agents() {
  local timeout="$1"
  local start_time=$(date +%s)
  local all_done=0
  local poll_interval=5

  log "PARALLEL" "Waiting for $(list_count "$PARALLEL_PIDS") agents (timeout: ${timeout}s)"

  while [ $all_done -eq 0 ]; do
    all_done=1
    local elapsed=$(( $(date +%s) - start_time ))

    if [ "$elapsed" -ge "$timeout" ]; then
      log "TIMEOUT" "Parallel wave timeout after ${elapsed}s"
      # Kill remaining agents
      for pid in $PARALLEL_PIDS; do
        if ps -p "$pid" > /dev/null 2>&1; then
          local sid=$(get_story_for_pid "$pid")
          log "TIMEOUT" "Killing timed-out agent for $sid (PID: $pid)"
          kill -TERM "$pid" 2>/dev/null || true
        fi
      done
      sleep 2
      for pid in $PARALLEL_PIDS; do
        if ps -p "$pid" > /dev/null 2>&1; then
          kill -9 "$pid" 2>/dev/null || true
        fi
      done
      return 1
    fi

    # Check each PID
    for pid in $PARALLEL_PIDS; do
      if ps -p "$pid" > /dev/null 2>&1; then
        all_done=0
      fi
    done

    if [ $all_done -eq 0 ]; then
      local running=0
      for pid in $PARALLEL_PIDS; do
        if ps -p "$pid" > /dev/null 2>&1; then
          running=$((running + 1))
        fi
      done
      log "PARALLEL" "Still running: $running agents (${elapsed}s elapsed)"
      sleep "$poll_interval"
    fi
  done

  log "PARALLEL" "All agents completed"
  return 0
}

# Helper: get story_id for a given PID using positional matching
get_story_for_pid() {
  local target_pid="$1"
  local idx=0

  for pid in $PARALLEL_PIDS; do
    if [ "$pid" = "$target_pid" ]; then
      list_get "$PARALLEL_STORIES" "$idx"
      return 0
    fi
    idx=$((idx + 1))
  done

  echo "unknown"
}

# Reset parallel tracking lists between batches
reset_parallel_tracking() {
  PARALLEL_PIDS=""
  PARALLEL_STORIES=""
  PARALLEL_DIRS=""
  PARALLEL_OUTPUTS=""
  PARALLEL_BRANCHES=""
}

# ============================================================================
# Merge and Knowledge (Phase 4)
# ============================================================================

# Merge a story branch back into the feature branch
# Args: story_id, story_branch, feature_branch
# Returns: 0 on success, 1 on conflict
merge_story_branch() {
  local story_id="$1"
  local story_branch="$2"
  local feature_branch="$3"

  log "MERGE" "Merging $story_branch into $feature_branch"

  # Ensure we're on the feature branch
  local current_branch
  current_branch=$(git branch --show-current 2>/dev/null)
  if [ "$current_branch" != "$feature_branch" ]; then
    if ! git checkout "$feature_branch" 2>&1; then
      log "ERROR" "Failed to checkout $feature_branch for merge"
      return 1
    fi
  fi

  # Merge with --no-ff to preserve story branch history
  local merge_msg="feat($story_id): merge parallel story branch"
  if git merge --no-ff "$story_branch" -m "$merge_msg" 2>&1; then
    log "MERGE" "Successfully merged $story_branch"
    return 0
  else
    log "ERROR" "Merge conflict for $story_branch"
    return 1
  fi
}

# Handle a merge conflict based on conflict_strategy config
# Args: story_id, story_branch, feature_branch
# Returns: 0 if resolved, 1 if aborted
handle_merge_conflict() {
  local story_id="$1"
  local story_branch="$2"
  local feature_branch="$3"

  if [ "$CONFLICT_STRATEGY" = "merger" ]; then
    log "MERGE" "Invoking merger agent for $story_id conflict resolution"

    # Abort the current failed merge first
    git merge --abort 2>/dev/null || true

    # Attempt merge again via merger agent
    local merger_prompt="Resolve the merge conflict between branch '$story_branch' and '$feature_branch'.
Steps:
1. git merge --no-ff $story_branch
2. Resolve any conflicts by examining both sides
3. Prefer the story branch changes when unclear
4. Stage resolved files and commit the merge"

    local merger_output
    merger_output=$($TIMEOUT_CMD 300 claude -p "$merger_prompt" \
      --output-format json \
      --no-session-persistence \
      --agent merger \
      --agents-dir "$PLUGIN_ROOT/agents" \
      2>&1)

    if [ $? -eq 0 ]; then
      log "MERGE" "Merger agent resolved conflict for $story_id"
      return 0
    else
      log "ERROR" "Merger agent failed to resolve conflict for $story_id"
      git merge --abort 2>/dev/null || true
      return 1
    fi
  else
    # abort strategy (default) — skip the story
    log "MERGE" "Aborting merge for $story_id (conflict_strategy=abort)"
    git merge --abort 2>/dev/null || true
    return 1
  fi
}

# ============================================================================
# Wave Orchestration
# ============================================================================

# Run a single wave of parallel stories
# Args: wave_number, wave_stories_json (JSON array of story IDs)
# Returns: 0 if wave completed, 1 if errors occurred
run_wave_parallel() {
  local wave_num="$1"
  local wave_stories="$2"

  local feature_branch
  feature_branch=$(jq -r '.branchName // empty' "$PRD_FILE")

  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Wave $wave_num — $(echo "$wave_stories" | jq -r '. | length') stories"
  echo "═══════════════════════════════════════════════════════"

  # Split wave into conflict-free batches
  local batches
  batches=$(split_wave_by_conflicts "$wave_stories")
  local batch_count
  batch_count=$(echo "$batches" | jq '. | length')

  log "WAVE-$wave_num" "Split into $batch_count batch(es)"

  local wave_learnings=""
  local wave_has_errors=0

  # Process each batch
  local batch_idx=0
  while [ "$batch_idx" -lt "$batch_count" ]; do
    local batch
    batch=$(echo "$batches" | jq ".[$batch_idx]")
    local batch_size
    batch_size=$(echo "$batch" | jq '. | length')

    log "WAVE-$wave_num" "Batch $((batch_idx + 1))/$batch_count: $batch_size stories"

    # Reset tracking for this batch
    reset_parallel_tracking

    # Create worktrees and spawn agents for each story in the batch
    local story_idx=0
    while [ "$story_idx" -lt "$batch_size" ]; do
      local story_id
      story_id=$(echo "$batch" | jq -r ".[$story_idx]")

      # Mark story as in progress
      update_story_status "$story_id" "in_progress"
      log_progress "$story_id" "STARTED" "wave $wave_num, batch $((batch_idx + 1))"

      # Create worktree
      local worktree_dir
      worktree_dir=$(create_worktree "$story_id" "$feature_branch" "$WORKTREE_BASE")

      if [ $? -ne 0 ] || [ -z "$worktree_dir" ]; then
        log "ERROR" "Failed to create worktree for $story_id, skipping"
        update_story_status "$story_id" "skipped" "Worktree creation failed" "unknown"
        story_idx=$((story_idx + 1))
        continue
      fi

      local story_branch="${feature_branch}-${story_id}"

      # Track branch name
      if [ -z "$PARALLEL_BRANCHES" ]; then
        PARALLEL_BRANCHES="$story_branch"
      else
        PARALLEL_BRANCHES="$PARALLEL_BRANCHES $story_branch"
      fi

      # Setup worktree (npm install, etc.)
      setup_worktree "$worktree_dir"

      # Generate context brief
      local context_brief
      context_brief=$(generate_context_brief "$story_id")

      # Build full prompt
      local prompt_file="/tmp/taskplex-prompt-$$-${story_id}.md"
      cat "$context_brief" > "$prompt_file"
      echo "" >> "$prompt_file"
      echo "---" >> "$prompt_file"
      echo "" >> "$prompt_file"
      cat "$SCRIPT_DIR/prompt.md" >> "$prompt_file"

      # Spawn agent
      spawn_parallel_agent "$story_id" "$worktree_dir" "$prompt_file"

      # Clean up prompt/brief files (agent reads them at spawn)
      rm -f "$context_brief" "$prompt_file"

      # Count iteration
      TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

      story_idx=$((story_idx + 1))
    done

    # Wait for all agents in this batch
    wait_for_agents "$ITERATION_TIMEOUT"

    # Process results for each story in the batch
    story_idx=0
    local pid_list="$PARALLEL_PIDS"
    local story_list="$PARALLEL_STORIES"
    local dir_list="$PARALLEL_DIRS"
    local output_list="$PARALLEL_OUTPUTS"
    local branch_list="$PARALLEL_BRANCHES"

    while [ "$story_idx" -lt "$batch_size" ]; do
      local story_id
      story_id=$(list_get "$story_list" "$story_idx")
      local pid
      pid=$(list_get "$pid_list" "$story_idx")
      local worktree_dir
      worktree_dir=$(list_get "$dir_list" "$story_idx")
      local output_file
      output_file=$(list_get "$output_list" "$story_idx")
      local story_branch
      story_branch=$(list_get "$branch_list" "$story_idx")

      # Skip stories that failed worktree creation
      if [ -z "$worktree_dir" ] || [ -z "$pid" ]; then
        story_idx=$((story_idx + 1))
        continue
      fi

      # Check agent exit status
      local agent_exit=0
      if ! wait "$pid" 2>/dev/null; then
        agent_exit=$?
      fi

      # Read output
      local output
      output=$(cat "$output_file" 2>/dev/null || echo '{"error": "no output"}')
      rm -f "$output_file"

      if [ "$agent_exit" -ne 0 ]; then
        # Agent failed
        log "PARALLEL" "Agent for $story_id failed (exit: $agent_exit)"
        log_progress "$story_id" "FAILED" "exit code $agent_exit in parallel wave $wave_num"

        local category
        category=$(categorize_error "$agent_exit" "$output")
        update_story_status "$story_id" "skipped" "Failed in parallel wave" "$category"
        add_knowledge_warning "$story_id" "$category" "$(echo "$output" | head -c 150 | tr '\n' ' ')"
        wave_has_errors=1
      else
        # Agent succeeded — extract learnings
        log "PARALLEL" "Agent for $story_id completed successfully"
        extract_learnings "$story_id" "$output"

        # Collect learnings for wave-level knowledge update
        local story_learnings
        story_learnings=$(echo "$output" | jq -r '.result // . | if type == "string" then (try fromjson catch {}) else . end | .learnings // [] | .[]' 2>/dev/null)
        if [ -n "$story_learnings" ]; then
          wave_learnings="${wave_learnings}${story_learnings}\n"
        fi

        # Merge story branch into feature branch
        if merge_story_branch "$story_id" "$story_branch" "$feature_branch"; then
          # Run validator
          if run_validator "$story_id"; then
            update_story_status "$story_id" "completed"
            log_progress "$story_id" "COMPLETED" "wave $wave_num"

            # Commit story in feature branch context if needed
            local story_title
            story_title=$(jq -r --arg id "$story_id" '.userStories[] | select(.id == $id) | .title' "$PRD_FILE")
            commit_story "$story_id" "$story_title"
          else
            log "PARALLEL" "Validation failed for $story_id"
            log_progress "$story_id" "VALIDATION_FAILED" "wave $wave_num"

            # Check if retries remain — defer to next wave
            local attempts
            attempts=$(jq -r --arg id "$story_id" '.userStories[] | select(.id == $id) | .attempts // 0' "$PRD_FILE")
            if [ "$attempts" -lt "$MAX_RETRIES_PER_STORY" ]; then
              log "PARALLEL" "$story_id deferred to next wave for retry"
              # Reset status to pending so it gets picked up
              TEMP_PRD=$(mktemp)
              jq --arg id "$story_id" '
                .userStories |= map(if .id == $id then .status = "pending" | .passes = false else . end)
              ' "$PRD_FILE" > "$TEMP_PRD" && mv "$TEMP_PRD" "$PRD_FILE"
            else
              update_story_status "$story_id" "skipped" "Validation failed after max retries" "test_failure"
            fi
            wave_has_errors=1
          fi
        else
          # Merge conflict
          log "PARALLEL" "Merge conflict for $story_id"
          if handle_merge_conflict "$story_id" "$story_branch" "$feature_branch"; then
            update_story_status "$story_id" "completed"
            log_progress "$story_id" "COMPLETED" "wave $wave_num (conflict resolved)"
          else
            log_progress "$story_id" "MERGE_CONFLICT" "wave $wave_num"
            # Defer retry if attempts remain
            local attempts
            attempts=$(jq -r --arg id "$story_id" '.userStories[] | select(.id == $id) | .attempts // 0' "$PRD_FILE")
            if [ "$attempts" -lt "$MAX_RETRIES_PER_STORY" ]; then
              TEMP_PRD=$(mktemp)
              jq --arg id "$story_id" '
                .userStories |= map(if .id == $id then .status = "pending" | .passes = false else . end)
              ' "$PRD_FILE" > "$TEMP_PRD" && mv "$TEMP_PRD" "$PRD_FILE"
            else
              update_story_status "$story_id" "skipped" "Merge conflict unresolvable" "unknown"
            fi
            wave_has_errors=1
          fi
        fi
      fi

      # Clean up worktree
      cleanup_worktree "$story_id" "$worktree_dir" "$story_branch"

      story_idx=$((story_idx + 1))
    done

    batch_idx=$((batch_idx + 1))
  done

  # Trim knowledge after wave
  trim_knowledge

  if [ "$wave_has_errors" -ne 0 ]; then
    return 1
  fi
  return 0
}

# ============================================================================
# Main Parallel Loop Entry Point
# ============================================================================

# Run the full parallel execution loop
# Called from taskplex.sh instead of the sequential for-loop
run_parallel_loop() {
  log "PARALLEL" "Starting parallel execution mode"

  # Compute worktree base directory
  if [ -n "$WORKTREE_DIR" ] && [ "$WORKTREE_DIR" != "" ]; then
    WORKTREE_BASE="$WORKTREE_DIR"
  else
    WORKTREE_BASE="$(dirname "$PROJECT_DIR")/.worktrees/$(basename "$PROJECT_DIR")"
  fi
  mkdir -p "$WORKTREE_BASE"
  log "PARALLEL" "Worktree base: $WORKTREE_BASE"

  # Track total iterations for max_iterations limit
  TOTAL_ITERATIONS=0

  # Compute waves
  local waves
  waves=$(compute_waves)
  local total_waves
  total_waves=$(echo "$waves" | jq '. | length')

  log "PARALLEL" "Computed $total_waves wave(s)"
  echo ""
  echo "Parallel execution plan: $total_waves wave(s)"
  echo "$waves" | jq -r '.[] | "  Wave \(.wave): \(.stories | join(", "))"'
  echo ""

  # Execute each wave
  local wave_idx=0
  while [ "$wave_idx" -lt "$total_waves" ]; do
    # Check iteration budget
    if [ "$TOTAL_ITERATIONS" -ge "$MAX_ITERATIONS" ]; then
      log "PARALLEL" "Max iterations ($MAX_ITERATIONS) reached at wave $wave_idx"
      break
    fi

    local wave_stories
    wave_stories=$(echo "$waves" | jq ".[$wave_idx].stories")

    # Filter out already-completed stories (from retries or previous runs)
    wave_stories=$(echo "$wave_stories" | jq --slurpfile prd "$PRD_FILE" '
      [.[] | . as $sid |
        $prd[0].userStories[] | select(.id == $sid) |
        select(.passes != true and .status != "skipped") | $sid
      ]
    ')

    local wave_count
    wave_count=$(echo "$wave_stories" | jq '. | length')

    if [ "$wave_count" -eq 0 ]; then
      log "WAVE-$wave_idx" "All stories in wave already complete, skipping"
      wave_idx=$((wave_idx + 1))
      continue
    fi

    run_wave_parallel "$wave_idx" "$wave_stories"

    # Check for overall completion
    local incomplete_count
    incomplete_count=$(jq '[.userStories[] | select(.passes == false and .status != "skipped")] | length' "$PRD_FILE")

    if [ "$incomplete_count" -eq 0 ]; then
      log "PARALLEL" "All stories complete after wave $wave_idx"
      break
    fi

    # Recompute waves for next iteration (handles deferred retries)
    waves=$(compute_waves)
    total_waves=$(echo "$waves" | jq '. | length')

    wave_idx=$((wave_idx + 1))
  done

  # Final status check
  local completed_count
  completed_count=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE")
  local total_count
  total_count=$(jq '[.userStories[]] | length' "$PRD_FILE")
  local skipped_count
  skipped_count=$(jq '[.userStories[] | select(.status == "skipped")] | length' "$PRD_FILE")

  echo ""
  if [ "$completed_count" -eq "$total_count" ]; then
    echo "All $total_count stories completed in $((wave_idx)) wave(s)!"
    return 0
  elif [ "$((completed_count + skipped_count))" -eq "$total_count" ]; then
    echo "Finished with $completed_count completed, $skipped_count skipped"
    return 1
  else
    local remaining=$((total_count - completed_count - skipped_count))
    echo "Parallel execution ended: $completed_count completed, $skipped_count skipped, $remaining remaining"
    return 1
  fi
}
