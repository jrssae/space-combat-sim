"""The generator writes textured meshes only (M4-T31): the point-cloud writers are gone and no asset writes a point cloud, its
lighting records or its level ladder."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

from tools.procgen.assets import nav_buoy
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext

# The point-cloud modules: the PLY writer, the lighting records, the old frame flip and T27's painted mesh.
REMOVED_MODULES = ("ply", "lighting", "frames", "paint_mesh")
# What an asset used to write beside its mesh: point clouds and their lighting records.
REMOVED_SUFFIXES = (".ply", ".light")
REMOVED_MANIFEST_KEYS = ("lods", "hero", "paint_mesh", "sampling")


class MeshOnlyTests(unittest.TestCase):
    def test_the_point_cloud_modules_are_gone(self) -> None:
        for name in REMOVED_MODULES:
            with self.subTest(module=name):
                self.assertIsNone(importlib.util.find_spec(f"tools.procgen.core.{name}"))

    def test_a_built_asset_writes_no_point_cloud_and_its_manifest_names_none(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "nav_buoy"
            nav_buoy.build(BuildContext(out, seed=42))
            written = sorted(p.name for p in out.iterdir())
            self.assertFalse([n for n in written if n.endswith(REMOVED_SUFFIXES)], written)
            manifest = manifest_io.read_manifest(out)
            for key in REMOVED_MANIFEST_KEYS:
                self.assertNotIn(key, manifest)
            self.assertIn("mesh", manifest, "the textured mesh is the asset")
            for name in manifest["files"].values():
                self.assertFalse(name.endswith(REMOVED_SUFFIXES), name)


if __name__ == "__main__":
    unittest.main()
