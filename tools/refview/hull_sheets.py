"""Lays a capital hull's shots out as its look sheet and its surface option sheet (M12-T19).

``scripts/hull_sheet.sh`` photographs the hull on the GPU (``<out>/shots/*.png``) and calls this to put the shots on two
labelled sheets: ``look_sheet.png`` (three quarters on from 50 m, 500 m and 5 km, then port, top and front) and, when surface
options are named, ``option_sheet.png`` (a row per option, its low and high texture sets close and whole). Development only;
the sheets go under the gitignored ``references/screenshots/``. Needs Pillow, as ``refview.py`` does.

Usage::

    .venv/bin/python3 tools/refview/hull_sheets.py <asset_id> <out_dir> [option ...] [--titles "a=A: show green|b=..."] [--note TEXT]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

TILE_W = 960
LABEL_H = 34
BACKGROUND = (20, 20, 23)
INK = (232, 232, 226)
LOOK_ROWS = (
    (("look_50m", "three quarters on, nearest corner 50 m"), ("look_500m", "500 m")),
    (("look_5km", "5 km"), ("look_port", "port side (bow to the left)")),
    (("look_top", "top (bow up)"), ("look_front", "front (bow on)")),
)
OPTION_COLUMNS = (("low_close", "low set, flank at 8 m"), ("high_close", "high set, flank at 8 m"), ("low_whole", "low set, whole ship"),
                  ("high_whole", "high set, whole ship"))  # fmt: skip


def font(size: int) -> ImageFont.ImageFont:
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # Pillow without FreeType sizing
        return ImageFont.load_default()


def sheet(rows: list[list[tuple[Path, str]]], title: str, out: Path) -> None:
    """One sheet: a title line, then the rows of tiles, each tile under its label. A missing shot leaves its tile empty."""
    columns = max(len(row) for row in rows)
    tile_h = TILE_W * 9 // 16
    image = Image.new("RGB", (columns * TILE_W, LABEL_H + len(rows) * (tile_h + LABEL_H)), BACKGROUND)
    draw = ImageDraw.Draw(image)
    draw.text((10, 6), title, fill=INK, font=font(20))
    for r, row in enumerate(rows):
        for c, (path, label) in enumerate(row):
            x, y = c * TILE_W, LABEL_H + r * (tile_h + LABEL_H)
            draw.text((x + 10, y + 7), label, fill=INK, font=font(17))
            if path.is_file():
                image.paste(Image.open(path).convert("RGB").resize((TILE_W, tile_h), Image.LANCZOS), (x, y + LABEL_H))
    image.save(out)
    print(f"wrote {out}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("asset")
    ap.add_argument("out", type=Path)
    ap.add_argument("options", nargs="*", help="surface options beside the asset's own build (which is option a)")
    ap.add_argument("--titles", default="", metavar="KEY=TITLE|...", help="a title per option, e.g. 'a=A: show green|b=B: raider brown'")
    ap.add_argument("--note", default="", help="added to both sheets' title lines (the machine the shots were taken on)")
    args = ap.parse_args(argv)
    shots = args.out / "shots"
    titles = dict(t.split("=", 1) for t in args.titles.split("|") if "=" in t)
    note = f"  ({args.note})" if args.note else ""
    sheet([[(shots / f"{name}.png", label) for name, label in row] for row in LOOK_ROWS],
          f"{args.asset}: look sheet, a Delta-V docked on the top outer cradle for scale{note}", args.out / "look_sheet.png")
    if args.options:
        rows = [[(shots / f"option_{key}_{column}.png", f"{titles.get(key, key.upper())}: {label}") for column, label in OPTION_COLUMNS]
                for key in ("a", *args.options)]
        sheet(rows, f"{args.asset}: surface options, low and high texture sets{note}", args.out / "option_sheet.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
