"""``narn_transport``: the Narn freighter (M5-T14, D59; docs/assets-civilian.md and docs/design-references.md, "Narn
transport").

Composition only, like ``raider_fighter``: parts from ``parts/narn.py`` placed with the ``narn`` style, and every output
(the textured mesh, fallback mesh, hardpoints, chunks, the turret model) derived from the placed parts so they agree by
construction.

Layout (authored Godot frame, metres, before re-centring; -Z is forward, the prong tips at z = 0, the box's aft face at
z = 70, y = 0 the crescent's centre plane; the design references' measurements):

* a flat crescent 46 m across, 7.8 m thick on the centre line and thinning to a beveled edge at the rim, two thinner
  prongs reaching forward round a notch, a red band on each half's top;
* the cockpit in the notch (z 2.8 to 15.8): a hexagonal nose with a framed canopy on its flat top and a windscreen block
  behind it; the dorsal block on the crescent and the bar running aft from it into the box;
* two upright fins at x +-17.1 and, inboard of them, the flank towers with three bent vanes in front, a slotted crown
  (the turret mounts) and the main nozzles on their aft faces, on a thrust line 5 m above the centre plane;
* the light grey cargo box (25.5 x 14 m, z 31.2 to 70) with a wedge front, the aft lower edge cut back, a green panel and
  hazard checkers on each side and two vent grilles on top.

Every part belongs to a group (``CHUNK_ORDER``); the hull is one textured mesh (``core/civilian.py``; Godot's importer
builds its levels of detail) and each group a cut of it, the break-up chunks. The body origin is the visible surface's
centroid, exactly on the centre plane: right-hand parts are sampled once and mirrored, centre-line parts symmetrised,
surface buried inside another part left out. The turret (D61) is its own small textured mesh.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any

import numpy as np

from ..core import civilian as cv
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh
from ..core.manifest import build_manifest, write_manifest
from ..core.sampling import SurfaceSamples, sample_mesh
from ..parts import Part, mass_centroid, total_mass
from ..parts.narn import (
    CargoBoxSpec,
    CrescentSpec,
    DorsalSpec,
    FinSpec,
    NarnCockpitSpec,
    NarnTurretSpec,
    TowerSpec,
    box_grilles,
    cargo_box,
    crescent_centre,
    crescent_half,
    dorsal,
    fin,
    flank_tower,
    narn_cockpit,
    narn_turret,
)
from ..parts.propulsion import pilot_tags
from ..styles import Style
from ..styles.narn import NARN

ASSET_ID = "narn_transport"
GENERATOR_VERSION = 2  # 2: textured meshes (M5-T27)
OBJ_NAME = f"{ASSET_ID}.obj"
HARDPOINTS_NAME = "hardpoints.json"

DEFAULT_SPACING_M = 0.31  # the surface samples' spacing: the body origin and the chunks' offsets
CHUNK_ORDER = ("cockpit", "wing_l", "wing_r", "box")

# The turret (D61): its own panel size and seam (the hull's 2.4 m plates are about its size); arc and barrel length from
# docs/assets-civilian.md.
TURRET_STEM = f"{ASSET_ID}_turret"
TURRET_PANEL_M = (0.65, 0.06)
TURRET_ARC_DEG = 220.0  # the tower tops: a hemisphere and then some, to fire down past the crescent's edge

BURIED_MARGIN_M = 0.05
JSON_DIGITS = 5
EYE = (0.0, 1.2, 11.3)  # inside the windscreen block, looking out over the canopy (authored frame)
CHASE_ANCHOR_SHARE = (0.3, 1.2)  # above and behind the centroid, in lengths
NAV_LIGHT_CLEARANCE_M = 0.15
NAV_SIDE = (23.0, 0.0, 27.0)  # the crescent's widest point, right side
NAV_TOP_Z = 50.0  # the white light on the box's top, the highest point on the centre line
NAV_LAMP_HEIGHT_M = 7.0
NAV_LAMP_RANGE_SHARE = 0.3
NAV_CABIN_RANGE_SHARE = 0.05


@dataclass(frozen=True)
class NarnSpec:
    crescent: CrescentSpec = CrescentSpec()
    cockpit: NarnCockpitSpec = NarnCockpitSpec()
    dorsal: DorsalSpec = DorsalSpec()
    fin: FinSpec = FinSpec()
    tower: TowerSpec = TowerSpec()
    box: CargoBoxSpec = CargoBoxSpec()
    turret: NarnTurretSpec = NarnTurretSpec()


DEFAULT_SPEC = NarnSpec()


@dataclass
class Placed:
    """A placed part with its visible surface samples (``None`` for meshes that are not sampled)."""

    part: Part
    samples: SurfaceSamples | None
    spacing: float = 0.0
    hull: bool = True

    def translated(self, offset: np.ndarray) -> Placed:
        return Placed(self.part.translated(offset), None if self.samples is None else self.samples.translated(offset), self.spacing, self.hull)

    def mirrored(self, name: str, group: str) -> Placed:
        return Placed(
            self.part.mirrored("x").renamed(name, group=group),
            None if self.samples is None else self.samples.mirrored("x"),
            self.spacing,
            self.hull,
        )


def _unburied(samples: SurfaceSamples, solids: tuple[Any, ...], extra: np.ndarray | None = None) -> SurfaceSamples:
    """The samples not hidden inside any of ``solids`` (nor flagged by ``extra``)."""
    buried = np.zeros(len(samples), dtype=bool) if extra is None else np.asarray(extra, dtype=bool).copy()
    for solid in solids:
        buried |= solid.contains(samples.positions, BURIED_MARGIN_M)
    return samples.subset(~buried)


def _under_grilles(spec: CargoBoxSpec, samples: SurfaceSamples) -> np.ndarray:
    """The box's top samples under a grille's plate."""
    p = samples.positions
    covered = np.zeros(len(p), dtype=bool)
    for x0, x1, z0, z1 in spec.grille_footprints():
        covered |= (p[:, 0] > x0) & (p[:, 0] < x1) & (p[:, 2] > z0) & (p[:, 2] < z1)
    return covered & (p[:, 1] > spec.top_y - 0.05)


def build_parts(
    spec: NarnSpec, style: Style, ctx: BuildContext, spacing: float, stream_suffix: tuple[str, ...] = (), systematic: bool = False
) -> list[Placed]:
    """Every part in the authored frame with its visible surface sampled; right-hand groups mirrored to the left.
    ``stream_suffix`` keeps another build's random draws apart; ``systematic`` as ``sample_mesh``'s."""

    def sample(mesh: Mesh, stream: str) -> SurfaceSamples:
        return sample_mesh(mesh, spacing, ctx.rng("surface", stream, *stream_suffix), systematic=systematic)

    crescent = spec.crescent
    cockpit_body, hump = spec.cockpit.body_solid(), spec.cockpit.hump.solid()
    block, rod = spec.dorsal.block.solid(), spec.dorsal.rod_solid()
    fin_body, tower_body, box_body = spec.fin.solid(), spec.tower.body.solid(), spec.box.solid()

    def place(part: Part, group: str, buried_by: tuple[Any, ...], symmetric: bool = False, extra=None) -> Placed:
        part = part.renamed(part.name, group=group)
        samples = sample(part.mesh, part.name)
        samples = _unburied(samples, buried_by, None if extra is None else extra(samples))
        return Placed(part, samples.symmetrized("x") if symmetric else samples, spacing)

    placed = [
        place(crescent_centre(crescent, style), "cockpit", (cockpit_body, hump, block, rod, box_body), symmetric=True),
        place(narn_cockpit(spec.cockpit, style), "cockpit", (crescent, cockpit_body, hump), symmetric=True),
        place(dorsal(spec.dorsal, style), "cockpit", (crescent, block, rod, box_body), symmetric=True),
    ]
    right = [
        place(crescent_half(crescent, style), "wing_r", (box_body, fin_body, tower_body)),
        place(fin(spec.fin, style), "wing_r", (crescent, tower_body)),
        place(flank_tower(spec.tower, style), "wing_r", (crescent, fin_body, tower_body)),
    ]
    placed += [p.mirrored(p.part.name[:-2] + "_l", "wing_l") for p in right] + right
    placed += [
        place(cargo_box(spec.box, style), "box", (crescent, block, rod), symmetric=True, extra=lambda s: _under_grilles(spec.box, s)),
        place(box_grilles(spec.box, style), "box", (box_body,), symmetric=True),
    ]
    return placed


# --- centring -------------------------------------------------------------------------------------------------------
def centre(placed: list[Placed]) -> tuple[list[Placed], np.ndarray]:
    """Moves the visible surface's centroid to the origin. x is zero by symmetry; the offset (Godot frame) is the authored
    position of the new origin (``manifest.centroid_offset``)."""
    sampled = [p.samples for p in placed if p.samples is not None]
    total = sum(len(s) for s in sampled)
    mean = sum(s.positions.sum(axis=0) for s in sampled) / total
    offset = np.array([0.0, float(mean[1]), float(mean[2])])
    return [p.translated(-offset) for p in placed], offset


def paint_name(name: str) -> str:
    """Twins share their panel phase: a left part paints as its right one."""
    return name[:-2] + "_r" if name.endswith("_l") else name


def hull_parts(placed: list[Placed]) -> list[cv.HullPart]:
    """The (centred) hull parts as the textured mesh takes them."""
    return [
        cv.HullPart(p.part.name, p.part.group, p.part.mesh, p.samples.positions if p.samples is not None else np.zeros((0, 3)),
                    paint_name(p.part.name))
        for p in placed if p.hull
    ]  # fmt: skip


# --- hardpoints --------------------------------------------------------------------------------------------------------
def _r(v: Any) -> list[float]:
    return [round(float(x), JSON_DIGITS) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


def rcs_ports(spec: NarnSpec) -> list[tuple[str, tuple[float, float, float], tuple[float, float, float]]]:
    """Cosmetic RCS ports of the right side (authored frame): the prong tip forward and outboard, the fin tips up and
    down, the box's aft corner up, outboard and down."""
    c, f, b = spec.crescent, spec.fin, spec.box
    tip_x = c.outer[0][1]
    out_z = 2.0
    corner_x = b.chamfer_x - 0.2
    return [
        ("prong_fwd", (tip_x + 0.2, 0.0, 0.3), (0.0, 0.0, -1.0)),
        ("prong_out", (float(c.half_width(out_z)), 0.0, out_z), (1.0, 0.0, 0.0)),
        ("fin_up", (f.x, f.outline[1][1], 33.0), (0.0, 1.0, 0.0)),
        ("fin_down", (f.x, f.outline[-1][1], 33.0), (0.0, -1.0, 0.0)),
        ("box_aft_up", (corner_x, b.top_y, b.rear_chamfer_z - 0.2), (0.0, 1.0, 0.0)),
        ("box_aft_out", (b.half_width, 2.0, b.rear_z - 0.5), (1.0, 0.0, 0.0)),
        ("box_aft_down", (corner_x, b.bottom_y, b.aft_cut_z - 0.4), (0.0, -1.0, 0.0)),
    ]


def chunk_joints(spec: NarnSpec, offset: np.ndarray) -> dict[str, list[float]]:
    """Where each chunk detaches: a wing along its seam with the crescent's centre, the box where it hangs under the
    centre, the cockpit chunk (the crescent's centre) at the middle of the three."""
    c, b = spec.crescent, spec.box
    wing = np.array([c.seam_x, 0.0, 0.5 * (c.notch_back_z + c.seam_end_z)])
    joints = {
        "wing_r": wing,
        "wing_l": wing * np.array([-1.0, 1.0, 1.0]),
        "box": np.array([0.0, 0.0, 0.5 * (b.front_z + c.rear_z)]),
    }
    joints["cockpit"] = np.mean(list(joints.values()), axis=0)
    return {name: _r(point - offset) for name, point in joints.items()}


def nav_lights(spec: NarnSpec, by_name: dict[str, Part], offset: np.ndarray, length: float) -> dict[str, Any]:
    """Running lights: red and green just past the crescent's widest points, white on the box's top, a lamp standing over it,
    the cabin glow at the windscreen."""
    side = np.array(NAV_SIDE) + np.array([NAV_LIGHT_CLEARANCE_M, 0.0, 0.0])
    top_y = spec.box.top_y
    return {
        "port": _r(side * np.array([-1.0, 1.0, 1.0]) - offset),
        "starboard": _r(side - offset),
        "top": _r(np.array([0.0, top_y + NAV_LIGHT_CLEARANCE_M, NAV_TOP_Z]) - offset),
        "top_lamp": _r(np.array([0.0, top_y + NAV_LAMP_HEIGHT_M, NAV_TOP_Z]) - offset),
        "top_lamp_range_m": round(NAV_LAMP_RANGE_SHARE * length, 2),
        "cabin": _r(by_name["cockpit"].anchor("windscreen").position),
        "cabin_range_m": round(NAV_CABIN_RANGE_SHARE * length, 2),
    }


def hardpoints(placed: list[Placed], spec: NarnSpec, chunks: list[dict[str, Any]], offset: np.ndarray) -> dict[str, Any]:
    """The hardpoints document (centred Godot frame) from the placed (already centred) parts; ``chunks`` are the
    ``write_chunks`` entries."""
    by_name = {p.part.name: p.part for p in placed}
    hull_parts = [p.part for p in placed if p.hull]
    lo, hi = Mesh.concatenate(p.mesh for p in hull_parts).bounds()
    length = float(hi[2] - lo[2])

    thrust_y = spec.tower.thrust[1] - float(offset[1])
    com = np.array([0.0, thrust_y, float(mass_centroid(hull_parts)[2])])  # on the thrust line: main thrust makes no pitch torque
    inertia = np.zeros(3)
    for part in hull_parts:
        d = part.area_centroid() - com
        inertia += part.mass_kg * np.array([d[1] ** 2 + d[2] ** 2, d[0] ** 2 + d[2] ** 2, d[0] ** 2 + d[1] ** 2])

    pods = []
    for name, side in (("l", "left"), ("r", "right")):
        tower = by_name[f"tower_{name}"]
        main, retro = tower.anchor("main"), tower.anchor("retro")
        pods.append({
            "name": name,
            "side": side,
            "center": _r(tower.anchor("centre").position),
            "main": {"position": _r(main.position), "exhaust": _r(main.direction), "radius": spec.tower.nozzle.exit_r},
            "retro": {"position": _r(retro.position), "exhaust": _r(retro.direction), "radius": spec.tower.retro_radius},
        })  # fmt: skip

    rcs = []
    for prefix, flip in (("r", 1.0), ("l", -1.0)):
        for name, position, exhaust in rcs_ports(spec):
            p = np.array(position) * np.array([flip, 1.0, 1.0]) - offset
            e = np.array(exhaust) * np.array([flip, 1.0, 1.0])
            rcs.append({"name": f"{prefix}_{name}", "pod": prefix, "position": _r(p), "exhaust": _r(e), "tags": pilot_tags(p, e, com)})

    collision = []
    for part in hull_parts:
        for shape in part.collision:
            collision.append({**shape.to_json(digits=JSON_DIGITS), "name": f"{part.name}_{shape.name}" if shape.name else part.name})

    turrets = []
    for name, side in (("tower_l", "l"), ("tower_r", "r")):
        mount = by_name[f"tower_{side}"].anchor("turret")
        turrets.append({"name": name, "position": _r(mount.position), "up": _r(mount.direction), "arc_deg": TURRET_ARC_DEG,
                        "barrel_m": spec.turret.barrel_m})  # fmt: skip

    joints = chunk_joints(spec, offset)
    return {
        "asset_id": ASSET_ID,
        "generator_version": GENERATOR_VERSION,
        "frame": "godot",
        "units": "m",
        "length_m": round(length, 3),
        "span_m": round(float(hi[0] - lo[0]), 3),
        "height_m": round(float(hi[1] - lo[1]), 3),
        "mass_kg": round(total_mass(hull_parts), 1),
        "inertia_estimate_kg_m2": _r(inertia),
        "center_of_mass": _r(com),
        "cockpit_camera": {"position": _r(np.array(EYE) - offset), "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0]},
        "chase_anchor": {"position": _r((0.0, CHASE_ANCHOR_SHARE[0] * length, CHASE_ANCHOR_SHARE[1] * length))},
        "muzzles": [],
        "pods": pods,
        "rcs": rcs,
        "collision": collision,
        "nav_lights": nav_lights(spec, by_name, offset, length),
        "turrets": turrets,
        "chunks": [{**c, "joint": joints[c["name"]]} for c in chunks],
    }


# --- build -------------------------------------------------------------------------------------------------------------
def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the ship and its turret into ``ctx.out_dir``.

    Options: ``spacing`` (m, default 0.31; the surface samples' spacing), ``atlas_px`` (the hull's atlas, default 2 048),
    ``model_atlas_px`` (the turret's, default 1 024), ``occlusion`` (default off).
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    if spacing <= 0.0:
        raise ValueError("spacing must be positive")
    spec, style = DEFAULT_SPEC, NARN
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",)

    placed, offset = centre(build_parts(spec, style, ctx, spacing))
    hull = cv.write_hull(out_dir, ASSET_ID, hull_parts(placed), CHUNK_ORDER, style, ctx, comments)
    files: list[Path] = list(hull.files)

    turret_part = narn_turret(spec.turret, style)
    fine = replace(style, panel_size_m=TURRET_PANEL_M[0], panel_line_width_m=TURRET_PANEL_M[1])
    turret_files, section = cv.write_model(out_dir, TURRET_STEM, [(turret_part.name, turret_part.mesh)], fine, ctx, comments + ("turret",))
    files += turret_files
    turret_entry = cv.turret_entry(TURRET_STEM, turret_part, spec.turret.barrel_m, section)

    hp = hardpoints(placed, spec, hull.chunks, offset)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=hull.aabb_min,
        aabb_max=hull.aabb_max,
        centroid_offset=offset,
        files={"obj": OBJ_NAME, "mesh": hull.mesh_section["file"], "hardpoints": HARDPOINTS_NAME},
        extra={
            "mesh": hull.mesh_section,
            "chunks": [c["name"] for c in hull.chunks],
            "surface_spacing_m": spacing,
            "dimensions_m": {"length": hp["length_m"], "span": hp["span_m"], "height": hp["height_m"]},
            "turret": turret_entry,
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
