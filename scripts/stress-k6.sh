#!/usr/bin/env bash
# prueba spike con k6 contra /extract (perfil de la consigna del tp de carga)
set -euo pipefail

cd "$(dirname "$0")/.."
domain=${DOMAIN:-pdfextractext.localhost}
mkdir -p tests/stress/results

# corre con el usuario del host para poder escribir en results
docker run --rm -i \
    --user "$(id -u):$(id -g)" \
    --add-host "extract.$domain:host-gateway" \
    -e BASE_URL="https://extract.$domain" \
    -v "$PWD/tests/stress:/stress" \
    grafana/k6:latest run --summary-export=/stress/results/k6-summary.json /stress/k6/spike.js
