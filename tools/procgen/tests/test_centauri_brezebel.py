"""``centauri_brezebel`` (M5-T15, AC12; textured meshes from M5-T27): files, the mesh contract, frames, symmetry, chunk cuts,
collision coverage, the hardpoint contract with its one dorsal turret (Q19), the turret model, the confirmed colours, the
texture pack and determinism. The visible surface (the samples that place the body origin) stands in for the hull's skin
where a test asks what the eye sees."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import centauri_brezebel as brez
from tools.procgen.core import civilian as cv
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.color import linear_to_srgb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.obj import read_obj
from tools.procgen.core.textured_mesh import TexturedPart, phase_steps
from tools.procgen.tests.mesh_checks import (
    TEST_OPTIONS,
    assert_chunks_cut_the_hull,
    assert_hull_mesh,
    assert_mirror_symmetric,
    assert_model_mesh,
    glowing_points,
    painted_points,
)

PILOT_TERMS = {
    "sway_left", "sway_right", "heave_up", "heave_down", "pitch_up", "pitch_down",
    "yaw_left", "yaw_right", "roll_left", "roll_right",
}  # fmt: skip
SYM_TOL = 1e-6
TRIANGLE_BUDGET = 25_000  # 16 810 as built; the importer adds the levels of detail
TURRET_TRIANGLE_BUDGET = 5_000
TEXEL_MAX_M = 0.06  # the hull at the default 2 048 px atlas


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


def mirrored(v: list[float]) -> list[float]:
    return [-v[0], v[1], v[2]]


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
        cls.out_a = brez.build(BuildContext(cls.dir_a, seed=42, options=TEST_OPTIONS))
        cls.out_b = brez.build(BuildContext(cls.dir_b, seed=42, options=TEST_OPTIONS))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.hp = json.loads((cls.dir_a / brez.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / brez.OBJ_NAME)
        cls.length = cls.hp["length_m"]
        cls.offset = np.array(cls.manifest["centroid_offset"])
        sampled = brez.build_parts(brez.CENTAURI, BuildContext(cls.dir_a, seed=42), brez.DEFAULT_SPACING_M)
        cls.xyz = np.concatenate([s.samples.positions for s in sampled]) - cls.offset  # the visible surface, body frame
        cls.authored = cls.xyz + cls.offset  # back in the design references' frame: nose at z = 0
        cls.paint_at, cls.rgb = painted_points(cls.dir_a, cls.manifest["mesh"])
        cls.paint_authored = cls.paint_at + cls.offset

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    # --- registry, files, manifest, budgets --------------------------------------------------------------------------
    def test_the_asset_is_registered(self) -> None:
        self.assertIs(ASSETS["centauri_brezebel"], brez.build)
        self.assertEqual(brez.ASSET_ID, "centauri_brezebel")

    def test_all_files_are_written_and_listed(self) -> None:
        expected = {brez.OBJ_NAME, "centauri_brezebel.mtl", brez.HARDPOINTS_NAME, "manifest.json"}
        for stem in ("centauri_brezebel", "centauri_brezebel_turret"):
            expected |= {f"{stem}.glb"} | {f"{stem}_{k}.png{x}" for k in ("albedo", "normal", "orm", "emissive") for x in ("", ".import")}
        for entry in self.hp["chunks"]:
            expected |= {entry["mesh"], entry["obj"], entry["obj"].replace(".obj", ".mtl")}
        turret = self.manifest["turret"]
        expected |= {turret["obj"], turret["obj"].replace(".obj", ".mtl")}
        self.assertEqual({p.name for p in self.dir_a.iterdir()}, expected)
        self.assertEqual({p.name for p in self.out_a.files}, expected)

    def test_the_hull_is_its_textured_mesh_inside_the_budget(self) -> None:
        assert_hull_mesh(self, self.dir_a, self.manifest, brez.OBJ_NAME)
        self.assertLessEqual(self.manifest["mesh"]["triangles"], TRIANGLE_BUDGET)
        self.assertEqual(self.out_a.warnings, ())
        self.assertEqual(brez.CHUNK_ORDER, ("bow", "arm_l", "arm_r"), "docs/assets-civilian.md: bow and the two arms")
        for key in ("lods", "counts", "sampling", "paint_mesh", "chunk_lod"):
            self.assertNotIn(key, self.manifest)

    def test_the_default_atlas_lands_under_six_centimetres_a_texel(self) -> None:
        parts = [TexturedPart(p.part.mesh, phase_steps(p.part.name, False), (), p.part.name)
                 for p in brez.with_twins(brez.assemble(brez.DEFAULT_SPEC, brez.CENTAURI))]  # fmt: skip
        self.assertLess(cv.texel_of(parts, cv.HULL_ATLAS_PX), TEXEL_MAX_M)

    def test_dimensions_match_the_reference(self) -> None:
        self.assertAlmostEqual(self.hp["length_m"], 60.0, delta=0.3, msg="Q11: about 60 m")
        self.assertAlmostEqual(self.hp["span_m"], 39.12, delta=0.4, msg="the bow's widest points")
        self.assertAlmostEqual(self.hp["height_m"], 25.27, delta=0.5, msg="over the tip fins")
        self.assertEqual(
            self.manifest["dimensions_m"],
            {"length": self.hp["length_m"], "span": self.hp["span_m"], "height": self.hp["height_m"]},
        )

    # --- frames, symmetry ------------------------------------------------------------------------------------------------
    def test_the_body_origin_is_the_visible_surfaces_centroid(self) -> None:
        np.testing.assert_allclose(self.xyz.mean(axis=0), [0.0, 0.0, 0.0], atol=1e-3)
        np.testing.assert_allclose(self.obj.vertices.min(axis=0), self.manifest["aabb_min"], atol=2e-4)
        np.testing.assert_allclose(self.obj.vertices.max(axis=0), self.manifest["aabb_max"], atol=2e-4)
        np.testing.assert_allclose(self.manifest["centroid_offset"][0], 0.0, atol=1e-9)

    def test_the_authored_frame_starts_at_the_nose(self) -> None:
        authored = self.obj.vertices + self.offset
        self.assertAlmostEqual(float(authored[:, 2].min()), 0.0, delta=0.1, msg="the nose tip at z = 0")
        self.assertAlmostEqual(float(authored[:, 2].max()), 60.0, delta=0.15, msg="the arm tips at z = 60")

    def test_the_mesh_and_the_surface_are_mirror_symmetric_in_x(self) -> None:
        assert_mirror_symmetric(self, self.obj.vertices, "hull")
        assert_mirror_symmetric(self, self.xyz, "visible surface", decimals=4)

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
    def test_the_paint_reads_violet_with_gold_caps_and_a_pale_rim_band(self) -> None:
        rgb, a = self.rgb, self.paint_authored
        # The arms' top faces are plain violet plating: blue over red over green.
        arm_top = (np.abs(a[:, 0]) > 12.0) & (a[:, 2] > 44.0) & (a[:, 2] < 56.0) & (np.abs(a[:, 1] - brez.CENTRE_Y) < 2.6)
        violet = np.median(rgb[arm_top], axis=0)
        self.assertGreater(violet[2], violet[0] * 1.5, "violet: much more blue than red")
        self.assertGreater(violet[0], violet[1] * 1.2, "violet, not blue: more red than green")
        gold = (rgb[:, 0] > 0.55) & (rgb[:, 1] > 0.4) & (rgb[:, 2] < 0.35)
        self.assertGreater(int(gold.sum()), 4, "the tip fins' gold caps")
        self.assertGreater(float(np.abs(a[gold, 1] - brez.CENTRE_Y).min()), 10.0, "the caps are on the fins' tips")
        pale = (rgb.min(axis=1) > 0.6) & (np.ptp(rgb, axis=1) < 0.25)
        rim = pale & (a[:, 2] < 19.5) & (np.abs(a[:, 1] - brez.CENTRE_Y) < 1.0)
        self.assertGreater(int(rim.sum()), 10, "the pale lavender band round the bow's rim")

    def test_the_windows_and_the_engine_glow(self) -> None:
        glowing = glowing_points(self.dir_a, self.manifest["mesh"]) + self.offset
        windows = glowing[(glowing[:, 2] < 3.5) & (glowing[:, 1] > 1.5) & (np.abs(glowing[:, 0]) < 3.5)]
        self.assertGreater(len(windows), 0, "the row of windows on the dorsal fitting's front")
        self.assertTrue((glowing[:, 2] > 25.0).any(), "the main engines' throats")
        self.assertEqual(len(glowing) - len(windows), int((glowing[:, 2] > 19.0).sum()), "nothing else on the bow glows")

    def test_the_texture_pack_is_polished_paint(self) -> None:
        # Centauri Liner.jpg: fine seams barely darker than the paint, little wear, glossy paint.
        style = brez.CENTAURI
        self.assertGreater(style.panel_line_darkness, 0.75)
        self.assertLess(style.panel_line_darkness, 1.0)
        self.assertLess(style.edge_wear, 0.3)
        self.assertEqual(style.extra["bare_metal"], 0.0)
        self.assertLess(style.extra["paint_roughness"], 0.5)

    # --- chunks --------------------------------------------------------------------------------------------------------
    def test_chunks_cut_the_hull(self) -> None:
        assert_chunks_cut_the_hull(self, self.dir_a, self.manifest, self.hp, brez.CHUNK_ORDER)

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
        # The depth proxy (the hull's mesh) hides a plume inside the hull: the retro's forward ray leaves the skin within
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

    def test_the_turret_model_is_its_own_textured_mesh(self) -> None:
        turret = self.manifest["turret"]
        self.assertEqual(turret["obj"], "centauri_brezebel_turret.obj")
        self.assertEqual(set(turret), {"obj", "mesh", "barrel_m", "trunnion", "muzzles"})
        assert_model_mesh(self, self.dir_a, turret["mesh"], turret["obj"], "turret")
        self.assertLessEqual(turret["mesh"]["triangles"], TURRET_TRIANGLE_BUDGET)
        self.assertEqual(turret["barrel_m"], 2.6)
        left, right = turret["muzzles"]
        self.assertLess(left[0], 0.0)
        self.assertEqual(left, mirrored(right))
        self.assertAlmostEqual(left[2], -2.6, msg="barrel_m ahead of the turning axis")
        self.assertEqual(turret["trunnion"][0], 0.0)
        self.assertEqual(turret["trunnion"][2], 0.0, "on the turning axis")
        self.assertAlmostEqual(turret["trunnion"][1], left[1], msg="the barrels elevate about their own axis")
        local = read_obj(self.dir_a / turret["obj"]).vertices  # the turret's frame: the pivot at the origin
        self.assertAlmostEqual(float(local[:, 1].min()), 0.0, delta=0.1, msg="the stalk stands on the mount")
        self.assertAlmostEqual(float(-local[:, 2].min()), 2.6, delta=0.1, msg="the muzzles are barrel_m ahead of the pivot")
        self.assertAlmostEqual(float(local[:, 0].max()), 1.1, delta=0.15, msg="a teardrop pod 2.2 m across")
        assert_mirror_symmetric(self, local, "turret")
        _, rgb = painted_points(self.dir_a, turret["mesh"])
        gold = (rgb[:, 0] > 0.55) & (rgb[:, 1] > 0.4) & (rgb[:, 2] < 0.35)
        violet = rgb[:, 2] > 1.5 * rgb[:, 0]
        self.assertGreater(int(gold.sum()), 4, "gold collars on the barrels")
        self.assertGreater(int(violet.sum()), len(rgb) // 4, "a violet pod")

    # --- collision -----------------------------------------------------------------------------------------------------
    def test_collision_boxes_cover_the_visible_surface_and_fit_what_they_hold(self) -> None:
        shapes = self.hp["collision"]
        names = [c["name"] for c in shapes]
        self.assertEqual(len(names), len(set(names)), "unique names")
        self.assertEqual({c["type"] for c in shapes}, {"box"})
        inside = np.zeros(len(self.xyz), dtype=bool)
        for c in shapes:
            inside |= inside_primitive(self.xyz, c, inflate=brez.DEFAULT_SPACING_M)
        self.assertGreaterEqual(float(inside.mean()), 0.999, "the hit volumes cover the visible surface")
        for c in shapes:
            basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
            np.testing.assert_allclose(basis.T @ basis, np.eye(3), atol=1e-4)
            self.assertAlmostEqual(float(np.linalg.det(basis)), 1.0, places=3)
            # Tight: every face of a box lies within 0.45 m of the surface it holds, so no box reaches into empty space.
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

    def test_fallback_obj_is_valid_and_holds_the_visible_surface(self) -> None:
        v = self.obj.vertices
        self.assertGreater(len(v), 0)
        self.assertTrue(np.all(np.isfinite(v)))
        slack = 2.0 * brez.DEFAULT_SPACING_M
        np.testing.assert_allclose(v.min(axis=0), self.xyz.min(axis=0), atol=slack)
        np.testing.assert_allclose(v.max(axis=0), self.xyz.max(axis=0), atol=slack)
        for name in ("cn_hull", "cn_stripe", "cn_trim_light", "cn_window"):
            self.assertIn(name, self.obj.materials, "the painted regions reach the mesh")

    # --- determinism, options --------------------------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        for out in self.out_a.files:
            self.assertEqual(sha256(out), sha256(self.dir_b / out.name), out.name)

    def test_a_different_seed_changes_the_wear_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = brez.build(BuildContext(Path(tmp), seed=7, options=TEST_OPTIONS))
            albedo = self.manifest["mesh"]["surfaces"][0]["albedo"]
            self.assertNotEqual(sha256(Path(tmp) / albedo), sha256(self.dir_a / albedo))
            hp = json.loads((Path(tmp) / brez.HARDPOINTS_NAME).read_text(encoding="utf-8"))

            def authored(doc: dict, manifest: dict) -> np.ndarray:
                return np.array([t["position"] for t in doc["turrets"]]) + np.array(manifest["centroid_offset"])

            np.testing.assert_allclose(authored(hp, other.manifest), authored(self.hp, self.manifest), atol=1e-3)
            self.assertLess(float(np.abs(np.subtract(other.manifest["centroid_offset"], self.manifest["centroid_offset"])).max()), 0.25)
            self.assertEqual([c["name"] for c in hp["collision"]], [c["name"] for c in self.hp["collision"]])

    def test_the_spacing_option_is_recorded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = brez.build(BuildContext(Path(tmp), seed=42, options={**TEST_OPTIONS, "spacing": 2.0 * brez.DEFAULT_SPACING_M}))
            self.assertEqual(out.manifest["surface_spacing_m"], 2.0 * brez.DEFAULT_SPACING_M)
            self.assertEqual(out.manifest["mesh"]["triangles"], self.manifest["mesh"]["triangles"], "the mesh does not follow it")

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for bad in ({"spacing": 0.0}, {"spacing": -1.0}):
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
        # The texture pack (M5-T27) paints the seams lightly and the windows and throat glow.
        self.assertLess(CENTAURI.panel_line_darkness, 1.0)
        self.assertGreater(CENTAURI.material("window").emissive_strength, 0.0)
        self.assertGreater(CENTAURI.material("nozzle_throat").emissive_strength, 0.0)

    def test_the_confirmed_scheme_is_painted_as_written(self) -> None:
        # Q19: the maintainer confirmed the written scheme; any lift waits for T16's GPU check and the maintainer's OK.
        from tools.procgen.styles import centauri

        for role, value in (("hull", 0x4C3C8E), ("hull_dark", 0x2B2257), ("stripe", 0xD9B23A), ("trim_light", 0xD7D2E6),
                            ("window", 0xF3F1FF), ("nozzle", 0x3A3448), ("nozzle_throat", 0x141218)):  # fmt: skip
            got = srgb_hex(centauri.CENTAURI.material(role).albedo)
            for shift in (16, 8, 0):
                self.assertAlmostEqual((got >> shift) & 255, (value >> shift) & 255, delta=1, msg=role)
        self.assertEqual(centauri.GLOW_SRGB, 0xFFB8E0, "engine and fin-tip glow: the throats' and a ShipSpec tint for T16")
        self.assertEqual(srgb_hex(centauri.CENTAURI.material("nozzle_throat").emissive), 0xFFB8E0)


if __name__ == "__main__":
    unittest.main()
