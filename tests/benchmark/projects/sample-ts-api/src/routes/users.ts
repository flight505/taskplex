// BUG: S005 — unused import `Request` (only Router is used)
// GAP: S014 — no Zod validation on create/update bodies

import { Router, Request, Response } from "express";
import { requireAuth, AuthenticatedRequest } from "../auth/middleware.js";
import * as UserModel from "../models/user.js";
import { hashPassword } from "../auth/helpers.js";

const router = Router();

// GET /users
router.get("/", (_req: Request, res: Response) => {
  const users = UserModel.getAllUsers().map(({ passwordHash, ...u }) => u);
  res.json({ users });
});

// GET /users/:id
router.get("/:id", (req: Request, res: Response) => {
  const user = UserModel.getUserById(req.params.id);
  if (!user) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  const { passwordHash, ...safe } = user;
  res.json(safe);
});

// POST /users — GAP: no body validation
router.post("/", async (req: Request, res: Response) => {
  const { email, name, password } = req.body;
  const passwordHash = await hashPassword(password);
  const user = UserModel.createUser({ email, name, passwordHash });
  const { passwordHash: _, ...safe } = user;
  res.status(201).json(safe);
});

// PUT /users/:id — GAP: no body validation
router.put("/:id", requireAuth, (req: AuthenticatedRequest, res: Response) => {
  const user = UserModel.updateUser(req.params.id, req.body);
  if (!user) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  const { passwordHash, ...safe } = user;
  res.json(safe);
});

// DELETE /users/:id — GAP: hard delete, S009 wants soft delete
router.delete("/:id", requireAuth, (req: AuthenticatedRequest, res: Response) => {
  const deleted = UserModel.deleteUser(req.params.id);
  if (!deleted) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  res.status(204).end();
});

export { router as usersRouter };
