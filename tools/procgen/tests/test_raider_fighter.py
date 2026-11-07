"""``raider_fighter`` (AC4): files, frames, chunks, hardpoints contract, collision coverage, determinism."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import raider_fighter as raider
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.obj import read_obj
from tools.procgen.styles.raider import RAIDER

SPEC = raider.DEFAULT_SPEC
PILOT_TERMS = {
    "sway_left", "sway_right", "heave_up", "heave_down", "pitch_up", "pitch_down",
    "yaw_left", "yaw_right", "roll_left", "roll_right",
}  # fmt: skip
SYM_TOL = 1e-6


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inside_primitive(points: np.ndarray, c: dict, inflate: float) -> np.ndarray:
    basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
    local = (points - np.array(c["position"])) @ basis
    if c["type"] == "box":
        return np.all(np.abs(local) <= 0.5 * np.array(c["size"]) + inflate, axis=1)
    half = 0.5 * c["height"] - c["radius"]
    along = np.clip(local[:, 2], -half, half)
    axis_point = np.column_stack([np.zeros_like(along), np.zeros_like(along), along])
    return np.linalg.norm(local - axis_point, axis=1) <= c["radius"] + inflate


class RaiderFighterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = raider.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = raider.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.placed, _ = raider.centre(raider.build_parts(SPEC, RAIDER, BuildContext(cls.dir_a, seed=42), raider.DEFAULT_SPACING_M))
        cls.godot_xyz = np.concatenate([p.samples.positions for p in cls.placed if p.samples is not None])  # the hardpoints frame
        cls.hp = json.loads((cls.dir_a / raider.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / raider.OBJ_NAME)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    # --- files, manifest --------------------------------------------------------------------------------
    def test_all_files_are_written_and_listed(self) -> None:
        expected = {raider.OBJ_NAME, "raider_fighter.mtl", raider.HARDPOINTS_NAME, "manifest.json", raider.MESH_NAME}
        expected |= {f"raider_fighter_{k}.png{ext}" for k in ("albedo", "emissive", "normal", "orm") for ext in ("", ".import")}  # M4-T30d
        for entry in self.hp["chunks"]:
            expected |= {entry["obj"], entry["obj"].replace(".obj", ".mtl"), entry["mesh"]}
        self.assertEqual({p.name for p in self.dir_a.iterdir()}, expected)
        self.assertEqual({p.name for p in self.out_a.files}, expected)

    def test_the_manifest_names_the_textured_mesh(self) -> None:
        self.assertEqual(self.out_a.warnings, ())
        self.assertEqual(self.manifest["files"], {"obj": raider.OBJ_NAME, "mesh": raider.MESH_NAME, "hardpoints": raider.HARDPOINTS_NAME})
        self.assertEqual(self.manifest["chunks"], list(raider.CHUNK_ORDER))
        self.assertEqual(self.out_a.triangle_count, self.manifest["mesh"]["triangles"])

    def test_dimensions_match_the_design(self) -> None:
        self.assertAlmostEqual(self.hp["span_m"], 2.0 * SPEC.wing.half_span, places=3)
        self.assertAlmostEqual(self.hp["length_m"], SPEC.nacelle_z + SPEC.nacelle.total_length, places=3)
        self.assertEqual(self.manifest["dimensions_m"]["span"], self.hp["span_m"])
        self.assertGreater(self.hp["span_m"] / self.hp["length_m"], 2.0, "a flying wing: the span is more than twice the length")

    # --- frames, symmetry --------------------------------------------------------------------------------
    def test_the_samples_are_centred_and_the_aabb_is_the_hulls(self) -> None:
        np.testing.assert_allclose(self.godot_xyz.mean(axis=0), [0.0, 0.0, 0.0], atol=1e-3)
        np.testing.assert_allclose(self.obj.vertices.min(axis=0), self.manifest["aabb_min"], atol=2e-4)
        np.testing.assert_allclose(self.obj.vertices.max(axis=0), self.manifest["aabb_max"], atol=2e-4)

    def test_sample_positions_are_exactly_mirror_symmetric_in_x(self) -> None:
        xyz = self.godot_xyz
        mirrored = xyz * np.array([-1.0, 1.0, 1.0])
        key = lambda a: a[np.lexsort((a[:, 2], a[:, 1], a[:, 0]))]  # noqa: E731
        np.testing.assert_allclose(key(xyz), key(mirrored), atol=SYM_TOL)

    # --- chunks ----------------------------------------------------------------------------------------------
    def test_each_chunk_sits_at_its_groups_samples_centroid(self) -> None:
        names = [c["name"] for c in self.hp["chunks"]]
        self.assertEqual(names, list(raider.CHUNK_ORDER))
        for entry in self.hp["chunks"]:
            members = [p.samples.positions for p in self.placed if p.part.group == entry["name"] and p.samples is not None]
            np.testing.assert_allclose(entry["offset"], np.concatenate(members).mean(axis=0), atol=1e-4)

    def test_chunks_sit_where_they_belong(self) -> None:
        offsets = {c["name"]: np.array(c["offset"]) for c in self.hp["chunks"]}
        self.assertLess(offsets["wing_l"][0], -2.0)
        self.assertGreater(offsets["wing_r"][0], 2.0)
        self.assertAlmostEqual(float(offsets["hump"][0]), 0.0, places=4)
        self.assertLess(offsets["nacelle_l"][0], 0.0)
        self.assertGreater(offsets["nacelle_r"][0], 0.0)
        self.assertGreater(offsets["nacelle_r"][2], offsets["hump"][2], "the drums are behind the hump's middle")

    def test_chunk_objs_are_valid_and_recentred(self) -> None:
        for entry in self.hp["chunks"]:
            obj = read_obj(self.dir_a / entry["obj"])
            self.assertGreater(len(obj.vertices), 0, entry["name"])
            self.assertTrue(np.all(np.isfinite(obj.vertices)))
            centre = 0.5 * (obj.vertices.min(axis=0) + obj.vertices.max(axis=0))
            self.assertLess(float(np.linalg.norm(centre)), 3.0, "%s: centred near its samples' centroid" % entry["name"])

    # --- hardpoints contract -----------------------------------------------------------------------------------
    def test_hardpoints_schema(self) -> None:
        hp = self.hp
        for key in ("asset_id", "frame", "units", "length_m", "span_m", "height_m", "mass_kg", "inertia_estimate_kg_m2",
                    "center_of_mass", "cockpit_camera", "chase_anchor", "muzzles", "pods", "rcs", "collision", "chunks"):
            self.assertIn(key, hp)
        self.assertEqual((hp["asset_id"], hp["frame"], hp["units"]), ("raider_fighter", "godot", "m"))
        self.assertEqual(hp["mass_kg"], 20_000.0)
        self.assertEqual(len(hp["center_of_mass"]), 3)
        self.assertIn("position", hp["cockpit_camera"])
        self.assertIn("position", hp["chase_anchor"])
        self.assertGreater(hp["chase_anchor"]["position"][2], hp["length_m"] * 0.5, "behind the ship")

    def test_two_pods_one_per_side_each_with_main_and_retro(self) -> None:
        pods = {p["name"]: p for p in self.hp["pods"]}
        self.assertEqual(set(pods), {"l", "r"})
        self.assertEqual((pods["l"]["side"], pods["r"]["side"]), ("left", "right"))
        for p in pods.values():
            self.assertEqual(p["main"]["exhaust"], [0.0, 0.0, 1.0])
            self.assertEqual(p["retro"]["exhaust"], [0.0, 0.0, -1.0])
            self.assertGreater(p["main"]["radius"], p["retro"]["radius"])
            self.assertGreater(p["main"]["position"][2], p["retro"]["position"][2], "main aft of retro")
        np.testing.assert_allclose(pods["l"]["main"]["position"], mirrored(pods["r"]["main"]["position"]), atol=SYM_TOL)
        np.testing.assert_allclose(pods["l"]["retro"]["position"], mirrored(pods["r"]["retro"]["position"]), atol=SYM_TOL)
        self.assertLess(pods["l"]["main"]["position"][0], 0.0)

    def test_nozzle_y_equals_centre_of_mass_y(self) -> None:
        com_y = self.hp["center_of_mass"][1]
        self.assertEqual(self.hp["center_of_mass"][0], 0.0)
        for p in self.hp["pods"]:
            for key in ("main", "retro"):
                self.assertAlmostEqual(p[key]["position"][1], com_y, delta=1e-6, msg=(p["name"], key))

    def test_the_main_exits_are_the_rearmost_points_of_the_hull_at_their_axes(self) -> None:
        for p in self.hp["pods"]:
            d = self.godot_xyz - np.array(p["main"]["position"])
            near_axis = np.hypot(d[:, 0], d[:, 1]) < p["main"]["radius"] + 0.2
            self.assertAlmostEqual(float(self.godot_xyz[near_axis, 2].max()), p["main"]["position"][2], delta=0.01)

    def test_four_forward_muzzles_left_and_right_taking_turns(self) -> None:
        muzzles = self.hp["muzzles"]
        self.assertEqual([m["name"] for m in muzzles], list(raider.MUZZLE_ORDER))
        for m in muzzles:
            self.assertEqual(m["direction"], [0.0, 0.0, -1.0])
        sides = [np.sign(m["position"][0]) for m in muzzles]
        self.assertEqual(sides, [-1.0, 1.0, -1.0, 1.0], "alternating fire alternates sides")
        for m in muzzles:
            nearest = float(np.linalg.norm(self.godot_xyz - np.array(m["position"]), axis=1).min())
            self.assertLess(nearest, 0.12, m["name"])

    def test_cosmetic_rcs_ports_carry_pilot_terms(self) -> None:
        self.assertGreaterEqual(len(self.hp["rcs"]), 4)
        for port in self.hp["rcs"]:
            self.assertTrue(set(port["tags"]) <= PILOT_TERMS, port)
            self.assertAlmostEqual(float(np.linalg.norm(port["exhaust"])), 1.0, places=4)

    # --- collision -----------------------------------------------------------------------------------------
    def test_collision_primitives_cover_the_surface_and_stay_close(self) -> None:
        shapes = self.hp["collision"]
        names = [c["name"] for c in shapes]
        self.assertEqual(len(names), len(set(names)), "unique names")
        self.assertEqual({"hump", "nacelle_l", "nacelle_r"} <= set(names), True)
        self.assertEqual(sum(1 for n in names if n.startswith("wing_l_step")), sum(1 for n in names if n.startswith("wing_r_step")))
        inside = np.zeros(len(self.godot_xyz), dtype=bool)
        for c in shapes:
            inside |= inside_primitive(self.godot_xyz, c, inflate=0.15)
        self.assertGreaterEqual(float(inside.mean()), 0.97, "AC4: at least 97 % of the surface samples")
        lo, hi = self.godot_xyz.min(axis=0), self.godot_xyz.max(axis=0)
        for c in shapes:
            basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
            np.testing.assert_allclose(basis.T @ basis, np.eye(3), atol=1e-4)
            self.assertAlmostEqual(float(np.linalg.det(basis)), 1.0, places=3)
            if c["type"] == "box":
                corners = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]) * 0.5 * np.array(c["size"])
                extent = corners @ basis.T + np.array(c["position"])
            else:
                half = 0.5 * c["height"] - c["radius"]  # `height` includes both caps
                ends = np.array([[0, 0, -half], [0, 0, half]]) @ basis.T + np.array(c["position"])
                extent = np.concatenate([ends - c["radius"], ends + c["radius"]])
            self.assertTrue(np.all(extent.min(axis=0) >= lo - 0.5) and np.all(extent.max(axis=0) <= hi + 0.5), c["name"])

    def test_hit_volume_reaches_the_wing_tips_and_the_nozzles(self) -> None:
        tip = np.array([[self.hp["span_m"] / 2 - 0.05, 0.0, 0.0]])
        # A point on the leading edge near the tip is inside a wing step.
        le_z = SPEC.wing.leading_z(SPEC.wing.half_span - 0.3) + 0.3 - self.manifest["centroid_offset"][2]
        point = np.array([[SPEC.wing.half_span - 0.3, -self.manifest["centroid_offset"][1], le_z]])
        self.assertTrue(any(inside_primitive(point, c, 0.1).any() for c in self.hp["collision"]))
        self.assertGreater(float(tip[0, 0]), 8.0)

    # --- meshes ----------------------------------------------------------------------------------------------
    def test_the_obj_is_valid_and_bounds_the_samples(self) -> None:
        v = self.obj.vertices
        self.assertGreater(len(v), 0)
        self.assertTrue(np.all(np.isfinite(v)))
        np.testing.assert_allclose(v.min(axis=0)[[0, 2]], self.godot_xyz.min(axis=0)[[0, 2]], atol=0.15)
        np.testing.assert_allclose(v.max(axis=0)[[0, 2]], self.godot_xyz.max(axis=0)[[0, 2]], atol=0.15)

    # --- determinism, options --------------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        for out in self.out_a.files:
            self.assertEqual(sha256(out), sha256(self.dir_b / out.name), out.name)

    def test_a_different_seed_changes_the_wear_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            raider.build(BuildContext(Path(tmp), seed=7))
            albedo = "raider_fighter_albedo.png"
            self.assertNotEqual(sha256(Path(tmp) / albedo), sha256(self.dir_a / albedo))
            hp = json.loads((Path(tmp) / raider.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            self.assertEqual([m["name"] for m in hp["muzzles"]], [m["name"] for m in self.hp["muzzles"]])
            # The centroid (the frame's origin) moves a little with the random samples; the design does not.
            np.testing.assert_allclose([m["position"] for m in hp["muzzles"]], [m["position"] for m in self.hp["muzzles"]], atol=0.05)
            self.assertEqual([c["name"] for c in hp["collision"]], [c["name"] for c in self.hp["collision"]])

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for bad in ({"spacing": 0.0}, {"spacing": -1.0}):
                with self.assertRaises(ValueError):
                    raider.build(BuildContext(Path(tmp), seed=1, options=bad))


class RaiderNavLightTests(unittest.TestCase):
    """Running lights (M3-T27, Q27): read from a generated ``hardpoints.json``, never from typed-in positions."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        out = Path(cls._tmp.name) / "a"
        raider.build(BuildContext(out, seed=42))
        cls.hp = json.loads((out / raider.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.nav = cls.hp["nav_lights"]

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_port_is_the_ships_left_and_starboard_its_right_on_the_wingtips(self) -> None:
        # -X is the ship's left (DamageZones: +X right, +Y up, -Z forward).
        half_span = SPEC.wing.half_span
        self.assertLess(self.nav["port"][0], -half_span, "port is past the left wingtip")
        self.assertGreater(self.nav["starboard"][0], half_span, "starboard past the right one")
        self.assertEqual(self.nav["port"], [-self.nav["starboard"][0], *self.nav["starboard"][1:]], "a mirrored pair")

    def test_the_top_light_is_on_top_of_the_hump(self) -> None:
        top = self.nav["top"]
        hump = next(c for c in self.hp["collision"] if c["name"] == "hump")
        self.assertEqual(top[0], 0.0)
        self.assertGreater(top[1], hump["position"][1] + 0.5 * hump["size"][1], "above the hump")
        self.assertGreater(top[2], self.hp["cockpit_camera"]["position"][2], "behind the canopy: +Z is aft")

    def test_the_top_lamp_stands_over_the_hump_and_reaches_it(self) -> None:
        lamp, top = self.nav["top_lamp"], self.nav["top"]
        self.assertEqual(lamp[0], 0.0)
        self.assertGreater(lamp[1], top[1], "it shines down on the hump")
        self.assertGreater(self.nav["top_lamp_range_m"], lamp[1] - top[1], "the hump is within its range")

    def test_the_cabin_glow_is_at_the_canopy_panel(self) -> None:
        cabin, eye = self.nav["cabin"], self.hp["cockpit_camera"]["position"]
        self.assertEqual(cabin[0], 0.0)
        self.assertLess(abs(cabin[2] - eye[2]), 1.0, "over the pilot: the panel is above the eye")
        self.assertLess(self.nav["cabin_range_m"], 3.0, "it stays on the hump's front: the wings are outside it")


def mirrored(v: list[float]) -> list[float]:
    return [-v[0], v[1], v[2]]


class RaiderStyleTests(unittest.TestCase):
    def test_style_provides_every_role_and_the_canopy_is_dark_and_opaque(self) -> None:
        from tools.procgen.styles import REQUIRED_ROLES
        from tools.procgen.styles.raider import RAIDER

        for role in REQUIRED_ROLES:
            self.assertIn(role, RAIDER.materials)
        canopy = RAIDER.material("canopy_glass")
        self.assertEqual(canopy.transmittance, 0.0)
        self.assertLess(max(canopy.albedo), 0.02)
        self.assertGreater(RAIDER.panel_tint_jitter, 0.1)

    def test_hull_is_a_worn_grey_brown(self) -> None:
        from tools.procgen.core.color import linear_to_srgb
        from tools.procgen.styles.raider import RAIDER

        r, g, b = (float(c) * 255 for c in linear_to_srgb(np.array(RAIDER.material("hull").albedo)))
        self.assertAlmostEqual(r, 0xA8, delta=2)
        self.assertAlmostEqual(g, 0x9F, delta=2)
        self.assertAlmostEqual(b, 0x96, delta=2)
        self.assertGreater(r, b, "warm: brown-grey, not blue-grey")


if __name__ == "__main__":
    unittest.main()
