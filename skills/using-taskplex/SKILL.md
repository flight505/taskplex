---
name: using-taskplex
description: "Use when starting any conversation - establishes TaskPlex workflow awareness, requiring skill invocation before ANY response including clarifying questions"
disable-model-invocation: false
user-invocable: false
---

<EXTREMELY-IMPORTANT>
If you think there is even a 1% chance a TaskPlex skill might apply to what you are doing, you ABSOLUTELY MUST invoke the skill.

IF A SKILL APPLIES TO YOUR TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.

This is not negotiable. This is not optional. You cannot rationalize your way out of this.

**Autonomous invocation:** When the decision flow routes to a skill, use the **Skill tool** to invoke it directly — do NOT tell the user to type a slash command. You have the Skill tool available. Use it.
</EXTREMELY-IMPORTANT>

## How to Access Skills

**In Claude Code:** Use the `Skill` tool. When you invoke a skill, its content is loaded and presented to you—follow it directly. Never use the Read tool on skill files.

## TaskPlex Skill Catalog

| Skill | Triggers When | What It Does |
|-------|--------------|-------------|
| `taskplex:brainstorm` | User describes a feature, BEFORE jumping to planning | Challenges assumptions, explores alternatives, produces Design Brief |
| `taskplex:writing-plans` | Need a detailed task-by-task implementation plan | Creates bite-sized plan doc with TDD steps and exact commands |
| `taskplex:test-driven-development` | Before ANY implementation (feature, bugfix, refactor) | Enforces RED-GREEN-REFACTOR discipline |
| `taskplex:verification-before-completion` | Before ANY completion claim ("done", "fixed", "passing") | Enforces fresh evidence before claims |
| `taskplex:systematic-debugging` | Any bug, test failure, or unexpected behavior | 4-phase root cause investigation before fixes |
| `taskplex:using-git-worktrees` | Starting feature work that needs isolation | Creates isolated git worktree with safety verification |
| `taskplex:finishing-a-development-branch` | Implementation complete, tests pass, ready to integrate | Verify tests, present options, execute, cleanup |
| `taskplex:receiving-code-review` | Receiving code review feedback | Technical evaluation, not performative agreement |
| `taskplex:writing-skills` | Creating or editing skills | TDD applied to process documentation |
| `taskplex:e2e-testing` | User explicitly invokes `/e2e-test` | Parallel research, journey planning, systematic testing with evidence |

## Decision Flow

1. **Bug/failure?** → `systematic-debugging` (root cause FIRST)
2. **Feature described?**
   - a. Novel/ambiguous? → `brainstorm` → `writing-plans`
   - b. Large project (6+ files, multi-story)? → Suggest SDK-Bridge: "This task is larger scope. Consider using `/sdk-bridge:start` for PRD-driven autonomous development."
3. **Plan exists?** → Execute with `/batch` (parallel worktree-isolated agents) or work through tasks inline with TDD
4. **Need plan?** → `writing-plans`
5. **Before code?** → `test-driven-development`
6. **Claiming done?** → `verification-before-completion`
7. **Review feedback?** → `receiving-code-review`
8. **Work complete?** → `finishing-a-development-branch`

**Tip:** For complex brainstorm or multi-task planning on Opus 4.6, type "ultrathink" before your message to request deeper reasoning.

## TaskPlex + CLI: Think, Then Execute

TaskPlex is the **thinking discipline layer**. The CLI provides the **execution engines**. Use them together:

1. **Think first** — `brainstorm` challenges assumptions, `writing-plans` creates bite-sized TDD tasks
2. **Execute with CLI** — `/batch` runs all tasks in parallel worktrees with auto-review, `/simplify` does 3-agent code review
3. **Verify after** — `verification-before-completion` ensures claims have evidence, `finishing-a-development-branch` handles integration

TaskPlex prepares the work so `/batch` and `/simplify` produce better results. Without discipline, speed just means faster mistakes.

## Red Flags — STOP, You're Rationalizing

| Thought | Reality |
|---------|---------|
| "This is just a simple question" | Questions are tasks. Check for skills. |
| "I need more context first" | Skill check comes BEFORE clarifying questions. |
| "Let me explore the codebase first" | Skills tell you HOW to explore. Check first. |
| "I'll just start coding" | Even small tasks need acceptance criteria. |
| "Tests can come later" | TDD is not optional. Invoke test-driven-development. |
| "It's working, I'm done" | Claims without evidence are lies. Invoke verification-before-completion. |
| "Let me try a quick fix" | Systematic debugging required. Root cause first. |
| "The reviewer is wrong" | Use receiving-code-review — verify before dismissing. |
| "The skill is overkill" | Simple things become complex. Use it. |
| "I know what that means" | Knowing the concept ≠ using the skill. Invoke it. |

## Skill Priority

When multiple skills could apply, use this order:

**Process skills first** (brainstorm, debugging, planning) — these determine HOW to approach the task.

## Skill Types

**Rigid** (TDD, debugging, verification): Follow exactly. Don't adapt away discipline.

**Flexible** (patterns): Adapt principles to context.

The skill itself tells you which.

## User Instructions

Instructions say WHAT, not HOW. "Add X" or "Fix Y" doesn't mean skip workflows.
