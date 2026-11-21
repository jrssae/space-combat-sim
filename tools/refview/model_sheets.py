"""Lays a model's shots out as one labelled sheet (M10-T50): the option sheets and comparisons of a hull the game has no
``ShipSpec`` for, photographed by ``scripts/model_sheet.sh``. Development only; the sheets go under the gitignored
``references/screenshots/``. Needs Pillow, as ``refview.py`` does.

Usage::

    .venv/bin/python3 tools/refview/model_sheets.py <sheet.png> --title TEXT --shots <dir> \\
        --row "name=label|name=label" [--row ...]

Each ``--row`` is one row of tiles: ``<dir>/<name>.png`` under its label.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from . import hull_sheets
except ImportError:  # run as a script
    import hull_sheets  # type: ignore[no-redef]


def parse_row(text: str, shots: Path) -> list[tuple[Path, str]]:
    """One row's tiles: ``name=label`` pairs split by ``|``; a pair without a label is labelled by its name."""
    tiles = []
    for pair in text.split("|"):
        name, _, label = pair.partition("=")
        if name.strip():
            tiles.append((shots / f"{name.strip()}.png", label.strip() or name.strip()))
    return tiles


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("sheet", type=Path)
    ap.add_argument("--title", default="")
    ap.add_argument("--shots", type=Path, required=True, help="the folder the shots are in")
    ap.add_argument("--row", action="append", default=[], metavar="NAME=LABEL|...", help="a row of tiles (repeatable)")
    args = ap.parse_args(argv)
    rows = [row for row in (parse_row(text, args.shots) for text in args.row) if row]
    if not rows:
        print("model_sheets: no rows", file=sys.stderr)
        return 2
    hull_sheets.sheet(rows, args.title, args.sheet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
