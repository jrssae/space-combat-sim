"""The big stand-in pieces (M4-T27, textured in M4-T30d): the capital hulls as textured meshes. The Babylon 5 station that replaced
M4's stand-in (M7-T04) has its own tests in ``test_babylon5_station.py``."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import capital_hulls as capitals
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.glb import read_glb


def mesh_positions(path: Path) -> np.ndarray:
    return np.concatenate([p.positions for p in read_glb(path).primitives])


class CapitalHullTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name) / "a"
        capitals.build(BuildContext(cls.dir, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_one_textured_box_per_class_at_the_stand_ins_size(self) -> None:
        classes = self.manifest["classes"]
        self.assertEqual(set(classes), {"cruiser", "destroyer", "carrier"})
        for cls, entry in classes.items():
            size = np.array(capitals.CLASSES[cls])
            self.assertEqual(entry["size"], list(size))
            mesh = mesh_positions(self.dir / entry["mesh"]["file"])
            np.testing.assert_allclose(mesh.max(axis=0) - mesh.min(axis=0), size, atol=1e-3)
            np.testing.assert_allclose(mesh.mean(axis=0), [0.0, 0.0, 0.0], atol=1e-3)
            self.assertEqual(entry["mesh"]["triangles"], 12)
            self.assertEqual(self.manifest["files"][f"{cls}_mesh"], entry["mesh"]["file"])


if __name__ == "__main__":
    unittest.main()
