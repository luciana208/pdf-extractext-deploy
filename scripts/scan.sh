#!/usr/bin/env bash
# escanea las imagenes con trivy y deja un reporte por imagen en reports/
# uso: ./scripts/scan.sh            (trivy)
#      SCANNER=grype ./scripts/scan.sh
set -euo pipefail

cd "$(dirname "$0")/.."
set -a; [ -f .env ] && . ./.env; set +a

scanner=${SCANNER:-trivy}
mkdir -p reports

images=(
    "pdf-extractext/orchestrator:${ORCHESTRATOR_VERSION:-1.0.0}"
    "pdf-extractext/validation:${VALIDATION_VERSION:-1.0.0}"
    "pdf-extractext/extract:${EXTRACT_VERSION:-1.0.0}"
    "pdf-extractext/documents:${DOCUMENTS_VERSION:-1.0.0}"
)

for image in "${images[@]}"; do
    report="reports/$(echo "$image" | tr '/:' '__').$scanner.txt"
    echo "escaneando $image -> $report"
    if [ "$scanner" = "grype" ]; then
        docker run --rm -v /var/run/docker.sock:/var/run/docker.sock anchore/grype:latest "$image" > "$report"
    else
        docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache \
            aquasec/trivy:latest image --scanners vuln --severity HIGH,CRITICAL "$image" > "$report"
    fi
done
echo "reportes en reports/"
