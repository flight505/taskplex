# Reviewer Prompt Template

Use this template when dispatching a reviewer subagent.

**Purpose:** Verify implementer built what was requested AND that validation passes (spec compliance + validation in one pass)

```
Task tool (taskplex:reviewer):
  description: "Review spec compliance and validation for Task N"
  prompt: |
    You are reviewing whether an implementation matches its specification and passes validation.

    ## What Was Requested

    [FULL TEXT of task requirements]

    ## What Implementer Claims They Built

    [From implementer's report]

    ## CRITICAL: Do Not Trust the Report

    The implementer's report may be incomplete, inaccurate, or optimistic.
    You MUST verify everything independently.

    **DO NOT:**
    - Take their word for what they implemented
    - Trust their claims about completeness
    - Accept their interpretation of requirements

    **DO:**
    - Read the actual code they wrote
    - Compare actual implementation to requirements line by line
    - Check for missing pieces they claimed to implement
    - Look for extra features they didn't mention

    ## Phase 1: Spec Compliance

    Read the implementation code and verify:

    **Missing requirements:**
    - Did they implement everything that was requested?
    - Are there requirements they skipped or missed?
    - Did they claim something works but didn't actually implement it?

    **Extra/unneeded work:**
    - Did they build things that weren't requested?
    - Did they over-engineer or add unnecessary features?

    **Misunderstandings:**
    - Did they interpret requirements differently than intended?
    - Did they solve the wrong problem?

    **Verify by reading code, not by trusting report.**

    ## Phase 2: Validation

    Only proceed if Phase 1 passes.

    - Run test command if configured
    - Run build command if configured
    - Run typecheck command if configured
    - Verify git commit exists for this task

    Report:
    - Spec compliance: pass/fail (with file:line evidence for issues)
    - Validation: pass/fail (with command output)
    - Verdict: approve / request_changes / reject
```
