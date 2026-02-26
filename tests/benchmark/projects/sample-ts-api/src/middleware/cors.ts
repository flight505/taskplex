// BUG: S005 — unused import NextFunction
import { Request, Response, NextFunction } from "express";

export function corsMiddleware(req: Request, res: Response, next: (err?: Error) => void): void {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");

  if (req.method === "OPTIONS") {
    res.status(204).end();
    return;
  }

  next();
}
