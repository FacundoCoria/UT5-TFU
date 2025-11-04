#!/usr/bin/env bash
set -euo pipefail

docker compose up -d --build
echo "Esperando 5s..."
sleep 5
curl -s http://localhost:8080/health || true
echo
