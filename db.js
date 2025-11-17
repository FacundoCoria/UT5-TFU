// Base de datos
import mysql from "mysql2/promise";

export const pool = mysql.createPool({
    host: "db",
    user: "app",
    password: "app",
    database: "proyectos_db",
    waitForConnections: true,
    connectionLimit: 10
});