import express from "express";
import { corsMiddleware } from "./middleware/index.js";
import { usersRouter } from "./routes/users.js";
import { postsRouter } from "./routes/posts.js";
import { authRouter } from "./routes/auth.js";
import { logger } from "./utils/logger.js";

const app = express();

app.use(express.json());
app.use(corsMiddleware);

// Health check
app.get("/health", (_req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

app.get("/ready", (_req, res) => {
  res.json({ status: "ready" });
});

// Routes
app.use("/auth", authRouter);
app.use("/users", usersRouter);
app.use("/posts", postsRouter);

// Start server
const PORT = parseInt(process.env.PORT ?? "3000", 10);

export function startServer(port = PORT) {
  return app.listen(port, () => {
    logger.info(`Server running on port ${port}`);
  });
}

export { app };

// Only start if run directly
if (process.argv[1]?.includes("server")) {
  startServer();
}
