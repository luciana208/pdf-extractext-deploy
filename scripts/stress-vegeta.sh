#!/usr/bin/env bash
# carga fija con vegeta: 50 req/s durante 30 s rotando los pdfs de tests/stress/pdfs
set -euo pipefail

cd "$(dirname "$0")/.."
domain=${DOMAIN:-pdfextractext.localhost}
rate=${RATE:-50}
duration=${DURATION:-30s}

# un target por pdf, vegeta los va rotando
targets=tests/stress/vegeta/targets.txt
mkdir -p tests/stress/vegeta tests/stress/results
: > "$targets"
for pdf in tests/stress/pdfs/*.pdf; do
    printf 'POST https://extract.%s/extract\nContent-Type: application/pdf\n@/stress/pdfs/%s\n\n' "$domain" "$(basename "$pdf")" >> "$targets"
done

# corre con el usuario del host para poder escribir en results
docker run --rm -i \
    --user "$(id -u):$(id -g)" \
    --add-host "extract.$domain:host-gateway" \
    -v "$PWD/tests/stress:/stress" \
    --entrypoint sh peterevans/vegeta:latest -c "
        vegeta attack -insecure -targets=/stress/vegeta/targets.txt -rate=$rate -duration=$duration -timeout=30s \
            | tee /stress/results/vegeta.bin \
            | vegeta report
        vegeta report -type=json /stress/results/vegeta.bin > /stress/results/vegeta-report.json
        vegeta plot /stress/results/vegeta.bin > /stress/results/vegeta-plot.html
    "
