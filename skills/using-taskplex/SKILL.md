---
name: using-taskplex
description: "Routes tasks to the correct discipline skill based on complexity tier. Use when starting any conversation — provides skill awareness and CLI command reference."
disable-model-invocation: false
user-invocable: false
---

You have TaskPlex — a development companion that right-sizes process to task complexity.

## Task Tiers

Assess the task before choosing a workflow:

| Tier | Signals | Route |
|------|---------|-------|
| **Trivial** | Single file, obvious fix, config, typo, rename | Just do it. TDD if adding behavior. Verify before claiming done. |
| **Standard** | Multi-file feature, bug fix, refactor (3+ files) | `writing-plans` → `/batch` or inline TDD |
| **Complex** | New system, architecture change, ambiguous requirements | `brainstorm` → `writing-plans` → `/batch` |

**Quick test:** Can you describe the change in one sentence and name every file? → Trivial. Clear requirements, multiple files? → Standard. Unsure what to build? → Complex.

## Skill Catalog

| Skill | When to Use |
|-------|-------------|
| `taskplex:brainstorm` | Complex tier — ambiguous requirements need design exploration |
| `taskplex:writing-plans` | Standard+ tier — multi-file work needs a plan |
| `taskplex:test-driven-development` | Before implementing any behavior change |
| `taskplex:verification-before-completion` | Before claiming work is done (proportional to change size) |
| `taskplex:systematic-debugging` | Any bug, failure, or unexpected behavior — root cause first |
| `taskplex:using-git-worktrees` | Feature work needing branch isolation |
| `taskplex:finishing-a-development-branch` | Branch work complete, ready to merge/PR/discard |
| `taskplex:receiving-code-review` | Processing review feedback — evaluate technically before acting |
| `taskplex:writing-skills` | Creating or editing SKILL.md files |
| `taskplex:e2e-testing` | User invokes `/e2e-test` explicitly |

**Invoke skills via the Skill tool.** Don't tell the user to type skill names — invoke them directly.

## Non-Negotiable Disciplines

These three apply regardless of tier:

- **Debugging:** Investigate root cause before fixing (`systematic-debugging`)
- **TDD:** Write the test before the implementation (`test-driven-development`)
- **Verification:** Run the command before claiming it passes (`verification-before-completion`)

Everything else scales with task complexity. Don't brainstorm a config change. Don't write a plan for a typo fix.

## CLI Execution Commands

Bundled skills (`disable-model-invocation: true`) — you CANNOT invoke them via Skill tool. The user types them.

| Command | What it does |
|---------|-------------|
| `/batch <plan-or-instruction>` | Parallel execution: 5-30 worktrees, each agent implements + tests + PRs |
| `/simplify [focus]` | 3 parallel review agents on recent changes |
| `/debug [description]` | Troubleshoot current session via debug log |
| `/loop [interval] <prompt>` | Recurring task on interval |
| `/plan [description]` | Enter plan mode for design before coding |

**Handoff:** When workflow reaches a CLI command, explain what it does *for this task*, give the exact command to type, and **STOP**. Don't invoke other skills after handing off.

**Tip:** Type "ultrathink" before your message for high-effort reasoning on the next turn.

## Agent Teams (Experimental)

Claude Code supports agent teams — parallel teammate sessions with shared task lists. Enable with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Teams use `TeammateIdle` and `TaskCompleted` hooks for coordination. For most parallel work, `/batch` is the simpler option.
