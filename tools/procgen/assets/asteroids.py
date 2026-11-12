"""``asteroids``: rock shapes for sparse belts (M5-T29, D63, Q38).

Every shape starts as a finely faceted ball whose radius, direction by direction, comes from one of twelve kinds: a lumpy
potato, a fragment broken off a larger body (flat fracture planes with sharp edges), a peanut of two fused lobes, a long cut
shard, a blocky polyhedral boulder, a flat slab, a near-sphere ruled by big craters, a rubble pile of three or four lobes, a
half rock split by one huge plane, a bent banana, a tapered spindle and a rock pitted all over with small craters. Layered
noise roughens each one, craters are pressed in, and a bend or taper may follow. It is written as M4's textured mesh
(``core/textured_mesh.py``): a coarse render mesh whose normal map carries a fine mesh's detail, painted in greys and browns
per shape, darker regolith in the craters and fresher, lighter rock on fracture faces. Godot's importer builds the levels.

Shapes are authored at about ``AUTHOR_RADIUS_M`` so the fine mesh's detail is closer than the normal map's transfer reach; the
game scales each rock to its own size. The manifest lists every shape's kind, file, bounding radius and collision spheres:
one for a round rock, two or three along a long one, so a peanut or a shard collides as it looks.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np

from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Material, Mesh
from ..core.manifest import build_manifest, write_manifest
from ..core.textured_mesh import TexturedPart, write_textured_mesh
from ..core.textures import value_noise
from ..styles import REQUIRED_ROLES, Style

ASSET_ID = "asteroids"
GENERATOR_VERSION = 3  # 3: a deeper peanut waist; 2: twelve kinds of rock (fragments, peanuts, shards ...); 1: lumpy potatoes only
KINDS: tuple[str, ...] = ("potato", "fragment", "peanut", "shard", "boulder", "slab", "cratered", "rubble", "half", "banana",
                          "spindle", "pitted")
SHAPE_COUNT = 16  # every kind once, then the first four again with other draws
AUTHOR_RADIUS_M = 4.0
FINE_LEVEL = 6  # 81 920 triangles: the detail the normal map carries
RENDER_LEVEL = 4  # 5 120 triangles: what is drawn up close; the importer's levels take over further out
ATLAS_PX = 1024
TEXEL_M = 0.018
JSON_DIGITS = 5

# Rock colours (linear RGB): a grey, a warm brown and a cold dark grey family; each shape picks one and varies it.
ROCK_FAMILIES: tuple[tuple[float, float, float], ...] = ((0.085, 0.081, 0.076), (0.098, 0.076, 0.058), (0.060, 0.062, 0.066))


@dataclass(frozen=True)
class Craters:
    """How many craters, their angular radius range (radians) and depth range (share of the radius)."""

    count: int
    radius: tuple[float, float] = (0.18, 0.45)
    depth: tuple[float, float] = (0.04, 0.09)


@dataclass(frozen=True)
class RockSpec:
    """One shape. ``lobes`` (centre, radius) replace the ellipsoid when given; ``cuts`` (unit normal, distance) are fracture
    planes that clip it; ``bend`` and ``taper`` deform the finished rock along its long axis (x)."""

    kind: str
    axes: tuple[float, float, float]
    roughness_amp: float
    craters: Craters
    colour: tuple[float, float, float]
    lobes: tuple[tuple[tuple[float, float, float], float], ...] = ()
    cuts: tuple[tuple[tuple[float, float, float], float], ...] = ()
    bend: float = 0.0
    taper: float = 0.0
    extra: dict[str, float] = field(default_factory=dict)


def icosphere(level: int) -> tuple[np.ndarray, np.ndarray]:
    """Unit vertices and outward faces of an icosahedron subdivided ``level`` times."""
    t = (1.0 + np.sqrt(5.0)) / 2.0
    v = np.array([[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
                  [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]], dtype=float)
    f = np.array([[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6],
                  [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10],
                  [8, 6, 7], [9, 8, 1]], dtype=np.int64)
    v /= np.linalg.norm(v, axis=1, keepdims=True)
    for _ in range(level):
        edges = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), axis=1)
        unique, inverse = np.unique(edges, axis=0, return_inverse=True)
        mid = v[unique[:, 0]] + v[unique[:, 1]]
        mid /= np.linalg.norm(mid, axis=1, keepdims=True)
        m = inverse.reshape(3, -1).T + len(v)  # midpoints of edges (a,b), (b,c), (c,a) per face
        a, b, c = f[:, 0], f[:, 1], f[:, 2]
        ab, bc, ca = m[:, 0], m[:, 1], m[:, 2]
        f = np.concatenate([np.stack([a, ab, ca], 1), np.stack([b, bc, ab], 1), np.stack([c, ca, bc], 1), np.stack([ab, bc, ca], 1)])
        v = np.concatenate([v, mid])
    return v, f


def _unit(rng: np.random.Generator, bias: tuple[float, float, float] = (1.0, 1.0, 1.0)) -> tuple[float, float, float]:
    n = rng.normal(size=3) * np.asarray(bias)
    n /= np.linalg.norm(n)
    return tuple(float(x) for x in n)


def spec_for(index: int, seed: int) -> RockSpec:
    """Shape ``index``'s kind and parameters, drawn from the build seed."""
    kind = KINDS[index % len(KINDS)]
    rng = np.random.default_rng([seed, 7_919, index])
    family = np.asarray(ROCK_FAMILIES[index % len(ROCK_FAMILIES)])
    colour = tuple(float(c) for c in family * rng.uniform(0.85, 1.15) * rng.uniform(0.95, 1.05, 3))
    u = rng.uniform

    def cuts(n: int, dist: tuple[float, float], bias: tuple[float, float, float] = (1.0, 1.0, 1.0)) -> tuple:
        return tuple((_unit(rng, bias), float(u(*dist))) for _ in range(n))

    if kind == "potato":
        return RockSpec(kind, (1.0, u(0.78, 0.95), u(0.68, 0.88)), u(0.10, 0.18), Craters(int(rng.integers(3, 9))), colour)
    if kind == "fragment":
        main = cuts(int(rng.integers(4, 7)), (0.38, 0.62))  # the breaks that freed it from its parent
        chips = cuts(int(rng.integers(6, 11)), (0.55, 0.75))  # smaller flakes knocked off its edges
        return RockSpec(kind, (1.0, u(0.75, 0.9), u(0.65, 0.85)), u(0.05, 0.08), Craters(int(rng.integers(0, 2))), colour,
                        cuts=main + chips)
    if kind == "peanut":
        small = u(0.46, 0.58)
        return RockSpec(kind, (1.0, u(0.85, 1.0), u(0.8, 0.95)), u(0.07, 0.10), Craters(int(rng.integers(1, 4))), colour,
                        lobes=(((0.52, 0.0, 0.0), 0.62), ((-0.55, u(-0.06, 0.06), u(-0.06, 0.06)), small)))
    if kind == "shard":
        sides = cuts(int(rng.integers(5, 8)), (0.17, 0.24), (0.05, 1.0, 1.0))  # long faces along the shard
        tips = tuple((((1.0 if k == 0 else -1.0) * float(u(0.85, 1.0)), float(u(-0.5, 0.5)), float(u(-0.5, 0.5))), float(u(0.8, 0.95)))
                     for k in range(2))  # its two broken ends, slanted
        tips = tuple((tuple(float(x) for x in np.asarray(n) / np.linalg.norm(n)), d) for n, d in tips)
        return RockSpec(kind, (1.0, u(0.26, 0.32), u(0.2, 0.25)), u(0.03, 0.05), Craters(0), colour, cuts=sides + tips)
    if kind == "boulder":
        return RockSpec(kind, (1.0, u(0.82, 0.92), u(0.75, 0.88)), u(0.04, 0.07), Craters(1), colour,
                        cuts=cuts(int(rng.integers(9, 15)), (0.62, 0.8)))
    if kind == "slab":
        return RockSpec(kind, (1.0, u(0.32, 0.4), u(0.8, 0.92)), u(0.08, 0.12), Craters(int(rng.integers(2, 5))), colour,
                        cuts=cuts(2, (0.26, 0.34), (0.2, 1.0, 0.2)))
    if kind == "cratered":
        return RockSpec(kind, (1.0, u(0.9, 0.96), u(0.86, 0.94)), u(0.05, 0.07),
                        Craters(int(rng.integers(4, 7)), (0.35, 0.7), (0.08, 0.14)), colour)
    if kind == "rubble":
        lobes = tuple((tuple(float(x) for x in np.asarray(_unit(rng)) * u(0.3, 0.48)), float(u(0.42, 0.56)))
                      for _ in range(int(rng.integers(3, 5))))
        return RockSpec(kind, (1.0, 1.0, 1.0), u(0.08, 0.12), Craters(int(rng.integers(1, 3))), colour, lobes=lobes)
    if kind == "half":
        return RockSpec(kind, (1.0, u(0.8, 0.95), u(0.75, 0.9)), u(0.10, 0.15), Craters(int(rng.integers(2, 5))), colour,
                        cuts=cuts(1, (0.08, 0.25)))
    if kind == "banana":
        return RockSpec(kind, (1.0, u(0.42, 0.52), u(0.38, 0.48)), u(0.08, 0.12), Craters(int(rng.integers(2, 5))), colour,
                        bend=float(u(0.25, 0.4)))
    if kind == "spindle":
        return RockSpec(kind, (1.0, u(0.38, 0.45), u(0.35, 0.42)), u(0.06, 0.09), Craters(int(rng.integers(1, 3))), colour,
                        taper=float(u(0.45, 0.65)))
    return RockSpec(kind, (1.0, u(0.85, 0.92), u(0.78, 0.88)), u(0.07, 0.09),  # pitted
                    Craters(int(rng.integers(14, 23)), (0.06, 0.14), (0.03, 0.05)), colour)


def _lobe_radius(directions: np.ndarray, lobes: tuple) -> np.ndarray:
    """Distance from the centre to the outer surface of fused spheres along each direction, blended so the necks fill."""
    hits = []
    for centre, radius in lobes:
        c = np.asarray(centre)
        b = directions @ c
        disc = b * b - (c @ c - radius * radius)
        hits.append(np.where(disc > 0.0, b + np.sqrt(np.maximum(disc, 0.0)), 0.0))
    stack = np.stack(hits)
    k = 7.0  # a soft maximum: the lobes melt into each other at the neck instead of meeting in a crease
    return np.log(np.exp(k * stack).sum(axis=0)) / k


def surface_radius(directions: np.ndarray, spec: RockSpec, seed: int, index: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """The rock's radius along each unit direction (unitless, about 1), how deep in a crater each one lies (0..1) and whether
    it lies on a fracture face."""
    rng = np.random.default_rng([seed, 104_729, index])
    if spec.lobes:
        r = _lobe_radius(directions, spec.lobes)
    else:
        r = 1.0 / np.sqrt(((directions / np.asarray(spec.axes)) ** 2).sum(axis=1))
    for octave in range(5):
        freq = 1.6 * 2.0 ** octave
        r = r * (1.0 + spec.roughness_amp * 0.55 ** octave * (2.0 * value_noise(directions * freq, 1.0, seed * 31 + index * 7 + octave) - 1.0))
    floor = np.zeros(len(directions))
    for _ in range(spec.craters.count):
        centre = np.asarray(_unit(rng))
        radius = float(rng.uniform(*spec.craters.radius))
        depth = float(rng.uniform(*spec.craters.depth))
        angle = np.arccos(np.clip(directions @ centre, -1.0, 1.0))
        inside = np.clip(1.0 - (angle / radius) ** 2, 0.0, 1.0)
        rim = np.exp(-(((angle - radius) / (0.25 * radius)) ** 2))
        r = r * (1.0 - depth * inside + 0.35 * depth * rim)
        floor = np.maximum(floor, inside)
    fractured = np.zeros(len(directions), dtype=bool)
    for normal, distance in spec.cuts:
        facing = directions @ np.asarray(normal)
        limit = np.where(facing > 1e-6, distance / np.maximum(facing, 1e-6), np.inf)
        # A fracture face is fresh, rougher only at a fine scale.
        limit = limit * (1.0 + 0.012 * (2.0 * value_noise(directions * 9.0, 1.0, seed + 811 + index) - 1.0))
        cut = limit < r
        r = np.where(cut, limit, r)
        fractured |= cut
        floor = np.where(cut, 0.0, floor)
    return r, floor, fractured


def _deform(p: np.ndarray, spec: RockSpec) -> np.ndarray:
    """The bend and the taper along the long axis (x): a banana's arc, a spindle's thinning ends."""
    out = p.copy()
    half = max(float(np.abs(p[:, 0]).max()), 1e-9)
    s = p[:, 0] / half
    if spec.taper > 0.0:
        out[:, 1:] *= (1.0 - spec.taper * s * s)[:, None]
    if spec.bend > 0.0:
        out[:, 1] += spec.bend * half * (s * s - 0.33)
    return out


def rock_mesh(level: int, spec: RockSpec, seed: int, index: int, materials: tuple[Material, Material, Material],
              finish: bool = True) -> Mesh:
    """The rock at one subdivision ``level``, in metres. With ``finish`` the bend and taper are applied and it is centred on its
    mean vertex; without, it is the plain radial rock (every face seen from its centre, for the tests)."""
    directions, faces = icosphere(level)
    r, floor, fractured = surface_radius(directions, spec, seed, index)
    vertices = directions * r[:, None] * AUTHOR_RADIUS_M
    if finish:
        vertices = _deform(vertices, spec)
        vertices = vertices - vertices.mean(axis=0)
    face_floor = floor[faces].mean(axis=1)
    face_fracture = fractured[faces].all(axis=1)
    face_material = np.where(face_floor > 0.55, 2, np.where(face_fracture, 1, 0)).astype(np.int64)
    return Mesh(vertices, faces, face_material, materials)


def rock_materials(spec: RockSpec) -> tuple[Material, Material, Material]:
    """The base rock, a lighter patch (and fresh fracture faces) and the dark regolith of crater floors; matte, never metal."""
    base = np.asarray(spec.colour)
    return (Material("rock", tuple(float(c) for c in base), roughness=0.92),
            Material("rock_light", tuple(float(c) for c in base * 1.2), roughness=0.85),
            Material("rock_floor", tuple(float(c) for c in base * 0.75), roughness=0.97))


def rock_style(materials: tuple[Material, Material, Material]) -> Style:
    """A style that paints the rock as it is: no plating, rivets, streaks or worn metal; only a low-frequency grime."""
    return Style(name="rock", materials={role: materials[0] for role in REQUIRED_ROLES}, groove_depth_m=0.0, hatch_fraction=0.0,
                 edge_wear=0.0, streaks=0.0, grime=0.2, grime_scale_m=1.1, extra={"bare_metal": 0.0, "rivets": 0.0})


def collision_spheres(vertices: np.ndarray) -> list[tuple[np.ndarray, float]]:
    """Spheres that stand in for the rock: one for a round rock, two or three spaced along a long one's axis, each the mean
    distance of its stretch of surface from its centre."""
    centre = vertices.mean(axis=0)
    q = vertices - centre
    _, _, vt = np.linalg.svd(q, full_matrices=False)
    axis = vt[0]
    along = q @ axis
    across = np.linalg.norm(q - along[:, None] * axis, axis=1)
    elongation = float(np.ptp(along)) / max(2.0 * float(np.median(across)), 1e-9)
    count = 1 if elongation < 1.5 else 2 if elongation < 2.4 else 3
    edges = np.linspace(along.min(), along.max(), count + 1)
    out = []
    for k in range(count):
        sel = (along >= edges[k]) & (along <= edges[k + 1])
        c = vertices[sel].mean(axis=0)
        out.append((c, float(np.linalg.norm(vertices[sel] - c, axis=1).mean())))
    return out


def shape_id(index: int) -> str:
    return f"{ASSET_ID}_{index}"


def _r(v: Any) -> list[float]:
    return [round(float(x), JSON_DIGITS) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


def build_shape(out_dir: Path, index: int, seed: int) -> tuple[list[Path], dict[str, Any]]:
    """Write one shape's textured mesh; returns its files and its manifest entry."""
    spec = spec_for(index, seed)
    materials = rock_materials(spec)
    render = rock_mesh(RENDER_LEVEL, spec, seed, index, materials)
    fine = rock_mesh(FINE_LEVEL, spec, seed, index, materials)
    part = TexturedPart(render, (0, 0, 0), (), "rock")
    paths, mesh_entry = write_textured_mesh(out_dir, shape_id(index), [part], rock_style(materials), atlas_px=ATLAS_PX,
                                            texel_m=TEXEL_M, seed=seed + index, occlusion=True, fine_mesh=fine, normal_scale=1)
    spheres = collision_spheres(fine.vertices)
    lo, hi = render.bounds()
    entry = {
        "id": shape_id(index),
        "kind": spec.kind,
        "mesh": mesh_entry,
        "bounding_radius_m": round(float(np.linalg.norm(render.vertices, axis=1).max()), 4),
        "collision_radius_m": round(float(np.linalg.norm(fine.vertices, axis=1).mean()), 4),
        "spheres": [{"centre": _r(c), "radius_m": round(r, 4)} for c, r in spheres],
        "aabb_min": _r(lo),
        "aabb_max": _r(hi),
    }
    return paths, entry


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate every rock shape into ``ctx.out_dir``. Option: ``shapes`` (default 16)."""
    count = int(ctx.option("shapes", SHAPE_COUNT))
    if count < 1:
        raise ValueError("shapes must be at least 1")
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    files: list[Path] = []
    shapes: list[dict[str, Any]] = []
    for index in range(count):
        paths, entry = build_shape(out_dir, index, ctx.seed)
        files += paths
        shapes.append(entry)
    lo = np.min([s["aabb_min"] for s in shapes], axis=0)
    hi = np.max([s["aabb_max"] for s in shapes], axis=0)
    shapes_path = out_dir / "shapes.json"
    shapes_path.write_text(json.dumps({"asset_id": ASSET_ID, "author_radius_m": AUTHOR_RADIUS_M, "shapes": shapes}, indent=2) + "\n",
                           encoding="utf-8", newline="\n")
    files.append(shapes_path)
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=lo,
        aabb_max=hi,
        centroid_offset=np.zeros(3),
        files={"shapes": shapes_path.name},
        extra={"author_radius_m": AUTHOR_RADIUS_M, "kinds": list(KINDS), "shapes": shapes},
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
