#!/usr/bin/env bash
# baja el sistema; con --volumes tambien borra los datos de mongo y consul
set -euo pipefail

cd "$(dirname "$0")/.."
docker compose down "$@"
