"""The station's detail props (M7-T19, M7-T05), instanced under their sections with small atlases of their own
(``core/near_props.py``).

On the drum: the Cobra-bay launch doors' leaves (six doors an arm, M7-T05), two a door, each its own instance so a launch can swing
it open (M7-T08); they are the doors, with no painted stand-in on the hull, so they are drawn as far as the hull is. Their faces
carry what the hull atlas (about 1.4 m a texel) would blur at 50 m: the stencilled number, the slats with the bay's light between
them, rivets and a hazard band where the leaves meet, at 3 cm a texel. Near only: the clamp beside each door (its red cap painted on
the deck as the far stand-in), and over each door in the launch hall the gantry that holds its Starfury, seen through an open door
(T20 refits M7-T09's hangar to these doors).

On the frame: the command section's windows along the spine's flanks over the docking sphere, crisp panes over the hull's painted
ones (Q2: they hold from 50 m).
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from ..core.color import linear_to_srgb
from ..core.geometry import Material, Mesh, rotation_z
from ..core.near_props import PropGroup, PropKind
from ..core.textures import text_coverage
from ..styles import _hash01
from ..styles.earth_alliance_station import BAY_GLOW, BAY_STRENGTH, SCHEME, WINDOW_GLOW, WINDOW_STRENGTH, colour, lin
from . import station as st

NEAR_M = 1500.0  # where the hull atlas's texel (1.39 m) reaches a pixel at 1080 rows and a 62 degree view (docs/assets-station.md)
MARGIN_M = 400.0
ATLAS_W, ATLAS_H = 1024, 4096
CELL_H = 512  # one door per cell down the atlas (16 m by 32 m), then the swatches
PX_PER_M = 32.0  # 3.1 cm a texel on a door's face
LEAF = (0.4, 9.6, 6.6)  # a leaf's inner and outer edge across its door, its half length along
SLATS = 6
NUMBER = (7.0, 1.1, (0.42, 0.42, 0.40))  # height, stroke, colour (linear)
GLOW_GAP = 0.1  # the bay light between the slats, of the surface's strength (a glow, not a lamp)
GLOW_SEAM = 0.12  # and in the seam where the leaves meet
SWATCH_COLUMNS = 16  # the swatch cell: flat paints side by side, 64 texels each
STATION_SWATCHES = ("machinery", "trim", "recess", "door")  # then the lamps
LEAF_RANGE_M = 30_000.0  # the leaves are the doors: drawn as far as the hull (M6's far prop shrinks it beyond)


def _srgb8(rgb: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(np.clip(linear_to_srgb(np.clip(rgb, 0.0, 1.0)), 0.0, 1.0) * 255.0), 0, 255).astype(np.uint8)


def _smooth(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _door_cell(number: int, seed: int) -> dict[str, np.ndarray]:
    """One door's face (``CELL_H`` rows by ``ATLAS_W``): linear albedo, height, roughness, metallic, occlusion and glow."""
    cols, rows = np.meshgrid(np.arange(ATLAS_W), np.arange(CELL_H))
    x = (cols + 0.5) / PX_PER_M - st.LAUNCH_DOOR_HALF[0]
    z = (rows + 0.5) / PX_PER_M - st.LAUNCH_DOOR_HALF[1]
    inner, outer, half = LEAF
    ax = np.abs(x)
    leaf = (ax > inner) & (ax < outer) & (np.abs(z) < half)
    # The slats run across each leaf; the gaps between them are grated and lit from the bay below.
    pitch = 2.0 * half / SLATS
    t = np.mod(z + half, pitch)
    gap_w = 0.5
    in_gap = leaf & (t > pitch - gap_w)
    bar = in_gap & (np.mod(x, 0.5) < 0.12)  # the grating's bars across each gap
    edge = np.minimum.reduce([ax - inner, outer - ax, half - np.abs(z)])
    door, metal_d, rough_d = colour("door"), SCHEME["door"][2], SCHEME["door"][3]
    s = np.full(x.shape, seed + number, dtype=np.int64)
    slat_key = np.floor((z + half) / pitch).astype(np.int64) * 2 + (x > 0)
    tone = 1.0 - 0.08 * _hash01(slat_key, s) - 0.05 * _hash01(np.floor(x / 3.0).astype(np.int64), slat_key, s + 3)
    albedo = np.tile(np.asarray(door) * 0.35, (CELL_H, ATLAS_W, 1))  # the dark well round and between the leaves
    albedo = np.where(leaf[..., None], np.asarray(door)[None, None, :] * tone[..., None], albedo)
    rough = np.where(leaf, rough_d + 0.06 * (_hash01(slat_key, s + 9) - 0.5), 0.7)
    metal = np.where(leaf, metal_d, 0.5)
    ao = np.where(leaf, 1.0, 0.45)
    height = np.where(leaf, 0.0, -0.4) - 0.25 * _smooth(1.0 - (pitch - t) / 0.2) * leaf  # slats bevelled down to each gap
    # Rivets along each slat's two edges, a metre apart; the leaves' edges worn to bare metal.
    rivet = leaf & ~in_gap & (np.hypot(np.mod(x, 1.0) - 0.5, np.minimum(t - 0.25, pitch - gap_w - 0.25 - t)) < 0.09)
    height = height + 0.05 * rivet
    worn = leaf & (edge < 0.25)
    albedo = np.where(worn[..., None], np.asarray(colour("machinery"))[None, None, :], albedo)
    metal = np.where(worn, 0.85, metal)
    rough = np.where(worn, 0.3, rough)
    # A hazard band down the seam where the leaves meet.
    hazard = leaf & (ax < inner + 0.8)
    stripe = np.mod(x + z, 0.8) < 0.4
    albedo = np.where((hazard & stripe)[..., None], np.asarray(colour("hatch"))[None, None, :], albedo)
    albedo = np.where((hazard & ~stripe)[..., None], np.asarray([0.03, 0.03, 0.03])[None, None, :], albedo)
    # The grates: dark bars over the bay's light.
    albedo = np.where(in_gap[..., None], np.where(bar[..., None], 0.05, 0.02) * np.ones(3)[None, None, :], albedo)
    height = np.where(in_gap, np.where(bar, -0.3, -0.6), height)
    ao = np.where(in_gap, np.where(bar, 0.5, 0.3), ao)
    glow = np.where(in_gap & ~bar, GLOW_GAP, 0.0) + np.where(~leaf & (ax < inner) & (np.abs(z) < half), GLOW_SEAM, 0.0)
    # The number stencilled across both leaves, its top toward the bow (-z), over the grates and the seam too, so it reads from
    # a few hundred metres as the hull's painted one does.
    height_m, stroke, pale = NUMBER
    ink = text_coverage(np.column_stack([x.ravel(), -z.ravel()]), str(number), height_m, stroke).reshape(x.shape) * (np.abs(z) < half)
    albedo = albedo * (1.0 - ink[..., None]) + np.asarray(pale)[None, None, :] * ink[..., None]
    rough = rough * (1.0 - ink) + 0.62 * ink
    metal = metal * (1.0 - ink) + 0.3 * ink
    ao = ao * (1.0 - ink) + ink
    glow = glow * (1.0 - ink)
    return {"albedo": albedo, "height": height, "rough": rough, "metal": metal, "ao": ao, "glow": glow}


@dataclass(frozen=True)
class Swatch:
    """One flat paint on the swatch cell: linear albedo, roughness, metal, and its glow as a share of the atlas's strength."""

    albedo: tuple[float, float, float]
    rough: float
    metal: float
    glow: tuple[float, float, float] = (0.0, 0.0, 0.0)


def _station_swatch(role: str) -> Swatch:
    return Swatch(colour(role), SCHEME[role][3], SCHEME[role][2])


LAMP_SWATCH = Swatch(lin(0xD8D0C0), 0.4, 0.0, tuple(float(c) for c in lin(BAY_GLOW)))


def swatches() -> list[Swatch]:
    """The swatch cell's paints, left to right: the station's, then a lamp's glow."""
    return [_station_swatch(r) for r in STATION_SWATCHES] + [LAMP_SWATCH]


def _swatch_cell(paints: list[Swatch], rows: int = CELL_H) -> dict[str, np.ndarray]:
    """Flat paints side by side, each a column with a faint plate pattern."""
    cols, rws = np.meshgrid(np.arange(ATLAS_W), np.arange(rows))
    width = ATLAS_W // SWATCH_COLUMNS
    k = np.minimum(cols // width, len(paints) - 1)
    plate = _hash01(cols // 16, rws // 16, np.full(cols.shape, 31, dtype=np.int64))
    albedo = np.array([p.albedo for p in paints])[k] * (1.0 - 0.06 * plate)[..., None]
    rough = np.array([p.rough for p in paints])[k] + 0.05 * (plate - 0.5)
    metal = np.array([p.metal for p in paints])[k]
    glow = np.array([p.glow for p in paints])[k]
    seam = (np.mod(cols, 16) < 1) | (np.mod(rws, 16) < 1)
    return {"albedo": albedo, "height": np.where(seam, -0.05, 0.0), "rough": rough, "metal": metal, "ao": np.where(seam, 0.7, 1.0),
            "glow": glow}


def _maps(cells: list[dict[str, np.ndarray]], glow_colour: np.ndarray | None) -> dict[str, np.ndarray]:
    """The atlas's four maps as 8-bit arrays from its cells stacked down it (albedo and emissive sRGB, ORM and the normal map
    linear). A cell's glow is a share of the atlas's strength: a colour, or a scalar times ``glow_colour``."""
    stack = {key: np.concatenate([c[key] for c in cells], axis=0) for key in ("albedo", "height", "rough", "metal", "ao")}
    glow = np.concatenate([c["glow"] if c["glow"].ndim == 3 else np.asarray(glow_colour)[None, None, :] * c["glow"][..., None]
                           for c in cells], axis=0)
    texel = 1.0 / PX_PER_M
    h = stack["height"]
    dhdu = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) / (2.0 * texel)
    dhdv = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) / (2.0 * texel)
    n = np.stack([-dhdu, dhdv, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    to8 = lambda a: np.clip(np.rint(a * 255.0), 0, 255).astype(np.uint8)  # noqa: E731
    orm = np.stack([stack["ao"], np.clip(stack["rough"], 0.0, 1.0), np.clip(stack["metal"], 0.0, 1.0)], axis=-1)
    return {"albedo": _srgb8(stack["albedo"]), "normal": to8(n * 0.5 + 0.5), "orm": to8(orm), "emissive": _srgb8(glow)}


def prop_maps(seed: int) -> dict[str, np.ndarray]:
    """The drum's prop atlas: the six doors' faces, then the swatches."""
    cells = [_door_cell(k + 1, seed) for k in range(st.LAUNCH_DOORS)]
    paints = swatches()
    cells += [_swatch_cell(paints) for _ in range(ATLAS_H // CELL_H - len(cells))]
    return _maps(cells, np.asarray(lin(BAY_GLOW)))


EMISSIVE_STRENGTH = BAY_STRENGTH


# --- meshes ------------------------------------------------------------------------------------------------------------
def _prop_mesh(verts: list, faces: list, uvs: list) -> Mesh:
    return Mesh(np.array(verts, dtype=float), np.array(faces), np.zeros(len(faces), dtype=np.int64), (Material("prop", (0.5, 0.5, 0.5)),),
                np.zeros(len(faces), dtype=np.int64), np.array(uvs, dtype=float))


def swatch_uv(column: int, atlas_h: int = ATLAS_H, cell: int = st.LAUNCH_DOORS) -> tuple[float, float, float, float]:
    """The inside of a swatch column (u0, v0, u1, v1), clear of its neighbours for mipmaps."""
    w = 1.0 / SWATCH_COLUMNS
    return (column * w + 0.15 * w, (cell * CELL_H + 16.0) / atlas_h, (column + 1) * w - 0.15 * w, ((cell + 1) * CELL_H - 16.0) / atlas_h)


def _box(lo: np.ndarray, hi: np.ndarray, uv_of, verts: list, faces: list, uvs: list) -> None:
    """A box's six faces, outward, each corner's UV from ``uv_of(axis, side, corner)``."""
    for axis in range(3):
        a, b = [i for i in range(3) if i != axis]
        for side in (0, 1):
            w = hi[axis] if side else lo[axis]
            quad = []
            for ca, cb in ((0, 0), (1, 0), (1, 1), (0, 1)):
                p = np.zeros(3)
                p[axis], p[a], p[b] = w, (hi[a] if ca else lo[a]), (hi[b] if cb else lo[b])
                quad.append(p)
            normal = np.zeros(3)
            normal[axis] = 1.0 if side else -1.0
            uq = [uv_of(axis, side, q) for q in quad]
            if np.dot(np.cross(quad[1] - quad[0], quad[2] - quad[0]), normal) < 0.0:
                quad, uq = quad[::-1], uq[::-1]
            base = len(verts)
            verts += list(quad)
            faces += [[base, base + 1, base + 2], [base, base + 2, base + 3]]
            uvs += [[uq[0], uq[1], uq[2]], [uq[0], uq[2], uq[3]]]


def _flat_uv(column: int):
    """Every face on one swatch, its corners spread over the column (a uniform paint, so only its plate pattern moves)."""
    u0, v0, u1, v1 = swatch_uv(column)

    def uv(axis: int, side: int, p: np.ndarray) -> list[float]:
        a, b = [i for i in range(3) if i != axis]
        return [u0 + (u1 - u0) * (0.5 + 0.5 * math.tanh(0.05 * p[a])), v0 + (v1 - v0) * (0.5 + 0.5 * math.tanh(0.05 * p[b]))]

    return uv


LEAF_FACE = (-0.1, 0.4)  # a leaf's underside and face, about the doors' plane


def door_leaf(number: int, side: float) -> Mesh:
    """One leaf of door ``number`` (1 to 6 from the bow), ``side`` +1 (+x, starboard on the top arm) or -1, in the arm's frame as it
    stands on top (+y), its origin on the doors' plane at the door's middle. Its face is its half of the door's cell (number,
    slats, hazard band); its edges and back a dark steel."""
    inner, outer, half = LEAF
    lo = np.array([min(side * inner, side * outer), LEAF_FACE[0], -half])
    hi = np.array([max(side * inner, side * outer), LEAF_FACE[1], half])
    edge = _flat_uv(STATION_SWATCHES.index("machinery"))
    cell = number - 1

    def uv(axis: int, side_: int, p: np.ndarray) -> list[float]:
        if axis == 1 and side_ == 1:  # the face
            dx, dz = st.LAUNCH_DOOR_HALF
            return [(p[0] + dx) * PX_PER_M / ATLAS_W, (cell * CELL_H + (p[2] + dz) * PX_PER_M) / ATLAS_H]
        return edge(axis, side_, p)

    verts, faces, uvs = [], [], []
    _box(lo, hi, uv, verts, faces, uvs)
    return _prop_mesh(verts, faces, uvs)


def clamp() -> Mesh:
    """A door's hinged clamp: the post on the rail, the arm reaching over the door's edge and the red cap block."""
    verts, faces, uvs = [], [], []
    for lo, hi, swatch in CLAMP_BLOCKS:
        _box(np.asarray(lo, dtype=float), np.asarray(hi, dtype=float), _flat_uv(swatch), verts, faces, uvs)
    return _prop_mesh(verts, faces, uvs)


CLAMP_BLOCKS = (  # in the clamp's frame (origin on the deck at the door's edge): lo, hi, swatch column
    ((2.0, 0.0, -1.0), (4.5, 4.0, 1.0), 0),
    ((-3.0, 3.0, -0.75), (4.5, 4.0, 0.75), 0),
    ((1.5, 4.0, -1.5), (5.0, 6.0, 1.5), 1),
)


HANG_DEPTH_M = 9.0  # a held Starfury's middle under the doors' plane, toward the axis (as M7-T09 hangs them)
RELEASE_M = 8.0  # where a launch lets it go: this far out past the doors' plane, clear of the deck (4 m) by 4 m
GANTRY_BLOCKS = (  # over one door, in the arm's frame at the door's middle on its plane (-y into the hall): lo, hi, swatch column
    # The rack: an arm from each wall of the upper hall reaching in over the fighter's claw tips, a red clamp head at its end; the
    # middle stays open so the second row rises onto the rack between them.
    ((8.2, -15.0, -1.0), (20.0, -13.5, 1.0), 0), ((-20.0, -15.0, -1.0), (-8.2, -13.5, 1.0), 0),
    ((8.2, -15.5, -2.0), (10.0, -11.0, 2.0), 1), ((-10.0, -15.5, -2.0), (-8.2, -11.0, 2.0), 1),
    # The staging clamp in the lower hall, from its port wall over the second row's fighter (its back toward the axis).
    ((-40.0, -29.6, -1.0), (-36.2, -28.2, 1.0), 0), ((-37.4, -29.6, -2.0), (-35.8, -26.0, 2.0), 1),
    ((19.0, -12.0, -0.8), (19.8, -10.0, 0.8), 4), ((-19.8, -12.0, -0.8), (-19.0, -10.0, 0.8), 4),  # work lamps on the walls
    ((-39.8, -27.0, -0.8), (-39.0, -26.0, 0.8), 4),
    ((-19.8, -18.5, -3.0), (-19.0, -2.0, 3.0), 2), ((19.0, -18.5, -3.0), (19.8, -2.0, 3.0), 2),  # wall panels either side
)


def gantry() -> Mesh:
    """The launch hall's rack over one door: clamp arms from the walls holding the racked Starfury by its claw tips, the staging clamp
    over the second row in the lower hall, work lamps, dark panels on the walls (seen through an open door)."""
    verts, faces, uvs = [], [], []
    for lo, hi, swatch in GANTRY_BLOCKS:
        _box(np.asarray(lo, dtype=float), np.asarray(hi, dtype=float), _flat_uv(swatch), verts, faces, uvs)
    return _prop_mesh(verts, faces, uvs)


def kinds() -> list[PropKind]:
    out = [PropKind(leaf_kind(n, side), door_leaf(n, side), LEAF_RANGE_M) for n in range(1, st.LAUNCH_DOORS + 1) for side in (1.0, -1.0)]
    return out + [PropKind("clamp", clamp()), PropKind("gantry", gantry())]


def leaf_kind(number: int, side: float) -> str:
    return f"door_leaf_{number}_{'r' if side > 0 else 'l'}"


def _transform(turn: np.ndarray, at: np.ndarray, shift: np.ndarray, basis: np.ndarray | None = None) -> np.ndarray:
    b = turn if basis is None else turn @ basis
    return np.column_stack([b, turn @ at - shift])


def groups(section: str, shift: np.ndarray) -> list[PropGroup]:
    """The doors' leaves (one group a leaf of each number: an instance an arm), the clamps (one a door) and the gantry over each door
    in its hall, in the frame of ``section``: the station frame moved by ``shift`` (the drum's centre, then the section's origin)."""
    floor, top = st.ARM_HATCH[4] - st.DOOR_DEPTH, st.ARM_HATCH[4]
    turns = [rotation_z(math.radians(a - 90.0)) for a in st.ARM_ANGLES_DEG]
    centres, cx, dx = st.launch_door_centres(), st.LAUNCH_STRIP_X, st.LAUNCH_DOOR_HALF[0]
    out = [PropGroup(leaf_kind(n, side), section, tuple(_transform(t, np.array([cx, floor, centres[n - 1]]), shift) for t in turns))
           for n in range(1, st.LAUNCH_DOORS + 1) for side in (1.0, -1.0)]
    out.append(PropGroup("clamp", section, tuple(_transform(t, np.array([cx + dx, top, c]), shift) for t in turns for c in centres)))
    out.append(PropGroup("gantry", section, tuple(_transform(t, np.array([cx, floor, c]), shift) for t in turns for c in centres)))
    return out


# --- the frame's props: the command section's windows ------------------------------------------------------------------
FRAME_ATLAS_H = 2 * CELL_H
WINDOW_PANEL = (64.0, 32.0)  # along the flank, up it: one window cell at the doors' texel
WINDOW_GRID = (6, 4)  # windows along and up a panel
WINDOW_PANE = (5.6, 3.0)
WINDOW_LIFT_M = 0.3
# The panels lie on the command section's beam, on its sloped flanks (M7-T22: the STL's pointed beam): two rows up each flank (their
# middles this far down the slope from the top's edge) of whole panels along it (z from, z to, how many).
WINDOW_SLOPE_M = (28.5, 66.5)
WINDOW_RUNS = ((1012.0, 1268.0, 4),)
FRAME_SECTION = "spine_sphere"


def _window_cell(seed: int) -> dict[str, np.ndarray]:
    """A panel of windows: dark plating, each pane in a frame with a mullion, most lit warm, some dark (Q10)."""
    cols, rows = np.meshgrid(np.arange(ATLAS_W), np.arange(CELL_H))
    u = (cols + 0.5) / PX_PER_M  # along the panel
    v = (rows + 0.5) / PX_PER_M  # up it
    pu, pv = WINDOW_PANEL[0] / WINDOW_GRID[0], WINDOW_PANEL[1] / WINDOW_GRID[1]
    i, j = np.floor(u / pu).astype(np.int64), np.floor(v / pv).astype(np.int64)
    fu, fv = np.mod(u, pu) - 0.5 * pu, np.mod(v, pv) - 0.5 * pv
    w, h = WINDOW_PANE
    pane = (np.abs(fu) < 0.5 * w) & (np.abs(fv) < 0.5 * h)
    frame = (np.abs(fu) < 0.5 * w + 0.35) & (np.abs(fv) < 0.5 * h + 0.35) & ~pane
    mullion = pane & (np.abs(fu) < 0.08)
    s = np.full(u.shape, seed + 77, dtype=np.int64)
    lit = (_hash01(i, j, s) < 0.62) & pane & ~mullion
    plate = _hash01(np.floor(u / 8.0).astype(np.int64), np.floor(v / 4.0).astype(np.int64), s + 3)
    hull = np.asarray(colour("spine")) * (0.92 + 0.08 * plate)[..., None]
    albedo = np.where(pane[..., None], np.where(lit[..., None], 0.55, 0.02) * np.ones(3), hull)
    albedo = np.where(frame[..., None], np.asarray(colour("machinery")) * 0.6, albedo)
    albedo = np.where(mullion[..., None], np.asarray(colour("machinery")) * 0.5, albedo)
    seam = (np.mod(u, 8.0) < 0.1) | (np.mod(v, 4.0) < 0.1)
    height = np.where(pane, -0.25, 0.0) + np.where(frame, 0.08, 0.0) - 0.05 * seam
    rough = np.where(pane, 0.12, SCHEME["spine"][3] + 0.08 * (plate - 0.5))
    metal = np.where(pane, 0.0, SCHEME["spine"][2])
    ao = np.where(seam, 0.75, 1.0)
    glow = np.where(lit, 1.0, 0.0) * (0.85 + 0.15 * _hash01(i, j, s + 9))
    return {"albedo": albedo, "height": height, "rough": rough, "metal": metal, "ao": ao, "glow": glow}


def frame_maps(seed: int) -> dict[str, np.ndarray]:
    """The frame's prop atlas: the window panel's cell, then the swatches."""
    return _maps([_window_cell(seed), _swatch_cell([_station_swatch(r) for r in STATION_SWATCHES])], np.asarray(lin(WINDOW_GLOW)))


FRAME_EMISSIVE_STRENGTH = WINDOW_STRENGTH


def window_panel() -> Mesh:
    """One panel of windows, facing +x, its middle at the origin, along z and up y."""
    hu, hv = 0.5 * WINDOW_PANEL[0], 0.5 * WINDOW_PANEL[1]
    verts = [[0.0, -hv, -hu], [0.0, -hv, hu], [0.0, hv, hu], [0.0, hv, -hu]]
    v1 = CELL_H / FRAME_ATLAS_H
    uvs = [[[0.0, 0.0], [1.0, 0.0], [1.0, v1]], [[0.0, 0.0], [1.0, v1], [0.0, v1]]]
    return _prop_mesh(verts, [[0, 1, 2], [0, 2, 3]], uvs)


def frame_kinds() -> list[PropKind]:
    return [PropKind("window_panel", window_panel())]


def window_placements() -> list[tuple[np.ndarray, np.ndarray]]:
    """Each panel's basis (columns: out of the flank, up, along) and middle, station frame, on both flanks of the beam."""
    from . import station_spine as ssp  # noqa: PLC0415

    (xt, yt), (xe, ye) = (ssp.BEAM_TOP_X, ssp.BEAM_TOP), ssp.BEAM_EDGE
    down = np.array([xe - xt, ye - yt])
    down /= np.linalg.norm(down)
    out = []
    for z0, z1, count in WINDOW_RUNS:
        length = (z1 - z0) / count
        for k in range(count):
            zm = z0 + length * (k + 0.5)
            for s in WINDOW_SLOPE_M:
                for sx in (-1.0, 1.0):
                    up = np.array([-sx * down[0], -down[1], 0.0])
                    along = np.array([0.0, 0.0, sx])
                    out_n = np.cross(up, along)
                    basis = np.column_stack([out_n, up, along])
                    at = np.array([sx * (xt + s * down[0]), yt + s * down[1], zm]) + WINDOW_LIFT_M * out_n
                    out.append((basis, at))
    return out


def frame_groups(section: str, shift: np.ndarray) -> list[PropGroup]:
    """The window panels in the frame of ``section`` (the station frame moved by ``shift``)."""
    return [PropGroup("window_panel", section, tuple(np.column_stack([b, at - shift]) for b, at in window_placements()))]


__all__ = ["EMISSIVE_STRENGTH", "FRAME_EMISSIVE_STRENGTH", "HANG_DEPTH_M", "MARGIN_M", "NEAR_M", "RELEASE_M", "clamp", "door_leaf",
           "frame_groups", "frame_kinds", "frame_maps", "gantry", "groups", "kinds", "prop_maps", "window_placements"]
