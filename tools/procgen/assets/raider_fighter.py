"""``raider_fighter``: the raiders' Delta-V flying wing (docs/architecture.md section 15.11).

Composition only, like ``starfury_aurora``: parts from ``parts/raider.py`` placed with the ``raider`` style, and every output
(the textured mesh, the OBJ, hardpoints, chunks) derived from the placed parts so they agree by construction.

The shape is the reference model's (M7-T16, ``references/Raider_Fighter_16m.stl`` at 16 m across; never committed), held to
the 90 % rule (``docs/assets-raider.md``, "Fidelity"). Authored Godot frame, metres, before re-centring: -Z is forward, the
nose at z = 0, the wing's mid-plane at y = 0, the trailing edge at z = 7.37:

* a flying wing 16 m across, its leading edge one straight line from the nose to the tip (47.8 degrees from the centre line),
  a notch cut into it 2.7 to 3.4 m out where two short guns sit, a straight trailing edge chamfered in at the root; the section
  thickens aft to 0.33 m and closes at the trailing edge;
* a narrow centre ridge along the whole length: the dark canopy on its top over the nose, the keel below, the hump behind;
* two engine housings beside the ridge, flat above and below with rounded outer sides, a grilled intake in front and a
  nozzle on the back of each.

Every part belongs to a *group* (``wing_l``, ``wing_r``, ``hump``, ``nacelle_l``, ``nacelle_r``: the ridge is the hump, the
housings the nacelles); each group is written as a break-up chunk (``core/chunks.py``), with a textured mesh cut from the
hull's (M4-T30d).

The textured mesh (M4-T30d, the contract of ``core/textured_mesh.py``): the same hull parts on one atlas, the ``raider`` style's
wear (chipped edges down to bare metal, streaks, grime), soot behind the nozzles and the two yellow-white engine glows of the
reference in the main nozzles' throats. No insignia. ``render_triangles`` rebuilds the round parts coarser with the fine hull
baked into the normal map, as the Starfury's option does. The sample set is exactly mirror-symmetric in x (the right-hand
groups are sampled once and mirrored, the centre-line ridge is symmetrised); the samples' centroid is moved to the origin, so
the hardpoints frame equals the rendered frame. Samples buried inside another part are dropped.
"""

from __future__ import annotations

import dataclasses
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..core.chunks import ChunkCut, ChunkSource, chunk_offsets, write_chunks
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Material, Mesh, box
from ..core.manifest import build_manifest, write_manifest
from ..core.obj import write_obj
from ..core.textured_mesh import TexturedPart, phase_steps, write_textured_mesh
from ..core.textures import Marking
from ..core.sampling import SurfaceSamples, sample_mesh
from ..core.seams import MAJOR, SeamLayout
from ..parts import Part, layouts, mass_centroid, total_mass
from ..parts.hull import tapered_wedge
from ..parts.propulsion import pilot_tags
from ..parts.raider import LobeStation, RaiderLobe, RaiderRidge, RaiderWing, RidgeStation, raider_lobe, raider_ridge, raider_wing
from ..parts.weapons import BarrelSpec, gun_barrel
from ..parts.wing import vent_grille
from ..styles import Style
from ..styles.raider import RAIDER, TEXTURED_ALBEDO

ASSET_ID = "raider_fighter"
# 6: the shape rebuilt to the reference model at 90 %, painted metal not plastic (M7-T16); 5: drawn surface layouts, low and high texture sets (M7-T15); 4: the textured mesh only (M4-T31); 3: the textured mesh and chunk
# meshes (M4-T30d)
GENERATOR_VERSION = 6
OBJ_NAME = "raider_fighter.obj"
HARDPOINTS_NAME = "hardpoints.json"
MESH_NAME = "raider_fighter.glb"
# The textured mesh (M4-T30d): about 190 m² of hull at a centimetre a texel in a 2 048 px atlas, the normal map at the atlas's size.
ATLAS_PX = 2048
DETAIL_LEVELS = {"low": MAJOR}  # the second texture set, major seams only, for `settings.texture_detail` (M7-T15)
TEXEL_M = 0.01
NORMAL_SCALE = 1
COARSE_STREAM = "coarse"

# The reference model (M7-T16): ``references/Raider_Fighter_16m.stl`` at 16 m across, its file axes onto the ship's (right, up, aft)
# and the shift from its box centre onto the authored frame's wing plane; the 90 % rule scores the hull against it.
REFERENCE_DIMENSIONS_M = {"length": 7.374, "span": 16.0, "height": 1.525}
REFERENCE_MAPPING = ("-x", "+z", "+y")
REFERENCE_MODEL_OFFSET = (0.0, 0.079, 0.0)
DEFAULT_SPACING_M = 0.09  # the surface samples' spacing: the centroid, the buried faces, the chunks' offsets
CHASE_ANCHOR = (0.0, 3.5, 14.0)  # authored frame: behind and above, frames the 16 m span at 70 degrees
EYE = (0.0, 0.40, 2.1)  # the pilot's eye under the canopy (authored frame); looks down -Z
JSON_DIGITS = 5
# Running lights (M3-T27): how far a marker stands off the hull, where the top one sits, and the lamp over the hump.
NAV_LIGHT_CLEARANCE_M = 0.12
NAV_TOP_BEHIND_CANOPY_M = 0.5
NAV_LAMP_HEIGHT_M = 2.2
NAV_LAMP_RANGE_M = 5.5
NAV_CABIN_RANGE_M = 1.4
BURIED_MARGIN_M = 0.01
CHUNK_ORDER = ("wing_l", "wing_r", "hump", "nacelle_l", "nacelle_r")
MUZZLE_ORDER = ("root_l", "root_r", "nacelle_l", "nacelle_r")  # left and right take turns in ALTERNATING fire
# The muzzles' names are the hardpoints contract's; both guns of a side now sit in its wing's notch (M7-T16).
MUZZLE_GUNS = {"root": "inner_gun", "nacelle": "outer_gun"}


@dataclass(frozen=True)
class RaiderSpec:
    """The shape, measured off the reference model at 16 m across (sections in ``docs/assets-raider.md``)."""

    wing: RaiderWing = RaiderWing()
    ridge: RaiderRidge = RaiderRidge(
        stations=(
            RidgeStation(0.00, 0.03, 0.03, -0.02),
            RidgeStation(0.30, 0.12, 0.17, -0.09),
            RidgeStation(0.70, 0.18, 0.32, -0.13),
            RidgeStation(1.10, 0.22, 0.43, -0.14),
            RidgeStation(1.50, 0.25, 0.52, -0.15),
            RidgeStation(1.70, 0.26, 0.56, -0.18),
            RidgeStation(1.90, 0.27, 0.59, -0.29),
            RidgeStation(2.30, 0.29, 0.64, -0.43),
            RidgeStation(2.70, 0.31, 0.68, -0.52),
            RidgeStation(3.10, 0.33, 0.74, -0.58),
            RidgeStation(3.50, 0.38, 0.82, -0.64),
            RidgeStation(3.90, 0.45, 0.83, -0.68),
            RidgeStation(4.30, 0.45, 0.84, -0.67),
            RidgeStation(4.90, 0.45, 0.78, -0.62),
            RidgeStation(5.50, 0.45, 0.71, -0.58),
            RidgeStation(6.10, 0.45, 0.63, -0.52),
            RidgeStation(6.20, 0.45, 0.20, -0.34),
            RidgeStation(6.80, 0.45, 0.18, -0.28),
            RidgeStation(7.00, 0.40, 0.12, -0.15),
        ),
    )
    lobe: RaiderLobe = RaiderLobe(
        stations=(
            LobeStation(3.70, 2.05, 0.61, -0.54),
            LobeStation(3.95, 2.33, 0.68, -0.61),
            LobeStation(4.30, 2.42, 0.69, -0.61),
            LobeStation(5.00, 2.44, 0.63, -0.55),
            LobeStation(5.80, 2.42, 0.55, -0.48),
            LobeStation(6.05, 2.37, 0.52, -0.46),
            LobeStation(6.15, 2.30, 0.43, -0.38),
            LobeStation(6.50, 2.20, 0.34, -0.30),
            LobeStation(6.80, 2.10, 0.22, -0.20),
        ),
    )
    inner_barrel: BarrelSpec = BarrelSpec(
        length=0.42, radius=0.05, base_radius=0.06, base_length=0.30, bore_radius=0.025, bore_depth=0.04, segments=14, mass_kg=300.0
    )
    outer_barrel: BarrelSpec = BarrelSpec(
        length=0.42, radius=0.085, base_radius=0.10, base_length=0.12, bore_radius=0.04, bore_depth=0.04, segments=14, mass_kg=300.0
    )
    inner_gun_x: float = 2.84
    outer_gun_x: float = 3.16
    gun_muzzle_z: float = 2.70
    canopy_z: tuple[float, float] = (1.15, 2.95)
    canopy_widths: tuple[float, float] = (0.20, 0.34)

    @property
    def nacelle_y(self) -> float:
        """The thrust line: the centre of mass is trimmed onto it."""
        return 0.0


DEFAULT_SPEC = RaiderSpec()


@dataclass
class Placed:
    """A placed part with its surface samples (``None`` for meshes that are not sampled)."""

    part: Part
    samples: SurfaceSamples | None
    hull: bool = True

    def translated(self, offset: np.ndarray) -> Placed:
        return Placed(
            self.part.translated(offset),
            None if self.samples is None else self.samples.translated(offset),
            self.hull,
        )

    def mirrored(self, name: str, group: str) -> Placed:
        return Placed(
            self.part.mirrored("x").renamed(name, group=group),
            None if self.samples is None else self.samples.mirrored("x"),
            self.hull,
        )


# --- burial tests (authored frame) -------------------------------------------------------------------
def _in_lobes(spec: RaiderSpec, points: np.ndarray, margin: float) -> np.ndarray:
    """Inside either engine housing (the grille and the nozzle are not part of the test)."""
    p = np.array(points, dtype=float).reshape(-1, 3)
    p[:, 0] = np.abs(p[:, 0])
    return spec.lobe.contains(p, margin)


def _unburied(samples: SurfaceSamples, *inside: np.ndarray) -> SurfaceSamples:
    buried = np.zeros(len(samples), dtype=bool)
    for mask in inside:
        buried |= mask
    return samples.subset(~buried)


def _plate(width: float, length: float, height: float, role: str, style: Style) -> Mesh:
    """A thin raised plate (accent band or recessed-looking panel), base on y = 0."""
    return box((width, height, length), style.material(role), center=(0.0, 0.5 * height, 0.0))


def canopy(spec: RaiderSpec, style: Style) -> Mesh:
    """The dark opaque canopy lying along the ridge's top over the nose, following its slope."""
    z0, z1 = spec.canopy_z
    (_, top0, _), (_, top1, _) = spec.ridge.at(z0), spec.ridge.at(z1)
    slope = float(top1 - top0) / (z1 - z0)
    thickness = 0.10
    w0, w1 = spec.canopy_widths
    wedge = tapered_wedge(z1 - z0, (w0, thickness), (w1, thickness), style.material("canopy_glass"), slope)
    return wedge.translated((0.0, 0.5 * float(top0 + top1) - 0.25 * thickness, 0.5 * (z0 + z1)))


def build_parts(
    spec: RaiderSpec, style: Style, ctx: BuildContext, spacing: float, stream_suffix: tuple[str, ...] = ()
) -> list[Placed]:
    """Every part in the authored frame, sampled, mirrored to the left side where it has one. ``stream_suffix``
    keeps another build's random draws (the coarse one) apart from the fine one's."""

    def sample(mesh: Mesh, stream: str) -> SurfaceSamples:
        return sample_mesh(mesh, spacing, ctx.rng("surface", stream, *stream_suffix))

    wing_spec, ridge_spec = spec.wing, spec.ridge

    def in_ridge(p: np.ndarray) -> np.ndarray:
        return ridge_spec.contains(p, BURIED_MARGIN_M)

    def in_wing(p: np.ndarray) -> np.ndarray:
        return wing_spec.contains(p, BURIED_MARGIN_M)

    def in_lobes(p: np.ndarray) -> np.ndarray:
        return _in_lobes(spec, p, BURIED_MARGIN_M)

    placed: list[Placed] = []
    surface = surface_layouts(spec)

    # --- right wing group: slab, vents, accent band, the notch's two guns ---------------------------------
    wing = raider_wing(wing_spec, style).renamed("wing_r", group="wing_r").with_seams(surface["wing_r"])
    s_wing = sample(wing.mesh, "wing")
    s_wing = _unburied(s_wing, in_ridge(s_wing.positions), in_lobes(s_wing.positions))
    right: list[Placed] = [Placed(wing, s_wing)]

    def on_wing(x: float, z: float, mesh: Mesh, name: str, stream: str) -> Placed:
        """Detail sitting on the top skin at its footprint's lowest point, so no edge floats where the wing thins forward."""
        lo, hi = mesh.bounds()
        corners_x, corners_z = np.meshgrid([x + lo[0], x + hi[0]], [z + lo[2], z + hi[2]])
        top = 0.5 * float(wing_spec.thickness(corners_x.ravel(), corners_z.ravel()).min())
        part = Part(name, mesh.translated((x, top - 0.004, z)), group="wing_r", mass_kg=0.0)
        return Placed(part, sample(part.mesh, stream))

    # Detail on the top skin, every corner well inside the planform (the old build's plates overhung the leading edge).
    right.append(on_wing(3.75, 5.7, vent_grille(1.0, 1.4, 7, style, slat_height=0.025), "wing_vent_a", "wing_vent_a"))
    right.append(on_wing(6.4, 6.75, vent_grille(0.8, 0.7, 4, style, slat_height=0.025), "wing_vent_b", "wing_vent_b"))
    right.append(on_wing(7.25, 7.12, _plate(0.30, 0.35, 0.012, "stripe", style), "wing_band", "wing_band"))
    for k, (x, z, w, d) in enumerate([(4.95, 5.4, 1.0, 0.7), (5.6, 6.3, 0.9, 0.6), (3.05, 3.65, 0.6, 0.5)]):
        right.append(on_wing(x, z, _plate(w, d, 0.014, "hull_panel", style), f"wing_plate_{k}", f"wing_plate_{k}"))
    for name, x, barrel in (("inner_gun_r", spec.inner_gun_x, spec.inner_barrel), ("outer_gun_r", spec.outer_gun_x, spec.outer_barrel)):
        gun = gun_barrel(barrel, style).translated((x, 0.0, spec.gun_muzzle_z + barrel.length)).renamed(name, group="wing_r")
        right.append(Placed(gun, sample(gun.mesh, name[:-2])))
    placed += right
    for p in right:
        placed.append(p.mirrored(p.part.name[:-2] + "_l" if p.part.name.endswith("_r") else p.part.name + "_l", "wing_l"))

    # --- hump group: the ridge and its canopy (centre line, symmetrised) -------------------------------
    body = raider_ridge(ridge_spec, style).with_seams(surface["hump"])
    s_body = sample(body.mesh, "hump")
    s_body = _unburied(s_body, in_wing(s_body.positions), in_lobes(s_body.positions)).symmetrized("x")
    placed.append(Placed(body, s_body))
    cover = Part("canopy", canopy(spec, style), group="hump")
    placed.append(Placed(cover, sample(cover.mesh, "canopy").symmetrized("x")))

    # --- right nacelle group: the engine housing, its grille and nozzle ------------------------------------
    lobe = raider_lobe(spec.lobe, style).renamed("nacelle_r", group="nacelle_r").with_seams(surface["nacelle_r"])
    s_lobe = sample(lobe.mesh, "nacelle")
    s_lobe = _unburied(s_lobe, in_wing(s_lobe.positions), in_ridge(s_lobe.positions))
    n_right = Placed(lobe, s_lobe)
    placed.append(n_right)
    placed.append(n_right.mirrored("nacelle_l", "nacelle_l"))
    return placed


def surface_layouts(spec: RaiderSpec) -> dict[str, SeamLayout]:
    """The drawn surface by part (M7-T15), fitted to the spec's wing, ridge and housings (M7-T16)."""
    wing, lobe = spec.wing, spec.lobe
    return layouts.raider(
        le_ratio=wing.le_ratio, half_span=wing.half_span, trailing_z=wing.trailing_z, notch=(wing.notch_x, wing.notch_z),
        body_x=max(s.x_out for s in lobe.stations), lobe_z=(lobe.stations[0].z, lobe.stations[-1].z), lobe_x=(lobe.x_in, lobe.axis_x),
        canopy_z=spec.canopy_z,
    )


# --- centring ------------------------------------------------------------------------------------------
def centre(placed: list[Placed]) -> tuple[list[Placed], np.ndarray]:
    """Moves the samples' centroid to the origin. x is zero by symmetry; the offset (Godot frame) is the authored
    position of the new origin (``manifest.centroid_offset``)."""
    sampled = [p.samples for p in placed if p.samples is not None]
    total = sum(len(s) for s in sampled)
    mean = sum(s.positions.sum(axis=0) for s in sampled) / total
    offset = np.array([0.0, float(mean[1]), float(mean[2])])
    return [p.translated(-offset) for p in placed], offset


# --- hardpoints ------------------------------------------------------------------------------------------
def _r(v: Any) -> list[float]:
    return [round(float(x), JSON_DIGITS) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


def nav_lights(by_name: dict[str, Part], spec: RaiderSpec, offset: np.ndarray) -> dict[str, Any]:
    """Running lights (M3-T27): red and green past the wingtips, white on top of the hump behind the canopy, a lamp standing
    over the hump to light it, and the cabin glow on the canopy panel."""
    wing = spec.wing
    tip_x = wing.half_span + NAV_LIGHT_CLEARANCE_M
    tip_y = 0.0 - float(offset[1])
    tip_z = 0.5 * (wing.tip_leading_z + wing.tip_trailing_z) - float(offset[2])
    hump_lo, hump_hi = by_name["hump"].mesh.bounds()
    canopy_lo, canopy_hi = by_name["canopy"].mesh.bounds()
    top_z = float(canopy_hi[2]) + NAV_TOP_BEHIND_CANOPY_M
    canopy_centre = 0.5 * (canopy_lo + canopy_hi)
    return {
        "port": _r((-tip_x, tip_y, tip_z)),
        "starboard": _r((tip_x, tip_y, tip_z)),
        "top": _r((0.0, float(hump_hi[1]) + NAV_LIGHT_CLEARANCE_M, top_z)),
        "top_lamp": _r((0.0, float(hump_hi[1]) + NAV_LAMP_HEIGHT_M, 0.5 * (top_z + float(hump_hi[2])))),
        "top_lamp_range_m": NAV_LAMP_RANGE_M,
        "cabin": _r((0.0, canopy_centre[1], canopy_centre[2])),
        "cabin_range_m": NAV_CABIN_RANGE_M,
    }


def hardpoints(placed: list[Placed], spec: RaiderSpec, chunks: list[dict[str, Any]], offset: np.ndarray) -> dict[str, Any]:
    """The hardpoints document (centred Godot frame) from the placed (already centred) parts."""
    by_name = {p.part.name: p.part for p in placed}
    hull_parts = [p.part for p in placed if p.hull]
    hull_mesh = Mesh.concatenate(p.mesh for p in hull_parts)
    lo, hi = hull_mesh.bounds()

    thrust_y = spec.nacelle_y - float(offset[1])
    com_z = float(mass_centroid(hull_parts)[2])
    com = np.array([0.0, thrust_y, com_z])  # trimmed onto the nacelle axis: pod thrust makes no pitch torque
    mass = total_mass(hull_parts)
    inertia = np.zeros(3)
    for part in hull_parts:
        d = part.area_centroid() - com
        inertia += part.mass_kg * np.array([d[1] ** 2 + d[2] ** 2, d[0] ** 2 + d[2] ** 2, d[0] ** 2 + d[1] ** 2])

    pods = []
    for name, side in (("l", "left"), ("r", "right")):
        drum = by_name[f"nacelle_{name}"]
        main, retro = drum.anchor("main"), drum.anchor("retro")
        pods.append(
            {
                "name": name,
                "side": side,
                "center": _r(drum.anchor("axis_centre").position),
                "main": {"position": _r(main.position), "exhaust": _r(main.direction), "radius": spec.lobe.nozzle_exit_r},
                "retro": {"position": _r(retro.position), "exhaust": _r(retro.direction), "radius": spec.lobe.retro_radius},
            }
        )

    muzzles = []
    for key in MUZZLE_ORDER:
        kind, side = key.split("_")
        gun = by_name[f"{MUZZLE_GUNS[kind]}_{side}"]
        a = gun.anchor("muzzle")
        muzzles.append({"name": key, "position": _r(a.position), "direction": _r(a.direction)})

    rcs = []
    wing = spec.wing
    ports = []  # cosmetic RCS ports: wing tips up/down, the leading edge outboard of the notch, sideways
    for sx, tag in ((1.0, "r"), (-1.0, "l")):
        z_tip = 0.5 * (wing.tip_leading_z + wing.tip_trailing_z) - float(offset[2])
        for sy, ey in (("u", 1.0), ("d", -1.0)):
            ports.append((f"{tag}_tip_{sy}", np.array([sx * (wing.half_span - 0.1), 0.0 - float(offset[1]), z_tip]), np.array([0.0, ey, 0.0])))
        ports.append((f"{tag}_edge_x", np.array([sx * 4.0, 0.0 - float(offset[1]), float(wing.leading_z(4.0)) + 0.4 - float(offset[2])]), np.array([sx, 0.0, 0.0])))
    for name, position, exhaust in ports:
        rcs.append({"name": name, "pod": name.split("_")[0], "position": _r(position), "exhaust": _r(exhaust), "tags": pilot_tags(position, exhaust, com)})

    collision = []
    for part in hull_parts:
        for shape in part.collision:
            collision.append({**shape.to_json(digits=JSON_DIGITS), "name": f"{part.name}_{shape.name}" if shape.name else part.name})

    eye = np.array(EYE) - offset
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
        "cockpit_camera": {"position": _r(eye), "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0]},
        "chase_anchor": {"position": _r(np.array(CHASE_ANCHOR) - offset)},
        "muzzles": muzzles,
        "pods": pods,
        "rcs": rcs,
        "collision": collision,
        "nav_lights": nav_lights(by_name, spec, offset),
        "chunks": chunks,
    }


# --- the textured mesh (M4-T30d) --------------------------------------------------------------------------
INTAKE = Material("rd_intake", (0.012, 0.011, 0.01), metallic=0.6, roughness=0.6)  # the nose intakes: dark, never lit


def _cold_intakes(mesh: Mesh, main_z: float) -> Mesh:
    """Only the main nozzles glow (the reference's two engine glows): the nose intake shares the throats' material, so it gets a dark
    one of its own."""
    throat = RAIDER.material("nozzle_throat").name
    hot = np.array([m.name == throat for m in mesh.materials], dtype=bool)[mesh.face_material]
    cold = hot & (mesh.vertices[mesh.faces].mean(axis=1)[:, 2] < main_z - 1.5)
    if not cold.any():
        return mesh
    face_material = np.where(cold, len(mesh.materials), mesh.face_material)
    return Mesh(mesh.vertices, mesh.faces, face_material, mesh.materials + (INTAKE,), mesh.face_chart, mesh.face_uv)


def _textured_paint(mesh: Mesh) -> Mesh:
    """The mesh with the textured mesh's darker paint (``TEXTURED_ALBEDO``) in place of the parts' own (the M3 hull's)."""
    materials = tuple(dataclasses.replace(m, albedo=TEXTURED_ALBEDO[m.name]) if m.name in TEXTURED_ALBEDO else m for m in mesh.materials)
    return Mesh(mesh.vertices, mesh.faces, mesh.face_material, materials, mesh.face_chart, mesh.face_uv)


def textured_parts(placed: list[Placed], style: Style) -> list[TexturedPart]:
    """The hull parts as the textured mesh takes them: the darker paint, soot behind each main nozzle, the intakes dark, no livery."""
    out = []
    for p in placed:
        if not p.hull:
            continue
        mesh, marks = _textured_paint(p.part.mesh), ()
        if p.part.name in ("nacelle_r", "nacelle_l"):
            main = p.part.anchor("main")
            mesh = _cold_intakes(mesh, float(main.position[2]))
            marks = (Marking.soot(p.part.name, main.position, main.direction, 0.6, 0.45, 0.9),)
        out.append(TexturedPart(mesh, phase_steps(p.part.name, False), marks, p.part.name, seams=p.part.seams))
    return out


def coarse_placed(spec: RaiderSpec, style: Style, ctx: BuildContext, triangles: int, offset: np.ndarray) -> list[Placed]:
    """The parts rebuilt with fewer segments, about ``triangles`` in all (never fewer than the flat parts allow), in the fine
    build's frame (moved by its centring ``offset``)."""
    from .starfury_aurora import coarse_spec

    def build_at(factor: float) -> list[Placed]:
        return [p.translated(-offset) for p in build_parts(coarse_spec(spec, factor), style, ctx, 0.3, (COARSE_STREAM,))]

    def count(placed: list[Placed]) -> int:
        return sum(p.part.mesh.face_count for p in placed if p.hull)

    lo, hi = 0.02, 1.0
    best = build_at(hi)
    for _ in range(8):
        mid = 0.5 * (lo + hi)
        placed = build_at(mid)
        if count(placed) > triangles:
            hi = mid
        else:
            lo = mid
            best = placed
    if count(best) > triangles:  # the floor: the wing, the hump and the plates have no segments to drop
        best = build_at(lo)
    return best


# --- build -----------------------------------------------------------------------------------------------
def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the ship into ``ctx.out_dir``.

    Options: ``spacing`` (m, default 0.09), the surface samples' spacing; for the textured mesh (M4-T30d) ``render_triangles`` (0, the
    default, draws the full hull; otherwise the round parts are rebuilt for about this many triangles), ``atlas_px``, ``texel_m``,
    ``occlusion``.
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    if spacing <= 0.0:
        raise ValueError("spacing must be positive")
    spec, style = DEFAULT_SPEC, RAIDER

    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    placed, offset = centre(build_parts(spec, style, ctx, spacing))

    chunk_sources: list[ChunkSource] = []
    for group in CHUNK_ORDER:
        members = [p for p in placed if p.part.group == group]
        points = np.concatenate([p.samples.positions for p in members if p.samples is not None])
        mesh = Mesh.concatenate(p.part.mesh for p in members if p.hull)
        chunk_sources.append(ChunkSource(group, points, mesh))

    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",)
    hull_mesh = Mesh.concatenate(p.part.mesh for p in placed if p.hull)
    aabb_min, aabb_max = hull_mesh.bounds()
    files: list[Path] = write_obj(out_dir / OBJ_NAME, hull_mesh, ASSET_ID, comments)

    chunk_files, chunk_entries = write_chunks(out_dir, ASSET_ID, chunk_sources, comments, with_meshes=True)
    files += chunk_files

    # The textured mesh (M4-T30d) and each chunk's cut of it, on one atlas.
    render_triangles = int(ctx.option("render_triangles", 0))
    textured_source = placed if render_triangles <= 0 else coarse_placed(spec, style, ctx, render_triangles, offset)
    offsets = chunk_offsets(chunk_sources)
    cuts = [ChunkCut(group, tuple(p.part.name for p in textured_source if p.hull and p.part.group == group),
                     tuple(float(v) for v in offsets[group])) for group in CHUNK_ORDER]
    textured_paths, mesh_entry = write_textured_mesh(
        out_dir, ASSET_ID, textured_parts(textured_source, style), style, atlas_px=int(ctx.option("atlas_px", ATLAS_PX)),
        texel_m=float(ctx.option("texel_m", TEXEL_M)), seed=ctx.seed, occlusion=bool(ctx.option("occlusion", True)),
        fine_mesh=hull_mesh if render_triangles > 0 else None, normal_scale=NORMAL_SCALE, chunks=cuts,
        grid=False, detail_levels=DETAIL_LEVELS,
    )
    if render_triangles > 0:
        mesh_entry["render_triangles"] = render_triangles
        mesh_entry["fine_triangles"] = int(hull_mesh.face_count)
    files += textured_paths

    hp = hardpoints(placed, spec, chunk_entries, offset)
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
        files={"obj": OBJ_NAME, "mesh": mesh_entry["file"], "hardpoints": HARDPOINTS_NAME},
        extra={
            "chunks": [c["name"] for c in chunk_entries],
            "mesh": mesh_entry,
            "dimensions_m": {"length": hp["length_m"], "span": hp["span_m"], "height": hp["height_m"]},
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
