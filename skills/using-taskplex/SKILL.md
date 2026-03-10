---
name: using-taskplex
description: "Routes tasks to the correct discipline skill and guides CLI execution command usage. Use when starting any conversation — establishes TaskPlex workflow awareness, requiring skill invocation before ANY response including clarifying questions."
disable-model-invocation: false
user-invocable: false
---

<EXTREMELY-IMPORTANT>
If you think there is even a 1% chance a TaskPlex skill might apply to what you are doing, you ABSOLUTELY MUST invoke the skill.

IF A SKILL APPLIES TO YOUR TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.

This is not negotiable. This is not optional. You cannot rationalize your way out of this.

**TaskPlex skills** (listed in the catalog below): Use the **Skill tool** to invoke them directly. Do NOT tell the user to type a slash command — you have the Skill tool available. Use it.

**CLI execution commands** (`/batch`, `/simplify`, `/debug`, `/loop`): These are Claude Code **bundled skills** with `disable-model-invocation: true`. You CANNOT invoke them via the Skill tool. Instead, provide a **contextual handoff** — see the CLI Execution Commands section below.
</EXTREMELY-IMPORTANT>

## How to Access Skills

**TaskPlex skills:** Use the `Skill` tool. When you invoke a skill, its content is loaded and presented to you—follow it directly. Never use the Read tool on skill files.

**CLI bundled skills:** You must guide the user to type these commands themselves. See "CLI Execution Commands" below.

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

1. **User chose a CLI command from a handoff?** → Output the exact command and STOP (do not route to other skills)
2. **Bug/failure?** → `systematic-debugging` (root cause FIRST)
3. **Feature described?**
   - a. Novel/ambiguous? → `brainstorm` → `writing-plans`
   - b. Multi-step? → `writing-plans` → handoff to `/batch` (CLI)
4. **Plan exists?** → Handoff to `/batch` (CLI) or work through tasks inline with TDD
5. **Need plan?** → `writing-plans`
6. **Before code?** → `test-driven-development`
7. **Claiming done?** → `verification-before-completion`
8. **After implementation?** → Handoff to `/simplify` (CLI) for code review
9. **Review feedback?** → `receiving-code-review`
10. **Work complete?** → `finishing-a-development-branch`

**Tip:** Type "ultrathink" before your message to request high effort for the next turn. Effort levels: low (○), medium (◐), high (●). Use `/effort auto` to reset to default.

## TaskPlex + CLI: Think, Then Execute

TaskPlex is the **thinking discipline layer**. The CLI provides the **execution engines**. Use them together:

1. **Think first** — `brainstorm` challenges assumptions, `writing-plans` creates bite-sized TDD tasks
2. **Execute with CLI** — handoff to `/batch` for parallel worktree execution, `/simplify` for 3-agent code review
3. **Verify after** — `verification-before-completion` ensures claims have evidence, `finishing-a-development-branch` handles integration

TaskPlex prepares the work so `/batch` and `/simplify` produce better results. Without discipline, speed just means faster mistakes.

## CLI Execution Commands

These are Claude Code **bundled skills** — prompt-based playbooks that spawn agents and orchestrate work. They have `disable-model-invocation: true`, meaning you CANNOT invoke them via the Skill tool. The user must type them.

**Your job:** When the workflow reaches one of these commands, provide a **contextual handoff** — explain what the command will do *for this specific task*, then give the exact command to type.

**When the user accepts a handoff** (says "option 1", "/batch", "parallel", "yes", etc. after you presented CLI command options): Output the exact command to type and **STOP**. Do not invoke `test-driven-development` or any other skill. Do not start implementing. The CLI takes over — your job is done until the user returns.

### Commands

**`/batch <plan-or-instruction>`** — Researches the codebase, decomposes work into 5-30 independent units, presents a plan for approval. Once approved, spawns one agent per unit in an isolated git worktree. Each agent implements, runs tests, and opens a PR. Requires a git repo.

**`/simplify [focus]`** — Reviews recently changed files with 3 parallel agents (code reuse, quality, efficiency). Aggregates findings and applies fixes. Pass optional text to focus: `/simplify focus on error handling`.

**`/debug [description]`** — Reads the session debug log to troubleshoot the current Claude Code session. Describe the issue to focus analysis.

**`/loop [interval] <prompt>`** — Runs a prompt on a recurring interval while the session stays open. Example: `/loop 5m check if the deploy finished`.

**`/plan [description]`** — Enters plan mode. With a description (e.g., `/plan fix the auth bug`), starts planning immediately. Without arguments, enters interactive plan mode. Use when the user wants to design an approach before coding.

### Contextual Handoff Pattern

Do NOT give generic descriptions. Generate a handoff specific to the current task:

**Bad (generic):**
> "Type `/batch` to execute the plan in parallel."

**Good (contextual):**
> "Your plan has 5 tasks — auth middleware, route handlers, database migration, tests, and API docs. `/batch` will decompose these into parallel worktrees, each getting its own agent that implements the task, runs tests, and opens a PR. Type:
> `/batch docs/plans/2026-03-08-auth-refactor.md`"

**Good (contextual, after implementation):**
> "You've changed 4 files across the payment module. `/simplify` will review them with 3 parallel agents checking for code reuse, quality issues, and efficiency. Type:
> `/simplify focus on the new Stripe webhook handlers`"

The handoff should convey: **what it will do**, **why it's the right tool here**, and **the exact command**.

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
| "User said option 1, let me start TDD" | They chose /batch. Output the command and STOP. |

## Skill Priority

When multiple skills could apply, use this order:

**Process skills first** (brainstorm, debugging, planning) — these determine HOW to approach the task.

## Skill Types

**Rigid** (TDD, debugging, verification): Follow exactly. Don't adapt away discipline.

**Flexible** (patterns): Adapt principles to context.

The skill itself tells you which.

## User Instructions

Instructions say WHAT, not HOW. "Add X" or "Fix Y" doesn't mean skip workflows.
