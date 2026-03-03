---
name: using-taskplex
description: "Use when starting any conversation - establishes TaskPlex workflow awareness, requiring skill invocation before ANY response. Replaces using-superpowers."
disable-model-invocation: false
user-invocable: false
---

<EXTREMELY-IMPORTANT>
If you think there is even a 1% chance a TaskPlex skill might apply to what you are doing, you ABSOLUTELY MUST invoke the skill.

IF A SKILL APPLIES TO YOUR TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.

This is not negotiable. This is not optional. You cannot rationalize your way out of this.

**Autonomous invocation:** When the decision flow routes to a skill, use the **Skill tool** to invoke it directly — do NOT tell the user to type a slash command. You have the Skill tool available. Use it.
</EXTREMELY-IMPORTANT>

## TaskPlex Skill Catalog

| Skill | Triggers When | What It Does |
|-------|--------------|-------------|
| `taskplex:brainstorm` | User describes a feature, BEFORE jumping to PRD | Challenges assumptions, explores alternatives, produces Design Brief |
| `taskplex:prd-generator` | User describes a feature, project, or multi-file change | Generates structured PRD with clarifying questions |
| `taskplex:prd-converter` | PRD markdown exists and needs execution as JSON | Converts PRD to prd.json for autonomous execution |
| `taskplex:writing-plans` | Need a detailed task-by-task implementation plan | Creates bite-sized plan doc with TDD steps and exact commands |
| `taskplex:focused-task` | Well-scoped task (1-5 files, clear criteria) | Inline TDD implementation without PRD overhead |
| `taskplex:taskplex-tdd` | Before ANY implementation (feature, bugfix, refactor) | Enforces RED-GREEN-REFACTOR discipline |
| `taskplex:taskplex-verify` | Before ANY completion claim ("done", "fixed", "passing") | Enforces fresh evidence before claims |
| `taskplex:systematic-debugging` | Any bug, test failure, or unexpected behavior | 4-phase root cause investigation before fixes |
| `taskplex:dispatching-parallel-agents` | 2+ independent tasks with no shared state | One agent per problem domain, concurrent execution |
| `taskplex:using-git-worktrees` | Starting feature work that needs isolation | Creates isolated git worktree with safety verification |
| `taskplex:finishing-a-development-branch` | Implementation complete, tests pass, ready to integrate | Verify tests, present options, execute, cleanup |
| `taskplex:requesting-code-review` | After task completion or before merge | Dispatches code-reviewer agent with SHA range |
| `taskplex:receiving-code-review` | Receiving code review feedback | Technical evaluation, not performative agreement |
| `taskplex:subagent-driven-development` | Executing plan with independent tasks in current session | Fresh subagent per task + two-stage review |
| `taskplex:guided-implementation` | Executing plan inline with human review checkpoints | Batch execution with human feedback between batches |
| `taskplex:writing-skills` | Creating or editing skills | TDD applied to process documentation |
| `taskplex:failure-analyzer` | Implementation fails with unclear error | Categorizes error and suggests retry strategy |

## Decision Flow

1. **Active prd.json?** → Report status + invoke `taskplex:start` via the Skill tool to resume
2. **Bug/failure?** → `systematic-debugging` (root cause FIRST)
3. **Feature described?**
   - a. Well-scoped (1-5 files, clear criteria)? → `focused-task`
   - b. Novel/ambiguous? → `brainstorm` → invoke `prd-generator` via the Skill tool
   - c. Clear but multi-story? → invoke `prd-generator` directly
4. **Plan exists?** → `subagent-driven-development` (same session) or `guided-implementation` (inline with human checkpoints)
5. **Need plan?** → `writing-plans`
6. **2+ independent tasks?** → `dispatching-parallel-agents`
7. **Before code?** → `taskplex-tdd`
8. **Claiming done?** → `taskplex-verify`
9. **Review feedback?** → `receiving-code-review`
10. **Work complete?** → `finishing-a-development-branch`

## Red Flags — STOP, You're Rationalizing

| Thought | Reality |
|---------|---------|
| "This is just a simple feature" | Simple doesn't mean undisciplined. Use focused-task for 1-5 files, PRD for 6+. |
| "I'll just start coding" | Even small tasks need acceptance criteria. Use focused-task as the lightweight path. |
| "Tests can come later" | TDD is not optional. Invoke taskplex-tdd. |
| "It's working, I'm done" | Claims without evidence are lies. Invoke taskplex-verify. |
| "This doesn't need a PRD" | 1-5 files → focused-task. 6+ files → PRD. Both enforce discipline. |
| "Let me try a quick fix" | Systematic debugging required. Root cause first. |
| "I'll review at the end" | Review after EACH task, not at the end. |
| "The reviewer is wrong" | Use receiving-code-review — verify before dismissing. |
| "I'll do it all in sequence" | Independent tasks → dispatch parallel agents. |
| "I'll just do this one thing first" | Check BEFORE doing anything. |
| "This is too small for focused-task" | Discipline always applies. Even one-file fixes get acceptance criteria + TDD. |

## Skill Priority

1. Debugging → 2. Discipline (TDD/verify) → 3. Planning (brainstorm/PRD) → 4. Execution → 5. Integration
