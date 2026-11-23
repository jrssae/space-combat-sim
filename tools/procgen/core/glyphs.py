"""Hull lettering (M10-T21, redrawn in M10-T22): a bold condensed sans in the show's style (the Hyperion's HYPERION and 21), its
capital letters and digits drawn in code as strokes and packed in one atlas, so any hull that carries a name, a letter or a
number (the EA warships' bows, a fighter's tail code) shares the same print.

Each glyph is a set of strokes (polylines and elliptical arcs) of one weight, in cap-height units: x from 0 to the glyph's
width, y from the baseline (0) to the cap line (1). Sharp corners are squared, gentle ones rounded, and every glyph is cut to its
box, which flattens the apexes of A, M, V and W; sharper points are rounded. Coverage comes from the exact distance to the strokes, so the edges are smooth
at any size the atlas is seen at; white on transparent, the game tints the quad that shows one. No font file is read: the shapes
are original, only drawn to the show's style.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from .image import write_png

CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
COLUMNS = 6  # the atlas is COLUMNS by COLUMNS cells, row by row in CHARS order
CELL_PX = 256
GLYPH_PX = 160  # the cap height inside a cell; the rest is margin for the mip chain
STROKE = 0.17  # the stroke's width, in cap heights
TRACKING = 0.1  # the gap between letters, in cap heights
SPACE = 0.32  # a space's advance, in cap heights
ATLAS_NAME = "{asset}_marks.png"

_H = STROKE / 2.0
_B, _T = _H, 1.0 - _H  # the centrelines of strokes lying on the baseline and the cap line
_SHARP_DEG = (35.0, 100.0)  # turns between these are mitred corners; gentler curves and sharper points are rounded


def _arc(cx: float, cy: float, rx: float, ry: float, a0: float, a1: float) -> list[tuple[float, float]]:
    """Points along an ellipse from angle ``a0`` to ``a1`` (degrees, either way round)."""
    n = max(4, int(abs(a1 - a0) / 6.0))
    return [(cx + rx * np.cos(a), cy + ry * np.sin(a)) for a in np.radians(np.linspace(a0, a1, n + 1))]


def _oval(x0: float, y0: float, x1: float, y1: float, ry: float) -> list[tuple[float, float]]:
    """A closed bowl with straight sides and elliptical ends, starting and ending mid-way up its right side."""
    cx, rx, mid = 0.5 * (x0 + x1), 0.5 * (x1 - x0), 0.5 * (y0 + y1)
    return [(x1, mid), *_arc(cx, y1 - ry, rx, ry, 0.0, 180.0), *_arc(cx, y0 + ry, rx, ry, 180.0, 360.0), (x1, mid)]


def _design() -> dict[str, tuple[float, list[list[tuple[float, float]]]]]:
    """Every glyph: its width and its strokes."""
    g: dict[str, tuple[float, list[list[tuple[float, float]]]]] = {}

    def put(char: str, width: float, *strokes: list[tuple[float, float]]) -> None:
        g[char] = (width, [list(s) for s in strokes])

    def sides(w: float) -> tuple[float, float, float, float]:
        left, right = _H, w - _H
        return left, right, 0.5 * w, 0.5 * (right - left)

    w = 0.62
    put("A", w, [(0.09, 0.0), (w / 2, 1.0), (w - 0.09, 0.0)], [(0.17, 0.3), (w - 0.17, 0.3)])
    w = 0.6
    L, R, cx, rx = sides(w)
    mid, xu, xl = 0.54, R - 0.2, R - 0.19
    put("B", w, [(L, mid), (xu, mid), *_arc(xu, 0.5 * (_T + mid), 0.17, 0.5 * (_T - mid), -90.0, 90.0), (L, _T), (L, _B), (xl, _B),
                 *_arc(xl, 0.5 * (mid + _B), 0.19, 0.5 * (mid - _B), -90.0, 90.0), (L, mid)])
    w = 0.58
    L, R, cx, rx = sides(w)
    put("C", w, [*_arc(cx, _T - 0.26, rx, 0.26, 25.0, 180.0), *_arc(cx, _B + 0.26, rx, 0.26, 180.0, 335.0)])
    w = 0.6
    L, R, cx, rx = sides(w)
    put("D", w, [(L, 0.5), (L, _T), (L + 0.14, _T), *_arc(L + 0.14, _T - 0.25, R - L - 0.14, 0.25, 90.0, 0.0),
                 *_arc(L + 0.14, _B + 0.25, R - L - 0.14, 0.25, 0.0, -90.0), (L, _B), (L, 0.5)])
    w = 0.52
    L = _H
    put("E", w, [(w, _T), (L, _T), (L, _B), (w, _B)], [(L, 0.52), (w - 0.05, 0.52)])
    w = 0.5
    put("F", w, [(w, _T), (L, _T), (L, 0.0)], [(L, 0.52), (w - 0.06, 0.52)])
    w = 0.6
    L, R, cx, rx = sides(w)
    put("G", w, [*_arc(cx, _T - 0.26, rx, 0.26, 25.0, 180.0), *_arc(cx, _B + 0.26, rx, 0.26, 180.0, 360.0), (R, 0.46)], [(0.33, 0.46), (w, 0.46)])
    w = 0.6
    L, R, cx, rx = sides(w)
    put("H", w, [(L, 0.0), (L, 1.0)], [(R, 0.0), (R, 1.0)], [(L, 0.52), (R, 0.52)])
    put("I", STROKE, [(_H, 0.0), (_H, 1.0)])
    w = 0.5
    L, R, cx, rx = sides(w)
    put("J", w, [(R, 1.0), (R, _B + 0.22), *_arc(cx, _B + 0.22, rx, 0.22, 360.0, 180.0), (L, 0.32)])
    w = 0.6
    L, R, cx, rx = sides(w)
    put("K", w, [(L, 0.0), (L, 1.0)], [(w - 0.1, 1.0), (L + 0.03, 0.34)], [(L + 0.19, 0.55), (w - 0.08, 0.0)])
    w = 0.5
    put("L", w, [(_H, 1.0), (_H, _B), (w, _B)])
    w = 0.78
    L, R, cx, rx = sides(w)
    put("M", w, [(L, 0.0), (L, 1.0), (cx, 0.22), (R, 1.0), (R, 0.0)])
    w = 0.62
    L, R, cx, rx = sides(w)
    put("N", w, [(L, 0.0), (L, 1.0), (R, 0.0), (R, 1.0)])
    w = 0.62
    L, R, cx, rx = sides(w)
    put("O", w, _oval(L, _B, R, _T, 0.27))
    w = 0.58
    L, R, cx, rx = sides(w)
    put("P", w, [(L, 0.0), (L, _T), (L + 0.15, _T), *_arc(L + 0.15, 0.5 * (_T + 0.46), R - L - 0.15, 0.5 * (_T - 0.46), 90.0, -90.0), (L, 0.46)])
    w = 0.62
    L, R, cx, rx = sides(w)
    put("Q", w, _oval(L, _B, R, _T, 0.27), [(0.36, 0.3), (w, 0.0)])
    w = 0.6
    L, R, cx, rx = sides(w)
    put("R", w, [(L, 0.0), (L, _T), (L + 0.15, _T), *_arc(L + 0.15, 0.5 * (_T + 0.48), R - L - 0.15, 0.5 * (_T - 0.48), 90.0, -90.0), (L, 0.48)],
        [(0.3, 0.48), (w - 0.07, 0.0)])
    w = 0.58
    L, R, cx, rx = sides(w)
    q = 0.25 * (_T - _B)
    put("S", w, [*_arc(cx, _T - q, rx, q, 20.0, 270.0), *_arc(cx, _B + q, rx, q, 90.0, -160.0)])
    w = 0.54
    put("T", w, [(0.0, _T), (w, _T)], [(w / 2, _T), (w / 2, 0.0)])
    w = 0.6
    L, R, cx, rx = sides(w)
    put("U", w, [(L, 1.0), (L, _B + 0.24), *_arc(cx, _B + 0.24, rx, 0.24, 180.0, 360.0), (R, 1.0)])
    w = 0.6
    put("V", w, [(0.09, 1.0), (w / 2, 0.0), (w - 0.09, 1.0)])
    w = 0.86
    put("W", w, [(0.08, 1.0), (0.25, 0.0), (w / 2, 0.86), (w - 0.25, 0.0), (w - 0.08, 1.0)])
    w = 0.6
    put("X", w, [(0.08, 1.0), (w - 0.08, 0.0)], [(0.08, 0.0), (w - 0.08, 1.0)])
    put("Y", w, [(0.08, 1.0), (w / 2, 0.46), (w / 2, 0.0)], [(w - 0.08, 1.0), (w / 2, 0.46)])
    w = 0.56
    L, R, cx, rx = sides(w)
    put("Z", w, [(0.0, _T), (R, _T), (L, _B), (w, _B)])

    w = 0.58
    L, R, cx, rx = sides(w)
    put("0", w, _oval(L, _B, R, _T, 0.27))
    put("1", 0.44, [(0.03, 0.76), (0.29, 1.0), (0.29, 0.0)])
    put("2", w, [*_arc(cx, _T - 0.25, rx, 0.25, 160.0, -25.0), (L, _B), (w, _B)])
    up, low = 0.5 * (_T - 0.53), 0.5 * (0.53 - _B)
    put("3", w, [*_arc(cx, _T - up, rx, up, 155.0, -90.0), (cx - 0.08, 0.53)], [(cx - 0.08, 0.53), (cx, 0.53), *_arc(cx, _B + low, rx, low, 90.0, -155.0)])
    put("4", 0.6, [(0.42, 0.0), (0.42, 1.0), (_H, 0.3), (0.6, 0.3)])
    put("5", w, [(w, _T), (L + 0.02, _T), (L, 0.56), *_arc(cx, _B + 0.27, rx, 0.27, 125.0, -150.0)])
    six = [_oval(L, _B, R, 0.64, 0.26), [*_arc(cx, _T - 0.3, rx, 0.3, 35.0, 180.0), (L, 0.36)]]
    put("6", w, *six)
    put("9", w, *[[(w - x, 1.0 - y) for x, y in s] for s in six])
    put("7", 0.56, [(0.0, _T), (0.56 - _H, _T), (0.2, 0.0)])
    put("8", w, _oval(L + 0.03, 0.5, R - 0.03, _T, 0.2), _oval(L, _B, R, 0.5, 0.22))
    return g


GLYPHS = _design()


def width(char: str) -> float:
    """A glyph's width in cap heights."""
    return GLYPHS[char][0]


def _box_distance(p: np.ndarray, a: np.ndarray, b: np.ndarray, ext_a: float, ext_b: float) -> np.ndarray:
    """Signed distance from points to a stroke segment from ``a`` to ``b`` of the stroke's width, lengthened past each end."""
    d = b - a
    length = float(np.hypot(*d))
    u = d / length
    rel = p - a
    along = rel @ u
    across = rel @ np.array([-u[1], u[0]])
    lo, hi = -ext_a, length + ext_b
    qx = np.abs(along - 0.5 * (lo + hi)) - 0.5 * (hi - lo)
    qy = np.abs(across) - _H
    return np.hypot(np.maximum(qx, 0.0), np.maximum(qy, 0.0)) + np.minimum(np.maximum(qx, qy), 0.0)


def distance(char: str, p: np.ndarray) -> np.ndarray:
    """Signed distance (cap heights, negative inside) from points ``p`` (N, 2) to ``char``'s ink."""
    w, strokes = GLYPHS[char]
    out = np.full(len(p), np.inf)
    for stroke in strokes:
        pts = [np.asarray(stroke[0], dtype=float)]
        for q in stroke[1:]:
            if np.hypot(*(np.asarray(q) - pts[-1])) > 1e-6:
                pts.append(np.asarray(q, dtype=float))

        def edge(q: np.ndarray) -> bool:
            return bool(q[0] <= 1e-6 or q[0] >= w - 1e-6 or q[1] <= 1e-6 or q[1] >= 1.0 - 1e-6)
        ext = [STROKE if edge(pts[0]) else 0.0] + [0.0] * (len(pts) - 2) + [STROKE if edge(pts[-1]) else 0.0]
        for i in range(1, len(pts) - 1):
            d0, d1 = pts[i] - pts[i - 1], pts[i + 1] - pts[i]
            turn = np.degrees(np.arccos(np.clip(d0 @ d1 / (np.hypot(*d0) * np.hypot(*d1)), -1.0, 1.0)))
            if _SHARP_DEG[0] < turn <= _SHARP_DEG[1]:
                ext[i] = _H * float(np.tan(np.radians(0.5 * turn)))
            else:
                out = np.minimum(out, np.hypot(*(p - pts[i]).T) - _H)
        for i in range(len(pts) - 1):
            out = np.minimum(out, _box_distance(p, pts[i], pts[i + 1], ext[i] if i > 0 else ext[0], ext[i + 1]))
    clip = np.maximum.reduce([-p[:, 0], p[:, 0] - w, -p[:, 1], p[:, 1] - 1.0])
    return np.maximum(out, clip)


def glyph(char: str) -> np.ndarray:
    """One glyph's coverage, a ``(CELL_PX, CELL_PX)`` float array in 0..1, the letter centred in its cell and its edges smoothed
    over one texel from the exact distance to its strokes."""
    w = width(char)
    idx = np.arange(CELL_PX) + 0.5
    x = (idx - 0.5 * (CELL_PX - w * GLYPH_PX)) / GLYPH_PX
    y = (0.5 * (CELL_PX + GLYPH_PX) - idx) / GLYPH_PX
    gx, gy = np.meshgrid(x, y)
    d = distance(char, np.stack([gx.ravel(), gy.ravel()], axis=1)).reshape(CELL_PX, CELL_PX)
    return np.clip(0.5 - d * GLYPH_PX, 0.0, 1.0)


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
    """Godot's ``.import`` for the atlas: lossless with mipmaps, colour left alone under clear texels."""
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
    """Writes the atlas and its sidecar into ``out_dir``; returns the files and the entry the game reads the layout and spacing from."""
    png = write_png(out_dir / ATLAS_NAME.format(asset=asset_id), atlas())
    sidecar = Path(str(png) + ".import")
    sidecar.write_text(import_sidecar(), encoding="utf-8", newline="\n")
    entry = {"file": png.name, "chars": CHARS, "columns": COLUMNS, "glyph_height_share": GLYPH_PX / CELL_PX,
             "widths": [round(width(c), 4) for c in CHARS], "tracking": TRACKING, "space": SPACE}
    return [png, sidecar], entry


__all__ = ["ATLAS_NAME", "CELL_PX", "CHARS", "COLUMNS", "GLYPHS", "GLYPH_PX", "SPACE", "STROKE", "TRACKING", "atlas", "distance", "glyph",
           "import_sidecar", "width", "write_atlas"]
