"""``saturn_family``: the Earth Alliance Saturn freighters, five hulls from one set of parts (docs/assets-civilian.md, Q16).

Every Saturn is one lead ship (antenna, command disc, forward truss with its drum frame, engine section; the same size on
every variant) plus cargo. A cargo section is 100 m: a transport section (a banded hull cylinder with four pods on their
arms) or a tank section (three banded tanks). The Saturn 4s carry one section, the Saturn 8s two with a junction
between them, and the Saturn 3 three of the same pods in a stack behind its drum frame. Each variant record holds only
the layout (which cargo, how many sections, trim, turrets, lights); the length follows from the parts.

Outputs per id, as ``raider_fighter`` and ``starfury_aurora``: LOD0-3 PLYs with lighting records, the fallback mesh
(also the depth proxy), break-up chunks cut from LOD1, the style's turret model, ``hardpoints.json`` with ``turrets[]``
and the manifest. All of it is derived from the placed pieces, so splats, meshes and hardpoints agree by construction.
Right-hand pieces are sampled once and mirrored, centre-line pieces are symmetrised, so every level is exactly
mirror-symmetric; samples buried inside another piece are dropped.
"""

from __future__ import annotations

import functools
import json
import re
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..core import frames, lighting
from ..core import civilian as cv
from ..core.chunks import ChunkSource, write_chunks
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh, mirror_matrix
from ..core.manifest import build_manifest, lod_entry, write_manifest
from ..core.obj import write_obj
from ..core.ply import SplatData, write_ply
from ..core.sampling import DEFAULT_OVERLAP, DEFAULT_THICKNESS, SurfaceSamples, sample_mesh, to_splats
from ..parts import Part, mass_centroid, total_mass
from ..parts import saturn as sp
from ..parts.propulsion import pilot_tags
from ..parts.saturn import CENTRE, RIGHT, Piece, PodTrim
from ..parts.turret import TurretSpec, write_turret
from ..styles import Style
from ..styles.ea_civilian import EA_CIVILIAN

GENERATOR_VERSION = 1
HARDPOINTS_NAME = "hardpoints.json"
FAR_LODS = {1: (2.0, "lod1", (0.20, 0.30)), 2: (4.0, "lod2", (0.04, 0.09)), 3: (8.0, "lod3", (0.01, 0.025))}  # factor, stream, share
CHUNK_LOD = 1  # the chunks partition LOD1, as the Starfury's do
JSON_DIGITS = 5
BURIED_MARGIN_M = 0.01

LEAD_FORE_M = 49.3  # the lead ship ahead of the first cargo section
ENGINE_INSET_M = 1.25  # the engine collar starts this far inside the last cylinder's aft dome
NAV_CLEARANCE_M = 0.15
CHASE_UP, CHASE_BACK = 0.3, 1.2  # chase anchor above and behind the centroid, in lengths
CABIN_RANGE = 0.05  # of the length

TURRET = TurretSpec()
TURRET_SPACING_M = 0.12
TURRET_SPLAT_BUDGET = (1_500, 3_500)
TURRET_ARC_DEG = 200.0  # a hemisphere plus 10 degrees below the mount's base
TURRET_PAD_RADIUS = 1.6
UP = (0.0, 1.0, 0.0)
BANDS = ("band_light", "stripe", "band_light", "stripe", "band_light")
TANK_MASS_KG = 6_000_000.0  # a loaded tank; informational, ShipSpec (T16) sets the flight mass


@dataclass(frozen=True)
class Mount:
    """A turret mount (D61) in the authored frame; ``host`` is the chunk its pad belongs to (None: the disc's hub)."""

    name: str
    position: tuple[float, float, float]
    up: tuple[float, float, float]
    host: str | None


LEAD_MOUNTS = (Mount("dorsal_fwd", (0.0, 3.8, 19.1), UP, None),)  # Q19: dorsal mounts only


@dataclass(frozen=True)
class Variant:
    """One hull's layout. ``cargo`` is ``transport``, ``tank`` or ``stack`` (the Saturn 3)."""

    asset_id: str
    cargo: str
    sections: int
    spacing_m: float
    budget: tuple[int, int]
    chunks: tuple[str, ...]
    mounts: tuple[Mount, ...]
    starboard_light: tuple[float, float, float]
    top_light_z: float
    top_lamp: tuple[float, float, float]
    top_lamp_range_m: float
    pod_trim: PodTrim = PodTrim()
    bands: tuple[str, ...] = BANDS
    engine_scale: float = 1.0  # the Saturn 3's slim engine (Q20)

    def section_start(self, k: int) -> float:
        """Where cargo section ``k`` (from 0) starts."""
        return LEAD_FORE_M + k * sp.SECTION_LENGTH

    @property
    def engine_length(self) -> float:
        return self.engine_scale * sp.ENGINE_LENGTH

    @property
    def engine_front_z(self) -> float:
        if self.cargo == "stack":  # Q20: the bell's exit just behind the pods' aft faces
            return sp.STACK_FRONT_Z + sp.POD.width + sp.STACK_EXHAUST_CLEARANCE - self.engine_length
        return self.section_start(self.sections - 1) + sp.CYLINDER_Z[1] - ENGINE_INSET_M

    @property
    def length(self) -> float:
        return self.engine_front_z + self.engine_length


TRANSPORT_TRIM = PodTrim(stripe_role="stripe", hazard_flank=True)
STACK_RIDGE_Z = sp.STACK_FRONT_Z + sp.POD.ridge_u  # the Saturn 3's highest point: the top pod's ridge, short side forward
VARIANTS: dict[str, Variant] = {
    v.asset_id: v
    for v in (
        Variant(
            "saturn_4_transport", "transport", 1, 0.48, (105_000, 155_000), ("bow", "hull", "engine", "pods_l", "pods_r"),
            (*LEAD_MOUNTS, Mount("dorsal_aft", (0.0, 9.3, 124.4), UP, "hull")),
            (53.4, -7.29, 74.3), 75.0, (0.0, 16.6, 99.4), 48.0, TRANSPORT_TRIM,
        ),
        Variant(
            "saturn_4_tanker", "tank", 1, 0.50, (55_000, 85_000), ("bow", "spine", "engine", "tank_l", "tank_r"),
            (*LEAD_MOUNTS, Mount("dorsal_aft", (0.0, 9.3, 124.4), UP, "spine")),
            (25.6, -13.53, 99.4), 75.0, (0.0, 16.6, 99.4), 48.0,
        ),
        Variant(
            "saturn_8_transport", "transport", 2, 0.52, (170_000, 250_000),
            ("bow", "hull_1", "junction", "hull_2", "engine", "pods_1l", "pods_1r", "pods_2l", "pods_2r"),
            (*LEAD_MOUNTS, Mount("dorsal_mid", (0.0, 7.2, 149.4), UP, "junction")),
            (53.4, -7.29, 74.3), 75.0, (0.0, 21.5, 149.4), 78.0, TRANSPORT_TRIM,
        ),
        Variant(
            "saturn_8_tanker", "tank", 2, 0.545, (95_000, 145_000),
            ("bow", "spine_1", "junction", "spine_2", "engine", "tanks_1l", "tanks_1r", "tanks_2l", "tanks_2r"),
            (*LEAD_MOUNTS, Mount("dorsal_mid", (0.0, 9.0, 149.4), UP, "junction")),
            (25.6, -13.53, 99.4), 75.0, (0.0, 21.5, 149.4), 78.0,
        ),
        Variant(
            "saturn_3_freighter", "stack", 0, 0.54, (60_000, 90_000), ("bow", "pod_top", "pod_l", "pod_r", "engine"),
            LEAD_MOUNTS,
            (46.8, -5.46, 79.7), STACK_RIDGE_Z, (0.0, 27.8, 79.7), 36.0, PodTrim(top_paint=0x8E4A3F),
            engine_scale=sp.SLIM_ENGINE_SCALE,
        ),
    )
}


# --- assembly (authored frame) -----------------------------------------------------------------------------------------
def _left(name: str) -> str:
    return name[:-2] + "_l" if name.endswith("_r") else name + "_l"


def mirror_group(group: str) -> str:
    """The chunk of a right piece's left twin: ``pods_r`` -> ``pods_l``, ``tanks_2r`` -> ``tanks_2l``; centre chunks stay."""
    return group[:-1] + "l" if re.fullmatch(r".*_\d?r", group) else group


def _place(pieces: Sequence[Piece], group: str, offset: Sequence[float] = (0.0, 0.0, 0.0), prefix: str = "",
           rotation: np.ndarray | None = None, side: str | None = None) -> list[Piece]:
    """Puts parts' pieces into the ship: moved, named uniquely, assigned to a chunk (and to a side, for a whole
    assembly built on the right)."""
    out = []
    for p in pieces:
        moved = p.transformed(np.eye(3) if rotation is None else rotation, offset)
        s = side or p.side
        name = f"{prefix}{p.name}"
        if s == RIGHT and not name.endswith("_r"):
            name += "_r"
        out.append(Piece(moved.part.renamed(name, group=group), moved.solid, s, moved.fine))
    return out


def lead_ship(v: Variant, style: Style) -> list[Piece]:
    """Antenna, disc, forward truss and drum frame (the ``bow``); for the Saturn 3 also the truss through its stack."""
    pieces = _place(sp.antenna(style), "bow") + _place(sp.command_disc(style), "bow") + _place(sp.drum_frame(style), "bow")
    pieces += _place(sp.forward_frame(style), "bow")
    if v.cargo == "stack":
        # Q16: the Saturn 3 has the shared engine, so a truss runs on through its pod stack to it.
        aft = list(np.linspace(sp.DRUM_FRAME_Z[1] - 0.7, v.engine_front_z - 0.2, 7))
        pieces += _place(sp.truss(aft, style, "truss_aft"), "engine")
        pieces += _place([sp.truss_end_plate(style, v.engine_front_z - 0.2)], "engine")
    else:
        pieces += _place(sp.aft_frame(style), "bow")
    pieces += _place(sp.engine_section(style, v.engine_scale), "engine", (0.0, 0.0, v.engine_front_z))
    return pieces


def _chunk_name(base: str, k: int, sections: int, right: bool = False) -> str:
    """``hull`` / ``hull_1``, ``pods_r`` / ``pods_1r``, ``tank_r`` / ``tanks_1r``."""
    if sections == 1:
        return f"{base}_r" if right else base
    plural = "tanks" if base == "tank" else base
    return f"{plural}_{k + 1}r" if right else f"{base}_{k + 1}"


def cargo(v: Variant, style: Style) -> list[Piece]:
    """The cargo sections (or the Saturn 3's stack) and, between two sections, the junction."""
    pieces: list[Piece] = []
    if v.cargo == "stack":
        pieces += _place(sp.stack_mounts(style), "bow")
        rot = sp.stack_pod_rotation()
        pods = sp.transport_pod(v.pod_trim, style)
        pieces += _place(pods, "pod_top", sp.stack_pod_origin(*sp.TOP_POD_CENTRE), "top_", rot, CENTRE)
        pieces += _place(pods, "pod_r", sp.stack_pod_origin(*sp.LOWER_POD_CENTRE), "low_", rot, RIGHT)
        return pieces
    n = v.sections
    for k in range(n):
        s0 = v.section_start(k)
        tag = f"s{k + 1}_"
        cyl_z = s0 + sp.CYLINDER_Z[0]
        if v.cargo == "transport":
            hull = _chunk_name("hull", k, n)
            pieces += _place([sp.hull_cylinder(v.bands, style)], hull, (0.0, 0.0, cyl_z), tag)
            for i, (z0, z1) in enumerate(sp.ARM_Z):
                pieces += _place(sp.cargo_arm(style, z0, z1), hull, (0.0, 0.0, s0), f"{tag}{i + 1}")
            pod_chunk = _chunk_name("pods", k, n, right=True)
            for i, (z0, _z1) in enumerate(sp.POD_Z):
                at = (sp.POD_INBOARD_X, sp.POD_CENTRE_Y, s0 + z0)
                pieces += _place(sp.transport_pod(v.pod_trim, style), pod_chunk, at, f"{tag}{i + 1}", side=RIGHT)
        else:
            hull = _chunk_name("spine", k, n)
            pieces += _place([sp.hull_cylinder(v.bands, style, "tank", TANK_MASS_KG)], hull, (0.0, 0.0, cyl_z), tag)
            tanks = _chunk_name("tank", k, n, right=True)
            pieces += _place([sp.hull_cylinder(v.bands, style, "tank", TANK_MASS_KG)], tanks, (*sp.LOWER_TANK, cyl_z), tag, side=RIGHT)
            braces = Piece(Part("braces", sp.tank_braces(style), collision=sp.tank_brace_collision(), mass_kg=20_000.0), None, RIGHT)
            pieces += _place([braces], tanks, (0.0, 0.0, s0), tag)
        if k == 0 or v.cargo == "transport":
            pieces += _place([sp.dome_brackets(style)], hull, (0.0, 0.0, cyl_z), f"{tag}front_")
        if k < n - 1 and v.cargo == "transport":
            aft_tip = s0 + sp.CYLINDER_Z[1]
            pieces += _place([sp.dome_brackets(style)], hull, (0.0, 0.0, aft_tip), f"{tag}aft_", mirror_matrix("z"))
    if n == 2:
        aft_tip, front_tip = v.section_start(0) + sp.CYLINDER_Z[1], v.section_start(1) + sp.CYLINDER_Z[0]
        build = sp.transport_junction if v.cargo == "transport" else sp.tanker_junction
        pieces += _place(build(style, 0.5 * (aft_tip + front_tip), aft_tip, front_tip), "junction")
    return pieces


def turret_pads(v: Variant, pieces: Sequence[Piece], style: Style) -> list[Piece]:
    """A pad under every turret that does not stand on the disc's hub, reaching down into whatever it is mounted on."""
    solids = [p.solid for p in with_twins(pieces) if p.solid is not None]
    pads = []
    for m in v.mounts:
        if m.host is None:
            continue
        depth = _seat_depth(np.array(m.position), np.array(m.up), solids) + 0.3
        mesh, solid = sp.turret_pad(m.position, m.up, depth, style, TURRET_PAD_RADIUS)
        pads.append(Piece(Part(f"pad_{m.name}", mesh, mass_kg=5_000.0, group=m.host), solid, CENTRE))
    return pads


def _seat_depth(position: np.ndarray, up: np.ndarray, solids: Sequence[Any]) -> float:
    """How far below a mount (along -up) the hull starts under every point of the pad's rim."""
    side = np.array([1.0, 0.0, 0.0])
    fwd = np.cross(up, side)
    deepest = 0.0
    for offset in (np.zeros(3), side, -side, fwd, -fwd):
        start = position + 0.9 * TURRET_PAD_RADIUS * offset
        for t in np.arange(0.0, 6.0, 0.02):
            p = (start - t * up)[None, :]
            if any(s.contains(p, 0.0)[0] for s in solids):
                deepest = max(deepest, float(t))
                break
        else:
            raise ValueError(f"nothing under the turret mount at {position}")
    return deepest


def assemble(v: Variant, style: Style) -> list[Piece]:
    """Every centre and right piece of the hull, authored frame (left twins come from :func:`with_twins`)."""
    pieces = lead_ship(v, style) + cargo(v, style)
    pieces += turret_pads(v, pieces, style)
    names = [p.name for p in pieces]
    if len(names) != len(set(names)):
        raise ValueError(f"{v.asset_id}: piece names repeat")
    unknown = {p.group for p in with_twins(pieces)} - set(v.chunks)
    if unknown:
        raise ValueError(f"{v.asset_id}: pieces in unlisted chunks {sorted(unknown)}")
    return pieces


def with_twins(pieces: Sequence[Piece]) -> list[Piece]:
    """The pieces plus each right piece's mirrored left twin, twin after original."""
    out = []
    for p in pieces:
        out.append(p)
        if p.side == RIGHT:
            out.append(p.mirrored(_left(p.name), mirror_group(p.group)))
    return out


def chunk_joints(v: Variant) -> dict[str, np.ndarray]:
    """Where each chunk breaks away from the rest (authored frame): the drum frame's back or the first dome, a cylinder's
    middle, the first pod's inboard face, the braces' middle, a Saturn 3 pod's front face, the
    engine collar."""
    joints: dict[str, np.ndarray] = {"engine": np.array([0.0, 0.0, v.engine_front_z])}
    if v.cargo == "stack":
        joints["bow"] = np.array([0.0, 0.0, sp.DRUM_FRAME_Z[1]])
        joints["pod_top"] = np.array([0.0, sp.TOP_POD_CENTRE[1], sp.STACK_FRONT_Z])
        joints["pod_r"] = np.array([sp.LOWER_POD_CENTRE[0], sp.LOWER_POD_CENTRE[1], sp.STACK_FRONT_Z])
    else:
        joints["bow"] = np.array([0.0, 0.0, v.section_start(0) + sp.CYLINDER_Z[0]])
        n = v.sections
        for k in range(n):
            mid = v.section_start(k) + 0.5 * sp.SECTION_LENGTH
            if v.cargo == "transport":
                joints[_chunk_name("hull", k, n)] = np.array([0.0, 0.0, mid])
                first_pod = v.section_start(k) + 0.5 * sum(sp.POD_Z[0])  # on the first pod's inboard face, by its arm
                joints[_chunk_name("pods", k, n, True)] = np.array([sp.POD_INBOARD_X, sp.POD_CENTRE_Y, first_pod])
            else:
                joints[_chunk_name("spine", k, n)] = np.array([0.0, 0.0, mid])
                joints[_chunk_name("tank", k, n, True)] = np.array([0.5 * sp.LOWER_TANK[0], 0.5 * sp.LOWER_TANK[1], mid])
        if n == 2:
            joints["junction"] = np.array([0.0, 0.0, 0.5 * (v.section_start(0) + sp.CYLINDER_Z[1] + v.section_start(1) + sp.CYLINDER_Z[0])])
    for name in list(joints):
        twin = mirror_group(name)
        if twin != name:
            joints[twin] = joints[name] * np.array([-1.0, 1.0, 1.0])
    return joints


# --- sampling -------------------------------------------------------------------------------------------------------------
@dataclass
class Sampled:
    piece: Piece
    samples: SurfaceSamples
    spacing: float
    paint_name: str  # the right twin's name: both twins get the same panel pattern


def _right_half_first(mesh: Mesh) -> Mesh:
    """The same faces with the right half's first: systematic rounding then gives the half a centre piece keeps (and
    mirrors) its exact share of samples, so a coarse level keeps LOD0's centroid."""
    right = mesh.face_centroids()[:, 0] > 0.0
    order = np.concatenate([np.flatnonzero(right), np.flatnonzero(~right)])
    return Mesh(mesh.vertices, mesh.faces[order], mesh.face_material[order], mesh.materials)


def sample_hull(pieces: Sequence[Piece], ctx: BuildContext, spacing: float, suffix: tuple[str, ...] = ()) -> list[Sampled]:
    """Samples every centre and right piece, drops what other pieces hide, symmetrises the centre ones and mirrors the
    right ones; returns every piece of the hull with its samples, in assembly order."""
    everything = with_twins(pieces)
    solids = [(p.name, p.solid, p.solid.bounds()) for p in everything if p.solid is not None]
    out: list[Sampled] = []
    for p in pieces:
        step = spacing * p.fine
        mesh = p.part.mesh if p.side == RIGHT else _right_half_first(p.part.mesh)
        s = sample_mesh(mesh, step, ctx.rng("splats", p.name, *suffix), systematic=True)
        if len(s):
            lo, hi = s.positions.min(axis=0), s.positions.max(axis=0)
            hidden = np.zeros(len(s), dtype=bool)
            for name, solid, (slo, shi) in solids:
                if name == p.name or np.any(shi < lo) or np.any(slo > hi):
                    continue
                hidden |= solid.contains(s.positions, BURIED_MARGIN_M)
            s = s.subset(~hidden)
        if p.side == CENTRE:
            out.append(Sampled(p, s.symmetrized("x"), step, p.name))
        else:
            out.append(Sampled(p, s, step, p.name))
            out.append(Sampled(p.mirrored(_left(p.name), mirror_group(p.group)), s.mirrored("x"), step, p.name))
    return out


def centre(sampled: list[Sampled]) -> np.ndarray:
    """The splat centroid (x is zero by symmetry): the authored position of the body origin."""
    total = sum(len(s.samples) for s in sampled)
    mean = sum(s.samples.positions.sum(axis=0) for s in sampled) / total
    return np.array([0.0, float(mean[1]), float(mean[2])])


def _phase(name: str, style: Style) -> tuple[float, float, float]:
    h = sum((i + 1) * ord(c) for i, c in enumerate(name))
    return tuple(((h * k) % 97) / 97.0 * style.panel_size_m for k in (7, 11, 13))


def splats_of(s: Sampled, style: Style, offset: np.ndarray, overlap: float, thickness: float) -> SplatData:
    """Paint (panel lines mirrored across the centre line) and flat splats, moved into the centred frame."""
    smp = s.samples.translated(-offset)
    painted_at = s.samples.positions.copy()
    painted_at[:, 0] = np.abs(painted_at[:, 0])
    rgb = style.shade_panels(smp.albedo(), painted_at, smp.normals, smp.material_flag("paneled") > 0.5, _phase(s.paint_name, style))
    return to_splats(smp, rgb, s.spacing, overlap, thickness)


def chunked(sampled: list[Sampled], v: Variant, style: Style, offset: np.ndarray, overlap: float, thickness: float) -> list[ChunkSource]:
    """One source per chunk, in the variant's chunk order: its pieces' splats and fallback mesh, centred frame."""
    sources = []
    for chunk in v.chunks:
        members = [s for s in sampled if s.piece.group == chunk]
        splats = SplatData.concatenate([splats_of(s, style, offset, overlap, thickness) for s in members])
        mesh = Mesh.concatenate(s.piece.part.mesh.translated(-offset) for s in members)
        sources.append(ChunkSource(chunk, splats, mesh))
    return sources


# --- hardpoints -------------------------------------------------------------------------------------------------------------
def _r(v: Any) -> list[float]:
    return [round(float(x), JSON_DIGITS) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


def rcs_ports(v: Variant) -> list[tuple[str, np.ndarray, np.ndarray]]:
    """Cosmetic RCS (authored frame): both ends of the two lower drums and the top drum's aft end (its front is behind the
    crossed plates), the disc's flanks, four on the engine collar."""
    z0, z1 = sp.DRUM_FRAME_Z
    ports = []
    for name, (x, y) in (("drum_top", sp.TOP_DRUM), ("drum_low_r", sp.LOWER_DRUM), ("drum_low_l", (-sp.LOWER_DRUM[0], sp.LOWER_DRUM[1]))):
        if name != "drum_top":
            ports.append((f"{name}_fwd", np.array([x, y, z0]), np.array([0.0, 0.0, -1.0])))
        ports.append((f"{name}_aft", np.array([x, y, z1]), np.array([0.0, 0.0, 1.0])))
    for name, sx in (("disc_r", 1.0), ("disc_l", -1.0)):
        ports.append((name, np.array([sx * sp.DISC_RADIUS, 0.0, 19.06]), np.array([sx, 0.0, 0.0])))
    z = v.engine_front_z + v.engine_scale * sp.ENGINE_RCS_Z
    r = v.engine_scale * sp.ENGINE_RCS_RADIUS
    for name, d in (("collar_r", (1.0, 0.0)), ("collar_l", (-1.0, 0.0)), ("collar_top", (0.0, 1.0)), ("collar_bottom", (0.0, -1.0))):
        ports.append((name, np.array([r * d[0], r * d[1], z]), np.array([d[0], d[1], 0.0])))
    return ports


def hull_top(everything: Sequence[Piece], z: float) -> float:
    """The highest point of the hull on the centre line at ``z`` (authored frame)."""
    ys = np.arange(40.0, -40.0, -0.005)
    probe = np.column_stack([np.zeros_like(ys), ys, np.full_like(ys, z)])
    inside = np.zeros(len(ys), dtype=bool)
    for p in everything:
        if p.solid is not None:
            inside |= p.solid.contains(probe, 0.0)
    if not inside.any():
        raise ValueError(f"no hull on the centre line at z {z}")
    return float(ys[np.argmax(inside)])


def nav_lights(v: Variant, everything: Sequence[Piece], offset: np.ndarray) -> dict[str, Any]:
    """Running lights: red and green at the widest points, white on the highest point at ``top_light_z`` with the lamp
    standing over it, the cabin glow on the bridge."""
    starboard = np.array(v.starboard_light)
    top_y = hull_top(everything, v.top_light_z) + NAV_CLEARANCE_M
    return {
        "port": _r(starboard * np.array([-1.0, 1.0, 1.0]) - offset),
        "starboard": _r(starboard - offset),
        "top": _r(np.array([0.0, top_y, v.top_light_z]) - offset),
        "top_lamp": _r(np.array(v.top_lamp) - offset),
        "top_lamp_range_m": v.top_lamp_range_m,
        "cabin": _r(np.array(sp.COCKPIT_EYE) - offset),
        "cabin_range_m": round(CABIN_RANGE * v.length, 3),
    }


def hardpoints(v: Variant, everything: list[Piece], chunks: list[dict[str, Any]], offset: np.ndarray) -> dict[str, Any]:
    """The hardpoints document in the centred frame (authored positions minus ``offset``)."""
    parts = [p.part for p in everything]
    hull_mesh = Mesh.concatenate(p.mesh for p in parts)
    lo, hi = hull_mesh.bounds()
    com = np.array([0.0, 0.0, float(mass_centroid(parts)[2])])  # trimmed onto the spine axis: the thrust line
    mass = total_mass(parts)
    inertia = np.zeros(3)
    for part in parts:
        d = part.area_centroid() - com
        inertia += part.mass_kg * np.array([d[1] ** 2 + d[2] ** 2, d[0] ** 2 + d[2] ** 2, d[0] ** 2 + d[1] ** 2])
    com_c = com - offset
    length = v.length

    pods = []
    for name, side, sx in (("l", "left", -1.0), ("r", "right", 1.0)):
        main = np.array([sx * 0.95 * v.engine_scale, 0.0, length])
        retro = np.array([sx * sp.RETRO_EXIT[0], sp.RETRO_EXIT[1], sp.RETRO_EXIT[2]])
        pods.append({
            "name": name,
            "side": side,
            "center": _r(0.5 * (main + retro) - offset),
            "main": {"position": _r(main - offset), "exhaust": [0.0, 0.0, 1.0], "radius": round(sp.MAIN_RADIUS * v.engine_scale, 5)},
            "retro": {"position": _r(retro - offset), "exhaust": [0.0, 0.0, -1.0], "radius": sp.RETRO_RADIUS},
        })
    rcs = [
        {"name": name, "pod": "l" if pos[0] < 0.0 else "r", "position": _r(pos - offset), "exhaust": _r(ex),
         "tags": pilot_tags(pos, ex, com)}
        for name, pos, ex in rcs_ports(v)
    ]
    collision = []
    for part in parts:
        for shape in part.collision:
            collision.append({**shape.to_json(offset=offset, digits=JSON_DIGITS), "name": f"{part.name}_{shape.name}" if shape.name else part.name})
    turrets = [
        {"name": m.name, "position": _r(np.array(m.position) - offset), "up": _r(m.up), "arc_deg": TURRET_ARC_DEG, "barrel_m": TURRET.barrel_m}
        for m in v.mounts
    ]
    return {
        "asset_id": v.asset_id,
        "generator_version": GENERATOR_VERSION,
        "frame": "godot",
        "units": "m",
        "length_m": round(float(hi[2] - lo[2]), 3),
        "span_m": round(float(hi[0] - lo[0]), 3),
        "height_m": round(float(hi[1] - lo[1]), 3),
        "mass_kg": round(mass, 1),
        "inertia_estimate_kg_m2": _r(inertia),
        "center_of_mass": _r(com_c),
        "cockpit_camera": {"position": _r(np.array(sp.COCKPIT_EYE) - offset), "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0]},
        "chase_anchor": {"position": _r((0.0, CHASE_UP * length, CHASE_BACK * length))},
        "muzzles": [],
        "pods": pods,
        "rcs": rcs,
        "collision": collision,
        "nav_lights": nav_lights(v, everything, offset),
        "turrets": turrets,
        "chunks": chunks,
    }


# --- build -----------------------------------------------------------------------------------------------------------------
def _to_3dgs(splats: SplatData) -> SplatData:
    """Rz(180 deg) of the Godot frame: what the PLY stores, so the splat node stays at identity."""
    return SplatData(
        xyz=frames.godot_to_3dgs_positions(splats.xyz), rgb=splats.rgb, alpha=splats.alpha, scale=splats.scale,
        rot=frames.godot_to_3dgs_quats(splats.rot), normals=frames.flip_xy(splats.normals),
    )


def lod_file(asset_id: str, level: int) -> str:
    return f"{asset_id}.ply" if level == 0 else f"{asset_id}_lod{level}.ply"


def build_variant(asset_id: str, ctx: BuildContext) -> AssetOutputs:
    """Generate one Saturn into ``ctx.out_dir``.

    Options: ``spacing`` (m; the variant's default sits its LOD0 in its budget), ``overlap`` (sigma / spacing, default
    1.0), ``thickness`` (normal sigma / spacing, default 0.08).
    """
    v = VARIANTS[asset_id]
    spacing = float(ctx.option("spacing", v.spacing_m))
    overlap = float(ctx.option("overlap", DEFAULT_OVERLAP))
    thickness = float(ctx.option("thickness", DEFAULT_THICKNESS))
    if min(spacing, overlap, thickness) <= 0.0:
        raise ValueError("spacing, overlap and thickness must be positive")
    style = EA_CIVILIAN
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{asset_id} generator v{GENERATOR_VERSION} seed {ctx.seed}", "frame: 3dgs (Rz180 of godot)")

    pieces = assemble(v, style)
    everything = with_twins(pieces)
    files: list[Path] = []
    counts: dict[str, int] = {}
    levels: dict[int, tuple[int, float]] = {}

    # LOD0: the chunk groups concatenated (manifest ``counts`` order).
    lod0 = sample_hull(pieces, ctx, spacing)
    offset = centre(lod0)
    sources0 = chunked(lod0, v, style, offset, overlap, thickness)
    authored = SplatData.concatenate([c.splats for c in sources0])
    counts = {c.name: len(c.splats) for c in sources0}
    xyz32 = authored.xyz.astype(np.float32)
    aabb_min, aabb_max = xyz32.min(axis=0), xyz32.max(axis=0)
    written = _to_3dgs(authored)
    files += [write_ply(out_dir / lod_file(asset_id, 0), written, comments),
              lighting.write_lighting(out_dir / lighting.lod_file_name(asset_id, 0), written)]
    levels[0] = (len(authored), spacing)
    hull_mesh = Mesh.concatenate(p.part.mesh.translated(-offset) for p in everything)
    files += write_obj(out_dir / f"{asset_id}.obj", hull_mesh, asset_id, comments[:1])
    # The painted mesh: the ship as the game draws it from the 2026-11-04 directive (meshes, not splats).
    mesh_path, mesh_entry = cv.write_mesh(out_dir, asset_id, [(s.paint_name, s.piece.part.mesh.translated(-offset)) for s in lod0], style)
    files.append(mesh_path)

    # LOD1-3 from their own streams, each centred on its own centroid; the chunks are LOD1's, written chunk by chunk.
    chunk_entries: list[dict[str, Any]] = []
    for level, (factor, stream, _share) in FAR_LODS.items():
        sampled = sample_hull(pieces, ctx, factor * spacing, (stream,))
        lod_offset = centre(sampled)
        sources = chunked(sampled, v, style, lod_offset, overlap, thickness)
        splats = SplatData.concatenate([c.splats for c in sources])
        level_comments = comments + (f"lod {level}",)
        written = _to_3dgs(splats)
        files += [write_ply(out_dir / lod_file(asset_id, level), written, level_comments),
                  lighting.write_lighting(out_dir / lighting.lod_file_name(asset_id, level), written)]
        levels[level] = (len(splats), factor * spacing)
        if level == CHUNK_LOD:
            chunk_files, chunk_entries = write_chunks(out_dir, asset_id, sources, level_comments)
            files += chunk_files
    joints = chunk_joints(v)
    chunk_entries = [{**c, "joint": _r(joints[c["name"]] - offset)} for c in chunk_entries]

    turret_files, turret_entry = write_turret(out_dir, asset_id, TURRET, style, ctx, TURRET_SPACING_M, overlap, thickness, comments)
    files += turret_files

    hp = hardpoints(v, everything, chunk_entries, offset)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    total = levels[0][0]
    warnings: list[str] = []
    if abs(spacing - v.spacing_m) < 1e-12:
        if not v.budget[0] <= total <= v.budget[1]:
            warnings.append(f"{total} splats is outside the budget {v.budget} at the default spacing")
        for level, (_factor, _stream, bounds) in FAR_LODS.items():
            share = levels[level][0] / total
            if not bounds[0] <= share <= bounds[1]:
                warnings.append(f"LOD{level} has {share:.1%} of LOD0's splats, outside {bounds}")
    if not TURRET_SPLAT_BUDGET[0] <= turret_entry["splats"] <= TURRET_SPLAT_BUDGET[1]:
        warnings.append(f"the turret has {turret_entry['splats']} splats, outside {TURRET_SPLAT_BUDGET}")
    manifest = build_manifest(
        asset_id=asset_id,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        lods=[lod_entry(level, lod_file(asset_id, level), n, s, lighting.lod_file_name(asset_id, level)) for level, (n, s) in sorted(levels.items())],
        aabb_min=aabb_min,
        aabb_max=aabb_max,
        centroid_offset=offset,
        files={"fallback_mesh": f"{asset_id}.obj", "paint_mesh": mesh_entry["file"], "hardpoints": HARDPOINTS_NAME},
        extra={
            "paint_mesh": mesh_entry,
            "counts": counts,
            "chunks": [c["name"] for c in chunk_entries],
            "chunk_lod": CHUNK_LOD,
            "sampling": {"spacing_m": spacing, "overlap": overlap, "thickness": thickness},
            "dimensions_m": {"length": hp["length_m"], "span": hp["span_m"], "height": hp["height_m"]},
            "turret": turret_entry,
            "variant": {"cargo": v.cargo, "sections": v.sections},
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(asset_id, out_dir, manifest, tuple(files), tuple(warnings))


BUILDERS: dict[str, Callable[[BuildContext], AssetOutputs]] = {
    asset_id: functools.partial(build_variant, asset_id) for asset_id in VARIANTS
}
