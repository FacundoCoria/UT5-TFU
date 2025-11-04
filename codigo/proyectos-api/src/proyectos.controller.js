import pool from "./db.js";

export async function diag(_req, res) {
  try {
    const [rows] = await pool.query("SELECT 1 AS ok");
    res.json({ db: "up", result: rows[0] });
  } catch (e) {
    console.error("diag error:", e);
    res.status(500).json({ db: "down", error: "db_error" });
  }
}

export async function crearProyecto(req, res, next) {
  try {
    const { nombre, descripcion } = req.body || {};
    if (!nombre) return res.status(400).json({ error: "bad_request" });

    const ownerId = req.user?.sub;
    if (!ownerId) return res.status(401).json({ error: "unauthorized" });

    const [r] = await pool.query(
      "INSERT INTO proyectos_db.proyectos(nombre, descripcion, owner_usuario_id) VALUES(?,?,?)",
      [nombre, descripcion || null, ownerId]
    );
    res.status(201).json({ id: r.insertId, nombre, descripcion, owner_usuario_id: ownerId });
  } catch (e) {
    next(e);
  }
}

export async function listarProyectos(req, res, next) {
  try {
    const ownerId = req.user?.sub;
    const [rows] = await pool.query(
      "SELECT id, nombre, descripcion, owner_usuario_id, creado_en FROM proyectos_db.proyectos WHERE owner_usuario_id = ? ORDER BY id DESC",
      [ownerId]
    );
    res.json(rows);
  } catch (e) {
    next(e);
  }
}
