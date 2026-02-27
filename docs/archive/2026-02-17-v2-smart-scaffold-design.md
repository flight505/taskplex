# TaskPlex v2.0 Design: Smart Scaffold Architecture

**Date:** 2026-02-17
**Author:** Jesper Vang (@flight505) + Claude Opus 4.6
**Approach:** A — "Smart Scaffold" (bash infrastructure + hook-based intelligence)
**Target version:** 2.0.0

---

## 1. Design Philosophy

Keep bash as the reliable infrastructure layer. Add intelligence through three mechanisms:

1. **1-shot decision calls** — before each story, ask Opus (effort:low) whether to implement, retry differently, skip, or rewrite the story
2. **SubagentStart hook** — inject context from SQLite knowledge store into every agent spawn
3. **SubagentStop hook** — run inline validation, extract learnings, block agent if validation fails (agent self-heals in same context)

No persistent orchestrator. No compaction dependency. No beta API features.

**Why:** At 200-story scale, a persistent Opus orchestrator costs ~$50-60 in overhead alone (3.5-8x v1.2.1). The Smart Scaffold adds ~$0.25 total overhead (~1.1x v1.2.1) while capturing 90% of the intelligence gains.

---

## 2. Architecture Overview

```
taskplex.sh (bash scaffold — enhanced)
  ├── Process management (PID, signals, cleanup, worktrees)
  ├── Git operations (branch, merge, cleanup)
  ├── Story selection (jq-based, same as v1.2.1)
  │
  ├── NEW: decision_call() — 1-shot Opus call per story
  │     Input: story details, failure history, knowledge summary
  │     Output: {action, effort_level, model, modified_story?}
  │     Cost: ~$0.03/call (~5K tokens at $5/MTok)
  │
  ├── Spawns implementer via `claude -p` with model/effort from decision
  │
  └── Post-story: extract_learnings() from structured output → SQLite

SubagentStart hook (inject-knowledge.sh) — NEW
  ├── Queries SQLite for relevant learnings (story tags, file paths)
  ├── Runs check_before_implementing grep commands
  ├── Includes dependency diffs (moved from generate_context_brief)
  └── Returns JSON: {hookSpecificOutput: {additionalContext: "..."}}

SubagentStop hook (validate-result.sh) — NEW
  ├── Runs typecheck_command, build_command, test_command
  ├── Parses agent transcript for structured JSON output
  ├── Extracts learnings → SQLite via insert
  ├── If validation fails: exit 2 with {decision: "block", reason: "..."}
  └── Agent continues fixing in SAME context (no restart, no context loss)

SQLite knowledge store (knowledge.db) — NEW (replaces knowledge.md)
  ├── Table: learnings (id, story_id, content, confidence, tags, created_at)
  ├── Table: file_patterns (path_glob, pattern_type, description, source_story)
  ├── Table: error_history (story_id, category, message, attempt, resolved)
  ├── Table: decisions (story_id, action, model, effort, reasoning, created_at)
  ├── Confidence decay: score * 0.95^(days_since_created)
  └── Cross-run persistence (survives archive/new-run cycle)
```

---

## 3. Component Designs

### 3.1 Decision Call (`decision_call()`)

A new bash function in `taskplex.sh` that makes a 1-shot `claude -p` call before each story. Replaces the blind "pick next by priority" logic.

**When it runs:** After `get_next_task()` returns a story ID, before spawning the implementer.

**Input prompt (template):**

```
You are a task orchestrator deciding how to handle the next story.

## Story
{story JSON from prd.json}

## History
- Attempts: {N}
- Last error: {category}: {message}
- Retry hint from agent: {retry_hint}

## Knowledge Summary
{Top 10 relevant learnings from SQLite, sorted by confidence}

## Error Patterns
{Recent error_history entries for related stories}

## Decision Required
Respond with JSON only:
{
  "action": "implement" | "skip" | "rewrite",
  "model": "sonnet" | "opus" | "haiku",
  "effort_level": "" | "low" | "medium" | "high",
  "reasoning": "one sentence",
  "modified_story": null | {rewritten story object if action=rewrite}
}

Rules:
- First attempt with no errors: action=implement, model from config
- After 1 failed attempt: action=implement, consider model upgrade
- After 2+ failed attempts with same category: action=skip or rewrite
- env_missing/dependency_missing: always skip (agent can't fix these)
- Simple stories (1-2 criteria): model=haiku, effort=""
- Complex stories (5+ criteria): model=opus if configured, effort=high
```

**CLI invocation:**

```bash
decision_call() {
  local story_id="$1"
  local prompt_file="/tmp/taskplex-decision-$$-${story_id}.md"
  # ... generate prompt from template ...

  local result
  result=$(claude -p "$(cat "$prompt_file")" \
    --model opus \
    --output-format json \
    --max-turns 1 \
    --no-session-persistence 2>/dev/null)

  # Parse the JSON response
  local action model effort
  action=$(echo "$result" | jq -r '.result // "" | fromjson? // {} | .action // "implement"')
  model=$(echo "$result" | jq -r '.result // "" | fromjson? // {} | .model // "'$EXECUTION_MODEL'"')
  effort=$(echo "$result" | jq -r '.result // "" | fromjson? // {} | .effort_level // ""')

  # Store decision in SQLite for cost tracking
  sqlite3 "$KNOWLEDGE_DB" "INSERT INTO decisions ..."

  echo "${action}|${model}|${effort}"
}
```

**Cost:** ~5K input tokens + ~200 output tokens = ~$0.026/call at Opus $5/$25 pricing. For 200 stories: ~$5.20 total.

**Fallback:** If the decision call fails (timeout, parse error), fall back to v1.2.1 behavior: implement with configured model/effort.

---

### 3.2 SubagentStart Hook (`inject-knowledge.sh`)

Replaces `generate_context_brief()` in `taskplex.sh`. The key difference: this runs as a hook, so it works with ALL agent types (implementer, validator, merger) without orchestrator involvement.

**Hook config (correct syntax per CLI docs):**

```json
{
  "event": "SubagentStart",
  "matcher": "implementer|validator",
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/hooks/inject-knowledge.sh",
  "description": "Inject knowledge store context into agent spawn"
}
```

**Script behavior:**

1. Read `$HOOK_INPUT` from stdin (JSON with `agent_id`, `agent_type`)
2. Identify current story from prd.json (`status: "in_progress"`)
3. Query SQLite for relevant learnings:
   - Learnings tagged with files in this story's `related_to`
   - Learnings from dependency stories (`depends_on`)
   - Top-10 highest-confidence learnings (with decay applied)
   - Error history for this story (if retry)
4. Run `check_before_implementing` commands, capture output
5. Get dependency diffs (git diff from completed `depends_on` stories)
6. Assemble context brief as markdown string
7. Output JSON to stdout:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": "# Context Brief for US-003\n\n## Pre-Implementation Checks\n..."
  }
}
```

**What moves from orchestrator to hook:**
- `generate_context_brief()` logic (lines 264-346 of taskplex.sh)
- `check_before_implementing` execution
- Dependency diff generation
- Knowledge file reading

**What stays in orchestrator:**
- Story selection and status management
- Decision calls
- Process management

---

### 3.3 SubagentStop Hook (`validate-result.sh`)

The most impactful new component. Replaces the separate validator agent for the common case and enables agent self-healing.

**Hook config:**

```json
{
  "event": "SubagentStop",
  "matcher": "implementer",
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/hooks/validate-result.sh",
  "description": "Inline validation — block agent if checks fail"
}
```

**Script behavior:**

1. Read `$HOOK_INPUT` from stdin (JSON with `agent_id`, `agent_type`, `agent_transcript_path`, `stop_hook_active`)
2. If `stop_hook_active` is true: exit 0 (prevent infinite validation loops)
3. Read the agent's transcript to find structured JSON output block
4. Extract learnings → insert into SQLite knowledge store
5. Run configured validation commands:
   - `typecheck_command` (e.g., `tsc --noEmit`)
   - `build_command` (e.g., `npm run build`)
   - `test_command` (e.g., `npm test`)
6. If ALL pass: exit 0 (agent stops normally, orchestrator sees success)
7. If ANY fail: exit 2 with blocking output:

```json
{
  "decision": "block",
  "reason": "Typecheck failed:\n  src/api/routes.ts(45): error TS2345: Argument of type 'string' is not assignable..."
}
```

The agent receives the `reason` as its next instruction and continues working in the same context. It has full memory of what it just implemented, so it can fix the issue without re-exploring the codebase.

**Max validation cycles:** The `stop_hook_active` flag prevents infinite loops. On the second SubagentStop for the same agent, the hook sees `stop_hook_active: true` and exits 0 regardless. If the agent still has failing checks, the orchestrator handles retry logic.

**What this replaces:**
- `validator.md` agent for post-implementation verification (still available for explicit use)
- The orchestrator's "parse output → check status → decide retry" cycle for validation failures

**What it does NOT replace:**
- Error categorization (orchestrator still categorizes if the agent ultimately fails)
- Skip/rewrite decisions (that's the decision call's job)

---

### 3.4 SQLite Knowledge Store (`knowledge.db`)

Replaces `knowledge.md` flat file. Uses SQLite (available on every system, no extra dependencies).

**Schema:**

```sql
-- Core learnings from agent outputs
CREATE TABLE learnings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  story_id TEXT NOT NULL,
  run_id TEXT,
  content TEXT NOT NULL,
  confidence REAL DEFAULT 1.0,  -- 0.0 to 1.0
  tags TEXT,                     -- JSON array of relevant file paths/concepts
  created_at TEXT DEFAULT (datetime('now')),
  source TEXT DEFAULT 'agent'    -- 'agent', 'orchestrator', 'user'
);

-- File/directory patterns discovered
CREATE TABLE file_patterns (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path_glob TEXT NOT NULL,       -- e.g., "src/api/*.ts"
  pattern_type TEXT NOT NULL,    -- 'barrel_export', 'test_location', 'config_pattern'
  description TEXT NOT NULL,
  source_story TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

-- Error history for pattern detection
CREATE TABLE error_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  story_id TEXT NOT NULL,
  run_id TEXT,
  category TEXT NOT NULL,        -- env_missing, test_failure, etc.
  message TEXT,
  attempt INTEGER DEFAULT 1,
  resolved INTEGER DEFAULT 0,    -- 1 if story eventually completed
  created_at TEXT DEFAULT (datetime('now'))
);

-- Decision audit trail
CREATE TABLE decisions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  story_id TEXT NOT NULL,
  run_id TEXT,
  action TEXT NOT NULL,          -- implement, skip, rewrite
  model TEXT,
  effort_level TEXT,
  reasoning TEXT,
  tokens_used INTEGER,
  created_at TEXT DEFAULT (datetime('now'))
);

-- Run metadata
CREATE TABLE runs (
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
```

**Confidence decay query:**

```sql
SELECT content, tags,
  confidence * POWER(0.95, julianday('now') - julianday(created_at)) AS effective_confidence
FROM learnings
WHERE effective_confidence > 0.3
ORDER BY effective_confidence DESC
LIMIT 10;
```

Learnings lose ~5% confidence per day. After ~14 days a learning at 1.0 drops to 0.49. After ~30 days it drops below 0.3 and gets excluded. This prevents stale knowledge from polluting context briefs.

**Migration from knowledge.md:** On first v2.0 run, if `knowledge.md` exists and `knowledge.db` does not, parse `knowledge.md` entries and insert them into the learnings table with confidence 0.8 (slightly decayed since they're from a previous format).

**Cross-run persistence:** The database file persists across runs. Archiving copies the DB to the archive folder. New runs start with the existing DB, so learnings compound across features.

**No new dependencies:** SQLite is built into macOS (`/usr/bin/sqlite3`) and available on all Linux distributions. The `sqlite3` CLI tool handles all operations — no Bun, Python, or Node required.

---

### 3.5 Model Routing

The decision call picks the model per story. Default rules (overridable by decision call):

| Story characteristics | Model | Effort | Rationale |
|----------------------|-------|--------|-----------|
| 1-2 acceptance criteria, no dependencies | haiku | — | Trivial work, cheapest option |
| 3-5 criteria, standard | sonnet (default) | — | Best cost/quality balance |
| 5+ criteria, or has failed before | from config | high | Complex work needs reasoning |
| Rewrite needed | opus | high | PRD rewriting requires intelligence |

**Effort levels:** Only applied when model is `opus`. Passed via `CLAUDE_CODE_EFFORT_LEVEL` env var (already implemented in v1.2.1 taskplex.sh line 900-903).

**Cost impact:** If 70% of stories use Sonnet ($3/$15), 20% use Haiku ($1/$5), and 10% use Opus ($5/$25), the blended per-story cost drops ~15% vs fixed Sonnet.

---

### 3.6 Agent Teams (Future Mode)

**Not implemented in v2.0.** Designed as a future `parallel_mode: "team"` option.

Agent Teams are functional (confirmed by user with full documentation), but have constraints that make them unsuitable as the default:
- Interactive-only (not headless/scriptable from bash)
- 15x token cost vs single agent
- Two teammates editing same file = overwrites
- No session recovery
- Teammates can't spawn sub-teams

**When to add:** When any of these are resolved: headless Agent Teams API, cost reduction, or session recovery. The Smart Scaffold architecture is additive — hooks and SQLite work regardless of whether the orchestrator is bash or an Agent Team lead.

**Preparation for future integration:** The decision call's `model` field and the SubagentStart/Stop hooks are agent-type-agnostic. They'll work with Agent Teams teammates the same way they work with `claude -p` subagents.

---

## 4. Changes to Existing Components

### 4.1 `taskplex.sh` — Main Orchestration Loop

**New functions:**
- `decision_call()` — 1-shot Opus call for per-story decisions
- `init_knowledge_db()` — create SQLite schema if not exists, migrate from knowledge.md
- `query_knowledge()` — helper to query learnings by tags/confidence
- `insert_learning()` — helper to insert learnings from agent output
- `insert_error()` — helper to record error in history table

**Modified functions:**
- Main loop: add `decision_call()` between `get_next_task()` and agent spawn
- Main loop: pass model/effort from decision call to `claude -p` invocation
- `extract_learnings()` — redirect from knowledge.md append to SQLite insert
- `handle_error()` — record to SQLite error_history in addition to prd.json
- `generate_report()` — query SQLite for enriched statistics (decisions made, learnings extracted, error patterns)

**Removed/simplified:**
- `generate_context_brief()` — moved to SubagentStart hook (kept as fallback if hook not installed)
- `trim_knowledge()` — no longer needed (SQLite handles growth via confidence decay)
- `add_knowledge_warning()` — replaced by `insert_error()` + SQLite query in hook

**Backward compatibility:** If `knowledge.db` doesn't exist and hooks aren't installed, falls back to v1.2.1 behavior (knowledge.md, inline context brief generation).

### 4.2 `hooks/hooks.json` — Hook Configuration

**Added entries:**

```json
{
  "event": "SubagentStart",
  "matcher": "implementer|validator",
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/hooks/inject-knowledge.sh",
  "description": "Inject knowledge store context into agent spawn"
},
{
  "event": "SubagentStop",
  "matcher": "implementer",
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/hooks/validate-result.sh",
  "description": "Inline validation — block agent if checks fail"
}
```

**Kept as-is:**
- PostToolUse destructive command blocker
- All async monitor hooks (SubagentStart/Stop, PostToolUse, SessionStart/End)

### 4.3 `agents/implementer.md`

**Changes:**
- Remove context brief references from system prompt (hook injects it automatically via `additionalContext`)
- Add note about SubagentStop validation: "Your work will be validated automatically. If validation fails, you'll receive the error and should fix it in this same session."
- Keep structured JSON output format (unchanged — hooks parse this)

### 4.4 `agents/validator.md`

**Status:** Kept but role changes. No longer the primary validation mechanism (SubagentStop hook handles inline validation). The validator agent becomes useful for:
- Explicit re-validation after manual fixes
- Deep validation that's too complex for a shell script (e.g., "does the UI actually render correctly")
- User-triggered validation via wizard

### 4.5 `scripts/prompt.md`

**Changes:**
- Remove "Context Brief" section header and instructions (hook injects context automatically)
- Add "Validation" section: "After you finish, your changes will be validated automatically. If validation fails, you'll receive the error details and should fix the issues."
- Keep "Check Before Implementing" section (still relevant — but pre-check results now come via hook injection)

### 4.6 `commands/start.md` — Wizard

**Checkpoint 6 additions:**
- Ask about knowledge store initialization (migrate existing knowledge.md or start fresh)
- Show decision call configuration (can disable for simple projects to save ~$5)
- Keep monitor enable/disable question

### 4.7 `.claude-plugin/plugin.json`

**Version bump:** 1.2.1 → 2.0.0

### 4.8 Configuration Schema

**New fields in `.claude/taskplex.config.json`:**

```json
{
  "decision_calls": true,
  "decision_model": "opus",
  "knowledge_db": "knowledge.db",
  "validate_on_stop": true,
  "validation_max_cycles": 1,
  "model_routing": "auto"
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `decision_calls` | bool | true | Enable 1-shot decision calls before each story |
| `decision_model` | string | "opus" | Model for decision calls (opus recommended) |
| `knowledge_db` | string | "knowledge.db" | Path to SQLite knowledge store |
| `validate_on_stop` | bool | true | Enable SubagentStop inline validation |
| `validation_max_cycles` | int | 1 | Max validation-retry cycles before agent stops |
| `model_routing` | string | "auto" | "auto" (decision call picks), "fixed" (use execution_model) |

---

## 5. New Files

| File | Purpose | Size estimate |
|------|---------|---------------|
| `hooks/inject-knowledge.sh` | SubagentStart hook — SQLite query + context assembly | ~150 lines |
| `hooks/validate-result.sh` | SubagentStop hook — run checks, block on failure | ~120 lines |
| `scripts/knowledge-db.sh` | SQLite helper functions (init, query, insert, migrate) | ~200 lines |
| `scripts/decision-call.sh` | Decision call template and parsing (sourced by taskplex.sh) | ~100 lines |

**Total new code:** ~570 lines of bash + SQL

**Removed/simplified code:** ~200 lines (generate_context_brief, trim_knowledge, knowledge.md writing)

**Net change:** ~370 lines added

---

## 6. Cost Analysis

### Per-Story Cost Breakdown

| Component | v1.2.1 | v2.0 |
|-----------|--------|------|
| Implementer (Sonnet) | ~$1.29 | ~$1.29 (same) |
| Validator (Haiku) | ~$0.04 | $0 (replaced by hook) |
| Decision call (Opus) | $0 | ~$0.03 |
| SubagentStart hook | $0 | $0 (bash + SQLite) |
| SubagentStop hook | $0 | $0 (bash + shell commands) |
| Knowledge extraction | $0 | $0 (jq parsing) |
| **Per-story total** | **~$1.33** | **~$1.32** |

### Project-Scale Comparison

| Project size | v1.2.1 | v2.0 Smart Scaffold | v2.0 Hybrid Brain |
|--------------|--------|---------------------|-------------------|
| 3 stories | ~$4.00 | ~$4.09 | ~$10.90 |
| 8 stories | ~$10.64 | ~$10.56 | ~$29.04 |
| 15 stories | ~$19.95 | ~$19.80 | ~$54.45 |
| 50 stories | ~$66.50 | ~$66.00 | ~$181.50 |
| 200 stories | ~$266.00 | ~$264.00 | ~$726.00 |

**Key insight:** The Smart Scaffold is actually *slightly cheaper* than v1.2.1 because it eliminates the separate validator agent invocation. The decision call cost (~$0.03/story) is less than the validator cost (~$0.04/story) it partially replaces.

### Where Intelligence Adds Value (ROI)

| Feature | Cost | Expected benefit |
|---------|------|-----------------|
| Decision calls | $0.03/story | Fewer wasted retries, smarter skip/rewrite, model routing saves ~15% on blended cost |
| SubagentStop validation | $0 | ~50% retry reduction (agent fixes in same context vs restart) |
| SQLite knowledge | $0 | Better context briefs, cross-run memory, faster queries |
| Model routing | $0 (built into decision) | ~15% cost reduction from appropriate model selection |

---

## 7. Migration Path

### From v1.2.1 to v2.0

1. **knowledge.md → knowledge.db**: Auto-migration on first run. Entries parsed and inserted with confidence 0.8. Original knowledge.md kept as backup.
2. **Hooks**: New hook entries added to `hooks/hooks.json`. Existing monitor hooks unchanged. Existing PostToolUse destructive blocker unchanged.
3. **Config**: New fields have defaults that match v1.2.1 behavior. Setting `decision_calls: false` and `validate_on_stop: false` gives exact v1.2.1 behavior.
4. **Agents**: `implementer.md` and `prompt.md` updated but backward compatible. Validator agent kept for explicit use.
5. **Scripts**: `taskplex.sh` gains new functions but main loop structure preserved.

### Rollback

Set `decision_calls: false` and `validate_on_stop: false` in config. The system runs exactly as v1.2.1 with a SQLite database it never queries.

---

## 8. Testing Strategy

### Unit Tests (bash)

- `decision_call()` with mock Claude responses (various actions)
- `inject-knowledge.sh` with mock SQLite data and prd.json
- `validate-result.sh` with passing/failing typecheck scenarios
- SQLite schema creation and migration from knowledge.md
- Confidence decay calculation correctness

### Integration Tests

- Full story cycle: decision → spawn → implement → validate → extract learnings
- SubagentStop block cycle: implement → validate fails → agent fixes → validate passes
- Decision call fallback: timeout/error → falls back to v1.2.1 behavior
- Model routing: verify correct model passed to `claude -p` based on decision
- Cross-run knowledge: run 1 extracts learnings, run 2 injects them via hook

### Smoke Test

Run TaskPlex v2.0 on a 3-story project and verify:
- Decision calls appear in SQLite decisions table
- Knowledge DB populated with learnings
- At least one SubagentStop validation cycle observed
- Report includes enriched statistics from SQLite

---

## 9. Implementation Order

Stories should be implemented in this dependency order:

1. **SQLite knowledge store** — schema, init, migrate, query/insert helpers
2. **SubagentStart hook** — inject-knowledge.sh (depends on #1)
3. **SubagentStop hook** — validate-result.sh (independent of #1/#2)
4. **Decision call** — decision-call.sh + taskplex.sh integration (depends on #1)
5. **Model routing** — wire decision call model/effort into claude -p invocation (depends on #4)
6. **Orchestrator integration** — update main loop, remove redundant code (depends on #1-#5)
7. **Wizard updates** — Checkpoint 6 additions for new config (depends on #6)
8. **Agent prompt updates** — implementer.md, prompt.md, validator.md role change (depends on #3)
9. **Configuration** — new config fields, defaults, validation (depends on #6)
10. **Report enrichment** — SQLite-backed completion report (depends on #1, #6)

---

## 10. What This Does NOT Include (Deferred)

| Feature | Reason deferred | When to revisit |
|---------|----------------|-----------------|
| Persistent Opus orchestrator | 7x cost, requires compaction API (beta, not CLI-exposed) | When Claude Code exposes compaction config |
| Agent Teams parallel mode | Interactive-only, 15x cost, no session recovery | When headless API or `--create-team` flag ships |
| Adaptive PRD rewriting | Decision call can trigger rewrites, but organic rewriting needs persistent context | If decision call rewrite quality is insufficient |
| Compaction configuration | API-level only, not exposed through Claude Code CLI | When Claude Code exposes it |
| TDD mode | Useful but orthogonal — can be added independently | Next minor version (v2.1) |
| Cost budget enforcement | Decision table + SQLite tracks cost, but hard budget cutoff deferred | When token usage is reliably available from `claude -p` JSON output |
| Live intervention (pause/redirect) | Requires persistent orchestrator or monitor WebSocket commands | With persistent orchestrator |
| Contract-first interface spec | Useful for parallel, but parallel mode itself unchanged in v2.0 | v2.1 with parallel enhancements |

---

## 11. Success Criteria

v2.0 is successful if:

1. **Quality:** Retry rate drops by 30%+ (measured via SQLite error_history: compare `resolved` rate before/after SubagentStop)
2. **Cost:** Per-story cost stays within 5% of v1.2.1 (measured via SQLite decisions table token tracking)
3. **Intelligence:** Decision calls correctly skip/rewrite stories that v1.2.1 would waste retries on (measured by comparing skip timing)
4. **Knowledge compound:** Learnings from run N appear in context briefs of run N+1 on the same project (verified via inject-knowledge.sh output)
5. **Zero regressions:** All v1.2.1 functionality works with `decision_calls: false, validate_on_stop: false`

---

**Maintained by:** Jesper Vang (@flight505)
**Architecture:** Approach A — Smart Scaffold
**Research basis:** Evolution audit (2026-02-17), claude-flow analysis, SOTA multi-agent research
