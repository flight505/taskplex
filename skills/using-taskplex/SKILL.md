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
| `taskplex:focused-task` | Well-scoped task (1-5 files, clear criteria) | Inline TDD implementation without overhead |
| `taskplex:test-driven-development` | Before ANY implementation (feature, bugfix, refactor) | Enforces RED-GREEN-REFACTOR discipline |
| `taskplex:verification-before-completion` | Before ANY completion claim ("done", "fixed", "passing") | Enforces fresh evidence before claims |
| `taskplex:systematic-debugging` | Any bug, test failure, or unexpected behavior | 4-phase root cause investigation before fixes |
| `taskplex:dispatching-parallel-agents` | 2+ independent tasks with no shared state | One agent per problem domain, concurrent execution |
| `taskplex:using-git-worktrees` | Starting feature work that needs isolation | Creates isolated git worktree with safety verification |
| `taskplex:finishing-a-development-branch` | Implementation complete, tests pass, ready to integrate | Verify tests, present options, execute, cleanup |
| `taskplex:requesting-code-review` | After task completion or before merge | Dispatches code-reviewer subagent with SHA range |
| `taskplex:receiving-code-review` | Receiving code review feedback | Technical evaluation, not performative agreement |
| `taskplex:subagent-driven-development` | Executing plan with independent tasks in current session | Fresh subagent per task + two-stage review |
| `taskplex:guided-implementation` | Executing plan inline with human review checkpoints | Batch execution with human feedback between batches |
| `taskplex:writing-skills` | Creating or editing skills | TDD applied to process documentation |
| `taskplex:failure-analyzer` | Implementation fails with unclear error | Categorizes error and suggests retry strategy |

## Decision Flow

1. **Bug/failure?** → `systematic-debugging` (root cause FIRST)
2. **Feature described?**
   - a. Well-scoped (1-5 files, clear criteria)? → `focused-task`
   - b. Novel/ambiguous? → `brainstorm` → `writing-plans`
   - c. Large project (6+ files, multi-story)? → Suggest SDK-Bridge: "This task is larger scope. Consider using `/sdk-bridge:start` for PRD-driven autonomous development."
3. **Plan exists?** → `subagent-driven-development` (same session) or `guided-implementation` (inline with human checkpoints)
4. **Need plan?** → `writing-plans`
5. **2+ independent tasks?** → `dispatching-parallel-agents`
6. **Before code?** → `test-driven-development`
7. **Claiming done?** → `verification-before-completion`
8. **Review feedback?** → `receiving-code-review`
9. **Work complete?** → `finishing-a-development-branch`

**Tip:** For complex brainstorm or multi-task planning on Opus 4.6, type "ultrathink" before your message to request deeper reasoning.

## TaskPlex vs Built-in CLI Commands

The CLI includes `/simplify` (3 parallel review agents) and `/batch` (autonomous worktree-isolated agents). These are fast but have no discipline gates. TaskPlex skills complement them:

- `/batch` does large-scale autonomous work — TaskPlex enforces TDD, spec compliance, and human checkpoints
- `/simplify` does quick code review — TaskPlex's two-stage review catches spec drift, not just code quality
- Use CLI commands for speed when discipline is less critical; use TaskPlex skills when correctness matters

## Red Flags — STOP, You're Rationalizing

| Thought | Reality |
|---------|---------|
| "This is just a simple question" | Questions are tasks. Check for skills. |
| "I need more context first" | Skill check comes BEFORE clarifying questions. |
| "Let me explore the codebase first" | Skills tell you HOW to explore. Check first. |
| "I'll just start coding" | Even small tasks need acceptance criteria. Use focused-task. |
| "Tests can come later" | TDD is not optional. Invoke test-driven-development. |
| "It's working, I'm done" | Claims without evidence are lies. Invoke verification-before-completion. |
| "Let me try a quick fix" | Systematic debugging required. Root cause first. |
| "I'll review at the end" | Review after EACH task, not at the end. |
| "The reviewer is wrong" | Use receiving-code-review — verify before dismissing. |
| "I'll do it all in sequence" | Independent tasks → dispatch parallel agents. |
| "I'll just do this one thing first" | Check BEFORE doing anything. |
| "This is too small for focused-task" | Discipline always applies. Even one-file fixes get acceptance criteria + TDD. |
| "The skill is overkill" | Simple things become complex. Use it. |
| "I know what that means" | Knowing the concept ≠ using the skill. Invoke it. |

## Skill Priority

When multiple skills could apply, use this order:

1. **Process skills first** (brainstorm, debugging) — these determine HOW to approach the task
2. **Implementation skills second** — these guide execution

## Skill Types

**Rigid** (TDD, debugging, verification): Follow exactly. Don't adapt away discipline.

**Flexible** (patterns): Adapt principles to context.

The skill itself tells you which.

## User Instructions

Instructions say WHAT, not HOW. "Add X" or "Fix Y" doesn't mean skip workflows.
