"""``nav_buoy``: files, frames, symmetry about the spin axis, hardpoints, OBJ validity, determinism."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import nav_buoy as buoy
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.obj import read_obj
from tools.procgen.core.sampling import SurfaceSamples
from tools.procgen.styles.earthforce import EARTHFORCE


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sorted_rows(xyz: np.ndarray) -> np.ndarray:
    view = np.ascontiguousarray(xyz.astype(np.float32)).view("f4,f4,f4")
    return np.sort(view, axis=0)


class NavBuoyTests(unittest.TestCase):
    """Builds the default asset twice (same seed) once for the whole class (a few seconds)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = buoy.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = buoy.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        ctx = BuildContext(cls.dir_a, seed=42)
        cls.placed, _ = buoy.centre(buoy.build_parts(buoy.DEFAULT_SPEC, EARTHFORCE, ctx, buoy.DEFAULT_SPACING_M))
        cls.samples = {p.name: s for p, s in cls.placed}
        cls.godot_xyz = SurfaceSamples.concatenate(list(cls.samples.values())).positions  # centred Godot frame (the hardpoints frame)
        cls.hp = json.loads((cls.dir_a / buoy.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / buoy.OBJ_NAME)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    # --- registry, files and manifest -------------------------------------------------------
    def test_registered_under_its_id(self) -> None:
        self.assertIs(ASSETS["nav_buoy"], buoy.build)

    def test_all_files_are_written_and_listed(self) -> None:
        names = sorted(p.name for p in self.dir_a.iterdir())
        maps = [f"nav_buoy_{k}.png{ext}" for k in ("albedo", "emissive", "normal", "orm") for ext in ("", ".import")]  # M4-T30d
        self.assertEqual(names, sorted(["hardpoints.json", "manifest.json", "nav_buoy.glb", "nav_buoy.mtl", "nav_buoy.obj", *maps]))
        self.assertEqual(sorted(p.name for p in self.out_a.files), names)
        self.assertEqual(self.out_a.warnings, ())
        self.assertEqual(self.manifest["files"], {"obj": "nav_buoy.obj", "mesh": "nav_buoy.glb", "hardpoints": "hardpoints.json"})

    def test_manifest_names_the_textured_mesh(self) -> None:
        self.assertEqual((self.manifest["asset_id"], self.manifest["frame"], self.manifest["seed"]), ("nav_buoy", "godot", 42))
        self.assertEqual(self.manifest["mesh"]["file"], "nav_buoy.glb")
        self.assertEqual(self.out_a.triangle_count, self.manifest["mesh"]["triangles"])
        self.assertEqual(self.out_a.summary, f"{self.manifest['mesh']['triangles']} triangles")
        self.assertEqual(list(self.samples), ["hull", "wing_r", "wing_l", "mast", "stub"])

    # --- frame ------------------------------------------------------------------------------
    def test_the_samples_are_centred_on_the_spin_axis(self) -> None:
        self.assertLess(float(np.abs(self.godot_xyz.mean(axis=0)).max()), 1e-4)
        offset = self.manifest["centroid_offset"]
        self.assertEqual((offset[0], offset[2]), (0.0, 0.0))  # only y is re-centred

    def test_manifest_aabb_bounds_the_mesh_and_holds_the_samples(self) -> None:
        np.testing.assert_allclose(self.obj.vertices.min(axis=0), self.manifest["aabb_min"], atol=1e-4)
        np.testing.assert_allclose(self.obj.vertices.max(axis=0), self.manifest["aabb_max"], atol=1e-4)
        self.assertTrue(np.all(self.godot_xyz >= np.array(self.manifest["aabb_min"]) - 1e-4))
        self.assertTrue(np.all(self.godot_xyz <= np.array(self.manifest["aabb_max"]) + 1e-4))

    def test_the_sample_set_is_exactly_mirror_symmetric_in_x_and_z(self) -> None:
        xyz = self.godot_xyz.astype(np.float32)
        for k in (0, 2):
            flipped = xyz.copy()
            flipped[:, k] *= -1
            self.assertTrue(np.array_equal(sorted_rows(xyz), sorted_rows(flipped)), "xyz"[k])

    def test_dimensions_follow_the_design(self) -> None:
        lo, hi = self.godot_xyz.min(axis=0), self.godot_xyz.max(axis=0)
        self.assertTrue(4.0 < hi[1] - lo[1] < 4.6, hi[1] - lo[1])  # about 4 m tall (section 9.3)
        self.assertAlmostEqual(float(hi[0] - lo[0]), 2.54, delta=0.02)  # wing tip to wing tip
        self.assertAlmostEqual(float(hi[2] - lo[2]), 0.8, delta=0.02)  # the barrel's diameter
        dims = self.manifest["dimensions_m"]
        self.assertEqual((dims["height"], dims["span"], dims["depth"]), (self.hp["height_m"], self.hp["span_m"], self.hp["depth_m"]))

    def test_the_hazard_stripes_are_rings_near_both_ends(self) -> None:
        faces = self.obj.faces[np.array(self.obj.face_materials) == "ef_stripe"]
        centres = self.obj.vertices[faces].mean(axis=1)
        radius = np.hypot(centres[:, 0], centres[:, 2])
        self.assertGreater(float(radius.min()), 0.3)
        self.assertLess(float(radius.max()), 0.4 + 1e-4)
        self.assertGreater(int((centres[:, 1] > 0.5).sum()), 10)
        self.assertGreater(int((centres[:, 1] < -0.5).sum()), 10)

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
        # The mast tip: the mesh's highest vertex, every surface sample below it.
        self.assertGreater(pos[1], float(self.godot_xyz[:, 1].max()))
        self.assertAlmostEqual(float(self.obj.vertices[:, 1].max()), pos[1], places=4)
        self.assertLess(float(np.linalg.norm(self.obj.vertices - pos, axis=1).min()), 1e-4)
        self.assertGreater(pos[1] - float(self.samples["hull"].positions[:, 1].max()), 0.8)

    def test_collision_is_one_capsule_along_the_spin_axis(self) -> None:
        shapes = self.hp["collision"]
        self.assertEqual(len(shapes), 1)
        cap = shapes[0]
        self.assertEqual((cap["name"], cap["type"], cap["radius"], cap["height"], cap["axis"]), ("hull", "capsule", 0.4, 3.0, "z"))
        self.assertEqual(cap["basis"]["z"], [0.0, 1.0, 0.0])  # the capsule's local Z is the buoy's Y
        self.assertEqual((cap["position"][0], cap["position"][2]), (0.0, 0.0))
        self.assertAlmostEqual(cap["position"][1], -self.manifest["centroid_offset"][1], places=4)

    # --- meshes -----------------------------------------------------------------------------
    def test_the_obj_is_valid_and_matches_the_bounds(self) -> None:
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
        self.assertAlmostEqual(float(obj.vertices[:, 1].max()), self.hp["beacon"]["position"][1], places=4)

    # --- determinism ------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        for path in self.dir_a.iterdir():
            self.assertEqual(sha256(path), sha256(self.dir_b / path.name), path.name)

    def test_a_different_seed_changes_the_wear_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            buoy.build(BuildContext(Path(tmp), seed=7))
            albedo = "nav_buoy_albedo.png"
            self.assertNotEqual(sha256(Path(tmp) / albedo), sha256(self.dir_a / albedo))
            hp = json.loads((Path(tmp) / buoy.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            self.assertAlmostEqual(hp["beacon"]["position"][1], self.hp["beacon"]["position"][1], delta=0.01)
            self.assertEqual(hp["height_m"], self.hp["height_m"])


class NavBuoyOptionTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def test_invalid_options_are_rejected(self) -> None:
        for bad in ({"spacing": 0.0}, {"spacing": -1.0}):
            with self.subTest(bad), self.assertRaises(ValueError):
                buoy.build(BuildContext(self.dir / "bad", seed=1, options=bad))


if __name__ == "__main__":
    unittest.main()
