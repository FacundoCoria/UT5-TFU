# Arquitectura de Microservicios - Patrones Cloud

Este proyecto implementa una arquitectura de microservicios con varios patrones cloud nativos, usando Node.js, Express, MySQL y Redis. Está compuesto por un API Gateway (nginx) y cuatro servicios: Auth, Usuarios, Proyectos y Tareas, que utilizan dos bases de datos MySQL (`usuarios_db` y `proyectos_db`).

## Patrones Implementados

1. **Health Check**: Cada servicio expone un endpoint `/health` que reporta su estado.
   - Gateway: http://localhost:8080/health
   - Auth: http://localhost:8080/auth/health
   - Usuarios: http://localhost:8080/usuarios/health
   - Proyectos: http://localhost:8080/proyectos/health
   - Tareas: http://localhost:8080/tareas/health

2. **Retry Pattern**: Helper genérico (`codigo/lib/retry.js`) utilizado en el worker de tareas.
   - Reintentos exponenciales para operaciones de base de datos
   - Ejemplo de uso en `tareas-api/src/queue.js`

3. **Cache-Aside**: Implementado en `usuarios-api` usando Redis.
   - Caché de usuarios por ID
   - Invalidación automática en escrituras
   - Ver `usuarios-api/src/cache.js`

4. **Queue-Based Load Leveling**: Implementado en `tareas-api` usando Redis como cola.
   - Cola usando RPUSH/BLPOP
   - Worker procesando en background
   - Ver `tareas-api/src/queue.js`

5. **Gatekeeper**: Gateway nginx que actúa como reverse proxy.
   - Configuración en `gateway/nginx.conf`
   - Enruta y filtra requests a los servicios

6. **Valet Key**: Tokens JWT de corta duración para recursos específicos.
   - Endpoint: POST `/auth/valet`
   - Implementado en `auth-api/src/jwt.js`

7. **External Configuration**: Variables de entorno y docker-compose.
   - Ver `.env.example` y `docker-compose.yaml`
   - Configuración de servicios externalizada

## Requisitos

- Docker y docker-compose
- PowerShell (para scripts de prueba)
- Node.js 20+ (para desarrollo local)

## Instalación y Ejecución

1. Clonar el repositorio
2. Copiar `.env.example` a `.env` y ajustar si es necesario
3. Ejecutar el stack completo:
   ```powershell
   docker compose up -d
   ```

## Tests End-to-End

El script `codigo/scripts/run_full_test.ps1` ejecuta una prueba completa del sistema:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\codigo\scripts\run_full_test.ps1
```

Este script:
1. Detiene y limpia el stack anterior
2. Levanta DB y Redis
3. Carga el schema inicial
4. Construye y levanta los servicios
5. Prueba cada patrón implementado

## Ejemplos de Uso (curl)

### Auth y Valet Key

```bash
# Registro de usuario
curl -X POST http://localhost:8080/auth/register \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Test","email":"test@example.com","password":"secret"}'

# Login (obtener token)
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"secret"}'

# Obtener valet key (usar token del login)
curl -X POST http://localhost:8080/auth/valet \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"resource":"uploads/test.txt"}'
```

### Cache-Aside (Usuarios)

```bash
# Crear usuario
curl -X POST http://localhost:8080/usuarios/ \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Cache","email":"cache@test.com"}'

# Obtener usuario (primera vez, cache miss)
curl http://localhost:8080/usuarios/1

# Obtener usuario (segunda vez, cache hit)
curl http://localhost:8080/usuarios/1

# Verificar key en Redis
docker compose exec redis redis-cli get "user:1"
```

### Queue-Based Load Leveling (Tareas)

```bash
# Crear proyecto (requiere auth token)
curl -X POST http://localhost:8080/proyectos/ \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Test","descripcion":"Proyecto de prueba"}'

# Encolar tarea (retorna 202 si USE_QUEUE=1)
curl -X POST http://localhost:8080/tareas/ \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"proyecto_id":1,"titulo":"Tarea encolada"}'

# Verificar procesamiento
curl "http://localhost:8080/tareas/?proyecto_id=1" \
  -H "Authorization: Bearer <token>"

# Ver longitud de la cola en Redis
docker compose exec redis redis-cli llen tareas:queue
```

## Variables de Entorno

- `DB_HOST`: Host de MySQL (default: db)
- `DB_PORT`: Puerto de MySQL (default: 3306)
- `DB_USER`: Usuario de MySQL
- `DB_PASSWORD`: Contraseña de MySQL
- `DB_NAME`: Base de datos (default: proyectos_db)
- `REDIS_URL`: URL de Redis (default: redis://redis:6379)
- `USE_QUEUE`: Habilitar cola en tareas-api (1=sí, 0=no)
- `START_TAREAS_WORKER`: Iniciar worker de tareas (1=sí, 0=no)
- `JWT_SECRET`: Secreto para tokens JWT

## Estructura del Proyecto

```
codigo/
  ├── auth-api/        # Servicio de autenticación
  ├── usuarios-api/    # CRUD de usuarios + caché
  ├── proyectos-api/  # CRUD de proyectos
  ├── tareas-api/     # CRUD de tareas + cola
  ├── gateway/        # Reverse proxy (nginx)
  ├── db/            # Scripts SQL iniciales
  ├── lib/           # Utilidades compartidas
  └── scripts/       # Scripts de prueba
```

## Mantenimiento

- Los logs de cada servicio se pueden ver con:
  ```powershell
  docker compose logs <servicio>
  ```

- Para reconstruir un servicio específico:
  ```powershell
  docker compose up -d --build <servicio>
  ```

- Para resetear la base de datos:
  ```powershell
  ./codigo/scripts/reset-and-e2e.ps1
  ```
