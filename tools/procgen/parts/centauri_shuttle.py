"""Parts of the Centauri shuttle, 36 m long and 52 m across its upswept wing tips (M10-T58; docs/design-references.md,
"Centauri shuttle").

Built in code from the written description and the measurements of the maintainer's reference model
(``references/Centauri_Shuttle.stl``, gitignored): a flat delta body, diamond in section and deeper aft, a spine along its
back, a long blister either side of the spine, five louvres either side ahead of the stern, one large nozzle either side of
the keel, a keel pod under the stern, and outer wings that rise from the body's aft corners to tips 6.5 m above it.

The reference has no separate tail fin: what the description calls the tall swept fin is the wing tip seen from the side.

Frame (authored, metres): x to starboard, y up, z aft from the nose tip (z = 0), x and y centred on the reference
model's box. Right pieces are mirrored by the pipeline.
"""

from __future__ import annotations

from collections.abc import Sequence

import numpy as np

from ..core.civilian import RIGHT, Piece
from ..core.geometry import Mesh, lathe, loft
from ..styles import Style
from . import Anchor
from .ea_shuttle import Z_AXIS, box_of, faceted, loft_solid, piece
from .solids import lathe_solid

LENGTH_M = 36.0
# The body: z, half width, deck (y on the centre line under the spine), keel (y on the centre line), keel at half width, rim.
BODY_STATIONS = (
    (0.35, 1, -1.85, -2.65, -2.5, -2.25), (1.4, 1.95, -1.65, -2.85, -2.7, -2.25), (3, 2.55, -1.5, -2.95, -2.75, -2.2),
    (6, 3.6, -1.25, -3.25, -3, -2.15), (10, 5.05, -0.75, -3.7, -3.65, -2.1), (14, 6.5, -0.3, -4.05, -4, -2),
    (18, 8, 0.15, -4.45, -4.15, -1.95), (20.5, 9, 0.35, -4.7, -4.35, -1.9), (24, 12.6, 0.7, -5, -4.25, -1.55),
    (27, 14.2, 0.95, -5.25, -4.25, -1.6), (30, 14.8, 1.15, -5.4, -4.2, -1.9), (33.6, 15, 1.35, -5.75, -4.5, -2.2),
)  # fmt: skip
NOSE_Y = -2.25
RIM_HALF_M = 0.15
STERN_Z = BODY_STATIONS[-1][0]

# The spine: z and its top; it is 2.8 m wide at its foot and 2.0 m across its top.
SPINE_STATIONS = ((6.3, -1.2), (7.0, -0.5), (8.3, 0.25), (9.8, 0.88), (11.3, 0.95), (14.0, 1.1), (18.0, 1.3), (21.0, 1.35),
                  (24.0, 1.4), (27.0, 1.5), (30.0, 1.7), (33.0, 2.0), (34.8, 2.0))  # fmt: skip
SPINE_HALF = (1.4, 1.0)
CANOPY_SEGMENTS = 3  # the spine's first runs carry the canopy

BLISTER = ((3.66, -1.6, 17.86), (1.7, 1.45, 6.0))  # centre, radii
LOUVRE_X = (2.1, 3.7, 5.35, 7.0, 8.5)
LOUVRE_Z = (29.4, 30.4, 33.8)  # foot of the sloped front, top of it, aft end
LOUVRE_HALF_M = 0.15

NOZZLE_X, NOZZLE_Y = 3.3, -2.28
NOZZLE_PROFILE = ((32.1, 1.75), (33.6, 2.0), (35.5, 1.95))  # z, radius: the bell's outside
NOZZLE_THROAT = ((35.5, 1.6), (34.6, 1.45))
NOZZLE_EXIT_Z, NOZZLE_EXIT_R = 35.5, 1.6

KEEL_POD = ((28.2, 0.0), (28.9, 0.6), (30.0, 0.85), (33.6, 0.85), (34.7, 0.0))  # z, radius about (0, KEEL_Y)
KEEL_Y = -5.9

# The wing's sections out along the span: x, leading edge (z, y), trailing edge (z, y), the half thickness.
WING_STATIONS = (
    (11.5, 23.6, -1.25, 34.2, -3.1, 0.6), (14, 26, -0.25, 35.5, -2.8, 0.6), (16, 28, 0.95, 35.5, -1.6, 0.55),
    (18, 29, 2.2, 35.5, -0.2, 0.5), (20, 30, 3.35, 35.5, 1.3, 0.45), (22, 31, 4.55, 35.5, 2.75, 0.4),
    (24, 31.9, 5.8, 35.7, 4.3, 0.33), (25.98, 32.05, 6.66, 36, 5.2, 0.2),
)  # fmt: skip

EYE = (0.0, 0.2, 8.6)  # the pilot's eye behind the canopy


def body_ring(z: float, half_width: float, deck: float, keel: float, keel_half: float, rim: float) -> np.ndarray:
    """The body's section at ``z``: flat deck faces from the centre line down to a blunt rim, and a keel that bulges a
    little at half width. Counter-clockwise seen from astern, from the starboard rim's lower edge."""
    w, h = half_width, RIM_HALF_M
    right = [(0.5 * w, keel_half), (w, rim - h), (w, rim + h), (0.0, deck)]
    left = [(-x, y) for x, y in right[:-1][::-1]]
    return np.array([[x, y, z] for x, y in [(0.0, keel), *right, *left]])


def deck_y(x: float, z: float) -> float:
    """The deck's height over ``(x, z)``, for fittings standing on it."""
    zs = [s[0] for s in BODY_STATIONS]
    w = float(np.interp(z, zs, [s[1] for s in BODY_STATIONS]))
    deck = float(np.interp(z, zs, [s[2] for s in BODY_STATIONS]))
    rim = float(np.interp(z, zs, [s[5] for s in BODY_STATIONS])) + RIM_HALF_M
    return deck + (rim - deck) * min(abs(x) / w, 1.0)


def body_pieces(style: Style) -> list[Piece]:
    """The delta body and the spine with its canopy."""
    hull, panel, dark, glass, stripe = (style.material(r) for r in ("hull", "hull_panel", "hull_dark", "canopy_glass", "stripe"))
    rings = [np.array([[0.0, NOSE_Y, 0.0]] * 8)] + [body_ring(*s) for s in BODY_STATIONS]
    paints = [hull, hull, panel, hull, hull, panel, hull, hull]
    body = faceted(rings, paints, cap_end=dark)
    runs = ((1, 4), (4, 7), (7, 9), (9, 12))
    boxes = [box_of(np.concatenate([body_ring(*s) for s in BODY_STATIONS[a - 1 : b]]), f"body{k}") for k, (a, b) in enumerate(runs)]

    def spine_ring(z: float, top: float) -> np.ndarray:
        foot, crown = SPINE_HALF
        pts = [(foot, top - 2.0), (foot, top - 0.4), (crown, top), (-crown, top), (-foot, top - 0.4), (-foot, top - 2.0)]
        return np.array([[x, y, z] for x, y in pts])

    spine_rings = [spine_ring(*s) for s in SPINE_STATIONS]
    spine_paints = [[hull, stripe, hull, hull, None, hull] for _ in SPINE_STATIONS[1:]]
    for k in range(CANOPY_SEGMENTS):
        spine_paints[k] = [glass, glass, glass, hull, None, hull]
    spine = faceted(spine_rings, spine_paints, cap_start=hull, cap_end=dark)
    return [
        piece("body", "body", body, 60000.0, solid=loft_solid(2, [body_ring(*s) for s in BODY_STATIONS]), collision=boxes,
              anchors={"nose": Anchor((0.0, NOSE_Y, 0.0), (0.0, 0.0, -1.0))}),
        piece("spine", "body", spine, 4000.0, solid=loft_solid(2, spine_rings),
              collision=[box_of(np.concatenate(spine_rings[a : b + 1]), f"spine{k}") for k, (a, b) in enumerate(((0, 4), (4, 8), (8, 12)))],
              anchors={"eye": Anchor(EYE, (0.0, 0.0, -1.0)), "top": Anchor((0.0, SPINE_STATIONS[-2][1], 31.5), (0.0, 1.0, 0.0))}),
    ]


def ellipse_ring(z: float, centre: Sequence[float], rx: float, ry: float, points: int = 16) -> np.ndarray:
    t = np.linspace(0.0, 2.0 * np.pi, points, endpoint=False)
    return np.column_stack([centre[0] + rx * np.cos(t), centre[1] + ry * np.sin(t), np.full(points, z)])


def deck_pieces(style: Style) -> list[Piece]:
    """The fittings on the deck, each side: a long blister beside the spine and five louvres ahead of the stern."""
    hull, panel, stripe = style.material("hull"), style.material("hull_panel"), style.material("stripe")
    (cx, cy, cz), (rx, ry, rz) = BLISTER
    rings = [ellipse_ring(cz + rz * c, (cx, cy), rx * s, ry * s) for c, s in
             ((-0.97, 0.24), (-0.85, 0.53), (-0.6, 0.8), (-0.3, 0.95), (0.0, 1.0), (0.3, 0.95), (0.6, 0.8), (0.85, 0.53), (0.97, 0.24))]
    rings = [np.array([[cx, cy, cz - rz]])] + rings + [np.array([[cx, cy, cz + rz]])]
    blister = loft(rings, panel)
    louvres = []
    z0, z1, z2 = LOUVRE_Z
    for x in LOUVRE_X:
        def ring(z: float, rise: float, x: float = x) -> np.ndarray:
            foot = deck_y(x, z) - 0.6
            return np.array([[x + LOUVRE_HALF_M, foot, z], [x + LOUVRE_HALF_M, deck_y(x, z) + rise, z],
                             [x - LOUVRE_HALF_M, deck_y(x, z) + rise, z], [x - LOUVRE_HALF_M, foot, z]])
        louvres.append(faceted([ring(z0, 0.2), ring(z1, 0.8), ring(z2, 0.8)], [hull, stripe, hull, None], cap_start=hull, cap_end=hull))
    lo = np.array([LOUVRE_X[0] - LOUVRE_HALF_M, deck_y(LOUVRE_X[-1], z2) - 0.6, z0])
    hi = np.array([LOUVRE_X[-1] + LOUVRE_HALF_M, deck_y(LOUVRE_X[0], z0) + 1.1, z2])
    return [
        piece("blister_r", "body", blister, 1500.0, RIGHT, solid=loft_solid(2, rings[1:-1]), fine=0.7,
              collision=[box_of(np.concatenate(rings[1:-1]), "blister")]),
        piece("louvres_r", "stern", Mesh.concatenate(louvres), 1200.0, RIGHT, fine=0.5,
              collision=[box_of(np.array([lo, hi]), "louvres")]),
    ]


def stern_pieces(style: Style) -> list[Piece]:
    """The keel pod under the stern and one big nozzle either side of it."""
    hull, dark, nozzle, throat = (style.material(r) for r in ("hull", "hull_dark", "nozzle", "nozzle_throat"))
    pod = lathe(list(KEEL_POD), 16, hull).transformed(np.diag([1.3, 1.0, 1.0]), (0.0, KEEL_Y, 0.0))  # wider than deep
    strut = faceted([np.array([[0.3, KEEL_Y, z], [0.3, -4.6, z], [-0.3, -4.6, z], [-0.3, KEEL_Y, z]]) for z in (29.0, 33.4)], dark,
                    cap_start=dark, cap_end=dark)
    outer, inner = list(NOZZLE_PROFILE), list(NOZZLE_THROAT)
    profile = [(outer[0][0], 0.0), *outer, *inner, (inner[-1][0], 0.0)]
    bell = lathe(profile, 24, [dark, nozzle, nozzle, nozzle, throat, throat], creases=(1, 2, 3, 4, 5)).translated((NOZZLE_X, NOZZLE_Y, 0.0))
    anchors = {"main": Anchor((NOZZLE_X, NOZZLE_Y, NOZZLE_EXIT_Z), Z_AXIS), "centre": Anchor((NOZZLE_X, NOZZLE_Y, 33.8))}
    return [
        piece("keel", "stern", [pod, strut], 2000.0, solid=lathe_solid(KEEL_POD).translated((0.0, KEEL_Y, 0.0)), fine=0.7,
              collision=[box_of(np.array([[-1.1, KEEL_Y - 0.85, 28.2], [1.1, -4.6, 34.7]]), "keel")]),
        piece("engine_r", "stern", bell, 3000.0, RIGHT, solid=lathe_solid(outer).translated((NOZZLE_X, NOZZLE_Y, 0.0)), fine=0.7,
              anchors=anchors, collision=[box_of(np.array([[NOZZLE_X - 2.0, NOZZLE_Y - 2.0, 32.1], [NOZZLE_X + 2.0, NOZZLE_Y + 2.0, 35.5]]), "nozzle")]),
    ]


def wing_ring(x: float, lead_z: float, lead_y: float, trail_z: float, trail_y: float, half: float) -> np.ndarray:
    """A wing section at span ``x``: a blunt leading edge, a thick point at 40 % chord and a sharp trailing edge."""
    mid_z, mid_y = lead_z + 0.4 * (trail_z - lead_z), lead_y + 0.4 * (trail_y - lead_y)
    return np.array([[x, lead_y - 0.3 * half, lead_z], [x, mid_y - half, mid_z], [x, trail_y, trail_z], [x, mid_y + half, mid_z],
                     [x, lead_y + 0.3 * half, lead_z]])


def wing_pieces(style: Style) -> list[Piece]:
    """The starboard wing, from inside the body's aft corner up to its tip."""
    hull, panel, stripe = style.material("hull"), style.material("hull_panel"), style.material("stripe")
    rings = [wing_ring(*s) for s in WING_STATIONS]
    mesh = faceted(rings, [hull, hull, hull, panel, stripe], cap_start=hull, cap_end=stripe)
    boxes = []
    for k, (a, b) in enumerate(((0, 2), (2, 4), (4, 6), (6, 7))):
        run = np.concatenate(rings[a : b + 1])
        along = rings[b].mean(axis=0) - rings[a].mean(axis=0)
        u = along / np.linalg.norm(along)
        n = np.cross(Z_AXIS, u)
        n /= np.linalg.norm(n)
        boxes.append(box_of(run, f"span{k}", np.column_stack([u, n, np.cross(u, n)])))
    tip = WING_STATIONS[-1]
    return [piece("wing_r", "wing_r", mesh, 5000.0, RIGHT, collision=boxes, fine=0.7,
                  anchors={"tip": Anchor((tip[0], 0.5 * (tip[2] + tip[4]), 0.5 * (tip[1] + tip[3])), (1.0, 0.0, 0.0)),
                           "joint": Anchor((13.0, -1.6, 29.0))})]


def assemble(style: Style) -> list[Piece]:
    """Every piece of the shuttle in the authored frame (centre pieces and the starboard of each pair)."""
    return [*body_pieces(style), *deck_pieces(style), *stern_pieces(style), *wing_pieces(style)]

