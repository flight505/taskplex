// GAP: S014 — no Zod validation on create/update bodies

import { Router, Response } from "express";
import { requireAuth, AuthenticatedRequest } from "../auth/middleware.js";
import * as PostModel from "../models/post.js";

const router = Router();

// GET /posts
router.get("/", (_req: AuthenticatedRequest, res: Response) => {
  const posts = PostModel.getAllPosts();
  res.json({ posts });
});

// GET /posts/:id
router.get("/:id", (req: AuthenticatedRequest, res: Response) => {
  const post = PostModel.getPostById(req.params.id);
  if (!post) {
    res.status(404).json({ error: "Post not found" });
    return;
  }
  res.json(post);
});

// POST /posts — GAP: no body validation
router.post("/", requireAuth, (req: AuthenticatedRequest, res: Response) => {
  if (!req.user) {
    res.status(401).json({ error: "Not authenticated" });
    return;
  }
  const post = PostModel.createPost({
    title: req.body.title,
    body: req.body.body,
    authorId: req.user.userId,
  });
  res.status(201).json(post);
});

// PUT /posts/:id — GAP: no body validation
router.put("/:id", requireAuth, (req: AuthenticatedRequest, res: Response) => {
  const post = PostModel.updatePost(req.params.id, req.body);
  if (!post) {
    res.status(404).json({ error: "Post not found" });
    return;
  }
  res.json(post);
});

// DELETE /posts/:id
router.delete("/:id", requireAuth, (req: AuthenticatedRequest, res: Response) => {
  const deleted = PostModel.deletePost(req.params.id);
  if (!deleted) {
    res.status(404).json({ error: "Post not found" });
    return;
  }
  res.status(204).end();
});

export { router as postsRouter };
