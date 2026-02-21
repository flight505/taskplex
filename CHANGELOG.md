# Changelog

All notable changes to TaskPlex are documented here.

---

### v2.0.8 (2026-02-20)

**SOTA Audit — Complete CLI Feature Coverage + Competitive Intelligence:**

**Added:**
- `hooks/stop-guard.sh` — Stop hook prevents premature exit when stories are in_progress or pending. Checks `stop_hook_active` to prevent infinite loops.
- `hooks/task-completed.sh` — TaskCompleted hook runs test suite before allowing task completion. Exit 2 blocks with stderr feedback.
- `CLAUDE_ENV_FILE` persistence in `monitor/hooks/session-lifecycle.sh` — persists `TASKPLEX_MONITOR_PORT` and `TASKPLEX_RUN_ID` for all subsequent Bash commands.
- `$ARGUMENTS` fast-start in `commands/start.md` — `/taskplex:start Fix the login bug` skips interview, injects description directly.
- Dynamic context injection in `commands/start.md` — auto-detects existing `prd.json` and config, offers resume vs start fresh.
- Competitive analysis PRD (`docs/plans/2026-02-20-sota-upgrade-design.md`) covering 15+ plugins (Superpowers 55k stars, claude-mem 29k, wshobson/agents 29k, etc.)

**Changed:**
- All 5 agents now have explicit `permissionMode`:
  - `implementer`: `bypassPermissions` (headless write access)
  - `validator`: `dontAsk` (auto-deny prompts, read-only + test commands)
  - `reviewer`: `plan` (read-only exploration enforced at framework level)
  - `merger`: `bypassPermissions` (headless git operations)
  - `code-reviewer`: `dontAsk` (auto-deny, read + git diff)
- `merger` agent now has `disallowedTools: [Write, Edit, Task]` (principle of least privilege)
- `code-reviewer` agent now has `memory: project` (accumulates codebase patterns)
- `prd-generator` skill: added `agent: Explore`, `model: sonnet`, `disable-model-invocation: true`, `allowed-tools`
- `prd-converter` skill: added `agent: Explore`, `model: sonnet`, `disable-model-invocation: true`, `allowed-tools`
- `failure-analyzer` skill: added `user-invocable: false`, `disable-model-invocation: true`
- `start.md` command: added `disable-model-invocation: true`, `argument-hint: "[feature-description]"`
- `hooks.json`: added `statusMessage` on all sync hooks, added `timeout` on all sync hooks, added Stop and TaskCompleted hook entries
- `plugin.json`: added explicit `"hooks": "./hooks/hooks.json"`, added `author.email`, bumped to 2.0.8

**Leverages:**
- `Stop` hook with `decision: "block"` and `stop_hook_active` loop prevention (CLI 2.1.0+)
- `TaskCompleted` hook with exit 2 blocking and stderr feedback (CLI 2.1.47+)
- `statusMessage` common field on all hook types (CLI 2.1.0+)
- `timeout` common field for hook execution limits (CLI 2.1.0+)
- `permissionMode` agent frontmatter: 5 modes (default, acceptEdits, dontAsk, bypassPermissions, plan)
- `agent` field on `context: fork` skills for subagent type routing (CLI 2.1.0+)
- `disable-model-invocation: true` on skills and commands (CLI 2.1.0+)
- `$ARGUMENTS` substitution in skill/command content (CLI 2.1.0+)
- Dynamic context injection via `` !`command` `` preprocessing (CLI 2.1.0+)
- `CLAUDE_ENV_FILE` env var persistence from SessionStart hooks (CLI 2.1.47+)

### v2.0.7 (2026-02-19)

**v2.1 Batch 3 — Observability, Adaptive Control, Code Review:**

**Added:**
- `agents/code-reviewer.md` — New two-stage code review agent (model: sonnet). Stage 1: spec compliance ("nothing more, nothing less"). Stage 2: code quality (correctness, security, architecture). Adversarial framing. Issue taxonomy: Critical/Important/Minor with `file:line` references. Binary verdict: approve/request_changes/reject. Opt-in via `code_review: true` in config.
- `scripts/knowledge-db.sh` — `mine_implicit_learnings()`: transcript mining function that extracts observations, file relationships, and environment notes from agent prose responses. Three regex-based extraction patterns with deduplication. Confidence: 0.6-0.8 depending on pattern type.
- `scripts/decision-call.sh` — `rewrite_story()`: adaptive PRD rewriting function. When a story fails 2+ times and decision call returns "rewrite", spawns a Haiku call to split/simplify the story. Uses additive pattern: marks original story as "rewritten" and inserts new sub-stories with `depends_on` linkage.
- `scripts/taskplex.sh` — `post_merge_test()`: runs test suite after `merge_to_main()` succeeds. On failure, reverts the merge commit and returns to feature branch. Applied to all three merge paths (sequential complete, COMPLETE signal, parallel complete).
- `scripts/taskplex.sh` — `run_code_review()`: invokes code-reviewer agent after validation passes but before commit. Config-driven (`code_review: true`). Rejection triggers standard error handling; requested changes logged as warning but non-blocking.
- `scripts/taskplex.sh` — `check_intervention()`: polls monitor dashboard for user interventions (skip/pause/hint/resume) between iterations. Supports foreground (interactive pause) and background (poll for resume) modes.
- `monitor/server/index.ts` — `POST /api/intervention`, `GET /api/interventions`, `POST /api/intervention/consume` endpoints with SQLite `interventions` table. Orchestrator polls `consume` endpoint for pending interventions.

**Changed:**
- `hooks/validate-result.sh` — Added transcript mining (calls `mine_implicit_learnings` after structured learnings extraction). Added scope drift detection (compares `git diff --stat` against expected files, logs warnings to SQLite). Both are informational — never block the agent.
- `.claude-plugin/plugin.json` — Added `./agents/code-reviewer.md` to agents list (5 agents, was 4).
- Config schema: new `code_review` (bool, default false) field.
- Main loop: `check_intervention()` called at start of each iteration; `rewrite_story` handling after decision call.

### v2.0.6 (2026-02-19)

**v2.1 Batch 2 — Per-Edit Intelligence + Crash Recovery:**

**Added:**
- `hooks/inject-edit-context.sh` — PreToolUse hook on `Edit`/`Write` (agent-scoped in implementer). Queries SQLite `file_patterns` table and relevant learnings, injects file-specific guidance via `additionalContext` before each edit.
- `hooks/pre-compact.sh` — PreCompact hook (matcher: `auto`). Saves current story state, git diff snapshot, and progress to SQLite + recovery JSON before context compaction. Preserves knowledge for long-running implementer agents.
- Checkpoint resume in `scripts/taskplex.sh` — `recover_stuck_stories()` resets stuck `in_progress` stories to `pending` on startup (crash recovery). `write_checkpoint()` writes `.claude/taskplex-checkpoint.json` after each story state transition.
- `scripts/knowledge-db.sh` — New helpers: `query_file_patterns()`, `insert_file_pattern()`, `save_compaction_snapshot()`.
- `agents/implementer.md` — Added `skills: [failure-analyzer]` for self-diagnosis; added agent-scoped PreToolUse hook on `Edit|Write` for per-edit context injection.

**Changed:**
- `hooks/hooks.json` — Added `PreCompact` hook entry (9 hooks total, was 8).
- State files: added `.claude/taskplex-checkpoint.json` (crash recovery) and `.claude/taskplex-pre-compact.json` (compaction snapshot).

### v2.0.5 (2026-02-19)

**v2.1 Batch 1 — Quick Wins:**

**Added:**
- `maxTurns` on all agents: implementer (150), validator (50), reviewer (30), merger (50). Prevents runaway agent loops.
- `disallowedTools` on validator (`Write`, `Edit`, `Task`) and reviewer (`Write`, `Edit`, `Bash`, `Task`). Enforces read-only contracts.
- `PostToolUseFailure` monitor hook (`monitor/hooks/post-tool-use-failure.sh`). Captures tool failures for error pattern analysis in dashboard.

**Fixed:**
- `commands/start.md` — `allowed-tools` frontmatter changed from JSON array to comma-separated string (correct skill schema format).

### v2.0.4 (2026-02-19)

**Bug Fix Round — Code-Simplifier + Docs Compliance Review:**

**Fixed (HIGH):**
- `scripts/check-git.sh` — `set -e` + `[ ] && action` pattern silently crashed on clean repos (lines 55, 93). Changed to `if/then/fi`.
- `scripts/taskplex.sh` — `RUN_ID` exported before defined; hooks received empty `TASKPLEX_RUN_ID`. Moved export after generation.
- `scripts/check-deps.sh` — Added `sqlite3` dependency check (required since v2.0 knowledge store).

**Fixed (MEDIUM):**
- `hooks/validate-result.sh` — Fragile greedy-regex learnings extraction replaced with jq-first parsing + non-greedy fallback.
- `scripts/knowledge-db.sh` — Process substitution `< <()` normalized to here-string `<<<` for project consistency.

**Fixed (LOW):**
- `monitor/hooks/send-event.sh` — Removed `set -e` that contradicted "always exit 0" design.
- `scripts/check-destructive.sh` — Added `--force-with-lease` allowlist (safer than `--force`).
- `hooks/hooks.json` — Narrowed `inject-knowledge.sh` SubagentStart matcher from `implementer|validator` to `implementer` only.

### v2.0.3 (2026-02-19)

**CLI 2.1.47 Feature Adoption + Git Bootstrap:**

**Added:**
- `scripts/check-git.sh` — Git repository diagnostic script outputting JSON state.
- Checkpoint 2 in wizard: "Validate Git Repository" — bootstraps fresh repos, stashes dirty state, fixes detached HEAD.

**Changed:**
- `hooks/validate-result.sh` — Uses `last_assistant_message` from SubagentStop hook input instead of grepping transcript.
- `agents/implementer.md` — Destructive command hook moved to agent-scoped `PreToolUse` in frontmatter.
- `skills/prd-generator/SKILL.md`, `skills/prd-converter/SKILL.md` — Added `context: fork`.
- `commands/start.md` — 8 checkpoints (was 7), git validation added as Checkpoint 2.

### v2.0.0 (2026-02-17)

**Smart Scaffold Architecture — Hook-Based Intelligence:**

**Added:**
- SQLite knowledge store (`knowledge.db`): learnings, file_patterns, error_history, decisions, runs tables
- Confidence decay at 5%/day (~30 day half-life)
- 1-shot Opus decision calls for per-story model/effort routing
- SubagentStart hook: knowledge injection from SQLite
- SubagentStop hook: inline validation with self-healing
- Auto-migration from `knowledge.md` to SQLite

**New Config Fields:**
- `decision_calls`, `decision_model`, `knowledge_db`, `validate_on_stop`, `model_routing`

### v1.2.1 (2026-02-15)

**Execution Monitor Sidecar:**
- Bun HTTP + WebSocket server with SQLite storage
- Vue 3 + Tailwind CSS dashboard (Timeline, StoryGantt, ErrorPatterns, AgentInsights)
- Fire-and-forget hook scripts for event emission
- `emit_event()` in taskplex.sh at 15+ state transitions

### v1.2.0 (2026-02-15)

**Wave-Based Parallel Execution:**
- `scripts/parallel.sh` — topological wave computation, conflict splitting, worktree lifecycle
- New config: `parallel_mode`, `max_parallel`, `worktree_dir`, `worktree_setup_command`, `conflict_strategy`

### v1.1.0 (2026-02-14)

**Three-Layer Knowledge Architecture:**
- Operational log (Layer 1), project knowledge base (Layer 2), per-story context briefs (Layer 3)
- Structured agent output schema with `learnings`, `acceptance_criteria_results`, `retry_hint`
- `memory: project` on implementer and validator agents

### v1.0.0 (2026-02-11)

**Initial release — successor to SDK Bridge v4.8.1:**
- Custom subagents: implementer, validator, reviewer, merger
- Failure analyzer skill with 6 error categories
- PostToolUse hook to block destructive git commands
- Interactive wizard with 7 checkpoints
- PRD generator/converter skills with dependency inference
