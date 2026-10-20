"""``starfury_aurora``: files, counts, frames, hardpoints schema and symmetry, OBJ validity, determinism."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import starfury_aurora as ship
from tools.procgen.core import frames
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.obj import read_obj
from tools.procgen.core.ply import PROPERTY_NAMES, read_ply

PILOT_TERMS = {
    "sway_left", "sway_right", "heave_up", "heave_down", "pitch_up", "pitch_down",
    "yaw_left", "yaw_right", "roll_left", "roll_right",
}  # fmt: skip
SYM_TOL = 1e-6


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mirrored(v: list[float], axes: str) -> list[float]:
    out = list(v)
    for axis in axes:
        k = "xyz".index(axis)
        out[k] = -out[k]
    return out


class StarfuryAuroraTests(unittest.TestCase):
    """Builds the default asset twice (same seed) once for the whole class (about a second each)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = ship.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = ship.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.ply = read_ply(cls.dir_a / ship.PLY_NAME)
        cls.splats = cls.ply.to_splats()
        cls.godot_xyz = frames.flip_xy(cls.splats.xyz)  # centred Godot frame (the hardpoints frame)
        cls.hp = json.loads((cls.dir_a / ship.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / ship.OBJ_NAME)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    # --- files and manifest -----------------------------------------------------------------
    def test_all_ship_files_are_written_and_listed(self) -> None:
        names = sorted(p.name for p in self.dir_a.iterdir())
        self.assertEqual(
            names,
            [
                "cockpit_interior.mtl",
                "cockpit_interior.obj",
                "hardpoints.json",
                "manifest.json",
                "starfury_aurora.mtl",
                "starfury_aurora.obj",
                "starfury_aurora.ply",
            ],
        )
        self.assertEqual(sorted(p.name for p in self.out_a.files), names)
        self.assertEqual(self.out_a.warnings, ())
        self.assertEqual(
            self.manifest["files"],
            {"fallback_mesh": "starfury_aurora.obj", "cockpit_mesh": "cockpit_interior.obj", "hardpoints": "hardpoints.json"},
        )

    def test_manifest_lods_zero_and_budget(self) -> None:
        lod0 = self.manifest["lods"][0]
        self.assertEqual(len(self.manifest["lods"]), 1)
        self.assertEqual((lod0["level"], lod0["file"]), (0, "starfury_aurora.ply"))
        self.assertEqual(lod0["spacing_m"], ship.DEFAULT_SPACING_M)
        self.assertTrue(ship.SPLAT_BUDGET[0] <= lod0["splats"] <= ship.SPLAT_BUDGET[1], lod0["splats"])
        self.assertEqual(lod0["splats"], self.ply.count)
        self.assertEqual(self.out_a.splat_count, self.ply.count)
        self.assertEqual(sum(self.manifest["counts"].values()), self.ply.count)
        self.assertEqual((self.manifest["asset_id"], self.manifest["frame"], self.manifest["seed"]), ("starfury_aurora", "godot", 42))
        for key in ("fuselage", "canopy", "pod_ur", "pod_lr", "pod_ul", "pod_ll", "strut_ur", "barrel_l"):
            self.assertIn(key, self.manifest["counts"])
        self.assertEqual(self.manifest["counts"]["pod_ur"], self.manifest["counts"]["pod_ll"])

    # --- PLY content ------------------------------------------------------------------------
    def test_ply_parses_with_the_3dgs_layout_and_finite_values(self) -> None:
        self.assertEqual(self.ply.names, list(PROPERTY_NAMES))
        for name in PROPERTY_NAMES:
            self.assertTrue(np.all(np.isfinite(self.ply.column(name))), name)

    def test_written_positions_are_centred_within_1e_3(self) -> None:
        self.assertLess(float(np.abs(self.splats.xyz.mean(axis=0)).max()), 1e-3)
        self.assertLess(float(np.abs(self.splats.xyz.mean(axis=0)).max()), 1e-4)  # exact by construction
        self.assertEqual(self.manifest["centroid_offset"][:2], [0.0, 0.0])

    def test_manifest_aabb_matches_the_file_after_the_flip(self) -> None:
        lo, hi = frames.aabb_godot_to_3dgs(self.manifest["aabb_min"], self.manifest["aabb_max"])
        np.testing.assert_allclose(self.splats.xyz.min(axis=0), lo, atol=2e-3)
        np.testing.assert_allclose(self.splats.xyz.max(axis=0), hi, atol=2e-3)

    def test_splat_set_is_exactly_mirror_symmetric_in_x(self) -> None:
        xyz = self.godot_xyz.astype(np.float32)
        flipped = xyz.copy()
        flipped[:, 0] *= -1
        view = "f4,f4,f4"
        self.assertTrue(np.array_equal(np.sort(xyz.view(view), axis=0), np.sort(flipped.view(view), axis=0)))

    def test_splats_are_flat_oriented_discs(self) -> None:
        s = self.splats
        spacing = ship.DEFAULT_SPACING_M
        np.testing.assert_allclose(s.scale[:, 0], 1.4 * spacing, rtol=1e-4)
        np.testing.assert_allclose(s.scale[:, 1], 1.4 * spacing, rtol=1e-4)
        np.testing.assert_allclose(s.scale[:, 2], 0.03 * spacing, rtol=1e-3)
        rot = frames.quat_to_matrix(s.rot)
        normals = s.normals / np.linalg.norm(s.normals, axis=1, keepdims=True)
        agreement = np.abs(np.einsum("ij,ij->i", rot[:, :, 2], normals))
        self.assertGreater(float(agreement.min()), 0.999)
        np.testing.assert_allclose(np.linalg.norm(s.rot, axis=1), 1.0, atol=1e-5)

    def test_opacity_is_opaque_except_for_the_canopy_glass(self) -> None:
        alpha = self.splats.alpha
        glass = alpha < 0.5
        self.assertTrue(np.all(alpha[~glass] > 0.979))
        self.assertTrue(np.all(alpha[glass] < 0.05))
        self.assertTrue(0.002 < glass.mean() < 0.03, glass.mean())
        # Glass splats are dark blue, above the hull axis, in the canopy region.
        rgb = self.splats.rgb[glass]
        self.assertTrue(np.all(rgb[:, 2] >= rgb[:, 0]))
        self.assertTrue(np.all(self.godot_xyz[glass, 1] > 0.3))

    def test_colours_show_the_palette_and_the_baked_light(self) -> None:
        rgb, xyz = self.splats.rgb, self.godot_xyz
        self.assertTrue(np.all(rgb >= 0.0))
        self.assertLess(float(rgb.max()), 1.0)
        normals = frames.flip_xy(self.splats.normals)
        up, down = normals[:, 1] > 0.8, normals[:, 1] < -0.8
        self.assertGreater(float(rgb[up].mean()), 1.8 * float(rgb[down].mean()))  # key light from above
        orange = (rgb[:, 0] > 2.0 * rgb[:, 1]) & (rgb[:, 0] > 0.1)
        self.assertTrue(0.005 < orange.mean() < 0.05)  # pod stripes
        self.assertTrue(np.all(np.linalg.norm(xyz[orange, :2], axis=1) > 2.5))  # on the pods only
        chroma = (rgb.max(axis=1) - rgb.min(axis=1)) / np.maximum(rgb.max(axis=1), 1e-9)
        grey = (chroma < 0.15) & (rgb.max(axis=1) > 0.12)
        self.assertGreater(float(grey.mean()), 0.35)  # most of the lit hull is neutral grey

    # --- hardpoints -------------------------------------------------------------------------
    def test_hardpoints_schema(self) -> None:
        hp = self.hp
        for key in (
            "frame", "units", "length_m", "center_of_mass", "cockpit_camera", "chase_anchor",
            "muzzles", "pods", "rcs", "collision", "mass_kg",
        ):  # fmt: skip
            self.assertIn(key, hp)
        self.assertEqual((hp["frame"], hp["units"]), ("godot", "m"))
        self.assertTrue(9.0 < hp["length_m"] < 11.0)
        self.assertTrue(7.0 < hp["span_m"] < 11.0)
        self.assertEqual(hp["chase_anchor"]["position"], [0.0, 2.5, 9.0])
        self.assertEqual(hp["cockpit_camera"]["forward"], [0.0, 0.0, -1.0])
        self.assertEqual(hp["mass_kg"], 48000.0)

    def test_four_pods_two_per_side_symmetric_about_x_and_y(self) -> None:
        pods = {p["name"]: p for p in self.hp["pods"]}
        self.assertEqual(list(pods), ["ur", "lr", "ul", "ll"])
        self.assertEqual([p["side"] for p in self.hp["pods"]], ["right", "right", "left", "left"])
        ur = pods["ur"]
        self.assertGreater(ur["center"][0], 0.0)
        self.assertGreater(ur["center"][1], 0.0)
        self.assertAlmostEqual(ur["center"][0], ur["center"][1], delta=SYM_TOL)  # 45 degrees
        self.assertAlmostEqual(float(np.hypot(*ur["center"][:2])), 4.5, delta=1e-4)
        for name, axes in (("lr", "y"), ("ul", "x"), ("ll", "xy")):
            other = pods[name]
            for key in ("center",):
                np.testing.assert_allclose(other[key], mirrored(ur[key], axes), atol=SYM_TOL)
            for nozzle in ("main", "retro"):
                np.testing.assert_allclose(other[nozzle]["position"], mirrored(ur[nozzle]["position"], axes), atol=SYM_TOL)
                np.testing.assert_allclose(other[nozzle]["exhaust"], ur[nozzle]["exhaust"], atol=SYM_TOL)
        for p in self.hp["pods"]:
            self.assertEqual(p["main"]["exhaust"], [0.0, 0.0, 1.0])
            self.assertEqual(p["retro"]["exhaust"], [0.0, 0.0, -1.0])
            self.assertGreater(p["main"]["position"][2], p["center"][2])
            self.assertLess(p["retro"]["position"][2], p["center"][2])
            self.assertEqual(p["main"]["position"][:2], p["center"][:2])

    def test_center_of_mass_is_on_the_thrust_axis(self) -> None:
        com = self.hp["center_of_mass"]
        self.assertEqual(com[:2], [0.0, 0.0])
        self.assertLess(abs(com[2]), 1.0)
        inertia = self.hp["inertia_estimate_kg_m2"]
        self.assertTrue(all(2e5 < i < 1e6 for i in inertia))

    def test_muzzles_and_camera(self) -> None:
        muzzles = self.hp["muzzles"]
        self.assertEqual([m["name"] for m in muzzles], ["left", "right"])
        np.testing.assert_allclose(muzzles[0]["position"], mirrored(muzzles[1]["position"], "x"), atol=SYM_TOL)
        self.assertAlmostEqual(muzzles[1]["position"][0], 0.6, delta=SYM_TOL)
        self.assertLess(muzzles[0]["position"][1], 0.0)  # under the nose
        for m in muzzles:
            self.assertEqual(m["direction"], [0.0, 0.0, -1.0])
        cam = self.hp["cockpit_camera"]["position"]
        self.assertEqual(cam[0], 0.0)
        self.assertGreater(cam[1], 0.5)
        self.assertLess(cam[2], 0.0)
        self.assertLess(muzzles[0]["position"][2], cam[2])  # guns ahead of the pilot
        # The camera sits inside the canopy: clear of every splat, but within half a metre of the dome.
        d = np.linalg.norm(self.godot_xyz - np.array(cam), axis=1)
        self.assertGreater(float(d.min()), 0.15)
        self.assertLess(float(d.min()), 0.5)

    def test_rcs_nozzles_carry_pilot_term_tags_and_mirror_correctly(self) -> None:
        rcs = {r["name"]: r for r in self.hp["rcs"]}
        self.assertEqual(len(rcs), 16)
        for name, r in rcs.items():
            self.assertTrue(set(r["tags"]) <= PILOT_TERMS, name)
            self.assertTrue(any(t.startswith(("sway", "heave")) for t in r["tags"]), name)
            self.assertAlmostEqual(float(np.linalg.norm(r["exhaust"])), 1.0, places=6)
            self.assertIn(r["pod"], ("ur", "lr", "ul", "ll"))
        self.assertEqual(set(rcs["ur_px"]["tags"]), {"sway_left", "yaw_right", "roll_left"})  # milestone example
        self.assertEqual(set(rcs["ul_nx"]["tags"]), {"sway_right", "yaw_left", "roll_right"})
        self.assertEqual(set(rcs["ur_py"]["tags"]), {"heave_down", "pitch_up", "roll_right"})
        self.assertEqual(set(rcs["lr_ny"]["tags"]), {"heave_up", "pitch_down", "roll_left"})
        np.testing.assert_allclose(rcs["ur_px"]["position"], mirrored(rcs["ul_nx"]["position"], "x"), atol=SYM_TOL)
        np.testing.assert_allclose(rcs["ur_py"]["position"], mirrored(rcs["lr_ny"]["position"], "y"), atol=SYM_TOL)
        # Each RCS cone sits on its pod's surface.
        pods = {p["name"]: np.array(p["center"]) for p in self.hp["pods"]}
        for r in rcs.values():
            offset = np.array(r["position"]) - pods[r["pod"]]
            self.assertAlmostEqual(float(np.hypot(offset[0], offset[1])), 0.62, delta=0.01)

    def test_collision_primitives(self) -> None:
        shapes = {c["name"]: c for c in self.hp["collision"]}
        self.assertEqual(
            set(shapes), {"fuselage", "pod_ur", "pod_lr", "pod_ul", "pod_ll", "strut_ur", "strut_lr", "strut_ul", "strut_ll"}
        )
        self.assertEqual(shapes["fuselage"]["type"], "box")
        self.assertEqual(shapes["fuselage"]["size"], [1.6, 1.4, 7.5])
        pods = {p["name"]: p["center"] for p in self.hp["pods"]}
        for name in ("ur", "lr", "ul", "ll"):
            cap = shapes[f"pod_{name}"]
            self.assertEqual((cap["type"], cap["radius"], cap["height"], cap["axis"]), ("capsule", 0.55, 3.2, "z"))
            self.assertEqual(cap["position"], pods[name])
        for c in shapes.values():
            basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
            np.testing.assert_allclose(basis.T @ basis, np.eye(3), atol=1e-4)
            self.assertAlmostEqual(float(np.linalg.det(basis)), 1.0, places=3)
        strut = shapes["strut_ur"]
        self.assertEqual(strut["type"], "box")
        np.testing.assert_allclose(strut["basis"]["x"][:2], [0.70711, 0.70711], atol=1e-4)

    def test_hardpoints_agree_with_the_splats(self) -> None:
        xyz = self.godot_xyz

        def nearest(point: list[float]) -> float:
            return float(np.linalg.norm(xyz - np.array(point), axis=1).min())

        for m in self.hp["muzzles"]:
            self.assertLess(nearest(m["position"]), 0.08)  # the bore disc sits 6 cm behind the lip
        # Splats are written in manifest ``counts`` order, so each part is a contiguous slice.
        offsets, start = {}, 0
        for name, n in self.manifest["counts"].items():
            offsets[name] = (start, start + n)
            start += n
        for p in self.hp["pods"]:
            a, b = offsets[f"pod_{p['name']}"]
            own = np.linalg.norm(xyz[a:b] - np.array(p["center"]), axis=1)
            self.assertAlmostEqual(float(own.min()), 0.55, delta=0.03)  # pod body radius
            self.assertLess(nearest(p["center"]), 0.55)  # the strut tip reaches inside the pod
            # The bell lips are sampled rings in the exit planes around the exhaust anchors.
            for key, r_lo, r_hi in (("main", 0.4, 0.6), ("retro", 0.15, 0.35)):
                d = xyz - np.array(p[key]["position"])
                lip = (np.abs(d[:, 2]) < 0.05) & (r_lo < np.hypot(d[:, 0], d[:, 1])) & (np.hypot(d[:, 0], d[:, 1]) < r_hi)
                self.assertGreater(int(lip.sum()), 15, (p["name"], key))

    # --- meshes -----------------------------------------------------------------------------
    def test_fallback_obj_is_valid_and_matches_the_splat_bounds(self) -> None:
        obj = self.obj
        self.assertGreater(len(obj.vertices), 0)
        self.assertGreater(len(obj.faces), 0)
        self.assertGreaterEqual(int(obj.faces.min()), 0)
        self.assertLess(int(obj.faces.max()), len(obj.vertices))
        self.assertEqual(obj.mtllib, "starfury_aurora.mtl")
        mtl = (self.dir_a / "starfury_aurora.mtl").read_text(encoding="ascii")
        for name in obj.materials:
            self.assertIn(f"newmtl {name}", mtl)
        self.assertIn("ef_stripe", obj.materials)
        np.testing.assert_allclose(obj.vertices.min(axis=0), self.manifest["aabb_min"], atol=0.05)
        np.testing.assert_allclose(obj.vertices.max(axis=0), self.manifest["aabb_max"], atol=0.05)
        # Mirror symmetric mesh in x.
        self.assertAlmostEqual(float(obj.vertices[:, 0].min()), -float(obj.vertices[:, 0].max()), places=5)

    def test_cockpit_interior_obj_surrounds_the_camera(self) -> None:
        obj = read_obj(self.dir_a / ship.COCKPIT_NAME)
        self.assertGreater(len(obj.faces), 50)
        self.assertLess(int(obj.faces.max()), len(obj.vertices))
        cam = np.array(self.hp["cockpit_camera"]["position"])
        lo, hi = obj.vertices.min(axis=0), obj.vertices.max(axis=0)
        self.assertTrue(np.all(lo < cam + 0.3) and np.all(hi > cam - 0.3))
        self.assertLess(float(np.linalg.norm(obj.vertices - cam, axis=1).min()), 0.6)
        self.assertEqual(obj.mtllib, "cockpit_interior.mtl")

    # --- determinism ------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        for path in self.dir_a.iterdir():
            self.assertEqual(sha256(path), sha256(self.dir_b / path.name), path.name)

    def test_a_different_seed_changes_the_splats_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = ship.build(BuildContext(Path(tmp), seed=7))
            self.assertNotEqual(sha256(Path(tmp) / ship.PLY_NAME), sha256(self.dir_a / ship.PLY_NAME))
            self.assertAlmostEqual(other.splat_count, self.out_a.splat_count, delta=0.01 * self.out_a.splat_count)
            # The origin is the sampled centroid, so it moves by millimetres with the seed;
            # the design (every x/y, every z difference) does not.
            hp = json.loads((Path(tmp) / ship.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            for mine, theirs in zip(self.hp["pods"], hp["pods"], strict=True):
                self.assertEqual(mine["center"][:2], theirs["center"][:2])
                self.assertAlmostEqual(mine["center"][2], theirs["center"][2], delta=0.02)
                self.assertAlmostEqual(
                    mine["main"]["position"][2] - mine["retro"]["position"][2],
                    theirs["main"]["position"][2] - theirs["retro"]["position"][2],
                    places=4,
                )
            for mine, theirs in zip(self.hp["muzzles"], hp["muzzles"], strict=True):
                self.assertEqual(mine["position"][0], theirs["position"][0])
                self.assertAlmostEqual(mine["position"][1], theirs["position"][1], delta=0.005)  # y-balance shift
            self.assertAlmostEqual(
                hp["muzzles"][0]["position"][2] - hp["pods"][0]["main"]["position"][2],
                self.hp["muzzles"][0]["position"][2] - self.hp["pods"][0]["main"]["position"][2],
                places=4,
            )


class StarfuryOptionTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def test_spacing_option_scales_the_count_and_is_recorded(self) -> None:
        coarse = ship.build(BuildContext(self.dir / "c", seed=42, options={"spacing": 0.1}))
        self.assertEqual(coarse.manifest["lods"][0]["spacing_m"], 0.1)
        fine = ship.build(BuildContext(self.dir / "f", seed=42, options={"spacing": 0.07}))
        ratio = fine.splat_count / coarse.splat_count
        self.assertAlmostEqual(ratio, (0.1 / 0.07) ** 2, delta=0.1)
        self.assertEqual(coarse.warnings, ())  # the budget only applies at the default spacing
        splats = read_ply(self.dir / "c" / ship.PLY_NAME).to_splats()
        np.testing.assert_allclose(splats.scale[:, 0], 0.14, rtol=1e-4)

    def test_overlap_and_thickness_options(self) -> None:
        out = ship.build(BuildContext(self.dir / "o", seed=1, options={"spacing": 0.1, "overlap": 1.0, "thickness": 0.1}))
        splats = read_ply(self.dir / "o" / ship.PLY_NAME).to_splats()
        np.testing.assert_allclose(splats.scale[:, 0], 0.1, rtol=1e-4)
        np.testing.assert_allclose(splats.scale[:, 2], 0.01, rtol=1e-3)
        self.assertEqual(out.manifest["sampling"], {"spacing_m": 0.1, "overlap": 1.0, "thickness": 0.1})

    def test_invalid_options_are_rejected(self) -> None:
        for bad in ({"spacing": 0.0}, {"spacing": -1.0}, {"overlap": 0.0}, {"thickness": -0.1}):
            with self.subTest(bad), self.assertRaises(ValueError):
                ship.build(BuildContext(self.dir / "bad", seed=1, options=bad))


if __name__ == "__main__":
    unittest.main()
