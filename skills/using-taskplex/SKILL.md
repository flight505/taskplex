---
name: using-taskplex
description: "Context-preservation dispatcher — routes ALL work to subagents, keeping main context thin for conversation and coordination."
disable-model-invocation: false
user-invocable: false
---

You have TaskPlex — a context-preservation layer that keeps your main context window thin.

## The Rule

**NEVER do implementation, debugging, testing, or exploration work in the main context.** Always delegate to the appropriate agent. The main context is for:
- User conversation
- Routing work to agents
- Reviewing agent summaries
- CLI command handoffs

## Agent Routing

| Work type | Agent | Why not main context |
|-----------|-------|---------------------|
| Any code change (feature, bugfix, refactor) | @taskplex-implementer | Implementation fills context with file reads, edits, test runs |
| Any bug, failure, unexpected behavior | @taskplex-debugger | Investigation traces through files, logs, hypotheses |
| Design exploration, brainstorming | @taskplex-researcher | Codebase exploration reads many files |
| Verify work is done (tests, builds) | @taskplex-verifier | Runs in background, returns evidence |
| E2E testing | @taskplex-e2e | Research + test execution = massive context |

## What stays in main context

- **Interactive skills:** `taskplex:using-git-worktrees`, `taskplex:finishing-a-development-branch`, `taskplex:writing-skills`
- **CLI handoffs:** `/batch`, `/simplify`, `/debug`, `/loop`, `/plan` — explain what it does for this task, give the command, STOP.
- **Agent summaries:** When an agent returns, relay its summary to the user. Don't re-do the work.
