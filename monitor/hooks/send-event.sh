#!/bin/bash
# TaskPlex Monitor — Universal event sender
# Called by each hook script to forward events to the monitor server.
# Reads hook payload from stdin, enriches with event type, POSTs to server.
# Always exits 0 — never blocks Claude Code.
# NOTE: no set -e — failures must not produce non-zero exit

EVENT_TYPE="${1:-unknown}"
MONITOR_PORT="${TASKPLEX_MONITOR_PORT:-4444}"

# Read payload from stdin
PAYLOAD=$(cat -)

# Check if monitor is running (1s connect timeout)
if ! curl -s --connect-timeout 1 "http://localhost:${MONITOR_PORT}/health" > /dev/null 2>&1; then
  exit 0
fi

# Extract fields from hook payload
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null)
AGENT_NAME=$(echo "$PAYLOAD" | jq -r '.agent_name // empty' 2>/dev/null)
TOOL_NAME=$(echo "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null)

# Build event JSON
EVENT=$(jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg src "hook" \
  --arg et "$EVENT_TYPE" \
  --arg sid "$SESSION_ID" \
  --argjson pl "$PAYLOAD" \
  '{
    timestamp: $ts,
    source: $src,
    event_type: $et,
    session_id: (if $sid == "" then null else $sid end),
    payload: $pl
  }')

# Fire-and-forget POST
curl -s -X POST "http://localhost:${MONITOR_PORT}/api/events" \
  -H "Content-Type: application/json" \
  -d "$EVENT" > /dev/null 2>&1 &

exit 0
