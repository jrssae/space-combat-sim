"""``narn_transport`` (M5-T14, AC12): files, budgets, frames, symmetry, chunk partition, collision coverage, the hardpoint
contract with ``turrets[]``, the turret model, colours and determinism."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import narn_transport as narn
from tools.procgen.core import frames, lighting
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.color import linear_to_srgb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.obj import read_obj
from tools.procgen.core.ply import read_ply

PILOT_TERMS = {
    "sway_left", "sway_right", "heave_up", "heave_down", "pitch_up", "pitch_down",
    "yaw_left", "yaw_right", "roll_left", "roll_right",
}  # fmt: skip
SYM_TOL = 1e-6
MAX_ROUND_TRIP_DEG = 1.5
LOD_AABB_TOLERANCE_M = 0.3  # test_splat_import.gd's floor
LARGE_HULL_EXTENT_M = 30.0  # ... and from this box size a coarse level may fall short by 1.25 of its spacing


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


def assert_lod_box(tc: unittest.TestCase, xyz: np.ndarray, manifest: dict, spacing: float, label: object) -> None:
    """test_splat_import.gd's rule for a coarse level's box against LOD0's: it may reach past it only by its centroid
    drift, and a big hull's may fall short by up to 1.25 of the level's spacing (the sharp extremes it misses)."""
    lo0, hi0 = np.array(manifest["aabb_min"]), np.array(manifest["aabb_max"])
    lo, hi = xyz.min(axis=0), xyz.max(axis=0)
    past = max(float((lo0 - lo).max()), float((hi - hi0).max()))
    short = max(float((lo - lo0).max()), float((hi0 - hi).max()))
    tc.assertLessEqual(past, max(LOD_AABB_TOLERANCE_M, 0.25 * spacing), (label, "past LOD0's box", past))
    big = float((hi0 - lo0).max()) >= LARGE_HULL_EXTENT_M
    tc.assertLessEqual(short, max(LOD_AABB_TOLERANCE_M, 1.25 * spacing) if big else LOD_AABB_TOLERANCE_M, (label, "short of LOD0's box", short))


def mirrored(v: list[float]) -> list[float]:
    return [-v[0], v[1], v[2]]


def angle_deg(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return np.degrees(np.arccos(np.clip(np.einsum("ij,ij->i", a, b), -1.0, 1.0)))


class NarnTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = narn.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = narn.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.splats = read_ply(cls.dir_a / narn.PLY_NAME).to_splats()
        cls.xyz = frames.flip_xy(cls.splats.xyz)
        cls.hp = json.loads((cls.dir_a / narn.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / narn.OBJ_NAME)
        cls.lod1 = read_ply(cls.dir_a / narn.LODS[1][0]).to_splats()
        cls.length = cls.hp["length_m"]

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    # --- files, manifest, budgets ------------------------------------------------------------------------------------
    def test_all_files_are_written_and_listed(self) -> None:
        expected = {narn.PLY_NAME, narn.OBJ_NAME, "narn_transport.mtl", narn.HARDPOINTS_NAME, "manifest.json"}
        expected |= {entry[0] for entry in narn.LODS.values()}
        expected |= {lod["lighting"] for lod in self.manifest["lods"]}
        for entry in self.hp["chunks"]:
            expected |= {entry["ply"], entry["lighting"], entry["obj"], entry["obj"].replace(".obj", ".mtl")}
        turret = self.manifest["turret"]
        expected |= {turret["ply"], turret["lighting"], turret["obj"], turret["obj"].replace(".obj", ".mtl")}
        self.assertEqual({p.name for p in self.dir_a.iterdir()}, expected)
        self.assertEqual({p.name for p in self.out_a.files}, expected)

    def test_lod0_is_inside_the_budget_and_counted_by_group(self) -> None:
        lod = self.manifest["lods"][0]
        self.assertEqual(lod["file"], narn.PLY_NAME)
        self.assertEqual(lod["splats"], len(self.splats))
        self.assertEqual(narn.SPLAT_BUDGET, (60_000, 90_000), "docs/assets-civilian.md: 75 000 (60 000 to 90 000)")
        self.assertTrue(narn.SPLAT_BUDGET[0] <= lod["splats"] <= narn.SPLAT_BUDGET[1], lod["splats"])
        self.assertEqual(self.out_a.warnings, ())
        self.assertEqual(list(self.manifest["counts"]), list(narn.CHUNK_ORDER))
        self.assertEqual(sum(self.manifest["counts"].values()), len(self.splats))
        self.assertEqual(self.manifest["files"], {"fallback_mesh": narn.OBJ_NAME, "hardpoints": narn.HARDPOINTS_NAME})
        self.assertEqual(self.manifest["chunk_lod"], 1)

    def test_lods_one_to_three_are_coarser_centred_and_keep_the_box(self) -> None:
        lod0 = self.manifest["lods"][0]
        self.assertEqual([e["level"] for e in self.manifest["lods"]], [0, 1, 2, 3])
        for level, (name, factor, _stream, share_range) in narn.LODS.items():
            entry = self.manifest["lods"][level]
            self.assertEqual(entry["file"], name)
            self.assertAlmostEqual(entry["spacing_m"], factor * narn.DEFAULT_SPACING_M)
            share = entry["splats"] / lod0["splats"]
            self.assertTrue(share_range[0] <= share <= share_range[1], (level, share))
            xyz = godot_xyz(self.dir_a / name)
            self.assertEqual(len(xyz), entry["splats"])
            self.assertLess(float(np.abs(xyz.mean(axis=0)).max()), 1e-3, "centred like LOD0")
            # Coarse samples miss sharp extremes (the prong tips, the slotted tower tops) but never reach past them.
            assert_lod_box(self, xyz, self.manifest, entry["spacing_m"], level)

    def test_coarse_levels_keep_lod0s_centroid(self) -> None:
        # Every level is drawn in LOD0's frame but centred on its own centroid, so the two must agree. Systematic sampling
        # keeps them within a quarter of the level's own spacing (far under a pixel where each level is shown).
        ctx = BuildContext(Path("unused"), seed=42)
        lod0 = np.array(self.manifest["centroid_offset"])
        for level in narn.LODS:
            _placed, offset = narn.level_parts(narn.DEFAULT_SPEC, narn.NARN, ctx, narn.DEFAULT_SPACING_M, level)
            drift = float(np.linalg.norm(offset - lod0))
            self.assertLess(drift, 0.25 * self.manifest["lods"][level]["spacing_m"], (level, drift))

    def test_the_lod_budgets_follow_the_design_table(self) -> None:
        # docs/assets-civilian.md: LOD1 18 750, LOD2 4 700, LOD3 1 200 for a 75 000 LOD0; the shares carry that.
        counts = [lod["splats"] for lod in self.manifest["lods"]]
        self.assertLess(counts[1], 0.3 * counts[0])
        self.assertLess(counts[2], 0.09 * counts[0])
        self.assertLess(counts[3], 0.025 * counts[0])
        self.assertGreater(counts[3], 500, "the farthest level still draws the ship's outline")

    def test_dimensions_match_the_design(self) -> None:
        self.assertAlmostEqual(self.hp["length_m"], 70.0, delta=0.5, msg="Q8: about 70 m")
        self.assertAlmostEqual(self.hp["span_m"], 46.0, delta=0.5, msg="the crescent's prongs and widest points")
        self.assertAlmostEqual(self.hp["height_m"], 18.05, delta=0.5, msg="the wiki's 18.7 m draught, the model's 18.05 m")
        self.assertEqual(
            self.manifest["dimensions_m"],
            {"length": self.hp["length_m"], "span": self.hp["span_m"], "height": self.hp["height_m"]},
        )

    # --- frames, symmetry, splats ----------------------------------------------------------------------------------------
    def test_ply_is_centred_and_the_aabb_matches_after_the_flip(self) -> None:
        np.testing.assert_allclose(self.xyz.mean(axis=0), [0.0, 0.0, 0.0], atol=1e-3)
        np.testing.assert_allclose(self.xyz.min(axis=0), self.manifest["aabb_min"], atol=2e-4)
        np.testing.assert_allclose(self.xyz.max(axis=0), self.manifest["aabb_max"], atol=2e-4)
        np.testing.assert_allclose(self.manifest["centroid_offset"][0], 0.0, atol=1e-9)

    def test_lod0_and_lod1_are_exactly_mirror_symmetric_in_x(self) -> None:
        for xyz in (self.xyz, frames.flip_xy(self.lod1.xyz)):
            np.testing.assert_allclose(sorted_rows(xyz), sorted_rows(xyz * np.array([-1.0, 1.0, 1.0])), atol=SYM_TOL)

    def test_splats_are_flat_oriented_opaque_discs(self) -> None:
        scale = self.splats.scale
        self.assertTrue(np.all(scale[:, 2] < scale[:, 0]))
        self.assertTrue(np.all(np.isfinite(self.splats.rgb)))
        self.assertTrue(np.all((self.splats.alpha > 0.0) & (self.splats.alpha < 1.0)))
        self.assertGreater(float(np.median(self.splats.alpha)), 0.9, "an opaque hull: the canopy is dark glass, not clear")

    def test_the_nose_points_forward_and_the_box_is_aft(self) -> None:
        z_lo, z_hi = self.xyz[:, 2].min(), self.xyz[:, 2].max()
        front = self.xyz[self.xyz[:, 2] < z_lo + 2.5]  # ahead of the cockpit's nose, 2.8 m behind the tips
        rear = self.xyz[self.xyz[:, 2] > z_hi - 3.0]
        self.assertGreater(float(np.abs(front[:, 0]).min()), 8.0, "two prong tips with the notch between them")
        self.assertLess(float(np.ptp(rear[:, 0])), 26.5, "the cargo box (25.5 m wide) ends the ship")
        self.assertGreater(float(np.ptp(self.xyz[:, 0])), 45.0)

    # --- colours -------------------------------------------------------------------------------------------------------
    def test_the_paint_reads_narn_green_with_a_light_grey_box_and_a_red_band(self) -> None:
        rgb = self.splats.rgb
        y, z = self.xyz[:, 1], self.xyz[:, 2]
        box_side = (np.abs(np.abs(self.xyz[:, 0]) - 12.75) < 0.05) & (z > np.percentile(z, 85))
        grey = np.median(rgb[box_side], axis=0)
        self.assertLess(float(np.ptp(grey)), 0.08, "the box is a neutral grey")
        self.assertGreater(float(grey.mean()), 0.3, "a light grey")
        prongs = (z < z.min() + 6.0) & (y > -1.0)
        green = np.median(rgb[prongs], axis=0)
        self.assertGreater(green[1], green[0] * 1.5, "the hull is green")
        self.assertGreater(green[1], green[2] * 1.2)
        red = (rgb[:, 0] > 2.5 * rgb[:, 1]) & (rgb[:, 0] > 0.2)
        self.assertGreater(int(red.sum()), 200, "the red band on each side of the crescent")
        self.assertAlmostEqual(float(self.xyz[red, 0].mean()), 0.0, delta=0.5, msg="one band on each side")
        self.assertGreater(float(np.abs(self.xyz[red, 0]).min()), 12.0, "on the crescent halves, outboard of the box")

    def test_paint_brightness_does_not_follow_the_normal(self) -> None:
        normals, lum = [], []
        ctx = BuildContext(Path("unused"), seed=42)
        for p in narn.build_parts(narn.DEFAULT_SPEC, narn.NARN, ctx, 0.5):
            if p.samples is None:
                continue
            paint = p.samples.material == next(
                (i for i, m in enumerate(p.samples.materials) if m.name == narn.NARN.material("hull").name), -1
            )
            normals.append(p.samples.normals[paint])
            lum.append(narn.colour_samples(p, narn.NARN)[paint].mean(axis=1))
        normals, lum = np.concatenate(normals), np.concatenate(lum)
        self.assertGreater(len(lum), 1000)
        for axis in range(3):
            self.assertLess(abs(float(np.corrcoef(normals[:, axis], lum)[0, 1])), 0.05, axis)

    # --- lighting records ----------------------------------------------------------------------------------------------
    def test_every_level_chunk_and_the_turret_has_matching_lighting_records(self) -> None:
        pairs = [(lod["file"], lod["lighting"]) for lod in self.manifest["lods"]]
        pairs += [(c["ply"], c["lighting"]) for c in self.hp["chunks"]]
        pairs.append((self.manifest["turret"]["ply"], self.manifest["turret"]["lighting"]))
        self.assertEqual(len(pairs), 4 + len(narn.CHUNK_ORDER) + 1)
        for ply_name, light_name in pairs:
            splats = read_ply(self.dir_a / ply_name).to_splats()
            records = lighting.read_lighting(self.dir_a / light_name)
            self.assertEqual(len(records), len(splats), light_name)
            self.assertLess(float(angle_deg(lighting.decode_normals(records), splats.normals).max()), MAX_ROUND_TRIP_DEG, light_name)
            self.assertTrue(np.all(records[:, 3] == 255), light_name)

    # --- chunks --------------------------------------------------------------------------------------------------------
    def test_chunks_partition_lod1_exactly(self) -> None:
        self.assertEqual([c["name"] for c in self.hp["chunks"]], list(narn.CHUNK_ORDER))
        self.assertEqual(self.manifest["chunks"], list(narn.CHUNK_ORDER))
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
        offsets = {name: np.array(c["offset"]) for name, c in chunks.items()}
        self.assertLess(offsets["wing_l"][0], -10.0)
        self.assertGreater(offsets["wing_r"][0], 10.0)
        np.testing.assert_allclose(offsets["wing_l"], mirrored(list(offsets["wing_r"])), atol=1e-4)
        self.assertAlmostEqual(float(offsets["cockpit"][0]), 0.0, places=4)
        self.assertAlmostEqual(float(offsets["box"][0]), 0.0, places=4)
        self.assertGreater(offsets["box"][2], offsets["cockpit"][2] + 15.0, "the cargo box is aft of the bow")
        for name, c in chunks.items():
            self.assertEqual(len(c["joint"]), 3, name)
            self.assertLess(float(np.linalg.norm(np.array(c["joint"]) - offsets[name])), 30.0, name)
        self.assertAlmostEqual(abs(chunks["wing_r"]["joint"][0]), abs(chunks["wing_l"]["joint"][0]), places=4)

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
        self.assertEqual((hp["asset_id"], hp["frame"], hp["units"]), ("narn_transport", "godot", "m"))
        self.assertEqual(hp["generator_version"], narn.GENERATOR_VERSION)
        self.assertEqual(hp["muzzles"], [], "no fixed guns: the turrets carry their own barrels")
        self.assertGreater(hp["mass_kg"], 100_000.0, "a heavy freighter")
        self.assertEqual(hp["center_of_mass"][0], 0.0)

    def test_two_pods_on_the_flank_towers_each_with_main_and_retro(self) -> None:
        pods = {p["name"]: p for p in self.hp["pods"]}
        self.assertEqual(set(pods), {"l", "r"})
        self.assertEqual((pods["l"]["side"], pods["r"]["side"]), ("left", "right"))
        for p in pods.values():
            self.assertEqual(p["main"]["exhaust"], [0.0, 0.0, 1.0])
            self.assertEqual(p["retro"]["exhaust"], [0.0, 0.0, -1.0])
            self.assertAlmostEqual(p["main"]["radius"], 1.4)
            self.assertAlmostEqual(p["retro"]["radius"], 1.0)
            self.assertGreater(p["main"]["position"][2], p["retro"]["position"][2] + 7.0, "main aft of retro, the tower between")
            self.assertGreater(abs(p["main"]["position"][0]), 13.0, "on the flanks, outboard of the box")
        np.testing.assert_allclose(pods["l"]["main"]["position"], mirrored(pods["r"]["main"]["position"]), atol=SYM_TOL)
        np.testing.assert_allclose(pods["l"]["retro"]["position"], mirrored(pods["r"]["retro"]["position"]), atol=SYM_TOL)
        self.assertLess(pods["l"]["main"]["position"][0], 0.0)

    def test_the_thrust_line_is_5_m_above_the_crescent_and_the_centre_of_mass_on_it(self) -> None:
        com_y = self.hp["center_of_mass"][1]
        for p in self.hp["pods"]:
            for key in ("main", "retro"):
                self.assertAlmostEqual(p[key]["position"][1], com_y, delta=1e-6, msg=(p["name"], key))
        thrust_authored = com_y + self.manifest["centroid_offset"][1]
        self.assertAlmostEqual(thrust_authored, 5.0, delta=1e-3)

    def test_the_main_exits_are_the_rearmost_points_at_their_axes_and_the_retros_on_the_towers(self) -> None:
        for p in self.hp["pods"]:
            d = self.xyz - np.array(p["main"]["position"])
            near_axis = np.hypot(d[:, 0], d[:, 1]) < p["main"]["radius"] + 0.2
            self.assertAlmostEqual(float(self.xyz[near_axis, 2].max()), p["main"]["position"][2], delta=0.15)
            nearest = float(np.linalg.norm(self.xyz - np.array(p["retro"]["position"]), axis=1).min())
            self.assertLess(nearest, 0.6, "the retro sits on the tower's front")

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

    def test_cockpit_camera_is_inside_the_cockpit_looking_forward(self) -> None:
        cam = self.hp["cockpit_camera"]
        self.assertEqual(cam["forward"], [0.0, 0.0, -1.0])
        self.assertEqual(cam["up"], [0.0, 1.0, 0.0])
        eye = np.array([cam["position"]])
        self.assertEqual(eye[0, 0], 0.0)
        cockpit = [c for c in self.hp["collision"] if c["name"].startswith("cockpit")]
        self.assertTrue(any(inside_primitive(eye, c, 0.0)[0] for c in cockpit), "inside the cockpit block")
        # Closed in by hull: the windscreen just ahead, the block's roof just above, the keel below.
        x, y, z = (self.xyz[:, k] - eye[0, k] for k in range(3))
        near_x = np.abs(x) < 0.5
        ahead = -z[near_x & (np.abs(y) < 0.5) & (z < 0.0)]
        above = y[near_x & (np.abs(z) < 0.5) & (y > 0.0)]
        below = -y[near_x & (np.abs(z) < 0.5) & (y < 0.0)]
        for label, gaps, reach in (("ahead", ahead, 1.5), ("above", above, 1.5), ("below", below, 5.0)):
            self.assertGreater(len(gaps), 0, f"no hull {label} of the eye: it is outside the ship")
            self.assertLess(float(gaps.min()), reach, f"the hull {label} of the eye is too far")

    def test_chase_anchor_is_behind_and_above_by_the_length(self) -> None:
        anchor = self.hp["chase_anchor"]["position"]
        self.assertEqual(anchor[0], 0.0)
        self.assertAlmostEqual(anchor[1], 0.3 * self.length, delta=0.5)
        self.assertAlmostEqual(anchor[2], 1.2 * self.length, delta=0.5)

    def test_nav_lights(self) -> None:
        nav = self.hp["nav_lights"]
        for key in ("port", "starboard", "top", "top_lamp", "top_lamp_range_m", "cabin", "cabin_range_m"):
            self.assertIn(key, nav)
        self.assertLess(nav["port"][0], -23.0, "past the crescent's widest point, to port (-X)")
        self.assertEqual(nav["port"], mirrored(nav["starboard"]))
        self.assertEqual(nav["top"][0], 0.0)
        under = self.xyz[(np.abs(self.xyz[:, 0]) < 1.0) & (np.abs(self.xyz[:, 2] - nav["top"][2]) < 1.0)]
        self.assertGreater(nav["top"][1], float(under[:, 1].max()), "the top light stands on the hull")
        self.assertLess(nav["top"][1] - float(under[:, 1].max()), 0.5)
        self.assertGreater(nav["top_lamp"][1], nav["top"][1])
        self.assertAlmostEqual(nav["top_lamp_range_m"], 0.3 * self.length, delta=3.0)
        self.assertAlmostEqual(nav["cabin_range_m"], 0.05 * self.length, delta=1.0)
        self.assertLess(float(np.linalg.norm(np.array(nav["cabin"]) - np.array(self.hp["cockpit_camera"]["position"]))), 3.0)

    def test_two_turrets_on_the_tower_tops(self) -> None:
        turrets = self.hp["turrets"]
        self.assertEqual([t["name"] for t in turrets], ["tower_l", "tower_r"])
        for t in turrets:
            self.assertEqual(set(t), {"name", "position", "up", "arc_deg", "barrel_m"})
            self.assertEqual(t["up"], [0.0, 1.0, 0.0])
            self.assertEqual(t["arc_deg"], 220.0, "docs/assets-civilian.md: 220 for the Narn's tower tops")
            self.assertEqual(t["barrel_m"], 3.0)
            # It stands on the tower's slotted top: hull right under it, nothing above it.
            p = np.array(t["position"])
            column = self.xyz[np.hypot(self.xyz[:, 0] - p[0], self.xyz[:, 2] - p[2]) < 0.6]
            self.assertGreater(len(column), 0, t["name"])
            self.assertAlmostEqual(float(column[:, 1].max()), p[1], delta=0.35, msg=t["name"])
        self.assertLess(turrets[0]["position"][0], -13.0)
        np.testing.assert_allclose(turrets[0]["position"], mirrored(turrets[1]["position"]), atol=SYM_TOL)
        # The tower tops are the highest points of the ship.
        self.assertGreater(turrets[1]["position"][1], float(np.percentile(self.xyz[:, 1], 99.9)) - 0.2)

    def test_the_turret_model_is_written_like_a_chunk(self) -> None:
        turret = self.manifest["turret"]
        self.assertEqual(turret["ply"], "narn_transport_turret.ply")
        self.assertEqual(turret["obj"], "narn_transport_turret.obj")
        self.assertEqual(turret["lighting"], "narn_transport_turret.light")
        splats = read_ply(self.dir_a / turret["ply"]).to_splats()
        self.assertEqual(turret["splats"], len(splats))
        self.assertTrue(1_500 <= len(splats) <= 2_600, f"about 2 000 splats: {len(splats)}")
        self.assertAlmostEqual(turret["spacing_m"], narn.TURRET_SPACING_M)
        # The same keys as parts/turret.py's entry (T12), so the game reads every civilian's turret one way.
        self.assertEqual(set(turret), {"ply", "lighting", "obj", "splats", "spacing_m", "offset", "barrel_m", "trunnion", "muzzles"})
        self.assertEqual(turret["barrel_m"], 3.0)
        left, right = turret["muzzles"]
        self.assertLess(left[0], 0.0)
        self.assertEqual(left, mirrored(right))
        self.assertAlmostEqual(left[2], -3.0, msg="barrel_m ahead of the turning axis")
        self.assertEqual(turret["trunnion"][0], 0.0)
        self.assertEqual(turret["trunnion"][2], 0.0, "on the turning axis")
        self.assertAlmostEqual(turret["trunnion"][1], left[1], msg="the barrels elevate about their own axis")
        np.testing.assert_allclose(splats.xyz.mean(axis=0), [0.0, 0.0, 0.0], atol=1e-4)
        # Back in the turret's own frame (pivot at the origin, +Y up, barrels along -Z), via its offset.
        local = frames.flip_xy(splats.xyz) + np.array(turret["offset"])
        self.assertAlmostEqual(float(local[:, 1].min()), 0.0, delta=0.1, msg="the base stands on the mount")
        self.assertAlmostEqual(float(-local[:, 2].min()), 3.0, delta=0.1, msg="the muzzles are barrel_m ahead of the pivot")
        self.assertAlmostEqual(float(local[:, 0].max()), 1.3, delta=0.15, msg="a six-sided base 2.6 m across")
        np.testing.assert_allclose(sorted_rows(local), sorted_rows(local * np.array([-1.0, 1.0, 1.0])), atol=1e-5)
        red = (splats.rgb[:, 0] > 2.5 * splats.rgb[:, 1]) & (splats.rgb[:, 0] > 0.2)
        green = splats.rgb[:, 1] > 1.3 * splats.rgb[:, 0]
        self.assertGreater(int(red.sum()), 50, "the red band")
        self.assertGreater(int(green.sum()), len(splats) // 4, "dark green")
        obj = read_obj(self.dir_a / turret["obj"])
        lo, hi = obj.vertices.min(axis=0), obj.vertices.max(axis=0)
        self.assertTrue(np.all(frames.flip_xy(splats.xyz).min(axis=0) >= lo - 0.1))
        self.assertTrue(np.all(frames.flip_xy(splats.xyz).max(axis=0) <= hi + 0.1))

    # --- collision -----------------------------------------------------------------------------------------------------
    def test_collision_primitives_cover_the_splats_and_stay_close(self) -> None:
        shapes = self.hp["collision"]
        names = [c["name"] for c in shapes]
        self.assertEqual(len(names), len(set(names)), "unique names")
        inside = np.zeros(len(self.xyz), dtype=bool)
        for c in shapes:
            inside |= inside_primitive(self.xyz, c, inflate=narn.DEFAULT_SPACING_M)
        self.assertGreaterEqual(float(inside.mean()), 0.999, "the hit volumes hold the hull: 99.9 % of the LOD0 splat centres")
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
        # Every side primitive (an `l` or `r` in its name) has a mirrored twin of the same size; the rest are centred.
        shapes = {c["name"]: c for c in self.hp["collision"]}
        swap = {"l": "r", "r": "l"}
        for name, c in shapes.items():
            parts = name.split("_")
            sides = [i for i, p in enumerate(parts) if p in swap]
            if not sides:
                self.assertAlmostEqual(c["position"][0], 0.0, places=4, msg=name)
                continue
            side = parts[sides[0]]
            self.assertEqual(c["position"][0] < 0.0, side == "l", f"{name} is on its own side")
            parts[sides[0]] = swap[side]
            twin_name = "_".join(parts)
            self.assertIn(twin_name, shapes, f"{name} has no mirrored twin")
            twin = shapes[twin_name]
            np.testing.assert_allclose(twin["position"], mirrored(c["position"]), atol=1e-4, err_msg=name)
            self.assertEqual(twin.get("size"), c.get("size"), name)

    # --- meshes ----------------------------------------------------------------------------------------------------------
    def test_fallback_obj_is_valid_and_matches_the_splat_bounds(self) -> None:
        v = self.obj.vertices
        self.assertGreater(len(v), 0)
        self.assertTrue(np.all(np.isfinite(v)))
        slack = 2.0 * narn.DEFAULT_SPACING_M  # the import test's frame slack
        np.testing.assert_allclose(v.min(axis=0), self.xyz.min(axis=0), atol=slack)
        np.testing.assert_allclose(v.max(axis=0), self.xyz.max(axis=0), atol=slack)
        self.assertIn("nr_hull", self.obj.materials)
        self.assertIn("nr_stripe", self.obj.materials, "the painted regions reach the fallback mesh")

    # --- determinism, options --------------------------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        for out in self.out_a.files:
            self.assertEqual(sha256(out), sha256(self.dir_b / out.name), out.name)

    def test_a_different_seed_changes_the_splats_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = narn.build(BuildContext(Path(tmp), seed=7))
            self.assertNotEqual(sha256(Path(tmp) / narn.PLY_NAME), sha256(self.dir_a / narn.PLY_NAME))
            hp = json.loads((Path(tmp) / narn.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            self.assertEqual([t["name"] for t in hp["turrets"]], [t["name"] for t in self.hp["turrets"]])
            # The centroid (the frame's origin) moves with the random samples; back in the authored frame nothing moves.
            def authored(doc: dict, manifest: dict) -> np.ndarray:
                return np.array([t["position"] for t in doc["turrets"]]) + np.array(manifest["centroid_offset"])

            np.testing.assert_allclose(authored(hp, other.manifest), authored(self.hp, self.manifest), atol=1e-3)
            self.assertLess(float(np.abs(np.subtract(other.manifest["centroid_offset"], self.manifest["centroid_offset"])).max()), 0.25)
            self.assertEqual([c["name"] for c in hp["collision"]], [c["name"] for c in self.hp["collision"]])

    def test_spacing_option_scales_the_count_and_is_recorded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = narn.build(BuildContext(Path(tmp), seed=42, options={"spacing": 2.0 * narn.DEFAULT_SPACING_M}))
            count = out.manifest["lods"][0]["splats"]
            self.assertLess(count, 0.4 * len(self.splats))
            self.assertEqual(out.manifest["sampling"]["spacing_m"], 2.0 * narn.DEFAULT_SPACING_M)
            self.assertEqual(out.warnings, (), "the budget warning only applies at the default spacing")

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for bad in ({"spacing": 0.0}, {"overlap": -1.0}, {"thickness": 0}):
                with self.assertRaises(ValueError):
                    narn.build(BuildContext(Path(tmp), seed=1, options=bad))


class NarnStyleTests(unittest.TestCase):
    def test_style_provides_every_role_and_the_extras(self) -> None:
        from tools.procgen.styles import REQUIRED_ROLES
        from tools.procgen.styles.narn import NARN

        for role in (*REQUIRED_ROLES, "cargo_panel"):
            self.assertIn(role, NARN.materials, role)
        self.assertEqual(NARN.name, "narn")
        self.assertAlmostEqual(NARN.panel_size_m, 2.4)
        self.assertAlmostEqual(NARN.panel_line_width_m, 0.25)
        self.assertAlmostEqual(NARN.panel_tint_jitter, 0.08)
        self.assertEqual(NARN.material("canopy_glass").transmittance, 0.0, "dark opaque glass: there is no cockpit inside")

    def test_the_confirmed_scheme_is_painted_as_written(self) -> None:
        # Q19: the maintainer confirmed the written scheme; a lift waits for T16's GPU check and the maintainer's OK.
        from tools.procgen.styles.narn import NARN

        def srgb_hex(role: str) -> int:
            r, g, b = (round(float(c) * 255) for c in linear_to_srgb(np.array(NARN.material(role).albedo)))
            return (r << 16) | (g << 8) | b

        for role, value in (("hull", 0x2E4A3B), ("hull_dark", 0x1E2E25), ("cargo_panel", 0x4E7552), ("hull_panel", 0xB7BAB5),
                            ("stripe", 0xA3241C), ("hazard", 0xD2B032), ("hazard_dark", 0x262626), ("canopy_glass", 0x10201A),
                            ("canopy_frame", 0x1E2E25), ("nozzle", 0x3A3A36), ("nozzle_throat", 0x141413)):  # fmt: skip
            got = srgb_hex(role)
            for shift in (16, 8, 0):
                self.assertAlmostEqual((got >> shift) & 255, (value >> shift) & 255, delta=1, msg=role)


if __name__ == "__main__":
    unittest.main()
