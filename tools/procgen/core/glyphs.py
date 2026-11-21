"""Hull lettering (M10-T21): a blocky capital-letter and digit set drawn in code and packed in one atlas, so any hull that
carries a name letter or a number (the EA warships' bows, a fighter's tail code) shares the same print.

The glyphs are 5 by 7 bitmaps, grown into rounded block print by blurring and cutting the result (heavy strokes, softened
corners), one per atlas cell, white on transparent: the game tints the quad that shows one.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from .image import write_png

CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
COLUMNS = 6  # the atlas is COLUMNS by COLUMNS cells, row by row in CHARS order
CELL_PX = 128
GLYPH_PX = (84, 60)  # a glyph's height and width inside its cell: the letter is 7 by 5 units of 12 px
UNIT_PX = 12
ATLAS_NAME = "{asset}_marks.png"

_BITMAPS = {
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
    "C": ("01111", "10000", "10000", "10000", "10000", "10000", "01111"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "G": ("01111", "10000", "10000", "10011", "10001", "10001", "01111"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
    "I": ("11111", "00100", "00100", "00100", "00100", "00100", "11111"),
    "J": ("00111", "00010", "00010", "00010", "00010", "10010", "01100"),
    "K": ("10001", "10010", "10100", "11000", "10100", "10010", "10001"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "Q": ("01110", "10001", "10001", "10001", "10101", "10010", "01101"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
    "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
    "W": ("10001", "10001", "10001", "10101", "10101", "11011", "10001"),
    "X": ("10001", "10001", "01010", "00100", "01010", "10001", "10001"),
    "Y": ("10001", "10001", "01010", "00100", "00100", "00100", "00100"),
    "Z": ("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00110", "01000", "10000", "11111"),
    "3": ("11110", "00001", "00001", "01110", "00001", "00001", "11110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "11110", "00001", "00001", "10001", "01110"),
    "6": ("00110", "01000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00010", "01100"),
}


def glyph(char: str) -> np.ndarray:
    """One glyph's coverage, a ``(CELL_PX, CELL_PX)`` float array in 0..1, the letter centred in its cell."""
    rows = _BITMAPS[char]
    bits = np.array([[c == "1" for c in row] for row in rows], dtype=float)
    big = np.kron(bits, np.ones((UNIT_PX, UNIT_PX)))
    k = np.ones(UNIT_PX) / UNIT_PX  # a box blur one unit wide rounds the corners and thickens the diagonals
    for axis in (0, 1):
        big = np.apply_along_axis(lambda v: np.convolve(v, k, mode="same"), axis, big)
    cover = np.clip((big - 0.42) * 6.0 + 0.5, 0.0, 1.0)
    out = np.zeros((CELL_PX, CELL_PX))
    top, left = (CELL_PX - GLYPH_PX[0]) // 2, (CELL_PX - GLYPH_PX[1]) // 2
    out[top:top + GLYPH_PX[0], left:left + GLYPH_PX[1]] = cover
    return out


def atlas() -> np.ndarray:
    """The RGBA atlas, 8-bit: white glyphs, the coverage in alpha."""
    size = COLUMNS * CELL_PX
    image = np.zeros((size, size, 4), dtype=np.uint8)
    image[..., :3] = 255
    for i, char in enumerate(CHARS):
        row, col = divmod(i, COLUMNS)
        image[row * CELL_PX:(row + 1) * CELL_PX, col * CELL_PX:(col + 1) * CELL_PX, 3] = np.round(glyph(char) * 255.0).astype(np.uint8)
    return image


def import_sidecar() -> str:
    """Godot's ``.import`` for the atlas: lossless with mipmaps (the glyphs are small and crisp), colour left alone under clear texels."""
    return (
        "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\n"
        "compress/mode=0\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/uastc_level=0\n"
        "compress/rdo_quality_loss=0.0\ncompress/hdr_compression=1\ncompress/normal_map=0\ncompress/channel_pack=0\n"
        "mipmaps/generate=true\nmipmaps/limit=-1\nroughness/mode=0\nroughness/src_normal=\"\"\n"
        "process/channel_remap/red=0\nprocess/channel_remap/green=1\nprocess/channel_remap/blue=2\nprocess/channel_remap/alpha=3\n"
        "process/fix_alpha_border=false\nprocess/premult_alpha=false\nprocess/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\n"
        "process/hdr_clamp_exposure=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n"
    )


def write_atlas(out_dir: Path, asset_id: str) -> tuple[list[Path], dict[str, object]]:
    """Writes the atlas and its sidecar into ``out_dir``; returns the files and the entry the game reads the layout from."""
    png = write_png(out_dir / ATLAS_NAME.format(asset=asset_id), atlas())
    sidecar = Path(str(png) + ".import")
    sidecar.write_text(import_sidecar(), encoding="utf-8", newline="\n")
    entry = {"file": png.name, "chars": CHARS, "columns": COLUMNS, "glyph_height_share": GLYPH_PX[0] / CELL_PX}
    return [png, sidecar], entry


__all__ = ["ATLAS_NAME", "CELL_PX", "CHARS", "COLUMNS", "atlas", "glyph", "import_sidecar", "write_atlas"]
