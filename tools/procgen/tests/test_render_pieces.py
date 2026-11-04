"""The render comparison's big pieces (M4-T27): the Babylon 5 station stand-in and the capital hulls, as splat levels and painted meshes."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import b5_station as station
from tools.procgen.assets import capital_hulls as capitals
from tools.procgen.core import frames
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.glb import read_glb
from tools.procgen.core.ply import read_ply


def godot_xyz(path: Path) -> np.ndarray:
    return frames.flip_xy(read_ply(path).to_splats().xyz)


def mesh_positions(path: Path) -> np.ndarray:
    return np.concatenate([p.positions for p in read_glb(path).primitives])


class StationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        # A coarser LOD0 keeps the test quick; the shape and the files are the same.
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out = station.build(BuildContext(cls.dir_a, seed=42, options={"spacing": 16.0}))
        station.build(BuildContext(cls.dir_b, seed=42, options={"spacing": 16.0}))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.pieces = cls.manifest["pieces"]

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_two_pieces_each_a_chain_of_four_levels_and_a_mesh(self) -> None:
        self.assertEqual(set(self.pieces), {"drum", "frame"})
        for name, piece in self.pieces.items():
            lods = piece["lods"]
            self.assertEqual([e["level"] for e in lods], [0, 1, 2, 3])
            self.assertEqual([e["spacing_m"] for e in lods], [16.0, 32.0, 64.0, 128.0])
            for coarse, fine in zip(lods[1:], lods[:-1], strict=True):
                self.assertAlmostEqual(coarse["splats"] / fine["splats"], 0.25, delta=0.03, msg=name)
            for e in lods:
                self.assertTrue((self.dir_a / e["file"]).exists())
                self.assertTrue((self.dir_a / e["lighting"]).exists())
            self.assertTrue((self.dir_a / piece["paint_mesh"]["file"]).exists())

    def test_each_level_is_centred_on_its_recorded_centroid(self) -> None:
        for piece in self.pieces.values():
            for e in piece["lods"]:
                xyz = godot_xyz(self.dir_a / e["file"])
                self.assertLess(float(np.abs(xyz.mean(axis=0)).max()), 0.05)
                self.assertEqual(len(xyz), e["splats"])

    def test_about_8_km_long_with_a_drum_one_ninth_of_that_across(self) -> None:
        lo, hi = np.array(self.manifest["aabb_min"]), np.array(self.manifest["aabb_max"])
        self.assertAlmostEqual(float(hi[2] - lo[2]), 8000.0, delta=150.0)
        drum = mesh_positions(self.dir_a / self.pieces["drum"]["paint_mesh"]["file"])
        diameter = float(drum[:, 0].max() - drum[:, 0].min())
        self.assertAlmostEqual(diameter, 8000.0 / 9.0, delta=5.0)
        length = float(drum[:, 2].max() - drum[:, 2].min())
        self.assertTrue(0.40 <= length / 8000.0 <= 0.45, length)

    def test_the_drum_turns_in_place_about_its_own_axis(self) -> None:
        drum = mesh_positions(self.dir_a / self.pieces["drum"]["paint_mesh"]["file"])
        np.testing.assert_allclose(drum[:, :2].mean(axis=0), [0.0, 0.0], atol=1.0)
        radius = np.linalg.norm(drum[:, :2], axis=1).max()
        self.assertAlmostEqual(float(radius), station.DRUM_RADIUS_M, delta=1.0)
        lod0 = self.pieces["drum"]["lods"][0]
        self.assertLess(float(np.abs(np.array(lod0["centroid"][:2])).max()), 5.0, "the splat centroid sits on the axis")

    def test_the_top_bar_and_every_stationary_part_clear_the_turning_drum(self) -> None:
        frame = mesh_positions(self.dir_a / self.pieces["frame"]["paint_mesh"]["file"])
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
        for piece in self.pieces.values():
            for name in [e["file"] for e in piece["lods"]] + [piece["paint_mesh"]["file"]]:
                self.assertEqual((self.dir_a / name).read_bytes(), (self.dir_b / name).read_bytes(), name)

    def test_the_default_build_fits_its_budget(self) -> None:
        # The default spacing's count, from the areas: (area / spacing^2) per piece.
        drum = sum(p.mesh.area() for p in station.drum_parts())
        frame = sum(p.mesh.area() for p in station.frame_parts())
        expected = (drum + frame) / station.LOD_SPACINGS_M[0] ** 2
        self.assertTrue(station.LOD0_BUDGET[0] <= expected <= station.LOD0_BUDGET[1], expected)


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

    def test_one_box_per_class_at_the_stand_ins_size(self) -> None:
        classes = self.manifest["classes"]
        self.assertEqual(set(classes), {"cruiser", "destroyer", "carrier"})
        for cls, entry in classes.items():
            size = np.array(capitals.CLASSES[cls])
            self.assertEqual(entry["size"], list(size))
            mesh = mesh_positions(self.dir / entry["paint_mesh"]["file"])
            np.testing.assert_allclose(mesh.max(axis=0) - mesh.min(axis=0), size, atol=1e-3)
            np.testing.assert_allclose(mesh.mean(axis=0), [0.0, 0.0, 0.0], atol=1e-3)
            self.assertEqual(entry["paint_mesh"]["triangles"], 12)

    def test_about_the_same_count_per_class_and_coarser_levels(self) -> None:
        counts = [e["lods"][0]["splats"] for e in self.manifest["classes"].values()]
        self.assertLess(max(counts) / min(counts), 1.3)
        for entry in self.manifest["classes"].values():
            shares = [e["splats"] / entry["lods"][0]["splats"] for e in entry["lods"]]
            self.assertEqual(len(shares), 3)
            self.assertAlmostEqual(shares[1], 0.25, delta=0.03)
            self.assertAlmostEqual(shares[2], 0.0625, delta=0.01)
            xyz = godot_xyz(self.dir / entry["lods"][0]["file"])
            np.testing.assert_allclose(xyz.max(axis=0) - xyz.min(axis=0), entry["size"], rtol=0.02)


if __name__ == "__main__":
    unittest.main()
