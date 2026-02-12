# TaskPlex — Next-Generation Autonomous Development Plugin

**Architecture Plan v1.0** | February 10, 2026
**Author:** Claude Opus 4.6 + Jesper Vang
**Status:** Draft — Awaiting Review

---

## 1. Executive Summary

TaskPlex is the successor to SDK Bridge, designed to address the key pain points of the current system (task failures halting progression, orphaned branches, no merge management) while leveraging Claude Code's newest features (Agent Teams, Agent Memory, Custom Subagents, Hooks, and Sandbox).

The core philosophy remains: **precise PRD → sequential execution → fresh context per task**. What changes is the resilience layer, the knowledge persistence mechanism, and the quality gate enforcement.

**Name candidates:** TaskPlex (recommended), Conductor, Forge, Multiplex. "TaskPlex" is short, implies efficient task multiplexing, and is distinctive enough to be memorable.

---

## 2. SDK Bridge Code Review — Current State

### What Works Well

The current SDK Bridge (v4.8.1) has a solid foundation:

- **Single-command simplicity** — `/sdk-bridge:start` with a 7-checkpoint wizard is clean and user-friendly
- **AskUserQuestion loop** — the PRD refinement cycle (generate → review → suggest improvements → re-review) produces high-quality specs
- **Fresh context per iteration** — `--no-session-persistence` prevents context rot across tasks
- **PRD schema design** — the `prd.json` format with `depends_on`, `related_to`, `implementation_hint`, and `check_before_implementing` fields is well thought out
- **Process management** — trap-based cleanup, per-branch PID files, stale file detection
- **Timeout recovery** — foreground interactive prompts (skip/retry/abort) and background auto-skip
- **Already-implemented detection** — `prompt.md` instructs agents to verify before coding
- **Story size enforcement** — the 5-criteria threshold with decomposition patterns
- **Archiving** — automatic archiving of previous runs when branch changes

### Critical Issues

These are the problems that TaskPlex must solve:

**1. Task Failures Halt Everything**
When a task fails (missing API key, missing dependency, test environment issue), the loop either times out or errors out. The next iteration picks up the same broken story and fails again. There is no mechanism to:
- Categorize why a task failed (missing env vs. code bug vs. timeout)
- Skip a task and move to the next non-dependent one
- Retry with a different strategy
- Report which tasks were skippable vs. blocking

**2. Orphaned Branches**
The script creates a branch (`sdk-bridge/feature-name`) but never merges it. If 5 of 7 stories complete and 2 fail, the user is left with a partially-implemented branch that requires manual intervention to merge, cherry-pick, or clean up.

**3. Dependencies Are Tracked but Not Enforced**
`prd.json` has `depends_on` fields, but `sdk-bridge.sh` simply picks the first story with `passes: false` (line 342). It doesn't check whether that story's dependencies have been satisfied. This can cause a UI story to run before its backend dependency is complete.

**4. progress.txt Grows Unbounded**
Every iteration appends full output. After 20+ iterations, this file becomes enormous. The "Codebase Patterns" section at the top is a good idea but relies on each agent maintaining it — which is inconsistent.

**5. Config Parsing Is Fragile**
Lines 136-174 use `grep -A 10 "^---$"` to extract YAML frontmatter values. This breaks if the config has more than 10 lines of frontmatter, if values contain special characters, or if there are multiple `---` delimiters.

**6. No Branch Management in the Loop**
The script doesn't:
- Create the branch (assumes it exists)
- Merge completed work back to main
- Clean up failed branches
- Handle merge conflicts

**7. Error Output Not Parsed**
Line 424: `RESULT=$(echo "$OUTPUT" | jq -r '.result // empty')` — if Claude returns an error, the result extraction is unreliable. The script doesn't distinguish between "Claude errored" and "Claude completed but the task failed."

**8. No Post-Run Validation**
When all stories are marked `passes: true`, the script exits. There's no final verification that the branch is clean, tests pass, and the code actually works as a whole.

---

## 3. New Claude Code Features Analysis

### Features That Are Directly Useful for TaskPlex

**Agent Memory** (v2.1.33) — **HIGH VALUE**
Replaces `progress.txt` entirely. Each subagent can read/write to a persistent `MEMORY.md` with three scope options:
- `project` scope → `.claude/agent-memory/taskplex/` — project-specific patterns, shared via git
- `local` scope → `.claude/agent-memory-local/taskplex/` — local-only learnings, not committed

The memory auto-limits to 200 lines with instructions to curate, solving the unbounded growth problem. Cross-session knowledge transfer becomes native rather than ad-hoc.

**Custom Subagents** (v2.1.33+) — **HIGH VALUE**
Define specialized agents with YAML frontmatter:
- `implementer` agent: tools restricted to `Bash, Read, Edit, Write, Glob, Grep`, model = configurable
- `reviewer` agent: tools restricted to `Read, Glob, Grep, Bash`, permission mode = `plan` (read-only)
- `merger` agent: tools restricted to `Bash, Read, Glob`, focused on git operations

Each gets tool restrictions, model selection, and permission modes. This replaces the monolithic `claude -p` call with purpose-built agents.

**Hooks** (v2.1.33) — **MEDIUM-HIGH VALUE**
Two hooks are directly applicable:
- `TaskCompleted` — exit code 2 prevents completion. Use this to enforce: "tests must pass before marking a story done"
- `PreToolUse` — validate commands before execution. Use to block destructive operations during implementation.

These can be defined in the plugin's agent frontmatter or in a hooks configuration.

**Task Restriction Syntax** — **MEDIUM VALUE**
`Task(implementer, reviewer)` controls which subagents can be spawned. Prevents implementation agents from spawning their own subagents wastefully.

**Sandbox** — **MEDIUM VALUE**
Network isolation prevents tasks from accidentally hitting production APIs. Filesystem isolation prevents agents from modifying files outside the project. Useful for safe execution.

### Features That Are NOT Directly Useful

**Agent Teams** — **LOW VALUE for TaskPlex's use case**
Agent Teams are designed for parallel work with inter-agent communication. TaskPlex's sequential model is intentionally sequential to avoid merge conflicts. The overhead (higher token cost, coordination complexity, potential file conflicts) outweighs the benefit.

However, Agent Teams could be used in a limited way for the **PRD review phase** — spawn reviewers who analyze the PRD from different angles (security, performance, testability) in parallel before implementation begins. This is the one area where parallelism adds value without merge risk.

**tmux visualization** — **LOW VALUE**
Visual panes are cool for demos but add no value to a background automation process.

**Delegate mode** — **LOW VALUE**
Useful for Agent Teams but not for sequential execution.

---

## 4. TaskPlex Architecture

### Design Principles

1. **Precise PRD first** — keep the AskUserQuestion refinement loop, enhance it with multi-perspective review
2. **Sequential execution** — one task at a time, fresh context, no merge complications
3. **Resilient by default** — task failures don't halt the pipeline; categorize, retry, skip, report
4. **Native memory** — use Agent Memory instead of progress.txt
5. **Dependency enforcement** — never start a task whose dependencies haven't passed
6. **Branch lifecycle management** — create, implement, validate, merge, cleanup — all automated
7. **Quality gates via hooks** — tests must pass before a story is marked complete
8. **Structured error handling** — categorize failures, enable intelligent retry strategies

### Component Structure

```
taskplex/
├── .claude-plugin/
│   └── plugin.json                  # Plugin manifest
├── commands/
│   └── start.md                     # Single entry point (wizard)
├── agents/
│   ├── implementer.md               # Custom subagent: implements stories
│   ├── reviewer.md                  # Custom subagent: reviews PRDs
│   ├── validator.md                 # Custom subagent: post-task validation
│   └── merger.md                    # Custom subagent: git operations
├── skills/
│   ├── prd-generator/
│   │   └── SKILL.md                 # PRD creation (enhanced from SDK Bridge)
│   ├── prd-converter/
│   │   └── SKILL.md                 # PRD → JSON conversion (enhanced)
│   └── failure-analyzer/
│       └── SKILL.md                 # Analyzes failed tasks, suggests fixes
├── hooks/
│   └── hooks.json                   # Quality gate hooks
├── scripts/
│   ├── taskplex.sh                  # Main orchestration loop
│   ├── implementer-prompt.md        # Instructions for implementer agent
│   ├── validator-prompt.md          # Instructions for validator agent
│   ├── check-deps.sh               # Dependency checker
│   └── prd.json.example             # Reference format
├── examples/
│   ├── prd-simple.md
│   └── prd-complex.md
└── CLAUDE.md                        # Plugin documentation
```

### Key Differences from SDK Bridge

| Aspect | SDK Bridge | TaskPlex |
|--------|-----------|----------|
| Knowledge persistence | `progress.txt` (append-only, unbounded) | Agent Memory (auto-curated, scoped) |
| Dependency enforcement | Tracked but not enforced | Enforced in the loop — skips blocked tasks |
| Task failure handling | Timeout → skip or retry once | Categorize → retry with strategy → skip → report |
| Branch management | None (assumes branch exists) | Full lifecycle: create → implement → validate → merge |
| Agent specialization | Single monolithic `claude -p` | Custom subagents (implementer, reviewer, validator, merger) |
| Quality gates | None (trusts the agent) | Hooks enforce test-pass before completion |
| Config parsing | grep-based YAML extraction | `jq` + proper YAML parser (yq) or JSON config |
| Post-run validation | None | Final validation pass across all completed work |
| Error categorization | All errors treated equally | Categorized: env_missing, test_failure, timeout, code_error |
| PRD review | Single reviewer | Optional multi-perspective review (security, perf, testability) |

---

## 5. Detailed Component Design

### 5.1 The Orchestration Loop (`taskplex.sh`)

The main loop is the heart of the system. Here's the enhanced flow:

```
┌─────────────────────────────────────────────┐
│              INITIALIZATION                  │
│  1. Validate dependencies (claude, jq, git)  │
│  2. Load config (JSON format, not YAML)      │
│  3. Validate prd.json exists and is valid    │
│  4. Create/checkout implementation branch    │
│  5. Initialize agent memory                  │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│            TASK SELECTION                     │
│  1. Read prd.json                            │
│  2. Find all stories with passes: false      │
│  3. Filter out stories whose depends_on      │
│     contains any story with passes: false    │
│  4. Filter out stories in "skip" list        │
│  5. Pick highest-priority remaining story    │
│  6. If none available → check if blocked     │
│     or truly complete                        │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│          IMPLEMENTATION PHASE                │
│  1. Spawn implementer subagent with:        │
│     - Story details from prd.json           │
│     - Agent memory context                  │
│     - Restricted tool set                   │
│  2. Wait with timeout                       │
│  3. Capture structured output               │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│           VALIDATION PHASE                   │
│  1. Spawn validator subagent:               │
│     - Run verification commands from        │
│       acceptance criteria                   │
│     - Check that tests pass                 │
│     - Verify commit was created             │
│  2. If validation passes → mark complete    │
│  3. If validation fails → categorize error  │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│          ERROR HANDLING                       │
│  Based on category:                          │
│  - env_missing: skip + log (needs user)     │
│  - test_failure: retry once with feedback    │
│  - timeout: retry with extended timeout      │
│  - code_error: retry with error context      │
│  - max_retries_exceeded: skip + log          │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│         COMPLETION CHECK                     │
│  1. All stories passes: true? → MERGE PHASE │
│  2. All remaining stories blocked? → REPORT │
│  3. Max iterations reached? → REPORT        │
│  4. Otherwise → loop back to TASK SELECTION  │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│            MERGE PHASE                       │
│  1. Run full test suite on branch           │
│  2. If tests pass:                          │
│     - Merge to main (--no-ff for history)   │
│     - Delete implementation branch          │
│  3. If tests fail:                          │
│     - Report which tests fail               │
│     - Leave branch for manual review        │
│  4. Generate completion report              │
└─────────────────────────────────────────────┘
```

### 5.2 Dependency-Aware Task Selection

This is the single most impactful improvement. Current SDK Bridge picks the first `passes: false` story, which can attempt UI work before backend is ready.

```bash
# Pseudocode for task selection
get_next_task() {
  # Get all incomplete stories
  incomplete=$(jq '[.userStories[] | select(.passes == false)]' prd.json)

  for story in $incomplete; do
    # Check if all dependencies are satisfied
    deps=$(echo $story | jq -r '.depends_on[]')
    all_deps_met=true

    for dep in $deps; do
      dep_passes=$(jq -r ".userStories[] | select(.id == \"$dep\") | .passes" prd.json)
      if [ "$dep_passes" != "true" ]; then
        all_deps_met=false
        break
      fi
    done

    # Check if story is in skip list
    is_skipped=$(echo $story | jq -r '.status // empty')

    if $all_deps_met && [ "$is_skipped" != "skipped" ]; then
      echo $story  # This is the next task
      return 0
    fi
  done

  return 1  # No eligible tasks
}
```

### 5.3 Error Categorization and Retry Strategy

Instead of treating all failures the same, TaskPlex categorizes errors:

| Category | Detection | Strategy | Max Retries |
|----------|-----------|----------|-------------|
| `env_missing` | Output contains "API key", "token", "credentials", "ECONNREFUSED" | Skip immediately, log for user | 0 |
| `test_failure` | Tests ran but failed | Retry with test output as context | 2 |
| `timeout` | Exit code 124 | Retry with 1.5× timeout | 1 |
| `code_error` | Linter/typecheck/build failures | Retry with error output as context | 2 |
| `dependency_missing` | Import/package not found | Skip, log for user | 0 |
| `unknown` | Unclassifiable error | Retry once, then skip | 1 |

The retry mechanism passes the error context to the next attempt:

```bash
# On retry, prepend error context to the prompt
RETRY_CONTEXT="PREVIOUS ATTEMPT FAILED with: $ERROR_CATEGORY
Error output: $ERROR_OUTPUT
Fix this specific issue and try again."

claude -p "$RETRY_CONTEXT\n\n$(cat implementer-prompt.md)" ...
```

### 5.4 Custom Subagents

**`agents/implementer.md`** — The coding agent
```yaml
---
name: implementer
description: "Implements a single user story from prd.json. Reads the story, checks for existing implementation, codes the solution, runs quality checks, and commits."
tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
disallowedTools:
  - Task
model: inherit
memory: project
---
```

**`agents/validator.md`** — The verification agent
```yaml
---
name: validator
description: "Validates that a completed story actually works. Runs acceptance criteria verification commands, checks test results, and confirms the commit exists."
tools:
  - Bash
  - Read
  - Glob
  - Grep
permissionMode: plan
model: haiku
memory: project
---
```

**`agents/reviewer.md`** — The PRD review agent
```yaml
---
name: reviewer
description: "Reviews a PRD for completeness, testability, and potential issues. Focuses on one specific angle: security, performance, or test coverage."
tools:
  - Read
  - Glob
  - Grep
permissionMode: plan
model: sonnet
---
```

**`agents/merger.md`** — The branch management agent
```yaml
---
name: merger
description: "Handles git operations: branch creation, merge to main, conflict resolution, branch cleanup."
tools:
  - Bash
  - Read
  - Grep
model: haiku
---
```

### 5.5 Agent Memory Integration

Agent Memory replaces `progress.txt` with a native, auto-curated knowledge store.

**Scope:** `project` — stored in `.claude/agent-memory/taskplex/MEMORY.md`, committed to git so learnings persist across clones.

**What gets stored:**
- Codebase patterns discovered during implementation
- Gotchas and workarounds
- File relationships and conventions
- Test infrastructure details
- Environment requirements

**What does NOT get stored:**
- Story-specific implementation details
- Debugging logs
- Iteration timestamps

The implementer agent's frontmatter includes `memory: project`, so it automatically reads MEMORY.md at the start of each session and can write new learnings back. The 200-line auto-limit with curation instructions keeps it focused.

### 5.6 Hooks for Quality Gates

**`hooks/hooks.json`** — enforced during implementation:

```json
{
  "hooks": [
    {
      "event": "PostToolUse",
      "matcher": "Bash",
      "type": "command",
      "command": "scripts/check-destructive.sh",
      "description": "Block destructive git commands during implementation"
    }
  ]
}
```

Hooks defined in the implementer agent's frontmatter can enforce:
- "Don't commit if typecheck fails" (PreToolUse on `git commit`)
- "Don't push to main" (PreToolUse on `git push`)

### 5.7 Enhanced prd.json Schema

Add new fields to support TaskPlex's enhanced execution:

```json
{
  "project": "MyApp",
  "branchName": "taskplex/feature-name",
  "description": "Feature description",
  "config": {
    "max_retries_per_story": 2,
    "merge_strategy": "auto",
    "test_command": "npm test",
    "build_command": "npm run build",
    "typecheck_command": "npm run typecheck"
  },
  "userStories": [
    {
      "id": "US-001",
      "title": "Story title",
      "description": "As a...",
      "acceptanceCriteria": [...],
      "priority": 1,
      "passes": false,
      "status": "pending",
      "notes": "",
      "depends_on": [],
      "related_to": [],
      "implementation_hint": "",
      "check_before_implementing": [],
      "attempts": 0,
      "last_error": null,
      "last_error_category": null
    }
  ]
}
```

New fields:
- `config.test_command` / `build_command` / `typecheck_command` — project-specific commands used by the validator
- `status`: `pending` | `in_progress` | `completed` | `skipped` | `blocked`
- `attempts`: number of implementation attempts
- `last_error` / `last_error_category`: structured error tracking

### 5.8 Configuration Format

Replace YAML frontmatter with proper JSON (parsed with `jq`, no grep hacks):

**`.claude/taskplex.config.json`**

```json
{
  "max_iterations": 25,
  "iteration_timeout": 3600,
  "execution_mode": "foreground",
  "execution_model": "opus",
  "effort_level": "high",
  "max_retries_per_story": 2,
  "merge_on_complete": true,
  "branch_prefix": "taskplex",
  "test_command": "npm test",
  "build_command": "npm run build",
  "typecheck_command": "npm run typecheck"
}
```

### 5.9 Branch Lifecycle Management

TaskPlex manages the full branch lifecycle:

```
main ──────────────────────────────────────────► main (merged)
  │                                                ▲
  └── taskplex/feature ──┬── US-001 ──┬── US-002 ─┘
                         │  (commit)  │  (commit)
                         │            │
                     validate      validate
```

**On start:**
1. Ensure we're on main/develop (configurable base branch)
2. Pull latest
3. Create `taskplex/feature-name` branch
4. Push branch to remote (tracking)

**After each story:**
1. Commit with message: `feat(US-XXX): Story title`
2. Validator runs acceptance criteria
3. If passes → continue to next story
4. If fails → retry/skip based on error category

**On completion (all stories pass):**
1. Run full test suite on the branch
2. Run build
3. If all green:
   - `git merge --no-ff` to main (preserves feature branch history)
   - Delete the feature branch
   - Generate completion report
4. If tests fail:
   - Leave branch as-is
   - Report which tests fail
   - User merges manually

**On partial completion (some stories skipped):**
1. Generate report: completed stories, skipped stories, reasons
2. Leave branch for user review
3. User can: merge partial work, fix skipped stories manually, or re-run TaskPlex

### 5.10 Completion Report

Generated as `.claude/taskplex-report.md`:

```markdown
# TaskPlex Completion Report
**Feature:** task-priority-system
**Branch:** taskplex/task-priority
**Date:** 2026-02-10

## Summary
- Stories completed: 5/7
- Stories skipped: 2/7
- Total iterations: 14
- Total time: 47 minutes

## Completed Stories
- ✅ US-001: Add priority field to database (1 attempt)
- ✅ US-002: Priority display component (2 attempts)
- ✅ US-003: Priority selector in edit modal (1 attempt)
- ✅ US-004: Filter by priority (1 attempt)
- ✅ US-005: Sort by priority (1 attempt)

## Skipped Stories
- ⏭️ US-006: Priority-based email notifications
  - Category: env_missing
  - Error: SMTP_HOST not configured
  - Action needed: Set SMTP environment variables
- ⏭️ US-007: Priority analytics dashboard
  - Category: dependency_missing
  - Error: chart.js not installed
  - Action needed: npm install chart.js

## Branch Status
- Branch `taskplex/task-priority` is ready for review
- 5 commits on branch
- Tests: 23 passing, 0 failing
- Merge command: `git checkout main && git merge --no-ff taskplex/task-priority`
```

---

## 6. The Wizard (start.md)

The wizard flow is similar to SDK Bridge but with enhancements:

### Enhanced Checkpoints

1. **Check Dependencies** — same as SDK Bridge, plus check for `yq` or rely on JSON config
2. **Project Input** — same as SDK Bridge (file path or description, smart interview)
3. **Generate PRD** — enhanced: after generation, optionally spawn 2-3 reviewer subagents for multi-perspective review
4. **Review PRD** — same AskUserQuestion loop (approve / suggest improvements / edit / start over)
5. **Convert to JSON** — enhanced: adds `config` block with auto-detected test/build/typecheck commands
6. **Execution Settings** — JSON config instead of YAML, adds retry and merge settings
7. **Launch** — same foreground/background options

### New: Multi-Perspective PRD Review (Optional)

After PRD generation, the user can opt into a parallel review:

```
Question: "Would you like a multi-perspective review of the PRD before conversion?"
- "Skip — PRD looks good" (proceed to conversion)
- "Quick review — check for gaps" (single reviewer, 30 seconds)
- "Full review — security + testability + sizing" (3 reviewers in parallel, ~2 min)
```

If "Full review" is selected, spawn 3 reviewer subagents (using Task tool, not Agent Teams — simpler and lower cost):
- **Reviewer 1:** Check for security implications (auth, validation, data exposure)
- **Reviewer 2:** Check testability (are all criteria truly verifiable? Missing edge cases?)
- **Reviewer 3:** Check story sizing (any stories too large? Missing dependencies?)

Each reviewer returns a short report. The wizard synthesizes findings and presents to the user.

---

## 7. Migration Path from SDK Bridge

TaskPlex should be a **new plugin**, not a modification of SDK Bridge. This allows:
- SDK Bridge to continue working for existing users
- Side-by-side comparison during testing
- Clean codebase without legacy baggage

**Compatibility:**
- TaskPlex reads the same `prd.json` format (with optional new fields)
- Existing PRDs generated by SDK Bridge work with TaskPlex
- The `tasks/prd-*.md` files are compatible
- Agent Memory coexists with `progress.txt` (different location)

**Migration steps for users:**
1. Install TaskPlex plugin
2. Run `/taskplex:start` — it detects existing `prd.json` and offers to use it
3. Optionally uninstall SDK Bridge after confirming TaskPlex works

---

## 8. What We're NOT Doing (and Why)

**NOT using Agent Teams for implementation**
Agent Teams are designed for parallel work. Our sequential model exists for a good reason — avoiding merge conflicts. The token cost of Agent Teams (each teammate has its own context window) is not justified when tasks must be sequential anyway.

**NOT doing the IndyDevDan variation approach**
Creating multiple variations and letting the user choose is wasteful. TaskPlex's philosophy: know what you want (via PRD refinement), then execute it correctly once.

**NOT adding real-time UI/dashboard**
The tmux visualization and observability dashboards are impressive demos but add complexity without proportional value for a background automation tool. The completion report serves the same purpose.

**NOT using Agent Teams for implementation (even for "independent" tasks)**
Even tasks that appear independent (no `depends_on`) might touch shared files or have implicit dependencies. Sequential execution is the safest default. If we ever add parallel support, it should be opt-in per-run.

---

## 9. Implementation Plan

### Phase 1: Core Loop (Week 1)
- [ ] Plugin manifest and structure
- [ ] `taskplex.sh` with dependency-aware task selection
- [ ] JSON config parser (replacing grep-based YAML)
- [ ] Error categorization and structured retry logic
- [ ] Implementer prompt (enhanced from SDK Bridge's `prompt.md`)

### Phase 2: Subagents & Memory (Week 2)
- [ ] `agents/implementer.md` — custom subagent definition
- [ ] `agents/validator.md` — post-task verification
- [ ] `agents/merger.md` — git branch lifecycle
- [ ] Agent Memory integration (replace progress.txt)
- [ ] Validator prompt and verification flow

### Phase 3: Wizard & Skills (Week 3)
- [ ] `commands/start.md` — enhanced wizard with all checkpoints
- [ ] `skills/prd-generator/SKILL.md` — enhanced from SDK Bridge
- [ ] `skills/prd-converter/SKILL.md` — enhanced with config block
- [ ] `skills/failure-analyzer/SKILL.md` — new
- [ ] Multi-perspective PRD review (optional checkpoint)

### Phase 4: Branch Management & Reporting (Week 4)
- [ ] Branch creation and checkout in the loop
- [ ] Post-completion merge logic
- [ ] Completion report generation
- [ ] Partial completion handling
- [ ] Hooks configuration for quality gates

### Phase 5: Testing & Polish (Week 5)
- [ ] End-to-end testing with simple PRD
- [ ] End-to-end testing with complex PRD (7+ stories, dependencies)
- [ ] Failure scenario testing (env missing, test failures, timeouts)
- [ ] README and marketplace listing
- [ ] Migration guide from SDK Bridge

---

## 10. Open Questions

1. **Config format:** JSON (proposed) vs. TOML vs. keep YAML? JSON is native to `jq` but less human-friendly.
2. **Merge strategy:** Always `--no-ff`? Or configurable (squash, rebase, fast-forward)?
3. **Base branch:** Always `main`? Or detect default branch? Or configurable?
4. **Retry context window:** When retrying, should the error context be prepended to the prompt or passed as a separate file?
5. **Agent Memory scope:** `project` (shared via git) or `local` (per-machine)? Project scope means learnings propagate to all developers, which could be valuable or noisy.
6. **Plugin name:** TaskPlex? Conductor? Forge? Something else?

---

## Appendix A: Feature Comparison Matrix

| Feature | SDK Bridge v4.8 | TaskPlex v1.0 |
|---------|-----------------|---------------|
| PRD generation | ✅ | ✅ (enhanced) |
| AskUserQuestion loop | ✅ | ✅ |
| Multi-perspective PRD review | ❌ | ✅ (optional) |
| Sequential execution | ✅ | ✅ |
| Fresh context per task | ✅ | ✅ |
| Dependency tracking | ✅ (not enforced) | ✅ (enforced) |
| Error categorization | ❌ | ✅ |
| Intelligent retry | ❌ (basic timeout retry) | ✅ |
| Skip + continue | ❌ | ✅ |
| Agent Memory | ❌ (progress.txt) | ✅ (native) |
| Custom subagents | ❌ | ✅ |
| Hooks / quality gates | ❌ | ✅ |
| Branch creation | ❌ | ✅ |
| Auto-merge on complete | ❌ | ✅ |
| Completion report | ❌ | ✅ |
| JSON config | ❌ (YAML grep) | ✅ |
| Post-run validation | ❌ | ✅ |
| Parallel execution | ❌ | ❌ (intentionally) |

## Appendix B: Relevant Claude Code CLI Flags

```bash
# TaskPlex will use these flags for spawning agents:
claude -p "$PROMPT" \
  --output-format json \
  --no-session-persistence \
  --model "$MODEL" \
  --allowedTools "Bash,Read,Edit,Write,Glob,Grep" \
  --agent implementer \
  --agents-dir "$PLUGIN_ROOT/agents"
```

New flags available:
- `--agent <name>` — use a specific custom subagent
- `--agents <json>` — inline agent definitions
- `--agents-dir <path>` — directory containing agent `.md` files (the plugin's `agents/` dir)
- `--max-turns <n>` — limit agentic turns per invocation
- `--max-budget-usd <n>` — spending cap per invocation
