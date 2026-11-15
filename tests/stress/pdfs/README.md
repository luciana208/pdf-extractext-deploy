# PDFs de prueba de carga

Acá va la carpeta oficial de PDFs de la cátedra (`tests/stress/pdfs`). Los scripts esperan
por defecto estos nombres:

- `liviano.pdf`
- `mediano.pdf`
- `pesado.pdf`
- `graficos.pdf`

Si los archivos oficiales tienen otros nombres, se pasan a k6 con
`PDF_FILES=a.pdf,b.pdf` y Vegeta usa todos los `.pdf` de esta carpeta.

Mientras no estén los oficiales, `scripts/generate-sample-pdfs.sh` genera cuatro de prueba.
