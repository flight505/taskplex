# Claude Search Optimization (CSO) Guide

**Critical for discovery:** Future Claude needs to FIND your skill.

## 1. Rich Description Field

**Purpose:** Claude reads description to decide which skills to load for a given task. Make it answer: "Should I read this skill right now?"

**Format:** Hybrid pattern — start with what the skill does (third-person), then trigger conditions.

**The hybrid pattern:**
- First clause: what the skill does (third-person, concise — NOT a workflow summary)
- Then: "Use when..." trigger conditions
- Result: Claude understands both relevance AND timing

```yaml
# ✅ GOOD: Hybrid — what it does + when to use it
description: "Enforces RED-GREEN-REFACTOR discipline for all implementation work. Use when implementing any feature, bugfix, or refactor, before writing implementation code."

# ✅ GOOD: Hybrid — what it does + when to use it
description: "Investigates root cause through 4-phase analysis before any fix attempt. Use when encountering any bug, test failure, or unexpected behavior."

# ❌ BAD: Summarizes workflow — Claude may follow this instead of reading skill
description: "Use when executing plans - dispatches subagent per task with code review between tasks"

# ❌ BAD: Too much process detail
description: "Use for TDD - write test first, watch it fail, write minimal code, refactor"

# ❌ BAD: Only trigger, no context about what it does
description: "Use when implementing features"
```

**CRITICAL: Never summarize the workflow/process in descriptions.** Testing revealed that when a description summarizes the skill's workflow, Claude may follow the description as a shortcut instead of reading the full skill content. A description saying "code review between tasks" caused Claude to do ONE review, even though the skill's flowchart clearly showed TWO reviews.

When the description was changed to triggers-only (no workflow summary), Claude correctly read the flowchart and followed the two-stage review process.

**The trap:** Descriptions that summarize workflow create a shortcut Claude will take. The skill body becomes documentation Claude skips.

**Content guidelines:**
- Use concrete triggers, symptoms, and situations that signal this skill applies
- Describe the *problem* (race conditions, inconsistent behavior) not *language-specific symptoms* (setTimeout, sleep)
- Keep triggers technology-agnostic unless the skill itself is technology-specific
- Write in third person (injected into system prompt)
- Be "pushy" — Claude tends to undertrigger skills, so include edge cases

## 2. Keyword Coverage

Use words Claude would search for:
- Error messages: "Hook timed out", "ENOTEMPTY", "race condition"
- Symptoms: "flaky", "hanging", "zombie", "pollution"
- Synonyms: "timeout/hang/freeze", "cleanup/teardown/afterEach"
- Tools: Actual commands, library names, file types

## 3. Descriptive Naming

**Use active voice, verb-first:**
- ✅ `creating-skills` not `skill-creation`
- ✅ `condition-based-waiting` not `async-test-helpers`

**Gerunds (-ing) work well for processes:**
- `creating-skills`, `testing-skills`, `debugging-with-logs`
- Active, describes the action you're taking

**Name by what you DO or core insight:**
- ✅ `condition-based-waiting` > `async-test-helpers`
- ✅ `using-skills` not `skill-usage`
- ✅ `flatten-with-flags` > `data-structure-refactoring`
- ✅ `root-cause-tracing` > `debugging-techniques`

## 4. Token Efficiency (Critical)

**Problem:** Getting-started and frequently-referenced skills load into EVERY conversation. Every token counts.

**Target word counts:**
- Getting-started workflows: <150 words each
- Frequently-loaded skills: <200 words total
- Other skills: <500 words (still be concise)

**Techniques:**

**Move details to tool help:**
```bash
# ❌ BAD: Document all flags in SKILL.md
search-conversations supports --text, --both, --after DATE, --before DATE, --limit N

# ✅ GOOD: Reference --help
search-conversations supports multiple modes and filters. Run --help for details.
```

**Use cross-references:**
```markdown
# ❌ BAD: Repeat workflow details
When searching, dispatch subagent with template...
[20 lines of repeated instructions]

# ✅ GOOD: Reference other skill
Always use subagents (50-100x context savings). REQUIRED: Use [other-skill-name] for workflow.
```

**Compress examples:**
```markdown
# ❌ BAD: Verbose example (42 words)
your human partner: "How did we handle authentication errors in React Router before?"
You: I'll search past conversations for React Router authentication patterns.
[Dispatch subagent with search query: "React Router authentication error handling 401"]

# ✅ GOOD: Minimal example (20 words)
Partner: "How did we handle auth errors in React Router?"
You: Searching...
[Dispatch subagent → synthesis]
```

**Eliminate redundancy:**
- Don't repeat what's in cross-referenced skills
- Don't explain what's obvious from command
- Don't include multiple examples of same pattern

**Verification:**
```bash
wc -w skills/path/SKILL.md
# getting-started workflows: aim for <150 each
# Other frequently-loaded: aim for <200 total
```

## 5. Cross-Referencing Other Skills

**When writing documentation that references other skills:**

Use skill name only, with explicit requirement markers:
- ✅ Good: `**REQUIRED SUB-SKILL:** Use taskplex:test-driven-development`
- ✅ Good: `**REQUIRED BACKGROUND:** You MUST understand taskplex:systematic-debugging`
- ❌ Bad: `See skills/testing/test-driven-development` (unclear if required)
- ❌ Bad: `@skills/testing/test-driven-development/SKILL.md` (force-loads, burns context)

**Why no @ links:** `@` syntax force-loads files immediately, consuming 200k+ context before you need them.
