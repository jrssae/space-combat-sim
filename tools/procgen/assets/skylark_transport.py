"""``skylark_transport``: the Earth Alliance "Delta Gamma 9" type transport, 60 m (M5-T13, D59; docs/assets-civilian.md and
docs/design-references.md, "Skylark transport").

Composition only, like ``narn_transport``: the pieces of ``parts/skylark.py`` in the ``ea_civilian`` style with the
Skylark's own paint, and every output (the textured mesh, fallback mesh, hardpoints, chunks, the turret model) derived
from the placed pieces so they agree by construction.

Layout (authored frame, metres, before re-centring; -Z is forward, the nose vanes' tips at z = 0, x and y centred on the
reference model's box, as ``tools/refview`` draws it):

* a capsule 7.46 m across (z 1.7 to 20.5) with a dark nose face, four splayed vanes, a raised bridge plate with a glazed
  front, two red-orange bands and two thin fins under it; behind it the spine and the collar with a ring of vanes at
  each end, and beside them the side tanks (a band each) with a dumbbell tank ahead of each;
* the faceted body (z 32.1 to 51.6), 23.9 m wide, with swept fins at its aft corners, the dorsal fin, the centre
  engine's drum and exhaust cone, and the dorsal turret seated on the body's ridge (Q19, the only turret);
* the nacelles against the body's flanks on a thrust line 0.26 m below the box centre: a ribbed intake, two pods
  pointing up and down outboard, a ribbed dark bell, and two forked claws on short pylons reaching aft to z 60.

The hull is one textured mesh (``core/civilian.py``; Godot's importer builds its levels of detail), each chunk group a cut
of it. The body origin is the visible surface's centroid (right-hand pieces sampled once and mirrored, centre-line pieces
symmetrised, surface buried in another piece left out). The turret (D61) is ``parts/turret.py``'s EA turret at two
thirds of its size, its own textured mesh.
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
from ..parts import skylark as sp
from ..parts.propulsion import pilot_tags
from ..parts.skylark import CENTRE, RIGHT, Piece
from ..parts.turret import write_turret
from ..styles.ea_civilian import ea_civilian

ASSET_ID = "skylark_transport"
GENERATOR_VERSION = 2  # 2: textured meshes (M5-T27)
OBJ_NAME = f"{ASSET_ID}.obj"
HARDPOINTS_NAME = "hardpoints.json"

DEFAULT_SPACING_M = 0.26  # the surface samples' spacing: the body origin and the chunks' offsets
CHUNK_ORDER = ("capsule", "body", "nacelle_l", "nacelle_r")

# Q19's scheme on the ea_civilian style: grey khaki plating (to the captures, 2026-11-04), red-orange bands, dark bells.
SKYLARK_PAINT = {"hull": 0xA9A68E, "hull_panel": 0x7A7659, "hull_dark": 0x4A4839, "stripe": 0xB8452B, "nozzle": 0x4A4A46}
ENGINE_GLOW_SRGB = 0xFFE9C2  # warm white (7Tango7.JPG): the throats' glow and a ShipSpec tint (T16)
# The EA civilian texture pack, its plating finer and more patched, as Transport 1.png shows the Skylark.
STYLE = replace(ea_civilian(SKYLARK_PAINT, ENGINE_GLOW_SRGB), panel_size_m=2.4, panel_line_width_m=0.25, panel_tint_jitter=0.1)

TURRET = sp.TURRET  # the EA turret at two thirds: barrel_m 3.0; the body's seat is sized to its base
TURRET_ARC_DEG = 200.0  # a hemisphere plus 10 degrees below the mount's base

BURIED_MARGIN_M = 0.01
JSON_DIGITS = 5
CHASE_ANCHOR_SHARE = (0.3, 1.2)  # above and behind the centroid, in lengths
NAV_CLEARANCE_M = 0.15
NAV_SIDE_Z = 46.5  # the nacelles' outboard flank between the pods and the bell ribs
NAV_LAMP_HEIGHT_M = 4.0
NAV_LAMP_RANGE_SHARE = 0.3
NAV_CABIN_RANGE_SHARE = 0.05


# --- the visible surface ----------------------------------------------------------------------------------------------------------
def _left(name: str) -> str:
    return name[:-2] + "_l" if name.endswith("_r") else name + "_l"


def mirror_group(group: str) -> str:
    """The chunk of a right piece's left twin: ``nacelle_r`` -> ``nacelle_l``; centre chunks stay."""
    return group[:-2] + "_l" if group.endswith("_r") else group


def with_twins(pieces: list[Piece]) -> list[Piece]:
    """The pieces plus each right piece's mirrored left twin, twin after original."""
    out = []
    for p in pieces:
        out.append(p)
        if p.side == RIGHT:
            out.append(p.mirrored(_left(p.name), mirror_group(p.group)))
    return out


@dataclass
class Sampled:
    piece: Piece
    samples: SurfaceSamples
    spacing: float
    paint_name: str  # the right twin's name: both twins get the same panel phase


def _right_half_first(mesh: Mesh) -> Mesh:
    """The same faces with the right half's first, so systematic rounding gives a centre piece's kept half its exact
    share of samples."""
    right = mesh.face_centroids()[:, 0] > 0.0
    order = np.concatenate([np.flatnonzero(right), np.flatnonzero(~right)])
    return Mesh(mesh.vertices, mesh.faces[order], mesh.face_material[order], mesh.materials)


def sample_hull(pieces: list[Piece], ctx: BuildContext, spacing: float, suffix: tuple[str, ...] = ()) -> list[Sampled]:
    """Every piece of the hull with its visible surface: hidden samples dropped, centre pieces symmetrised, right pieces
    mirrored."""
    solids = [(p.name, p.solid, p.solid.bounds()) for p in with_twins(pieces) if p.solid is not None]
    out: list[Sampled] = []
    for p in pieces:
        step = spacing * p.fine
        mesh = p.part.mesh if p.side == RIGHT else _right_half_first(p.part.mesh)
        s = sample_mesh(mesh, step, ctx.rng("surface", p.name, *suffix), systematic=True)
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
    """The visible surface's centroid (x is zero by symmetry): the authored position of the body origin."""
    total = sum(len(s.samples) for s in sampled)
    mean = sum(s.samples.positions.sum(axis=0) for s in sampled) / total
    return np.array([0.0, float(mean[1]), float(mean[2])])


# --- hardpoints --------------------------------------------------------------------------------------------------------
def _r(v: Any) -> list[float]:
    return [round(float(x), JSON_DIGITS) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


def rcs_ports(by_name: dict[str, Part]) -> list[tuple[str, np.ndarray, np.ndarray]]:
    """Cosmetic RCS (authored frame): the right side's nose vane, nacelle pods and corner fin (``r_`` names, mirrored by
    the caller) and, on the centre line, the top and bottom nose vanes, the dorsal fin's crest and the keel aft."""
    vanes = by_name["vanes"]
    keel_z = 50.5
    keel_y = float(sp.BodySpec().at(keel_z)[8])
    ports = [
        ("r_vane", by_name["vane_r"].anchor("vane")),
        ("r_pod_up", by_name["cone_up_r"].anchor("tip")),
        ("r_pod_down", by_name["cone_down_r"].anchor("tip")),
        ("r_corner", by_name["corner_fin_r"].anchor("tip")),
        ("vane_top", vanes.anchor("vane_top")),
        ("vane_bottom", vanes.anchor("vane_bottom")),
        ("fin_top", by_name["dorsal_fin"].anchor("top")),
    ]
    out = [(name, a.position, a.direction) for name, a in ports]
    out.append(("keel", np.array([0.0, keel_y, keel_z]), np.array([0.0, -1.0, 0.0])))
    return out


def chunk_joints() -> dict[str, np.ndarray]:
    """Where each chunk breaks away (authored frame): the capsule where the collar meets the body, a nacelle along its
    seam with the body's flank, the body at the middle of the three."""
    nacelle = np.array([sp.NACELLE_AXIS[0] - 2.4, sp.NACELLE_AXIS[1], 45.5])
    joints = {
        "capsule": np.array([0.0, sp.CAPSULE_AXIS[1], sp.BodySpec().stations[0][0]]),
        "nacelle_r": nacelle,
        "nacelle_l": nacelle * np.array([-1.0, 1.0, 1.0]),
    }
    joints["body"] = np.mean(list(joints.values()), axis=0)
    return joints


def nav_lights(by_name: dict[str, Part], offset: np.ndarray, length: float) -> dict[str, Any]:
    """Running lights: red and green just outboard of the nacelles' flanks, white on the dorsal fin's crest with a lamp
    standing over it, the cabin glow in the bridge."""
    ax, ay = sp.NACELLE_AXIS
    side = np.array([ax + sp.nacelle_radius(NAV_SIDE_Z) + NAV_CLEARANCE_M, ay, NAV_SIDE_Z])
    crest = by_name["dorsal_fin"].anchor("top").position
    top = crest + np.array([0.0, NAV_CLEARANCE_M, 0.0])
    return {
        "port": _r(side * np.array([-1.0, 1.0, 1.0]) - offset),
        "starboard": _r(side - offset),
        "top": _r(top - offset),
        "top_lamp": _r(crest + np.array([0.0, NAV_LAMP_HEIGHT_M, 0.0]) - offset),
        "top_lamp_range_m": round(NAV_LAMP_RANGE_SHARE * length, 2),
        "cabin": _r(by_name["bridge"].anchor("eye").position - offset),
        "cabin_range_m": round(NAV_CABIN_RANGE_SHARE * length, 2),
    }


def hardpoints(everything: list[Piece], chunks: list[dict[str, Any]], offset: np.ndarray) -> dict[str, Any]:
    """The hardpoints document in the centred frame (authored positions minus ``offset``); ``chunks`` are the
    ``write_chunks`` entries."""
    parts = [p.part for p in everything]
    by_name = {p.name: p for p in parts}
    lo, hi = Mesh.concatenate(p.mesh for p in parts).bounds()
    length = float(hi[2] - lo[2])
    # On the thrust line (the nacelles' axis), so main thrust makes no pitch torque.
    com = np.array([0.0, sp.NACELLE_AXIS[1], float(mass_centroid(parts)[2])])
    inertia = np.zeros(3)
    for part in parts:
        d = part.area_centroid() - com
        inertia += part.mass_kg * np.array([d[1] ** 2 + d[2] ** 2, d[0] ** 2 + d[2] ** 2, d[0] ** 2 + d[1] ** 2])

    pods = []
    for name, side in (("l", "left"), ("r", "right")):
        nacelle = by_name[f"nacelle_{name}"]
        main, retro = nacelle.anchor("main"), nacelle.anchor("retro")
        pods.append({
            "name": name,
            "side": side,
            "center": _r(nacelle.anchor("centre").position - offset),
            "main": {"position": _r(main.position - offset), "exhaust": _r(main.direction), "radius": sp.NACELLE_EXIT_R},
            "retro": {"position": _r(retro.position - offset), "exhaust": _r(retro.direction), "radius": sp.NACELLE_INTAKE_R},
        })  # fmt: skip

    rcs = []
    flip = np.array([-1.0, 1.0, 1.0])
    for name, position, exhaust in rcs_ports(by_name):
        twins = [(name, position, exhaust)]
        if name.startswith("r_"):
            twins.append(("l_" + name[2:], position * flip, exhaust * flip))
        for n, p, e in twins:
            rcs.append({"name": n, "pod": "l" if p[0] < -1e-6 else "r", "position": _r(p - offset), "exhaust": _r(e),
                        "tags": pilot_tags(p, e, com)})  # fmt: skip

    collision = []
    for part in parts:
        for shape in part.collision:
            collision.append({**shape.to_json(offset=offset, digits=JSON_DIGITS), "name": f"{part.name}_{shape.name}" if shape.name else part.name})

    mount = by_name["body"].anchor("turret")
    turrets = [{"name": "dorsal", "position": _r(mount.position - offset), "up": _r(mount.direction), "arc_deg": TURRET_ARC_DEG,
                "barrel_m": round(TURRET.barrel_m, JSON_DIGITS)}]  # fmt: skip
    joints = chunk_joints()
    eye = by_name["bridge"].anchor("eye").position
    return {
        "asset_id": ASSET_ID,
        "generator_version": GENERATOR_VERSION,
        "frame": "godot",
        "units": "m",
        "length_m": round(length, 3),
        "span_m": round(float(hi[0] - lo[0]), 3),
        "height_m": round(float(hi[1] - lo[1]), 3),
        "mass_kg": round(total_mass(parts), 1),
        "inertia_estimate_kg_m2": _r(inertia),
        "center_of_mass": _r(com - offset),
        "cockpit_camera": {"position": _r(eye - offset), "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0]},
        "chase_anchor": {"position": _r((0.0, CHASE_ANCHOR_SHARE[0] * length, CHASE_ANCHOR_SHARE[1] * length))},
        "muzzles": [],
        "pods": pods,
        "rcs": rcs,
        "collision": collision,
        "nav_lights": nav_lights(by_name, offset, length),
        "turrets": turrets,
        "chunks": [{**c, "joint": _r(joints[c["name"]] - offset)} for c in chunks],
    }


# --- build -------------------------------------------------------------------------------------------------------------
def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the ship and its turret into ``ctx.out_dir``.

    Options: ``spacing`` (m, default 0.26; the surface samples' spacing), ``atlas_px`` (the hull's atlas, default 2 048),
    ``model_atlas_px`` (the turret's, default 1 024), ``occlusion`` (default off).
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    if spacing <= 0.0:
        raise ValueError("spacing must be positive")
    style = STYLE
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",)

    pieces = sp.assemble(style)
    everything = with_twins(pieces)
    sampled = sample_hull(pieces, ctx, spacing)
    offset = centre(sampled)
    hull = cv.write_hull(out_dir, ASSET_ID, cv.hull_parts(sampled, offset), CHUNK_ORDER, style, ctx, comments)
    files: list[Path] = list(hull.files)

    turret_files, turret_entry = write_turret(out_dir, ASSET_ID, TURRET, style, ctx, comments)
    files += turret_files

    hp = hardpoints(everything, hull.chunks, offset)
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
