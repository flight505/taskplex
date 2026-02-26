// BUG: S006 — DB_PORT has no fallback, is undefined in local dev.

export interface DatabaseConfig {
  host: string;
  port: number;
  database: string;
  user: string;
  password: string;
}

export function getDatabaseConfig(): DatabaseConfig {
  return {
    host: process.env.DB_HOST ?? "localhost",
    // BUG: no fallback, and not parsed to number
    port: process.env.DB_PORT as unknown as number,
    database: process.env.DB_NAME ?? "sample_app",
    user: process.env.DB_USER ?? "postgres",
    password: process.env.DB_PASSWORD ?? "postgres",
  };
}
