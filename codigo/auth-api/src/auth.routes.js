import { Router } from "express";
import { register, login, me } from "./auth.controller.js";
import { authMiddleware, signValet } from "./jwt.js";
import pool from "./db.js";

const r = Router();

// Duplicamos health/diag acá también (belt & suspenders). Si en el futuro
// movés app.use(routes), igual siguen estando bajo /auth/*.
r.get("/auth/health", (req, res) => {
  res.json({ ok: true, service: process.env.SERVICE_NAME || "auth-api" });
});
r.get("/auth/diag", async (req, res) => {
  try {
    const [rows] = await pool.query("SELECT 1 AS ok");
    res.json({ db: "up", result: rows?.[0] });
  } catch (e) {
    res.status(500).json({ db: "down", error: String(e?.message || e) });
  }
});

// Auth real
r.post("/auth/register", register);
r.post("/auth/login",    login);
r.get ("/auth/me",       authMiddleware, me);

// Valet key endpoint - issues a short-lived token for a specific resource
// Example: POST /auth/valet { "resource": "uploads/123.png" }
r.post("/auth/valet", authMiddleware, (req, res) => {
  const { resource } = req.body || {};
  if (!resource) return res.status(400).json({ error: "missing_resource" });
  const valet = signValet({ userId: req.user?.id, resource });
  res.json({ token: valet, expires_in: process.env.VALET_EXPIRES || "60s" });
});

export default r;
