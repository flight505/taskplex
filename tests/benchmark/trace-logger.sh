#!/usr/bin/env bash
# trace-logger.sh — Structured event logger for benchmark traces
#
# Usage:
#   source trace-logger.sh
#   trace_init "S001" "taskplex" "/path/to/trace.json"
#   trace_event "skill_invoked" '{"skill":"taskplex-tdd"}'
#   trace_finalize
#
# Events are buffered in memory and flushed on finalize.
# The trace file is a JSON object with an events array.
#
# Dependencies: jq, bash 3.2+

# Global state
_TRACE_FILE=""
_TRACE_STORY_ID=""
_TRACE_PLUGIN=""
_TRACE_EVENTS_FILE=""
_TRACE_START_TIME=""

trace_init() {
  local story_id="${1:?trace_init requires story_id}"
  local plugin="${2:?trace_init requires plugin name}"
  local trace_file="${3:?trace_init requires output path}"

  _TRACE_FILE="$trace_file"
  _TRACE_STORY_ID="$story_id"
  _TRACE_PLUGIN="$plugin"
  _TRACE_START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Temp file for event accumulation (one JSON object per line)
  _TRACE_EVENTS_FILE=$(mktemp "${TMPDIR:-/tmp}/trace-events.XXXXXX")

  # Write header
  echo "# Trace started: $_TRACE_START_TIME" > "$_TRACE_EVENTS_FILE"
}

trace_event() {
  local event_type="${1:?trace_event requires event type}"
  local data="${2:-{}}"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Append event as JSON line
  jq -nc \
    --arg ts "$timestamp" \
    --arg event "$event_type" \
    --arg story "$_TRACE_STORY_ID" \
    --arg plugin "$_TRACE_PLUGIN" \
    --argjson data "$data" \
    '{timestamp: $ts, event: $event, story_id: $story, plugin: $plugin} + $data' \
    >> "$_TRACE_EVENTS_FILE"
}

trace_finalize() {
  local end_time
  end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Read all events (skip the comment header line)
  local events_json
  events_json=$(grep -v '^#' "$_TRACE_EVENTS_FILE" | jq -s '.')

  # Compute summary counts
  local total_events
  total_events=$(echo "$events_json" | jq 'length')

  # Build final trace file
  jq -n \
    --arg story_id "$_TRACE_STORY_ID" \
    --arg plugin "$_TRACE_PLUGIN" \
    --arg start_time "$_TRACE_START_TIME" \
    --arg end_time "$end_time" \
    --argjson events "$events_json" \
    --argjson total_events "$total_events" \
    '{
      story_id: $story_id,
      plugin: $plugin,
      start_time: $start_time,
      end_time: $end_time,
      total_events: $total_events,
      events: $events
    }' > "$_TRACE_FILE"

  # Clean up
  rm -f "$_TRACE_EVENTS_FILE"

  echo "Trace written: $_TRACE_FILE ($total_events events)"
}

# ─────────────────────────────────────────────
# Convenience functions for common events
# ─────────────────────────────────────────────

trace_skill_invoked() {
  local skill="${1:?requires skill name}"
  local phase="${2:-execution}"
  trace_event "skill_invoked" "$(jq -nc --arg s "$skill" --arg p "$phase" '{skill:$s, phase:$p}')"
}

trace_agent_dispatched() {
  local agent="${1:?requires agent name}"
  local story_id="${2:-$_TRACE_STORY_ID}"
  trace_event "agent_dispatched" "$(jq -nc --arg a "$agent" --arg s "$story_id" '{agent:$a, for_story:$s}')"
}

trace_hook_fired() {
  local hook="${1:?requires hook name}"
  local result="${2:-ok}"
  local event_type="${3:-unknown}"
  trace_event "hook_fired" "$(jq -nc --arg h "$hook" --arg r "$result" --arg e "$event_type" '{hook:$h, result:$r, hook_event:$e}')"
}

trace_test_executed() {
  local command="${1:?requires command}"
  local pass="${2:?requires pass (true/false)}"
  local phase="${3:-execution}"
  trace_event "test_executed" "$(jq -nc --arg c "$command" --argjson p "$pass" --arg ph "$phase" '{command:$c, pass:$p, phase:$ph}')"
}

trace_commit_created() {
  local message="${1:?requires message}"
  local files_changed="${2:-0}"
  trace_event "commit_created" "$(jq -nc --arg m "$message" --argjson f "$files_changed" '{message:$m, files_changed:$f}')"
}

trace_error_occurred() {
  local error_type="${1:?requires error type}"
  local message="${2:-}"
  trace_event "error_occurred" "$(jq -nc --arg t "$error_type" --arg m "$message" '{error_type:$t, message:$m}')"
}

trace_error_recovered() {
  local error_type="${1:?requires error type}"
  local strategy="${2:-retry}"
  trace_event "error_recovered" "$(jq -nc --arg t "$error_type" --arg s "$strategy" '{error_type:$t, strategy:$s}')"
}

trace_human_intervention() {
  local reason="${1:?requires reason}"
  trace_event "human_intervention" "$(jq -nc --arg r "$reason" '{reason:$r}')"
}

trace_permission_blocked() {
  local tool="${1:?requires tool name}"
  trace_event "permission_blocked" "$(jq -nc --arg t "$tool" '{tool:$t}')"
}

trace_completion_claimed() {
  local verified="${1:-false}"
  trace_event "completion_claimed" "$(jq -nc --argjson v "$verified" '{verified:$v}')"
}
