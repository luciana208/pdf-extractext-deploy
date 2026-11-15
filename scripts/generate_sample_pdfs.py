"""genera pdfs de prueba: liviano, mediano, pesado (muchas paginas) y con graficos"""

import random
import sys
from pathlib import Path

import pymupdf

LOREM = (
    "el microservicio de extraccion recibe un pdf y devuelve su contenido en markdown "
    "o texto plano, separando el runtime http del procesamiento en un pool de procesos "
)


def text_pages(document: pymupdf.Document, pages: int) -> None:
    for number in range(pages):
        page = document.new_page()
        page.insert_text((72, 72), f"Seccion {number + 1}", fontsize=18)
        for line in range(45):
            page.insert_text((72, 100 + line * 15), (LOREM * 2)[line % 40 : line % 40 + 90], fontsize=9)


def graphic_pages(document: pymupdf.Document, pages: int) -> None:
    rng = random.Random(42)
    for number in range(pages):
        page = document.new_page()
        page.insert_text((72, 72), f"Grafico {number + 1}", fontsize=18)
        # muchas figuras vectoriales y una imagen de ruido para inflar el tamaño
        for _ in range(400):
            x, y = rng.uniform(50, 550), rng.uniform(100, 750)
            page.draw_rect(pymupdf.Rect(x, y, x + rng.uniform(5, 40), y + rng.uniform(5, 40)), color=(rng.random(), 0, 0))
        noise = bytes(rng.getrandbits(8) for _ in range(400 * 400 * 3))
        page.insert_image(pymupdf.Rect(100, 300, 500, 700), stream=pymupdf.Pixmap(pymupdf.csRGB, 400, 400, noise, False).tobytes("png"))


def build(path: Path, fill, pages: int) -> None:
    document = pymupdf.open()
    fill(document, pages)
    document.save(path, deflate=False)
    print(f"{path.name}: {pages} paginas, {path.stat().st_size / 1024 / 1024:.1f} MB")


def main() -> None:
    output = Path(sys.argv[1] if len(sys.argv) > 1 else "tests/stress/pdfs")
    output.mkdir(parents=True, exist_ok=True)
    build(output / "liviano.pdf", text_pages, 2)
    build(output / "mediano.pdf", text_pages, 30)
    build(output / "pesado.pdf", text_pages, 150)
    build(output / "graficos.pdf", graphic_pages, 18)


if __name__ == "__main__":
    main()
