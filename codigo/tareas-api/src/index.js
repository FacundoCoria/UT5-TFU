import express from "express";
import { createPool } from "mysql2/promise";
import routes from "./tareas.routes.js";

const app = express();
app.use(express.json());

// DB pool
export const pool = createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,          // proyectos_db
  port: Number(process.env.DB_PORT || 3306),
  waitForConnections: true,
  connectionLimit: 10,
});

// Health simple (sin auth, sin prefijo)
app.get("/health", (req, res) =>
  res.json({ ok: true, service: process.env.SERVICE_NAME || "tareas-api" })
);

// Montamos rutas en raíz (porque el gateway strippea /tareas/)
app.use("/", routes);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`tareas-api on ${PORT}`));
