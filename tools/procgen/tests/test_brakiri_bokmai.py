"""``brakiri_bokmai`` (M5-T22, AC12, D59, D61, Q17, Q22; textured meshes from M5-T27): files, the mesh contract, frames,
symmetry, chunk cuts, collision coverage, the hardpoint contract with its two flank turrets and three cargo mounts, the pod
model, the turret model, paint and determinism; and the shared civilian pipeline (``core/civilian.py``).

The expected numbers are typed in from docs/assets-civilian.md and docs/design-references.md ("Brakiri Bokmai
transport"), not read from the generator. The visible surface (the samples that place the body origin) stands in for the
hull's skin where a test asks what the eye sees.
"""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np


from tools.procgen.assets import ASSETS
from tools.procgen.assets import brakiri_bokmai as bok
from tools.procgen.core import civilian as cv
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.color import capture_albedo, linear_to_srgb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.obj import read_obj
from tools.procgen.core.textured_mesh import TexturedPart, phase_steps
from tools.procgen.parts import Part
from tools.procgen.parts import brakiri as bp
from tools.procgen.styles.brakiri import BOLT_SRGB, BRAKIRI, BRAKIRI_POD, GLOW_SRGB
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
CHUNKS = ("bow", "arm_l", "arm_r", "engine_l", "engine_r")
TRIANGLE_BUDGET = 20_000  # the hull without its pods (9 284 as built); the importer adds the levels of detail
MODEL_TRIANGLE_BUDGET = 5_000  # the pod or the turret
TEXEL_MAX_M = 0.06  # the hull at the default 2 048 px atlas
LENGTH, SPAN, HEIGHT = 80.0, 31.62, 30.91  # Q17 and the reference's box at 80 m
NACELLE_AXIS = (13.16, 2.09)  # x, y of the cups and domes: the thrust line
MOUNTS = {"pod_fwd": (0.0, 1.70, 24.63), "pod_mid": (0.0, 1.70, 39.07), "pod_aft": (0.0, 1.70, 53.57)}
POD_SPANS = {"pod_fwd": (17.94, 31.33), "pod_mid": (32.37, 45.76), "pod_aft": (46.87, 60.26)}  # the reference's pods' z
POD = (17.81, 11.74, 13.39)  # width, height, length
SLEEVE_R = 1.48  # the bore round the spindle the pod-volume test leaves out
FLANK_TURRET = (2.04, 8.45, 6.58)  # Q22: in the stepped inset high on the right flank, up +x (the maintainer's sheet)


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


def mirrored(v: list[float]) -> list[float]:
    return [-v[0], v[1], v[2]]


def srgb_hex(albedo: tuple[float, float, float]) -> int:
    r, g, b = (round(float(c) * 255) for c in linear_to_srgb(np.array(albedo)))
    return (r << 16) | (g << 8) | b


class BrakiriBokmaiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = bok.build(BuildContext(cls.dir_a, seed=42, options=TEST_OPTIONS))
        cls.out_b = bok.build(BuildContext(cls.dir_b, seed=42, options=TEST_OPTIONS))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.hp = json.loads((cls.dir_a / bok.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / bok.OBJ_NAME)
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.spacing = float(cls.manifest["surface_spacing_m"])
        sampled = cv.sample_pieces(bok.hull_pieces(), BuildContext(cls.dir_a, seed=42), cls.spacing, buried_margin=bok.BURIED_MARGIN_M)
        cls.xyz = np.concatenate([s.samples.positions for s in sampled]) - cls.offset  # the visible surface, body frame
        cls.authored_xyz = cls.xyz + cls.offset
        cls.pod_xyz = read_obj(cls.dir_a / "brakiri_bokmai_pod.obj").vertices

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def authored(self, v: list[float]) -> np.ndarray:
        """A hardpoint back in the design references' frame (the prow at z = 0, x and y from the box centre)."""
        return np.array(v) + self.offset

    # --- files, manifest, budgets ------------------------------------------------------------------------------------
    def test_registered_and_named(self) -> None:
        self.assertIs(ASSETS["brakiri_bokmai"], bok.build)
        self.assertEqual(self.out_a.asset_id, "brakiri_bokmai")
        self.assertEqual(self.out_a.warnings, ())

    def test_all_files_are_written_and_listed(self) -> None:
        names = {p.name for p in self.out_a.files}
        expected = {"hardpoints.json", "manifest.json"}
        for stem in ("brakiri_bokmai", "brakiri_bokmai_turret", "brakiri_bokmai_pod"):
            expected |= {f"{stem}.glb", f"{stem}.obj"} | {f"{stem}_{k}.png" for k in ("albedo", "normal", "orm", "emissive")}
        expected |= {f"brakiri_bokmai_chunk_{c}.{ext}" for c in CHUNKS for ext in ("obj", "glb")}
        # The low texture set of the hull and of the pod (M5-T40); the turret has no layouts, so one set.
        expected |= {f"{stem}_{k}_low.png" for stem in ("brakiri_bokmai", "brakiri_bokmai_pod") for k in ("albedo", "normal", "orm")}
        self.assertNotIn("brakiri_bokmai_turret_albedo_low.png", names)
        self.assertTrue(expected <= names, sorted(expected - names))
        self.assertFalse([n for n in names if n.endswith((".ply", ".light"))], "no point clouds")
        for p in self.out_a.files:
            self.assertTrue(p.is_file(), p)

    def test_the_hull_is_its_textured_mesh_inside_the_budget(self) -> None:
        assert_hull_mesh(self, self.dir_a, self.manifest, bok.OBJ_NAME)
        self.assertLessEqual(self.manifest["mesh"]["triangles"], TRIANGLE_BUDGET)
        for key in ("lods", "counts", "sampling", "paint_mesh", "chunk_lod"):
            self.assertNotIn(key, self.manifest)

    def test_the_default_atlas_lands_under_six_centimetres_a_texel(self) -> None:
        parts = [TexturedPart(p.part.mesh, phase_steps(p.name, False), (), p.name) for p in cv.with_twins(bok.hull_pieces())]
        self.assertLess(cv.texel_of(parts, cv.HULL_ATLAS_PX), TEXEL_MAX_M)

    def test_dimensions_match_the_design(self) -> None:
        self.assertAlmostEqual(self.hp["length_m"], LENGTH, delta=0.01 * LENGTH)
        self.assertAlmostEqual(self.hp["span_m"], SPAN, delta=0.01 * SPAN)
        self.assertAlmostEqual(self.hp["height_m"], HEIGHT, delta=0.01 * HEIGHT)

    # --- frames, symmetry ------------------------------------------------------------------------------------------------
    def test_the_body_origin_is_the_visible_surfaces_centroid(self) -> None:
        self.assertLess(float(np.abs(self.xyz.mean(axis=0)).max()), 1e-3)
        np.testing.assert_allclose(self.obj.vertices.min(axis=0), self.manifest["aabb_min"], atol=2e-4)
        np.testing.assert_allclose(self.obj.vertices.max(axis=0), self.manifest["aabb_max"], atol=2e-4)

    def test_the_authored_frame_is_the_references(self) -> None:
        authored = self.obj.vertices + self.offset
        lo, hi = authored.min(axis=0), authored.max(axis=0)
        self.assertAlmostEqual(float(lo[2]), 0.0, delta=0.3, msg="the prow at z = 0")
        self.assertAlmostEqual(float(hi[2]), LENGTH, delta=0.3, msg="the domes at z = 80")
        self.assertAlmostEqual(float(0.5 * (lo[1] + hi[1])), 0.0, delta=0.3, msg="y from the box centre")
        self.assertAlmostEqual(float(0.5 * (lo[0] + hi[0])), 0.0, delta=1e-6)

    def test_the_meshes_and_the_surface_are_mirror_symmetric_in_x(self) -> None:
        assert_mirror_symmetric(self, self.obj.vertices, "hull")
        assert_mirror_symmetric(self, self.pod_xyz, "pod")
        assert_mirror_symmetric(self, self.xyz, "visible surface", decimals=4)

    def test_the_blade_is_forward_and_the_fins_aft(self) -> None:
        a = self.authored_xyz
        bow = a[(a[:, 2] < 10.0) & (a[:, 1] > 3.0)]  # above the arms' roots
        self.assertLess(float(np.abs(bow[:, 0]).max()), 3.0, "the blade is narrow")
        self.assertGreater(float(bow[:, 1].max()), 12.5, "and tall")
        fins = a[np.abs(a[:, 1]) > 14.0]
        self.assertGreater(float(fins[:, 2].min()), 69.0, "the tall fins are at the stern (Q22)")
        np.testing.assert_allclose(np.abs(fins[:, 0]).mean(), 12.92, atol=0.3)

    # --- the hull leaves its pods out ----------------------------------------------------------------------------------
    def test_the_hull_shows_nothing_inside_the_pod_volumes(self) -> None:
        # An empty mount looks empty: only the spindle passes through, inside the sleeve's bore.
        for name, mount in MOUNTS.items():
            local = self.authored_xyz - np.array(mount)
            near = np.abs(local[:, 2]) < 0.5 * POD[2]
            half = np.array([bp.pod_half_height(x, z) for x, z in local[near][:, [0, 2]]])
            inside = (np.abs(local[near][:, 1]) < half - 0.05) & (np.hypot(local[near][:, 0], local[near][:, 1]) > SLEEVE_R)
            self.assertEqual(int(inside.sum()), 0, name)

    def test_the_spindle_runs_through_every_mount(self) -> None:
        a = self.authored_xyz
        rod = a[(np.hypot(a[:, 0], a[:, 1] - 1.70) < 1.3) & (a[:, 2] > 17.0)]
        for name, (_x, _y, z) in MOUNTS.items():
            self.assertGreater(int((np.abs(rod[:, 2] - z) < 1.0).sum()), 10, name)

    # --- paint ---------------------------------------------------------------------------------------------------------
    def test_the_brakiri_style_carries_the_confirmed_scheme(self) -> None:
        m = BRAKIRI.materials
        written = {"hull": 0x5A6B59, "hull_dark": 0x3A4538, "pod": 0xABAE9A, "stripe": 0xD8B840, "window": 0xE8F0DC,
                   "window_strip": 0x1E2620, "nozzle": 0x2E3530, "engine_dome": 0xF2EDC4}  # fmt: skip
        for role, value in written.items():
            # The scheme is what a lit face shows; the paint is the albedo that shows it (core/color.py, capture_albedo).
            # The pods are painted paler than written so they stay pale in shade (M5-T39).
            expected = 0xC8CCB4 if role == "pod" else srgb_hex(capture_albedo(value))
            self.assertEqual(srgb_hex(m[role].albedo), expected, role)
        self.assertEqual((GLOW_SRGB, BOLT_SRGB), (0xFFF0B0, 0x7CFF4F), "the glow and the bright green bolts (Q22)")
        # The texture pack (M5-T27): seams darker than the paint, a mild tint, worn to primer; the windows and domes glow.
        for style in (BRAKIRI, BRAKIRI_POD):
            self.assertLess(style.panel_line_darkness, 0.9, style.name)
            self.assertGreater(style.panel_tint_jitter, 0.0, style.name)
            self.assertEqual(style.extra["bare_metal"], 0.0, style.name)
        self.assertEqual(srgb_hex(m["engine_dome"].emissive), GLOW_SRGB)
        self.assertGreater(m["window"].emissive_strength, 0.0)

    def test_the_paint_reaches_the_maps(self) -> None:
        at, rgb = painted_points(self.dir_a, self.manifest["mesh"])
        authored = at + self.offset
        fins_top = authored[:, 1] > 14.2
        self.assertGreater(float(np.median(rgb[fins_top][:, 0])), 0.32, "the fins' yellow tops (darkened paint)")
        spine = (authored[:, 2] > 20) & (authored[:, 2] < 40) & (authored[:, 1] > 12.5)
        self.assertLess(float(np.median(rgb[spine][:, 0])), float(np.median(rgb[spine][:, 1])), "the spine is green")
        _, pod_rgb = painted_points(self.dir_a, self.manifest["pod"]["mesh"])
        self.assertGreater(float(np.median(pod_rgb.mean(axis=1))), float(np.median(rgb.mean(axis=1))), "the pods are paler")

    def test_the_engine_domes_and_the_windows_glow(self) -> None:
        glowing = glowing_points(self.dir_a, self.manifest["mesh"]) + self.offset
        self.assertGreater(len(glowing), 0)
        domes = glowing[glowing[:, 2] > 70.0]
        self.assertTrue((domes[:, 0] > 5.0).any() and (domes[:, 0] < -5.0).any(), "both engine domes")
        self.assertTrue((glowing[:, 2] < 20.0).any(), "the bow's window strips")
        self.assertEqual(len(glowing_points(self.dir_a, self.manifest["pod"]["mesh"])), 0, "the pods are dark")

    # --- chunks ------------------------------------------------------------------------------------------------------
    def test_chunks_cut_the_hull(self) -> None:
        assert_chunks_cut_the_hull(self, self.dir_a, self.manifest, self.hp, CHUNKS)

    def test_chunks_leave_the_pods_out_and_have_joints(self) -> None:
        self.assertNotIn("pod", self.manifest["chunks"])
        for entry in self.hp["chunks"]:
            self.assertEqual(len(entry["joint"]), 3, entry["name"])
        joints = {c["name"]: np.array(c["joint"]) for c in self.hp["chunks"]}
        np.testing.assert_allclose(joints["arm_l"], mirrored(list(joints["arm_r"])), atol=1e-4)
        np.testing.assert_allclose(joints["engine_l"], mirrored(list(joints["engine_r"])), atol=1e-4)

    # --- hardpoints --------------------------------------------------------------------------------------------------
    def test_hardpoints_schema(self) -> None:
        keys = {"asset_id", "generator_version", "frame", "units", "length_m", "span_m", "height_m", "mass_kg",
                "inertia_estimate_kg_m2", "center_of_mass", "cockpit_camera", "chase_anchor", "muzzles", "pods", "rcs",
                "collision", "nav_lights", "turrets", "cargo_pods", "chunks"}  # fmt: skip
        self.assertEqual(set(self.hp), keys)
        self.assertEqual(self.hp["muzzles"], [])
        self.assertEqual(self.hp["frame"], "godot")

    def test_two_pods_on_the_nacelles_each_with_main_and_retro(self) -> None:
        pods = {p["name"]: p for p in self.hp["pods"]}
        self.assertEqual(set(pods), {"l", "r"})
        self.assertEqual((pods["l"]["side"], pods["r"]["side"]), ("left", "right"))
        main = self.authored(pods["r"]["main"]["position"])
        np.testing.assert_allclose(main[:2], NACELLE_AXIS, atol=1e-3)
        self.assertEqual(pods["r"]["main"]["exhaust"], [0.0, 0.0, 1.0])
        self.assertEqual(pods["r"]["retro"]["exhaust"], [0.0, 0.0, -1.0])
        np.testing.assert_allclose(pods["l"]["main"]["position"], mirrored(pods["r"]["main"]["position"]), atol=1e-4)

    def test_each_retro_fires_clear_of_the_hull(self) -> None:
        # The depth proxy (the hull's mesh) hides a plume inside the hull: the retro's forward ray meets nothing within
        # the hull, and the skin is right behind the nozzle.
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
            self.assertLess(float(self.xyz[near_axis, 2].max()), p["main"]["position"][2], "behind the engine dome")
            self.assertAlmostEqual(float(self.xyz[near_axis, 2].max()), p["main"]["position"][2], delta=0.25)

    def test_the_centre_of_mass_is_on_the_thrust_line(self) -> None:
        com = self.authored(self.hp["center_of_mass"])
        self.assertAlmostEqual(float(com[0]), 0.0, places=4)
        self.assertAlmostEqual(float(com[1]), NACELLE_AXIS[1], places=3)
        self.assertTrue(30.0 < com[2] < 60.0, com)

    def test_cosmetic_rcs_ports_carry_pilot_terms_and_mirror(self) -> None:
        names = {r["name"]: r for r in self.hp["rcs"]}
        self.assertEqual(len(names), 9)
        for r in self.hp["rcs"]:
            self.assertTrue(set(r["tags"]) <= PILOT_TERMS, r["name"])
            self.assertIn(r["pod"], ("l", "r"))
        for name, r in names.items():
            if name.startswith("r_"):
                np.testing.assert_allclose(names["l_" + name[2:]]["position"], mirrored(r["position"]), atol=1e-4)
        prow = self.authored(names["prow"]["position"])
        self.assertLess(float(prow[2]), 0.5, "the prow's port is at the nose")

    def test_cockpit_camera_is_in_the_bow_looking_forward(self) -> None:
        cam = self.hp["cockpit_camera"]
        np.testing.assert_allclose(self.authored(cam["position"]), bp.EYE, atol=1e-3)
        self.assertEqual(cam["forward"], [0.0, 0.0, -1.0])
        eye = self.authored(cam["position"])
        self.assertGreater(bp.bow_half_width(float(eye[1]), float(eye[2])), 1.0, "inside the blade")

    def test_the_top_lamp_stands_over_the_spine_and_the_bow_joint_on_the_structure(self) -> None:
        lamp = self.authored(self.hp["nav_lights"]["top_lamp"])
        spine = self.authored_xyz[(np.abs(self.authored_xyz[:, 2] - lamp[2]) < 0.5) & (np.abs(self.authored_xyz[:, 0]) < 1.0)]
        self.assertAlmostEqual(float(lamp[1] - spine[:, 1].max()), 6.2, delta=0.3)
        joint = self.authored(next(c for c in self.hp["chunks"] if c["name"] == "bow")["joint"])
        nearest = float(np.linalg.norm(self.authored_xyz - joint, axis=1).min())
        self.assertLess(nearest, 2.5, "the bow breaks on its own structure")
        for name, mount in MOUNTS.items():
            local = joint - np.array(mount)
            self.assertFalse(abs(local[2]) < 0.5 * POD[2] and abs(local[0]) < 0.5 * POD[0] and abs(local[1]) < 0.5 * POD[1], name)

    def test_chase_anchor_and_nav_lights(self) -> None:
        length = self.hp["length_m"]
        np.testing.assert_allclose(self.hp["chase_anchor"]["position"], [0.0, 0.3 * length, 1.2 * length], atol=1e-3)
        nav = self.hp["nav_lights"]
        np.testing.assert_allclose(nav["port"], mirrored(nav["starboard"]), atol=1e-4)
        self.assertGreater(float(self.authored(nav["starboard"])[0]), 13.9, "outside the right arm")
        self.assertAlmostEqual(nav["top_lamp_range_m"], round(0.3 * length, 2))
        self.assertAlmostEqual(nav["cabin_range_m"], round(0.05 * length, 2))

    def test_two_flank_turrets_where_the_maintainer_placed_them(self) -> None:
        turrets = {t["name"]: t for t in self.hp["turrets"]}
        self.assertEqual(set(turrets), {"flank_l", "flank_r"}, "Q22: one in each flank inset, the Bokmai's exception to Q19")
        right = turrets["flank_r"]
        self.assertEqual(set(right), {"name", "position", "up", "arc_deg", "barrel_m"})
        np.testing.assert_allclose(self.authored(right["position"]), FLANK_TURRET, atol=1e-3)
        self.assertEqual(right["up"], [1.0, 0.0, 0.0], "outboard")
        self.assertEqual(turrets["flank_l"]["up"], [-1.0, 0.0, 0.0])
        np.testing.assert_allclose(turrets["flank_l"]["position"], mirrored(right["position"]), atol=1e-4)
        self.assertEqual((right["arc_deg"], right["barrel_m"]), (200.0, 3.0))
        # The seat is on the blade's skin, inside the inset's full-height step.
        x, y, z = FLANK_TURRET
        self.assertAlmostEqual(bp.bow_half_width(y, z), x, delta=0.15)
        (_u0, u1, _u2, u3), (l0, _l1, l2, _l3) = bp.INSET_STRIPS
        self.assertTrue(l0 < z < u1 and l2 < y < u3, "in the inset's full-height step")

    def test_the_turret_model_is_the_approved_brakiri_turret(self) -> None:
        turret = self.manifest["turret"]
        self.assertEqual(set(turret), {"obj", "mesh", "barrel_m", "trunnion", "muzzles"})
        self.assertEqual(turret["obj"], "brakiri_bokmai_turret.obj")
        assert_model_mesh(self, self.dir_a, turret["mesh"], turret["obj"], "turret")
        self.assertLessEqual(turret["mesh"]["triangles"], MODEL_TRIANGLE_BUDGET)
        left, right = turret["muzzles"]
        self.assertEqual(left, mirrored(right))
        self.assertAlmostEqual(left[2], -3.0, msg="the muzzles 3.0 m ahead of the turning axis")
        local = read_obj(self.dir_a / turret["obj"]).vertices  # the turret's frame: the pivot at the origin
        self.assertAlmostEqual(float(local[:, 1].min()), -0.05, delta=0.1, msg="the ring stands on the mount")
        ring = local[local[:, 1] < 0.3]
        self.assertAlmostEqual(float(np.hypot(ring[:, 0], ring[:, 2]).max()), 0.8, delta=0.1, msg="a 1.6 m ring (the sheet)")
        assert_mirror_symmetric(self, local, "turret")

    # --- cargo pods ----------------------------------------------------------------------------------------------------
    def test_three_cargo_mounts_on_the_spindle(self) -> None:
        cargo = {c["name"]: c for c in self.hp["cargo_pods"]}
        self.assertEqual(set(cargo), set(MOUNTS))
        for name, mount in MOUNTS.items():
            c = cargo[name]
            self.assertEqual(set(c), {"name", "position", "up", "forward"})
            np.testing.assert_allclose(self.authored(c["position"]), mount, atol=1e-3)
            self.assertEqual((c["up"], c["forward"]), ([0.0, 1.0, 0.0], [0.0, 0.0, -1.0]))

    def test_the_pod_model_is_a_textured_mesh_inside_its_budget(self) -> None:
        pod = self.manifest["pod"]
        self.assertEqual(set(pod), {"obj", "mesh", "mass_kg", "collision", "size_m"})
        self.assertEqual(pod["obj"], "brakiri_bokmai_pod.obj")
        assert_model_mesh(self, self.dir_a, pod["mesh"], pod["obj"], "pod")
        self.assertLessEqual(pod["mesh"]["triangles"], MODEL_TRIANGLE_BUDGET)
        self.assertGreater(pod["mass_kg"], 0.0)

    def test_the_pods_origin_is_its_mount_and_it_has_the_measured_size(self) -> None:
        lo, hi = self.pod_xyz.min(axis=0), self.pod_xyz.max(axis=0)
        np.testing.assert_allclose(hi[0] - lo[0], POD[0] + 0.48, atol=0.4, err_msg="width, with the side plates")
        np.testing.assert_allclose(hi[2] - lo[2], POD[2] + 0.7, atol=0.3, err_msg="length, with the sleeve's ends")
        self.assertAlmostEqual(float(0.5 * (lo[2] + hi[2])), 0.0, delta=0.05)
        self.assertAlmostEqual(float(-lo[1]), 0.5 * POD[1], delta=0.35, msg="centred on the spindle's axis")
        self.assertAlmostEqual(float(hi[1]), 0.5 * POD[1] + 0.5, delta=0.35, msg="the top plate's blocks above the crown")

    def test_mounted_pods_sit_where_the_reference_has_them_and_clear_the_frame(self) -> None:
        for name, mount in MOUNTS.items():
            placed = self.pod_xyz + np.array(mount)
            z0, z1 = POD_SPANS[name]
            body = placed[np.abs(placed[:, 0]) < 8.0]
            self.assertAlmostEqual(float(body[:, 2].min()), z0 - 0.35, delta=0.35, msg=name)
            self.assertAlmostEqual(float(body[:, 2].max()), z1 + 0.35, delta=0.35, msg=name)
        # Nothing of the hull but the spindle comes within 1 m of a mounted pod's body.
        hull = self.authored_xyz[np.hypot(self.authored_xyz[:, 0], self.authored_xyz[:, 1] - 1.70) > SLEEVE_R + 0.1]
        for mount in MOUNTS.values():
            local = hull - np.array(mount)
            near = (np.abs(local[:, 0]) < 0.5 * POD[0] + 1.0) & (np.abs(local[:, 1]) < 0.5 * POD[1] + 1.0) & (np.abs(local[:, 2]) < 0.5 * POD[2])
            self.assertEqual(int(near.sum()), 0, mount)

    def test_the_pod_collision_box_covers_its_mesh(self) -> None:
        box = self.manifest["pod"]["collision"][0]
        self.assertEqual((box["type"], box["name"]), ("box", "body"))
        inside = inside_primitive(self.pod_xyz, box, 0.05)
        self.assertTrue(bool(inside.all()))

    # --- collision -----------------------------------------------------------------------------------------------------
    def test_collision_primitives_cover_the_visible_surface_and_stay_close(self) -> None:
        inside = np.zeros(len(self.xyz), dtype=bool)
        for c in self.hp["collision"]:
            inside |= inside_primitive(self.xyz, c, inflate=self.spacing)
        missed = self.xyz[~inside] + self.offset
        self.assertTrue(bool(inside.all()), f"every visible surface sample; missed (authored frame): {np.round(missed[:10], 2).tolist()}")
        lo, hi = self.xyz.min(axis=0), self.xyz.max(axis=0)
        for c in self.hp["collision"]:
            basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
            np.testing.assert_allclose(basis.T @ basis, np.eye(3), atol=1e-4)
            self.assertAlmostEqual(float(np.linalg.det(basis)), 1.0, places=3)
            if c["type"] == "box":
                corners = np.array([[a, b, d] for a in (-1, 1) for b in (-1, 1) for d in (-1, 1)]) * 0.5 * np.array(c["size"])
                extent = corners @ basis.T + np.array(c["position"])
            else:
                half = 0.5 * c["height"] - c["radius"]
                ends = np.array([[0, 0, -half], [0, 0, half]]) @ basis.T + np.array(c["position"])
                extent = np.concatenate([ends - c["radius"], ends + c["radius"]])
            self.assertTrue(np.all(extent.min(axis=0) >= lo - 1.0) and np.all(extent.max(axis=0) <= hi + 1.0), c["name"])

    def test_collision_is_mirror_symmetric(self) -> None:
        shapes = {c["name"]: c for c in self.hp["collision"]}
        self.assertEqual(len(shapes), len(self.hp["collision"]), "unique names")
        for name, c in shapes.items():
            part = name.split("_")
            side = next((k for k, w in enumerate(part) if w in ("r", "l")), None)
            if side is None:
                self.assertAlmostEqual(c["position"][0], 0.0, places=4, msg=name)
            elif part[side] == "r":
                twin = shapes["_".join(part[:side] + ["l"] + part[side + 1 :])]
                np.testing.assert_allclose(twin["position"], mirrored(c["position"]), atol=1e-4, err_msg=name)

    # --- meshes --------------------------------------------------------------------------------------------------------
    def test_the_fallback_mesh_and_chunk_meshes_hold_every_piece(self) -> None:
        parts = [p.part for p in cv.with_twins(bp.assemble(BRAKIRI))]
        self.assertEqual(
            {p.name for p in parts},
            {"bow", "inset_r", "inset_l", "windows_r", "windows_l", "spine", "spindle", "web_r", "web_l", "arm_r", "arm_l",
             "strut_r", "strut_l", "post_r", "post_l", "nacelle_r", "nacelle_l", "dome_r", "dome_l", "fin_top_r",
             "fin_top_l", "fin_bot_r", "fin_bot_l"},
        )  # fmt: skip
        self.assertTrue(all(p.mesh.face_count > 0 for p in parts))
        self.assertEqual(len(self.obj.faces), sum(p.mesh.face_count for p in parts), "the hull OBJ is every piece")
        for entry in self.hp["chunks"]:
            expected = sum(p.mesh.face_count for p in parts if p.group == entry["name"])
            self.assertEqual(len(read_obj(self.dir_a / entry["obj"]).faces), expected, entry["name"])
        self.assertEqual(len(read_obj(self.dir_a / "brakiri_bokmai_pod.obj").faces), bp.cargo_pod(BRAKIRI).part.mesh.face_count)

    def test_the_fallback_mesh_holds_the_visible_surface(self) -> None:
        v = self.obj.vertices
        self.assertTrue(np.all(np.isfinite(v)))
        slack = 2.0 * self.spacing
        np.testing.assert_allclose(v.min(axis=0), self.xyz.min(axis=0), atol=slack)
        np.testing.assert_allclose(v.max(axis=0), self.xyz.max(axis=0), atol=slack)
        for name in ("bk_hull", "bk_stripe", "bk_hull_dark", "bk_nozzle", "bk_engine_dome", "bk_window"):
            self.assertIn(name, self.obj.materials, name)

    # --- determinism, options ------------------------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        for out in self.out_a.files:
            self.assertEqual(sha256(out), sha256(self.dir_b / out.name), out.name)

    def test_a_different_seed_changes_the_wear_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = bok.build(BuildContext(Path(tmp), seed=7, options=TEST_OPTIONS))
            albedo = self.manifest["mesh"]["surfaces"][0]["albedo"]
            self.assertNotEqual(sha256(Path(tmp) / albedo), sha256(self.dir_a / albedo))
            hp = json.loads((Path(tmp) / bok.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            authored = np.array(hp["turrets"][1]["position"]) + np.array(other.manifest["centroid_offset"])
            np.testing.assert_allclose(authored, FLANK_TURRET, atol=1e-3)
            self.assertEqual([c["name"] for c in hp["collision"]], [c["name"] for c in self.hp["collision"]])
            self.assertEqual(other.manifest["mesh"]["triangles"], self.manifest["mesh"]["triangles"])

    def test_the_spacing_option_is_recorded_and_keeps_the_origin(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = bok.build(BuildContext(Path(tmp), seed=42, options={**TEST_OPTIONS, "spacing": 2.0 * bok.DEFAULT_SPACING_M}))
            self.assertEqual(out.manifest["surface_spacing_m"], 2.0 * bok.DEFAULT_SPACING_M)
            np.testing.assert_allclose(out.manifest["centroid_offset"], self.offset, atol=0.15)  # a fifth of a per cent of the length

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for bad in ({"spacing": 0.0}, {"spacing": -1.0}):
                with self.assertRaises(ValueError):
                    bok.build(BuildContext(Path(tmp), seed=1, options=bad))


class CivilianPipelineTests(unittest.TestCase):
    """The shared helper's naming and mirroring rules (core/civilian.py)."""

    def test_left_names_and_twins(self) -> None:
        self.assertEqual(cv.left_name("arm_r"), "arm_l")
        self.assertEqual(cv.left_name("bow"), "bow")
        mesh = bp.cargo_pod(BRAKIRI).part.mesh.translated((5.0, 0.0, 0.0))
        right = cv.Piece(Part("thing_r", mesh, group="engine_r"), None, cv.RIGHT)
        centre = cv.Piece(Part("spine", mesh, group="bow"))
        twins = cv.with_twins([centre, right])
        self.assertEqual([p.name for p in twins], ["spine", "thing_r", "thing_l"])
        self.assertEqual(twins[2].group, "engine_l")
        np.testing.assert_allclose(twins[2].part.mesh.bounds()[0][0], -mesh.bounds()[1][0])

    def test_rounding_has_no_negative_zero(self) -> None:
        self.assertEqual(cv.r([-0.0000001, 1.234567]), [0.0, 1.23457])
        self.assertEqual(str(cv.r([-0.0])[0]), "0.0")


if __name__ == "__main__":
    unittest.main()
