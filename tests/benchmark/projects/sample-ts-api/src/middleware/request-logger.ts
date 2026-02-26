// GAP: S008 — basic request logger, no structured format, no correlation IDs

import type { Request, Response, NextFunction } from "express";

// GAP: S008 — console.log instead of structured logging
// GAP: S008 — no correlation ID generation or propagation
export function requestLogger(req: Request, _res: Response, next: NextFunction) {
  const start = Date.now();
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);

  _res.on("finish", () => {
    const duration = Date.now() - start;
    console.log(
      `[${new Date().toISOString()}] ${req.method} ${req.path} ${_res.statusCode} ${duration}ms`,
    );
  });

  next();
}
