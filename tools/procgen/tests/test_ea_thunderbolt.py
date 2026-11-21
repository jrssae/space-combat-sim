"""``ea_thunderbolt`` (M10-T50, stage 1): files, frames, chunks, the hardpoints contract, the class budget with the low
texture set a mip level down, the looks, determinism; the shape against its reference model (the 90 % rule)."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import ea_thunderbolt as bolt
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.budgets import CLASS_BUDGETS
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Mesh
from tools.procgen.core.image import read_png
from tools.procgen.core.livery import ZONES
from tools.procgen.core.obj import read_obj
from tools.procgen.styles.ea_thunderbolt import DEFAULT_LOOK, LOOKS

REPO = Path(__file__).resolve().parents[3]
REFERENCE_STL = REPO / "references" / "EA_Thunderbolt_fighter.stl"  # gitignored: the score test runs where the maintainer keeps it
SMALL = {"atlas_px": 512, "spacing": 0.12}  # a quick build: the design is the same, the maps are small
PODS = ("ur", "lr", "ul", "ll")
PILOT_TERMS = {
    "sway_left", "sway_right", "heave_up", "heave_down", "pitch_up", "pitch_down",
    "yaw_left", "yaw_right", "roll_left", "roll_right",
}  # fmt: skip


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class ThunderboltTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = bolt.build(BuildContext(cls.dir_a, seed=42, options=SMALL))
        cls.out_b = bolt.build(BuildContext(cls.dir_b, seed=42, options=SMALL))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        look = LOOKS[DEFAULT_LOOK]
        cls.placed, cls.offset = bolt.centre(bolt.build_parts(bolt.DEFAULT_SPEC, look.style, BuildContext(cls.dir_a, seed=42), SMALL["spacing"]))
        cls.samples = np.concatenate([p.samples.positions for p in cls.placed if p.samples is not None])
        cls.hp = json.loads((cls.dir_a / bolt.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / bolt.OBJ_NAME)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    # --- files, manifest, budget ---------------------------------------------------------------------------
    def test_it_is_registered_and_every_file_is_listed(self) -> None:
        self.assertIs(ASSETS[bolt.ASSET_ID], bolt.build)
        expected = {bolt.OBJ_NAME, "ea_thunderbolt.mtl", bolt.HARDPOINTS_NAME, "manifest.json", "ea_thunderbolt.glb", "ea_thunderbolt_digits.png",
                    "ea_thunderbolt_digits.png.import"}
        expected |= {f"ea_thunderbolt_{k}{s}.png{ext}" for k in ("albedo", "emissive", "normal", "orm") for s in ("", "_low") for ext in ("", ".import")}
        for entry in self.hp["chunks"]:
            expected |= {entry["obj"], entry["obj"].replace(".obj", ".mtl"), entry["mesh"]}
        self.assertEqual({p.name for p in self.dir_a.iterdir()}, expected)
        self.assertEqual({p.name for p in self.out_a.files}, expected)

    def test_the_low_texture_set_is_a_mip_level_down_glow_map_included(self) -> None:
        mesh = self.manifest["mesh"]
        self.assertEqual(mesh["map_px"], {"albedo": 512, "normal": 1024, "orm": 512, "emissive": 512})
        for surface in mesh["surfaces"]:
            low = surface["detail"]["low"]
            self.assertEqual(set(low), {"albedo", "normal", "orm", "emissive"})
            for key, file in low.items():
                self.assertEqual(read_png(self.dir_a / file).shape[0], mesh["map_px"][key] // 2, file)

    def test_low_shrink_one_writes_the_low_set_at_full_size(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            bolt.build(BuildContext(Path(tmp), seed=42, options={**SMALL, "low_shrink": 1}))
            manifest = manifest_io.read_manifest(Path(tmp))
            self.assertEqual(read_png(Path(tmp) / "ea_thunderbolt_albedo_low.png").shape[0], 512)
            self.assertEqual(manifest["budget"]["low_shrink"], 1)
            self.assertEqual(manifest["budget"]["texture_mb_low"], manifest["budget"]["texture_mb"])

    def test_the_default_build_is_inside_the_fighter_budget(self) -> None:
        from tools.procgen.core.budgets import over_budget, texture_mb
        from tools.procgen.core.textures import NORMAL_SCALE

        budget = CLASS_BUDGETS[bolt.SHIP_CLASS]
        self.assertEqual(self.manifest["budget"]["class"], "fighter")
        self.assertEqual(self.manifest["budget"]["over"], [])
        self.assertLess(self.manifest["mesh"]["triangles"], budget.triangles)
        self.assertEqual(bolt.ATLAS_PX, budget.atlas_px)
        high = texture_mb([bolt.ATLAS_PX], normal_px=bolt.ATLAS_PX * NORMAL_SCALE)
        low = texture_mb([bolt.ATLAS_PX // 2], normal_px=bolt.ATLAS_PX * NORMAL_SCALE // 2)
        self.assertEqual(over_budget(bolt.SHIP_CLASS, self.manifest["mesh"]["triangles"], high, low), [])
        self.assertAlmostEqual(high, 29.33, places=2)
        self.assertAlmostEqual(low, 7.33, places=2)

    def test_it_takes_wing_liveries_in_the_starfurys_zones(self) -> None:
        self.assertEqual(self.manifest["mesh"]["livery"]["zones"], dict(ZONES))
        zones = {p.part.name: bolt.zone_of(p.part.name) for p in self.placed if p.hull}
        self.assertEqual(zones["wing_ur"], ZONES["strut_upper"])
        self.assertEqual(zones["deck_lower"], ZONES["strut_lower"])
        self.assertEqual(zones["pod_ll"], ZONES["pod"])
        self.assertEqual(zones["tail_ul"], ZONES["claw"])
        self.assertEqual(zones["gun_mount"], ZONES["gun_mount"])
        self.assertTrue(all(z > 0 for z in zones.values()))

    def test_every_look_builds_its_parts_and_an_unknown_one_is_refused(self) -> None:
        self.assertEqual(set(LOOKS), {"a", "b", "c"})
        for key, look in LOOKS.items():
            self.assertEqual(look.key, key)
            self.assertEqual(look.style.material("hull").name, "ef_hull", "the paint keeps its name, so a livery may paint over it")
            marks = bolt.markings_for(self.placed, look, self.offset)
            self.assertTrue(all(any(m.kind == "soot" for m in marks[f"{kind}_{pod}"]) for kind in ("pod", "tail") for pod in PODS), key)
        with self.assertRaisesRegex(ValueError, "look"):
            bolt.build(BuildContext(self.dir_a / "bad", seed=42, options={**SMALL, "look": "z"}))
        with self.assertRaisesRegex(ValueError, "spacing"):
            bolt.build(BuildContext(self.dir_a / "bad", seed=42, options={**SMALL, "spacing": 0.0}))

    # --- the shape -------------------------------------------------------------------------------------------
    def test_dimensions_are_the_references(self) -> None:
        d = self.manifest["dimensions_m"]
        self.assertAlmostEqual(d["length"], bolt.REFERENCE_LENGTH_M, delta=0.05)
        self.assertAlmostEqual(d["span"], 12.0, delta=0.1)
        self.assertAlmostEqual(d["height"], 6.34, delta=0.1)

    def test_the_lower_pods_are_the_upper_ones_moved_down_not_mirrored(self) -> None:
        by_name = {p.part.name: p.part for p in self.placed}
        upper, lower = by_name["pod_ur"].mesh, by_name["pod_lr"].mesh
        shift = np.array([0.0, bolt.POD_Y["l"] - bolt.POD_Y["u"], 0.0])
        np.testing.assert_allclose(lower.vertices, upper.vertices + shift, atol=1e-9)
        np.testing.assert_allclose(by_name["pod_ul"].mesh.vertices, upper.vertices * np.array([-1.0, 1.0, 1.0]), atol=1e-9)

    @unittest.skipUnless(REFERENCE_STL.is_file(), "the reference model is not in this checkout")
    def test_the_silhouettes_score_ninety_percent_against_the_model(self) -> None:
        import sys

        sys.path.insert(0, str(REPO))
        from tools.refview import compare, refview

        raw, _ = refview.read_stl(REFERENCE_STL)
        rotation = refview.file_rotation(*bolt.REFERENCE_MAPPING, bolt.REFERENCE_TURN)
        model, _ = refview.to_ship_frame(raw, rotation, bolt.REFERENCE_LENGTH_M)
        hull = Mesh.concatenate(p.part.mesh for p in self.placed if p.hull)
        result = compare.compare_shapes(model, hull.vertices[hull.faces] + self.offset, float(np.ptp(model[..., 2])))
        self.assertEqual(compare.judge({n: v.iou for n, v in result.views.items()}, result.ratios), [])

    # --- frames, symmetry, chunks --------------------------------------------------------------------------
    def test_the_samples_are_centred_and_the_aabb_is_the_hulls(self) -> None:
        mean = self.samples.mean(axis=0)
        np.testing.assert_allclose(mean, [0.0, 0.0, 0.0], atol=1e-6)
        np.testing.assert_allclose(self.obj.vertices.min(axis=0), self.manifest["aabb_min"], atol=2e-4)
        np.testing.assert_allclose(self.obj.vertices.max(axis=0), self.manifest["aabb_max"], atol=2e-4)
        self.assertAlmostEqual(self.manifest["centroid_offset"][0], 0.0)

    def test_sample_positions_are_exactly_mirror_symmetric_in_x(self) -> None:
        key = lambda a: a[np.lexsort((a[:, 2], a[:, 1], a[:, 0]))]  # noqa: E731
        np.testing.assert_allclose(key(self.samples), key(self.samples * np.array([-1.0, 1.0, 1.0])), atol=1e-6)

    def test_the_chunks_are_the_cabin_and_four_arms_each_at_its_samples_centroid(self) -> None:
        self.assertEqual([c["name"] for c in self.hp["chunks"]], ["cabin", "arm_ur", "arm_lr", "arm_ul", "arm_ll"])
        self.assertEqual(self.manifest["chunks"], list(bolt.CHUNK_ORDER))
        for entry in self.hp["chunks"]:
            members = [p for p in self.placed if bolt.chunk_of(p.part.name) == entry["name"]]
            points = np.concatenate([p.samples.positions for p in members if p.samples is not None])
            np.testing.assert_allclose(entry["offset"], points.mean(axis=0), atol=2e-5)
            self.assertTrue((self.dir_a / entry["mesh"]).is_file())
            self.assertEqual(len(entry["joint"]), 3)
        arms = {c["name"]: c for c in self.hp["chunks"][1:]}
        self.assertGreater(arms["arm_ur"]["offset"][0], 3.0)
        self.assertLess(arms["arm_ll"]["offset"][0], -3.0)
        self.assertGreater(arms["arm_ur"]["offset"][1], 0.0)
        self.assertLess(arms["arm_lr"]["offset"][1], 0.0)
        self.assertAlmostEqual(arms["arm_ur"]["joint"][0], bolt.DEFAULT_SPEC.upper_wing.split_x, places=3)  # where the wing leaves the body
        self.assertEqual(self.hp["chunks"][0]["joint"][0], 0.0)

    def test_every_hull_part_is_in_one_chunk_and_carries_a_layout_where_one_is_drawn(self) -> None:
        names = [p.part.name for p in self.placed if p.hull]
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(sum(bolt.chunk_of(n) != "cabin" for n in names), 12)  # a wing, a pod and a tail per arm
        for p in self.placed:
            if p.part.name.split("_")[0] in ("fuselage", "canopy", "chin", "trunk", "deck", "wing", "pod", "tail"):
                self.assertTrue(p.part.seams, p.part.name)

    # --- hardpoints ------------------------------------------------------------------------------------------
    def test_hardpoints_schema(self) -> None:
        hp = self.hp
        for key in ("asset_id", "generator_version", "frame", "units", "length_m", "span_m", "height_m", "mass_kg", "inertia_estimate_kg_m2",
                    "center_of_mass", "cockpit_camera", "chase_anchor", "muzzles", "pods", "rcs", "collision", "nav_lights", "chunks"):
            self.assertIn(key, hp)
        self.assertEqual((hp["asset_id"], hp["frame"], hp["units"]), ("ea_thunderbolt", "godot", "m"))
        self.assertEqual(hp["generator_version"], bolt.GENERATOR_VERSION)
        self.assertEqual(hp["center_of_mass"][0], 0.0)

    def test_four_pods_each_with_a_main_bell_aft_and_a_retro_bell_forward(self) -> None:
        self.assertEqual([(p["name"], p["side"]) for p in self.hp["pods"]], list(bolt.POD_SIDES))
        hull_aft = self.manifest["aabb_max"][2]
        for pod in self.hp["pods"]:
            sign = 1.0 if pod["side"] == "right" else -1.0
            self.assertGreater(sign * pod["center"][0], 5.0)
            np.testing.assert_allclose(pod["main"]["exhaust"], [0.0, 0.0, 1.0], atol=1e-6)
            np.testing.assert_allclose(pod["retro"]["exhaust"], [0.0, 0.0, -1.0], atol=1e-6)
            self.assertGreater(pod["main"]["position"][2], pod["center"][2] + 3.0)
            self.assertLess(pod["retro"]["position"][2], pod["center"][2] - 2.0)
            self.assertLess(pod["main"]["position"][2], hull_aft)  # the blades and fins reach past the bells
        mains = np.array([p["main"]["position"] for p in self.hp["pods"]])
        self.assertAlmostEqual(float(mains[:, 1].mean()), self.hp["center_of_mass"][1], places=4)  # no pitch from the main engines
        self.assertAlmostEqual(float(mains[:, 0].sum()), 0.0, places=4)

    def test_five_forward_muzzles_the_sides_taking_turns(self) -> None:
        muzzles = self.hp["muzzles"]
        self.assertEqual([m["name"] for m in muzzles], ["nose", "left", "right", "root_left", "root_right"])
        for m in muzzles:
            np.testing.assert_allclose(m["direction"], [0.0, 0.0, -1.0], atol=1e-6)
        by_name = {m["name"]: m["position"] for m in muzzles}
        self.assertEqual(by_name["nose"][0], 0.0)
        for a, b in (("left", "right"), ("root_left", "root_right")):
            self.assertLess(by_name[a][0], 0.0)
            np.testing.assert_allclose(by_name[a], np.array(by_name[b]) * [-1.0, 1.0, 1.0], atol=1e-5)
        self.assertLess(by_name["nose"][2], by_name["root_right"][2])  # the nose battery is ahead of the wing roots' cannons

    def test_cosmetic_rcs_ports_carry_pilot_terms(self) -> None:
        rcs = self.hp["rcs"]
        self.assertEqual(len(rcs), 12)
        self.assertEqual(len({r["name"] for r in rcs}), 12)
        for r in rcs:
            self.assertIn(r["pod"], PODS)
            self.assertTrue(r["tags"] and set(r["tags"]) <= PILOT_TERMS, r)
            self.assertAlmostEqual(float(np.linalg.norm(r["exhaust"])), 1.0, places=5)

    def test_the_eye_is_under_the_glass_and_the_lights_are_on_their_sides(self) -> None:
        offset = np.asarray(self.offset)
        eye = np.array(self.hp["cockpit_camera"]["position"]) + offset
        panes = bolt.DEFAULT_SPEC.canopy.panes
        self.assertTrue(panes[0][0] < eye[2] < panes[-1][1])
        self.assertEqual(self.hp["cockpit_camera"]["forward"], [0.0, 0.0, -1.0])
        lights = self.hp["nav_lights"]
        self.assertLess(lights["port"][0], -5.0)
        self.assertGreater(lights["starboard"][0], 5.0)
        self.assertEqual(lights["top"][0], 0.0)
        self.assertGreater(lights["top_lamp"][1], lights["top"][1])
        np.testing.assert_allclose(lights["cabin"], self.hp["cockpit_camera"]["position"], atol=1e-6)
        hull_top = float(max(p.part.mesh.bounds()[1][1] for p in self.placed if p.part.name in ("pod_ur", "pod_ul")))
        self.assertGreater(lights["port"][1], hull_top)

    def test_collision_primitives_are_named_and_reach_the_pods(self) -> None:
        collision = self.hp["collision"]
        self.assertGreater(len(collision), 20)
        self.assertTrue(all(c["type"] in ("box", "capsule") and c["name"] for c in collision))
        self.assertEqual(sum(c["name"].startswith("pod_") for c in collision), 4)
        xs = [abs(c["position"][0]) for c in collision]
        self.assertGreater(max(xs), 5.0)

    # --- determinism -----------------------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        for path in sorted(self.dir_a.iterdir()):
            self.assertEqual(sha256(path), sha256(self.dir_b / path.name), path.name)

    def test_the_obj_is_valid_and_holds_the_textured_meshs_triangles(self) -> None:
        self.assertEqual(len(self.obj.faces), self.manifest["mesh"]["triangles"])
        self.assertTrue(np.isfinite(self.obj.vertices).all())


if __name__ == "__main__":
    unittest.main()
