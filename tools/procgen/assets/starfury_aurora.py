"""``starfury_aurora``: the player's SA-23E-style Starfury (docs/architecture.md section 9.1).

Composition only: this module places parts from ``parts/`` with the ``earthforce`` style and
derives every output from the placed parts, so the textured mesh, the OBJ, the cockpit interior
mesh and ``hardpoints.json`` agree by construction.

Layout (authored Godot frame, metres, before re-centring; -Z is forward, the nose at z = 0,
the X of struts centred on x = y = 0). Silhouette and proportions follow the written reference
in ``docs/design-references.md``:

* wedge fuselage 5.2 m long: arrowhead from above (1.8 m nose -> 3.1 m), wedge from the side
  (1.1 m deep at the nose -> 2.5 m), heater-shield section from the front
* faceted cockpit window at the nose: a raked front pane, roof and side panes, frame bars only
  along the facet edges; the pilot's eye 1 m behind the front pane
* ventral gun pod under the chin, twin barrels at x = +-0.45
* four trussed struts from the fuselage flanks to the pods, 18 deg above/below horizontal,
  leading edge swept 57 deg from the centre line, ladder webs with cut-outs (no hazard stripes: the base hull is plain grey and
  any colour is the wing's livery, M4-T30b Q41)
* four ring-faced pods (5 m x 1.64 m) centred at (+-5.5, +-2.2, 5.0): retro bell in the front
  ring, main bell at the rear
* a claw behind each pod: two outboard prongs and one inboard vane splaying aft, rooted in
  thruster blocks that carry the four RCS cones per pod

Frames: see ``docs/assets-starfury.md``. The sample set is made *exactly* mirror-symmetric
(centre-line parts are symmetrised in x, the pod/strut/claw cross is sampled once and mirrored
four ways), the body group is shifted so the samples' centroid's y is exactly 0, and the z
centroid is subtracted, so the samples' centroid is (0, 0, 0) and the hardpoints frame equals
the rendered frame. Samples buried inside another part (strut roots in the fuselage, strut tips
and claw roots in the pods, the gun pod's top) are dropped.

The break-up chunks (``cabin`` and the four ``arm_<pod>``, ``core/chunks.py``) group the parts; each is placed at its samples'
centroid and its textured mesh is cut from the hull's.
"""

from __future__ import annotations

import dataclasses
import json
import math
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..core.chunks import ChunkCut, ChunkSource, chunk_offsets, write_chunks
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh
from ..core.manifest import build_manifest, write_manifest
from ..core.obj import write_obj
from ..core.textured_mesh import TexturedPart, phase_steps, write_textured_mesh
from ..core.textures import Marking
from ..core.livery import zone_of
from ..core.sampling import SurfaceSamples, sample_mesh
from ..core.seams import MAJOR
from ..parts import Anchor, Part, mass_centroid, total_mass
from ..parts.hull import (
    WedgeFuselageSpec,
    WedgeStation,
    wedge_cockpit_faces,
    wedge_fuselage,
)
from ..parts.cockpit import CockpitSpec, cockpit_interior, cockpit_screens
from ..parts import layouts
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
from ..styles.earthforce import EARTHFORCE_FIGHTER

ASSET_ID = "starfury_aurora"
STYLE = EARTHFORCE_FIGHTER  # painted and bare metal (M7-T17)
# 11: painted and bare metal, metallic and roughness maps (M7-T17); 10: drawn surface layouts, low and high texture sets (M7-T15); 9: the textured mesh only (M4-T31); 8: chunk meshes (M4-T30d);
# 7: wing liveries, Q36 cabin glow (M4-T30b); 6: the textured mesh (M4-T30a)
GENERATOR_VERSION = 11
OBJ_NAME = "starfury_aurora.obj"
MESH_NAME = "starfury_aurora.glb"
# The textured mesh (M4-T30a): a 2 048 px atlas at about a centimetre a texel (the packer grows the texel until the hull fits).
ATLAS_PX = 2048
TEXEL_M = 0.011
LAYOUTS = layouts.starfury()  # the drawn surface by part (M7-T15)
DETAIL_LEVELS = {"low": MAJOR}  # the second texture set, major seams only, for `settings.texture_detail`
PAINTABLE = ("ef_hull", "ef_hull_panel")  # what a wing's livery may paint over (M4-T30b)
STENCIL = (0.035, 0.036, 0.04)  # near-black stencil paint, linear RGB
COCKPIT_NAME = "cockpit_interior.obj"
HARDPOINTS_NAME = "hardpoints.json"

# The surface samples' spacing: they centre the hull, keep the markers clear of it and place the chunks. The cockpit faces are
# sampled finer (2.2 cm).
DEFAULT_SPACING_M = 0.047
COCKPIT_SPACING_FACTOR = 0.47
CHASE_ANCHOR = (
    0.0,
    4.0,
    17.0,
)  # behind and above the centroid; frames the 15 m claw span at 70 deg FOV
JSON_DIGITS = 5
BURIED_MARGIN_M = 0.01  # samples deeper than this inside another part are dropped
FACING_REACH_M = 0.05  # samples facing into another part closer than this are dropped too
POD_NAMES = {"": "ur", "y": "lr", "x": "ul", "xy": "ll"}  # mirror key -> pod name
# Running lights (M3-T27): how far a marker stands off the hull, where the top one sits, and the lamp over the cabin top.
NAV_LIGHT_CLEARANCE_M = 0.12
NAV_NEAR_M = 0.3
NAV_TOP_BEHIND_GLASS_M = 0.6
NAV_LAMP_HEIGHT_M = 2.5
NAV_LAMP_RANGE_M = 6.0
NAV_CABIN_RANGE_M = 2.2
POD_SIDES = (("ur", "right"), ("lr", "right"), ("ul", "left"), ("ll", "left"))

# Break-up chunks, in order: the cabin (fuselage, cockpit faces, gun mount) and one arm
# (pod, strut, claw) per corner, named after the pods (DamageZones' X-fighter cabin and arms).
CHUNK_ORDER = ("cabin",) + tuple(f"arm_{pod}" for pod, _ in POD_SIDES)
ARM_PARTS = ("pod", "strut", "claw")
JOINT_FLANK_X = 1.0  # |x| where a strut leaves the fuselage: the arm's joint (M3-T28)
JOINT_SLAB_M = 0.1  # half thickness of the strut slice the joint is averaged over


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
# The first-person interior and its screens (M3-T29); the hull's own window stays as it was for the view from outside.
STARFURY_COCKPIT = CockpitSpec()
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
    """A placed part with its surface samples (``None`` for meshes that are not sampled)."""

    part: Part
    samples: SurfaceSamples | None
    hull: bool = True  # part of the hull mesh, the mass and the collision shapes

    def translated(self, offset: np.ndarray) -> Placed:
        return Placed(
            self.part.translated(offset),
            None if self.samples is None else self.samples.translated(offset),
            self.hull,
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


# Bare metal (M7-T17): the paint roles a bare face takes instead, and where the pods' bare rear begins (pod frame: the rear clamp
# ring and groove, the rails and the housing round the main bell).
BARE_ROLES = {"hull": "bare", "hull_panel": "bare_trim"}
POD_HOUSING_FROM_Z = 1.2


def bare_metal(part: Part, style: Style, where: Callable[[np.ndarray], np.ndarray] | None = None) -> Part:
    """``part`` with its paint stripped to bare metal on the faces ``where`` picks (by face centroid, in the part's frame; every
    face by default), for a style that has the bare roles. Colours stay; only the finish changes."""
    if not all(role in style.materials for role in BARE_ROLES.values()):
        return part
    mesh = part.mesh
    picked = np.ones(mesh.face_count, dtype=bool) if where is None else np.asarray(where(mesh.face_centroids()), dtype=bool)
    materials = list(mesh.materials)
    face_material = mesh.face_material.copy()
    for paint, bare in BARE_ROLES.items():
        if style.material(paint) not in materials:
            continue
        sel = picked & (face_material == materials.index(style.material(paint)))
        if sel.any():
            if style.material(bare) not in materials:
                materials.append(style.material(bare))
            face_material[sel] = materials.index(style.material(bare))
    return dataclasses.replace(part, mesh=Mesh(mesh.vertices, mesh.faces, face_material, tuple(materials), mesh.face_chart, mesh.face_uv))


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
    ``stream_suffix`` is appended to every RNG stream (the coarse build's), so another build's
    samples never disturb the fine one's."""

    def sample(mesh: Mesh, stream: str, step: float = spacing) -> SurfaceSamples:
        return sample_mesh(mesh, step, ctx.rng("surface", stream, *stream_suffix))

    # Body: centre-line parts, sampled and made exactly x-symmetric.
    fus = wedge_fuselage(spec.fuselage, style).renamed("fuselage", group="body").with_seams(LAYOUTS["fuselage"])
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
        cockpit_interior(STARFURY_COCKPIT, spec.fuselage.eye, style),
        group="body",
    )
    body = [
        Placed(fus, fus_samples),
        Placed(cockpit, cockpit_samples, hull=False),
        Placed(gun, gun_samples),
        Placed(fittings, fit_samples),
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

    pod = bare_metal(fury_pod(spec.pod, style), style, lambda c: c[:, 2] > POD_HOUSING_FROM_Z)
    pod = pod.with_seams(LAYOUTS["pod"]).translated(pod_c).renamed("pod_ur", group="cross")
    strut = fury_strut(spec.strut, style).renamed("strut_ur", group="cross").with_seams(LAYOUTS["strut_ur"])
    lower = fury_strut(spec.lower_strut, style).renamed("strut_lr", group="cross").with_seams(LAYOUTS["strut_lr"])
    claw = bare_metal(fury_claw(spec.claw, style), style).with_seams(LAYOUTS["claw"]).translated(pod_c).renamed("claw_ur", group="cross")
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
        _mirrors(Placed(pod, s_pod), "pod")
        + _mirrors(Placed(strut, s_strut), "strut", lower=Placed(lower, s_lower))
        + _mirrors(Placed(claw, s_claw), "claw")
    )
    return body + cross


# --- centring ---------------------------------------------------------------------------------
def centre(placed: list[Placed]) -> tuple[list[Placed], np.ndarray]:
    """Subtract the samples' centroid's y and z from everything (x is zero by symmetry). Returns
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


def chunk_joints(placed: list[Placed]) -> dict[str, list[float]]:
    """Where each break-up chunk detaches from the body, in the body frame (M3-T28): an arm where its
    strut leaves the fuselage's flank, the cabin on the centre line at the middle of the four."""
    joints: dict[str, np.ndarray] = {}
    for p in placed:
        kind, _, pod = p.part.name.rpartition("_")
        if kind == "strut" and pod in POD_NAMES.values():
            v = p.part.mesh.vertices
            near_flank = np.abs(np.abs(v[:, 0]) - JOINT_FLANK_X) <= JOINT_SLAB_M
            joints[f"arm_{pod}"] = v[near_flank].mean(axis=0)
    arms = np.array([joints[f"arm_{pod}"] for pod in POD_NAMES.values()])
    joints["cabin"] = np.array([0.0, arms[:, 1].mean(), arms[:, 2].mean()])
    return {name: _r(point) for name, point in joints.items()}


# --- markings (M4-T30a) -----------------------------------------------------------------------
def markings_for(placed: list[Placed], style: Style) -> dict[str, tuple[Marking, ...]]:
    """What the texture maps paint on each part beyond its panels: "EA" on the fuselage's flanks and soot round every bell's mouth.
    The wing's colours and the ship's number are the livery's, painted by the shader (M4-T30b), so the maps stay the same for every wing."""
    out: dict[str, tuple[Marking, ...]] = {}
    for p in placed:
        name = p.part.name
        if name.startswith("pod_"):
            out[name] = (
                Marking.soot(name, p.part.anchor("main").position, p.part.anchor("main").direction, 0.75, 0.5, 0.9),
                Marking.soot(name, p.part.anchor("retro").position, p.part.anchor("retro").direction, 0.55, 0.4, 0.6),
            )
        elif name == "fuselage":
            v = p.part.mesh.vertices
            z_mid = 0.55 * float(v[:, 2].max()) + 0.45 * float(v[:, 2].min())
            marks = []
            for side in (1.0, -1.0):
                x = float(np.abs(v[:, 0]).max())
                marks.append(Marking.text(name, "EA", (side * x, 0.25, z_mid), (0.0, 0.0, -side), (0.0, 1.0, 0.0), (side, 0.0, 0.0), 0.3, STENCIL))
            out[name] = tuple(marks)
    return out


# --- the textured mesh's parts and the coarse render mesh (M4-T30b) -------------------------------
COARSE_STREAM = "coarse"
MIN_SEGMENTS = 6


def _textured(placed: list[Placed], style: Style) -> list[TexturedPart]:
    """The hull parts as the textured mesh takes them: mesh, panel phase, markings and livery zone."""
    marks = markings_for(placed, style)
    return [TexturedPart(p.part.mesh, phase_steps(p.part.name, True), marks.get(p.part.name, ()), p.part.name, zone_of(p.part.name), p.part.seams)
            for p in placed if p.hull]


def textured_parts(spec: StarfurySpec, ctx: BuildContext, style: Style = STYLE) -> list[TexturedPart]:
    """The textured mesh's parts of ``spec``, centred as the build centres them (for tests and tools)."""
    placed, _ = centre(build_parts(spec, style, ctx, DEFAULT_SPACING_M, COCKPIT_SPACING_FACTOR * DEFAULT_SPACING_M))
    return _textured(placed, style)


def coarse_spec(spec: Any, factor: float) -> Any:
    """``spec`` with every round part's ``segments`` scaled by ``factor`` (at least ``MIN_SEGMENTS``): the coarse render mesh."""
    if dataclasses.is_dataclass(spec) and not isinstance(spec, type):
        changes = {}
        for f in dataclasses.fields(spec):
            value = getattr(spec, f.name)
            if f.name == "segments" and isinstance(value, int) and not isinstance(value, bool):
                changes[f.name] = max(MIN_SEGMENTS, int(round(value * factor)))
            elif dataclasses.is_dataclass(value) or isinstance(value, tuple):
                scaled = coarse_spec(value, factor)
                if scaled is not value:
                    changes[f.name] = scaled
        return dataclasses.replace(spec, **changes) if changes else spec
    if isinstance(spec, tuple) and any(dataclasses.is_dataclass(x) for x in spec):
        return tuple(coarse_spec(x, factor) for x in spec)
    return spec


def coarse_placed(spec: StarfurySpec, style: Style, ctx: BuildContext, triangles: int, offset: np.ndarray) -> list[Placed]:
    """The parts rebuilt with fewer segments, the scale chosen so the hull has about ``triangles`` (never fewer than the
    flat parts allow), moved by the fine build's centring ``offset`` so both share one frame."""
    def build_at(factor: float) -> list[Placed]:
        placed = build_parts(coarse_spec(spec, factor), style, ctx, 0.25, 0.25, (COARSE_STREAM,))
        return [Placed(p.part.translated(-offset), None, p.hull) for p in placed]

    def count(placed: list[Placed]) -> int:
        return sum(p.part.mesh.face_count for p in placed if p.hull)

    lo, hi = 0.02, 1.0
    best = build_at(hi)
    for _ in range(10):
        mid = 0.5 * (lo + hi)
        placed = build_at(mid)
        if count(placed) > triangles:
            hi = mid
        else:
            lo = mid
            best = placed
    if count(best) > triangles:  # the floor: plates and fittings have no segments to drop
        best = build_at(lo)
    return best


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


def _hull_samples(placed: list[Placed]) -> np.ndarray:
    """Every surface sample of the hull: what the markers must stand clear of."""
    return np.concatenate([p.samples.positions for p in placed if p.hull and p.samples is not None])


def nav_lights(placed: list[Placed], by_name: dict[str, Any], eye: np.ndarray) -> dict[str, Any]:
    """Running lights (M3-T27): red and green on the highest point of the upper pods, where no claw or pod hides them from ahead,
    astern or abeam, white on the cabin top behind the canopy, a lamp standing over that top to light it, and the cabin glow at
    the pilot's eye."""
    hull = _hull_samples(placed)
    pod_lo, pod_hi = by_name["pod_ur"].mesh.bounds()
    on_pod = (hull[:, 0] >= pod_lo[0]) & (hull[:, 0] <= pod_hi[0]) & (hull[:, 1] >= pod_lo[1]) & (hull[:, 2] <= pod_hi[2])
    pod_top = hull[on_pod][np.argmax(hull[on_pod, 1])]
    outer_x, pod_y, pod_z = float(pod_top[0]), float(pod_top[1]) + NAV_LIGHT_CLEARANCE_M, float(pod_top[2])
    fuselage = by_name["fuselage"].mesh
    glass = fuselage.face_material == fuselage.material_index(STYLE.material("canopy_glass").name)
    glass_rear_z = float(fuselage.face_centroids()[glass][:, 2].max())
    top_z = glass_rear_z + NAV_TOP_BEHIND_GLASS_M
    on_top = (np.abs(hull[:, 0]) < NAV_NEAR_M) & (np.abs(hull[:, 2] - top_z) < NAV_NEAR_M)
    top_y = float(hull[on_top, 1].max())
    lamp_z = glass_rear_z + 0.5 * (float(fuselage.bounds()[1][2]) - glass_rear_z)
    return {
        "port": _r((-outer_x, pod_y, pod_z)),
        "starboard": _r((outer_x, pod_y, pod_z)),
        "top": _r((0.0, top_y + NAV_LIGHT_CLEARANCE_M, top_z)),
        "top_lamp": _r((0.0, top_y + NAV_LAMP_HEIGHT_M, lamp_z)),
        "top_lamp_range_m": NAV_LAMP_RANGE_M,
        "cabin": _r(eye),
        "cabin_range_m": NAV_CABIN_RANGE_M,
    }


def _screens_json(eye: np.ndarray) -> dict[str, Any]:
    """The console's screens (M3-T29), in the hardpoints' rounding, so the game builds them where the mesh expects them."""
    out = {}
    for name, screen in cockpit_screens(STARFURY_COCKPIT, eye).items():
        out[name] = {
            key: _r(screen[key]) for key in ("center", "size", "normal", "up")
        } | {"corner": round(float(screen["corner"]), JSON_DIGITS)}
    return out


def hardpoints(
    placed: list[Placed], spec: StarfurySpec, chunks: list[dict[str, Any]]
) -> dict[str, Any]:
    """The hardpoints document (centred Godot frame) from the placed parts; ``chunks`` are
    the ``write_chunks`` entries."""
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
    joints = chunk_joints(placed)
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
        "nav_lights": nav_lights(placed, by_name, eye.position),
        "screens": _screens_json(eye.position),
        "chunks": [{**c, "joint": joints[c["name"]]} for c in chunks],
    }


# --- build ------------------------------------------------------------------------------------
def build_chunks(placed: list[Placed]) -> list[ChunkSource]:
    """One ``ChunkSource`` per ``CHUNK_ORDER`` entry: its parts' surface samples (placement order) and their hull mesh. The cockpit
    faces' mesh is already in the fuselage's, and the cockpit interior is neither sampled nor hull, so neither adds to a chunk."""
    sources = []
    for name in CHUNK_ORDER:
        members = [p for p in placed if chunk_of(p.part.name) == name]
        points = np.concatenate([p.samples.positions for p in members if p.samples is not None])
        mesh = Mesh.concatenate(p.part.mesh for p in members if p.hull)
        sources.append(ChunkSource(name, points, mesh))
    return sources


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the ship into ``ctx.out_dir``.

    Options: ``render_triangles`` (M4-T30b; 0, the default, draws the full hull; otherwise the textured mesh is rebuilt with about
    this many triangles and the fine hull's shape baked into its normal map), ``spacing`` (m, default 0.047, the surface samples'),
    ``cockpit_spacing`` (m, default 0.47 x the spacing: the window segment's frames, chin and lining), ``atlas_px``, ``texel_m``,
    ``occlusion``.
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    cockpit_spacing = float(ctx.option("cockpit_spacing", COCKPIT_SPACING_FACTOR * spacing))
    if min(spacing, cockpit_spacing) <= 0.0:
        raise ValueError("spacing and cockpit_spacing must be positive")
    spec, style = DEFAULT_SPEC, STYLE

    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    placed, offset = centre(build_parts(spec, style, ctx, spacing, cockpit_spacing))
    chunk_sources = build_chunks(placed)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",)

    hull_mesh = Mesh.concatenate(p.part.mesh for p in placed if p.hull)
    aabb_min, aabb_max = hull_mesh.bounds()
    files: list[Path] = write_obj(out_dir / OBJ_NAME, hull_mesh, ASSET_ID, comments)
    interior = next(p.part.mesh for p in placed if p.part.name == "cockpit_interior")
    files += write_obj(out_dir / COCKPIT_NAME, interior, "cockpit_interior", comments)
    chunk_files, chunk_entries = write_chunks(out_dir, ASSET_ID, chunk_sources, comments, with_meshes=True)
    files += chunk_files

    # The textured mesh (M4-T30a): the same parts with a UV atlas and the four maps, the contract M5 builds against. With
    # ``render_triangles`` (M4-T30b) the parts are rebuilt coarser and the normal map carries the fine hull's shape. Each chunk's
    # mesh (M4-T30d) is cut from it where the chunk's OBJ is.
    render_triangles = int(ctx.option("render_triangles", 0))
    textured_source = placed if render_triangles <= 0 else coarse_placed(spec, style, ctx, render_triangles, offset)
    cuts = [
        ChunkCut(name, tuple(p.part.name for p in textured_source if p.hull and chunk_of(p.part.name) == name),
                 tuple(float(v) for v in centroid))
        for name, centroid in chunk_offsets(chunk_sources).items()
    ]
    textured_paths, mesh_entry = write_textured_mesh(
        out_dir,
        ASSET_ID,
        _textured(textured_source, style),
        style,
        atlas_px=int(ctx.option("atlas_px", ATLAS_PX)),
        texel_m=float(ctx.option("texel_m", TEXEL_M)),
        seed=ctx.seed,
        occlusion=bool(ctx.option("occlusion", True)),
        paintable=PAINTABLE,
        fine_mesh=hull_mesh if render_triangles > 0 else None,
        chunks=cuts,
        grid=False,
        detail_levels=DETAIL_LEVELS,
    )
    if render_triangles > 0:
        mesh_entry["render_triangles"] = render_triangles
        mesh_entry["fine_triangles"] = int(hull_mesh.face_count)
    files += textured_paths

    hp = hardpoints(placed, spec, chunk_entries)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=aabb_min,
        aabb_max=aabb_max,
        centroid_offset=offset,
        files={
            "obj": OBJ_NAME,
            "mesh": mesh_entry["file"],
            "cockpit_mesh": COCKPIT_NAME,
            "hardpoints": HARDPOINTS_NAME,
        },
        extra={
            "dimensions_m": {
                "length": hp["length_m"],
                "span": hp["span_m"],
                "height": hp["height_m"],
            },
            "chunks": [c["name"] for c in chunk_entries],
            "mesh": mesh_entry,
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
