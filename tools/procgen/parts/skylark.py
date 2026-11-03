"""Skylark transport parts (docs/design-references.md "Skylark transport", docs/assets-civilian.md "skylark_transport").

The forward capsule with its nose vanes and bridge plate, the spine and collar with their vane rings, the side tanks and
the bars ahead of them, the belly fins, the faceted body with its corner fins, dorsal fin, centre engine and turret
pedestal, and the nacelles with their cones, ribbed rings, claws and the short pylons that carry the claws.

Frame of the design references: x to starboard, y up from the reference model's box centre, z aft from the nose tip,
metres (Godot's axes). Every shape is our own lathe, loft or plate through the sizes measured off the reference views.
Pieces come as :class:`Piece`: a part, the volume that hides what other pieces push into it, and whether it stands on the
centre line (sampled once and symmetrised) or on the right (mirrored to the left by the asset). The part's ``group`` is
its break-up chunk.
"""

from __future__ import annotations

import math
from collections.abc import Callable, Sequence
from dataclasses import dataclass

import numpy as np

from ..core.geometry import Material, Mesh, assign_material_by_predicate, box, lathe, prism, rotation_x, rotation_z, sweep_rect
from ..styles import Style
from . import Anchor, Collision, Part
from .solids import Solid, lathe_solid, prism_solid
from .starfury import closed_loft, section_loft

CENTRE, RIGHT = "c", "r"
_Z_TO_Y = rotation_x(-0.5 * math.pi)  # local +Z to +Y
_Y_UP = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]])  # a prism's plan (x, -z) flat, thickness on +Y

# --- layout (authored frame, the design references' measurements) -------------------------------------------------
CAPSULE_AXIS = (0.0, -0.45)  # x, y of the capsule, spine, collar and centre engine
CAPSULE_R = 3.73
NECK_R = 2.19  # the nose neck and the spine
CAPSULE_FACE_Z = 1.72
DOME_CENTRES = (6.2, 17.5)  # the capsule's two domes are spheres of the capsule's radius round these
SPINE_END_Z = 29.6
BAND_Z = ((6.6, 7.8), (15.6, 16.8))  # the two red-orange bands on the capsule
TANK_AXIS = (5.44, -0.45)
TANK_R = 2.16
TANK_BAND_Z = (23.8, 25.0)
NACELLE_AXIS = (13.03, -0.26)  # x, y; the thrust line
NACELLE_FRONT_Z = 35.64
NACELLE_EXIT_Z = 55.48
NACELLE_EXIT_R = 1.62
NACELLE_INTAKE_R = 1.3
CONE_Z = 41.9  # both nacelle cones stand at this z
TURRET_MOUNT = (0.0, 3.6, 37.5)  # Q19: the only turret, on a pedestal on the body's top ahead of the fin
PEDESTAL_R = 1.05  # under the turret's 2.4 m base, as the Saturns' pads are under theirs
BRIDGE_EYE = (0.0, 3.6, 11.8)  # inside the bridge plate, behind its glazed front


@dataclass
class Piece:
    """One sampled component. ``side`` is :data:`CENTRE` or :data:`RIGHT`; ``fine`` scales the sampling spacing (thin
    parts are sampled finer so their silhouette survives)."""

    part: Part
    solid: Solid | None = None
    side: str = CENTRE
    fine: float = 1.0

    @property
    def name(self) -> str:
        return self.part.name

    @property
    def group(self) -> str:
        return self.part.group

    def mirrored(self, name: str, group: str) -> Piece:
        """The left twin of a right piece."""
        solid = None if self.solid is None else self.solid.mirrored("x")
        return Piece(self.part.mirrored("x").renamed(name, group=group), solid, self.side, self.fine)


def _piece(name: str, group: str, mesh: Mesh, solid: Solid | None = None, side: str = CENTRE, mass_kg: float = 0.0,
           collision: Sequence[Collision] = (), anchors: dict[str, Anchor] | None = None, fine: float = 1.0) -> Piece:  # fmt: skip
    return Piece(Part(name, mesh, dict(anchors or {}), list(collision), mass_kg, group), solid, side, fine)


# --- helpers ----------------------------------------------------------------------------------------------------------
def _on_axis(mesh: Mesh, axis: Sequence[float]) -> Mesh:
    return mesh.translated((axis[0], axis[1], 0.0))


def _axial(profile: Sequence[tuple[float, float]], axis: Sequence[float], segments: int,
           materials: Material | Sequence[Material], creases=(), step: float = 1.0) -> Mesh:  # fmt: skip
    """A lathe about a z-parallel axis through ``axis`` (x, y). Long profile segments are split so no face is much
    longer than ``step``: long slivers sample unevenly and leave holes between splats."""
    mats = [materials] * (len(profile) - 1) if isinstance(materials, Material) else list(materials)
    points, seg_mats, index = [profile[0]], [], {0: 0}
    for i, ((z0, r0), (z1, r1)) in enumerate(zip(profile[:-1], profile[1:], strict=True)):
        n = max(1, math.ceil(math.hypot(z1 - z0, r1 - r0) / step - 1e-9))
        points += [(z0 + (z1 - z0) * k / n, r0 + (r1 - r0) * k / n) for k in range(1, n + 1)]
        seg_mats += [mats[i]] * n
        index[i + 1] = len(points) - 1
    return _on_axis(lathe(points, segments, seg_mats, creases={index[c] for c in creases}), axis)


def _axial_solid(profile: Sequence[tuple[float, float]], axis: Sequence[float]) -> Solid:
    return lathe_solid(profile).translated((axis[0], axis[1], 0.0))


def _box_of(mesh: Mesh, name: str = "", basis: np.ndarray | None = None) -> Collision:
    """The smallest box with the given axes round a mesh."""
    b = np.eye(3) if basis is None else np.asarray(basis, dtype=float)
    local = mesh.vertices @ b
    lo, hi = local.min(axis=0), local.max(axis=0)
    return Collision("box", b @ (0.5 * (lo + hi)), basis=b, size=hi - lo, name=name)


def _plate_y(outline_xz: Sequence[tuple[float, float]], y: float, thickness: float, material: Material) -> Mesh:
    """A flat plate of a convex plan outline ``(x, z)``, centred on height ``y``."""
    plan = np.array([(x, -z) for x, z in outline_xz])
    return prism([(plan, material)], [(plan, material)], thickness).transformed(_Y_UP, (0.0, y, 0.0))


def _plate_y_solid(outline_xz: Sequence[tuple[float, float]], y: float, thickness: float) -> Solid:
    plan = np.array([(x, -z) for x, z in outline_xz])
    return prism_solid(plan, -0.5 * thickness, 0.5 * thickness).transformed(_Y_UP, (0.0, y, 0.0))


def _sphere_arc(centre_z: float, radius: float, r_from: float, front: bool, steps: int) -> list[tuple[float, float]]:
    """Profile points of a spherical dome from radius ``r_from`` out to the full radius (front dome) or back down to it
    (aft dome)."""
    reach = math.sqrt(radius * radius - r_from * r_from)
    ts = np.linspace(0.0, 1.0, steps + 1)
    if front:
        zs = centre_z - reach * (1.0 - ts)
    else:
        zs = centre_z + reach * ts
    return [(float(z), float(math.sqrt(max(radius * radius - (z - centre_z) ** 2, 0.0)))) for z in zs]


def _materials_by_z(profile: Sequence[tuple[float, float]], paint: Callable[[float, float, float], Material]) -> list[Material]:
    """One material per profile segment from its middle (z, r) and whether it is a flat face (``dz == 0``)."""
    out = []
    for (z0, r0), (z1, r1) in zip(profile[:-1], profile[1:], strict=True):
        out.append(paint(0.5 * (z0 + z1), 0.5 * (r0 + r1), z1 - z0))
    return out


def _lerp(table: Sequence[Sequence[float]], at: np.ndarray | float, column: int) -> np.ndarray:
    keys = [row[0] for row in table]
    return np.interp(at, keys, [row[column] for row in table])


def _pwl(x: np.ndarray, knots_x: np.ndarray, knots_y: np.ndarray) -> np.ndarray:
    """Per-point piecewise-linear value: ``knots_*`` are ``(n, k)`` rows of increasing x."""
    out = knots_y[:, -1].copy()
    for k in range(knots_x.shape[1] - 2, -1, -1):
        x0, x1, y0, y1 = knots_x[:, k], knots_x[:, k + 1], knots_y[:, k], knots_y[:, k + 1]
        t = np.clip((x - x0) / np.where(x1 > x0, x1 - x0, 1.0), 0.0, 1.0)
        here = x <= x1
        out = np.where(here, y0 + t * (y1 - y0), out)
    return out


def _radial(phi: float) -> np.ndarray:
    return np.array([math.cos(phi), math.sin(phi), 0.0])


# --- the forward capsule ----------------------------------------------------------------------------------------------
def capsule_profile() -> list[tuple[float, float]]:
    """The capsule's outline: a flat nose face, the neck, a front dome, the long barrel with its bands, an aft dome and
    the spine running back into the collar."""
    front = _sphere_arc(DOME_CENTRES[0], CAPSULE_R, NECK_R, True, 6)
    aft = _sphere_arc(DOME_CENTRES[1], CAPSULE_R, NECK_R, False, 6)
    (b0, b1), (b2, b3) = BAND_Z
    barrel = [(b0, CAPSULE_R), (b1, CAPSULE_R), (b2, CAPSULE_R), (b3, CAPSULE_R)]
    return [(CAPSULE_FACE_Z, 0.0), (CAPSULE_FACE_Z, 1.75), (CAPSULE_FACE_Z, NECK_R), *front, *barrel, *aft,
            (SPINE_END_Z, NECK_R), (SPINE_END_Z, 0.0)]  # fmt: skip


def capsule(style: Style) -> Piece:
    """The capsule from its nose face to the spine's end. Its nose face is a dark recessed panel; two red-orange bands
    run round the barrel."""
    hull, dark, stripe = style.material("hull"), style.material("hull_dark"), style.material("stripe")
    profile = capsule_profile()

    def paint(z: float, r: float, dz: float) -> Material:
        if dz == 0.0 and z < 2.0 and r < 1.75:
            return dark
        return stripe if any(a <= z <= b for a, b in BAND_Z) and r > CAPSULE_R - 0.01 else hull

    creases = {2, 3, len(profile) - 3, len(profile) - 2}
    mesh = _axial(profile, CAPSULE_AXIS, 56, _materials_by_z(profile, paint), creases)
    solid = _axial_solid([p for p in profile if p[1] > 0.0], CAPSULE_AXIS)
    c0, c1 = DOME_CENTRES
    hit = Collision("capsule", (CAPSULE_AXIS[0], CAPSULE_AXIS[1], 0.5 * (c0 + c1)), radius=CAPSULE_R,
                    height=(c1 - c0) + 2.0 * CAPSULE_R, name="barrel")  # fmt: skip
    return _piece("capsule", "capsule", mesh, solid, mass_kg=300_000.0, collision=[hit])


@dataclass(frozen=True)
class VaneSpec:
    """A nose vane: a plate square to its radius, splayed forward from ``inner`` to ``outer`` ((radius, z) about the
    capsule axis) and narrowing towards its tip, with a strut behind it running back into the neck."""

    inner: tuple[float, float] = (2.85, 1.45)
    outer: tuple[float, float] = (4.55, 0.05)
    width: tuple[float, float] = (2.09, 1.13)  # at the root and at the tip
    thickness: float = 0.22
    strut: tuple[tuple[float, float], tuple[float, float]] = ((1.9, 2.25), (3.6, 0.95))
    strut_size: tuple[float, float] = (0.3, 0.18)


def _vane(spec: VaneSpec, phi: float, style: Style) -> tuple[Mesh, Anchor]:
    e, t = _radial(phi), _radial(phi + 0.5 * math.pi)
    axis = np.array([CAPSULE_AXIS[0], CAPSULE_AXIS[1], 0.0])
    ez = np.array([0.0, 0.0, 1.0])

    def at(r: float, z: float) -> np.ndarray:
        return axis + r * e + z * ez

    hull = style.material("hull")
    plate = sweep_rect(np.array([at(*spec.inner), at(*spec.outer)]), t, list(spec.width), [spec.thickness] * 2, hull)
    (a, b), (w, h) = spec.strut, spec.strut_size
    strut = sweep_rect(np.array([at(*a), at(*b)]), t, [w, w], [h, h], hull)
    return Mesh.concatenate([plate, strut]), Anchor(at(*spec.outer), e)


def nose_vanes(style: Style, spec: VaneSpec = VaneSpec()) -> list[Piece]:
    """The four vanes round the nose: the top and bottom pair on the centre line, the right one (mirrored)."""
    top, a_top = _vane(spec, 0.5 * math.pi, style)
    bottom, a_bottom = _vane(spec, 1.5 * math.pi, style)
    right, a_right = _vane(spec, 0.0, style)
    reach = spec.outer[0] + 0.1
    nose = Collision("box", (CAPSULE_AXIS[0], CAPSULE_AXIS[1], 1.25), size=(2.0 * reach, 2.0 * reach, 2.5), name="nose")
    return [
        _piece("vanes", "capsule", Mesh.concatenate([top, bottom]), mass_kg=4_000.0, collision=[nose],
               anchors={"vane_top": a_top, "vane_bottom": a_bottom}, fine=0.6),  # fmt: skip
        _piece("vane_r", "capsule", right, side=RIGHT, mass_kg=2_000.0, anchors={"vane": a_right}, fine=0.6),
    ]


@dataclass(frozen=True)
class BridgeSpec:
    """The raised plate on the capsule's top: pointed in front, its sides leaning in, its front glazed. Per station
    ``(z, half-width at the foot, half-width at the top, top)``; below the foot (``foot_y``) the walls drop straight
    into the capsule."""

    stations: tuple[tuple[float, float, float, float], ...] = (
        (10.44, 0.43, 0.43, 3.45), (10.67, 0.49, 0.45, 3.63), (12.6, 1.03, 0.68, 3.95), (14.69, 1.62, 0.93, 4.29),
        (16.41, 1.08, 0.73, 3.84), (16.66, 1.0, 0.6, 3.45),
    )  # fmt: skip
    bottom: float = 2.85  # inside the capsule
    foot_y: float = 3.39
    glass_end_z: float = 12.6  # a station, so the glazing ends on a facet edge

    def ring(self, z: float, foot: float, top_w: float, top: float) -> np.ndarray:
        y0, y1 = self.bottom, min(self.foot_y, top - 0.05)
        return np.array([[foot, y0, z], [foot, y1, z], [top_w, top, z], [-top_w, top, z], [-foot, y1, z], [-foot, y0, z]])

    def solid(self) -> Solid:
        st = self.stations

        def test(p: np.ndarray, margin: float) -> np.ndarray:
            z, y = p[:, 2], p[:, 1]
            foot, top_w, top = _lerp(st, z, 1), _lerp(st, z, 2), _lerp(st, z, 3)
            lean = np.clip((y - self.foot_y) / np.maximum(top - self.foot_y, 1e-6), 0.0, 1.0)
            half = foot + (top_w - foot) * lean
            inside_z = (z > st[0][0] + margin) & (z < st[-1][0] - margin)
            return inside_z & (np.abs(p[:, 0]) < half - margin) & (y > self.bottom + margin) & (y < top - margin)

        w_max, top_max = max(s[1] for s in st), max(s[3] for s in st)
        return Solid(test, ((-w_max, self.bottom, st[0][0]), (w_max, top_max, st[-1][0])))


def bridge(style: Style, spec: BridgeSpec = BridgeSpec()) -> Piece:
    """The bridge plate; its front faces are dark glass. Anchors: ``eye`` (inside it, looking forward)."""
    hull, glass = style.material("hull"), style.material("canopy_glass")
    rings = [spec.ring(*s) for s in spec.stations]
    mesh = section_loft(rings, [hull] * 6, hull)
    c, n = mesh.face_centroids(), mesh.face_normals()
    mesh = assign_material_by_predicate(mesh, glass, (c[:, 2] < spec.glass_end_z) & ((n[:, 1] > 0.3) | (n[:, 2] < -0.7)))
    return _piece("bridge", "capsule", mesh, spec.solid(), mass_kg=20_000.0, collision=[_box_of(mesh)],
                  anchors={"eye": Anchor(BRIDGE_EYE, (0.0, 0.0, -1.0))}, fine=0.7)  # fmt: skip


@dataclass(frozen=True)
class BellyFinSpec:
    """A thin trapezoid fin under the capsule, angled down and outboard: its plane runs from ``root`` (x, y) along
    ``slope_deg`` below the horizontal; ``outline`` is ``(distance out, z)``."""

    root: tuple[float, float] = (2.0, -2.45)
    slope_deg: float = 24.1
    outline: tuple[tuple[float, float], ...] = ((0.0, 6.0), (6.17, 7.8), (6.17, 9.95), (0.0, 12.75))
    thickness: float = 0.32

    def basis(self) -> np.ndarray:
        a = math.radians(self.slope_deg)
        d = np.array([math.cos(a), -math.sin(a), 0.0])
        ez = np.array([0.0, 0.0, 1.0])
        return np.column_stack([d, ez, np.cross(d, ez)])


def belly_fin(style: Style, spec: BellyFinSpec = BellyFinSpec()) -> Piece:
    b = spec.basis()
    origin = (spec.root[0], spec.root[1], 0.0)
    mesh = prism([(np.array(spec.outline), style.material("hull"))], [(np.array(spec.outline), style.material("hull"))],
                 spec.thickness).transformed(b, origin)  # fmt: skip
    return _piece("belly_fin_r", "capsule", mesh, side=RIGHT, mass_kg=6_000.0, collision=[_box_of(mesh, basis=b)], fine=0.8)


# --- spine, collar, side tanks ------------------------------------------------------------------------------------------
def collar(style: Style) -> Piece:
    """The collar where the spine enters the body."""
    profile = [(29.22, 0.0), (29.22, 3.17), (35.2, 3.17), (35.2, 0.0)]
    panel = style.material("hull_panel")
    mesh = _axial(profile, CAPSULE_AXIS, 48, panel, creases={1, 2})
    solid = _axial_solid(profile[1:3], CAPSULE_AXIS)
    hit = _box_of(mesh)
    return _piece("collar", "capsule", mesh, solid, mass_kg=60_000.0, collision=[hit])


SPINE_VANES = (
    ((18.56, 2.1), (18.56, 3.12), (20.4, 3.12), (22.85, 2.2), (22.85, 2.1)),  # (z, r): tall by the capsule's aft dome
    ((27.03, 2.1), (27.03, 2.2), (29.4, 3.12), (31.32, 3.12), (31.32, 2.1)),  # and tall by the collar
)


def vane_rings(style: Style) -> Piece:
    """Twelve short radial vanes round each end of the spine, each a wedge rising towards the capsule or the collar."""
    panel = style.material("hull_panel")
    mesh = Mesh.concatenate(_ribs(outline, 12, 0.4, panel, CAPSULE_AXIS) for outline in SPINE_VANES)
    spine = Collision("box", (CAPSULE_AXIS[0], CAPSULE_AXIS[1], 0.5 * (18.56 + 29.22)), size=(6.3, 6.3, 29.22 - 18.56))
    return _piece("spine_vanes", "capsule", mesh, mass_kg=12_000.0, collision=[spine])


def side_tank(style: Style) -> Piece:
    """The right capsule tank with its red-orange band and its neck running into the body's front face."""
    hull, panel, stripe = style.material("hull"), style.material("hull_panel"), style.material("stripe")
    b0, b1 = TANK_BAND_Z
    profile = [(19.39, 0.0), (19.39, 1.05), (19.5, 1.42), (19.95, 1.8), (20.45, 2.05), (20.95, 2.14), (21.4, TANK_R),
               (b0, TANK_R), (b1, TANK_R), (27.6, TANK_R), (27.95, 2.13), (28.45, 1.99), (28.95, 1.69), (29.35, 1.27),
               (34.9, 1.27), (34.9, 0.0)]  # fmt: skip

    def paint(z: float, r: float, dz: float) -> Material:
        if b0 <= z <= b1 and r > TANK_R - 0.01:
            return stripe
        return panel if z > 29.3 else hull

    mesh = _axial(profile, TANK_AXIS, 40, _materials_by_z(profile, paint), creases={1, 13, 14})
    solid = _axial_solid(profile[1:-1], TANK_AXIS)
    return _piece("tank_r", "capsule", mesh, solid, side=RIGHT, mass_kg=70_000.0, collision=[_box_of(mesh)])


def dumbbell(style: Style) -> Piece:
    """The small dumbbell tank ahead of each side tank."""
    profile = [(10.16, 0.0), (10.2, 0.3), (10.55, 0.6), (10.9, 0.8), (12.65, 0.8), (13.0, 0.73), (13.7, 0.47), (15.8, 0.47),
               (16.5, 0.74), (16.85, 0.84), (17.55, 0.84), (18.1, 0.48), (19.9, 0.46), (19.9, 0.0)]  # fmt: skip
    mesh = _axial(profile, TANK_AXIS, 24, style.material("hull_panel"))
    solid = _axial_solid(profile[1:-1], TANK_AXIS)
    return _piece("dumbbell_r", "capsule", mesh, solid, side=RIGHT, mass_kg=8_000.0, collision=[_box_of(mesh)], fine=0.8)


TANK_BRACKET = ((3.87, 19.0), (4.3, 18.44), (6.6, 18.44), (7.02, 19.0), (7.02, 20.3), (3.87, 20.3))  # plan (x, z)


def tank_bracket(style: Style) -> Piece:
    """The flat bracket round the dumbbell's rod where it meets the right tank's nose."""
    mesh = _plate_y(TANK_BRACKET, -0.445, 0.63, style.material("hull_dark"))
    return _piece("tank_bracket_r", "capsule", mesh, side=RIGHT, mass_kg=1_500.0, collision=[_box_of(mesh)], fine=0.8)


SPINE_PLATE = ((0.8, 21.4), (4.3, 22.5), (4.3, 27.0), (0.8, 28.8))  # plan (x, z): from the spine out to the tank


def spine_plate(style: Style) -> Piece:
    """The flat plate joining the spine to the right tank."""
    mesh = _plate_y(SPINE_PLATE, -0.32, 0.55, style.material("hull_panel"))
    return _piece("spine_plate_r", "capsule", mesh, side=RIGHT, mass_kg=4_000.0, collision=[_box_of(mesh)], fine=0.8)


FRONT_BAR = ((6.89, 30.86), (7.65, 32.33), (7.83, 35.83), (6.89, 35.83))  # plan (x, z): a pointed bar ahead of the body
FRONT_BAR_Y, FRONT_BAR_T = -0.535, 0.51


def front_bar(style: Style) -> Piece:
    """The pointed flat bar beside each tank's neck, running from ahead of the body into its front face."""
    mesh = _plate_y(FRONT_BAR, FRONT_BAR_Y, FRONT_BAR_T, style.material("hull"))
    return _piece("front_bar_r", "capsule", mesh, side=RIGHT, mass_kg=2_000.0, collision=[_box_of(mesh)], fine=0.8)


# --- the body ---------------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class BodySpec:
    """The faceted slab: a flattened diamond in section whose top ridge and keel are on the centre line and whose side
    faces are low on its flanks. Per station: ``(z, w, top, top3, edge_up, edge_low, knee_y, low_y, bottom3, keel)``:
    half-width, the top at x = 0 and x = 3, the side face's top and bottom at x = w, the bottom's knee near x = 7 and its
    lowest point just inside the edge, the bottom at x = 3 and x = 0."""

    stations: tuple[tuple[float, ...], ...] = (
        (32.07, 7.06, 2.10, 2.28, 0.64, -1.36, -2.00, -1.75, -3.03, -3.00),
        (33.3, 7.06, 3.05, 2.44, 0.64, -1.35, -2.00, -1.75, -3.27, -4.00),
        (34.5, 7.28, 3.05, 2.36, 0.50, -1.30, -1.95, -1.60, -3.22, -3.96),
        (35.5, 7.84, 3.01, 2.33, 0.25, -1.15, -1.96, -1.55, -3.15, -3.91),
        (36.5, 8.46, 2.95, 2.28, -0.10, -1.25, -1.92, -1.45, -3.14, -3.85),
        (37.5, 9.43, 2.87, 2.24, -0.55, -1.50, -1.79, -1.70, -3.07, -3.78),
        (38.5, 10.41, 2.79, 2.16, -1.00, -1.78, -1.82, -1.80, -2.99, -3.70),
        (39.5, 11.19, 2.70, 2.07, -1.30, -1.90, -1.91, -1.90, -2.93, -3.61),
        (40.5, 11.62, 2.61, 2.03, -1.25, -1.75, -1.91, -2.07, -2.86, -3.51),
        (41.5, 11.95, 2.51, 1.94, -1.10, -1.80, -1.90, -2.19, -2.80, -3.42),
        (42.5, 11.97, 2.41, 1.84, -1.07, -1.98, -1.89, -2.23, -2.70, -3.32),
        (44.5, 11.96, 2.22, 1.70, -1.08, -1.95, -1.80, -2.23, -2.54, -3.13),
        (46.5, 11.76, 2.05, 1.56, -1.14, -1.87, -1.73, -2.17, -2.40, -2.95),
        (47.5, 11.30, 1.98, 1.49, -1.25, -1.80, -1.68, -2.12, -2.33, -2.88),
        (48.5, 10.84, 1.92, 1.43, -1.35, -1.85, -1.66, -2.05, -2.29, -2.82),
        (49.5, 10.36, 1.87, 1.38, -1.25, -1.80, -1.65, -1.96, -2.22, -2.77),
        (50.5, 9.47, 1.82, 1.33, -1.10, -1.45, -1.55, -1.62, -2.17, -2.72),
        (51.6, 8.55, 1.78, 1.28, -0.85, -1.21, -1.25, -1.25, -2.13, -2.68),
    )  # fmt: skip
    knee_x: float = 7.0  # or 1.6 m inside the edge, where that is nearer
    low_inset: float = 0.9  # the lowest point of the bottom, inside the edge

    def at(self, z: float | np.ndarray) -> list[np.ndarray]:
        return [_lerp(self.stations, z, k) for k in range(1, 10)]

    def half_ring(self, z: float) -> list[tuple[float, float]]:
        """The right half from the top ridge round the flank to the keel."""
        w, top, top3, up, low, knee, lowest, bot3, keel = (float(v) for v in self.at(z))
        kx = min(self.knee_x, w - 1.6)
        return [(0.0, top), (1.0, top - 0.03), (3.0, top3), (w, up), (w, low), (w - self.low_inset, lowest), (kx, knee),
                (3.0, bot3), (1.0, keel + 0.04), (0.0, keel)]  # fmt: skip

    def ring(self, z: float) -> np.ndarray:
        right = self.half_ring(z)
        left = [(-x, y) for x, y in reversed(right[1:-1])]
        pts = right + left
        return np.array([[x, y, z] for x, y in pts])

    def solid(self) -> Solid:
        """Inside the slab: within the half-width and between the bottom and the top polylines at the point's z."""
        st = self.stations

        def test(p: np.ndarray, margin: float) -> np.ndarray:
            z = p[:, 2]
            w, top, top3, up, low, knee, lowest, bot3, keel = self.at(z)
            n = len(p)
            ax = np.abs(p[:, 0])
            kx = np.minimum(self.knee_x, w - 1.6)
            tx = np.column_stack([np.zeros(n), np.ones(n), np.full(n, 3.0), w])
            ty = np.column_stack([top, top - 0.03, top3, up])
            bx = np.column_stack([np.zeros(n), np.ones(n), np.full(n, 3.0), kx, w - self.low_inset, w])
            by = np.column_stack([keel, keel + 0.04, bot3, knee, lowest, low])
            y_top, y_bot = _pwl(ax, tx, ty), _pwl(ax, bx, by)
            inside_z = (z > st[0][0] + margin) & (z < st[-1][0] - margin)
            return inside_z & (ax < w - margin) & (p[:, 1] < y_top - margin) & (p[:, 1] > y_bot + margin)

        w_max = max(s[1] for s in st)
        return Solid(test, ((-w_max, min(s[9] for s in st), st[0][0]), (w_max, max(s[2] for s in st), st[-1][0])))


def body(style: Style, spec: BodySpec = BodySpec()) -> Piece:
    """The body slab. Olive patches run along its ridge and its flanks. Collision: two centre boxes (front and aft) and
    one box over each flank."""
    hull, panel = style.material("hull"), style.material("hull_panel")
    rings = [spec.ring(s[0]) for s in spec.stations]
    half = [hull, panel, hull, panel, panel, hull, hull, hull, hull]  # top ridge, ridge flank, top, side face, ...
    edges = half + half[::-1]
    mesh = section_loft(rings, edges, hull)
    st = spec.stations
    z0, zm, z1 = st[0][0], 42.0, st[-1][0]
    front_top, front_keel = max(s[2] for s in st if s[0] <= zm), min(s[9] for s in st if s[0] <= zm)
    aft_top, aft_keel = float(_lerp(st, zm, 2)), float(_lerp(st, zm, 9))
    flank_lo = min(min(s[5], s[7]) for s in st)
    flank_hi = max(s[4] for s in st if s[0] >= 34.0) + 0.3
    w_max = max(s[1] for s in st)
    collision = [
        Collision("box", (0.0, 0.5 * (front_top + front_keel), 0.5 * (z0 + zm)), size=(12.4, front_top - front_keel, zm - z0), name="front"),
        Collision("box", (0.0, 0.5 * (aft_top + aft_keel), 0.5 * (zm + z1)), size=(12.4, aft_top - aft_keel, z1 - zm), name="aft"),
    ]
    for side, sx in (("r", 1.0), ("l", -1.0)):
        x0 = 6.2
        collision.append(Collision("box", (sx * 0.5 * (x0 + w_max), 0.5 * (flank_lo + flank_hi), 0.5 * (34.0 + z1)),
                                   size=(w_max - x0, flank_hi - flank_lo, z1 - 34.0), name=f"side_{side}"))  # fmt: skip
    return _piece("body", "body", mesh, spec.solid(), mass_kg=700_000.0, collision=collision, fine=1.15)


CORNER_FIN = ((4.9, 51.2), (8.75, 51.2), (6.05, 54.5), (5.6, 54.5))  # plan (x, z) of the right aft corner fin
CORNER_FIN_Y, CORNER_FIN_T = -0.75, 0.5


def corner_fin(style: Style) -> Piece:
    mesh = _plate_y(CORNER_FIN, CORNER_FIN_Y, CORNER_FIN_T, style.material("hull_panel"))
    tip = Anchor((CORNER_FIN[2][0], CORNER_FIN_Y, CORNER_FIN[2][1] - 0.15), (1.0, 0.0, 0.0))
    return _piece("corner_fin_r", "body", mesh, _plate_y_solid(CORNER_FIN, CORNER_FIN_Y, CORNER_FIN_T), side=RIGHT,
                  mass_kg=5_000.0, collision=[_box_of(mesh)], anchors={"tip": tip}, fine=0.8)  # fmt: skip


@dataclass(frozen=True)
class DorsalFinSpec:
    """The sharp fin on the body's back: lens-shaped sections stacked up y, per station ``(y, front z, back z,
    half-width)``."""

    stations: tuple[tuple[float, float, float, float], ...] = (
        (1.3, 41.4, 54.6, 1.22), (1.8, 41.7, 54.3, 1.17), (2.1, 42.0, 53.7, 1.05), (2.4, 42.9, 53.15, 0.65),
        (2.7, 45.6, 52.85, 0.55), (3.0, 46.2, 52.8, 0.45), (3.9, 47.4, 52.2, 0.4), (4.5, 48.0, 51.9, 0.3),
        (5.13, 48.9, 51.6, 0.2),
    )  # fmt: skip
    shoulder: float = 0.25  # the lens is widest from this share of its chord to the same share from its back

    def ring(self, y: float, zf: float, zb: float, hw: float) -> np.ndarray:
        s = self.shoulder * (zb - zf)
        pts = [(0.0, zf), (hw, zf + s), (hw, zb - s), (0.0, zb), (-hw, zb - s), (-hw, zf + s)]
        return np.array([[x, y, z] for x, z in pts])

    def solid(self) -> Solid:
        st = self.stations

        def test(p: np.ndarray, margin: float) -> np.ndarray:
            y, z = p[:, 1], p[:, 2]
            zf, zb, hw = _lerp(st, y, 1), _lerp(st, y, 2), _lerp(st, y, 3)
            s = self.shoulder * (zb - zf)
            half = hw * np.clip(np.minimum((z - zf) / s, (zb - z) / s), 0.0, 1.0)
            inside_y = (y > st[0][0] + margin) & (y < st[-1][0] - margin)
            return inside_y & (np.abs(p[:, 0]) < half - margin)

        hw = max(s[3] for s in st)
        return Solid(test, ((-hw, st[0][0], min(s[1] for s in st)), (hw, st[-1][0], max(s[2] for s in st))))


def dorsal_fin(style: Style, spec: DorsalFinSpec = DorsalFinSpec()) -> Piece:
    """The fin. Anchors: ``top`` (its crest, up)."""
    rings = [spec.ring(*s) for s in spec.stations]
    mesh = section_loft(rings, [style.material("hull")] * 6, style.material("hull"))
    y, zf, zb, _hw = spec.stations[-1]
    top = Anchor((0.0, y, 0.5 * (zf + zb)), (0.0, 1.0, 0.0))
    return _piece("dorsal_fin", "body", mesh, spec.solid(), mass_kg=15_000.0, collision=[_box_of(mesh)],
                  anchors={"top": top}, fine=0.6)  # fmt: skip


def centre_engine(style: Style) -> list[Piece]:
    """The drum inside the body's tail, the exhaust cone behind it and the ring of vanes round the cone's neck."""
    panel, dark = style.material("hull_panel"), style.material("hull_dark")
    nozzle, throat = style.material("nozzle"), style.material("nozzle_throat")
    drum_profile = [(42.83, 0.0), (42.83, 2.37), (53.52, 2.37), (53.52, 0.0)]
    drum = _axial(drum_profile, CAPSULE_AXIS, 40, [panel, panel, dark], creases={1, 2})
    cone_profile = [(53.3, 0.0), (53.3, 1.44), (54.9, 1.44), (55.45, 1.85), (59.2, 1.18), (59.2, 0.95), (58.0, 0.85), (58.0, 0.0)]
    cone = _axial(cone_profile, CAPSULE_AXIS, 40, [nozzle, nozzle, nozzle, nozzle, throat, throat, throat], creases={1, 2, 3, 4, 5, 6})
    vanes = []
    for k in range(12):
        blade = box((0.88, 0.2, 2.91), dark, center=(1.84, 0.0, 53.515))
        vanes.append(_on_axis(blade.transformed(rotation_z(math.radians(30.0 * k))), CAPSULE_AXIS))
    vane_mesh = Mesh.concatenate(vanes)
    return [
        _piece("engine_drum", "body", drum, _axial_solid(drum_profile[1:3], CAPSULE_AXIS), mass_kg=60_000.0,
               collision=[Collision("box", (0.0, CAPSULE_AXIS[1], 52.16), size=(4.74, 4.74, 2.72))]),  # fmt: skip
        _piece("engine_cone", "body", cone, _axial_solid(cone_profile[1:5], CAPSULE_AXIS), mass_kg=20_000.0,
               collision=[_box_of(cone)]),  # fmt: skip
        _piece("engine_vanes", "body", vane_mesh, mass_kg=3_000.0, fine=0.8),
    ]


AFT_BLOCKS = (((2.85, 1.62, 1.99), (3.255, -0.33, 50.735)), ((0.73, 0.99, 2.49), (2.765, -0.995, 51.005)))  # size, centre


def aft_blocks(style: Style) -> Piece:
    """The blocks on the body's aft face beside the centre engine."""
    dark = style.material("hull_dark")
    mesh = Mesh.concatenate(box(size, dark, center=centre) for size, centre in AFT_BLOCKS)
    return _piece("aft_blocks_r", "body", mesh, side=RIGHT, mass_kg=6_000.0, collision=[_box_of(mesh)], fine=0.8)


def pedestal(style: Style) -> Piece:
    """The low drum the dorsal turret stands on, reaching down into the body's top. Anchors: ``turret`` (its top, up)."""
    x, y, z = TURRET_MOUNT
    profile = [(2.4, 0.0), (2.4, PEDESTAL_R), (y, PEDESTAL_R), (y, 0.0)]
    panel, dark = style.material("hull_panel"), style.material("hull_dark")
    mesh = lathe(profile, 32, [panel, panel, dark], creases={1, 2}).transformed(_Z_TO_Y, (x, 0.0, z))
    solid = lathe_solid(profile[1:3]).transformed(_Z_TO_Y, (x, 0.0, z))
    return _piece("pedestal", "body", mesh, solid, mass_kg=4_000.0, collision=[_box_of(mesh)],
                  anchors={"turret": Anchor(TURRET_MOUNT, (0.0, 1.0, 0.0))})  # fmt: skip


# --- the nacelles --------------------------------------------------------------------------------------------------------
NACELLE_PROFILE = (
    (35.9, 0.0), (35.9, 1.0), (NACELLE_FRONT_Z, 1.1), (NACELLE_FRONT_Z, NACELLE_INTAKE_R), (36.0, 1.55), (36.5, 1.70),
    (38.1, 1.95), (38.4, 1.80), (38.75, 1.80), (39.0, 2.09), (39.5, 2.20), (45.0, 2.55), (49.5, 2.87), (49.95, 2.76),
    (50.3, 2.48), (50.7, 2.48), (50.95, 2.65), (54.0, 2.07), (54.4, 1.97), (NACELLE_EXIT_Z, NACELLE_EXIT_R),
    (NACELLE_EXIT_Z, 1.30), (54.7, 1.15), (54.7, 0.0),
)  # fmt: skip


def nacelle_radius(z: float) -> float:
    """The nacelle's outer radius at ``z`` (on its body, between the intake and the bell)."""
    outer = NACELLE_PROFILE[3:20]
    return float(np.interp(z, [p[0] for p in outer], [p[1] for p in outer]))


def nacelle(style: Style) -> Piece:
    """The right nacelle: a dark ribbed intake ring, the sand body, the dark bell and its bore. Anchors: ``main`` (the
    bell's exit, aft), ``retro`` (the intake's face, forward), ``centre``."""
    hull, dark = style.material("hull"), style.material("hull_dark")
    nozzle, throat = style.material("nozzle"), style.material("nozzle_throat")
    mats = [dark] + [nozzle] * 5 + [dark] * 3 + [hull] * 3 + [nozzle] * 7 + [throat] * 3
    smooth = {4, 5, 10, 11, 17, 18}
    creases = set(range(1, len(NACELLE_PROFILE) - 1)) - smooth
    mesh = _axial(NACELLE_PROFILE, NACELLE_AXIS, 48, mats, creases)
    solid = _axial_solid(NACELLE_PROFILE[3:20], NACELLE_AXIS)
    ax, ay = NACELLE_AXIS
    main, retro = (ax, ay, NACELLE_EXIT_Z), (ax, ay, NACELLE_FRONT_Z)
    anchors = {"main": Anchor(main, (0.0, 0.0, 1.0)), "retro": Anchor(retro, (0.0, 0.0, -1.0)),
               "centre": Anchor(0.5 * (np.array(main) + np.array(retro)))}  # fmt: skip
    reach = 3.05  # the bell's ribs
    hit = Collision("box", (ax, ay, 0.5 * (NACELLE_FRONT_Z + NACELLE_EXIT_Z)), size=(2.0 * reach, 2.0 * reach, NACELLE_EXIT_Z - NACELLE_FRONT_Z))
    return _piece("nacelle_r", "nacelle_r", mesh, solid, side=RIGHT, mass_kg=150_000.0, collision=[hit], anchors=anchors)


@dataclass(frozen=True)
class ConeSpec:
    """A pod on the nacelle pointing out at ``angle_deg`` from the outboard horizontal: elliptical sections, per station
    ``(distance from the nacelle axis, half-width across, half-length along z)``, its root buried in the nacelle."""

    angle_deg: float
    stations: tuple[tuple[float, float, float], ...]

    def axes(self) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        a = math.radians(self.angle_deg)
        u = np.array([math.cos(a), math.sin(a), 0.0])
        v = np.array([-math.sin(a), math.cos(a), 0.0])
        return u, v, np.array([0.0, 0.0, 1.0])

    @property
    def tip(self) -> float:
        return self.stations[-1][0]

    def solid(self) -> Solid:
        st = self.stations

        def test(p: np.ndarray, margin: float) -> np.ndarray:
            t = p[:, 2]
            a, b = _lerp(st, t, 1), _lerp(st, t, 2)
            inside_t = (t > st[0][0] + margin) & (t < st[-1][0] - margin)
            q = (p[:, 0] / np.maximum(a - margin, 1e-3)) ** 2 + (p[:, 1] / np.maximum(b - margin, 1e-3)) ** 2
            return inside_t & (q < 1.0)

        u, v, ez = self.axes()
        a_max, b_max = max(s[1] for s in st), max(s[2] for s in st)
        origin = (NACELLE_AXIS[0], NACELLE_AXIS[1], CONE_Z)
        return Solid(test, ((-a_max, -b_max, st[0][0]), (a_max, b_max, st[-1][0])), np.column_stack([v, ez, u]), origin)


CONE_UP = ConeSpec(42.0, ((1.4, 1.3, 2.0), (2.4, 1.25, 1.85), (2.8, 1.2, 1.72), (3.8, 0.79, 0.8), (4.3, 0.65, 0.65),
                          (4.45, 0.62, 0.62), (4.57, 0.6, 0.6)))  # fmt: skip
CONE_DOWN = ConeSpec(-48.0, ((1.4, 1.3, 2.0), (2.4, 1.25, 1.85), (2.8, 1.2, 1.72), (3.8, 0.8, 0.8), (4.3, 0.66, 0.66),
                             (4.4, 0.45, 0.45), (4.45, 0.72, 0.72), (4.99, 0.66, 0.66)))  # fmt: skip


def _cone(spec: ConeSpec, style: Style) -> tuple[Mesh, Anchor, Collision]:
    u, v, ez = spec.axes()
    centre = np.array([NACELLE_AXIS[0], NACELLE_AXIS[1], CONE_Z])
    angles = 2.0 * math.pi * np.arange(24) / 24
    rings = [centre + t * u + a * np.cos(angles)[:, None] * v + b * np.sin(angles)[:, None] * ez for t, a, b in spec.stations]
    mesh = closed_loft(rings, style.material("hull"), style.material("hull_dark"))
    basis = np.column_stack([v, ez, u])
    return mesh, Anchor(centre + spec.tip * u, u), _box_of(mesh, basis=basis)


def nacelle_cones(style: Style) -> list[Piece]:
    """The two pods on the right nacelle, up-outboard and down-outboard. Anchors: ``tip`` (its end, outward)."""
    pieces = []
    for name, spec in (("cone_up_r", CONE_UP), ("cone_down_r", CONE_DOWN)):
        mesh, tip, hit = _cone(spec, style)
        pieces.append(_piece(name, "nacelle_r", mesh, spec.solid(), side=RIGHT, mass_kg=6_000.0, collision=[hit],
                             anchors={"tip": tip}, fine=0.7))  # fmt: skip
    return pieces


BELL_RIB = ((49.55, 2.4), (49.55, 3.02), (51.0, 3.02), (52.6, 2.52), (53.1, 2.22), (53.1, 1.95), (50.6, 2.1))  # (z, r)
INTAKE_RIB = ((37.78, 1.6), (37.78, 2.04), (38.69, 2.04), (38.69, 1.6))


def _ribs(outline: Sequence[tuple[float, float]], count: int, thickness: float, material: Material,
          axis: Sequence[float] = NACELLE_AXIS) -> Mesh:  # fmt: skip
    """Radial plates round a z-parallel axis (the nacelle's by default), each the outline ``(z, r)`` stood on its
    radius, the first at the outboard horizontal."""
    poly = np.array(outline)
    plate = prism([(poly, material)], [(poly, material)], thickness)
    ribs = []
    for k in range(count):
        phi = 2.0 * math.pi * k / count
        e = _radial(phi)
        basis = np.column_stack([np.array([0.0, 0.0, 1.0]), e, np.cross([0.0, 0.0, 1.0], e)])
        ribs.append(plate.transformed(basis, (axis[0], axis[1], 0.0)))
    return Mesh.concatenate(ribs)


def nacelle_ribs(style: Style) -> list[Piece]:
    """The ribbed rings: 24 plates round the bell, 16 round the intake, both in the bells' dark metal."""
    nozzle = style.material("nozzle")
    return [
        _piece("bell_ribs_r", "nacelle_r", _ribs(BELL_RIB, 24, 0.16, nozzle), side=RIGHT, mass_kg=6_000.0, fine=0.85),
        _piece("intake_ribs_r", "nacelle_r", _ribs(INTAKE_RIB, 16, 0.15, nozzle), side=RIGHT, mass_kg=1_000.0, fine=0.7),
    ]


@dataclass(frozen=True)
class ClawSpec:
    """A forked claw: two prongs either side of a gap, joined by a web over the front of their length. Per station
    ``(z, x at the gap faces, x at the outer faces, prong thickness, width)``: the prongs lean, so their outer faces sit
    at another x than their gap faces. ``gap`` is the gap's ``(low, high)`` y."""

    stations: tuple[tuple[float, float, float, float, float], ...]
    gap: tuple[float, float]
    web_end_z: float

    def prong(self, upper: bool) -> list[np.ndarray]:
        lo, hi = self.gap
        rings = []
        for z, xg, xo, h, w in self.stations:
            yg, yo = (hi, hi + h) if upper else (lo, lo - h)
            rings.append(np.array([[xg - 0.5 * w, yg, z], [xg + 0.5 * w, yg, z], [xo + 0.5 * w, yo, z], [xo - 0.5 * w, yo, z]]))
        return rings

    def web(self) -> list[np.ndarray]:
        lo, hi = self.gap
        rows = [s for s in self.stations if s[0] < self.web_end_z]
        end = (self.web_end_z, *(float(np.interp(self.web_end_z, [s[0] for s in self.stations], [s[k] for s in self.stations])) for k in (1, 2, 3, 4)))
        rings = []
        for z, xg, _xo, _h, w in [*rows, end]:
            w = max(w, 0.2)
            rings.append(np.array([[xg - 0.5 * w, lo, z], [xg + 0.5 * w, lo, z], [xg + 0.5 * w, hi, z], [xg - 0.5 * w, hi, z]]))
        return rings


CLAW_OUT = ClawSpec(
    stations=((49.62, 16.94, 16.69, 0.27, 0.2), (51.45, 17.42, 16.96, 1.28, 0.35), (55.0, 18.57, 18.11, 1.28, 0.35),
              (58.5, 19.83, 19.68, 0.44, 0.16), (59.2, 20.03, 19.92, 0.28, 0.14), (60.0, 19.96, 19.88, 0.27, 0.08)),
    gap=(-1.06, 0.18),
    web_end_z=55.0,
)  # fmt: skip
CLAW_IN = ClawSpec(
    stations=((51.18, 9.83, 9.98, 0.17, 0.12), (52.32, 9.57, 9.86, 0.78, 0.22), (54.5, 8.94, 9.23, 0.78, 0.22),
              (56.65, 8.25, 8.34, 0.27, 0.1), (57.1, 8.15, 8.22, 0.18, 0.09), (57.56, 8.2, 8.25, 0.18, 0.06)),
    gap=(-0.81, -0.05),
    web_end_z=54.5,
)  # fmt: skip
PYLON_OUT = ((15.26, 50.82), (16.9, 50.41), (17.77, 53.07), (14.76, 53.49))  # plan (x, z), y -0.72 to -0.16
PYLON_IN = ((9.87, 51.65), (11.2, 51.87), (11.2, 53.5), (9.39, 53.29))  # plan (x, z), y -0.6 to -0.26


def _claw(spec: ClawSpec, style: Style) -> Mesh:
    hull = style.material("hull")
    parts = [section_loft(rings, [hull] * 4, hull) for rings in (spec.prong(True), spec.prong(False), spec.web())]
    return Mesh.concatenate(parts)


def _claw_basis(spec: ClawSpec) -> np.ndarray:
    """Box axes along the claw's run in plan: x across, y up, z along."""
    (z0, x0, *_), (z1, x1, *_) = spec.stations[0], spec.stations[-1]
    d = np.array([x1 - x0, 0.0, z1 - z0])
    d /= np.linalg.norm(d)
    up = np.array([0.0, 1.0, 0.0])
    return np.column_stack([np.cross(up, d), up, d])


def claws(style: Style) -> list[Piece]:
    """The right nacelle's two claws and the short pylons that carry them, all in the nacelle's chunk."""
    out = _claw(CLAW_OUT, style)
    inner = _claw(CLAW_IN, style)
    hull = style.material("hull")
    pylon_out = _plate_y(PYLON_OUT, -0.44, 0.56, hull)
    pylon_in = _plate_y(PYLON_IN, -0.43, 0.34, hull)
    return [
        _piece("claw_out_r", "nacelle_r", out, side=RIGHT, mass_kg=8_000.0, collision=[_box_of(out, basis=_claw_basis(CLAW_OUT))], fine=0.65),
        _piece("claw_in_r", "nacelle_r", inner, side=RIGHT, mass_kg=4_000.0, collision=[_box_of(inner, basis=_claw_basis(CLAW_IN))], fine=0.65),
        _piece("pylon_out_r", "nacelle_r", pylon_out, side=RIGHT, mass_kg=2_000.0, collision=[_box_of(pylon_out)], fine=0.6),
        _piece("pylon_in_r", "nacelle_r", pylon_in, side=RIGHT, mass_kg=1_000.0, collision=[_box_of(pylon_in)], fine=0.6),
    ]


def assemble(style: Style) -> list[Piece]:
    """Every centre and right piece of the hull, authored frame (the asset mirrors the right ones)."""
    pieces = [capsule(style), *nose_vanes(style), bridge(style), belly_fin(style), collar(style), vane_rings(style),
              side_tank(style), tank_bracket(style), dumbbell(style), spine_plate(style), front_bar(style)]  # fmt: skip
    pieces += [body(style), corner_fin(style), dorsal_fin(style), *centre_engine(style), aft_blocks(style), pedestal(style)]
    pieces += [nacelle(style), *nacelle_cones(style), *nacelle_ribs(style), *claws(style)]
    names = [p.name for p in pieces]
    if len(names) != len(set(names)):
        raise ValueError("piece names repeat")
    return pieces


__all__ = [
    "BELL_RIB",
    "CENTRE",
    "CLAW_IN",
    "CLAW_OUT",
    "CONE_DOWN",
    "CONE_UP",
    "NACELLE_AXIS",
    "RIGHT",
    "TURRET_MOUNT",
    "BodySpec",
    "BridgeSpec",
    "ClawSpec",
    "ConeSpec",
    "DorsalFinSpec",
    "Piece",
    "assemble",
    "nacelle_radius",
]
