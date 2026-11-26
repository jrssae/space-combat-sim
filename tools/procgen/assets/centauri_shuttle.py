"""``centauri_shuttle``: the Centauri shuttle, 36 m long and 52 m across (M10-T58; docs/assets-civilian.md and
docs/design-references.md, "Centauri shuttle").

Composition only: the pieces of ``parts/centauri_shuttle.py`` in the chosen look of ``styles/centauri_shuttle.py``, through
the shuttles' shared build (``assets/ea_shuttles.py``, ``build_craft``): one textured mesh with a full and a low texture
set, the break-up chunks, ``hardpoints.json`` and the manifest. A small craft by the class budgets (M10 Q38), unarmed, on a
reaction drive; it lands in bays and has no docking port (Q93).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ..core import civilian as cv
from ..core.context import AssetOutputs, BuildContext
from ..core.color import capture_albedo
from ..core.seams import MAJOR, Feature, Relief, SeamLayout
from ..core.textures import Marking, value_noise
from ..parts import Part
from ..parts import centauri_shuttle as cp
from ..styles.centauri_shuttle import BRASS_SRGB, SHUTTLE_LOOK, Look
from .ea_shuttles import NAV_CLEARANCE_M, Craft, Port, build_craft, no_docks

ASSET_ID = "centauri_shuttle"
UP, DOWN, OUT = (0.0, 1.0, 0.0), (0.0, -1.0, 0.0), (1.0, 0.0, 0.0)


CREST_AT = (5.6, 26.4)  # x (either side of the spine) and z of each crest's centre, on the deck between blisters and louvres
CREST_R = 1.5
GOLD_LINES_Z = (11.5, 19.5, 27.6)  # lines across the deck
GOLD_LINE_X = 7.4  # a line along the deck either side, from GOLD_LINE_Z
GOLD_LINE_Z = (15.0, 29.0)
LINE_M = 0.22


@dataclass(frozen=True)
class Mottle(Feature):
    """Soft darker clouds on the paint (Q83): seeded noise at ``size_m`` and finer, where it rises above the share left
    clear the paint darkens by up to ``darker``, the edges blended over a band."""

    size_m: float = 2.0
    share: float = 0.4
    darker: float = 0.1
    seed: int = 0

    def _paint_all(self, p: np.ndarray, n: np.ndarray, line_m: float, depth_m: float, out: Relief, ok: np.ndarray) -> None:
        q = np.asarray(p, dtype=float)
        noise = (0.6 * value_noise(q, self.size_m, self.seed) + 0.28 * value_noise(q, 0.43 * self.size_m, self.seed + 1)
                 + 0.12 * value_noise(q, 0.17 * self.size_m, self.seed + 2))  # fmt: skip
        cover = np.clip((noise - (1.0 - self.share) * 0.75 - 0.12) / 0.1, 0.0, 1.0)
        out.tint *= 1.0 - self.darker * cover * ok


def _smooth(x: np.ndarray) -> np.ndarray:
    return np.clip(x / 0.06 + 0.5, 0.0, 1.0)


def crest_cover(points: np.ndarray, normals: np.ndarray) -> np.ndarray:
    """Where the crests lie, one either side of the spine: a ring round a rising crescent and a tall spike, open at the top,
    standing on a short bar: our own sign in the Centauri manner, nose up."""
    p = np.asarray(points, dtype=float)
    u, v = np.abs(p[:, 0]) - CREST_AT[0], CREST_AT[1] - p[:, 2]  # v points to the nose
    r = np.hypot(u, v)
    ring = _smooth(0.11 - np.abs(r - CREST_R)) * _smooth(0.65 * CREST_R - v)  # the ring, open over its top
    outer, inner = np.hypot(u, v + 0.25), np.hypot(u, v + 0.75)
    crescent = _smooth(0.95 - outer) * _smooth(inner - 0.95) * _smooth(v + 0.4)  # horns rising towards the nose
    spike = _smooth(0.12 * (1.6 - v) - np.abs(u)) * _smooth(v + 0.2) * _smooth(1.55 - v)
    bar = _smooth(0.1 - np.abs(v + 1.05)) * _smooth(0.7 - np.abs(u))
    up = np.asarray(normals, dtype=float)[:, 1] > 0.5
    return np.clip(np.maximum.reduce([ring, crescent, spike, bar]), 0.0, 1.0) * up


def gold_panel_spots() -> list[tuple[float, float, tuple[float, float]]]:
    """Where the small gold panels lie on the deck, the same either side: rows across it, clear of the spine, the blisters,
    the crests and the louvres; their sizes vary from spot to spot."""
    zs, ws = [s[0] for s in cp.BODY_STATIONS], [s[1] for s in cp.BODY_STATIONS]
    (bx, _, bz), (brx, _, brz) = cp.BLISTER
    spots = []
    for i, z in enumerate(np.arange(7.6, 31.0, 1.7)):
        w = float(np.interp(z, zs, ws))
        for j, share in enumerate((0.3, 0.5, 0.7, 0.88)):
            x = share * w
            clear = (x > cp.SPINE_HALF[0] + 0.6 and not (abs(x - bx) < brx + 0.5 and abs(z - bz) < brz + 0.4)
                     and np.hypot(x - CREST_AT[0], z - CREST_AT[1]) > CREST_R + 0.5 and not (z > cp.LOUVRE_Z[0] - 0.6 and x < cp.LOUVRE_X[-1] + 0.6))
            if clear and (3 * i + 5 * j) % 4 != 0:
                k = (7 * i + 3 * j) % 5
                size = (0.45 + 0.15 * k, 0.3 + 0.08 * ((i + j) % 4))
                spots += [(x, float(z), size), (-x, float(z), size)]
    return spots


def gold_markings(look: Look) -> dict[str, list[Marking]]:
    """The gold on the deck (lines, small panels, the crests) and the brass strip down the spine."""
    gold = look.style.material("stripe").albedo
    body = []
    for z in GOLD_LINES_Z:
        w = 0.9 * float(np.interp(z, [s[0] for s in cp.BODY_STATIONS], [s[1] for s in cp.BODY_STATIONS]))
        body.append(Marking.rect("body", (0.0, cp.deck_y(0.0, z), z), OUT, (0.0, 0.0, 1.0), UP, (2.0 * w, LINE_M), gold))
    z0, z1 = GOLD_LINE_Z
    for side in (1.0, -1.0):
        zc = 0.5 * (z0 + z1)
        body.append(Marking.rect("body", (side * GOLD_LINE_X, cp.deck_y(GOLD_LINE_X, zc), zc), OUT, (0.0, 0.0, 1.0), UP, (LINE_M, z1 - z0), gold))
    body.append(Marking.paint("body", gold, crest_cover, placed=True))
    body += [Marking.rect("body", (x, cp.deck_y(x, z), z), OUT, (0.0, 0.0, 1.0), UP, size, gold) for x, z, size in gold_panel_spots()]
    z0, z1 = cp.SPINE_STATIONS[cp.CANOPY_SEGMENTS][0], cp.SPINE_STATIONS[-1][0]
    top = max(t for _, t in cp.SPINE_STATIONS)
    spine = [Marking.rect("spine", (0.0, top, 0.5 * (z0 + z1)), OUT, (0.0, 0.0, 1.0), UP, (look.spine_strip_m, z1 - z0), capture_albedo(BRASS_SRGB))]
    return {"body": body, "spine": spine}


def dress(pieces: list[cv.Piece], look: Look) -> tuple[list[cv.Piece], dict]:
    """No seams: the solid violet under the look's soft darker mottle (Q83), kept in the low set; then the gold."""
    layout = SeamLayout.of([Mottle(level=MAJOR, size_m=size, share=share, darker=darker, seed=829 + 13 * k)
                            for k, (size, share, darker) in enumerate(look.mottle)])
    marks = {name: tuple(m) for name, m in gold_markings(look).items()}
    return [cv.Piece(p.part.with_seams(layout), p.solid, p.side, p.fine) for p in pieces], marks


def ports(by_name: dict[str, Part]) -> list[Port]:
    """Cosmetic RCS (authored frame; ``r_`` names are mirrored): at the nose and, for the side thrust, on the outer face of
    each wing's root; none at the wing tips (M10 Q93)."""
    return [
        ("r_nose", (2.0, -2.25, 2.0), OUT),
        ("nose_up", (0.0, cp.deck_y(0.0, 4.0), 4.0), UP),
        ("nose_down", (0.0, -2.9, 4.0), DOWN),
        ("r_root", cp.wing_root_port(), OUT),
    ]


def lights(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Running lights at the wing tips, white on the spine's crown aft, the cabin glow behind the canopy."""
    top = by_name["spine"].anchor("top").position
    return {"starboard": by_name["wing_r"].anchor("tip").position + np.array([NAV_CLEARANCE_M, 0.0, 0.0]),
            "top": top + np.array([0.0, NAV_CLEARANCE_M, 0.0]), "top_lamp": top + np.array([0.0, 2.0, 0.0]), "cabin": np.array(cp.EYE)}


def joints(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Where each chunk breaks away: the body at its middle, the stern at the louvres, a wing at its root."""
    wing = by_name["wing_r"].anchor("joint").position
    return {"body": np.array([0.0, -1.5, 18.0]), "stern": np.array([0.0, -2.3, 32.0]), "wing_r": wing, "wing_l": wing * np.array([-1.0, 1.0, 1.0])}


CRAFT = Craft(ASSET_ID, 0.25, ("body", "stern", "wing_l", "wing_r"), SHUTTLE_LOOK, cp.assemble, dress, cp.NOZZLE_Y,
              (("l", "left", "engine_l", cp.NOZZLE_EXIT_R), ("r", "right", "engine_r", cp.NOZZLE_EXIT_R)), 0.0,
              (1.2, cp.NOSE_Y, 1.0, 0.3), ports, lights, joints, no_docks)  # fmt: skip


def build(ctx: BuildContext) -> AssetOutputs:
    return build_craft(CRAFT, ctx)
