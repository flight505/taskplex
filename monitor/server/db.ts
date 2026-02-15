import { Database } from "bun:sqlite";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface Event {
  id: number;
  timestamp: string;
  source: "hook" | "orchestrator" | "parallel";
  event_type: string;
  session_id: string | null;
  run_id: string | null;
  story_id: string | null;
  wave: number | null;
  batch: number | null;
  payload: string;
  created_at: string;
}

export interface EventInput {
  timestamp?: string;
  source: "hook" | "orchestrator" | "parallel";
  event_type: string;
  session_id?: string | null;
  run_id?: string | null;
  story_id?: string | null;
  wave?: number | null;
  batch?: number | null;
  payload?: string | Record<string, unknown>;
}

export interface Run {
  id: string;
  started_at: string;
  ended_at: string | null;
  mode: "sequential" | "parallel";
  model: string | null;
  branch: string | null;
  total_stories: number | null;
  completed: number;
  skipped: number;
  config: string;
}

export interface RunInput {
  id: string;
  started_at: string;
  ended_at?: string | null;
  mode: "sequential" | "parallel";
  model?: string | null;
  branch?: string | null;
  total_stories?: number | null;
  completed?: number;
  skipped?: number;
  config?: string | Record<string, unknown>;
}

export interface EventFilters {
  run_id?: string;
  story_id?: string;
  event_type?: string;
  since?: string;
  limit?: number;
}

// ---------------------------------------------------------------------------
// Schema & migrations
// ---------------------------------------------------------------------------

const SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp TEXT NOT NULL,
  source TEXT NOT NULL,
  event_type TEXT NOT NULL,
  session_id TEXT,
  run_id TEXT,
  story_id TEXT,
  wave INTEGER,
  batch INTEGER,
  payload TEXT NOT NULL DEFAULT '{}',
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  mode TEXT NOT NULL,
  model TEXT,
  branch TEXT,
  total_stories INTEGER,
  completed INTEGER DEFAULT 0,
  skipped INTEGER DEFAULT 0,
  config TEXT DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_events_run_id ON events(run_id);
CREATE INDEX IF NOT EXISTS idx_events_story_id ON events(story_id);
CREATE INDEX IF NOT EXISTS idx_events_event_type ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);
`;

// ---------------------------------------------------------------------------
// Singleton
// ---------------------------------------------------------------------------

let db: Database | null = null;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export function initDb(dbPath?: string): Database {
  const path =
    dbPath ?? process.env.TASKPLEX_MONITOR_DB ?? "taskplex-monitor.db";

  db = new Database(path, { create: true });
  db.exec("PRAGMA journal_mode = WAL;");
  db.exec("PRAGMA busy_timeout = 5000;");
  db.exec(SCHEMA_SQL);

  return db;
}

export function getDb(): Database {
  if (!db) {
    throw new Error(
      "Database not initialized. Call initDb() before accessing the database.",
    );
  }
  return db;
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

export function insertEvent(event: EventInput): number {
  const d = getDb();

  const payload =
    typeof event.payload === "object"
      ? JSON.stringify(event.payload)
      : (event.payload ?? "{}");

  const stmt = d.prepare(`
    INSERT INTO events (timestamp, source, event_type, session_id, run_id, story_id, wave, batch, payload)
    VALUES ($timestamp, $source, $event_type, $session_id, $run_id, $story_id, $wave, $batch, $payload)
  `);

  const result = stmt.run({
    $timestamp: event.timestamp ?? new Date().toISOString(),
    $source: event.source,
    $event_type: event.event_type,
    $session_id: event.session_id ?? null,
    $run_id: event.run_id ?? null,
    $story_id: event.story_id ?? null,
    $wave: event.wave ?? null,
    $batch: event.batch ?? null,
    $payload: payload,
  });

  return Number(result.lastInsertRowid);
}

export function getEvents(filters: EventFilters): Event[] {
  const d = getDb();

  const conditions: string[] = [];
  const params: Record<string, string | number> = {};

  if (filters.run_id) {
    conditions.push("run_id = $run_id");
    params.$run_id = filters.run_id;
  }
  if (filters.story_id) {
    conditions.push("story_id = $story_id");
    params.$story_id = filters.story_id;
  }
  if (filters.event_type) {
    conditions.push("event_type = $event_type");
    params.$event_type = filters.event_type;
  }
  if (filters.since) {
    conditions.push("timestamp >= $since");
    params.$since = filters.since;
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
  const limit = filters.limit ?? 1000;

  const stmt = d.prepare(
    `SELECT * FROM events ${where} ORDER BY id ASC LIMIT $limit`,
  );
  params.$limit = limit;

  return stmt.all(params) as Event[];
}

// ---------------------------------------------------------------------------
// Runs
// ---------------------------------------------------------------------------

export function insertRun(run: RunInput): void {
  const d = getDb();

  const config =
    typeof run.config === "object"
      ? JSON.stringify(run.config)
      : (run.config ?? "{}");

  const stmt = d.prepare(`
    INSERT INTO runs (id, started_at, ended_at, mode, model, branch, total_stories, completed, skipped, config)
    VALUES ($id, $started_at, $ended_at, $mode, $model, $branch, $total_stories, $completed, $skipped, $config)
  `);

  stmt.run({
    $id: run.id,
    $started_at: run.started_at,
    $ended_at: run.ended_at ?? null,
    $mode: run.mode,
    $model: run.model ?? null,
    $branch: run.branch ?? null,
    $total_stories: run.total_stories ?? null,
    $completed: run.completed ?? 0,
    $skipped: run.skipped ?? 0,
    $config: config,
  });
}

export function updateRun(id: string, updates: Partial<RunInput>): void {
  const d = getDb();

  const setClauses: string[] = [];
  const params: Record<string, string | number | null> = { $id: id };

  if (updates.ended_at !== undefined) {
    setClauses.push("ended_at = $ended_at");
    params.$ended_at = updates.ended_at ?? null;
  }
  if (updates.mode !== undefined) {
    setClauses.push("mode = $mode");
    params.$mode = updates.mode;
  }
  if (updates.model !== undefined) {
    setClauses.push("model = $model");
    params.$model = updates.model ?? null;
  }
  if (updates.branch !== undefined) {
    setClauses.push("branch = $branch");
    params.$branch = updates.branch ?? null;
  }
  if (updates.total_stories !== undefined) {
    setClauses.push("total_stories = $total_stories");
    params.$total_stories = updates.total_stories ?? null;
  }
  if (updates.completed !== undefined) {
    setClauses.push("completed = $completed");
    params.$completed = updates.completed;
  }
  if (updates.skipped !== undefined) {
    setClauses.push("skipped = $skipped");
    params.$skipped = updates.skipped;
  }
  if (updates.config !== undefined) {
    setClauses.push("config = $config");
    params.$config =
      typeof updates.config === "object"
        ? JSON.stringify(updates.config)
        : (updates.config ?? "{}");
  }

  if (setClauses.length === 0) return;

  const stmt = d.prepare(
    `UPDATE runs SET ${setClauses.join(", ")} WHERE id = $id`,
  );
  stmt.run(params);
}

export function getRuns(limit?: number): Run[] {
  const d = getDb();
  const stmt = d.prepare(
    "SELECT * FROM runs ORDER BY started_at DESC LIMIT $limit",
  );
  return stmt.all({ $limit: limit ?? 50 }) as Run[];
}

export function getRunById(id: string): Run | null {
  const d = getDb();
  const stmt = d.prepare("SELECT * FROM runs WHERE id = $id");
  return (stmt.get({ $id: id }) as Run) ?? null;
}
