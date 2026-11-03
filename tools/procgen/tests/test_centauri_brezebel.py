"""``centauri_brezebel`` (M5-T15, AC12): files, budgets, frames, symmetry, chunk partition, collision coverage, the
hardpoint contract with its one dorsal turret (Q19), the turret model, the confirmed colours and determinism."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import centauri_brezebel as brez
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
    cos = np.einsum("ij,ij->i", a, b) / (np.linalg.norm(a, axis=1) * np.linalg.norm(b, axis=1))
    return np.degrees(np.arccos(np.clip(cos, -1.0, 1.0)))


def ray_hits(origin: np.ndarray, direction: np.ndarray, vertices: np.ndarray, faces: np.ndarray) -> np.ndarray:
    """Distances along the ray to every triangle it crosses (Moller-Trumbore), ahead of the origin only."""
    a, b, c = vertices[faces[:, 0]], vertices[faces[:, 1]], vertices[faces[:, 2]]
    e1, e2 = b - a, c - a
    p = np.cross(direction, e2)
    det = np.einsum("ij,ij->i", e1, p)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    s = origin - a
    u = np.einsum("ij,ij->i", s, p) * inv
    q = np.cross(s, e1)
    v = (q @ direction) * inv
    t = np.einsum("ij,ij->i", e2, q) * inv
    hit = ok & (u >= 0.0) & (v >= 0.0) & (u + v <= 1.0) & (t > 0.0)
    return t[hit]


def srgb_hex(albedo: tuple[float, float, float]) -> int:
    r, g, b = (round(float(c) * 255) for c in linear_to_srgb(np.array(albedo)))
    return (r << 16) | (g << 8) | b


class CentauriBrezebelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = brez.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = brez.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.splats = read_ply(cls.dir_a / brez.PLY_NAME).to_splats()
        cls.xyz = frames.flip_xy(cls.splats.xyz)
        cls.hp = json.loads((cls.dir_a / brez.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / brez.OBJ_NAME)
        cls.lod1 = read_ply(cls.dir_a / brez.LODS[1][0]).to_splats()
        cls.length = cls.hp["length_m"]
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.authored = cls.xyz + cls.offset  # back in the design references' frame: nose at z = 0

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    # --- registry, files, manifest, budgets --------------------------------------------------------------------------
    def test_the_asset_is_registered(self) -> None:
        self.assertIs(ASSETS["centauri_brezebel"], brez.build)
        self.assertEqual(brez.ASSET_ID, "centauri_brezebel")

    def test_all_files_are_written_and_listed(self) -> None:
        expected = {brez.PLY_NAME, brez.OBJ_NAME, "centauri_brezebel.mtl", brez.HARDPOINTS_NAME, "manifest.json"}
        expected |= {entry[0] for entry in brez.LODS.values()}
        expected |= {lod["lighting"] for lod in self.manifest["lods"]}
        for entry in self.hp["chunks"]:
            expected |= {entry["ply"], entry["lighting"], entry["obj"], entry["obj"].replace(".obj", ".mtl")}
        turret = self.manifest["turret"]
        expected |= {turret["ply"], turret["lighting"], turret["obj"], turret["obj"].replace(".obj", ".mtl")}
        self.assertEqual({p.name for p in self.dir_a.iterdir()}, expected)
        self.assertEqual({p.name for p in self.out_a.files}, expected)

    def test_lod0_is_inside_the_budget_and_counted_by_group(self) -> None:
        lod = self.manifest["lods"][0]
        self.assertEqual(lod["file"], brez.PLY_NAME)
        self.assertEqual(lod["splats"], len(self.splats))
        self.assertEqual(brez.SPLAT_BUDGET, (55_000, 85_000), "docs/assets-civilian.md: 70 000 (55 000 to 85 000)")
        self.assertTrue(brez.SPLAT_BUDGET[0] <= lod["splats"] <= brez.SPLAT_BUDGET[1], lod["splats"])
        self.assertEqual(self.out_a.warnings, ())
        self.assertEqual(brez.CHUNK_ORDER, ("bow", "arm_l", "arm_r"), "docs/assets-civilian.md: bow and the two arms")
        self.assertEqual(list(self.manifest["counts"]), list(brez.CHUNK_ORDER))
        self.assertEqual(sum(self.manifest["counts"].values()), len(self.splats))
        self.assertEqual(self.manifest["files"], {"fallback_mesh": brez.OBJ_NAME, "hardpoints": brez.HARDPOINTS_NAME})
        self.assertEqual(self.manifest["chunk_lod"], 1)

    def test_lods_one_to_three_are_coarser_centred_and_keep_the_box(self) -> None:
        lod0 = self.manifest["lods"][0]
        self.assertEqual([e["level"] for e in self.manifest["lods"]], [0, 1, 2, 3])
        for level, (name, factor, _stream, share_range) in brez.LODS.items():
            entry = self.manifest["lods"][level]
            self.assertEqual(entry["file"], name)
            self.assertAlmostEqual(entry["spacing_m"], factor * brez.DEFAULT_SPACING_M)
            share = entry["splats"] / lod0["splats"]
            self.assertTrue(share_range[0] <= share <= share_range[1], (level, share))
            xyz = godot_xyz(self.dir_a / name)
            self.assertEqual(len(xyz), entry["splats"])
            self.assertLess(float(np.abs(xyz.mean(axis=0)).max()), 1e-3, "centred like LOD0")
            tolerance = max(LOD_AABB_TOLERANCE_M, brez.LOD_AABB_SPACINGS * entry["spacing_m"])
            np.testing.assert_allclose(xyz.min(axis=0), self.manifest["aabb_min"], atol=tolerance)
            np.testing.assert_allclose(xyz.max(axis=0), self.manifest["aabb_max"], atol=tolerance)

    def test_the_lod_budgets_follow_the_design_table(self) -> None:
        # docs/assets-civilian.md: LOD1 17 500, LOD2 4 400, LOD3 1 100 for a 70 000 LOD0; the shares carry that.
        counts = [lod["splats"] for lod in self.manifest["lods"]]
        self.assertLess(counts[1], 0.3 * counts[0])
        self.assertLess(counts[2], 0.09 * counts[0])
        self.assertLess(counts[3], 0.025 * counts[0])
        self.assertGreater(counts[3], 500, "the farthest level still draws the ship's outline")

    def test_dimensions_match_the_reference(self) -> None:
        self.assertAlmostEqual(self.hp["length_m"], 60.0, delta=0.3, msg="Q11: about 60 m")
        self.assertAlmostEqual(self.hp["span_m"], 39.12, delta=0.4, msg="the bow's widest points")
        self.assertAlmostEqual(self.hp["height_m"], 25.27, delta=0.5, msg="over the tip fins")
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

    def test_the_authored_frame_starts_at_the_nose(self) -> None:
        self.assertAlmostEqual(float(self.authored[:, 2].min()), 0.0, delta=0.1, msg="the nose tip at z = 0")
        self.assertAlmostEqual(float(self.authored[:, 2].max()), 60.0, delta=0.15, msg="the arm tips at z = 60")

    def test_lod0_and_lod1_are_exactly_mirror_symmetric_in_x(self) -> None:
        for xyz in (self.xyz, frames.flip_xy(self.lod1.xyz)):
            np.testing.assert_allclose(sorted_rows(xyz), sorted_rows(xyz * np.array([-1.0, 1.0, 1.0])), atol=SYM_TOL)

    def test_splats_are_flat_oriented_opaque_discs(self) -> None:
        scale = self.splats.scale
        self.assertTrue(np.all(scale[:, 2] < scale[:, 0]))
        self.assertTrue(np.all(np.isfinite(self.splats.rgb)))
        self.assertTrue(np.all((self.splats.alpha > 0.0) & (self.splats.alpha < 1.0)))
        self.assertGreater(float(np.median(self.splats.alpha)), 0.9, "an opaque hull")

    def test_a_round_bow_and_two_arms_reaching_aft(self) -> None:
        a = self.authored
        x, z = np.abs(a[:, 0]), a[:, 2]
        # The bow is widest about 17 m back from the nose, 39 m across.
        widest = a[np.argmax(x)]
        self.assertAlmostEqual(float(widest[2]), 17.0, delta=1.5)
        # Behind the engine (z 31.4) nothing lies between the arms' inner walls (x +-10.4) but the fins' leaning tops.
        aft = (z > 32.0) & (x < 8.8)
        self.assertEqual(int(aft.sum()), 0, "an open U between the arms")
        # The arms taper: narrower at the tip than at the root.
        root, tip = x[(z > 20.0) & (z < 21.0)].max(), x[(z > 57.0) & (z < 58.0)].max()
        self.assertGreater(float(root - tip), 4.0)
        # The tip fins reach about 12.5 m above and below the hull's centre plane.
        fins = a[(z > 41.0) & (z < 57.5)]
        self.assertGreater(float(fins[:, 1].max() - brez.CENTRE_Y), 12.2)
        self.assertLess(float(fins[:, 1].min() - brez.CENTRE_Y), -12.2)

    def test_the_hull_is_symmetric_about_its_centre_plane(self) -> None:
        # The model's hull and fins are mirror images about y = CENTRE_Y (only the fin-tip lights stand on top).
        body = self.authored[np.abs(self.authored[:, 1] - brez.CENTRE_Y) < 12.4]
        top, bottom = body[:, 1].max() - brez.CENTRE_Y, brez.CENTRE_Y - body[:, 1].min()
        self.assertAlmostEqual(float(top), float(bottom), delta=0.3)

    # --- colours -------------------------------------------------------------------------------------------------------
    def test_the_paint_reads_violet_with_gold_caps_a_pale_rim_band_and_windows(self) -> None:
        rgb, a = self.splats.rgb, self.authored
        # The arms' top faces are plain violet plating: blue over red over green.
        arm_top = (np.abs(a[:, 0]) > 12.0) & (a[:, 2] > 44.0) & (a[:, 2] < 56.0) & (np.abs(a[:, 1] - brez.CENTRE_Y) < 2.6)
        violet = np.median(rgb[arm_top], axis=0)
        self.assertGreater(violet[2], violet[0] * 2.0, "violet: much more blue than red")
        self.assertGreater(violet[0], violet[1] * 1.2, "violet, not blue: more red than green")
        gold = (rgb[:, 0] > 0.4) & (rgb[:, 1] > 0.3) & (rgb[:, 2] < 0.2)
        self.assertGreater(int(gold.sum()), 200, "the tip fins' gold caps")
        self.assertGreater(float(np.abs(a[gold, 1] - brez.CENTRE_Y).min()), 10.0, "the caps are on the fins' tips")
        pale = (rgb.min(axis=1) > 0.55) & (np.ptp(rgb, axis=1) < 0.25)
        rim = pale & (a[:, 2] < 19.5) & (np.abs(a[:, 1] - brez.CENTRE_Y) < 1.0)
        self.assertGreater(int(rim.sum()), 300, "the pale lavender band round the bow's rim")
        windows = pale & (a[:, 2] < 3.5) & (a[:, 1] > 1.5) & (np.abs(a[:, 0]) < 3.5)
        self.assertGreater(int(windows.sum()), 10, "the row of windows on the dorsal fitting's front")

    def test_paint_brightness_does_not_follow_the_normal(self) -> None:
        normals, lum = [], []
        ctx = BuildContext(Path("unused"), seed=42)
        hull = brez.CENTAURI.material("hull").name
        for p in brez.build_parts(brez.CENTAURI, ctx, 0.5):
            paint = p.samples.material == next((i for i, m in enumerate(p.samples.materials) if m.name == hull), -1)
            normals.append(p.samples.normals[paint])
            lum.append(brez.colour_samples(p, brez.CENTAURI)[paint].mean(axis=1))
        normals, lum = np.concatenate(normals), np.concatenate(lum)
        self.assertGreater(len(lum), 1000)
        for axis in range(3):
            self.assertLess(abs(float(np.corrcoef(normals[:, axis], lum)[0, 1])), 0.05, axis)

    # --- lighting records ----------------------------------------------------------------------------------------------
    def test_every_level_chunk_and_the_turret_has_matching_lighting_records(self) -> None:
        pairs = [(lod["file"], lod["lighting"]) for lod in self.manifest["lods"]]
        pairs += [(c["ply"], c["lighting"]) for c in self.hp["chunks"]]
        pairs.append((self.manifest["turret"]["ply"], self.manifest["turret"]["lighting"]))
        self.assertEqual(len(pairs), 4 + len(brez.CHUNK_ORDER) + 1)
        for ply_name, light_name in pairs:
            splats = read_ply(self.dir_a / ply_name).to_splats()
            records = lighting.read_lighting(self.dir_a / light_name)
            self.assertEqual(len(records), len(splats), light_name)
            self.assertLess(float(angle_deg(lighting.decode_normals(records), splats.normals).max()), MAX_ROUND_TRIP_DEG, light_name)
            self.assertTrue(np.all(records[:, 3] == 255), light_name)

    # --- chunks --------------------------------------------------------------------------------------------------------
    def test_chunks_partition_lod1_exactly(self) -> None:
        self.assertEqual([c["name"] for c in self.hp["chunks"]], list(brez.CHUNK_ORDER))
        self.assertEqual(self.manifest["chunks"], list(brez.CHUNK_ORDER))
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
        self.assertLess(offsets["arm_l"][0], -10.0)
        self.assertGreater(offsets["arm_r"][0], 10.0)
        np.testing.assert_allclose(offsets["arm_l"], mirrored(list(offsets["arm_r"])), atol=1e-4)
        self.assertAlmostEqual(float(offsets["bow"][0]), 0.0, places=4)
        self.assertGreater(offsets["arm_r"][2], offsets["bow"][2] + 15.0, "the arms reach aft of the bow")
        for name, c in chunks.items():
            self.assertEqual(len(c["joint"]), 3, name)
            self.assertLess(float(np.linalg.norm(np.array(c["joint"]) - offsets[name])), 30.0, name)
        np.testing.assert_allclose(chunks["arm_l"]["joint"], mirrored(chunks["arm_r"]["joint"]), atol=1e-4)
        # An arm breaks away where it leaves the bow's rear face (z 19 in the authored frame).
        self.assertAlmostEqual(chunks["arm_r"]["joint"][2] + self.offset[2], 19.0, delta=0.5)

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
        self.assertEqual((hp["asset_id"], hp["frame"], hp["units"]), ("centauri_brezebel", "godot", "m"))
        self.assertEqual(hp["generator_version"], brez.GENERATOR_VERSION)
        self.assertEqual(hp["muzzles"], [], "no fixed guns: the turret carries its own barrels")
        self.assertGreater(hp["mass_kg"], 100_000.0, "a heavy liner")
        self.assertEqual(hp["center_of_mass"][0], 0.0)

    def test_two_pods_main_in_the_arm_tips_retro_on_the_bow_ahead_of_the_fairings(self) -> None:
        pods = {p["name"]: p for p in self.hp["pods"]}
        self.assertEqual(set(pods), {"l", "r"})
        self.assertEqual((pods["l"]["side"], pods["r"]["side"]), ("left", "right"))
        for p in pods.values():
            self.assertEqual(p["main"]["exhaust"], [0.0, 0.0, 1.0])
            self.assertEqual(p["retro"]["exhaust"], [0.0, 0.0, -1.0])
            self.assertAlmostEqual(p["main"]["radius"], 1.2)
            self.assertAlmostEqual(p["retro"]["radius"], 1.0)
            main = np.array(p["main"]["position"]) + self.offset
            retro = np.array(p["retro"]["position"]) + self.offset
            self.assertAlmostEqual(abs(main[0]), 12.0, delta=0.25, msg="in the arm's tip")
            self.assertAlmostEqual(main[2], 60.0, delta=0.05)
            self.assertAlmostEqual(abs(retro[0]), 14.6, delta=0.25, msg="on the fairing's axis")
            self.assertAlmostEqual(retro[2], brez.DEFAULT_SPEC.lens.rim_z(14.6), delta=1e-3, msg="where that axis meets the bow's rim")
            self.assertAlmostEqual(retro[2], 5.7, delta=0.1)
        np.testing.assert_allclose(pods["l"]["main"]["position"], mirrored(pods["r"]["main"]["position"]), atol=SYM_TOL)
        np.testing.assert_allclose(pods["l"]["retro"]["position"], mirrored(pods["r"]["retro"]["position"]), atol=SYM_TOL)
        self.assertLess(pods["l"]["main"]["position"][0], 0.0)

    def test_the_thrust_line_is_the_centre_plane_and_the_centre_of_mass_on_it(self) -> None:
        com_y = self.hp["center_of_mass"][1]
        for p in self.hp["pods"]:
            for key in ("main", "retro"):
                self.assertAlmostEqual(p[key]["position"][1], com_y, delta=1e-6, msg=(p["name"], key))
        self.assertAlmostEqual(com_y + self.offset[1], brez.CENTRE_Y, delta=1e-3)

    def test_each_retro_fires_clear_of_the_hull(self) -> None:
        # The depth proxy (the fallback mesh) hides a plume inside the hull: the retro's forward ray leaves the skin within
        # half a metre of the nozzle and never meets the hull again, and the skin is right behind the nozzle.
        v, f = self.obj.vertices, self.obj.faces
        for p in self.hp["pods"]:
            nozzle, exhaust = np.array(p["retro"]["position"]), np.array(p["retro"]["exhaust"])
            ahead = ray_hits(nozzle, exhaust, v, f)
            self.assertTrue(np.all(ahead <= 0.5), (p["name"], ahead[ahead > 0.5][:5]))
            behind = ray_hits(nozzle + 0.5 * exhaust, -exhaust, v, f)
            self.assertGreater(len(behind), 0, p["name"])
            self.assertLess(float(behind.min()), 1.0, "the nozzle sits on the skin")

    def test_the_main_exits_are_the_rearmost_points_at_their_axes(self) -> None:
        for p in self.hp["pods"]:
            d = self.xyz - np.array(p["main"]["position"])
            near_axis = np.hypot(d[:, 0], d[:, 1]) < p["main"]["radius"] + 0.2
            self.assertAlmostEqual(float(self.xyz[near_axis, 2].max()), p["main"]["position"][2], delta=0.15)

    def test_cosmetic_rcs_ports_carry_pilot_terms_and_sit_on_the_hull(self) -> None:
        rcs = self.hp["rcs"]
        self.assertGreaterEqual(len(rcs), 16, "the twelve blocks in the engine bay and the four fin tips")
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

    def test_cockpit_camera_is_behind_the_window_row_looking_forward(self) -> None:
        cam = self.hp["cockpit_camera"]
        self.assertEqual(cam["forward"], [0.0, 0.0, -1.0])
        self.assertEqual(cam["up"], [0.0, 1.0, 0.0])
        eye = np.array(cam["position"])
        np.testing.assert_allclose(eye + self.offset, [0.0, 3.5, 2.5], atol=1e-3)
        fitting = [c for c in self.hp["collision"] if c["name"].startswith("dorsal")]
        self.assertTrue(any(inside_primitive(eye[None, :], c, 0.0)[0] for c in fitting), "inside the dorsal fitting")
        above = self.xyz[(np.abs(self.xyz[:, 0]) < 0.5) & (np.abs(self.xyz[:, 2] - eye[2]) < 0.5) & (self.xyz[:, 1] > eye[1])]
        self.assertGreater(len(above), 0, "hull over the eye: it is not outside the ship")
        self.assertLess(float(above[:, 1].min() - eye[1]), 1.5)

    def test_chase_anchor_is_behind_and_above_by_the_length(self) -> None:
        anchor = self.hp["chase_anchor"]["position"]
        self.assertEqual(anchor[0], 0.0)
        self.assertAlmostEqual(anchor[1], 0.3 * self.length, delta=0.5)
        self.assertAlmostEqual(anchor[2], 1.2 * self.length, delta=0.5)

    def test_nav_lights(self) -> None:
        nav = self.hp["nav_lights"]
        for key in ("port", "starboard", "top", "top_lamp", "top_lamp_range_m", "cabin", "cabin_range_m"):
            self.assertIn(key, nav)
        self.assertLess(nav["port"][0], -19.5, "past the bow's widest point, to port (-X)")
        self.assertEqual(nav["port"], mirrored(nav["starboard"]))
        self.assertAlmostEqual(nav["starboard"][2] + self.offset[2], 17.0, delta=0.5)
        self.assertEqual(nav["top"][0], 0.0)
        under = self.xyz[(np.abs(self.xyz[:, 0]) < 1.0) & (np.abs(self.xyz[:, 2] - nav["top"][2]) < 1.0)]
        self.assertGreater(nav["top"][1], float(under[:, 1].max()), "the top light stands on the hull")
        self.assertLess(nav["top"][1] - float(under[:, 1].max()), 0.5)
        self.assertGreater(nav["top_lamp"][1], nav["top"][1])
        self.assertAlmostEqual(nav["top_lamp_range_m"], 0.3 * self.length, delta=3.0)
        self.assertAlmostEqual(nav["cabin_range_m"], 0.05 * self.length, delta=1.0)
        self.assertLess(float(np.linalg.norm(np.array(nav["cabin"]) - np.array(self.hp["cockpit_camera"]["position"]))), 3.0)

    def test_one_turret_on_top_of_the_dorsal_fitting(self) -> None:
        # Q19: turrets on top only; the Brezebel keeps its one dorsal mount.
        turrets = self.hp["turrets"]
        self.assertEqual([t["name"] for t in turrets], ["dorsal"])
        t = turrets[0]
        self.assertEqual(set(t), {"name", "position", "up", "arc_deg", "barrel_m"})
        np.testing.assert_allclose(np.array(t["position"]) + self.offset, [0.0, 4.3, 7.0], atol=1e-3)
        self.assertEqual(t["up"], [0.0, 1.0, 0.0])
        self.assertEqual(t["arc_deg"], 200.0, "docs/assets-civilian.md: 200 for a dorsal mount")
        self.assertEqual(t["barrel_m"], 2.6)
        p = np.array(t["position"])
        column = self.xyz[np.hypot(self.xyz[:, 0] - p[0], self.xyz[:, 2] - p[2]) < 0.6]
        self.assertGreater(len(column), 0)
        self.assertAlmostEqual(float(column[:, 1].max()), p[1], delta=0.2, msg="it stands on the fitting's top")

    def test_the_turret_model_is_written_like_a_chunk(self) -> None:
        turret = self.manifest["turret"]
        self.assertEqual(turret["ply"], "centauri_brezebel_turret.ply")
        self.assertEqual(turret["obj"], "centauri_brezebel_turret.obj")
        self.assertEqual(turret["lighting"], "centauri_brezebel_turret.light")
        splats = read_ply(self.dir_a / turret["ply"]).to_splats()
        self.assertEqual(turret["splats"], len(splats))
        self.assertTrue(brez.TURRET_SPLATS[0] <= len(splats) <= brez.TURRET_SPLATS[1], f"about 2 000 splats: {len(splats)}")
        self.assertAlmostEqual(turret["spacing_m"], brez.TURRET_SPACING_M)
        self.assertEqual(set(turret), {"ply", "lighting", "obj", "splats", "spacing_m", "offset", "barrel_m", "trunnion", "muzzles"})
        self.assertEqual(turret["barrel_m"], 2.6)
        left, right = turret["muzzles"]
        self.assertLess(left[0], 0.0)
        self.assertEqual(left, mirrored(right))
        self.assertAlmostEqual(left[2], -2.6, msg="barrel_m ahead of the turning axis")
        self.assertEqual(turret["trunnion"][0], 0.0)
        self.assertEqual(turret["trunnion"][2], 0.0, "on the turning axis")
        self.assertAlmostEqual(turret["trunnion"][1], left[1], msg="the barrels elevate about their own axis")
        np.testing.assert_allclose(splats.xyz.mean(axis=0), [0.0, 0.0, 0.0], atol=1e-4)
        local = frames.flip_xy(splats.xyz) + np.array(turret["offset"])
        self.assertAlmostEqual(float(local[:, 1].min()), 0.0, delta=0.1, msg="the stalk stands on the mount")
        self.assertAlmostEqual(float(-local[:, 2].min()), 2.6, delta=0.1, msg="the muzzles are barrel_m ahead of the pivot")
        self.assertAlmostEqual(float(local[:, 0].max()), 1.1, delta=0.15, msg="a teardrop pod 2.2 m across")
        np.testing.assert_allclose(sorted_rows(local), sorted_rows(local * np.array([-1.0, 1.0, 1.0])), atol=1e-5)
        gold = (splats.rgb[:, 0] > 0.4) & (splats.rgb[:, 1] > 0.3) & (splats.rgb[:, 2] < 0.2)
        violet = splats.rgb[:, 2] > 2.0 * splats.rgb[:, 0]
        self.assertGreater(int(gold.sum()), 30, "gold collars on the barrels")
        self.assertGreater(int(violet.sum()), len(splats) // 3, "a violet pod")
        obj = read_obj(self.dir_a / turret["obj"])
        lo, hi = obj.vertices.min(axis=0), obj.vertices.max(axis=0)
        self.assertTrue(np.all(frames.flip_xy(splats.xyz).min(axis=0) >= lo - 0.1))
        self.assertTrue(np.all(frames.flip_xy(splats.xyz).max(axis=0) <= hi + 0.1))

    # --- collision -----------------------------------------------------------------------------------------------------
    def test_collision_boxes_cover_every_splat_and_fit_what_they_hold(self) -> None:
        shapes = self.hp["collision"]
        names = [c["name"] for c in shapes]
        self.assertEqual(len(names), len(set(names)), "unique names")
        self.assertEqual({c["type"] for c in shapes}, {"box"})
        inside = np.zeros(len(self.xyz), dtype=bool)
        for c in shapes:
            inside |= inside_primitive(self.xyz, c, inflate=brez.DEFAULT_SPACING_M)
        self.assertGreaterEqual(float(inside.mean()), 0.999, "the hit volumes cover the LOD0 splat centres")
        for c in shapes:
            basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
            np.testing.assert_allclose(basis.T @ basis, np.eye(3), atol=1e-4)
            self.assertAlmostEqual(float(np.linalg.det(basis)), 1.0, places=3)
            # Tight: every face of a box lies within 0.45 m of the splats it holds, so no box reaches into empty space.
            held = inside_primitive(self.xyz, c, inflate=brez.DEFAULT_SPACING_M)
            self.assertGreater(int(held.sum()), 0, c["name"])
            local = (self.xyz[held] - np.array(c["position"])) @ basis
            half = 0.5 * np.array(c["size"])
            slack = np.concatenate([local.min(axis=0) + half, half - local.max(axis=0)])
            self.assertLess(float(slack.max()), 0.45, (c["name"], np.round(slack, 3)))

    def test_collision_is_mirror_symmetric(self) -> None:
        shapes = {c["name"]: c for c in self.hp["collision"]}
        for name, c in shapes.items():
            if "_r" in name and name.replace("_r", "_l", 1) in shapes:
                twin = shapes[name.replace("_r", "_l", 1)]
                np.testing.assert_allclose(twin["position"], mirrored(c["position"]), atol=1e-4, err_msg=name)
            elif "_l" not in name:
                self.assertAlmostEqual(c["position"][0], 0.0, places=4, msg=name)

    # --- meshes ----------------------------------------------------------------------------------------------------------
    def test_the_fallback_mesh_and_chunk_meshes_hold_every_piece(self) -> None:
        parts = [p.part for p in brez.with_twins(brez.assemble(brez.DEFAULT_SPEC, brez.CENTAURI))]
        self.assertEqual(
            {p.name for p in parts},
            {"bow", "bay", "engine", "dorsal", "windows", "arm_r", "arm_l", "rail_r", "rail_l", "fairing_r", "fairing_l",
             "fin_top_r", "fin_top_l", "fin_bot_r", "fin_bot_l"},
        )  # fmt: skip
        self.assertTrue(all(p.mesh.face_count > 0 for p in parts))
        self.assertEqual(len(self.obj.faces), sum(p.mesh.face_count for p in parts), "the hull OBJ is every piece")
        for entry in self.hp["chunks"]:
            expected = sum(p.mesh.face_count for p in parts if p.group == entry["name"])
            self.assertEqual(len(read_obj(self.dir_a / entry["obj"]).faces), expected, entry["name"])

    def test_fallback_obj_is_valid_and_matches_the_splat_bounds(self) -> None:
        v = self.obj.vertices
        self.assertGreater(len(v), 0)
        self.assertTrue(np.all(np.isfinite(v)))
        slack = 2.0 * brez.DEFAULT_SPACING_M  # the import test's frame slack
        np.testing.assert_allclose(v.min(axis=0), self.xyz.min(axis=0), atol=slack)
        np.testing.assert_allclose(v.max(axis=0), self.xyz.max(axis=0), atol=slack)
        for name in ("cn_hull", "cn_stripe", "cn_trim_light", "cn_window"):
            self.assertIn(name, self.obj.materials, "the painted regions reach the fallback mesh")

    # --- determinism, options --------------------------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        for out in self.out_a.files:
            self.assertEqual(sha256(out), sha256(self.dir_b / out.name), out.name)

    def test_a_different_seed_changes_the_splats_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = brez.build(BuildContext(Path(tmp), seed=7))
            self.assertNotEqual(sha256(Path(tmp) / brez.PLY_NAME), sha256(self.dir_a / brez.PLY_NAME))
            hp = json.loads((Path(tmp) / brez.HARDPOINTS_NAME).read_text(encoding="utf-8"))

            def authored(doc: dict, manifest: dict) -> np.ndarray:
                return np.array([t["position"] for t in doc["turrets"]]) + np.array(manifest["centroid_offset"])

            np.testing.assert_allclose(authored(hp, other.manifest), authored(self.hp, self.manifest), atol=1e-3)
            self.assertLess(float(np.abs(np.subtract(other.manifest["centroid_offset"], self.manifest["centroid_offset"])).max()), 0.25)
            self.assertEqual([c["name"] for c in hp["collision"]], [c["name"] for c in self.hp["collision"]])

    def test_spacing_option_scales_the_count_and_is_recorded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = brez.build(BuildContext(Path(tmp), seed=42, options={"spacing": 2.0 * brez.DEFAULT_SPACING_M}))
            count = out.manifest["lods"][0]["splats"]
            self.assertLess(count, 0.4 * len(self.splats))
            self.assertEqual(out.manifest["sampling"]["spacing_m"], 2.0 * brez.DEFAULT_SPACING_M)
            self.assertEqual(out.warnings, (), "the budget warning only applies at the default spacing")

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for bad in ({"spacing": 0.0}, {"overlap": -1.0}, {"thickness": 0}, {"turret_spacing": -0.1}):
                with self.assertRaises(ValueError):
                    brez.build(BuildContext(Path(tmp), seed=1, options=bad))


class CentauriStyleTests(unittest.TestCase):
    def test_style_provides_every_role_and_the_extras(self) -> None:
        from tools.procgen.styles import REQUIRED_ROLES
        from tools.procgen.styles.centauri import CENTAURI

        for role in (*REQUIRED_ROLES, "trim_light", "window"):
            self.assertIn(role, CENTAURI.materials, role)
        self.assertEqual(CENTAURI.name, "centauri")
        self.assertAlmostEqual(CENTAURI.panel_size_m, 2.4)
        self.assertAlmostEqual(CENTAURI.panel_line_width_m, 0.25)
        self.assertAlmostEqual(CENTAURI.panel_tint_jitter, 0.04, msg="the liner reads smooth")

    def test_the_confirmed_scheme_is_painted_as_written(self) -> None:
        # Q19: the maintainer confirmed the written scheme; any lift waits for T16's GPU check and the maintainer's OK.
        from tools.procgen.styles import centauri

        for role, value in (("hull", 0x4C3C8E), ("hull_dark", 0x2B2257), ("stripe", 0xD9B23A), ("trim_light", 0xD7D2E6),
                            ("window", 0xF3F1FF), ("nozzle", 0x3A3448), ("nozzle_throat", 0x141218)):  # fmt: skip
            got = srgb_hex(centauri.CENTAURI.material(role).albedo)
            for shift in (16, 8, 0):
                self.assertAlmostEqual((got >> shift) & 255, (value >> shift) & 255, delta=1, msg=role)
        self.assertEqual(centauri.GLOW_SRGB, 0xFFB8E0, "engine and fin-tip glow, a ShipSpec tint for T16")

    def test_panel_lines_are_the_written_dark_violet(self) -> None:
        # docs/assets-civilian.md: the panel lines are hull_dark (#2B2257) on the hull violet.
        from tools.procgen.styles.centauri import CENTAURI

        hull = np.array(CENTAURI.material("hull").albedo)
        line = hull * CENTAURI.panel_line_darkness
        got = srgb_hex(tuple(line))
        for shift, value in ((16, 0x2B), (8, 0x22), (0, 0x57)):
            self.assertAlmostEqual((got >> shift) & 255, value, delta=4)


if __name__ == "__main__":
    unittest.main()
