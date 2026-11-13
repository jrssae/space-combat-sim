"""``jumpgate``: an Earth Alliance jumpgate, four free-standing arms round the vortex (M6-T13, T19, D69, Q11;
docs/design-references.md, "Jumpgate").

Shape only, built from primitives: the proportions were read off the maintainer's model and the colours off show stills, and no
geometry from either is used. Every length below is a share of one arm's length (the reference model's arm is 164 of its units long,
so ``ARM_UNIT`` is one of those units), scaled to ``ARM_LENGTH_M``.

Layout (Godot frame, metres; corrected under T19 by the maintainer, 2026-11-11): the four arms run parallel to the vortex's axis,
at the top, bottom and both sides of the funnel. The gate faces -Z (its front: arrivals leave along -Z, departures fly in
along +Z); the origin is the centre of the arms' front ends, where the vortex's mouth lies, and the arms run back from z = 0 to
z = the arm's length, where the funnel ends. They stand at 90 degree steps round the axis (arm 0 on +Y): the top and bottom arms
``ARM_RADIUS_SHARE`` of an arm out from it, the side arms ``MOUTH_ASPECT`` times as far, so the four frame an elliptical mouth,
wider than tall (T19 round 3). An arm is a truss: a central spine with conical sleeves, four longerons round it with clamp rings, five stations of
two cross-shaped collars carrying a pair of fins spanning round the tube (a shallow V opening toward the axis, so each pair makes a
dish facing the funnel), cross-shaped end caps, an emitter lens on its back end and amber lamps on its inner and outer faces at each
station.

Outputs: the textured mesh (``jumpgate.glb``, its four maps; the importer builds the levels of detail), the OBJ, ``hardpoints.json``
(the vortex with its colours by direction, the arrival and departure points, the emitters, the lamps, the arms, the collision
boxes) and the manifest, which repeats the vortex.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Material, Mesh, box, inset_convex_polygon, lathe, prism, rotation_x, rotation_y, tapered_box
from ..core.manifest import build_manifest, write_manifest
from ..core.obj import write_obj
from ..core.silhouette import far_section
from ..core.textured_mesh import TexturedPart, phase_steps, write_textured_mesh
from ..parts import Collision
from ..styles import Style

ASSET_ID = "jumpgate"
GENERATOR_VERSION = 4  # 4: the far view's silhouette table (M6-T15)
OBJ_NAME = f"{ASSET_ID}.obj"
HARDPOINTS_NAME = "hardpoints.json"
JSON_DIGITS = 4

# The scale (docs/design-references.md, "Jumpgate"): no on-screen number exists, so the arm is sized so the vortex swallows a capital
# ship with room to spare. The top and bottom arms stand 2/3 of an arm out from the axis; the vortex's rim follows an ellipse that
# stops a metre short of the nearest part of the arms, and the funnel is as deep as an arm is long.
ARM_LENGTH_M = 1200.0
ARM_RADIUS_SHARE = 2.0 / 3.0
# How much further out the side arms stand than the top and bottom ones: the mouth's width over its height (option
# ``mouth_aspect``). Read off ``jumpgate.png`` (docs/design-references.md, "Jumpgate").
MOUTH_ASPECT = 1.35
RIM_CLEARANCE_M = 1.0
ARMS = 4
# Where a ship comes out (just in front of the mouth) and where one lines up to go in, in mouth half heights along the front normal.
ARRIVAL_RADII = 0.1
DEPARTURE_RADII = 2.0
# The vortex's colours by direction (the maintainer, 2026-11-11; linear RGB): blue for ships coming out of hyperspace, orange-yellow
# for ships going in; each with the paler colour of its swirl's streaks, and the pink-white flash the emitters make as it opens.
VORTEX_COLOURS = {
    "arrival": {"colour": (0.06, 0.38, 0.85), "highlight": (0.36, 0.75, 1.0)},
    "departure": {"colour": (0.95, 0.42, 0.06), "highlight": (1.0, 0.82, 0.38)},
}
VORTEX_FLASH = (1.0, 0.62, 0.86)

# The arm's proportions, read off the reference: one of its units is 1/164 of an arm.
ARM_UNIT = 1.0 / 164.0
SPINE_RADIUS = 1.05 * ARM_UNIT
LONGERON_OFFSET = 4.0 * ARM_UNIT  # from the spine's axis, round the tube and toward the axis
LONGERON_RADIUS = 0.45 * ARM_UNIT
CLAMP_RADIUS = 0.65 * ARM_UNIT
CLAMP_LENGTH = 1.3 * ARM_UNIT
STATIONS = 5
STATION_PITCH = 28.6 * ARM_UNIT
COLLAR_OFFSET = 3.4 * ARM_UNIT  # each collar's distance from its station
COLLAR_REACH = 5.0 * ARM_UNIT
COLLAR_WIDTH = 2.7 * ARM_UNIT
COLLAR_THICKNESS = 1.4 * ARM_UNIT
SLEEVE_RADIUS = 1.75 * ARM_UNIT
SLEEVE_WAIST = 1.3 * ARM_UNIT
SLEEVE_TAPER = 2.4 * ARM_UNIT  # the cone from the spine to the sleeve, outside each collar
# A fin: a flat hexagon from its root to its tip, (span, half chord) pairs, spanning round the tube; swept in toward the axis.
FIN_ROOT = 3.0 * ARM_UNIT
FIN_OUTLINE = ((0.0, 2.5 * ARM_UNIT), (3.5 * ARM_UNIT, 4.75 * ARM_UNIT), (16.4 * ARM_UNIT, 2.25 * ARM_UNIT))
FIN_THICKNESS = 0.35 * ARM_UNIT
FIN_RIM = 0.45 * ARM_UNIT
FIN_SWEEP_DEG = 20.0
# The end caps: a cross whose four arms droop towards the arm's middle, and a cone down to the spine.
CAP_REACH = 4.95 * ARM_UNIT
CAP_WIDTH = 3.7 * ARM_UNIT
CAP_THICKNESS = 1.4 * ARM_UNIT
CAP_DROOP = 1.4 * ARM_UNIT
CAP_CONE = ((1.4, 1.65), (4.8, 1.2))  # (depth from the arm's end, radius), reference units
CAP_BAND = ((4.8, 1.35), (5.1, 1.35))
END_CLAMP_DEPTH = 13.1 * ARM_UNIT  # the longerons' last clamp from each end
# The emitter lens on the back end, our addition from the stills (the ends glow while the vortex forms): (depth backwards, radius).
EMITTER_PROFILE = ((0.0, 1.6), (0.6, 1.4), (1.1, 0.8), (1.3, 0.0))
# The lamps: a small amber box on the inner and outer face of every station, on the collar nearer the back.
LAMP_SIZE = (1.2 * ARM_UNIT, 1.2 * ARM_UNIT, 0.6 * ARM_UNIT)

SPINE_SEGMENTS = 16
TUBE_SEGMENTS = 8
# The textured mesh: four arms on one 2 048 px atlas, about 1.2 m a texel (the packer grows the start value); panels sized to the arm.
ATLAS_PX = 2048
TEXEL_M = 0.7


def _lin(hex_rgb: int) -> tuple[float, float, float]:
    srgb = np.array([(hex_rgb >> 16) & 255, (hex_rgb >> 8) & 255, hex_rgb & 255], dtype=float) / 255.0
    lin = np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)
    return (float(lin[0]), float(lin[1]), float(lin[2]))


# The show's gate: warm tan girders, gunmetal collars and caps, pale grey fins with darker slate insets, amber lamps.
JUMPGATE = Style(
    name="jumpgate",
    materials={
        "hull": Material("jg_cap", _lin(0x5C5A55), paneled=True, metallic=0.3),
        "hull_dark": Material("jg_collar", _lin(0x3A3A3C), paneled=True, metallic=0.4),
        "hull_panel": Material("jg_fin", _lin(0x7E8085), paneled=True, metallic=0.2),
        "stripe": Material("jg_fin_inset", _lin(0x474B54), paneled=True, metallic=0.2),
        "hazard": Material("jg_lamp_housing", _lin(0x2C2B29)),
        "hazard_dark": Material("jg_sleeve", _lin(0x4A4741), paneled=True, metallic=0.4),
        "canopy_glass": Material("jg_glass", (0.01, 0.012, 0.016)),
        "canopy_frame": Material("jg_frame", _lin(0x3A3A3C)),
        "nozzle": Material("jg_nozzle", _lin(0x404248)),
        "nozzle_throat": Material("jg_throat", _lin(0x18181A)),
        "barrel": Material("jg_girder", _lin(0x7D7058), paneled=True, metallic=0.5),
        "bore": Material("jg_bore", (0.01, 0.01, 0.01)),
        "interior": Material("jg_interior", (0.02, 0.02, 0.022)),
        "rcs": Material("jg_spine", _lin(0x6B6352), paneled=True, metallic=0.5),
    },
    panel_size_m=6.0,
    panel_line_width_m=0.6,
    panel_line_darkness=0.7,
    panel_tint_jitter=0.07,
    groove_depth_m=0.15,
    hatch_depth_m=0.06,
    edge_wear_width_m=1.2,
    grime_scale_m=60.0,
    streaks=0.15,
    grime=0.08,
    extra={"wear_scale": 60.0, "rivets": 0.0, "bare_metal": 0.0, "smudge": 0.2, "speckle": 0.04, "paint_roughness": 0.75,
           "streak_length_m": 0.25},
)
LAMP = Material("jg_lamp", (0.05, 0.035, 0.015), roughness=0.2, emissive=(1.0, 0.66, 0.26), emissive_strength=4.0)
EMITTER = Material("jg_emitter", _lin(0x2A2230), roughness=0.15, metallic=0.6, emissive=(1.0, 0.55, 0.85), emissive_strength=0.4)
LAMP_COLOUR = (1.0, 0.66, 0.26)


def _m(role: str) -> Material:
    return JUMPGATE.material(role)


# --- the layout, pure ------------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class GateLayout:
    """The gate's size: an arm's length, the top and bottom arms' distance from the vortex's axis and the side arms', metres."""

    arm_length_m: float = ARM_LENGTH_M
    mouth_aspect: float = MOUTH_ASPECT

    @property
    def arm_radius_m(self) -> float:
        return ARM_RADIUS_SHARE * self.arm_length_m

    @property
    def side_radius_m(self) -> float:
        return self.mouth_aspect * self.arm_radius_m

    def radius_of(self, k: int) -> float:
        """Arm ``k``'s distance from the axis: the even arms are the top and bottom ones, the odd arms the sides."""
        return self.arm_radius_m if k % 2 == 0 else self.side_radius_m


def station_offsets() -> np.ndarray:
    """The stations' places along an arm (shares from its back end), evenly pitched about its middle."""
    return 0.5 + STATION_PITCH * (np.arange(STATIONS) - 0.5 * (STATIONS - 1))


def arm_rotation(k: int) -> np.ndarray:
    """Arm ``k``'s turn from its own frame into the gate's: its length runs to the front (-Z), its fins round the tube and its z out
    from the axis. Exact quarter turns about the axis, so the four arms are exact copies."""
    c, s = [(0, 1), (-1, 0), (0, -1), (1, 0)][k % 4]  # the arm's outward direction: +Y, -X, -Y, +X
    out = np.array([c, s, 0.0])
    round_ = np.array([s, -c, 0.0])  # so (round, front, out) is a proper rotation
    return np.stack([round_, np.array([0.0, 0.0, -1.0]), out], axis=1)


def fin_outline() -> np.ndarray:
    """A fin's hexagon in its own plane, (span from the root, chord), counter-clockwise."""
    half = [(s, -c) for s, c in FIN_OUTLINE] + [(s, c) for s, c in reversed(FIN_OUTLINE)]
    return np.array(half, dtype=float)


def fin_basis(side: float) -> np.ndarray:
    """A starboard (+1) or port (-1) fin's axes in the arm's frame: span, chord (along the arm), normal (a proper rotation)."""
    a = math.radians(FIN_SWEEP_DEG)
    span = np.array([side * math.cos(a), 0.0, -math.sin(a)])  # tips swept toward the axis (-z): the dish faces the funnel
    chord = np.array([0.0, 1.0, 0.0])
    normal = np.cross(span, chord)
    return np.stack([span, chord, normal], axis=1)


def markers(layout: GateLayout, rim_m: tuple[float, float]) -> dict[str, Any]:
    """The points the game needs, in the gate's frame: the vortex (its mouth at the front ends, an ellipse of semi-axes ``rim_m``
    across and up, as deep as an arm is long; ``radius_m`` is the half height, the largest circle inside it), where ships arrive
    and depart, and the emitters on the arms' back ends."""
    front = np.array([0.0, 0.0, -1.0])
    half_width, half_height = rim_m
    unit = layout.arm_length_m * ARM_UNIT
    emitters = []
    for k in range(ARMS):
        r, t = _placement(layout, k)
        lens = r @ np.array([0.0, -EMITTER_PROFILE[-1][0] * unit, 0.0]) + t
        emitters.append({"name": f"arm_{k}", "position": _r(lens), "direction": _r(-front)})
    return {
        "vortex": {"center": [0.0, 0.0, 0.0], "normal": _r(front), "up": [0.0, 1.0, 0.0], "radius_m": round(half_height, 3),
                   "semi_axes_m": [round(half_width, 3), round(half_height, 3)], "depth_m": round(layout.arm_length_m, 3), **vortex_colours()},
        "arrival": {"position": _r(front * ARRIVAL_RADII * half_height), "forward": _r(front), "up": [0.0, 1.0, 0.0],
                    "vortex": "arrival"},
        "departure": {"position": _r(front * DEPARTURE_RADII * half_height), "forward": _r(-front), "up": [0.0, 1.0, 0.0],
                      "vortex": "departure"},
        "emitters": emitters,
    }


def mouth_semi_axes(body: Mesh) -> tuple[float, float]:
    """The vortex's rim, measured off the built mesh: the ellipse (half width, half height) that touches the side arms and the top
    and bottom arms at once, drawn in by the clearance so it comes within a metre of them and meets none."""
    x, y = np.abs(body.vertices[:, 0]), np.abs(body.vertices[:, 1])
    side = x > y
    half_width, half_height = float(x[side].min()), float(y[~side].min())
    # Each pair of arms limits mostly its own semi-axis; a few rounds settle the little each takes from the other.
    for _ in range(8):
        half_height = float((y[~side] / np.sqrt(1.0 - (x[~side] / half_width) ** 2)).min())
        half_width = float((x[side] / np.sqrt(1.0 - (y[side] / half_height) ** 2)).min())
    return half_width - RIM_CLEARANCE_M, half_height - RIM_CLEARANCE_M


def vortex_colours() -> dict[str, Any]:
    """The vortex's look by direction, so the game picks blue for an arrival and orange-yellow for a departure."""
    return {
        "colour_space": "linear",
        "colours": {k: {name: _r(c) for name, c in v.items()} for k, v in VORTEX_COLOURS.items()},
        "flash": _r(VORTEX_FLASH),
    }


def _r(v: Any) -> list[float]:
    return [round(float(x), JSON_DIGITS) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


# --- one arm, in its own frame (y from 0 at the back end to the arm's length at the front; x round the tube; z out from the axis) --
def _along_y(mesh: Mesh) -> Mesh:
    """A mesh built along local Z turned to run along +Y."""
    return mesh.transformed(rotation_x(-0.5 * math.pi))


def spine(length: float) -> Mesh:
    """The central tube with its station sleeves and the cones under both end caps, one surface of revolution."""
    u = length * ARM_UNIT
    rs = SPINE_RADIUS * length
    pts: list[tuple[float, float]] = [(CAP_CONE[0][0] * u, 0.0)]
    mats: list[Material] = []

    def add(y: float, r: float, material: Material) -> None:
        pts.append((y, r))
        mats.append(material)

    sleeve, girder = _m("hazard_dark"), _m("rcs")
    # Under the back cap: its cone and band.
    add(CAP_CONE[0][0] * u, CAP_CONE[0][1] * u, sleeve)
    add(CAP_CONE[1][0] * u, CAP_CONE[1][1] * u, sleeve)
    add(CAP_BAND[0][0] * u, CAP_BAND[0][1] * u, sleeve)
    add(CAP_BAND[1][0] * u, CAP_BAND[1][1] * u, sleeve)
    add(CAP_BAND[1][0] * u, rs, sleeve)
    for share in station_offsets():
        y = share * length
        c0 = c1 = COLLAR_OFFSET * length
        add(y - c0 - SLEEVE_TAPER * length, rs, girder)
        add(y - c0, SLEEVE_RADIUS * length, sleeve)
        add(y - c0 + 0.5 * COLLAR_THICKNESS * length, SLEEVE_WAIST * length, sleeve)
        add(y + c1 - 0.5 * COLLAR_THICKNESS * length, SLEEVE_WAIST * length, sleeve)
        add(y + c1, SLEEVE_RADIUS * length, sleeve)
        add(y + c1 + SLEEVE_TAPER * length, rs, sleeve)
    # Under the front cap, the back one mirrored.
    add(length - CAP_BAND[1][0] * u, rs, girder)
    add(length - CAP_BAND[1][0] * u, CAP_BAND[1][1] * u, sleeve)
    add(length - CAP_BAND[0][0] * u, CAP_BAND[0][1] * u, sleeve)
    add(length - CAP_CONE[1][0] * u, CAP_CONE[1][1] * u, sleeve)
    add(length - CAP_CONE[0][0] * u, CAP_CONE[0][1] * u, sleeve)
    add(length - CAP_CONE[0][0] * u, 0.0, sleeve)
    creases = tuple(range(1, len(pts) - 1))
    return _along_y(lathe(pts, SPINE_SEGMENTS, mats, creases=creases))


def longeron(length: float) -> Mesh:
    """One longeron along the arm's axis (at the origin), its clamp rings between the stations and near both ends."""
    u = length * ARM_UNIT
    y0, y1 = CAP_CONE[0][0] * u, length - CAP_CONE[0][0] * u
    stations = station_offsets() * length
    clamps = [END_CLAMP_DEPTH * length] + [0.5 * (a + b) for a, b in zip(stations[:-1], stations[1:])] + [length - END_CLAMP_DEPTH * length]
    r, rc, half = LONGERON_RADIUS * length, CLAMP_RADIUS * length, 0.5 * CLAMP_LENGTH * length
    pts = [(y0, 0.0), (y0, r)]
    mats = [_m("barrel")]
    for c in clamps:
        pts += [(c - half, r), (c - half, rc), (c + half, rc), (c + half, r)]
        mats += [_m("barrel"), _m("hazard_dark"), _m("hazard_dark"), _m("hazard_dark")]
    pts += [(y1, r), (y1, 0.0)]
    mats += [_m("barrel"), _m("barrel")]
    return _along_y(lathe(pts, TUBE_SEGMENTS, mats, creases=tuple(range(1, len(pts) - 1))))


def longerons(length: float) -> Mesh:
    """The four longerons round the spine: two round the tube, one toward the axis and one away."""
    d = LONGERON_OFFSET * length
    one = longeron(length)
    return Mesh.concatenate(one.translated(offset) for offset in ((d, 0.0, 0.0), (-d, 0.0, 0.0), (0.0, 0.0, d), (0.0, 0.0, -d)))


def collars(length: float) -> Mesh:
    """Two cross-shaped collars at each station, the longerons running through their arms."""
    reach, width, thick = 2.0 * COLLAR_REACH * length, COLLAR_WIDTH * length, COLLAR_THICKNESS * length
    out = []
    for share in station_offsets():
        for sign in (-1.0, 1.0):
            y = share * length + sign * COLLAR_OFFSET * length
            out.append(box((reach, thick, width), _m("hull_dark"), (0.0, y, 0.0)))
            out.append(box((width, thick, reach), _m("hull_dark"), (0.0, y, 0.0)))
    return Mesh.concatenate(out)


def fin(length: float, side: float, station_y: float) -> Mesh:
    """One fin at a station: a framed plate, its inset panel darker, spanning round the tube and swept toward the axis."""
    if side < 0.0:
        # The port fin is the starboard one mirrored, so both sides are exact images.
        return fin(length, 1.0, station_y).mirrored("x")
    outline = fin_outline() * length
    inner = inset_convex_polygon(outline, FIN_RIM * length)
    nxt = np.roll(np.arange(len(outline)), -1)
    rims = [(np.array([outline[i], outline[j], inner[j], inner[i]]), _m("hull_panel")) for i, j in enumerate(nxt)]
    plate = prism([(inner, _m("stripe"))] + rims, [(outline, _m("hull_panel"))], FIN_THICKNESS * length)
    basis = fin_basis(1.0)
    return plate.transformed(basis, basis[:, 0] * FIN_ROOT * length + np.array([0.0, station_y, 0.0]))


def end_cap(length: float, outer: bool) -> Mesh:
    """A cross-shaped cap at one end of the arm, its four arms drooping towards the arm's middle."""
    reach, width, thick, droop = CAP_REACH * length, CAP_WIDTH * length, CAP_THICKNESS * length, CAP_DROOP * length
    centre = [box((width, thick, width), _m("hull"), (0.0, -0.5 * thick, 0.0))]
    arm_len = reach - 0.5 * width
    for turn in range(4):
        # Built along +Z with its far end lowered (-Y), then turned to each side.
        limb = tapered_box(arm_len, (width, thick), (width, thick), _m("hull"), center=(0.0, -0.5 * thick, 0.5 * width + 0.5 * arm_len),
                           offset_b=(0.0, -droop))
        centre.append(limb.transformed(rotation_y(0.5 * math.pi * turn)))
    cap = Mesh.concatenate(centre)  # its top face at y = 0, hanging below
    if outer:
        return cap.translated((0.0, length, 0.0))
    return cap.mirrored("y")


def emitter(length: float) -> Mesh:
    """The lens on the back end, bulging backwards."""
    u = length * ARM_UNIT
    pts = [(0.0, 0.0)] + [(d * u, r * u) for d, r in EMITTER_PROFILE]
    return _along_y(lathe(pts, SPINE_SEGMENTS, EMITTER, creases=(1,))).mirrored("y")


def lamp_positions(length: float) -> list[tuple[np.ndarray, np.ndarray]]:
    """Each lamp's face centre and normal, in the arm's frame: one on the inner and outer face of every station, front first."""
    out = []
    for share in station_offsets()[::-1]:
        y = share * length - COLLAR_OFFSET * length
        for face in (-1.0, 1.0):
            z = face * (COLLAR_REACH * length + LAMP_SIZE[2] * length)
            out.append((np.array([0.0, y, z]), np.array([0.0, 0.0, face])))
    return out


def lamps(length: float) -> Mesh:
    sx, sy, sz = (s * length for s in LAMP_SIZE)
    return Mesh.concatenate(box((sx, sy, sz), LAMP, p - n * 0.5 * sz) for p, n in lamp_positions(length))


def arm_parts(length: float) -> dict[str, Mesh]:
    """Every surface of one arm in its own frame, by part."""
    stations = station_offsets() * length
    fins = [fin(length, side, y) for y in stations for side in (1.0, -1.0)]
    return {
        "spine": spine(length),
        "longeron": longerons(length),
        "collar": collars(length),
        "fin": Mesh.concatenate(fins),
        "cap": Mesh.concatenate([end_cap(length, False), end_cap(length, True)]),
        "emitter": emitter(length),
        "lamp": lamps(length),
    }


def arm_collision(length: float) -> list[Collision]:
    """One arm's boxes in its own frame: the truss with its caps, collars and lamps, then one box per fin."""
    u = length * ARM_UNIT
    tip = -EMITTER_PROFILE[-1][0] * u
    half_x = max(COLLAR_REACH, CAP_REACH, LONGERON_OFFSET + CLAMP_RADIUS) * length
    half_z = COLLAR_REACH * length + LAMP_SIZE[2] * length
    shapes = [Collision("box", (0.0, 0.5 * (tip + length), 0.0), size=(2.0 * half_x, length - tip, 2.0 * half_z), name="truss")]
    span = FIN_OUTLINE[-1][0] * length
    chord = 2.0 * max(c for _, c in FIN_OUTLINE) * length
    for y in station_offsets() * length:
        for side in (1.0, -1.0):
            basis = fin_basis(1.0)
            centre = basis[:, 0] * (FIN_ROOT * length + 0.5 * span) + np.array([0.0, y, 0.0])
            shape = Collision("box", centre, basis, size=(span, chord, FIN_THICKNESS * length), name="fin")
            shapes.append(shape if side > 0.0 else shape.transformed(np.diag([-1.0, 1.0, 1.0])))
    return shapes


def _placement(layout: GateLayout, k: int) -> tuple[np.ndarray, np.ndarray]:
    """Arm ``k``'s rotation and translation from its own frame into the gate's: its back end at z = the arm's length."""
    r = arm_rotation(k)
    return r, r @ np.array([0.0, 0.0, layout.radius_of(k)]) + np.array([0.0, 0.0, layout.arm_length_m])


def gate_parts(layout: GateLayout) -> list[TexturedPart]:
    """All four arms' parts in the gate's frame, as the textured mesh takes them."""
    parts = []
    arm = arm_parts(layout.arm_length_m)
    for k in range(ARMS):
        r, t = _placement(layout, k)
        for name, mesh in arm.items():
            label = f"{name}_{k}"
            parts.append(TexturedPart(mesh.transformed(r, t), phase_steps(label, False), (), label))
    return parts


def lights(layout: GateLayout) -> list[dict[str, Any]]:
    """The amber running lamps in the gate's frame, each arm's from its front end to its back end (the activation's order)."""
    out = []
    for k in range(ARMS):
        r, t = _placement(layout, k)
        for i, (p, n) in enumerate(lamp_positions(layout.arm_length_m)):
            out.append({"name": f"arm_{k}_{i // 2}_{'inner' if n[2] < 0 else 'outer'}", "arm": k, "station": i // 2,
                        "position": _r(r @ p + t), "normal": _r(r @ n), "colour": list(LAMP_COLOUR)})
    return out


def collision(layout: GateLayout) -> list[dict[str, Any]]:
    out = []
    shapes = arm_collision(layout.arm_length_m)
    for k in range(ARMS):
        r, t = _placement(layout, k)
        for i, shape in enumerate(shapes):
            placed = shape.transformed(r, t)
            out.append({**placed.to_json(digits=JSON_DIGITS), "name": f"arm_{k}_{shape.name}_{i}"})
    return out


def hardpoints(layout: GateLayout, body: Mesh) -> dict[str, Any]:
    lo, hi = body.bounds()
    arms = []
    for k in range(ARMS):
        r, t = _placement(layout, k)
        arms.append({"name": f"arm_{k}", "front": _r(t + r @ np.array([0.0, layout.arm_length_m, 0.0])), "back": _r(t),
                     "axis": _r(r @ np.array([0.0, 1.0, 0.0]))})
    return {
        "asset_id": ASSET_ID,
        "generator_version": GENERATOR_VERSION,
        "frame": "godot",
        "units": "m",
        "span_m": round(float(hi[0] - lo[0]), 3),
        "depth_m": round(float(hi[2] - lo[2]), 3),
        "arm_length_m": round(layout.arm_length_m, 3),
        "arm_radius_m": round(layout.arm_radius_m, 3),
        "arm_side_radius_m": round(layout.side_radius_m, 3),
        "mouth_aspect": round(layout.mouth_aspect, 4),
        **markers(layout, mouth_semi_axes(body)),
        "arms": arms,
        "lights": lights(layout),
        "collision": collision(layout),
    }


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the gate into ``ctx.out_dir``.

    Options: ``arm_length_m`` (default 1 200), ``mouth_aspect`` (the side arms' distance from the axis over the top and bottom
    arms', default ``MOUTH_ASPECT``), ``atlas_px`` (default 2 048).
    """
    layout = GateLayout(float(ctx.option("arm_length_m", ARM_LENGTH_M)), float(ctx.option("mouth_aspect", MOUTH_ASPECT)))
    if layout.arm_length_m <= 0.0:
        raise ValueError("arm_length_m must be positive")
    if not 1.0 <= layout.mouth_aspect <= 2.0:
        raise ValueError("mouth_aspect must be between 1 and 2")
    atlas_px = int(ctx.option("atlas_px", ATLAS_PX))
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    parts = gate_parts(layout)
    body = Mesh.concatenate(p.mesh for p in parts)
    aabb_min, aabb_max = body.bounds()
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",)
    files: list[Path] = write_obj(out_dir / OBJ_NAME, body, ASSET_ID, comments)
    texel = TEXEL_M * layout.arm_length_m / ARM_LENGTH_M
    mesh_paths, mesh_entry = write_textured_mesh(out_dir, ASSET_ID, parts, JUMPGATE, atlas_px=atlas_px, texel_m=texel, seed=ctx.seed,
                                                 occlusion=False, normal_scale=1)
    files += mesh_paths

    hp = hardpoints(layout, body)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=aabb_min,
        aabb_max=aabb_max,
        centroid_offset=(0.0, 0.0, 0.0),  # the origin is the vortex's mouth, by design
        files={"obj": OBJ_NAME, "mesh": mesh_entry["file"], "hardpoints": HARDPOINTS_NAME},
        extra={
            "dimensions_m": {"span": hp["span_m"], "depth": hp["depth_m"], "arm_length": hp["arm_length_m"],
                             "arm_radius": hp["arm_radius_m"], "arm_side_radius": hp["arm_side_radius_m"],
                             "vortex_radius": hp["vortex"]["radius_m"], "vortex_half_width": hp["vortex"]["semi_axes_m"][0],
                             "vortex_depth": hp["vortex"]["depth_m"]},
            "mesh": mesh_entry,
            "far": far_section(body.vertices, body.faces),
            "vortex": {k: hp["vortex"][k] for k in ("center", "normal", "up", "radius_m", "semi_axes_m", "depth_m", "colour_space",
                                                    "colours", "flash")},
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
