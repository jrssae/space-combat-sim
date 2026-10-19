"""3D Gaussian splat PLY writer and reader (docs/architecture.md section 9.1 item 3).

Layout: standard 3DGS, ``format binary_little_endian 1.0``, one ``vertex`` element of float32
properties in this order::

    x y z nx ny nz f_dc_0 f_dc_1 f_dc_2 opacity scale_0 scale_1 scale_2 rot_0 rot_1 rot_2 rot_3

with ``rot_* = (w, x, y, z)``, ``scale_* = ln(scale)``, ``opacity = logit(alpha)`` and
``f_dc = (rgb - 0.5) / C0``. SH degree 0 only (no ``f_rest_*``); GDGS defaults those to zero.

``write_ply`` takes data exactly as it should be stored: callers apply the Godot -> 3DGS frame
change (``core.frames``) before writing. The reader decodes back to :class:`SplatData` for tests.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np

SH_C0 = 0.28209479177387814

PROPERTY_NAMES: tuple[str, ...] = (
    "x", "y", "z",
    "nx", "ny", "nz",
    "f_dc_0", "f_dc_1", "f_dc_2",
    "opacity",
    "scale_0", "scale_1", "scale_2",
    "rot_0", "rot_1", "rot_2", "rot_3",
)  # fmt: skip

# Alpha is stored as a logit, which is infinite at 0 and 1; clamp to a finite, still opaque range.
ALPHA_MIN = 1e-4
ALPHA_MAX = 0.9999
# GDGS clamps scales to 1e-6 as well, so a smaller value would only waste the log.
SCALE_MIN = 1e-6

_VERTEX_DTYPE = np.dtype([(name, "<f4") for name in PROPERTY_NAMES])

_PLY_TYPES = {
    "char": "i1", "int8": "i1",
    "uchar": "u1", "uint8": "u1",
    "short": "<i2", "int16": "<i2",
    "ushort": "<u2", "uint16": "<u2",
    "int": "<i4", "int32": "<i4",
    "uint": "<u4", "uint32": "<u4",
    "float": "<f4", "float32": "<f4",
    "double": "<f8", "float64": "<f8",
}  # fmt: skip


@dataclass
class SplatData:
    """Decoded splats: linear units, one row per splat.

    ``rgb`` is linear display radiance (>= 0, may exceed 1), ``alpha`` is in (0, 1),
    ``scale`` is the per-axis standard deviation in metres and ``rot`` is ``(w, x, y, z)``.
    ``normals`` may be ``None`` (written as zeros; GDGS ignores them).
    """

    xyz: np.ndarray
    rgb: np.ndarray
    alpha: np.ndarray
    scale: np.ndarray
    rot: np.ndarray
    normals: np.ndarray | None = None

    def __len__(self) -> int:
        return int(self.xyz.shape[0])

    def validate(self) -> None:
        n = len(self)
        shapes = {
            "xyz": (n, 3),
            "rgb": (n, 3),
            "alpha": (n,),
            "scale": (n, 3),
            "rot": (n, 4),
        }
        if self.normals is not None:
            shapes["normals"] = (n, 3)
        for name, shape in shapes.items():
            got = np.asarray(getattr(self, name)).shape
            if got != shape:
                raise ValueError(f"SplatData.{name} has shape {got}, expected {shape}")

    @staticmethod
    def concatenate(parts: list[SplatData]) -> SplatData:
        normals = [
            p.normals if p.normals is not None else np.zeros_like(p.xyz) for p in parts
        ]
        return SplatData(
            xyz=np.concatenate([p.xyz for p in parts]),
            rgb=np.concatenate([p.rgb for p in parts]),
            alpha=np.concatenate([p.alpha for p in parts]),
            scale=np.concatenate([p.scale for p in parts]),
            rot=np.concatenate([p.rot for p in parts]),
            normals=np.concatenate(normals),
        )


def alpha_to_logit(alpha: np.ndarray) -> np.ndarray:
    a = np.clip(np.asarray(alpha, dtype=np.float64), ALPHA_MIN, ALPHA_MAX)
    return np.log(a / (1.0 - a))


def logit_to_alpha(logit: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-np.asarray(logit, dtype=np.float64)))


def rgb_to_f_dc(rgb: np.ndarray) -> np.ndarray:
    return (np.maximum(np.asarray(rgb, dtype=np.float64), 0.0) - 0.5) / SH_C0


def f_dc_to_rgb(f_dc: np.ndarray) -> np.ndarray:
    return np.asarray(f_dc, dtype=np.float64) * SH_C0 + 0.5


def encode_vertices(splats: SplatData) -> np.ndarray:
    """Pack splats into the structured little-endian float32 vertex array."""
    splats.validate()
    n = len(splats)
    rot = np.asarray(splats.rot, dtype=np.float64)
    rot = rot / np.linalg.norm(rot, axis=1, keepdims=True)
    scale = np.log(np.maximum(np.asarray(splats.scale, dtype=np.float64), SCALE_MIN))
    f_dc = rgb_to_f_dc(splats.rgb)
    normals = splats.normals if splats.normals is not None else np.zeros((n, 3))

    out = np.empty(n, dtype=_VERTEX_DTYPE)
    for axis, name in enumerate(("x", "y", "z")):
        out[name] = splats.xyz[:, axis]
    for axis, name in enumerate(("nx", "ny", "nz")):
        out[name] = normals[:, axis]
    for axis in range(3):
        out[f"f_dc_{axis}"] = f_dc[:, axis]
        out[f"scale_{axis}"] = scale[:, axis]
    out["opacity"] = alpha_to_logit(splats.alpha)
    for axis in range(4):
        out[f"rot_{axis}"] = rot[:, axis]
    return out


def ply_header(count: int, comments: tuple[str, ...] = ()) -> bytes:
    lines = ["ply", "format binary_little_endian 1.0"]
    lines += [f"comment {c}" for c in comments]
    lines.append(f"element vertex {count}")
    lines += [f"property float {name}" for name in PROPERTY_NAMES]
    lines.append("end_header")
    return ("\n".join(lines) + "\n").encode("ascii")


def write_ply(path: Path, splats: SplatData, comments: tuple[str, ...] = ()) -> Path:
    """Write ``splats`` as a binary 3DGS PLY. Output depends only on the arguments."""
    vertices = encode_vertices(splats)
    path = Path(path)
    path.write_bytes(ply_header(len(vertices), comments) + vertices.tobytes())
    return path


@dataclass
class PlyFile:
    """A parsed binary PLY with a single ``vertex`` element."""

    format: str
    comments: list[str]
    count: int
    properties: list[tuple[str, str]]  # (ply type, name) in file order
    vertices: np.ndarray  # structured array, native values

    @property
    def names(self) -> list[str]:
        return [name for _, name in self.properties]

    def column(self, name: str) -> np.ndarray:
        return self.vertices[name]

    def to_splats(self) -> SplatData:
        """Decode the 3DGS encoding (exp/sigmoid/SH0) back to linear :class:`SplatData`."""
        missing = [n for n in PROPERTY_NAMES if n not in self.names]
        if missing:
            raise ValueError(f"PLY is missing 3DGS properties: {missing}")
        v = self.vertices

        def stack(*names: str) -> np.ndarray:
            return np.stack([v[n].astype(np.float64) for n in names], axis=1)

        rot = stack("rot_0", "rot_1", "rot_2", "rot_3")
        return SplatData(
            xyz=stack("x", "y", "z"),
            normals=stack("nx", "ny", "nz"),
            rgb=f_dc_to_rgb(stack("f_dc_0", "f_dc_1", "f_dc_2")),
            alpha=logit_to_alpha(v["opacity"]),
            scale=np.exp(stack("scale_0", "scale_1", "scale_2")),
            rot=rot / np.linalg.norm(rot, axis=1, keepdims=True),
        )


def read_ply(path: Path) -> PlyFile:
    """Parse a binary little-endian PLY (scalar properties only), raising ``ValueError`` if malformed."""
    raw = Path(path).read_bytes()
    marker = b"end_header\n"
    end = raw.find(marker)
    if end < 0:
        raise ValueError("PLY header has no end_header line")
    header = raw[:end].decode("ascii").split("\n")
    body = memoryview(raw)[end + len(marker) :]

    if header[0] != "ply":
        raise ValueError("missing 'ply' magic line")
    fmt = ""
    comments: list[str] = []
    count = -1
    properties: list[tuple[str, str]] = []
    for line in header[1:]:
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "format":
            fmt = " ".join(parts[1:])
        elif parts[0] == "comment":
            comments.append(line[len("comment ") :])
        elif parts[0] == "element":
            if parts[1] != "vertex" or count >= 0:
                raise ValueError("only a single 'vertex' element is supported")
            count = int(parts[2])
        elif parts[0] == "property":
            if parts[1] == "list":
                raise ValueError("list properties are not supported")
            if parts[1] not in _PLY_TYPES:
                raise ValueError(f"unknown property type {parts[1]!r}")
            properties.append((parts[1], parts[2]))
        else:
            raise ValueError(f"unexpected header line {line!r}")
    if fmt != "binary_little_endian 1.0":
        raise ValueError(f"unsupported PLY format {fmt!r}")
    if count < 0:
        raise ValueError("PLY has no vertex element")

    dtype = np.dtype([(name, _PLY_TYPES[ply_type]) for ply_type, name in properties])
    if len(body) != count * dtype.itemsize:
        raise ValueError(
            f"PLY body is {len(body)} bytes, expected {count * dtype.itemsize} "
            f"({count} vertices x {dtype.itemsize})"
        )
    vertices = np.frombuffer(body, dtype=dtype, count=count)
    return PlyFile(fmt, comments, count, properties, vertices)
