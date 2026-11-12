"""Hull surface layouts drawn per part (M5-T40): seams, hatches, ribs and plating read off the show, in place of the generic
staggered grid.

A part carries a :class:`SeamLayout`: features in the part's own frame that travel with it when the generator places, turns or
mirrors it. The texture baker asks the layout, per texel, for the relief (grooves, sunk hatches, raised ribs and plates), how much
of a dark seam line covers it, and the plate's tone and roughness shift. Every feature is a distance on the surface, so a line is
as crisp as the atlas allows on any hull size.

Features have a ``level``: 1 the major structural breaks, 2 the references' full seam density with hatches and ribs, 3 the plating
texture (plate to plate tone, grime at plate edges). A layout is baked up to a level.
"""

from __future__ import annotations

import dataclasses
import math
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field

import numpy as np

from ..styles import _hash01

Vec3 = tuple[float, float, float]
_INF = float("inf")
_NO_LO: Vec3 = (-_INF, -_INF, -_INF)
_NO_HI: Vec3 = (_INF, _INF, _INF)


@dataclass
class Relief:
    """What a layout paints on some points: height in metres (0 the plate), seam line cover 0..1, the plate's albedo factor and
    roughness shift."""

    height: np.ndarray
    line: np.ndarray
    tint: np.ndarray
    rough: np.ndarray

    @staticmethod
    def flat(n: int) -> Relief:
        return Relief(np.zeros(n), np.zeros(n), np.ones(n), np.zeros(n))


def _smooth(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


@dataclass(frozen=True)
class Feature:
    """Shared by every feature: where it may paint (a box in the part's frame and a side the surface must face), its level, its
    line's width and depth as multiples of the baker's seam (``depth`` below zero stands proud: a rib), ``flat_m`` the half width of a
    flat floor or crown (a recessed band, a wide rib), and how dark its line is painted (0: relief only)."""

    level: int = 1
    width: float = 1.0
    depth: float = 1.0
    flat_m: float = 0.0
    dark: float = 1.0
    lo: Vec3 = _NO_LO
    hi: Vec3 = _NO_HI
    facing: Vec3 | None = None
    min_dot: float = 0.35

    def _allowed(self, p: np.ndarray, n: np.ndarray) -> np.ndarray:
        ok = np.all((p >= np.asarray(self.lo)) & (p <= np.asarray(self.hi)), axis=1)
        if self.facing is not None:
            ok &= n @ np.asarray(self.facing, dtype=float) > self.min_dot
        return ok

    def distance(self, p: np.ndarray, n: np.ndarray) -> np.ndarray:  # pragma: no cover - overridden
        raise NotImplementedError

    def paint(self, p: np.ndarray, n: np.ndarray, line_m: float, depth_m: float, out: Relief) -> None:
        """Adds this feature's groove or rib to ``out``."""
        d = np.where(self._allowed(p, n), self.distance(p, n), _INF)
        half = 0.5 * line_m * self.width
        s = _smooth(1.0 - (d - self.flat_m) / half)
        out.height -= depth_m * self.depth * s
        if self.depth > 0.0:
            out.line[:] = np.maximum(out.line, self.dark * s)
        else:  # a rib: a thin shadow line at its foot only
            foot = _smooth(1.0 - np.abs(d - self.flat_m - half) / (0.5 * half))
            out.line[:] = np.maximum(out.line, 0.5 * self.dark * foot)


@dataclass(frozen=True)
class Cut(Feature):
    """A seam where the plane ``axis = at`` meets the surface: a ring round a barrel, a frame line across a slab."""

    axis: int = 2
    at: float = 0.0

    def distance(self, p: np.ndarray, n: np.ndarray) -> np.ndarray:
        across = np.sqrt(np.clip(1.0 - n[:, self.axis] ** 2, 0.0, 1.0))  # the plane's distance over the surface's slope to it
        return np.where(across > 0.3, np.abs(p[:, self.axis] - self.at) / np.maximum(across, 0.3), _INF)


@dataclass(frozen=True)
class Spoke(Feature):
    """A seam along a body of revolution: at ``angle_deg`` round ``axis`` through ``centre`` (angles from the next axis in x, y, z
    order towards the one after), between ``span`` along the axis."""

    axis: int = 2
    centre: Vec3 = (0.0, 0.0, 0.0)
    angle_deg: float = 0.0
    span: tuple[float, float] = (-_INF, _INF)
    reach: tuple[float, float] = (0.0, _INF)  # the radii it runs between (a disc's radial seams)

    def distance(self, p: np.ndarray, n: np.ndarray) -> np.ndarray:
        a, b = (self.axis + 1) % 3, (self.axis + 2) % 3
        da, db = p[:, a] - self.centre[a], p[:, b] - self.centre[b]
        radius = np.hypot(da, db)
        turn = np.arctan2(db, da) - math.radians(self.angle_deg)
        turn = np.abs((turn + math.pi) % (2.0 * math.pi) - math.pi)
        along = p[:, self.axis]
        on = (along >= self.span[0]) & (along <= self.span[1]) & (radius >= self.reach[0]) & (radius <= self.reach[1])
        return np.where(on & (turn < 0.5 * math.pi), radius * np.sin(np.minimum(turn, 0.5 * math.pi)), _INF)


@dataclass(frozen=True)
class Hoop(Feature):
    """A circular seam on a face square to ``axis``: every point ``radius`` from the axis through ``centre`` (a disc's rings)."""

    axis: int = 1
    centre: Vec3 = (0.0, 0.0, 0.0)
    radius: float = 1.0

    def distance(self, p: np.ndarray, n: np.ndarray) -> np.ndarray:
        a, b = (self.axis + 1) % 3, (self.axis + 2) % 3
        return np.abs(np.hypot(p[:, a] - self.centre[a], p[:, b] - self.centre[b]) - self.radius)


@dataclass(frozen=True)
class Path(Feature):
    """A seam along a polyline, laid on the surface from the ``facing`` side (set ``facing``): plate breaks that run at an angle."""

    points: tuple[Vec3, ...] = ()
    closed: bool = False

    def distance(self, p: np.ndarray, n: np.ndarray) -> np.ndarray:
        f = np.asarray(self.facing if self.facing is not None else (0.0, 1.0, 0.0), dtype=float)
        f = f / np.linalg.norm(f)
        flat = p - np.outer(p @ f, f)
        pts = np.asarray(self.points, dtype=float)
        pts = pts - np.outer(pts @ f, f)
        if self.closed:
            pts = np.concatenate([pts, pts[:1]])
        best = np.full(len(p), _INF)
        for a, b in zip(pts[:-1], pts[1:], strict=True):
            ab = b - a
            t = np.clip(((flat - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
            best = np.minimum(best, np.linalg.norm(flat - (a + t[:, None] * ab), axis=1))
        return best


@dataclass(frozen=True)
class Hatch(Feature):
    """A rectangular hatch seen from ``facing``: a groove round its rounded outline, the plate inside sunk by ``sunk`` seam depths
    (below zero: a plate standing proud) and toned by ``tone``. ``right`` and ``up`` span it; ``slats`` cuts it into louvres along
    ``up``."""

    centre: Vec3 = (0.0, 0.0, 0.0)
    right: Vec3 = (0.0, 0.0, 1.0)
    up: Vec3 = (0.0, 1.0, 0.0)
    size: tuple[float, float] = (1.0, 1.0)
    corner_m: float = 0.0
    sunk: float = 0.5
    tone: float = 0.95
    slats: int = 0

    def _uv(self, p: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        d = p - np.asarray(self.centre, dtype=float)
        return d @ np.asarray(self.right, dtype=float), d @ np.asarray(self.up, dtype=float)

    def _signed(self, p: np.ndarray) -> np.ndarray:
        u, v = self._uv(p)
        qx = np.abs(u) - (0.5 * self.size[0] - self.corner_m)
        qy = np.abs(v) - (0.5 * self.size[1] - self.corner_m)
        return np.hypot(np.maximum(qx, 0.0), np.maximum(qy, 0.0)) + np.minimum(np.maximum(qx, qy), 0.0) - self.corner_m

    def distance(self, p: np.ndarray, n: np.ndarray) -> np.ndarray:
        return np.abs(self._signed(p))

    def paint(self, p: np.ndarray, n: np.ndarray, line_m: float, depth_m: float, out: Relief) -> None:
        super().paint(p, n, line_m, depth_m, out)
        ok = self._allowed(p, n)
        inside = _smooth(-self._signed(p) / (0.5 * line_m)) * ok
        out.height -= depth_m * self.sunk * inside
        out.tint *= 1.0 - (1.0 - self.tone) * inside
        if self.slats > 0:
            _, v = self._uv(p)
            pitch = self.size[1] / self.slats
            saw = np.mod(v + 0.5 * self.size[1], pitch) / pitch  # each louvre leans, its lower edge the shadow
            out.height -= depth_m * 0.8 * (1.0 - saw) * inside
            out.line[:] = np.maximum(out.line, 0.6 * self.dark * inside * (saw < 0.22))


@dataclass(frozen=True)
class Plates(Feature):
    """Plating as the show's models wear it: rectangles of mixed size, cut from ``cell`` sized fields by ``depth`` rounds of
    uneven splits (never smaller than ``min_m``), each plate with its own tone (``tone``, the +- share of the paint's value; base
    colours stay) and sheen, some standing proud (``proud`` share), grime gathered along their edges (``grime``). No rows, no
    stagger. ``wrap``: ``"planar"`` lays the fields along ``right`` and ``up``; ``"barrel"`` along ``axis`` and round it at
    ``radius`` (``around`` fields round the girth); ``"polar"`` out from ``axis`` and round it (a disc's face); ``"sides"`` picks,
    per point, the two axes its normal faces least. ``offset`` moves the fields so their edges meet drawn seams. ``scatter`` above
    zero draws no plating: only that share of the plates, each shrunk by ``inset_m``, as hatches standing proud."""

    wrap: str = "sides"
    cell: tuple[float, float] = (8.0, 4.0)
    splits: int = 3
    min_m: float = 1.0
    keep: float = 0.25  # the share of plates left whole at each round
    tone: float = 0.06
    sheen: float = 0.06
    proud: float = 0.0
    grime: float = 0.0
    grime_m: float = 0.6
    right: Vec3 = (0.0, 0.0, 1.0)
    up: Vec3 = (0.0, 1.0, 0.0)
    axis: int = 2
    centre: Vec3 = (0.0, 0.0, 0.0)
    radius: float = 1.0
    around: int = 8
    seed: int = 0
    long_axis: int = 2  # with "sides": the plates' long side runs along this axis where it can
    offset: tuple[float, float] = (0.0, 0.0)
    symmetric: bool = True  # the plating left of the part's centre plane (through ``centre``) mirrors the right's
    scatter: float = 0.0
    inset_m: float = 0.3

    def _uv(self, p: np.ndarray, n: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, tuple[float, float]]:
        """Plate coordinates in metres, a chart key per point, and the field size."""
        cu, cv = self.cell
        if self.wrap == "barrel":
            a, b = (self.axis + 1) % 3, (self.axis + 2) % 3
            turn = np.arctan2(p[:, b] - self.centre[b], p[:, a] - self.centre[a]) + math.pi
            girth = 2.0 * math.pi * self.radius
            return p[:, self.axis], turn * self.radius, np.zeros(len(p), dtype=np.int64), (cu, girth / self.around)
        if self.wrap == "polar":
            a, b = (self.axis + 1) % 3, (self.axis + 2) % 3
            da, db = p[:, a] - self.centre[a], p[:, b] - self.centre[b]
            girth = 2.0 * math.pi * self.radius
            return np.hypot(da, db), (np.arctan2(db, da) + math.pi) * self.radius, np.zeros(len(p), dtype=np.int64), (cu, girth / self.around)
        if self.wrap == "planar":
            return p @ np.asarray(self.right, dtype=float), p @ np.asarray(self.up, dtype=float), np.zeros(len(p), dtype=np.int64), (cu, cv)
        drop = np.argmax(np.abs(n), axis=1)
        pair = np.array([[1, 2], [0, 2], [0, 1]])[drop]
        swap = pair[:, 1] == self.long_axis
        ua = np.where(swap, pair[:, 1], pair[:, 0])
        va = np.where(swap, pair[:, 0], pair[:, 1])
        index = np.arange(len(p))
        return p[index, ua], p[index, va], drop.astype(np.int64) + 1, (cu, cv)

    def cells(self, p: np.ndarray, n: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        """The plate each point lies on: its key, its bounds ``u0, u1, v0, v1`` in plate coordinates, and the point's own ``u, v``."""
        if self.symmetric:
            p = np.column_stack([self.centre[0] + np.abs(p[:, 0] - self.centre[0]), p[:, 1], p[:, 2]])
        u, v, chart, (cu, cv) = self._uv(p, n)
        u, v = u - self.offset[0], v - self.offset[1]
        seed = np.full(len(p), self.seed, dtype=np.int64)
        iu, iv = np.floor(u / cu).astype(np.int64), np.floor(v / cv).astype(np.int64)
        if self.wrap in ("barrel", "polar"):
            iv = np.mod(iv, self.around)
        u0, v0 = np.floor(u / cu) * cu, np.floor(v / cv) * cv
        u1, v1 = u0 + cu, v0 + cv
        key = (_hash01(iu, iv, chart, seed) * 0xFFFFFF).astype(np.int64)
        for round_ in range(self.splits):
            w, h = u1 - u0, v1 - v0
            r_keep = _hash01(key, seed + 101 + round_)
            r_side = _hash01(key, seed + 211 + round_)
            r_at = 0.3 + 0.4 * _hash01(key, seed + 307 + round_)
            along_u = np.where(w > 1.6 * h, True, np.where(h > 1.6 * w, False, r_side < 0.5))
            size = np.where(along_u, w, h)
            split = (r_keep >= self.keep) & (size * np.minimum(r_at, 1.0 - r_at) >= self.min_m)
            cut_u = u0 + r_at * w
            cut_v = v0 + r_at * h
            first = np.where(along_u, u < cut_u, v < cut_v)
            su, sv = split & along_u, split & ~along_u
            u1 = np.where(su & first, cut_u, u1)
            u0 = np.where(su & ~first, cut_u, u0)
            v1 = np.where(sv & first, cut_v, v1)
            v0 = np.where(sv & ~first, cut_v, v0)
            key = np.where(split, (_hash01(key, first.astype(np.int64) + 7, seed + round_) * 0xFFFFFF).astype(np.int64), key)
        return key, u0, u1, v0, v1, u, v

    def paint(self, p: np.ndarray, n: np.ndarray, line_m: float, depth_m: float, out: Relief) -> None:
        ok = self._allowed(p, n)
        if not ok.any():
            return
        key, u0, u1, v0, v1, u, v = self.cells(p, n)
        seed = np.full(len(p), self.seed, dtype=np.int64)
        edge = np.minimum(np.minimum(u - u0, u1 - u), np.minimum(v - v0, v1 - v))
        half = 0.5 * line_m * self.width
        if self.scatter > 0.0:
            chosen = ok & (_hash01(key, seed + 503) < self.scatter) & (np.minimum(u1 - u0, v1 - v0) > 2.5 * self.inset_m)
            inner = edge - self.inset_m
            out.height += depth_m * abs(self.depth) * _smooth(inner / half) * chosen
            out.line[:] = np.maximum(out.line, self.dark * _smooth(1.0 - np.abs(inner + 0.5 * half) / half) * chosen)
            out.tint *= 1.0 + self.tone * (2.0 * _hash01(key, seed + 401) - 1.0) * chosen * (inner > 0.0)
            return
        s = _smooth(1.0 - edge / half) * ok
        out.height -= depth_m * self.depth * s
        out.line[:] = np.maximum(out.line, self.dark * s)
        inside = _smooth(edge / half - 1.0) * ok
        out.tint *= 1.0 + self.tone * (2.0 * _hash01(key, seed + 401) - 1.0) * ok
        out.rough += self.sheen * (2.0 * _hash01(key, seed + 607) - 1.0) * ok
        if self.proud > 0.0:
            out.height += depth_m * 0.6 * inside * (_hash01(key, seed + 503) < self.proud)
        if self.grime > 0.0:
            out.tint *= 1.0 - self.grime * np.exp(-edge / self.grime_m) * ok


@dataclass(frozen=True)
class SeamLayout:
    """A part's features, in groups that each keep the frame they were drawn in (``matrix`` columns are that frame's axes in the
    part's current frame, ``origin`` its origin), so the layout follows the part through moves, turns and mirrors."""

    groups: tuple[tuple[np.ndarray, np.ndarray, tuple[Feature, ...]], ...] = ()

    @staticmethod
    def of(features: Iterable[Feature]) -> SeamLayout:
        return SeamLayout(((np.eye(3), np.zeros(3), tuple(features)),))

    def __bool__(self) -> bool:
        return any(len(g[2]) for g in self.groups)

    def __add__(self, other: SeamLayout) -> SeamLayout:
        return SeamLayout(self.groups + other.groups)

    def transformed(self, rotation: np.ndarray, translation: Sequence[float] = (0.0, 0.0, 0.0)) -> SeamLayout:
        r = np.asarray(rotation, dtype=float)
        t = np.asarray(translation, dtype=float)
        return SeamLayout(tuple((r @ m, r @ o + t, f) for m, o, f in self.groups))

    def mirrored_too(self, axis: int = 0) -> SeamLayout:
        """The layout and its mirror image across ``axis``: a centre part drawn on one side."""
        flip = np.eye(3)
        flip[axis, axis] = -1.0
        return self + self.transformed(flip)

    def up_to(self, level: int) -> SeamLayout:
        return SeamLayout(tuple((m, o, tuple(f for f in fs if f.level <= level)) for m, o, fs in self.groups))

    def features(self) -> list[Feature]:
        return [f for _, _, fs in self.groups for f in fs]

    def evaluate(self, positions: np.ndarray, normals: np.ndarray, line_m: float, depth_m: float) -> Relief:
        """The layout's relief, lines and plate tones at surface points given in the part's current frame."""
        out = Relief.flat(len(positions))
        for matrix, origin, features in self.groups:
            if not features:
                continue
            p = (np.asarray(positions, dtype=float) - origin) @ matrix  # the matrix is orthogonal: its transpose undoes it
            n = np.asarray(normals, dtype=float) @ matrix
            for f in features:
                f.paint(p, n, line_m, depth_m, out)
        return out


EMPTY = SeamLayout()
MAJOR, FULL, PLATING = 1, 2, 3  # the levels: major breaks, the references' seam density, the plating texture


def rings(axis: int, stations: Iterable[float], **kw: object) -> list[Feature]:
    return [Cut(axis=axis, at=float(z), **kw) for z in stations]


def spokes(axis: int, centre: Vec3, angles_deg: Iterable[float], **kw: object) -> list[Feature]:
    return [Spoke(axis=axis, centre=centre, angle_deg=float(a), **kw) for a in angles_deg]


def every(start: float, stop: float, pitch: float) -> list[float]:
    """Stations from ``start`` to ``stop`` about ``pitch`` apart, both ends included."""
    count = max(1, round((stop - start) / pitch))
    return [start + (stop - start) * k / count for k in range(count + 1)]


def retuned(feature: Feature, **kw: object) -> Feature:
    return dataclasses.replace(feature, **kw)


__all__ = ["Cut", "EMPTY", "Feature", "Hatch", "FULL", "Hoop", "MAJOR", "PLATING", "Path", "Plates", "Relief", "SeamLayout", "Spoke", "every", "retuned", "rings",
           "spokes"]
