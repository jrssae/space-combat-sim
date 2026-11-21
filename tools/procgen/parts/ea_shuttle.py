"""Parts of the Earth Alliance shuttle, 18.64 m (M10-T57; docs/design-references.md, "EA shuttle").

Built in code from the written description and the measurements of the maintainer's reference model (``references/EA
Shuttle.stl``, gitignored): a blunt octagonal box hull whose nose tapers to a small face, a cockpit hood on the nose's
top slope, six framed blocks along each flank, pipe runs on the roof and the keel, a raised spine and a tall plate at
the stern with the hatch, a box on each chine aft, and six flaps flaring out behind the stern bulkhead.

Frame (authored, metres): x to starboard, y up, z aft from the nose block's face (z = 0), x and y centred on the
reference model's box; the hull's own centre line lies at y = -0.31. Right pieces are mirrored by the pipeline.

The small helpers at the top (faceted lofts, plates, bars) are shared with ``parts/ea_atmo_shuttle.py``.
"""

from __future__ import annotations

from collections.abc import Sequence

import numpy as np

from ..core.civilian import CENTRE, RIGHT, Piece
from ..core.geometry import Material, Mesh, box, lathe
from ..styles import Style
from . import Anchor, Collision, Part
from .narn import LoftSolid
from .solids import Solid, box_solid

LENGTH_M = 18.64
AXIS_Y = -0.31  # the hull's centre line: the engines' thrust line
X_AXIS, Y_AXIS, Z_AXIS = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)

# The hull's octagon at each station: z, top (y, half width), flank (half width, y top, y bottom), keel (y, half width).
HULL_STATIONS = (
    (0.55, 0.39, 1.97, 2.02, 0.35, -0.97, -1.01, 1.97),
    (1.17, 0.55, 2.00, 2.25, 0.35, -0.97, -1.17, 2.00),
    (2.00, 0.76, 2.00, 2.58, 0.35, -0.97, -1.38, 2.00),
    (5.45, 1.65, 2.00, 3.98, 0.35, -0.97, -2.27, 2.00),
)
CABIN = HULL_STATIONS[-1][1:]  # the section that runs level from the nose's end to the stern bulkhead
CABIN_Z = (5.45, 12.8, 17.41)  # the cabin's start, the cut between the cabin and stern chunks, the bulkhead
FLANK_BLOCK_Z = tuple(5.71 + 1.83 * k for k in range(6))  # each flank block's forward end
FLANK_BLOCK_LENGTH = 1.32
CHINE_NORMAL = np.array([1.30, 1.98]) / float(np.hypot(1.30, 1.98))  # out of the upper starboard chine face, in x and y
ENGINE_FACE_Z = 17.93
ENGINE_X = 2.36  # each engine panel's centre on the stern bulkhead's wing plates
EYE = (0.0, 1.2, 2.9)  # the pilot's eye behind the hood's window


# --- shared helpers --------------------------------------------------------------------------------------------------------
def faceted(rings: Sequence[np.ndarray], paints: Material | Sequence, cap_start: Material | None = None,
            cap_end: Material | None = None) -> Mesh:
    """A solid skinned through closed rings of equal size, every face flat with its own corners so its edges stay hard.
    ``paints`` is one material, one per ring edge (edge k runs from corner k to k + 1), or such a list per segment; a
    ``None`` edge gets no faces. The rings may wind either way; a ``None`` cap leaves that end open."""
    rings = [np.asarray(ring, dtype=float).reshape(-1, 3) for ring in rings]
    n, segments = len(rings[0]), len(rings) - 1
    if isinstance(paints, Material):
        paints = [paints] * n
    per_segment = [list(paints)] * segments if not isinstance(paints[0], (list, tuple)) else [list(p) for p in paints]
    widest = max(rings, key=lambda ring: float(np.linalg.norm(_ring_normal(ring))))
    turned = float(_ring_normal(widest) @ (rings[-1].mean(axis=0) - rings[0].mean(axis=0))) < 0.0
    table: list[Material] = []
    verts: list[np.ndarray] = []
    faces: list[list[int]] = []
    mats: list[int] = []

    def add(poly: Sequence[np.ndarray], material: Material | None) -> None:
        if material is None:
            return
        if material not in table:
            table.append(material)
        base = sum(len(v) for v in verts)
        verts.append(np.asarray(poly[::-1] if turned else poly, dtype=float))
        for k in range(1, len(poly) - 1):
            faces.append([base, base + k, base + k + 1])
            mats.append(table.index(material))

    for (a, b), edge in zip(zip(rings[:-1], rings[1:], strict=True), per_segment, strict=True):
        for k in range(n):
            j = (k + 1) % n
            add([a[k], a[j], b[j], b[k]], edge[k])
    add(list(rings[0][::-1]), cap_start)
    add(list(rings[-1]), cap_end)
    mesh = Mesh(np.concatenate(verts), np.array(faces), np.array(mats), tuple(table))
    return mesh.face_subset(mesh.face_areas() > 1e-9)


def _ring_normal(ring: np.ndarray) -> np.ndarray:
    centre = ring.mean(axis=0)
    return np.cross(ring - centre, np.roll(ring, -1, axis=0) - centre).sum(axis=0)


def rect_ring(axis: int, at: float, lo: Sequence[float], hi: Sequence[float]) -> np.ndarray:
    """A rectangle standing across ``axis`` at ``at``; ``lo`` and ``hi`` bound it in the other two axes, in axis order."""
    a, b = [i for i in range(3) if i != axis]
    ring = np.zeros((4, 3))
    ring[:, axis] = at
    ring[:, a] = (lo[0], hi[0], hi[0], lo[0])
    ring[:, b] = (lo[1], lo[1], hi[1], hi[1])
    return ring


def block(lo: Sequence[float], hi: Sequence[float], material: Material) -> Mesh:
    """An axis-aligned box from its two corners."""
    lo, hi = np.asarray(lo, dtype=float), np.asarray(hi, dtype=float)
    return box(tuple(hi - lo), material, tuple(0.5 * (lo + hi)))


def bar_z(x: float, y: float, z0: float, z1: float, radius: float, material: Material, segments: int = 10) -> Mesh:
    """A round bar along z: a pipe run."""
    tube = lathe([(z0, 0.0), (z0, radius), (z1, radius), (z1, 0.0)], segments, material, creases=(1, 2))
    return tube.translated((x, y, 0.0))


def loft_solid(axis: int, rings: Sequence[np.ndarray]) -> Solid:
    """The burial volume of a loft whose convex sections stand across ``axis``."""
    rings = [np.asarray(ring, dtype=float) for ring in rings]
    others = [i for i in range(3) if i != axis]
    loft = LoftSolid(axis, tuple(float(ring[0, axis]) for ring in rings), tuple(ring[:, others] for ring in rings))
    points = np.concatenate(rings)
    return Solid(lambda p, m: loft.contains(p, m), (points.min(axis=0), points.max(axis=0)))


def box_of(points: np.ndarray, name: str, basis: np.ndarray | None = None) -> Collision:
    """The smallest box with the given axes (columns of ``basis``) round some points."""
    b = np.eye(3) if basis is None else np.asarray(basis, dtype=float)
    local = np.asarray(points, dtype=float).reshape(-1, 3) @ b
    lo, hi = local.min(axis=0), local.max(axis=0)
    return Collision("box", b @ (0.5 * (lo + hi)), size=tuple(hi - lo), basis=b, name=name)


def face_slabs(rings: Sequence[np.ndarray], names: Sequence[str | None], depth: float) -> list[Collision]:
    """A loft's flat sides as hit volumes: per ring edge with a name, one box lying in that side's plane, ``depth`` deep
    into the loft, so slanted faces are covered without a box standing proud of them."""
    rings = [np.asarray(ring, dtype=float) for ring in rings]
    n = len(rings[0])
    axis = np.concatenate(rings).mean(axis=0)
    out = []
    for k, name in enumerate(names):
        if name is None:
            continue
        j = (k + 1) % n
        face = np.concatenate([[ring[k], ring[j]] for ring in rings])
        along = rings[-1][k] + rings[-1][j] - rings[0][k] - rings[0][j]
        normal = np.cross(rings[0][j] - rings[0][k], along)
        normal /= np.linalg.norm(normal)
        if normal @ (face.mean(axis=0) - axis) < 0.0:
            normal = -normal
        u = along / np.linalg.norm(along)
        out.append(box_of(np.concatenate([face, face - depth * normal]), name, np.column_stack([u, normal, np.cross(u, normal)])))
    return out


def piece(name: str, group: str, meshes: Mesh | Sequence[Mesh], mass_kg: float, side: str = CENTRE, solid: Solid | None = None,
          collision: Sequence[Collision] = (), anchors: dict[str, Anchor] | None = None, fine: float = 1.0) -> Piece:
    mesh = meshes if isinstance(meshes, Mesh) else Mesh.concatenate(meshes)
    return Piece(Part(name, mesh, dict(anchors or {}), list(collision), mass_kg, group), solid, side, fine)


# --- the hull ----------------------------------------------------------------------------------------------------------------
def hull_ring(z: float, top_y: float, top_w: float, flank_w: float, flank_top: float, flank_bottom: float, keel_y: float,
              keel_w: float) -> np.ndarray:
    """The hull's eight corners at ``z``, counter-clockwise seen from astern, from the starboard flank's foot: the edges are the
    starboard flank, the upper chine, the roof, the port upper chine, the port flank, its lower chine, the keel, the lower chine."""
    return np.array([[flank_w, flank_bottom, z], [flank_w, flank_top, z], [top_w, top_y, z], [-top_w, top_y, z],
                     [-flank_w, flank_top, z], [-flank_w, flank_bottom, z], [-keel_w, keel_y, z], [keel_w, keel_y, z]])


def flank_half_width(z: float) -> float:
    """The hull's half width at ``z``: the nose's taper, then the cabin."""
    return float(np.interp(z, [s[0] for s in HULL_STATIONS], [s[3] for s in HULL_STATIONS]))


def roof_y(z: float) -> float:
    return float(np.interp(z, [s[0] for s in HULL_STATIONS], [s[1] for s in HULL_STATIONS]))


HULL_SIDES = ("flank_r", "chine_up_r", "roof", "chine_up_l", "flank_l", "chine_down_l", "keel", "chine_down_r")  # ``hull_ring``'s edges
HULL_SLAB_M = 0.8  # how deep the hull's hit volumes reach under its skin


def hull_pieces(style: Style) -> list[Piece]:
    """The hull in its three chunks: the tapered nose, the cabin and the stern, each closed where it meets the next."""
    hull, dark, inside = style.material("hull"), style.material("hull_dark"), style.material("interior")
    nose = [hull_ring(*s) for s in HULL_STATIONS]
    cabin = [hull_ring(z, *CABIN) for z in CABIN_Z]
    nose_boxes = [*face_slabs(nose, HULL_SIDES, HULL_SLAB_M), box_of(np.array([[-2.02, -1.17, 0.0], [2.02, 0.55, HULL_STATIONS[1][0]]]), "tip")]
    # A box down the hull's middle, inside the chines: it closes the hit volumes at the bulkhead and where a chunk breaks off.
    cores = [box_of(np.array([[-3.0, -1.6, z0], [3.0, 1.0, z1]]), "core") for z0, z1 in zip(CABIN_Z[:-1], CABIN_Z[1:], strict=True)]
    return [
        piece("hull_bow", "bow", faceted(nose, hull, cap_start=hull, cap_end=inside), 9000.0, solid=loft_solid(2, nose),
              collision=nose_boxes),
        piece("hull_cabin", "cabin", faceted(cabin[:2], hull, cap_start=inside, cap_end=inside), 16000.0,
              solid=loft_solid(2, cabin[:2]), collision=[*face_slabs(cabin[:2], HULL_SIDES, HULL_SLAB_M), cores[0]]),
        piece("hull_stern", "stern", faceted(cabin[1:], hull, cap_start=inside, cap_end=dark), 12000.0,
              solid=loft_solid(2, cabin[1:]), collision=[*face_slabs(cabin[1:], HULL_SIDES, HULL_SLAB_M), cores[1]]),
    ]


def bow_pieces(style: Style) -> list[Piece]:
    """What the nose carries: the docking and sensor blocks on its face (off centre, as the reference has them), the cockpit
    hood with its window, and the pipe runs along each flank."""
    hull, dark, glass, frame = (style.material(r) for r in ("hull", "hull_dark", "canopy_glass", "canopy_frame"))
    face = [block((-1.80, -0.75, 0.0), (0.10, 0.20, 0.62), dark), block((0.45, -0.61, 0.41), (1.68, -0.07, 0.62), dark)]
    hood_rings = [rect_ring(2, 2.51, (-1.50, 0.80), (1.50, 1.55)), rect_ring(2, 4.40, (-1.70, 1.30), (1.70, 1.62)),
                  rect_ring(2, 5.50, (-1.74, 1.58), (1.74, 1.66))]
    hood = faceted(hood_rings, hull, cap_start=glass, cap_end=hull)
    rim = faceted([rect_ring(2, 2.45, (-1.56, 0.80), (1.56, 1.61)), rect_ring(2, 2.56, (-1.56, 0.80), (1.56, 1.61))],
                  frame, cap_end=frame)  # the window's frame: a band round the hood's face, open where the glass shows
    manifold = [block((sx * 0.42, 1.50, 4.05), (sx * 0.92, 1.88, 5.40), dark) for sx in (1.0, -1.0)]
    out = [
        piece("nose_blocks", "bow", face, 600.0, solid=box_solid((1.9, 0.95, 0.62), (-0.85, -0.275, 0.31))),
        piece("hood", "bow", [hood, _frame_only(rim), *manifold], 900.0, solid=loft_solid(2, hood_rings),
              collision=[box_of(np.array([[-1.74, 0.80, 2.45], [1.74, 1.88, 5.50]]), "hood")], anchors={"eye": Anchor(EYE, (0.0, 0.0, -1.0))}),
    ]
    # The flank pipes: a slab lying against the nose's slanted flank.
    z0, z1 = 0.75, 5.30
    slab = [np.array([[flank_half_width(z) - 0.05, -0.87, z], [flank_half_width(z) + 0.17, -0.87, z],
                      [flank_half_width(z) + 0.17, 0.36, z], [flank_half_width(z) - 0.05, 0.36, z]]) for z in (z0, z1)]
    run = slab[1].mean(axis=0) - slab[0].mean(axis=0)
    run /= np.linalg.norm(run)
    lying = np.column_stack([np.cross(Y_AXIS, run), Y_AXIS, run])  # the box lies along the slanted flank
    out.append(piece("nose_pipes_r", "bow", faceted(slab, dark, cap_start=dark, cap_end=dark), 250.0, RIGHT,
                     collision=[box_of(np.concatenate(slab), "pipes", lying)]))
    return out


def _frame_only(rim: Mesh) -> Mesh:
    """The window frame without the face that would cover the glass: only the band's outer walls."""
    keep = np.abs(rim.face_normals()[:, 2]) < 0.5
    return rim.face_subset(keep)


def cabin_pieces(style: Style) -> list[Piece]:
    """What the cabin carries: the flank blocks, the roof's pipe runs and ridge, the keel's pipes and boxes."""
    hull, panel, dark = style.material("hull"), style.material("hull_panel"), style.material("hull_dark")
    flank_w, flank_top, flank_bottom = CABIN[2], CABIN[3], CABIN[4]

    def flank_block(z: float) -> Mesh:
        rings = [rect_ring(0, flank_w - 0.05, (flank_bottom, z), (flank_top, z + FLANK_BLOCK_LENGTH)),
                 rect_ring(0, flank_w + 0.42, (flank_bottom + 0.12, z + 0.12), (flank_top - 0.12, z + FLANK_BLOCK_LENGTH - 0.12))]
        return faceted(rings, hull, cap_end=panel)

    roof = CABIN[0]
    pipes = [bar_z(x, roof + 0.17, 5.68, 14.25, 0.145, dark) for x in (1.145, 1.44, 1.735)]
    pipes += [bar_z(x, roof + 0.15, 5.68, 8.07, 0.145, dark) for x in (0.43, 0.775)]
    pipes += [block((0.14, roof - 0.06, 5.27), (1.44, roof + 0.35, 5.80), panel), block((0.20, roof - 0.01, 7.88), (1.22, roof + 0.32, 8.64), panel)]
    ridge = [rect_ring(2, 9.04, (-0.30, 1.48), (0.30, 1.70)), rect_ring(2, 9.80, (-0.48, 1.48), (0.48, 2.13)),
             rect_ring(2, 12.90, (-0.48, 1.48), (0.48, 2.13)), rect_ring(2, 13.47, (-0.40, 1.48), (0.40, 1.95))]
    keel = CABIN[5]
    under = [block((0.28, keel - 0.36, 5.89), (0.57, keel + 0.07, 8.06), dark), block((0.64, keel - 0.36, 5.89), (0.92, keel + 0.07, 8.06), dark),
             block((0.20, keel - 0.31, 7.88), (1.22, keel + 0.02, 8.64), panel),
             bar_z(1.49, keel - 0.08, 8.47, 14.20, 0.075, dark, 8), bar_z(1.28, keel - 0.07, 8.45, 14.41, 0.06, dark, 8)]
    return [
        piece("flank_blocks_r", "cabin", [flank_block(z) for z in FLANK_BLOCK_Z[:4]], 1200.0, RIGHT,
              collision=[box_of(np.array([[flank_w, flank_bottom, FLANK_BLOCK_Z[0]], [flank_w + 0.42, flank_top, FLANK_BLOCK_Z[3] + FLANK_BLOCK_LENGTH]]), "blocks")]),
        piece("flank_blocks_aft_r", "stern", [flank_block(z) for z in FLANK_BLOCK_Z[4:]], 600.0, RIGHT,
              collision=[box_of(np.array([[flank_w, flank_bottom, FLANK_BLOCK_Z[4]], [flank_w + 0.42, flank_top, FLANK_BLOCK_Z[5] + FLANK_BLOCK_LENGTH]]), "blocks")]),
        piece("roof_pipes_r", "cabin", pipes, 500.0, RIGHT, collision=[box_of(np.array([[0.14, roof, 5.27], [1.88, roof + 0.35, 14.25]]), "pipes")]),
        piece("ridge", "cabin", faceted(ridge, panel, cap_start=panel, cap_end=panel), 400.0, solid=loft_solid(2, ridge),
              collision=[box_of(np.concatenate(ridge), "ridge")]),
        piece("keel_pipes_r", "cabin", under, 450.0, RIGHT,
              collision=[box_of(np.array([[0.20, keel - 0.36, 5.89], [1.22, keel, 8.64]]), "fore"), box_of(np.array([[1.22, keel - 0.16, 8.45], [1.57, keel, 14.41]]), "aft")]),
    ]


def stern_pieces(style: Style) -> list[Piece]:
    """The stern: the raised spine and the tall plate with the hatch, the roof's cross fins, the boxes on the chines, the
    bulkhead's wing plates with the engine panels, and the six flaps flaring out behind."""
    hull, panel, dark, frame = (style.material(r) for r in ("hull", "hull_panel", "hull_dark", "canopy_frame"))
    throat, nozzle = style.material("nozzle_throat"), style.material("nozzle")
    roof, keel = CABIN[0], CABIN[5]

    def spine_ring(z: float, w: float, crown_w: float, crown: float) -> np.ndarray:
        return np.array([[w, 1.50, z], [crown_w, crown, z], [-crown_w, crown, z], [-w, 1.50, z]])

    spine = [spine_ring(10.87, 0.80, 0.72, 1.77), spine_ring(13.92, 1.02, 0.88, 2.39), spine_ring(17.20, 1.02, 0.88, 2.39)]
    plate = [np.array([[1.02, -1.67, z], [1.02, 1.60, z], [0.88, 2.39, z], [-0.88, 2.39, z], [-1.02, 1.60, z], [-1.02, -1.67, z],
                       [-0.74, -2.25, z], [0.74, -2.25, z]]) for z in (17.20, 18.07)]
    hatch = [block((-0.60, -1.77, 18.00), (0.60, 1.25, 18.27), frame), block((-0.40, -1.45, 18.27), (0.40, 0.95, 18.30), dark)]
    fins = [block((-1.94, roof - 0.05, z), (1.94, 2.31, z + 0.29), panel) for z in (15.28, 15.84, 16.40)]
    crown = block((-0.56, 2.30, 14.13), (0.56, 2.63, 14.94), panel)
    corner_boxes = [block((1.12, roof - 0.05, 14.13), (1.94, roof + 0.34, 14.94), panel), block((1.12, keel - 0.33, 14.13), (1.94, keel + 0.05, 14.94), panel)]

    # The box on the upper starboard chine: its foot sunk a little into the chine's face, its ends chamfered.
    foot = np.array([[3.82, 0.46], [2.25, 1.47]]) - 0.10 * CHINE_NORMAL
    face = np.array([[4.02, 1.00], [2.71, 1.88]])
    low = foot + 0.20 * CHINE_NORMAL

    def chine_ring(z: float, top: np.ndarray, flip: bool) -> np.ndarray:
        pts = np.array([foot[0], top[0], top[1], foot[1]])
        if flip:  # the lower chine's box: mirrored about the hull's centre line
            pts = np.column_stack([pts[:, 0], 2.0 * AXIS_Y - pts[:, 1]])
        return np.column_stack([pts, np.full(4, z)])

    def chine_box(flip: bool) -> Mesh:
        rings = [chine_ring(14.37, low, flip), chine_ring(14.65, face, flip), chine_ring(16.81, face, flip), chine_ring(17.09, low, flip)]
        return faceted(rings, [hull, panel, hull, None], cap_start=hull, cap_end=hull)

    def chine_collision(flip: bool, name: str) -> Collision:
        turn = np.array([[CHINE_NORMAL[1], CHINE_NORMAL[0], 0.0], [-CHINE_NORMAL[0], CHINE_NORMAL[1], 0.0], [0.0, 0.0, 1.0]])
        if flip:
            turn = np.diag([1.0, -1.0, 1.0]) @ turn @ np.diag([1.0, -1.0, 1.0])
        return box_of(np.concatenate([chine_ring(14.37, face, flip), chine_ring(17.09, face, flip)]), name, turn)

    wing_rings = [rect_ring(0, 0.93, (-1.12, 17.45), (0.50, ENGINE_FACE_Z)), rect_ring(0, 3.80, (-0.62, 17.45), (0.00, ENGINE_FACE_Z))]
    wing = faceted(wing_rings, dark, cap_start=dark, cap_end=dark)
    panel_rings = [rect_ring(2, ENGINE_FACE_Z - 0.02, (1.25, -0.90), (3.45, 0.28)), rect_ring(2, ENGINE_FACE_Z + 0.03, (1.32, -0.83), (3.38, 0.21))]
    engine = faceted(panel_rings, nozzle, cap_end=throat)
    brace = block((2.84, -1.09, 17.34), (3.46, 0.68, 17.60), dark)

    # The flaps: plates hinged on the bulkhead's edge, flaring outwards to their trailing edge.
    thick = 0.15 * CHINE_NORMAL
    diag = [np.array([[3.82, 0.42, 17.41], [3.82 + thick[0], 0.42 + thick[1], 17.41], [2.06 + thick[0], 1.55 + thick[1], 17.41], [2.06, 1.55, 17.41]]),
            np.array([[4.00, 0.92, 18.62], [4.14, 0.98, 18.62], [2.64, 2.00, 18.62], [2.63, 1.86, 18.62]])]
    lower = [ring * np.array([1.0, -1.0, 1.0]) + np.array([0.0, 2.0 * AXIS_Y, 0.0]) for ring in diag]
    lower[1][:, 2] = LENGTH_M
    side = [rect_ring(2, 17.41, (3.90, -0.97), (4.05, 0.35)), rect_ring(2, 18.55, (4.46, -0.73), (4.60, 0.12))]
    rails = [block((4.00, y, 15.96), (4.45, y + 0.14, 18.31), dark) for y in (-0.68, -0.04)]
    flaps = [faceted(r, panel, cap_start=panel, cap_end=panel) for r in (diag, lower, side)]
    flap_boxes = [box_of(np.concatenate(r), f"flap{k}") for k, r in enumerate((diag, lower, side))]
    flap_boxes.append(box_of(np.array([[4.00, -0.68, 15.96], [4.45, 0.10, 18.31]]), "rails"))
    rise = spine[1].mean(axis=0) - spine[0].mean(axis=0)
    rise /= np.linalg.norm(rise)
    ramp = np.column_stack([X_AXIS, np.cross(rise, X_AXIS), rise])  # the box leans with the spine's ramp
    return [
        piece("spine", "stern", faceted(spine, hull, cap_start=hull, cap_end=hull), 1500.0, solid=loft_solid(2, spine),
              collision=[box_of(np.concatenate(spine[:2]), "ramp", ramp), box_of(np.concatenate(spine[1:]), "spine")]),
        piece("stern_plate", "stern", [faceted(plate, hull, cap_start=hull, cap_end=panel), *hatch], 1800.0, solid=loft_solid(2, plate),
              collision=[box_of(np.concatenate(plate), "plate"), box_of(np.array([[-0.60, -1.77, 18.00], [0.60, 1.25, 18.30]]), "hatch")],
              anchors={"hatch": Anchor((0.0, AXIS_Y, 18.30), Z_AXIS)}),
        piece("roof_fins", "stern", [*fins, crown], 500.0,
              collision=[box_of(np.array([[-1.94, roof, 15.28], [1.94, 2.31, 16.69]]), "fins"), box_of(np.array([[-0.56, 2.30, 14.13], [0.56, 2.63, 14.94]]), "crown")],
              anchors={"top": Anchor((0.0, 2.63, 14.53), Y_AXIS)}),
        piece("corner_boxes_r", "stern", corner_boxes, 300.0, RIGHT,
              collision=[box_of(np.array([[1.12, roof, 14.13], [1.94, roof + 0.34, 14.94]]), "up"), box_of(np.array([[1.12, keel - 0.33, 14.13], [1.94, keel, 14.94]]), "down")]),
        piece("chine_box_up_r", "stern", chine_box(False), 700.0, RIGHT, collision=[chine_collision(False, "box")]),
        piece("chine_box_down_r", "stern", chine_box(True), 700.0, RIGHT, collision=[chine_collision(True, "box")]),
        piece("engine_r", "stern", [wing, engine, brace], 1600.0, RIGHT, collision=[box_of(np.concatenate(wing_rings), "wing")],
              anchors={"main": Anchor((ENGINE_X, AXIS_Y, ENGINE_FACE_Z + 0.03), Z_AXIS), "centre": Anchor((ENGINE_X, AXIS_Y, 17.0))}),
        piece("flaps_r", "stern", [*flaps, *rails], 600.0, RIGHT, collision=flap_boxes, fine=0.6,
              anchors={"side": Anchor((4.60, AXIS_Y, 18.4), X_AXIS)}),
    ]


def assemble(style: Style) -> list[Piece]:
    """Every piece of the shuttle in the authored frame (centre pieces and the starboard of each pair)."""
    return [*hull_pieces(style), *bow_pieces(style), *cabin_pieces(style), *stern_pieces(style)]
