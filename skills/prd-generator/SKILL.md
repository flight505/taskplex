---
name: prd-generator
description: "Generate a Product Requirements Document (PRD) for a new feature. Use when planning a feature, building something new, implementing multi-file changes, or when a bug fix has unclear scope. Triggers on: build X, add Y, implement Z, plan this feature, create a prd, requirements for, spec out."
context: fork
agent: Explore
model: sonnet
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Write, AskUserQuestion
---

# PRD Generator

Create detailed Product Requirements Documents that are clear, actionable, and suitable for implementation.

## The Job

1. Receive a feature description from the user
2. Ask 3-5 essential clarifying questions (with lettered options)
3. Generate a structured PRD based on answers
4. Save to `tasks/prd-[feature-name].md`

**Important:** Do NOT start implementing. Just create the PRD.

## Step 1: Clarifying Questions

Ask only critical questions where the initial prompt is ambiguous. Focus on:
- **Problem/Goal:** What problem does this solve?
- **Core Functionality:** What are the key actions?
- **Scope/Boundaries:** What should it NOT do?
- **Success Criteria:** How do we know it's done?

Format with lettered options so users can respond "1A, 2C, 3B".

## Step 2: PRD Structure

### Required Sections
1. **Introduction/Overview** — Feature description and problem it solves
2. **Goals** — Specific, measurable objectives (bullet list)
3. **User Stories** — Each with title, description, acceptance criteria, dependencies
4. **Functional Requirements** — Numbered (FR-1, FR-2, ...), explicit and unambiguous
5. **Non-Goals** — What this feature will NOT include
6. **Success Metrics** — How success is measured
7. **Open Questions** — Remaining areas needing clarification

### Optional Sections
- Design Considerations (UI/UX, mockups, reusable components)
- Technical Considerations (constraints, integrations, performance)

## User Story Guidelines

**Format:**
```markdown
### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Specific verifiable criterion
  - **Must verify:** `[command or condition]`
  - **Expected:** What success looks like
- [ ] Typecheck passes
  - **Must verify:** `npm run typecheck` or `pyright --project .`
- [ ] [UI stories] Verify in browser
  - **Must verify:** Navigate to page and test interaction

**Depends on:** US-XXX (optional)
**Implementation hint:** Check if US-XXX already implemented this. (optional)
```

### Story Size Rules
- **Target:** 3-5 acceptance criteria per story
- **Maximum:** 6 criteria — if more, MUST split
- **Simple features (≤4 criteria):** One full-stack story is fine
- **Complex features (>4 criteria):** Split into layer-specific stories

### How to Split Large Features

**By Responsibility:**
- ❌ "Add [feature]" → ✅ Data model → API → UI components

**By User Journey:**
- ❌ "Build [workflow]" → ✅ Step 1 → Step 2 → Step 3

**By Complexity:**
- ❌ "Add advanced [feature]" → ✅ Basic functionality → Configuration → Edge cases

### Criteria Requirements
- Each criterion MUST include "Must verify: [command]" with specific verification
- Avoid vague criteria ("Works correctly") — specify HOW to verify
- Always include "Typecheck passes"
- UI stories always include "Verify in browser"

### Dependency Guidelines
- `Depends on: US-XXX` for hard blocking dependencies
- `Implementation hint` to prevent duplicate work
- Data model → backend logic → UI (natural order)

## Writing for Junior Developers

The PRD reader may be a junior developer or AI agent:
- Be explicit and unambiguous
- Avoid jargon or explain it
- Number requirements for easy reference
- Use concrete examples where helpful

## Output

- **Format:** Markdown (`.md`)
- **Location:** `tasks/`
- **Filename:** `prd-[feature-name].md` (kebab-case)

## Checklist

- [ ] Asked clarifying questions with lettered options
- [ ] Incorporated user's answers
- [ ] User stories are small (3-5 criteria) and specific
- [ ] Functional requirements are numbered and unambiguous
- [ ] Non-goals section defines clear boundaries
- [ ] Saved to `tasks/prd-[feature-name].md`
