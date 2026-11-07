"""The big stand-in pieces (M4-T27, textured in M4-T30d): the Babylon 5 station stand-in and the capital hulls as textured meshes."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import b5_station as station
from tools.procgen.assets import capital_hulls as capitals
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.glb import read_glb


def mesh_positions(path: Path) -> np.ndarray:
    return np.concatenate([p.positions for p in read_glb(path).primitives])


class StationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out = station.build(BuildContext(cls.dir_a, seed=42))
        station.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.pieces = cls.manifest["pieces"]

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_two_pieces_each_a_textured_mesh_and_its_bounds(self) -> None:
        self.assertEqual(set(self.pieces), {"drum", "frame"})
        for name, piece in self.pieces.items():
            self.assertEqual(set(piece) - {"pivot", "axis"}, {"aabb_min", "aabb_max", "mesh"}, name)
            self.assertTrue((self.dir_a / piece["mesh"]["file"]).exists())
            mesh = mesh_positions(self.dir_a / piece["mesh"]["file"])
            np.testing.assert_allclose(mesh.min(axis=0), piece["aabb_min"], atol=1e-2)
            np.testing.assert_allclose(mesh.max(axis=0), piece["aabb_max"], atol=1e-2)
        self.assertEqual(self.manifest["files"], {"drum_mesh": self.pieces["drum"]["mesh"]["file"],
                                                  "frame_mesh": self.pieces["frame"]["mesh"]["file"]})

    def test_about_8_km_long_with_a_drum_one_ninth_of_that_across(self) -> None:
        lo, hi = np.array(self.manifest["aabb_min"]), np.array(self.manifest["aabb_max"])
        self.assertAlmostEqual(float(hi[2] - lo[2]), 8000.0, delta=150.0)
        drum = mesh_positions(self.dir_a / self.pieces["drum"]["mesh"]["file"])
        diameter = float(drum[:, 0].max() - drum[:, 0].min())
        self.assertAlmostEqual(diameter, 8000.0 / 9.0, delta=5.0)
        length = float(drum[:, 2].max() - drum[:, 2].min())
        self.assertTrue(0.40 <= length / 8000.0 <= 0.45, length)

    def test_the_drum_turns_in_place_about_its_own_axis(self) -> None:
        drum = mesh_positions(self.dir_a / self.pieces["drum"]["mesh"]["file"])
        np.testing.assert_allclose(0.5 * (drum[:, :2].min(axis=0) + drum[:, :2].max(axis=0)), [0.0, 0.0], atol=1.0)
        radius = np.linalg.norm(drum[:, :2], axis=1).max()
        self.assertAlmostEqual(float(radius), station.DRUM_RADIUS_M, delta=1.0)

    def test_the_top_bar_and_every_stationary_part_clear_the_turning_drum(self) -> None:
        frame = mesh_positions(self.dir_a / self.pieces["frame"]["mesh"]["file"])
        pivot = np.array(self.pieces["drum"]["pivot"])
        local = frame - pivot
        half = 0.5 * (station.DRUM_BACK_Z - station.DRUM_FRONT_Z)
        along = np.abs(local[:, 2]) < half - 1.0
        radial = np.linalg.norm(local[:, :2], axis=1)
        # Inside the drum's length nothing stationary comes within 10 m of its surface (vertices of the bar and its struts).
        self.assertGreater(float(radial[along].min()), station.DRUM_RADIUS_M + 10.0)
        top = local[along & (local[:, 1] > station.DRUM_RADIUS_M)]
        self.assertGreater(len(top), 0, "a top bar runs over the drum")

    def test_deterministic(self) -> None:
        for path in self.dir_a.iterdir():
            self.assertEqual(path.read_bytes(), (self.dir_b / path.name).read_bytes(), path.name)


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
