# TaskPlex Architecture

**Version 2.0.3** | Last Updated: 2026-02-19

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

## 2. Current Architecture (v2.0.3)

### Component Structure

```
taskplex/
├── .claude-plugin/plugin.json        # Plugin manifest
├── agents/
│   ├── implementer.md                # Codes a single story (model: inherit)
│   ├── validator.md                  # Verifies acceptance criteria (model: haiku)
│   ├── reviewer.md                   # Reviews PRD from specific angles (model: sonnet)
│   └── merger.md                     # Git branch operations (model: haiku)
├── commands/
│   └── start.md                      # 8-checkpoint interactive wizard
├── skills/
│   ├── prd-generator/SKILL.md        # PRD creation (context: fork)
│   ├── prd-converter/SKILL.md        # Markdown → JSON (context: fork)
│   └── failure-analyzer/SKILL.md     # Error categorization and retry strategy
├── hooks/
│   ├── hooks.json                    # Hook definitions (7 hooks across 5 events)
│   ├── inject-knowledge.sh           # SubagentStart: SQLite → additionalContext
│   └── validate-result.sh            # SubagentStop: uses last_assistant_message
├── scripts/
│   ├── taskplex.sh                   # Main orchestration loop
│   ├── parallel.sh                   # Wave-based parallel execution (sourced conditionally)
│   ├── prompt.md                     # Instructions for each Claude iteration
│   ├── knowledge-db.sh              # SQLite knowledge store helpers
│   ├── decision-call.sh             # 1-shot Opus decision calls
│   ├── check-deps.sh                # Dependency checker (claude, jq, coreutils)
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

**Task selection:** Find all stories with `passes: false`, filter out those whose `depends_on` contains incomplete stories, filter out skipped stories, pick highest priority.

**Decision call (v2.0):** A 1-shot Opus call selects model/effort per story based on complexity, error history, and knowledge store contents. Disabled with `decision_calls: false`.

**Implementation:** Spawn implementer via Task tool. The SubagentStart hook injects context from SQLite. The agent codes the story and outputs structured JSON. The SubagentStop hook runs typecheck/build/test — if they fail, the agent continues in the same context to fix the issue (self-healing).

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

| Agent | Model | Tools | Memory | Purpose |
|-------|-------|-------|--------|---------|
| implementer | inherit | Bash, Read, Edit, Write, Glob, Grep | project | Code a single story |
| validator | haiku | Bash, Read, Glob, Grep | project | Verify acceptance criteria |
| reviewer | sonnet | Read, Glob, Grep | — | Review PRD quality |
| merger | haiku | Bash, Read, Grep | — | Git branch operations |

- `disallowedTools: [Task]` on implementer prevents subagent spawning
- `model: inherit` means implementer uses the user's configured model
- `memory: project` provides cross-run learning via `.claude/agent-memory/`

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

TaskPlex defines 7 hooks across 5 events in `hooks/hooks.json`, plus 1 agent-scoped hook in `implementer.md` frontmatter:

### PreToolUse: Quality Gate (agent-scoped)

```
implementer.md frontmatter → Bash → check-destructive.sh
```
Blocks: `git push --force`, `git reset --hard`, `git clean -f`, direct pushes to main/master. Defined in the implementer agent's YAML frontmatter (not in `hooks.json`), so it only runs during implementer agent lifecycle — not globally.

### SubagentStart: Knowledge Injection

```
implementer|validator → inject-knowledge.sh
```
Queries SQLite knowledge store for relevant learnings. Returns `additionalContext` JSON that gets injected into the subagent's system prompt. Replaces manual `generate_context_brief()`.

### SubagentStop: Inline Validation

```
implementer → validate-result.sh
```
Extracts learnings from `last_assistant_message` (CLI 2.1.47) instead of grepping transcript files. Runs `typecheck_command`, `build_command`, `test_command` from config. If any fail, returns `{"decision": "block", "reason": "..."}` — the implementer continues in the same context with the error injected as feedback (self-healing). This eliminates most separate validator invocations.

### Monitor Event Hooks (async, fire-and-forget)

```
SubagentStart  → monitor/hooks/subagent-start.sh
SubagentStop   → monitor/hooks/subagent-stop.sh
PostToolUse    → monitor/hooks/post-tool-use.sh
SessionStart   → monitor/hooks/session-lifecycle.sh session.start
SessionEnd     → monitor/hooks/session-lifecycle.sh session.end
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

## 9. Known Issues & Fixes (v2.0.3)

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

---

## 10. Future Roadmap

### Implemented in v2.0

- SubagentStart/Stop hooks (knowledge injection, inline validation)
- SQLite knowledge store with confidence decay
- 1-shot Opus decision calls for model/effort routing
- Auto-migration from `knowledge.md` to SQLite

### Not Yet Implemented

| Feature | Priority | Effort | Notes |
|---------|----------|--------|-------|
| Transcript mining | P2 | Medium | SubagentStop provides `agent_transcript_path`; spawn Haiku to extract implicit learnings |
| Checkpoint resume | P2 | Low | Write checkpoint JSON after each story; resume on restart |
| Live intervention via dashboard | P3 | Medium | REST endpoint for skip/hint/pause commands; orchestrator polls between stories |
| Self-improving prompts | P3 | High | Cross-run analytics proposes `prompt.md` modifications |
| Adaptive PRD rewriting | P2 | Medium | Orchestrator rewrites story criteria after repeated failures |
| Code review agent | P3 | Medium | Review git diff before merge; new `code-reviewer` agent |
| Dependency graph visualization | P3 | Low | Mermaid DAG in monitor dashboard |
| Post-merge regression check | P2 | Low | Full test suite after merge; `git revert` on regression |
| Preemptive conflict detection | P2 | Low | Run `check_before_implementing` across all stories to auto-populate `related_to` |
| Scope drift detection | P2 | Low | Compare git diff against expected file scope |

### Blocked by Platform

| Feature | Blocking Reason |
|---------|----------------|
| Agent Teams for parallel execution | Interactive-only. No headless API. Cannot be driven by `claude -p`. |
| Configurable compaction | API-level only. Claude Code CLI exposes only `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, not full compaction parameters. |
| Persistent Opus orchestrator | Requires either API-direct orchestrator or CLI compaction support. Current Option C (decision calls) provides 80% of the benefit. |

---

## 11. Version History

| Version | Date | Highlights |
|---------|------|------------|
| 2.0.3 | 2026-02-19 | CLI 2.1.47 adoption (last_assistant_message, agent-scoped hooks, context: fork), git repo bootstrap wizard |
| 2.0.0 | 2026-02-17 | Smart Scaffold: SQLite knowledge store, decision calls, SubagentStart/Stop hooks, inline validation |
| 1.2.1 | 2026-02-15 | Execution monitor sidecar (Bun + Vue 3 dashboard) |
| 1.2.0 | 2026-02-15 | Wave-based parallel execution via git worktrees |
| 1.1.0 | 2026-02-14 | Three-layer knowledge architecture |
| 1.0.0 | 2026-02-11 | Initial release — custom subagents, error categorization, quality gate hooks |

For detailed changelogs, see [CLAUDE.md § Version History](./CLAUDE.md#version-history).
