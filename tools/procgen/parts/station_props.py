"""The station's near-only detail props (M7-T19): the Cobra-bay launch doors' close-up faces and the clamps beside them, instanced
on the drum and drawn only near (``core/near_props.py``). The proof of the seam T05 builds its bay and aperture detail on.

The doors' faces carry what the hull atlas (about 1.4 m a texel) blurs at 50 m: the stencilled number, the slats of the two grated
leaves with the bay's light between them, rivets and a hazard band where the leaves meet, at 6 cm a texel. The hull keeps its
painted door underneath, so past the near range the door still reads, only softer. The clamps left the hull for good; their red
caps stay painted on the rail as the far stand-in.
"""

from __future__ import annotations

import math

import numpy as np

from ..core.color import linear_to_srgb
from ..core.geometry import Material, Mesh, rotation_z
from ..core.near_props import PropGroup, PropKind
from ..core.textures import text_coverage
from ..styles import _hash01
from ..styles.earth_alliance_station import BAY_GLOW, BAY_STRENGTH, SCHEME, colour, lin
from . import station as st

NEAR_M = 1500.0  # where the hull atlas's texel (1.39 m) reaches a pixel at 1080 rows and a 62 degree view (docs/assets-station.md)
MARGIN_M = 400.0
ATLAS_W, ATLAS_H = 1024, 4096
CELL_H = 512  # one door per cell, eight cells down the atlas; the last holds the clamps' swatches
PX_PER_M = ATLAS_W / (2.0 * st.DOOR_HALF[0])  # 16: 6.25 cm a texel across a door
DOOR_FACE = (30.4, 12.4)  # half across and half along of the face laid over each door, inside the bay light's strips
DOOR_LIFT_M = 0.2  # above the well's floor, clear of it
LEAF = (0.75, 31.25, 13.0)  # a leaf's inner and outer edge across, its half length along
SLATS = 6
NUMBER = (14.0, 2.2, (0.42, 0.42, 0.40))  # height, stroke, colour (linear)
GLOW_GAP = 0.1  # the bay light between the slats, of the surface's strength (a glow, not a lamp)
GLOW_SEAM = 0.12  # and in the seam where the leaves meet
SWATCHES = ("machinery", "trim")


def _srgb8(rgb: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(np.clip(linear_to_srgb(np.clip(rgb, 0.0, 1.0)), 0.0, 1.0) * 255.0), 0, 255).astype(np.uint8)


def _smooth(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _door_cell(number: int, seed: int) -> dict[str, np.ndarray]:
    """One door's face (``CELL_H`` rows by ``ATLAS_W``): linear albedo, height, roughness, metallic, occlusion and glow."""
    cols, rows = np.meshgrid(np.arange(ATLAS_W), np.arange(CELL_H))
    x = (cols + 0.5) / PX_PER_M - st.DOOR_HALF[0]
    z = (rows + 0.5) / PX_PER_M - st.DOOR_HALF[1]
    inner, outer, half = LEAF
    ax = np.abs(x)
    leaf = (ax > inner) & (ax < outer) & (np.abs(z) < half)
    # The slats run across each leaf; the gaps between them are grated and lit from the bay below.
    pitch = 2.0 * half / SLATS
    t = np.mod(z + half, pitch)
    gap_w = 0.85
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
    hazard = leaf & (ax < inner + 1.6)
    stripe = np.mod(x + z, 1.6) < 0.8
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


def _swatch_cell() -> dict[str, np.ndarray]:
    """The clamps' paints side by side, with a faint plate pattern: bare machinery metal, then the red trim."""
    cols, rows = np.meshgrid(np.arange(ATLAS_W), np.arange(CELL_H))
    right = cols >= ATLAS_W // 2
    plate = _hash01(cols // 64, rows // 64, np.full(cols.shape, 31, dtype=np.int64))
    albedo = np.where(right[..., None], np.asarray(colour("trim"))[None, None, :], np.asarray(colour("machinery"))[None, None, :])
    albedo = albedo * (1.0 - 0.06 * plate)[..., None]
    rough = np.where(right, SCHEME["trim"][3], SCHEME["machinery"][3]) + 0.05 * (plate - 0.5)
    metal = np.where(right, SCHEME["trim"][2], SCHEME["machinery"][2])
    seam = (np.mod(cols, 64) < 2) | (np.mod(rows, 64) < 2)
    return {"albedo": albedo, "height": np.where(seam, -0.05, 0.0), "rough": rough, "metal": metal, "ao": np.where(seam, 0.7, 1.0),
            "glow": np.zeros(cols.shape)}


def prop_maps(seed: int) -> dict[str, np.ndarray]:
    """The prop atlas's four maps as 8-bit arrays (albedo and emissive sRGB, ORM and the normal map linear)."""
    cells = [_door_cell(k + 1, seed) for k in range(st.COBRA_DOORS)] + [_swatch_cell()]
    cells += [_swatch_cell() for _ in range(ATLAS_H // CELL_H - len(cells))]
    stack = {key: np.concatenate([c[key] for c in cells], axis=0) for key in cells[0]}
    texel = 1.0 / PX_PER_M
    h = stack["height"]
    dhdu = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) / (2.0 * texel)
    dhdv = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) / (2.0 * texel)
    n = np.stack([-dhdu, dhdv, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    to8 = lambda a: np.clip(np.rint(a * 255.0), 0, 255).astype(np.uint8)  # noqa: E731
    glow = np.asarray(lin(BAY_GLOW))[None, None, :] * stack["glow"][..., None]
    orm = np.stack([stack["ao"], np.clip(stack["rough"], 0.0, 1.0), np.clip(stack["metal"], 0.0, 1.0)], axis=-1)
    return {"albedo": _srgb8(stack["albedo"]), "normal": to8(n * 0.5 + 0.5), "orm": to8(orm), "emissive": _srgb8(glow)}


EMISSIVE_STRENGTH = BAY_STRENGTH


def door_row() -> Mesh:
    """The faces over one arm's seven doors, in the arm's frame as it stands on top (+y), its origin on the well floor at the
    middle of the row."""
    mid = 0.5 * sum(st.DOOR_ROW)
    fx, fz = DOOR_FACE
    verts, faces, uvs = [], [], []
    for k, c in enumerate(st.door_centres()):
        z0, z1 = c - fz - mid, c + fz - mid
        base = 4 * k
        verts += [[-fx, DOOR_LIFT_M, z0], [fx, DOOR_LIFT_M, z0], [fx, DOOR_LIFT_M, z1], [-fx, DOOR_LIFT_M, z1]]
        faces += [[base, base + 2, base + 1], [base, base + 3, base + 2]]  # facing +y
        u0, u1 = (st.DOOR_HALF[0] - fx) / (2 * st.DOOR_HALF[0]), (st.DOOR_HALF[0] + fx) / (2 * st.DOOR_HALF[0])
        v0 = (k * CELL_H + (st.DOOR_HALF[1] - fz) * PX_PER_M) / ATLAS_H
        v1 = (k * CELL_H + (st.DOOR_HALF[1] + fz) * PX_PER_M) / ATLAS_H
        uvs += [[[u0, v0], [u1, v1], [u1, v0]], [[u0, v0], [u0, v1], [u1, v1]]]
    return Mesh(np.array(verts), np.array(faces), np.zeros(len(faces), dtype=np.int64), (Material("prop", (0.5, 0.5, 0.5)),),
                np.zeros(len(faces), dtype=np.int64), np.array(uvs))


CLAMP_BLOCKS = (  # in the clamp's frame (origin on the rail's top at the door's edge): lo, hi, swatch
    ((4.0, 0.0, -2.0), (9.0, 8.0, 2.0), 0),
    ((-6.0, 6.0, -1.5), (9.0, 8.0, 1.5), 0),
    ((3.0, 8.0, -3.0), (10.0, 12.0, 3.0), 1),
)


def clamp() -> Mesh:
    """A door's hinged clamp: the post on the rail, the arm reaching over the door's edge and the red cap block."""
    verts, faces, uvs = [], [], []
    swatch_v = ((st.COBRA_DOORS * CELL_H) + 8.0) / ATLAS_H, ((st.COBRA_DOORS + 1) * CELL_H - 8.0) / ATLAS_H
    for lo, hi, swatch in CLAMP_BLOCKS:
        lo, hi = np.asarray(lo), np.asarray(hi)
        u_lo = 0.02 + 0.5 * swatch
        for axis in range(3):
            a, b = [i for i in range(3) if i != axis]
            for side in (0, 1):
                w = hi[axis] if side else lo[axis]
                quad = []
                for ca, cb in ((0, 0), (1, 0), (1, 1), (0, 1)):
                    p = np.zeros(3)
                    p[axis], p[a], p[b] = w, (hi[a] if ca else lo[a]), (hi[b] if cb else lo[b])
                    quad.append(p)
                quad = np.array(quad)
                normal = np.zeros(3)
                normal[axis] = 1.0 if side else -1.0
                if np.dot(np.cross(quad[1] - quad[0], quad[2] - quad[0]), normal) < 0.0:
                    quad = quad[::-1]
                base = len(verts)
                verts += list(quad)
                faces += [[base, base + 1, base + 2], [base, base + 2, base + 3]]
                # 64 texels a metre-ish across the swatch's plate pattern, a different spot per face.
                du = 0.02 * (axis * 2 + side)
                uq = [[u_lo + du + 0.012 * k, swatch_v[0] + 0.01 * j] for k, j in ((0, 0), (1, 0), (1, 1), (0, 1))]
                uvs += [[uq[0], uq[1], uq[2]], [uq[0], uq[2], uq[3]]]
    return Mesh(np.array(verts), np.array(faces), np.zeros(len(faces), dtype=np.int64), (Material("prop", (0.5, 0.5, 0.5)),),
                np.zeros(len(faces), dtype=np.int64), np.array(uvs))


def kinds() -> list[PropKind]:
    return [PropKind("door_row", door_row()), PropKind("clamp", clamp())]


def _transform(turn: np.ndarray, at: np.ndarray, shift: np.ndarray) -> np.ndarray:
    return np.column_stack([turn, turn @ at - shift])


def groups(section: str, shift: np.ndarray) -> list[PropGroup]:
    """The doors' faces (one row per arm) and the clamps (one per door per arm), in the frame of ``section``: the station frame
    moved by ``shift`` (the drum's centre, then the section's origin)."""
    floor, top = st.ARM_HATCH[4] - st.DOOR_DEPTH, st.ARM_HATCH[4]
    turns = [rotation_z(math.radians(a - 90.0)) for a in st.ARM_ANGLES_DEG]
    rows = tuple(_transform(t, np.array([0.0, floor, 0.5 * sum(st.DOOR_ROW)]), shift) for t in turns)
    clamps = tuple(_transform(t, np.array([st.DOOR_HALF[0], top, c]), shift) for t in turns for c in st.door_centres())
    return [PropGroup("door_row", section, rows), PropGroup("clamp", section, clamps)]


__all__ = ["EMISSIVE_STRENGTH", "MARGIN_M", "NEAR_M", "clamp", "door_row", "groups", "kinds", "prop_maps"]
