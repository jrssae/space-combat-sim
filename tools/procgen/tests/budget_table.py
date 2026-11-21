"""The class budget table of docs/assets-capital.md ("Class budgets", M10 Q38), read for the tests that hold hulls to it."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

DOC = Path(__file__).resolve().parents[3] / "docs" / "assets-capital.md"
HEADING = "## Class budgets"


@dataclass(frozen=True)
class Row:
    name: str
    triangles: int
    atlases: int
    atlas_px: int
    normal_px: int  # 0: as the atlas
    high_mb: float
    low_mb: float


def _int(text: str) -> int:
    return int(re.sub(r"[^0-9]", "", text))


def read_budgets(doc: Path = DOC) -> dict[str, Row]:
    """The table's rows by class, in the document's order."""
    lines = doc.read_text(encoding="utf-8").splitlines()
    start = next(k for k, line in enumerate(lines) if line.startswith(HEADING))
    rows: dict[str, Row] = {}
    for line in lines[start + 1:]:
        if line.startswith("## "):
            break
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 6 or not re.fullmatch(r"[\d ]+", cells[1]):
            if rows:
                break  # the table has ended
            continue
        count, size = cells[2].split(" x ")
        rows[cells[0]] = Row(cells[0], _int(cells[1]), _int(count), _int(size), 0 if cells[3] == "as the atlas" else _int(cells[3]),
                             float(cells[4]), float(cells[5]))
    return rows
