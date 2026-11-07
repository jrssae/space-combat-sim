"""Shared checks for the civilian ships' textured meshes (M5-T27, AC12): the mesh contract of ``core/textured_mesh.py`` as the
civilian generators write it.

A model's ``<stem>.glb`` must be its fallback ``<stem>.obj`` drawn the game's way (the same triangles and box), with its four maps
and their import sidecars; a hull's chunks are cuts of its mesh on its atlas that share out its triangles.
"""

from __future__ import annotations

import unittest
from pathlib import Path

import numpy as np

from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.glb import read_glb
from tools.procgen.core.image import read_png
from tools.procgen.core.obj import read_obj

MAP_KEYS = ("albedo", "normal", "orm", "emissive")
# Hull atlases are 2 048 px by default; the tests build at these sizes to stay quick (the paint is checked, not its detail).
TEST_OPTIONS = {"atlas_px": 512, "model_atlas_px": 256}


def glb_triangles(path: Path) -> np.ndarray:
    """Every triangle of a glb, ``(n, 3, 3)``."""
    return np.concatenate([p.positions.astype(float)[np.asarray(p.indices, dtype=np.int64).reshape(-1, 3)]
                           for p in read_glb(path).primitives if len(p.indices)])  # fmt: skip


def assert_model_mesh(tc: unittest.TestCase, folder: Path, section: dict, obj_name: str, label: str) -> None:
    """``section`` (a manifest ``mesh`` section) is valid, its glb is ``obj_name``'s triangles in the same frame, and its maps
    and their ``.import`` sidecars are written."""
    folder = Path(folder)
    manifest_io.validate_mesh_section(section)
    tc.assertEqual(section["file"], obj_name[: -len(".obj")] + ".glb", label)
    obj = read_obj(folder / obj_name)
    tris = glb_triangles(folder / section["file"])
    tc.assertEqual(len(tris), len(obj.faces), f"{label}: every fallback-mesh triangle, no more")
    tc.assertEqual(section["triangles"], len(tris), label)
    verts = tris.reshape(-1, 3)
    np.testing.assert_allclose(verts.min(axis=0), obj.vertices.min(axis=0), atol=1e-3, err_msg=label)
    np.testing.assert_allclose(verts.max(axis=0), obj.vertices.max(axis=0), atol=1e-3, err_msg=label)
    np.testing.assert_allclose(section["aabb_min"], obj.vertices.min(axis=0), atol=1e-3, err_msg=label)
    np.testing.assert_allclose(section["aabb_max"], obj.vertices.max(axis=0), atol=1e-3, err_msg=label)
    surface = section["surfaces"][0]
    for key in MAP_KEYS:
        tc.assertTrue((folder / surface[key]).is_file(), f"{label}: {key}")
        tc.assertTrue((folder / (surface[key] + ".import")).is_file(), f"{label}: {key} sidecar")


def assert_hull_mesh(tc: unittest.TestCase, folder: Path, manifest: dict, obj_name: str) -> None:
    """The hull's mesh contract: the manifest names the glb, the OBJ and the hardpoints; the glb is the OBJ; the manifest's box is
    the mesh's."""
    tc.assertEqual(manifest["files"], {"obj": obj_name, "mesh": manifest["mesh"]["file"], "hardpoints": "hardpoints.json"})
    assert_model_mesh(tc, folder, manifest["mesh"], obj_name, "hull")
    np.testing.assert_allclose(manifest["aabb_min"], manifest["mesh"]["aabb_min"], atol=2e-4)
    np.testing.assert_allclose(manifest["aabb_max"], manifest["mesh"]["aabb_max"], atol=2e-4)
    tc.assertNotIn("livery", manifest["mesh"], "civilians take no wing livery")


def _uv_rows(primitive) -> set[tuple[float, float]]:
    return {(round(float(u), 5), round(float(v), 5)) for u, v in primitive.uv}


def assert_chunks_cut_the_hull(tc: unittest.TestCase, folder: Path, manifest: dict, hp: dict, order: tuple[str, ...]) -> None:
    """Each chunk is a cut of the hull's mesh on its atlas (its OBJ the same triangles), back in place inside the hull's box, and
    together they share out the hull's triangles."""
    folder = Path(folder)
    asset_id = manifest["asset_id"]
    tc.assertEqual([c["name"] for c in hp["chunks"]], list(order))
    tc.assertEqual(manifest["chunks"], list(order))
    parent = read_glb(folder / manifest["mesh"]["file"])
    uvs = set().union(*(_uv_rows(p) for p in parent.primitives))
    lo, hi = np.array(manifest["aabb_min"]), np.array(manifest["aabb_max"])
    total = 0
    for entry in hp["chunks"]:
        name = entry["name"]
        tc.assertEqual((entry["obj"], entry["mesh"]), (f"{asset_id}_chunk_{name}.obj", f"{asset_id}_chunk_{name}.glb"))
        chunk = read_glb(folder / entry["mesh"])
        for primitive in chunk.primitives:
            tc.assertTrue(_uv_rows(primitive) <= uvs, f"{name}: on the hull's atlas")
        tris = glb_triangles(folder / entry["mesh"])
        tc.assertEqual(len(tris), len(read_obj(folder / entry["obj"]).faces), name)
        placed = tris.reshape(-1, 3) + np.array(entry["offset"])
        tc.assertTrue(np.all(placed >= lo - 1e-3) and np.all(placed <= hi + 1e-3), f"{name}: back in place inside the hull's box")
        total += len(tris)
    tc.assertEqual(total, manifest["mesh"]["triangles"], "the chunks share out the hull's triangles")


def _sample(image: np.ndarray, uv: np.ndarray) -> np.ndarray:
    size = image.shape[0]
    cols = np.clip((uv[:, 0] * size).astype(int), 0, size - 1)
    rows = np.clip((uv[:, 1] * size).astype(int), 0, size - 1)
    return image[rows, cols]


def painted_points(folder: Path, section: dict, key: str = "albedo") -> tuple[np.ndarray, np.ndarray]:
    """The opaque surface's triangle centres and the colour (sRGB, 0..1) of ``key``'s map under each: the centres, not the
    corners, which sit on the worn edges."""
    hull = read_glb(Path(folder) / section["file"]).primitives[0]
    image = read_png(Path(folder) / section["surfaces"][0][key]).astype(float) / 255.0
    corners = np.asarray(hull.indices, dtype=np.int64).reshape(-1, 3)
    centres = hull.positions.astype(float)[corners].mean(axis=1)
    return centres, _sample(image, hull.uv.astype(float)[corners].mean(axis=1))[:, :3]


def painted_faces(folder: Path, section: dict) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """As :func:`painted_points` for the albedo, plus each triangle's area and the metalness under it (the ORM map's blue): a
    colour check weighs by area and can leave the bare-metal chips out."""
    centres, rgb = painted_points(folder, section, "albedo")
    _, orm = painted_points(folder, section, "orm")
    hull = read_glb(Path(folder) / section["file"]).primitives[0]
    tris = hull.positions.astype(float)[np.asarray(hull.indices, dtype=np.int64).reshape(-1, 3)]
    area = 0.5 * np.linalg.norm(np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]), axis=1)
    return centres, rgb, area, orm[:, 2]


def glowing_points(folder: Path, section: dict) -> np.ndarray:
    """The opaque surface's triangle centres whose texel in the emissive map glows."""
    positions, glow = painted_points(folder, section, "emissive")
    return positions[glow.max(axis=1) > 40.0 / 255.0]


def assert_mirror_symmetric(tc: unittest.TestCase, vertices: np.ndarray, label: str, decimals: int = 3) -> None:
    """The point set equals its mirror image in x (rounded to ``decimals``)."""
    v = np.round(np.asarray(vertices, dtype=float), decimals) + 0.0
    m = np.round(v * np.array([-1.0, 1.0, 1.0]), decimals) + 0.0
    tc.assertEqual({tuple(r) for r in v}, {tuple(r) for r in m}, label)


__all__ = ["MAP_KEYS", "TEST_OPTIONS", "assert_chunks_cut_the_hull", "assert_hull_mesh", "assert_mirror_symmetric", "assert_model_mesh",
           "glb_triangles", "glowing_points", "painted_faces", "painted_points"]
