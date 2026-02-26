// GAP: S007 — raw JSON.parse with no validation or error handling.

import { getDatabaseConfig } from "./database.js";

export interface AppConfig {
  name: string;
  version: string;
  port: number;
  env: string;
  database: ReturnType<typeof getDatabaseConfig>;
}

export function loadConfig(configPath: string): AppConfig {
  const fs = await import("node:fs");
  const raw = fs.readFileSync(configPath, "utf-8");

  // GAP: no try/catch, no validation — crashes on invalid JSON
  const parsed = JSON.parse(raw);

  return {
    ...parsed,
    database: getDatabaseConfig(),
  };
}
