import pool from "./db.js";
import cache from "./cache.js";

export async function listUsers(req, res) {
  const [rows] = await pool.query(
    "SELECT id, nombre, email, creado_en FROM usuarios_db.usuarios ORDER BY id"
  );
  res.json(rows);
}

export async function getUser(req, res) {
  console.log("GET /usuarios/:id", req.params.id);
  const id = String(req.params.id);
  // Cache-aside: try cache first (Redis)
  try {
    const cached = await cache.get(`user:${id}`);
    if (cached) return res.json(cached);
  } catch (e) {
    // proceed to DB on cache error
    console.error("cache read failed", e?.message || e);
  }

  const [rows] = await pool.query(
    "SELECT id, nombre, email, creado_en FROM usuarios_db.usuarios WHERE id=?",
    [id]
  );
  if (!rows[0]) return res.status(404).json({ error: "not_found" });
  // Populate cache
  try { await cache.set(`user:${id}`, rows[0], 60_000); } catch (e) { console.error(e); }
  res.json(rows[0]);
}

export async function createUser(req, res) {
  const { nombre, email } = req.body || {};
  if (!nombre || !email) return res.status(400).json({ error: "bad_request" });
  try {
    const [r] = await pool.query(
      "INSERT INTO usuarios_db.usuarios(nombre,email,hash) VALUES(?,?,?)",
      [nombre, email, ""]
    );
    const newUser = { id: r.insertId, nombre, email };
    // invalidate any related caches (list)
    try { await cache.del("users:list"); await cache.set(`user:${r.insertId}`, newUser, 60_000); } catch (e) { console.error(e); }
    res.status(201).json(newUser);
  } catch {
    res.status(409).json({ error: "email_exists" });
  }
}

export async function updateUser(req, res) {
  const { nombre, email } = req.body || {};
  const [r] = await pool.query(
    "UPDATE usuarios_db.usuarios SET nombre=?, email=? WHERE id=?",
    [nombre, email, req.params.id]
  );
  if (!r.affectedRows) return res.status(404).json({ error: "not_found" });
  const updated = { id: Number(req.params.id), nombre, email };
  try { await cache.del("users:list"); await cache.set(`user:${req.params.id}`, updated, 60_000); } catch (e) { console.error(e); }
  res.json(updated);
}

export async function deleteUser(req, res) {
  const [r] = await pool.query("DELETE FROM usuarios_db.usuarios WHERE id=?", [req.params.id]);
  if (!r.affectedRows) return res.status(404).json({ error: "not_found" });
  try { await cache.del("users:list"); await cache.del(`user:${req.params.id}`); } catch (e) { console.error(e); }
  res.status(204).send();
}
