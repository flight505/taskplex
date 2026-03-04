# Plan: SDK-Bridge Upgrade — PRD-Driven Project Orchestration

**Date:** 2026-03-04
**Goal:** SDK-Bridge becomes the long-running project orchestration plugin, absorbing TaskPlex's proven PRD pipeline, multi-agent system, and quality gates. Keeps its battle-tested bash loop + fresh Claude instances approach while adding TaskPlex's verification infrastructure.

---

## Current State

SDK-Bridge v4.8.1 has 2 skills, 0 agents, 0 hooks, 1 command, bash orchestration loop.
It already handles: PRD generation, JSON conversion, fresh Claude per story, progress tracking, background execution.

**What's missing:** Structured agents, verification hooks, two-phase review, failure categorization, resume intelligence, destructive command blocking.

---

## Design Principle

> SDK-Bridge = Long-running autonomous project execution with quality gates.

The bash loop (`sdk-bridge.sh`) spawning fresh Claude CLI instances is a proven pattern — keep it. Layer TaskPlex's quality infrastructure on top, not as replacement.

---

## What SDK-Bridge Already Has (Keep As-Is)

| Component | Notes |
|-----------|-------|
| `commands/start.md` (7-checkpoint wizard) | Working well, keep |
| `skills/prd-generator/` | Good, but merge TaskPlex improvements |
| `skills/prd-converter/` | Good, but merge TaskPlex improvements |
| `scripts/sdk-bridge.sh` (bash loop) | Battle-tested, keep |
| `scripts/prompt.md` | Working instructions for Claude instances |
| `scripts/check-deps.sh` | Keep |
| Background/foreground execution | Keep |
| Per-branch PID files | Keep |
| Progress.txt learnings accumulation | Keep |
| Already-implemented detection | Keep |

---

## What Moves FROM TaskPlex to SDK-Bridge

### Agents (4 agents)

| Agent | Source | Adaptation Needed |
|-------|--------|-------------------|
| `architect.md` | TaskPlex | Read-only codebase explorer for brainstorm phase. No changes needed. |
| `implementer.md` | TaskPlex | Story implementation agent. Remove `isolation: worktree` (already fixed). Add as registered agent that `sdk-bridge.sh` can reference. |
| `reviewer.md` | TaskPlex | Two-phase review (spec + validation). Keep as-is. |
| `merger.md` | TaskPlex | Git branch operations. Keep as-is. |

**Note:** SDK-Bridge's bash loop spawns fresh Claude CLI instances, not native subagents. These agents serve as **templates** that the prompt.md can reference, and as registered agents for users who want to use SDK-Bridge's components manually.

### Skills (2 skills, enhanced)

| Skill | What Changes |
|-------|-------------|
| `prd-generator` | Merge TaskPlex's improvements: lettered options (A, B, C, D), better dependency inference |
| `prd-converter` | Merge TaskPlex's improvements: segment grouping, story size validation, `check_before_implementing` field |

### Hooks (3-4 hooks)

| Hook | Event | Purpose | Priority |
|------|-------|---------|----------|
| `check-destructive.sh` | PreToolUse (Bash) | Block `git push --force`, `reset --hard`, direct push to main | High — prevents damage during long unattended runs |
| `validate-result.sh` | SubagentStop (implementer) | Run test/build/typecheck after story completion | High — quality gate |
| `task-completed.sh` | TaskCompleted | Verify story reviewed + tests pass | Medium — extra safety |
| Session context | SessionStart | Inject SDK-Bridge awareness + active prd.json status | Medium — convenience |

### Scripts (2 scripts)

| Script | Purpose |
|--------|---------|
| `check-destructive.sh` | Shared by PreToolUse hook |
| `check-git.sh` | Git diagnostics for start wizard |

### Config System

Merge TaskPlex's config fields into SDK-Bridge's existing `.claude/sdk-bridge.local.md`:

| Field | Source | Notes |
|-------|--------|-------|
| `test_command` | TaskPlex | For validation hooks |
| `build_command` | TaskPlex | For validation hooks |
| `typecheck_command` | TaskPlex | For validation hooks |
| `code_review` | TaskPlex | Enable/disable code-reviewer after stories (default: **true** — caught real bugs in every story during evaluation) |
| `interactive_mode` | TaskPlex | Pause between stories |
| `max_iterations` | SDK-Bridge (existing) | Keep |
| `iteration_timeout` | SDK-Bridge (existing) | Keep |
| `execution_mode` | SDK-Bridge (existing) | Keep |
| `execution_model` | SDK-Bridge (existing) | Keep |
| `effort_level` | SDK-Bridge (existing) | Keep |

### Failure Analyzer

Add `failure-analyzer` as a skill that's preloaded into the implementer agent context. When a story fails, categorize it before retrying.

### Resume Intelligence

Merge TaskPlex's resume logic into `sdk-bridge.sh`:
- Detect completed stories (`passes: true`), skip them
- Carry forward learnings from completed stories
- Report progress on resume: "X/Y stories complete, starting from US-NNN"

---

## Target State: SDK-Bridge v5.0.0

```
sdk-bridge/
├── .claude-plugin/plugin.json
├── commands/
│   └── start.md                       # 7-checkpoint wizard (enhanced)
├── agents/                             # 4+1 agents
│   ├── architect.md                   # Read-only explorer (from TaskPlex)
│   ├── implementer.md                 # Story implementation (from TaskPlex)
│   ├── reviewer.md                    # Two-phase review (from TaskPlex)
│   ├── merger.md                      # Git operations (from TaskPlex)
│   └── code-reviewer.md              # Code quality (from TaskPlex)
├── hooks/
│   ├── hooks.json                     # 3-4 hooks
│   ├── session-context.sh            # SessionStart: prd.json awareness
│   ├── check-destructive.sh          # PreToolUse: block dangerous commands
│   └── validate-result.sh            # SubagentStop: test/build/typecheck
├── skills/
│   ├── prd-generator/                 # Enhanced with TaskPlex improvements
│   ├── prd-converter/                 # Enhanced with TaskPlex improvements
│   └── failure-analyzer/              # From TaskPlex
├── scripts/
│   ├── sdk-bridge.sh                  # Bash loop (enhanced with resume)
│   ├── prompt.md                      # Per-iteration instructions
│   ├── check-deps.sh                  # Dependency verification
│   └── check-git.sh                   # Git diagnostics (from TaskPlex)
├── examples/
│   ├── prd-simple-feature.md
│   └── prd-complex-feature.md
├── README.md
├── CLAUDE.md
└── CHANGELOG.md
```

### Key Metrics

| Metric | v4.8.1 | v5.0.0 Target |
|--------|--------|---------------|
| Skills | 2 | 3 |
| Agents | 0 | 5 |
| Hooks | 0 | 3-4 |
| Commands | 1 | 1 |
| Scripts | 3 | 4 |

---

## Migration Steps

### Phase 1: Copy Components from TaskPlex

1. **Copy agents:** `architect.md`, `implementer.md`, `reviewer.md`, `merger.md`, `code-reviewer.md`
   - Adapt paths (`${CLAUDE_PLUGIN_ROOT}` references)
   - Update skill references (implementer references `taskplex-tdd` → should reference the skill by whatever name it has, or inline the instructions)
   - Remove `isolation: worktree` from implementer (already done in TaskPlex)

2. **Copy `failure-analyzer` skill**
   - No adaptation needed (standalone skill)

3. **Copy hook scripts:** `check-destructive.sh`, `validate-result.sh`, `session-context.sh`
   - Adapt config path references (`.claude/sdk-bridge.local.md` instead of `.claude/taskplex.config.json`)
   - Update session-context.sh to inject SDK-Bridge awareness instead of TaskPlex

4. **Copy `check-git.sh` script**
   - No adaptation needed

### Phase 2: Enhance Existing SDK-Bridge Components

1. **Enhance `prd-generator`**
   - Merge TaskPlex's lettered options (A, B, C, D) for clarifying questions
   - Keep SDK-Bridge's 5-criteria decomposition threshold
   - Add TaskPlex's `implementation_hint` field

2. **Enhance `prd-converter`**
   - Add segment grouping for partial re-execution
   - Add story size validation warnings
   - Keep `check_before_implementing` field (already in SDK-Bridge)

3. **Enhance `sdk-bridge.sh`**
   - Add resume intelligence: detect completed stories, skip, report progress
   - Add learnings carry-forward from completed stories
   - Add validation command execution (test/build/typecheck) after each iteration
   - Keep existing timeout/retry/background logic

4. **Enhance `start.md` wizard**
   - Add test/build/typecheck command collection (Checkpoint 6 expansion)
   - Add code review toggle
   - Keep existing 7 checkpoints, extend Checkpoint 6

### Phase 3: Create Hook System

1. **Create `hooks/hooks.json`** with 3-4 hooks
2. **Adapt hook scripts** for SDK-Bridge context
3. **Test hook firing** in both foreground and background modes

### Phase 4: Update Configuration

1. **Extend `.claude/sdk-bridge.local.md`** with test/build/typecheck fields
2. **Update `scripts/prompt.md`** to reference new agents and skills
3. **Update `plugin.json`** — add agents, hooks, skills, bump to v5.0.0

### Phase 5: Documentation

1. **Update `CLAUDE.md`** — document new architecture
2. **Update `README.md`** — position as "project orchestration plugin"
3. **Write `CHANGELOG.md` v5.0.0 entry**
4. **Add architecture doc** if complexity warrants it

### Phase 6: Verify

1. Run marketplace validation
2. Test full workflow: `/sdk-bridge:start` → PRD → execution → completion
3. Test resume: interrupt mid-run, restart, verify skip logic
4. Test hooks: destructive command blocking, validation gates
5. Test background mode with new hooks

---

## Integration Between Plugins

After both refactors, the user experience is:

```
User has a task
    ↓
TaskPlex (always-on) auto-detects via SessionStart hook
    ↓
Small task (1-5 files)?
    → focused-task (inline TDD, done in minutes)
    ↓
Large task (6+ files)?
    → TaskPlex suggests: "Use /sdk-bridge:start for PRD-driven development"
    → User runs /sdk-bridge:start
    → SDK-Bridge wizard: describe → PRD → review → config → launch
    → Autonomous execution with quality gates
    → Done
```

**TaskPlex** = fast, lightweight, always-on discipline (daily coding companion)
**SDK-Bridge** = thorough, autonomous, quality-gated (project execution engine)

---

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Agent references break across plugins | Audit all skill cross-references before removing from TaskPlex |
| Hook scripts assume TaskPlex paths | Adapt all `${CLAUDE_PLUGIN_ROOT}` and config references |
| SDK-Bridge bash loop conflicts with native agents | Agents are templates/manual-use; bash loop continues as primary execution |
| Users confused by plugin split | Clear README messaging + TaskPlex auto-suggests SDK-Bridge |
| Implementer agent skills (taskplex-tdd, taskplex-verify) no longer in same plugin | Either: (a) inline TDD instructions in implementer prompt, or (b) keep skill references (Claude resolves across installed plugins) |

---

## Open Questions

1. **Implementer skill dependencies:** The implementer agent references `taskplex-tdd` and `taskplex-verify` skills. If both plugins are installed, Claude resolves cross-plugin skills. But if only SDK-Bridge is installed, those skills don't exist. Options:
   - (a) Copy those skills into SDK-Bridge too (duplication)
   - (b) Inline the TDD/verify instructions into the implementer agent prompt
   - (c) Require TaskPlex as a dependency of SDK-Bridge
   - (d) List TaskPlex as "recommended companion plugin" in SDK-Bridge README

2. **Bash loop vs native subagents:** SDK-Bridge uses `sdk-bridge.sh` (bash loop spawning fresh Claude CLI). TaskPlex uses native Agent tool. Should SDK-Bridge offer both execution modes, or stick with bash loop?

3. **Config format:** SDK-Bridge uses YAML in `.claude/sdk-bridge.local.md`. TaskPlex uses JSON in `.claude/taskplex.config.json`. Standardize on one?

4. **Version bump:** SDK-Bridge v5.0.0 is a major version bump. Is the scope large enough to warrant it, or should it be v4.9.0?
