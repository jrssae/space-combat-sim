"""Organic bodies on the capital framework (M10-T06, D12.2; docs/assets-capital.md, "Organic hulls").

The capital framework (``core/capital.py``) builds a hull from modules, each whole inside one damage section. An organic
body is one skin with no joints, so this file is the bridge:

* :func:`sectioned` meshes a body's field once and cuts the mesh into one module per section, by which section's region
  each face lies in. The cuts share their vertices' places and normals, so the hull still draws as one seamless skin, and
  each section breaks away along its cut;
* :func:`module` wraps any organic mesh (a limb, a petal) as a module with its collision;
* :func:`convex_pieces` gives a mesh the convex collision shapes M7's builder wants (``core/collision.py``): it splits
  the points until no piece's hull bridges a hollow deeper than the tolerance.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass

import numpy as np

from ..parts import capital as cp
from . import collision as col
from . import sdf
from .geometry import Material, Mesh

MAX_PIECE_POINTS = 4000  # of a mesh's points looked at when it is fitted
MAX_FILLING_POINTS = 12000
CHORDS = 600  # lines between points tried for a hollow
MIN_PIECE_POINTS = 12
MIN_THICKNESS_M = 0.05
OVERLAP_SHARE = 0.04  # of a piece's length: the band two halves share at their cut


def split(mesh: Mesh, labels: np.ndarray, count: int) -> list[Mesh]:
    """The mesh cut into ``count`` meshes by a label per face, each with only the vertices it uses (and their normals)."""
    labels = np.asarray(labels, dtype=np.int64).reshape(mesh.face_count)
    out = []
    for k in range(count):
        mask = labels == k
        used, faces = np.unique(mesh.faces[mask], return_inverse=True)
        out.append(Mesh(mesh.vertices[used], faces.reshape(-1, 3), mesh.face_material[mask], mesh.materials, mesh.face_chart[mask],
                        mesh.face_uv[mask], None if mesh.vertex_normal is None else mesh.vertex_normal[used]))
    return out


def nearest_region(mesh: Mesh, regions: Sequence[sdf.Field]) -> np.ndarray:
    """A label per face: the region whose field is least at the face's middle (the one it is deepest in, or nearest to)."""
    centres = mesh.face_centroids()
    return np.argmin(np.stack([region(centres) for region in regions], axis=1), axis=1)


def _hollow(skin: np.ndarray, filling: np.ndarray, grain_m: float) -> float:
    """How far a hull round the points would stand off them: the hull holds every line between two of its points, so the
    middles of a spread of such lines are tried, and the one farthest from any point (skin or filling) is the hollow the
    hull would bridge. ``grain_m``, the points' own spacing, is what a middle on the surface still measures; it is taken off."""
    order = np.random.default_rng(len(skin)).permutation(len(skin))  # seeded by the size: the same points, the same lines
    a, b = order[:CHORDS], order[::-1][:CHORDS]
    middles = 0.5 * (skin[a] + skin[b])
    cloud = np.concatenate([skin, filling])
    nearest = np.sqrt(((middles[:, None, :] - cloud[None]) ** 2).sum(axis=2).min(axis=1))
    return max(float(nearest.max()) - grain_m, 0.0)


def _grain(points: np.ndarray) -> float:
    """The points' typical spacing: the median distance from one to its nearest neighbour, over a spread of them."""
    some = points[np.linspace(0, len(points) - 1, min(len(points), 400)).astype(np.int64)]
    d = np.sqrt(((some[:, None, :] - points[None]) ** 2).sum(axis=2))
    d[d == 0.0] = np.inf
    return float(np.median(d.min(axis=1)))


@dataclass
class _Piece:
    skin: np.ndarray
    filling: np.ndarray
    hollow: float


def _halves(piece: _Piece, tolerance_m: float, grain_m: float) -> list[tuple[_Piece, _Piece]]:
    """The piece cut in two through its middle, once across each of its three main directions. The halves share a band
    of points at the cut, so their hulls overlap and leave no wall standing inside the body."""
    centre = piece.skin.mean(axis=0)
    axes = np.linalg.svd(piece.skin - centre, full_matrices=False)[2]
    out = []
    for axis in axes:
        along = (piece.skin - centre) @ axis
        inner = (piece.filling - centre) @ axis
        band = max(tolerance_m, OVERLAP_SHARE * float(along.max() - along.min()))
        near, far = along > -band, along < band
        if MIN_PIECE_POINTS <= int(near.sum()) < len(along) and MIN_PIECE_POINTS <= int(far.sum()) < len(along):
            halves = [(piece.skin[side], piece.filling[fill]) for side, fill in ((near, inner > -band), (far, inner < band))]
            out.append(tuple(_Piece(skin, filling, _hollow(skin, filling, grain_m)) for skin, filling in halves))
    return out


def convex_pieces(name: str, points: np.ndarray, tolerance_m: float, max_pieces: int = 16, filling: np.ndarray | None = None) -> list[col.Shape]:
    """Convex hulls that together hold ``points`` (a mesh's vertices): the piece whose hull bridges the deepest hollow is
    cut in two, across whichever of its main directions leaves the shallowest hollows, until every hollow is within
    ``tolerance_m`` or there are ``max_pieces``. The points alone are taken as a shell (a petal: its hull may not fill
    its curl). For a solid, ``filling`` are points inside it no farther apart than the tolerance: they tell its inside
    from a hollow, and go with the pieces, so each is a solid share of the body. Named ``<name>_00``, ``<name>_01``, ..."""
    skin = np.asarray(points, dtype=float).reshape(-1, 3)
    if len(skin) > MAX_PIECE_POINTS:
        skin = skin[np.linspace(0, len(skin) - 1, MAX_PIECE_POINTS).astype(np.int64)]
    inside = np.zeros((0, 3)) if filling is None else np.asarray(filling, dtype=float).reshape(-1, 3)
    if len(inside) > MAX_FILLING_POINTS:
        inside = inside[np.linspace(0, len(inside) - 1, MAX_FILLING_POINTS).astype(np.int64)]
    grain = _grain(skin)
    pieces = [_Piece(skin, inside, _hollow(skin, inside, grain))]
    while len(pieces) < max_pieces:
        worst = max(range(len(pieces)), key=lambda k: pieces[k].hollow)
        if pieces[worst].hollow <= tolerance_m:
            break
        options = _halves(pieces[worst], tolerance_m, grain)
        if not options:
            break
        pieces[worst:worst + 1] = list(min(options, key=lambda pair: max(pair[0].hollow, pair[1].hollow)))
    return [col.hull(f"{name}_{k:02d}", _with_thickness(np.concatenate([p.skin, p.filling]))) for k, p in enumerate(pieces)]


def _with_thickness(points: np.ndarray) -> np.ndarray:
    """The points, given ``MIN_THICKNESS_M`` across their thinnest direction when they have less (a shell's edge, where its
    two faces meet, is a sheet of no volume, and a hull needs one)."""
    centre = points.mean(axis=0)
    thin = np.linalg.svd(points - centre, full_matrices=False)[2][-1]
    across = (points - centre) @ thin
    if float(across.max() - across.min()) >= MIN_THICKNESS_M:
        return points
    return np.concatenate([points + 0.5 * MIN_THICKNESS_M * thin, points - 0.5 * MIN_THICKNESS_M * thin])


def module(name: str, mesh: Mesh, tolerance_m: float, max_pieces: int = 16, hardpoints: Sequence[cp.Hardpoint] = (),
           skin: str = cp.SKIN_NONE, solid: sdf.Field | None = None) -> cp.Module:
    """An organic mesh as a capital module: its collision fitted by :func:`convex_pieces`, bare of seams unless ``skin``
    says the style's layout dresses it (the semi-organic hulls, Q47). ``solid`` is the field that buries other parts."""
    return cp.module(name, mesh, convex_pieces(name, mesh.vertices, tolerance_m, max_pieces), hardpoints,
                     None if solid is None else sdf.solid(solid), skin)


def sectioned(body: sdf.Field, regions: Mapping[str, sdf.Field], cell_m: float, triangles: int, material: Material, tolerance_m: float,
              max_pieces: int = 4, skin: str = cp.SKIN_NONE, hardpoints: Mapping[str, Sequence[cp.Hardpoint]] | None = None,
              parts: Sequence[sdf.Field] = (), overlap_m: float | None = None) -> list[cp.Module]:
    """One seamless body as a module per damage section: the field meshed once at ``cell_m`` and thinned to ``triangles``,
    then cut by ``regions`` (section name -> the field of its part of the body; a face goes to the region it is deepest
    in). Each module is named for its section and already in it, with the ``hardpoints`` listed for it.

    Collision: ``parts`` are the fields the body was melted from (its lobes, pods and limb roots). Each is near enough
    convex, so within a section every part gets the hulls of its own share of the body (:func:`convex_pieces`, at most
    ``max_pieces`` each), which follows the body far closer than hulls cut blindly through it. With no parts a section's
    whole share is fitted as one. A section's collision reaches ``overlap_m`` (two cells by default) into its neighbours,
    so there is no gap at a cut. The first module carries the body's volume as its solid, so limbs rooted in the body do
    not count their buried ends as skin."""
    whole = sdf.mesh(body, cell_m, material, triangles)
    names = list(regions)
    cuts = split(whole, nearest_region(whole, [regions[n] for n in names]), len(names))
    empty = [n for n, cut in zip(names, cuts, strict=True) if cut.face_count == 0]
    if empty:
        raise ValueError(f"sections with none of the body's skin: {empty}")
    reach = 2.0 * cell_m if overlap_m is None else overlap_m
    # Points inside the body, the tolerance apart: they tell the body's inside from a hollow (``convex_pieces``).
    grid = np.stack(np.meshgrid(*(np.arange(lo, hi, tolerance_m) for lo, hi in zip(body.lo, body.hi, strict=True)), indexing="ij"),
                    axis=-1).reshape(-1, 3)
    inside = grid[body(grid) < -0.5 * tolerance_m]
    owners = list(parts) or [body]
    skin_owner = np.argmin(np.stack([part(whole.vertices) for part in owners], axis=1), axis=1)
    # An inside point goes to every part it is nearly as deep in as in its own: the parts' hulls overlap inside the
    # body, so no hollow is left between them.
    depth = np.stack([part(inside) for part in owners], axis=1)
    shared = depth <= depth.min(axis=1, keepdims=True) + 1.5 * tolerance_m
    points = hardpoints or {}
    out = []
    for k, (n, cut) in enumerate(zip(names, cuts, strict=True)):
        near_skin, near_inside = regions[n](whole.vertices) <= reach, regions[n](inside) <= reach
        shapes: list[col.Shape] = []
        for j in range(len(owners)):
            mine = whole.vertices[near_skin & (skin_owner == j)]
            if len(mine) >= MIN_PIECE_POINTS:
                shapes += convex_pieces(f"{n}_{j:02d}", mine, tolerance_m, max_pieces, inside[near_inside & shared[:, j]])
        out.append(cp.module(n, cut, shapes, points.get(n, ()), sdf.solid(body) if k == 0 else None, skin).in_section(n))
    return out


__all__ = ["convex_pieces", "module", "nearest_region", "sectioned", "split"]
