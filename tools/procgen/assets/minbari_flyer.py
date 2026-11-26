"""``minbari_flyer``: the Minbari Flyer, a diplomatic transport 40 m long (M10-T58, Q67; docs/assets-civilian.md and
docs/design-references.md, "Minbari Flyer").

Composition only: the pieces of ``parts/minbari_flyer.py`` in one of the looks of ``styles/minbari_flyer.py``, through the
shuttles' shared build (``assets/ea_shuttles.py``, ``build_craft``). The skin is the Minbari's hexagonal grid (Q45) under
the branching band pattern (Q90, ``assets/minbari_flyer_pattern.py``). A small craft by the class budgets (M10 Q38); its two plasma guns (Q91) come with stage 2.

Option ``look`` names the surface option; ``p1`` is the only one.
"""

from __future__ import annotations

from dataclasses import replace

import numpy as np

from ..core import civilian as cv
from ..core.color import capture_albedo
from ..core.context import AssetOutputs, BuildContext
from ..core.seams import FULL, MAJOR, Hexes, SeamLayout
from ..core.textures import Marking
from ..parts import Part
from ..parts import minbari_flyer as mp
from . import minbari_flyer_pattern as mfp
from ..styles.minbari_flyer import DEFAULT_OPTION, Look, looks
from .ea_shuttles import NAV_CLEARANCE_M, Craft, Port, build_craft, no_docks

ASSET_ID = "minbari_flyer"
UP, DOWN, OUT = (0.0, 1.0, 0.0), (0.0, -1.0, 0.0), (1.0, 0.0, 0.0)
FINS = ("blade_r", "blade_l", "spindle_r", "spindle_l")  # the darker blue on the stills
PANEL_LAMPS = 16
BODY_SEAM = (1.6, 1.6, 2.5)  # the hexagon seams off the fins: width, depth, darkness
BODY_OUTLINE, BODY_EDGE = 2.0, 6.0  # the body's blue outlines against the fins': wide and full enough to read from 12 m (round 3)
_BLADE = mfp.Sheet(along=2, across=1, centre=0.0, reach_m=3.6)
_BODY = {"outline": BODY_OUTLINE, "edge": BODY_EDGE}
_BARE = {**_BODY, "line": False}  # bands without a line: fewer lines run the hull's length (round 3)
LOBES: dict[str, mfp.Tube | mfp.Sheet] = {
    "body": mfp.Tube(0.0, **_BODY),
    "pod_r": mfp.Tube(mp.POD_STATIONS[2][1], scale=0.6, **_BODY), "pod_l": mfp.Tube(-mp.POD_STATIONS[2][1], scale=0.6, **_BODY),
    "waist_r": mfp.Tube(mp.WAIST_AT[0], mp.WAIST_AT[1], split_y=True, scale=0.45, **_BARE),
    "waist_l": mfp.Tube(-mp.WAIST_AT[0], mp.WAIST_AT[1], split_y=True, scale=0.45, **_BARE),
    "blade_r": _BLADE, "blade_l": _BLADE, "spindle_r": _BLADE, "spindle_l": _BLADE,
    "web_r": mfp.Sheet(2, 0, 6.0, 1.3, mirror=True, scale=0.6, flat=True, **_BARE), "web_l": mfp.Sheet(2, 0, 6.0, 1.3, mirror=True, scale=0.6, flat=True, **_BARE),
    "strake_r": mfp.Sheet(2, 0, 2.4, 1.1, mirror=True, scale=0.55, flat=True, **_BARE), "strake_l": mfp.Sheet(2, 0, 2.4, 1.1, mirror=True, scale=0.55, flat=True, **_BARE),
    "crossbar": mfp.Sheet(0, 2, 0.5 * sum(mp.CROSSBAR[0]), 2.1, scale=0.8, flat=True, **_BODY),
}  # fmt: skip


def _everywhere(points: np.ndarray, normals: np.ndarray) -> np.ndarray:
    return np.ones(len(points))


def panel_lamps() -> list[tuple[float, float, float]]:
    """Where the hidden lamps that light the panel under the crossbar sit, scattered so their pools overlap unevenly."""
    (c0, c1), _, y, half = mp.CROSSBAR
    k = np.arange(PANEL_LAMPS)
    x = (np.mod(k * 0.618034, 1.0) - 0.5) * 12.5
    z = c0 + 0.4 + np.mod(k * 0.381966 + 0.13, 1.0) * (c1 - c0 - 0.8)
    return [(float(a), y - half - 0.35 - 0.25 * float(np.mod(i * 0.7548, 1.0)), float(b)) for i, (a, b) in enumerate(zip(x, z, strict=True))]


def dress(pieces: list[cv.Piece], look: Look) -> tuple[list[cv.Piece], dict[str, tuple[Marking, ...]]]:
    """The hexagonal grid (Q45), subtle: each cell's shade kept in the low set, faint seams in the full one; then the pattern
    (Q90) on every lobe, each band's blue outline, its purple core and the dark line over them; the fins darker blue under it,
    their outboard faces bright blue with darker outlines so the bands still show; and the soft glow under the crossbar."""
    layout = SeamLayout.of([Hexes(level=MAJOR, cell_m=look.hex_m, tone=look.hex_tone, sheen=0.04, depth=0.0, dark=0.0, seed=907),
                            Hexes(level=FULL, cell_m=look.hex_m, tone=0.0, sheen=0.0, dark=0.6, seed=907)])
    # The pale body washes a seam out in full light, so its seams are cut wider, deeper and darker to read as the fins' do.
    cells, seams = layout.features()
    body_layout = SeamLayout.of([cells, replace(seams, width=BODY_SEAM[0], depth=BODY_SEAM[1], dark=BODY_SEAM[2])])
    dressed = [cv.Piece(p.part.with_seams(layout if p.name in FINS else body_layout), p.solid, p.side, p.fine) for p in pieces]
    marks: dict[str, list[Marking]] = {name: [] for name in LOBES}
    for name in FINS:
        marks[name].append(Marking.paint(name, capture_albedo(look.fins), _everywhere))
        marks[name].append(Marking.paint(name, capture_albedo(look.fin_outer), mfp.outboard, placed=True))
    colours = {"blue": capture_albedo(look.band_blue), "purple": capture_albedo(look.purple), "dark": capture_albedo(look.dark)}
    for k, (name, lobe) in enumerate(LOBES.items()):
        seed = 1.3 + 0.71 * k
        for layer in mfp.LAYERS:
            colour = colours["dark"] if layer == "blue" and name in FINS else colours[layer]
            marks[name].append(Marking.paint(name, colour, mfp.cover_fn(lobe, seed, layer), placed=True))
    glow = capture_albedo(look.panel_glow)
    marks["crossbar"] += [Marking.flood("crossbar", lamp, (0.0, 1.0, 0.0), 70.0, 10.0, 2.2, glow, look.glow_strength) for lamp in panel_lamps()]
    return dressed, {name: tuple(m) for name, m in marks.items() if m}


def ports(by_name: dict[str, Part]) -> list[Port]:
    """Cosmetic RCS (authored frame; ``r_`` names are mirrored): on the bow blades, the spindles and the fuselage's crown."""
    return [
        ("r_blade", (8.45, 0.0, 9.0), OUT),
        ("r_spindle", (mp.SPINDLE_X + 0.93, 0.0, 32.5), OUT),
        ("r_blade_up", (8.15, 4.0, 4.0), UP),
        ("r_blade_down", (8.15, -4.0, 4.0), DOWN),
        ("r_spindle_up", (mp.SPINDLE_X, 3.6, 32.0), UP),
        ("r_spindle_down", (mp.SPINDLE_X, -3.6, 32.0), DOWN),
    ]


def lights(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Running lights on the spindles' flanks, white on the fuselage's crown, the cabin glow in the bow."""
    top = by_name["body"].anchor("top").position
    return {"starboard": by_name["spindle_r"].anchor("tip").position + np.array([NAV_CLEARANCE_M, 0.0, 0.0]),
            "top": top + np.array([0.0, NAV_CLEARANCE_M, 0.0]), "top_lamp": top + np.array([0.0, 2.0, 0.0]), "cabin": np.array(mp.EYE)}


def joints(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Where each chunk breaks away: the bow's pods and blades at their webs, the tail at the waist, the crossbar at the
    fuselage, a spindle at its root."""
    spindle = np.array([mp.SPINDLE_X, 0.0, 32.0])
    return {"body": np.array([0.0, 0.0, 10.0]), "bow": np.array([0.0, 0.0, 8.0]), "tail": np.array([0.0, 0.0, 26.0]),
            "crossbar": np.array([0.0, 0.0, 32.4]), "spindle_r": spindle, "spindle_l": spindle * np.array([-1.0, 1.0, 1.0])}


CRAFT = Craft(ASSET_ID, 0.25, ("body", "bow", "tail", "crossbar", "spindle_l", "spindle_r"), looks()[DEFAULT_OPTION], mp.assemble, dress,
              0.0, (("l", "left", "spindle_l", 0.3), ("r", "right", "spindle_r", 0.3)), 0.0, (1.0, 0.0, 1.0, 0.3), ports, lights, joints,
              no_docks)  # fmt: skip


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the Flyer into ``ctx.out_dir``; option ``look`` picks the surface option, the rest as ``build_craft``."""
    options = looks()
    option = str(ctx.option("look", DEFAULT_OPTION))
    if option not in options:
        raise ValueError(f"{ASSET_ID} has no look {option!r} (one of {sorted(options)})")
    return build_craft(replace(CRAFT, look=options[option]), ctx)
