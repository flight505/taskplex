import type { EventInput } from "./db";

// ---------------------------------------------------------------------------
// Validation errors
// ---------------------------------------------------------------------------

export class EventValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EventValidationError";
  }
}

// ---------------------------------------------------------------------------
// Valid values
// ---------------------------------------------------------------------------

const VALID_SOURCES = new Set(["hook", "orchestrator", "parallel"]);

// ---------------------------------------------------------------------------
// processEvent — validate and normalize raw input
// ---------------------------------------------------------------------------

export function processEvent(raw: unknown): EventInput {
  if (raw === null || raw === undefined || typeof raw !== "object") {
    throw new EventValidationError("Event must be a non-null JSON object.");
  }

  const obj = raw as Record<string, unknown>;

  // event_type is required
  if (typeof obj.event_type !== "string" || obj.event_type.trim() === "") {
    throw new EventValidationError(
      "Field 'event_type' is required and must be a non-empty string.",
    );
  }

  // source is required and must be one of the valid values
  if (typeof obj.source !== "string" || !VALID_SOURCES.has(obj.source)) {
    throw new EventValidationError(
      `Field 'source' is required and must be one of: ${[...VALID_SOURCES].join(", ")}.`,
    );
  }

  // payload: if provided as string, must parse as JSON object
  let payload: string | Record<string, unknown> = "{}";
  if (obj.payload !== undefined && obj.payload !== null) {
    if (typeof obj.payload === "string") {
      try {
        const parsed = JSON.parse(obj.payload);
        if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
          throw new EventValidationError(
            "Field 'payload' string must parse as a JSON object (not array or primitive).",
          );
        }
        payload = obj.payload;
      } catch (e) {
        if (e instanceof EventValidationError) throw e;
        throw new EventValidationError(
          `Field 'payload' is not valid JSON: ${(e as Error).message}`,
        );
      }
    } else if (typeof obj.payload === "object" && !Array.isArray(obj.payload)) {
      payload = obj.payload as Record<string, unknown>;
    } else {
      throw new EventValidationError(
        "Field 'payload' must be a JSON object or a JSON string encoding an object.",
      );
    }
  }

  // Optional string fields
  const optStr = (key: string): string | null => {
    const v = obj[key];
    if (v === undefined || v === null) return null;
    if (typeof v !== "string") {
      throw new EventValidationError(
        `Field '${key}' must be a string if provided.`,
      );
    }
    return v;
  };

  // Optional integer fields
  const optInt = (key: string): number | null => {
    const v = obj[key];
    if (v === undefined || v === null) return null;
    if (typeof v !== "number" || !Number.isInteger(v)) {
      throw new EventValidationError(
        `Field '${key}' must be an integer if provided.`,
      );
    }
    return v;
  };

  const event: EventInput = {
    source: obj.source as EventInput["source"],
    event_type: obj.event_type.trim(),
    timestamp: optStr("timestamp") ?? undefined,
    session_id: optStr("session_id"),
    run_id: optStr("run_id"),
    story_id: optStr("story_id"),
    wave: optInt("wave"),
    batch: optInt("batch"),
    payload,
  };

  return enrichEvent(event);
}

// ---------------------------------------------------------------------------
// enrichEvent — add defaults for missing fields
// ---------------------------------------------------------------------------

export function enrichEvent(event: EventInput): EventInput {
  return {
    ...event,
    timestamp: event.timestamp || new Date().toISOString(),
    payload: event.payload ?? "{}",
  };
}
