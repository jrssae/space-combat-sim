"""``maintenance_bot`` (M7-T11): the output contract, size and triangle budget, the frame (nose -Z, centred), the metal finish,
the hardpoints and determinism. Built twice on the default seed (about ten seconds)."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import maintenance_bot as bot
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.image import read_png
from tools.procgen.core.obj import read_obj
from tools.procgen.styles import REQUIRED_ROLES
from tools.procgen.styles.maintenance_bot import MAINTENANCE_BOT


def _rgb(path: Path) -> np.ndarray:
    """A PNG's colour channels as floats (the project's reader, so no PIL)."""
    return read_png(path)[..., :3].astype(float)

TRIANGLE_BUDGET = 6000


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class MaintenanceBotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = bot.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = bot.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.hp = json.loads((cls.dir_a / bot.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / bot.OBJ_NAME)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    # --- registry, files, manifest ----------------------------------------------------------
    def test_registered_under_its_id(self) -> None:
        self.assertIs(ASSETS["maintenance_bot"], bot.build)

    def test_all_files_are_written_and_listed(self) -> None:
        names = sorted(p.name for p in self.dir_a.iterdir())
        maps = [f"maintenance_bot_{k}.png{ext}" for k in ("albedo", "emissive", "normal", "orm") for ext in ("", ".import")]
        self.assertEqual(names, sorted(["hardpoints.json", "manifest.json", "maintenance_bot.glb", "maintenance_bot.mtl",
                                        "maintenance_bot.obj", *maps]))
        self.assertEqual(sorted(p.name for p in self.out_a.files), names)
        self.assertEqual(self.out_a.warnings, ())
        self.assertEqual(self.manifest["files"], {"obj": "maintenance_bot.obj", "mesh": "maintenance_bot.glb", "hardpoints": "hardpoints.json"})

    def test_manifest_names_the_textured_mesh(self) -> None:
        self.assertEqual((self.manifest["asset_id"], self.manifest["frame"], self.manifest["seed"]), ("maintenance_bot", "godot", 42))
        self.assertEqual(self.manifest["mesh"]["file"], "maintenance_bot.glb")
        self.assertEqual(self.out_a.triangle_count, self.manifest["mesh"]["triangles"])

    # --- size and budget --------------------------------------------------------------------
    def test_a_few_metres_across_within_the_triangle_budget(self) -> None:
        dims = self.manifest["dimensions_m"]
        for key in ("length", "width", "height"):
            self.assertGreater(dims[key], 2.0, key)
            self.assertLess(dims[key], 6.0, key)
        self.assertLessEqual(self.out_a.triangle_count, TRIANGLE_BUDGET)
        self.assertGreater(self.out_a.triangle_count, 500)

    def test_the_manifest_box_bounds_the_obj(self) -> None:
        np.testing.assert_allclose(self.obj.vertices.min(axis=0), self.manifest["aabb_min"], atol=1e-4)
        np.testing.assert_allclose(self.obj.vertices.max(axis=0), self.manifest["aabb_max"], atol=1e-4)

    # --- frame ------------------------------------------------------------------------------
    def test_it_is_centred_and_the_nose_is_minus_z(self) -> None:
        lo, hi = np.array(self.manifest["aabb_min"]), np.array(self.manifest["aabb_max"])
        np.testing.assert_allclose(lo + hi, [0.0, 0.0, 0.0], atol=0.05)  # the box is centred, the bot symmetric in x
        self.assertEqual(self.hp["nose"], [0.0, 0.0, -1.0])
        # The shells are the long part: the box is longest along z, so the nose can be told from the width.
        self.assertGreater(hi[2] - lo[2], hi[0] - lo[0])

    def test_the_bound_covers_every_vertex(self) -> None:
        radius = float(np.linalg.norm(self.obj.vertices, axis=1).max())
        self.assertAlmostEqual(self.hp["bound_radius_m"], radius, places=2)
        self.assertLess(radius, 4.0)

    def test_it_has_no_collision_and_the_lamps_are_listed(self) -> None:
        self.assertNotIn("collision", self.hp)  # ambient: it takes no hit (Q11)
        self.assertEqual(len(self.hp["lamps"]), 3)
        for lamp in self.hp["lamps"]:
            self.assertEqual(len(lamp), 3)

    # --- style and finish -------------------------------------------------------------------
    def test_the_style_is_metal_not_plastic(self) -> None:
        for role in REQUIRED_ROLES:
            self.assertIn(role, MAINTENANCE_BOT.materials)
        self.assertIn("metal_finish", MAINTENANCE_BOT.extra)
        for role in ("hull", "hull_panel", "hazard", "stripe"):
            self.assertGreaterEqual(MAINTENANCE_BOT.material(role).metallic, 0.4, role)

    def test_the_maps_carry_the_metal_finish(self) -> None:
        # ORM: R occlusion, G roughness, B metallic. Metal in the shells and truss, roughness that varies plate to plate.
        orm = _rgb(self.dir_a / "maintenance_bot_orm.png") / 255.0
        albedo = _rgb(self.dir_a / "maintenance_bot_albedo.png")
        filled = albedo.sum(axis=2) > 0
        self.assertGreater(float(orm[..., 2][filled].mean()), 0.3)
        self.assertGreater(float(orm[..., 1][filled].std()), 0.04)

    def test_the_lens_and_lamps_glow(self) -> None:
        emissive = _rgb(self.dir_a / "maintenance_bot_emissive.png")
        lit = emissive.sum(axis=2) > 60
        self.assertGreater(int(lit.sum()), 100)
        green = emissive[..., 1] > 1.5 * emissive[..., 0]
        self.assertGreater(int((lit & green).sum()), 10, "the sensor lens is green")

    # --- determinism ------------------------------------------------------------------------
    def test_two_builds_of_one_seed_are_byte_identical(self) -> None:
        for name in sorted(p.name for p in self.dir_a.iterdir()):
            if name.endswith(".png.import"):
                continue
            self.assertEqual(sha256(self.dir_a / name), sha256(self.dir_b / name), name)


if __name__ == "__main__":
    unittest.main()
