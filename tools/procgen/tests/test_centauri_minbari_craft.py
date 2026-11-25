"""``centauri_shuttle`` and ``minbari_flyer`` (M10-T58, stage 1): files, the mesh contract with both texture sets, the small-craft
budget, sizes and frames, outward faces, symmetry, chunk cuts, the hardpoint contract, the three looks and determinism.
The expected numbers are typed in from docs/design-references.md ("Centauri shuttle", "Minbari Flyer") and M10 Q67, not read
from the generators.
"""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import centauri_shuttle as cs
from tools.procgen.assets import ea_shuttles as es
from tools.procgen.assets import minbari_flyer as mf
from tools.procgen.core import civilian as cv
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.budgets import LOW_SHRINK, low_set_mb, over_budget, texture_mb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.image import read_png
from tools.procgen.core.obj import read_obj
from tools.procgen.core.seams import Hexes, PatchPlates
from tools.procgen.core.textured_mesh import TexturedPart, phase_steps
from tools.procgen.styles import centauri_shuttle as cs_style
from tools.procgen.styles import minbari_flyer as mf_style
from tools.procgen.tests.mesh_checks import TEST_OPTIONS, assert_chunks_cut_the_hull, assert_hull_mesh, assert_mirror_symmetric, glowing_points

TEXEL_MAX_M = 0.04  # a small craft at the default 2 048 px atlas


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mirrored(v: list[float]) -> list[float]:
    return [-v[0], v[1], v[2]]


class CraftChecks:
    """The checks both craft share; a subclass names the craft and its expected numbers."""

    CRAFT: es.Craft
    BUILD = None
    LOOKS = None
    LENGTH: float
    SPAN: float
    HEIGHT: float
    CHUNKS: tuple[str, ...]
    THRUST_Y: float

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = cls.BUILD(BuildContext(cls.dir_a, seed=42, options=TEST_OPTIONS))
        cls.out_b = cls.BUILD(BuildContext(cls.dir_b, seed=42, options=TEST_OPTIONS))
        cls.asset_id = cls.CRAFT.asset_id
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.hp = json.loads((cls.dir_a / es.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / f"{cls.asset_id}.obj")
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.pieces = cls.CRAFT.assemble(cls.CRAFT.look.style)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def authored(self, v: list[float]) -> np.ndarray:
        """A hardpoint back in the design references' frame (the nose at z = 0, x and y from the box centre)."""
        return np.array(v) + self.offset

    # --- files, manifest, budgets ------------------------------------------------------------------------------------
    def test_registered_and_named(self) -> None:
        self.assertIs(ASSETS[self.asset_id], self.BUILD)
        self.assertEqual(self.out_a.asset_id, self.asset_id)
        self.assertEqual(self.out_a.warnings, ())

    def test_all_files_are_written_and_listed(self) -> None:
        names = {p.name for p in self.out_a.files}
        stem = self.asset_id
        expected = {"hardpoints.json", "manifest.json", f"{stem}.glb", f"{stem}.obj"}
        expected |= {f"{stem}_{k}.png" for k in ("albedo", "normal", "orm", "emissive")}
        expected |= {f"{stem}_{k}_low.png" for k in ("albedo", "normal", "orm", "emissive")}
        expected |= {f"{stem}_chunk_{c}.{ext}" for c in self.CHUNKS for ext in ("obj", "glb")}
        self.assertTrue(expected <= names, sorted(expected - names))
        self.assertFalse([n for n in names if "turret" in n], "unarmed")
        for p in self.out_a.files:
            self.assertTrue(p.is_file(), p)

    def test_the_hull_is_its_textured_mesh(self) -> None:
        assert_hull_mesh(self, self.dir_a, self.manifest, f"{self.asset_id}.obj")
        self.assertEqual((self.manifest["asset_id"], self.manifest["frame"], self.manifest["seed"]), (self.asset_id, "godot", 42))

    def test_the_low_texture_set_is_a_mip_level_down(self) -> None:
        surface = self.manifest["mesh"]["surfaces"][0]
        low = surface["detail"]["low"]
        self.assertEqual(low, {k: f"{self.asset_id}_{k}_low.png" for k in ("albedo", "normal", "orm", "emissive")})
        for key, file in low.items():
            high = read_png(self.dir_a / surface[key])
            self.assertEqual(read_png(self.dir_a / file).shape[:2], (high.shape[0] // LOW_SHRINK, high.shape[1] // LOW_SHRINK), key)

    def test_the_hull_is_inside_the_small_craft_budget(self) -> None:
        budget = self.manifest["budget"]
        self.assertEqual((budget["class"], budget["triangles"]), ("small_craft", self.manifest["mesh"]["triangles"]))
        atlas = [cv.HULL_ATLAS_PX]  # the default build's one atlas; the test build's is smaller
        self.assertEqual(over_budget("small_craft", budget["triangles"], texture_mb(atlas), low_set_mb(atlas)), [])

    def test_the_default_atlas_lands_under_four_centimetres_a_texel(self) -> None:
        parts = [TexturedPart(p.part.mesh, phase_steps(p.name, False), (), p.name) for p in cv.with_twins(self.pieces)]
        self.assertLess(cv.texel_of(parts, cv.HULL_ATLAS_PX), TEXEL_MAX_M)

    # --- size, frame, shape ----------------------------------------------------------------------------------------------
    def test_dimensions_match_the_reference(self) -> None:
        dims = self.manifest["dimensions_m"]
        self.assertAlmostEqual(dims["length"], self.LENGTH, delta=0.02)
        self.assertAlmostEqual(dims["span"], self.SPAN, delta=0.02 * self.SPAN)
        self.assertAlmostEqual(dims["height"], self.HEIGHT, delta=0.03 * self.HEIGHT)
        self.assertEqual((self.hp["length_m"], self.hp["span_m"], self.hp["height_m"]), (dims["length"], dims["span"], dims["height"]))

    def test_the_authored_frame_is_the_references(self) -> None:
        lo = np.array(self.manifest["aabb_min"]) + self.offset
        hi = np.array(self.manifest["aabb_max"]) + self.offset
        self.assertAlmostEqual(lo[2], 0.0, delta=0.01, msg="the nose at z = 0")
        self.assertAlmostEqual(hi[2], self.LENGTH, delta=0.02)
        self.assertAlmostEqual(lo[0] + hi[0], 0.0, delta=0.01, msg="x centred")
        self.assertAlmostEqual(lo[1] + hi[1], 0.0, delta=0.03 * self.HEIGHT, msg="y centred on the reference's box")
        self.assertAlmostEqual(self.offset[0], 0.0, places=6)

    def test_every_closed_piece_faces_outward(self) -> None:
        for p in self.pieces:
            a, b, c = p.part.mesh.corners()
            volume = float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum()) / 6.0
            self.assertGreater(volume, 0.0, p.name)

    def test_the_mesh_is_mirror_symmetric_in_x(self) -> None:
        assert_mirror_symmetric(self, np.concatenate([p.part.mesh.vertices for p in cv.with_twins(self.pieces)]), "hull")

    def test_the_cockpit_is_forward_and_the_engines_aft(self) -> None:
        eye = self.authored(self.hp["cockpit_camera"]["position"])
        self.assertLess(eye[2], 0.25 * self.LENGTH)
        for pod in self.hp["pods"]:
            self.assertGreater(self.authored(pod["main"]["position"])[2], 0.8 * self.LENGTH, pod["name"])

    def test_the_drives_and_nothing_else_glow(self) -> None:
        glow = glowing_points(self.dir_a, self.manifest["mesh"]) + self.offset
        self.assertGreater(len(glow), 0)
        self.assertTrue(bool(np.all(glow[:, 2] > 0.8 * self.LENGTH)), "the glow is at the stern")

    # --- chunks and hardpoints ---------------------------------------------------------------------------------------------
    def test_chunks_cut_the_hull_and_have_joints(self) -> None:
        assert_chunks_cut_the_hull(self, self.dir_a, self.manifest, self.hp, self.CHUNKS)

    def test_pods_on_both_sides_fire_aft_on_the_thrust_line(self) -> None:
        by_name = {pod["name"]: pod for pod in self.hp["pods"]}
        self.assertEqual(set(by_name), {"l", "r"})
        for pod in self.hp["pods"]:
            main = self.authored(pod["main"]["position"])
            self.assertEqual(pod["main"]["exhaust"], [0.0, 0.0, 1.0], pod["name"])
            self.assertAlmostEqual(main[1], self.THRUST_Y, places=4, msg=pod["name"])
            self.assertEqual(pod["side"], "left" if main[0] < 0.0 else "right", pod["name"])
        np.testing.assert_allclose(by_name["l"]["main"]["position"], mirrored(by_name["r"]["main"]["position"]), atol=1e-4)

    def test_hardpoints_are_unarmed_and_mirror(self) -> None:
        self.assertEqual((self.hp["muzzles"], self.hp["turrets"]), ([], []))
        ports = {port["name"]: port for port in self.hp["rcs"]}
        self.assertEqual(len(ports), len(self.hp["rcs"]), "unique names")
        for name, port in ports.items():
            self.assertTrue(port["tags"], name)
            if name.startswith("r_"):
                np.testing.assert_allclose(ports["l_" + name[2:]]["position"], mirrored(port["position"]), atol=1e-4, err_msg=name)
        lights = self.hp["nav_lights"]
        np.testing.assert_allclose(lights["port"], mirrored(lights["starboard"]), atol=1e-4)
        self.assertGreater(lights["top_lamp"][1], lights["top"][1])

    # --- looks, determinism ---------------------------------------------------------------------------------------------------
    def test_three_looks_with_their_own_styles(self) -> None:
        looks = self.LOOKS()
        self.assertEqual(tuple(looks), ("a", "b", "c"))
        self.assertEqual(len({look.style.name for look in looks.values()}), 3)
        self.assertIs(type(self.CRAFT.look), type(looks["a"]))

    def test_another_look_repaints_the_same_hull(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            self.BUILD(BuildContext(Path(tmp), seed=42, options={**TEST_OPTIONS, "look": "b"}))
            albedo = self.manifest["mesh"]["surfaces"][0]["albedo"]
            self.assertNotEqual(sha256(Path(tmp) / albedo), sha256(self.dir_a / albedo))
            np.testing.assert_array_equal(read_obj(Path(tmp) / f"{self.asset_id}.obj").vertices, self.obj.vertices)
            self.assertEqual(sha256(Path(tmp) / es.HARDPOINTS_NAME), sha256(self.dir_a / es.HARDPOINTS_NAME))

    def test_same_seed_gives_byte_identical_output(self) -> None:
        for out in self.out_a.files:
            self.assertEqual(sha256(out), sha256(self.dir_b / out.name), out.name)

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                self.BUILD(BuildContext(Path(tmp), options={"look": "z"}))
            with self.assertRaises(ValueError):
                self.BUILD(BuildContext(Path(tmp), options={"spacing": 0.0}))


class CentauriShuttleTests(CraftChecks, unittest.TestCase):
    CRAFT = cs.CRAFT
    BUILD = staticmethod(cs.build)
    LOOKS = staticmethod(cs_style.looks)
    LENGTH, SPAN, HEIGHT = 36.0, 51.97, 13.51  # T01's length and the reference's box at it
    CHUNKS = ("body", "stern", "wing_l", "wing_r")
    THRUST_Y = -2.28  # the nozzles' axes

    def test_the_skin_is_darker_patches_not_a_mosaic(self) -> None:
        """Q83: solid paint with patches a few shades darker, at a few sizes; no seam lines."""
        dressed, marks = cs.dress(self.pieces, self.CRAFT.look)
        for p in dressed:
            features = p.part.seams.features()
            self.assertTrue(features, p.name)
            self.assertTrue(all(isinstance(f, PatchPlates) for f in features), p.name)
            self.assertGreaterEqual(len({f.cell for f in features}), 2, p.name)
            for f in features:
                self.assertTrue(all(0.0 < dark <= 0.3 for _, dark in f.tiers), p.name)
        self.assertEqual(marks, {})

    def test_the_wings_rise_to_the_tips(self) -> None:
        starboard = self.authored(self.hp["nav_lights"]["starboard"])
        self.assertGreater(starboard[0], 25.0)
        self.assertGreater(starboard[1], 5.0, "the tips stand high over the body")

    def test_the_looks_are_purple(self) -> None:
        for look in cs_style.looks().values():
            r, g, b = look.style.material("hull").albedo[:3]
            self.assertTrue(r > g and b > g, look.name)


class MinbariFlyerTests(CraftChecks, unittest.TestCase):
    CRAFT = mf.CRAFT
    BUILD = staticmethod(mf.build)
    LOOKS = staticmethod(mf_style.looks)
    LENGTH, SPAN, HEIGHT = 40.0, 18.48, 8.2  # Q67's length and the reference's box at it
    CHUNKS = ("body", "bow", "tail", "crossbar", "spindle_l", "spindle_r")
    THRUST_Y = 0.0  # the spindles' axes

    def test_the_skin_is_the_hexagonal_grid(self) -> None:
        """Q45: hexagons on every piece, their shades in the low set."""
        dressed, marks = mf.dress(self.pieces, self.CRAFT.look)
        for p in dressed:
            features = p.part.seams.features()
            self.assertTrue(features and all(isinstance(f, Hexes) for f in features), p.name)
            self.assertIn(1, {f.level for f in features}, p.name)
        self.assertTrue(all(len(m) == len(self.CRAFT.look.streaks) for m in marks.values()))

    def test_the_crossbar_carries_a_spindle_at_each_tip(self) -> None:
        starboard = self.authored(self.hp["nav_lights"]["starboard"])
        self.assertGreater(starboard[0], 9.0)
        self.assertTrue(0.7 * self.LENGTH < starboard[2] < 0.9 * self.LENGTH)


if __name__ == "__main__":
    unittest.main()
