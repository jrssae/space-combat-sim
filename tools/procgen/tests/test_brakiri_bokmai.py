"""``brakiri_bokmai`` (M5-T22, AC12, D59, D61, Q17, Q22): files, budgets, frames, symmetry, chunk partition, collision
coverage, the hardpoint contract with its two flank turrets and three cargo mounts, the pod model, the turret model,
colours and determinism; and the shared civilian pipeline (``core/civilian.py``).

The expected numbers are typed in from docs/assets-civilian.md and docs/design-references.md ("Brakiri Bokmai
transport"), not read from the generator.
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
from tools.procgen.core import frames, lighting
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.color import linear_to_srgb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.obj import read_obj
from tools.procgen.core.ply import read_ply
from tools.procgen.parts import Part
from tools.procgen.parts import brakiri as bp
from tools.procgen.styles.brakiri import BOLT_SRGB, BRAKIRI, GLOW_SRGB

PILOT_TERMS = {
    "sway_left", "sway_right", "heave_up", "heave_down", "pitch_up", "pitch_down",
    "yaw_left", "yaw_right", "roll_left", "roll_right",
}  # fmt: skip
SYM_TOL = 1e-5
LOD_AABB_TOLERANCE_M = 0.3  # test_splat_import.gd's floor
LARGE_HULL_EXTENT_M = 30.0  # ... and from this box size a coarse level may fall short by 1.25 of its spacing
CHUNKS = ("bow", "arm_l", "arm_r", "engine_l", "engine_r")
BUDGET = (32_000, 49_000)  # docs/assets-civilian.md: the hull 40 500 (32 000 to 49 000)
POD_BUDGET = (9_000, 14_000)  # each pod 11 500
LOD_SHARES = {1: (0.20, 0.30), 2: (0.04, 0.09), 3: (0.01, 0.025)}
LENGTH, SPAN, HEIGHT = 80.0, 31.62, 30.91  # Q17 and the reference's box at 80 m
NACELLE_AXIS = (13.16, 2.09)  # x, y of the cups and domes: the thrust line
MOUNTS = {"pod_fwd": (0.0, 1.70, 24.63), "pod_mid": (0.0, 1.70, 39.07), "pod_aft": (0.0, 1.70, 53.57)}
POD_SPANS = {"pod_fwd": (17.94, 31.33), "pod_mid": (32.37, 45.76), "pod_aft": (46.87, 60.26)}  # the reference's pods' z
POD = (17.81, 11.74, 13.39)  # width, height, length
SLEEVE_R = 1.48  # the bore round the spindle the no-splats test leaves out
FLANK_TURRET = (2.04, 8.45, 6.58)  # Q22: in the stepped inset high on the right flank, up +x (the maintainer's sheet)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sorted_rows(a: np.ndarray) -> np.ndarray:
    return a[np.lexsort((a[:, 2], a[:, 1], a[:, 0]))]


def godot_xyz(path: Path) -> np.ndarray:
    return frames.flip_xy(read_ply(path).to_splats().xyz)


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


def assert_lod_box(tc: unittest.TestCase, xyz: np.ndarray, manifest: dict, spacing: float, label: object) -> None:
    """test_splat_import.gd's rule for a coarse level's box against LOD0's (see test_narn_transport.py)."""
    lo0, hi0 = np.array(manifest["aabb_min"]), np.array(manifest["aabb_max"])
    lo, hi = xyz.min(axis=0), xyz.max(axis=0)
    past = max(float((lo0 - lo).max()), float((hi - hi0).max()))
    short = max(float((lo - lo0).max()), float((hi0 - hi).max()))
    tc.assertLessEqual(past, max(LOD_AABB_TOLERANCE_M, 0.25 * spacing), (label, "past LOD0's box", past))
    big = float((hi0 - lo0).max()) >= LARGE_HULL_EXTENT_M
    tc.assertLessEqual(short, max(LOD_AABB_TOLERANCE_M, 1.25 * spacing) if big else LOD_AABB_TOLERANCE_M, (label, "short", short))


class BrakiriBokmaiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = bok.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = bok.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.splats = read_ply(cls.dir_a / bok.PLY_NAME).to_splats()
        cls.xyz = frames.flip_xy(cls.splats.xyz)
        cls.hp = json.loads((cls.dir_a / bok.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / bok.OBJ_NAME)
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.spacing = float(cls.manifest["lods"][0]["spacing_m"])
        cls.authored_xyz = cls.xyz + cls.offset
        cls.pod_xyz = godot_xyz(cls.dir_a / "brakiri_bokmai_pod.ply")

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
        expected = {"brakiri_bokmai.ply", "brakiri_bokmai.obj", "hardpoints.json", "manifest.json", "brakiri_bokmai_turret.ply",
                    "brakiri_bokmai_turret.obj", "brakiri_bokmai_pod.ply", "brakiri_bokmai_pod.obj"}  # fmt: skip
        expected |= {f"brakiri_bokmai_lod{k}.ply" for k in (1, 2, 3)} | {f"brakiri_bokmai_pod_lod{k}.ply" for k in (1, 2, 3)}
        expected |= {f"brakiri_bokmai_chunk_{c}.ply" for c in CHUNKS}
        self.assertTrue(expected <= names, sorted(expected - names))
        self.assertFalse(any(n.startswith("brakiri_bokmai_pod_lod") and n.endswith(".obj") for n in names), "one pod mesh")
        for p in self.out_a.files:
            self.assertTrue(p.is_file(), p)

    def test_lod0_is_inside_the_budget_and_counted_by_group(self) -> None:
        total = self.manifest["lods"][0]["splats"]
        self.assertTrue(BUDGET[0] <= total <= BUDGET[1], total)
        self.assertEqual(len(self.splats), total)
        self.assertEqual(tuple(self.manifest["counts"]), CHUNKS)
        self.assertEqual(sum(self.manifest["counts"].values()), total)
        self.assertEqual(self.manifest["counts"]["arm_l"], self.manifest["counts"]["arm_r"])
        self.assertEqual(self.manifest["counts"]["engine_l"], self.manifest["counts"]["engine_r"])

    def test_lods_one_to_three_are_coarser_centred_and_keep_the_box(self) -> None:
        lod0 = self.manifest["lods"][0]
        for level, (name, factor, _stream, share) in bok.LODS.items():
            entry = self.manifest["lods"][level]
            self.assertEqual(entry["file"], name)
            self.assertAlmostEqual(entry["spacing_m"], factor * lod0["spacing_m"])
            self.assertTrue(LOD_SHARES[level][0] <= entry["splats"] / lod0["splats"] <= LOD_SHARES[level][1], level)
            xyz = godot_xyz(self.dir_a / name)
            self.assertEqual(len(xyz), entry["splats"])
            self.assertLess(float(np.abs(xyz.mean(axis=0)).max()), 1e-3, "centred like LOD0")
            assert_lod_box(self, xyz, self.manifest, entry["spacing_m"], level)

    def test_dimensions_match_the_design(self) -> None:
        self.assertAlmostEqual(self.hp["length_m"], LENGTH, delta=0.01 * LENGTH)
        self.assertAlmostEqual(self.hp["span_m"], SPAN, delta=0.01 * SPAN)
        self.assertAlmostEqual(self.hp["height_m"], HEIGHT, delta=0.01 * HEIGHT)

    # --- frames, symmetry, splats ------------------------------------------------------------------------------------
    def test_ply_is_centred_and_the_aabb_matches_after_the_flip(self) -> None:
        self.assertLess(float(np.abs(self.xyz.mean(axis=0)).max()), 1e-3)
        np.testing.assert_allclose(self.xyz.min(axis=0), self.manifest["aabb_min"], atol=2e-4)
        np.testing.assert_allclose(self.xyz.max(axis=0), self.manifest["aabb_max"], atol=2e-4)

    def test_the_authored_frame_is_the_references(self) -> None:
        lo, hi = self.authored_xyz.min(axis=0), self.authored_xyz.max(axis=0)
        self.assertAlmostEqual(float(lo[2]), 0.0, delta=0.3, msg="the prow at z = 0")
        self.assertAlmostEqual(float(hi[2]), LENGTH, delta=0.3, msg="the domes at z = 80")
        self.assertAlmostEqual(float(0.5 * (lo[1] + hi[1])), 0.0, delta=0.3, msg="y from the box centre")
        self.assertAlmostEqual(float(0.5 * (lo[0] + hi[0])), 0.0, delta=1e-6)

    def test_every_level_is_exactly_mirror_symmetric_in_x(self) -> None:
        levels = [self.xyz] + [godot_xyz(self.dir_a / bok.LODS[k][0]) for k in (1, 2, 3)] + [self.pod_xyz]
        for k, xyz in enumerate(levels):
            np.testing.assert_allclose(sorted_rows(xyz), sorted_rows(xyz * np.array([-1.0, 1.0, 1.0])), atol=SYM_TOL, err_msg=str(k))

    def test_splats_are_flat_oriented_opaque_discs(self) -> None:
        scale = self.splats.scale
        self.assertTrue(np.all(scale[:, 2] < scale[:, 0]))
        self.assertTrue(np.all(self.splats.alpha > 0.9))

    def test_the_blade_is_forward_and_the_fins_aft(self) -> None:
        a = self.authored_xyz
        bow = a[(a[:, 2] < 10.0) & (a[:, 1] > 3.0)]  # above the arms' roots
        self.assertLess(float(np.abs(bow[:, 0]).max()), 3.0, "the blade is narrow")
        self.assertGreater(float(bow[:, 1].max()), 12.5, "and tall")
        fins = a[np.abs(a[:, 1]) > 14.0]
        self.assertGreater(float(fins[:, 2].min()), 69.0, "the tall fins are at the stern (Q22)")
        np.testing.assert_allclose(np.abs(fins[:, 0]).mean(), 12.92, atol=0.3)

    # --- the hull leaves its pods out ----------------------------------------------------------------------------------
    def test_the_hull_has_no_splats_inside_the_pod_volumes(self) -> None:
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
            self.assertEqual(srgb_hex(m[role].albedo), value, role)
        self.assertEqual((GLOW_SRGB, BOLT_SRGB), (0xFFF0B0, 0x7CFF4F), "the glow and the bright green bolts (Q22)")

    def test_the_paint_reaches_the_splats(self) -> None:
        rgb = self.splats.rgb
        a = self.authored_xyz
        fins_top = (a[:, 1] > 14.2)
        self.assertGreater(float(rgb[fins_top][:, 0].mean()), 0.45, "the fins' yellow tops")
        green = (a[:, 2] > 20) & (a[:, 2] < 40) & (a[:, 1] > 12.5)
        self.assertLess(float(rgb[green][:, 0].mean()), float(rgb[green][:, 1].mean()), "the spine is green")
        pod_rgb = read_ply(self.dir_a / "brakiri_bokmai_pod.ply").to_splats().rgb
        self.assertGreater(float(np.median(pod_rgb.mean(axis=1))), float(np.median(rgb.mean(axis=1))), "the pods are paler")

    def test_every_level_chunk_pod_and_the_turret_has_matching_lighting_records(self) -> None:
        pairs = [(lod["file"], lod["lighting"]) for lod in self.manifest["lods"] + self.manifest["pod"]["lods"]]
        pairs += [(c["ply"], c["lighting"]) for c in self.hp["chunks"]]
        pairs.append((self.manifest["turret"]["ply"], self.manifest["turret"]["lighting"]))
        self.assertEqual(len(pairs), 8 + len(CHUNKS) + 1)
        for ply_name, light_name in pairs:
            records = lighting.read_lighting(self.dir_a / light_name)
            self.assertEqual(len(records), len(read_ply(self.dir_a / ply_name).to_splats()), light_name)

    # --- chunks ------------------------------------------------------------------------------------------------------
    def test_chunks_partition_lod1_exactly(self) -> None:
        self.assertEqual([c["name"] for c in self.hp["chunks"]], list(CHUNKS))
        self.assertEqual(self.manifest["chunks"], list(CHUNKS))
        lod1 = read_ply(self.dir_a / bok.LODS[1][0]).to_splats()
        lod1_xyz = frames.flip_xy(lod1.xyz)
        start = 0
        for entry in self.hp["chunks"]:
            n = entry["splats"]
            chunk = read_ply(self.dir_a / entry["ply"]).to_splats()
            self.assertEqual(len(chunk), n)
            np.testing.assert_allclose(frames.flip_xy(chunk.xyz) + np.array(entry["offset"]), lod1_xyz[start : start + n], atol=1e-5)
            np.testing.assert_allclose(chunk.rgb, lod1.rgb[start : start + n], atol=1e-4)
            start += n
        self.assertEqual(start, len(lod1))

    def test_chunks_leave_the_pods_out_and_have_joints(self) -> None:
        self.assertNotIn("pod", self.manifest["counts"])
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
        self.assertTrue(5.77 < z < 7.39 and 7.23 < y < 9.67)

    def test_the_turret_model_is_the_approved_brakiri_turret(self) -> None:
        turret = self.manifest["turret"]
        self.assertEqual(turret["ply"], "brakiri_bokmai_turret.ply")
        self.assertEqual(set(turret), {"ply", "lighting", "obj", "splats", "spacing_m", "offset", "barrel_m", "trunnion", "muzzles"})
        splats = read_ply(self.dir_a / turret["ply"]).to_splats()
        self.assertEqual(turret["splats"], len(splats))
        self.assertTrue(1_500 <= len(splats) <= 3_000, len(splats))
        left, right = turret["muzzles"]
        self.assertEqual(left, mirrored(right))
        self.assertAlmostEqual(left[2], -3.0, msg="the muzzles 3.0 m ahead of the turning axis")
        local = frames.flip_xy(splats.xyz) + np.array(turret["offset"])
        self.assertAlmostEqual(float(local[:, 1].min()), -0.05, delta=0.1, msg="the ring stands on the mount")
        ring = local[local[:, 1] < 0.3]
        self.assertAlmostEqual(float(np.hypot(ring[:, 0], ring[:, 2]).max()), 0.8, delta=0.1, msg="a 1.6 m ring (the sheet)")

    # --- cargo pods ----------------------------------------------------------------------------------------------------
    def test_three_cargo_mounts_on_the_spindle(self) -> None:
        cargo = {c["name"]: c for c in self.hp["cargo_pods"]}
        self.assertEqual(set(cargo), set(MOUNTS))
        for name, mount in MOUNTS.items():
            c = cargo[name]
            self.assertEqual(set(c), {"name", "position", "up", "forward"})
            np.testing.assert_allclose(self.authored(c["position"]), mount, atol=1e-3)
            self.assertEqual((c["up"], c["forward"]), ([0.0, 1.0, 0.0], [0.0, 0.0, -1.0]))

    def test_the_pod_model_is_inside_its_budget_and_its_levels_follow_the_hull(self) -> None:
        pod = self.manifest["pod"]
        self.assertEqual(set(pod), {"obj", "lods", "offset", "mass_kg", "collision", "size_m"})
        self.assertEqual(pod["obj"], "brakiri_bokmai_pod.obj")
        self.assertEqual([e["level"] for e in pod["lods"]], [0, 1, 2, 3])
        self.assertTrue(POD_BUDGET[0] <= pod["lods"][0]["splats"] <= POD_BUDGET[1], pod["lods"][0]["splats"])
        for entry, hull in zip(pod["lods"], self.manifest["lods"]):
            self.assertAlmostEqual(entry["spacing_m"], hull["spacing_m"], msg="it switches with the hull")
            self.assertEqual(len(read_ply(self.dir_a / entry["file"]).to_splats()), entry["splats"])
        self.assertGreater(pod["mass_kg"], 0.0)

    def test_the_pods_origin_is_its_mount_and_it_has_the_measured_size(self) -> None:
        lo, hi = self.pod_xyz.min(axis=0), self.pod_xyz.max(axis=0)
        np.testing.assert_allclose(hi[0] - lo[0], POD[0] + 0.48, atol=0.4, err_msg="width, with the side plates")
        np.testing.assert_allclose(hi[2] - lo[2], POD[2] + 0.7, atol=0.3, err_msg="length, with the sleeve's ends")
        self.assertAlmostEqual(float(0.5 * (lo[2] + hi[2])), 0.0, delta=0.05)
        self.assertAlmostEqual(float(-lo[1]), 0.5 * POD[1], delta=0.35, msg="centred on the spindle's axis")
        np.testing.assert_allclose(self.pod_xyz.mean(axis=0), self.manifest["pod"]["offset"], atol=1e-3)

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

    def test_the_pod_collision_box_covers_its_splats(self) -> None:
        box = self.manifest["pod"]["collision"][0]
        self.assertEqual(box["type"], "box")
        inside = inside_primitive(self.pod_xyz, box, self.spacing)
        self.assertTrue(bool(inside.all()))

    # --- collision -----------------------------------------------------------------------------------------------------
    def test_collision_primitives_cover_every_splat_and_stay_close(self) -> None:
        inside = np.zeros(len(self.xyz), dtype=bool)
        for c in self.hp["collision"]:
            inside |= inside_primitive(self.xyz, c, inflate=self.spacing)
        missed = self.xyz[~inside] + self.offset
        self.assertTrue(bool(inside.all()), f"every LOD0 splat centre; missed (authored frame): {np.round(missed[:10], 2).tolist()}")
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

    def test_fallback_obj_matches_the_splat_bounds(self) -> None:
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

    def test_a_different_seed_changes_the_splats_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = bok.build(BuildContext(Path(tmp), seed=7))
            self.assertNotEqual(sha256(Path(tmp) / bok.PLY_NAME), sha256(self.dir_a / bok.PLY_NAME))
            hp = json.loads((Path(tmp) / bok.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            authored = np.array(hp["turrets"][1]["position"]) + np.array(other.manifest["centroid_offset"])
            np.testing.assert_allclose(authored, FLANK_TURRET, atol=1e-3)
            self.assertEqual([c["name"] for c in hp["collision"]], [c["name"] for c in self.hp["collision"]])

    def test_spacing_option_scales_the_count_and_is_recorded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = bok.build(BuildContext(Path(tmp), seed=42, options={"spacing": 2.0 * bok.DEFAULT_SPACING_M}))
            self.assertLess(out.manifest["lods"][0]["splats"], 0.4 * len(self.splats))
            self.assertEqual(out.manifest["sampling"]["spacing_m"], 2.0 * bok.DEFAULT_SPACING_M)
            self.assertEqual(out.warnings, (), "the budget warning only applies at the default spacing")

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for bad in ({"spacing": 0.0}, {"overlap": -1.0}, {"thickness": 0}, {"turret_spacing": -0.1}):
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
