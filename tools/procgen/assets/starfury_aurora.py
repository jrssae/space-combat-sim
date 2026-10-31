"""``starfury_aurora``: the player's SA-23E-style Starfury (docs/architecture.md section 9.1).

Composition only: this module places parts from ``parts/`` with the ``earthforce`` style and
derives every output from the placed parts, so the splats (``.ply``), the fallback mesh
(``.obj``), the cockpit interior mesh and ``hardpoints.json`` agree by construction.

Layout (authored Godot frame, metres, before re-centring; -Z is forward, the nose at z = 0,
the X of struts centred on x = y = 0). Silhouette and proportions follow the written reference
in ``docs/design-references.md``:

* wedge fuselage 5.2 m long: arrowhead from above (1.8 m nose -> 3.1 m), wedge from the side
  (1.1 m deep at the nose -> 2.5 m), heater-shield section from the front
* faceted cockpit window at the nose: a raked front pane, roof and side panes, frame bars only
  along the facet edges; the pilot's eye 1 m behind the front pane
* ventral gun pod under the chin, twin barrels at x = +-0.45
* four trussed struts from the fuselage flanks to the pods, 18 deg above/below horizontal,
  leading edge swept 57 deg from the centre line, hazard stripes, ladder webs with cut-outs
* four ring-faced pods (5 m x 1.64 m) centred at (+-5.5, +-2.2, 5.0): retro bell in the front
  ring, main bell at the rear
* a claw behind each pod: two outboard prongs and one inboard vane splaying aft, rooted in
  thruster blocks that carry the four RCS cones per pod

Frames: see ``docs/assets-starfury.md``. The sample set is made *exactly* mirror-symmetric
(centre-line parts are symmetrised in x, the pod/strut/claw cross is sampled once and mirrored
four ways), the body group is shifted so the splat centroid's y is exactly 0, and the z
centroid is subtracted, so the splat centroid is (0, 0, 0): GDGS's import centring is a no-op
and the hardpoints frame equals the rendered frame. Samples buried inside another part (strut
roots in the fuselage, strut tips and claw roots in the pods, the gun pod's top) are dropped.

LOD1 (``starfury_aurora_lod1.ply``, architecture section 16 D35) is the same build resampled at
``LOD1_SPACING_FACTOR`` times every spacing from RNG streams suffixed ``lod1`` (so LOD0 never
changes), balanced and centred the same way; its splats are written chunk by chunk (``cabin``
and the four ``arm_<pod>``), and each chunk is also written as a break-up chunk
(``core/chunks.py``), so the chunks partition LOD1 exactly.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..core import frames
from ..core.chunks import ChunkSource, write_chunks
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh
from ..core.lighting import STUDIO_DEFAULT, StudioRig

# The baked light of the hull. The studio default left the shadow sides (undersides of the struts, the fuselage's flanks) nearly black
# against the black sky, and the play test kept finding "weird shading" there; the ambient is lifted, as the raider's was.
STARFURY_RIG = StudioRig(
    sky=(0.46, 0.47, 0.50),
    ground=(0.24, 0.24, 0.26),
    lights=STUDIO_DEFAULT.lights,
    exposure=1.05,
)
from ..core.manifest import build_manifest, lod_entry, write_manifest
from ..core.obj import write_obj
from ..core.ply import SplatData, write_ply
from ..core.sampling import (
    DEFAULT_OVERLAP,
    DEFAULT_THICKNESS,
    SurfaceSamples,
    sample_mesh,
    to_splats,
)
from ..parts import Anchor, Part, mass_centroid, total_mass
from ..parts.hull import (
    WedgeFuselageSpec,
    WedgeStation,
    wedge_cockpit_faces,
    wedge_cockpit_interior,
    wedge_fuselage,
)
from ..parts.propulsion import pilot_tags
from ..parts.starfury import (
    BladeSpec,
    FittingsSpec,
    FuryClawSpec,
    FuryGunSpec,
    FuryPodSpec,
    FuryStrutSpec,
    KnuckleSpec,
    PlateStation,
    ThrusterBlockSpec,
    fury_claw,
    fury_fittings,
    fury_guns,
    fury_pod,
    fury_strut,
)
from ..styles import Style
from ..styles.earthforce import EARTHFORCE

ASSET_ID = "starfury_aurora"
GENERATOR_VERSION = 4
PLY_NAME = "starfury_aurora.ply"
OBJ_NAME = "starfury_aurora.obj"
COCKPIT_NAME = "cockpit_interior.obj"
HARDPOINTS_NAME = "hardpoints.json"

# The hull after the reference model has about a third more surface than the earlier one; 4.7 cm keeps it inside the
# AC3 budget. The cockpit faces stay at 2.2 cm (the frames' softness was tuned in play tests).
DEFAULT_SPACING_M = 0.047
COCKPIT_SPACING_FACTOR = (
    0.47  # the window segment's frames, chin and lining, seen from 0.6-1 m: 2.2 cm
)
SPLAT_BUDGET = (100_000, 250_000)  # AC3, at the default spacing
CHASE_ANCHOR = (
    0.0,
    4.0,
    17.0,
)  # behind and above the centroid; frames the 15 m claw span at 70 deg FOV
JSON_DIGITS = 5
BURIED_MARGIN_M = 0.01  # samples deeper than this inside another part are dropped
FACING_REACH_M = 0.05  # samples facing into another part closer than this are dropped too
POD_NAMES = {"": "ur", "y": "lr", "x": "ul", "xy": "ll"}  # mirror key -> pod name
POD_SIDES = (("ur", "right"), ("lr", "right"), ("ul", "left"), ("ll", "left"))

# LOD1 (allies and all Starfury debris, architecture section 16 D35): every spacing (the cockpit
# faces' too) times this factor; the splat scales grow with the spacing, so the sheet closes as
# LOD0's does. 2.0 lands at about 25 % of LOD0's splats.
LOD1_PLY_NAME = "starfury_aurora_lod1.ply"
LOD1_SPACING_FACTOR = 2.0
LOD1_STREAM = "lod1"  # suffix of every LOD1 RNG stream: ctx.rng("splats", <part>, "lod1")
LOD1_SHARE = (0.20, 0.30)  # AC6: LOD1 splats / LOD0 splats, at the default spacing and factor
CHUNK_LOD = 1  # the chunks partition this LOD's splats
# Break-up chunks, in LOD1 file order: the cabin (fuselage, cockpit faces, gun mount) and one arm
# (pod, strut, claw) per corner, named after the pods (DamageZones' X-fighter cabin and arms).
CHUNK_ORDER = ("cabin",) + tuple(f"arm_{pod}" for pod, _ in POD_SIDES)
ARM_PARTS = ("pod", "strut", "claw")


# --- the parametric description --------------------------------------------------------------
# Authored frame: the reference model's, metres (its bounding box centred on the origin, the nose at z = -4.93, the pods'
# axes at x = +-5.53, y = +-2.295). Stations and outlines are measured off its silhouettes and sections.
STARFURY_FUSELAGE = WedgeFuselageSpec(
    stations=(
        # The canopy: a hexagonal beak whose tip is a small front pane, flaring back over 1 m to the full section. Every
        # facet of this segment is glazed; the chamfers between them are the frame bars that converge on the tip, below
        # and to the sides of the pilot's line of sight.
        WedgeStation(-4.93, 0.15, 0.15, 0.33, 0.0, 0.12, -0.22),
        WedgeStation(-4.62, 0.40, 0.26, 0.50, 0.0, 0.18, -0.62),
        WedgeStation(-4.30, 0.66, 0.36, 0.63, 0.0, 0.25, -0.98),
        WedgeStation(-3.95, 0.92, 0.45, 0.76, 0.0, 0.32, -1.18),
        # The body between the strut roots: flat top under the deck, shoulders at mid height, a narrow keel; it ends in
        # the dark rear panel. The glazing runs back to -3.5 (behind the deck's lip, the port blocks and the
        # teardrops), so the cockpit's rear bulkhead is behind the pilot.
        WedgeStation(-3.50, 0.98, 0.55, 0.90, -0.04, 0.45, -1.25),
        WedgeStation(-2.00, 1.00, 0.56, 0.95, -0.08, 0.55, -1.30),
        WedgeStation(-0.85, 0.98, 0.50, 0.90, -0.10, 0.50, -1.25),
    ),
    chamfer=0.045,
    window_end=4,
    frame_width=0.06,
    eye=(0.0, 0.70, -3.85),
    glass_facets=("keel", "lower", "upper", "top"),
    mass_kg=16_000.0,
)
# The heavy dark frame of the reference view, from inside: 9 cm bars (about 5 deg), a 45 cm sill.
COCKPIT_BARS = {"bar_width": 0.09, "bar_depth": 0.06, "sill_depth": 0.45}
STARFURY_GUNS = FuryGunSpec()
STARFURY_FITTINGS = FittingsSpec()
STARFURY_POD = FuryPodSpec(
    # Pod frame (pod centre at z = 0.25 of the authored frame). A narrow ring-faced intake widening to a groove, the
    # long body swelling to 0.93 m at the rear groove, then the rear housing tapering to the main bell's face.
    profile=(
        (-2.82, 0.41), (-2.78, 0.47), (-2.72, 0.495), (-1.97, 0.615), (-1.93, 0.6), (-1.88, 0.545),
        (-1.83, 0.545), (-1.78, 0.6), (-1.73, 0.645), (-1.65, 0.655), (-0.5, 0.77), (0.5, 0.85),
        (1.17, 0.928), (1.21, 0.915), (1.26, 0.86), (1.33, 0.81), (1.39, 0.84), (1.45, 0.883),
        (2.1, 0.76), (2.7, 0.633), (2.75, 0.618), (2.8, 0.565),
    ),
    grooves=(-1.855, 1.31),
    clamps=((-2.05, -1.6, 0.13), (1.1, 1.5, 0.11)),
    rails=(1.5, 2.6),
    knuckles=(
        # The dorsal dome (ventral on the lower pods) and the outboard sensor bulb: the same flared column with a cap.
        KnuckleSpec(90.0, -1.0, ((0.5, 0.55), (0.7, 0.45), (0.85, 0.39), (1.0, 0.35), (1.1, 0.32), (1.15, 0.3),
                                 (1.16, 0.28), (1.4, 0.28), (1.44, 0.24)), stretch=1.3, round_from=0.95),
        KnuckleSpec(0.0, -1.0, ((0.5, 0.55), (0.7, 0.45), (0.85, 0.39), (1.0, 0.35), (1.1, 0.33), (1.15, 0.33),
                                (1.16, 0.3), (1.42, 0.3), (1.46, 0.26)), stretch=1.3, round_from=0.95),
    ),
    mass_kg=5_000.0,
)  # fmt: skip
# Hazard stripes on the deck just behind its leading edge, between the hull and the pod.
HAZARD = tuple((2.3 + 0.3 * k, 2.6 + 0.3 * k, "hazard" if k % 2 == 0 else "hazard_dark") for k in range(6))
STARFURY_STRUT = FuryStrutSpec(
    # (x, centre y, thickness, leading edge z, trailing edge z). The deck spans the fuselage's top from the centre line
    # (a notch over the canopy, cheeks either side of it, a tooth in its trailing edge at x = 2-2.8) and climbs out to
    # the pod's flank.
    deck=tuple(PlateStation(*s) for s in (
        (0.0, 1.2, 0.41, -4.02, 0.22), (0.4, 1.17, 0.42, -4.03, 0.21), (0.55, 1.15, 0.44, -4.25, 0.2),
        (0.95, 1.14, 0.42, -4.27, 0.17), (1.1, 1.14, 0.42, -4.15, 0.05), (1.25, 1.15, 0.42, -3.94, 0.03),
        (1.4, 1.16, 0.44, -3.69, 0.03), (1.55, 1.17, 0.46, -3.45, 0.01), (1.7, 1.2, 0.46, -3.21, 0.01),
        (1.85, 1.25, 0.44, -2.99, 0.03),
        (1.97, 1.3, 0.44, -2.88, 0.62), (2.5, 1.52, 0.41, -2.53, 0.9), (2.72, 1.62, 0.4, -2.4, 0.9),
        (2.82, 1.66, 0.4, -2.33, 0.55), (3.25, 1.85, 0.38, -2.03, 0.74), (3.75, 2.07, 0.35, -1.71, 0.98),
        (4.25, 2.27, 0.34, -1.45, 1.2), (4.95, 2.5, 0.32, -1.25, 1.45),
    )),
    # The brace climbs from the fuselage's shoulder and runs under the deck from x = 3, a slot between them.
    brace=tuple(PlateStation(*s) for s in (
        (0.75, 0.05, 0.55, -2.95, -0.6), (1.0, 0.0, 0.6, -2.9, -0.55), (1.5, 0.17, 0.66, -2.75, -0.46),
        (1.75, 0.445, 0.57, -2.6, -0.3), (2.0, 0.645, 0.47, -2.4, -0.17), (2.5, 0.91, 0.44, -2.12, 0.13),
        (3.25, 1.285, 0.43, -1.7, 0.57), (3.75, 1.54, 0.42, -1.42, 0.86), (4.25, 1.68, 0.46, -1.3, 1.05),
        (4.95, 1.72, 0.5, -1.2, 1.3),
    )),
    bands=HAZARD,
    mass_kg=1_500.0,
)  # fmt: skip
# The lower arms are not quite the upper ones mirrored: their deck runs under the keel, and their brace stays close under
# it, rooted in the fuselage's lower flank instead of diving to the shoulder. Authored mirrored up (as the upper right
# arm); the asset mirrors it down.
STARFURY_LOWER_STRUT = FuryStrutSpec(
    deck=tuple(PlateStation(*s) for s in (
        (0.0, 1.22, 0.45, -4.3, -0.05), (0.5, 1.22, 0.45, -4.2, -0.08), (1.0, 1.2, 0.45, -3.4, -0.15),
        (1.3, 1.2, 0.45, -3.23, -0.14), (1.75, 1.285, 0.45, -3.01, -0.06), (1.85, 1.31, 0.45, -2.95, -0.05),
        (1.97, 1.375, 0.45, -2.86, 0.6), (2.5, 1.56, 0.44, -2.56, 0.85), (2.72, 1.64, 0.42, -2.45, 0.85),
        (2.82, 1.68, 0.42, -2.38, 0.5), (3.25, 1.85, 0.42, -2.1, 0.67), (3.75, 2.04, 0.4, -1.79, 0.92),
        (4.25, 2.27, 0.34, -1.48, 1.2), (4.95, 2.5, 0.32, -1.28, 1.45),
    )),
    brace=tuple(PlateStation(*s) for s in (
        (0.6, 0.86, 0.3, -2.8, -0.35), (1.25, 0.86, 0.3, -2.8, -0.35), (1.75, 0.86, 0.28, -2.78, -0.34),
        (2.0, 0.905, 0.31, -2.58, -0.25), (2.5, 1.1, 0.32, -2.32, 0.02), (3.25, 1.4, 0.32, -1.92, 0.39),
        (3.75, 1.6, 0.32, -1.66, 0.64), (4.25, 1.67, 0.46, -1.45, 1.0), (4.95, 1.72, 0.5, -1.3, 1.3),
    )),
    bands=HAZARD,
    mass_kg=1_500.0,
)  # fmt: skip
STARFURY_CLAW = FuryClawSpec(
    blades=(
        # The outboard pincer (pod frame, (x, y) from the pod axis): a plate bent along its length, over the pod's
        # outboard flank, that splits at z = 3 into an upper prong (its top band) and a lower one (its side).
        BladeSpec((
            (1.35, ((0.95, 0.92), (1.25, 0.75), (1.4, 0.45), (1.42, -0.24))),
            (1.65, ((1.0, 1.1), (1.3, 0.9), (1.45, 0.55), (1.47, -0.3))),
            (1.95, ((1.05, 1.11), (1.38, 0.92), (1.53, 0.58), (1.55, -0.12))),
            (2.25, ((1.1, 1.15), (1.45, 0.95), (1.6, 0.6), (1.62, 0.04))),
            (2.55, ((1.14, 1.18), (1.55, 0.95), (1.7, 0.6), (1.7, 0.07))),
            (2.85, ((1.19, 1.22), (1.62, 0.95), (1.77, 0.6), (1.77, 0.1))),
            (3.0, ((1.21, 1.25), (1.64, 0.94), (1.79, 0.6), (1.79, 0.1))),
        )),
        BladeSpec((
            (2.95, ((1.2, 1.24), (1.64, 0.94))),
            (3.15, ((1.23, 1.27), (1.65, 0.93))),
            (3.45, ((1.4, 1.24), (1.73, 0.97))),
            (3.75, ((1.56, 1.21), (1.8, 1.02))),
            (4.05, ((1.72, 1.19), (1.88, 1.06))),
            (4.35, ((1.85, 1.16), (1.95, 1.1))),
            (4.65, ((1.88, 1.14), (1.93, 1.11))),
        ), thickness=0.09),
        BladeSpec((
            (2.95, ((1.79, 0.6), (1.79, 0.1))),
            (3.15, ((1.8, 0.56), (1.8, 0.09))),
            (3.45, ((1.88, 0.6), (1.88, 0.22))),
            (3.75, ((1.97, 0.64), (1.97, 0.36))),
            (4.05, ((2.05, 0.67), (2.05, 0.49))),
            (4.35, ((2.12, 0.7), (2.12, 0.6))),
            (4.65, ((2.12, 0.69), (2.12, 0.63))),
        ), thickness=0.09),
        # The inboard blade, under the strut: shorter, splitting at z = 2.8.
        BladeSpec((
            (1.3, ((-1.0, 0.0), (-0.98, -0.3), (-0.85, -0.55), (-0.7, -0.7))),
            (1.6, ((-1.18, -0.04), (-1.13, -0.35), (-0.98, -0.6), (-0.8, -0.76))),
            (2.0, ((-1.29, -0.1), (-1.24, -0.4), (-1.08, -0.65), (-0.92, -0.79))),
            (2.4, ((-1.41, -0.1), (-1.36, -0.42), (-1.18, -0.7), (-0.98, -0.88))),
            (2.85, ((-1.51, -0.27), (-1.47, -0.5), (-1.33, -0.72), (-1.2, -0.85))),
        )),
        BladeSpec((
            (2.8, ((-1.51, -0.27), (-1.47, -0.5))),
            (3.0, ((-1.56, -0.36), (-1.55, -0.5))),
            (3.2, ((-1.6, -0.44), (-1.59, -0.52))),
            (3.45, ((-1.62, -0.47), (-1.61, -0.52))),
        ), thickness=0.08),
        BladeSpec((
            (2.8, ((-1.33, -0.72), (-1.2, -0.85))),
            (3.0, ((-1.44, -0.73), (-1.32, -0.83))),
            (3.2, ((-1.49, -0.76), (-1.43, -0.81))),
            (3.45, ((-1.5, -0.77), (-1.47, -0.8))),
        ), thickness=0.08),
    ),
    blocks=(
        # Bracket blocks at the rear clamp ring, each with one RCS cone clear of the blades.
        ThrusterBlockSpec((1.15, -0.55, 1.4), (0.3, 0.3, 0.36), ("px",)),
        ThrusterBlockSpec((0.8, 1.0, 1.4), (0.3, 0.3, 0.36), ("py",)),
        ThrusterBlockSpec((-1.2, 0.2, 1.4), (0.3, 0.3, 0.36), ("nx",)),
        ThrusterBlockSpec((-0.55, -0.95, 1.4), (0.3, 0.3, 0.36), ("ny",)),
    ),
    collision_blades=3,
    mass_kg=1_000.0,
)  # fmt: skip


@dataclass(frozen=True)
class StarfurySpec:
    fuselage: WedgeFuselageSpec = STARFURY_FUSELAGE
    gun_mount: FuryGunSpec = STARFURY_GUNS
    fittings: FittingsSpec = STARFURY_FITTINGS
    pod: FuryPodSpec = STARFURY_POD
    pod_center: tuple[float, float, float] = (5.53, 2.295, 0.25)  # upper right; mirrored to the others
    strut: FuryStrutSpec = STARFURY_STRUT
    lower_strut: FuryStrutSpec = STARFURY_LOWER_STRUT
    claw: FuryClawSpec = STARFURY_CLAW


DEFAULT_SPEC = StarfurySpec()


@dataclass
class Placed:
    """A placed part with its surface samples (``None`` for meshes that are not splatted)."""

    part: Part
    samples: SurfaceSamples | None
    hull: bool = True  # part of the fallback mesh, the mass and the collision shapes
    spacing: float = 0.0  # sample spacing of ``samples`` (m)

    def translated(self, offset: np.ndarray) -> Placed:
        return Placed(
            self.part.translated(offset),
            None if self.samples is None else self.samples.translated(offset),
            self.hull,
            self.spacing,
        )


def _mirrors(base: Placed, prefix: str, lower: Placed | None = None) -> list[Placed]:
    """The upper-right placement plus its mirror images ``<prefix>_ur/lr/ul/ll``; samples are
    mirrored with the mesh, so the set is exactly symmetric. With ``lower`` (authored as an
    upper-right arm), the lower corners are mirrored from it instead."""
    out = []
    for key, pod in POD_NAMES.items():
        src = lower if lower is not None and "y" in key else base
        part, samples = src.part, src.samples
        for axis in key:
            part = part.mirrored(axis)
            samples = None if samples is None else samples.mirrored(axis)
        out.append(
            Placed(
                part.renamed(f"{prefix}_{pod}", group=base.part.group),
                samples,
                base.hull,
                base.spacing,
            )
        )
    return out


def _facing_into(samples: SurfaceSamples, contains, reach: float = FACING_REACH_M) -> np.ndarray:
    """Samples whose outward normal runs into a solid (``contains``) within ``reach``: faces
    pressed against another part (a plate lying on the fuselage, a root against a pod)."""
    return contains(samples.positions + reach * samples.normals)


def _unburied(samples: SurfaceSamples, *inside: np.ndarray) -> SurfaceSamples:
    """Drop the samples flagged by any of the ``inside`` masks."""
    buried = np.zeros(len(samples), dtype=bool)
    for mask in inside:
        buried |= mask
    return samples.subset(~buried)


def build_parts(
    spec: StarfurySpec,
    style: Style,
    ctx: BuildContext,
    spacing: float,
    cockpit_spacing: float,
    stream_suffix: tuple[str, ...] = (),
) -> list[Placed]:
    """Place every part in the authored frame and sample it (symmetric by construction). The
    body group is already shifted so its sample centroid's y is zero (the cross is symmetric).
    The faces the pilot sees up close (``wedge_cockpit_faces``) are a separate ``cockpit``
    placement sampled at ``cockpit_spacing``; its mesh stays part of the fuselage's.
    ``stream_suffix`` is appended to every RNG stream (``("lod1",)`` for LOD1), so another LOD's
    samples never disturb LOD0's."""

    def sample(mesh: Mesh, stream: str, step: float = spacing) -> SurfaceSamples:
        return sample_mesh(mesh, step, ctx.rng("splats", stream, *stream_suffix))

    # Body: centre-line parts, sampled and made exactly x-symmetric.
    fus = wedge_fuselage(spec.fuselage, style).renamed("fuselage", group="body")
    near = wedge_cockpit_faces(spec.fuselage, fus.mesh, style)
    fus_samples = sample(fus.mesh.face_subset(~near), "fuselage").symmetrized("x")
    cockpit = Part("cockpit", fus.mesh.face_subset(near), group="body")
    cockpit_samples = sample(cockpit.mesh, "cockpit", cockpit_spacing).symmetrized("x")
    gun = fury_guns(spec.gun_mount, style).renamed("gun_mount", group="body")
    gun_samples = sample(gun.mesh, "gun_mount")
    def in_hull(points: np.ndarray) -> np.ndarray:
        return spec.fuselage.contains(points, BURIED_MARGIN_M)

    gun_samples = _unburied(
        gun_samples, in_hull(gun_samples.positions), _facing_into(gun_samples, in_hull)
    ).symmetrized("x")
    fittings = fury_fittings(spec.fittings, style).renamed("fittings", group="body")
    fit_samples = sample(fittings.mesh, "fittings")
    fit_samples = _unburied(
        fit_samples, in_hull(fit_samples.positions), _facing_into(fit_samples, in_hull)
    ).symmetrized("x")
    interior = Part(
        "cockpit_interior",
        wedge_cockpit_interior(spec.fuselage, style, **COCKPIT_BARS),
        group="body",
    )
    body = [
        Placed(fus, fus_samples, spacing=spacing),
        Placed(cockpit, cockpit_samples, hull=False, spacing=cockpit_spacing),
        Placed(gun, gun_samples, spacing=spacing),
        Placed(fittings, fit_samples, spacing=spacing),
        Placed(interior, None, hull=False),
    ]

    # Cross: the upper-right pod, strut and claw, minus what is buried in the fuselage or the
    # pod, then mirrored four ways. The fuselage is not symmetric in y, so a strut sample is only
    # dropped when it is inside the fuselage *and* its y mirror image.
    def in_fuselage(points: np.ndarray) -> np.ndarray:
        flipped = points * np.array([1.0, -1.0, 1.0])
        return spec.fuselage.contains(points, BURIED_MARGIN_M) & spec.fuselage.contains(
            flipped, BURIED_MARGIN_M
        )

    pod_c = np.asarray(spec.pod_center, dtype=float)

    def in_pod(points: np.ndarray) -> np.ndarray:
        return spec.pod.contains(points - pod_c, BURIED_MARGIN_M)

    pod = fury_pod(spec.pod, style).translated(pod_c).renamed("pod_ur", group="cross")
    strut = fury_strut(spec.strut, style).renamed("strut_ur", group="cross")
    lower = fury_strut(spec.lower_strut, style).renamed("strut_lr", group="cross")
    claw = fury_claw(spec.claw, style).translated(pod_c).renamed("claw_ur", group="cross")
    s_pod = sample(pod.mesh, "pod")
    # The bells' outer walls and the knuckle cones' bases are inside the shell; the bells' inner
    # walls (facing the axis, near it) are what shows through the exits and stay.
    radial = s_pod.positions[:, :2] - pod_c[:2]
    r = np.linalg.norm(radial, axis=1)
    facing_out = np.einsum("ij,ij->i", s_pod.normals[:, :2], radial) > 0.2 * r
    off_axis = r > spec.pod.main.exit_r + spec.pod.main.wall + 0.02
    s_pod = _unburied(s_pod, in_pod(s_pod.positions) & (facing_out | off_axis))
    s_strut = sample(strut.mesh, "strut")
    s_strut = _unburied(
        s_strut, in_fuselage(s_strut.positions), in_pod(s_strut.positions),
        _facing_into(s_strut, in_fuselage), _facing_into(s_strut, in_pod),
    )
    s_lower = sample(lower.mesh, "strut_lower")
    s_lower = _unburied(
        s_lower, in_fuselage(s_lower.positions), in_pod(s_lower.positions),
        _facing_into(s_lower, in_fuselage), _facing_into(s_lower, in_pod),
    )
    s_claw = sample(claw.mesh, "claw")
    s_claw = _unburied(s_claw, in_pod(s_claw.positions), _facing_into(s_claw, in_pod))
    cross = (
        _mirrors(Placed(pod, s_pod, spacing=spacing), "pod")
        + _mirrors(Placed(strut, s_strut, spacing=spacing), "strut", lower=Placed(lower, s_lower, spacing=spacing))
        + _mirrors(Placed(claw, s_claw, spacing=spacing), "claw")
    )
    return body + cross


# --- centring ---------------------------------------------------------------------------------
def centre(placed: list[Placed]) -> tuple[list[Placed], np.ndarray]:
    """Subtract the splat centroid's y and z from everything (x is zero by symmetry). Returns
    the placements and the offset (Godot frame) that was subtracted from the authored positions
    (``manifest.centroid_offset``). The fuselage hangs low between the arms (chin guns, keel), so
    the centroid sits a little below the arms' centre: the cross is symmetric about its own
    centre line, ``thrust_axis_y``, not about y = 0."""
    sampled = [p.samples for p in placed if p.samples is not None]
    total = sum(len(s) for s in sampled)
    y_mean = sum(float(s.positions[:, 1].sum()) for s in sampled) / total
    z_mean = sum(float(s.positions[:, 2].sum()) for s in sampled) / total
    offset = np.array([0.0, y_mean, z_mean])
    return [p.translated(-offset) for p in placed], offset


def chunk_of(part_name: str) -> str:
    """The break-up chunk a part belongs to: a corner's pod, strut and claw are ``arm_<pod>``,
    everything else (fuselage, cockpit faces, gun mount, cockpit interior) is the ``cabin``."""
    kind, _, pod = part_name.rpartition("_")
    if kind in ARM_PARTS and pod in POD_NAMES.values():
        return f"arm_{pod}"
    return "cabin"


# --- colour -----------------------------------------------------------------------------------
def _phase(name: str, style: Style) -> tuple[float, float, float]:
    base = name.split("_")[0]
    h = sum((i + 1) * ord(c) for i, c in enumerate(base))
    return tuple(((h * k) % 97) / 97.0 * style.panel_size_m for k in (7, 11, 13))


def colour_samples(placed: Placed, style: Style, rig: StudioRig) -> np.ndarray:
    s = placed.samples
    albedo = style.shade_panels(
        s.albedo(),
        s.positions,
        s.normals,
        s.material_flag("paneled") > 0.5,
        _phase(placed.part.name, style),
    )
    return rig.shade(s.normals, albedo, s.material_flag("metallic"))


# --- hardpoints -------------------------------------------------------------------------------
def _r(v: Any) -> list[float]:
    return [
        round(float(x), JSON_DIGITS) + 0.0
        for x in np.asarray(v, dtype=float).reshape(-1)
    ]


def _anchor_json(a: Anchor, direction_key: str | None = None) -> dict[str, Any]:
    out: dict[str, Any] = {"position": _r(a.position)}
    if direction_key and a.direction is not None:
        out[direction_key] = _r(a.direction)
    return out


def _axis_label(direction: np.ndarray) -> str:
    axis = int(np.argmax(np.abs(direction)))
    return ("p" if direction[axis] > 0 else "n") + "xyz"[axis]


def hardpoints(
    placed: list[Placed], spec: StarfurySpec, chunks: list[dict[str, Any]]
) -> dict[str, Any]:
    """The hardpoints document (centred Godot frame) from the placed LOD0 parts; ``chunks`` are
    the ``write_chunks`` entries (from LOD1)."""
    by_name = {p.part.name: p.part for p in placed}
    hull_parts = [p.part for p in placed if p.hull]
    hull_mesh = Mesh.concatenate(p.mesh for p in hull_parts)
    lo, hi = hull_mesh.bounds()

    com = mass_centroid(hull_parts)
    # Trimmed onto the thrust axis by design (ballast), see docs: the pods' centre line.
    axis_y = float(np.mean([by_name[f"pod_{n}"].anchor("center").position[1] for n, _ in POD_SIDES]))
    com = np.array([0.0, axis_y, com[2]])
    mass = total_mass(hull_parts)
    inertia = np.zeros(3)
    for part in hull_parts:
        d = part.area_centroid() - com
        inertia += part.mass_kg * np.array(
            [d[1] ** 2 + d[2] ** 2, d[0] ** 2 + d[2] ** 2, d[0] ** 2 + d[1] ** 2]
        )

    pods = []
    rcs = []
    for name, side in POD_SIDES:
        pod = by_name[f"pod_{name}"]
        pods.append(
            {
                "name": name,
                "side": side,
                "center": _r(pod.anchor("center").position),
                "main": {
                    **_anchor_json(pod.anchor("main"), "exhaust"),
                    "radius": spec.pod.main.exit_r,
                },
                "retro": {
                    **_anchor_json(pod.anchor("retro"), "exhaust"),
                    "radius": spec.pod.retro.exit_r,
                },
            }
        )
        claw = by_name[f"claw_{name}"]
        for key in ("rcs_px", "rcs_nx", "rcs_py", "rcs_ny"):
            a = claw.anchor(key)
            rcs.append(
                {
                    "name": f"{name}_{_axis_label(a.direction)}",
                    "pod": name,
                    "position": _r(a.position),
                    "exhaust": _r(a.direction),
                    "tags": pilot_tags(a.position, a.direction, com),
                }
            )

    gun = by_name["gun_mount"]
    muzzles = [
        {"name": n, **_anchor_json(gun.anchor(f"muzzle_{n}"), "direction")}
        for n in ("left", "right")
    ]
    eye = by_name["fuselage"].anchor("eye")
    collision = []
    for part in hull_parts:
        for shape in part.collision:
            collision.append({**shape.to_json(digits=JSON_DIGITS), "name": part.name})

    return {
        "asset_id": ASSET_ID,
        "generator_version": GENERATOR_VERSION,
        "frame": "godot",
        "units": "m",
        "length_m": round(float(hi[2] - lo[2]), 3),
        "span_m": round(float(hi[0] - lo[0]), 3),
        "height_m": round(float(hi[1] - lo[1]), 3),
        "mass_kg": round(mass, 1),
        "inertia_estimate_kg_m2": _r(inertia),
        "center_of_mass": _r(com),
        "cockpit_camera": {
            "position": _r(eye.position),
            "forward": _r(eye.direction),
            "up": [0.0, 1.0, 0.0],
        },
        "chase_anchor": {"position": list(CHASE_ANCHOR)},
        "muzzles": muzzles,
        "pods": pods,
        "rcs": rcs,
        "collision": collision,
        "chunks": chunks,
    }


# --- build ------------------------------------------------------------------------------------
def part_splats(
    placed: list[Placed], style: Style, rig: StudioRig, overlap: float, thickness: float
) -> SplatData:
    """The splats of every sampled placement, in order (body frame, Godot axes)."""
    return SplatData.concatenate(
        [
            to_splats(
                p.samples, colour_samples(p, style, rig), p.spacing, overlap, thickness
            )
            for p in placed
            if p.samples is not None
        ]
    )


def _to_3dgs(splats: SplatData) -> SplatData:
    """Rz(180 deg) of the Godot frame: what the PLY stores, so the splat node stays at identity."""
    return SplatData(
        xyz=frames.godot_to_3dgs_positions(splats.xyz),
        rgb=splats.rgb,
        alpha=splats.alpha,
        scale=splats.scale,
        rot=frames.godot_to_3dgs_quats(splats.rot),
        normals=frames.flip_xy(splats.normals),
    )


def build_chunks(
    placed: list[Placed], style: Style, rig: StudioRig, overlap: float, thickness: float
) -> list[ChunkSource]:
    """One ``ChunkSource`` per ``CHUNK_ORDER`` entry: its parts' splats (placement order) and
    their fallback mesh. The cockpit faces' mesh is already in the fuselage's, and the cockpit
    interior is neither splatted nor hull, so neither adds to a chunk mesh."""
    sources = []
    for name in CHUNK_ORDER:
        members = [p for p in placed if chunk_of(p.part.name) == name]
        mesh = Mesh.concatenate(p.part.mesh for p in members if p.hull)
        sources.append(
            ChunkSource(name, part_splats(members, style, rig, overlap, thickness), mesh)
        )
    return sources


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the ship into ``ctx.out_dir``.

    Options: ``spacing`` (m, default 0.04; the CLI's ``--spacing``), ``cockpit_spacing`` (m,
    default 0.55 x the spacing: the window segment's frames, chin and lining), ``overlap``
    (sigma / spacing, default 1.0), ``thickness`` (normal sigma / spacing, default 0.08),
    ``lod1_factor`` (LOD1 spacing / LOD0 spacing, default 2.0).
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    cockpit_spacing = float(
        ctx.option("cockpit_spacing", COCKPIT_SPACING_FACTOR * spacing)
    )
    overlap = float(ctx.option("overlap", DEFAULT_OVERLAP))
    thickness = float(ctx.option("thickness", DEFAULT_THICKNESS))
    lod1_factor = float(ctx.option("lod1_factor", LOD1_SPACING_FACTOR))
    if min(spacing, cockpit_spacing, overlap, thickness, lod1_factor) <= 0.0:
        raise ValueError(
            "spacing, cockpit_spacing, overlap, thickness and lod1_factor must be positive"
        )
    spec, style, rig = DEFAULT_SPEC, EARTHFORCE, STARFURY_RIG

    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    # LOD0: the full-detail hull, part by part (manifest ``counts`` order).
    placed, offset = centre(build_parts(spec, style, ctx, spacing, cockpit_spacing))
    sampled = [p for p in placed if p.samples is not None]
    authored = part_splats(placed, style, rig, overlap, thickness)

    # Splats are already centred; the manifest AABB is theirs, Godot frame.
    xyz32 = authored.xyz.astype(np.float32)
    aabb_min, aabb_max = xyz32.min(axis=0), xyz32.max(axis=0)
    comments = (
        f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",
        "frame: 3dgs (Rz180 of godot)",
    )
    files: list[Path] = [write_ply(out_dir / PLY_NAME, _to_3dgs(authored), comments)]

    hull_mesh = Mesh.concatenate(p.part.mesh for p in placed if p.hull)
    files += write_obj(out_dir / OBJ_NAME, hull_mesh, ASSET_ID, comments[:1])
    interior = next(p.part.mesh for p in placed if p.part.name == "cockpit_interior")
    files += write_obj(
        out_dir / COCKPIT_NAME, interior, "cockpit_interior", comments[:1]
    )

    # LOD1: the same parts resampled coarser from their own streams, balanced and centred
    # like LOD0 (its splat centroid is the origin too), written chunk by chunk.
    lod1_spacing = lod1_factor * spacing
    lod1_placed, _ = centre(
        build_parts(
            spec,
            style,
            ctx,
            lod1_spacing,
            lod1_factor * cockpit_spacing,
            (LOD1_STREAM,),
        )
    )
    chunk_sources = build_chunks(lod1_placed, style, rig, overlap, thickness)
    lod1 = SplatData.concatenate([c.splats for c in chunk_sources])
    lod1_comments = comments + (f"lod {CHUNK_LOD}",)
    files.append(write_ply(out_dir / LOD1_PLY_NAME, _to_3dgs(lod1), lod1_comments))
    chunk_files, chunk_entries = write_chunks(
        out_dir, ASSET_ID, chunk_sources, lod1_comments
    )
    files += chunk_files

    hp = hardpoints(placed, spec, chunk_entries)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    total = len(authored)
    warnings: list[str] = []
    if abs(spacing - DEFAULT_SPACING_M) < 1e-12:
        if not SPLAT_BUDGET[0] <= total <= SPLAT_BUDGET[1]:
            warnings.append(
                f"{total} splats is outside the AC3 budget {SPLAT_BUDGET} at the default spacing"
            )
        share = len(lod1) / total
        if (
            abs(lod1_factor - LOD1_SPACING_FACTOR) < 1e-12
            and not LOD1_SHARE[0] <= share <= LOD1_SHARE[1]
        ):
            warnings.append(
                f"LOD1 has {share:.1%} of LOD0's splats, outside the AC6 share {LOD1_SHARE}"
            )
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        lods=[
            lod_entry(0, PLY_NAME, total, spacing),
            lod_entry(CHUNK_LOD, LOD1_PLY_NAME, len(lod1), lod1_spacing),
        ],
        aabb_min=aabb_min,
        aabb_max=aabb_max,
        centroid_offset=offset,
        files={
            "fallback_mesh": OBJ_NAME,
            "cockpit_mesh": COCKPIT_NAME,
            "hardpoints": HARDPOINTS_NAME,
        },
        extra={
            "counts": {p.part.name: len(p.samples) for p in sampled},
            "sampling": {
                "spacing_m": spacing,
                "cockpit_spacing_m": cockpit_spacing,
                "overlap": overlap,
                "thickness": thickness,
            },
            "dimensions_m": {
                "length": hp["length_m"],
                "span": hp["span_m"],
                "height": hp["height_m"],
            },
            "chunks": [c["name"] for c in chunk_entries],
            "chunk_lod": CHUNK_LOD,
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), tuple(warnings))
