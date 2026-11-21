"""``ea_thunderbolt``: the Earth Alliance Thunderbolt, model only (M10-T50; M11 gives it a ``ShipSpec`` and a cockpit).

Composition only, on the Starfury's generator (``starfury_aurora``): parts from ``parts/thunderbolt.py`` in the Earthforce
fighter finish, and every output (the textured mesh, the OBJ, hardpoints, chunks) derived from the placed parts so they
agree by construction. The hardpoints, the chunks (``cabin`` and four ``arm_<pod>``) and the livery zones are the
Starfury's contract, so the game's fighter code takes it as it takes the Starfury.

The shape is the reference model's (``references/EA_Thunderbolt_fighter.stl``, turned 42 degrees about its z, at 16.24 m;
never committed), held to the 90 % rule (docs/assets-starfury.md, "Thunderbolt"). Authored frame, metres: the reference's
ship frame, the nose at z = 0 and +z aft (Godot's -Z forward), x and y on the reference's box centre:

* a long narrow two-seat fuselage with a glazed spine, a chin box under its forward half, three guns under the nose and a
  store behind each side gun;
* two wing plates a side, swept back from the fuselage and bent forward again into the pods, their inboard parts the
  centre body's upper and lower deck; a trunk between them, a diamond block on the upper deck's rear, a cannon housing in
  each upper wing root;
* four eight-sided engine pods (5.2 m long) at x = +-5.22, y = 1.82 and -2.17, a retro bell in each nose; behind each an
  engine, two blades and a fin swept inboard.

The upper and lower arms are not mirror images (the lower pod is the upper one moved down; wings and tails differ), so
each starboard arm is authored and the port side mirrors it. The sample set is exactly mirror-symmetric in x; the samples'
centroid's y and z are moved to the origin, so the hardpoints frame equals the rendered frame.

Class budget (M10 Q38): a fighter, one 2 048 px atlas with a 4 096 px normal map; the low texture set a mip level down
(``low_shrink``; 1 writes it at full size, for the maintainer's comparison of the two, Q52).
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any

import numpy as np

from ..core.budgets import LOW_SHRINK, over_budget, texture_mb
from ..core.chunks import ChunkCut, ChunkSource, chunk_offsets, write_chunks
from ..core.color import capture_albedo
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh
from ..core.livery import ZONES
from ..core.manifest import build_manifest, write_manifest
from ..core.obj import write_obj
from ..core.sampling import SurfaceSamples, sample_mesh
from ..core.seams import MAJOR
from ..core.textured_mesh import TexturedPart, phase_steps, write_textured_mesh
from ..core.textures import NORMAL_SCALE, Marking
from ..parts import Part, layouts, mass_centroid, total_mass
from ..parts.propulsion import pilot_tags
from ..parts.thunderbolt import (
    BoltCanopySpec,
    BoltFittingsSpec,
    BoltFuselageSpec,
    BoltGunSpec,
    BoltPodSpec,
    BoltStation,
    BoltTailSpec,
    BoltWingSpec,
    BladeSpec,
    ChinSpec,
    ChordStation,
    SpineStation,
    TrunkSpec,
    bolt_canopy,
    bolt_chin,
    bolt_deck,
    bolt_fittings,
    bolt_fuselage,
    bolt_guns,
    bolt_pod,
    bolt_tail,
    bolt_trunk,
    bolt_wing,
)
from ..styles import Style
from ..styles.ea_thunderbolt import BLACK, DEFAULT_LOOK, LOOKS, MOUTH, TEETH, Look
from .starfury_aurora import PAINTABLE, STENCIL, Placed, bare_metal, centre

ASSET_ID = "ea_thunderbolt"
GENERATOR_VERSION = 1
SHIP_CLASS = "fighter"  # its class budget (docs/assets-capital.md, "Class budgets")
OBJ_NAME = "ea_thunderbolt.obj"
HARDPOINTS_NAME = "hardpoints.json"
ATLAS_PX = 2048
TEXEL_M = 0.012  # the packer grows it until the hull fits the atlas
DETAIL_LEVELS = {"low": MAJOR}  # the second texture set, major seams only, for `settings.texture_detail`

# The reference model: its file is turned about its z, then mapped onto (right, up, aft); the 90 % rule scores against it.
REFERENCE_LENGTH_M = 16.24
REFERENCE_MAPPING = ("-x", "+z", "+y")
REFERENCE_TURN = "z=42"

DEFAULT_SPACING_M = 0.06  # the surface samples' spacing: the centroid, the buried faces, the chunks' offsets
BURIED_MARGIN_M = 0.01
JSON_DIGITS = 5
CHASE_ANCHOR = (0.0, 4.2, 18.0)  # behind and above the centroid; frames the 12 m span at 70 degrees
POD_SIDES = (("ur", "right"), ("lr", "right"), ("ul", "left"), ("ll", "left"))
CHUNK_ORDER = ("cabin",) + tuple(f"arm_{pod}" for pod, _ in POD_SIDES)
ARM_PARTS = ("wing", "pod", "tail")
MUZZLE_ORDER = ("nose", "left", "right", "root_left", "root_right")  # left and right take turns in alternating fire
# The livery zone each kind of part is painted as (``core/livery.py``): the Starfury's, so a wing's livery fits both.
PART_ZONES = {"fuselage": "fuselage", "canopy": "fuselage", "chin": "fuselage", "trunk": "fuselage", "fittings": "fittings",
              "gun": "gun_mount", "pod": "pod", "tail": "claw"}
NAV_LIGHT_CLEARANCE_M = 0.12
NAV_LAMP_HEIGHT_M = 2.5
NAV_LAMP_RANGE_M = 6.0
NAV_CABIN_RANGE_M = 1.6


# --- the parametric description (authored frame; stations measured off the reference's silhouettes and sections) -------
FUSELAGE = BoltFuselageSpec(
    stations=tuple(BoltStation(*row) for row in (
        # z, keel y, keel half width, shoulder y, shoulder half width, deck y, deck half width
        (0.40, -0.42, 0.08, -0.25, 0.17, -0.08, 0.13),
        (0.90, -0.90, 0.13, -0.15, 0.21, 0.02, 0.15),
        (1.20, -1.00, 0.20, -0.12, 0.23, 0.04, 0.17),
        (2.00, -1.40, 0.28, -0.10, 0.28, 0.05, 0.25),
        (2.80, -1.40, 0.29, -0.10, 0.33, 0.12, 0.27),
        (3.60, -1.40, 0.29, -0.10, 0.40, 0.18, 0.32),
        (4.40, -1.41, 0.29, -0.10, 0.48, 0.20, 0.40),
        (5.20, -1.45, 0.31, -0.10, 0.52, 0.22, 0.43),
        (6.00, -1.53, 0.31, -0.10, 0.54, 0.25, 0.48),
        (6.80, -1.60, 0.31, -0.10, 0.55, 0.30, 0.50),
        (8.30, -1.60, 0.33, -0.10, 0.56, 0.40, 0.50),
        (9.80, -1.52, 0.33, -0.10, 0.56, 0.40, 0.50),
        (10.20, -1.32, 0.33, -0.10, 0.54, 0.40, 0.48),
        (10.60, -0.95, 0.33, -0.10, 0.50, 0.40, 0.45),
    )),
    cabin_z=(2.05, 4.95),
)  # fmt: skip
CANOPY = BoltCanopySpec(
    stations=tuple(SpineStation(*row) for row in (
        # z, base y, base half width, top y, top half width
        (0.45, -0.10, 0.12, -0.06, 0.10),
        (0.90, 0.00, 0.14, 0.04, 0.12),
        (1.60, 0.03, 0.19, 0.12, 0.15),
        (2.00, 0.04, 0.22, 0.23, 0.16),
        (2.80, 0.10, 0.24, 0.46, 0.19),
        (3.65, 0.16, 0.28, 0.69, 0.22),
        (4.00, 0.18, 0.30, 0.73, 0.24),
        (5.00, 0.20, 0.31, 0.76, 0.27),
        (6.20, 0.25, 0.32, 0.78, 0.28),
        (7.00, 0.30, 0.32, 0.80, 0.28),
        (7.45, 0.30, 0.30, 0.78, 0.26),
    )),
    panes=((2.05, 3.60), (3.75, 4.95)),
    frames=((1.95, 2.05), (3.60, 3.75), (4.95, 5.05)),
    eye=(0.0, 0.42, 3.30),
)  # fmt: skip
CHIN = ChinSpec(stations=((1.00, -0.55, -1.30, 0.50), (1.25, -0.52, -1.50, 0.54), (2.90, -0.52, -1.67, 0.55), (3.55, -0.52, -1.67, 0.55),
                          (4.25, -0.50, -1.05, 0.42)))


def _wing(rows: tuple[tuple[float, float, tuple[tuple[float, float], ...]], ...], **kw: Any) -> BoltWingSpec:
    return BoltWingSpec(tuple(ChordStation(x, flat, ridge) for x, flat, ridge in rows), split_x=1.8, **kw)


# x, the flat (lower) face's y, then (z, y) along the ridged (upper) face from the leading to the trailing edge. The plate
# is a delta over the fuselage inboard, sweeps back to x = 3.25 and bends forward again into the pod's flank.
UPPER_WING = _wing((
    (0.00, 0.20, ((5.40, 0.44), (6.20, 0.50), (7.00, 0.68), (9.00, 1.05), (10.20, 0.97), (11.20, 0.90))),
    (0.45, 0.20, ((5.40, 0.44), (6.20, 0.48), (7.00, 0.67), (9.00, 1.05), (10.20, 0.97), (11.20, 0.90))),
    (1.00, 0.45, ((6.50, 0.50), (6.60, 0.56), (7.60, 0.83), (9.00, 1.05), (10.20, 0.97), (11.30, 0.90))),
    (1.40, 0.70, ((7.30, 0.74), (7.40, 0.78), (8.30, 1.00), (9.30, 1.07), (10.30, 0.99), (11.44, 0.88))),
    (1.80, 0.91, ((8.15, 0.94), (8.25, 0.99), (9.00, 1.16), (9.60, 1.24), (10.60, 1.17), (11.65, 1.06))),
    (2.20, 1.12, ((9.04, 1.15), (9.14, 1.21), (9.50, 1.34), (10.00, 1.40), (11.00, 1.33), (11.86, 1.24))),
    (2.60, 1.33, ((9.68, 1.36), (9.78, 1.42), (10.10, 1.53), (10.60, 1.57), (11.30, 1.52), (12.07, 1.45))),
    (3.00, 1.54, ((10.32, 1.57), (10.42, 1.61), (10.70, 1.72), (11.10, 1.73), (11.70, 1.69), (12.27, 1.65))),
    (3.25, 1.60, ((10.65, 1.63), (10.75, 1.68), (11.00, 1.78), (11.30, 1.80), (11.80, 1.76), (12.35, 1.70))),
    (3.85, 1.72, ((10.67, 1.76), (10.77, 1.82), (11.00, 1.90), (11.40, 1.94), (11.90, 1.90), (12.40, 1.84))),
    (4.10, 1.81, ((9.95, 1.84), (10.05, 1.88), (10.40, 1.96), (10.80, 1.98), (11.60, 1.94), (12.31, 1.90))),
    (4.40, 1.85, ((9.24, 1.88), (9.34, 1.92), (9.70, 1.99), (10.20, 2.01), (11.20, 1.98), (12.30, 1.93))),
    (4.70, 1.86, ((8.65, 1.89), (8.75, 1.93), (9.20, 2.00), (9.80, 2.02), (11.00, 1.99), (12.30, 1.94))),
), blister=((11.00, 3.25, 3.80, 1.64, 1.88), (11.45, 3.14, 3.88, 1.56, 1.93), (12.50, 3.14, 3.88, 1.56, 1.93), (12.96, 3.28, 3.76, 1.66, 1.84)),
   blister_shear=0.2)  # fmt: skip
# The lower plate: rooted in the fuselage's lower flank, a little more swept inboard, its ridge on top as the upper one's.
LOWER_WING = _wing((
    (0.00, -1.20, ((6.60, -1.15), (6.75, -1.10), (7.60, -0.90), (8.40, -0.84), (9.60, -0.93), (10.75, -1.05))),
    (0.60, -1.22, ((6.85, -1.15), (6.95, -1.06), (7.60, -0.86), (8.40, -0.84), (9.60, -0.93), (10.75, -1.05))),
    (1.00, -1.06, ((7.30, -1.00), (7.40, -0.92), (8.10, -0.70), (9.00, -0.69), (10.20, -0.78), (11.10, -0.90))),
    (1.40, -1.07, ((7.80, -1.01), (7.90, -0.94), (8.60, -0.79), (9.20, -0.70), (10.20, -0.77), (11.43, -0.95))),
    (1.80, -1.22, ((8.60, -1.17), (8.70, -1.10), (9.10, -0.98), (9.60, -0.90), (10.60, -0.97), (11.65, -1.08))),
    (2.20, -1.38, ((9.20, -1.33), (9.30, -1.27), (9.60, -1.16), (10.20, -1.10), (11.00, -1.16), (11.86, -1.25))),
    (2.60, -1.53, ((9.80, -1.50), (9.90, -1.44), (10.20, -1.33), (10.80, -1.30), (11.40, -1.36), (12.07, -1.42))),
    (3.00, -1.68, ((10.38, -1.66), (10.48, -1.61), (10.80, -1.51), (11.20, -1.49), (11.70, -1.54), (12.28, -1.60))),
    (3.25, -1.74, ((10.65, -1.72), (10.75, -1.68), (11.00, -1.60), (11.30, -1.57), (11.80, -1.62), (12.35, -1.67))),
    (3.85, -1.92, ((10.62, -1.88), (10.72, -1.84), (11.00, -1.76), (11.40, -1.72), (11.90, -1.76), (12.40, -1.82))),
    (4.10, -1.94, ((9.90, -1.92), (10.00, -1.88), (10.30, -1.80), (10.80, -1.78), (11.50, -1.82), (12.31, -1.85))),
    (4.40, -1.99, ((9.19, -1.96), (9.29, -1.92), (9.60, -1.86), (10.20, -1.83), (11.20, -1.87), (12.30, -1.90))),
    (4.70, -2.00, ((8.65, -1.97), (8.75, -1.93), (9.20, -1.86), (9.80, -1.84), (11.00, -1.87), (12.30, -1.90))),
), blister=((11.00, 3.25, 3.80, -1.92, -1.66), (11.45, 3.14, 3.88, -1.97, -1.60), (12.50, 3.14, 3.88, -1.97, -1.60), (12.96, 3.28, 3.76, -1.88, -1.70)),
   blister_shear=-0.15)  # fmt: skip

# The pod in its own frame: outlines from the inner lower corner round by the bottom, the outer flank and the top (the
# flat bottom and the peaked top make it taller than wide).
POD = BoltPodSpec(stations=(
    (7.10, ((-0.39, -0.37), (-0.20, -0.66), (0.11, -0.66), (0.33, -0.36), (0.34, 0.08), (0.16, 0.27), (-0.25, 0.26), (-0.40, 0.06))),
    (7.40, ((-0.44, -0.42), (-0.22, -0.72), (0.12, -0.72), (0.40, -0.39), (0.39, 0.15), (0.18, 0.35), (-0.28, 0.34), (-0.46, 0.11))),
    (8.00, ((-0.50, -0.40), (-0.20, -0.80), (0.21, -0.78), (0.50, -0.30), (0.47, 0.29), (0.19, 0.49), (-0.23, 0.50), (-0.53, 0.24))),
    (8.40, ((-0.54, -0.36), (-0.19, -0.80), (0.24, -0.76), (0.52, -0.25), (0.48, 0.33), (0.20, 0.53), (-0.39, 0.46), (-0.58, 0.24))),
    (8.70, ((-0.54, -0.36), (-0.19, -0.78), (0.26, -0.73), (0.55, -0.26), (0.50, 0.36), (0.20, 0.55), (-0.38, 0.49), (-0.59, 0.26))),
    (10.00, ((-0.58, -0.33), (-0.23, -0.77), (0.28, -0.74), (0.61, -0.19), (0.56, 0.49), (0.23, 0.71), (-0.42, 0.65), (-0.59, 0.46))),
    (11.00, ((-0.57, -0.33), (-0.21, -0.77), (0.29, -0.73), (0.63, -0.13), (0.56, 0.56), (0.25, 0.77), (-0.44, 0.70), (-0.58, 0.54))),
    (12.38, ((-0.58, -0.30), (-0.18, -0.75), (0.30, -0.71), (0.64, -0.14), (0.58, 0.56), (0.16, 0.78), (-0.42, 0.74), (-0.58, 0.55))),
))  # fmt: skip
POD_X = 5.22
POD_Y = {"u": 1.82, "l": -2.17}  # the pods' axes: the lower pod is the upper one moved down, not mirrored

# The tails differ: the upper fin climbs steeper than the lower one drops, and the blades taper towards opposite edges.
FIN_OUTLINE = ((13.08, 4.38), (13.60, 3.99), (15.40, 1.71), (15.74, 1.96), (15.74, 2.31), (15.60, 2.29), (15.20, 2.76), (14.80, 3.77), (14.45, 4.20),
               (14.10, 4.36))


def _fin(root_y: float, rise: float) -> tuple[tuple[float, float, float], ...]:
    """The fin's outline in a pod's frame: ``FIN_OUTLINE`` (z, ship x) laid on the plane that passes ``root_y`` at the pod's
    inner flank and climbs ``rise`` for every metre inboard."""
    return tuple((x - POD_X, root_y + rise * (4.38 - x), z) for z, x in FIN_OUTLINE)


# Plates round each engine, as ``(z, section)`` stations: the inner one thin by the engine and a thick prong behind it, a
# short outer one, and one under (the lower pods: over and under) the engine.
UPPER_TAIL = BoltTailSpec(
    engine_at=(0.0, 0.0),
    blades=(
        BladeSpec(((12.85, ((-0.66, -0.30), (-0.59, 0.45))), (13.20, ((-0.74, -0.48), (-0.60, 0.62))), (14.00, ((-0.74, -0.48), (-0.60, 0.62))),
                   (14.40, ((-0.70, -0.14), (-0.66, 0.40)))), 0.06),
        BladeSpec(((14.20, ((-0.715, -0.14), (-0.715, 0.40))), (15.20, ((-0.715, -0.10), (-0.715, 0.38))), (16.00, ((-0.715, -0.05), (-0.715, 0.34))),
                   (16.24, ((-0.715, -0.03), (-0.715, 0.32)))), 0.20),
        BladeSpec(((12.90, ((0.62, -0.20), (0.66, 0.42))), (14.00, ((0.62, -0.20), (0.66, 0.40))), (14.40, ((0.63, -0.19), (0.66, 0.14))),
                   (15.10, ((0.64, -0.17), (0.66, 0.06)))), 0.05),
        BladeSpec(((13.15, ((0.05, -0.65), (0.42, -0.63), (0.56, -0.42))), (13.70, ((0.05, -0.65), (0.42, -0.63), (0.56, -0.42))),
                   (14.20, ((0.10, -0.46), (0.40, -0.44), (0.56, -0.28))), (15.10, ((0.30, -0.30), (0.45, -0.29), (0.60, -0.25)))), 0.06),
    ),
    fin=_fin(0.33, 0.367),
)
LOWER_TAIL = BoltTailSpec(
    engine_at=(0.0, 0.04),
    blades=(
        BladeSpec(((12.85, ((-0.62, -0.30), (-0.72, 0.25))), (13.20, ((-0.60, -0.41), (-0.76, 0.28))), (14.00, ((-0.60, -0.41), (-0.76, 0.28))),
                   (14.40, ((-0.71, -0.40), (-0.48, 0.06))), (15.20, ((-0.72, -0.42), (-0.42, -0.04))), (16.00, ((-0.71, -0.40), (-0.42, -0.05))),
                   (16.24, ((-0.66, -0.36), (-0.46, -0.08)))), 0.07),
        BladeSpec(((12.90, ((0.78, -0.22), (0.62, 0.43))), (14.00, ((0.78, -0.09), (0.62, 0.44))), (14.40, ((0.78, 0.09), (0.55, 0.45))),
                   (15.25, ((0.78, 0.15), (0.48, 0.42)))), 0.05),
        BladeSpec(((13.05, ((0.00, 0.74), (0.30, 0.80), (0.62, 0.42))), (13.60, ((0.00, 0.74), (0.30, 0.80), (0.62, 0.42))),
                   (14.00, ((0.02, 0.66), (0.30, 0.71), (0.60, 0.42))), (14.40, ((0.04, 0.54), (0.30, 0.58), (0.56, 0.44))),
                   (15.20, ((0.10, 0.44), (0.30, 0.48), (0.50, 0.42)))), 0.10),
        BladeSpec(((12.90, ((-0.56, -0.42), (-0.24, -0.73), (0.02, -0.70))), (14.00, ((-0.56, -0.42), (-0.24, -0.73), (0.02, -0.70))),
                   (14.30, ((-0.50, -0.40), (-0.26, -0.54), (0.02, -0.52)))), 0.07),
    ),
    fin=_fin(-0.175, -0.294),
)


@dataclass(frozen=True)
class ThunderboltSpec:
    fuselage: BoltFuselageSpec = FUSELAGE
    canopy: BoltCanopySpec = CANOPY
    chin: ChinSpec = CHIN
    guns: BoltGunSpec = BoltGunSpec()
    fittings: BoltFittingsSpec = BoltFittingsSpec()
    trunk: TrunkSpec = TrunkSpec()
    upper_wing: BoltWingSpec = UPPER_WING
    lower_wing: BoltWingSpec = LOWER_WING
    pod: BoltPodSpec = POD
    upper_tail: BoltTailSpec = UPPER_TAIL
    lower_tail: BoltTailSpec = LOWER_TAIL

    def pod_centre(self, level: str) -> np.ndarray:
        return np.array([POD_X, POD_Y[level], 0.0])


DEFAULT_SPEC = ThunderboltSpec()


# --- placing and sampling -----------------------------------------------------------------------------------------------
def _unburied(samples: SurfaceSamples, *inside: np.ndarray) -> SurfaceSamples:
    buried = np.zeros(len(samples), dtype=bool)
    for mask in inside:
        buried |= mask
    return samples.subset(~buried)


def _solids(spec: ThunderboltSpec) -> dict[str, Any]:
    """What a part's hidden faces lie inside: every closed body by the name of the part that owns it (authored frame, both
    sides at once)."""

    def pods(points: np.ndarray, margin: float) -> np.ndarray:
        p = np.array(points, dtype=float).reshape(-1, 3)
        p[:, 0] = np.abs(p[:, 0])
        return spec.pod.contains(p - spec.pod_centre("u"), margin) | spec.pod.contains(p - spec.pod_centre("l"), margin)

    return {"fuselage": spec.fuselage.contains, "chin": spec.chin.contains, "trunk": spec.trunk.contains,
            "upper": spec.upper_wing.contains, "lower": spec.lower_wing.contains, "pod": pods}


def build_parts(spec: ThunderboltSpec, style: Style, ctx: BuildContext, spacing: float, plate_tone: float = 0.06) -> list[Placed]:
    """Every part in the authored frame, sampled, the port side mirrored from the starboard one (so the set is exactly
    symmetric); samples inside another body are dropped."""
    surface = layouts.thunderbolt(plate_tone)
    solids = _solids(spec)

    def placed(part: Part, stream: str, own: str = "", symmetric: bool = False) -> Placed:
        samples = sample_mesh(part.mesh, spacing, ctx.rng("surface", stream))
        samples = _unburied(samples, *(inside(samples.positions, BURIED_MARGIN_M) for name, inside in solids.items() if name != own))
        return Placed(part, samples.symmetrized("x") if symmetric else samples)

    def centre_part(part: Part, name: str, layout: str = "", own: str = "", both_sides: bool = False) -> Placed:
        seams = surface.get(layout or name, layouts.EMPTY)
        return placed(part.renamed(name, group="cabin").with_seams(seams.mirrored_too() if both_sides else seams), name, own, True)

    body = [
        centre_part(bolt_fuselage(spec.fuselage, style), "fuselage", own="fuselage"),
        centre_part(bolt_canopy(spec.canopy, style), "canopy"),
        centre_part(bolt_chin(spec.chin, style), "chin", own="chin"),
        centre_part(bolt_guns(spec.guns, style), "gun_mount"),
        centre_part(bolt_fittings(spec.fittings, style), "fittings"),
        centre_part(bolt_trunk(spec.trunk, style), "trunk", own="trunk"),
        centre_part(bolt_deck(spec.upper_wing, style), "deck_upper", "deck", "upper", both_sides=True),
        centre_part(bolt_deck(spec.lower_wing, style), "deck_lower", "deck", "lower", both_sides=True),
    ]
    arms: list[Placed] = []
    for level, wing_spec, tail_spec in (("u", spec.upper_wing, spec.upper_tail), ("l", spec.lower_wing, spec.lower_tail)):
        at = spec.pod_centre(level)
        wing = bolt_wing(wing_spec, style).with_seams(surface["wing"]).renamed(f"wing_{level}r", group="arm")
        pod = bolt_pod(spec.pod, style).with_seams(surface["pod"]).translated(at).renamed(f"pod_{level}r", group="arm")
        tail = bare_metal(bolt_tail(tail_spec, style), style, lambda c: np.abs(c[:, 0]) < 0.9)  # the blades; the fin keeps its paint
        tail = tail.with_seams(surface["tail"]).translated(at).renamed(f"tail_{level}r", group="arm")
        right = [placed(wing, f"wing_{level}", "upper" if level == "u" else "lower"), placed(pod, f"pod_{level}", "pod"), placed(tail, f"tail_{level}")]
        arms += right
        arms += [Placed(p.part.mirrored("x").renamed(p.part.name[:-1] + "l"), p.samples.mirrored("x")) for p in right]
    return body + arms


def chunk_of(part_name: str) -> str:
    """The break-up chunk a part belongs to: a corner's wing, pod and tail are ``arm_<pod>``, everything else the ``cabin``."""
    kind, _, pod = part_name.rpartition("_")
    return f"arm_{pod}" if kind in ARM_PARTS and pod in dict(POD_SIDES) else "cabin"


def zone_of(part_name: str) -> int:
    """The livery zone of a part (0: never painted)."""
    kind, _, where = part_name.partition("_")
    if kind in ("wing", "deck"):
        return ZONES["strut_upper" if where.startswith("u") else "strut_lower"]
    return ZONES[PART_ZONES[kind]]


def build_chunks(placed: list[Placed]) -> list[ChunkSource]:
    sources = []
    for name in CHUNK_ORDER:
        members = [p for p in placed if chunk_of(p.part.name) == name]
        points = np.concatenate([p.samples.positions for p in members if p.samples is not None])
        sources.append(ChunkSource(name, points, Mesh.concatenate(p.part.mesh for p in members if p.hull)))
    return sources


# --- paint ----------------------------------------------------------------------------------------------------------------
def _band(lo: float, hi: float, soft: float = 0.01) -> Any:
    def cover(values: np.ndarray) -> np.ndarray:
        return np.clip((np.minimum(values - lo, hi - values)) / soft + 0.5, 0.0, 1.0)

    return cover


def _mouth(points: np.ndarray, normals: np.ndarray, offset: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """The shark's mouth on the chin's flanks (authored frame): its dark lip line, where it is open, and where its teeth are."""
    z, y = points[:, 2] + offset[2], points[:, 1] + offset[1]
    t = np.clip((z - 1.10) / 2.45, 0.0, 1.0)
    half = 0.36 * np.sin(math.pi * t) ** 0.5 * (1.0 - 0.3 * t)
    depth = half - np.abs(y - (-1.07 + 0.08 * t))  # how far inside the lips
    flank = (np.abs(normals[:, 0]) > 0.5) & (t > 0.0) & (t < 1.0)
    inside = flank & (depth > 0.0)
    saw = 1.0 - np.abs(np.mod(z / 0.24, 1.0) - 0.5) * 2.0
    lip = flank & (depth > -0.035) & (depth <= 0.015)
    return lip.astype(float), inside.astype(float), (inside & (depth < 0.7 * half * saw)).astype(float)


def markings_for(placed: list[Placed], look: Look, offset: np.ndarray) -> dict[str, tuple[Marking, ...]]:
    """What the maps paint on each part beyond its plating (centred frame): soot at every bell, "EA" on the fuselage, and
    the look's bands, anti-glare strip, nose cap and nose art. A wing's colours and number are the livery's."""
    off = np.asarray(offset, dtype=float)
    red = capture_albedo(look.band) if look.band is not None else None
    black = capture_albedo(BLACK)
    out: dict[str, list[Marking]] = {}

    def paint(name: str, colour: tuple[float, float, float], cover: Any) -> None:
        out.setdefault(name, []).append(Marking.paint(name, colour, cover))

    for p in placed:
        name, kind = p.part.name, p.part.name.split("_")[0]
        if kind == "pod":
            a = p.part.anchor("retro")
            out.setdefault(name, []).append(Marking.soot(name, a.position, a.direction, 0.45, 0.35, 0.6))
            if red is not None:
                paint(name, red, lambda q, n: _band(9.08, 9.42)(q[:, 2] + off[2]))
        elif kind == "tail":
            a = p.part.anchor("main")
            out.setdefault(name, []).append(Marking.soot(name, a.position, a.direction, 0.6, 0.5, 0.9))
            if red is not None:  # the fin's tip
                paint(name, red, lambda q, n: _band(15.25, 99.0)(q[:, 2] + off[2]) * (np.abs(q[:, 0]) < 3.9))
        elif kind == "wing" and red is not None:
            paint(name, red, lambda q, n: _band(2.25, 2.75)(np.abs(q[:, 0])))
        elif name == "fuselage":
            z = 6.3 - off[2]
            for side in (1.0, -1.0):
                out.setdefault(name, []).append(Marking.text(name, "EA", (side * 0.5, -0.45 - off[1], z), (0.0, 0.0, -side), (0.0, 1.0, 0.0),
                                                             (side, 0.0, 0.0), 0.32, STENCIL))
        if name in ("fuselage", "canopy"):
            if look.anti_glare:
                paint(name, black, lambda q, n: _band(0.85, 1.95)(q[:, 2] + off[2]) * (n[:, 1] > 0.3))
            if look.nose_cap and red is not None:
                paint(name, red, lambda q, n: _band(-9.0, 0.85)(q[:, 2] + off[2]))
        if name == "chin" and look.nose_art:
            paint(name, capture_albedo(MOUTH), lambda q, n: _mouth(q, n, off)[1])
            paint(name, capture_albedo(TEETH), lambda q, n: _mouth(q, n, off)[2])
            paint(name, black, lambda q, n: _mouth(q, n, off)[0])
    return {name: tuple(marks) for name, marks in out.items()}


def textured_parts(placed: list[Placed], look: Look, offset: np.ndarray) -> list[TexturedPart]:
    """The hull parts as the textured mesh takes them: mesh, panel phase, markings, livery zone and drawn surface."""
    marks = markings_for(placed, look, offset)
    return [TexturedPart(p.part.mesh, phase_steps(p.part.name, True), marks.get(p.part.name, ()), p.part.name, zone_of(p.part.name), p.part.seams)
            for p in placed if p.hull]


# --- hardpoints -----------------------------------------------------------------------------------------------------------
def _r(v: Any) -> list[float]:
    return [round(float(x), JSON_DIGITS) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


def _axis_label(direction: np.ndarray) -> str:
    axis = int(np.argmax(np.abs(direction)))
    return ("p" if direction[axis] > 0 else "n") + "xyz"[axis]


def nav_lights(by_name: dict[str, Part], eye: np.ndarray) -> dict[str, Any]:
    """Running lights: red and green on the upper pods' tops, white on the block at the deck's rear, a lamp standing over the
    deck to light it, and the cabin glow at the front seat."""
    pod_lo, pod_hi = by_name["pod_ur"].mesh.bounds()
    pod = by_name["pod_ur"].anchor("center").position
    block_top = float(by_name["trunk"].mesh.bounds()[1][1])
    block_z = float(by_name["trunk"].mesh.bounds()[1][2]) - 0.8
    return {
        "port": _r((-pod[0], float(pod_hi[1]) + NAV_LIGHT_CLEARANCE_M, pod[2])),
        "starboard": _r((pod[0], float(pod_hi[1]) + NAV_LIGHT_CLEARANCE_M, pod[2])),
        "top": _r((0.0, block_top + NAV_LIGHT_CLEARANCE_M, block_z)),
        "top_lamp": _r((0.0, block_top + NAV_LAMP_HEIGHT_M, block_z - 2.0)),
        "top_lamp_range_m": NAV_LAMP_RANGE_M,
        "cabin": _r(eye),
        "cabin_range_m": NAV_CABIN_RANGE_M,
    }


def hardpoints(placed: list[Placed], spec: ThunderboltSpec, chunks: list[dict[str, Any]]) -> dict[str, Any]:
    """The hardpoints document (centred Godot frame) from the placed parts; ``chunks`` are the ``write_chunks`` entries."""
    by_name = {p.part.name: p.part for p in placed}
    hull_parts = [p.part for p in placed if p.hull]
    lo, hi = Mesh.concatenate(p.mesh for p in hull_parts).bounds()

    # Trimmed onto the thrust axis by design (ballast), as the Starfury: the four bells' centre line.
    axis_y = float(np.mean([by_name[f"tail_{n}"].anchor("main").position[1] for n, _ in POD_SIDES]))
    com = np.array([0.0, axis_y, float(mass_centroid(hull_parts)[2])])
    inertia = np.zeros(3)
    for part in hull_parts:
        d = part.area_centroid() - com
        inertia += part.mass_kg * np.array([d[1] ** 2 + d[2] ** 2, d[0] ** 2 + d[2] ** 2, d[0] ** 2 + d[1] ** 2])

    pods, rcs, joints = [], [], {}
    for name, side in POD_SIDES:
        pod, tail = by_name[f"pod_{name}"], by_name[f"tail_{name}"]
        main, retro = tail.anchor("main"), pod.anchor("retro")
        pods.append({
            "name": name,
            "side": side,
            "center": _r(pod.anchor("center").position),
            "main": {"position": _r(main.position), "exhaust": _r(main.direction), "radius": spec.upper_tail.bell.exit_r},
            "retro": {"position": _r(retro.position), "exhaust": _r(retro.direction), "radius": spec.pod.retro.exit_r},
        })
        for key in ("rcs_px", "rcs_py", "rcs_ny"):
            a = pod.anchor(key)
            rcs.append({"name": f"{name}_{_axis_label(a.direction)}", "pod": name, "position": _r(a.position), "exhaust": _r(a.direction),
                        "tags": pilot_tags(a.position, a.direction, com)})
        joints[f"arm_{name}"] = by_name[f"wing_{name}"].anchor("root").position  # where the wing leaves the centre body
    arms = np.array(list(joints.values()))
    joints["cabin"] = np.array([0.0, arms[:, 1].mean(), arms[:, 2].mean()])

    anchors = {**by_name["gun_mount"].anchors, **by_name["fittings"].anchors}
    muzzles = [{"name": n, "position": _r(anchors[f"muzzle_{n}"].position), "direction": _r(anchors[f"muzzle_{n}"].direction)} for n in MUZZLE_ORDER]
    collision = [{**shape.to_json(digits=JSON_DIGITS), "name": f"{part.name}_{shape.name}" if shape.name != part.name else part.name}
                 for part in hull_parts for shape in part.collision]
    eye = by_name["canopy"].anchor("eye")
    return {
        "asset_id": ASSET_ID,
        "generator_version": GENERATOR_VERSION,
        "frame": "godot",
        "units": "m",
        "length_m": round(float(hi[2] - lo[2]), 3),
        "span_m": round(float(hi[0] - lo[0]), 3),
        "height_m": round(float(hi[1] - lo[1]), 3),
        "mass_kg": round(total_mass(hull_parts), 1),
        "inertia_estimate_kg_m2": _r(inertia),
        "center_of_mass": _r(com),
        "cockpit_camera": {"position": _r(eye.position), "forward": _r(eye.direction), "up": [0.0, 1.0, 0.0]},
        "chase_anchor": {"position": list(CHASE_ANCHOR)},
        "muzzles": muzzles,
        "pods": pods,
        "rcs": rcs,
        "collision": collision,
        "nav_lights": nav_lights(by_name, eye.position),
        "chunks": [{**c, "joint": _r(joints[c["name"]])} for c in chunks],
    }


# --- build ------------------------------------------------------------------------------------------------------------------
def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the ship into ``ctx.out_dir``.

    Options: ``look`` (``a``, ``b`` or ``c``: the stage 1 choices, ``styles/ea_thunderbolt.py``), ``low_shrink`` (how many
    times smaller the low texture set's maps are; 2 by the class budgets, 1 for the full-size comparison), ``spacing`` (m,
    the surface samples'), ``atlas_px``, ``texel_m``, ``occlusion``.
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    if spacing <= 0.0:
        raise ValueError("spacing must be positive")
    key = str(ctx.option("look", DEFAULT_LOOK))
    if key not in LOOKS:
        raise ValueError(f"look {key!r} is not one of {sorted(LOOKS)}")
    look = LOOKS[key]
    low_shrink = int(ctx.option("low_shrink", LOW_SHRINK))
    atlas_px = int(ctx.option("atlas_px", ATLAS_PX))
    spec, style = DEFAULT_SPEC, look.style

    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    placed, offset = centre(build_parts(spec, style, ctx, spacing, look.plate_tone))
    chunk_sources = build_chunks(placed)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",)

    hull_mesh = Mesh.concatenate(p.part.mesh for p in placed if p.hull)
    aabb_min, aabb_max = hull_mesh.bounds()
    files: list[Path] = write_obj(out_dir / OBJ_NAME, hull_mesh, ASSET_ID, comments)
    chunk_files, chunk_entries = write_chunks(out_dir, ASSET_ID, chunk_sources, comments, with_meshes=True)
    files += chunk_files

    cuts = [ChunkCut(name, tuple(p.part.name for p in placed if p.hull and chunk_of(p.part.name) == name), tuple(float(v) for v in centroid))
            for name, centroid in chunk_offsets(chunk_sources).items()]
    textured_paths, mesh_entry = write_textured_mesh(
        out_dir, ASSET_ID, textured_parts(placed, look, offset), style, atlas_px=atlas_px, texel_m=float(ctx.option("texel_m", TEXEL_M)),
        seed=ctx.seed, occlusion=bool(ctx.option("occlusion", True)), paintable=PAINTABLE, chunks=cuts, grid=False,
        detail_levels=DETAIL_LEVELS, detail_shrink={name: low_shrink for name in DETAIL_LEVELS},
    )
    files += textured_paths

    hp = hardpoints(placed, spec, chunk_entries)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    high_mb = texture_mb([atlas_px], normal_px=atlas_px * NORMAL_SCALE)
    low_mb = texture_mb([atlas_px // low_shrink], normal_px=atlas_px * NORMAL_SCALE // low_shrink)
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=aabb_min,
        aabb_max=aabb_max,
        centroid_offset=offset,
        files={"obj": OBJ_NAME, "mesh": mesh_entry["file"], "hardpoints": HARDPOINTS_NAME},
        extra={
            "dimensions_m": {"length": hp["length_m"], "span": hp["span_m"], "height": hp["height_m"]},
            "chunks": [c["name"] for c in chunk_entries],
            "mesh": mesh_entry,
            "look": look.key,
            "budget": {"class": SHIP_CLASS, "triangles": mesh_entry["triangles"], "texture_mb": round(high_mb, 2),
                       "texture_mb_low": round(low_mb, 2), "low_shrink": low_shrink,
                       "over": over_budget(SHIP_CLASS, mesh_entry["triangles"], high_mb, low_mb)},
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())


__all__ = ["ASSET_ID", "CHUNK_ORDER", "DEFAULT_SPEC", "GENERATOR_VERSION", "REFERENCE_LENGTH_M", "REFERENCE_MAPPING", "REFERENCE_TURN",
           "ThunderboltSpec", "build", "build_parts", "chunk_of", "hardpoints", "zone_of"]
