import express from "express";
import routes from "./proyectos.routes.js";
import { reqLogger } from "./logger.js";
import { routesIntrospect } from "./routes-introspect.js";

const app = express();
app.use(express.json());
app.use(reqLogger);
app.use(routes);

app.get("/health", (req,res)=> res.json({ ok:true, service: process.env.SERVICE_NAME || "proyectos-api" }));
app.get("/__routes", (req,res)=> res.json(routesIntrospect(app)));

const PORT = process.env.PORT || 3000;
console.log(JSON.stringify({ at:new Date().toISOString(), evt:"BOOT", svc:"proyectos-api" }));
app.listen(PORT, ()=> console.log(`proyectos-api on ${PORT}`));
