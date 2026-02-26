---
name: brainstorm
description: "Use when a user describes a feature or project BEFORE jumping to PRD generation. Triggers on: novel features, ambiguous requirements, architecture-level decisions, or when the right approach isn't obvious. Challenges assumptions and explores alternatives."
context: fork
agent: architect
model: sonnet
disable-model-invocation: false
allowed-tools: Read, Grep, Glob
---

# Brainstorm

Challenge assumptions and explore alternatives before committing to a PRD.

## When to Use

- User describes a feature and the best approach isn't obvious
- Multiple valid architectures could solve the problem
- Requirements are ambiguous or have hidden complexity
- User says "I want to build X" but hasn't considered trade-offs

**Skip brainstorming when:** Requirements are crystal clear, scope is tiny (1-2 files), user explicitly says "just do it".

## The Process

### 1. Understand Context (Codebase-Aware)

Before proposing anything, explore the existing codebase:
- Grep for related patterns, modules, or prior art
- Read key files in the affected area
- Identify existing conventions and constraints

### 2. Challenge Assumptions (Devil's Advocate)

For each assumption in the user's description, ask:
- **Is this the right problem?** Could the real problem be upstream?
- **Is this the right scope?** Too big? Too small? Wrong boundary?
- **Is this the right approach?** What alternatives exist?

### 3. Explore Alternatives

Present 2-3 distinct approaches. For each:
- **Approach name** (one line)
- **How it works** (2-3 sentences)
- **Pros** (bullet list)
- **Cons** (bullet list)
- **Fits existing codebase?** (yes/no with reason)

### 4. Produce Design Brief

Output a concise Design Brief (~1 page):

```markdown
# Design Brief: [Feature Name]

## Problem Statement
[What we're actually solving — may differ from initial description]

## Chosen Approach
[Selected approach with rationale]

## Rejected Alternatives
- [Alt 1]: Rejected because [reason]
- [Alt 2]: Rejected because [reason]

## Constraints
- [Constraint 1 from codebase exploration]
- [Constraint 2 from requirements]

## Open Questions
- [Unresolved question that PRD should address]

## Recommendation
Proceed to PRD generation with [chosen approach].
```

## Key Rules

- **Never skip codebase exploration.** Proposals without grep/read are speculation.
- **Always present alternatives.** Even if one is clearly better, show why.
- **Keep it brief.** The Design Brief is ONE page, not a thesis.
- **Don't implement.** Output is a Design Brief, not code.

## After Brainstorming

Hand off to `taskplex:prd-generator` with the Design Brief as input. The PRD generator incorporates the chosen approach and constraints.
