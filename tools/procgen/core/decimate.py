"""Thinning a closed mesh to a triangle budget (M10-T06, D12.2): edge collapses by quadric error, many at once.

:func:`decimate` removes the edges whose loss changes the shape least until the mesh is down to the asked triangles. An
edge's cost is how far its merged vertex would stand from the planes of the faces round it (Garland and Heckbert's
quadrics, weighted by area), plus a little for its length so flat regions thin evenly.

Collapses are done in rounds, each a set of edges that cannot disturb one another (no two closer than one edge apart), so a
round is plain array work and the result does not depend on any order of visiting. A collapse is refused when it would pinch
the skin (its ends share more than their two side vertices) or fold a face over, so a watertight mesh stays watertight.
The same mesh and target give the same result.
"""

from __future__ import annotations

import numpy as np

LENGTH_WEIGHT = 0.02  # an edge's length counts as this share of it off the surface: breaks ties on flat skin
FOLD_COS = 0.1  # a face may not turn further than this cosine from where it faced
MAX_ROUNDS = 400
APART_PASSES = 8  # passes a round takes to fill its set of collapses


def _edges(faces: np.ndarray, count: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """The mesh's edges as their two ends (low index first) and how many faces use each."""
    pairs = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
    keys, uses = np.unique(pairs.min(axis=1) * count + pairs.max(axis=1), return_counts=True)
    return keys // count, keys % count, uses


def _quadrics(vertices: np.ndarray, faces: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Each vertex's quadric (the summed squared distance to its faces' planes, as a 4 x 4 matrix) and the area round it."""
    a, b, c = vertices[faces[:, 0]], vertices[faces[:, 1]], vertices[faces[:, 2]]
    normal = np.cross(b - a, c - a)
    doubled = np.linalg.norm(normal, axis=1)
    normal = normal / np.maximum(doubled, 1e-30)[:, None]
    plane = np.concatenate([normal, -np.einsum("ij,ij->i", normal, a)[:, None]], axis=1)
    per_face = 0.5 * doubled[:, None, None] * plane[:, :, None] * plane[:, None, :]
    quadric = np.zeros((len(vertices), 4, 4))
    area = np.zeros(len(vertices))
    for k in range(3):
        np.add.at(quadric, faces[:, k], per_face)
        np.add.at(area, faces[:, k], 0.5 * doubled)
    return quadric, area


def _merged(vertices: np.ndarray, quadric: np.ndarray, area: np.ndarray, a: np.ndarray, b: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Where each edge's two ends would merge and what that costs: the point nearest all their faces' planes, pulled to the
    edge's middle where those planes do not pin it down."""
    q = quadric[a] + quadric[b]
    middle = 0.5 * (vertices[a] + vertices[b])
    pull = 1e-3 * np.trace(q[:, :3, :3], axis1=1, axis2=2) / 3.0 + 1e-30
    lhs = q[:, :3, :3] + pull[:, None, None] * np.eye(3)
    at = np.linalg.solve(lhs, (-q[:, :3, 3] + pull[:, None] * middle)[..., None])[..., 0]
    homogeneous = np.concatenate([at, np.ones((len(at), 1))], axis=1)
    cost = np.maximum(np.einsum("ei,eij,ej->e", homogeneous, q, homogeneous), 0.0)
    length = np.linalg.norm(vertices[a] - vertices[b], axis=1)
    return at, cost + (area[a] + area[b]) * (LENGTH_WEIGHT * length) ** 2


def _apart(count: int, a: np.ndarray, b: np.ndarray, rank: np.ndarray, candidates: np.ndarray) -> np.ndarray:
    """The candidates (edge indices) that may collapse together: no end of one is an end of another or next to one. Picked
    in passes: each pass takes the edges that are the best at both their ends, then rules out everything beside them."""
    worst = np.iinfo(np.int64).max
    blocked = np.zeros(count, dtype=bool)
    out = []
    for _ in range(APART_PASSES):
        candidates = candidates[~blocked[a[candidates]] & ~blocked[b[candidates]]]
        if len(candidates) == 0:
            break
        best = np.full(count, worst)
        np.minimum.at(best, a[candidates], rank[candidates])
        np.minimum.at(best, b[candidates], rank[candidates])
        chosen = candidates[(best[a[candidates]] == rank[candidates]) & (best[b[candidates]] == rank[candidates])]
        held = np.full(count, worst)
        held[a[chosen]] = rank[chosen]
        held[b[chosen]] = rank[chosen]
        beside = np.full(count, worst)
        np.minimum.at(beside, a, held[b])
        np.minimum.at(beside, b, held[a])
        chosen = chosen[(beside[a[chosen]] == rank[chosen]) & (beside[b[chosen]] == rank[chosen])]
        out.append(chosen)
        ends = np.zeros(count, dtype=bool)
        ends[a[chosen]] = True
        ends[b[chosen]] = True
        blocked |= ends
        blocked[a[ends[b]]] = True
        blocked[b[ends[a]]] = True
    return np.concatenate(out) if out else candidates[:0]


def _keeps_the_skin(count: int, a: np.ndarray, b: np.ndarray, chosen: np.ndarray) -> np.ndarray:
    """Which chosen edges' ends share exactly their two side vertices: collapsing any other would pinch the skin."""
    source = np.concatenate([a, b])
    target = np.concatenate([b, a])
    order = np.argsort(source * count + target, kind="stable")
    keys, target = (source * count + target)[order], target[order]
    start = np.searchsorted(keys, np.arange(count) * count)
    degree = np.diff(np.concatenate([start, [len(keys)]]))
    ends_a, ends_b = a[chosen], b[chosen]
    lens = degree[ends_a]
    owner = np.repeat(np.arange(len(chosen)), lens)
    within = np.arange(int(lens.sum())) - np.repeat(np.cumsum(lens) - lens, lens)
    neighbour = target[np.repeat(start[ends_a], lens) + within]
    wanted = ends_b[owner] * count + neighbour
    at = np.minimum(np.searchsorted(keys, wanted), len(keys) - 1)
    return np.bincount(owner, weights=(keys[at] == wanted), minlength=len(chosen)) == 2


def _folds(vertices: np.ndarray, faces: np.ndarray, edge_of: np.ndarray, moved_to: np.ndarray, edges: int) -> np.ndarray:
    """Which collapses (by index) would turn a face they keep over or flatten it to nothing."""
    touched = edge_of[faces]  # faces x 3: the collapse each corner belongs to, or -1
    kept = (touched >= 0).sum(axis=1) == 1
    idx = np.flatnonzero(kept)
    which = touched[idx].max(axis=1)
    before = vertices[faces[idx]]
    after = np.where((touched[idx] >= 0)[..., None], moved_to[which][:, None, :], before)
    n0 = np.cross(before[:, 1] - before[:, 0], before[:, 2] - before[:, 0])
    n1 = np.cross(after[:, 1] - after[:, 0], after[:, 2] - after[:, 0])
    bad = np.einsum("ij,ij->i", n0, n1) <= FOLD_COS * np.linalg.norm(n0, axis=1) * np.linalg.norm(n1, axis=1)
    out = np.zeros(edges, dtype=bool)
    out[which[bad]] = True
    return out


def decimate(vertices: np.ndarray, faces: np.ndarray, triangles: int) -> tuple[np.ndarray, np.ndarray]:
    """The mesh thinned to at most ``triangles`` faces (or as near as its shape allows), as ``(vertices, faces)``."""
    v = np.asarray(vertices, dtype=float).reshape(-1, 3).copy()
    f = np.asarray(faces, dtype=np.int64).reshape(-1, 3).copy()
    refused = np.zeros(0, dtype=np.int64)  # edges (by their ends) a fold check turned down: not tried again for a while
    for _ in range(MAX_ROUNDS):
        need = -(-(len(f) - triangles) // 2)
        if need <= 0:
            break
        a, b, uses = _edges(f, len(v))
        quadric, area = _quadrics(v, f)
        at, cost = _merged(v, quadric, area, a, b)
        # An open edge's ends stay where they are: the rim of a cut mesh keeps its shape.
        rim = np.zeros(len(v), dtype=bool)
        rim[a[uses != 2]] = True
        rim[b[uses != 2]] = True
        cost[rim[a] | rim[b] | np.isin(a * len(v) + b, refused)] = np.inf
        order = np.argsort(cost, kind="stable")
        rank = np.empty(len(order), dtype=np.int64)
        rank[order] = np.arange(len(order))
        candidates = order[:min(len(order), max(3 * need, 64))]
        candidates = candidates[np.isfinite(cost[candidates])]
        candidates = candidates[_keeps_the_skin(len(v), a, b, candidates)]
        chosen = _apart(len(v), a, b, rank, candidates)
        edge_of = np.full(len(v), -1, dtype=np.int64)
        edge_of[a[chosen]] = np.arange(len(chosen))
        edge_of[b[chosen]] = np.arange(len(chosen))
        folds = _folds(v, f, edge_of, at[chosen], len(chosen))
        turned_down = chosen[folds]
        chosen = chosen[~folds]
        chosen = chosen[np.argsort(rank[chosen], kind="stable")][:need]
        if len(chosen) == 0:
            if len(refused) == 0 and len(turned_down) == 0:
                break  # nothing left that may collapse
            refused = refused[:0] if len(turned_down) == 0 else np.union1d(refused, a[turned_down] * len(v) + b[turned_down])
            continue
        refused = np.union1d(refused, a[turned_down] * len(v) + b[turned_down])
        remap = np.arange(len(v))
        remap[b[chosen]] = a[chosen]
        v[a[chosen]] = at[chosen]
        f = remap[f]
        f = f[(f[:, 0] != f[:, 1]) & (f[:, 1] != f[:, 2]) & (f[:, 2] != f[:, 0])]
    used, f = np.unique(f, return_inverse=True)
    return v[used], f.reshape(-1, 3)


__all__ = ["decimate"]
