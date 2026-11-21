"""A field's skin as triangles (M10-T06, D12.2): marching cubes on a sparse grid, always watertight.

:func:`extract` lays a grid of ``cell``-sized cubes over the field's box, finds the cubes the skin passes through and
writes each one's triangles from a table of the 256 ways a cube's corners can be inside or outside.

Why the result has no holes: the table is not typed in but made here (:func:`_case_table`) by one rule. On every cube face
the skin's crossings are joined so that inside corners are cut off from each other; a face is shared by two cubes and the
rule looks only at that face's corners, so both cubes draw the same line on it and their triangles meet edge to edge.

Why it stays cheap on a kilometre hull: the field is first asked on a coarse lattice of blocks (``block`` cells a side),
and only blocks that could hold skin (the field's ``lipschitz`` bounds how fast its answer changes, its ``slack`` what
relief adds) are worked through.
Every lattice point is asked once, so neighbouring blocks agree on it exactly. The same grid, field and cell give the same
mesh, vertex for vertex.
"""

from __future__ import annotations

import itertools
from collections.abc import Callable

import numpy as np

SAFETY = 1.25  # on a block's reach: the fields' distances are estimates
MAX_SMALL_BLOCKS = 3_000_000
NEAR_CORNER = 0.02  # a vertex keeps this share of its grid edge away from the corners, so no triangle is a sliver of no size

# A cube's corner k sits at (k & 1, k >> 1 & 1, k >> 2 & 1). Edge 4 * axis + j runs along ``axis`` from EDGE_CORNERS[.., 0].
CORNERS = np.array([[k & 1, (k >> 1) & 1, (k >> 2) & 1] for k in range(8)])
EDGE_CORNERS = np.array([[sum(b << o for b, o in zip(bits, others)), sum(b << o for b, o in zip(bits, others)) | (1 << axis)]
                         for axis in range(3) for others in [[k for k in range(3) if k != axis]]
                         for bits in ((0, 0), (1, 0), (0, 1), (1, 1))])
EDGE_AXIS = np.repeat(np.arange(3), 4)


def _face_segments(inside: list[bool]) -> list[tuple[int, int]]:
    """The lines the skin draws on a cube's six faces for one pattern of inside corners, as pairs of crossed edges."""
    crossed = [inside[a] != inside[b] for a, b in EDGE_CORNERS]
    segments = []
    for axis, level in itertools.product(range(3), (0, 1)):
        on_face = [e for e in range(12) if crossed[e] and EDGE_AXIS[e] != axis and CORNERS[EDGE_CORNERS[e, 0], axis] == level]
        if len(on_face) == 2:
            segments.append((on_face[0], on_face[1]))
        elif len(on_face) == 4:
            # Two inside corners on a diagonal: each is cut off by the line between the two edges that meet at it.
            for corner in range(8):
                if inside[corner] and CORNERS[corner, axis] == level:
                    a, b = (e for e in on_face if corner in EDGE_CORNERS[e])
                    segments.append((a, b))
    return segments


def _loops(segments: list[tuple[int, int]]) -> list[list[int]]:
    """The closed loops the segments form: every crossed edge lies on two faces, so it has two segments."""
    links: dict[int, list[int]] = {}
    for a, b in segments:
        links.setdefault(a, []).append(b)
        links.setdefault(b, []).append(a)
    loops, seen = [], set()
    for start in sorted(links):
        if start in seen:
            continue
        loop, previous, current = [start], -1, start
        seen.add(start)
        while True:
            nxt = links[current][0] if links[current][0] != previous else links[current][1]
            if nxt == start:
                break
            loop.append(nxt)
            seen.add(nxt)
            previous, current = current, nxt
        loops.append(loop)
    return loops


def _case_table() -> np.ndarray:
    """For each of the 256 corner patterns, its triangles as triples of cube edges, padded with -1."""
    mid = (CORNERS[EDGE_CORNERS[:, 0]] + CORNERS[EDGE_CORNERS[:, 1]]) * 0.5
    cases = []
    for pattern in range(256):
        inside = [bool(pattern >> k & 1) for k in range(8)]
        triangles = []
        for loop in _loops(_face_segments(inside)):
            points = mid[loop]
            # Outward is from the inside corner of each crossed edge to its outside one: wind the loop to face that way.
            outward = sum((CORNERS[b] - CORNERS[a]) * (1.0 if inside[a] else -1.0) for a, b in EDGE_CORNERS[loop])
            normal = sum(np.cross(points[k], points[(k + 1) % len(loop)]) for k in range(len(loop)))
            if float(normal @ outward) < 0.0:
                loop = loop[::-1]
            triangles += [(loop[0], loop[k], loop[k + 1]) for k in range(1, len(loop) - 1)]
        cases.append(triangles)
    table = np.full((256, max(len(c) for c in cases), 3), -1, dtype=np.int64)
    for pattern, triangles in enumerate(cases):
        if triangles:
            table[pattern, :len(triangles)] = triangles
    return table


CASES = _case_table()


def _blocks_with_skin(field: Callable[[np.ndarray], np.ndarray], lo: np.ndarray, cell: float, blocks: np.ndarray, block: int,
                      lipschitz: float, slack: float) -> np.ndarray:
    """The blocks (``(n, 3)`` block indices) the skin may pass through: the field asked at every block's middle; a block is
    kept when the answer there is nearer zero than the block's far corner could be."""
    grid = np.stack(np.meshgrid(*(np.arange(n) for n in blocks), indexing="ij"), axis=-1).reshape(-1, 3)
    size = block * cell
    middle = lo + (grid + 0.5) * size
    reach = SAFETY * lipschitz * (0.5 * np.sqrt(3.0) * size + cell) + slack
    return grid[np.abs(field(middle)) <= reach]


def extract(field: Callable[[np.ndarray], np.ndarray], lo: np.ndarray, hi: np.ndarray, cell: float, lipschitz: float = 1.0,
            slack: float = 0.0, block: int | None = None) -> tuple[np.ndarray, np.ndarray]:
    """The field's zero skin inside the box ``lo``..``hi`` as ``(vertices, faces)``: watertight, wound outward (the field is
    negative inside). The grid is padded a cell beyond the box, so a body that fills its box is still closed."""
    lo, hi = np.asarray(lo, dtype=float) - cell, np.asarray(hi, dtype=float) + cell
    if cell <= 0.0 or np.any(hi <= lo):
        raise ValueError("an extraction needs a cell size and a box")
    cells = np.maximum(np.ceil((hi - lo) / cell).astype(np.int64), 1)
    if block is None:  # small blocks hug the skin closer; a big grid cannot afford to ask about that many
        block = 4 if float(np.prod(cells / 4.0)) <= MAX_SMALL_BLOCKS else 8
    blocks = -(-cells // block)
    kept = _blocks_with_skin(field, lo, cell, blocks, block, lipschitz, slack)
    if len(kept) == 0:
        raise ValueError("the field has no skin inside its box")

    # Every lattice point of the kept blocks, asked once.
    side = block + 1
    dims = blocks * block + 1  # lattice points per axis
    local = np.stack(np.meshgrid(*(np.arange(side),) * 3, indexing="ij"), axis=-1).reshape(-1, 3)
    points = kept[:, None, :] * block + local[None]  # blocks x side^3 x 3
    ids = (points[..., 0] * dims[1] + points[..., 1]) * dims[2] + points[..., 2]
    unique, inverse = np.unique(ids, return_inverse=True)
    coords = np.stack([unique // (dims[1] * dims[2]), (unique // dims[2]) % dims[1], unique % dims[2]], axis=1)
    values = field(lo + coords * cell)[inverse.reshape(ids.shape)].reshape(len(kept), side, side, side)

    # Each cell's eight corner values and its pattern.
    corner_values = np.stack([values[:, c[0]:c[0] + block, c[1]:c[1] + block, c[2]:c[2] + block] for c in CORNERS], axis=-1)
    pattern = ((corner_values < 0.0) * (1 << np.arange(8))).sum(axis=-1)
    b, i, j, k = np.nonzero((pattern > 0) & (pattern < 255))
    if len(b) == 0:
        raise ValueError("the field has no skin inside its box")
    cell_corner = kept[b] * block + np.stack([i, j, k], axis=1)
    cell_values = corner_values[b, i, j, k]
    triangles = CASES[pattern[b, i, j, k]]  # cells x triangles x 3 edges
    used = triangles[..., 0] >= 0
    # The triangles in the order of their cells along the grid, whatever order the blocks came in.
    cell_id = (cell_corner[:, 0] * dims[1] + cell_corner[:, 1]) * dims[2] + cell_corner[:, 2]
    by_cell = np.argsort(cell_id, kind="stable")
    cell_corner, cell_values, triangles, used = cell_corner[by_cell], cell_values[by_cell], triangles[by_cell], used[by_cell]
    owner = np.broadcast_to(np.arange(len(b))[:, None], used.shape)[used]
    edges = triangles[used]  # triangles x 3

    # A vertex per crossed grid edge, named by the edge's lower lattice point and axis, so neighbours share it.
    base = cell_corner[owner][:, None, :] + CORNERS[EDGE_CORNERS[edges, 0]]
    axis = EDGE_AXIS[edges]
    keys = ((base[..., 0] * dims[1] + base[..., 1]) * dims[2] + base[..., 2]) * 3 + axis
    v0 = np.take_along_axis(cell_values[owner], EDGE_CORNERS[edges, 0], axis=1)
    v1 = np.take_along_axis(cell_values[owner], EDGE_CORNERS[edges, 1], axis=1)
    along = np.clip(v0 / (v0 - v1), NEAR_CORNER, 1.0 - NEAR_CORNER)
    positions = lo + base * cell
    np.add.at(positions, (np.arange(len(owner))[:, None], np.arange(3)[None, :], axis), along * cell)
    _, first, faces = np.unique(keys.reshape(-1), return_index=True, return_inverse=True)
    return positions.reshape(-1, 3)[first], faces.reshape(-1, 3)


def edge_faults(faces: np.ndarray) -> int:
    """How many edges of a mesh are not shared by exactly two faces that run along them in opposite directions: zero for a
    closed skin with one consistent outside."""
    f = np.asarray(faces, dtype=np.int64).reshape(-1, 3)
    directed = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    span = int(f.max()) + 1 if len(f) else 1
    forward = np.unique(directed[:, 0] * span + directed[:, 1], return_counts=True)
    backward = directed[:, 1] * span + directed[:, 0]
    faults = int(np.sum(forward[1] != 1))  # an edge walked twice the same way
    return faults + int(np.sum(~np.isin(backward, forward[0])))  # an edge with no face walking it back


__all__ = ["CASES", "edge_faults", "extract"]
