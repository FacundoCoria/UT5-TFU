import { Router } from "express";
import jwt from "jsonwebtoken";
import {
  listTasks,
  getTask,
  createTask,
  updateTask,
  patchTaskState,
  deleteTask
} from "./tareas.controller.js";

const r = Router();
const secret = process.env.JWT_SECRET || "dev_secret";

function auth(req, res, next) {
  const h = req.headers.authorization || "";
  const token = h.startsWith("Bearer ") ? h.slice(7) : null;
  if (!token) return res.status(401).json({ error: "missing_token" });
  try {
    req.user = jwt.verify(token, secret);
    next();
  } catch {
    return res.status(401).json({ error: "invalid_token" });
  }
}

// OJO: SIN prefijo "tareas" acá. El gateway lo strippea.
r.get("/", auth, listTasks);
r.get("/:id", auth, getTask);
r.post("/", auth, createTask);
r.put("/:id", auth, updateTask);
r.patch("/:id/estado", auth, patchTaskState);
r.delete("/:id", auth, deleteTask);

export default r;
