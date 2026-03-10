---
name: e2e-testing
description: "Systematically tests every user journey with parallel research agents and evidence collection. Use when the user explicitly requests end-to-end testing via /e2e-test command. Works for web apps, APIs, CLIs, and any project with user-facing interfaces."
---

# End-to-End Testing

## Philosophy

E2E testing is a research problem, not a scripting problem. Most test gaps come from
incomplete journey discovery, not poor test code. This skill forces systematic coverage
through parallel research before any testing begins.

**This is a Flexible skill.** Adapt tool choices and evidence types to the project. The
phases and human checkpoints are rigid.

## When to Use

- User explicitly invokes `/e2e-test`
- Need systematic coverage of all user journeys
- Pre-launch QA pass
- Setting up E2E test infrastructure for a project

## When NOT to Use

- **Unit or integration tests** — use `test-driven-development` directly
- **Debugging a specific failure** — use `systematic-debugging`
- **Quick smoke test** — just run the existing test suite
- **No user-facing interface** — libraries and packages don't need E2E testing

## Phase 0: Pre-flight

### Detect Project Type

Investigate the codebase to determine:

1. **Interface type** — web app, API, CLI tool, desktop app, or hybrid
2. **Tech stack** — framework, language, package manager
3. **Existing E2E framework** — Playwright, Cypress, Selenium, agent-browser, test scripts, or nothing
4. **State layer** — database (type + client), file system, external APIs, in-memory
5. **How to run** — dev server command, API start command, CLI entry point

### Tool Recommendation

If no E2E framework is detected, recommend based on project type:

| Stack | Recommendation | Rationale |
|-------|---------------|-----------|
| Web (React/Next/Vue/Svelte/etc.) | Playwright | Most universal, headless, best maintained |
| Web + Cypress already configured | Cypress | Don't switch what works |
| API-only (no frontend) | curl/httpie + test scripts | No browser needed |
| CLI tool | Direct command execution | Just run the commands and check output |
| Any + Claude-in-Chrome MCP available | Claude-in-Chrome | Already connected, zero install |

**Never auto-install.** Present the recommendation and let the human decide. If they say
"just do exploratory without a framework," that works — Path B needs no framework.

### Present to Human

> **Pre-flight summary:**
> - Project type: [web app / API / CLI / etc.]
> - Stack: [framework, language]
> - Existing E2E: [framework name or "none detected" + recommendation]
> - State layer: [DB type, other state stores]
> - Start command: [command]
>
> **Please confirm:**
> 1. Is the application running and accessible? (Web: provide URL. API: provide base URL. CLI: confirm installed.)
> 2. Any areas to focus on or skip?

**STOP. Wait for human response before proceeding.**

## Phase 1: Parallel Research

Launch **three sub-agents simultaneously** using the Agent tool. All three run in parallel.

### Sub-agent 1: Structure & Journeys

> Research this codebase thoroughly. Return a structured summary:
>
> 1. **Every user-facing entry point** — routes/pages (web), endpoints (API), commands/flags (CLI), screens (desktop)
> 2. **Authentication** — if the app has protected areas, how to create a test account or authenticate (from .env.example, seed data, or sign-up flow). DO NOT read .env directly.
> 3. **Every user journey** — complete flows a user can take from start to finish. For each:
>    - Name and description
>    - Ordered steps (what the user does)
>    - Expected outcomes (what should happen)
>    - Prerequisites (auth, prior data, config)
> 4. **Interactive elements** — forms, modals, dropdowns, toggles, file uploads, and other elements requiring testing
>
> Be exhaustive. Testing will only cover what you identify here.

### Sub-agent 2: State Layer & Data Flows

> Research this codebase's data and state layer. Read .env.example (NOT .env) for connection details. Return:
>
> 1. **State stores** — database type, file paths, external services, cache layers
> 2. **Schema** — tables/collections, fields, types, relationships (DB); file formats and locations (file-based); endpoint contracts (API state)
> 3. **Data flows per user action** — for each user-facing action, what state changes? Records created, updated, deleted?
> 4. **Verification commands** — for each data flow, the exact command to verify state is correct after the action

### Sub-agent 3: Risk Analysis

> Analyze this codebase for areas most likely to fail during E2E testing. Focus on:
>
> 1. **Error handling gaps** — missing try/catch, unhandled rejections, no error states in UI
> 2. **Edge cases** — empty states, boundary values, concurrent operations, long inputs
> 3. **Integration points** — where components/services connect (these break most often)
> 4. **Known fragility** — complex conditionals, deeply nested state, timing-dependent code
>
> Return a prioritized list with file paths. These become targeted test scenarios.

**Wait for all three sub-agents to complete.**

### Present Findings to Human

Synthesize the three reports:

> **Research Complete**
>
> **Journeys discovered:** [count]
> [List each journey name + 1-line description]
>
> **State flows mapped:** [count data-modifying actions]
>
> **Risk areas identified:** [count]
> [Top 3-5 risks with file paths]
>
> **Gaps or unknowns:**
> [Anything the sub-agents couldn't determine]
>
> Are there journeys missing from this list? Any areas to prioritize or skip?

**STOP. Wait for human response before proceeding.**

## Phase 2: Coverage Plan

Using research findings, create a task (TaskCreate) for each user journey:

- **subject:** Journey name (e.g., "Test user registration flow")
- **description:** Steps to execute, expected outcomes, state to verify, associated risks from Sub-agent 3
- **activeForm:** Present continuous (e.g., "Testing user registration flow")

Add a final task: "Cross-cutting concerns" covering error states, edge cases, and responsive/viewport testing (if web).

### Present Plan and Ask for Execution Approach

> **Test Plan: [count] journeys + cross-cutting**
>
> [Numbered list of task subjects]
>
> **How should we execute?**
> - **Write permanent tests** — creates test files using your E2E framework, follows TDD discipline. Durable, runs in CI.
> - **Exploratory session** — systematic manual testing with evidence capture. Immediate and thorough, but ephemeral.
> - **Mix** — write tests for critical paths, explore the rest.

**STOP. Wait for human to choose before proceeding.**

## Phase 3: Test Execution

Mark each task `in_progress` (TaskUpdate) before starting. Complete one journey fully before moving to the next.

### Path A: Write Permanent Tests

For each journey task:

1. Follow `test-driven-development` discipline (RED-GREEN-REFACTOR)
2. Write a test file using the project's E2E framework
3. **RED:** Write test describing journey steps and assertions — verify it fails
4. **GREEN:** If test fails due to app bugs (not test bugs), fix the app code
5. Verify the test passes
6. Mark task `completed` and move to next journey

### Path B: Exploratory Testing

For each journey task:

1. **Execute each step** in the journey using available tools
2. **Collect evidence** at each step:
   - Web: screenshots, console output, network responses
   - API: response bodies, status codes, headers
   - CLI: stdout/stderr, exit codes, file system changes
   - All: state verification using Sub-agent 2's commands
3. **Verify state** after every data-modifying action
4. **Check risks** flagged by Sub-agent 3 at relevant steps
5. **When an issue is found:**
   - Document: expected vs actual + evidence
   - Fix the code
   - Re-execute the failing step
   - Collect new evidence confirming the fix
6. Mark task `completed` when all steps verified with evidence

### Cross-cutting Concerns (final task)

After all journey testing:

- **Error states:** trigger validation errors, network failures, empty data scenarios
- **Edge cases:** from Sub-agent 3's risk analysis — test each flagged area
- **Responsive testing** (web only): key pages at mobile (375x812), tablet (768x1024), desktop (1440x900)

## Phase 4: Report

Before generating the report, apply `verification-before-completion` — confirm every task has evidence of completion.

### Summary (always output)

```
## E2E Testing Complete

**Approach:** [permanent tests / exploratory / mixed]
**Journeys Tested:** [count]
**Issues Found:** [count] ([fixed] fixed, [remaining] remaining)

### Issues Fixed During Testing
- [Description] — [file:line]

### Remaining Issues
- [Description] — [severity: high/medium/low] — [file:line]

### Risk Areas Validated
- [From Sub-agent 3: confirmed/not reproduced]

### Evidence
[Where screenshots/logs/test files were saved]
```

### Detailed Report (ask first)

> Export full report to `e2e-test-report.md`? Includes per-journey breakdowns, evidence references, state verification results, and risk analysis. Useful for PR descriptions or follow-up work.

## Red Flags — You're Skipping Discipline

| Thought | Reality |
|---------|---------|
| "I know the app, skip research" | Research finds journeys you forgot. Always run Phase 1. |
| "Just test the happy path" | Edge cases and error states are where bugs live. Test cross-cutting. |
| "Screenshots are enough evidence" | State verification catches data bugs that look fine in the UI. |
| "I'll fix issues after all testing" | Fix-and-reverify immediately. Cascading failures waste time. |
| "The research sub-agents are overkill" | 3 agents in parallel takes the same time as 1. More coverage, same cost. |
| "Skip the plan, just start testing" | Phase 2 prevents random testing. Systematic beats ad-hoc. |
