export interface MonitorEvent {
  id: string;
  timestamp: string;
  source: string;
  event_type: string;
  session_id: string;
  run_id: string;
  story_id: string;
  wave: number | null;
  batch: number | null;
  payload: Record<string, any>;
}

export interface Run {
  id: string;
  started_at: string;
  ended_at: string | null;
  mode: string;
  model: string;
  branch: string;
  total_stories: number;
  completed: number;
  skipped: number;
  config: Record<string, any>;
}

export interface StoryTimelineEntry {
  story_id: string;
  title: string;
  started_at: string;
  ended_at: string | null;
  status: "pending" | "in_progress" | "completed" | "failed" | "skipped";
  attempts: number;
  error_category: string | null;
  wave: number | null;
}

export interface ErrorBreakdown {
  category: string;
  count: number;
  stories: string[];
}

export interface ToolUsageEntry {
  tool_name: string;
  count: number;
  agent_type: string;
}

export interface RunSummary {
  total_stories: number;
  completed: number;
  skipped: number;
  blocked: number;
  elapsed_s: number;
  error_rate: number;
  mode: string;
}

export interface AgentDuration {
  agent_type: string;
  avg_duration_ms: number;
  count: number;
}
