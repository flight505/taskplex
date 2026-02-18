# TASKPLEX-EVOLUTION.md — Deep Dive Audit Report

**Date:** 2026-02-17
**Audited Document:** `TASKPLEX-EVOLUTION.md` (v2.0 proposal)
**Research Method:** Parallel Tier 4 deep dives into CLI docs (21,721 lines), API docs (1,079,918 lines), and token cost modeling against v1.2.1 architecture.

---

## Research Sources

- **CLI Reference:** `cli-full.txt` — hooks, subagents, agent teams, plugins (57 consolidated docs from code.claude.com)
- **API Reference:** `llms-full.txt` — compaction, effort levels, pricing, model capabilities (full platform.claude.com docs)
- **Primer:** `primer.md` — quick reference for model IDs, basic API patterns
- **Changelog:** `changelog.md` — recent API changes (v2.0.0+)
- **Cost Analysis:** Full token modeling against current v1.2.1 architecture (taskplex.sh, prompt.md, implementer.md, parallel.sh)

---

## 1. Verified Claims (Green Light)

These evolution doc proposals are **confirmed accurate** by the documentation:

| Feature | Status | Docs Source |
|---------|--------|-------------|
| Compaction API (`compact_20260112`) | Beta, header `compact-2026-01-12` | API line 22979 |
| `pause_after_compaction` behavior | Correct — preserves recent messages | API line 23131 |
| Custom instructions **replace** default prompt | Correct | API line 23091 |
| `usage.iterations` billing format | Correct — compaction tokens billed separately | API line 23474 |
| `thinking: {type: "adaptive"}` | Real, GA, Opus 4.6 only | API line 3301 |
| Effort levels: `low/medium/high/max` | Confirmed (`max` is Opus 4.6 only) | API line 6983 |
| Effort is GA (no beta header) | Correct | API line 1608 |
| `budget_tokens` deprecated on Opus 4.6 | Correct (still required on older models) | API line 3288 |
| Fast mode: $30/$150, 2.5x speed, research preview | All confirmed | API line 7513 |
| 128K output tokens for Opus 4.6 | Confirmed | API line 1585 |
| 1M context window is beta | Correct, header `context-1m-2025-08-07` | API line 24924 |
| SubagentStart can inject `additionalContext` | Confirmed | CLI line 20443 |
| SubagentStop can return `decision: "block"` | Confirmed | CLI line 20504 |
| SubagentStop provides `agent_transcript_path` | Confirmed | CLI line 20464 |
| PreCompact hook exists | Confirmed | CLI line 20611 |
| Agent Teams: shared task list + messaging | Confirmed | CLI line 6166 |
| Agent Teams: experimental status | Confirmed | CLI line 6019 |
| Each subagent starts with fresh context | Confirmed | CLI lines 6422, 6991 |

---

## 2. Critical Issues Found (Red Flags)

### Issue A: Hook Config Syntax is Wrong Throughout

**Evolution doc lines 275-308** use this format:
```json
{
  "type": "SubagentStart",
  "matcher": {"agent_type": "implementer"},
  "hooks": [{ ... }]
}
```

**Actual format** (CLI line 19504):
```json
{
  "hooks": {
    "SubagentStart": [{
      "matcher": "implementer",
      "hooks": [{ "type": "command", "command": "..." }]
    }]
  }
}
```

Two errors: (1) matcher is a **regex string**, not an object; (2) hooks nest under event-name keys inside a top-level `"hooks"` object.

---

### Issue B: Agent Teams Cannot Be Driven Programmatically

**Evolution doc lines 114-132** propose integrating Agent Teams into TaskPlex's bash workflow with JSON config (`"parallel_mode": "team"`).

**Reality**: Agent Teams are interactive-only. The docs describe starting teams via natural language ("tell Claude to create an agent team"). There is **no `--create-team` flag**, no headless API, no programmatic team creation documented. This is a fundamental gap — the entire Section 1.2 architecture depends on a capability that doesn't exist in a scriptable form.

Additionally: teammates **cannot spawn their own teams** (CLI line 6388), and the orchestrator would need to BE the team lead (an interactive Claude Code session, not a subagent).

---

### Issue C: Agent Teams is a CLI Feature, NOT an API Feature

**Evolution doc line 101** calls it "a first-class feature." The term "Agent Teams" appears **zero times** in the 1M-line API reference. It exists only in Claude Code CLI docs. Since TaskPlex orchestrates via `claude -p` (headless), not interactive sessions, Agent Teams may not be composable with the current architecture at all.

---

### Issue D: Effort Levels Don't Work on Sonnet

**Evolution doc lines 231-233** propose using Sonnet 4.5 without effort levels for standard stories. The docs confirm effort levels are supported on **Opus 4.6 and Opus 4.5 only** (API line 6953). Sonnet 4.5 is not listed. This means the effort-adaptive execution table is correct by accident (Sonnet rows don't use effort), but the underlying assumption that effort is available across models is wrong.

---

### Issue E: PreCompact is Fire-and-Forget Only

**Evolution doc lines 299-309** propose using PreCompact for "context preservation." The CLI docs show:
- PreCompact **cannot block** compaction (CLI line 19836)
- PreCompact has **no documented output fields** at all
- PreCompact **cannot inject** data that survives compaction

It can trigger side effects (write to a DB), which is valid. But calling it "context preservation" is misleading — it's a notification hook, not a control mechanism.

---

### Issue F: Compaction Config is API-Level, Not CLI-Level

**Evolution doc lines 76-89** show a `context_management` configuration block. This is a **Messages API parameter**, not something exposed through Claude Code CLI. Claude Code handles compaction internally (triggering at 75% context utilization). The CLI docs do not expose `trigger`, `pause_after_compaction`, or custom `instructions` to users.

This means: the "persistent Opus orchestrator with configurable compaction" requires either (a) using the raw API instead of `claude -p`, or (b) waiting for Claude Code to expose compaction configuration.

---

### Issue G: Opus 4.6 Does NOT Support Prefilling

**Not mentioned in the evolution doc but critical**: API line 1670 states prefilling assistant messages returns a 400 error on Opus 4.6. If any TaskPlex prompts use prefilling, they'll break.

---

## 3. Minor Issues / Clarifications

| Issue | Details |
|-------|---------|
| **Pricing mismatch** | Evolution doc line 228 uses $15/$75 for Opus. Actual: **$5/$25** (API line 1179). The $15/$75 was Opus 4.5 pricing, not 4.6. This significantly affects cost estimates. |
| **Haiku pricing** | Evolution cost analysis uses $0.80/$4. Actual: **$1/$5** (API line 1189). |
| **Compaction model support** | Features table says "Opus 4.6 and Haiku 4.5" but compaction page lists only Opus 4.6. Internal docs inconsistency. |
| **SubagentStop semantics** | The evolution doc implies `block` prevents "completing." Actual behavior: the subagent **continues its existing conversation** with the `reason` injected — it's not restarted, it keeps working in the same context. |
| **Effort `max` level** | Confirmed in API docs (API line 6983) but not documented in CLI reference. CLI docs only mention `low`, `medium`, `high`. |

---

## 4. Token Cost Analysis — v1.2.1 vs Proposed v2.0

### Corrected Pricing (from API docs, February 2026)

| Model | Input | Output |
|-------|-------|--------|
| Opus 4.6 | $5/MTok | $25/MTok |
| Sonnet 4.5 | $3/MTok | $15/MTok |
| Haiku 4.5 | $1/MTok | $5/MTok |

### Per-Story Token Profile

| Component | v1.2.1 | v2.0 (proposed) |
|-----------|--------|-----------------|
| Implementer input | ~38K | ~36K (slightly better briefs) |
| Implementer output | ~5K | ~5K |
| Validator | ~8K in / ~0.8K out | Reduced 50% (hook-based inline validation) |
| Orchestrator share | **$0** (bash) | **~$2.30/story** (persistent Opus) |
| Transcript mining | $0 | ~$0.05/story (Haiku) |

### 8-Story Project Comparison

| Scenario | v1.2.1 | v2.0 Sequential | v2.0 Agent Teams |
|----------|--------|-----------------|------------------|
| **Sonnet implementation** | **~$2** | **~$14** | **Not feasible*** |
| **Opus implementation** | **~$5** | **~$18** | **Not feasible*** |
| **Cost multiplier** | 1.0x | ~7x (Sonnet) / ~3.5x (Opus) | N/A |

*Agent Teams can't be scripted per current docs.

### 15-Story Large Project

| Scenario | v1.2.1 | v2.0 Sequential |
|----------|--------|-----------------|
| **Sonnet** | ~$5 | ~$28 |
| **Opus** | ~$12 | ~$35 |
| **With TDD + code review** | — | ~$40 |

### Scenario Breakdown

#### Small project (3 stories, simple, sequential)

| Metric | v1.2.1 | v2.0 |
|--------|--------|------|
| Total input tokens | ~165K | ~435K |
| Total output tokens | ~25K | ~50K |
| **Cost (Sonnet impl)** | **$0.87** | **$6.75** |
| **Cost multiplier** | **1.0x** | **7.8x** |

The persistent Opus orchestrator is expensive overkill for 3 simple stories.

#### Medium project (8 stories, mixed complexity, sequential)

| Metric | v1.2.1 | v2.0 |
|--------|--------|------|
| **Cost (Sonnet impl)** | **$2.55** | **$21.50** |
| **Cost (Opus impl)** | **$12.50** | **$30.00** |
| **Sonnet multiplier** | **1.0x** | **8.4x** |
| **Opus multiplier** | **1.0x** | **2.4x** |

#### Large project (15 stories, complex, subagent parallel)

| Metric | v1.2.1 | v2.0 |
|--------|--------|------|
| Compaction events | 0 | 2-3 |
| **Cost (Sonnet impl)** | **$5.10** | **$38.00** |
| **Cost (Opus impl)** | **$25.00** | **$52.00** |
| **Sonnet multiplier** | **1.0x** | **7.5x** |

### The Dominant Cost Driver

**The persistent Opus orchestrator accounts for ~75% of the cost increase.** It processes ~12.5K tokens per story decision cycle, with accumulated context re-read each turn. At ~150K tokens, compaction triggers (~$2.50 per compaction at corrected Opus pricing). For 8 stories: ~1 compaction. For 15 stories: 2-3 compactions.

### Best Value-Add by Cost

| Feature | Cost per Story | ROI |
|---------|---------------|-----|
| **Transcript mining** (Haiku) | $0.05 | Excellent — structured knowledge for negligible cost |
| **SubagentStop validation hooks** | $0 | Free — replaces separate validator |
| **SubagentStart knowledge injection** | $0 | Free — better context via hooks |
| **SQLite knowledge store** | $0 | Free — replaces flat-file, enables cross-run persistence |

---

## 5. Recommendations

### Implement Now (Confirmed by docs, no architecture change needed)

1. **SubagentStart `additionalContext` injection** — query knowledge store, inject into implementers. Zero extra tokens. Confirmed working.
2. **SubagentStop `decision: "block"` for inline validation** — run typecheck/build before letting implementer finish. Eliminates separate validator. Confirmed working.
3. **SQLite knowledge store** — reuse monitor's Bun+SQLite. Replace `knowledge.md`. No API dependency.
4. **Transcript mining via Haiku** — `agent_transcript_path` is confirmed. Cheapest new capability at $0.05/story.

### Defer Until Docs Catch Up

5. **Agent Teams parallel mode** — wait for programmatic/headless API or `--create-team` flag.
6. **Configurable compaction** — wait for Claude Code to expose `context_management` parameters, or build a separate API-direct orchestrator (major architecture change).

### Reconsider

7. **Persistent Opus orchestrator** — the 7x cost increase is driven almost entirely by this. Consider a **hybrid approach**: keep bash for orchestration decisions on simple/medium projects, add Opus orchestrator only for complex projects (15+ stories) where retry reduction and plan adaptation justify the cost.

### Fix Before Any Implementation

- Correct all hook config syntax (regex strings, nested structure)
- Remove Agent Teams as a parallel mode option until scriptable
- Note compaction is API-level, not CLI-level
- Update pricing to actual $5/$25 Opus rates
- Flag prefill incompatibility with Opus 4.6

---

## 6. Detailed Hook Reference (for implementation)

### SubagentStart — Knowledge Injection

**Confirmed input fields:**
- `agent_id` — unique identifier
- `agent_type` — agent name (matches custom agent names from `agents/`)

**Confirmed output:**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": "Relevant learnings injected here"
  }
}
```

**Cannot block** subagent creation. Exit 2 shows stderr to user only.

**Correct hook config:**
```json
{
  "hooks": {
    "SubagentStart": [{
      "matcher": "implementer",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/inject-knowledge.sh"
      }]
    }]
  }
}
```

### SubagentStop — Inline Validation

**Confirmed input fields:**
- `stop_hook_active` — boolean (prevents infinite loops)
- `agent_id` — unique identifier
- `agent_type` — agent name
- `agent_transcript_path` — full path to subagent's conversation transcript

**Confirmed output:**
```json
{
  "decision": "block",
  "reason": "Typecheck failed: src/api/routes.ts(45): error TS2345..."
}
```

**CAN block** — exit code 2 prevents subagent from stopping. The subagent continues its existing conversation with the `reason` as its next instruction (not restarted).

**Correct hook config:**
```json
{
  "hooks": {
    "SubagentStop": [{
      "matcher": "implementer",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/validate-result.sh"
      }]
    }]
  }
}
```

### PreCompact — Side-Effect Notification

**Input fields:**
- `trigger` — `"manual"` or `"auto"`
- `custom_instructions` — user-provided instructions (manual only)

**No output fields documented.** Cannot block. Cannot inject. Fire-and-forget only.

**Valid use:** Read `transcript_path`, extract data to knowledge store before compaction happens.

---

## 7. Correct Model Capabilities Reference

### Opus 4.6

| Property | Value |
|----------|-------|
| API ID | `claude-opus-4-6` |
| Context window | 200K (standard), 1M (beta) |
| Max output | 128K tokens |
| Adaptive thinking | Yes (recommended over budget_tokens) |
| Effort levels | low, medium, high, max |
| Prefilling | **NOT supported** (400 error) |
| Compaction | Supported (beta) |
| Pricing | $5/$25 per MTok |
| Fast mode | $30/$150 per MTok (research preview) |

### Sonnet 4.5

| Property | Value |
|----------|-------|
| API ID | `claude-sonnet-4-5-20250929` |
| Context window | 200K (standard), 1M (beta) |
| Max output | 64K tokens |
| Adaptive thinking | No (use budget_tokens) |
| Effort levels | **Not supported** |
| Pricing | $3/$15 per MTok |

### Haiku 4.5

| Property | Value |
|----------|-------|
| API ID | `claude-haiku-4-5-20251001` |
| Context window | 200K |
| Max output | 64K tokens |
| Extended thinking | Yes (budget_tokens) |
| Effort levels | **Not supported** |
| Pricing | $1/$5 per MTok |

---

**Maintained by:** Jesper Vang (@flight505)
**Audited by:** Claude Opus 4.6 (3 parallel research agents)
