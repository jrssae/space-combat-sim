"""``skylark_transport`` (M5-T13, AC12, D61, Q19; textured meshes from M5-T27): files, the mesh contract, frames, symmetry,
chunk cuts, collision coverage, the hardpoint contract with its single dorsal turret, the turret model, colours, the
texture pack and determinism.

The expected numbers are typed in from docs/assets-civilian.md and docs/design-references.md ("Skylark transport"), not
read from the generator. The visible surface (the samples that place the body origin) stands in for the hull's skin where
a test asks what the eye sees.
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
from tools.procgen.core import civilian as cv
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.color import capture_albedo, linear_to_srgb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.obj import read_obj
from tools.procgen.core.textured_mesh import TexturedPart, phase_steps
from tools.procgen.parts import skylark as sp
from tools.procgen.tests.mesh_checks import (
    TEST_OPTIONS,
    assert_chunks_cut_the_hull,
    assert_hull_mesh,
    assert_mirror_symmetric,
    assert_model_mesh,
    glowing_points,
    painted_faces,
)

PILOT_TERMS = {
    "sway_left", "sway_right", "heave_up", "heave_down", "pitch_up", "pitch_down",
    "yaw_left", "yaw_right", "roll_left", "roll_right",
}  # fmt: skip
SYM_TOL = 1e-5
CHUNKS = ("capsule", "body", "nacelle_l", "nacelle_r")
TRIANGLE_BUDGET = 35_000  # 26 052 as built; the importer adds the levels of detail
TURRET_TRIANGLE_BUDGET = 5_000
TEXEL_MAX_M = 0.06  # the hull at the default 2 048 px atlas
NACELLE_AXIS = (13.03, -0.26)  # x, y of the nacelles' axis (authored frame, y from the box centre)
DORSAL_TURRET = (0.0, 2.766, 37.5)  # Q19: the only turret, on the body's ridge ahead of the dorsal fin, as low as the hull under its rim


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


def srgb_hex(albedo: tuple[float, float, float]) -> int:
    r, g, b = (round(float(c) * 255) for c in linear_to_srgb(np.array(albedo)))
    return (r << 16) | (g << 8) | b


class SkylarkTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = sky.build(BuildContext(cls.dir_a, seed=42, options=TEST_OPTIONS))
        cls.out_b = sky.build(BuildContext(cls.dir_b, seed=42, options=TEST_OPTIONS))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.hp = json.loads((cls.dir_a / sky.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / sky.OBJ_NAME)
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.spacing = float(cls.manifest["surface_spacing_m"])
        cls.length = cls.hp["length_m"]
        sampled = sky.sample_hull(sp.assemble(sky.STYLE), BuildContext(cls.dir_a, seed=42), cls.spacing)
        cls.xyz = np.concatenate([s.samples.positions for s in sampled]) - cls.offset  # the visible surface, body frame
        cls.paint_at, cls.rgb, cls.area, metal = painted_faces(cls.dir_a, cls.manifest["mesh"])
        cls.painted = metal < 0.3

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
        expected = {sky.OBJ_NAME, "skylark_transport.mtl", sky.HARDPOINTS_NAME, "manifest.json"}
        for stem in ("skylark_transport", "skylark_transport_turret"):
            expected |= {f"{stem}.glb"} | {f"{stem}_{k}.png{x}" for k in ("albedo", "normal", "orm", "emissive") for x in ("", ".import")}
        # The hull's low texture set (M5-T40); the turret has no layouts, so one set.
        expected |= {f"skylark_transport_{k}_low.png{x}" for k in ("albedo", "normal", "orm") for x in ("", ".import")}
        for entry in self.hp["chunks"]:
            expected |= {entry["mesh"], entry["obj"], entry["obj"].replace(".obj", ".mtl")}
        turret = self.manifest["turret"]
        expected |= {turret["obj"], turret["obj"].replace(".obj", ".mtl")}
        self.assertEqual({p.name for p in self.dir_a.iterdir()}, expected)
        self.assertEqual({p.name for p in self.out_a.files}, expected)

    def test_the_hull_is_its_textured_mesh_inside_the_budget(self) -> None:
        assert_hull_mesh(self, self.dir_a, self.manifest, sky.OBJ_NAME)
        self.assertLessEqual(self.manifest["mesh"]["triangles"], TRIANGLE_BUDGET)
        self.assertEqual(self.out_a.warnings, ())
        for key in ("lods", "counts", "sampling", "paint_mesh", "chunk_lod"):
            self.assertNotIn(key, self.manifest)

    def test_the_default_atlas_lands_under_six_centimetres_a_texel(self) -> None:
        parts = [TexturedPart(p.part.mesh, phase_steps(p.name, False), (), p.name) for p in sky.with_twins(sp.assemble(sky.STYLE))]
        self.assertLess(cv.texel_of(parts, cv.HULL_ATLAS_PX), TEXEL_MAX_M)

    def test_dimensions_match_the_design(self) -> None:
        self.assertAlmostEqual(self.hp["length_m"], 60.0, delta=0.6, msg="Q8: about 60 m, nose vanes to claw tips")
        self.assertAlmostEqual(self.hp["span_m"], 40.2, delta=0.6, msg="across the claw tips")
        self.assertAlmostEqual(self.hp["height_m"], 10.27, delta=0.5, msg="ventral nose vane to dorsal fin")
        self.assertEqual(
            self.manifest["dimensions_m"],
            {"length": self.hp["length_m"], "span": self.hp["span_m"], "height": self.hp["height_m"]},
        )

    # --- frames, symmetry ------------------------------------------------------------------------------------------------
    def test_the_body_origin_is_the_visible_surfaces_centroid(self) -> None:
        np.testing.assert_allclose(self.xyz.mean(axis=0), [0.0, 0.0, 0.0], atol=1e-3)
        np.testing.assert_allclose(self.obj.vertices.min(axis=0), self.manifest["aabb_min"], atol=2e-4)
        np.testing.assert_allclose(self.obj.vertices.max(axis=0), self.manifest["aabb_max"], atol=2e-4)
        self.assertAlmostEqual(self.manifest["centroid_offset"][0], 0.0, places=9)

    def test_the_authored_frame_is_the_references(self) -> None:
        # Back in the authored frame the nose tip is at z = 0 and the box is centred on x = y = 0 (refview's frame).
        authored = self.obj.vertices + self.offset
        lo, hi = authored.min(axis=0), authored.max(axis=0)
        self.assertAlmostEqual(float(lo[2]), 0.0, delta=0.3)
        self.assertAlmostEqual(float(0.5 * (lo[1] + hi[1])), 0.0, delta=0.3)
        self.assertAlmostEqual(float(0.5 * (lo[0] + hi[0])), 0.0, delta=1e-6)

    def test_the_mesh_and_the_surface_are_mirror_symmetric_in_x(self) -> None:
        assert_mirror_symmetric(self, self.obj.vertices, "hull")
        assert_mirror_symmetric(self, self.xyz, "visible surface", decimals=4)

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
        # Area-weighted over the paint (the bare-metal chips left out): the test atlas is coarse, so its wear is broad.
        keep = self.painted
        rgb, authored, area = self.rgb[keep], self.paint_at[keep] + self.offset, self.area[keep]
        x, y, z = authored[:, 0], authored[:, 1], authored[:, 2]
        top = (np.abs(x) > 4.0) & (np.abs(x) < 9.0) & (z > 40.0) & (z < 48.0) & (y > -0.5)
        sand = np.average(rgb[top], axis=0, weights=area[top])
        self.assertGreater(sand[0], sand[2] + 0.05, "khaki: warm, not neutral grey")
        self.assertGreater(float(sand.mean()), 0.22, "a light plating (darker than the capture, which shows lit paint)")
        band = (rgb[:, 0] > 1.6 * rgb[:, 1]) & (rgb[:, 0] > 0.22)  # the darkened red (capture_albedo)
        self.assertGreater(int(band.sum()), 10, "two bands on the capsule, one on each side tank")
        self.assertAlmostEqual(float(x[band].mean()), 0.0, delta=0.5)
        self.assertLess(float(z[band].max()), 30.0, "the bands are on the forward capsule and the tanks")
        on_tanks = band & (np.abs(np.abs(x) - 5.44) < 2.3) & (z > 19.0)
        self.assertGreater(int(on_tanks.sum()), 2, "one band on each side tank")
        every = self.paint_at + self.offset  # the bells are dark metal: every face, the metal ones too
        bell = (np.hypot(np.abs(every[:, 0]) - NACELLE_AXIS[0], every[:, 1] - NACELLE_AXIS[1]) < 3.1) & (every[:, 2] > 52.0) & (every[:, 2] < 55.4)
        dark = np.median(self.rgb[bell], axis=0)  # by face: the bell's many small faces, not the claws' big ones beside them
        self.assertLess(float(dark.mean()), float(sand.mean()) - 0.15, "dark nacelle bells")

    def test_the_engine_throats_glow_warm_white(self) -> None:
        glowing = glowing_points(self.dir_a, self.manifest["mesh"]) + self.offset
        self.assertGreater(len(glowing), 0)
        self.assertGreater(float(glowing[:, 2].min()), 40.0, "the nacelles' and the centre engine's throats, aft")
        self.assertEqual(srgb_hex(sky.STYLE.material("nozzle_throat").emissive), sky.ENGINE_GLOW_SRGB)

    def test_the_skylark_style_carries_the_written_scheme(self) -> None:
        style = sky.STYLE
        for role, value in (("hull", 0xA9A68E), ("hull_panel", 0x7A7659), ("hull_dark", 0x4A4839), ("stripe", 0xB8452B),
                            ("nozzle", 0x4A4A46)):  # fmt: skip
            # The scheme is what a lit face shows; the paint is the albedo that shows it (core/color.py, capture_albedo).
            r, g, b = (round(float(c) * 255) for c in linear_to_srgb(np.array(capture_albedo(value))))
            value = (r << 16) | (g << 8) | b
            got = srgb_hex(style.material(role).albedo)
            for shift in (16, 8, 0):
                self.assertAlmostEqual((got >> shift) & 255, (value >> shift) & 255, delta=1, msg=role)
        self.assertEqual(style.name, "ea_civilian")
        self.assertAlmostEqual(style.panel_size_m, 2.4)
        self.assertAlmostEqual(style.panel_line_width_m, 0.25)
        # The EA civilian texture pack, more patched than the Saturns' (Transport 1.png).
        self.assertLess(style.panel_line_darkness, 1.0)
        self.assertGreater(style.panel_tint_jitter, sky.ea_civilian().panel_tint_jitter)
        self.assertEqual(sky.ENGINE_GLOW_SRGB, 0xFFE9C2)

    # --- chunks --------------------------------------------------------------------------------------------------------
    def test_chunks_cut_the_hull(self) -> None:
        assert_chunks_cut_the_hull(self, self.dir_a, self.manifest, self.hp, CHUNKS)

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
        # Its base (2.4 m across) meets the hull all round: the hull's surface just inside the rim reach the base in every
        # direction, and nothing stands above the base inside it.
        p = np.array(t["position"])
        d = self.xyz[:, [0, 2]] - p[[0, 2]]
        r, ang = np.hypot(d[:, 0], d[:, 1]), np.arctan2(d[:, 1], d[:, 0])
        rim = (r > 0.9) & (r < 1.2)
        for k in range(8):
            sector = rim & (np.floor((ang + np.pi) / (np.pi / 4.0)) == k)
            self.assertGreater(int(sector.sum()), 0, k)
            self.assertGreater(float(self.xyz[sector, 1].max()), p[1] - 0.05, f"the base floats over sector {k}")
        self.assertLess(float(self.xyz[r < 1.2, 1].max()), p[1] + 0.25, "only the front of the base is buried")
        fin = self.xyz[(np.abs(self.xyz[:, 0]) < 0.5) & (self.xyz[:, 1] > p[1] + 0.5) & (self.xyz[:, 2] > p[2] - 10.0)]
        self.assertGreater(float(fin[:, 2].min()), p[2] + 2.0, "ahead of the dorsal fin, nothing else above it")

    def test_the_turret_model_is_the_ea_turret_at_two_thirds(self) -> None:
        turret = self.manifest["turret"]
        self.assertEqual(turret["obj"], "skylark_transport_turret.obj")
        self.assertEqual(set(turret), {"obj", "mesh", "barrel_m", "trunnion", "muzzles"})
        assert_model_mesh(self, self.dir_a, turret["mesh"], turret["obj"], "turret")
        self.assertLessEqual(turret["mesh"]["triangles"], TURRET_TRIANGLE_BUDGET)
        self.assertEqual(turret["barrel_m"], 3.0)
        left, right = turret["muzzles"]
        self.assertEqual(left, mirrored(right))
        self.assertAlmostEqual(left[2], -3.0)
        self.assertAlmostEqual(abs(left[0]), 0.4 * 2.0 / 3.0, places=4, msg="the barrels 0.8 m apart at full size")
        local = read_obj(self.dir_a / turret["obj"]).vertices  # the turret's frame: the pivot at the origin
        self.assertAlmostEqual(float(local[:, 1].min()), 0.0, delta=0.1, msg="the base stands on the mount")
        self.assertAlmostEqual(float(local[:, 0].max()), 1.2, delta=0.1, msg="a round base 2.4 m across")
        self.assertLess(abs(float(local[:, 0].max() + local[:, 0].min())), 0.1, "centred on its turning axis")

    # --- collision -----------------------------------------------------------------------------------------------------
    def test_collision_primitives_cover_the_visible_surface_and_stay_close(self) -> None:
        shapes = self.hp["collision"]
        names = [c["name"] for c in shapes]
        self.assertEqual(len(names), len(set(names)), "unique names")
        inside = np.zeros(len(self.xyz), dtype=bool)
        for c in shapes:
            inside |= inside_primitive(self.xyz, c, inflate=self.spacing)
        missed = self.xyz[~inside] + self.offset
        self.assertTrue(bool(inside.all()), f"every visible surface sample; missed (authored frame): {np.round(missed[:10], 2).tolist()}")
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

    def test_fallback_obj_is_valid_and_holds_the_visible_surface(self) -> None:
        v = self.obj.vertices
        self.assertTrue(np.all(np.isfinite(v)))
        slack = 2.0 * self.spacing
        np.testing.assert_allclose(v.min(axis=0), self.xyz.min(axis=0), atol=slack)
        np.testing.assert_allclose(v.max(axis=0), self.xyz.max(axis=0), atol=slack)
        self.assertIn("eac_hull_a9a68e", self.obj.materials, "the Skylark's sand plating, its own material name")
        self.assertIn("eac_stripe_b8452b", self.obj.materials, "the bands reach the mesh")

    # --- determinism, options --------------------------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        for out in self.out_a.files:
            self.assertEqual(sha256(out), sha256(self.dir_b / out.name), out.name)

    def test_a_different_seed_changes_the_wear_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = sky.build(BuildContext(Path(tmp), seed=7, options=TEST_OPTIONS))
            albedo = self.manifest["mesh"]["surfaces"][0]["albedo"]
            self.assertNotEqual(sha256(Path(tmp) / albedo), sha256(self.dir_a / albedo))
            hp = json.loads((Path(tmp) / sky.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            authored = np.array(hp["turrets"][0]["position"]) + np.array(other.manifest["centroid_offset"])
            np.testing.assert_allclose(authored, DORSAL_TURRET, atol=1e-3)
            self.assertLess(float(np.abs(np.subtract(other.manifest["centroid_offset"], self.manifest["centroid_offset"])).max()), 0.25)
            self.assertEqual([c["name"] for c in hp["collision"]], [c["name"] for c in self.hp["collision"]])

    def test_the_spacing_option_is_recorded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = sky.build(BuildContext(Path(tmp), seed=42, options={**TEST_OPTIONS, "spacing": 2.0 * sky.DEFAULT_SPACING_M}))
            self.assertEqual(out.manifest["surface_spacing_m"], 2.0 * sky.DEFAULT_SPACING_M)
            self.assertEqual(out.manifest["mesh"]["triangles"], self.manifest["mesh"]["triangles"], "the mesh does not follow it")

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for bad in ({"spacing": 0.0}, {"spacing": -1.0}):
                with self.assertRaises(ValueError):
                    sky.build(BuildContext(Path(tmp), seed=1, options=bad))


if __name__ == "__main__":
    unittest.main()
