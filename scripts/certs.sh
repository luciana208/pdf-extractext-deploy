#!/usr/bin/env bash
# genera el certificado local para *.pdfextractext.localhost con mkcert
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v mkcert >/dev/null 2>&1; then
    echo "falta mkcert: https://github.com/FiloSottile/mkcert#installation" >&2
    exit 1
fi

domain=${DOMAIN:-pdfextractext.localhost}

# instala la ca local en el sistema y el navegador (una sola vez por maquina)
mkcert -install
mkcert -cert-file traefik/certs/cert.pem -key-file traefik/certs/key.pem "$domain" "*.$domain"
echo "certificado generado en traefik/certs/"
