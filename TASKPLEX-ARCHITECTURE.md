# TaskPlex Architecture

**Version 4.0.0** | Last Updated: 2026-02-27

Ground truth for TaskPlex's design, implementation status, known issues, and roadmap. For developer instructions and config schema, see [CLAUDE.md](./CLAUDE.md). For version history, see [CHANGELOG.md](./CHANGELOG.md).

---

## 1. Overview & Philosophy

TaskPlex is an **always-on autonomous development companion** for Claude Code. It combines brainstorming, all 15 Superpowers discipline skills (adapted, MIT licensed from Jesse Vincent), PRD-driven autonomous execution, TDD enforcement, verification gates, two-stage code review, SQLite knowledge persistence, experience-based learning, difficulty-aware routing, reward hacking prevention, and Agent Teams support. Fully replaces Superpowers.

**Core principles:**

1. **Always-on awareness** — proactive context injection via SessionStart hook; skills auto-trigger without requiring `/taskplex:start`
2. **Challenge assumptions first** — brainstorming phase with architect agent before committing to implementation
3. **Discipline before code** — 17 skills enforce TDD, verification, planning, and review practices
4. **Precise PRD** — interactive refinement loop produces verifiable acceptance criteria
5. **Lean context** — skills trimmed 71% (using-taskplex 67 lines, writing-skills 128, prd-converter 165, prd-generator 118)
6. **Fresh context per task** — each agent starts cold with knowledge injected via hooks
7. **Resilient error recovery** — failures categorized, retried with strategy, or skipped; pipeline continues
8. **Dependency enforcement** — stories only execute when all `depends_on` stories have passed
9. **Quality gates via hooks** — destructive commands blocked, inline validation before agent completion, test file integrity checksums
10. **Orchestrator owns state** — agents produce structured output; the bash orchestrator curates knowledge and drives decisions

---

## 2. Current Architecture (v4.0.0)

### Component Structure

```
taskplex/
├── .claude-plugin/plugin.json        # Plugin manifest
├── agents/
│   ├── architect.md                  # Read-only codebase explorer (model: sonnet, brainstorm phase)
│   ├── implementer.md                # Codes a single story (model: inherit)
│   ├── validator.md                  # Verifies acceptance criteria (model: haiku)
│   ├── spec-reviewer.md              # Spec compliance review — Stage 1 (model: haiku)
│   ├── reviewer.md                   # Reviews PRD quality (model: sonnet)
│   ├── merger.md                     # Git branch operations (model: haiku)
│   └── code-reviewer.md              # Code quality review — Stage 2 (model: sonnet)
├── commands/
│   └── start.md                      # 8-checkpoint interactive wizard (optional — proactive path available)
├── skills/                           # 17 skills
│   ├── brainstorm/SKILL.md           # Brainstorming with architect agent (new in v4)
│   ├── prd-generator/SKILL.md        # PRD creation (context: fork)
│   ├── prd-converter/SKILL.md        # Markdown → JSON (context: fork)
│   ├── failure-analyzer/SKILL.md     # Error categorization and retry strategy
│   ├── using-taskplex/SKILL.md       # Always-on 1% gate (67 lines)
│   ├── taskplex-tdd/SKILL.md         # TDD enforcement + rationalization prevention
│   ├── taskplex-verify/SKILL.md      # Verification gates
│   ├── systematic-debugging/         # Adapted Superpowers discipline
│   ├── dispatching-parallel-agents/  # Adapted Superpowers discipline
│   ├── using-git-worktrees/          # Adapted Superpowers discipline
│   ├── finishing-a-development-branch/ # Adapted Superpowers discipline
│   ├── requesting-code-review/       # Adapted Superpowers discipline
│   ├── receiving-code-review/        # Adapted Superpowers discipline
│   ├── subagent-driven-development/  # Adapted Superpowers discipline
│   ├── writing-skills/               # Adapted Superpowers discipline (128 lines)
│   ├── executing-plans/              # Adapted Superpowers discipline
│   └── writing-plans/                # Adapted Superpowers discipline
├── hooks/
│   ├── hooks.json                    # 12 hooks across 10 events
│   ├── stop-guard.sh                 # Stop: prevents premature exit
│   ├── task-completed.sh             # TaskCompleted: gates on test pass
│   ├── inject-knowledge.sh           # SubagentStart: SQLite → additionalContext
│   ├── inject-edit-context.sh        # PreToolUse (agent-scoped in implementer only): file patterns → additionalContext
│   ├── pre-compact.sh               # PreCompact: saves state before compaction
│   ├── validate-result.sh            # SubagentStop: inline validation + learnings
│   ├── session-context.sh            # SessionStart: proactive context injection
│   └── teammate-idle.sh              # TeammateIdle: assigns next story to teammate
├── scripts/
│   ├── taskplex.sh                   # Main orchestration loop
│   ├── parallel.sh                   # Wave-based parallel execution (opt-in)
│   ├── teams.sh                      # Agent Teams orchestrator (opt-in)
│   ├── prompt.md                     # Instructions for each Claude iteration
│   ├── knowledge-db.sh              # SQLite knowledge store helpers
│   ├── decision-call.sh             # Rule-based fast path + 1-shot Opus decision calls
│   ├── check-deps.sh                # Dependency checker (claude, jq, sqlite3, coreutils)
│   ├── check-git.sh                 # Git repo diagnostic (JSON output)
│   └── check-destructive.sh         # PreToolUse: blocks dangerous git commands
├── monitor/
│   ├── server/                       # Bun HTTP + WebSocket + SQLite server
│   ├── client/                       # Vue 3 + Tailwind dashboard
│   ├── hooks/                        # Fire-and-forget event emitters
│   └── scripts/                      # start-monitor.sh, stop-monitor.sh
└── tests/
    ├── run-suite.sh                  # All unit tests (pure bash, no API calls)
    ├── behavioral/test-hooks.sh      # Hook contract tests (5 hooks, ~20 assertions)
    └── test-*.sh                     # Script unit tests (decision-call, knowledge-db, etc.)
```

> **Note:** Structural validation (manifests, hooks, cross-refs, frontmatter, shell syntax) is handled by the marketplace's `validate-plugin-manifests.sh`. All tests are pure bash with no API calls.

### Data Flow

TaskPlex supports two activation paths: the explicit wizard and the proactive path.

#### Proactive Path (default, always-on)

```
Session starts
    │
    ├─ SessionStart hook fires (session-context.sh)
    │   ├─ Detects prd.json, taskplex.config.json, knowledge.db
    │   └─ Injects status summary into conversation context
    │
    ├─ using-taskplex skill (1% gate) auto-triggers on relevant prompts
    │   ├─ Routes to brainstorm skill if exploration needed
    │   ├─ Routes to prd-generator/prd-converter if PRD needed
    │   └─ Routes to taskplex:start if execution needed
    │
    └─ Discipline skills auto-trigger on matching patterns
        ├─ taskplex-tdd: enforces TDD + rationalization prevention
        ├─ taskplex-verify: enforces verification gates
        ├─ systematic-debugging: structured debugging approach
        └─ ... (all 14 adapted Superpowers disciplines)
```

#### Explicit Path (via /taskplex:start)

```
User → /taskplex:start (wizard)
         │
         ├─ Checkpoint 1: Gather project input
         ├─ Checkpoint 2: Validate git repository (init/fix/bootstrap)
         ├─ Checkpoint 3-6: PRD generation → prd.json
         ├─ Checkpoint 7: Config (.claude/taskplex.config.json)
         └─ Checkpoint 8: Launch taskplex.sh
```

#### Execution Pipeline

```
         ┌─────────────────────────────────────────────┐
         │              taskplex.sh (loop)              │
         │                                               │
         │  1. Select next ready story                   │
         │  2. Rule-based fast path check                │
         │     ├─ Skip? → skip story                     │
         │     ├─ Haiku/Sonnet? → use directly           │
         │     └─ Complex? → Opus decision call          │
         │  3. Spawn implementer (--agent flag)           │
         │     ├─ SubagentStart hook injects              │
         │     │  knowledge from SQLite                   │
         │     ├─ PreToolUse hooks (agent-scoped):        │
         │     │  ├─ check-destructive.sh                 │
         │     │  └─ inject-edit-context.sh               │
         │     ├─ Agent implements story (TDD enforced)   │
         │     └─ SubagentStop hook validates              │
         │        (typecheck/build/test + checksums)       │
         │  4. Extract learnings → SQLite                  │
         │  5. Spawn spec-reviewer (Stage 1, mandatory)    │
         │  6. Spawn code-reviewer (Stage 2, opt-in)       │
         │  7. Update prd.json                             │
         │  8. Loop or complete                            │
         └─────────────────────────────────────────────┘
                │
                ▼
         Completion report + optional merge
```

### State Files (in user's project)

| File | Owner | Purpose |
|------|-------|---------|
| `prd.json` | Orchestrator | Source of truth for story status |
| `progress.txt` | Orchestrator | Layer 1: compact operational log |
| `knowledge.db` | Orchestrator | SQLite knowledge store (v2.0+) |
| `knowledge.md` | Orchestrator | Layer 2: curated knowledge (legacy, auto-migrated to SQLite) |
| `.claude/taskplex.config.json` | User/wizard | Execution configuration |
| `.claude/taskplex-{branch}.pid` | Orchestrator | Per-branch PID file |
| `tasks/prd-{feature}.md` | Wizard | Human-readable PRD |

### Key Design Decisions

- **Bash orchestrator, not a persistent agent.** The bash script handles PID management, signal trapping, worktree lifecycle, and crash recovery — things agents can't do reliably. Intelligence is injected via rule-based fast paths and 1-shot decision calls at decision points.
- **Fresh context per subagent.** Each implementer starts cold. Context briefs are injected via SubagentStart hooks querying the SQLite knowledge store, not manually constructed.
- **`jq` as the only JSON parser.** No `yq`, no Python for JSON. Shell scripts stay bash 3.2 compatible (no `declare -A`, no bash 4+ features).
- **Hooks for feedback loops, not just telemetry.** SubagentStart injects knowledge; SubagentStop validates and blocks on failure for self-healing.
- **Rule-based fast path eliminates ~40% of Opus decision calls.** Simple stories (documentation, config changes, single-file edits) are routed directly to haiku/sonnet without an Opus decision call, reducing cost and latency.
- **Always-on proactive path.** SessionStart hook and using-taskplex gate skill ensure TaskPlex is aware of project state without requiring explicit `/taskplex:start` invocation.
- **Reward hacking prevention.** Test file integrity checksums detect when agents modify test files to make them pass rather than fixing the actual code.

---

## 3. Orchestration Loop

### Sequential Mode (default)

```
INIT → TASK SELECTION → FAST PATH / DECISION CALL → IMPLEMENTATION → VALIDATION → REVIEW → ERROR HANDLING → COMPLETION CHECK → loop
```

**Crash recovery (v2.0.6):** On startup, `recover_stuck_stories()` resets any `in_progress` stories back to `pending` (preserving attempt counts). This handles cases where the orchestrator was killed mid-story.

**Task selection:** Find all stories with `passes: false`, filter out those whose `depends_on` contains incomplete stories, filter out skipped stories, pick highest priority.

**Routing (v4.0):** A two-tier routing system selects model/effort per story:
1. **Rule-based fast path** (`decision-call.sh`): Pattern-matches story type (docs, config, single-file) against known complexity buckets. Routes ~40% of stories directly to haiku/sonnet without an Opus call.
2. **Decision call** (remaining ~60%): A 1-shot Opus call selects model/effort based on complexity, error history, and knowledge store contents. Disabled with `decision_calls: false`.

**Effort auto-tuning:** On retries, effort level is automatically escalated (low -> medium -> high) to give the agent more room to solve harder problems.

**Implementation:** Spawn implementer via `--agent implementer` flag on `claude -p`. The SubagentStart hook injects context from SQLite. Agent-scoped PreToolUse hooks inject file-specific patterns before each Edit/Write and block destructive commands. The agent codes the story and outputs structured JSON. The SubagentStop hook runs typecheck/build/test and verifies test file checksums — if they fail, the agent continues in the same context to fix the issue (self-healing). PreCompact hook preserves state if auto-compaction triggers mid-story.

**Review pipeline (v4.0):** After implementation passes validation:
1. **Stage 1 (mandatory):** spec-reviewer agent checks spec compliance
2. **Stage 2 (opt-in):** code-reviewer agent checks code quality (enabled via `code_review: true`)

**Checkpoint (v2.0.6):** After each story state change (`in_progress`, `completed`, `skipped`), `write_checkpoint()` persists a JSON snapshot to `.claude/taskplex-checkpoint.json`.

**Completion check:** All stories pass -> optional merge. All remaining blocked -> report. Max iterations -> report.

### Parallel Mode (wave-based, opt-in)

When `parallel_mode: "parallel"` in config, stories are partitioned into topological waves based on the dependency graph. All stories in a wave run simultaneously in separate git worktrees.

```
Wave 0: [US-001, US-005]  <- no dependencies, parallel
         | merge both | extract learnings | update knowledge
Wave 1: [US-002, US-003]  <- depend on wave 0, parallel
         | merge all | extract learnings | update knowledge
Wave 2: [US-004]           <- depends on wave 1
```

**Conflict safety:** Stories sharing `related_to` targets are split into separate batches within a wave. All process tracking uses space-separated lists (bash 3.2 compatible).

**Implementation:** `scripts/parallel.sh` is sourced conditionally. Key functions: `compute_waves()`, `split_wave_by_conflicts()`, `create_worktree()`, `spawn_parallel_agent()`, `wait_for_agents()`, `merge_story_branch()`.

### Interactive Mode (v4.0, opt-in)

When `interactive_mode: true` in config, the orchestrator pauses between stories for user approval. The user can review the implementation, accept/reject, provide hints, or skip remaining stories.

### Agent Teams Mode (v4.0, opt-in)

When `parallel_mode: "teams"` in config, TaskPlex leverages Claude Code's Agent Teams feature for parallel execution. Instead of managing worktrees directly, the orchestrator delegates to Agent Teams, which manages concurrent agents natively.

**Implementation:** `scripts/teams.sh` provides the orchestrator. The `TeammateIdle` hook (`hooks/teammate-idle.sh`) assigns the next ready story to idle teammates.

**Key differences from worktree parallel mode:**
- Agent Teams manages concurrency natively (no manual worktree lifecycle)
- `TeammateIdle` hook drives story assignment (event-driven, not polling)
- `max_parallel` config controls maximum concurrent teammates

### CLI Invocation Pattern

**Correct `claude -p` invocation for headless agents:**

```bash
env -u CLAUDECODE claude -p "$PROMPT" \
  --output-format json \
  --no-session-persistence \
  --model "$MODEL" \
  --max-turns "$MAX_TURNS" \
  --dangerously-skip-permissions \
  --agent implementer \
  --agents-dir "${CLAUDE_PLUGIN_ROOT}/agents" \
  --allowedTools "Bash,Read,Edit,Write,Glob,Grep"
```

**Critical notes:**
- `env -u CLAUDECODE` is **required** — nested `claude -p` calls fail if the `CLAUDECODE` env var is set (necessary but NOT sufficient inside active sessions — see Known Issues)
- `--dangerously-skip-permissions` is **required** for headless file writes
- `--agent` and `--agents-dir` flags **are available** in the CLI and used for agent invocation (confirmed working since v4.0)
- `-r` flag on `jq` is required for raw string output (no quotes around IDs)
- `claude -p` **hangs inside active Claude Code sessions** — scripts that call `claude -p` must check `$CLAUDECODE` and exit early; run from external terminal or CI only

---

## 4. Knowledge Architecture

### Three-Layer System

**Layer 1: Operational Log (`progress.txt`)** — Orchestrator-only. Compact timestamped entries: story start/complete/fail/retry. Agents never read or write this file.

**Layer 2: Project Knowledge Base (`knowledge.md` -> SQLite)** — Originally a 100-line flat file, auto-migrated to SQLite in v2.0. Contains codebase patterns, environment notes, and learnings extracted from agent output.

**Layer 3: Per-Story Context Brief (ephemeral)** — Generated before each agent spawn by the SubagentStart hook. Contains story details, pre-check results, dependency diffs, relevant knowledge, and retry context. Deleted after use.

### SQLite Knowledge Store (v2.0+)

Tables: `learnings`, `file_patterns`, `error_history`, `decisions`, `runs`, `patterns`.

**Retrieval (via inject-knowledge.sh):**
1. Always include `environment` and `gotcha` category learnings
2. Match `file_patterns` against the current story's `check_before_implementing` results
3. Include recent learnings from dependency stories
4. Apply confidence decay (5%/day — stale learnings auto-expire after ~60 days)
5. Include promoted patterns from the `patterns` table

**Patterns table (v4.0):** Recurring learnings observed across 3+ stories are promoted to the `patterns` table. Patterns have higher base confidence and slower decay, representing durable project knowledge rather than one-off observations.

**Enhanced implicit mining (v4.0):** `mine_implicit_learnings()` extracts 5 pattern types from agent transcripts:
1. File relationship observations
2. Environment/toolchain notes
3. Architecture patterns
4. Naming conventions
5. Testing patterns

**Cross-run persistence:** The DB lives at `knowledge.db` in the project root. Each run tags entries with `run_id`. Previous runs' learnings persist and are available to future runs.

### Decision Calls (v2.0+)

**Rule-based fast path (v4.0):** Before making an Opus decision call, `decision-call.sh` checks the story against pattern rules:
- Documentation-only stories -> haiku, low effort
- Config/single-file changes -> sonnet, low effort
- Stories with 0 acceptance criteria -> skip
- Stories with previous failures -> escalate model + effort

This eliminates ~40% of Opus calls, reducing cost and latency.

**Decision call (remaining):** At each decision point, a 1-shot Opus call selects the optimal approach:

| Decision Point | Input | Output |
|---------------|-------|--------|
| Model/effort selection | Story complexity, criteria count, error history | `{model, effort}` |
| Retry vs. skip | Error output, previous attempts, knowledge | `{decision, reason}` |
| Story rewriting | Failure analysis, original criteria | `{modified_criteria}` |

Configured via `decision_calls` (bool, default true) and `decision_model` (string, default "opus").

---

## 5. Subagents

### Agent Definitions

| Agent | Model | Permission | maxTurns | Tools | Purpose |
|-------|-------|------------|----------|-------|---------|
| architect | sonnet | dontAsk | 30 | Read, Grep, Glob, Bash | Read-only codebase explorer (brainstorm phase) |
| implementer | inherit | bypassPermissions | 150 | Bash, Read, Edit, Write, Glob, Grep | Code a single story (TDD + verify REQUIRED) |
| validator | haiku | dontAsk | 50 | Bash, Read, Glob, Grep | Verify acceptance criteria (read-only) |
| spec-reviewer | haiku | dontAsk | 30 | Read, Grep, Glob, Bash | Spec compliance review — Stage 1 (mandatory) |
| reviewer | sonnet | plan | 30 | Read, Glob, Grep | Review PRD quality |
| merger | haiku | bypassPermissions | 50 | Bash, Read, Grep | Git branch operations |
| code-reviewer | sonnet | dontAsk | 40 | Read, Grep, Glob, Bash | Code quality review — Stage 2 (opt-in) |

- `disallowedTools: [Task]` on implementer prevents subagent spawning
- `disallowedTools: [Write, Edit, Task]` on validator enforces read-only
- `disallowedTools: [Write, Edit, Bash, Task]` on reviewer enforces read-only
- `model: inherit` means implementer uses the user's configured model
- `memory: project` provides cross-run learning via `.claude/agent-memory/`
- `skills: [failure-analyzer]` on implementer preloads error categorization for self-diagnosis
- `permissionMode` on all agents eliminates need for `--dangerously-skip-permissions` in some cases

### Agent Pipeline

```
brainstorm (architect agent)
    |
    v
PRD generation (prd-generator + prd-converter skills)
    |
    v
Per-story loop:
    implementer -> validator -> spec-reviewer -> code-reviewer (opt-in)
    |
    v
merger (on completion)
```

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

TaskPlex defines 12 hooks across 10 events in `hooks/hooks.json`, plus agent-scoped hooks in `implementer.md` frontmatter:

### Global Hooks (hooks.json)

| Event | Matcher | Hook Script | Type | Purpose |
|-------|---------|-------------|------|---------|
| Stop | — | `stop-guard.sh` | sync | Prevents premature exit during active stories |
| TaskCompleted | — | `task-completed.sh` | sync | Gates completion on test pass |
| PostToolUse | — | `monitor/hooks/post-tool-use.sh` | async | Monitor telemetry |
| PostToolUseFailure | — | `monitor/hooks/post-tool-use-failure.sh` | async | Monitor telemetry |
| SubagentStart | `implementer` | `inject-knowledge.sh` | sync | SQLite knowledge injection |
| SubagentStart | `spec-reviewer` | `inject-knowledge.sh` | sync | SQLite knowledge injection (review context) |
| SubagentStart | — | `monitor/hooks/subagent-start.sh` | async | Monitor telemetry |
| SubagentStop | `implementer` | `validate-result.sh` | sync | Inline validation + learnings extraction |
| SubagentStop | — | `monitor/hooks/subagent-stop.sh` | async | Monitor telemetry |
| PreCompact | `auto` | `pre-compact.sh` | sync | Saves state before compaction |
| SessionStart | `startup\|resume\|clear\|compact` | `session-context.sh` | sync | Proactive context injection |
| SessionStart | — | `monitor/hooks/session-lifecycle.sh session.start` | async | Monitor telemetry |
| TeammateIdle | — | `teammate-idle.sh` | sync | Assigns next story to idle teammate |
| SessionEnd | — | `monitor/hooks/session-lifecycle.sh session.end` | async | Monitor telemetry |

### Agent-Scoped Hooks (implementer.md frontmatter)

| Event | Matcher | Hook Script | Purpose |
|-------|---------|-------------|---------|
| PreToolUse | `Bash` | `check-destructive.sh` | Blocks `git push --force`, `git reset --hard`, etc. |
| PreToolUse | `Edit\|Write` | `inject-edit-context.sh` | File-specific patterns from SQLite before each edit |

These are defined in the implementer YAML frontmatter and only run during the implementer lifecycle, not globally. This ensures per-edit context injection does not add latency to non-implementer sessions.

### Hook Details

**Stop: stop-guard.sh** — Checks for active TaskPlex stories. If a story is in progress, returns exit 2 to block premature exit. Uses `stop_hook_active` flag to prevent infinite loops.

**TaskCompleted: task-completed.sh** — Runs the configured test command before allowing task completion. Exit 2 blocks completion with stderr message. Ensures stories are truly validated.

**SubagentStart: inject-knowledge.sh** — Queries SQLite knowledge store for relevant learnings. Returns `additionalContext` JSON that gets injected into the subagent's system prompt. Fires for both `implementer` and `spec-reviewer` agents. Replaces manual `generate_context_brief()`.

**SubagentStop: validate-result.sh** — Extracts learnings from `last_assistant_message`. Runs `typecheck_command`, `build_command`, `test_command` from config. Verifies test file integrity checksums (reward hacking prevention). If any check fails, returns `{"decision": "block", "reason": "..."}` — the implementer continues in the same context with the error injected as feedback (self-healing).

**PreCompact: pre-compact.sh** — Fires before auto-compaction. Saves current story state, git diff snapshot, and progress to SQLite via `save_compaction_snapshot()`. Also writes `.claude/taskplex-pre-compact.json` recovery file. Cannot block compaction (informational only).

**SessionStart: session-context.sh** — Fires on startup, resume, clear, and compact events. Detects `prd.json`, `taskplex.config.json`, and `knowledge.db` in the project. Injects a status summary (active stories, pending count, last run results) into conversation context. Hardened against malformed `prd.json`.

**TeammateIdle: teammate-idle.sh** — Fires when an Agent Teams teammate goes idle. Queries `prd.json` for the next ready story (respecting dependency order) and assigns it to the idle teammate.

**Monitor hooks** — All monitor hooks are async (fire-and-forget) and exit 0 regardless. The monitor being down never blocks Claude Code. Event emission is backgrounded in the orchestrator.

---

## 7. Safety & Quality

### Reward Hacking Prevention (v4.0)

Test file integrity checksums are computed before implementation begins and verified after. If an agent modifies test files to make them pass (rather than fixing the actual code), the SubagentStop hook detects the checksum mismatch and blocks completion.

### Scope Drift Detection

Configurable via `scope_drift_action` in config:
- `"warn"` (default): Logs warning to SQLite when `git diff --stat` shows unexpected files
- `"block"`: Blocks story completion if drift detected
- `"review"`: Routes to spec-reviewer for human-readable drift assessment

### Rationalization Prevention (v4.0)

The `taskplex-tdd` skill includes rationalization prevention tables that detect when an agent is rationalizing skipping tests or verification steps. Common rationalizations are explicitly listed with their correct responses.

### Destructive Command Blocking

Agent-scoped PreToolUse hook blocks: `git push --force`, `git reset --hard`, `git clean -f`, direct pushes to main/master. Allows `--force-with-lease` as the safer alternative.

---

## 8. Monitor Dashboard

Real-time browser dashboard for observing TaskPlex execution. Optional sidecar launched at Checkpoint 8.

### Architecture

```
Hook scripts + orchestrator emit_event()
    | fire-and-forget curl POST
Bun server (port 4444) -> SQLite WAL -> WebSocket broadcast
    |
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

## 9. Error Handling & Retry

### Error Categories

| Category | Detection | Strategy | Max Retries |
|----------|-----------|----------|-------------|
| `env_missing` | "API key", "token", "ECONNREFUSED" | Skip immediately, log for user | 0 |
| `test_failure` | Tests ran but failed | Retry with test output as context | 2 |
| `timeout` | Exit code 124 | Retry with 1.5x timeout | 1 |
| `code_error` | Linter/typecheck/build failures | Retry with error output as context | 2 |
| `dependency_missing` | Import/package not found | Skip, log for user | 0 |
| `unknown` | Unclassifiable | Retry once, then skip | 1 |

### Effort Auto-Tuning on Retries (v4.0)

When a story fails and is retried, the effort level is automatically escalated:
- First attempt: level from routing decision
- First retry: escalate to medium (if was low)
- Second retry: escalate to high

This gives the agent progressively more room to solve harder problems without wasting resources on easy stories.

### Interactive vs. Background Mode

- **Foreground:** On timeout or failure, user gets interactive prompt (skip/retry/abort)
- **Background:** Auto-skip with logging to `.claude/taskplex.log`
- **Interactive (v4.0):** Pauses between stories for user approval (enabled via `interactive_mode: true`)

### Story Completion Logic

A story is marked complete **only when validation passes** — not when the agent signals COMPLETE. The SubagentStop hook runs typecheck/build/test inline and verifies test file checksums; the orchestrator also optionally spawns a validator agent for acceptance criteria verification. Both must pass.

**Important:** `commit_story` must be non-fatal (`|| log`) since the agent may have already committed directly.

---

## 10. Known Issues & Fixes

### CLI Headless Bugs

| Issue | Status | Fix |
|-------|--------|-----|
| `CLAUDECODE` env var breaks nested `claude -p` | Active | Use `env -u CLAUDECODE` before every nested call (necessary but not sufficient inside active sessions) |
| `claude -p` hangs inside active Claude Code sessions | Active | Scripts must check `$CLAUDECODE` and exit early; run from external terminal or CI only |
| Headless writes fail silently | Resolved | Add `--dangerously-skip-permissions` |
| `jq` output includes quotes around IDs | Resolved | Always use `jq -r` for raw strings |
| `--agent`/`--agents-dir` flags assumed to not exist | Resolved (v4.0) | `--agent` and `--agents-dir` ARE available and used for agent invocation |

### Script Patterns (all resolved)

| Issue | Fix |
|-------|-----|
| `set -e` + `[ cond ] && action` at end of function | Crashes when condition is false. Changed to `if/then/fi` |
| Story marked complete on COMPLETE signal | Tied to validation pass, not agent signal |
| `commit_story` failure halts pipeline | Made non-fatal: `commit_story ... \|\| log "WARN" "..."` |
| `set -e` + `grep -c` returns exit 1 on zero matches | Use `\|\| true` instead of `\|\| echo 0` |
| `check-git.sh` `set -e` + `[ ] && action` | Changed to `if/then/fi` |
| `taskplex.sh` `RUN_ID` exported before defined | Moved export after definition |
| `check-deps.sh` missing `sqlite3` check | Added sqlite3 to dependency validation |
| `validate-result.sh` greedy regex learnings extraction | Replaced with jq-first parsing + non-greedy fallback |
| `knowledge-db.sh` process substitution `< <()` | Normalized to here-string `<<<` |
| `send-event.sh` `set -e` contradicts "always exit 0" | Removed `set -e` from async monitor hook |
| `check-destructive.sh` blocks `--force-with-lease` | Added allowlist for `--force-with-lease` |
| `hooks.json` inject-knowledge triggers for validator | Narrowed SubagentStart matcher to `implementer` (and `spec-reviewer` in v3.0) |

---

## 11. Future Roadmap

### Implemented

**v2.0.0-v2.0.8:**
- SubagentStart/Stop hooks (knowledge injection, inline validation)
- SQLite knowledge store with confidence decay
- 1-shot Opus decision calls for model/effort routing
- Auto-migration from `knowledge.md` to SQLite
- `last_assistant_message` for learnings extraction
- Agent-scoped PreToolUse hooks in implementer frontmatter
- `context: fork` on PRD generation/conversion skills
- Effort level tuning for per-story decision calls
- Git repo bootstrap wizard with diagnostic script
- `maxTurns` on all agents, `disallowedTools` enforcement
- PreToolUse per-edit context injection, failure-analyzer preload
- PreCompact hook, checkpoint resume
- Transcript mining, adaptive PRD rewriting, post-merge regression check
- Scope drift detection, code review agent, live intervention via dashboard
- `permissionMode` on all agents, Stop/TaskCompleted hooks
- SOTA audit vs 15+ competing plugins

**v3.0.0 (Proactive Architecture):**
- SessionStart hook (`session-context.sh`) for proactive context injection
- 6th agent: spec-reviewer (haiku, dontAsk) for mandatory Stage 1 review
- Proactive path: skills auto-trigger without `/taskplex:start`
- `using-taskplex` skill as always-on gate
- Hardened session-context.sh against malformed prd.json

**v3.1.0 (Benchmark):**
- Benchmark suite for testing (later collapsed to pure bash unit tests)
- All tests pure bash, no API calls

**v4.0.0 (SOTA Transformation):**
- 7 agents: added architect (sonnet, dontAsk) for brainstorming phase
- 17 skills: brainstorm (new) + 14 adapted Superpowers + failure-analyzer + using-taskplex gate
- Skills trimmed 71% for lean context
- Rule-based fast path eliminates ~40% of Opus decision calls
- Effort auto-tuning on retries
- Test file integrity checksums (reward hacking prevention)
- Rationalization prevention tables in taskplex-tdd
- Configurable scope drift (warn/block/review)
- Confidence decay extended to 60 days (was 30)
- Patterns table (promoted from 3+ stories)
- Enhanced implicit mining (5 pattern types)
- Agent Teams mode via `scripts/teams.sh` + TeammateIdle hook
- Interactive mode (pause between stories)
- `--agent implementer` correctly passed to headless `claude -p` calls
- Segment filtering in prd-converter

### Aspirational

| Feature | Effort | Impact | Details |
|---------|--------|--------|---------|
| Dependency graph visualization | Low | Low | Mermaid DAG in monitor dashboard |
| Self-improving prompts | High | High | Cross-run analytics proposes `prompt.md` modifications. Requires statistical significance across runs. |

### Blocked by Platform

| Feature | Blocking Reason | Last Checked |
|---------|----------------|--------------|
| Configurable compaction | API-level only. CLI exposes `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` but not full compaction parameters. | 2026-02-19 |
| Per-agent effort level in frontmatter | No `effortLevel` field in agent frontmatter. Workaround: set `CLAUDE_CODE_EFFORT_LEVEL` env var per-invocation. | 2026-02-19 |
| `Task(agent_type)` selective restrictions | CLI supports `Task(type)` in `tools:` list but not in `disallowedTools:`. Workaround: blanket `disallowedTools: [Task]`. | 2026-02-19 |

### Resolved / No Longer Relevant

| Item | Resolution |
|------|-----------|
| Memory vs knowledge injection overlap | Overlap is intentional. `memory: project` provides cross-run persistence; SQLite provides decay-weighted fresh context. |
| Effort level tuning for decision calls | Implemented in v2.0.0. Decision call selects effort per-story; env var applied before each agent spawn. |
| `--agent`/`--agents-dir` CLI flags | Resolved in v4.0. Flags exist and work correctly. Agents invoked via `--agent` flag. |
| Agent Teams blocked by platform | Implemented in v4.0 as opt-in via `parallel_mode: "teams"` + `scripts/teams.sh` + TeammateIdle hook. |
| `permissionMode` on agents | Implemented in v2.0.8. All agents use `permissionMode` in frontmatter. |

---

## 12. Version History

| Version | Date | Highlights |
|---------|------|------------|
| 4.0.0 | 2026-02-26 | SOTA transformation: brainstorming + architect agent, 17 skills (14 adapted Superpowers), rule-based routing (~40% Opus savings), reward hacking prevention, Agent Teams, interactive mode, 60-day confidence decay, patterns table, enhanced implicit mining, effort auto-tuning |
| 3.1.0 | 2026-02-24 | Benchmark suite (pure bash, no API calls), test infrastructure cleanup |
| 3.0.0 | 2026-02-22 | Proactive architecture: SessionStart hook, spec-reviewer agent, always-on using-taskplex gate, proactive path without /start |
| 2.0.8 | 2026-02-20 | SOTA audit: permissionMode on all agents, Stop/TaskCompleted hooks, statusMessage/timeout, skill agent routing, $ARGUMENTS fast-start, CLAUDE_ENV_FILE, competitive analysis vs 15+ plugins |
| 2.0.7 | 2026-02-19 | v2.1 Batch 3: Transcript mining, adaptive PRD rewriting, post-merge regression check, scope drift detection, code review agent, live intervention via dashboard |
| 2.0.6 | 2026-02-19 | v2.1 Batch 2: PreToolUse per-edit context injection, failure-analyzer preload on implementer, PreCompact hook, checkpoint resume |
| 2.0.5 | 2026-02-19 | v2.1 Batch 1: maxTurns on agents, disallowedTools enforcement, PostToolUseFailure hook, allowed-tools format fix, memory vs knowledge docs |
| 2.0.4 | 2026-02-19 | Bug fix round: 9 fixes from code-simplifier + docs compliance review |
| 2.0.3 | 2026-02-19 | CLI 2.1.47 adoption (last_assistant_message, agent-scoped hooks, context: fork), git repo bootstrap wizard |
| 2.0.0 | 2026-02-17 | Smart Scaffold: SQLite knowledge store, decision calls, SubagentStart/Stop hooks, inline validation |
| 1.2.1 | 2026-02-15 | Execution monitor sidecar (Bun + Vue 3 dashboard) |
| 1.2.0 | 2026-02-15 | Wave-based parallel execution via git worktrees |
| 1.1.0 | 2026-02-14 | Three-layer knowledge architecture |
| 1.0.0 | 2026-02-11 | Initial release — custom subagents, error categorization, quality gate hooks |

For detailed changelogs, see [CHANGELOG.md](./CHANGELOG.md).
