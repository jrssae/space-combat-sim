"""``grid_heavy_cannon``: the station's heavy cannon (M7-T43), an original model after the maintainer's notes on the show's big guns:
one large barrel with an oval (racetrack) muzzle on a boxy, ribbed body, sitting in a recess in the hull and swinging out of it.

The maintainer's sizes (2026-11-15): about 30 m long, the oval muzzle about 9 x 4 m. Built from primitives, never traced.

Frame (the mount's, as every turret model's, ``parts/turret.py``): the origin at the base's foot on the recess floor, +Y the mount's
up, the barrel along -Z at rest, +X to the right. Three parts move apart, as ``TurretMount`` turns them:

* ``base``: the bearing ring, fixed to the recess floor;
* ``yaw``: the turntable and the yoke's two cheeks, turning about +Y through the origin;
* ``pitch``: the body, the breech and the barrel, lifting about the trunnion axis (parallel to X).

The trunnion stands high enough that the breech clears the turntable with the barrel straight up, and the barrel's underside clears
the hull's deck (the recess is ``RECESS_DEPTH_M`` deep) with the barrel level.

Outputs: the textured mesh of the whole gun (``grid_heavy_cannon.glb``, its maps) and one cut per moving part on the same maps
(``grid_heavy_cannon_chunk_<part>.glb``; the pitch cut's origin is the trunnion), the fallback OBJ and the manifest, whose ``turret``
entry names the parts, the trunnion and the one muzzle (turret frame, and pitch frame).
"""

from __future__ import annotations

import dataclasses
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..core.chunks import ChunkCut, chunk_mesh_name
from ..core.civilian import DETAIL_LEVELS, MODEL_ATLAS_PX, at_texel, r, texel_of
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Material, Mesh, box, lathe, loft, prism, rotation_x, rotation_y
from ..core.manifest import build_manifest, write_manifest
from ..core.obj import write_obj
from ..core.textured_mesh import TexturedPart, phase_steps, write_textured_mesh
from ..styles import Style
from ..styles.earth_alliance_station import EARTH_ALLIANCE_STATION

ASSET_ID = "grid_heavy_cannon"
GENERATOR_VERSION = 1
OBJ_NAME = f"{ASSET_ID}.obj"
PARTS = ("base", "yaw", "pitch")
ATLAS_PX = 2 * MODEL_ATLAS_PX  # twice a turret's: the gun is 30 m long

_Z_TO_Y = rotation_x(-0.5 * math.pi)
_Z_TO_X = rotation_y(0.5 * math.pi)
_SIDE_TO_X = rotation_y(-0.5 * math.pi)  # a side profile drawn in (z, y) laid across x


@dataclass(frozen=True)
class CannonSpec:
    """Sizes in metres, in the mount's frame (z along the barrel, negative ahead of the trunnion)."""

    trunnion_y: float = 9.5
    muzzle_w: float = 9.0  # the oval muzzle's outside, across and up
    muzzle_h: float = 4.0
    bore_w: float = 7.0
    bore_h: float = 2.2
    bore_depth_m: float = 12.0  # through the housing and well down the tube
    bore_rings: tuple[float, ...] = (3.2, 6.4, 9.6)  # the stepped rings down the bore, back from the mouth
    muzzle_z: float = -22.5
    housing_m: float = 3.9  # the muzzle housing's length
    barrel_w: float = 8.0  # the tube behind the housing
    barrel_h: float = 3.2
    collars: tuple[float, ...] = (-16.0, -13.2, -10.4)
    body_front_z: float = -6.5
    body_back_z: float = 5.5
    body_w: float = 7.6
    body_bottom: float = -2.2  # off the trunnion
    body_top: float = 3.2
    rib_pitch_m: float = 1.05
    rear_z: float = 7.5  # the back of the capacitor drum
    cheek_inner_x: float = 5.2
    cheek_t: float = 1.2
    table_r: float = 5.6
    base_r: float = 6.2
    panel_size_m: float = 2.4  # its own plating: the station's 40 m panels are bigger than the whole gun
    panel_line_m: float = 0.06
    segments: int = 32
    oval_points: int = 40  # points round a racetrack ring

    @property
    def length_m(self) -> float:
        return self.rear_z - self.muzzle_z

    def muzzle(self) -> tuple[float, float, float]:
        """The muzzle in the mount's frame: the centre of the bore's mouth."""
        return (0.0, self.trunnion_y, self.muzzle_z)

    def pitch_muzzle(self) -> tuple[float, float, float]:
        """The muzzle in the pitch frame (origin at the trunnion)."""
        return (0.0, 0.0, self.muzzle_z)


DEFAULT_SPEC = CannonSpec()
# How deep the recess in the hull is (``station.py`` cuts it): with the barrel level, the body's ribs just clear the deck and the
# turntable and yoke sit below it.
RECESS_DEPTH_M = 6.8


def fine_style(spec: CannonSpec) -> Style:
    """The station's paint at the gun's scale: its own panels and a fighter's wear (``at_texel`` scales it up)."""
    s = EARTH_ALLIANCE_STATION
    finish = dict(s.extra.get("metal_finish", {}))
    finish.update({"panel_m": spec.panel_size_m, "noise_m": 2.0})
    extra = {k: v for k, v in s.extra.items() if k not in ("planar_detail", "wear_scale")}
    extra.update({"metal_finish": finish, "rivets": 0.3})
    return dataclasses.replace(s, panel_size_m=spec.panel_size_m, panel_line_width_m=spec.panel_line_m, groove_depth_m=0.015,
                               hatch_depth_m=0.005, edge_wear_width_m=0.05, grime_scale_m=1.2, extra=extra)


# --- shapes ----------------------------------------------------------------------------------------------------------------
def racetrack(w: float, h: float, n: int) -> np.ndarray:
    """``(n, 2)`` closed outline of a stadium ``w`` across and ``h`` tall (round ends, straight top and bottom), counter-clockwise,
    its points spread evenly along the outline so rings of the same ``n`` line up."""
    rad = 0.5 * min(w, h)
    s = 0.5 * w - rad
    straight, arc = 2.0 * s, math.pi * rad
    total = 2.0 * (straight + arc)
    out = []
    for k in range(n):
        d = (k + 0.5) / n * total
        if d < 0.5 * arc:  # the right end's upper half
            a = d / rad
            out.append((s + rad * math.cos(a), rad * math.sin(a)))
            continue
        d -= 0.5 * arc
        if d < straight:  # the top, right to left
            out.append((s - d, rad))
            continue
        d -= straight
        if d < arc:  # the left end
            a = 0.5 * math.pi + d / rad
            out.append((-s + rad * math.cos(a), rad * math.sin(a)))
            continue
        d -= arc
        if d < straight:  # the bottom, left to right
            out.append((-s + d, -rad))
            continue
        d -= straight
        a = -0.5 * math.pi + d / rad  # the right end's lower half
        out.append((s + rad * math.cos(a), rad * math.sin(a)))
    return np.asarray(out, dtype=float)


def chamfered(w: float, h: float, c: float, y0: float = 0.0) -> np.ndarray:
    """``(8, 2)`` outline of a ``w`` x ``h`` rectangle with its corners cut by ``c``, counter-clockwise, its centre ``y0`` up."""
    x, y = 0.5 * w, 0.5 * h
    pts = [(x, -y + c), (x, y - c), (x - c, y), (-x + c, y), (-x, y - c), (-x, -y + c), (-x + c, -y), (x - c, -y)]
    return np.asarray([(px, py + y0) for px, py in pts], dtype=float)


def ring3(outline: np.ndarray, z: float) -> np.ndarray:
    return np.column_stack([outline, np.full(len(outline), z)])


def tube(outlines: list[tuple[np.ndarray, float]], material: Material, caps: bool = True) -> Mesh:
    """A closed solid lofted through ``(outline, z)`` rings from front to back."""
    return loft([ring3(o, z) for o, z in outlines], material, cap_start=caps, cap_end=caps)


def annulus(outer: np.ndarray, inner: np.ndarray, z: float, facing: float, material: Material) -> Mesh:
    """The flat ring between two outlines of the same point count at depth ``z``, its faces turned toward ``facing`` (-1 the bow)."""
    a, b = ring3(outer, z), ring3(inner, z)
    n = len(a)
    verts = np.concatenate([a, b])
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces += [[i, j, n + j], [i, n + j, n + i]]
    faces = np.asarray(faces)
    v = verts[faces]
    normal = np.cross(v[0, 1] - v[0, 0], v[0, 2] - v[0, 0])
    if normal[2] * facing < 0.0:
        faces = faces[:, ::-1]
    return Mesh(verts, faces, np.zeros(len(faces), dtype=np.int64), (material,))


def band(w: float, h: float, under_w: float, under_h: float, z0: float, z1: float, n: int, material: Material) -> Mesh:
    """A raised racetrack ring ``w`` x ``h`` round a surface ``under_w`` x ``under_h``, from ``z0`` to ``z1``: open through the
    middle, so it never shuts the bore it girdles."""
    outer, under = racetrack(w, h, n), racetrack(under_w, under_h, n)
    return Mesh.concatenate([tube([(outer, z0), (outer, z1)], material, caps=False), annulus(outer, under, z0, -1.0, material),
                             annulus(outer, under, z1, 1.0, material)])


def _mirror_x(mesh: Mesh) -> Mesh:
    return Mesh.concatenate([mesh, mesh.mirrored("x")])


def cylinder_z(z0: float, z1: float, radius: float, material: Material, segments: int) -> Mesh:
    """A closed cylinder along z from ``z0`` to ``z1``."""
    return lathe([(z0, 0.0), (z0, radius), (z1, radius), (z1, 0.0)], segments, material, creases={1, 2})


# --- the parts -------------------------------------------------------------------------------------------------------------
def barrel(spec: CannonSpec, style: Style) -> list[tuple[str, Mesh]]:
    """The barrel in the pitch frame: the oval muzzle housing (a chamfered lip round a deep dark bore that runs well down the tube,
    stepped by rings that show its depth), the tube behind it with raised collars, and a row of cooling fins along its top."""
    steel, grey, dark, hull = style.material("vane_frame"), style.material("spine"), style.material("recess"), style.material("spine_top")
    n = spec.oval_points
    z0 = spec.muzzle_z
    z_back = z0 + spec.housing_m
    lip = 0.4
    outer = [(racetrack(spec.muzzle_w - 2 * lip, spec.muzzle_h - 2 * lip, n), z0),
             (racetrack(spec.muzzle_w, spec.muzzle_h, n), z0 + lip),
             (racetrack(spec.muzzle_w, spec.muzzle_h, n), z_back - lip),
             (racetrack(spec.muzzle_w - 0.6, spec.muzzle_h - 0.6, n), z_back)]
    housing = tube(outer, grey, caps=False)
    bands = [band(spec.muzzle_w + 0.5, spec.muzzle_h + 0.5, spec.muzzle_w, spec.muzzle_h, z - 0.2, z + 0.2, n, steel)
             for z in (z0 + 1.5, z0 + 2.6)]
    bore = racetrack(spec.bore_w, spec.bore_h, n)
    face = annulus(outer[0][0], bore, z0, -1.0, steel)
    # The bore runs through the housing into the tube, its walls facing in, shut by a back plate: near black inside, so it reads as
    # a deep hole whatever the light, as the clip's does.
    soot, void = style.material("bay_dark"), style.material("bay_void")
    walls = tube([(bore[::-1], z0), (bore[::-1], z0 + spec.bore_depth_m)], soot, caps=False)
    plate = tube([(bore, z0 + spec.bore_depth_m), (bore, z0 + spec.bore_depth_m + 0.1)], void)
    narrow = racetrack(spec.bore_w - 0.5, spec.bore_h - 0.5, n)
    rings = []
    for d in spec.bore_rings:
        za, zb = z0 + d, z0 + d + 0.4
        rings += [tube([(narrow[::-1], za), (narrow[::-1], zb)], dark, caps=False), annulus(bore, narrow, za, -1.0, dark),
                  annulus(bore, narrow, zb, 1.0, dark)]
    back = annulus(outer[-1][0], racetrack(spec.barrel_w, spec.barrel_h, n), z_back, 1.0, steel)
    tube_z0, tube_z1 = z_back, spec.body_front_z + 0.5
    # Open at its front: the bore runs on into it.
    pipe = loft([ring3(racetrack(spec.barrel_w, spec.barrel_h, n), tube_z0), ring3(racetrack(spec.barrel_w, spec.barrel_h, n), tube_z1)], hull,
                cap_start=False)
    collars = [band(spec.barrel_w + 0.6, spec.barrel_h + 0.6, spec.barrel_w, spec.barrel_h, z - 0.35, z + 0.35, n, steel)
               for z in spec.collars]
    fins = [box((0.22, 0.6, tube_z1 - tube_z0 - 1.0), steel, center=(x, 0.5 * spec.barrel_h + 0.25, 0.5 * (tube_z0 + tube_z1)))
            for x in (-1.2, -0.4, 0.4, 1.2)]
    return [("muzzle", Mesh.concatenate([housing, face, back, *bands])), ("bore", Mesh.concatenate([walls, plate, *rings])),
            ("barrel", Mesh.concatenate([pipe, *collars, *fins]))]


def body(spec: CannonSpec, style: Style) -> list[tuple[str, Mesh]]:
    """The body in the pitch frame: a chamfered box girdled by heavy ribs, a dorsal housing, conduits down each flank, the breech
    tapering to a capacitor drum at the back, and the trunnion pins into the yoke."""
    hull, grey, steel, dark, mach = (style.material(k) for k in ("spine_top", "spine", "vane_frame", "recess", "machinery"))
    h = spec.body_top - spec.body_bottom
    yc = 0.5 * (spec.body_top + spec.body_bottom)
    core = tube([(chamfered(spec.body_w, h, 0.9, yc), spec.body_front_z), (chamfered(spec.body_w, h, 0.9, yc), spec.body_back_z)], hull)
    ribs = []
    z = spec.body_front_z + 0.8
    while z < spec.body_back_z - 0.4:
        rib = chamfered(spec.body_w + 0.9, h + 0.9, 1.2, yc)
        ribs.append(tube([(rib, z - 0.25), (rib, z + 0.25)], grey))
        z += spec.rib_pitch_m
    top = spec.body_top + 0.3
    dorsal = box((3.6, 1.1, 8.0), grey, center=(0.0, top + 0.55, 0.5))
    vents = [box((3.0, 0.12, 0.35), dark, center=(0.0, top + 1.16, z)) for z in np.linspace(-2.6, 3.6, 7)]
    sensor = box((1.4, 0.9, 1.6), mach, center=(1.0, top + 1.55, 3.4))
    conduits = []
    for y in (-1.0, 0.9):
        conduits.append(cylinder_z(spec.body_front_z - 0.4, spec.body_back_z + 0.6, 0.38, mach, 14).translated((spec.body_w / 2 + 0.4, y, 0.0)))
    breech = tube([(chamfered(6.2, 4.6, 0.8, yc), spec.body_back_z), (chamfered(4.8, 3.6, 0.6, yc), spec.rear_z - 0.5)], hull)
    drum = cylinder_z(spec.rear_z - 0.5, spec.rear_z, 1.5, steel, spec.segments).translated((0.0, yc, 0.0))
    pin_x0, pin_x1 = 0.5 * spec.body_w + 0.3, spec.cheek_inner_x + 0.5 * spec.cheek_t
    pin = lathe([(0.0, 0.0), (0.0, 1.1), (pin_x1 - pin_x0, 1.1), (pin_x1 - pin_x0, 0.0)], spec.segments, steel, creases={1, 2})
    pin = pin.transformed(_Z_TO_X, (pin_x0, 0.0, 0.0))
    return [("body", Mesh.concatenate([core, breech, drum])), ("ribs", Mesh.concatenate([*ribs, dorsal, sensor])),
            ("vents", Mesh.concatenate(vents)), ("conduits", _mirror_x(Mesh.concatenate([*conduits, pin])))]


def yoke(spec: CannonSpec, style: Style) -> list[tuple[str, Mesh]]:
    """The turntable and the yoke: a deck on the turntable and a tapering cheek up each side to the trunnion, with a bearing boss."""
    grey, steel, mach = style.material("spine"), style.material("vane_frame"), style.material("machinery")
    y0, table_h = 1.0, 0.8
    table = lathe([(0.0, 0.0), (0.0, spec.table_r - 0.2), (0.2, spec.table_r), (table_h, spec.table_r), (table_h, 0.0)], spec.segments,
                  [steel, steel, grey, grey], creases={1, 2, 3})
    deck_y = y0 + table_h
    deck = box((2.0 * (spec.cheek_inner_x + spec.cheek_t), 0.7, 8.4), grey, center=(0.0, deck_y + 0.35, 0.0))
    top = spec.trunnion_y + 1.6
    side = np.array([(-4.2, deck_y + 0.7), (4.2, deck_y + 0.7), (2.0, top), (-2.0, top)])
    cheek = prism([(side, grey)], [(side, grey)], spec.cheek_t).transformed(_SIDE_TO_X, (spec.cheek_inner_x + 0.5 * spec.cheek_t, 0.0, 0.0))
    boss = lathe([(0.0, 0.0), (0.0, 1.6), (0.35, 1.6), (0.35, 0.0)], spec.segments, steel, creases={1, 2})
    boss = boss.transformed(_Z_TO_X, (spec.cheek_inner_x + spec.cheek_t, spec.trunnion_y, 0.0))
    # The elevation drive's housings low on each cheek's inside.
    drive = box((0.9, 2.4, 3.2), mach, center=(spec.cheek_inner_x - 0.45, deck_y + 1.9, 1.2))
    return [("yoke", Mesh.concatenate([table.transformed(_Z_TO_Y, (0.0, y0, 0.0)), deck, _mirror_x(Mesh.concatenate([cheek, boss, drive]))]))]


def base(spec: CannonSpec, style: Style) -> list[tuple[str, Mesh]]:
    """The bearing ring bolted to the recess floor."""
    steel, mach = style.material("vane_frame"), style.material("machinery")
    ring = lathe([(0.0, 0.0), (0.0, spec.base_r), (0.6, spec.base_r), (0.6, spec.base_r - 0.5), (1.0, spec.base_r - 0.5), (1.0, 0.0)],
                 spec.segments, [mach, mach, steel, steel, steel], creases={1, 2, 3, 4})
    return [("base", ring.transformed(_Z_TO_Y))]


def cannon_parts(spec: CannonSpec, style: Style) -> dict[str, list[tuple[str, Mesh]]]:
    """Every named mesh by moving part, in the mount's frame."""
    lift = (0.0, spec.trunnion_y, 0.0)
    pitch = [(name, mesh.translated(lift)) for name, mesh in barrel(spec, style) + body(spec, style)]
    return {"base": base(spec, style), "yaw": yoke(spec, style), "pitch": pitch}


def turret_entry(spec: CannonSpec, section: dict[str, Any]) -> dict[str, Any]:
    """The manifest's ``turret`` entry: the whole mesh, a cut per moving part (the pitch cut's origin at the trunnion), the trunnion
    and the muzzle, in the mount's frame (``muzzles``, as every turret's) and the pitch frame (``pitch_muzzles``)."""
    return {
        "obj": OBJ_NAME,
        "mesh": section,
        "parts": {name: chunk_mesh_name(ASSET_ID, name) for name in PARTS},
        "barrel_m": round(-spec.muzzle_z, 4),
        "trunnion": r((0.0, spec.trunnion_y, 0.0)),
        "muzzles": [r(spec.muzzle())],
        "pitch_muzzles": [r(spec.pitch_muzzle())],
        "muzzle_size_m": r((spec.muzzle_w, spec.muzzle_h)),
        "recess_depth_m": round(RECESS_DEPTH_M, 4),
    }


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the gun into ``ctx.out_dir``. Option: ``model_atlas_px`` (default 2 048)."""
    spec = DEFAULT_SPEC
    style = fine_style(spec)
    out_dir = Path(ctx.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    groups = cannon_parts(spec, style)
    named = [(name, mesh) for part in PARTS for name, mesh in groups[part]]
    whole = Mesh.concatenate(m for _, m in named)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",)
    files: list[Path] = write_obj(out_dir / OBJ_NAME, whole, ASSET_ID, comments)
    textured = [TexturedPart(m, phase_steps(name, False), (), name) for name, m in named]
    atlas_px = int(ctx.option("model_atlas_px", ATLAS_PX))
    texel = texel_of(textured, atlas_px)
    trunnion = (0.0, spec.trunnion_y, 0.0)
    cuts = [ChunkCut(part, tuple(name for name, _ in groups[part]), trunnion if part == "pitch" else (0.0, 0.0, 0.0)) for part in PARTS]
    paths, section = write_textured_mesh(out_dir, ASSET_ID, textured, at_texel(style, texel), atlas_px=atlas_px, texel_m=texel,
                                         seed=ctx.seed, occlusion=bool(ctx.option("occlusion", False)), normal_scale=1, chunks=cuts,
                                         grid=False, detail_levels=DETAIL_LEVELS)
    files += paths
    lo, hi = whole.bounds()
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=lo,
        aabb_max=hi,
        centroid_offset=(0.0, 0.0, 0.0),
        files={"obj": OBJ_NAME, "mesh": section["file"]},
        extra={
            "dimensions_m": {"length": round(float(hi[2] - lo[2]), 3), "span": round(float(hi[0] - lo[0]), 3),
                             "height": round(float(hi[1] - lo[1]), 3)},
            "mesh": section,
            "turret": turret_entry(spec, section),
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
