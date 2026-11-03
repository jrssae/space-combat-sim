"""``skylark_transport`` (M5-T13, AC12, D61, Q19): files, budgets, frames, symmetry, chunk partition, collision coverage,
the hardpoint contract with its single dorsal turret, the turret model, colours and determinism.

The expected numbers are typed in from docs/assets-civilian.md and docs/design-references.md ("Skylark transport"), not
read from the generator.
"""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import skylark_transport as sky
from tools.procgen.core import frames, lighting
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.color import linear_to_srgb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.obj import read_obj
from tools.procgen.core.ply import read_ply
from tools.procgen.parts import skylark as sp

PILOT_TERMS = {
    "sway_left", "sway_right", "heave_up", "heave_down", "pitch_up", "pitch_down",
    "yaw_left", "yaw_right", "roll_left", "roll_right",
}  # fmt: skip
SYM_TOL = 1e-5
MAX_ROUND_TRIP_DEG = 1.5
CHUNKS = ("capsule", "body", "nacelle_l", "nacelle_r")
BUDGET = (48_000, 72_000)  # docs/assets-civilian.md: 60 000 (48 000 to 72 000)
LOD_SHARES = {1: (0.20, 0.30), 2: (0.04, 0.09), 3: (0.01, 0.025)}
NACELLE_AXIS = (13.03, -0.26)  # x, y of the nacelles' axis (authored frame, y from the box centre)
DORSAL_TURRET = (0.0, 2.87, 37.5)  # Q19: the only turret, seated on the body's ridge ahead of the dorsal fin


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sorted_rows(a: np.ndarray) -> np.ndarray:
    return a[np.lexsort((a[:, 2], a[:, 1], a[:, 0]))]


def inside_primitive(points: np.ndarray, c: dict, inflate: float) -> np.ndarray:
    basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
    local = (points - np.array(c["position"])) @ basis
    if c["type"] == "box":
        return np.all(np.abs(local) <= 0.5 * np.array(c["size"]) + inflate, axis=1)
    half = 0.5 * c["height"] - c["radius"]
    along = np.clip(local[:, 2], -half, half)
    axis_point = np.column_stack([np.zeros_like(along), np.zeros_like(along), along])
    return np.linalg.norm(local - axis_point, axis=1) <= c["radius"] + inflate


def godot_xyz(path: Path) -> np.ndarray:
    return frames.flip_xy(read_ply(path).to_splats().xyz)


def mirrored(v: list[float]) -> list[float]:
    return [-v[0], v[1], v[2]]


def angle_deg(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return np.degrees(np.arccos(np.clip(np.einsum("ij,ij->i", a, b), -1.0, 1.0)))


def srgb_hex(albedo: tuple[float, float, float]) -> int:
    r, g, b = (round(float(c) * 255) for c in linear_to_srgb(np.array(albedo)))
    return (r << 16) | (g << 8) | b


class SkylarkTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = sky.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = sky.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.splats = read_ply(cls.dir_a / sky.PLY_NAME).to_splats()
        cls.xyz = frames.flip_xy(cls.splats.xyz)
        cls.hp = json.loads((cls.dir_a / sky.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / sky.OBJ_NAME)
        cls.lod1 = read_ply(cls.dir_a / sky.LODS[1][0]).to_splats()
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.spacing = float(cls.manifest["lods"][0]["spacing_m"])
        cls.length = cls.hp["length_m"]

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def authored(self, v: list[float]) -> np.ndarray:
        """A hardpoint back in the design references' frame (nose tip at z = 0, x and y from the box centre)."""
        return np.array(v) + self.offset

    # --- files, manifest, budgets ------------------------------------------------------------------------------------
    def test_registered_and_named(self) -> None:
        self.assertIs(ASSETS["skylark_transport"], sky.build)
        self.assertEqual(self.manifest["asset_id"], "skylark_transport")
        self.assertEqual(self.hp["asset_id"], "skylark_transport")

    def test_all_files_are_written_and_listed(self) -> None:
        expected = {sky.PLY_NAME, sky.OBJ_NAME, "skylark_transport.mtl", sky.HARDPOINTS_NAME, "manifest.json"}
        expected |= {entry[0] for entry in sky.LODS.values()}
        expected |= {lod["lighting"] for lod in self.manifest["lods"]}
        for entry in self.hp["chunks"]:
            expected |= {entry["ply"], entry["lighting"], entry["obj"], entry["obj"].replace(".obj", ".mtl")}
        turret = self.manifest["turret"]
        expected |= {turret["ply"], turret["lighting"], turret["obj"], turret["obj"].replace(".obj", ".mtl")}
        self.assertEqual({p.name for p in self.dir_a.iterdir()}, expected)
        self.assertEqual({p.name for p in self.out_a.files}, expected)

    def test_lod0_is_inside_the_budget_and_counted_by_group(self) -> None:
        lod = self.manifest["lods"][0]
        self.assertEqual(lod["file"], sky.PLY_NAME)
        self.assertEqual(lod["splats"], len(self.splats))
        self.assertEqual(sky.SPLAT_BUDGET, BUDGET)
        self.assertTrue(BUDGET[0] <= lod["splats"] <= BUDGET[1], lod["splats"])
        self.assertEqual(self.out_a.warnings, ())
        self.assertEqual(list(self.manifest["counts"]), list(CHUNKS))
        self.assertEqual(sum(self.manifest["counts"].values()), len(self.splats))
        self.assertEqual(self.manifest["files"], {"fallback_mesh": sky.OBJ_NAME, "hardpoints": sky.HARDPOINTS_NAME})
        self.assertEqual(self.manifest["chunk_lod"], 1)

    def test_lods_one_to_three_are_coarser_centred_and_keep_the_box(self) -> None:
        lod0 = self.manifest["lods"][0]
        self.assertEqual([e["level"] for e in self.manifest["lods"]], [0, 1, 2, 3])
        # The Godot import test allows a big hull's coarse levels a looser box only from a 0.25 m LOD0 spacing.
        self.assertGreaterEqual(lod0["spacing_m"], 0.25)
        for level, (name, factor, _stream) in sky.LODS.items():
            entry = self.manifest["lods"][level]
            self.assertEqual(entry["file"], name)
            self.assertAlmostEqual(entry["spacing_m"], factor * lod0["spacing_m"])
            share = entry["splats"] / lod0["splats"]
            self.assertTrue(LOD_SHARES[level][0] <= share <= LOD_SHARES[level][1], (level, share))
            xyz = godot_xyz(self.dir_a / name)
            self.assertEqual(len(xyz), entry["splats"])
            self.assertLess(float(np.abs(xyz.mean(axis=0)).max()), 1e-3, "centred like LOD0")
            tolerance = max(0.3, 1.25 * entry["spacing_m"])  # the import test's rule for big hulls
            np.testing.assert_allclose(xyz.min(axis=0), self.manifest["aabb_min"], atol=tolerance)
            np.testing.assert_allclose(xyz.max(axis=0), self.manifest["aabb_max"], atol=tolerance)
        self.assertGreater(self.manifest["lods"][3]["splats"], 500, "the farthest level still draws the outline")

    def test_dimensions_match_the_design(self) -> None:
        self.assertAlmostEqual(self.hp["length_m"], 60.0, delta=0.6, msg="Q8: about 60 m, nose vanes to claw tips")
        self.assertAlmostEqual(self.hp["span_m"], 40.2, delta=0.6, msg="across the claw tips")
        self.assertAlmostEqual(self.hp["height_m"], 10.27, delta=0.5, msg="ventral nose vane to dorsal fin")
        self.assertEqual(
            self.manifest["dimensions_m"],
            {"length": self.hp["length_m"], "span": self.hp["span_m"], "height": self.hp["height_m"]},
        )

    # --- frames, symmetry, splats ----------------------------------------------------------------------------------------
    def test_ply_is_centred_and_the_aabb_matches_after_the_flip(self) -> None:
        np.testing.assert_allclose(self.xyz.mean(axis=0), [0.0, 0.0, 0.0], atol=1e-3)
        np.testing.assert_allclose(self.xyz.min(axis=0), self.manifest["aabb_min"], atol=2e-4)
        np.testing.assert_allclose(self.xyz.max(axis=0), self.manifest["aabb_max"], atol=2e-4)
        self.assertAlmostEqual(self.manifest["centroid_offset"][0], 0.0, places=9)

    def test_the_authored_frame_is_the_references(self) -> None:
        # Back in the authored frame the nose tip is at z = 0 and the box is centred on x = y = 0 (refview's frame).
        authored = self.xyz + self.offset
        lo, hi = authored.min(axis=0), authored.max(axis=0)
        self.assertAlmostEqual(float(lo[2]), 0.0, delta=0.3)
        self.assertAlmostEqual(float(0.5 * (lo[1] + hi[1])), 0.0, delta=0.3)
        self.assertAlmostEqual(float(0.5 * (lo[0] + hi[0])), 0.0, delta=1e-6)

    def test_every_level_is_exactly_mirror_symmetric_in_x(self) -> None:
        levels = [self.xyz] + [godot_xyz(self.dir_a / sky.LODS[level][0]) for level in (1, 2, 3)]
        for level, xyz in enumerate(levels):
            np.testing.assert_allclose(sorted_rows(xyz), sorted_rows(xyz * np.array([-1.0, 1.0, 1.0])), atol=SYM_TOL, err_msg=f"LOD{level}")

    def test_splats_are_flat_oriented_opaque_discs(self) -> None:
        scale = self.splats.scale
        self.assertTrue(np.all(scale[:, 2] < scale[:, 0]))
        self.assertTrue(np.all(np.isfinite(self.splats.rgb)))
        self.assertTrue(np.all((self.splats.alpha > 0.0) & (self.splats.alpha < 1.0)))
        self.assertGreater(float(np.median(self.splats.alpha)), 0.9)

    def test_the_capsule_is_forward_and_the_claws_aft(self) -> None:
        authored = self.xyz + self.offset
        x, z = authored[:, 0], authored[:, 2]
        nose = authored[z < 2.0]
        self.assertLess(float(np.abs(nose[:, 0]).max()), 4.8, "the nose and its vanes, about 9 m across")
        tail = authored[z > 59.4]
        self.assertGreater(float(np.abs(tail[:, 0]).min()), 15.0, "only the outboard claws reach past the exhaust cone")
        self.assertAlmostEqual(float(np.abs(x).max()), 20.1, delta=0.3, msg="the claw tips are the widest points")
        capsule = authored[(z > 8.0) & (z < 16.0) & (np.abs(x) < 4.2) & (authored[:, 1] > -1.5)]  # not the tanks or fins
        self.assertAlmostEqual(float(np.abs(capsule[:, 0]).max()), 3.73, delta=0.15, msg="the 7.46 m capsule")
        body = authored[(z > 42.0) & (z < 46.0) & (np.abs(authored[:, 1] + 1.6) < 0.8)]
        self.assertGreater(float(np.abs(body[:, 0]).max()), 15.0, "body and nacelles side by side")

    # --- colours -------------------------------------------------------------------------------------------------------
    def test_the_paint_is_sand_with_red_orange_bands_and_dark_bells(self) -> None:
        rgb, authored = self.splats.rgb, self.xyz + self.offset
        x, y, z = authored[:, 0], authored[:, 1], authored[:, 2]
        top = (np.abs(x) > 4.0) & (np.abs(x) < 9.0) & (z > 40.0) & (z < 48.0) & (y > -0.5)
        sand = linear_to_srgb(np.median(rgb[top], axis=0))
        self.assertGreater(sand[0], sand[2] + 0.1, "sand khaki: warm, not grey")
        self.assertGreater(float(sand.mean()), 0.45, "a light plating")
        band = (rgb[:, 0] > 2.0 * rgb[:, 1]) & (rgb[:, 0] > 0.2)
        self.assertGreater(int(band.sum()), 400, "two bands on the capsule, one on each side tank")
        self.assertAlmostEqual(float(x[band].mean()), 0.0, delta=0.2)
        self.assertLess(float(z[band].max()), 30.0, "the bands are on the forward capsule and the tanks")
        on_tanks = band & (np.abs(np.abs(x) - 5.44) < 2.3) & (z > 19.0)
        self.assertGreater(int(on_tanks.sum()), 50, "one band on each side tank")
        bell = (np.hypot(np.abs(x) - NACELLE_AXIS[0], y - NACELLE_AXIS[1]) < 3.1) & (z > 52.0) & (z < 55.4)
        dark = linear_to_srgb(np.median(rgb[bell], axis=0))
        self.assertLess(float(dark.mean()), float(sand.mean()) - 0.2, "dark nacelle bells")

    def test_the_skylark_style_carries_the_written_scheme(self) -> None:
        style = sky.STYLE
        for role, value in (("hull", 0xB3A982), ("hull_panel", 0x7E7552), ("hull_dark", 0x4A4536), ("stripe", 0xB8452B),
                            ("nozzle", 0x4A4A46)):  # fmt: skip
            got = srgb_hex(style.material(role).albedo)
            for shift in (16, 8, 0):
                self.assertAlmostEqual((got >> shift) & 255, (value >> shift) & 255, delta=1, msg=role)
        self.assertEqual(style.name, "ea_civilian")
        self.assertAlmostEqual(style.panel_size_m, 2.4)
        self.assertAlmostEqual(style.panel_line_width_m, 0.25)
        self.assertAlmostEqual(style.panel_tint_jitter, 0.06)
        self.assertEqual(sky.ENGINE_GLOW_SRGB, 0xFFE9C2)

    # --- lighting records ----------------------------------------------------------------------------------------------
    def test_every_level_chunk_and_the_turret_has_matching_lighting_records(self) -> None:
        pairs = [(lod["file"], lod["lighting"]) for lod in self.manifest["lods"]]
        pairs += [(c["ply"], c["lighting"]) for c in self.hp["chunks"]]
        pairs.append((self.manifest["turret"]["ply"], self.manifest["turret"]["lighting"]))
        self.assertEqual(len(pairs), 4 + len(CHUNKS) + 1)
        for ply_name, light_name in pairs:
            splats = read_ply(self.dir_a / ply_name).to_splats()
            records = lighting.read_lighting(self.dir_a / light_name)
            self.assertEqual(len(records), len(splats), light_name)
            self.assertLess(float(angle_deg(lighting.decode_normals(records), splats.normals).max()), MAX_ROUND_TRIP_DEG, light_name)

    # --- chunks --------------------------------------------------------------------------------------------------------
    def test_chunks_partition_lod1_exactly(self) -> None:
        self.assertEqual([c["name"] for c in self.hp["chunks"]], list(CHUNKS))
        self.assertEqual(self.manifest["chunks"], list(CHUNKS))
        lod1 = frames.flip_xy(self.lod1.xyz)
        start = 0
        for entry in self.hp["chunks"]:
            n = entry["splats"]
            chunk = read_ply(self.dir_a / entry["ply"]).to_splats()
            self.assertEqual(len(chunk), n)
            body = frames.flip_xy(chunk.xyz) + np.array(entry["offset"])
            np.testing.assert_allclose(body, lod1[start : start + n], atol=1e-5)
            np.testing.assert_allclose(chunk.rgb, self.lod1.rgb[start : start + n], atol=1e-4)
            np.testing.assert_allclose(chunk.xyz.mean(axis=0), [0.0, 0.0, 0.0], atol=1e-4)
            start += n
        self.assertEqual(start, len(self.lod1))

    def test_chunks_sit_where_they_belong_and_have_joints(self) -> None:
        chunks = {c["name"]: c for c in self.hp["chunks"]}
        offsets = {name: self.authored(c["offset"]) for name, c in chunks.items()}
        self.assertGreater(offsets["nacelle_r"][0], 10.0)
        np.testing.assert_allclose(chunks["nacelle_l"]["offset"], mirrored(chunks["nacelle_r"]["offset"]), atol=1e-4)
        self.assertAlmostEqual(float(offsets["capsule"][0]), 0.0, places=4)
        self.assertAlmostEqual(float(offsets["body"][0]), 0.0, places=4)
        self.assertLess(float(offsets["capsule"][2]), 25.0, "the capsule chunk is forward")
        self.assertGreater(float(offsets["body"][2]), 38.0, "the body chunk is aft")
        for name, c in chunks.items():
            self.assertEqual(len(c["joint"]), 3, name)
            self.assertLess(float(np.linalg.norm(np.array(c["joint"]) - np.array(c["offset"]))), 25.0, name)
        np.testing.assert_allclose(chunks["nacelle_l"]["joint"], mirrored(chunks["nacelle_r"]["joint"]), atol=1e-4)

    def test_chunk_objs_are_valid_and_recentred(self) -> None:
        for entry in self.hp["chunks"]:
            obj = read_obj(self.dir_a / entry["obj"])
            self.assertGreater(len(obj.vertices), 0, entry["name"])
            self.assertTrue(np.all(np.isfinite(obj.vertices)))
            chunk = godot_xyz(self.dir_a / entry["ply"])
            lo, hi = obj.vertices.min(axis=0), obj.vertices.max(axis=0)
            self.assertTrue(np.all(chunk.min(axis=0) >= lo - 0.5) and np.all(chunk.max(axis=0) <= hi + 0.5), entry["name"])

    # --- hardpoints contract -----------------------------------------------------------------------------------------------
    def test_hardpoints_schema(self) -> None:
        hp = self.hp
        for key in ("asset_id", "generator_version", "frame", "units", "length_m", "span_m", "height_m", "mass_kg",
                    "inertia_estimate_kg_m2", "center_of_mass", "cockpit_camera", "chase_anchor", "muzzles", "pods",
                    "rcs", "collision", "nav_lights", "chunks", "turrets"):  # fmt: skip
            self.assertIn(key, hp)
        self.assertEqual((hp["frame"], hp["units"]), ("godot", "m"))
        self.assertEqual(hp["generator_version"], sky.GENERATOR_VERSION)
        self.assertEqual(hp["muzzles"], [], "no fixed guns: the turret carries its own barrels")
        self.assertGreater(hp["mass_kg"], 100_000.0)
        self.assertEqual(hp["center_of_mass"][0], 0.0)

    def test_two_pods_on_the_nacelles_each_with_main_and_retro(self) -> None:
        pods = {p["name"]: p for p in self.hp["pods"]}
        self.assertEqual(set(pods), {"l", "r"})
        self.assertEqual((pods["l"]["side"], pods["r"]["side"]), ("left", "right"))
        for p in pods.values():
            self.assertEqual(p["main"]["exhaust"], [0.0, 0.0, 1.0])
            self.assertEqual(p["retro"]["exhaust"], [0.0, 0.0, -1.0])
            main, retro = self.authored(p["main"]["position"]), self.authored(p["retro"]["position"])
            self.assertAlmostEqual(abs(float(main[0])), NACELLE_AXIS[0], delta=1e-3)
            self.assertAlmostEqual(float(main[1]), NACELLE_AXIS[1], delta=1e-3)
            self.assertAlmostEqual(float(main[2]), 55.48, delta=0.05, msg="the bell's exit")
            self.assertAlmostEqual(float(retro[2]), 35.64, delta=0.05, msg="the intake's face")
            self.assertTrue(1.3 <= p["main"]["radius"] <= 1.8, "inside the 3.2 m bell exit")
            self.assertTrue(1.0 <= p["retro"]["radius"] <= 1.5, "inside the intake ring")
        np.testing.assert_allclose(pods["l"]["main"]["position"], mirrored(pods["r"]["main"]["position"]), atol=SYM_TOL)
        np.testing.assert_allclose(pods["l"]["retro"]["position"], mirrored(pods["r"]["retro"]["position"]), atol=SYM_TOL)
        self.assertLess(pods["l"]["main"]["position"][0], 0.0)

    def test_the_centre_of_mass_is_on_the_thrust_line(self) -> None:
        com_y = self.hp["center_of_mass"][1]
        for p in self.hp["pods"]:
            for key in ("main", "retro"):
                self.assertAlmostEqual(p[key]["position"][1], com_y, delta=1e-6, msg=(p["name"], key))
        com_z = float(self.authored(self.hp["center_of_mass"])[2])
        self.assertTrue(25.0 < com_z < 50.0, com_z)

    def test_the_main_exits_are_the_rearmost_points_at_their_axes(self) -> None:
        for p in self.hp["pods"]:
            d = self.xyz - np.array(p["main"]["position"])
            near_axis = np.hypot(d[:, 0], d[:, 1]) < p["main"]["radius"] + 0.1
            self.assertAlmostEqual(float(self.xyz[near_axis, 2].max()), p["main"]["position"][2], delta=0.2)
            nearest = float(np.linalg.norm(self.xyz - np.array(p["retro"]["position"]), axis=1).min())
            self.assertLess(nearest, 0.6, "the retro sits on the intake")

    def test_cosmetic_rcs_ports_carry_pilot_terms_and_sit_on_the_hull(self) -> None:
        rcs = self.hp["rcs"]
        self.assertGreaterEqual(len(rcs), 12)
        tags = set()
        for port in rcs:
            self.assertTrue(set(port["tags"]) <= PILOT_TERMS, port)
            self.assertIn(port["pod"], ("l", "r"))
            self.assertEqual(port["pod"] == "l", port["position"][0] < 0.0, port["name"])
            self.assertAlmostEqual(float(np.linalg.norm(port["exhaust"])), 1.0, places=4)
            nearest = float(np.linalg.norm(self.xyz - np.array(port["position"]), axis=1).min())
            self.assertLess(nearest, 0.8, port["name"])
            tags |= set(port["tags"])
        self.assertEqual(tags, PILOT_TERMS, "every pilot term has at least one port")
        names = [p["name"] for p in rcs]
        self.assertEqual(len(names), len(set(names)))
        by_name = {p["name"]: p for p in rcs}
        for name, port in by_name.items():
            if name.startswith("r_"):
                twin = by_name["l_" + name[2:]]
                np.testing.assert_allclose(twin["position"], mirrored(port["position"]), atol=SYM_TOL)
                np.testing.assert_allclose(twin["exhaust"], mirrored(port["exhaust"]), atol=SYM_TOL)

    def test_cockpit_camera_is_in_the_bridge_looking_forward(self) -> None:
        cam = self.hp["cockpit_camera"]
        self.assertEqual(cam["forward"], [0.0, 0.0, -1.0])
        self.assertEqual(cam["up"], [0.0, 1.0, 0.0])
        eye = np.array([cam["position"]])
        self.assertEqual(eye[0, 0], 0.0)
        bridge = [c for c in self.hp["collision"] if c["name"].startswith("bridge")]
        self.assertTrue(bridge and any(inside_primitive(eye, c, 0.0)[0] for c in bridge), "inside the bridge plate")
        authored = self.authored(cam["position"])
        self.assertTrue(10.0 < authored[2] < 17.0, "on the capsule's dorsal plate")
        above = self.xyz[(np.abs(self.xyz[:, 0]) < 0.5) & (np.abs(self.xyz[:, 2] - eye[0, 2]) < 0.5) & (self.xyz[:, 1] > eye[0, 1])]
        self.assertGreater(len(above), 0, "hull over the eye")
        self.assertLess(float(above[:, 1].min() - eye[0, 1]), 1.5)

    def test_chase_anchor_is_behind_and_above_by_the_length(self) -> None:
        anchor = self.hp["chase_anchor"]["position"]
        self.assertEqual(anchor[0], 0.0)
        self.assertAlmostEqual(anchor[1], 0.3 * self.length, delta=0.5)
        self.assertAlmostEqual(anchor[2], 1.2 * self.length, delta=0.5)

    def test_nav_lights(self) -> None:
        nav = self.hp["nav_lights"]
        for key in ("port", "starboard", "top", "top_lamp", "top_lamp_range_m", "cabin", "cabin_range_m"):
            self.assertIn(key, nav)
        self.assertLess(nav["port"][0], -15.0, "outboard of the port nacelle (-X)")
        self.assertEqual(nav["port"], mirrored(nav["starboard"]))
        self.assertEqual(nav["top"][0], 0.0)
        under = self.xyz[(np.abs(self.xyz[:, 0]) < 0.6) & (np.abs(self.xyz[:, 2] - nav["top"][2]) < 0.6)]
        self.assertGreater(nav["top"][1], float(under[:, 1].max()), "the top light stands on the hull")
        self.assertLess(nav["top"][1] - float(under[:, 1].max()), 0.5)
        self.assertGreater(nav["top"][1], float(np.percentile(self.xyz[:, 1], 99.9)), "on the highest point: the fin")
        self.assertGreater(nav["top_lamp"][1], nav["top"][1])
        self.assertAlmostEqual(nav["top_lamp_range_m"], 0.3 * self.length, delta=2.0)
        self.assertAlmostEqual(nav["cabin_range_m"], 0.05 * self.length, delta=0.5)
        self.assertLess(float(np.linalg.norm(np.array(nav["cabin"]) - np.array(self.hp["cockpit_camera"]["position"]))), 3.0)

    def test_one_dorsal_turret_where_the_maintainer_placed_it(self) -> None:
        turrets = self.hp["turrets"]
        self.assertEqual([t["name"] for t in turrets], ["dorsal"], "Q19: turrets on top only, one on the Skylark")
        t = turrets[0]
        self.assertEqual(set(t), {"name", "position", "up", "arc_deg", "barrel_m"})
        np.testing.assert_allclose(self.authored(t["position"]), DORSAL_TURRET, atol=1e-3)
        self.assertEqual(t["up"], [0.0, 1.0, 0.0])
        self.assertEqual(t["arc_deg"], 200.0, "a hemisphere plus 10 degrees below the base")
        self.assertEqual(t["barrel_m"], 3.0, "the EA turret at two thirds of its size")
        # It sits on the body's ridge with nothing above it.
        p = np.array(t["position"])
        column = self.xyz[np.hypot(self.xyz[:, 0] - p[0], self.xyz[:, 2] - p[2]) < 0.8]
        self.assertGreater(len(column), 0)
        self.assertAlmostEqual(float(column[:, 1].max()), p[1], delta=0.3)
        fin = self.xyz[(np.abs(self.xyz[:, 0]) < 0.5) & (self.xyz[:, 1] > p[1] + 0.5) & (self.xyz[:, 2] > p[2] - 10.0)]
        self.assertGreater(float(fin[:, 2].min()), p[2] + 2.0, "ahead of the dorsal fin, nothing else above it")

    def test_the_turret_model_is_the_ea_turret_at_two_thirds(self) -> None:
        turret = self.manifest["turret"]
        self.assertEqual(turret["ply"], "skylark_transport_turret.ply")
        self.assertEqual(turret["obj"], "skylark_transport_turret.obj")
        self.assertEqual(turret["lighting"], "skylark_transport_turret.light")
        splats = read_ply(self.dir_a / turret["ply"]).to_splats()
        self.assertEqual(turret["splats"], len(splats))
        self.assertTrue(1_500 <= len(splats) <= 3_500, f"about 2 000 splats: {len(splats)}")
        self.assertEqual(set(turret), {"ply", "lighting", "obj", "splats", "spacing_m", "offset", "barrel_m", "trunnion", "muzzles"})
        self.assertEqual(turret["barrel_m"], 3.0)
        left, right = turret["muzzles"]
        self.assertEqual(left, mirrored(right))
        self.assertAlmostEqual(left[2], -3.0)
        self.assertAlmostEqual(abs(left[0]), 0.4 * 2.0 / 3.0, places=4, msg="the barrels 0.8 m apart at full size")
        local = frames.flip_xy(splats.xyz) + np.array(turret["offset"])
        self.assertAlmostEqual(float(local[:, 1].min()), 0.0, delta=0.1, msg="the base stands on the mount")
        self.assertAlmostEqual(float(local[:, 0].max()), 1.2, delta=0.1, msg="a round base 2.4 m across")
        self.assertLess(abs(float(local[:, 0].max() + local[:, 0].min())), 0.1, "centred on its turning axis")

    # --- collision -----------------------------------------------------------------------------------------------------
    def test_collision_primitives_cover_the_splats_and_stay_close(self) -> None:
        shapes = self.hp["collision"]
        names = [c["name"] for c in shapes]
        self.assertEqual(len(names), len(set(names)), "unique names")
        inside = np.zeros(len(self.xyz), dtype=bool)
        for c in shapes:
            inside |= inside_primitive(self.xyz, c, inflate=self.spacing)
        self.assertGreaterEqual(float(inside.mean()), 0.999, "at least 99.9 % of the LOD0 splat centres")
        lo, hi = self.xyz.min(axis=0), self.xyz.max(axis=0)
        for c in shapes:
            basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
            np.testing.assert_allclose(basis.T @ basis, np.eye(3), atol=1e-4)
            self.assertAlmostEqual(float(np.linalg.det(basis)), 1.0, places=3)
            if c["type"] == "box":
                corners = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]) * 0.5 * np.array(c["size"])
                extent = corners @ basis.T + np.array(c["position"])
            else:
                half = 0.5 * c["height"] - c["radius"]
                ends = np.array([[0, 0, -half], [0, 0, half]]) @ basis.T + np.array(c["position"])
                extent = np.concatenate([ends - c["radius"], ends + c["radius"]])
            self.assertTrue(np.all(extent.min(axis=0) >= lo - 1.0) and np.all(extent.max(axis=0) <= hi + 1.0), c["name"])

    def test_collision_is_mirror_symmetric(self) -> None:
        shapes = {c["name"]: c for c in self.hp["collision"]}
        for name, c in shapes.items():
            if name.endswith("_r") or "_r_" in name:
                twin = shapes[name.replace("_r", "_l", 1)]
                np.testing.assert_allclose(twin["position"], mirrored(c["position"]), atol=1e-4, err_msg=name)
            elif not (name.endswith("_l") or "_l_" in name):
                self.assertAlmostEqual(c["position"][0], 0.0, places=4, msg=name)

    # --- meshes ----------------------------------------------------------------------------------------------------------
    def test_the_fallback_mesh_and_chunk_meshes_hold_every_piece(self) -> None:
        parts = [p.part for p in sky.with_twins(sp.assemble(sky.STYLE))]
        self.assertNotIn("pedestal", {p.name for p in parts}, "the turret sits on the ridge itself")
        self.assertTrue(all(p.mesh.face_count > 0 for p in parts))
        self.assertEqual(len(self.obj.faces), sum(p.mesh.face_count for p in parts), "the hull OBJ is every piece")
        for entry in self.hp["chunks"]:
            expected = sum(p.mesh.face_count for p in parts if p.group == entry["name"])
            self.assertEqual(len(read_obj(self.dir_a / entry["obj"]).faces), expected, entry["name"])

    def test_fallback_obj_is_valid_and_matches_the_splat_bounds(self) -> None:
        v = self.obj.vertices
        self.assertTrue(np.all(np.isfinite(v)))
        slack = 2.0 * self.spacing  # the import test's frame slack
        np.testing.assert_allclose(v.min(axis=0), self.xyz.min(axis=0), atol=slack)
        np.testing.assert_allclose(v.max(axis=0), self.xyz.max(axis=0), atol=slack)
        self.assertIn("eac_hull_b3a982", self.obj.materials, "the Skylark's sand plating, its own material name")
        self.assertIn("eac_stripe_b8452b", self.obj.materials, "the bands reach the fallback mesh")

    # --- determinism, options --------------------------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        for out in self.out_a.files:
            self.assertEqual(sha256(out), sha256(self.dir_b / out.name), out.name)

    def test_a_different_seed_changes_the_splats_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = sky.build(BuildContext(Path(tmp), seed=7))
            self.assertNotEqual(sha256(Path(tmp) / sky.PLY_NAME), sha256(self.dir_a / sky.PLY_NAME))
            hp = json.loads((Path(tmp) / sky.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            authored = np.array(hp["turrets"][0]["position"]) + np.array(other.manifest["centroid_offset"])
            np.testing.assert_allclose(authored, DORSAL_TURRET, atol=1e-3)
            self.assertLess(float(np.abs(np.subtract(other.manifest["centroid_offset"], self.manifest["centroid_offset"])).max()), 0.25)
            self.assertEqual([c["name"] for c in hp["collision"]], [c["name"] for c in self.hp["collision"]])

    def test_spacing_option_scales_the_count_and_is_recorded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = sky.build(BuildContext(Path(tmp), seed=42, options={"spacing": 2.0 * sky.DEFAULT_SPACING_M}))
            self.assertLess(out.manifest["lods"][0]["splats"], 0.4 * len(self.splats))
            self.assertEqual(out.manifest["sampling"]["spacing_m"], 2.0 * sky.DEFAULT_SPACING_M)
            self.assertEqual(out.warnings, (), "the budget warning only applies at the default spacing")

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for bad in ({"spacing": 0.0}, {"overlap": -1.0}, {"thickness": 0}):
                with self.assertRaises(ValueError):
                    sky.build(BuildContext(Path(tmp), seed=1, options=bad))


if __name__ == "__main__":
    unittest.main()
