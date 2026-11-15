#!/usr/bin/env bash
# prueba punta a punta: sube un pdf, lo consulta, lo descarga y lo borra
# uso: ./scripts/smoke.sh ruta/al/archivo.pdf
set -euo pipefail

pdf=${1:?pasar la ruta de un pdf}
domain=${DOMAIN:-pdfextractext.localhost}
api="https://api.$domain/api/v1/documents"
curl_opts=(--silent --show-error ${CURL_INSECURE:+--insecure})

echo "1. subida"
created=$(curl "${curl_opts[@]}" -F "file=@$pdf;type=application/pdf" "$api/")
printf '%s\n' "${created:0:300}"
id=$(echo "$created" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')

echo "2. consulta"
curl "${curl_opts[@]}" -o /dev/null -w "status %{http_code}\n" "$api/$id"

echo "3. subida duplicada (espera 409)"
curl "${curl_opts[@]}" -o /dev/null -w "status %{http_code}\n" -F "file=@$pdf;type=application/pdf" "$api/"

echo "4. descarga"
downloaded=$(curl "${curl_opts[@]}" "$api/$id/download")
printf '%s\n' "${downloaded:0:200}"

echo "5. borrado"
curl "${curl_opts[@]}" -X DELETE -w " status %{http_code}\n" "$api/$id"
