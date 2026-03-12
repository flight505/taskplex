# Changelog

All notable changes to TaskPlex are documented here.

---

### v7.0.4 (2026-03-12)

**Fix: brainstorm skill circular invocation:**

- Removed `commands/brainstorm.md` — it shared the name `taskplex:brainstorm` with `skills/brainstorm/`, causing a circular invocation loop (4x "Successfully loaded skill" with no content execution)
- Moved `argument-hint: "[feature-description]"` from the removed command into the brainstorm skill frontmatter
- Added gotcha to CLAUDE.md: never create a command with the same name as a skill in a plugin
- Commands reduced from 3 → 2 (write-plan and e2e-test remain — they have different names from their target skills)

---

### v7.0.3 (2026-03-10)

**Fix: CLI handoff response handling:**

- Fixed: user choosing "option 1" (/batch) from plan handoff triggered TDD instead of outputting the command
- Added "When the User Chooses" response handling to `writing-plans` — /batch → output command and stop, inline → start TDD
- Added handoff acceptance rule to `using-taskplex` decision flow as step 1 (highest priority)
- Added red flag: "User said option 1, let me start TDD" → they chose /batch, output command and STOP

---

### v7.0.2 (2026-03-10)

**Skills 2.0 compliance, CLI execution command handoff, and v2.1.72 integration:**

**Fixed:**
- Critical bug: `using-taskplex` blanket "use Skill tool" instruction caused Claude to invoke `/batch` and `/simplify` via Skill tool, failing with `disable-model-invocation` error
- Split skill routing into two paths: TaskPlex skills (Skill tool) vs CLI bundled skills (contextual handoff to user)
- `@testing-anti-patterns.md` → `${CLAUDE_SKILL_DIR}/testing-anti-patterns.md` in `test-driven-development`
- `@testing-skills-with-subagents.md` → `${CLAUDE_SKILL_DIR}/testing-skills-with-subagents.md` in `writing-skills`

**Added:**
- CLI Execution Commands section in `using-taskplex` — documents `/batch`, `/simplify`, `/debug`, `/loop`, `/plan` with contextual handoff pattern
- Contextual handoff examples (good/bad) showing task-specific CLI command guidance
- Decision flow step 7: handoff to `/simplify` after implementation
- `ExitWorktree` tool reference in `using-git-worktrees` and `finishing-a-development-branch` (v2.1.72)
- `/plan [description]` command documented in CLI Execution Commands (v2.1.72)
- `argument-hint` frontmatter on all 3 commands: brainstorm, write-plan, e2e-test

**Changed:**
- All 11 skill descriptions rewritten to hybrid pattern (third-person what + "Use when..." triggers)
- `writing-skills/SKILL.md` reduced from 655→514 lines — CSO guide extracted to `cso-guide.md` reference file
- `writing-skills` description guidance updated from "triggers-only" to hybrid pattern per current Anthropic best practices
- Ultrathink tip updated for simplified effort levels (low ○, medium ◐, high ●)
- `CLAUDE.md` frontmatter docs expanded to list all valid fields (argument-hint, allowed-tools, model, context, agent, hooks)
- `/reload-plugins` replaces "Plugins update on restart only" in gotchas

---

### v7.0.1 (2026-03-08)

**Skill description optimization and code-review integration:**

- Optimized all 11 skill descriptions — triggers-only pattern with edge-case coverage
- Added automated review handling section to `receiving-code-review`
- Added code-review plugin cross-references to `finishing-a-development-branch`
- Use `${CLAUDE_SKILL_DIR}` for relative path references in `systematic-debugging` and `writing-skills`
- Added explanatory comment to SessionStart hook matcher
- Gitignore `docs/` and `evals/` (dev-only)

---

### v7.0.0 (2026-03-05)

**Trim Execution Skills, Amplify CLI:**

Removed execution/orchestration skills that duplicate CLI built-ins (`/batch`, `/simplify`). TaskPlex is now purely a thinking discipline layer — brainstorm, plan, TDD, verify, debug. Execution handled by CLI.

**Removed:**
- `skills/guided-implementation/` — replaced by `/batch` (CLI built-in)
- `skills/subagent-driven-development/` (+ 4 prompt templates) — replaced by `/batch`
- `skills/dispatching-parallel-agents/` — replaced by `/batch`
- `skills/requesting-code-review/` (+ code-reviewer.md template) — replaced by `/simplify`
- `agents/code-reviewer.md` — no dispatcher after skill removal
- `commands/execute-plan.md` — only wrapped `guided-implementation`

**Changed:**
- `skills/using-taskplex/SKILL.md` — Removed 4 skills from catalog, rewrote decision flow to route to `/batch` for execution, replaced "complementary" framing with "think then execute" framing
- `skills/writing-plans/SKILL.md` — Execution handoff now offers `/batch` or inline TDD instead of removed skills
- `skills/finishing-a-development-branch/SKILL.md` — Removed "Called by" refs to deleted skills
- `skills/using-git-worktrees/SKILL.md` — Removed "Called by" refs to deleted skills
- `.claude-plugin/plugin.json` — v7.0.0, 0 agents, 11 skills, 3 commands
- `CLAUDE.md` — Updated architecture tree, component counts
- `README.md` — Updated for v7.0.0

**Net change:** 15 → 11 skills, 4 → 3 commands, 1 → 0 agents

**Migration notes:**
- `/execute-plan` command no longer exists — use `/batch` instead
- Code review dispatch is gone — use `/simplify` for code review
- Users must restart Claude Code after updating the plugin

---

### v6.1.0 (2026-03-04)

Added `/e2e-test` command and `e2e-testing` skill — systematic end-to-end testing that works for web apps, APIs, CLIs, and desktop applications. Launches 3 parallel research sub-agents to map all user journeys, state flows, and risk areas.

---

### v6.0.0 (2026-03-04)

**Lightweight Always-On Companion:**

Stripped heavy orchestration — PRD pipeline, config system, shell scripts, 5 registered agents — in favor of pure discipline skills. Heavy project execution moved to [SDK-Bridge](https://github.com/flight505/sdk-bridge). Result: 14 skills, 3 commands, 1 hook, 1 agent, 0 config.

**Added:**
- `commands/brainstorm.md` — Shortcut to `taskplex:brainstorm` skill
- `commands/write-plan.md` — Shortcut to `taskplex:writing-plans` skill
- `commands/execute-plan.md` — Shortcut to `taskplex:guided-implementation` skill
- `agents/code-reviewer.md` — Code quality review agent (dispatched by requesting-code-review)
- `hooks/run-hook.cmd` — Cross-platform hook runner (polyglot bash/batch)
- `hooks/session-start` — Extensionless SessionStart hook
- CLI 2.1.63+ awareness: worktree-shared auto memory documented in skills
- CLI 2.1.68 awareness: ultrathink tip for Opus 4.6 deep reasoning
- Positioning vs built-in `/batch` and `/simplify` CLI commands

**Changed:**
- Skills rewritten for discipline focus:
  - `skills/brainstorm/` — rebuilt (was inline in commands)
  - `skills/test-driven-development/` — rebuilt (was `taskplex-tdd/`)
  - `skills/verification-before-completion/` — rebuilt (was `taskplex-verify/`)
  - `skills/guided-implementation/` — rebuilt (was `executing-plans/`)
  - `skills/subagent-driven-development/` — rebuilt with inline prompt templates
- `skills/using-taskplex/SKILL.md` — Removed PRD routing, added SDK-Bridge pointer for 6+ file tasks
- `hooks/hooks.json` — Simplified to single SessionStart hook (was 5 hooks across 5 events)
- `.claude-plugin/plugin.json` — v6.0.0, 1 agent, 14 skills, 3 commands
- `CLAUDE.md` — Rewritten for lightweight architecture
- `README.md` — Rewritten for lightweight architecture

**Removed:**
- `agents/` — architect.md, implementer.md, reviewer.md, merger.md (moved to SDK-Bridge)
- `commands/start.md` — 8-checkpoint interactive wizard
- `scripts/` — check-deps.sh, check-git.sh, check-destructive.sh (moved to SDK-Bridge)
- `hooks/session-context.sh`, `validate-result.sh`, `task-completed.sh`, `teammate-idle.sh`, `check-destructive.sh`
- `skills/prd-generator/`, `skills/prd-converter/` (moved to SDK-Bridge)
- `skills/taskplex-tdd/`, `skills/taskplex-verify/` (rebuilt as standard names)
- `skills/focused-task/`, `skills/failure-analyzer/` (removed — orchestration overhead)
- `TASKPLEX-ARCHITECTURE.md` — Consolidated into CLAUDE.md
- Configuration system — `.claude/taskplex.config.json` (8 options → 0)

**Migration notes:**
- No configuration file needed — remove `.claude/taskplex.config.json` if present
- `/taskplex:start` wizard no longer exists — use `/brainstorm`, `/write-plan`, `/execute-plan`, or just start working
- For PRD-driven projects with 6+ files, use SDK-Bridge instead
- Users must restart Claude Code after updating the plugin

---

### v5.2.0 (2026-03-03)

**Workflow Refactoring — Scale-Aware Routing, Resume Intelligence, Clear Boundaries:**

**Added:**
- `skills/focused-task/SKILL.md` — Lightweight inline implementation path for well-scoped tasks (1-5 files). No PRD, no prd.json, no agent dispatch. TDD discipline without ceremony.
- Resume logic in `subagent-driven-development` — Detects completed stories on interrupted runs, skips them, carries forward learnings to subsequent stories.
- "Standalone vs. Built-In" section in `requesting-code-review` — Clarifies when code review is automatic (subagent-driven-development) vs. manual invocation (focused-task, guided-implementation, ad-hoc).
- Scale-aware routing in `using-taskplex` decision flow — 1-5 files routes to focused-task, 6+ files routes to PRD.

**Changed:**
- `skills/executing-plans/` → `skills/guided-implementation/` — Renamed to clarify that this is human-guided inline execution, distinct from autonomous agent dispatch. Added "How This Differs" comparison table.
- `skills/subagent-driven-development/SKILL.md` — Integration section now lists prd.json and plan documents as alternative input paths (was: writing-plans REQUIRED). Added resume red flags.
- `skills/using-taskplex/SKILL.md` — Skill catalog updated (added focused-task, renamed guided-implementation). Decision flow now has scale-aware feature routing. Red flags table updated with nuanced PRD threshold.
- `skills/requesting-code-review/SKILL.md` — Mandatory list rewritten for standalone contexts. Integration section clarifies automatic vs. manual invocation per workflow.
- `skills/writing-plans/SKILL.md` — Updated 3 references from executing-plans to guided-implementation.
- `skills/finishing-a-development-branch/SKILL.md` — Updated reference from executing-plans to guided-implementation.
- `.claude-plugin/plugin.json` — Skills array: executing-plans → guided-implementation, added focused-task (17→18 skills).
- `CLAUDE.md` — Architecture tree updated, skill count 17→18.
- `TASKPLEX-ARCHITECTURE.md` — Layer 1 skills table updated, data flow updated, skill count 17→18.

**Removed:**
- `skills/executing-plans/` — Replaced by `skills/guided-implementation/` (content preserved, name and description changed).

---

### v5.0.0 (2026-02-28)

**Remove Orchestration, Leverage Native Claude Code:**

This is a major simplification release. ~7,350 lines of custom orchestration removed in favor of native Claude Code features.

**Removed:**
- `scripts/taskplex.sh` (2,361 lines) — bash orchestration loop, replaced by `subagent-driven-development` skill
- `scripts/parallel.sh` (787 lines) — wave-based parallelism, replaced by native `isolation: worktree`
- `scripts/knowledge-db.sh` (526 lines) — SQLite knowledge store, replaced by native `memory: project`
- `scripts/decision-call.sh` (332 lines) — model routing, replaced by `model:` in agent frontmatter
- `scripts/teams.sh` (123 lines) — Agent Teams wrapper, native Agent Teams used directly
- `scripts/prompt.md` — orchestrator prompt template
- `monitor/` (~2,000 lines) — Bun+Vue3 dashboard sidecar (extracted)
- `agents/validator.md` — merged into `reviewer.md`
- `agents/spec-reviewer.md` — merged into `reviewer.md`
- `hooks/stop-guard.sh` — Stop hook (35 lines)
- `hooks/task-completed.sh` — TaskCompleted hook (33 lines)
- `hooks/inject-knowledge.sh` — SubagentStart knowledge injection (260 lines)
- `hooks/inject-edit-context.sh` — PreToolUse file pattern injection (91 lines)
- `hooks/pre-compact.sh` — PreCompact state preservation (78 lines)
- `test-results/taskplex/run-evals.sh` — evaluation suite (55 orchestration-focused tests)
- Config options: `max_iterations`, `iteration_timeout`, `execution_mode`, `effort_level`, `max_retries_per_story`, `max_turns`, `parallel_mode`, `max_parallel`, `worktree_dir`, `worktree_setup_command`, `conflict_strategy`, `decision_calls`, `decision_model`, `validate_on_stop`, `model_routing`, `spec_hardening`, `spec_harden_model`, `scope_drift_action`

**Added:**
- `agents/reviewer.md` — merged two-phase review (spec compliance + validation), replaces validator + spec-reviewer
- `skills/subagent-driven-development/reviewer-prompt.md` — prompt template for reviewer subagent

**Changed:**
- Agents: 6 → 5 (validator + spec-reviewer merged into reviewer)
- Hooks: 13 → 4 (SessionStart, PreToolUse, SubagentStop, TeammateIdle)
- Config: 24 → 8 options (branch_prefix, test/build/typecheck commands, execution_model, merge_on_complete, code_review, interactive_mode)
- `agents/architect.md` — added `skills: [brainstorm]` to frontmatter
- `agents/implementer.md` — removed inject-edit-context hook, SQLite/orchestrator references, Stop/Worktree sections
- `agents/code-reviewer.md` — removed Stage 1 (spec compliance), now does code quality only
- `hooks/hooks.json` — 4 hooks across 4 events (was 13 across 10)
- `hooks/validate-result.sh` — simplified to ~90 lines (was 236), removed SQLite learnings extraction, scope drift, implicit mining
- `scripts/check-deps.sh` — removed sqlite3 and coreutils dependency checks
- `commands/start.md` — simplified wizard, checkpoint 7 reduced to 3 questions, checkpoint 8 launches subagent-driven-development instead of taskplex.sh
- `skills/taskplex-tdd` — "validator and spec-reviewer" → "reviewer agent"
- `skills/taskplex-verify` — triple-layer → two-layer enforcement (removed Stop/TaskCompleted hooks)
- `skills/subagent-driven-development` — spec-reviewer-prompt.md → reviewer-prompt.md, TodoWrite → TaskCreate
- `skills/prd-converter` — removed progress.txt reference
- `CLAUDE.md` — major rewrite for v5.0 architecture
- `README.md` — major rewrite, simplified feature list
- `TASKPLEX-ARCHITECTURE.md` — rewritten: 3 layers (Skills, Agents, Hooks) instead of 8
- `TASKPLEX-AUDIT.md` → moved to `docs/archive/`
- `TASKPLEX-SOTA-RESEARCH-AND-PLAN.md` → moved to `docs/archive/`
- `.gitignore` — removed monitor-specific entries, test database entries

**Migration notes:**
- Existing `prd.json` files remain fully compatible
- Existing `knowledge.db` is abandoned — native `memory: project` replaces it
- Existing `taskplex.config.json` will have unrecognized fields (harmless, ignored)
- Users must restart Claude Code after updating the plugin

---

### v4.1.1 (2026-02-27)

**Test Suite Overhaul — Structural Optimization + Evaluation Suite:**

**Added:**
- `test-results/taskplex/run-evals.sh` — new offline evaluation suite (5 sections, 53 tests, pure bash/SQLite, no LLM calls): decision routing accuracy, knowledge mining quality, Bayesian ranking, pattern promotion, hook behavior
- `run_hook()` helper in `run-tests.sh` — reduces hook test boilerplate to single-line calls
- Per-section metrics in `--save` output: each section tracks pass/fail/warn independently
- Three-tier OVERALL status: `PASS`, `PASS_WITH_ISSUES` (1-3 failures), `FAIL` (4+)
- `suite` field in JSONL history (`"structural"` or `"evaluation"`) for tracking both test types
- `notes` array in JSONL output — captures all warnings and failures

**Changed:**
- Structural suite (`run-tests.sh`): 276 tests (was 322) — removed ~41 redundant tests (S8.1, S8.2, S8.4, S7 SKILL.md exists) that duplicated S1/S3 checks
- Fixed false positive in S8.5/S8.6 cross-refs: `grep -q "$name"` → exact path match `grep -q "/$name$"` (prevented `reviewer.md` false-matching `code-reviewer.md`)
- `header()` now takes section key parameter for JSON metrics
- JSONL records now compact (single-line) with `jq -cn`

**Fixed:**
- `mine_implicit_learnings()` Pattern 3 (environment) regex broken on macOS — `(to be |)` empty alternative invalid in macOS ERE → changed to `(to be )?` which is portable across GNU and BSD ERE

---

### v4.1.0 (2026-02-27)

**SSC Spec Hardening + Bayesian Confidence:**

**Added:**
- `harden_spec()` in `taskplex.sh` — SSC-inspired pre-implementation spec hardening that tightens vague acceptance criteria before the first implementation attempt (arxiv: 2507.18742)
- Bayesian confidence tracking: `applied_count` and `success_count` columns in learnings table. Learnings with 2+ applications use Beta posterior `(success+1)/(applied+2)` instead of linear time-decay
- `record_learning_application()` — tracks when learnings are injected into agents
- `record_learning_success()` — records story-level success for Bayesian update
- `query_learnings_with_ids()` — returns learning IDs for application tracking
- Config options: `spec_hardening` (bool, default: true), `spec_harden_model` (string, default: "haiku")

**Changed:**
- `query_learnings()` now uses Bayesian confidence when applied_count >= 2, graceful fallback to time-decay otherwise
- `inject-knowledge.sh` switched from `query_learnings()` to `query_learnings_with_ids()` for application tracking
- Story completion now calls `record_learning_success()` alongside `update_decision_outcome()`

---

### v4.0.0 (2026-02-26)

**SOTA Transformation — Brainstorming, Lean Skills, Routing, Safety:**

**Added:**
- `agents/architect.md` — Read-only codebase explorer for brainstorm phase (model: sonnet, permissionMode: dontAsk)
- `agents/spec-reviewer.md` — Spec compliance review Stage 1 (model: haiku, permissionMode: dontAsk)
- `skills/brainstorm/SKILL.md` — Challenge assumptions before jumping to PRD
- 14 discipline skills: `taskplex-tdd`, `taskplex-verify`, `systematic-debugging`, `dispatching-parallel-agents`, `using-git-worktrees`, `finishing-a-development-branch`, `requesting-code-review`, `receiving-code-review`, `subagent-driven-development`, `writing-skills`, `executing-plans`, `writing-plans`
- `scripts/teams.sh` — Agent Teams orchestrator (opt-in via `parallel_mode: "teams"`)
- `hooks/session-context.sh` — SessionStart hook for proactive context injection
- `hooks/teammate-idle.sh` — TeammateIdle hook for Agent Teams story assignment
- Rule-based fast path in `decision-call.sh` — eliminates ~40% of Opus decision calls
- Test file integrity checksums (reward hacking prevention)
- Configurable scope drift detection (`scope_drift_action`: warn/block/review)
- `patterns` table in SQLite knowledge store (promoted from 3+ story occurrences)
- Execution modes: interactive (new), teams (new)
- Effort auto-tuning on retries (escalates model/effort for failed stories)
- Rationalization prevention tables in discipline skills

**Changed:**
- Skills trimmed 71%: using-taskplex 67 lines, writing-skills 128, prd-converter 165, prd-generator 118
- Confidence decay extended from 30-day to 60-day cutoff
- Enhanced implicit mining (5 pattern types, was 3)
- `--agent implementer` now correctly passed to headless `claude -p` calls
- `hooks.json`: 12 hooks across 10 events (added SessionStart, TeammateIdle)
- Total: 7 agents, 17 skills, 1 command

### v3.1.0 (2026-02-25)

**Benchmark Infrastructure:**

**Added:**
- `tests/run-suite.sh` — Pure bash test suite (no API calls)
- `tests/behavioral/test-hooks.sh` — Hook contract tests (5 hooks, ~20 assertions)
- Script unit tests for knowledge-db, decision-call, validate-result, inject-knowledge, integration
- `.github/workflows/benchmark.yml` — CI workflow

### v3.0.0 (2026-02-24)

**Proactive Architecture — Always-On Awareness:**

**Added:**
- `hooks/session-context.sh` — SessionStart hook detects active `prd.json` and injects context at session start
- `skills/using-taskplex/SKILL.md` — Always-on gate skill (1% trigger threshold)
- Proactive path: skills auto-trigger without requiring `/taskplex:start`

**Changed:**
- Architecture shifted from command-driven to proactive: SessionStart hook + skill gate replace manual wizard invocation
- `hooks.json`: added SessionStart event (10 hooks across 8 events)
- Upgraded from 5 to 6 agents (added spec-reviewer)

### v2.0.8 (2026-02-20)

**SOTA Audit — Complete CLI Feature Coverage + Competitive Intelligence:**

**Added:**
- `hooks/stop-guard.sh` — Stop hook prevents premature exit when stories are in_progress or pending. Checks `stop_hook_active` to prevent infinite loops.
- `hooks/task-completed.sh` — TaskCompleted hook runs test suite before allowing task completion. Exit 2 blocks with stderr feedback.
- `CLAUDE_ENV_FILE` persistence in `monitor/hooks/session-lifecycle.sh` — persists `TASKPLEX_MONITOR_PORT` and `TASKPLEX_RUN_ID` for all subsequent Bash commands.
- `$ARGUMENTS` fast-start in `commands/start.md` — `/taskplex:start Fix the login bug` skips interview, injects description directly.
- Dynamic context injection in `commands/start.md` — auto-detects existing `prd.json` and config, offers resume vs start fresh.
- Competitive analysis PRD (`docs/plans/2026-02-20-sota-upgrade-design.md`) covering 15+ plugins

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
