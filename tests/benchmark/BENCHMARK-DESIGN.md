# TaskPlex vs Superpowers — Benchmark Design

**Version:** 1.0.0
**Date:** 2026-02-26
**Status:** Draft

---

## Goal

Build a reproducible scoring system that:
1. Compares TaskPlex (v3.1.0) against Superpowers (v4.3.1) across multiple quality dimensions
2. Tracks TaskPlex regression/improvement across versions
3. Identifies specific areas where each plugin excels or falls short
4. Uses statistical rigor for A/B comparison (Wilcoxon signed-rank, n≥30 stories)

---

## Component Inventory Comparison

| Dimension | Superpowers v4.3.1 | TaskPlex v3.1.0 | Delta |
|-----------|-------------------|-----------------|-------|
| Skills | 14 | 16 | +2 (prd-generator, prd-converter, failure-analyzer, using-taskplex, taskplex-tdd, taskplex-verify vs brainstorming) |
| Agents | 1 (code-reviewer) | 6 (implementer, validator, spec-reviewer, code-reviewer, reviewer, merger) | +5 |
| Hook Events | 1 (SessionStart) | 7 (Stop, TaskCompleted, SubagentStart, SubagentStop, PostToolUse, PreCompact, SessionStart, SessionEnd) | +6 |
| Hook Handlers | 1 | 13 | +12 |
| Commands | 3 (brainstorm, write-plan, execute-plan) | 1 (start) | -2 |
| Scripts | ~2 (run-hook.cmd, skills-core.js) | 7 main + 5 test | +10 |
| Tests | unknown | 5 test scripts | — |

---

## Scoring Framework: Decision Quality (DQ) Score

Adapted from Drammeh 2025 (arxiv:2511.15755) and Agent-as-a-Judge (Zhuge et al. 2024, arxiv:2410.10934).

### Four Sub-Dimensions

```
DQ = 0.35×D + 0.35×C + 0.20×A + 0.10×E
```

| Dimension | Weight | Symbol | What It Measures |
|-----------|--------|--------|------------------|
| **Discipline Compliance** | 0.35 | D | Were mandatory workflow steps executed? |
| **Output Correctness** | 0.35 | C | Do tests pass? Does the code work? |
| **Autonomy Rate** | 0.20 | A | Completed without human intervention? |
| **Efficiency** | 0.10 | E | Resource usage (turns, tokens, time) |

### Why These Weights

- **D + C = 0.70** — The core thesis: discipline AND correctness together are what matter. A plugin that enforces TDD but produces broken code is useless. A plugin that produces working code but skips review is risky.
- **A = 0.20** — Autonomy is the key differentiator for TaskPlex (PRD-driven execution, error recovery, stop guards). Worth significant weight.
- **E = 0.10** — Efficiency matters but is secondary. A correct, disciplined result in 200 turns is better than a wrong one in 50.

---

## Dimension 1: Discipline Compliance (D)

Score: 0.0 to 1.0

### Metrics

| Metric | ID | Score | How to Measure |
|--------|----|-------|----------------|
| TDD sequence observed | D1 | 0/1 | Git history shows test commit BEFORE implementation commit |
| Verification before completion | D2 | 0/1 | Test/build/typecheck ran before final commit |
| Code review executed | D3 | 0/1 | Code review agent/skill was invoked |
| Spec review executed | D4 | 0/1 | Spec compliance check ran (TaskPlex-specific) |
| Stop guard respected | D5 | 0/1 | Agent didn't exit prematurely when work remained |
| Skill routing gate fired | D6 | 0/1 | using-taskplex/using-superpowers loaded at session start |
| Debugging before fix | D7 | 0/1 | On failure: systematic debugging invoked before retry |

**Scoring:**
```
D = count(passed_metrics) / count(applicable_metrics)
```

Not all metrics apply to every story. D4 (spec review) and D5 (stop guard) only apply to TaskPlex. For fair comparison, use only shared metrics (D1–D3, D6–D7) in head-to-head scoring, and report TaskPlex-specific metrics separately.

### Measurement Method

**Trace-based:** Capture a structured event log during execution. Each event records:
```json
{
  "timestamp": "2026-02-26T12:00:00Z",
  "event": "skill_invoked",
  "skill": "taskplex-tdd",
  "story_id": "S001",
  "plugin": "taskplex"
}
```

Events to capture:
- `skill_invoked` — which skill, when
- `agent_dispatched` — which agent, for which story
- `hook_fired` — which hook event, matcher, result
- `test_executed` — command, pass/fail, timing
- `commit_created` — message, files changed, order relative to tests
- `completion_claimed` — did agent say "done"
- `human_intervention` — user had to step in

---

## Dimension 2: Output Correctness (C)

Score: 0.0 to 1.0

### Metrics

| Metric | ID | Score | How to Measure |
|--------|----|-------|----------------|
| Tests pass | C1 | 0/1 | `test_command` exits 0 |
| Build succeeds | C2 | 0/1 | `build_command` exits 0 |
| Typecheck passes | C3 | 0/1 | `typecheck_command` exits 0 |
| Acceptance criteria met | C4 | 0.0-1.0 | Fraction of AC items verified by validator |
| No regressions introduced | C5 | 0/1 | Pre-existing tests still pass |
| Code compiles/runs | C6 | 0/1 | No syntax errors in changed files |

**Scoring:**
```
C = (C1 + C2 + C3 + C4 + C5 + C6) / count(applicable_metrics)
```

### Measurement Method

Run the project's test/build/typecheck commands after each story completes. Compare test results against baseline (pre-story snapshot).

---

## Dimension 3: Autonomy Rate (A)

Score: 0.0 to 1.0

### Metrics

| Metric | ID | Score | How to Measure |
|--------|----|-------|----------------|
| Completed without human input | A1 | 0/1 | No `AskUserQuestion` or manual intervention |
| Error self-recovered | A2 | 0.0-1.0 | Fraction of errors that were auto-retried and resolved |
| No permission blocks | A3 | 0/1 | Agent didn't hit permission denial requiring user |
| Story fully autonomous | A4 | 0/1 | Story went from "pending" to "done" with zero human turns |

**Scoring:**
```
A = (A1 + A2 + A3 + A4) / 4
```

### Measurement Method

Count `human_intervention` events in the trace log. Track retry attempts and their outcomes.

---

## Dimension 4: Efficiency (E)

Score: 0.0 to 1.0

### Metrics

| Metric | ID | Score | How to Measure |
|--------|----|-------|----------------|
| Turn count | E1 | 0.0-1.0 | Normalized: `1 - min(turns/max_turns, 1)` |
| Token usage | E2 | 0.0-1.0 | Normalized: `1 - min(tokens/token_budget, 1)` |
| Wall clock time | E3 | 0.0-1.0 | Normalized: `1 - min(seconds/timeout, 1)` |
| Retry count | E4 | 0.0-1.0 | `1 - min(retries/max_retries, 1)` |

**Scoring:**
```
E = (E1 + E2 + E3 + E4) / 4
```

### Measurement Method

Extract from Claude session metadata and script logs. Normalize against per-story budgets (complexity-tier dependent).

---

## Test Story Suite

### Design Principles

1. **Real, not synthetic** — Stories drawn from actual project backlogs (avoids SWE-Bench+ contamination issues)
2. **Complexity tiers** — 5 tiers ensuring coverage from trivial to complex
3. **Deterministic inputs** — Same PRD/requirements for both plugins
4. **Reproducible** — Fixed model, temperature, context window

### Complexity Tiers

| Tier | Stories | Description | Expected Turns | Example |
|------|---------|-------------|----------------|---------|
| T1: Trivial | 6 | Single-file, obvious fix | 5-15 | Fix typo, add export |
| T2: Simple | 8 | Single-file feature or multi-file fix | 15-40 | Add validation, fix bug |
| T3: Medium | 8 | Multi-file feature, needs tests | 40-80 | New API endpoint with tests |
| T4: Complex | 5 | Cross-module feature, architectural | 80-150 | New subsystem with integration |
| T5: Ambitious | 3 | Full feature with design decisions | 150+ | New user-facing workflow |
| **Total** | **30** | | | |

### Story Format

```json
{
  "id": "S001",
  "tier": "T2",
  "title": "Add input validation to config parser",
  "description": "The config parser accepts invalid JSON silently...",
  "acceptance_criteria": [
    "Invalid JSON throws ConfigParseError with line number",
    "Missing required fields throw ConfigValidationError",
    "Unit tests cover all error paths"
  ],
  "test_command": "npm test",
  "build_command": "npm run build",
  "typecheck_command": "tsc --noEmit",
  "target_project": "sample-project-a",
  "files_affected": ["src/config.ts", "tests/config.test.ts"],
  "complexity_notes": "Requires understanding of existing error hierarchy"
}
```

---

## Test Execution Architecture

### Control Variables

| Variable | Setting | Rationale |
|----------|---------|-----------|
| Model | claude-sonnet-4-6 | Same model for both plugins |
| Temperature | 0 (default) | Deterministic |
| Max turns | 200 | Sufficient for T5 stories |
| Context window | Default | No manual truncation |
| Permission mode | bypassPermissions | Remove human permission as variable |
| Project state | Fresh git clone per story | No cross-story contamination |

### Execution Flow

```
For each story S in test_suite:
  For each plugin P in [taskplex, superpowers]:
    1. Clone fresh project state (git worktree)
    2. Install plugin P (--plugin-dir)
    3. Start trace logger
    4. Execute story S with plugin P
    5. Collect: trace log, git history, test results, session metadata
    6. Score: D, C, A, E → DQ
    7. Clean up worktree
```

### Runner Script

```bash
# tests/benchmark/run-benchmark.sh
# Orchestrates the full benchmark suite
# Outputs: results/run-<timestamp>/
#   - scores.json (per-story DQ scores)
#   - traces/ (per-story event traces)
#   - summary.json (aggregate statistics)
#   - comparison.md (human-readable report)
```

---

## Statistical Analysis

### Head-to-Head Comparison

- **Test:** Wilcoxon signed-rank test (non-parametric, paired)
- **Pairs:** Same story, different plugin → paired DQ scores
- **Significance:** p < 0.05
- **Effect size:** Cohen's d; meaningful if d ≥ 0.5
- **Sample size:** 30 stories → power ≈ 0.80 at medium effect size

### Per-Dimension Breakdown

Report each dimension separately to identify WHERE plugins differ:
```
| Dimension | TaskPlex μ | Superpowers μ | Δ | p-value | Winner |
|-----------|-----------|--------------|---|---------|--------|
| Discipline (D) | 0.82 | 0.61 | +0.21 | 0.003 | TaskPlex |
| Correctness (C) | 0.75 | 0.78 | -0.03 | 0.42 | — |
| ...
```

### Regression Tracking

For version-over-version tracking:
- Store all results in `results/` directory, keyed by plugin version
- Compare DQ scores across versions using Mann-Whitney U test
- Flag regressions: any dimension dropping >0.1 from previous version

---

## Report Output Format

### Per-Story Report
```json
{
  "story_id": "S001",
  "plugin": "taskplex",
  "plugin_version": "3.1.0",
  "tier": "T2",
  "scores": {
    "discipline": 0.85,
    "correctness": 1.0,
    "autonomy": 0.75,
    "efficiency": 0.60,
    "dq": 0.82
  },
  "metrics": {
    "D1_tdd_sequence": true,
    "D2_verification": true,
    "D3_code_review": true,
    "D4_spec_review": true,
    "D5_stop_guard": false,
    "D6_skill_routing": true,
    "D7_debug_before_fix": null,
    "C1_tests_pass": true,
    "C2_build_succeeds": true,
    "...": "..."
  },
  "trace_events": 47,
  "turns": 62,
  "tokens_used": 145000,
  "wall_clock_seconds": 180,
  "retries": 1,
  "human_interventions": 0
}
```

### Summary Report
```
═══════════════════════════════════════════
  BENCHMARK RESULTS: TaskPlex v3.1.0
  vs Superpowers v4.3.1
  Date: 2026-02-26 | Stories: 30
═══════════════════════════════════════════

OVERALL DQ SCORE
  TaskPlex:    0.78 ± 0.12
  Superpowers: 0.65 ± 0.15
  Δ = +0.13 (p = 0.008, d = 0.72) ✓ Significant

PER-DIMENSION BREAKDOWN
  Discipline:  0.85 vs 0.62 (+0.23, p=0.001) ✓
  Correctness: 0.76 vs 0.79 (-0.03, p=0.52)  —
  Autonomy:    0.72 vs 0.55 (+0.17, p=0.012) ✓
  Efficiency:  0.58 vs 0.64 (-0.06, p=0.31)  —

PER-TIER BREAKDOWN
  T1 Trivial:  0.90 vs 0.82 (+0.08)
  T2 Simple:   0.82 vs 0.70 (+0.12)
  T3 Medium:   0.75 vs 0.62 (+0.13)
  T4 Complex:  0.70 vs 0.55 (+0.15)
  T5 Ambitious: 0.65 vs 0.48 (+0.17)

PROBLEM AREAS (TaskPlex)
  ⚠ E1 turn count: 15% higher than Superpowers
  ⚠ C4 acceptance criteria: 2 stories partial

STRENGTHS (TaskPlex)
  ✓ D1 TDD compliance: 93% vs 42%
  ✓ A1 full autonomy: 80% vs 53%
  ✓ D4 spec review: 87% (Superpowers: N/A)
═══════════════════════════════════════════
```

---

## Implementation Phases

### Phase 1: Scaffolding (this PR)
- [ ] Create benchmark directory structure
- [ ] Define story schema (JSON Schema)
- [ ] Build trace logger (shell script, captures hook events)
- [ ] Build scoring engine (Python/shell, reads traces → scores)
- [ ] Create 5 sample stories (1 per tier) for validation

### Phase 2: Story Suite
- [ ] Write 30 stories across 5 tiers
- [ ] Create 3-5 sample target projects (varying tech stacks)
- [ ] Validate stories are solvable by both plugins

### Phase 3: Runner
- [ ] Build benchmark runner script (worktree isolation, plugin switching)
- [ ] Implement trace collection from hooks/session metadata
- [ ] Build report generator (summary + per-story)

### Phase 4: Statistical Analysis
- [ ] Implement Wilcoxon signed-rank test
- [ ] Implement per-dimension breakdown
- [ ] Build regression detection (version-over-version)

### Phase 5: CI Integration
- [ ] Run benchmark on version bumps
- [ ] Store historical results
- [ ] Generate trend charts

---

## References

- Drammeh (2025) — Decision Quality composite metric. arxiv:2511.15755
- Zhuge et al. (2024) — Agent-as-a-Judge. arxiv:2410.10934. github.com/metauto-ai/agent-as-a-judge
- Orogat et al. (2026) — Multi-Agent Framework Benchmarking. arxiv:2602.03128
- Fu et al. (2025) — PRDBench: PRD-driven agent evaluation. arxiv:2510.24358
- Thai et al. (2025) — SWE-EVO: Long-horizon agent evaluation. arxiv:2512.18470
- Garg et al. (2025) — SWE-Bench+: Contamination-resistant benchmarks. arxiv:2410.06992
- Agarwal et al. (2024) — Copilot Evaluation Harness. arxiv:2402.14261
- Tao et al. (2024) — MAGIS: Multi-agent issue resolution. arxiv:2403.17927
- Yang et al. (2024) — SWE-agent: ACI design. arxiv:2405.15793
