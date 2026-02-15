import { getDb } from "./db";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface StoryTimelineEntry {
  story_id: string;
  started_at: string;
  ended_at: string | null;
  status: "completed" | "skipped" | "blocked" | "running" | "failed";
  attempts: number;
  wave: number | null;
  batch: number | null;
}

export interface ErrorBreakdown {
  category: string;
  count: number;
}

export interface ToolUsageEntry {
  tool_name: string;
  agent_type: string;
  count: number;
}

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

export interface AgentDuration {
  agent_type: string;
  avg_duration_seconds: number;
  min_duration_seconds: number;
  max_duration_seconds: number;
  invocations: number;
}

// ---------------------------------------------------------------------------
// Story timeline — per-story start/end for Gantt chart
// ---------------------------------------------------------------------------

export function getStoryTimeline(runId: string): StoryTimelineEntry[] {
  const d = getDb();

  const rows = d
    .prepare(
      `
    SELECT
      story_id,
      MIN(CASE WHEN event_type = 'story.start' THEN timestamp END) AS started_at,
      MAX(CASE WHEN event_type IN ('story.complete', 'story.skip', 'story.fail', 'story.blocked') THEN timestamp END) AS ended_at,
      MAX(CASE
        WHEN event_type = 'story.complete' THEN 'completed'
        WHEN event_type = 'story.skip' THEN 'skipped'
        WHEN event_type = 'story.blocked' THEN 'blocked'
        WHEN event_type = 'story.fail' THEN 'failed'
        ELSE NULL
      END) AS final_status,
      COUNT(CASE WHEN event_type = 'story.start' THEN 1 END) AS attempts,
      MAX(wave) AS wave,
      MAX(batch) AS batch
    FROM events
    WHERE run_id = $run_id AND story_id IS NOT NULL
    GROUP BY story_id
    ORDER BY MIN(id)
    `,
    )
    .all({ $run_id: runId }) as Array<{
    story_id: string;
    started_at: string | null;
    ended_at: string | null;
    final_status: string | null;
    attempts: number;
    wave: number | null;
    batch: number | null;
  }>;

  return rows.map((r) => ({
    story_id: r.story_id,
    started_at: r.started_at ?? "",
    ended_at: r.ended_at,
    status: (r.final_status as StoryTimelineEntry["status"]) ?? "running",
    attempts: r.attempts,
    wave: r.wave,
    batch: r.batch,
  }));
}

// ---------------------------------------------------------------------------
// Error breakdown — error categories with counts
// ---------------------------------------------------------------------------

export function getErrorBreakdown(runId?: string): ErrorBreakdown[] {
  const d = getDb();

  const whereClause = runId ? "AND run_id = $run_id" : "";
  const params: Record<string, string> = {};
  if (runId) params.$run_id = runId;

  const rows = d
    .prepare(
      `
    SELECT
      json_extract(payload, '$.category') AS category,
      COUNT(*) AS count
    FROM events
    WHERE event_type IN ('story.fail', 'error.categorized') ${whereClause}
      AND json_extract(payload, '$.category') IS NOT NULL
    GROUP BY category
    ORDER BY count DESC
    `,
    )
    .all(params) as Array<{ category: string; count: number }>;

  return rows;
}

// ---------------------------------------------------------------------------
// Tool usage — tool name + count grouped by agent type
// ---------------------------------------------------------------------------

export function getToolUsage(runId?: string): ToolUsageEntry[] {
  const d = getDb();

  const whereClause = runId ? "AND run_id = $run_id" : "";
  const params: Record<string, string> = {};
  if (runId) params.$run_id = runId;

  const rows = d
    .prepare(
      `
    SELECT
      json_extract(payload, '$.tool') AS tool_name,
      COALESCE(json_extract(payload, '$.agent_type'), 'unknown') AS agent_type,
      COUNT(*) AS count
    FROM events
    WHERE event_type = 'tool.use' ${whereClause}
      AND json_extract(payload, '$.tool') IS NOT NULL
    GROUP BY tool_name, agent_type
    ORDER BY count DESC
    `,
    )
    .all(params) as ToolUsageEntry[];

  return rows;
}

// ---------------------------------------------------------------------------
// Run summary — aggregated stats for a single run
// ---------------------------------------------------------------------------

export function getRunSummary(runId: string): RunSummary | null {
  const d = getDb();

  const run = d
    .prepare("SELECT * FROM runs WHERE id = $id")
    .get({ $id: runId }) as {
    id: string;
    started_at: string;
    ended_at: string | null;
    mode: string;
    model: string | null;
    branch: string | null;
    total_stories: number | null;
    completed: number;
    skipped: number;
    config: string;
  } | null;

  if (!run) return null;

  // Count blocked and failed from events
  const storyStats = d
    .prepare(
      `
    SELECT
      COUNT(DISTINCT CASE WHEN event_type = 'story.blocked' THEN story_id END) AS blocked,
      COUNT(DISTINCT CASE WHEN event_type = 'story.fail' THEN story_id END) AS failed
    FROM events
    WHERE run_id = $run_id
    `,
    )
    .get({ $run_id: runId }) as { blocked: number; failed: number };

  const total = run.total_stories ?? 0;
  let elapsedSeconds: number | null = null;

  if (run.started_at) {
    const endTime = run.ended_at ? new Date(run.ended_at) : new Date();
    const startTime = new Date(run.started_at);
    elapsedSeconds = Math.round(
      (endTime.getTime() - startTime.getTime()) / 1000,
    );
  }

  const errorRate = total > 0 ? storyStats.failed / total : 0;

  return {
    run_id: run.id,
    mode: run.mode,
    model: run.model,
    branch: run.branch,
    started_at: run.started_at,
    ended_at: run.ended_at,
    elapsed_seconds: elapsedSeconds,
    total_stories: total,
    completed: run.completed,
    skipped: run.skipped,
    blocked: storyStats.blocked,
    failed: storyStats.failed,
    error_rate: Math.round(errorRate * 10000) / 10000,
  };
}

// ---------------------------------------------------------------------------
// Agent durations — average duration per agent type
// ---------------------------------------------------------------------------

export function getAgentDurations(runId?: string): AgentDuration[] {
  const d = getDb();

  const whereClause = runId ? "AND e_start.run_id = $run_id" : "";
  const params: Record<string, string> = {};
  if (runId) params.$run_id = runId;

  // Pair subagent.start with subagent.end events to calculate duration
  const rows = d
    .prepare(
      `
    WITH agent_spans AS (
      SELECT
        e_start.story_id,
        json_extract(e_start.payload, '$.agent_type') AS agent_type,
        e_start.timestamp AS start_ts,
        MIN(e_end.timestamp) AS end_ts
      FROM events e_start
      LEFT JOIN events e_end
        ON e_end.run_id = e_start.run_id
        AND e_end.story_id = e_start.story_id
        AND e_end.event_type = 'subagent.end'
        AND e_end.id > e_start.id
        AND json_extract(e_end.payload, '$.agent_type') = json_extract(e_start.payload, '$.agent_type')
      WHERE e_start.event_type = 'subagent.start' ${whereClause}
        AND json_extract(e_start.payload, '$.agent_type') IS NOT NULL
      GROUP BY e_start.id
    )
    SELECT
      agent_type,
      ROUND(AVG(
        (julianday(end_ts) - julianday(start_ts)) * 86400
      ), 1) AS avg_duration_seconds,
      ROUND(MIN(
        (julianday(end_ts) - julianday(start_ts)) * 86400
      ), 1) AS min_duration_seconds,
      ROUND(MAX(
        (julianday(end_ts) - julianday(start_ts)) * 86400
      ), 1) AS max_duration_seconds,
      COUNT(*) AS invocations
    FROM agent_spans
    WHERE end_ts IS NOT NULL
    GROUP BY agent_type
    ORDER BY avg_duration_seconds DESC
    `,
    )
    .all(params) as AgentDuration[];

  return rows;
}
