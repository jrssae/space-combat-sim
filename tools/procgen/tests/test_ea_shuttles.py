"""``ea_shuttle`` and ``ea_atmo_shuttle`` (M10-T57): files, the mesh contract with both texture sets, budgets, sizes and frames,
outward faces, symmetry, chunk cuts, the hardpoint contract, the three looks and determinism.
The expected numbers are typed in from docs/design-references.md ("EA shuttle", "EA atmospheric shuttle") and
docs/assets-capital.md ("M10 lengths (T01)"), not read from the generators.
"""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import ea_shuttles as es
from tools.procgen.core import civilian as cv
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.obj import read_obj
from tools.procgen.core.textured_mesh import TexturedPart, phase_steps
from tools.procgen.styles.ea_shuttle import DEFAULT_OPTION, OPTIONS, atmo_looks, shuttle_looks
from tools.procgen.tests.mesh_checks import TEST_OPTIONS, assert_chunks_cut_the_hull, assert_hull_mesh, assert_mirror_symmetric, glowing_points

PILOT_TERMS = {
    "sway_left", "sway_right", "heave_up", "heave_down", "pitch_up", "pitch_down",
    "yaw_left", "yaw_right", "roll_left", "roll_right",
}  # fmt: skip
TEXEL_MAX_M = 0.04  # a small craft at the default 2 048 px atlas


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mirrored(v: list[float]) -> list[float]:
    return [-v[0], v[1], v[2]]


class ShuttleChecks:
    """The checks both shuttles share; a subclass names the craft and its expected numbers."""

    CRAFT: es.Craft
    BUILD = None
    LENGTH: float
    SPAN: float
    HEIGHT: float
    TRIANGLE_BUDGET: int
    CHUNKS: tuple[str, ...]
    THRUST_Y: float
    ASYMMETRIC: tuple[str, ...] = ()  # pieces the reference has off centre

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
        cls.pieces = cls.CRAFT.assemble(cls.CRAFT.looks()[DEFAULT_OPTION].style)

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
        expected |= {f"{stem}_{k}_low.png" for k in ("albedo", "normal", "orm")}
        expected |= {f"{stem}_chunk_{c}.{ext}" for c in self.CHUNKS for ext in ("obj", "glb")}
        self.assertTrue(expected <= names, sorted(expected - names))
        self.assertFalse([n for n in names if "turret" in n], "the shuttles carry no turret")
        for p in self.out_a.files:
            self.assertTrue(p.is_file(), p)

    def test_the_hull_is_its_textured_mesh_inside_the_budget(self) -> None:
        assert_hull_mesh(self, self.dir_a, self.manifest, f"{self.asset_id}.obj")
        self.assertLessEqual(self.manifest["mesh"]["triangles"], self.TRIANGLE_BUDGET)
        self.assertEqual((self.manifest["asset_id"], self.manifest["frame"], self.manifest["seed"]), (self.asset_id, "godot", 42))

    def test_the_manifest_names_a_low_texture_set(self) -> None:
        low = self.manifest["mesh"]["surfaces"][0]["detail"]["low"]
        self.assertEqual(low, {k: f"{self.asset_id}_{k}_low.png" for k in ("albedo", "normal", "orm")})

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
        keep = [p.part.mesh.vertices for p in cv.with_twins(self.pieces) if p.name not in self.ASYMMETRIC]
        assert_mirror_symmetric(self, np.concatenate(keep), "hull")

    def test_the_cockpit_is_forward_and_the_engines_aft(self) -> None:
        eye = self.authored(self.hp["cockpit_camera"]["position"])
        self.assertLess(eye[2], 0.2 * self.LENGTH)
        self.assertEqual(self.hp["cockpit_camera"]["forward"], [0.0, 0.0, -1.0])
        for pod in self.hp["pods"]:
            self.assertGreater(self.authored(pod["main"]["position"])[2], 0.8 * self.LENGTH, pod["name"])

    def test_the_engines_and_nothing_else_glow(self) -> None:
        glow = glowing_points(self.dir_a, self.manifest["mesh"]) + self.offset
        self.assertGreater(len(glow), 0)
        self.assertTrue(bool(np.all(glow[:, 2] > 0.8 * self.LENGTH)), "the glow is at the stern")

    # --- chunks and hardpoints ---------------------------------------------------------------------------------------------
    def test_chunks_cut_the_hull_and_have_joints(self) -> None:
        assert_chunks_cut_the_hull(self, self.dir_a, self.manifest, self.hp, self.CHUNKS)
        lo, hi = np.array(self.manifest["aabb_min"]), np.array(self.manifest["aabb_max"])
        for entry in self.hp["chunks"]:
            joint = np.array(entry["joint"])
            self.assertTrue(np.all(joint >= lo) and np.all(joint <= hi), entry["name"])

    def test_hardpoints_schema(self) -> None:
        keys = {"asset_id", "generator_version", "frame", "units", "length_m", "span_m", "height_m", "mass_kg",
                "inertia_estimate_kg_m2", "center_of_mass", "cockpit_camera", "chase_anchor", "muzzles", "pods", "rcs",
                "collision", "nav_lights", "turrets", "chunks"}  # fmt: skip
        self.assertEqual(set(self.hp), keys)
        self.assertEqual((self.hp["muzzles"], self.hp["turrets"]), ([], []), "unarmed")
        self.assertGreater(self.hp["mass_kg"], 0.0)

    def test_pods_on_both_sides_fire_aft_on_the_thrust_line(self) -> None:
        sides = [pod["side"] for pod in self.hp["pods"]]
        self.assertIn("left", sides)
        self.assertIn("right", sides)
        by_name = {pod["name"]: pod for pod in self.hp["pods"]}
        for pod in self.hp["pods"]:
            main = self.authored(pod["main"]["position"])
            self.assertEqual(pod["main"]["exhaust"], [0.0, 0.0, 1.0], pod["name"])
            self.assertEqual(pod["retro"]["exhaust"], [0.0, 0.0, -1.0], pod["name"])
            self.assertAlmostEqual(main[1], self.THRUST_Y, places=4, msg=pod["name"])
            self.assertEqual(pod["side"], "left" if main[0] < 0.0 else "right", pod["name"])
            self.assertLess(self.authored(pod["retro"]["position"])[2], 0.1 * self.LENGTH, pod["name"])
        np.testing.assert_allclose(by_name["l"]["main"]["position"], mirrored(by_name["r"]["main"]["position"]), atol=1e-4)

    def test_the_centre_of_mass_is_on_the_thrust_line(self) -> None:
        com = self.authored(self.hp["center_of_mass"])
        self.assertAlmostEqual(com[0], 0.0, places=5)
        self.assertAlmostEqual(com[1], self.THRUST_Y, places=4)
        self.assertTrue(0.3 * self.LENGTH < com[2] < 0.8 * self.LENGTH, com)

    def test_cosmetic_rcs_ports_carry_pilot_terms_and_mirror(self) -> None:
        ports = {port["name"]: port for port in self.hp["rcs"]}
        self.assertEqual(len(ports), len(self.hp["rcs"]), "unique names")
        for name, port in ports.items():
            self.assertTrue(port["tags"], name)
            self.assertTrue(set(port["tags"]) <= PILOT_TERMS, name)
            self.assertAlmostEqual(float(np.linalg.norm(port["exhaust"])), 1.0, places=4, msg=name)
            if name.startswith("r_"):
                twin = ports["l_" + name[2:]]
                np.testing.assert_allclose(twin["position"], mirrored(port["position"]), atol=1e-4, err_msg=name)
                np.testing.assert_allclose(twin["exhaust"], mirrored(port["exhaust"]), atol=1e-4, err_msg=name)

    def test_nav_lights_port_on_the_left_and_the_lamp_on_top(self) -> None:
        lights = self.hp["nav_lights"]
        np.testing.assert_allclose(lights["port"], mirrored(lights["starboard"]), atol=1e-4)
        self.assertLess(lights["port"][0], 0.0)
        self.assertGreater(lights["top_lamp"][1], lights["top"][1])
        self.assertGreater(lights["top"][1], 0.0)
        self.assertGreater(lights["top_lamp_range_m"], 0.0)
        self.assertGreater(lights["cabin_range_m"], 0.0)
        self.assertEqual(lights["cabin"], self.hp["cockpit_camera"]["position"])

    def test_collision_primitives_are_proper_and_named_once(self) -> None:
        names = [c["name"] for c in self.hp["collision"]]
        self.assertEqual(len(names), len(set(names)))
        self.assertGreater(len(names), 4)
        for c in self.hp["collision"]:
            basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
            np.testing.assert_allclose(basis.T @ basis, np.eye(3), atol=1e-4, err_msg=c["name"])
            self.assertAlmostEqual(float(np.linalg.det(basis)), 1.0, places=3, msg=c["name"])

    # --- looks, determinism, options -----------------------------------------------------------------------------------------
    def test_three_looks_and_the_default_is_built(self) -> None:
        looks = self.CRAFT.looks()
        self.assertEqual(tuple(looks), OPTIONS)
        self.assertEqual(self.manifest["look"], DEFAULT_OPTION)
        self.assertEqual(len({look.style.name for look in looks.values()}), 3)

    def test_another_look_repaints_the_same_hull(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = self.BUILD(BuildContext(Path(tmp), seed=42, options={**TEST_OPTIONS, "look": "b"}))
            albedo = self.manifest["mesh"]["surfaces"][0]["albedo"]
            self.assertEqual(other.manifest["look"], "b")
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


class EaShuttleTests(ShuttleChecks, unittest.TestCase):
    CRAFT = es.SHUTTLE
    BUILD = staticmethod(es.build_shuttle)
    LENGTH, SPAN, HEIGHT = 18.64, 9.21, 5.27  # T01's length and the reference's box at it
    TRIANGLE_BUDGET = 6_000  # 1 456 as built
    CHUNKS = ("bow", "cabin", "stern")
    THRUST_Y = -0.31  # the hull's centre line under the box centre
    ASYMMETRIC = ("nose_blocks",)

    def test_the_looks_wear_their_bands(self) -> None:
        looks = shuttle_looks()
        self.assertEqual([look.number for look in looks.values()], ["25", "18", "03"])
        self.assertEqual(len({look.bands[0][2] for look in looks.values()}), 3)

    def test_the_bow_carries_the_reference_off_centre_blocks(self) -> None:
        block = next(p for p in self.pieces if p.name == "nose_blocks").part.mesh.vertices
        self.assertAlmostEqual(float(block[:, 2].min()), 0.0, places=6, msg="the docking block leads the nose")
        self.assertLess(float(block[block[:, 2] < 1e-6][:, 0].mean()), 0.0, "to port")


class EaAtmoShuttleTests(ShuttleChecks, unittest.TestCase):
    CRAFT = es.ATMO
    BUILD = staticmethod(es.build_atmo)
    LENGTH, SPAN, HEIGHT = 25.59, 45.56, 8.56  # T01's length and the reference's box at it
    TRIANGLE_BUDGET = 10_000  # 3 074 as built
    CHUNKS = ("body", "wing_l", "wing_r", "tail", "engines")
    THRUST_Y = -0.47  # the three nacelles' axes

    def test_three_engines_the_centre_one_as_two_pods(self) -> None:
        mains = {pod["name"]: self.authored(pod["main"]["position"]) for pod in self.hp["pods"]}
        self.assertEqual(set(mains), {"l", "cl", "cr", "r"})
        self.assertAlmostEqual(mains["r"][0], 4.43, places=3)
        self.assertAlmostEqual(mains["cl"][0], -mains["cr"][0], places=5)
        self.assertLess(abs(mains["cr"][0]), 0.6, "inside the centre nozzle")

    def test_the_wings_sweep_back_and_rise_to_the_tips(self) -> None:
        port, starboard = (self.authored(self.hp["nav_lights"][k]) for k in ("port", "starboard"))
        self.assertGreater(starboard[0], 22.0)
        self.assertGreater(starboard[1], 3.0, "dihedral")
        self.assertGreater(starboard[2], 23.0, "sweep")
        self.assertAlmostEqual(port[0], -starboard[0], places=4)

    def test_the_camouflage_look_paints_the_tail_its_own_colour(self) -> None:
        look = atmo_looks()["b"]
        self.assertEqual(len(look.camo), 2)
        self.assertIsNotNone(look.tail)
        _, marks = es.dress_atmo(self.pieces, look)
        self.assertEqual({m.kind for m in marks["fin"]}, {"paint", "rect"})
        self.assertEqual(len([m for m in marks["body"] if m.kind == "paint"]), 2)


if __name__ == "__main__":
    unittest.main()
