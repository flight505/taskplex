---
name: writing-skills
description: Use when creating new skills, editing existing skills, or verifying skills work before deployment
---

# Writing Skills

## Overview

**Writing skills IS Test-Driven Development applied to process documentation.**

You write test cases (pressure scenarios with subagents), watch them fail (baseline behavior), write the skill (documentation), watch tests pass (agents comply), and refactor (close loopholes).

**Core principle:** If you didn't watch an agent fail without the skill, you don't know if the skill teaches the right thing.

**REQUIRED BACKGROUND:** You MUST understand taskplex:taskplex-tdd before using this skill.

## When to Create a Skill

**Create when:** Technique wasn't intuitively obvious, would reference again across projects, applies broadly.

**Don't create for:** One-off solutions, standard practices, project-specific conventions (use CLAUDE.md), enforceable with validation/regex.

## Skill Types

- **Technique:** Concrete method with steps (condition-based-waiting, root-cause-tracing)
- **Pattern:** Way of thinking about problems (flatten-with-flags)
- **Reference:** API docs, syntax guides, tool documentation

## Directory Structure

```
skills/skill-name/
  SKILL.md              # Main reference (required)
  supporting-file.*     # Only if needed (heavy reference or reusable tools)
```

## SKILL.md Structure

**Frontmatter (YAML):** Only `name` and `description` (max 1024 chars total).
- `name`: Letters, numbers, hyphens only
- `description`: Start with "Use when..." — triggering conditions ONLY, never summarize workflow

```yaml
# BAD: Summarizes workflow — Claude follows description instead of reading skill
description: Use when executing plans - dispatches subagent per task with code review

# GOOD: Just triggering conditions
description: Use when executing implementation plans with independent tasks in the current session
```

**Body sections:** Overview → When to Use → Core Pattern → Quick Reference → Implementation → Common Mistakes

## Claude Search Optimization (CSO)

**Description = WHEN to use, NOT WHAT it does.** Testing confirmed: workflow summaries in descriptions cause Claude to shortcut the skill body.

**Keywords:** Use words Claude searches for — error messages, symptoms, synonyms, tool names.

**Naming:** Active voice, verb-first (`creating-skills` not `skill-creation`).

**Token targets:** Getting-started <150 words, frequently-loaded <200, others <500.

**Cross-references:** Use `**REQUIRED:** taskplex:skill-name` — never `@` links (force-loads 200k+ context).

## Flowchart Usage

Use flowcharts ONLY for non-obvious decision points. Never for reference material, code examples, or linear instructions.

## The Iron Law

```
NO SKILL WITHOUT A FAILING TEST FIRST
```

Applies to NEW skills AND EDITS. Write skill before testing? Delete it. Start over.

**No exceptions:** Not for "simple additions", "just adding a section", or "documentation updates".

## RED-GREEN-REFACTOR for Skills

### RED: Baseline Test
Run pressure scenario WITHOUT skill. Document: choices, rationalizations (verbatim), pressures that triggered violations.

### GREEN: Write Minimal Skill
Address those specific rationalizations. Run same scenarios WITH skill — agent should comply.

### REFACTOR: Close Loopholes
New rationalization? Add explicit counter. Re-test until bulletproof.

**Full testing methodology:** See @testing-skills-with-subagents.md.

## Bulletproofing Discipline Skills

1. **Close every loophole explicitly** — don't just state the rule, forbid specific workarounds
2. **Address "spirit vs letter"** — "Violating the letter IS violating the spirit"
3. **Build rationalization table** from baseline testing — every excuse gets a counter
4. **Create red flags list** for agent self-checking

## Testing by Skill Type

| Type | Test With | Success Criteria |
|------|-----------|-----------------|
| Discipline | Pressure scenarios (time + sunk cost + exhaustion) | Follows rule under maximum pressure |
| Technique | Application + variation + missing-info scenarios | Successfully applies to new scenario |
| Pattern | Recognition + application + counter-examples | Correctly identifies when/how to apply |
| Reference | Retrieval + application + gap testing | Finds and correctly applies information |

## Common Rationalizations for Skipping Tests

| Excuse | Reality |
|--------|---------|
| "Skill is obviously clear" | Clear to you ≠ clear to agents. Test it. |
| "Testing is overkill" | Untested skills have issues. Always. |
| "I'll test if problems emerge" | Test BEFORE deploying. |
| "No time to test" | Deploying untested wastes more time fixing later. |

## Skill Creation Checklist

**RED:** Create pressure scenarios → Run WITHOUT skill → Document baseline failures

**GREEN:** Write minimal skill addressing specific failures → Run WITH skill → Verify compliance

**REFACTOR:** Find new rationalizations → Add counters → Build rationalization table → Re-test

**Quality:** Descriptive name → Rich description (triggers only) → Keywords → Quick reference table → One excellent example

**Deploy:** Commit and push. Test EACH skill before moving to next.
