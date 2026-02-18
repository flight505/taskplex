# TaskPlex v2.0: Evolution Plan (Corrected)

**Author:** Claude (analysis for Jesper Vang)
**Date:** 2026-02-17
**Target audience:** Claude Code Max 20x subscribers ($200/mo flat rate)

---

## Corrections from v1

The first version of this document contained significant errors. This version corrects them based on Jesper's independent verification against the full CLI docs (21,721 lines) and API reference (1,079,918 lines). Every claim below is tagged with its verification status.

### Errors fixed

| Error | What v1 said | What's actually true |
|-------|-------------|---------------------|
| Hook syntax | `{"type": "SubagentStart", "matcher": {"agent_type": "..."}}` | `{"hooks": {"SubagentStart": [{"matcher": "regex-string", "hooks": [...]}]}}` |
| Agent Teams | Proposed as programmable parallel mode with JSON config | Interactive-only. No headless API. Cannot be driven by `claude -p`. |
| Effort models | Implied Sonnet supports effort levels | Opus 4.6 and Opus 4.5 only. `max` is Opus 4.6 only. |
| PreCompact | Called it "context preservation" | Fire-and-forget notification. Cannot block compaction. Cannot inject data that survives compaction. |
| Compaction config | Showed `context_management` as CLI-configurable | API-level only. Claude Code exposes `/compact` command and `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` env var, not the full API parameters. |
| Opus prefilling | Not mentioned | Opus 4.6 does NOT support prefilling. Returns 400 error. |
| Pricing | Used $15/$75 for Opus in cost estimates | Opus 4.6 is $5/$25. Haiku 4.5 is $1/$5. Sonnet 4.5 is $3/$15. |
| SubagentStop behavior | "prevents completing" | Subagent continues working in the same context with the reason injected. It does not restart. |

### Context: Max 20x subscription

This plan targets Max 20x subscribers ($200/mo flat rate). **Token costs are irrelevant.** The v1 cost analysis showing "7x cost increase" from a persistent Opus orchestrator doesn't apply — you're not paying per-token. The actual constraints are:

- **Rate limits:** ~900 messages per 5-hour rolling window
- **Capability gaps:** What's actually scriptable vs. interactive-only
- **Maturity:** Beta vs. GA vs. experimental features

---

## Verified Sources

| Source | What it covers | Lines reviewed |
|--------|---------------|----------------|
| [Claude Code Hooks](https://code.claude.com/docs/en/hooks) | Hook syntax, SubagentStart/Stop, PreCompact, TeammateIdle, TaskCompleted | CLI docs |
| [Agent Teams](https://code.claude.com/docs/en/agent-teams) | Architecture, limitations, interactive-only creation, display modes | CLI docs |
| [Compaction API](https://platform.claude.com/docs/en/build-with-claude/compaction) | `compact_20260112`, triggers, pause, custom instructions, billing | API docs |
| [Effort Parameter](https://platform.claude.com/docs/en/build-with-claude/effort) | Opus-only support, low/medium/high/max levels, GA status | API docs |
| [What's new in Claude 4.6](https://platform.claude.com/docs/en/about-claude/models/whats-new-claude-4-6) | Adaptive thinking, 128K output, fast mode, prefill removal | API docs |
| [Subagents](https://code.claude.com/docs/en/sub-agents) | Fresh context per spawn, Task tool, agent definitions | CLI docs |

---

## Part 1: What's Actually Implementable Now

These proposals use only confirmed, GA or stable-beta features and require no architectural changes to how TaskPlex spawns agents.

### 1.1 SubagentStart Knowledge Injection

**Status:** Confirmed working. CLI docs line 20443.

Replace the manual context brief generation in `taskplex.sh` with a SubagentStart hook that automatically injects knowledge when an implementer spawns.

**Correct hook syntax:**
```json
{
  "hooks": {
    "SubagentStart": [
      {
        "matcher": "implementer",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/inject-knowledge.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

**What `inject-knowledge.sh` does:**
1. Reads the current story ID from an env var or temp file set by the orchestrator
2. Queries the knowledge store (SQLite or flat file) for relevant learnings
3. Outputs JSON to stdout:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": "Project uses ESM imports. Auth middleware expects JWT in Authorization header. Always run 'pnpm install' after adding deps. Test framework is vitest, not jest."
  }
}
```

**What this replaces:** The `generate_context_brief()` function in `taskplex.sh` (lines 264-346). The hook handles knowledge injection automatically, so the orchestrator only needs to set the story context.

**Cost:** Zero extra tokens. The `additionalContext` is injected into the subagent's system prompt, not as a separate message.

---

### 1.2 SubagentStop Inline Validation

**Status:** Confirmed working. CLI docs line 20504.

Replace the separate validator agent invocation with a SubagentStop hook that runs typecheck/build/test before letting the implementer finish.

**Correct hook syntax:**
```json
{
  "hooks": {
    "SubagentStop": [
      {
        "matcher": "implementer",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/validate-on-stop.sh",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

**What `validate-on-stop.sh` does:**
1. Reads `taskplex.config.json` for `typecheck_command`, `build_command`, `test_command`
2. Runs each in sequence
3. If all pass: exits 0 (subagent stops normally)
4. If any fail: exits 0 with blocking decision:
```json
{
  "decision": "block",
  "reason": "Build failed: error TS2345: Argument of type 'string' is not assignable to parameter of type 'number' in src/auth/middleware.ts:42. Fix this before completing."
}
```

**Behavior when blocked:** The implementer does NOT restart. It continues working in the same context with the error output injected as feedback. It sees the build error and can fix it immediately. This is far more efficient than a separate validator invocation — no fresh context, no re-reading the codebase.

**What this reduces:** Eliminates most validator agent invocations (Haiku, ~8K input tokens each). The validator becomes a lightweight final confirmation, not the primary quality gate.

**Limitation:** The hook timeout must be long enough for the build/test suite. Set `timeout` appropriately (120s default, configurable).

---

### 1.3 SQLite Knowledge Store

**Status:** New code. No API dependency. Reuses monitor's Bun + SQLite infrastructure.

Replace `knowledge.md` (100-line flat file, FIFO trimming) with a SQLite database.

```sql
CREATE TABLE learnings (
  id INTEGER PRIMARY KEY,
  run_id TEXT NOT NULL,
  story_id TEXT,
  category TEXT CHECK(category IN ('pattern', 'gotcha', 'environment', 'decision')),
  content TEXT NOT NULL,
  importance INTEGER DEFAULT 3 CHECK(importance BETWEEN 1 AND 5),
  created_at TEXT DEFAULT (datetime('now')),
  last_accessed TEXT,
  source TEXT DEFAULT 'agent_output'
);

CREATE TABLE learning_refs (
  learning_id INTEGER REFERENCES learnings(id),
  ref_type TEXT CHECK(ref_type IN ('file', 'story', 'function', 'module')),
  ref_value TEXT
);

CREATE INDEX idx_learnings_run ON learnings(run_id);
CREATE INDEX idx_learnings_category ON learnings(category);
CREATE INDEX idx_learning_refs_value ON learning_refs(ref_value);
```

**Retrieval for the SubagentStart hook:**
```bash
#!/bin/bash
# inject-knowledge.sh — query SQLite, return as additionalContext

STORY_ID="${TASKPLEX_CURRENT_STORY:-}"
DB=".claude/taskplex-knowledge.db"

if [ ! -f "$DB" ]; then
  exit 0  # no knowledge store yet, skip injection
fi

# Always include environment and gotcha learnings
LEARNINGS=$(sqlite3 "$DB" "
  SELECT content FROM learnings
  WHERE category IN ('environment', 'gotcha')
  ORDER BY importance DESC, created_at DESC
  LIMIT 10
")

# Add pattern learnings related to files this story touches
if [ -n "$STORY_ID" ]; then
  RELATED=$(sqlite3 "$DB" "
    SELECT l.content FROM learnings l
    JOIN learning_refs lr ON l.id = lr.learning_id
    WHERE lr.ref_value IN (
      SELECT ref_value FROM learning_refs
      WHERE learning_id IN (
        SELECT id FROM learnings WHERE story_id = '$STORY_ID'
      )
    )
    AND l.story_id != '$STORY_ID'
    ORDER BY l.importance DESC
    LIMIT 5
  ")
  LEARNINGS="$LEARNINGS"$'\n'"$RELATED"
fi

if [ -n "$LEARNINGS" ]; then
  # Escape for JSON
  ESCAPED=$(echo "$LEARNINGS" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SubagentStart\",\"additionalContext\":$ESCAPED}}"
fi
```

**Cross-run persistence:** The DB lives at `.claude/taskplex-knowledge.db`. Each run tags entries with `run_id`. Previous runs' learnings persist automatically. No extra architecture needed.

**No embeddings needed:** The orchestrator (or the hook script) does keyword-based retrieval. For semantic filtering, the orchestrator agent can review 20 candidate learnings and pick the relevant ones. An LLM IS a semantic search engine.

---

### 1.4 Transcript Mining

**Status:** Confirmed. SubagentStop provides `agent_transcript_path` (CLI docs line 20464).

After each implementer finishes, spawn a cheap Haiku agent to read the transcript and extract implicit knowledge.

**What to extract:**
- Files read but not modified (implicit dependencies → future `related_to` edges)
- Error messages encountered and how they were resolved (→ `gotcha` learnings)
- Patterns the agent used (import style, test framework, naming conventions → `pattern` learnings)

**Implementation:** Add a second SubagentStop hook for the implementer that fires *after* the validation hook. This hook reads `$AGENT_TRANSCRIPT_PATH`, runs a Haiku extraction, and writes results to the knowledge store.

**On Max 20x:** Haiku calls don't cost extra. The only constraint is the rate limit, and a single Haiku call per story is negligible.

---

### 1.5 PreCompact State Backup

**Status:** Confirmed fire-and-forget. Cannot block compaction. CLI docs line 20611.

**Correct characterization:** PreCompact is a notification hook, not a control mechanism. It fires before compaction but cannot prevent it or inject data that survives it.

**Valid use:** Trigger a side effect — write the current orchestrator's decision state to disk before compaction summarizes it away.

```json
{
  "hooks": {
    "PreCompact": [
      {
        "matcher": "auto",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-compact-backup.sh"
          }
        ]
      }
    ]
  }
}
```

The script dumps the current `prd.json` status, knowledge store summary, and iteration count to a checkpoint file. If the compaction loses critical details, the orchestrator can re-read this checkpoint.

---

### 1.6 Preemptive Conflict Detection

**Status:** New code. No API dependency.

Before parallel execution begins, run all `check_before_implementing` commands across every story and build a file-overlap matrix. Auto-populate `related_to` edges in `prd.json`.

This is pure bash — no agent needed. Can run as a pre-execution step in `taskplex.sh` before the main loop starts.

---

## Part 2: Architectural Changes (Require Design Work)

### 2.1 Hybrid Orchestration: Opus Brain + Bash Scaffold

**Status:** Feasible but requires significant refactoring. Compaction is API-level only.

**The core idea remains sound:** Move decision-making from bash to an intelligent Opus agent. The bash script handles process management (PID, signals, cleanup, worktrees). The Opus agent handles story selection, retry decisions, plan adaptation, and knowledge curation.

**Critical constraint:** Compaction's full configuration (`trigger`, `pause_after_compaction`, `instructions`) is only available through the Messages API, not through Claude Code CLI. This means:

**Option A: Use Claude Code CLI's built-in compaction**
- Claude Code auto-compacts at ~95% context (or configurable via `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`)
- No control over summarization prompt or pause behavior
- The orchestrator agent runs as a long-lived `claude` session (not `claude -p` per-story)
- Simplest path, but less control over what gets preserved during compaction

**Option B: Build an API-direct orchestrator**
- Bypass Claude Code CLI entirely for the orchestrator
- Use the Messages API with `compact_20260112` for full compaction control
- Custom summarization instructions to preserve story status, learnings, and plan state
- The orchestrator calls subagents via the API too (or via Claude Code for the implementers)
- More work, but full control

**Option C (pragmatic): Enhanced bash orchestrator that calls Opus for decisions**
- Keep `taskplex.sh` as the loop
- At each decision point (retry? skip? reorder? rewrite story?), call `claude -p` with the current state and ask Opus to decide
- No long-lived agent, no compaction needed
- Each decision call is stateless but receives the full current state (prd.json + knowledge store + recent error context)
- The "intelligence" is injected at decision points, not as a persistent agent

**Recommendation for Max 20x:** Option C first. It's the smallest change, requires no API-level work, and gives you 80% of the benefit. The Opus decision calls are free on Max. Upgrade to Option A or B later if the decision-point approach proves limiting.

**Example: Intelligent retry decision**
```bash
# Current: pattern-matching heuristic in bash
# Proposed: ask Opus
DECISION=$(claude -p "You are the TaskPlex orchestrator. Story $STORY_ID failed with:
$ERROR_OUTPUT

Story acceptance criteria:
$CRITERIA

Previous attempts: $ATTEMPTS
Knowledge from this run:
$KNOWLEDGE

Should I: (A) retry with the same approach, (B) retry with a modified approach (explain what to change), (C) skip this story, or (D) rewrite the story's acceptance criteria? Respond with JSON: {\"decision\": \"A|B|C|D\", \"reason\": \"...\", \"modified_criteria\": [...] }" \
  --output-format json --no-session-persistence --model claude-opus-4-6)
```

This replaces the 200-line error categorization logic in `taskplex.sh` with a single Opus call that can reason about the specific error in context.

---

### 2.2 Adaptive PRD Rewriting

**Status:** Novel capability. Depends on 2.1 (intelligent orchestrator).

When the orchestrator (Option C: Opus at decision points) determines a story's approach is fundamentally wrong, it rewrites the acceptance criteria rather than retrying the same instructions.

**Safeguards:**
- Only after 2 failed attempts with the same approach
- Log all rewrites with before/after in the knowledge store
- In foreground mode: show the user the proposed rewrite via stdin prompt
- Never change the story's intent, only its approach
- Write the rewrite to `prd.json` so it's persisted

---

### 2.3 Effort-Adaptive Story Execution

**Status:** Effort is GA, but ONLY on Opus 4.6 and Opus 4.5. Not on Sonnet.

**Corrected mapping:**

| Scenario | Model | Effort | Notes |
|----------|-------|--------|-------|
| Already-implemented check | Haiku 4.5 | N/A | Effort not supported |
| Simple story (1-2 criteria) | Sonnet 4.5 | N/A | Effort not supported |
| Standard story (3-5 criteria) | Opus 4.6 | medium | 76% fewer output tokens vs high |
| Complex story (6+ criteria) | Opus 4.6 | high | Default quality |
| Failed retry (1st) | Opus 4.6 | high | Full reasoning |
| Failed retry (2nd) | Opus 4.6 | max | Maximum capability, Opus 4.6 only |

**Key insight from the docs:** At medium effort, Opus 4.6 matches Sonnet 4.5's SWE-bench performance while using 76% fewer output tokens. For Max subscribers, token count doesn't matter for cost, but fewer tokens = faster responses = faster pipeline throughput. Medium effort on Opus 4.6 could be faster than Sonnet for standard stories.

**On Max 20x:** The model choice affects rate limits, not cost. Using Opus for everything is fine if you're not hitting the ~900 msgs/5h cap. For large projects (15+ stories), Haiku for trivial checks and Sonnet for simple stories preserves rate limit headroom.

---

### 2.4 Post-Merge Regression Check with Rollback

**Status:** New code. No API dependency.

After each story's changes are committed, run the full test suite:
1. If tests pass: proceed
2. If tests fail that passed before: `git revert` the commit, mark story as `needs_rework`, log regression details in knowledge store, continue to next story

This is straightforward bash + git. The key decision is whether to run the full test suite (slow but safe) or just the affected tests (fast but might miss regressions).

---

## Part 3: Deferred (Blocked by Platform Gaps)

### 3.1 Agent Teams Integration

**Status:** BLOCKED. Interactive-only. No headless API.

Agent Teams are confirmed experimental (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var) and interactive-only. There is no:
- `--create-team` CLI flag
- Headless team creation API
- Way to drive teams from `claude -p`
- Way for teammates to be non-interactive

**What would need to change:** Anthropic would need to expose team creation and management through a scriptable interface. The team lead would need to accept programmatic task lists, not just natural language prompts.

**Until then:** Keep `parallel.sh` for worktree-based parallelism, or use the existing subagent approach with multiple `claude -p` calls.

**What Agent Teams DO offer today (manually):** If you run TaskPlex in foreground mode and want to parallelize a wave, you could theoretically:
1. Let TaskPlex identify the wave's independent stories
2. Pause execution
3. Manually create an Agent Team for those stories in an interactive Claude Code session
4. Resume TaskPlex after the team completes

This is hacky and manual, but it works for power users willing to supervise.

**Agent Teams hooks that ARE useful now:**
- `TeammateIdle` — runs when a teammate is about to go idle. Exit code 2 sends feedback and keeps the teammate working.
- `TaskCompleted` — runs when a task is being marked complete. Exit code 2 prevents completion and sends feedback.

These hooks could be useful if someone manually uses Agent Teams alongside TaskPlex, even before programmatic integration exists.

### 3.2 Configurable Compaction

**Status:** BLOCKED. API-level only.

The full compaction parameters (`trigger`, `pause_after_compaction`, `instructions`) are Messages API features. Claude Code CLI doesn't expose them. The CLI only offers:
- `/compact` interactive command
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` env var (changes trigger threshold %)
- Auto-compaction at ~95% context

**Workaround:** Build an API-direct orchestrator (Option B from 2.1) that uses the Messages API with full compaction control. This is a significant architecture change.

### 3.3 Opus 4.6 Prefilling

**Status:** INCOMPATIBLE. Opus 4.6 returns 400 on prefilled assistant messages.

**Impact on TaskPlex:** Review `prompt.md` and agent definitions for any prefilling patterns. If TaskPlex or any of its agents use prefilled assistant messages, they'll break on Opus 4.6.

**Alternatives (from the docs):**
- Structured outputs (`output_config.format`) for JSON response control
- System prompt instructions for format guidance
- Note: `output_format` parameter is deprecated, use `output_config.format` instead

---

## Part 4: Novel Capabilities (Implementable on Current Platform)

### 4.1 Intelligent Decision Injection (Option C from 2.1)

The single highest-value change: at every decision point in `taskplex.sh`, call Opus for a reasoned decision instead of using bash heuristics.

**Decision points in `taskplex.sh` that benefit:**

| Decision | Current (bash) | Proposed (Opus call) |
|----------|---------------|---------------------|
| Next story selection | First ready by priority | Opus considers complexity, knowledge, recent errors |
| Retry vs. skip | Pattern matching on error output | Opus reasons about root cause |
| Error categorization | Regex on exit code + output | Opus reads full error context |
| Story rewriting | Not possible | Opus rewrites criteria based on failure analysis |
| Knowledge extraction | JSON field extraction | Opus reads full agent output, extracts implicit learnings |
| Model selection | Config-level static choice | Opus picks model/effort per story based on complexity |

**Each call is stateless:** The orchestrator passes the current state (prd.json + knowledge + error context) and gets back a decision. No long-lived session needed. No compaction needed. Works with `claude -p`.

**On Max 20x:** These calls are free. The only cost is latency (Opus responds in 5-15 seconds per decision). For an 8-story project, that's ~40-80 seconds of decision overhead across the entire run — negligible.

### 4.2 Self-Improving Prompts

After each run, the knowledge store accumulates which stories succeeded first-try vs. needed retries. Over multiple runs on the same project, patterns emerge. A post-run analytics step (Opus call) reviews the knowledge store and proposes modifications to `prompt.md`:

```bash
claude -p "Review these learnings from the last 3 TaskPlex runs:
$LEARNINGS

Current agent prompt:
$PROMPT_MD

Suggest specific additions or modifications to the prompt that would prevent the recurring failures. Output as a diff." \
  --output-format json --no-session-persistence --model claude-opus-4-6
```

### 4.3 Scope Drift Detection

After each implementer completes, compare the git diff against the story's expected scope:

1. Extract expected file paths from `check_before_implementing` results + `implementation_hint`
2. Get actual modified files from `git diff --name-only`
3. If files modified ∉ expected files: flag for review
4. In foreground mode: prompt user. In background mode: log warning.

This is simple bash + git, no agent needed.

### 4.4 Code Review Agent

```yaml
name: code-reviewer
model: sonnet
tools: [Bash, Read, Glob, Grep]
disallowedTools: [Task, Edit, Write]
purpose: Review implementation diff for quality, security, consistency
```

Runs `git diff` after implementation, outputs structured findings. The orchestrator (or an Opus decision call) decides whether issues are blocking.

### 4.5 Checkpoint Resume

After each story completes, write a checkpoint:

```json
{
  "run_id": "abc123",
  "completed_stories": ["US-001", "US-002"],
  "git_state": {"branch": "taskplex/feature", "commit": "abc123"},
  "knowledge_db": ".claude/taskplex-knowledge.db",
  "prd_hash": "sha256:...",
  "timestamp": "2026-02-17T14:30:00Z"
}
```

On restart: detect checkpoint, verify git state matches, resume from next pending story. Pure bash + git, no API dependency.

### 4.6 Live Intervention via Monitor Dashboard

The monitor's Bun server already exists. Add a REST endpoint for user commands:

```
POST /api/commands
{"type": "skip", "story_id": "US-003"}
{"type": "hint", "story_id": "US-005", "content": "Use the existing AuthService"}
{"type": "pause"}
```

The bash orchestrator polls this endpoint between stories. The Vue dashboard gets a command input panel.

### 4.7 Dependency Graph Visualization

Generate a Mermaid DAG from `prd.json` and render it in the monitor dashboard. Color-coded by status. Shows wave boundaries and critical path.

---

## Implementation Priority (Corrected)

### Tier 1: Implement now (confirmed capabilities, zero architecture change)

| # | Feature | What it replaces | Effort | Depends on |
|---|---------|-----------------|--------|-----------|
| 1 | SubagentStart knowledge injection (1.1) | `generate_context_brief()` | Medium | Correct hook syntax |
| 2 | SubagentStop inline validation (1.2) | Separate validator agent | Medium | Correct hook syntax |
| 3 | SQLite knowledge store (1.3) | `knowledge.md` flat file | Medium | None |
| 4 | Transcript mining (1.4) | Manual learnings only | Low | Knowledge store |
| 5 | Preemptive conflict detection (1.6) | Manual `related_to` | Low | None |
| 6 | Checkpoint resume (4.5) | No resume capability | Low | None |

### Tier 2: Implement soon (new capability, moderate architecture change)

| # | Feature | What it enables | Effort | Depends on |
|---|---------|----------------|--------|-----------|
| 7 | Opus decision injection (4.1) | Intelligent retry/skip/rewrite | Medium | None |
| 8 | Effort-adaptive execution (2.3) | Better model/effort selection | Low | Decision injection |
| 9 | Post-merge regression check (2.4) | Branch integrity protection | Low | None |
| 10 | Scope drift detection (4.3) | Prevent out-of-scope changes | Low | None |
| 11 | Adaptive PRD rewriting (2.2) | Plan adapts to reality | Medium | Decision injection |

### Tier 3: Implement later (nice-to-have, higher effort)

| # | Feature | What it enables | Effort | Depends on |
|---|---------|----------------|--------|-----------|
| 12 | Code review agent (4.4) | Quality review before merge | Medium | New agent definition |
| 13 | Live intervention (4.6) | User control during execution | Medium | Monitor dashboard |
| 14 | Dependency graph viz (4.7) | Visual story tracking | Low | Monitor dashboard |
| 15 | Self-improving prompts (4.2) | Cross-run optimization | High | Knowledge store + analytics |

### Deferred: Wait for platform

| # | Feature | Blocking reason |
|---|---------|----------------|
| — | Agent Teams integration | Interactive-only, no headless API |
| — | Configurable compaction | API-level only, not exposed via Claude Code CLI |
| — | Persistent Opus orchestrator (full) | Requires API-direct orchestrator or CLI compaction support |

---

## Rate Limit Considerations (Max 20x)

On Max 20x (~900 msgs/5h), the constraint is message count, not cost.

**Per-story message budget (current v1.2.1):**
- 1 implementer invocation (~1 msg)
- 1 validator invocation (~1 msg)
- Total: ~2 msgs/story

**Per-story message budget (proposed v2.0):**
- 1 implementer invocation (~1 msg)
- 0-1 validator (reduced by SubagentStop hook)
- 0-1 Opus decision call for retry/skip
- 0-1 Haiku transcript mining
- Total: ~2-4 msgs/story

**Capacity on Max 20x:**
- Conservative (4 msgs/story): 225 stories per 5-hour window
- Realistic (3 msgs/story): 300 stories per 5-hour window
- This is far more than any practical TaskPlex run (typically 5-20 stories)

**Rate limits are not a constraint** for TaskPlex on Max 20x. Even with the proposed additions, a 20-story project uses ~80 messages — well within the ~900/5h cap.

---

## Summary

The v1 evolution document was architecturally ambitious but built on several incorrect assumptions about what's actually scriptable. This v2 focuses on what's confirmed working today:

**Biggest wins for smallest changes:**
1. **SubagentStart/Stop hooks** — zero extra tokens, replaces manual context briefs and separate validator
2. **SQLite knowledge store** — persistent, cross-run, queryable, replaces fragile flat file
3. **Opus decision injection** — replaces 200 lines of bash heuristics with actual reasoning

**The "persistent Opus orchestrator" dream is deferred** — not because it's wrong, but because it requires either building an API-direct orchestrator or waiting for Claude Code to expose compaction configuration. The pragmatic Option C (Opus at decision points) gives 80% of the benefit with 20% of the effort.

**Agent Teams are the future of parallel execution** — but they're interactive-only and experimental today. When Anthropic exposes team creation through a scriptable interface, TaskPlex should be the first to integrate it. Until then, `parallel.sh` with worktrees remains the practical choice.
