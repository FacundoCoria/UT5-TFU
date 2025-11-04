import pool from "./db.js";
import { enqueueTask } from "./queue.js";

// GET /?proyecto_id=#
export async function listTasks(req, res) {
  const { proyecto_id } = req.query || {};
  if (proyecto_id) {
    const [rows] = await pool.query(
      `SELECT id, proyecto_id, titulo, estado, asignado_a_usuario_id, creado_en
       FROM proyectos_db.tareas
       WHERE proyecto_id = ?
       ORDER BY id DESC`,
      [proyecto_id]
    );
    return res.json(rows);
  }
  const [rows] = await pool.query(
    `SELECT id, proyecto_id, titulo, estado, asignado_a_usuario_id, creado_en
     FROM proyectos_db.tareas
     ORDER BY id DESC`
  );
  return res.json(rows);
}

// GET /:id
export async function getTask(req, res) {
  const { id } = req.params;
  const [rows] = await pool.query(
    `SELECT id, proyecto_id, titulo, estado, asignado_a_usuario_id, creado_en
     FROM proyectos_db.tareas
     WHERE id = ?`,
    [id]
  );
  const t = rows[0];
  if (!t) return res.status(404).json({ error: "not_found" });
  return res.json(t);
}

// POST /
export async function createTask(req, res) {
  const { proyecto_id, titulo, asignado_a_usuario_id } = req.body || {};
  if (!proyecto_id || !titulo) return res.status(400).json({ error: "bad_request" });
  // If queue-based load leveling enabled, enqueue and return 202
  if (process.env.USE_QUEUE === "1") {
    try {
      const queued = await enqueueTask({ proyecto_id, titulo, asignado_a_usuario_id });
      // Enqueued: return 202 Accepted to indicate async processing
      return res.status(202).json(queued);
    } catch (e) {
      return res.status(500).json({ error: "enqueue_failed", message: String(e?.message || e) });
    }
  }

  // Default immediate insertion (synchronous)
  const [r] = await pool.query(
    `INSERT INTO proyectos_db.tareas(proyecto_id, titulo, asignado_a_usuario_id)
     VALUES(?,?,?)`,
    [proyecto_id, titulo, asignado_a_usuario_id ?? null]
  );

  const [rows] = await pool.query(
    `SELECT id, proyecto_id, titulo, estado, asignado_a_usuario_id, creado_en
     FROM proyectos_db.tareas
     WHERE id = ?`,
    [r.insertId]
  );
  return res.status(201).json(rows[0]);
}

// PUT /:id
export async function updateTask(req, res) {
  const { id } = req.params;
  const { proyecto_id, titulo, estado, asignado_a_usuario_id } = req.body || {};

  if (!proyecto_id && !titulo && !estado && typeof asignado_a_usuario_id === "undefined") {
    return res.status(400).json({ error: "bad_request" });
  }

  const fields = [];
  const params = [];
  if (proyecto_id) { fields.push("proyecto_id = ?"); params.push(proyecto_id); }
  if (titulo) { fields.push("titulo = ?"); params.push(titulo); }
  if (estado) { fields.push("estado = ?"); params.push(estado); }
  if (typeof asignado_a_usuario_id !== "undefined") {
    fields.push("asignado_a_usuario_id = ?");
    params.push(asignado_a_usuario_id);
  }
  params.push(id);

  const [r] = await pool.query(
    `UPDATE proyectos_db.tareas SET ${fields.join(", ")} WHERE id = ?`,
    params
  );
  if (r.affectedRows === 0) return res.status(404).json({ error: "not_found" });

  const [rows] = await pool.query(
    `SELECT id, proyecto_id, titulo, estado, asignado_a_usuario_id, creado_en
     FROM proyectos_db.tareas
     WHERE id = ?`,
    [id]
  );
  return res.json(rows[0]);
}

// PATCH /:id/estado
export async function patchTaskState(req, res) {
  const { id } = req.params;
  const { estado } = req.body || {};
  if (!estado) return res.status(400).json({ error: "bad_request" });

  const [r] = await pool.query(
    `UPDATE proyectos_db.tareas SET estado = ? WHERE id = ?`,
    [estado, id]
  );
  if (r.affectedRows === 0) return res.status(404).json({ error: "not_found" });

  const [rows] = await pool.query(
    `SELECT id, proyecto_id, titulo, estado, asignado_a_usuario_id, creado_en
     FROM proyectos_db.tareas
     WHERE id = ?`,
    [id]
  );
  return res.json(rows[0]);
}

// DELETE /:id
export async function deleteTask(req, res) {
  const { id } = req.params;
  const [r] = await pool.query(
    `DELETE FROM proyectos_db.tareas WHERE id = ?`,
    [id]
  );
  if (r.affectedRows === 0) return res.status(404).json({ error: "not_found" });
  return res.json({ ok: 1 });
}
