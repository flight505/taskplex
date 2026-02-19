// MonitorEvent — server returns id as INTEGER, payload as JSON object
export interface MonitorEvent {
  id: number;
  timestamp: string;
  source: "hook" | "orchestrator" | "parallel";
  event_type: string;
  session_id?: string;
  run_id?: string;
  story_id?: string;
  wave: number | null;
  batch: number | null;
  payload: Record<string, any>;
}

// Run — server returns config as JSON string, model/branch can be null
export interface Run {
  id: string;
  started_at: string;
  ended_at: string | null;
  mode: string;
  model: string | null;
  branch: string | null;
  total_stories: number | null;
  completed: number;
  skipped: number;
  config: string; // JSON string from SQLite
}

// StoryTimelineEntry — from GET /api/analytics/timeline/:runId
export interface StoryTimelineEntry {
  story_id: string;
  started_at: string;
  ended_at: string | null;
  status: "completed" | "skipped" | "blocked" | "running" | "failed";
  attempts: number;
  wave: number | null;
  batch: number | null;
}

// ErrorBreakdown — from GET /api/analytics/errors
// Server returns {category, count} only — no stories array
export interface ErrorBreakdown {
  category: string;
  count: number;
}

// ToolUsageEntry — from GET /api/analytics/tools
export interface ToolUsageEntry {
  tool_name: string;
  agent_type: string;
  count: number;
}

// RunSummary — from GET /api/analytics/summary/:runId
export interface RunSummary {
  run_id: string;
  mode: string;
  model: string | null;
  branch: string | null;
  started_at: string;
  ended_at: string | null;
  elapsed_seconds: number | null;
  total_stories: number;
  completed: number;
  skipped: number;
  blocked: number;
  failed: number;
  error_rate: number;
}

// AgentDuration — from GET /api/analytics/agents
// Server returns *_seconds and invocations, NOT *_ms and count
export interface AgentDuration {
  agent_type: string;
  avg_duration_seconds: number;
  min_duration_seconds: number;
  max_duration_seconds: number;
  invocations: number;
}

// WebSocket message envelope — server broadcasts these wrappers
export type WsMessage =
  | { type: "event"; event: MonitorEvent }
  | { type: "run.created"; run: Run }
  | { type: "run.updated"; run: Run };
