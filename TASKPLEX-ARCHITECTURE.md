# TaskPlex Architecture

**Version 2.0.8** | Last Updated: 2026-02-20

Ground truth for TaskPlex's current design, implementation status, known issues, and roadmap. For component-level docs (config schema, agent frontmatter, skill details), see [CLAUDE.md](./CLAUDE.md).

---

## 1. Overview & Philosophy

TaskPlex is a resilient autonomous development assistant for Claude Code. A single command (`/taskplex:start`) drives the full lifecycle: PRD generation, JSON conversion, and story-by-story execution via custom subagents.

**Core principles:**

1. **Precise PRD first** — interactive refinement loop produces verifiable acceptance criteria
2. **Sequential by default** — one story at a time, fresh context per agent, no merge conflicts
3. **Resilient execution** — failures are categorized, retried with strategy, or skipped; the pipeline continues
4. **Dependency enforcement** — stories only execute when all `depends_on` stories have passed
5. **Quality gates via hooks** — destructive commands blocked, inline validation before agent completion
6. **Orchestrator owns state** — agents produce structured output; the bash orchestrator curates knowledge and drives decisions

---

## 2. Current Architecture (v2.0.8)

### Component Structure

```
taskplex/
├── .claude-plugin/plugin.json        # Plugin manifest
├── agents/
│   ├── implementer.md                # Codes a single story (model: inherit)
│   ├── validator.md                  # Verifies acceptance criteria (model: haiku)
│   ├── reviewer.md                   # Reviews PRD from specific angles (model: sonnet)
│   ├── merger.md                     # Git branch operations (model: haiku)
│   └── code-reviewer.md              # Two-stage code review (model: sonnet)
├── commands/
│   └── start.md                      # 8-checkpoint interactive wizard
├── skills/
│   ├── prd-generator/SKILL.md        # PRD creation (context: fork)
│   ├── prd-converter/SKILL.md        # Markdown → JSON (context: fork)
│   └── failure-analyzer/SKILL.md     # Error categorization and retry strategy
├── hooks/
│   ├── hooks.json                    # Hook definitions (9 hooks across 7 events)
│   ├── inject-knowledge.sh           # SubagentStart: SQLite → additionalContext
│   ├── inject-edit-context.sh        # PreToolUse Edit/Write: file patterns → additionalContext
│   ├── pre-compact.sh               # PreCompact: saves story state before compaction
│   └── validate-result.sh            # SubagentStop: uses last_assistant_message
├── scripts/
│   ├── taskplex.sh                   # Main orchestration loop
│   ├── parallel.sh                   # Wave-based parallel execution (sourced conditionally)
│   ├── prompt.md                     # Instructions for each Claude iteration
│   ├── knowledge-db.sh              # SQLite knowledge store helpers
│   ├── decision-call.sh             # 1-shot Opus decision calls
│   ├── check-deps.sh                # Dependency checker (claude, jq, sqlite3, coreutils)
│   ├── check-git.sh                 # Git repo diagnostic (JSON output)
│   └── check-destructive.sh         # PreToolUse: blocks dangerous git commands
├── monitor/
│   ├── server/                       # Bun HTTP + WebSocket + SQLite server
│   ├── client/                       # Vue 3 + Tailwind dashboard
│   ├── hooks/                        # Fire-and-forget event emitters
│   └── scripts/                      # start-monitor.sh, stop-monitor.sh
└── tests/                            # Test suite for v2.0 modules
```

### Data Flow

```
User → /taskplex:start (wizard)
         │
         ├─ Checkpoint 1: Gather project input
         ├─ Checkpoint 2: Validate git repository (init/fix/bootstrap)
         ├─ Checkpoint 3-6: PRD generation → prd.json
         ├─ Checkpoint 7: Config (.claude/taskplex.config.json)
         └─ Checkpoint 8: Launch taskplex.sh
                │
                ▼
         ┌─────────────────────────────────────┐
         │         taskplex.sh (loop)           │
         │                                       │
         │  1. Select next ready story           │
         │  2. Decision call → model/effort      │
         │  3. Spawn implementer (Task tool)     │
         │     ├─ SubagentStart hook injects     │
         │     │  knowledge from SQLite           │
         │     ├─ Agent implements story           │
         │     └─ SubagentStop hook validates     │
         │        (typecheck/build/test)          │
         │  4. Extract learnings → SQLite         │
         │  5. Update prd.json                    │
         │  6. Loop or complete                   │
         └─────────────────────────────────────┘
                │
                ▼
         Completion report + optional merge
```

### State Files (in user's project)

| File | Owner | Purpose |
|------|-------|---------|
| `prd.json` | Orchestrator | Source of truth for story status |
| `progress.txt` | Orchestrator | Layer 1: compact operational log |
| `knowledge.db` | Orchestrator | SQLite knowledge store (v2.0) |
| `knowledge.md` | Orchestrator | Layer 2: curated knowledge (legacy, auto-migrated to SQLite) |
| `.claude/taskplex.config.json` | User/wizard | Execution configuration |
| `.claude/taskplex-{branch}.pid` | Orchestrator | Per-branch PID file |
| `tasks/prd-{feature}.md` | Wizard | Human-readable PRD |

### Key Design Decisions

- **Bash orchestrator, not a persistent agent.** The bash script handles PID management, signal trapping, worktree lifecycle, and crash recovery — things agents can't do reliably. Intelligence is injected via 1-shot decision calls at decision points (Option C from the evolution plan).
- **Fresh context per subagent.** Each implementer starts cold. Context briefs are injected via SubagentStart hooks querying the SQLite knowledge store, not manually constructed.
- **`jq` as the only JSON parser.** No `yq`, no Python for JSON. Shell scripts stay bash 3.2 compatible (no `declare -A`, no bash 4+ features).
- **Hooks for feedback loops, not just telemetry.** SubagentStart injects knowledge; SubagentStop validates and blocks on failure for self-healing.

---

## 3. Orchestration Loop

### Sequential Mode (default)

```
INIT → TASK SELECTION → DECISION CALL → IMPLEMENTATION → VALIDATION → ERROR HANDLING → COMPLETION CHECK → loop
```

**Crash recovery (v2.0.6):** On startup, `recover_stuck_stories()` resets any `in_progress` stories back to `pending` (preserving attempt counts). This handles cases where the orchestrator was killed mid-story.

**Task selection:** Find all stories with `passes: false`, filter out those whose `depends_on` contains incomplete stories, filter out skipped stories, pick highest priority.

**Decision call (v2.0):** A 1-shot Opus call selects model/effort per story based on complexity, error history, and knowledge store contents. Disabled with `decision_calls: false`.

**Implementation:** Spawn implementer via Task tool. The SubagentStart hook injects context from SQLite. Per-edit PreToolUse hooks inject file-specific patterns before each Edit/Write. The agent codes the story and outputs structured JSON. The SubagentStop hook runs typecheck/build/test — if they fail, the agent continues in the same context to fix the issue (self-healing). PreCompact hook preserves state if auto-compaction triggers mid-story.

**Checkpoint (v2.0.6):** After each story state change (`in_progress`, `completed`, `skipped`), `write_checkpoint()` persists a JSON snapshot to `.claude/taskplex-checkpoint.json`.

**Completion check:** All stories pass → optional merge. All remaining blocked → report. Max iterations → report.

### Parallel Mode (wave-based, opt-in)

When `parallel_mode: "parallel"` in config, stories are partitioned into topological waves based on the dependency graph. All stories in a wave run simultaneously in separate git worktrees.

```
Wave 0: [US-001, US-005]  ← no dependencies, parallel
         │ merge both │ extract learnings │ update knowledge
Wave 1: [US-002, US-003]  ← depend on wave 0, parallel
         │ merge all │ extract learnings │ update knowledge
Wave 2: [US-004]           ← depends on wave 1
```

**Conflict safety:** Stories sharing `related_to` targets are split into separate batches within a wave. All process tracking uses space-separated lists (bash 3.2 compatible).

**Implementation:** `scripts/parallel.sh` is sourced conditionally. Key functions: `compute_waves()`, `split_wave_by_conflicts()`, `create_worktree()`, `spawn_parallel_agent()`, `wait_for_agents()`, `merge_story_branch()`.

### CLI Invocation Pattern

**Correct `claude -p` invocation for headless agents:**

```bash
env -u CLAUDECODE claude -p "$PROMPT" \
  --output-format json \
  --no-session-persistence \
  --model "$MODEL" \
  --max-turns "$MAX_TURNS" \
  --dangerously-skip-permissions \
  --allowedTools "Bash,Read,Edit,Write,Glob,Grep"
```

**Critical notes:**
- `env -u CLAUDECODE` is **required** — nested `claude -p` calls fail if the `CLAUDECODE` env var is set
- `--dangerously-skip-permissions` is **required** for headless file writes
- `--agent` and `--agents-dir` flags do **NOT exist** in the CLI — agents are invoked via the Task tool, not CLI flags
- `-r` flag on `jq` is required for raw string output (no quotes around IDs)

---

## 4. Knowledge Architecture

### Three-Layer System (v1.1)

**Layer 1: Operational Log (`progress.txt`)** — Orchestrator-only. Compact timestamped entries: story start/complete/fail/retry. Agents never read or write this file.

**Layer 2: Project Knowledge Base (`knowledge.md` → SQLite)** — Originally a 100-line flat file, auto-migrated to SQLite in v2.0. Contains codebase patterns, environment notes, and learnings extracted from agent output.

**Layer 3: Per-Story Context Brief (ephemeral)** — Generated before each agent spawn by the SubagentStart hook. Contains story details, pre-check results, dependency diffs, relevant knowledge, and retry context. Deleted after use.

### SQLite Knowledge Store (v2.0)

Tables: `learnings`, `file_patterns`, `error_history`, `decisions`, `runs`.

**Retrieval (via inject-knowledge.sh):**
1. Always include `environment` and `gotcha` category learnings
2. Match `file_patterns` against the current story's `check_before_implementing` results
3. Include recent learnings from dependency stories
4. Apply confidence decay (5%/day — stale learnings auto-expire after ~30 days)

**Cross-run persistence:** The DB lives at `knowledge.db` in the project root. Each run tags entries with `run_id`. Previous runs' learnings persist and are available to future runs.

### Decision Calls (v2.0)

At each decision point, a 1-shot Opus call replaces bash heuristics:

| Decision Point | Input | Output |
|---------------|-------|--------|
| Model/effort selection | Story complexity, criteria count, error history | `{model, effort}` |
| Retry vs. skip | Error output, previous attempts, knowledge | `{decision, reason}` |
| Story rewriting | Failure analysis, original criteria | `{modified_criteria}` |

Configured via `decision_calls` (bool, default true) and `decision_model` (string, default "opus").

---

## 5. Subagents

### Agent Definitions

| Agent | Model | maxTurns | Tools | Skills | Memory | Purpose |
|-------|-------|----------|-------|--------|--------|---------|
| implementer | inherit | 150 | Bash, Read, Edit, Write, Glob, Grep | failure-analyzer | project | Code a single story |
| validator | haiku | 50 | Bash, Read, Glob, Grep | — | project | Verify acceptance criteria |
| reviewer | sonnet | 30 | Read, Glob, Grep | — | — | Review PRD quality |
| merger | haiku | 50 | Bash, Read, Grep | — | — | Git branch operations |
| code-reviewer | sonnet | 40 | Read, Grep, Glob, Bash | Edit, Write, Task | — | Two-stage code review (opt-in) |

- `disallowedTools: [Task]` on implementer prevents subagent spawning
- `disallowedTools: [Write, Edit, Task]` on validator enforces read-only
- `disallowedTools: [Write, Edit, Bash, Task]` on reviewer enforces read-only
- `model: inherit` means implementer uses the user's configured model
- `memory: project` provides cross-run learning via `.claude/agent-memory/`
- `skills: [failure-analyzer]` on implementer preloads error categorization for self-diagnosis

### Structured Output Schema

Agents output JSON that the orchestrator parses:

```json
{
  "story_id": "US-001",
  "status": "completed|failed|skipped",
  "error_category": null,
  "error_details": null,
  "files_modified": ["src/models/task.ts"],
  "files_created": ["src/components/Badge.tsx"],
  "commits": ["abc1234"],
  "learnings": ["This project uses barrel exports in src/index.ts"],
  "acceptance_criteria_results": [
    {"criterion": "Add priority column", "passed": true, "evidence": "Migration ran"}
  ],
  "retry_hint": null
}
```

The orchestrator extracts `learnings` and writes them to the SQLite knowledge store after each story.

---

## 6. Hook System

TaskPlex defines 9 hooks across 7 events in `hooks/hooks.json`, plus 2 agent-scoped hooks in `implementer.md` frontmatter:

### PreToolUse: Quality Gate + Per-Edit Context (agent-scoped)

```
implementer.md frontmatter → Bash → check-destructive.sh
implementer.md frontmatter → Edit|Write → inject-edit-context.sh
```
**Quality gate:** Blocks `git push --force`, `git reset --hard`, `git clean -f`, direct pushes to main/master. Allows `--force-with-lease`.

**Per-edit context (v2.0.6):** Queries SQLite `file_patterns` table and relevant learnings for the file being edited. Returns `additionalContext` with file-specific patterns and conventions before each Edit/Write. Both defined in implementer YAML frontmatter — only run during implementer lifecycle, not globally.

### SubagentStart: Knowledge Injection

```
implementer → inject-knowledge.sh
```
Queries SQLite knowledge store for relevant learnings. Returns `additionalContext` JSON that gets injected into the subagent's system prompt. Replaces manual `generate_context_brief()`.

### SubagentStop: Inline Validation

```
implementer → validate-result.sh
```
Extracts learnings from `last_assistant_message` (CLI 2.1.47) instead of grepping transcript files. Runs `typecheck_command`, `build_command`, `test_command` from config. If any fail, returns `{"decision": "block", "reason": "..."}` — the implementer continues in the same context with the error injected as feedback (self-healing). This eliminates most separate validator invocations.

### PreCompact: Knowledge Preservation (v2.0.6)

```
auto → pre-compact.sh
```
Fires before auto-compaction. Saves current story state, git diff snapshot, and progress to SQLite via `save_compaction_snapshot()`. Also writes `.claude/taskplex-pre-compact.json` recovery file. Ensures long-running implementer agents don't lose project knowledge when context is compressed. Cannot block compaction (informational only).

### Monitor Event Hooks (async, fire-and-forget)

```
SubagentStart      → monitor/hooks/subagent-start.sh
SubagentStop       → monitor/hooks/subagent-stop.sh
PostToolUse        → monitor/hooks/post-tool-use.sh
PostToolUseFailure → monitor/hooks/post-tool-use-failure.sh
SessionStart       → monitor/hooks/session-lifecycle.sh session.start
SessionEnd         → monitor/hooks/session-lifecycle.sh session.end
```

All monitor hooks exit 0 regardless — the monitor being down never blocks Claude Code. All event emission is backgrounded (`&`) in the orchestrator.

---

## 7. Monitor Dashboard

Real-time browser dashboard for observing TaskPlex execution. Optional sidecar launched at Checkpoint 8.

### Architecture

```
Hook scripts + orchestrator emit_event()
    ↓ fire-and-forget curl POST
Bun server (port 4444) → SQLite WAL → WebSocket broadcast
    ↓
Vue 3 dashboard (single-page, 4 views)
```

**Two event sources:**
- `hook`: Automatic from Claude Code lifecycle (SubagentStart/Stop, PostToolUse, Session*)
- `orchestrator`: Explicit `emit_event` calls from `taskplex.sh` at ~15 state transitions

### Dashboard Views

- **Timeline**: Real-time event stream with filters, wave progress bars
- **Story Gantt**: Horizontal duration bars per story, color-coded status, retry segments
- **Error Patterns**: Error category breakdown, diagnostic table
- **Agent Insights**: Tool usage by agent type, duration averages, detection rates

### Usage

```bash
bash ${CLAUDE_PLUGIN_ROOT}/monitor/scripts/start-monitor.sh   # Launch
bash ${CLAUDE_PLUGIN_ROOT}/monitor/scripts/stop-monitor.sh    # Shutdown
export TASKPLEX_MONITOR_PORT=4444                              # Default port
```

---

## 8. Error Handling & Retry

### Error Categories

| Category | Detection | Strategy | Max Retries |
|----------|-----------|----------|-------------|
| `env_missing` | "API key", "token", "ECONNREFUSED" | Skip immediately, log for user | 0 |
| `test_failure` | Tests ran but failed | Retry with test output as context | 2 |
| `timeout` | Exit code 124 | Retry with 1.5x timeout | 1 |
| `code_error` | Linter/typecheck/build failures | Retry with error output as context | 2 |
| `dependency_missing` | Import/package not found | Skip, log for user | 0 |
| `unknown` | Unclassifiable | Retry once, then skip | 1 |

### Interactive vs. Background Mode

- **Foreground:** On timeout or failure, user gets interactive prompt (skip/retry/abort)
- **Background:** Auto-skip with logging to `.claude/taskplex.log`

### Story Completion Logic

A story is marked complete **only when validation passes** — not when the agent signals COMPLETE. The SubagentStop hook runs typecheck/build/test inline; the orchestrator also optionally spawns a validator agent for acceptance criteria verification. Both must pass.

**Important:** `commit_story` must be non-fatal (`|| log`) since the agent may have already committed directly.

---

## 9. Known Issues & Fixes (v2.0.6)

These bugs were discovered during real-world testing and fixed in v2.0.1-2.0.3:

### CLI Headless Bugs

| Issue | Fix |
|-------|-----|
| `CLAUDECODE` env var breaks nested `claude -p` | Use `env -u CLAUDECODE` before every nested call |
| `--agent`/`--agents-dir` flags assumed to exist | They don't exist. Agents are invoked via Task tool only |
| Headless writes fail silently | Add `--dangerously-skip-permissions` |
| `jq` output includes quotes around IDs | Always use `jq -r` for raw strings |

### Script Patterns

| Issue | Fix |
|-------|-----|
| `set -e` + `[ cond ] && action` at end of function | Crashes when condition is false. Add `return 0` after |
| Story marked complete on COMPLETE signal | Must be tied to validation pass, not agent signal |
| `commit_story` failure halts pipeline | Must be non-fatal: `commit_story ... \|\| log "WARN" "..."` |
| Duplicate watcher timers in monitor | Merge watchers, add cleanup in `onUnmounted` |
| `set -e` + `grep -c` returns exit 1 on zero matches | Use `\|\| true` instead of `\|\| echo 0` to prevent premature script exit |
| `check-git.sh` `set -e` + `[ ] && action` on lines 55, 93 | Script silently exits on clean repos. Changed to `if/then/fi` |
| `taskplex.sh` `RUN_ID` exported before defined (line 971 vs 1084) | Hooks got empty `TASKPLEX_RUN_ID`. Moved export after definition |
| `check-deps.sh` missing `sqlite3` check | Added sqlite3 to dependency validation (required since v2.0) |
| `validate-result.sh` greedy regex learnings extraction | Replaced with jq-first parsing + non-greedy JSON object fallback |
| `knowledge-db.sh` process substitution `< <()` | Normalized to here-string `<<<` for project consistency |
| `send-event.sh` `set -e` contradicts "always exit 0" | Removed `set -e` from async monitor hook |
| `check-destructive.sh` blocks `--force-with-lease` | Added allowlist for safer `--force-with-lease` operation |
| `hooks.json` inject-knowledge triggers for validator | Narrowed SubagentStart matcher to `implementer` only |

---

## 10. Future Roadmap

### Implemented (v2.0.0–v2.0.4)

- SubagentStart/Stop hooks (knowledge injection, inline validation)
- SQLite knowledge store with confidence decay
- 1-shot Opus decision calls for model/effort routing
- Auto-migration from `knowledge.md` to SQLite
- `last_assistant_message` for learnings extraction (v2.0.3)
- Agent-scoped PreToolUse hooks in implementer frontmatter (v2.0.3)
- `context: fork` on PRD generation/conversion skills (v2.0.3)
- Effort level tuning for per-story decision calls (v2.0.0)
- Git repo bootstrap wizard with diagnostic script (v2.0.3)

### Next Up: v2.1 — Agent Hardening + New Hook Events

**Batch 1: Quick wins** — Done (v2.0.5)

- `maxTurns` on all agents (implementer:150, validator:50, reviewer:30, merger:50)
- `disallowedTools` on validator (`Write, Edit, Task`) and reviewer (`Write, Edit, Bash, Task`)
- `PostToolUseFailure` monitor hook
- Fixed `allowed-tools` format in start.md
- Documented memory vs knowledge precedence

**Batch 2: Medium effort, high value** — Done (v2.0.6)

- PreToolUse `additionalContext` per-edit: `inject-edit-context.sh` queries `file_patterns` table + relevant learnings before each Edit/Write
- Preloaded failure-analyzer skill on implementer via `skills:` frontmatter field
- `PreCompact` knowledge preservation: `pre-compact.sh` saves story state + progress to SQLite before auto-compaction
- Checkpoint resume: reset stuck `in_progress` stories on startup, write checkpoint JSON after each state change

**Batch 3: Larger features** *(Done — v2.0.7)*

- Transcript mining: `mine_implicit_learnings()` in knowledge-db.sh extracts observations, file relationships, environment notes from agent prose via regex patterns. Called from validate-result.sh SubagentStop hook.
- Adaptive PRD rewriting: `rewrite_story()` in decision-call.sh spawns Haiku to split/simplify failed stories. Additive pattern (inserts sub-stories, marks original as "rewritten"). Integrated into orchestrator decision handling.
- Post-merge regression check: `post_merge_test()` in taskplex.sh runs test suite after merge, reverts on failure. Applied to all 3 merge paths.
- Scope drift detection: SubagentStop hook compares `git diff --stat` against expected files. Logs warnings to SQLite. Informational only — never blocks agent.
- Code review agent: `agents/code-reviewer.md` (model: sonnet). Two-stage: spec compliance then code quality. Adversarial framing, issue taxonomy (Critical/Important/Minor with file:line), binary verdict. Opt-in via `code_review: true`.
- Live intervention: `POST/GET /api/intervention`, `POST /api/intervention/consume` endpoints on monitor server. `check_intervention()` in orchestrator polls between iterations. Actions: skip, pause, hint, resume.

**Batch 4: Aspirational**

| Feature | Effort | Impact | Details |
|---------|--------|--------|---------|
| Dependency graph visualization | Low | Low | Mermaid DAG in monitor dashboard. Nice-to-have. |
| Self-improving prompts | High | High | Cross-run analytics proposes `prompt.md` modifications. Requires statistical significance across runs. |
| `permissionMode` on agents | Low | Low | Use `permissionMode: bypassPermissions` in agent frontmatter instead of CLI flag `--dangerously-skip-permissions`. Cleaner invocation. Needs testing. |

### Blocked by Platform

| Feature | Blocking Reason | Last Checked |
|---------|----------------|--------------|
| Agent Teams for parallel execution | Interactive-only. No headless API. Cannot be driven by `claude -p`. `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` flag exists but only for interactive sessions. | 2026-02-19 |
| Configurable compaction | API-level only. CLI exposes `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` but not full compaction parameters. | 2026-02-19 |
| Per-agent effort level in frontmatter | No `effortLevel` field in agent frontmatter. Workaround: set `CLAUDE_CODE_EFFORT_LEVEL` env var per-invocation (already done). | 2026-02-19 |
| `Task(agent_type)` selective restrictions | CLI supports `Task(type)` in `tools:` list but not in `disallowedTools:`. Cannot say "allow Task but only for validator type". Workaround: blanket `disallowedTools: [Task]`. | 2026-02-19 |

### Resolved / No Longer Relevant

| Item | Resolution |
|------|-----------|
| Memory vs knowledge injection overlap | Audited: overlap is intentional. `memory: project` provides cross-run persistence; SQLite provides decay-weighted fresh context. Document precedence rules in CLAUDE.md. |
| Effort level tuning for decision calls | Implemented in v2.0.0. Decision call selects effort per-story; env var applied before each agent spawn. |

---

## 11. Version History

| Version | Date | Highlights |
|---------|------|------------|
| 2.0.8 | 2026-02-20 | SOTA audit: permissionMode on all agents, Stop/TaskCompleted hooks, statusMessage/timeout, skill agent routing, $ARGUMENTS fast-start, CLAUDE_ENV_FILE, competitive analysis vs 15+ plugins |
| 2.0.7 | 2026-02-19 | v2.1 Batch 3: Transcript mining, adaptive PRD rewriting, post-merge regression check, scope drift detection, code review agent, live intervention via dashboard |
| 2.0.6 | 2026-02-19 | v2.1 Batch 2: PreToolUse per-edit context injection, failure-analyzer preload on implementer, PreCompact hook, checkpoint resume |
| 2.0.5 | 2026-02-19 | v2.1 Batch 1: maxTurns on agents, disallowedTools enforcement, PostToolUseFailure hook, allowed-tools format fix, memory vs knowledge docs |
| 2.0.4 | 2026-02-19 | Bug fix round: 9 fixes from code-simplifier + docs compliance review (set -e crashes, RUN_ID export, sqlite3 dep check, learnings extraction, force-with-lease) |
| 2.0.3 | 2026-02-19 | CLI 2.1.47 adoption (last_assistant_message, agent-scoped hooks, context: fork), git repo bootstrap wizard |
| 2.0.0 | 2026-02-17 | Smart Scaffold: SQLite knowledge store, decision calls, SubagentStart/Stop hooks, inline validation |
| 1.2.1 | 2026-02-15 | Execution monitor sidecar (Bun + Vue 3 dashboard) |
| 1.2.0 | 2026-02-15 | Wave-based parallel execution via git worktrees |
| 1.1.0 | 2026-02-14 | Three-layer knowledge architecture |
| 1.0.0 | 2026-02-11 | Initial release — custom subagents, error categorization, quality gate hooks |

For detailed changelogs, see [CLAUDE.md § Version History](./CLAUDE.md#version-history).
