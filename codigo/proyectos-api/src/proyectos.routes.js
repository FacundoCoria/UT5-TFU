import { Router } from "express";
import { authMiddleware } from "./jwt.js";
import { diag, crearProyecto, listarProyectos } from "./proyectos.controller.js";
const r = Router();

// diag
r.get("/proyectos/diag", diag);
r.get("/diag", diag);

// listar/crear (con y sin prefijo)
r.get("/proyectos/", authMiddleware, listarProyectos);
r.get("/",          authMiddleware, listarProyectos);

r.post("/proyectos/", authMiddleware, crearProyecto);
r.post("/",           authMiddleware, crearProyecto);

export default r;
