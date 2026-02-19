# CLAUDE.md

**Version 2.0.3** | Last Updated: 2026-02-19

Developer instructions for working with the TaskPlex plugin for Claude Code CLI.

---

## Overview

TaskPlex is a **resilient autonomous development assistant** — the next-generation successor to SDK Bridge. It provides a single command (`/taskplex:start`) that:
1. Generates detailed PRDs with clarifying questions
2. Converts to executable JSON format with dependency inference
3. Runs custom subagents with error categorization, retry strategies, and branch lifecycle management

**Philosophy:** Precise PRD, sequential execution, fresh context per task, resilient error recovery.

**What's new vs SDK Bridge:**
- Custom subagents (implementer, validator, reviewer, merger) replace monolithic `claude -p` calls
- Error categorization with intelligent retry/skip decisions
- Dependency-aware task selection (enforced, not just tracked)
- Branch lifecycle management (create, merge, cleanup)
- Quality gate hooks (block destructive commands during implementation)
- Failure analyzer skill for structured error diagnosis
- **v1.1:** Three-layer knowledge architecture (operational log, knowledge base, context briefs)
- **v1.1:** Structured agent output with learnings extraction
- **v1.1:** Per-story context briefs with dependency diffs
- **v1.2:** Wave-based parallel execution via git worktrees (opt-in)
- **v1.2:** Conflict detection using `related_to` for safe parallelism
- **v1.2:** Knowledge propagation across parallel waves
- **v1.2.1:** Execution monitor sidecar (Bun + Vue 3 dashboard)
- **v2.0:** Smart Scaffold: SQLite knowledge store, 1-shot decision calls, SubagentStart/Stop hooks
- **v2.0:** Model routing: per-story haiku/sonnet/opus selection based on complexity
- **v2.0:** Inline validation with agent self-healing (SubagentStop hook)
- **v2.0.3:** Leverages CLI 2.1.47 features: `last_assistant_message`, agent frontmatter hooks, `context: fork` skills

---

## Architecture

### Component Structure

```
taskplex/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest (v1.2.0)
├── .github/
│   └── workflows/
│       └── notify-marketplace.yml  # Marketplace webhook notification
├── agents/
│   ├── implementer.md           # Codes a single story, outputs structured result
│   ├── validator.md             # Verifies acceptance criteria (read-only)
│   ├── reviewer.md              # Reviews PRD from specific angles
│   └── merger.md                # Git branch operations
├── assets/
│   ├── taskplex-orchestration-flow.png    # Architecture diagram
│   └── taskplex-knowledge-architecture.png # Knowledge layer diagram
├── commands/
│   └── start.md                 # Interactive wizard (7-checkpoint workflow)
├── hooks/
│   └── hooks.json               # PostToolUse: block destructive git commands
├── skills/
│   ├── prd-generator/           # PRD creation with clarifying questions
│   │   └── SKILL.md
│   ├── prd-converter/           # Markdown → JSON converter with dependency inference
│   │   └── SKILL.md
│   └── failure-analyzer/        # Error categorization and retry strategy
│       └── SKILL.md
├── monitor/
│   ├── server/                  # Bun HTTP + WebSocket + SQLite server
│   │   ├── index.ts             # API routes, WebSocket, static serving
│   │   ├── db.ts                # SQLite schema and queries
│   │   ├── events.ts            # Event validation and enrichment
│   │   └── analytics.ts         # Dashboard analytics queries
│   ├── client/                  # Vue 3 + Tailwind dashboard
│   │   └── src/
│   │       ├── views/           # Timeline, StoryGantt, ErrorPatterns, AgentInsights
│   │       ├── components/      # EventRow, FilterBar, WaveProgress, StoryCard
│   │       └── composables/     # useWebSocket, useApi, useFilters
│   ├── hooks/                   # Event-emitting hook scripts
│   │   ├── send-event.sh        # Universal fire-and-forget event sender
│   │   ├── subagent-start.sh    # SubagentStart hook → monitor
│   │   ├── subagent-stop.sh     # SubagentStop hook → monitor
│   │   ├── post-tool-use.sh     # PostToolUse hook → monitor
│   │   └── session-lifecycle.sh # SessionStart/SessionEnd hook → monitor
│   └── scripts/
│       ├── start-monitor.sh     # Launch server, build client, open browser
│       └── stop-monitor.sh      # Graceful shutdown with PID file
├── scripts/
│   ├── taskplex.sh              # Main bash loop (orchestrator)
│   ├── parallel.sh              # Parallel execution functions (sourced conditionally)
│   ├── prompt.md                # Instructions for each Claude iteration
│   ├── check-deps.sh            # Dependency checker (claude, jq, coreutils)
│   ├── check-git.sh             # Git repo diagnostic (state, dirty files, .gitignore)
│   ├── check-destructive.sh     # Hook script: blocks destructive git commands
│   └── prd.json.example         # Reference format
├── examples/
│   ├── prd-simple-feature.md    # Simple PRD example
│   └── prd-complex-feature.md   # Complex PRD with decomposition
├── README.md                    # Public documentation with architecture diagrams
├── TASKPLEX-ARCHITECTURE.md     # Architecture ground truth (design, issues, roadmap)
└── .gitignore
```

### Component Roles

**Commands (`start.md`):**
- Single entry point orchestrating 8-checkpoint workflow
- Checkpoint 2 validates git state (or bootstraps a fresh repo)
- Uses AskUserQuestion for user input at decision points
- Invokes skills via Task tool for PRD generation/conversion
- Launches bash scripts via Bash tool for execution

**Agents:**
- `implementer`: Implements a single user story. Tools: Bash, Read, Edit, Write, Glob, Grep. Disallowed: Task (no subagent spawning). Model: inherit from parent. Memory: project. Outputs structured JSON with learnings, per-AC results, and retry hints.
- `validator`: Verifies completed stories work. Tools: Bash, Read, Glob, Grep. Model: haiku (fast, cheap). Memory: project. Read-only — does NOT fix issues.
- `reviewer`: Reviews PRDs from specific angles (security, performance, testability, sizing). Tools: Read, Glob, Grep. Model: sonnet. No memory (runs infrequently).
- `merger`: Git branch lifecycle (create, merge, cleanup). Tools: Bash, Read, Grep. Model: haiku. No memory (git ops only).

**Skills:**
- `prd-generator`: Creates detailed PRDs with verifiable acceptance criteria and dependency tracking. Uses 5-criteria threshold for story decomposition.
- `prd-converter`: Transforms markdown PRD to `prd.json` with inferred `depends_on`, `related_to`, `implementation_hint`, and `check_before_implementing` fields.
- `failure-analyzer`: Categorizes failed task output into: `env_missing`, `test_failure`, `timeout`, `code_error`, `dependency_missing`, `unknown`. Recommends retry strategy with max retry limits per category.

**Hooks:**
- `PreToolUse` on Bash (agent-scoped): `check-destructive.sh` blocks `git push --force`, `git reset --hard`, `git clean`, and direct pushes to main/master. Defined in `implementer.md` frontmatter — only runs during implementer agent lifecycle, not globally.
- `SubagentStart/Stop`: Async hooks that emit events to the monitor sidecar for agent lifecycle tracking.
- `PostToolUse` (monitor): Async hook that emits tool usage events for agent behavior analysis.
- `SessionStart/End`: Async hooks that track session lifecycle in the monitor.

**Scripts:**
- `taskplex.sh`: Main orchestration loop — runs fresh Claude instances until all stories complete
- `parallel.sh`: Wave-based parallel execution functions — sourced conditionally when `parallel_mode=parallel`
- `prompt.md`: Instructions given to each Claude agent (includes "check before implementing" guidance)
- `check-deps.sh`: Validates `claude` CLI, `jq`, and `coreutils` installation
- `check-destructive.sh`: PostToolUse hook — blocks dangerous git commands

### State Files (User's Project)

```
.claude/
├── taskplex.config.json         # Config (JSON format)
├── taskplex-{branch}.pid        # Per-branch PID file
└── taskplex.log                 # Background mode log

tasks/
└── prd-{feature}.md             # Human-readable PRD

prd.json                         # Execution format (source of truth)
progress.txt                     # Layer 1: Operational log (orchestrator-only)
knowledge.md                     # Layer 2: Project knowledge base (orchestrator-curated)

../.worktrees/<project>/         # Parallel mode: worktree directories (ephemeral)
```

### Three-Layer Knowledge Architecture (v1.1)

TaskPlex uses a three-layer system for knowledge management:

**Layer 1: Operational Log (`progress.txt`)** — Orchestrator-only. Compact timestamped entries tracking story start/complete/fail/retry events. Agents never read or write this file.

**Layer 2: Project Knowledge Base (`knowledge.md`)** — Orchestrator-curated. After each story, the orchestrator extracts `learnings` from the agent's structured output and appends them here. Contains "Codebase Patterns", "Environment Notes", and "Recent Learnings" sections. 100-line max with oldest-entry trimming.

**Layer 3: Per-Story Context Brief (ephemeral)** — Generated before each agent spawn. Contains story details, `check_before_implementing` results, git diffs from dependency stories, relevant knowledge from `knowledge.md`, and retry context. Passed to the agent via the prompt. Deleted after use.

---

## Key Features

### 1. Custom Subagents

Each agent has restricted tools and a specific model, replacing the monolithic `claude -p` approach:

| Agent | Model | Tools | Purpose |
|-------|-------|-------|---------|
| implementer | inherit | Bash, Read, Edit, Write, Glob, Grep | Code a single story |
| validator | haiku | Bash, Read, Glob, Grep | Verify acceptance criteria |
| reviewer | sonnet | Read, Glob, Grep | Review PRD quality |
| merger | haiku | Bash, Read, Grep | Git branch operations |

### 2. Error Categorization & Retry

When a task fails, the failure-analyzer skill classifies the error:

| Category | Retry? | Max Retries | Action |
|----------|--------|-------------|--------|
| `env_missing` | No | 0 | Skip, log for user |
| `test_failure` | Yes | 2 | Retry with test output as context |
| `timeout` | Yes | 1 | Retry with 1.5x timeout |
| `code_error` | Yes | 2 | Retry with error output as context |
| `dependency_missing` | No | 0 | Skip, log for user |
| `unknown` | Once | 1 | Retry once, then skip |

### 3. Resilience & Process Management

**Iteration Timeouts:**
- Default: 900 seconds (15 minutes)
- Configurable via `iteration_timeout` in config
- Foreground: Interactive prompt (skip/retry/abort)
- Background: Auto-skip with logging

**Process Management:**
- Trap-based cleanup (graceful SIGTERM, force SIGKILL fallback)
- Per-branch PID files (allows parallel execution)
- Duplicate run prevention
- Automatic stale file cleanup
- Structured logging to stderr (`[INIT]`, `[ITER-N]`, `[CLEANUP]`, `[TIMEOUT]`)

### 4. Already-Implemented Detection

**Prompt-based** (`scripts/prompt.md`):
- Agents search for existing implementation before coding
- Verify each acceptance criterion
- If all met: mark complete and skip
- If partial: implement only missing pieces
- Never refactor working code

### 5. Wave-Based Parallel Execution (v1.2)

When `parallel_mode: "parallel"`, stories are partitioned into topological waves based on the dependency graph. All stories in a wave run simultaneously in separate git worktrees:

1. **Wave computation** — stories with no unsatisfied dependencies form wave 0, their dependents form wave 1, etc.
2. **Conflict splitting** — stories sharing `related_to` targets are separated into different batches within a wave (prevents merge conflicts)
3. **Worktree creation** — each story gets `git worktree add -b <story-branch> <dir> <feature-branch>`
4. **Parallel agents** — Claude agents run in separate worktree directories via subshells
5. **Sequential merge** — completed branches merge back into the feature branch in priority order
6. **Knowledge propagation** — learnings from all stories in a wave update `knowledge.md` before the next wave

**Key constraint:** bash 3.2 compatible — uses space-separated lists instead of associative arrays for process tracking.

### 6. Quality Gate Hooks

**PostToolUse hook** blocks destructive commands:
- `git push --force` / `git push -f`
- `git reset --hard`
- `git clean -f`
- Direct `git push` to main/master

### 7. Enhanced PRD Generation

**Story Decomposition** (5-criteria threshold):
- 3-5 criteria: Ideal story size
- 6-7 criteria: Warning, consider splitting
- 8+ criteria: Must split into multiple stories

**Verifiable Acceptance Criteria:**
- Every criterion must be checkable (not vague)
- Always include "Typecheck passes" as final criterion
- UI stories include "Verify in browser using dev-browser skill"

**Dependency Tracking:**
- `depends_on`: Hard dependencies (must complete first)
- `related_to`: Soft dependencies (check for related work)
- `implementation_hint`: Free-form guidance
- `check_before_implementing`: Grep commands to detect existing code

### 8. Execution Monitor Sidecar (v1.2.1)

Real-time browser dashboard for observing TaskPlex execution. Uses a hooks-first architecture where Claude Code hooks and orchestrator `curl` calls feed events into a Bun+SQLite server, which broadcasts to connected Vue 3 dashboard clients via WebSocket.

**Architecture:**
```
Claude Code hooks (SubagentStart/Stop, PostToolUse, Session*)
    ↓ fire-and-forget curl POST
taskplex.sh emit_event() calls (story.start, story.complete, etc.)
    ↓ backgrounded curl POST
Bun server (port 4444) → SQLite WAL → WebSocket broadcast
    ↓
Vue 3 dashboard (Timeline, StoryGantt, ErrorPatterns, AgentInsights)
```

**Two event sources:**
- `hook`: Automatic from Claude Code lifecycle (subagent spawns, tool usage, sessions)
- `orchestrator`: Explicit `emit_event` calls from `taskplex.sh` at state transitions

**Dashboard views:**
- **Timeline**: Real-time event stream with filters (story, source, event type), wave progress bars
- **Story Gantt**: Horizontal duration bars per story, color-coded status, wave separators, retry segments
- **Error Patterns**: Error category breakdown with counts, diagnostic table
- **Agent Insights**: Tool usage by agent type, duration averages, already-implemented detection rates

**Usage:**
```bash
# Start monitor (done automatically by wizard at Checkpoint 6)
bash ${CLAUDE_PLUGIN_ROOT}/monitor/scripts/start-monitor.sh

# Stop monitor
bash ${CLAUDE_PLUGIN_ROOT}/monitor/scripts/stop-monitor.sh

# Set port (default: 4444)
export TASKPLEX_MONITOR_PORT=4444
```

**Key design decisions:**
- All hook scripts exit 0 regardless — monitor being down never blocks Claude Code
- All `emit_event` calls are backgrounded (`&`) — never blocks orchestrator
- SQLite WAL mode for concurrent read/write access
- Events tied to a `run_id` for per-invocation correlation
- Server auto-detects via `TASKPLEX_MONITOR_PORT` env var or PID file

---

## Development Guidelines

### Modifying Components

**Commands (`start.md`):**
- Follow 8-checkpoint structure
- Use AskUserQuestion at decision points
- Test both foreground and background modes

**Agents (`agents/*.md`):**
- YAML frontmatter defines: name, description, tools, disallowedTools, model
- Keep tool lists minimal (principle of least privilege)
- Use `model: haiku` for cheap/fast agents (validator, merger)
- Use `model: sonnet` for quality-sensitive agents (reviewer)
- Use `model: inherit` for agents that should use user's configured model (implementer)

**Skills (`skills/*/SKILL.md`):**
- Single responsibility per skill
- Lettered options for questions (A, B, C, D)
- Document expected input/output format

**Hooks (`hooks/hooks.json`):**
- Follow Claude Code hooks schema
- `${CLAUDE_PLUGIN_ROOT}` resolves to plugin install path
- Hook scripts must be executable (`chmod +x`)

**Scripts (`scripts/*.sh`):**
- Use `set -e` for fail-fast
- Keep portable (avoid bash 4+ features)
- Use `${CLAUDE_PLUGIN_ROOT}` in command references
- Use absolute paths in scripts
- Make executable: `chmod +x scripts/*.sh`

### Testing Changes

```bash
# 1. Make changes in this directory

# 2. Reinstall plugin
/plugin uninstall taskplex@flight505-marketplace
/plugin install taskplex@flight505-marketplace

# 3. Restart Claude Code

# 4. Test command
/taskplex:start

# 5. Verify files created
ls -la .claude/ tasks/ prd.json progress.txt
```

---

## File Conventions

**Naming:**
- Commands: `kebab-case.md`
- Skills: `kebab-case/` directories with `SKILL.md`
- Agents: `kebab-case.md` in `agents/` directory
- Scripts: `kebab-case.sh` or `kebab-case.md`
- Hooks: `hooks.json` in `hooks/` directory
- Config: `.claude/taskplex.config.json`

**Path References:**
- In commands (markdown): `${CLAUDE_PLUGIN_ROOT}/scripts/file.sh`
- In skills (markdown): relative paths `./examples/file.md`
- In hooks (JSON): `${CLAUDE_PLUGIN_ROOT}/scripts/file.sh`
- In bash scripts: absolute paths `$HOME/.claude/...`
- Never hardcode absolute paths in committed files

**Script Permissions:**
```bash
chmod +x scripts/*.sh
git add --chmod=+x scripts/*.sh
```

---

## Configuration Schema

`.claude/taskplex.config.json` format:

```json
{
  "max_iterations": 25,
  "iteration_timeout": 900,
  "execution_mode": "foreground",
  "execution_model": "sonnet",
  "effort_level": "",
  "branch_prefix": "taskplex",
  "max_retries_per_story": 2,
  "max_turns": 200,
  "merge_on_complete": false,
  "test_command": "",
  "build_command": "",
  "typecheck_command": "",
  "parallel_mode": "sequential",
  "max_parallel": 3,
  "worktree_dir": "",
  "worktree_setup_command": "",
  "conflict_strategy": "abort"
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_iterations` | int | 25 | Stop after N iterations (1 story = 1-3 iterations) |
| `iteration_timeout` | int | 900 | Timeout per iteration in seconds (15 min) |
| `execution_mode` | string | "foreground" | "foreground" (interactive) or "background" |
| `execution_model` | string | "sonnet" | "sonnet" or "opus" for story implementation |
| `effort_level` | string | "" | "low", "medium", or "high" (Opus 4.6 only, empty = default) |
| `branch_prefix` | string | "taskplex" | Git branch prefix |
| `max_retries_per_story` | int | 2 | Max retry attempts per story before skipping |
| `max_turns` | int | 200 | Max agentic turns per Claude invocation |
| `merge_on_complete` | bool | false | Auto-merge to main when all stories complete |
| `test_command` | string | "" | Project test command (e.g., "npm test") |
| `build_command` | string | "" | Project build command (e.g., "npm run build") |
| `typecheck_command` | string | "" | Project typecheck command (e.g., "tsc --noEmit") |
| `parallel_mode` | string | "sequential" | "sequential" (default) or "parallel" (worktree-based) |
| `max_parallel` | int | 3 | Max concurrent agents per wave batch |
| `worktree_dir` | string | "" | Custom worktree base dir. Empty = `../.worktrees` relative to project |
| `worktree_setup_command` | string | "" | Command run in each new worktree (e.g., "npm install") |
| `conflict_strategy` | string | "abort" | "abort" (skip on merge conflict) or "merger" (invoke merger agent) |

**Iteration Guidelines:**
- Each story typically consumes 1-3 iterations
- Simple stories: 1 iteration (already-implemented check passes)
- Standard stories: 1-2 iterations (implement + verify)
- Complex stories: 2-3 iterations (may need retries/fixes)
- Formula: `stories x 2.5 = recommended iterations`

**Model Selection:**
- `execution_model`: Which Claude model implements the stories (default: sonnet)
- `effort_level`: Controls reasoning depth for Opus 4.6 (low/medium/high). Ignored for Sonnet. Empty by default.
  - `high`: Deep reasoning, best quality, highest cost
  - `medium`: Best cost/quality balance
  - `low`: Fastest, minimal reasoning, cheapest
- Planning (PRD generation) uses `CLAUDE_CODE_SUBAGENT_MODEL` env var (recommend: opus)

---

## Authentication

TaskPlex supports two methods with intelligent fallback:

**OAuth Token (Recommended for Max subscribers):**
```bash
claude setup-token
export CLAUDE_CODE_OAUTH_TOKEN='your-token'
```

**API Key (Fallback):**
```bash
export ANTHROPIC_API_KEY='your-key'
```

Script prioritizes OAuth if available, falls back to API key otherwise.

---

## Debugging

### Command Not Appearing

```bash
# Check installation
cat ~/.claude/plugins/installed_plugins.json | jq '.plugins | keys'

# Verify plugin structure
ls -la ~/.claude/plugins/cache/flight505-marketplace/taskplex/*/

# Check manifest
cat ~/.claude/plugins/cache/flight505-marketplace/taskplex/*/.claude-plugin/plugin.json
```

### Loop Issues

```bash
# Test script directly
bash scripts/taskplex.sh 1

# Check Claude CLI
claude -p "What is 2+2?" --output-format json --no-session-persistence

# Verify dependencies
bash scripts/check-deps.sh
```

### Skills Not Loading

```bash
# Verify skill structure
ls -la skills/*/SKILL.md

# Check frontmatter
head -5 skills/*/SKILL.md
```

### Agent Issues

```bash
# Verify agent structure
ls -la agents/*.md

# Check frontmatter has required fields
head -15 agents/*.md
```

### Hook Issues

```bash
# Verify hooks.json is valid JSON
jq . hooks/hooks.json

# Test destructive command blocker
echo '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' | bash scripts/check-destructive.sh
```

---

## Version History

### v2.0.3 (2026-02-19)

**CLI 2.1.47 Feature Adoption + Git Bootstrap:**

**Added:**
- `scripts/check-git.sh` — Git repository diagnostic script outputting JSON state (repo exists, dirty files, branch status, .gitignore coverage, stale worktrees). Handles fresh folders (no repo) gracefully.
- Checkpoint 2 in wizard: "Validate Git Repository" — can bootstrap a fresh repo with `git init`, stash/commit dirty state, fix detached HEAD, update .gitignore, and prune stale worktrees. Wizard is now 8 checkpoints (was 7).

**Changed:**
- `hooks/validate-result.sh` — Learnings extraction now uses `last_assistant_message` from SubagentStop hook input instead of grepping the transcript file. Simpler, faster, no file I/O.
- `agents/implementer.md` — Destructive command hook (`check-destructive.sh`) moved from global `hooks.json` into implementer YAML frontmatter as a scoped `PreToolUse` hook. Only runs during implementer lifecycle, reducing overhead.
- `hooks/hooks.json` — Removed global `PreToolUse` Bash hook (now agent-scoped in implementer.md).
- `skills/prd-generator/SKILL.md` — Added `context: fork` to run PRD generation in isolated subagent context, preserving main conversation context window.
- `skills/prd-converter/SKILL.md` — Added `context: fork` to run PRD conversion in isolated subagent context.
- `commands/start.md` — Renumbered all checkpoints (1-8), added git validation as Checkpoint 2, fixed cross-references.

**Leverages:**
- `last_assistant_message` field in SubagentStop hooks (CLI 2.1.47)
- Agent frontmatter hooks with `PreToolUse` scoping (CLI 2.1.0)
- `context: fork` for skills running in isolated subagent context (CLI 2.1.0)

### v2.0.0 (2026-02-17)

**Smart Scaffold Architecture — Hook-Based Intelligence:**

**Added:**
- `scripts/knowledge-db.sh` — SQLite knowledge store helpers (schema, CRUD, confidence decay, migration)
- `scripts/decision-call.sh` — 1-shot Opus decision calls for per-story model/effort routing
- `hooks/inject-knowledge.sh` — SubagentStart hook: queries SQLite, runs pre-checks, injects context
- `hooks/validate-result.sh` — SubagentStop hook: runs typecheck/build/test, blocks agent on failure for self-healing
- `tests/` — Test suite for knowledge-db, inject-knowledge, validate-result, decision-call
- SQLite knowledge store (`knowledge.db`): learnings, file_patterns, error_history, decisions, runs tables
- Confidence decay at 5%/day (stale learnings auto-expire after ~30 days)
- One-time idempotent migration from `knowledge.md` to SQLite
- Model routing: decision call picks haiku/sonnet/opus per story based on complexity and history
- Enriched completion report with decision breakdown, knowledge stats, error patterns

**Changed:**
- `scripts/taskplex.sh` — sources v2.0 modules, decision call in main loop, SQLite integration
- `hooks/hooks.json` — added SubagentStart (inject-knowledge) and SubagentStop (validate-result) hook entries
- `agents/implementer.md` — updated for hook-based context injection and inline validation
- `scripts/prompt.md` — updated for hook-based workflow
- `commands/start.md` — added intelligence configuration question at Checkpoint 6
- `extract_learnings()` — writes to SQLite instead of knowledge.md
- `handle_error()` — records to SQLite error_history
- `generate_report()` — includes SQLite-backed intelligence report

**New Config Fields:**
- `decision_calls` (bool, default true) — enable 1-shot decision calls
- `decision_model` (string, default "opus") — model for decision calls
- `knowledge_db` (string, default "knowledge.db") — SQLite knowledge store path
- `validate_on_stop` (bool, default true) — enable SubagentStop inline validation
- `model_routing` (string, default "auto") — "auto" (decision call picks) or "fixed" (use execution_model)

**Backward Compatible:**
- Setting `decision_calls: false, validate_on_stop: false` gives exact v1.2.1 behavior
- Wizard offers "Classic mode" option for full backward compatibility
- knowledge.md auto-migrated to SQLite on first run

### v1.2.1 (2026-02-15)

**Execution Monitor Sidecar:**

**Added:**
- `monitor/server/` — Bun HTTP + WebSocket server with SQLite storage (db.ts, events.ts, analytics.ts, index.ts)
- `monitor/client/` — Vue 3 + Tailwind CSS dashboard with 4 views (Timeline, StoryGantt, ErrorPatterns, AgentInsights)
- `monitor/hooks/` — Fire-and-forget hook scripts (send-event.sh, subagent-start.sh, subagent-stop.sh, post-tool-use.sh, session-lifecycle.sh)
- `monitor/scripts/` — Lifecycle management (start-monitor.sh, stop-monitor.sh)
- `emit_event()` function in taskplex.sh — orchestrator event emission at 15+ state transitions
- `emit_run_start()` / `emit_run_end()` — run lifecycle tracking via REST API
- Monitor launch option in wizard Checkpoint 6
- WebSocket real-time broadcast to connected dashboard clients
- REST API: events, runs, analytics endpoints (timeline, errors, tools, summary, agents)

**Changed:**
- `hooks/hooks.json` — added 5 async monitor hooks (SubagentStart, SubagentStop, PostToolUse, SessionStart, SessionEnd)
- `scripts/taskplex.sh` — integrated monitor event emission (~80 lines), auto-detect monitor via env var or PID file
- `commands/start.md` — added monitor enable/disable question at Checkpoint 6, monitor launch at Checkpoint 7
- `.gitignore` — added monitor build artifacts exclusions

### v1.2.0 (2026-02-15)

**Wave-Based Parallel Execution:**

**Added:**
- `scripts/parallel.sh` — all parallel execution functions, sourced conditionally by taskplex.sh
- `compute_waves()` — jq-based topological sort partitioning stories into dependency-free waves
- `split_wave_by_conflicts()` — splits waves into conflict-free batches using `related_to` overlap detection
- Worktree lifecycle: `create_worktree()`, `setup_worktree()`, `cleanup_worktree()`, `cleanup_all_worktrees()`
- Parallel agent management: `spawn_parallel_agent()`, `wait_for_agents()` with PID polling
- Merge flow: `merge_story_branch()`, `handle_merge_conflict()` with configurable conflict strategy
- `run_wave_parallel()` — full wave orchestration (create → spawn → wait → validate → merge → learn)
- `run_parallel_loop()` — entry point replacing sequential for-loop when parallel mode active
- New config fields: `parallel_mode`, `max_parallel`, `worktree_dir`, `worktree_setup_command`, `conflict_strategy`
- Worktree awareness instructions in `prompt.md` and `implementer.md`
- Parallel execution question in wizard Checkpoint 6

**Changed:**
- `taskplex.sh` conditionally sources `parallel.sh` and branches to wave-based loop
- `load_config()` reads new parallel config fields
- Cleanup trap calls `cleanup_all_worktrees()` in parallel mode
- `generate_report()` includes execution mode in summary

**Backward Compatible:**
- Default `parallel_mode: "sequential"` preserves v1.1 behavior exactly
- `parallel.sh` is only sourced when parallel mode is active
- All existing config options remain valid

### v1.1.0 (2026-02-14)

**Three-Layer Knowledge Architecture:**

**Added:**
- Three-layer knowledge system: operational log (Layer 1), project knowledge base (Layer 2), per-story context briefs (Layer 3)
- `knowledge.md` — orchestrator-curated knowledge base with 100-line max and oldest-entry trimming
- `generate_context_brief()` — generates targeted context for each agent spawn (dependency diffs, existing code checks, knowledge)
- Structured agent output schema with `learnings`, `acceptance_criteria_results`, `retry_hint` fields
- `memory: project` on implementer and validator agents for cross-run learning
- Knowledge extraction from structured agent output after each story
- Environment/dependency warnings automatically added to knowledge.md on failures

**Changed:**
- `progress.txt` simplified to orchestrator-only operational log (agents no longer write to it)
- `prompt.md` simplified: removed progress.txt/AGENTS.md writing duties from agents
- `implementer.md` updated with comprehensive structured output schema and context brief reference
- Retry logic now uses `retry_hint` from agent output and generates context briefs with failure context
- Archiving now includes `knowledge.md`

**Removed:**
- Agent responsibility for writing to progress.txt
- "Consolidate Patterns" section from agent prompt
- "Update AGENTS.md Files" section from agent prompt

### v1.0.0 (2026-02-11)

**Initial release — successor to SDK Bridge v4.8.1:**

**Added:**
- Custom subagents: implementer, validator, reviewer, merger
- Failure analyzer skill with 6 error categories and retry strategies
- PostToolUse hook to block destructive git commands
- JSON configuration format (replaces YAML frontmatter)
- Structured agent output format with error categorization

**Inherited from SDK Bridge:**
- Interactive wizard with 7 checkpoints
- PRD generator skill with smart decomposition
- PRD converter skill with dependency inference
- Configurable iteration timeouts
- Already-implemented detection
- Robust process management
- Verifiable acceptance criteria
- Automatic archiving of previous runs

**Architecture changes:**
- Monolithic `claude -p` replaced with purpose-built agents
- Config moved from `.claude/sdk-bridge.local.md` (YAML) to `.claude/taskplex.config.json` (JSON)
- Branch prefix changed from `sdk-bridge/` to `taskplex/`
- All references renamed from sdk-bridge to taskplex

---

## References

- [Claude Code CLI](https://code.claude.com/docs/en/cli-reference.md)
- [Claude Code Headless Mode](https://code.claude.com/docs/en/headless.md)
- [Claude Code Custom Subagents](https://code.claude.com/docs/en/sub-agents.md)
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks.md)
- [Plugin Development Guide](https://github.com/anthropics/claude-code/blob/main/docs/plugins.md)
- [Marketplace Format](https://github.com/anthropics/claude-code/blob/main/docs/plugin-marketplace.md)
- [TaskPlex Architecture](./TASKPLEX-ARCHITECTURE.md)

---

**Maintained by:** Jesper Vang (@flight505)
**Repository:** https://github.com/flight505/taskplex
**License:** MIT
