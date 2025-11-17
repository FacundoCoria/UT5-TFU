// app.js (Monolito)
import express from "express";
import dotenv from "dotenv";
dotenv.config();

import xmlparser from "express-xml-bodyparser"; // SOAP XML parser

// IMPORTS DE LOS MÓDULOS REST
import authRoutes from "./codigo/auth-api/src/auth.routes.js";
import usuarioRoutes from "./codigo/usuarios-api/src/user.routes.js";
import proyectoRoutes from "./codigo/proyectos-api/src/proyectos.routes.js";
import tareasRoutes from "./codigo/tareas-api/src/tareas.routes.js";
import { pool } from "./db.js";

const app = express();

// Middleware JSON y XML
app.use(express.json());
app.use(xmlparser());

// Health del monolito
app.get("/health", (req, res) => {
  res.json({ ok: true, service: "monolito" });
});

// Rutas rest del monolito
app.use("/", authRoutes);

app.use("/usuarios", usuarioRoutes);

app.use("/proyectos", proyectoRoutes);
app.use("/", proyectoRoutes); // compatibilidad vieja

app.use("/tareas", tareasRoutes);

// Endpoint SOAP - GET USUARIO por id
app.post("/soap/usuarios", async (req, res) => {
  try {
    console.log("SOAP BODY:", JSON.stringify(req.body, null, 2));

    const userId =
      req.body?.["soap:envelope"]?.["soap:body"]?.[0]?.["getusuariorequest"]?.[0]?.id?.[0];

    if (!userId) {
      const xmlError = `
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <GetUsuarioResponse>
              <error>ID de usuario no proporcionado</error>
            </GetUsuarioResponse>
          </soap:Body>
        </soap:Envelope>
      `;
      res.set("Content-Type", "text/xml");
      return res.send(xmlError);
    }

    // Consulta a DB
    const [rows] = await pool.query(
      "SELECT id, nombre, email FROM usuarios WHERE id = ?",
      [userId]
    );

    if (rows.length === 0) {
      const xmlError = `
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <GetUsuarioResponse>
              <error>Usuario no encontrado</error>
            </GetUsuarioResponse>
          </soap:Body>
        </soap:Envelope>
      `;
      res.set("Content-Type", "text/xml");
      return res.send(xmlError);
    }

    const usuario = rows[0];

    const xmlResponse = `
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <GetUsuarioResponse>
            <usuario>
              <id>${usuario.id}</id>
              <nombre>${usuario.nombre}</nombre>
              <email>${usuario.email}</email>
            </usuario>
          </GetUsuarioResponse>
        </soap:Body>
      </soap:Envelope>
    `;

    res.set("Content-Type", "text/xml");
    res.send(xmlResponse);

  } catch (err) {
    console.error("ERROR SOAP:", err);

    const xmlInternalError = `
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <GetUsuarioResponse>
            <error>Error interno del servidor</error>
          </GetUsuarioResponse>
        </soap:Body>
      </soap:Envelope>
    `;
    res.set("Content-Type", "text/xml");
    res.send(xmlInternalError);
  }
});

// Iniciar servidor
const PORT = process.env.PORT || 3000;
app.listen(PORT, () =>
  console.log(`Monolito levantado en puerto ${PORT}`)
);

// Para correr el codigo:
// docker compose restart monolito
// docker compose up --build

// docker exec -it db mysql -u app -p
// USE proyectos_db
// SELECT * FROM usuarios