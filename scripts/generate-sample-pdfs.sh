#!/usr/bin/env bash
# genera cuatro pdfs de prueba de distinto tamaño en tests/stress/pdfs (necesita uv)
set -euo pipefail

cd "$(dirname "$0")/.."
uv run --no-project --with pymupdf python scripts/generate_sample_pdfs.py tests/stress/pdfs
