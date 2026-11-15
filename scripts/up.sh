#!/usr/bin/env bash
# levanta todo el sistema con una sola linea: ./scripts/up.sh
set -euo pipefail

cd "$(dirname "$0")/.."

# los repos de los servicios tienen que estar al lado de este
for repo in pdf-extractext-orchestrator pdf-validation-service pdf-extract-service pdf-extractext; do
    if [ ! -d "../$repo" ]; then
        echo "falta el repo ../$repo (clonarlo al lado de pdf-extractext-deploy)" >&2
        exit 1
    fi
done

# configuracion local
if [ ! -f .env ]; then
    cp .env.example .env
    echo "se creo .env desde .env.example, revisar las contraseñas"
fi

# red compartida (como en el ejemplo de la catedra)
docker network inspect mired >/dev/null 2>&1 || docker network create mired

# certificados para https
if [ ! -f traefik/certs/cert.pem ]; then
    bash scripts/certs.sh
fi

docker compose up -d --build "$@"

domain=$(grep -E '^DOMAIN=' .env | cut -d= -f2)
domain=${domain:-pdfextractext.localhost}
echo
echo "api:      https://api.$domain/docs"
echo "extract:  https://extract.$domain/docs"
echo "traefik:  https://traefik.$domain/dashboard/"
echo "consul:   https://consul.$domain/ui/"
