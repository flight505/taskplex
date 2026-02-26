// GAP: S016 — only access tokens, no refresh token support

import { Router, Request, Response } from "express";
import { getUserByEmail } from "../models/user.js";
import { comparePassword, generateToken } from "../auth/helpers.js";

const router = Router();

// POST /auth/login
router.post("/login", async (req: Request, res: Response) => {
  const { email, password } = req.body;

  if (!email || !password) {
    res.status(400).json({ error: "Email and password required" });
    return;
  }

  const user = getUserByEmail(email);
  if (!user) {
    res.status(401).json({ error: "Invalid credentials" });
    return;
  }

  const valid = await comparePassword(password, user.passwordHash);
  if (!valid) {
    res.status(401).json({ error: "Invalid credentials" });
    return;
  }

  // GAP: only access token, no refresh token
  const accessToken = generateToken({ userId: user.id, email: user.email });

  res.json({ accessToken });
});

export { router as authRouter };
