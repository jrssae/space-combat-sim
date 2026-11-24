"""``ea_panama`` and ``ea_construction_tender``: the Earth Alliance's two working ships (M10-T51 and M10-T55;
docs/assets-civilian.md and docs/design-references.md, "EA Panama-class transport" and "EA construction tender").

Composition only: the pieces of ``parts/ea_panama.py`` (modelled at 180 m and built 20 m tall, about 122 m long, Q66; a lopsided
wedge-section cargo hull) and
``parts/ea_construction_tender.py`` (modelled at 50 m and built at 8 m, Q65; a hexagonal work body with claws, a boom and two thruster pods), each in a
look from ``styles/ea_work_ships.py``, through the shuttles' shared build (``assets/ea_shuttles.py``, ``build_craft``) on
the civilian pipeline (``core/civilian.py``). Neither carries a weapon.

Classes by the budgets (M10 Q38; docs/assets-capital.md, "Class budgets"): the Panama is a **cruiser** (one 4 096 px atlas:
it flies into Babylon 5's bay, so it is seen from a few metres), the tender a **small craft** (one
2 048 px atlas). Both write the low texture set a mip level down.
"""

from __future__ import annotations

import numpy as np

from ..core import civilian as cv
from ..core.color import capture_albedo
from ..core.context import AssetOutputs, BuildContext
from ..core.seams import Cut, Feature, Hatch, Plates, SeamLayout
from ..core.textures import Marking
from ..parts import Part
from ..parts import ea_construction_tender as tp
from ..parts import ea_panama as pp
from ..styles.ea_civilian import WINDOW_STRENGTH
from ..styles.ea_work_ships import PANAMA_LOOK, TENDER_LOOK, WorkLook
from .ea_shuttles import NAV_CLEARANCE_M, Craft, Port, build_craft

PANAMA_ID = "ea_panama"
TENDER_ID = "ea_construction_tender"
TENDER_LENGTH_M = 8.0  # the maintainer's length (M10 Q65): the parts are modelled at 50 m, then shrunk
PANAMA_HEIGHT_M = 20.0  # the maintainer's height (M10 Q66, T71): the parts are modelled at 180 m long, then shrunk
PANAMA_MODELLED_HEIGHT_M = 29.6066  # the authored hull's height, aerials included
INF = float("inf")
X_AXIS, Y_AXIS, Z_AXIS = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)
Marks = dict[str, tuple[Marking, ...]]


# --- surfaces ------------------------------------------------------------------------------------------------------------------
def plating(look: WorkLook, cell: tuple[float, float], seed: int, scale: float) -> list[Feature]:
    """The show's patchwork at the hull's scale: plates of mixed size, each with its own tone, and a scatter of small proud
    hatches over them. ``scale`` sizes the smallest plate and the grime for the hull (1 for a shuttle)."""
    return [
        Plates(level=3, wrap="sides", long_axis=2, cell=cell, splits=3, min_m=0.22 * scale, keep=0.25, tone=look.plate_tone, sheen=0.07,
               grime=look.plate_grime, grime_m=0.12 * scale, depth=0.5, dark=0.5, width=0.8, seed=seed),
        Plates(level=3, wrap="sides", long_axis=2, cell=(0.5 * cell[0], 0.6 * cell[1]), splits=1, min_m=0.15 * scale, scatter=0.08,
               inset_m=0.05 * scale, tone=look.plate_tone, dark=0.7, depth=0.7, seed=seed + 6),
    ]  # fmt: skip


def _dressed(pieces: list[cv.Piece], layout: SeamLayout) -> list[cv.Piece]:
    return [cv.Piece(p.part.with_seams(layout), p.solid, p.side, p.fine) for p in pieces]


def dress_panama(pieces: list[cv.Piece], look: WorkLook) -> tuple[list[cv.Piece], Marks]:
    """The Panama's seams and paint: frames along the hold, cargo hatches in the roof and the keel, the patchwork, the rows of
    lit ports along the port face and on the bow spine, then the look's bands."""
    slope = np.array([-pp.ROOF_SLOPE, 1.0, 0.0]) / float(np.hypot(pp.ROOF_SLOPE, 1.0))  # out of the roof
    along = np.array([1.0, pp.ROOF_SLOPE, 0.0]) / float(np.hypot(pp.ROOF_SLOPE, 1.0))  # across the roof, to starboard
    frames = [57.1, 70.9, 84.7, 98.0, 112.3, 126.1, 140.0]
    major: list[Feature] = [Cut(axis=2, at=z, level=1, width=1.4) for z in (30.0, 70.9, 98.0, 126.1)]
    full: list[Feature] = [Cut(axis=2, at=z, level=2) for z in frames if z not in (70.9, 98.0, 126.1)]
    full += [Cut(axis=2, at=z, level=2) for z in (12.0, 16.5, 36.0, 162.0)]
    for sign in (1.0, -1.0):
        out = slope * np.array([1.0, sign, 1.0])
        right = along * np.array([1.0, sign, 1.0])
        for z in (64.0, 77.8, 91.6, 105.2, 119.2):
            centre = (1.0, pp.AXIS_Y + sign * (pp.roof_y(1.0) - pp.AXIS_Y), z)
            full.append(Hatch(centre=centre, right=tuple(right), up=Z_AXIS, size=(22.0, 9.6), corner_m=0.5, sunk=0.6, tone=0.93, level=2,
                              facing=tuple(out), min_dot=0.9))
    layout = SeamLayout.of(major + full + plating(look, (9.0, 6.0), 733, 5.0))
    dressed = _dressed(pieces, layout)

    lit = capture_albedo(0xF2E6C8)
    marks: dict[str, list[Marking]] = {}
    for part, z0, z1 in (("hold_fore", 58.0, pp.HOLD_Z[1]), ("hold_aft", pp.HOLD_Z[1], 129.0)):
        for y in (7.3, -7.3):
            marks.setdefault(part, []).append(Marking.windows(part, (pp.PORT_X, pp.AXIS_Y + y, 0.5 * (z0 + z1)), Z_AXIS, Y_AXIS, (-1.0, 0.0, 0.0),
                                                              (z1 - z0, 2.4), (2.6, 1.2), (1.1, 0.5), lit, WINDOW_STRENGTH, lit=0.6))
    for side in (1.0, -1.0):
        marks.setdefault("bow_spine", []).append(Marking.windows("bow_spine", (pp.BOW_X + side * 3.95, 0.4, 14.5), Z_AXIS, Y_AXIS, (side, 0.0, 0.0),
                                                                 (9.0, 1.6), (1.5, 0.8), (0.8, 0.4), lit, WINDOW_STRENGTH, lit=0.7))
    for z, width, colour in look.bands:
        for part in ("hold_fore", "hold_aft"):
            marks.setdefault(part, []).append(Marking.band(part, (0.0, 0.0, 0.0), Z_AXIS, z + 0.5 * width, width, capture_albedo(colour)))
    return dressed, {name: tuple(m) for name, m in marks.items()}


def dress_tender(pieces: list[cv.Piece], look: WorkLook) -> tuple[list[cv.Piece], Marks]:
    """The tender's seams and paint: frames round the body, hatches on its flanks, the patchwork, then the look's hazard stripes
    across the claws' blades and round the pods."""
    major: list[Feature] = [Cut(axis=2, at=z, level=1, width=1.4) for z in (17.0, 26.9, tp.BODY_Z[1])]
    full: list[Feature] = [Cut(axis=2, at=z, level=2) for z in (20.5, 23.8, 30.0, 34.0, 39.5, 43.0)]
    full += [Cut(axis=2, at=z, level=2, lo=(24.0, -INF, -INF)) for z in (38.0, 41.0, 44.2)]  # the pods' rings
    full += [
        Hatch(centre=(4.6, 3.6, 22.0), right=Z_AXIS, up=Y_AXIS, size=(3.0, 2.2), corner_m=0.12, sunk=0.6, tone=0.92, level=2, facing=(0.9, 0.44, 0.0), min_dot=0.8),
        Hatch(centre=(4.6, -2.6, 23.5), right=Z_AXIS, up=Y_AXIS, size=(3.6, 2.4), corner_m=0.12, sunk=0.6, tone=0.9, level=2, facing=(0.9, -0.44, 0.0), min_dot=0.8,
              slats=5),
        Hatch(centre=(0.0, tp.STERN_HEX[4], 41.5), right=X_AXIS, up=Z_AXIS, size=(3.6, 4.4), corner_m=0.15, sunk=0.6, tone=0.9, level=2,
              facing=(0.0, -1.0, 0.0), min_dot=0.8),
    ]
    layout = SeamLayout.of(major + full + plating(look, (2.4, 1.5), 911, 1.6)).mirrored_too()
    dressed = _dressed(pieces, layout)

    marks: dict[str, list[Marking]] = {}
    if look.stripes is not None:
        stripe = capture_albedo(look.stripes)
        for name, _, hub, axis, _ in tp.CLAWS:
            marks[name] = [Marking.band(name, hub, axis, at, 0.75, stripe) for at in (5.4, 7.4, 9.4, 11.4, 13.4, 15.4)]
        for part in ("pod_r", "pod_l"):
            x = tp.POD_AT[0] if part.endswith("_r") else -tp.POD_AT[0]
            marks[part] = [Marking.band(part, (x, tp.POD_AT[1], 0.0), Z_AXIS, at, 0.5, stripe) for at in (37.2, 38.2, 44.0, 45.0)]
    return dressed, {name: tuple(m) for name, m in marks.items()}


# --- hardpoints ----------------------------------------------------------------------------------------------------------------
def panama_ports(by_name: dict[str, Part]) -> list[Port]:
    """Cosmetic RCS (authored frame; the hull is lopsided, so each port is named for where it stands): four round the fore body
    and four round the hold's after end."""
    fore_roof = pp.roof_y(-6.0, pp.FORE_ROOF_AT_0)
    aft_roof = pp.roof_y(4.0)
    return [
        ("bow_up", (-6.0, fore_roof, 26.0), Y_AXIS),
        ("bow_down", (-6.0, 2.0 * pp.AXIS_Y - fore_roof, 26.0), (0.0, -1.0, 0.0)),
        ("bow_port", (pp.FORE_PORT_X, pp.AXIS_Y, 26.0), (-1.0, 0.0, 0.0)),
        ("bow_starboard", (pp.FORE_TUBE[-1][0], pp.AXIS_Y, 26.0), X_AXIS),
        ("stern_up", (4.0, aft_roof, 127.0), Y_AXIS),
        ("stern_down", (4.0, 2.0 * pp.AXIS_Y - aft_roof, 127.0), (0.0, -1.0, 0.0)),
        ("stern_port", (pp.PORT_X, pp.AXIS_Y + 8.0, 127.0), (-1.0, 0.0, 0.0)),
        ("stern_starboard", (pp.EDGE_X + pp.EDGE_R, pp.AXIS_Y, 127.0), X_AXIS),
    ]


def panama_lights(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Running lights: green on the starboard edge and red on the port band amidships, white on the upper tube's crown, the
    cabin glow in the bow spine."""
    top = np.array([pp.TUBE_X, pp.AXIS_Y + pp.TUBE_OFF + pp.TUBE_R, pp.HOLD_Z[1]])
    return {"starboard": np.array([pp.EDGE_X + pp.EDGE_R + NAV_CLEARANCE_M, pp.AXIS_Y, pp.HOLD_Z[1]]),
            "port": np.array([-21.4 - NAV_CLEARANCE_M, pp.AXIS_Y, pp.HOLD_Z[1]]),
            "top": top + np.array([0.0, NAV_CLEARANCE_M, 0.0]), "top_lamp": top + np.array([0.0, 6.0, 0.0]), "cabin": np.array(pp.EYE)}


def panama_joints(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Where each chunk breaks away: on the hull's axis at the three cuts, the fore hold in its middle."""
    z0, cut, _ = pp.HOLD_Z
    at = lambda z: np.array([0.0, pp.AXIS_Y, z])  # noqa: E731
    return {"bow": at(z0), "hold_fore": at(0.5 * (z0 + cut)), "hold_aft": at(cut), "stern": at(pp.STERN_WALL_Z)}


def panama_docks(by_name: dict[str, Part]) -> list[tuple[str, np.ndarray, np.ndarray]]:
    """The plate on the port side aft: the cargo lock another hull or a bay's arm meets."""
    return [("port_lock", np.array([-22.4, pp.AXIS_Y, 142.7]), np.array([-1.0, 0.0, 0.0]))]


def tender_ports(by_name: dict[str, Part]) -> list[Port]:
    """Cosmetic RCS (authored frame; ``r_`` names are mirrored): the three small thrusters round each pod, and two on the bow
    housings."""
    pod = by_name["pod_r"]
    side, top = pod.anchor("side").position, pod.anchor("top").position
    bottom = np.array([top[0], 2.0 * tp.POD_AT[1] - top[1], top[2]])
    return [
        ("r_pod_out", side, X_AXIS),
        ("r_pod_up", top, Y_AXIS),
        ("r_pod_down", bottom, (0.0, -1.0, 0.0)),
        ("r_bow_up", (2.3, 8.8, 16.3), Y_AXIS),
        ("r_bow_down", (2.3, -7.5, 16.3), (0.0, -1.0, 0.0)),
    ]


def tender_lights(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Running lights: red and green on the pods' outboard thrusters, white on the stern's domes, the cabin glow behind the
    nose's glass."""
    top = by_name["hull_stern"].anchor("top").position
    return {"starboard": by_name["pod_r"].anchor("side").position + np.array([NAV_CLEARANCE_M, 0.0, 0.0]),
            "top": top + np.array([0.0, NAV_CLEARANCE_M, 0.0]), "top_lamp": top + np.array([0.0, 2.5, 0.0]), "cabin": np.array(tp.EYE)}


def tender_joints(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Where each chunk breaks away: the stern at its cut, each boom at its root, each side's claws at the upper one's joint."""
    boom = by_name["boom_r"].anchor("joint").position
    flip = np.array([-1.0, 1.0, 1.0])
    return {"body": np.array([0.0, tp.HEX[1], 26.0]), "stern": np.array([0.0, tp.HEX[1], tp.BODY_Z[1]]), "boom_r": boom, "boom_l": boom * flip,
            "claws_r": by_name["claw_up_r"].anchor("joint").position, "claws_l": by_name["claw_up_l"].anchor("joint").position}


def no_docks(by_name: dict[str, Part]) -> list[tuple[str, np.ndarray, np.ndarray]]:
    return []


PANAMA = Craft(PANAMA_ID, 1.5, ("bow", "hold_fore", "hold_aft", "stern"), PANAMA_LOOK, pp.assemble, dress_panama, pp.AXIS_Y,
               (("l", "left", "engine_l", pp.ENGINE_THROAT[1]), ("r", "right", "engine_r", pp.ENGINE_THROAT[1])), 0.0,
               (4.0, pp.AXIS_Y, pp.FORE_Z[0], 1.0), panama_ports, panama_lights, panama_joints, panama_docks,
               ship_class="cruiser", atlas_px=4096, scale=PANAMA_HEIGHT_M / PANAMA_MODELLED_HEIGHT_M)  # fmt: skip
TENDER = Craft(TENDER_ID, 0.4, ("body", "stern", "boom_l", "boom_r", "claws_l", "claws_r"), TENDER_LOOK, tp.assemble, dress_tender, tp.POD_AT[1],
               (("l", "left", "pod_l", 1.4), ("r", "right", "pod_r", 1.4)), 0.0, (tp.POD_AT[0], tp.POD_AT[1], tp.POD_Z[0] + 1.3, 1.4),
               tender_ports, tender_lights, tender_joints, no_docks, scale=TENDER_LENGTH_M / tp.LENGTH_M)  # fmt: skip


def build_panama(ctx: BuildContext) -> AssetOutputs:
    return build_craft(PANAMA, ctx)


def build_tender(ctx: BuildContext) -> AssetOutputs:
    return build_craft(TENDER, ctx)
