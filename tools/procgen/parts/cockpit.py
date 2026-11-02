"""The Starfury's cockpit interior (M3-T29, Q29), seen only from the pilot's eye: slim V struts rising from the sides of the octagonal
display, a thin bar across the top, side panes down to low sills, and a closed shell behind them. The camera never leaves the eye, so the layout is authored as what
the eye sees: 1080p pixels from the screen's centre (Y up) with a depth for each point. Original geometry, after the written description in
``docs/design-references.md``, with the maintainer's slimmer proportions.

The console's screens are not in this mesh: ``cockpit_screens`` gives their centre, size and facing for the game to build them on, so
the two agree by construction. Frame: the eye's position plus Godot axes (-Z forward)."""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from ..core.geometry import Material, Mesh, unit
from ..styles import Style
from .hull import _FlatMeshBuilder

# The state lamps in the console's indicator row, port to starboard; each is a material of its own, so the game can light it.
INDICATORS = ("assist", "guns", "lights", "track")
# Half the box around the crosshair that the view must keep clear, 1080p pixels.
CROSSHAIR_CLEAR_PX = 60.0
# How far aft of the nose the side panes reach, degrees from straight ahead.
PANE_AFT_DEG = 73.0
# The smallest box a side screen or the octagon may fill at 1080p, pixels: below this its text stops reading at a glance.
MIN_SCREEN_PX = (300.0, 220.0)
# How tall the side sills stand above the frame's bottom edge at 1080p, outside the screens (the maintainer's number).
SILL_HEIGHT_PX = 75.0


@dataclass(frozen=True)
class CockpitSpec:
    """Where the interior's edges fall on a 1080p screen, and how far the shell stands from the eye. The defaults are the Starfury's."""

    focal_px: float = 540.0 / math.tan(math.radians(37.5))  # the cockpit camera's 75 deg vertical field of view at 1080p

    # The V's inner edge: half the opening's width at height Y. It runs down to the octagon's cut top corners.
    opening_px_at_horizon: float = 200.7
    opening_px_per_y: float = 0.3691
    # The red face's outer edge, then the dark trim's, which is the strut's outer edge: about 100 px across at the octagon, 180 at the top.
    red_px_at_horizon: float = 262.0
    red_px_per_y: float = 0.459
    outer_px_at_horizon: float = 322.7
    outer_px_per_y: float = 0.4765
    # Where the V's floor lies, the octagon's top edge; where the inner edge lands on the rim; and the thin bar across the top of the frame.
    opening_floor_y_px: float = -166.0
    strut_foot_y_px: float = -205.0
    bar_y_px: float = 525.0
    # The side panes' lower edge, from the strut out: along the top of the screen's housing, down its outer side, then out along the low sill.
    pane_floor_px: tuple[tuple[float, float], ...] = (
        (240.0, -173.0), (705.0, -196.0), (726.0, SILL_HEIGHT_PX - 540.0), (1340.0, SILL_HEIGHT_PX - 540.0),
    )  # fmt: skip

    # The shell, metres from the eye: walls, ceiling, floor and the bulkhead behind the pilot. All stay inside the hull's own faces
    # (the deck above the eye comes down to 0.23 m at the sides and the old bulkhead stands 0.29 m aft).
    wall_x: float = 0.72
    ceiling_y: float = 0.222
    floor_y: float = -0.70
    aft: float = 0.20
    pillar_d: float = 0.22
    tub_x: float = 0.50

    def opening_half_px(self, y: float) -> float:
        return self.opening_px_at_horizon + self.opening_px_per_y * y

    def red_px(self, y: float) -> float:
        return self.red_px_at_horizon + self.red_px_per_y * y

    def strut_outer_px(self, y: float) -> float:
        return self.outer_px_at_horizon + self.outer_px_per_y * y

    def sill_y_px(self, x: float) -> float:
        """The side pane's lower edge at screen distance ``x`` from the centre."""
        xs, ys = zip(*self.pane_floor_px)
        return float(np.interp(abs(x), xs, ys))


def opening_half_deg(spec: CockpitSpec, y_px: float) -> float:
    """How far the V's edge lies off the nose, in azimuth, at screen height ``y_px``: the opening as the tests record it."""
    return math.degrees(math.atan2(spec.opening_half_px(y_px), spec.focal_px))


# --- planes the eye sees ---------------------------------------------------------------------------------------------------
Plane = tuple[np.ndarray, np.ndarray]

# Where the octagon's plane stands: a point straight ahead on its top edge's line, as a screen height and a depth.
_CONSOLE_ANCHOR_Y_PX = -125.0
_CONSOLE_ANCHOR_D = 0.79
# The panel beside the octagon carries a side screen; it is anchored here on the octagon's plane.
_WING_ANCHOR_PX = (222.0, -172.0)
# The console tips up to the pilot. The panels beside it barely do: at this field of view, a screen turned to the eye far off the axis reads
# slanted, and one nearly square to the view keeps its text upright.
_CONSOLE_TILT_DEG = 24.0
_WING_TILT_DEG = 6.0
_WING_YAW_DEG = 2.0
# How far a part stands proud of its surface, metres: a bezel's face, then the screen set into it; and how far a bezel reaches past its screen.
_BEZEL_PROUD = 0.015
_SCREEN_PROUD = 0.006
_BEZEL_GROW = 0.022
_OCTAGON_SIZE = (0.375, 0.285)
_OCTAGON_CORNER = 0.08
_OCTAGON_CENTRE_Y_PX = -335.0
_WING_SCREEN_SIZE = (0.42, 0.305)
_WING_SCREEN_CENTRE_PX = (465.0, -345.0)
# Where the sill's inner edge straightens out along the tub, how the sill falls toward the pilot, and the lamp on screen, in the sill's band.
_TUB_FORWARD_D = 0.30
_SILL_AFT_DROP = 0.06
_LAMP_PX = (850.0, -502.0)


def _at(spec: CockpitSpec, x_px: float, y_px: float, depth: float) -> np.ndarray:
    """The eye-relative point at a screen position and a distance ahead."""
    return np.array([x_px * depth / spec.focal_px, y_px * depth / spec.focal_px, -depth])


def _on(spec: CockpitSpec, x_px: float, y_px: float, plane: Plane) -> np.ndarray:
    """Where the ray through a screen position meets ``plane``."""
    point, normal = plane
    ray = np.array([x_px / spec.focal_px, y_px / spec.focal_px, -1.0])
    return ray * float(normal @ point) / float(normal @ ray)


def _plane(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> Plane:
    """The plane through three points, its normal turned to the eye."""
    normal = unit(np.cross(b - a, c - a))
    return a, (normal if float(normal @ a) < 0.0 else -normal)


def _at_floor(plane: Plane, x: float, floor_y: float) -> np.ndarray:
    """The point on ``plane`` at a given x on the floor."""
    point, normal = plane
    return np.array([x, floor_y, float(normal @ point - normal[0] * x - normal[1] * floor_y) / normal[2]])


def _console_plane(spec: CockpitSpec) -> Plane:
    rear = _at(spec, 0.0, _CONSOLE_ANCHOR_Y_PX, _CONSOLE_ANCHOR_D)
    tilt = math.radians(_CONSOLE_TILT_DEG)
    return rear, np.array([0.0, math.sin(tilt), math.cos(tilt)])


def _wing_plane(spec: CockpitSpec) -> Plane:
    """The right-hand panel that carries the side screen, standing just behind the octagon's plane."""
    tilt, yaw = math.radians(_WING_TILT_DEG), math.radians(_WING_YAW_DEG)
    corner = _on(spec, _WING_ANCHOR_PX[0], _WING_ANCHOR_PX[1], _console_plane(spec))
    return corner, np.array([-math.sin(yaw) * math.cos(tilt), math.sin(tilt), math.cos(yaw) * math.cos(tilt)])


def cockpit_screens(spec: CockpitSpec, eye: tuple[float, float, float] | np.ndarray) -> dict[str, dict]:
    """The console's screens, in the eye's frame plus ``eye``: ``center``, ``size`` (width, height), ``normal`` (to the pilot), ``up``,
    and ``corner``, how much each corner is cut along both edges (0 for a plain rectangle)."""
    origin = np.asarray(eye, dtype=float)
    world_up = np.array([0.0, 1.0, 0.0])

    def entry(plane: Plane, centre_px: tuple[float, float], size: tuple[float, float], corner: float, mirror: float = 1.0) -> dict:
        centre = _on(spec, centre_px[0], centre_px[1], plane) + plane[1] * _SCREEN_PROUD
        up = unit(world_up - plane[1] * float(world_up @ plane[1]))
        flip = np.array([mirror, 1.0, 1.0])
        return {
            "center": ((centre * flip) + origin).tolist(),
            "size": list(size),
            "normal": (plane[1] * flip).tolist(),
            "up": (up * flip).tolist(),
            "corner": corner,
        }

    console, wing = _console_plane(spec), _wing_plane(spec)
    return {
        "octagon": entry(console, (0.0, _OCTAGON_CENTRE_Y_PX), _OCTAGON_SIZE, _OCTAGON_CORNER),
        "left": entry(wing, _WING_SCREEN_CENTRE_PX, _WING_SCREEN_SIZE, 0.0, -1.0),
        "right": entry(wing, _WING_SCREEN_CENTRE_PX, _WING_SCREEN_SIZE, 0.0),
    }


# --- the mesh --------------------------------------------------------------------------------------------------------------
class _Shell:
    """Polygons mirrored or not, each facing the eye."""

    def __init__(self) -> None:
        self.builder = _FlatMeshBuilder()

    def poly(self, points: list[np.ndarray] | np.ndarray, material: Material, sign: float = 1.0) -> None:
        pts = np.asarray(points, dtype=float) * np.array([sign, 1.0, 1.0])
        self.builder.poly(pts, material, -pts.mean(axis=0))

    def both(self, points: list[np.ndarray] | np.ndarray, material: Material) -> None:
        self.poly(points, material, 1.0)
        self.poly(points, material, -1.0)

    def bar(self, p: np.ndarray, q: np.ndarray, across: np.ndarray, out: np.ndarray, width: float, height: float, material: Material) -> None:
        """A box from ``p`` to ``q`` on both sides of the ship, ``width`` along ``across`` and standing ``height`` along ``out``."""
        a, b = 0.5 * width * unit(across), height * unit(out)
        self.both([p - a + b, p + a + b, q + a + b, q - a + b], material)
        self.both([p - a, p - a + b, q - a + b, q - a], material)
        self.both([p + a, p + a + b, q + a + b, q + a], material)
        self.both([p - a, p + a, p + a + b, p - a + b], material)
        self.both([q - a, q + a, q + a + b, q - a + b], material)

    def mesh(self) -> Mesh:
        return self.builder.mesh()


def _landing(spec: CockpitSpec, at_horizon: float, per_y: float, rim: list[np.ndarray]) -> tuple[float, float]:
    """Where a strut's edge, a line on screen, comes down onto the octagon's rim, given as the top edge's end, the cut corner and the side."""
    pixels = [spec.focal_px * p[:2] / -p[2] for p in rim]
    for start, end in zip(pixels, pixels[1:]):
        edge = end - start
        # The rim's x at this height equals the line's: solve along the rim segment.
        denominator = edge[0] - per_y * edge[1]
        share = (at_horizon + per_y * start[1] - start[0]) / denominator
        if 0.0 <= share <= 1.0:
            y = start[1] + share * edge[1]
            return at_horizon + per_y * y, y
    raise ValueError("this strut edge misses the octagon")


def _strut(s: _Shell, spec: CockpitSpec, style: Style) -> None:
    """One strut's rails run from the octagon's rim up past the ceiling, leaning back over the pilot. The red face is what the eye sees of the
    opening's jamb, with its cable runs; the dark trim beyond it is the part that faces the pilot. The feet tuck just under the bezel."""
    red, dim = style.material("cockpit_red"), style.material("cockpit_red_dim")
    dark, metal = style.material("cockpit_dark"), style.material("cockpit_metal")
    console = _console_plane(spec)
    screen = cockpit_screens(spec, np.zeros(3))["octagon"]
    bezel = _outline(screen, _BEZEL_GROW)
    rim = [bezel[1], bezel[2], bezel[3]]  # the right-hand end of the top edge, the cut corner's foot and the side's foot
    high = 600.0
    tuck = 8.0  # how far past the rim each foot runs on screen, under the bezel

    def foot(at_horizon: float, per_y: float) -> np.ndarray:
        x, y = _landing(spec, at_horizon, per_y, rim)
        return _on(spec, at_horizon + per_y * (y - tuck), y - tuck, console) + console[1] * (_BEZEL_PROUD - 0.003)

    rails = {
        "inner": (foot(spec.opening_px_at_horizon, spec.opening_px_per_y), _at(spec, spec.opening_half_px(560.0), 560.0, 0.44)),
        "red": (foot(spec.red_px_at_horizon, spec.red_px_per_y), _at(spec, spec.red_px(high), high, 0.33)),
        "outer": (foot(spec.outer_px_at_horizon, spec.outer_px_per_y), _at(spec, spec.strut_outer_px(high), high, 0.32)),
    }
    back_foot = rails["outer"][0] * 1.08  # further along the same ray, so the eye never sees it
    rails["back"] = (back_foot, _at(spec, spec.strut_outer_px(high) - 6.0, high, 0.46))

    def along(rail: str, t: float) -> np.ndarray:
        lo, hi = rails[rail]
        return lo + t * (hi - lo)

    s.both([along("inner", 0.0), along("red", 0.0), along("red", 1.0), along("inner", 1.0)], red)
    s.both([along("red", 0.0), along("outer", 0.0), along("outer", 1.0), along("red", 1.0)], dark)
    s.both([along("outer", 0.0), along("back", 0.0), along("back", 1.0), along("outer", 1.0)], dark)
    s.both([along("back", 0.0), along("inner", 0.0), along("inner", 1.0), along("back", 1.0)], dark)
    s.both([along("inner", 0.0), along("red", 0.0), along("outer", 0.0), along("back", 0.0)], dark)

    def across(t: float, share: float) -> np.ndarray:
        return along("inner", t) + share * (along("red", t) - along("inner", t))

    def trim(t: float, share: float) -> np.ndarray:
        return along("red", t) + share * (along("outer", t) - along("red", t))

    # A dark lip along the opening, recessed panels down the red face, cable runs in clamps, and a plate on the trim. All stand off the
    # face toward the eye, so they start a little in from its inner edge and the V stays clear.
    _, normal = _plane(along("inner", 0.0), along("inner", 1.0), along("red", 0.5))
    lift = normal * 0.003
    s.both([across(0.0, 0.10) + lift, across(0.0, 0.16) + lift, across(1.0, 0.16) + lift, across(1.0, 0.10) + lift], dark)
    for lo, hi in ((0.06, 0.26), (0.30, 0.50), (0.54, 0.76), (0.80, 0.97)):
        s.both([across(lo, 0.58) + lift, across(lo, 0.94) + lift, across(hi, 0.94) + lift, across(hi, 0.58) + lift], dim)
    width_axis = np.cross(along("inner", 1.0) - along("inner", 0.0), normal)
    for share, thick in ((0.30, 0.008), (0.43, 0.006)):
        s.bar(across(0.02, share), across(0.98, share), width_axis, normal, thick, 0.005, dark)
    for t in (0.14, 0.40, 0.66, 0.90):
        s.bar(across(t - 0.010, 0.365), across(t + 0.010, 0.365), width_axis, normal, 0.026, 0.008, metal)
    _, trim_normal = _plane(along("red", 0.0), along("red", 1.0), along("outer", 0.5))
    trim_lift = trim_normal * 0.003
    for lo, hi in ((0.08, 0.40), (0.46, 0.92)):
        s.both([trim(lo, 0.34) + trim_lift, trim(lo, 0.66) + trim_lift, trim(hi, 0.66) + trim_lift, trim(hi, 0.34) + trim_lift], metal)


def _outline(screen: dict, grow: float) -> list[np.ndarray]:
    """A screen's outline grown by ``grow`` metres, eye frame: its eight corners if cut, its four if not."""
    centre, up, normal = (np.array(screen[k]) for k in ("center", "up", "normal"))
    right = np.cross(up, normal)
    hw, hh = 0.5 * screen["size"][0] + grow, 0.5 * screen["size"][1] + grow
    c = screen["corner"] + grow * 0.6 if screen["corner"] > 0.0 else 0.0
    if c > 0.0:
        shape = ((-hw + c, hh), (hw - c, hh), (hw, hh - c), (hw, -hh + c), (hw - c, -hh), (-hw + c, -hh), (-hw, -hh + c), (-hw, hh - c))
    else:
        shape = ((-hw, hh), (hw, hh), (hw, -hh), (-hw, -hh))
    return [centre + a * right + b * up for a, b in shape]


def _surround(s: _Shell, screen: dict, sign: float, dark: Material, metal: Material, rim: Material) -> None:
    """The screen's backing, a thin rim, then a raised bezel. The screen sits just below the bezel's face, so it reads as built in."""
    normal = np.array(screen["normal"])
    below = -normal * _SCREEN_PROUD
    s.poly(np.array(_outline(screen, 0.0)) + below, dark, sign)
    inner, lit, outer = _outline(screen, 0.0), _outline(screen, 0.004), _outline(screen, _BEZEL_GROW)
    count = len(inner)
    face = normal * (_BEZEL_PROUD - _SCREEN_PROUD)
    level = normal * 0.001
    for i in range(count):
        j = (i + 1) % count
        s.poly([inner[i] + level, inner[j] + level, lit[j] + level, lit[i] + level], rim, sign)
        s.poly([lit[i] + face, lit[j] + face, outer[j] + face, outer[i] + face], metal, sign)
        s.poly([outer[i] + face, outer[j] + face, outer[j] + below, outer[i] + below], dark, sign)
        s.poly([lit[i] + face, lit[j] + face, lit[j] + level, lit[i] + level], dark, sign)


def _console(s: _Shell, spec: CockpitSpec, style: Style) -> None:
    """Nothing stands above the octagon: below its sides the panel runs on down to the floor. The screens' surrounds, and the indicator lamps
    along the octagon's top rim."""
    dark, metal, rim = style.material("cockpit_dark"), style.material("cockpit_metal"), style.material("cockpit_rim")
    red = style.material("cockpit_red")
    console = _console_plane(spec)
    flip = np.array([-1.0, 1.0, 1.0])
    screens = cockpit_screens(spec, np.zeros(3))
    octagon = screens["octagon"]
    # Hidden behind the octagon at its top, where it starts.
    start = _on(spec, 190.0, -285.0, console)
    foot = _at_floor(console, float(start[0]), spec.floor_y)
    s.poly([start * flip, start, foot, foot * flip], dark)
    _surround(s, octagon, 1.0, dark, metal, rim)
    for sign in (1.0, -1.0):
        _surround(s, screens["right"], sign, dark, metal, red)

    # One thin lamp per state on the bezel's face, along the top edge.
    centre, up, normal = (np.array(octagon[k]) for k in ("center", "up", "normal"))
    right = np.cross(up, normal)
    pitch, half_w, half_h = 0.042, 0.014, 0.0045
    along_rim = 0.5 * octagon["size"][1] + 0.5 * (0.004 + _BEZEL_GROW)
    lift = normal * (_BEZEL_PROUD - _SCREEN_PROUD + 0.001)
    for i, name in enumerate(INDICATORS):
        cx = (i - 0.5 * (len(INDICATORS) - 1)) * pitch
        s.poly([centre + (cx + a) * right + (along_rim + b) * up + lift for a, b in ((-half_w, half_h), (half_w, half_h), (half_w, -half_h), (-half_w, -half_h))],
               style.material(f"cockpit_ind_{name}"))


def _sills(s: _Shell, spec: CockpitSpec, style: Style) -> None:
    """The panel behind each side screen, a low dark sill out to the frame's edge with shallow ribs and a round lamp in it, and the tub between."""
    sill_mat, metal, lamp = style.material("cockpit_sill"), style.material("cockpit_metal"), style.material("cockpit_lamp")
    dark = style.material("cockpit_dark")
    wing = _wing_plane(spec)
    flip = np.array([-1.0, 1.0, 1.0])
    _, shoulder_px, knee_px, far_px = spec.pane_floor_px
    shoulder = _on(spec, shoulder_px[0], shoulder_px[1], wing)
    knee = _on(spec, knee_px[0], knee_px[1], wing)
    # The sill's front edge is level, so its top is one line on screen; it runs on past the frame for wider windows.
    far = _at(spec, far_px[0], far_px[1], float(-knee[2]))
    sill = _plane(knee, far, np.array([spec.wall_x, float(knee[1]) - _SILL_AFT_DROP, spec.aft]))

    def on_sill(x: float, z: float) -> np.ndarray:
        point, normal = sill
        return np.array([x, float(normal @ point - normal[0] * x - normal[2] * z) / normal[1], z])

    pillar = on_sill(spec.wall_x, -spec.pillar_d)
    aft_outer = on_sill(spec.wall_x, spec.aft)
    aft_inner = on_sill(spec.tub_x, spec.aft)
    elbow = on_sill(spec.tub_x, -_TUB_FORWARD_D)
    s.both([knee, far, pillar], sill_mat)
    s.both([pillar, aft_outer, aft_inner, elbow, knee], sill_mat)

    # The panel behind the side screen, from behind the strut to the sill and on down to the floor. Its inner edge lies behind the octagon's panel.
    inner_top = _on(spec, 185.0, -172.0, wing)
    inner_foot = _at_floor(wing, float(inner_top[0]), spec.floor_y)
    knee_foot = _at_floor(wing, float(knee[0]), spec.floor_y)
    s.both([inner_top, shoulder, knee, knee_foot, inner_foot], dark)

    # The tub's walls under the sill's inner edge, and its floor.
    aft_foot = np.array([spec.tub_x, spec.floor_y, spec.aft])
    elbow_foot = np.array([spec.tub_x, spec.floor_y, elbow[2]])
    s.both([elbow, aft_inner, aft_foot, elbow_foot], dark)
    s.both([knee, elbow, elbow_foot], dark)
    s.both([knee, elbow_foot, knee_foot], dark)
    s.poly([aft_foot * flip, aft_foot, elbow_foot, knee_foot, knee_foot * flip, elbow_foot * flip], dark)

    # Shallow ribs from the sill's front edge toward the pilot.
    up = sill[1]
    for i, x_px in enumerate((760.0, 795.0, 905.0, 940.0)):
        start = _on(spec, x_px, far_px[1] - 3.0, sill)
        end = on_sill(float(start[0]) - 0.01, float(start[2]) + 0.25)
        s.bar(start, end, np.cross(up, end - start), up, 0.008, 0.003, metal if i % 2 else dark)
    # A round lamp in a dark collar inside the sill's band, square to the view so it reads round this far off the axis. It stands on the
    # sill at the collar's foot, so all of it clears the sloping surface.
    collar_px, lamp_px = 26.0, 15.0
    depth = -float(_on(spec, _LAMP_PX[0], _LAMP_PX[1] - collar_px, sill)[2]) - 0.002
    centre = _at(spec, _LAMP_PX[0], _LAMP_PX[1], depth)
    u, v, facing = np.array([1.0, 0.0, 0.0]), np.array([0.0, 1.0, 0.0]), np.array([0.0, 0.0, 1.0])
    for radius_px, material, lift in ((collar_px, dark, 0.0), (lamp_px, lamp, 0.002)):
        radius = radius_px * depth / spec.focal_px
        s.both([centre + facing * lift + radius * (math.cos(a) * u + math.sin(a) * v) for a in np.linspace(0.0, 2.0 * math.pi, 18, endpoint=False)], material)


def _shell_walls(s: _Shell, spec: CockpitSpec, style: Style) -> None:
    """Ceiling, bar, side walls, aft pillars and the bulkhead behind the pilot: what free look finds."""
    dark, metal = style.material("cockpit_dark"), style.material("cockpit_metal")
    w, c, f, a = spec.wall_x, spec.ceiling_y, spec.floor_y, spec.aft
    bar_near, bar_far = 0.288, 0.298
    bar_low = spec.bar_y_px * bar_far / spec.focal_px
    bar_high = 0.31
    z_front = -bar_near - 0.005
    s.poly([np.array([-w, c, z_front]), np.array([w, c, z_front]), np.array([w, c, a]), np.array([-w, c, a])], dark)
    for x0, x1 in ((0.10, 0.42), (0.50, 0.68)):
        s.both([np.array([x0, c - 0.004, -0.24]), np.array([x1, c - 0.004, -0.24]), np.array([x1, c - 0.004, 0.14]), np.array([x0, c - 0.004, 0.14])], metal)
    # The bar across the top: its under face and the face toward the pilot.
    s.poly([np.array([-w, bar_low, -bar_far]), np.array([w, bar_low, -bar_far]), np.array([w, bar_low, -bar_near]), np.array([-w, bar_low, -bar_near])], dark)
    s.poly([np.array([-w, bar_low, -bar_near]), np.array([w, bar_low, -bar_near]), np.array([w, bar_high, -bar_near]), np.array([-w, bar_high, -bar_near])], dark)
    # Side walls from the aft pillar back, down past the sills.
    pillar = -spec.pillar_d
    s.both([np.array([w, c, pillar]), np.array([w, c, a]), np.array([w, f, a]), np.array([w, f, pillar])], dark)
    # The aft pillar: a post closing the side pane, from sill to ceiling.
    post = 0.04
    s.both([np.array([w - post, c, pillar + post]), np.array([w, c, pillar]), np.array([w, f, pillar]), np.array([w - post, f, pillar + post])], metal)
    # The bulkhead, with a few raised plates so a turn of the head finds a built thing.
    s.poly([np.array([-w, c, a]), np.array([w, c, a]), np.array([w, f, a]), np.array([-w, f, a])], dark)
    plate = a - 0.004
    for x0, x1, y0, y1 in ((0.06, 0.34, -0.10, 0.20), (0.40, 0.66, -0.10, 0.20), (0.06, 0.34, -0.55, -0.16), (0.40, 0.66, -0.55, -0.16)):
        s.both([np.array([x0, y1, plate]), np.array([x1, y1, plate]), np.array([x1, y0, plate]), np.array([x0, y0, plate])], metal)


def cockpit_interior(spec: CockpitSpec, eye: tuple[float, float, float] | np.ndarray, style: Style) -> Mesh:
    """The interior mesh at ``eye``: hard edges (no shared vertices), mirrored in x but for the indicator row."""
    s = _Shell()
    _strut(s, spec, style)
    _console(s, spec, style)
    _sills(s, spec, style)
    _shell_walls(s, spec, style)
    return s.mesh().translated(np.asarray(eye, dtype=float))
