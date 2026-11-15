#!/usr/bin/env bash
# sigue los logs de un servicio (o de todos): ./scripts/logs.sh orchestrator
set -euo pipefail

cd "$(dirname "$0")/.."
docker compose logs -f --tail=100 "$@"
