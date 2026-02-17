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
  # Claude's --output-format json returns {"result": "..."} where .result is
  # a string containing the model's output. The model output itself is JSON,
  # so we need double-parsing: extract .result then fromjson.
  local action model effort reasoning
  action=$(echo "$result" | jq -r '.result // "" | if type == "string" then (try fromjson catch {}) else . end | .action // "implement"' 2>/dev/null)
  model=$(echo "$result" | jq -r '.result // "" | if type == "string" then (try fromjson catch {}) else . end | .model // "'"$EXECUTION_MODEL"'"' 2>/dev/null)
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
