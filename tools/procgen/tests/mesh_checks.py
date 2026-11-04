"""Shared check for the civilian ships' painted meshes (the 2026-11-04 directive: ships are meshes, M4's exporter).

A model's ``<stem>_mesh.glb`` must be its fallback mesh drawn the game's way: the same triangles, the same bounds and the same
materials, so the 90 % fidelity check, which scores the fallback mesh, scores what the game draws.
"""

from __future__ import annotations

import unittest
from pathlib import Path

import numpy as np

from tools.procgen.core.glb import read_glb
from tools.procgen.core.obj import read_obj


def assert_painted_mesh(tc: unittest.TestCase, folder: Path, entry: dict, obj_name: str, label: str) -> None:
    """``entry`` is the manifest's ``paint_mesh`` section of a model whose fallback mesh is ``obj_name``."""
    obj = read_obj(Path(folder) / obj_name)
    glb = read_glb(Path(folder) / entry["file"])
    tc.assertEqual(entry["file"], obj_name[: -len(".obj")] + "_mesh.glb", label)
    triangles = sum(len(p.indices) // 3 for p in glb.primitives)
    tc.assertEqual(triangles, len(obj.faces), f"{label}: every fallback-mesh triangle, no more")
    tc.assertEqual(entry["triangles"], triangles, label)
    positions = np.concatenate([p.positions for p in glb.primitives])
    np.testing.assert_allclose(positions.min(axis=0), obj.vertices.min(axis=0), atol=1e-3, err_msg=label)
    np.testing.assert_allclose(positions.max(axis=0), obj.vertices.max(axis=0), atol=1e-3, err_msg=label)
    np.testing.assert_allclose(entry["aabb_min"], obj.vertices.min(axis=0), atol=1e-3, err_msg=label)
    tc.assertTrue(set(obj.materials) <= {m["name"] for m in entry["materials"]}, f"{label}: the same paint")
