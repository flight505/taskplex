# TaskPlex v2.1 SOTA Upgrade — PRD & Competitive Analysis

**Date:** 2026-02-20
**Version:** 2.0.7 → 2.0.8
**Author:** Jesper Vang (@flight505)

---

## 1. Executive Summary

A comprehensive audit of TaskPlex v2.0.7 against the latest Claude Code CLI documentation (2.1.47+) and 15+ competing plugins reveals **28 verified gaps** across agent frontmatter, skill configuration, hook coverage, and plugin manifest. This PRD documents every gap, the competitive landscape, and the implementation plan to bring TaskPlex to absolute state-of-the-art.

### Audit Methodology
- CLI documentation verification: 15 schema questions answered with verbatim doc excerpts
- Competitive analysis: 15 plugins analyzed (55k-star Superpowers down to 4-star newcomers)
- File-by-file inspection of all 12 plugin component files

### Key Corrections from Initial Audit
The initial audit flagged 3 "Critical" items that were **false positives** on file inspection:
- `memory: project` IS present on implementer.md and validator.md (no drift)
- `inject-knowledge.sh` already outputs correct `hookSpecificOutput.additionalContext` JSON
- `PermissionRequest` hook does NOT fire in `-p` (headless) mode — downgraded from High

---

## 2. Competitive Landscape

### Top 10 Competitors by GitHub Stars

| # | Plugin | Stars | Key Differentiator |
|---|--------|-------|-------------------|
| 1 | **Superpowers** (obra) | 55,300 | Composable skills, TDD enforcement, auto-triggering |
| 2 | **claude-mem** (thedotmack) | 29,300 | Cross-session memory with vector search |
| 3 | **wshobson/agents** | 28,900 | 72 plugins, 112 agents, progressive disclosure |
| 4 | **Claude Task Master** (eyaltoledano) | 25,500 | PRD→tasks, multi-model, MCP server architecture |
| 5 | **Claude-Flow** (ruvnet) | 14,200 | Enterprise swarm intelligence, Byzantine fault tolerance |
| 6 | **Auto-Claude** (AndyMik90) | 12,300 | Electron GUI, kanban board, 12 concurrent agents |
| 7 | **Compound Engineering** (EveryInc) | 9,200 | Learning accumulation, cross-platform export |
| 8 | **anthropics/claude-plugins-official** | 7,700 | Official: ralph-wiggum, feature-dev, code-review |
| 9 | **ccpm** (automazeio) | 7,400 | GitHub Issues as state, team collaboration |
| 10 | **oh-my-claudecode** (Yeachan-Heo) | 6,700 | 32 agents, natural language activation, 5 modes |

### Feature Gap Matrix: TaskPlex vs Top Competitors

| Feature | TaskPlex | Superpowers | oh-my-cc | wshobson | Auto-Claude | ccpm |
|---------|----------|-------------|----------|----------|-------------|------|
| PRD generation | **Yes** | No | No | No | No | Yes |
| JSON execution state | **Yes** | No | No | No | Kanban | GitHub Issues |
| Dependency graph | **Yes** | No | No | No | No | Yes |
| Error categorization (6 types) | **Yes** | No | No | No | No | No |
| Retry strategies per category | **Yes** | No | No | No | QA loops | No |
| SQLite knowledge store | **Yes** | No | No | No | Memory | No |
| Confidence decay | **Yes** | No | No | No | No | No |
| Execution monitor (web) | **Yes** | No | No | No | Electron GUI | GitHub |
| Model routing per story | **Yes** | No | Yes | Yes (3 tier) | No | No |
| Parallel worktrees | **Yes** | Yes | Yes | No | Yes (12) | Yes |
| Inline validation (self-heal) | **Yes** | No | No | No | QA loops | No |
| Code review agent | **Yes** | Yes | No | No | No | No |
| TDD enforcement | **No** | **Yes (hard)** | No | Yes | No | No |
| Natural language activation | **No** | Partial | **Yes** | No | Yes | No |
| Multi-platform | **No** | **Yes** | No | No | Yes | No |
| CI/PR/Deploy automation | **No** | No | No | No | No | **Yes** |

### TaskPlex's Unique Differentiators (No Competitor Has)
1. **Failure categorization with per-category retry limits** — 6 error types, each with specific strategy
2. **SQLite knowledge store with 5%/day confidence decay** — stale learnings auto-expire
3. **Three-layer knowledge architecture** — operational log / knowledge base / context briefs
4. **Adaptive PRD rewriting** — failed stories auto-split into smaller sub-stories
5. **Scope drift detection** — git diff vs expected files, informational warnings
6. **Decision calls for model routing** — 1-shot Opus call picks haiku/sonnet/opus per story

### Competitive Features Worth Adopting
1. **`$ARGUMENTS` fast-start** — `/taskplex:start Fix the login bug` skips interview
2. **Dynamic context injection** — auto-detect existing prd.json/config in wizard
3. **One-time status hook** — print active run status on session start

---

## 3. Verified Gaps (28 items)

### 3.1 Agent Frontmatter (5 items)

| # | Agent | Gap | Fix | Priority |
|---|-------|-----|-----|----------|
| 1 | implementer | No `permissionMode` | Add `permissionMode: bypassPermissions` | High |
| 2 | validator | No `permissionMode` | Add `permissionMode: dontAsk` | High |
| 3 | reviewer | No `permissionMode` | Add `permissionMode: plan` | Medium |
| 4 | merger | No `permissionMode`, no `disallowedTools` | Add `permissionMode: bypassPermissions`, `disallowedTools: [Write, Edit, Task]` | High |
| 5 | code-reviewer | No `permissionMode`, no `memory` | Add `permissionMode: dontAsk`, `memory: project` | Medium |

### 3.2 Skill Frontmatter (8 items)

| # | Skill | Gap | Fix | Priority |
|---|-------|-----|-----|----------|
| 6 | prd-generator | No `agent` field (defaults to expensive general-purpose) | Add `agent: Explore` | High |
| 7 | prd-generator | No `model`, no `disable-model-invocation` | Add `model: sonnet`, `disable-model-invocation: true` | Medium |
| 8 | prd-generator | No `allowed-tools` | Add `allowed-tools: Read, Grep, Glob, Write, AskUserQuestion` | Medium |
| 9 | prd-converter | No `agent` field | Add `agent: Explore` | High |
| 10 | prd-converter | No `model`, no `disable-model-invocation` | Add `model: sonnet`, `disable-model-invocation: true` | Medium |
| 11 | prd-converter | No `allowed-tools` | Add `allowed-tools: Read, Grep, Glob, Write` | Medium |
| 12 | failure-analyzer | No `user-invocable`, no `disable-model-invocation` | Add `user-invocable: false`, `disable-model-invocation: true` | Medium |
| 13 | start.md | No `disable-model-invocation` | Add `disable-model-invocation: true` | High |

### 3.3 Hooks (10 items)

| # | Hook | Gap | Fix | Priority |
|---|------|-----|-----|----------|
| 14 | **NEW** | No `Stop` hook | Add Stop hook to prevent premature exit during active run | High |
| 15 | **NEW** | No `TaskCompleted` hook | Add TaskCompleted hook to validate story completion | Medium |
| 16 | **NEW** | No `CLAUDE_ENV_FILE` in SessionStart | Persist `TASKPLEX_RUN_ID`, `TASKPLEX_MONITOR_PORT` env vars | Medium |
| 17 | inject-knowledge.sh | No `statusMessage` | Add `statusMessage: "Injecting knowledge context..."` | Medium |
| 18 | inject-knowledge.sh | No `timeout` | Add `timeout: 120` | Medium |
| 19 | validate-result.sh | No `statusMessage` | Add `statusMessage: "Validating implementation..."` | Medium |
| 20 | validate-result.sh | No `timeout` | Add `timeout: 180` | Medium |
| 21 | pre-compact.sh | No `statusMessage` | Add `statusMessage: "Saving context before compaction..."` | Medium |
| 22 | All monitor hooks | No `statusMessage` | Not needed (async hooks don't show spinners) | N/A — Skip |
| 23 | hooks.json | No `description` field | Not documented in schema — skip | N/A — Skip |

### 3.4 Plugin Manifest (2 items)

| # | Field | Gap | Fix | Priority |
|---|-------|-----|-----|----------|
| 24 | plugin.json | `hooks` not declared | Add `"hooks": "./hooks/hooks.json"` | Low |
| 25 | plugin.json | `author.email` missing | Add `"email": "jesper_vang@me.com"` | Low |

### 3.5 Competitive Features (3 items)

| # | Feature | Source | Fix | Priority |
|---|---------|--------|-----|----------|
| 26 | `$ARGUMENTS` fast-start | ccpm, Claude Task Master | Add `$ARGUMENTS` to start.md for inline feature descriptions | Medium |
| 27 | Dynamic context injection | spec-workflow | Add `` !`command` `` in start.md to detect existing state | Medium |
| 28 | One-time status hook | compound-engineering | Add `once: true` SessionStart hook that prints run status | Low |

---

## 4. Implementation Plan

### Batch A: Agent Frontmatter (items 1-5)
**Files:** `agents/implementer.md`, `agents/validator.md`, `agents/reviewer.md`, `agents/merger.md`, `agents/code-reviewer.md`
**Changes:** Add `permissionMode`, `disallowedTools`, `memory` fields to YAML frontmatter
**Risk:** Low — frontmatter-only changes, no logic changes
**Verification:** `bash -n` won't help (YAML), visual inspection of frontmatter

### Batch B: Skill Frontmatter (items 6-13)
**Files:** `skills/prd-generator/SKILL.md`, `skills/prd-converter/SKILL.md`, `skills/failure-analyzer/SKILL.md`, `commands/start.md`
**Changes:** Add `agent`, `model`, `disable-model-invocation`, `allowed-tools`, `user-invocable` fields
**Risk:** Low — frontmatter-only changes
**Note:** `agent: Explore` on forked skills will use the built-in Explore agent (haiku, read-only tools) instead of default general-purpose

### Batch C: New Hooks (items 14-16)
**Files:** `hooks/hooks.json`, NEW `hooks/stop-guard.sh`, NEW `hooks/task-completed.sh`, modified `monitor/hooks/session-lifecycle.sh`
**Changes:**
- `stop-guard.sh`: Check if prd.json has in_progress stories; if yes, block with "Stories still in progress"
- `task-completed.sh`: Run test command before allowing task completion; exit 2 if tests fail
- `session-lifecycle.sh`: Add `CLAUDE_ENV_FILE` writes for env var persistence
**Risk:** Medium — Stop hook needs careful loop prevention (check `stop_hook_active`)
**Verification:** Test Stop hook with `stop_hook_active: true` → must exit 0

### Batch D: Hook Enhancements (items 17-21)
**Files:** `hooks/hooks.json`
**Changes:** Add `statusMessage` and `timeout` fields to existing hook entries
**Risk:** Low — declarative JSON changes only

### Batch E: Plugin Manifest + Competitive Features (items 24-28)
**Files:** `plugin.json`, `commands/start.md`
**Changes:**
- Add `hooks` and `author.email` to plugin.json
- Add `$ARGUMENTS` handling and dynamic context injection to start.md
- Add `once: true` SessionStart hook for status display
**Risk:** Low-Medium — `$ARGUMENTS` and `` !`command` `` need careful syntax

### Execution Order
Batches A and B are independent (parallel-safe). Batch C depends on nothing. Batch D depends on C (new hooks must exist before adding statusMessage). Batch E depends on nothing.

**Recommended:** A → B → C → D → E (sequential for clarity in one session)

---

## 5. Non-Goals (Explicitly Out of Scope)

- **TDD enforcement** — Would require fundamental changes to implementer agent workflow. Future PRD.
- **Multi-platform support** — Claude Code plugin architecture is platform-specific by design.
- **Natural language activation** — `/taskplex:start` is clear; auto-triggering risks false activations.
- **GitHub Issues as state** — prd.json is simpler and works offline; different philosophy.
- **CI/PR/Deploy automation** — Post-completion pipeline is a separate feature (`/taskplex:ship`).
- **Cross-model PRD review** — Adversarial spec review is interesting but adds cost and complexity.
- **Agent teams** — Experimental CLI feature; revisit when stable.

---

## 6. Success Criteria

After implementation, TaskPlex v2.0.8 will:
1. Use every documented agent frontmatter field where applicable (11/11 field coverage)
2. Use every documented skill frontmatter field where applicable (10/10 field coverage)
3. Have explicit `permissionMode` on all 5 agents for clean headless execution
4. Have `statusMessage` on all synchronous hooks for UX feedback
5. Have `timeout` on all synchronous hooks to prevent hanging
6. Have a `Stop` hook preventing premature exit during active runs
7. Have a `TaskCompleted` hook enforcing test-gate on story completion
8. Have `CLAUDE_ENV_FILE` persistence for TaskPlex environment variables
9. Support `$ARGUMENTS` for fast-start (`/taskplex:start <description>`)
10. Have `disable-model-invocation: true` on all skills/commands (prevent false auto-trigger)
11. Declare `hooks` explicitly in plugin.json for self-documentation
12. All 28 gaps resolved, verified against CLI documentation

---

## 7. Appendix: CLI Documentation Verification

All 15 features verified against `cli-full-docs.txt` (CLI 2.1.47+):

| Feature | Exists | Key Detail |
|---------|--------|------------|
| SubagentStart `additionalContext` | Yes | JSON `hookSpecificOutput.additionalContext` format |
| Stop hook | Yes | Can block with `decision: "block"`, has `stop_hook_active` |
| PermissionRequest hook | Yes | Does NOT fire in `-p` mode (headless) |
| permissionMode (5 values) | Yes | default, acceptEdits, dontAsk, bypassPermissions, plan |
| Agent frontmatter (11 fields) | Yes | name, description, tools, disallowedTools, model, permissionMode, maxTurns, skills, mcpServers, hooks, memory |
| Skill frontmatter (10 fields) | Yes | name, description, argument-hint, disable-model-invocation, user-invocable, allowed-tools, model, context, agent, hooks |
| statusMessage | Yes | Common field on all hook types |
| CLAUDE_ENV_FILE | Yes | SessionStart only, write `export` statements |
| type: "prompt" hooks | Yes | Single-turn LLM eval, `{ok: true/false}` response |
| type: "agent" hooks | Yes | Multi-turn with Read/Grep/Glob tools |
| disable-model-invocation | Yes | Applies to both skills and commands |
| TaskCompleted hook | Yes | Exit 2 blocks completion, stderr is feedback |
| UserPromptSubmit hook | Yes | Can inject context and block prompts |
| plugin.json schema | Yes | 15 fields: 8 metadata + 7 component paths |
| once field | Yes | Skills only, not agents; removed after first fire |
| $ARGUMENTS | Yes | Works in both skills and commands |
