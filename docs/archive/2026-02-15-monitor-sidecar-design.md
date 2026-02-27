# TaskPlex Monitor Sidecar — Design Document

**Date:** 2026-02-15
**Status:** Approved
**Approach:** Hooks-First Sidecar (Approach A)

## Overview

A bundled monitoring sidecar for TaskPlex that provides real-time execution visibility and historical analytics. Captures events via Claude Code hooks and orchestrator `curl` calls, stores in SQLite, displays in a Vue 3 browser dashboard via WebSocket.

## Architecture

```
Claude Code hooks → HTTP POST → Bun server (port 4444) → SQLite + WebSocket → Vue 3 dashboard
taskplex.sh events → HTTP POST ↗
```

### Directory Layout

```
taskplex/monitor/
├── server/          # Bun HTTP + WebSocket + SQLite
├── client/          # Vue 3 + Tailwind dashboard
├── hooks/           # Shell-based hook scripts
├── scripts/         # start-monitor.sh, stop-monitor.sh
└── package.json     # Bun workspace root
```

## Event Schema

Two sources: Claude Code hooks (automatic) and taskplex.sh orchestrator (~15 curl calls).

### SQLite Tables

- `events` — all events with timestamp, source, event_type, run_id, story_id, wave, payload (JSON)
- `runs` — run metadata with mode, model, branch, story counts, config snapshot

### Event Types

**Hook events:** subagent.start, subagent.stop, tool.use, tool.error, session.start, session.end
**Orchestrator events:** run.start, run.end, story.start, story.complete, story.failed, story.skipped, story.retry, story.validated, wave.start, wave.end, merge.start, merge.result, knowledge.update, context.generated, iteration.start

### Key Properties

- Fire-and-forget emission (never blocks execution)
- run_id ties all events from one invocation
- No AI summarization at capture time (structured types are self-describing)

## Dashboard Views

1. **Timeline** — Real-time event stream with filters, color-coded by story/type
2. **Story Gantt** — Horizontal bars per story showing duration, attempts, wave membership
3. **Error Patterns** — Category breakdown, trends over runs, diagnostic tables
4. **Agent Insights** — Tool usage, turn counts, already-implemented detection rate, learnings

## Tech Stack

- Server: Bun + SQLite (WAL mode)
- Client: Vue 3 + Vite + Tailwind CSS
- Transport: WebSocket (real-time) + REST (analytics queries)
- Hook scripts: bash + curl + jq

## Integration Points

- Wizard Checkpoint 6: "Enable execution monitor?" option
- taskplex.sh: emit_event() helper + ~15 calls at existing log points
- hooks.json: Extended with SubagentStart, SubagentStop, PostToolUse for monitor
- start-monitor.sh / stop-monitor.sh managed by wizard and cleanup trap
