"""``nav_buoy``: files, counts, frames, symmetry about the spin axis, hardpoints, OBJ validity, determinism."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import nav_buoy as buoy
from tools.procgen.core import frames
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.sampling import DEFAULT_OVERLAP, DEFAULT_THICKNESS
from tools.procgen.core.obj import read_obj
from tools.procgen.core.ply import PROPERTY_NAMES, read_ply


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sorted_rows(xyz: np.ndarray) -> np.ndarray:
    view = np.ascontiguousarray(xyz.astype(np.float32)).view("f4,f4,f4")
    return np.sort(view, axis=0)


class NavBuoyTests(unittest.TestCase):
    """Builds the default asset twice (same seed) once for the whole class (well under a second)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = buoy.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = buoy.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.ply = read_ply(cls.dir_a / buoy.PLY_NAME)
        cls.splats = cls.ply.to_splats()
        cls.godot_xyz = frames.flip_xy(cls.splats.xyz)  # centred Godot frame (the hardpoints frame)
        cls.hp = json.loads((cls.dir_a / buoy.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / buoy.OBJ_NAME)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def part_slice(self, name: str) -> slice:
        """Splats are written in manifest ``counts`` order, so each part is a contiguous slice."""
        start = 0
        for part, n in self.manifest["counts"].items():
            if part == name:
                return slice(start, start + n)
            start += n
        raise KeyError(name)

    # --- registry, files and manifest -------------------------------------------------------
    def test_registered_under_its_id(self) -> None:
        self.assertIs(ASSETS["nav_buoy"], buoy.build)

    def test_all_files_are_written_and_listed(self) -> None:
        names = sorted(p.name for p in self.dir_a.iterdir())
        self.assertEqual(names, ["hardpoints.json", "manifest.json", "nav_buoy.mtl", "nav_buoy.obj", "nav_buoy.ply"])
        self.assertEqual(sorted(p.name for p in self.out_a.files), names)
        self.assertEqual(self.out_a.warnings, ())
        self.assertEqual(self.manifest["files"], {"fallback_mesh": "nav_buoy.obj", "hardpoints": "hardpoints.json"})

    def test_manifest_lods_zero_and_budget(self) -> None:
        lods = self.manifest["lods"]
        self.assertEqual(len(lods), 1)
        lod0 = lods[0]
        self.assertEqual((lod0["level"], lod0["file"]), (0, "nav_buoy.ply"))
        self.assertEqual(lod0["spacing_m"], buoy.DEFAULT_SPACING_M)
        self.assertEqual(buoy.SPLAT_BUDGET, (5_000, 15_000))  # AC3
        self.assertTrue(buoy.SPLAT_BUDGET[0] <= lod0["splats"] <= buoy.SPLAT_BUDGET[1], lod0["splats"])
        self.assertEqual(lod0["splats"], self.ply.count)
        self.assertEqual(self.out_a.splat_count, self.ply.count)
        self.assertEqual(sum(self.manifest["counts"].values()), self.ply.count)
        self.assertEqual(list(self.manifest["counts"]), ["hull", "wing_r", "wing_l", "mast", "stub"])
        self.assertEqual(self.manifest["counts"]["wing_r"], self.manifest["counts"]["wing_l"])
        self.assertEqual((self.manifest["asset_id"], self.manifest["frame"], self.manifest["seed"]), ("nav_buoy", "godot", 42))

    # --- PLY content ------------------------------------------------------------------------
    def test_ply_parses_with_the_3dgs_layout_and_finite_values(self) -> None:
        self.assertEqual(self.ply.names, list(PROPERTY_NAMES))
        for name in PROPERTY_NAMES:
            self.assertTrue(np.all(np.isfinite(self.ply.column(name))), name)

    def test_written_positions_are_centred_on_the_spin_axis(self) -> None:
        self.assertLess(float(np.abs(self.splats.xyz.mean(axis=0)).max()), 1e-4)
        offset = self.manifest["centroid_offset"]
        self.assertEqual((offset[0], offset[2]), (0.0, 0.0))  # only y is re-centred

    def test_manifest_aabb_matches_the_file_after_the_flip(self) -> None:
        lo, hi = frames.aabb_godot_to_3dgs(self.manifest["aabb_min"], self.manifest["aabb_max"])
        np.testing.assert_allclose(self.splats.xyz.min(axis=0), lo, atol=2e-3)
        np.testing.assert_allclose(self.splats.xyz.max(axis=0), hi, atol=2e-3)

    def test_splat_set_is_exactly_mirror_symmetric_in_x_and_z(self) -> None:
        xyz = self.godot_xyz.astype(np.float32)
        for k in (0, 2):
            flipped = xyz.copy()
            flipped[:, k] *= -1
            self.assertTrue(np.array_equal(sorted_rows(xyz), sorted_rows(flipped)), "xyz"[k])

    def test_splats_are_flat_oriented_opaque_discs(self) -> None:
        s = self.splats
        spacing = buoy.DEFAULT_SPACING_M
        np.testing.assert_allclose(s.scale[:, :2], DEFAULT_OVERLAP * spacing, rtol=1e-4)
        np.testing.assert_allclose(s.scale[:, 2], DEFAULT_THICKNESS * spacing, rtol=1e-3)
        rot = frames.quat_to_matrix(s.rot)
        normals = s.normals / np.linalg.norm(s.normals, axis=1, keepdims=True)
        self.assertGreater(float(np.abs(np.einsum("ij,ij->i", rot[:, :, 2], normals)).min()), 0.999)
        self.assertTrue(np.all(s.alpha > 0.979))  # no glass on a buoy

    def test_dimensions_follow_the_design(self) -> None:
        lo, hi = self.godot_xyz.min(axis=0), self.godot_xyz.max(axis=0)
        self.assertTrue(4.0 < hi[1] - lo[1] < 4.6, hi[1] - lo[1])  # about 4 m tall (section 9.3)
        self.assertAlmostEqual(float(hi[0] - lo[0]), 2.54, delta=0.02)  # wing tip to wing tip
        self.assertAlmostEqual(float(hi[2] - lo[2]), 0.8, delta=0.02)  # the barrel's diameter
        dims = self.manifest["dimensions_m"]
        self.assertEqual((dims["height"], dims["span"], dims["depth"]), (self.hp["height_m"], self.hp["span_m"], self.hp["depth_m"]))

    def test_colours_show_the_palette_and_hazard_stripes(self) -> None:
        rgb, xyz = self.splats.rgb, self.godot_xyz
        self.assertTrue(np.all(rgb >= 0.0))
        self.assertLess(float(rgb.max()), 1.0)
        orange = (rgb[:, 0] > 2.0 * rgb[:, 1]) & (rgb[:, 0] > 0.1)
        self.assertTrue(0.03 < orange.mean() < 0.2, orange.mean())
        # Stripes are rings on the barrel (a 36-sided prism of radius 0.4), one near each end.
        radius = np.hypot(xyz[orange, 0], xyz[orange, 2])
        self.assertGreater(float(radius.min()), 0.4 * np.cos(np.pi / 36) - 1e-4)
        self.assertLess(float(radius.max()), 0.4 + 1e-4)
        self.assertGreater(int((xyz[orange, 1] > 0.5).sum()), 100)
        self.assertGreater(int((xyz[orange, 1] < -0.5).sum()), 100)
        # The wings are dark panels; the rest of the hull is neutral grey.
        hull = self.part_slice("hull")
        wings = rgb[self.part_slice("wing_r")]
        self.assertLess(float(wings.mean()), 0.5 * float(rgb[hull].mean()))
        chroma = (rgb.max(axis=1) - rgb.min(axis=1)) / np.maximum(rgb.max(axis=1), 1e-9)
        # (The cool fill light tints the shadow side a little, hence 0.2 rather than the ship's 0.15.)
        lit_grey = (chroma[hull] < 0.2)[~orange[hull] & (rgb[hull].max(axis=1) > 0.05)]
        self.assertGreater(float(lit_grey.mean()), 0.95)
        self.assertGreater(float(rgb[hull][~orange[hull]].mean()), 0.15)

    # --- hardpoints -------------------------------------------------------------------------
    def test_hardpoints_schema(self) -> None:
        hp = self.hp
        for key in ("asset_id", "frame", "units", "height_m", "span_m", "mass_kg", "spin_axis", "beacon", "collision"):
            self.assertIn(key, hp)
        self.assertEqual((hp["asset_id"], hp["frame"], hp["units"]), ("nav_buoy", "godot", "m"))
        self.assertEqual(hp["spin_axis"], [0.0, 1.0, 0.0])
        self.assertGreater(hp["mass_kg"], 0.0)

    def test_beacon_sits_on_the_spin_axis_at_the_mast_tip(self) -> None:
        beacon = self.hp["beacon"]
        pos = np.array(beacon["position"])
        self.assertEqual((pos[0], pos[2]), (0.0, 0.0))
        self.assertEqual(beacon["radius"], 0.1)
        # The highest point of the buoy: every splat is below it, the mast's are just below.
        self.assertGreater(pos[1], float(self.godot_xyz[:, 1].max()))
        mast = self.godot_xyz[self.part_slice("mast")]
        self.assertLess(float(np.linalg.norm(mast - pos, axis=1).min()), beacon["radius"])
        self.assertGreater(pos[1] - float(self.godot_xyz[self.part_slice("hull"), 1].max()), 0.8)

    def test_collision_is_one_capsule_along_the_spin_axis(self) -> None:
        shapes = self.hp["collision"]
        self.assertEqual(len(shapes), 1)
        cap = shapes[0]
        self.assertEqual((cap["name"], cap["type"], cap["radius"], cap["height"], cap["axis"]), ("hull", "capsule", 0.4, 3.0, "z"))
        self.assertEqual(cap["basis"]["z"], [0.0, 1.0, 0.0])  # the capsule's local Z is the buoy's Y
        self.assertEqual((cap["position"][0], cap["position"][2]), (0.0, 0.0))
        self.assertAlmostEqual(cap["position"][1], -self.manifest["centroid_offset"][1], places=4)

    # --- meshes -----------------------------------------------------------------------------
    def test_fallback_obj_is_valid_and_matches_the_splat_bounds(self) -> None:
        obj = self.obj
        self.assertGreater(len(obj.vertices), 0)
        self.assertGreater(len(obj.faces), 0)
        self.assertGreaterEqual(int(obj.faces.min()), 0)
        self.assertLess(int(obj.faces.max()), len(obj.vertices))
        self.assertEqual(obj.mtllib, "nav_buoy.mtl")
        mtl = (self.dir_a / "nav_buoy.mtl").read_text(encoding="ascii")
        for name in obj.materials:
            self.assertIn(f"newmtl {name}", mtl)
        self.assertIn("ef_stripe", obj.materials)
        np.testing.assert_allclose(obj.vertices.min(axis=0), self.manifest["aabb_min"], atol=0.05)
        # The mast tip is a lathe pole: the mesh reaches it, the splats stop a few centimetres short.
        np.testing.assert_allclose(obj.vertices.max(axis=0), self.manifest["aabb_max"], atol=0.05)
        self.assertAlmostEqual(float(obj.vertices[:, 1].max()), self.hp["beacon"]["position"][1], places=4)

    # --- determinism ------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        for path in self.dir_a.iterdir():
            self.assertEqual(sha256(path), sha256(self.dir_b / path.name), path.name)

    def test_a_different_seed_changes_the_splats_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = buoy.build(BuildContext(Path(tmp), seed=7))
            self.assertNotEqual(sha256(Path(tmp) / buoy.PLY_NAME), sha256(self.dir_a / buoy.PLY_NAME))
            self.assertAlmostEqual(other.splat_count, self.out_a.splat_count, delta=0.02 * self.out_a.splat_count)
            hp = json.loads((Path(tmp) / buoy.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            self.assertAlmostEqual(hp["beacon"]["position"][1], self.hp["beacon"]["position"][1], delta=0.01)
            self.assertEqual(hp["height_m"], self.hp["height_m"])


class NavBuoyOptionTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def test_spacing_option_scales_the_count_and_is_recorded(self) -> None:
        coarse = buoy.build(BuildContext(self.dir / "c", seed=42, options={"spacing": 0.08}))
        fine = buoy.build(BuildContext(self.dir / "f", seed=42, options={"spacing": 0.05}))
        self.assertEqual(coarse.manifest["lods"][0]["spacing_m"], 0.08)
        self.assertAlmostEqual(fine.splat_count / coarse.splat_count, (0.08 / 0.05) ** 2, delta=0.15)
        self.assertEqual(coarse.warnings, ())  # the budget only applies at the default spacing
        splats = read_ply(self.dir / "c" / buoy.PLY_NAME).to_splats()
        np.testing.assert_allclose(splats.scale[:, 0], DEFAULT_OVERLAP * 0.08, rtol=1e-4)

    def test_overlap_and_thickness_options(self) -> None:
        out = buoy.build(BuildContext(self.dir / "o", seed=1, options={"overlap": 1.0, "thickness": 0.1}))
        splats = read_ply(self.dir / "o" / buoy.PLY_NAME).to_splats()
        np.testing.assert_allclose(splats.scale[:, 0], 0.04, rtol=1e-4)
        np.testing.assert_allclose(splats.scale[:, 2], 0.004, rtol=1e-3)
        self.assertEqual(out.manifest["sampling"], {"spacing_m": 0.04, "overlap": 1.0, "thickness": 0.1})

    def test_invalid_options_are_rejected(self) -> None:
        for bad in ({"spacing": 0.0}, {"spacing": -1.0}, {"overlap": 0.0}, {"thickness": -0.1}):
            with self.subTest(bad), self.assertRaises(ValueError):
                buoy.build(BuildContext(self.dir / "bad", seed=1, options=bad))


if __name__ == "__main__":
    unittest.main()
