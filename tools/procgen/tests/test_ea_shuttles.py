"""``ea_shuttle`` and ``ea_atmo_shuttle`` (M10-T57): files, the mesh contract with both texture sets, budgets, sizes and frames,
outward faces, symmetry, chunk cuts, collision coverage, the hardpoint contract, the chosen looks and determinism.
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
from tools.procgen.core.budgets import LOW_SHRINK, low_set_mb, over_budget, texture_mb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.image import read_png
from tools.procgen.core.obj import read_obj
from tools.procgen.core.textured_mesh import TexturedPart, phase_steps
from tools.procgen.styles.ea_shuttle import ATMO_LOOK, SHUTTLE_LOOK
from tools.procgen.tests.mesh_checks import (
    TEST_OPTIONS,
    assert_chunks_cut_the_hull,
    assert_hull_mesh,
    assert_mirror_symmetric,
    glowing_points,
)

PILOT_TERMS = {
    "sway_left", "sway_right", "heave_up", "heave_down", "pitch_up", "pitch_down",
    "yaw_left", "yaw_right", "roll_left", "roll_right",
}  # fmt: skip
TEXEL_MAX_M = 0.04  # a small craft at the default 2 048 px atlas


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mirrored(v: list[float]) -> list[float]:
    return [-v[0], v[1], v[2]]


def inside_primitive(points: np.ndarray, c: dict, inflate: float) -> np.ndarray:
    basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
    local = (points - np.array(c["position"])) @ basis
    if c["type"] == "box":
        return np.all(np.abs(local) <= 0.5 * np.array(c["size"]) + inflate, axis=1)
    half = 0.5 * c["height"] - c["radius"]
    along = np.clip(local[:, 2], -half, half)
    axis_point = np.column_stack([np.zeros_like(along), np.zeros_like(along), along])
    return np.linalg.norm(local - axis_point, axis=1) <= c["radius"] + inflate


class ShuttleChecks:
    """The checks both shuttles share; a subclass names the craft and its expected numbers."""

    CRAFT: es.Craft
    BUILD = None
    LENGTH: float
    SPAN: float
    HEIGHT: float
    BAND_SRGB: int
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
        cls.spacing = float(cls.manifest["surface_spacing_m"])
        cls.pieces = cv.scaled_pieces(cls.CRAFT.assemble(cls.CRAFT.look.style), cls.CRAFT.scale)  # at the built size
        sampled = cv.sample_pieces(cls.pieces, BuildContext(cls.dir_a, seed=42), cls.spacing, buried_margin=es.BURIED_MARGIN_M * cls.CRAFT.scale)
        cls.xyz = np.concatenate([s.samples.positions for s in sampled]) - cls.offset  # the visible surface, body frame

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
        self.assertFalse([n for n in names if "turret" in n], "the shuttles carry no turret")
        for p in self.out_a.files:
            self.assertTrue(p.is_file(), p)

    def test_the_hull_is_its_textured_mesh_inside_the_budget(self) -> None:
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
        built = [TEST_OPTIONS["atlas_px"]]
        self.assertAlmostEqual(budget["texture_mb"], texture_mb(built), places=2, msg="the manifest records this build's")
        self.assertAlmostEqual(budget["texture_mb_low"], low_set_mb(built), places=2)

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
                "collision", "nav_lights", "turrets", "docking_ports", "chunks"}  # fmt: skip
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

    def test_the_body_origin_is_the_visible_surfaces_centroid(self) -> None:
        np.testing.assert_allclose(self.xyz.mean(axis=0)[1:], 0.0, atol=1e-3)

    def test_collision_primitives_cover_the_visible_surface_and_stay_close(self) -> None:
        inside = np.zeros(len(self.xyz), dtype=bool)
        for c in self.hp["collision"]:
            inside |= inside_primitive(self.xyz, c, inflate=self.spacing)
        missed = self.xyz[~inside] + self.offset
        self.assertTrue(bool(inside.all()), f"every visible surface sample; missed (authored frame): {np.round(missed[:10], 2).tolist()}")
        lo, hi = self.xyz.min(axis=0), self.xyz.max(axis=0)
        for c in self.hp["collision"]:
            basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
            np.testing.assert_allclose(basis.T @ basis, np.eye(3), atol=1e-4, err_msg=c["name"])
            self.assertAlmostEqual(float(np.linalg.det(basis)), 1.0, places=3, msg=c["name"])
            if c["type"] == "box":
                corners = np.array([[a, b, d] for a in (-1, 1) for b in (-1, 1) for d in (-1, 1)]) * 0.5 * np.array(c["size"])
                extent = corners @ basis.T + np.array(c["position"])
            else:
                half = 0.5 * c["height"] - c["radius"]
                ends = np.array([[0, 0, -half], [0, 0, half]]) @ basis.T + np.array(c["position"])
                extent = np.concatenate([ends - c["radius"], ends + c["radius"]])
            self.assertTrue(np.all(extent.min(axis=0) >= lo - 0.5) and np.all(extent.max(axis=0) <= hi + 0.5), c["name"])

    def test_collision_is_mirror_symmetric(self) -> None:
        shapes = {c["name"]: c for c in self.hp["collision"]}
        self.assertEqual(len(shapes), len(self.hp["collision"]), "unique names")
        for name, c in shapes.items():
            part = name.split("_")
            side = next((k for k, w in enumerate(part) if w in ("r", "l")), None)
            if side is None:
                if not name.startswith(self.ASYMMETRIC):
                    self.assertAlmostEqual(c["position"][0], 0.0, places=4, msg=name)
            elif part[side] == "r":
                twin = shapes["_".join(part[:side] + ["l"] + part[side + 1 :])]
                np.testing.assert_allclose(twin["position"], mirrored(c["position"]), atol=1e-4, err_msg=name)
                np.testing.assert_allclose(sorted(twin.get("size", [0.0])), sorted(c.get("size", [0.0])), atol=1e-4, err_msg=name)

    # --- looks, determinism, options -----------------------------------------------------------------------------------------
    def test_the_look_carries_the_chosen_band(self) -> None:
        look = self.CRAFT.look
        self.assertIn(self.BAND_SRGB, [colour for _, _, colour in look.bands])
        self.assertEqual(look.style.name, self.asset_id)
        lead = int(np.argmax([(self.BAND_SRGB >> shift) & 255 for shift in (16, 8, 0)]))
        albedo = read_png(self.dir_a / self.manifest["mesh"]["surfaces"][0]["albedo"])[..., :3].astype(int)
        others = np.delete(albedo, lead, axis=2).max(axis=2)
        painted = float(np.mean(albedo[..., lead] > others + 30))
        self.assertGreater(painted, 0.002, "the band's colour is on the atlas; the plating is grey")

    def test_a_different_seed_changes_the_wear_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = self.BUILD(BuildContext(Path(tmp), seed=7, options=TEST_OPTIONS))
            albedo = self.manifest["mesh"]["surfaces"][0]["albedo"]
            self.assertNotEqual(sha256(Path(tmp) / albedo), sha256(self.dir_a / albedo))
            self.assertEqual(other.manifest["dimensions_m"], self.manifest["dimensions_m"])
            self.assertEqual(other.manifest["mesh"]["triangles"], self.manifest["mesh"]["triangles"])
            hp = json.loads((Path(tmp) / es.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            self.assertEqual([c["name"] for c in hp["collision"]], [c["name"] for c in self.hp["collision"]])

    def test_same_seed_gives_byte_identical_output(self) -> None:
        for out in self.out_a.files:
            self.assertEqual(sha256(out), sha256(self.dir_b / out.name), out.name)

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for bad in (0.0, -1.0):
                with self.assertRaises(ValueError):
                    self.BUILD(BuildContext(Path(tmp), options={"spacing": bad}))


class EaShuttleTests(ShuttleChecks, unittest.TestCase):
    CRAFT = es.SHUTTLE
    BUILD = staticmethod(es.build_shuttle)
    K = 38.0 / 18.64  # Q65's length over T01's
    LENGTH, SPAN, HEIGHT = 38.0, 9.21 * K, 5.27 * K  # Q65's length and the reference's box at it
    CHUNKS = ("bow", "cabin", "stern")
    THRUST_Y = -0.31 * K  # the hull's centre line under the box centre
    ASYMMETRIC = ("nose_blocks",)
    BAND_SRGB = 0x2E8B4E  # the maintainer's choice (2026-11-20): worn dark grey, green band, number 03

    def test_the_shuttle_is_number_03(self) -> None:
        self.assertIs(self.CRAFT.look, SHUTTLE_LOOK)
        self.assertEqual(SHUTTLE_LOOK.number, "03")

    def test_the_stern_hatch_is_the_docking_port(self) -> None:
        (port,) = self.hp["docking_ports"]
        self.assertEqual((port["name"], port["out"], port["up"]), ("stern_hatch", [0.0, 0.0, 1.0], [0.0, 1.0, 0.0]))
        at = self.authored(port["position"])
        np.testing.assert_allclose(at[:2], [0.0, self.THRUST_Y], atol=1e-4)
        self.assertGreater(at[2], 18.0 * self.K)
        self.assertLessEqual(at[2], self.LENGTH)

    def test_the_bow_carries_the_reference_off_centre_blocks(self) -> None:
        block = next(p for p in self.pieces if p.name == "nose_blocks").part.mesh.vertices
        self.assertAlmostEqual(float(block[:, 2].min()), 0.0, places=6, msg="the docking block leads the nose")
        self.assertLess(float(block[block[:, 2] < 1e-6][:, 0].mean()), 0.0, "to port")


class EaAtmoShuttleTests(ShuttleChecks, unittest.TestCase):
    CRAFT = es.ATMO
    BUILD = staticmethod(es.build_atmo)
    K = 29.0 / 25.59  # Q65's length over T01's
    LENGTH, SPAN, HEIGHT = 29.0, 45.56 * K, 8.56 * K  # Q65's length and the reference's box at it
    CHUNKS = ("body", "wing_l", "wing_r", "tail", "engines")
    THRUST_Y = -0.47 * K  # the three nacelles' axes
    BAND_SRGB = 0xA8322C  # the maintainer's choice (2026-11-20): fleet grey, one red band

    def test_the_atmospheric_shuttle_has_no_docking_port(self) -> None:
        self.assertIs(self.CRAFT.look, ATMO_LOOK)
        self.assertEqual(self.hp["docking_ports"], [])

    def test_three_engines_the_centre_one_as_two_pods(self) -> None:
        mains = {pod["name"]: self.authored(pod["main"]["position"]) for pod in self.hp["pods"]}
        self.assertEqual(set(mains), {"l", "cl", "cr", "r"})
        self.assertAlmostEqual(mains["r"][0], 4.43 * self.K, places=2)
        self.assertAlmostEqual(mains["cl"][0], -mains["cr"][0], places=5)
        self.assertLess(abs(mains["cr"][0]), 0.6 * self.K, "inside the centre nozzle")

    def test_the_wings_sweep_back_and_rise_to_the_tips(self) -> None:
        port, starboard = (self.authored(self.hp["nav_lights"][k]) for k in ("port", "starboard"))
        self.assertGreater(starboard[0], 22.0 * self.K)
        self.assertGreater(starboard[1], 3.0 * self.K, "dihedral")
        self.assertGreater(starboard[2], 23.0 * self.K, "sweep")
        self.assertAlmostEqual(port[0], -starboard[0], places=4)


if __name__ == "__main__":
    unittest.main()
