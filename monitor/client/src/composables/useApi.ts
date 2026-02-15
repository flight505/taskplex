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
  const url = new URL(path, window.location.origin);
  url.pathname = `${BASE}${path}`;
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
  async function fetchRuns(): Promise<Run[]> {
    return get<Run[]>("/runs");
  }

  async function fetchEvents(filters?: {
    run_id?: string;
    story_id?: string;
    event_type?: string;
    source?: string;
    limit?: number;
  }): Promise<MonitorEvent[]> {
    const params: Record<string, string> = {};
    if (filters?.run_id) params.run_id = filters.run_id;
    if (filters?.story_id) params.story_id = filters.story_id;
    if (filters?.event_type) params.event_type = filters.event_type;
    if (filters?.source) params.source = filters.source;
    if (filters?.limit) params.limit = String(filters.limit);
    return get<MonitorEvent[]>("/events", params);
  }

  async function fetchTimeline(runId: string): Promise<StoryTimelineEntry[]> {
    return get<StoryTimelineEntry[]>(`/runs/${runId}/timeline`);
  }

  async function fetchErrors(runId?: string): Promise<ErrorBreakdown[]> {
    const path = runId ? `/runs/${runId}/errors` : "/errors";
    return get<ErrorBreakdown[]>(path);
  }

  async function fetchTools(runId?: string): Promise<ToolUsageEntry[]> {
    const path = runId ? `/runs/${runId}/tools` : "/tools";
    return get<ToolUsageEntry[]>(path);
  }

  async function fetchSummary(runId: string): Promise<RunSummary> {
    return get<RunSummary>(`/runs/${runId}/summary`);
  }

  async function fetchAgents(runId?: string): Promise<AgentDuration[]> {
    const path = runId ? `/runs/${runId}/agents` : "/agents";
    return get<AgentDuration[]>(path);
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
