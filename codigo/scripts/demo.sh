#!/usr/bin/env bash
set -euo pipefail
BASE=http://localhost:8080

echo "==> Health"
curl -s $BASE/health && echo

echo "==> Register (si email existe, ignora error)"
curl -s -X POST $BASE/auth/register -H 'Content-Type: application/json' \
  -d '{"nombre":"Linus","email":"linus@example.com","password":"secret"}' && echo

echo "==> Login"
TOKEN=$(curl -s -X POST $BASE/auth/login -H 'Content-Type: application/json' \
  -d '{"email":"linus@example.com","password":"secret"}' | jq -r .token)
echo "TOKEN=$TOKEN"

echo "==> /auth/me"
curl -s $BASE/auth/me -H "Authorization: Bearer $TOKEN" && echo

echo "==> Crear proyecto"
PID=$(curl -s -X POST $BASE/proyectos/ -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"nombre":"Demo TFU","descripcion":"Proyecto demo"}' | jq -r .id)
echo "Proyecto id=$PID"

echo "==> Crear tarea"
TID=$(curl -s -X POST $BASE/tareas/ -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d "{\"proyecto_id\":$PID,\"titulo\":\"Primera tarea\"}" | jq -r .id)
echo "Tarea id=$TID"

echo "==> Cambiar estado tarea -> done"
curl -s -X PATCH $BASE/tareas/$TID/estado -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"estado":"done"}' && echo

echo "==> Listar proyectos y tareas"
curl -s $BASE/proyectos/ -H "Authorization: Bearer $TOKEN" | jq . || true
curl -s $BASE/tareas/?proyecto_id=$PID -H "Authorization: Bearer $TOKEN" | jq . || true
