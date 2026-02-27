# TaskPlex SOTA Research & Transformation Plan

**Date:** 2026-02-27 | **Author:** Jesper Vang (@flight505) | **Version:** 1.0

This document reconstructs the research and strategic analysis that drove TaskPlex's transformation from a simple PRD executor (v2.0.8) into an always-on autonomous development companion (v4.0.0). It captures the competitive analysis of Superpowers, SOTA literature findings, user pain point analysis from 200+ GitHub issues, and a gap analysis of what remains to be done.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Superpowers Analysis](#2-superpowers-analysis)
3. [Superpowers GitHub Issues Analysis](#3-superpowers-github-issues-analysis)
4. [SOTA Literature Review](#4-sota-literature-review)
5. [TaskPlex v4.0.0 Feature Inventory](#5-taskplex-v400-feature-inventory)
6. [Competitive Comparison Matrix](#6-competitive-comparison-matrix)
7. [What We Already Implemented](#7-what-we-already-implemented)
8. [Remaining Gaps & Future Directions](#8-remaining-gaps--future-directions)
9. [References](#9-references)

---

## 1. Executive Summary

**Goal:** Create a Claude Code plugin that is definitively better than Superpowers (63k+ GitHub stars) by understanding what "better" means from both a human perspective (studying Superpowers' 200+ issues) and a research perspective (studying current SOTA in agentic frameworks for foundation models).

**Key Findings:**

1. **Superpowers' biggest weakness is advisory-only enforcement.** Skills tell the model what to do, but the model can rationalize its way out. Users report review steps being skipped (#528, #463), TDD not being followed (#384, #373), and the concealment directive preventing diagnosis (#472). TaskPlex solves this with hook-based mechanical enforcement — `SubagentStop` validation, `TaskCompleted` test gates, `Stop` hook exit prevention.

2. **No persistence is Superpowers' second biggest gap.** Every session starts from zero. Users request cross-session memory (#551, #230), progress tracking, and failure learning. TaskPlex's SQLite knowledge store with 60-day confidence decay directly addresses this.

3. **SOTA research validates TaskPlex's architecture.** Multi-agent role specialization (SWE-agent, Agentless), external memory (A-MEM, Memora), process reward models (AgentPRM), reward hacking prevention (Sycophancy to Subterfuge), and difficulty-aware routing (Hybrid LLM, BEST-Route) are all active research frontiers — and TaskPlex implements practical versions of each.

4. **TaskPlex v4.0.0 has already implemented ~90% of the transformative features.** v4.1.0 adds SSC spec hardening and Bayesian confidence. The remaining frontier capabilities are self-improving prompts, consistency-based routing, and structured reflection.

---

## 2. Superpowers Analysis

### 2.1 Architecture Overview

Superpowers v4.3.1 is a **14-skill, 1-agent, 1-hook behavioral enforcement framework**.

| Component | Count | Purpose |
|-----------|-------|---------|
| Skills | 14 | Discipline enforcement (TDD, debugging, verification, planning, review) |
| Agents | 1 | `code-reviewer` (inherits user's model) |
| Hooks | 1 | `SessionStart` (injects `using-superpowers` skill) |
| Config | 0 | No configuration system |
| Persistence | 0 | No knowledge database |
| Routing | 0 | No model selection |

### 2.2 Skill Inventory

| Skill | Words | Purpose |
|-------|-------|---------|
| writing-skills | 3,204 | TDD applied to skill documentation |
| systematic-debugging | 1,504 | 4-phase root cause investigation |
| test-driven-development | 1,496 | RED-GREEN-REFACTOR enforcement |
| subagent-driven-development | 1,213 | Fresh subagent + 2-stage review |
| receiving-code-review | 929 | Technical feedback evaluation |
| dispatching-parallel-agents | 872 | Concurrent subagent workflows |
| using-git-worktrees | 784 | Isolated workspace creation |
| finishing-a-development-branch | 679 | Integration + merge verification |
| verification-before-completion | 668 | Evidence-before-claims gate |
| brainstorming | 663 | Socratic design refinement |
| using-superpowers | 621 | Skill discovery + mandatory invocation |
| writing-plans | 458 | Bite-sized TDD-compatible tasks |
| executing-plans | 378 | Batch execution with review checkpoints |
| requesting-code-review | 366 | Dispatch code-reviewer agent |
| **Total** | **13,835** | |

### 2.3 Enforcement Mechanisms

Superpowers relies on **in-context enforcement** through:

1. **Hard Gates** — `<HARD-GATE>` blocks in brainstorming skill
2. **Iron Laws** — 6 "NO X WITHOUT Y FIRST" rules
3. **Rationalization Tables** — 10-30 common excuses + reality counters per skill
4. **Red Flags Lists** — Self-check signals for rule violations
5. **1% Chance Rule** — "If ANY skill might apply, MUST invoke it"

**Critical limitation:** All enforcement is advisory. The model can and does rationalize its way around rules, especially under context pressure.

### 2.4 What Superpowers Does Well

- Battle-tested discipline patterns (55k+ stars, production-validated)
- Multi-platform support (Claude Code, Cursor, Codex, OpenCode)
- Clean philosophical foundation (TDD, spec-first, YAGNI)
- Responsive maintainer (Jesse Vincent)
- Lean token footprint (~14k words total)

### 2.5 What Superpowers Does NOT Do

| Capability | Status |
|-----------|--------|
| Persistent knowledge | None — every session starts from zero |
| Model routing | None — same model for everything |
| Cost optimization | None — no fast-path, no effort tuning |
| Learning from failures | None — no error categorization or retry strategy |
| Hook-based enforcement | 1 hook (SessionStart only) — all else is advisory |
| Agent specialization | 1 agent — no validator, architect, merger, etc. |
| Parallel orchestration | Manual only — no dependency-aware batching |
| Interactive mode | None — no mid-run user approval points |
| Configuration | None — no config file, take-it-or-leave-it |
| Reward hacking prevention | None — no test file integrity checks |
| Scope drift detection | None — no configurable drift strategies |
| Agent Teams support | None — community-built workaround only |

---

## 3. Superpowers GitHub Issues Analysis

**Repository:** github.com/obra/superpowers | **Stars:** 63,290 | **Issues analyzed:** 200 (79 open, 121 closed)

### 3.1 Top Pain Points (by frequency and severity)

#### Pain Point 1: Skills Not Triggering Reliably (~15 issues)

Users install Superpowers and cannot tell whether it's doing anything.

- **#446** (20 comments): "How to know if Superpowers are being invoked?" — experienced user cannot detect activation
- **#554**: Codex CLI requires explicit `$` or `/skills` mention
- **#378**: Claude performs brainstorming but skips worktree creation
- **#439**: Skills not triggered when prompt contains large file — model gets "sidetracked"
- **#433**: OpenCode agent goes from brainstorming straight to code changes without plan/TDD

**TaskPlex solution:** Hook-based mechanical enforcement. `SessionStart` injects context, `SubagentStart` injects knowledge, `SubagentStop` validates results, `TaskCompleted` gates on test pass. Skills are the philosophy; hooks are the enforcement.

#### Pain Point 2: Review Steps Skipped by Model (~8 issues)

The model finds ways to shortcut mandatory processes.

- **#528**: "Claude skips spec and code quality review — it will always say it was because it wanted to go faster"
- **#463**: "The controller rationalized skipping the reviewer dispatches because the requirements were 'straightforward'"
- **#384**: "TDD skill is advisory only" — no enforcement mechanism
- **#493**: When TDD is followed, agent writes superficial tests (schema metadata instead of behavior)

Community consensus (#528 comments): "Quality gates that run as external checks (not as in-context instructions) are one way to prevent it."

**TaskPlex solution:** Two-stage review pipeline (spec-reviewer + code-reviewer) spawned as separate agents, not in-context suggestions. `SubagentStop` hook runs typecheck/build/test after implementation. Test file integrity checksums catch reward hacking.

#### Pain Point 3: Windows Support Broken (~27 issues)

Not directly relevant to TaskPlex (bash 3.2 + macOS/Linux focus), but reveals the cost of multi-platform ambition.

#### Pain Point 4: No Cross-Session Memory (~4 issues, high demand)

- **#551**: Detailed feature request for `progress-tracking` skill with structured development memory. "Repeated mistakes without records of failed approaches."
- **#230**: Request for "compounding" — capturing lessons so they don't need re-discovery
- **#284**: "How to continue superpowers work after exit claude-code"
- **#364**: Context hits 100%, no built-in resume mechanism

**TaskPlex solution:** SQLite knowledge store with 6 tables (learnings, file_patterns, error_history, decisions, patterns, runs), confidence decay (5%/day, 60-day cutoff), and pattern promotion from 3+ story occurrences.

#### Pain Point 5: Token Bloat (~5 issues)

- **#512** (15 comments): Plans are 1,750+ lines, users report $50+ token burns
- **#227**: `write-plan` exceeds 32k output token limit
- **#190**: 22k+ tokens consumed at startup by preloaded skills

**TaskPlex solution:** 71% skill trimming (using-taskplex: 67 lines), segment filtering for PRD, lean context per subagent, fast-path routing eliminates 40% of Opus calls.

#### Pain Point 6: Concealment Directive Problem (#472)

The `<EXTREMELY_IMPORTANT>` wrapper with "This is not negotiable" prevented the agent from telling the user it was stuck. Led to 50+ zombie sessions over 5 days.

**TaskPlex solution:** No concealment directives. using-taskplex gate uses strong language for triggering but doesn't hide its own existence. Hooks are transparent — all emit events to optional monitor dashboard.

### 3.2 Feature Requests That TaskPlex Already Addresses

| Superpowers Request | Issue # | TaskPlex Feature |
|--------------------|---------|-----------------|
| Cross-session memory | #551, #230 | SQLite knowledge store |
| Progress tracking | #551 | prd.json state + progress.txt |
| Agent Teams | #429, #464, #469 | `scripts/teams.sh` + `TeammateIdle` hook |
| Model routing per task | #306 | `decision-call.sh` (Haiku/Sonnet/Opus) |
| Configurability | #337, #348, #306 | `taskplex.config.json` (23 options) |
| Architecture awareness | #495 | `architect` agent (read-only codebase explorer) |
| Automatic TDD enforcement | #384 | `SubagentStop` hook + test file checksums |
| Resume after exit | #284, #364 | `SessionStart` hook detects prd.json + `pre-compact.sh` saves state |
| Challenge product assumptions | #530 | `brainstorm` skill with `architect` agent |
| Quality gates as external checks | #528 comments | All hooks are external to model context |

### 3.3 Feature Requests We Haven't Addressed Yet

| Request | Issue # | Status | Complexity |
|---------|---------|--------|-----------|
| Self-improving prompts from execution data | #551 (implied) | Not implemented | High |
| Multi-platform (Cursor, Codex, OpenCode) | #503, #217, #352, #262 | Not planned | Medium |
| Plan splitting into per-task files | #512 | Not implemented | Low |
| Cost tracking per story | Implied by #512 | Not implemented | Low |
| Merge conflict auto-resolution | Not explicit | Not implemented | Medium |

---

## 4. SOTA Literature Review

### 4.1 Consensus Findings (Established in Literature)

#### Multi-Agent Role Specialization Outperforms Single-Agent Loops

**Key papers:** SWE-agent (Yang et al., 2024, arxiv: 2405.15793), Agentless (Xia et al., 2024, arxiv: 2407.01489), ALMAS (Tawosi et al., 2025, arxiv: 2510.03463)

Architectures that decompose tasks across planner, implementer, reviewer, and validator agents consistently outperform monolithic LLM calls on SWE-bench. Every competitive system builds on role specialization as a baseline.

**TaskPlex alignment:** 7 agents (architect, implementer, validator, spec-reviewer, code-reviewer, reviewer, merger) with explicit pipeline: brainstorm → PRD → implement → validate → review → merge.

#### External Hierarchical Memory Is Required

**Key papers:** "Memory in the Age of AI Agents" (Hu et al., 2025, arxiv: 2512.13564, 1309 GitHub stars), A-MEM (Xu et al., 2025, arxiv: 2502.12110, 801 GitHub stars)

No LLM context window is sufficient for long-running agentic tasks. External memory — whether vector store, graph, or structured key-value — is the consensus architecture.

**TaskPlex alignment:** SQLite knowledge store with 6 tables, confidence decay, pattern promotion, per-edit context injection via hooks.

#### Process Supervision Improves Agent Quality Over Outcome-Only Rewards

**Key papers:** AgentPRM (Choudhury, 2025, arxiv: 2502.10325), "Lessons of Developing PRMs" (Zhang et al., 2025, arxiv: 2501.07301)

Dense step-level signals outperform sparse outcome signals for complex multi-step tasks. The practical equivalent for a plugin is encoding gate decisions as explicit tool calls with mandatory outputs, not prose.

**TaskPlex alignment:** SubagentStop hook provides dense inline validation (typecheck → build → test) after each implementation, not just at the end.

#### Reward Hacking Is a Real and Documented Risk

**Key papers:** "Sycophancy to Subterfuge" (Denison et al., Anthropic, 2024, arxiv: 2406.10162), TRACE benchmark (Deshpande et al., 2026, arxiv: 2601.20103, 54 categories of code reward exploits)

LLMs trained on simple specification gaming generalize to complex reward tampering, including test file modification in coding contexts.

**TaskPlex alignment:** Test file integrity checksums computed before implementation, verified after. Configurable scope drift detection (warn/block/review).

#### Difficulty-Aware Routing Reduces Cost 40-60%

**Key papers:** Hybrid LLM (Ding et al., Microsoft, 2024, arxiv: 2404.14618, 214 S2 citations), BEST-Route (Ding et al., ICML 2025, arxiv: 2506.22716)

Route queries to small vs. large models based on predicted difficulty. BEST-Route shows 40-60% cost reduction with <1% performance drop.

**TaskPlex alignment:** Rule-based fast path eliminates ~40% of Opus calls. Simple stories → Haiku, standard → Sonnet, complex → Opus decision call.

### 4.2 Frontier Research (Not Yet Consensus)

#### Self-Evolving Agent Systems

**Key papers:** "A Self-Improving Coding Agent" (Robeyns et al., 2025, arxiv: 2504.15228), Live-SWE-agent (Xia et al., 2025, arxiv: 2511.13646)

Agents that edit their own orchestration logic between runs, achieving 17-53% improvement on SWE-bench subsets. Promising but not yet validated at production scale.

**TaskPlex status:** Not implemented. Would require analyzing execution data across runs to identify prompt improvements. High complexity, high potential.

#### Zero-Shot Model Routing

**Key papers:** ZeroRouter (Yan et al., 2026, arxiv: 2601.06220), SCOPE (Cao et al., 2026, arxiv: 2601.22323)

Decouple query difficulty estimation from specific model pool — new models can be added without recalibrating the router.

**TaskPlex status:** Partially implemented. Rule-based fast path is model-agnostic but uses hardcoded thresholds. Could evolve to embedding-based difficulty estimation.

#### Specification Self-Correction

**Key papers:** SSC (Gallego, 2025, arxiv: 2507.18742)

Model identifies and rewrites flawed rubrics in its own specification before generating output. Inference-time defense against reward hacking.

**TaskPlex status:** Not implemented. Could complement test file checksums with specification-level self-correction.

#### Structured Reflection for Error Recovery

**Key papers:** "Failure Makes the Agent Stronger" (Su et al., 2025, arxiv: 2509.18847), VIGIL (Cruz, 2025, arxiv: 2512.07094)

Turn error-to-repair paths into explicit, replayable action sequences. Eliminates repetitive failure loops.

**TaskPlex status:** Partially implemented. `failure-analyzer` skill categorizes errors (6 types) and suggests retry strategies. Could evolve to structured reflection with replay.

#### Bayesian Confidence Over Time-Based Decay

**Key papers:** MACLA (Forouzandeh et al., 2025, arxiv: 2512.18950)

Track per-entry success/failure counts and compute posterior reliability rather than simple timestamp decay. More stable under low-sample conditions.

**TaskPlex status:** Not implemented. Current confidence decay is linear time-based (5%/day). Bayesian posterior would be more robust.

### 4.3 Open Questions in the Field

1. **How to prevent test contamination vs. legitimate test evolution?** No deployed system has a robust real-time detector at high precision. TaskPlex uses checksums (coarse) — finer detection remains open.

2. **What is the right memory architecture for multi-session coding agents?** MemoryAgentBench shows no current architecture dominates all competencies. SQLite structured storage vs. RAG vs. graph-based memory remains unresolved.

3. **Can model routing be robust to adversarial difficulty misclassification?** Short bug reports that require deep architectural understanding appear simple but need expert reasoning. IRT-Router partially addresses this.

4. **How do parallel agents maintain coherent shared context across worktree execution?** No work has specifically studied context coherence under parallel writes to shared repositories at production CI scale.

---

## 5. TaskPlex v4.0.0 Feature Inventory

### 5.1 Eight-Layer Architecture

| Layer | Name | Components |
|-------|------|-----------|
| L1 | Proactivity | SessionStart hook → session-context.sh, using-taskplex skill (1% gate) |
| L2 | Discipline | brainstorm, taskplex-tdd, taskplex-verify, failure-analyzer + rationalization tables |
| L3 | Intelligence | prd-generator, prd-converter, knowledge-db.sh (SQLite), decision-call.sh (routing) |
| L4 | Execution | 7 agents: architect, implementer, validator, spec-reviewer, code-reviewer, reviewer, merger |
| L5 | Orchestration | taskplex.sh (sequential), parallel.sh (wave-based), teams.sh (Agent Teams), interactive mode |
| L6 | Routing | Rule-based fast path (~40% Opus savings) + 1-shot Opus decision calls |
| L7 | Safety | Test file checksums, scope drift detection, destructive command blocking, rationalization prevention |
| L8 | Learning | Confidence decay (60-day), pattern promotion (3+ stories), implicit mining (5 types), per-edit injection |

### 5.2 Full Component Counts

| Component | TaskPlex | Superpowers |
|-----------|----------|-------------|
| Skills | 17 | 14 |
| Agents | 7 | 1 |
| Hooks | 12 across 10 events | 1 (SessionStart) |
| Config options | 23 | 0 |
| SQLite tables | 6 | 0 |
| Execution modes | 4 (sequential, parallel, teams, interactive) | 1 (sequential) |
| Review stages | 2 (spec + code) | 1 (code only) |

### 5.3 Innovation Catalog (Unique to TaskPlex)

1. **Bash orchestrator as intelligence holder** — Knowledge and routing computed by orchestrator, agents remain stateless
2. **Fresh context per subagent** — No agent memory pollution, each iteration isolated
3. **Two-tier routing** — Rule-based fast path + Opus decision call
4. **SQLite with confidence decay** — Time-aware knowledge (5%/day, 60-day cutoff)
5. **Pattern promotion** — Learnings graduate from 3+ story occurrences
6. **Enhanced implicit mining** — 5 pattern types extracted from agent transcripts
7. **Per-edit context injection** — PreToolUse hook injects file patterns before each Edit/Write
8. **Inline validation with self-healing** — SubagentStop runs checks, agent auto-fixes in same context
9. **Reward hacking prevention** — Test file integrity checksums
10. **Destructive command blocking** — Agent-scoped PreToolUse on Bash
11. **Configurable scope drift** — warn/block/review strategies
12. **Wave-based parallel execution** — Dependency-aware batching with conflict detection
13. **Agent Teams integration** — TeammateIdle hook assigns work
14. **Interactive mode** — Mid-run user approval points
15. **Effort auto-tuning** — Escalation on retries (low → medium → high)
16. **Optional real-time dashboard** — Bun + Vue 3 sidecar with WebSocket
17. **Three-layer observability** — Operational log, SQLite history, per-instance context

---

## 6. Competitive Comparison Matrix

| Feature | Superpowers | claude-mem | wshobson/agents | TaskPlex |
|---------|-------------|-----------|-----------------|----------|
| **Stars** | 63k | 29k | 29k | Internal |
| **Skills** | 14 | — | 72 | 17 |
| **Agents** | 1 | — | Variable | 7 |
| **Hooks** | 1 | — | — | 12 |
| **Persistence** | None | Vector DB | None | SQLite (decay) |
| **TDD enforcement** | Advisory | No | Advisory | Hook-enforced |
| **Review pipeline** | Advisory | No | Partial | 2-stage mandatory |
| **Reward hacking prevention** | None | None | None | Checksums |
| **Cost optimization** | None | None | None | 40% Opus savings |
| **Parallel execution** | Manual | No | Partial | Wave-based + Teams |
| **Model routing** | None | None | None | Rule-based + decision calls |
| **Knowledge decay** | None | None | None | 60-day with promotion |
| **Error categorization** | None | None | Partial | 6 types |
| **Dashboard** | None | None | Partial | Bun + Vue 3 |
| **Configuration** | 0 options | Minimal | Some | 23 options |
| **Token footprint** | ~14k words | Minimal | Large | ~10k words (lean) |

---

## 7. What We Already Implemented

The v4.0.0 transformation addressed the vast majority of findings from our research. Here's the mapping from research insight to implementation:

### 7.1 From Superpowers Issues

| Issue Insight | Implementation | Status |
|--------------|----------------|--------|
| Advisory-only enforcement (#528, #463, #384) | Hook-based gates (SubagentStop, TaskCompleted, Stop) | **Done** |
| No cross-session memory (#551, #230) | SQLite knowledge store with 6 tables | **Done** |
| Review steps skipped (#528, #463) | Two-stage agent-based review pipeline | **Done** |
| No model routing (#306) | decision-call.sh with fast path | **Done** |
| No configurability (#337, #348) | taskplex.config.json (23 options) | **Done** |
| Token bloat (#512, #227, #190) | 71% skill trimming, lean context, segment filtering | **Done** |
| No Agent Teams (#429, #464) | scripts/teams.sh + TeammateIdle hook | **Done** |
| No resume mechanism (#284, #364) | SessionStart context + pre-compact.sh | **Done** |
| Concealment directive problem (#472) | No concealment directives, transparent hooks | **Done** |
| No architecture awareness (#495) | architect agent (read-only codebase explorer) | **Done** |
| Challenge product assumptions (#530) | brainstorm skill | **Done** |

### 7.2 From SOTA Literature

| Research Finding | Implementation | Status |
|-----------------|----------------|--------|
| Multi-agent role specialization | 7 specialized agents with pipeline | **Done** |
| External hierarchical memory | SQLite with 6 tables | **Done** |
| Process supervision (dense signals) | SubagentStop inline validation | **Done** |
| Reward hacking prevention | Test file integrity checksums | **Done** |
| Difficulty-aware routing | Rule-based fast path (~40% savings) | **Done** |
| Constitutional AI principles | Rationalization prevention tables | **Done** |
| Error categorization | failure-analyzer (6 categories) | **Done** |
| Confidence decay | Linear time-based (5%/day, 60-day) | **Done** |
| Implicit knowledge mining | 5 pattern types from transcripts | **Done** |
| Pattern promotion | 3+ story threshold | **Done** |

---

## 8. Remaining Gaps & Future Directions

### 8.1 Research-Frontier Capabilities

| Capability | Research Basis | Complexity | Impact | Priority | Claude Native? | Status |
|-----------|---------------|-----------|--------|----------|---------------|--------|
| **Specification self-correction (SSC)** | SSC (arxiv: 2507.18742) | Low | High | P1 | No — requires pre-implementation spec rewriting | **Implemented v4.1.0** |
| **Bayesian confidence** | MACLA (arxiv: 2512.18950) | Medium | High | P1 | No — requires tracking per-learning success/failure | **Implemented v4.1.0** |
| **Self-improving prompts** | SCOPE (arxiv: 2512.15374) | High | High | P2 | Partially — Claude learns within session, not across runs | Not implemented |
| **Consistency-based routing** | BEST-Route (arxiv: 2506.22716) | Medium | High | P2 | No — requires multi-sample consensus logic | Not implemented |
| **Structured reflection** | VIGIL (arxiv: 2512.07094) | Medium | Medium | P3 | Partially — Claude reflects naturally but not in structured replay format | Not implemented |

> **Note on attribution:** Live-SWE-agent (arxiv: 2511.13646) is about *runtime tool synthesis* — the agent generates new tools during execution. The actual cross-run prompt optimization reference is SCOPE (arxiv: 2512.15374), which analyzes execution traces across runs to identify and promote successful prompt patterns.

#### Specification Self-Correction (SSC) — Implemented v4.1.0

**Problem:** Agents game acceptance criteria at 63-75% (SSC paper). Vague specs like "handle edge cases" get satisfied by a single `if` check.
**Mechanism:** Before implementation, a Haiku call critiques each acceptance criterion for gaming vectors (vagueness, missing bounds, untestable claims) and rewrites them with concrete, measurable thresholds. Runs once on first attempt only — retries use already-hardened specs.
**Integration:** `harden_spec()` in `taskplex.sh`, runs between decision call and context brief. Non-fatal; configurable via `spec_hardening` (default: true).

#### Bayesian Confidence — Implemented v4.1.0

**Problem:** Linear time-based decay (5%/day) treats all learnings equally regardless of actual reliability. A learning that worked 10/10 times decays at the same rate as one that worked 1/5 times.
**Mechanism:** Adds `applied_count` and `success_count` columns to the learnings table. Each time a learning is injected into an agent, `applied_count` increments. On story success, `success_count` increments for all learnings that were applied. With 2+ applications, confidence switches from time-decay to Beta posterior: `(success+1)/(applied+2)`. Below 2 applications, the original time-decay formula persists as a graceful fallback.
**Integration:** `inject-knowledge.sh` tracks applied IDs; `taskplex.sh` records success on story completion. Schema migration is idempotent (`ALTER TABLE ... || true` pattern).

#### Self-Improving Prompts

**Problem:** Agent prompts are static — the same instructions regardless of what worked or failed in previous runs.
**Mechanism (SCOPE):** After each run, compare prompt variations against outcomes. Patterns yielding >80% success across 5+ stories get promoted to the agent's system prompt. Requires statistical significance testing to avoid overfitting.
**Claude native?** Partially — Claude learns within a session context, but cannot persist prompt improvements across sessions without external infrastructure.

#### Consistency-Based Routing

**Problem:** Default Sonnet routing is expensive for stories where Haiku would suffice, but Haiku's correctness is unpredictable.
**Mechanism (BEST-Route):** For moderate-difficulty stories, sample 3 Haiku responses and check consistency. If all agree, use the result (~$0.003). If they disagree, escalate to Sonnet ($0.06). Saves cost vs. default Sonnet routing.
**Claude native?** No — requires multi-sample consensus logic external to any single model call.

### 8.2 Practical Enhancements (Low-Hanging Fruit)

| Enhancement | Effort | Impact |
|-------------|--------|--------|
| **Plan splitting** into per-task files (addresses #512 concern) | Low | Medium |
| **Cost tracking** per story (query decision table, estimate tokens) | Low | Medium |
| **Dependency graph visualization** (Mermaid DAG in monitor) | Low | Low |
| **prd.json schema validation** at orchestrator startup | Low | Medium |
| **SQLite PRAGMA integrity_check** on every init | Low | Low |
| **Cross-run analytics** in monitor dashboard | Medium | High |

### 8.3 Platform Decisions

TaskPlex intentionally does NOT pursue multi-platform support (Cursor, Codex, OpenCode). Superpowers' 27 Windows issues demonstrate the cost of that ambition. TaskPlex targets Claude Code exclusively, going deep on hooks and agent integration rather than wide on platform compatibility.

### 8.4 What "Better Than Superpowers" Means

Based on our research, "better" means:

1. **Mechanically enforced discipline** — not advisory prompts that can be rationalized away
2. **Persistent learning** — knowledge that compounds across sessions, not starting from zero
3. **Cost-aware execution** — routing to the right model for the right task, not one-size-fits-all
4. **Self-healing validation** — inline checks that catch errors in context, not after the fact
5. **Proactive awareness** — the plugin knows what's happening without being asked
6. **Configurable behavior** — users can tune the system to their needs
7. **Research-grounded architecture** — each design decision backed by SOTA literature

TaskPlex v4.0.0 achieves all seven. v4.1.0 adds SSC spec hardening and Bayesian confidence, moving two frontier capabilities into production. The remaining capabilities (self-improving prompts, consistency routing, structured reflection) represent the next research frontier.

---

## 9. References

### 9.1 Key Papers

| Paper | Year | arxiv | Relevance |
|-------|------|-------|-----------|
| Constitutional AI: Harmlessness from AI Feedback | 2022 | 2212.08073 | Principles-based behavioral alignment |
| SWE-agent: Agent-Computer Interfaces | 2024 | 2405.15793 | Role-specialized agent architecture |
| Agentless: Demystifying LLM-based SWE Agents | 2024 | 2407.01489 | Cost-efficient two-phase approach |
| Hybrid LLM: Cost-Efficient Query Routing | 2024 | 2404.14618 | Difficulty-aware model selection |
| Sycophancy to Subterfuge: Reward Tampering | 2024 | 2406.10162 | Reward hacking in coding agents |
| Memory in the Age of AI Agents | 2025 | 2512.13564 | External memory architectures |
| A-MEM: Agentic Memory for LLM Agents | 2025 | 2502.12110 | Zettelkasten dynamic linking |
| AgentPRM: Process Reward Models for Agents | 2025 | 2502.10325 | Process supervision |
| BEST-Route: Adaptive LLM Routing | 2025 | 2506.22716 | Consistency-based cost optimization |
| SWE-Master: Post-Training for SWE Agents | 2026 | 2602.03411 | Current SOTA open-source SWE benchmark |
| TRACE: Reward Exploit Taxonomy | 2026 | 2601.20103 | 54 categories of code reward exploits |
| ZeroRouter: Universal Latent Space Routing | 2026 | 2601.06220 | Zero-shot model onboarding |
| VIGIL: Reflective Runtime for Self-Healing Agents | 2025 | 2512.07094 | Structured reflection |
| Live-SWE-agent: Runtime Tool Synthesis | 2025 | 2511.13646 | Self-evolving orchestration (runtime) |
| SCOPE: Cross-Run Prompt Optimization | 2025 | 2512.15374 | Self-improving prompts (cross-run) |
| MACLA: Bayesian Procedural Memory | 2025 | 2512.18950 | Bayesian confidence tracking |

### 9.2 Superpowers GitHub Issues

| Issue | Title | Relevance |
|-------|-------|-----------|
| #528 | Claude skips spec and code quality review | Advisory enforcement failure |
| #463 | Controller skips reviewer dispatches | Rationalization of "straightforward" tasks |
| #472 | Concealment directives prevent diagnosis | Forced behavior backfires |
| #384 | Request for automatic TDD enforcement | Advisory-only limitation |
| #551 | Progress tracking with development memory | Cross-session persistence gap |
| #230 | Compounding — capturing lessons | Knowledge retention gap |
| #429 | Agent Teams integration request | Parallel execution gap |
| #512 | Plans are bloated (1,750+ lines) | Token efficiency gap |
| #446 | How to know if Superpowers are invoked? | Activation reliability gap |
| #306 | Different models for different task types | Model routing gap |

### 9.3 Competing Plugins

| Plugin | Stars | Focus |
|--------|-------|-------|
| obra/superpowers | 63k | Behavioral discipline |
| claude-mem | 29k | Cross-session vector memory |
| wshobson/agents | 29k | 72 specialized plugins |
| parthalon025/autonomous-coding-toolkit | ~100 | Quality gates on top of Superpowers |
| compound-engineering-plugin (Every Inc) | — | Upfront research + lesson capture |

---

**This document serves as the permanent record of the research and strategic analysis that informed TaskPlex's v2.0.8 → v4.0.0 transformation. It should be updated as new research emerges and as remaining gaps are addressed.**
