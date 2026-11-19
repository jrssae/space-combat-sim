"""The raider Battle Wagon's parts (M8-T09; docs/assets-capital.md and docs/design-references.md, "Raider Battle Wagon").

There is no reference model: every proportion below is a percentage of the ship's length, read off the maintainer's
three-view sheet and written down in docs/assets-capital.md; :class:`WagonSpec` turns them into metres. The frame is the
authored one: x to starboard, y up, z aft from the bow (the tips of the antenna spikes at z = 0).

Bow to stern: two antenna spikes and the eye frame on its neck, four booms back to the bow cone, the eight-sided core, a wide
launch tube above it and one below (open at both ends, carried on five frames before the ring and five behind it), a deck arm
on each side before and behind the ring, one deep ring round everything with a cross-braced lattice inside it, and the engine
block: three slabs with two rows of four nozzles between them.

Each builder returns its render piece and the convex collision shapes that stand for it (``core/collision.py``); a piece of
the right side is mirrored to the left by the generator, shapes and all.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np

from ..core import civilian as cv
from ..core import collision as col
from ..core.geometry import Material, Mesh, box, lathe, prism
from ..styles import Style
from .raider_carrier import Built, clock_frame, flat, part

# --- proportions, in percent of the length ----------------------------------------------------------------------------
# The bow: the eye frame, its neck, the cone, the booms from the eye to the cone's shoulders, the antenna spikes.
EYE_Z = (9.3, 10.6)
EYE_R = (3.3, 4.13)  # the frame's opening, its rim
EYE_HUB_R = 1.3
NECK = (10.6, 14.8, 3.3)  # from, to, radius
CONE = (14.8, 23.9, 6.1)  # from, to, the half width across flats at the bow face
BOOM = 1.0  # a boom's section
SPIKE_X = 5.5  # the long spikes' distance from the axis
SPIKE_ROOT_Z = 14.8
SPIKE_R = (0.07, 0.2)  # at the tip, at the root
SPIKE_SHORT = (4.6, -4.4)  # the short spike under the eye: its tip's station, its height

# The core: eight-sided, the same half width across flats all along.
CORE_R = 11.5
CORE_Z = (23.9, 81.3)
CORE_BREAKS = (33.5, 46.1, 68.3)  # the bow block, the frames before the ring, inside the ring, the frames behind it
FRAME_R = 12.6
FRAME_T = 0.7
FRAMES_Z = ((34.6, 36.9, 39.3, 41.7, 44.0), (70.4, 72.8, 75.1, 77.5, 79.8))

# A launch tube (the upper one; the lower mirrors it): outside and inside half sizes and corner cuts (across, up).
TUBE_Z = (25.4, 89.8)
TUBE_Y = 16.6
TUBE_OUTER = ((8.4, 4.25), (3.1, 2.1))
TUBE_INNER = ((7.07, 2.93), (2.4, 1.6))
TUBE_COLLAR = 0.35  # how far a rib stands out of the wall
TUBE_MOUTH = 5.1  # the plain heavy section at each end
TUBE_RIB = (2.3, 1.0)  # the ribs' pitch and width between the mouth sections

# The ring: its station, then its section as (distance from the station, radius), the bow half; the stern half mirrors it.
RING_Z = 57.2
RING_R = (21.1, 29.2)
RING_PROFILE = ((-11.1, 21.1), (-11.1, 22.4), (-8.3, 22.4), (-7.8, 23.0), (-3.3, 28.5), (-2.4, 28.5), (-2.4, 29.2), (-1.5, 29.2), (-1.5, 28.15))
RING_SLOPE = ((-7.8, 23.0), (-3.3, 28.5))  # the bow face the buttresses, fins, windows and missile racks stand on
BUTTRESS = (1.0, 0.8)  # across, proud of the face
BUTTRESS_COUNT = 16
FIN = (0.45, 0.7, 3.8, 1.05)  # across, proud, along the face, the pitch of a bay's three
WINDOW = (2.6, 0.2, 1.5)  # a window bay's dark panel
WINDOW_PANE = (0.5, 0.1, 0.8, 0.75)  # one of its three lit panes: across, proud, along the face, their pitch
RACK = (3.6, 1.5, 3.4)  # a missile rack in a diagonal bay of the bow face: across, proud, along the face
RACK_CELL = (1.0, 0.12, 0.85)

# The lattice in the ring's plane, one cross in each quarter: where its beams cross, their width and depth, the corner blocks.
LATTICE_AT = (13.5, 11.5)
LATTICE_BEAM = (1.6, 1.5)
LATTICE_BLOCK = (2.2, 3.0)  # a block's size, its distance from the crossing

# The deck arms from the core to the ring, as plan outlines (x, z); they carry the turrets.
ARM_HALF = 1.45
ARM_FORE = (((11.0, 23.9), (14.0, 23.9), (14.2, 29.8), (14.2, 46.5), (11.0, 46.5)), ((14.2, 29.8), (21.3, 43.5), (21.3, 46.5), (14.2, 46.5)))
ARM_FORE_OUTLINE = ((11.0, 23.9), (14.0, 23.9), (14.2, 29.8), (21.3, 43.5), (21.3, 46.5), (11.0, 46.5))
ARM_AFT = ((11.0, 68.0), (21.3, 68.0), (21.3, 71.0), (15.7, 84.0), (11.0, 84.0))
TURRETS = ((17.3, 40.5), (17.0, 74.5))  # the mounts on an arm's deck (x, z): before the ring, behind it

# The engine block: the housing behind the core, three slabs, two rows of four nozzles between them.
HOUSING = (81.3, 86.0, 10.4, 6.5)  # from, to, half width, half height
SLAB_Z = (81.3, 100.0)
SLAB_MID = (15.7, 14.3, 1.8)  # half width at the bow end and at the stern, half height
SLAB_TOP = (8.5, 8.1, (7.0, 11.3), (7.2, 9.8))  # half width at each end, its height span at each end
NOZZLE_X = (2.6, 7.9)
NOZZLE_Y = 4.15
NOZZLE_PROFILE = ((85.0, 1.7), (91.5, 1.7), (91.5, 2.2), (96.4, 2.2), (97.4, 1.95), (97.4, 1.6), (95.6, 1.6), (95.6, 0.0))

AREAL_DENSITY = 260.0  # kg per square metre of skin: the informational mass


@dataclass(frozen=True)
class WagonSpec:
    """The one free number: the length over the antenna spikes (docs/assets-capital.md, "Length")."""

    length_m: float = 275.0

    @property
    def u(self) -> float:
        """Metres per percent of the length."""
        return self.length_m / 100.0


# --- helpers -----------------------------------------------------------------------------------------------------------
def octagon(half: Sequence[float], cut: Sequence[float], centre: Sequence[float] = (0.0, 0.0)) -> np.ndarray:
    """The eight corners (x, y) of a box section with its corners cut, counter-clockwise seen from astern."""
    (w, h), (cx, cy), (ox, oy) = half, cut, centre
    pts = [(w, -h + cy), (w, h - cy), (w - cx, h), (-w + cx, h), (-w, h - cy), (-w, -h + cy), (-w + cx, -h), (w - cx, -h)]
    return np.array(pts) + np.array([ox, oy])


def regular(radius: float) -> np.ndarray:
    """A regular octagon whose flats touch ``radius``."""
    return octagon((radius, radius), (radius * (1.0 - math.tan(math.pi / 8.0)),) * 2)


def at_z(ring: np.ndarray, z: float) -> np.ndarray:
    return np.column_stack([ring, np.full(len(ring), z)])


def frustum(a: np.ndarray, za: float, b: np.ndarray, zb: float, walls: Material | Sequence[Material],
            caps: tuple[Material | None, Material | None] = (None, None)) -> Mesh:
    """The straight-sided solid between two sections with the same number of corners: a flat wall per edge, a cap where a
    material is given."""
    pa, pb = at_z(a, za), at_z(b, zb)
    inside = 0.5 * (pa.mean(axis=0) + pb.mean(axis=0))
    mats = [walls] * len(a) if isinstance(walls, Material) else list(walls)
    faces = []
    for k in range(len(a)):
        n = (k + 1) % len(a)
        faces.append(flat([pa[k], pa[n], pb[n], pb[k]], mats[k], inside))
    for pts, material in zip((pa, pb), caps, strict=True):
        if material is not None:
            faces.append(flat(pts, material, inside))
    return Mesh.concatenate(faces)


def lining(a: np.ndarray, za: float, zb: float, material: Material) -> Mesh:
    """The inside of a tube of section ``a``: walls that face its middle."""
    pa, pb = at_z(a, za), at_z(a, zb)
    middle = 0.5 * (pa.mean(axis=0) + pb.mean(axis=0))
    faces = []
    for k in range(len(a)):
        n = (k + 1) % len(a)
        quad = np.array([pa[k], pa[n], pb[n], pb[k]])
        faces.append(flat(quad, material, 2.0 * quad.mean(axis=0) - middle))
    return Mesh.concatenate(faces)


def rim(outer: np.ndarray, inner: np.ndarray, z: float, material: Material, away: Sequence[float]) -> Mesh:
    """The flat band between two sections at one station, facing away from ``away``."""
    po, pi = at_z(outer, z), at_z(inner, z)
    faces = []
    for k in range(len(outer)):
        n = (k + 1) % len(outer)
        faces.append(flat([po[k], po[n], pi[n], pi[k]], material, away))
    return Mesh.concatenate(faces)


_DECK = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, -1.0], [0.0, 1.0, 0.0]])  # a plan drawn in (x, z) laid flat: its thickness along y


def deck(polygons: Sequence[Sequence[Sequence[float]]], outline: Sequence[Sequence[float]], y0: float, y1: float, top: Material,
         edge: Material) -> Mesh:
    """A flat slab from a plan (x, z) between two heights."""
    return prism([(np.array(p), top) for p in polygons], [(np.array(outline), edge)], y1 - y0).transformed(_DECK, (0.0, 0.5 * (y0 + y1), 0.0))


def deck_points(outline: Sequence[Sequence[float]], y0: float, y1: float) -> np.ndarray:
    return np.array([(x, y, z) for y in (y0, y1) for x, z in outline])


def quartered(mesh: Mesh, sectors: int = 4) -> Mesh:
    """A part swept round the ship's axis with each of its charts cut into ``sectors``: a chart all the way round the ring is
    half a kilometre long, and the atlas's texel would be set by fitting it in."""
    centre = mesh.face_centroids()
    sector = np.floor((np.arctan2(centre[:, 0], centre[:, 1]) % (2.0 * math.pi)) / (2.0 * math.pi) * sectors).astype(np.int64) % sectors
    chart = np.where(mesh.face_chart >= 0, mesh.face_chart * sectors + sector, mesh.face_chart)
    return Mesh(mesh.vertices, mesh.faces, mesh.face_material, mesh.materials, chart, mesh.face_uv)


def slope_frame(clock_deg: float, u: float) -> tuple[np.ndarray, np.ndarray]:
    """The ring's bow face at a clock angle: the basis of a fitting standing on it (across, proud of the face, up the face) and
    the middle of the face, in the ring's own frame (its station at z = 0)."""
    across, outward = clock_frame(clock_deg)
    (z0, r0), (z1, r1) = RING_SLOPE
    run = math.hypot(z1 - z0, r1 - r0)
    along = ((r1 - r0) * outward + np.array([0.0, 0.0, z1 - z0])) / run
    proud = np.cross(along, across)
    middle = 0.5 * (r0 + r1) * u * outward + np.array([0.0, 0.0, 0.5 * (z0 + z1) * u])
    return np.stack([across, proud, along], axis=1), middle


SLOPE_RUN = math.hypot(RING_SLOPE[1][0] - RING_SLOPE[0][0], RING_SLOPE[1][1] - RING_SLOPE[0][1])


def on_slope(size: Sequence[float], material: Material, clock_deg: float, u: float, across: float = 0.0, lift: float = 0.0) -> Mesh:
    """A block standing on the ring's bow face (``size``: across, proud, up the face), ``across`` off the bay's middle."""
    basis, middle = slope_frame(clock_deg, u)
    return box(size, material).transformed(basis, middle + basis @ np.array([across, 0.5 * size[1] + lift, 0.0]))


# --- the bow -----------------------------------------------------------------------------------------------------------
def eye(spec: WagonSpec, style: Style) -> Built:
    """The eye frame at the bow: an open rim, a hub held by four spokes, the cross bar that carries the long spikes, the neck."""
    u = spec.u
    dark, metal, frame, void = style.material("hull_dark"), style.material("rcs"), style.material("hull_panel"), style.material("interior")
    z0, z1, r0, r1 = EYE_Z[0] * u, EYE_Z[1] * u, EYE_R[0] * u, EYE_R[1] * u
    ring = lathe([(z0, r0), (z0, r1), (z1, r1), (z1, r0), (z0, r0)], 24, frame, creases=range(1, 4))
    zm = 0.5 * (z0 + z1)
    hub = lathe([(z0, 0.0), (z0, EYE_HUB_R * u), (z1, EYE_HUB_R * u), (z1, 0.0)], 12, metal, creases=(1, 2))
    bar = 0.5 * u
    spokes = [box((2.0 * r0, bar, bar), metal, (0.0, 0.0, zm)), box((bar, 2.0 * r0, bar), metal, (0.0, 0.0, zm))]
    cross = box((2.0 * (SPIKE_X + 0.35) * u, 0.7 * u, 0.7 * u), dark, (0.0, 0.0, zm))
    n0, n1, nr = NECK[0] * u, NECK[1] * u, NECK[2] * u
    neck = lathe([(n0, 0.0), (n0, nr), (n1, nr)], 16, [void, dark], creases=(1,))  # its bow face is the dark behind the eye
    mesh = Mesh.concatenate([ring, hub, *spokes, cross, neck])
    shapes = (
        col.hull("eye", col.prism_points((0, 0, 0), (0, 0, 1), [(z0, r1), (z1, r1)], 8)),
        col.box("eye_bar", (0.0, 0.0, zm), (2.0 * (SPIKE_X + 0.35) * u, 0.7 * u, 0.7 * u)),
        col.hull("neck", col.prism_points((0, 0, 0), (0, 0, 1), [(n0, nr), (n1, nr)], 8)),
    )
    return Built(cv.Piece(part("eye", "bow", mesh)), shapes)


def cone(spec: WagonSpec, style: Style) -> Built:
    """The bow cone: eight flat faces from the neck out to the core."""
    u = spec.u
    z0, z1 = CONE[0] * u, CONE[1] * u
    a, b = regular(CONE[2] * u), regular(CORE_R * u)
    mesh = frustum(a, z0, b, z1, style.material("hull"), (style.material("hull_dark"), None))
    return Built(cv.Piece(part("cone", "bow", mesh)), (col.hull("cone", np.concatenate([at_z(a, z0), at_z(b, z1)])),))


def booms(spec: WagonSpec, style: Style) -> Built:
    """Four girders from the eye's rim to the cone's shoulders: above, below and on each side."""
    u = spec.u
    half = 0.5 * BOOM * u
    meshes, shapes = [], []
    for k, clock in enumerate((0, 90, 180, 270)):
        across, outward = clock_frame(clock)
        a = EYE_R[1] * u * outward + np.array([0.0, 0.0, EYE_Z[1] * u])
        b = (CORE_R + 0.2) * u * outward + np.array([0.0, 0.0, CONE[1] * u])
        along = (b - a) / np.linalg.norm(b - a)
        basis = np.stack([across, np.cross(along, across), along], axis=1)
        length = float(np.linalg.norm(b - a))
        meshes.append(box((2.0 * half, 2.0 * half, length), style.material("hull_panel")).transformed(basis, 0.5 * (a + b)))
        shapes.append(col.box(f"boom_{k}", 0.5 * (a + b), (2.0 * half, 2.0 * half, length), basis))
    return Built(cv.Piece(part("booms", "bow", Mesh.concatenate(meshes))), tuple(shapes))


def spikes(spec: WagonSpec, style: Style) -> list[Built]:
    """The antenna spikes: a long one on each end of the eye's cross bar, a short one under the eye."""
    u = spec.u
    metal = style.material("barrel")
    r_tip, r_root = SPIKE_R[0] * u, SPIKE_R[1] * u
    length = SPIKE_ROOT_Z * u
    long = lathe([(0.0, 0.0), (0.0, r_tip), (0.6 * length, 0.6 * r_root), (EYE_Z[0] * u, r_root), (length, r_root), (length, 0.0)], 8, metal,
                 creases=(1, 4)).translated((SPIKE_X * u, 0.0, 0.0))
    long_shape = col.capsule_between("spike_long_r", (SPIKE_X * u, 0.0, r_root), (SPIKE_X * u, 0.0, length - r_root), r_root)
    z0, y = SPIKE_SHORT[0] * u, SPIKE_SHORT[1] * u
    z1 = EYE_Z[1] * u
    short = lathe([(z0, 0.0), (z0, r_tip), (z1, 0.8 * r_root), (z1, 0.0)], 8, metal, creases=(1, 2)).translated((0.0, y, 0.0))
    short_shape = col.capsule_between("spike_short", (0.0, y, z0 + r_root), (0.0, y, z1 - r_root), r_root)
    return [Built(cv.Piece(part("spike_long_r", "bow", long), side=cv.RIGHT, fine=0.5), (long_shape,)),
            Built(cv.Piece(part("spike_short", "bow", short), fine=0.5), (short_shape,))]


# --- the core ----------------------------------------------------------------------------------------------------------
def core(spec: WagonSpec, style: Style) -> list[Built]:
    """The eight-sided core in four lengths: the plated bow block, the dark bays the frames stand in, the length inside the ring."""
    u = spec.u
    ring = regular(CORE_R * u)
    stations = (CORE_Z[0], *CORE_BREAKS, CORE_Z[1])
    paints = ("hull", "hull_dark", "hull_panel", "hull_dark")
    out = []
    for k, (z0, z1, paint) in enumerate(zip(stations[:-1], stations[1:], paints, strict=True)):
        caps = (None, style.material("hull_dark") if k == 3 else None)
        out.append(Built(cv.Piece(part(f"core_{k}", "core", frustum(ring, z0 * u, ring, z1 * u, style.material(paint), caps)))))
    body = col.hull("core", np.concatenate([at_z(ring, CORE_Z[0] * u), at_z(ring, CORE_Z[1] * u)]))
    return [Built(out[0].piece, (body,)), *out[1:]]


def frames(spec: WagonSpec, style: Style) -> Built:
    """The ten frames that carry the tubes: eight-sided plates round the core, five before the ring and five behind it."""
    u = spec.u
    ring = regular(FRAME_R * u)
    metal = style.material("hull_panel")
    half = 0.5 * FRAME_T * u
    meshes = [frustum(ring, z * u - half, ring, z * u + half, metal, (metal, metal)) for group in FRAMES_Z for z in group]
    shapes = [col.hull(f"frames_{k}", np.concatenate([at_z(ring, group[0] * u - half), at_z(ring, group[-1] * u + half)]))
              for k, group in enumerate(FRAMES_Z)]
    return Built(cv.Piece(part("frames", "core", Mesh.concatenate(meshes))), tuple(shapes))


def arms(spec: WagonSpec, style: Style) -> list[Built]:
    """The starboard deck arms from the core out to the ring, one before the ring and one behind it."""
    u = spec.u
    top, edge = style.material("hull_panel"), style.material("hull_dark")
    y = ARM_HALF * u
    fore = deck([np.array(p) * u for p in ARM_FORE], np.array(ARM_FORE_OUTLINE) * u, -y, y, top, edge)
    fore_shapes = tuple(col.hull(f"arm_fore_{k}_r", deck_points(np.array(p) * u, -y, y)) for k, p in enumerate(ARM_FORE))
    aft = deck([np.array(ARM_AFT) * u], np.array(ARM_AFT) * u, -y, y, top, edge)
    aft_shape = col.hull("arm_aft_r", deck_points(np.array(ARM_AFT) * u, -y, y))
    return [Built(cv.Piece(part("arm_fore_r", "core", fore), side=cv.RIGHT), fore_shapes),
            Built(cv.Piece(part("arm_aft_r", "core", aft), side=cv.RIGHT), (aft_shape,))]


def lattice(spec: WagonSpec, style: Style) -> Built:
    """The starboard half of the lattice in the ring's plane: in each quarter two beams crossing, from the core's side out to the
    ring, and four blocks in the crossing's corners."""
    u = spec.u
    dark, metal = style.material("hull_dark"), style.material("rcs")
    cx, cy = LATTICE_AT[0] * u, LATTICE_AT[1] * u
    width, depth = LATTICE_BEAM[0] * u, LATTICE_BEAM[1] * u
    z = RING_Z * u
    inner = RING_R[0] * u + 0.3 * u  # the beams' ends lie just inside the ring's body
    spar = ((inner - CORE_R * u, 2.0 * ARM_HALF * u, depth), (0.5 * (inner + CORE_R * u), 0.0, z))  # joins the arms through the ring
    meshes, shapes = [box(spar[0], dark, spar[1])], [col.box("lattice_spar_r", spar[1], spar[0])]
    for label, sign in (("up", 1.0), ("down", -1.0)):
        y_end = math.sqrt(inner**2 - cx**2)
        upright = ((width, y_end - ARM_HALF * u, depth), (cx, sign * 0.5 * (y_end + ARM_HALF * u), z))
        x0, x_end = (CORE_R * math.tan(math.pi / 8.0) + 0.3) * u, math.sqrt(inner**2 - cy**2)
        level = ((x_end - x0, width, depth), (0.5 * (x0 + x_end), sign * cy, z))
        for name, (size, centre) in (("upright", upright), ("level", level)):
            meshes.append(box(size, dark, centre))
            shapes.append(col.box(f"lattice_{name}_{label}_r", centre, size))
        size, off = LATTICE_BLOCK[0] * u, LATTICE_BLOCK[1] * u
        for k, turn in enumerate((0.25 * math.pi, -0.25 * math.pi)):  # the braces through the blocks
            basis = np.array([[math.cos(turn), -math.sin(turn), 0.0], [math.sin(turn), math.cos(turn), 0.0], [0.0, 0.0, 1.0]])
            brace = (2.0 * math.sqrt(2.0) * off, 0.5 * width, 0.6 * depth)
            meshes.append(box(brace, dark).transformed(basis, (cx, sign * cy, z)))
            shapes.append(col.box(f"lattice_brace_{label}_{k}_r", (cx, sign * cy, z), brace, basis))
        for k, (sx, sy) in enumerate(((1, 1), (1, -1), (-1, 1), (-1, -1))):
            centre = (cx + sx * off, sign * (cy + sy * off), z)
            meshes.append(box((size, size, 0.8 * depth), metal, centre))
            shapes.append(col.box(f"lattice_block_{label}_{k}_r", centre, (size, size, 0.8 * depth)))
    return Built(cv.Piece(part("lattice_r", "core", Mesh.concatenate(meshes)), side=cv.RIGHT), tuple(shapes))


# --- a launch tube -----------------------------------------------------------------------------------------------------
def tube_sections(spec: WagonSpec, sign: float = 1.0) -> tuple[np.ndarray, np.ndarray]:
    """A tube's outside and inside sections (x, y), in metres; ``sign`` -1 gives the lower tube's."""
    u = spec.u
    centre = (0.0, sign * TUBE_Y * u)
    return (octagon(np.array(TUBE_OUTER[0]) * u, np.array(TUBE_OUTER[1]) * u, centre),
            octagon(np.array(TUBE_INNER[0]) * u, np.array(TUBE_INNER[1]) * u, centre))


def tube_ribs() -> list[tuple[float, float]]:
    """Where a tube's ribs stand (from, to): the heavy section at each mouth, then narrow ribs at an even pitch between them."""
    z0, z1 = TUBE_Z[0] + TUBE_MOUTH, TUBE_Z[1] - TUBE_MOUTH
    count = round((z1 - z0) / TUBE_RIB[0])
    pitch = (z1 - z0) / count
    ribs = [(z0 + (k + 0.5) * pitch - 0.5 * TUBE_RIB[1], z0 + (k + 0.5) * pitch + 0.5 * TUBE_RIB[1]) for k in range(count)]
    return [(TUBE_Z[0], z0), *ribs, (z1, TUBE_Z[1])]


def tube(spec: WagonSpec, style: Style, name: str, sign: float) -> Built:
    """One launch tube, open at both ends: the wall, the lining, the rims of its mouths and the ribs round it. Its collision is
    one convex slab per wall, so the way through stays open."""
    u = spec.u
    wall, dark, mouth, inside = style.material("hull_panel"), style.material("hull_dark"), style.material("hull"), style.material("hull_dark")
    outer, inner = tube_sections(spec, sign)
    z0, z1 = TUBE_Z[0] * u, TUBE_Z[1] * u
    middle = (0.0, sign * TUBE_Y * u, 0.5 * (z0 + z1))
    meshes = [frustum(outer, z0, outer, z1, wall), lining(inner, z0, z1, inside), rim(outer, inner, z0, dark, middle), rim(outer, inner, z1, dark, middle)]
    grown = octagon((np.array(TUBE_OUTER[0]) + TUBE_COLLAR) * u, (np.array(TUBE_OUTER[1]) + 0.4 * TUBE_COLLAR) * u, (0.0, sign * TUBE_Y * u))
    ribs = tube_ribs()
    for k, (a, b) in enumerate(ribs):
        paint = mouth if k in (0, len(ribs) - 1) else dark
        at = (0.0, sign * TUBE_Y * u, 0.5 * (a + b) * u)
        meshes += [frustum(grown, a * u, grown, b * u, paint), rim(grown, outer, a * u, dark, at), rim(grown, outer, b * u, dark, at)]
    shapes = []
    for k in range(8):
        n = (k + 1) % 8
        corners = [(*p, z) for z in (z0, z1) for p in (grown[k], grown[n], inner[n], inner[k])]
        shapes.append(col.hull(f"{name}_wall_{k}", np.array(corners)))
    return Built(cv.Piece(part(name, name, Mesh.concatenate(meshes))), tuple(shapes))


# --- the ring ----------------------------------------------------------------------------------------------------------
def ring(spec: WagonSpec, style: Style) -> Built:
    """The ring: its section swept round the axis, with a collar on each face and two ribs round the rim. Its collision is the
    body in convex sectors and each collar in sectors of its own, so the way through the ring stays open."""
    u = spec.u
    hull, dark, band = style.material("hull"), style.material("hull_dark"), style.material("stripe")
    half = [(z, r) for z, r in RING_PROFILE]
    profile = half + [(-z, r) for z, r in reversed(half)]
    profile.append(profile[0])
    paints = [dark, dark, dark, hull, hull, band, band, band, dark, band, band, band, hull, hull, dark, dark, dark, dark]
    zc = RING_Z * u
    mesh = quartered(lathe([(zc + z * u, r * u) for z, r in profile], 64, paints, creases=range(1, len(profile) - 1)))
    # The body's section for the collision, its faces pushed out half a buttress so the fittings on them are covered.
    (sz, sr), (tz, tr) = RING_SLOPE
    lift = 0.5 * BUTTRESS[1]
    section = [(sz, RING_R[0]), (sz, sr + lift), (tz - lift, RING_R[1]), (-tz + lift, RING_R[1]), (-sz, sr + lift), (-sz, RING_R[0])]
    sectors = 24
    step = 2.0 * math.pi / sectors
    grow = 1.0 / math.cos(0.5 * step)  # a sector's outer corners stand out so its flat touches the radius
    shapes = []
    for k in range(sectors):
        pts = []
        for a in (k * step, (k + 1) * step):
            for z, r in section:
                radius = r * u * (grow if r > RING_R[0] else 1.0)
                pts.append((radius * math.sin(a), radius * math.cos(a), zc + z * u))
        shapes.append(col.hull(f"ring_{k:02d}", np.array(pts)))
    for label, side in (("fore", -1.0), ("aft", 1.0)):
        z0, z1 = sorted((zc + side * 11.1 * u, zc + side * 7.8 * u))
        shapes += col.ring_sectors(f"ring_collar_{label}", (0, 0, 0), (0, 0, 1), RING_R[0] * u, 22.4 * u, z0, z1, 16)
    return Built(cv.Piece(part("ring", "ring", mesh)), tuple(shapes))


def rack_clocks() -> tuple[int, ...]:
    """The bays of the ring's bow face that hold a missile rack: the four diagonals."""
    return (45, 135, 225, 315)


def ring_fittings(spec: WagonSpec, style: Style) -> list[Built]:
    """On both faces of the ring: sixteen buttresses, and between them bays in turn of three fins and of lit windows. The bow
    face's diagonal bays hold the missile racks instead of fins."""
    u = spec.u
    dark, panel, glow, bore = style.material("hull_dark"), style.material("hull_panel"), style.material("hazard"), style.material("bore")
    zc = np.array([0.0, 0.0, RING_Z * u])
    step = 360.0 / BUTTRESS_COUNT
    shared, bow_only, stern_only, racks, rack_shapes = [], [], [], [], []
    for k in range(BUTTRESS_COUNT):
        shared.append(on_slope((BUTTRESS[0] * u, BUTTRESS[1] * u, SLOPE_RUN * u), dark, (k + 0.5) * step, u))
    for k in range(BUTTRESS_COUNT):
        clock = k * step
        if k % 2:  # a window bay
            shared.append(on_slope((WINDOW[0] * u, WINDOW[1] * u, WINDOW[2] * u), dark, clock, u))
            pane = (WINDOW_PANE[0] * u, WINDOW_PANE[1] * u, WINDOW_PANE[2] * u)
            shared += [on_slope(pane, glow, clock, u, across=j * WINDOW_PANE[3] * u, lift=WINDOW[1] * u) for j in (-1, 0, 1)]
            continue
        fins = [on_slope((FIN[0] * u, FIN[1] * u, FIN[2] * u), panel, clock, u, across=j * FIN[3] * u) for j in (-1, 0, 1)]
        stern_only += fins
        if int(clock) in rack_clocks():
            size = np.array(RACK) * u
            racks.append(on_slope(size, dark, clock, u))
            cell = np.array(RACK_CELL) * u
            basis, middle = slope_frame(clock, u)
            for cx in (-1.0, 1.0):
                for cz in (-1.0, 0.0, 1.0):
                    at = middle + basis @ np.array([cx * 0.25 * size[0], size[1] + 0.5 * cell[1], cz * 0.3 * size[2]])
                    racks.append(box(cell, bore).transformed(basis, at))
            rack_shapes.append(col.box(f"rack_{int(clock):03d}", middle + basis @ np.array([0.0, 0.5 * size[1], 0.0]) + zc, size, basis))
        else:
            bow_only += fins
    both = Mesh.concatenate(shared)
    fore = Mesh.concatenate([both, *bow_only]).translated(zc)
    aft = Mesh.concatenate([both, *stern_only]).mirrored("z").translated(zc)
    return [Built(cv.Piece(part("ring_fittings", "ring", Mesh.concatenate([fore, aft])))),
            Built(cv.Piece(part("missile_racks", "ring", Mesh.concatenate(racks).translated(zc))), tuple(rack_shapes))]


# --- the engine block --------------------------------------------------------------------------------------------------
def engines(spec: WagonSpec, style: Style) -> list[Built]:
    """The engine block: the housing behind the core, a slab on the centre line with a wedge slab above and below it, and two
    rows of four nozzles between the slabs, their throats glowing."""
    u = spec.u
    dark, plate, metal, throat = style.material("hull_dark"), style.material("hull_panel"), style.material("nozzle"), style.material("nozzle_throat")
    h0, h1, hw, hh = (v * u for v in HOUSING)
    housing = box((2.0 * hw, 2.0 * hh, h1 - h0), dark, (0.0, 0.0, 0.5 * (h0 + h1)))
    out = [Built(cv.Piece(part("engine_housing", "engines", housing)), (col.box("engine_housing", (0.0, 0.0, 0.5 * (h0 + h1)), (2.0 * hw, 2.0 * hh, h1 - h0)),))]
    z0, z1 = SLAB_Z[0] * u, SLAB_Z[1] * u
    w0, w1, t = SLAB_MID[0] * u, SLAB_MID[1] * u, SLAB_MID[2] * u
    plan = [(-w0, z0), (w0, z0), (w1, z1), (-w1, z1)]
    out.append(Built(cv.Piece(part("slab_mid", "engines", deck([plan], plan, -t, t, plate, dark))), (col.hull("slab_mid", deck_points(plan, -t, t)),)))
    a0, a1, (lo0, hi0), (lo1, hi1) = SLAB_TOP
    for label, sign in (("top", 1.0), ("bottom", -1.0)):
        fore = np.array([(a0, sign * lo0), (a0, sign * hi0), (-a0, sign * hi0), (-a0, sign * lo0)]) * u
        aft = np.array([(a1, sign * lo1), (a1, sign * hi1), (-a1, sign * hi1), (-a1, sign * lo1)]) * u
        mesh = frustum(fore, z0, aft, z1, [dark, plate, dark, plate], (dark, dark))
        shape = col.hull(f"slab_{label}", np.concatenate([at_z(fore, z0), at_z(aft, z1)]))
        out.append(Built(cv.Piece(part(f"slab_{label}", "engines", mesh)), (shape,)))
    bells, shapes = [], []
    paints = [metal, dark, metal, metal, metal, dark, throat]
    for row, y in (("top", NOZZLE_Y), ("bottom", -NOZZLE_Y)):
        for k, x in enumerate(NOZZLE_X):
            at = (x * u, y * u, 0.0)
            bells.append(lathe([(z * u, r * u) for z, r in NOZZLE_PROFILE], 16, paints, creases=range(1, 7)).translated(at))
            rings = [(NOZZLE_PROFILE[0][0] * u, 2.2 * u), (NOZZLE_PROFILE[4][0] * u, 2.2 * u)]
            shapes.append(col.hull(f"nozzle_{row}_{k}_r", col.prism_points(at, (0, 0, 1), rings, 8)))
    out.append(Built(cv.Piece(part("nozzles_r", "engines", Mesh.concatenate(bells)), side=cv.RIGHT), tuple(shapes)))
    return out


def nozzles(spec: WagonSpec) -> list[tuple[str, np.ndarray, float]]:
    """Every nozzle: its name, the middle of its mouth and its radius (authored frame, metres)."""
    u = spec.u
    out = []
    for row, y in (("top", NOZZLE_Y), ("bottom", -NOZZLE_Y)):
        for x in (-NOZZLE_X[1], -NOZZLE_X[0], NOZZLE_X[0], NOZZLE_X[1]):
            side = "l" if x < 0 else "r"
            inner = "inner" if abs(x) == NOZZLE_X[0] else "outer"
            out.append((f"{row}_{inner}_{side}", np.array([x * u, y * u, NOZZLE_PROFILE[4][0] * u]), NOZZLE_PROFILE[4][1] * u))
    return out


# --- the whole ship ----------------------------------------------------------------------------------------------------
def assemble(spec: WagonSpec, style: Style) -> list[Built]:
    """Every piece in the authored frame, centre-line pieces and the starboard one of each pair."""
    built = [eye(spec, style), cone(spec, style), booms(spec, style), *spikes(spec, style)]
    built += [*core(spec, style), frames(spec, style), *arms(spec, style), lattice(spec, style)]
    built += [tube(spec, style, "tube_upper", 1.0), tube(spec, style, "tube_lower", -1.0)]
    built += [ring(spec, style), *ring_fittings(spec, style), *engines(spec, style)]
    return built


__all__ = ["Built", "WagonSpec", "assemble", "nozzles", "octagon", "rack_clocks", "regular", "slope_frame", "tube_ribs", "tube_sections"]
