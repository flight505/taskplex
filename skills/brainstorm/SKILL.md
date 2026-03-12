---
name: brainstorm
description: "Challenges assumptions and explores design alternatives through collaborative dialogue. Use when requirements are ambiguous, architecture decisions need exploration, or the user wants to think through a problem before coding."
argument-hint: "[feature-description]"
---

# Brainstorming Ideas Into Designs

Help turn ambiguous ideas into clear designs through collaborative dialogue.

## When This Skill Applies

Only for **Complex tier** tasks — where requirements are unclear, multiple valid architectures exist, or the user explicitly asks to brainstorm. If the requirements are clear and the work is just multi-file implementation, skip this and go straight to `writing-plans`.

## Process

1. **Explore project context** — check files, docs, recent commits
2. **Ask clarifying questions** — one at a time, purpose/constraints/success criteria
3. **Propose 2-3 approaches** — with trade-offs and your recommendation
4. **Present design** — scale detail to complexity, get user approval
5. **Hand off** — invoke `writing-plans` to create the implementation plan

## Guidelines

- **One question at a time** — don't overwhelm with lists
- **Multiple choice preferred** — easier to answer than open-ended
- **YAGNI ruthlessly** — remove features that aren't needed yet
- **Scale the design** — a few sentences for simple decisions, paragraphs for novel architecture
- **No separate design doc** — the conversation IS the design. The plan doc captures what matters.
- **Lead with your recommendation** — present options, but say which you'd pick and why

## After Approval

Invoke `taskplex:writing-plans` to create the implementation plan. Pass the key design decisions as context — the plan is the single artifact that captures both design and execution.

Do NOT invoke any other skill. `writing-plans` is the only next step.
