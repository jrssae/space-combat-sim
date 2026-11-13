"""``raider_fighter`` (AC4): files, frames, chunks, hardpoints contract, collision coverage, determinism; the shape against its
reference model (M7-T16)."""

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
from tools.procgen.core.geometry import Mesh
from tools.procgen.core.image import read_png
from tools.procgen.core.obj import read_obj
from tools.procgen.core.textures import metal_finish
from tools.procgen.styles.raider import RAIDER

REPO = Path(__file__).resolve().parents[3]
REFERENCE_STL = REPO / "references" / "Raider_Fighter_16m.stl"  # gitignored: the score test runs where the maintainer keeps it

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
        cls.placed, cls.offset = raider.centre(raider.build_parts(SPEC, RAIDER, BuildContext(cls.dir_a, seed=42), raider.DEFAULT_SPACING_M))
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
        expected |= {f"raider_fighter_{k}_low.png{ext}" for k in ("albedo", "normal", "orm") for ext in ("", ".import")}  # M7-T15
        for entry in self.hp["chunks"]:
            expected |= {entry["obj"], entry["obj"].replace(".obj", ".mtl"), entry["mesh"]}
        self.assertEqual({p.name for p in self.dir_a.iterdir()}, expected)
        self.assertEqual({p.name for p in self.out_a.files}, expected)

    def test_the_manifest_names_the_textured_mesh(self) -> None:
        self.assertEqual(self.out_a.warnings, ())
        self.assertEqual(self.manifest["files"], {"obj": raider.OBJ_NAME, "mesh": raider.MESH_NAME, "hardpoints": raider.HARDPOINTS_NAME})
        self.assertEqual(self.manifest["chunks"], list(raider.CHUNK_ORDER))
        self.assertEqual(self.out_a.triangle_count, self.manifest["mesh"]["triangles"])

    # --- surface (M7-T15) --------------------------------------------------------------------------------
    def test_every_surface_names_the_low_texture_set(self) -> None:
        for surface in self.manifest["mesh"]["surfaces"]:
            low = surface["detail"]["low"]
            self.assertEqual(low, {k: f"raider_fighter_{k}_low.png" for k in ("albedo", "normal", "orm")})
            for file in low.values():
                self.assertTrue((self.dir_a / file).is_file(), file)
        for key in ("albedo", "normal", "orm"):
            self.assertNotEqual(sha256(self.dir_a / f"raider_fighter_{key}_low.png"), sha256(self.dir_a / f"raider_fighter_{key}.png"), key)

    def test_the_hull_parts_carry_their_layouts_and_twins_mirror(self) -> None:
        parts = {p.part.name: p for p in self.placed}
        self.assertEqual({name for name, p in parts.items() if p.part.seams}, {"wing_r", "wing_l", "hump", "nacelle_r", "nacelle_l"})
        for right, twin in (("wing_r", "wing_l"), ("nacelle_r", "nacelle_l")):
            a, b = parts[right], parts[twin]
            here = a.part.seams.evaluate(a.samples.positions, a.samples.normals, 0.02, 0.005)
            there = b.part.seams.evaluate(b.samples.positions, b.samples.normals, 0.02, 0.005)
            self.assertGreater(float(here.line.max()), 0.4, f"{right}: the samples meet its seams")
            np.testing.assert_allclose(there.line, here.line, atol=1e-9, err_msg=twin)
            np.testing.assert_allclose(there.tint, here.tint, atol=1e-9, err_msg=twin)

    def test_dimensions_match_the_design(self) -> None:
        self.assertAlmostEqual(self.hp["span_m"], 2.0 * SPEC.wing.half_span, places=3)
        self.assertAlmostEqual(self.hp["length_m"], SPEC.wing.trailing_z, places=3)
        self.assertEqual(self.manifest["dimensions_m"]["span"], self.hp["span_m"])
        self.assertGreater(self.hp["span_m"] / self.hp["length_m"], 2.0, "a flying wing: the span is more than twice the length")

    def test_length_width_and_height_are_within_ten_percent_of_the_model(self) -> None:
        for key, hp_key in (("length", "length_m"), ("span", "span_m"), ("height", "height_m")):
            ratio = self.hp[hp_key] / raider.REFERENCE_DIMENSIONS_M[key]
            self.assertLess(abs(ratio - 1.0), 0.10, key)

    # --- the shape (M7-T16) ---------------------------------------------------------------------------------
    def authored(self, name: str) -> np.ndarray:
        """A placed part's mesh vertices in the authored frame (nose at z = 0, the wing's mid-plane at y = 0)."""
        part = next(p.part for p in self.placed if p.part.name == name)
        return part.mesh.vertices + self.offset

    def test_the_leading_edge_is_one_straight_line_from_the_nose_to_the_tip(self) -> None:
        wing = SPEC.wing
        self.assertAlmostEqual(wing.sweep_deg, 47.8, delta=0.2)
        v = self.authored("wing_r")
        ahead = v[:, 2] < wing.line_z(v[:, 0]) - 1e-6
        self.assertFalse(ahead.any(), "nothing of the wing lies ahead of its leading edge")
        self.assertAlmostEqual(float(v[:, 0].max()), wing.half_span, places=6)
        self.assertAlmostEqual(float(v[:, 2].max()), wing.trailing_z, places=6)

    def test_the_notch_is_cut_out_of_the_leading_edge_and_holds_the_guns(self) -> None:
        wing = SPEC.wing
        v = self.authored("wing_r")
        in_notch = (v[:, 0] > wing.notch_x + 0.01) & (v[:, 2] < wing.notch_z - 0.01) & (v[:, 2] > wing.line_z(v[:, 0]) + 0.01)
        self.assertFalse(in_notch.any(), "the notch is empty wing")
        for name in ("inner_gun_r", "outer_gun_r"):
            g = self.authored(name)
            self.assertTrue(np.all(g[:, 0] > wing.notch_x) and np.all(g[:, 0] < wing.notch_z * wing.le_ratio), name)
            self.assertAlmostEqual(float(g[:, 2].min()), SPEC.gun_muzzle_z, places=6)
            self.assertLess(float(g[:, 2].min()), wing.notch_z, f"{name}: the muzzle stands out of the notch's back wall")

    def test_the_wings_detail_stays_inside_the_planform(self) -> None:
        # The old build's plates and vents overhung the leading edge: "the panels leading the wing are really wrong".
        wing = SPEC.wing
        details = [p.part.name for p in self.placed if p.part.group == "wing_r" and p.part.name.startswith("wing_") and p.part.name != "wing_r"]
        self.assertGreaterEqual(len(details), 5)
        for name in details:
            v = self.authored(name)
            self.assertTrue(np.all(v[:, 2] > wing.leading_z(v[:, 0]) + 0.1), f"{name}: behind the leading edge")
            self.assertTrue(np.all(v[:, 2] < wing.trailing_z_at(v[:, 0]) - 0.05), f"{name}: ahead of the trailing edge")
            self.assertTrue(np.all(v[:, 0] < wing.half_span - 0.3), name)

    def test_the_housings_and_ridge_hold_the_reference_sections(self) -> None:
        # The ridge peaks over the hump, the housings reach 2.4 m out and sit flat on either side of the wing's plane.
        ridge, lobe = self.authored("hump"), self.authored("nacelle_r")
        self.assertAlmostEqual(float(ridge[:, 1].max()), 0.84, delta=0.02)
        self.assertAlmostEqual(float(ridge[:, 1].min()), -0.68, delta=0.02)
        self.assertAlmostEqual(float(lobe[:, 0].max()), 2.44, delta=0.03)
        self.assertGreater(float(lobe[:, 1].max()), 0.7)
        self.assertLess(float(lobe[:, 1].min()), -0.6)

    # --- metal, not plastic (M7-T16) ---------------------------------------------------------------------------
    def test_both_texture_sets_read_as_metal_not_plastic(self) -> None:
        for suffix in ("", "_low"):
            orm = read_png(self.dir_a / f"raider_fighter_orm{suffix}.png").astype(float) / 255.0
            albedo = read_png(self.dir_a / f"raider_fighter_albedo{suffix}.png")
            rough, metal = orm[..., 1], orm[..., 2]
            hull = metal > 0.05  # the atlas's filled texels: nothing on the raider is fully dielectric but the canopy
            self.assertGreater(float(hull.mean()), 0.3, suffix)
            paint = hull & (metal > 0.3) & (metal < 0.6)
            bare = hull & (metal >= 0.65)
            self.assertGreater(float(paint.sum()) / hull.sum(), 0.4, f"{suffix}: most of it is painted metal")
            self.assertGreater(float(bare.sum()) / hull.sum(), 0.05, f"{suffix}: housings, grilles, barrels and edges are bare")
            self.assertLess(float(np.median(rough[bare])), float(np.median(rough[paint])), f"{suffix}: bare metal is smoother")
            spread = np.percentile(rough[paint], 90) - np.percentile(rough[paint], 10)
            self.assertGreater(float(spread), 0.12, f"{suffix}: the paint's roughness breaks up (no wet or matte plastic)")
            self.assertTrue(0.3 < float(np.median(rough[paint])) < 0.75, suffix)
            self.assertEqual(albedo.shape[:2], orm.shape[:2])

    def test_the_paint_keeps_its_colours(self) -> None:
        from tools.procgen.styles.raider import TEXTURED_ALBEDO as textured
        self.assertEqual(textured["rd_hull_metal"], textured["rd_hull"], "the housings' metal is the hull's colour")
        self.assertEqual(RAIDER.material("hull_metal").albedo, RAIDER.material("hull").albedo)

    @unittest.skipUnless(REFERENCE_STL.is_file(), "the reference model is not in this checkout")
    def test_the_silhouettes_score_ninety_percent_against_the_model(self) -> None:
        import sys

        sys.path.insert(0, str(REPO))
        from tools.refview import compare, refview

        raw, _ = refview.read_stl(REFERENCE_STL)
        model, _ = refview.to_ship_frame(raw, refview.frame_matrix(*raider.REFERENCE_MAPPING), raider.REFERENCE_DIMENSIONS_M["length"])
        model = model + np.asarray(raider.REFERENCE_MODEL_OFFSET)
        hull = Mesh.concatenate(p.part.mesh for p in self.placed if p.hull)
        tris = hull.vertices[hull.faces] + self.offset
        result = compare.compare_shapes(model, tris, float(np.ptp(model[..., 2])))
        self.assertEqual(compare.judge({n: v.iou for n, v in result.views.items()}, result.ratios), [])

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
        self.assertGreater(offsets["nacelle_r"][2], offsets["hump"][2], "the housings are behind the ridge's middle")

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
        # A point on the leading edge near the tip is inside a wing step.
        le_z = SPEC.wing.leading_z(SPEC.wing.half_span - 0.3) + 0.3 - self.manifest["centroid_offset"][2]
        point = np.array([[SPEC.wing.half_span - 0.3, -self.manifest["centroid_offset"][1], le_z]])
        self.assertTrue(any(inside_primitive(point, c, 0.1).any() for c in self.hp["collision"]))
        for p in self.hp["pods"]:  # the nozzles' exits are inside the housings' hit volumes
            exit_point = np.array([p["main"]["position"]]) - np.array([0.0, 0.0, 0.02])
            self.assertTrue(any(inside_primitive(exit_point, c, 0.0).any() for c in self.hp["collision"]), p["name"])

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


class MetalFinishTests(unittest.TestCase):
    """``textures.metal_finish`` (M7-T16): roughness per panel, dirt rough and dull; nothing without the style's parameters."""

    POS = np.stack(np.meshgrid(np.linspace(0.0, 5.0, 60), np.linspace(0.0, 5.0, 60), [0.0], indexing="ij"), axis=-1).reshape(-1, 3)

    def test_roughness_steps_between_panels_and_only_on_paint(self) -> None:
        n = len(self.POS)
        painted = self.POS[:, 0] < 2.5
        r, m = metal_finish({"panel_m": 1.0, "panel_rough": 0.12}, self.POS, painted, np.full(n, 0.5), np.full(n, 0.45), np.zeros(n), 3)
        np.testing.assert_allclose(r[~painted], 0.5)
        np.testing.assert_allclose(m, 0.45)
        cells = {tuple(np.floor(p).astype(int)): v for p, v in zip(self.POS[painted], r[painted])}
        self.assertGreater(len(set(np.round(list(cells.values()), 6))), 3, "each panel its own roughness")
        self.assertLessEqual(float(np.abs(r - 0.5).max()), 0.12 + 1e-9)

    def test_dirt_is_rougher_and_duller(self) -> None:
        n = len(self.POS)
        dirt = np.linspace(0.0, 1.0, n)
        r, m = metal_finish({"dirt_rough": 0.3, "dirt_metal": 0.5}, self.POS, np.ones(n, bool), np.full(n, 0.5), np.full(n, 0.6), dirt, 3)
        np.testing.assert_allclose(r, 0.5 + 0.3 * dirt)
        np.testing.assert_allclose(m, 0.6 * (1.0 - 0.5 * dirt))

    def test_without_parameters_it_changes_nothing(self) -> None:
        n = len(self.POS)
        r, m = metal_finish({}, self.POS, np.ones(n, bool), np.full(n, 0.5), np.full(n, 0.6), np.ones(n), 3)
        np.testing.assert_allclose(r, 0.5)
        np.testing.assert_allclose(m, 0.6)


class RaiderStyleTests(unittest.TestCase):
    def test_paint_is_metal_and_bare_metal_is_smoother(self) -> None:
        from tools.procgen.styles.raider import RAIDER

        for role in ("hull", "hull_panel", "stripe"):
            m = RAIDER.material(role)
            self.assertTrue(0.3 <= m.metallic <= 0.6 and 0.4 <= m.roughness_value <= 0.6, role)
        for role in ("hull_metal", "hull_dark", "nozzle", "barrel"):
            m = RAIDER.material(role)
            self.assertGreaterEqual(m.metallic, 0.7, role)
            self.assertLess(m.roughness_value, RAIDER.material("hull").roughness_value, role)
        self.assertNotIn("paint_roughness", RAIDER.extra, "no flat matte override")

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
