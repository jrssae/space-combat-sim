"""``grid_interceptor_battery``: the station's interceptor battery (M7-T42), an original model after the maintainer's notes on the
show's battery: a truss pedestal with diagonal braces standing on the deck, an inverted-T bracket that turns on it (a base bar and
one central upright with the swivel head on top), and four large barrels with ribbed shrouds in a 2 x 2 rectangle round the head,
a pair above and below on each side, clamped outside the bracket on the ends of the pitch axle (maintainer, after the first sheet).

The maintainer's sizes (2026-11-15): about 15 m tall overall, the pedestal about 8 m, the head and barrels about 10 m wide, the barrels
about 9 m long. Built from primitives, never traced.

Frame (the mount's, as every turret model's, ``parts/turret.py``): the origin at the pedestal's foot on the hull, +Y the mount's up,
the barrels along -Z at rest, +X to the right. Three parts move apart, as ``TurretMount`` turns them:

* ``base``: the pedestal, fixed to the hull;
* ``yaw``: the turntable, the base bar, the upright and its head, turning about +Y through the origin;
* ``pitch``: the axle, the cradles and the barrels, lifting about the axle (the trunnion, parallel to X). Everything that lifts
  lies outside the cradle plates' inner faces (``cradle_x``) but the axle itself, and everything that turns lies inside them, so the
  barrels swing clear of the bracket at any elevation.

Outputs: the textured mesh of the whole battery (``grid_interceptor_battery.glb``, its maps) and one cut per moving part on the same
maps (``grid_interceptor_battery_chunk_<part>.glb``; the pitch cut's origin is the trunnion), the fallback OBJ and the manifest,
whose ``turret`` entry names the parts, the trunnion and the four muzzles (turret frame, and pitch frame for the barrel cadence).
"""

from __future__ import annotations

import dataclasses
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..core.chunks import ChunkCut, chunk_mesh_name
from ..core.civilian import DETAIL_LEVELS, at_texel, r, texel_of
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Material, Mesh, box, lathe, prism, rotation_x, rotation_y, sweep_rect, unit
from ..core.manifest import build_manifest, write_manifest
from ..core.obj import write_obj
from ..core.textured_mesh import TexturedPart, phase_steps, write_textured_mesh
from ..styles import Style
from ..styles.earth_alliance_station import EARTH_ALLIANCE_STATION

ASSET_ID = "grid_interceptor_battery"
GENERATOR_VERSION = 1
OBJ_NAME = f"{ASSET_ID}.obj"
PARTS = ("base", "yaw", "pitch")
# About 900 m² of surface: a 2 048 px atlas keeps it near 3 cm a texel, as the Saturn turret's 1 024 px does at a third the size.
ATLAS_PX = 2048

_Z_TO_Y = rotation_x(-0.5 * math.pi)
_Z_TO_X = rotation_y(0.5 * math.pi)
_SIDE_TO_X = rotation_y(-0.5 * math.pi)  # a side profile drawn in (z, y) laid across x


@dataclass(frozen=True)
class BatterySpec:
    """Sizes in metres, in the mount's frame."""

    pedestal_m: float = 8.0  # the turntable's seat
    foot_m: float = 7.0  # the footing plate's side
    truss_foot_m: float = 5.4  # the corner posts' spread at the foot and under the top deck
    truss_top_m: float = 4.0
    truss_bays: int = 3
    trunnion_y: float = 12.5
    bar_half_m: float = 2.3  # the base bar's half width: inside the cradles, so the barrels swing clear of it
    upright_m: float = 1.8  # the central upright's width and depth
    head_width_m: float = 2.6  # the swivel head on top of the upright
    cradle_x: float = 2.5  # each cradle plate's inner face: everything that lifts lies outside it, save the axle
    barrel_dx: float = 3.9  # each barrel's axis off the centre plane, outside its cradle plate
    barrel_dy: float = 1.4  # and above or below the trunnion
    barrel_m: float = 9.0
    barrel_rear_z: float = 0.6  # behind the trunnion
    barrel_radius: float = 0.84  # the shroud's ribs
    axle_radius: float = 0.55
    top_y: float = 15.0  # the sensor housing's roof
    panel_size_m: float = 1.8  # its own plating: the station's 40 m panels are bigger than the whole battery
    panel_line_m: float = 0.06
    segments: int = 28

    @property
    def muzzle_z(self) -> float:
        return self.barrel_rear_z - self.barrel_m

    def pitch_muzzles(self) -> list[tuple[float, float, float]]:
        """The four muzzles in the pitch frame (origin at the trunnion), in firing order: upper right, lower left, upper left,
        lower right, so each shot comes from the opposite corner of the last."""
        dx, dy, z = self.barrel_dx, self.barrel_dy, self.muzzle_z
        return [(dx, dy, z), (-dx, -dy, z), (-dx, dy, z), (dx, -dy, z)]

    def muzzles(self) -> list[tuple[float, float, float]]:
        """The muzzles in the mount's frame."""
        return [(x, y + self.trunnion_y, z) for x, y, z in self.pitch_muzzles()]


DEFAULT_SPEC = BatterySpec()


def fine_style(spec: BatterySpec) -> Style:
    """The station's paint at the battery's scale: its own small panels and a fighter's wear (``at_texel`` scales it up)."""
    s = EARTH_ALLIANCE_STATION
    finish = dict(s.extra.get("metal_finish", {}))
    finish.update({"panel_m": spec.panel_size_m, "noise_m": 1.5})
    extra = {k: v for k, v in s.extra.items() if k not in ("planar_detail", "wear_scale")}
    extra.update({"metal_finish": finish, "rivets": 0.3})
    return dataclasses.replace(s, panel_size_m=spec.panel_size_m, panel_line_width_m=spec.panel_line_m, groove_depth_m=0.012,
                               hatch_depth_m=0.004, edge_wear_width_m=0.035, grime_scale_m=0.9, extra=extra)


def beam(a: Any, b: Any, w: float, t: float, material: Material) -> Mesh:
    """A square bar from ``a`` to ``b``."""
    a, b = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
    d = unit(b - a)
    hint = np.array([0.0, 1.0, 0.0]) if abs(d[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    return sweep_rect(np.array([a, b]), unit(np.cross(d, hint)), [w, w], [t, t], material)


def _mirror_x(mesh: Mesh) -> Mesh:
    return Mesh.concatenate([mesh, mesh.mirrored("x")])


def _four_way(mesh: Mesh) -> Mesh:
    half = _mirror_x(mesh)
    return Mesh.concatenate([half, half.mirrored("z")])


def pedestal(spec: BatterySpec, style: Style) -> list[tuple[str, Mesh]]:
    """The fixed truss tower: a footing plate, four leaning corner posts tied by ring beams, X braces on every face of every bay,
    a dark machinery core inside, outrigger struts and the bearing ring the turntable sits on."""
    frame, brace, core, steel = style.material("spine"), style.material("machinery"), style.material("recess"), style.material("vane_frame")
    foot_t, deck_t, ring_h = 0.4, 0.3, 0.35
    deck_y = spec.pedestal_m - ring_h - deck_t
    lo, hi = 0.5 * spec.truss_foot_m, 0.5 * spec.truss_top_m

    def corner(y: float) -> float:
        """A post's distance off the centre (x and z) at height ``y``."""
        return lo + (hi - lo) * (y - foot_t) / (deck_y - foot_t)

    meshes = [box((spec.foot_m, foot_t, spec.foot_m), frame, center=(0.0, 0.5 * foot_t, 0.0))]
    meshes.append(_four_way(beam((lo, foot_t, lo), (hi, deck_y, hi), 0.42, 0.42, frame)))
    levels = np.linspace(foot_t + 0.2, deck_y - 0.15, spec.truss_bays + 1)
    for y in levels:
        c = corner(float(y))
        side = beam((-c, y, c), (c, y, c), 0.3, 0.3, frame)
        meshes.append(Mesh.concatenate([side, side.mirrored("z"), side.transformed(rotation_y(0.5 * math.pi)),
                                        side.transformed(rotation_y(-0.5 * math.pi))]))
    for y0, y1 in zip(levels[:-1], levels[1:], strict=True):
        c0, c1 = corner(float(y0)), corner(float(y1))
        face = Mesh.concatenate([beam((-c0, y0, c0), (c1, y1, c1), 0.18, 0.18, brace),
                                 beam((c0, y0, c0), (-c1, y1, c1), 0.18, 0.18, brace)])
        meshes.append(Mesh.concatenate([face, face.mirrored("z"), face.transformed(rotation_y(0.5 * math.pi)),
                                        face.transformed(rotation_y(-0.5 * math.pi))]))
    # Outriggers: struts from the plate's corners up to the posts, the clip's leaning legs.
    out = 0.5 * spec.foot_m - 0.35
    meshes.append(_four_way(beam((out, foot_t, out), (corner(3.6), 3.6, corner(3.6)), 0.24, 0.24, steel)))
    meshes.append(box((spec.truss_top_m + 0.8, deck_t, spec.truss_top_m + 0.8), frame, center=(0.0, deck_y + 0.5 * deck_t, 0.0)))
    ring_r = 0.5 * spec.truss_top_m + 0.1
    ring = lathe([(0.0, 0.0), (0.0, ring_r), (ring_h, ring_r), (ring_h, 0.0)], spec.segments, steel, creases={1, 2})
    meshes.append(ring.transformed(_Z_TO_Y, (0.0, deck_y + deck_t, 0.0)))
    # The machinery core and the blocks hung on it.
    core_h = deck_y - foot_t
    machinery = [box((2.2, core_h, 2.2), core, center=(0.0, foot_t + 0.5 * core_h, 0.0))]
    sides = Mesh.concatenate([box(size, brace, center=(1.1 + 0.5 * size[0], y, z))
                              for y, z, size in ((2.0, 0.3, (0.9, 1.8, 1.4)), (4.6, -0.3, (0.9, 1.4, 1.2)))])
    machinery.append(_mirror_x(sides))
    for sz, y, size in ((1.0, 3.2, (1.6, 2.2, 0.9)), (-1.0, 5.4, (1.4, 1.2, 0.9))):
        machinery.append(box(size, brace, center=(0.0, y, sz * (1.1 + 0.5 * size[2]))))
    return [("pedestal", Mesh.concatenate(meshes)), ("pedestal_core", Mesh.concatenate(machinery))]


def yoke(spec: BatterySpec, style: Style) -> list[tuple[str, Mesh]]:
    """The inverted T that turns: the turntable, a base bar across it, one central upright rising from its middle with braces out to
    the bar's ends, and the swivel head on top of the upright (a boxy body sloping to the front, vents and a sensor housing) that
    carries the pitch axle's bearings."""
    grey, steel, dark, hull = style.material("arm_grey"), style.material("vane_frame"), style.material("machinery"), style.material("hull")
    recess = style.material("recess")
    table_h, bar_h = 0.5, 0.8
    y0 = spec.pedestal_m
    table_r = 0.5 * spec.truss_top_m + 0.4
    table = lathe([(0.0, 0.0), (0.0, table_r - 0.15), (0.15, table_r), (table_h, table_r), (table_h, 0.0)], spec.segments,
                  [steel, steel, grey, grey], creases={1, 2, 3})
    bar_y = y0 + table_h
    bar_top = bar_y + bar_h
    t = spec.trunnion_y
    head = np.array([(2.4, -0.9), (2.4, 1.9), (0.4, 2.25), (-2.2, 1.5), (-3.8, 0.5), (-3.8, -0.5), (-2.0, -0.9)])
    head_bottom = t + float(head[:, 1].min())
    up = spec.upright_m
    roof = spec.top_y - t
    meshes = [table.transformed(_Z_TO_Y, (0.0, y0, 0.0)),
              box((2.0 * spec.bar_half_m, bar_h, 2.4), grey, center=(0.0, bar_y + 0.5 * bar_h, 0.0)),
              box((up, head_bottom - bar_top + 0.1, up), grey, center=(0.0, 0.5 * (head_bottom + bar_top), 0.2))]
    brace = Mesh.concatenate([beam((spec.bar_half_m - 0.25, bar_top, z), (0.5 * up, head_bottom - 0.3, z), 0.3, 0.3, dark)
                              for z in (-0.7, 0.9)])
    collar = lathe([(0.0, 0.0), (0.0, 0.85), (0.25, 0.85), (0.25, 0.0)], spec.segments, steel, creases={1, 2})
    collar = collar.transformed(_Z_TO_X, (0.5 * spec.head_width_m, t, 0.0))
    meshes.append(_mirror_x(Mesh.concatenate([brace, collar])))
    meshes.append(prism([(head, hull)], [(head, hull)], spec.head_width_m).transformed(_SIDE_TO_X, (0.0, t, 0.0)))
    meshes.append(box((1.8, roof - 1.9, 2.4), grey, center=(0.0, t + 0.5 * (roof + 1.9), 1.2)))
    meshes.append(box((1.2, 0.22, 0.1), recess, center=(0.0, t + roof - 0.25, -0.02)))
    # Vents: dark slats laid across the front slope, and a grille on the back.
    (z0, ya), (z1, yb) = head[4], head[3]
    slope = math.atan2(yb - ya, z1 - z0)
    for k in range(4):
        f = 0.15 + 0.2 * k
        meshes.append(box((0.8 * spec.head_width_m, 0.08, 0.3), recess).transformed(
            rotation_x(-slope), (0.0, t + ya + f * (yb - ya) + 0.04, z0 + f * (z1 - z0))))
    for k in range(5):
        meshes.append(box((0.8 * spec.head_width_m, 0.14, 0.08), recess, center=(0.0, t + 0.1 + 0.32 * k, head[0][0] + 0.03)))
    return [("yoke", Mesh.concatenate(meshes[:4])), ("head", Mesh.concatenate(meshes[4:]))]


def barrel(spec: BatterySpec, style: Style) -> Mesh:
    """One barrel along -Z from its breech to the muzzle at the origin: a recessed bore in a lipped muzzle, a ribbed shroud with
    two painted bands near its back, then the narrower breech."""
    rib, between = spec.barrel_radius, spec.barrel_radius - 0.06
    hull, steel, bore = style.material("hull"), style.material("vane_frame"), style.material("recess")
    red, blue = style.material("trim"), style.material("drum_blue")
    # (distance back from the muzzle, radius) along the outside, front to back.
    profile = [(0.4, 0.0), (0.4, 0.5), (0.0, 0.5), (0.0, rib), (0.35, rib), (0.35, between), (1.6, between)]
    mats = [bore, bore, steel, steel, steel, hull]
    d = 1.6
    for _ in range(6):  # the shroud's ribs
        profile += [(d, rib), (d + 0.22, rib), (d + 0.22, between), (d + 0.55, between)]
        mats += [steel, steel, steel, hull]
        d += 0.55
    for band in (red, blue):  # proud of the shroud, so they catch the light
        profile += [(d, rib + 0.02), (d + 0.45, rib + 0.02), (d + 0.45, between), (d + 0.75, between)]
        mats += [band, band, band, hull]
        d += 0.75
    breech = 0.55
    profile += [(d, breech), (spec.barrel_m - 0.3, breech), (spec.barrel_m, 0.38), (spec.barrel_m, 0.0)]
    mats += [hull, steel, steel, steel]
    creases = set(range(1, len(profile) - 1))
    return lathe(profile, spec.segments, mats, creases=creases)


def barrels(spec: BatterySpec, style: Style) -> Mesh:
    """The four barrels in the pitch frame (origin at the trunnion)."""
    one = barrel(spec, style)
    return Mesh.concatenate([one.translated((x, y, z)) for x, y, z in spec.pitch_muzzles()])


def cradles(spec: BatterySpec, style: Style) -> Mesh:
    """What lifts besides the barrels, in the pitch frame: the axle through the head, and on each end a cradle plate with a rail
    and two clamps holding its pair of barrels on the plate's outside."""
    grey, steel = style.material("arm_grey"), style.material("vane_frame")
    sx, x0 = spec.barrel_dx, spec.cradle_x
    span = 2.0 * (spec.barrel_dy + spec.barrel_radius) + 0.12
    x1 = sx + spec.barrel_radius + 0.21  # the clamps' outer face
    plate = box((0.5, span - 0.6, 4.6), grey, center=(x0 + 0.25, 0.0, -1.4))
    rail = box((0.55, 1.1, 7.2), grey, center=(sx, 0.0, -2.6))
    clamps = [box((x1 - x0, span, 0.7), grey, center=(0.5 * (x0 + x1), 0.0, z)) for z in (-0.2, -4.6)]  # the bands between them
    hub = lathe([(0.0, 0.0), (0.0, 0.8), (0.3, 0.8), (0.3, 0.0)], spec.segments, steel, creases={1, 2})
    hub = hub.transformed(_Z_TO_X, (x0 - 0.3, 0.0, 0.0))
    reach = x0 + 0.3
    axle = lathe([(0.0, 0.0), (0.0, spec.axle_radius), (2.0 * reach, spec.axle_radius), (2.0 * reach, 0.0)], spec.segments, steel,
                 creases={1, 2})
    return Mesh.concatenate([axle.transformed(_Z_TO_X, (-reach, 0.0, 0.0)), _mirror_x(Mesh.concatenate([plate, rail, *clamps, hub]))])


def battery_parts(spec: BatterySpec, style: Style) -> dict[str, list[tuple[str, Mesh]]]:
    """Every named mesh by moving part, in the mount's frame."""
    lift = (0.0, spec.trunnion_y, 0.0)
    pitch = [("cradles", cradles(spec, style).translated(lift)), ("barrels", barrels(spec, style).translated(lift))]
    return {"base": pedestal(spec, style), "yaw": yoke(spec, style), "pitch": pitch}


def turret_entry(spec: BatterySpec, section: dict[str, Any]) -> dict[str, Any]:
    """The manifest's ``turret`` entry: the whole mesh, a cut per moving part (the pitch cut's origin at the trunnion), the trunnion
    and the muzzles, in the mount's frame (``muzzles``, as every turret's) and the pitch frame (``pitch_muzzles``)."""
    return {
        "obj": OBJ_NAME,
        "mesh": section,
        "parts": {name: chunk_mesh_name(ASSET_ID, name) for name in PARTS},
        "barrel_m": round(-spec.muzzle_z, 4),
        "trunnion": r((0.0, spec.trunnion_y, 0.0)),
        "muzzles": [r(m) for m in spec.muzzles()],
        "pitch_muzzles": [r(m) for m in spec.pitch_muzzles()],
    }


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the battery into ``ctx.out_dir``. Option: ``model_atlas_px`` (default 2 048)."""
    spec = DEFAULT_SPEC
    style = fine_style(spec)
    out_dir = Path(ctx.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    groups = battery_parts(spec, style)
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
            "dimensions_m": {"height": round(float(hi[1] - lo[1]), 3), "span": round(float(hi[0] - lo[0]), 3),
                             "depth": round(float(hi[2] - lo[2]), 3)},
            "mesh": section,
            "turret": turret_entry(spec, section),
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
