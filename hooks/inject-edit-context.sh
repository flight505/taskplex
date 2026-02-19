#!/bin/bash
# inject-edit-context.sh — PreToolUse hook for Edit/Write
# Injects file-specific guidance from SQLite before each edit.
#
# Input: JSON on stdin with tool_name, tool_input (file_path, etc.)
# Output: JSON on stdout with hookSpecificOutput.additionalContext
# Exit 0 always — never blocks edits
# NOTE: set -e intentionally omitted — hook requires explicit exit code control

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/knowledge-db.sh" 2>/dev/null || { echo '{}'; exit 0; }

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Extract file path from tool_input
FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  echo '{}'
  exit 0
fi

# Find knowledge DB
PROJECT_DIR="$(pwd)"
CONFIG_FILE="$PROJECT_DIR/.claude/taskplex.config.json"
KNOWLEDGE_DB="$PROJECT_DIR/knowledge.db"
if [ -f "$CONFIG_FILE" ]; then
  CONFIGURED_DB=$(jq -r '.knowledge_db // ""' "$CONFIG_FILE" 2>/dev/null)
  [ -n "$CONFIGURED_DB" ] && KNOWLEDGE_DB="$PROJECT_DIR/$CONFIGURED_DB"
fi

if [ ! -f "$KNOWLEDGE_DB" ]; then
  echo '{}'
  exit 0
fi

# Build context from file patterns and relevant learnings
CONTEXT=""

# 1. File-specific patterns from file_patterns table
PATTERNS=$(query_file_patterns "$KNOWLEDGE_DB" "$FILE_PATH" 2>/dev/null)
if [ -n "$PATTERNS" ]; then
  CONTEXT="File patterns for $(basename "$FILE_PATH"):
"
  while IFS='|' read -r pattern_type description source_story; do
    [ -z "$pattern_type" ] && continue
    CONTEXT="${CONTEXT}- [${pattern_type}] ${description}${source_story:+ (from $source_story)}
"
  done <<< "$PATTERNS"
fi

# 2. Learnings mentioning this file or its directory
# Extract relative path components for tag matching
REL_PATH=$(echo "$FILE_PATH" | sed "s|^$PROJECT_DIR/||")
DIR_PATH=$(dirname "$REL_PATH")

TAGS_JSON="[\"$(echo "$REL_PATH" | sed "s/'/''/g")\",\"$(echo "$DIR_PATH" | sed "s/'/''/g")\"]"
LEARNINGS=$(query_learnings "$KNOWLEDGE_DB" 5 "$TAGS_JSON" 2>/dev/null)

if [ -n "$LEARNINGS" ]; then
  CONTEXT="${CONTEXT}${CONTEXT:+
}Relevant learnings:
"
  while IFS='|' read -r content story_id confidence; do
    [ -z "$content" ] && continue
    CONTEXT="${CONTEXT}- ${content}
"
  done <<< "$LEARNINGS"
fi

# If no context found, exit clean
if [ -z "$CONTEXT" ]; then
  echo '{}'
  exit 0
fi

# Escape for JSON and return
ESCAPED_CONTEXT=$(echo "$CONTEXT" | jq -Rs '.' 2>/dev/null)

cat <<HOOK_OUTPUT
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": ${ESCAPED_CONTEXT}
  }
}
HOOK_OUTPUT

exit 0
