import {
  initDb,
  getDb,
  insertEvent,
  insertRun,
  updateRun,
  getEvents,
  getRuns,
  getRunById,
  type RunInput,
  type EventFilters,
} from "./db";
import { processEvent, EventValidationError } from "./events";
import {
  getStoryTimeline,
  getErrorBreakdown,
  getToolUsage,
  getRunSummary,
  getAgentDurations,
} from "./analytics";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const PORT = parseInt(process.env.TASKPLEX_MONITOR_PORT ?? "4444", 10);
const SERVE_CLIENT = process.env.SERVE_CLIENT === "true";

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

const db = initDb();

// ---------------------------------------------------------------------------
// WebSocket client tracking
// ---------------------------------------------------------------------------

const wsClients = new Set<ServerWebSocket<unknown>>();

type ServerWebSocket<T> = {
  send(data: string | ArrayBuffer | Uint8Array): void;
  close(): void;
  data: T;
};

function broadcast(data: unknown): void {
  const json = JSON.stringify(data);
  for (const ws of wsClients) {
    try {
      ws.send(json);
    } catch {
      wsClients.delete(ws);
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function errorResponse(message: string, status = 400): Response {
  return jsonResponse({ error: message }, status);
}

function extractParam(url: URL, name: string): string | undefined {
  return url.searchParams.get(name) ?? undefined;
}

function extractRunIdFromPath(pathname: string, prefix: string): string | null {
  const match = pathname.match(new RegExp(`^${prefix}/([^/]+)$`));
  return match ? match[1] : null;
}

// ---------------------------------------------------------------------------
// Route handlers
// ---------------------------------------------------------------------------

async function handlePostEvents(req: Request): Promise<Response> {
  try {
    const body = await req.json();
    const event = processEvent(body);
    const id = insertEvent(event);
    broadcast({ type: "event", event: { id, ...event } });
    return jsonResponse({ id }, 201);
  } catch (e) {
    if (e instanceof EventValidationError) {
      return errorResponse(e.message, 400);
    }
    return errorResponse(`Failed to process event: ${(e as Error).message}`, 500);
  }
}

async function handlePostRuns(req: Request): Promise<Response> {
  try {
    const body = (await req.json()) as RunInput;
    if (!body.id || !body.started_at || !body.mode) {
      return errorResponse("Fields 'id', 'started_at', and 'mode' are required.", 400);
    }
    insertRun(body);
    broadcast({ type: "run.created", run: body });
    return jsonResponse({ id: body.id }, 201);
  } catch (e) {
    return errorResponse(`Failed to create run: ${(e as Error).message}`, 500);
  }
}

async function handlePatchRun(req: Request, runId: string): Promise<Response> {
  try {
    const body = await req.json();
    updateRun(runId, body as Partial<RunInput>);
    const updated = getRunById(runId);
    if (updated) {
      broadcast({ type: "run.updated", run: updated });
    }
    return jsonResponse({ ok: true });
  } catch (e) {
    return errorResponse(`Failed to update run: ${(e as Error).message}`, 500);
  }
}

function handleGetEvents(url: URL): Response {
  const filters: EventFilters = {
    run_id: extractParam(url, "run_id"),
    story_id: extractParam(url, "story_id"),
    event_type: extractParam(url, "event_type"),
    since: extractParam(url, "since"),
    limit: extractParam(url, "limit") ? parseInt(extractParam(url, "limit")!, 10) : undefined,
  };
  const events = getEvents(filters);
  return jsonResponse(events);
}

function handleGetRuns(): Response {
  return jsonResponse(getRuns());
}

function handleGetRunById(runId: string): Response {
  const run = getRunById(runId);
  if (!run) return errorResponse("Run not found.", 404);
  return jsonResponse(run);
}

function handleHealth(): Response {
  const d = getDb();
  const eventCount = (
    d.prepare("SELECT COUNT(*) AS c FROM events").get() as { c: number }
  ).c;
  const runCount = (
    d.prepare("SELECT COUNT(*) AS c FROM runs").get() as { c: number }
  ).c;
  return jsonResponse({ status: "ok", events: eventCount, runs: runCount });
}

// ---------------------------------------------------------------------------
// Intervention queue (live user commands)
// ---------------------------------------------------------------------------

interface Intervention {
  id: number;
  action: "skip" | "hint" | "pause" | "resume";
  story_id?: string;
  message?: string;
  created_at: string;
  consumed: boolean;
}

// Create interventions table on startup
(() => {
  const d = getDb();
  d.run(`
    CREATE TABLE IF NOT EXISTS interventions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      action TEXT NOT NULL,
      story_id TEXT,
      message TEXT,
      run_id TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      consumed INTEGER DEFAULT 0
    )
  `);
})();

async function handlePostIntervention(req: Request): Promise<Response> {
  try {
    const body = await req.json() as {
      action: string;
      story_id?: string;
      message?: string;
      run_id?: string;
    };

    if (!body.action || !["skip", "hint", "pause", "resume"].includes(body.action)) {
      return errorResponse("'action' must be one of: skip, hint, pause, resume", 400);
    }

    const d = getDb();
    const stmt = d.prepare(
      "INSERT INTO interventions (action, story_id, message, run_id) VALUES (?, ?, ?, ?)"
    );
    const result = stmt.run(body.action, body.story_id ?? null, body.message ?? null, body.run_id ?? null);

    const intervention = {
      id: result.lastInsertRowid,
      action: body.action,
      story_id: body.story_id,
      message: body.message,
    };

    broadcast({ type: "intervention.created", intervention });
    return jsonResponse(intervention, 201);
  } catch (e) {
    return errorResponse(`Failed to create intervention: ${(e as Error).message}`, 500);
  }
}

function handleGetInterventions(url: URL): Response {
  const d = getDb();
  const runId = extractParam(url, "run_id");
  const pending = extractParam(url, "pending");

  let query = "SELECT * FROM interventions WHERE 1=1";
  const params: string[] = [];

  if (runId) {
    query += " AND run_id = ?";
    params.push(runId);
  }
  if (pending === "true") {
    query += " AND consumed = 0";
  }

  query += " ORDER BY created_at DESC LIMIT 50";

  const stmt = d.prepare(query);
  const rows = stmt.all(...params);
  return jsonResponse(rows);
}

function handleConsumeIntervention(url: URL): Response {
  const d = getDb();
  const runId = extractParam(url, "run_id");

  if (!runId) {
    return errorResponse("'run_id' query parameter is required", 400);
  }

  // Get the oldest unconsumed intervention for this run
  const stmt = d.prepare(
    "SELECT * FROM interventions WHERE run_id = ? AND consumed = 0 ORDER BY created_at ASC LIMIT 1"
  );
  const row = stmt.get(runId) as Intervention | undefined;

  if (!row) {
    return jsonResponse({ intervention: null });
  }

  // Mark as consumed
  d.prepare("UPDATE interventions SET consumed = 1 WHERE id = ?").run(row.id);

  broadcast({ type: "intervention.consumed", intervention: row });
  return jsonResponse({ intervention: row });
}

// Analytics
function handleTimeline(runId: string): Response {
  return jsonResponse(getStoryTimeline(runId));
}

function handleErrors(url: URL): Response {
  const runId = extractParam(url, "run_id");
  return jsonResponse(getErrorBreakdown(runId));
}

function handleTools(url: URL): Response {
  const runId = extractParam(url, "run_id");
  return jsonResponse(getToolUsage(runId));
}

function handleSummary(runId: string): Response {
  const summary = getRunSummary(runId);
  if (!summary) return errorResponse("Run not found.", 404);
  return jsonResponse(summary);
}

function handleAgents(url: URL): Response {
  const runId = extractParam(url, "run_id");
  return jsonResponse(getAgentDurations(runId));
}

// ---------------------------------------------------------------------------
// Static file serving (optional)
// ---------------------------------------------------------------------------

const CLIENT_DIR = new URL("../client/dist", import.meta.url).pathname;

async function serveStaticFile(pathname: string): Promise<Response | null> {
  if (!SERVE_CLIENT) return null;

  let filePath = pathname === "/" ? "/index.html" : pathname;
  filePath = `${CLIENT_DIR}${filePath}`;

  const file = Bun.file(filePath);
  if (await file.exists()) {
    return new Response(file, {
      headers: CORS_HEADERS,
    });
  }

  // SPA fallback: serve index.html for non-API routes
  const indexFile = Bun.file(`${CLIENT_DIR}/index.html`);
  if (await indexFile.exists()) {
    return new Response(indexFile, {
      headers: CORS_HEADERS,
    });
  }

  return null;
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

const server = Bun.serve({
  port: PORT,

  async fetch(req, server) {
    const url = new URL(req.url);
    const { pathname } = url;
    const method = req.method;

    // CORS preflight
    if (method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    // WebSocket upgrade
    if (pathname === "/ws") {
      const upgraded = server.upgrade(req);
      if (!upgraded) {
        return errorResponse("WebSocket upgrade failed.", 400);
      }
      return undefined as unknown as Response;
    }

    // --- API routes ---

    // POST /api/events
    if (method === "POST" && pathname === "/api/events") {
      return handlePostEvents(req);
    }

    // POST /api/runs
    if (method === "POST" && pathname === "/api/runs") {
      return handlePostRuns(req);
    }

    // PATCH /api/runs/:id
    if (method === "PATCH" && pathname.startsWith("/api/runs/")) {
      const runId = extractRunIdFromPath(pathname, "/api/runs");
      if (!runId) return errorResponse("Missing run id.", 400);
      return handlePatchRun(req, runId);
    }

    // GET /api/events
    if (method === "GET" && pathname === "/api/events") {
      return handleGetEvents(url);
    }

    // GET /api/runs
    if (method === "GET" && pathname === "/api/runs") {
      return handleGetRuns();
    }

    // GET /api/runs/:id
    if (method === "GET" && pathname.startsWith("/api/runs/") && !pathname.includes("/analytics")) {
      const runId = extractRunIdFromPath(pathname, "/api/runs");
      if (!runId) return errorResponse("Missing run id.", 400);
      return handleGetRunById(runId);
    }

    // GET /api/analytics/timeline/:runId
    if (method === "GET" && pathname.startsWith("/api/analytics/timeline/")) {
      const runId = extractRunIdFromPath(pathname, "/api/analytics/timeline");
      if (!runId) return errorResponse("Missing run id.", 400);
      return handleTimeline(runId);
    }

    // GET /api/analytics/errors
    if (method === "GET" && pathname === "/api/analytics/errors") {
      return handleErrors(url);
    }

    // GET /api/analytics/tools
    if (method === "GET" && pathname === "/api/analytics/tools") {
      return handleTools(url);
    }

    // GET /api/analytics/summary/:runId
    if (method === "GET" && pathname.startsWith("/api/analytics/summary/")) {
      const runId = extractRunIdFromPath(pathname, "/api/analytics/summary");
      if (!runId) return errorResponse("Missing run id.", 400);
      return handleSummary(runId);
    }

    // GET /api/analytics/agents
    if (method === "GET" && pathname === "/api/analytics/agents") {
      return handleAgents(url);
    }

    // POST /api/intervention
    if (method === "POST" && pathname === "/api/intervention") {
      return handlePostIntervention(req);
    }

    // GET /api/interventions
    if (method === "GET" && pathname === "/api/interventions") {
      return handleGetInterventions(url);
    }

    // POST /api/intervention/consume (orchestrator polls this)
    if (method === "POST" && pathname === "/api/intervention/consume") {
      return handleConsumeIntervention(url);
    }

    // GET /health
    if (method === "GET" && pathname === "/health") {
      return handleHealth();
    }

    // --- Static file serving ---
    const staticResponse = await serveStaticFile(pathname);
    if (staticResponse) return staticResponse;

    return errorResponse("Not found.", 404);
  },

  websocket: {
    open(ws) {
      wsClients.add(ws as unknown as ServerWebSocket<unknown>);
    },
    message(_ws, _message) {
      // Clients send no meaningful messages; server is push-only
    },
    close(ws) {
      wsClients.delete(ws as unknown as ServerWebSocket<unknown>);
    },
  },
});

// ---------------------------------------------------------------------------
// Startup log
// ---------------------------------------------------------------------------

const dbPath = process.env.TASKPLEX_MONITOR_DB ?? "taskplex-monitor.db";
console.error(`[taskplex-monitor] Server running on http://localhost:${server.port}`);
console.error(`[taskplex-monitor] Database: ${dbPath}`);
console.error(`[taskplex-monitor] WebSocket: ws://localhost:${server.port}/ws`);
if (SERVE_CLIENT) {
  console.error(`[taskplex-monitor] Serving client from ${CLIENT_DIR}`);
}
