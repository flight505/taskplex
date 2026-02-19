#!/bin/bash
# pre-compact.sh — PreCompact hook
# Saves current story state and progress to SQLite before context compaction.
# This preserves knowledge that would otherwise be lost when a long-running
# implementer agent hits context limits mid-story.
#
# Input: JSON on stdin with trigger ("manual"|"auto"), transcript_path, session_id
# Output: none (informational only — PreCompact cannot block compaction)
# Exit 0 always
# NOTE: set -e intentionally omitted — hook must not fail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/knowledge-db.sh" 2>/dev/null || exit 0

# Read hook input
HOOK_INPUT=$(cat)
TRIGGER=$(echo "$HOOK_INPUT" | jq -r '.trigger // "unknown"' 2>/dev/null)

# Find project state
PROJECT_DIR="$(pwd)"
PRD_FILE="$PROJECT_DIR/prd.json"
CONFIG_FILE="$PROJECT_DIR/.claude/taskplex.config.json"
KNOWLEDGE_DB="$PROJECT_DIR/knowledge.db"

if [ -f "$CONFIG_FILE" ]; then
  CONFIGURED_DB=$(jq -r '.knowledge_db // ""' "$CONFIG_FILE" 2>/dev/null)
  [ -n "$CONFIGURED_DB" ] && KNOWLEDGE_DB="$PROJECT_DIR/$CONFIGURED_DB"
fi

# Bail if no DB or no PRD
if [ ! -f "$KNOWLEDGE_DB" ] || [ ! -f "$PRD_FILE" ]; then
  exit 0
fi

# Find current in_progress story
STORY_ID=$(jq -r '.userStories[] | select(.status == "in_progress") | .id' "$PRD_FILE" 2>/dev/null | head -1)

if [ -z "$STORY_ID" ]; then
  exit 0
fi

# Gather state to preserve
STORY_TITLE=$(jq -r --arg id "$STORY_ID" '.userStories[] | select(.id == $id) | .title' "$PRD_FILE" 2>/dev/null)
STORY_ATTEMPTS=$(jq -r --arg id "$STORY_ID" '.userStories[] | select(.id == $id) | .attempts // 1' "$PRD_FILE" 2>/dev/null)

# Get recent git changes (files modified since story started)
RECENT_CHANGES=$(git diff --stat HEAD~3 2>/dev/null | head -20 || echo "no recent changes")

# Get staged files
STAGED=$(git diff --cached --name-only 2>/dev/null | head -10 || echo "none")

# Build context summary
CONTEXT_SUMMARY="[Pre-compact snapshot] Story ${STORY_ID}: ${STORY_TITLE} (attempt ${STORY_ATTEMPTS}, trigger: ${TRIGGER}). Recent changes: ${RECENT_CHANGES}. Staged: ${STAGED}."

# Save to SQLite as high-confidence learning (tagged for recovery)
save_compaction_snapshot "$KNOWLEDGE_DB" "$STORY_ID" "$CONTEXT_SUMMARY" 2>/dev/null || true

# Also write a recovery file that survives compaction
RECOVERY_FILE="$PROJECT_DIR/.claude/taskplex-pre-compact.json"
mkdir -p "$(dirname "$RECOVERY_FILE")"
jq -n \
  --arg story_id "$STORY_ID" \
  --arg story_title "$STORY_TITLE" \
  --arg attempts "$STORY_ATTEMPTS" \
  --arg trigger "$TRIGGER" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg recent_changes "$RECENT_CHANGES" \
  '{
    story_id: $story_id,
    story_title: $story_title,
    attempts: ($attempts | tonumber),
    trigger: $trigger,
    timestamp: $timestamp,
    recent_changes: $recent_changes
  }' > "$RECOVERY_FILE" 2>/dev/null || true

exit 0
