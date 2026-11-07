"""Binary glTF 2.0 (``.glb``) writer for the textured meshes, and a small reader for tests (M4-T27).

Godot imports a ``.glb`` as a scene and builds the mesh's levels of detail at import, so a mesh written here gets the engine's
own LOD chain. Only what the textured meshes need: one mesh of indexed triangle primitives, each with positions, normals and
one UV set, and a named material per primitive. Output is deterministic: no timestamps, fixed key order, 4-byte alignment.
"""

from __future__ import annotations

import json
import struct
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

MAGIC = 0x46546C67  # "glTF"
VERSION = 2
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942
FLOAT = 5126
UINT32 = 5125
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963
TRIANGLES = 4
GENERATOR = "space-combat-sim procgen"


@dataclass
class GlbPrimitive:
    """One primitive: its own compact vertex arrays, triangle indices and material."""

    positions: np.ndarray
    normals: np.ndarray
    uv: np.ndarray
    indices: np.ndarray
    material: str
    base_color: tuple[float, float, float, float] = (1.0, 1.0, 1.0, 1.0)
    blend: bool = False
    extras: dict = field(default_factory=dict)
    colors: np.ndarray | None = None  # optional COLOR_0, one RGBA per vertex (M4-T30b: the livery zone in red)

    def __post_init__(self) -> None:
        self.positions = np.asarray(self.positions, dtype=np.float32).reshape(-1, 3)
        self.normals = np.asarray(self.normals, dtype=np.float32).reshape(-1, 3)
        self.uv = np.asarray(self.uv, dtype=np.float32).reshape(-1, 2)
        self.indices = np.asarray(self.indices, dtype=np.uint32).reshape(-1)
        n = len(self.positions)
        if self.colors is not None:
            self.colors = np.asarray(self.colors, dtype=np.float32).reshape(-1, 4)
        if len(self.normals) != n or len(self.uv) != n or (self.colors is not None and len(self.colors) != n):
            raise ValueError("primitive arrays disagree in length")
        if len(self.indices) % 3 != 0:
            raise ValueError("indices must be whole triangles")
        if len(self.indices) and int(self.indices.max()) >= n:
            raise ValueError("index out of range")


def _pad(data: bytes, fill: bytes) -> bytes:
    return data + fill * ((4 - len(data) % 4) % 4)


def glb_bytes(primitives: Sequence[GlbPrimitive], mesh_name: str) -> bytes:
    """The whole ``.glb`` file for one mesh of ``primitives`` (empty primitives are left out)."""
    used = [p for p in primitives if len(p.indices) > 0]
    if not used:
        raise ValueError("a glb mesh needs at least one non-empty primitive")
    blob = bytearray()
    views: list[dict] = []
    accessors: list[dict] = []

    def add(array: np.ndarray, component: int, kind: str, target: int, bounds: bool = False) -> int:
        offset = len(blob)
        raw = np.ascontiguousarray(array).tobytes()
        blob.extend(_pad(raw, b"\x00"))
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(raw), "target": target})
        accessor: dict = {"bufferView": len(views) - 1, "componentType": component, "count": int(len(array)), "type": kind}
        if bounds:
            accessor["min"] = [float(v) for v in array.min(axis=0)]
            accessor["max"] = [float(v) for v in array.max(axis=0)]
        accessors.append(accessor)
        return len(accessors) - 1

    gltf_primitives = []
    materials = []
    for p in used:
        attributes = {
            "POSITION": add(p.positions, FLOAT, "VEC3", ARRAY_BUFFER, bounds=True),
            "NORMAL": add(p.normals, FLOAT, "VEC3", ARRAY_BUFFER),
            "TEXCOORD_0": add(p.uv, FLOAT, "VEC2", ARRAY_BUFFER),
        }
        if p.colors is not None:
            attributes["COLOR_0"] = add(p.colors, FLOAT, "VEC4", ARRAY_BUFFER)
        indices = add(p.indices, UINT32, "SCALAR", ELEMENT_ARRAY_BUFFER)
        material: dict = {
            "name": p.material,
            "pbrMetallicRoughness": {"baseColorFactor": [float(c) for c in p.base_color], "metallicFactor": 0.0, "roughnessFactor": 1.0},
        }
        if p.blend:
            material["alphaMode"] = "BLEND"
        if p.extras:
            material["extras"] = p.extras
        materials.append(material)
        gltf_primitives.append({"attributes": attributes, "indices": indices, "material": len(materials) - 1, "mode": TRIANGLES})

    doc = {
        "asset": {"version": "2.0", "generator": GENERATOR},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": mesh_name, "mesh": 0}],
        "meshes": [{"name": mesh_name, "primitives": gltf_primitives}],
        "materials": materials,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    json_chunk = _pad(json.dumps(doc, separators=(",", ":"), sort_keys=False).encode("ascii"), b" ")
    bin_chunk = bytes(blob)
    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    out = bytearray(struct.pack("<III", MAGIC, VERSION, total))
    out += struct.pack("<II", len(json_chunk), CHUNK_JSON) + json_chunk
    out += struct.pack("<II", len(bin_chunk), CHUNK_BIN) + bin_chunk
    return bytes(out)


def write_glb(path: Path, primitives: Sequence[GlbPrimitive], mesh_name: str) -> Path:
    path = Path(path)
    path.write_bytes(glb_bytes(primitives, mesh_name))
    return path


@dataclass
class GlbMesh:
    """What ``read_glb`` gives back: the JSON document and each primitive's arrays."""

    doc: dict
    primitives: list[GlbPrimitive]


def read_glb(path: Path) -> GlbMesh:
    """Parse a ``.glb`` this module wrote (for tests): every primitive of the first mesh."""
    data = Path(path).read_bytes()
    magic, version, total = struct.unpack_from("<III", data, 0)
    if magic != MAGIC or version != VERSION or total != len(data):
        raise ValueError("not a glb file this reader understands")
    json_len, json_type = struct.unpack_from("<II", data, 12)
    if json_type != CHUNK_JSON:
        raise ValueError("glb: first chunk is not JSON")
    doc = json.loads(data[20 : 20 + json_len].decode("ascii"))
    bin_start = 20 + json_len
    bin_len, bin_type = struct.unpack_from("<II", data, bin_start)
    if bin_type != CHUNK_BIN:
        raise ValueError("glb: second chunk is not BIN")
    blob = data[bin_start + 8 : bin_start + 8 + bin_len]

    def read(index: int) -> np.ndarray:
        accessor = doc["accessors"][index]
        view = doc["bufferViews"][accessor["bufferView"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
        dtype = np.float32 if accessor["componentType"] == FLOAT else np.uint32
        raw = np.frombuffer(blob, dtype=dtype, count=accessor["count"] * width, offset=view["byteOffset"])
        return raw.reshape(-1, width) if width > 1 else raw

    primitives = []
    for p in doc["meshes"][0]["primitives"]:
        material = doc["materials"][p["material"]]
        primitives.append(
            GlbPrimitive(
                read(p["attributes"]["POSITION"]),
                read(p["attributes"]["NORMAL"]),
                read(p["attributes"]["TEXCOORD_0"]),
                read(p["indices"]),
                material["name"],
                tuple(material["pbrMetallicRoughness"]["baseColorFactor"]),
                material.get("alphaMode") == "BLEND",
                material.get("extras", {}),
                read(p["attributes"]["COLOR_0"]) if "COLOR_0" in p["attributes"] else None,
            )
        )
    return GlbMesh(doc, primitives)
