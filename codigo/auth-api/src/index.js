import express from "express";
import routes from "./auth.routes.js";
import { reqLogger } from "./logger.js";
import { routesIntrospect } from "./routes-introspect.js";
import pool from "./db.js";

const app = express();
app.use(express.json());
app.use(reqLogger);

const serviceName = process.env.SERVICE_NAME || "auth-api";

/**
 * IMPORTANTE: estas rutas van ANTES de app.use(routes)
 * para que jamás queden tapadas por middlewares del router.
 * Las exponemos con y sin prefijo para funcionar igual
 * si algún día cambias el proxy.
 */
app.get("/health",       (req, res) => res.json({ ok: true, service: serviceName }));
app.get("/auth/health",  (req, res) => res.json({ ok: true, service: serviceName }));

app.get("/diag", async (req, res) => {
  try {
    const [rows] = await pool.query("SELECT 1 AS ok");
    res.json({ db: "up", result: rows?.[0] });
  } catch (e) {
    res.status(500).json({ db: "down", error: String(e?.message || e) });
  }
});
app.get("/auth/diag", async (req, res) => {
  try {
    const [rows] = await pool.query("SELECT 1 AS ok");
    res.json({ db: "up", result: rows?.[0] });
  } catch (e) {
    res.status(500).json({ db: "down", error: String(e?.message || e) });
  }
});

// Tus rutas de negocio
app.use(routes);

// Introspección (mantengo tus endpoints)
app.get("/__routes",      (req, res) => res.json(routesIntrospect(app)));
app.get("/auth/__routes", (req, res) => res.json(routesIntrospect(app)));

const PORT = process.env.PORT || 3000;
console.log(JSON.stringify({ at: new Date().toISOString(), evt: "BOOT", svc: serviceName }));
app.listen(PORT, () => console.log(`${serviceName} on ${PORT}`));
