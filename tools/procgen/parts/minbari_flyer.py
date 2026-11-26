"""Parts of the Minbari Flyer, 40 m long and 18.5 m across (M10-T58, Q67; docs/design-references.md, "Minbari Flyer").

Built in code from the written description and the measurements of the maintainer's reference model
(``references/Minbari_Flyer_diplomat_transport_40m.stl``, gitignored). Semi-organic (Q47): every piece is a smooth loft
of ellipses. A round fuselage, fullest a quarter of the way back, its nose a ring of petals, tapering to a long tail
spike; a pod either side of it, joined by a thin web to a tall blade at each side of the bow, each blade with two small
thruster pods at its front and a small thruster pod just inside it; a flat strake along each flank from the pods to the tail; four small pods round the waist; a
straight crossbar at 75 % carrying a spindle at each tip, tall as a blade, with a forward tube. The gun pods, the blades'
thruster pods and the small inner pods each open forward in a dark hole (M10 Q97).

Frame (authored, metres): x to starboard, y up, z aft from the nose tip (z = 0), x and y centred on the reference
model's box. Right pieces are mirrored by the pipeline.
"""

from __future__ import annotations

from collections.abc import Sequence

import numpy as np

from ..core.civilian import RIGHT, Piece
from ..core.geometry import Material, Mesh, lathe, loft
from ..styles import Style
from . import Anchor, Collision
from .ea_shuttle import Z_AXIS, box_of, faceted, loft_solid, piece
from .solids import lathe_solid

LENGTH_M = 40.0
RING_POINTS = 20

# The fuselage: z, radius.
BODY_PROFILE = (
    (0.6, 0.0), (0.75, 0.6), (1.0, 1.0), (1.4, 1.4), (2.0, 1.87), (3.0, 2.4), (4.0, 2.73), (5.0, 2.9), (6.0, 2.98), (8.0, 3.05), (10.0, 3.05),
    (11.0, 3.0), (12.0, 2.96), (13.0, 2.86), (14.0, 2.72), (15.0, 2.57), (16.0, 2.4), (17.0, 2.22), (18.0, 2.04), (19.0, 1.86),
    (20.0, 1.7), (21.0, 1.55), (22.0, 1.42), (23.0, 1.31), (24.0, 1.2), (25.0, 1.11), (26.0, 1.03), (27.0, 0.96), (28.0, 0.9),
    (30.0, 0.86), (35.0, 0.85), (36.0, 0.79), (37.0, 0.68), (38.0, 0.47), (39.0, 0.2), (39.6, 0.0),
)  # fmt: skip
PETALS = 12
PETAL_DEPTH = 0.07  # how far the nose's petals stand out, a share of the radius
PETAL_END_Z = 6.0

# The flank pods: z, centre x, half width, half height.
POD_STATIONS = (
    (3.3, 3.8, 0.0, 0.0), (3.6, 3.8, 0.8, 0.95), (4.5, 3.8, 1.1, 1.3), (7.0, 3.8, 1.15, 1.45), (10.0, 3.8, 1.15, 1.35),
    (13.0, 3.8, 1.15, 1.1), (16.0, 3.8, 1.15, 0.95), (17.5, 3.8, 1.12, 0.75), (18.1, 3.8, 0.9, 0.5), (18.4, 3.8, 0.0, 0.0),
)  # fmt: skip
# The web from pod to blade: z, inner x, outer x, half thickness.
WEB_STATIONS = (
    (2.3, 7.2, 7.6, 0.3), (3.0, 6.5, 7.6, 0.4), (4.0, 5.5, 7.6, 0.4), (5.0, 4.5, 7.6, 0.4), (8.0, 4.5, 7.6, 0.3), (10.0, 4.5, 7.6, 0.19),
    (13.0, 4.5, 7.6, 0.19),
    (14.5, 4.5, 7.1, 0.19), (15.0, 4.5, 6.75, 0.19), (16.0, 4.5, 6.2, 0.19), (17.0, 4.5, 5.65, 0.19), (18.0, 4.5, 5.07, 0.17),
)  # fmt: skip
# The bow blades: z, centre x, half width, half height.
BLADE_STATIONS = (
    (0.3, 8.15, 0, 0), (1, 8.15, 0.5, 2), (2, 8.15, 0.65, 3.3), (3, 8.15, 0.65, 3.96), (4, 8.15, 0.65, 4.1),
    (5, 8.15, 0.65, 3.43), (6, 8.15, 0.65, 2.45), (7, 8.15, 0.65, 1.65), (8, 8.15, 0.62, 1.2), (9, 8.1, 0.6, 0.9),
    (10, 8.05, 0.58, 0.72), (12, 7.95, 0.5, 0.5), (13, 7.9, 0.45, 0.45), (13.6, 7.8, 0, 0),
)  # fmt: skip
BLADE_POWER = 2.0  # the blade's section is a diamond with hollow sides: wide at its middle, thin out to its edges
# The lobe where the web meets the blade: z, half width, half height, at x LOBE_X.
LOBE_X = 7.05
LOBE_STATIONS = ((1.6, 0.0, 0.0), (2.2, 0.35, 1.0), (3.5, 0.5, 1.45), (5.0, 0.5, 1.4), (6.5, 0.35, 0.9), (8.5, 0.0, 0.0))
INTAKE_HOLE_R, INTAKE_HOLE_DEPTH = 0.34, 0.9  # the thruster pods' forward holes
INTAKE_PROFILE = ((INTAKE_HOLE_DEPTH, 0.0), (INTAKE_HOLE_DEPTH, 0.3), (0.0, INTAKE_HOLE_R), (0.03, 0.44), (0.6, 0.6), (2.5, 0.58),
                  (5.0, 0.0))  # z, radius: up the hole's wall to the rim, then the pod
INTAKE_AT = (8.2, 1.15)  # x, and y above and below the blade's middle
# The gun pods' forward holes: the mouth's z, its half width and half height, how deep.
POD_HOLE = (3.5, 0.5, 0.6, 0.9)
# The inner pods' forward holes, a rounded rectangle: the mouth's z, its half width and half height, how deep (short of the web).
LOBE_HOLE = (1.75, 0.27, 0.8, 0.5)
LOBE_HOLE_POWER = 0.4  # below one squares an ellipse's corners off
LOBE_RIM = (0.33, 0.95)  # the pod's blunt front round the hole
# The strake along each flank: z, outer x, half thickness.
STRAKE_STATIONS = ((18.0, 4.6, 0.25), (19.0, 4.0, 0.28), (21.0, 3.6, 0.28), (23.0, 3.5, 0.28), (25.0, 3.6, 0.28), (27.0, 3.4, 0.28),
                   (29.0, 3.2, 0.28), (29.4, 1.4, 0.27), (33.0, 1.4, 0.25))  # fmt: skip
# The rod along each side of the tail spike: z, radius, at x TAIL_ROD_X.
TAIL_ROD = ((29.5, 0.0), (29.6, 0.2), (38.0, 0.2), (39.6, 0.0))
TAIL_ROD_X = 1.3
# The waist pods: centre (x, y) and the profile z, half width, half height; a pair above and below each strake.
WAIST_AT = (2.25, 1.0)
WAIST_STATIONS = ((22.2, 0.0, 0.0), (23.0, 0.75, 0.45), (24.5, 1.1, 0.68), (26.0, 1.05, 0.6), (28.0, 0.75, 0.42), (30.0, 0.0, 0.0))
# The crossbar: z of its leading and trailing edge at the centre and at the tips, its height and half thickness.
CROSSBAR = ((30.2, 34.5), (30.0, 34.7), -0.05, 0.2)
CROSSBAR_X = 8.3
# The tip spindles: z, half width, half height, centred on (SPINDLE_X, 0).
SPINDLE_X = 8.3
SPINDLE_POWER = 1.9
SPINDLE_STATIONS = (
    (29.3, 0, 0), (30, 0.63, 2.6), (31, 0.85, 3.26), (32, 0.93, 3.62), (33, 0.93, 3.53), (34, 0.85, 2.85), (35, 0.68, 1.94),
    (36, 0.45, 1.14), (37, 0.29, 0.61), (38, 0.18, 0.34), (39, 0.11, 0.2), (40, 0, 0),
)  # fmt: skip
GLOW_FROM_Z = 37.0  # the spindles' tails glow: the Flyer's drive
TUBE = ((25.4, 0.0), (25.5, 0.24), (28.5, 0.24), (28.6, 0.34), (29.8, 0.34))  # z, radius of the forward tube on each spindle
TUBE_Y = 0.08

EYE = (0.0, 1.4, 4.2)


def ellipse_ring(z: float, cx: float, cy: float, rx: float, ry: float, points: int = RING_POINTS, power: float = 1.0) -> np.ndarray:
    """An ellipse across z, counter-clockwise seen from astern; a pole when both radii are zero. ``power`` above one pinches
    it towards a diamond with hollow sides."""
    if rx <= 0.0 and ry <= 0.0:
        return np.array([[cx, cy, z]])
    t = np.linspace(0.0, 2.0 * np.pi, points, endpoint=False)
    c, s = np.cos(t), np.sin(t)
    c, s = np.sign(c) * np.abs(c) ** power, np.sign(s) * np.abs(s) ** power
    return np.column_stack([cx + rx * c, cy + ry * s, np.full(points, z)])


def recess(z: float, cx: float, rx: float, ry: float, depth: float, material: Material, points: int = RING_POINTS, power: float = 1.0,
           taper: float = 0.9) -> Mesh:
    """A hole sunk into a pod from its mouth at ``z``: the wall and the floor, facing the way the hole opens."""
    floor = z + depth
    return loft([np.array([[cx, 0.0, floor]]), ellipse_ring(floor, cx, 0.0, taper * rx, taper * ry, points, power),
                 ellipse_ring(z, cx, 0.0, rx, ry, points, power)], material, cap_end=False)


def in_holes(points: np.ndarray, normals: np.ndarray) -> np.ndarray:
    """One inside a forward hole (the gun pods', the thruster pods', the inner pods'), zero elsewhere: what stays dark."""
    p = np.asarray(points, dtype=float)
    x, y, z = np.abs(p[:, 0]), p[:, 1], p[:, 2]
    edge = 0.02
    pz, prx, pry, pd = POD_HOLE
    lz, lrx, lry, ld = LOBE_HOLE
    gun = (((x - POD_STATIONS[1][1]) / (prx + edge)) ** 2 + (y / (pry + edge)) ** 2 <= 1.0) & (z <= pz + pd + edge)
    thruster = (np.hypot(x - INTAKE_AT[0], np.abs(y) - INTAKE_AT[1]) <= INTAKE_HOLE_R + edge) & (z <= INTAKE_HOLE_DEPTH + edge)
    inner = (np.abs(x - LOBE_X) <= lrx + edge) & (np.abs(y) <= lry + edge) & (z <= lz + ld + edge)
    return (gun | thruster | inner).astype(float)


def smooth_loft(stations: Sequence[tuple[float, float, float, float, float]], material: Material, points: int = RING_POINTS
                ) -> tuple[Mesh, list[np.ndarray]]:
    """A smooth body through elliptic sections ``(z, cx, cy, rx, ry)``; also the full rings, for its burial volume."""
    rings = [ellipse_ring(*s, points=points) for s in stations]
    return loft(rings, material), [r for r in rings if len(r) > 1]


def station_box(stations: Sequence[tuple[float, float, float, float, float]], name: str) -> Collision:
    """The hit volume round a run of a loft's stations (z, centre x, centre y, half width, half height), pointed ends included."""
    return box_of(np.array([[cx + sx * rx, cy + sy * ry, z] for z, cx, cy, rx, ry in stations for sx in (-1.0, 1.0) for sy in (-1.0, 1.0)]), name)


def body_pieces(style: Style) -> list[Piece]:
    """The fuselage, its nose a ring of petals."""
    hull = style.material("hull")
    t = np.linspace(0.0, 2.0 * np.pi, 48, endpoint=False)
    rings = []
    for z, r in BODY_PROFILE:
        if r <= 0.0:
            rings.append(np.array([[0.0, 0.0, z]]))
            continue
        petal = PETAL_DEPTH * max(0.0, 1.0 - z / PETAL_END_Z) * np.abs(np.cos(0.5 * PETALS * t)) ** 0.5
        rr = r * (1.0 - PETAL_DEPTH * max(0.0, 1.0 - z / PETAL_END_Z) + petal)
        rings.append(np.column_stack([rr * np.cos(t), rr * np.sin(t), np.full(len(t), z)]))
    mesh = loft(rings, hull)
    solid = lathe_solid(list(BODY_PROFILE))
    runs = ((1, 8), (8, 16), (16, 25), (25, 36))
    boxes = [box_of(np.array([[-r, -r, z] for z, r in BODY_PROFILE[a - 1 : b]] + [[r, r, z] for z, r in BODY_PROFILE[a - 1 : b]]), f"body{k}")
             for k, (a, b) in enumerate(runs)]
    return [piece("body", "body", mesh, 50000.0, solid=solid, collision=boxes,
                  anchors={"nose": Anchor((0.0, 0.0, 0.6), (0.0, 0.0, -1.0)), "eye": Anchor(EYE, (0.0, 0.0, -1.0)),
                           "top": Anchor((0.0, 3.05, 9.0), (0.0, 1.0, 0.0))})]


def bow_pieces(style: Style) -> list[Piece]:
    """Each side of the bow: the gun pod, the web, the blade with its two thruster pods and the small pod inside it, each
    pod open forward in a dark hole."""
    hull, panel, dark = style.material("hull"), style.material("hull_panel"), style.material("interior")
    pod_x = POD_STATIONS[1][1]
    pz, prx, pry, pd = POD_HOLE
    pod = loft([ellipse_ring(pz, pod_x, 0.0, prx, pry, power=1.3), *(ellipse_ring(z, x, 0.0, rx, ry, power=1.3) for z, x, rx, ry in POD_STATIONS[1:])],
               hull, cap_start=False)
    pod_hole = recess(pz, pod_x, prx, pry, pd, dark, power=1.3)
    # The burial volume starts behind the hole, so the hole's own wall is never taken for buried.
    pod_rings = [ellipse_ring(z, x, 0.0, 0.8 * rx, 0.8 * ry) for z, x, rx, ry in POD_STATIONS[2:-1]]
    web_rings = [np.array([[xi, -t, z], [xo, -t, z], [xo, t, z], [xi, t, z]]) for z, xi, xo, t in WEB_STATIONS]
    web = faceted(web_rings, panel, cap_start=panel, cap_end=panel)
    blade = [(z, x, 0.0, rx, ry) for z, x, rx, ry in BLADE_STATIONS]
    blade_mesh = loft([ellipse_ring(*s, points=24, power=BLADE_POWER) for s in blade], hull)
    blade_rings = [ellipse_ring(z, x, 0.0, rx, ry) for z, x, rx, ry in BLADE_STATIONS[1:-1]]
    lz, lrx, lry, ld = LOBE_HOLE
    lobe = loft([ellipse_ring(lz, LOBE_X, 0.0, lrx, lry, power=LOBE_HOLE_POWER), ellipse_ring(lz + 0.03, LOBE_X, 0.0, *LOBE_RIM, power=0.6),
                 *(ellipse_ring(z, LOBE_X, 0.0, rx, ry) for z, rx, ry in LOBE_STATIONS[1:])], hull, cap_start=False)
    lobe_hole = recess(lz, LOBE_X, lrx, lry, ld, dark, power=LOBE_HOLE_POWER)
    intakes = [lathe(list(INTAKE_PROFILE), 14, [dark, dark, hull, hull, hull, hull], creases=(2,)).translated((INTAKE_AT[0], sy * INTAKE_AT[1], 0.0))
               for sy in (1.0, -1.0)]
    return [
        piece("pod_r", "bow", [pod, pod_hole], 3000.0, RIGHT, solid=loft_solid(2, pod_rings), fine=0.7,
              collision=[station_box([(z, x, 0.0, rx, ry) for z, x, rx, ry in POD_STATIONS], "pod")],
              anchors={"gun": Anchor((pod_x, 0.0, pz + 0.5 * pd), (0.0, 0.0, -1.0))}),
        piece("web_r", "bow", web, 1200.0, RIGHT, solid=loft_solid(2, web_rings), fine=0.6,
              collision=[box_of(np.concatenate(web_rings), "web")]),
        piece("blade_r", "bow", [blade_mesh, lobe, lobe_hole, *intakes], 1800.0, RIGHT, solid=loft_solid(2, blade_rings), fine=0.6,
              anchors={"inner": Anchor((LOBE_X, 0.0, lz - 0.3), (0.0, 0.0, -1.0))},  # ahead of the mouth: a swung plume clears its rim
              collision=[station_box(blade[:7], "blade_fore"), station_box(blade[6:9], "blade_mid"), station_box(blade[8:], "blade_aft"),
                         station_box([(z, LOBE_X, 0.0, rx, ry) for z, rx, ry in LOBE_STATIONS], "lobe"),
                         *(station_box([(z, INTAKE_AT[0], sy * INTAKE_AT[1], r, r) for z, r in INTAKE_PROFILE[2:]], name)
                           for sy, name in ((1.0, "intake_up"), (-1.0, "intake_down")))]),
    ]


def waist_pieces(style: Style) -> list[Piece]:
    """Each flank: the strake from the pod to the tail and the two small pods above and below it."""
    hull, panel = style.material("hull"), style.material("hull_panel")
    strake_rings = []
    for z, xo, t in STRAKE_STATIONS:
        xi = 0.2
        strake_rings.append(np.array([[xi, -t, z], [xo - 0.25, -t, z], [xo, 0.0, z], [xo - 0.25, t, z], [xi, t, z]]))
    strake = faceted(strake_rings, panel, cap_start=panel, cap_end=panel)
    rod = lathe(list(TAIL_ROD), 10, panel).translated((TAIL_ROD_X, 0.0, 0.0))
    x, y = WAIST_AT
    pods = [smooth_loft([(z, x, sy * y, rx, ry) for z, rx, ry in WAIST_STATIONS], hull, points=16)[0] for sy in (1.0, -1.0)]
    return [
        piece("strake_r", "tail", [strake, rod], 1000.0, RIGHT, fine=0.6,
              collision=[box_of(np.concatenate(strake_rings[:8]), "strake"),
                         box_of(np.array([[TAIL_ROD_X - 0.2, -0.2, 29.5], [TAIL_ROD_X + 0.2, 0.2, 39.6]]), "rod")]),
        piece("waist_r", "tail", pods, 1200.0, RIGHT, fine=0.7,
              collision=[station_box([(z, x, sy * y, rx, ry) for z, rx, ry in WAIST_STATIONS], name) for sy, name in ((1.0, "waist_up"), (-1.0, "waist_down"))]),
    ]


def crossbar_pieces(style: Style) -> list[Piece]:
    """The crossbar across the stern and the spindle at each of its tips, its tail glowing."""
    hull, panel, dark, throat = (style.material(r) for r in ("hull", "hull_panel", "hull_dark", "nozzle_throat"))
    (c0, c1), (t0, t1), y, half = CROSSBAR

    def section(x: float, lead: float, trail: float) -> np.ndarray:
        return np.array([[x, y, lead], [x, y - half, lead + 0.3], [x, y - half, trail - 0.5], [x, y, trail], [x, y + half, trail - 0.5],
                         [x, y + half, lead + 0.3]])

    bar_rings = [section(-CROSSBAR_X, t0, t1), section(0.0, c0, c1), section(CROSSBAR_X, t0, t1)]
    bar = faceted(bar_rings, panel, cap_start=panel, cap_end=panel)
    stations = [(z, SPINDLE_X, 0.0, rx, ry) for z, rx, ry in SPINDLE_STATIONS]
    fore = [s for s in stations if s[0] <= GLOW_FROM_Z]
    aft = [s for s in stations if s[0] >= GLOW_FROM_Z]
    # The fore loft ends open at the glowing tail's first ring, which closes it.
    spindle = loft([ellipse_ring(*s, power=SPINDLE_POWER) for s in fore], hull, cap_end=False)
    tail = loft([ellipse_ring(*s, power=SPINDLE_POWER) for s in aft], throat, cap_start=False)
    tube = lathe(list(TUBE), 12, [dark, hull, hull, hull]).translated((SPINDLE_X, TUBE_Y, 0.0))
    anchors = {"main": Anchor((SPINDLE_X, 0.0, LENGTH_M), Z_AXIS), "centre": Anchor((SPINDLE_X, 0.0, 33.0)),
               "tip": Anchor((SPINDLE_X + 0.93, 0.0, 32.5), (1.0, 0.0, 0.0))}
    all_rings = [r for r in (ellipse_ring(*s) for s in stations) if len(r) > 1]
    return [
        piece("crossbar", "crossbar", bar, 1500.0, solid=loft_solid(0, bar_rings), fine=0.6,
              collision=[box_of(np.concatenate(bar_rings), "crossbar")]),
        piece("spindle_r", "spindle_r", [spindle, tail, tube], 2500.0, RIGHT, solid=loft_solid(2, all_rings), fine=0.6, anchors=anchors,
              collision=[station_box(stations[:7], "spindle_fore"), station_box(stations[6:], "spindle_aft"),
                         box_of(np.array([[SPINDLE_X - 0.34, TUBE_Y - 0.34, 25.4], [SPINDLE_X + 0.34, TUBE_Y + 0.34, 29.8]]), "tube")]),
    ]


def assemble(style: Style) -> list[Piece]:
    """Every piece of the Flyer in the authored frame (centre pieces and the starboard of each pair)."""
    return [*body_pieces(style), *bow_pieces(style), *waist_pieces(style), *crossbar_pieces(style)]

