import express from "express";
import { createPool } from "mysql2/promise";

const app = express();
app.use(express.json());

import routes from "./user.routes.js";

const pool = createPool({
  host: process.env.DB_HOST, user: process.env.DB_USER, password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME, port: Number(process.env.DB_PORT || 3306),
  waitForConnections: true, connectionLimit: 10
});

app.get("/health", (req,res)=> res.json({ ok:true, service: process.env.SERVICE_NAME || "usuarios-api" }));

// The gateway strips the /usuarios/ prefix, so mount routes at root
app.use("/", routes);

const PORT = process.env.PORT || 3000;
app.listen(PORT, "0.0.0.0", ()=> console.log(`usuarios-api on ${PORT}`));
