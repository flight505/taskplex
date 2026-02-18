import type {
  Run,
  MonitorEvent,
  StoryTimelineEntry,
  ErrorBreakdown,
  ToolUsageEntry,
  RunSummary,
  AgentDuration,
} from "@/types";

const BASE = "/api";

async function get<T>(path: string, params?: Record<string, string>): Promise<T> {
  const url = new URL(`${BASE}${path}`, window.location.origin);
  if (params) {
    for (const [k, v] of Object.entries(params)) {
      if (v) url.searchParams.set(k, v);
    }
  }
  const res = await fetch(url.toString());
  if (!res.ok) {
    throw new Error(`API error: ${res.status} ${res.statusText}`);
  }
  return res.json() as Promise<T>;
}

export function useApi() {
  // GET /api/runs
  async function fetchRuns(): Promise<Run[]> {
    return get<Run[]>("/runs");
  }

  // GET /api/events?run_id=&story_id=&event_type=&limit=
  async function fetchEvents(filters?: {
    run_id?: string;
    story_id?: string;
    event_type?: string;
    limit?: number;
  }): Promise<MonitorEvent[]> {
    const params: Record<string, string> = {};
    if (filters?.run_id) params.run_id = filters.run_id;
    if (filters?.story_id) params.story_id = filters.story_id;
    if (filters?.event_type) params.event_type = filters.event_type;
    if (filters?.limit) params.limit = String(filters.limit);
    return get<MonitorEvent[]>("/events", params);
  }

  // GET /api/analytics/timeline/:runId
  async function fetchTimeline(runId: string): Promise<StoryTimelineEntry[]> {
    return get<StoryTimelineEntry[]>(`/analytics/timeline/${runId}`);
  }

  // GET /api/analytics/errors?run_id=
  async function fetchErrors(runId?: string): Promise<ErrorBreakdown[]> {
    const params: Record<string, string> = {};
    if (runId) params.run_id = runId;
    return get<ErrorBreakdown[]>("/analytics/errors", params);
  }

  // GET /api/analytics/tools?run_id=
  async function fetchTools(runId?: string): Promise<ToolUsageEntry[]> {
    const params: Record<string, string> = {};
    if (runId) params.run_id = runId;
    return get<ToolUsageEntry[]>("/analytics/tools", params);
  }

  // GET /api/analytics/summary/:runId
  async function fetchSummary(runId: string): Promise<RunSummary> {
    return get<RunSummary>(`/analytics/summary/${runId}`);
  }

  // GET /api/analytics/agents?run_id=
  async function fetchAgents(runId?: string): Promise<AgentDuration[]> {
    const params: Record<string, string> = {};
    if (runId) params.run_id = runId;
    return get<AgentDuration[]>("/analytics/agents", params);
  }

  return {
    fetchRuns,
    fetchEvents,
    fetchTimeline,
    fetchErrors,
    fetchTools,
    fetchSummary,
    fetchAgents,
  };
}
