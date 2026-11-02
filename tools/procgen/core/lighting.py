"""Per-splat lighting records for GDGS relighting (docs/architecture.md section 7.3).

Ships and buoys are lit in the game by the scene's lights, so their PLY colours are plain paint and the surface they
need comes from here: GDGS's ``GaussianLightingResource`` format 1, 4 bytes per splat in PLY order::

    octahedral normal x, octahedral normal y, ambient occlusion, confidence

GDGS bakes these in its editor from a voxel proxy; a generator already knows every sample's surface normal, so it
writes them itself. A ``.light`` file is those bytes and nothing else. The normals are read from the splats as they
are written, so they are in the PLY's frame, which is the frame the GDGS shader rotates them out of.

The encoding must use the same codec as ``addons/gdgs_scs/runtime/resources/gaussian_lighting_resource.gd``. GDGS goes through
float32 and this module through float64, so a value exactly on a rounding boundary can differ by one unit.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from .ply import SplatData

BYTES_PER_SPLAT = 4
SUFFIX = ".light"


def lod_file_name(asset_id: str, level: int) -> str:
    return f"{asset_id}_lod{level}{SUFFIX}"


def hero_file_name(asset_id: str) -> str:
    return f"{asset_id}_hero{SUFFIX}"


def chunk_file_name(asset_id: str, name: str) -> str:
    return f"{asset_id}_chunk_{name}{SUFFIX}"


def _non_zero_sign(value: np.ndarray) -> np.ndarray:
    # A plain sign is 0 at 0, which would collapse a fold of the octahedron.
    return np.where(value < 0.0, -1.0, 1.0)


def oct_encode(normals: np.ndarray) -> np.ndarray:
    """Octahedral projection of ``(N, 3)`` directions onto ``[-1, 1]^2``; zero vectors give ``(0, 0)``."""
    n = np.asarray(normals, dtype=np.float64).reshape(-1, 3)
    l1 = np.abs(n).sum(axis=1, keepdims=True)
    p = np.divide(n[:, :2], l1, out=np.zeros((len(n), 2)), where=l1 > 0.0)
    folded = (1.0 - np.abs(p[:, ::-1])) * _non_zero_sign(p)
    return np.where(n[:, 2:3] < 0.0, folded, p)


def oct_decode(encoded: np.ndarray) -> np.ndarray:
    """The unit directions of octahedral coordinates ``(N, 2)``."""
    e = np.asarray(encoded, dtype=np.float64).reshape(-1, 2)
    z = 1.0 - np.abs(e).sum(axis=1)
    folded = (1.0 - np.abs(e[:, ::-1])) * _non_zero_sign(e)
    xy = np.where(z[:, None] < 0.0, folded, e)
    v = np.column_stack([xy, z])
    return v / np.linalg.norm(v, axis=1, keepdims=True)


def _round_half_up(value: np.ndarray) -> np.ndarray:
    # Godot's roundf; numpy's own round sends halves to the even neighbour and would differ by one.
    return np.floor(value + 0.5)


def encode_signed_byte(value: np.ndarray) -> np.ndarray:
    """``[-1, 1]`` to a byte."""
    unit_range = np.clip(np.asarray(value, dtype=np.float64), -1.0, 1.0) * 0.5 + 0.5
    return np.clip(_round_half_up(unit_range * 255.0), 0, 255).astype(np.uint8)


def encode_unit_byte(value: np.ndarray) -> np.ndarray:
    """``[0, 1]`` to a byte."""
    return np.clip(_round_half_up(np.clip(np.asarray(value, dtype=np.float64), 0.0, 1.0) * 255.0), 0, 255).astype(np.uint8)


def lighting_records(normals: np.ndarray) -> np.ndarray:
    """The ``(N, 4)`` byte records of a surface. AO is 1.0 everywhere: the ambient term is small and panel lines and dark
    recesses are already in the paint. A splat with no normal gets confidence 0, which GDGS lights with ambient only."""
    n = np.asarray(normals, dtype=np.float64).reshape(-1, 3)
    has_normal = np.linalg.norm(n, axis=1) > 0.0
    records = np.empty((len(n), BYTES_PER_SPLAT), dtype=np.uint8)
    records[:, :2] = encode_signed_byte(oct_encode(n))
    records[:, 2] = encode_unit_byte(np.ones(len(n)))
    records[:, 3] = encode_unit_byte(has_normal.astype(np.float64))
    return records


def decode_normals(records: np.ndarray) -> np.ndarray:
    """The unit normals of ``(N, 4)`` records, as the GDGS shader decodes them."""
    return oct_decode(np.asarray(records, dtype=np.float64)[:, :2] / 255.0 * 2.0 - 1.0)


def write_lighting(path: Path, splats: SplatData) -> Path:
    """Write the records of ``splats``, which must be the data of the PLY they go with (same order, same frame)."""
    normals = splats.normals if splats.normals is not None else np.zeros((len(splats), 3))
    path = Path(path)
    path.write_bytes(lighting_records(normals).tobytes())
    return path


def read_lighting(path: Path) -> np.ndarray:
    """The ``(N, 4)`` records of a ``.light`` file, raising ``ValueError`` if it is not a whole number of them."""
    raw = Path(path).read_bytes()
    if len(raw) % BYTES_PER_SPLAT != 0:
        raise ValueError(f"{path}: {len(raw)} bytes is not a whole number of {BYTES_PER_SPLAT}-byte records")
    return np.frombuffer(raw, dtype=np.uint8).reshape(-1, BYTES_PER_SPLAT)
