"""``raider_fighter``: the raiders' Delta-V flying wing (docs/architecture.md section 15.11).

Composition only, like ``starfury_aurora``: parts from ``parts/`` placed with the ``raider`` style, and every output
(the textured mesh, the OBJ, hardpoints, chunks) derived from the placed parts so they agree by construction.

Layout (authored Godot frame, metres, before re-centring; -Z is forward, the nose at z = 0, the nacelle nozzles at
z = 9). Proportions follow ``docs/design-references.md`` and the maintainer's reference sheet:

* a delta wing 17 m across: leading edges swept 60 degrees from the centre line, a root chord of 5.4 m, square-cut
  0.9 m tips, thickness tapering from 0.35 m to 0.10 m, a darker plated edge band and a few vent grilles;
* a raised central hump 1.8 m wide and 1.2 m high running back from the apex, with a dark canopy panel on its
  forward slope and a louvre grille on its rear top;
* two cylindrical nacelles side by side behind the hump (x = +-0.9, 1.1 m across), each with a dark intake port
  in its nose (the retro) and a bell nozzle 0.9 m across at its rear (the main);
* four spike guns 1.5 m long: two hung under the wing roots, two on the nacelle flanks.

Every part belongs to a *group* (``wing_l``, ``wing_r``, ``hump``, ``nacelle_l``, ``nacelle_r``); each group is written
as a break-up chunk (``core/chunks.py``), with a textured mesh cut from the hull's (M4-T30d).

The textured mesh (M4-T30d, the contract of ``core/textured_mesh.py``): the same hull parts on one atlas, the ``raider`` style's
wear (chipped edges down to bare metal, streaks, grime), soot behind the nozzles and the two yellow-white engine glows of the
reference in the main nozzles' throats; the nose intakes stay dark. No insignia. ``render_triangles`` rebuilds the round parts
coarser with the fine hull baked into the normal map, as the Starfury's option does. The sample set is exactly mirror-symmetric in x (the right-hand groups are sampled once and
mirrored, the centre-line hump is symmetrised); the samples' centroid is moved to the origin, so the hardpoints frame equals
the rendered frame. Samples buried inside another part are dropped.
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
from ..parts import Anchor, Part, mass_centroid, total_mass
from ..parts.hull import HumpSpec, HumpStation, canopy_panel, hump
from ..parts.propulsion import NacelleSpec, NozzleSpec, nacelle, pilot_tags
from ..parts.weapons import BarrelSpec, gun_barrel
from ..parts.wing import WingSpec, delta_wing, vent_grille
from ..styles import Style
from ..styles.raider import RAIDER, TEXTURED_ALBEDO

ASSET_ID = "raider_fighter"
GENERATOR_VERSION = 4  # 4: the textured mesh only (M4-T31); 3: the textured mesh and chunk meshes (M4-T30d)
OBJ_NAME = "raider_fighter.obj"
HARDPOINTS_NAME = "hardpoints.json"
MESH_NAME = "raider_fighter.glb"
# The textured mesh (M4-T30d): about 190 m² of hull at a centimetre a texel in a 2 048 px atlas, the normal map at the atlas's size.
ATLAS_PX = 2048
TEXEL_M = 0.01
NORMAL_SCALE = 1
COARSE_STREAM = "coarse"

DEFAULT_SPACING_M = 0.09  # the surface samples' spacing: the centroid, the buried faces, the chunks' offsets
CHASE_ANCHOR = (0.0, 3.5, 14.0)  # authored frame: behind and above, frames the 17 m span at 70 degrees
EYE = (0.0, 0.95, 1.5)  # the pilot's eye under the canopy panel (authored frame); looks down -Z
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


@dataclass(frozen=True)
class RaiderSpec:
    wing: WingSpec = WingSpec(sweep_deg=56.0, root_chord=5.6, mass_kg=4_400.0)
    hump: HumpSpec = HumpSpec(
        stations=(
            HumpStation(0.50, 0.30, 0.22),
            HumpStation(1.30, 1.00, 0.65),
            HumpStation(2.20, 1.50, 1.00),
            HumpStation(3.40, 1.70, 1.25),
            HumpStation(5.40, 1.50, 1.10),
        ),
        mass_kg=4_000.0,
    )
    nacelle: NacelleSpec = NacelleSpec(
        body_length=4.5,
        radius=0.70,
        nose_length=0.9,
        intake_radius=0.20,
        retro_radius=0.15,
        collar_radius=0.78,
        nozzle=NozzleSpec(throat_r=0.42, exit_r=0.55, length=0.7, wall=0.05),
        mass_kg=3_000.0,
    )
    nacelle_x: float = 1.15
    nacelle_y: float = 0.70  # the thrust line: the centre of mass is trimmed onto it
    nacelle_z: float = 2.0  # front of the drum
    barrel: BarrelSpec = BarrelSpec(
        length=1.5, radius=0.045, base_radius=0.11, base_length=0.45, bore_radius=0.02, bore_depth=0.05, segments=14, mass_kg=300.0
    )
    root_gun_x: float = 3.0
    root_gun_y: float = -0.42
    root_gun_muzzle_z: float = 1.4
    nacelle_gun_muzzle_z: float = 1.7
    canopy_z: tuple[float, float] = (0.9, 2.3)
    canopy_widths: tuple[float, float] = (0.30, 1.00)

    @property
    def nacelle_gun_x(self) -> float:
        return self.nacelle_x + self.nacelle.collar_radius + 0.14

    @property
    def nacelle_gun_y(self) -> float:
        return self.nacelle_y


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
def _in_nacelle(spec: RaiderSpec, points: np.ndarray, margin: float) -> np.ndarray:
    """Inside either nacelle drum (the nozzle bell is not part of the test)."""
    p = np.asarray(points, dtype=float).reshape(-1, 3)
    n = spec.nacelle
    z_local = p[:, 2] - spec.nacelle_z
    r = np.hypot(np.abs(p[:, 0]) - spec.nacelle_x, p[:, 1] - spec.nacelle_y)
    radius = np.array([n.radius_at(float(z)) for z in np.clip(z_local, 0.0, n.body_length)])
    return (z_local > 0.0) & (z_local < n.body_length) & (r < radius - margin)


def _unburied(samples: SurfaceSamples, *inside: np.ndarray) -> SurfaceSamples:
    buried = np.zeros(len(samples), dtype=bool)
    for mask in inside:
        buried |= mask
    return samples.subset(~buried)


def _plate(width: float, length: float, height: float, role: str, style: Style) -> Mesh:
    """A thin raised plate (accent band or recessed-looking panel), base on y = 0."""
    return box((width, height, length), style.material(role), center=(0.0, 0.5 * height, 0.0))


def build_parts(
    spec: RaiderSpec, style: Style, ctx: BuildContext, spacing: float, stream_suffix: tuple[str, ...] = ()
) -> list[Placed]:
    """Every part in the authored frame, sampled, mirrored to the left side where it has one. ``stream_suffix``
    keeps another build's random draws (the coarse one) apart from the fine one's."""

    def sample(mesh: Mesh, stream: str) -> SurfaceSamples:
        return sample_mesh(mesh, spacing, ctx.rng("surface", stream, *stream_suffix))

    wing_spec, hump_spec = spec.wing, spec.hump
    nac_origin = np.array([spec.nacelle_x, spec.nacelle_y, spec.nacelle_z])

    def in_hump(p: np.ndarray) -> np.ndarray:
        return hump_spec.contains(p, BURIED_MARGIN_M)

    def in_wing(p: np.ndarray) -> np.ndarray:
        return wing_spec.contains(p, BURIED_MARGIN_M)

    def in_nac(p: np.ndarray) -> np.ndarray:
        return _in_nacelle(spec, p, BURIED_MARGIN_M)

    placed: list[Placed] = []

    # --- right wing group: slab, vents, accents, root gun --------------------------------------------
    wing = delta_wing(wing_spec, style).renamed("wing_r", group="wing_r")
    s_wing = sample(wing.mesh, "wing")
    s_wing = _unburied(s_wing, in_hump(s_wing.positions), in_nac(s_wing.positions))
    right: list[Placed] = [Placed(wing, s_wing)]

    def on_wing(x: float, z: float, mesh: Mesh, name: str, stream: str) -> Placed:
        top = 0.5 * float(wing_spec.thickness(x))
        part = Part(name, mesh.translated((x, top - 0.002, z)), group="wing_r", mass_kg=0.0)
        return Placed(part, sample(part.mesh, stream))

    right.append(on_wing(3.7, 4.4, vent_grille(1.4, 1.6, 7, style), "wing_vent_a", "wing_vent_a"))
    right.append(on_wing(5.9, 5.2, vent_grille(1.0, 0.8, 4, style), "wing_vent_b", "wing_vent_b"))
    right.append(on_wing(7.3, 5.75, _plate(0.42, 1.0, 0.012, "stripe", style), "wing_band", "wing_band"))
    for k, (x, z, w, d) in enumerate([(4.0, 3.2, 1.2, 0.9), (5.8, 4.0, 1.3, 0.8), (7.0, 5.0, 0.9, 0.7), (2.6, 2.6, 0.8, 0.7)]):
        right.append(on_wing(x, z, _plate(w, d, 0.014, "hull_panel", style), f"wing_plate_{k}", f"wing_plate_{k}"))
    barrel = gun_barrel(spec.barrel, style).translated((spec.root_gun_x, spec.root_gun_y, spec.root_gun_muzzle_z + spec.barrel.length))
    root_gun = barrel.renamed("root_gun_r", group="wing_r")
    pylon_top = 0.5 * float(wing_spec.thickness(spec.root_gun_x))
    pylon = Part(
        "root_pylon_r",
        box((0.34, pylon_top - spec.root_gun_y + 0.02, 0.9), style.material("hull_panel"),
            center=(spec.root_gun_x, 0.5 * (pylon_top + spec.root_gun_y), spec.root_gun_muzzle_z + spec.barrel.length + 0.1)),
        group="wing_r",
    )
    right.append(Placed(root_gun, sample(root_gun.mesh, "root_gun")))
    right.append(Placed(pylon, sample(pylon.mesh, "root_pylon")))
    placed += right
    for p in right:
        placed.append(p.mirrored(p.part.name[:-2] + "_l" if p.part.name.endswith("_r") else p.part.name + "_l", "wing_l"))

    # --- hump group: body, canopy, grille (centre line, symmetrised) -----------------------------------
    body = hump(hump_spec, style)
    s_body = sample(body.mesh, "hump")
    s_body = _unburied(s_body, in_wing(s_body.positions), in_nac(s_body.positions)).symmetrized("x")
    placed.append(Placed(body, s_body))
    canopy = Part(
        "canopy",
        canopy_panel(hump_spec, style, *spec.canopy_z, *spec.canopy_widths),
        group="hump",
    )
    placed.append(Placed(canopy, sample(canopy.mesh, "canopy").symmetrized("x")))
    grille_y = hump_spec.bottom_y + hump_spec.section(4.0)[1] - 0.012
    grille = Part("hump_vent", vent_grille(0.9, 1.8, 8, style).translated((0.0, grille_y, 4.2)), group="hump")
    placed.append(Placed(grille, sample(grille.mesh, "hump_vent").symmetrized("x")))

    # --- right nacelle group: drum, nozzle, flank gun ---------------------------------------------------
    drum = nacelle(spec.nacelle, style).translated(nac_origin).renamed("nacelle_r", group="nacelle_r")
    s_drum = sample(drum.mesh, "nacelle")
    s_drum = _unburied(s_drum, in_wing(s_drum.positions), in_hump(s_drum.positions))
    n_right: list[Placed] = [Placed(drum, s_drum)]
    n_gun = gun_barrel(spec.barrel, style).translated(
        (spec.nacelle_gun_x, spec.nacelle_gun_y, spec.nacelle_gun_muzzle_z + spec.barrel.length)
    ).renamed("nacelle_gun_r", group="nacelle_r")
    n_pylon_x = spec.nacelle_x + spec.nacelle.radius
    n_pylon = Part(
        "nacelle_pylon_r",
        box((spec.nacelle_gun_x - n_pylon_x + 0.1, 0.22, 0.8), style.material("hull_panel"),
            center=(0.5 * (spec.nacelle_gun_x + n_pylon_x), spec.nacelle_gun_y, spec.nacelle_gun_muzzle_z + spec.barrel.length + 0.1)),
        group="nacelle_r",
    )
    n_right.append(Placed(n_gun, sample(n_gun.mesh, "nacelle_gun")))
    n_right.append(Placed(n_pylon, sample(n_pylon.mesh, "nacelle_pylon")))
    placed += n_right
    for p in n_right:
        placed.append(p.mirrored(p.part.name[:-2] + "_l", "nacelle_l"))
    return placed


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
                "main": {"position": _r(main.position), "exhaust": _r(main.direction), "radius": spec.nacelle.nozzle.exit_r},
                "retro": {"position": _r(retro.position), "exhaust": _r(retro.direction), "radius": spec.nacelle.retro_radius},
            }
        )

    muzzles = []
    for key in MUZZLE_ORDER:
        kind, side = key.split("_")
        gun = by_name[f"{'root' if kind == 'root' else 'nacelle'}_gun_{side}"]
        a = gun.anchor("muzzle")
        muzzles.append({"name": key, "position": _r(a.position), "direction": _r(a.direction)})

    rcs = []
    wing = spec.wing
    ports = []  # cosmetic RCS ports: wing tips up/down, mid-wing leading-edge sides
    for sx, tag in ((1.0, "r"), (-1.0, "l")):
        z_tip = 0.5 * (wing.tip_leading_z + wing.tip_trailing_z) - float(offset[2])
        for sy, ey in (("u", 1.0), ("d", -1.0)):
            ports.append((f"{tag}_tip_{sy}", np.array([sx * (wing.half_span - 0.1), 0.0 - float(offset[1]), z_tip]), np.array([0.0, ey, 0.0])))
        ports.append((f"{tag}_edge_x", np.array([sx * 3.4, 0.0 - float(offset[1]), float(wing.leading_z(3.4)) + 0.4 - float(offset[2])]), np.array([sx, 0.0, 0.0])))
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
        out.append(TexturedPart(mesh, phase_steps(p.part.name, False), marks, p.part.name))
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
