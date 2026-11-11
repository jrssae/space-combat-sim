"""``jumpgate`` built whole (standard tier, about a minute): the output contract, the hardpoints and markers, the OBJ against the
manifest, the collision covering the written mesh, determinism."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import jumpgate as jg
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.obj import read_obj
from tools.procgen.tests.test_jumpgate_helpers import boxes_contain

SMALL = {"atlas_px": 512}  # the determinism builds: the same geometry on a small atlas


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class JumpgateTests(unittest.TestCase):
    """Builds the default asset once for the class."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name) / "jumpgate"
        cls.out = jg.build(BuildContext(cls.dir, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir)
        cls.hp = json.loads((cls.dir / jg.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir / jg.OBJ_NAME)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    # --- registry, files and manifest -------------------------------------------------------
    def test_registered_under_its_id(self) -> None:
        self.assertIs(ASSETS["jumpgate"], jg.build)

    def test_all_files_are_written_and_listed(self) -> None:
        names = sorted(p.name for p in self.dir.iterdir())
        maps = [f"jumpgate_{k}.png{ext}" for k in ("albedo", "emissive", "normal", "orm") for ext in ("", ".import")]
        self.assertEqual(names, sorted(["hardpoints.json", "manifest.json", "jumpgate.glb", "jumpgate.mtl", "jumpgate.obj", *maps]))
        self.assertEqual(sorted(p.name for p in self.out.files), names)
        self.assertEqual(self.out.warnings, ())
        self.assertEqual(self.manifest["files"], {"obj": "jumpgate.obj", "mesh": "jumpgate.glb", "hardpoints": "hardpoints.json"})

    def test_the_mesh_section_meets_the_contract(self) -> None:
        mesh = self.manifest["mesh"]
        manifest_io.validate_mesh_section(mesh)
        self.assertEqual((self.manifest["asset_id"], self.manifest["frame"], self.manifest["seed"]), ("jumpgate", "godot", 42))
        self.assertEqual(mesh["lods"], [])  # the importer builds the levels of detail
        self.assertEqual(mesh["atlas_px"], jg.ATLAS_PX)
        self.assertEqual([s["name"] for s in mesh["surfaces"]], ["hull"])  # no glass
        self.assertGreater(mesh["surfaces"][0]["emissive_strength"], 0.0)  # the lamps
        self.assertLess(mesh["texel_m"], 1.5)
        self.assertEqual(self.out.triangle_count, mesh["triangles"])
        self.assertLess(mesh["triangles"], 30_000)  # a prop seen from 100 m to 1 000 km

    def test_the_manifest_aabb_bounds_the_obj(self) -> None:
        np.testing.assert_allclose(self.obj.vertices.min(axis=0), self.manifest["aabb_min"], atol=1e-3)
        np.testing.assert_allclose(self.obj.vertices.max(axis=0), self.manifest["aabb_max"], atol=1e-3)
        self.assertEqual(self.manifest["centroid_offset"], [0.0, 0.0, 0.0])
        self.assertEqual(len(self.obj.faces), self.manifest["mesh"]["triangles"])

    def test_the_manifest_carries_the_vortex_and_the_dimensions(self) -> None:
        vortex = self.manifest["vortex"]
        for key, value in vortex.items():
            self.assertEqual(value, self.hp["vortex"][key], key)
        dims = self.manifest["dimensions_m"]
        self.assertEqual((dims["arm_length"], dims["arm_radius"], dims["vortex_depth"]), (1200.0, 800.0, 1200.0))
        self.assertEqual(dims["arm_side_radius"], round(jg.MOUTH_ASPECT * 800.0, 3))
        self.assertTrue(740.0 < dims["vortex_radius"] < 800.0, dims["vortex_radius"])
        self.assertTrue(0.9 * dims["arm_side_radius"] < dims["vortex_half_width"] < dims["arm_side_radius"])
        self.assertEqual(vortex["semi_axes_m"], [dims["vortex_half_width"], dims["vortex_radius"]])

    # --- hardpoints -------------------------------------------------------------------------
    def test_hardpoints_schema(self) -> None:
        for key in ("asset_id", "frame", "units", "span_m", "depth_m", "arm_length_m", "arm_radius_m", "arm_side_radius_m", "mouth_aspect",
                    "vortex", "arrival", "departure",
                    "emitters", "arms", "lights", "collision"):
            self.assertIn(key, self.hp)
        self.assertEqual((self.hp["asset_id"], self.hp["frame"], self.hp["units"]), ("jumpgate", "godot", "m"))
        self.assertEqual(len(self.hp["arms"]), 4)
        self.assertEqual(len(self.hp["lights"]), 40)
        self.assertEqual(len(self.hp["collision"]), 44)

    def test_the_arms_run_parallel_to_the_axis_from_front_to_back(self) -> None:
        for k, arm in enumerate(self.hp["arms"]):
            front, back, axis = (np.array(arm[k]) for k in ("front", "back", "axis"))
            out = self.hp["arm_radius_m"] if k % 2 == 0 else self.hp["arm_side_radius_m"]  # top and bottom, then the sides
            self.assertAlmostEqual(float(np.hypot(front[0], front[1])), out, places=3)
            self.assertEqual(float(front[2]), 0.0)  # the front ends in the mouth's plane
            np.testing.assert_allclose(front - back, 1200.0 * axis, atol=1e-3)
            np.testing.assert_allclose(axis, [0.0, 0.0, -1.0], atol=1e-9)
        self.assertEqual(self.hp["vortex"]["depth_m"], 1200.0)

    def test_the_markers_sit_inside_the_ring(self) -> None:
        radial = np.hypot(self.obj.vertices[:, 0], self.obj.vertices[:, 1]).min()
        for name in ("arrival", "departure"):
            p = np.array(self.hp[name]["position"])
            self.assertLess(float(np.hypot(p[0], p[1])), self.hp["vortex"]["radius_m"])
        self.assertLess(self.hp["vortex"]["radius_m"], radial)
        half_width, half_height = self.hp["vortex"]["semi_axes_m"]
        outside = (self.obj.vertices[:, 0] / half_width) ** 2 + (self.obj.vertices[:, 1] / half_height) ** 2
        self.assertGreater(float(outside.min()), 1.0)  # the elliptical rim meets no arm
        self.assertEqual(self.hp["arrival"]["vortex"], "arrival")
        self.assertEqual(self.hp["departure"]["vortex"], "departure")

    def test_the_collision_covers_the_written_mesh(self) -> None:
        inside = boxes_contain(self.hp["collision"], self.obj.vertices, 1.5)
        self.assertTrue(inside.all(), self.obj.vertices[~inside][:5])

    def test_the_obj_is_valid(self) -> None:
        obj = self.obj
        self.assertGreaterEqual(int(obj.faces.min()), 0)
        self.assertLess(int(obj.faces.max()), len(obj.vertices))
        mtl = (self.dir / "jumpgate.mtl").read_text(encoding="ascii")
        for name in obj.materials:
            self.assertIn(f"newmtl {name}", mtl)
        for name in ("jg_fin", "jg_fin_inset", "jg_girder", "jg_lamp", "jg_emitter"):
            self.assertIn(name, obj.materials)


class JumpgateDeterminismTests(unittest.TestCase):
    """Three small builds: two with the same seed, one with another."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.root = Path(cls._tmp.name)
        for name, seed in (("a", 42), ("b", 42), ("c", 7)):
            jg.build(BuildContext(cls.root / name, seed=seed, options=SMALL))

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_same_seed_gives_byte_identical_output(self) -> None:
        for path in (self.root / "a").iterdir():
            self.assertEqual(sha256(path), sha256(self.root / "b" / path.name), path.name)

    def test_a_different_seed_changes_the_wear_but_not_the_design(self) -> None:
        self.assertNotEqual(sha256(self.root / "a" / "jumpgate_albedo.png"), sha256(self.root / "c" / "jumpgate_albedo.png"))
        for name in ("jumpgate.obj", jg.HARDPOINTS_NAME):
            a = (self.root / "a" / name).read_text(encoding="utf-8").replace("seed 42", "")
            c = (self.root / "c" / name).read_text(encoding="utf-8").replace("seed 7", "")
            self.assertEqual(a, c, name)

    def test_invalid_options_are_rejected(self) -> None:
        for bad in ({"arm_length_m": 0.0}, {"arm_length_m": -5.0}, {"mouth_aspect": 0.8}, {"mouth_aspect": 3.0}):
            with self.subTest(bad), self.assertRaises(ValueError):
                jg.build(BuildContext(self.root / "bad", seed=1, options=bad))


if __name__ == "__main__":
    unittest.main()
