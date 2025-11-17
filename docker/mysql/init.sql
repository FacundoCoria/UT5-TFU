-- Inicialización de BD para monolito
-- Crea esquemas, tablas y datos.

-- Esquemas
CREATE DATABASE IF NOT EXISTS usuarios_db
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS proyectos_db
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Permisos para el usuario 'app'
GRANT ALL PRIVILEGES ON usuarios_db.*  TO 'app'@'%';
GRANT ALL PRIVILEGES ON proyectos_db.* TO 'app'@'%';
FLUSH PRIVILEGES;

-- Tabla usuarios
DROP TABLE IF EXISTS usuarios_db.usuarios;

CREATE TABLE usuarios_db.usuarios (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  nombre    VARCHAR(120) NOT NULL,
  email     VARCHAR(160) NOT NULL UNIQUE,
  hash      VARCHAR(200) NOT NULL,
  creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Inserto datos
INSERT INTO usuarios_db.usuarios (nombre, email, hash) VALUES
('facu','facu@example.com','$2a$10$CwTycUXWue0Thq9StjUM0uJ8WcOqKq7n1t42ZT3zh/OEl8rmnE9lO');

-- Esquema proyectos

DROP TABLE IF EXISTS proyectos_db.tareas;
DROP TABLE IF EXISTS proyectos_db.proyectos;

CREATE TABLE proyectos_db.proyectos (
  id                INT AUTO_INCREMENT PRIMARY KEY,
  nombre            VARCHAR(160) NOT NULL,
  descripcion       TEXT,
  owner_usuario_id  INT NOT NULL,
  creado_en         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE proyectos_db.tareas (
  id                     INT AUTO_INCREMENT PRIMARY KEY,
  proyecto_id            INT NOT NULL,
  titulo                 VARCHAR(200) NOT NULL,
  estado                 ENUM('todo','doing','done') NOT NULL DEFAULT 'todo',
  asignado_a_usuario_id  INT,
  creado_en              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_tareas_proyecto
    FOREIGN KEY (proyecto_id) REFERENCES proyectos_db.proyectos(id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_proyectos_owner ON proyectos_db.proyectos (owner_usuario_id);
create index idx_tareas_proyecto on proyectos_db.tareas (proyecto_id);

-- Seeds
INSERT INTO proyectos_db.proyectos (nombre,descripcion,owner_usuario_id)
VALUES ('Proyecto semilla','Backlog inicial',1);

INSERT INTO proyectos_db.tareas (proyecto_id,titulo,estado,asignado_a_usuario_id)
VALUES (1,'Configurar repositorio','doing',1);
