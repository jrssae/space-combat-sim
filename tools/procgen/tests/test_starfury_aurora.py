"""``starfury_aurora``: files, counts, frames, hardpoints schema and symmetry, the cockpit view, OBJ validity, determinism."""

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
from tools.procgen.core.sampling import DEFAULT_OVERLAP, DEFAULT_THICKNESS
from tools.procgen.core.obj import read_obj
from tools.procgen.core.ply import PROPERTY_NAMES, read_ply

PILOT_TERMS = {
    "sway_left", "sway_right", "heave_up", "heave_down", "pitch_up", "pitch_down",
    "yaw_left", "yaw_right", "roll_left", "roll_right",
}  # fmt: skip
SYM_TOL = 1e-6
POD_NAMES = ("ur", "lr", "ul", "ll")
SPEC = ship.DEFAULT_SPEC
# Cockpit view (camera FOV 75 deg vertical, 16:9): the box every opaque splat, halo included,
# and the cockpit mesh stay out of. It is the narrow bottom of the trapezoid front pane: the
# struts close in towards the sill (bottom corners +-26 deg, top corners +-42 deg), the bar
# across the top is at about 33 deg and the sill edge at -20 deg.
CLEAR_AZIMUTH_DEG = 20.0
CLEAR_ELEVATION_DEG = (-12.0, 28.0)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mirrored(v: list[float], axes: str) -> list[float]:
    out = list(v)
    for axis in axes:
        k = "xyz".index(axis)
        out[k] = -out[k]
    return out


def slices(manifest: dict) -> dict[str, tuple[int, int]]:
    """Splats are written in manifest ``counts`` order, so each part is a contiguous slice."""
    out, start = {}, 0
    for name, n in manifest["counts"].items():
        out[name] = (start, start + n)
        start += n
    return out


def eye_angles(
    points: np.ndarray, eye: np.ndarray
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Distance ahead (-Z), azimuth and elevation in degrees of points seen from ``eye`` looking -Z."""
    rel = np.asarray(points, dtype=float) - eye
    ahead = -rel[:, 2]
    return (
        ahead,
        np.degrees(np.arctan2(rel[:, 0], ahead)),
        np.degrees(np.arctan2(rel[:, 1], ahead)),
    )


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
        cls.godot_xyz = frames.flip_xy(
            cls.splats.xyz
        )  # centred Godot frame (the hardpoints frame)
        cls.hp = json.loads(
            (cls.dir_a / ship.HARDPOINTS_NAME).read_text(encoding="utf-8")
        )
        cls.obj = read_obj(cls.dir_a / ship.OBJ_NAME)
        cls.slices = slices(cls.manifest)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def part(self, name: str) -> np.ndarray:
        a, b = self.slices[name]
        return self.godot_xyz[a:b]

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
            {
                "fallback_mesh": "starfury_aurora.obj",
                "cockpit_mesh": "cockpit_interior.obj",
                "hardpoints": "hardpoints.json",
            },
        )

    def test_manifest_lods_zero_and_budget(self) -> None:
        lod0 = self.manifest["lods"][0]
        self.assertEqual(len(self.manifest["lods"]), 1)
        self.assertEqual((lod0["level"], lod0["file"]), (0, "starfury_aurora.ply"))
        self.assertEqual(lod0["spacing_m"], ship.DEFAULT_SPACING_M)
        self.assertTrue(
            ship.SPLAT_BUDGET[0] <= lod0["splats"] <= ship.SPLAT_BUDGET[1],
            lod0["splats"],
        )
        self.assertEqual(lod0["splats"], self.ply.count)
        self.assertEqual(self.out_a.splat_count, self.ply.count)
        self.assertEqual(sum(self.manifest["counts"].values()), self.ply.count)
        self.assertEqual(
            (self.manifest["asset_id"], self.manifest["frame"], self.manifest["seed"]),
            ("starfury_aurora", "godot", 42),
        )
        expected = ["fuselage", "cockpit", "gun_mount"] + [
            f"{p}_{n}" for p in ("pod", "strut", "claw") for n in POD_NAMES
        ]
        self.assertEqual(list(self.manifest["counts"]), expected)
        for prefix in ("pod", "strut", "claw"):
            self.assertEqual(
                len({self.manifest["counts"][f"{prefix}_{n}"] for n in POD_NAMES}),
                1,
                prefix,
            )
        sampling = self.manifest["sampling"]
        self.assertEqual(sampling["spacing_m"], ship.DEFAULT_SPACING_M)
        self.assertAlmostEqual(
            sampling["cockpit_spacing_m"],
            ship.COCKPIT_SPACING_FACTOR * ship.DEFAULT_SPACING_M,
        )

    # --- PLY content ------------------------------------------------------------------------
    def test_ply_parses_with_the_3dgs_layout_and_finite_values(self) -> None:
        self.assertEqual(self.ply.names, list(PROPERTY_NAMES))
        for name in PROPERTY_NAMES:
            self.assertTrue(np.all(np.isfinite(self.ply.column(name))), name)

    def test_written_positions_are_centred_within_1e_3(self) -> None:
        self.assertLess(float(np.abs(self.splats.xyz.mean(axis=0)).max()), 1e-3)
        self.assertLess(
            float(np.abs(self.splats.xyz.mean(axis=0)).max()), 1e-4
        )  # exact by construction
        self.assertEqual(self.manifest["centroid_offset"][:2], [0.0, 0.0])

    def test_manifest_aabb_matches_the_file_after_the_flip(self) -> None:
        lo, hi = frames.aabb_godot_to_3dgs(
            self.manifest["aabb_min"], self.manifest["aabb_max"]
        )
        np.testing.assert_allclose(self.splats.xyz.min(axis=0), lo, atol=2e-3)
        np.testing.assert_allclose(self.splats.xyz.max(axis=0), hi, atol=2e-3)

    def test_splat_set_is_exactly_mirror_symmetric_in_x_and_the_cross_in_y(
        self,
    ) -> None:
        view = "f4,f4,f4"

        def symmetric(xyz: np.ndarray, axis: int) -> bool:
            xyz = xyz.astype(np.float32)
            flipped = xyz.copy()
            flipped[:, axis] *= -1
            return bool(
                np.array_equal(
                    np.sort(xyz.view(view), axis=0), np.sort(flipped.view(view), axis=0)
                )
            )

        self.assertTrue(symmetric(self.godot_xyz, 0))
        start = self.slices["pod_ur"][0]
        self.assertTrue(symmetric(self.godot_xyz[start:], 1))  # pods, struts and claws

    def test_splats_are_flat_oriented_discs_at_their_part_spacing(self) -> None:
        s = self.splats
        a, b = self.slices["cockpit"]
        spacing = np.full(len(s.scale), ship.DEFAULT_SPACING_M)
        spacing[a:b] = self.manifest["sampling"]["cockpit_spacing_m"]
        np.testing.assert_allclose(s.scale[:, 0], DEFAULT_OVERLAP * spacing, rtol=1e-4)
        np.testing.assert_allclose(s.scale[:, 1], DEFAULT_OVERLAP * spacing, rtol=1e-4)
        np.testing.assert_allclose(s.scale[:, 2], DEFAULT_THICKNESS * spacing, rtol=1e-3)
        rot = frames.quat_to_matrix(s.rot)
        normals = s.normals / np.linalg.norm(s.normals, axis=1, keepdims=True)
        agreement = np.abs(np.einsum("ij,ij->i", rot[:, :, 2], normals))
        self.assertGreater(float(agreement.min()), 0.999)
        np.testing.assert_allclose(np.linalg.norm(s.rot, axis=1), 1.0, atol=1e-5)

    def test_opacity_is_opaque_except_for_the_green_canopy_glass(self) -> None:
        alpha = self.splats.alpha
        glass = alpha < 0.5
        self.assertTrue(np.all(alpha[~glass] > 0.979))
        self.assertTrue(np.all(alpha[glass] < 0.07))  # 1 - 0.7^(1 / (2 pi k^2)) is 0.056 at k = 1
        self.assertTrue(0.002 < glass.mean() < 0.03, glass.mean())
        rgb = self.splats.rgb[glass]
        self.assertTrue(
            np.all((rgb[:, 1] > rgb[:, 0]) & (rgb[:, 1] > rgb[:, 2]))
        )  # green tint
        # The panes are the window at the nose: the fuselage's slice, ahead of its rear edge.
        a, b = self.slices["fuselage"]
        self.assertFalse(glass[:a].any() or glass[b:].any())
        window_end = (
            SPEC.fuselage.stations[SPEC.fuselage.window_end].z
            - self.manifest["centroid_offset"][2]
        )
        self.assertTrue(np.all(self.godot_xyz[glass, 2] < window_end))
        self.assertLess(
            float(np.abs(self.godot_xyz[glass, 0]).max()),
            SPEC.fuselage.stations[1].shoulder_half_width,
        )

    def test_colours_show_the_palette_and_the_baked_light(self) -> None:
        rgb, xyz = self.splats.rgb, self.godot_xyz
        self.assertTrue(np.all(rgb >= 0.0))
        self.assertLess(float(rgb.max()), 1.0)
        normals = frames.flip_xy(self.splats.normals)
        up, down = normals[:, 1] > 0.8, normals[:, 1] < -0.8
        self.assertGreater(
            float(rgb[up].mean()), 1.8 * float(rgb[down].mean())
        )  # key light from above
        yellow = (
            (rgb[:, 2] < 0.2 * rgb[:, 0])
            & (rgb[:, 1] > 0.4 * rgb[:, 0])
            & (rgb[:, 0] > 0.1)
        )
        self.assertTrue(0.01 < yellow.mean() < 0.09, yellow.mean())  # hazard stripes
        start, end = self.slices["strut_ur"][0], self.slices["strut_ll"][1]
        self.assertFalse(
            yellow[:start].any() or yellow[end:].any()
        )  # on the struts only
        span = np.abs(xyz[yellow, 0])
        self.assertTrue(
            np.all((span > 1.5) & (span < SPEC.pod_center[0] - SPEC.pod.radius))
        )  # between hull and pods
        chroma = (rgb.max(axis=1) - rgb.min(axis=1)) / np.maximum(rgb.max(axis=1), 1e-9)
        grey = (chroma < 0.15) & (rgb.max(axis=1) > 0.12)
        self.assertGreater(
            float(grey.mean()), 0.3
        )  # most of the lit hull is neutral grey

    # --- hardpoints -------------------------------------------------------------------------
    def test_hardpoints_schema(self) -> None:
        hp = self.hp
        for key in (
            "frame", "units", "length_m", "center_of_mass", "cockpit_camera", "chase_anchor",
            "muzzles", "pods", "rcs", "collision", "mass_kg",
        ):  # fmt: skip
            self.assertIn(key, hp)
        self.assertEqual((hp["frame"], hp["units"]), ("godot", "m"))
        self.assertTrue(
            9.0 < hp["length_m"] < 11.0
        )  # design reference: 9-10 m with the claws
        self.assertTrue(
            13.0 < hp["span_m"] < 17.0
        )  # about 13 m across the pods, more with the claws
        self.assertTrue(6.5 < hp["height_m"] < 9.0)  # about 8 m
        self.assertGreater(
            hp["span_m"], 1.6 * hp["height_m"]
        )  # the X is wider than tall
        self.assertEqual(hp["chase_anchor"]["position"], list(ship.CHASE_ANCHOR))
        self.assertEqual(hp["cockpit_camera"]["forward"], [0.0, 0.0, -1.0])
        self.assertEqual(hp["mass_kg"], 48000.0)

    def test_four_pods_two_per_side_symmetric_about_x_and_y(self) -> None:
        pods = {p["name"]: p for p in self.hp["pods"]}
        self.assertEqual(list(pods), list(POD_NAMES))
        self.assertEqual(
            [p["side"] for p in self.hp["pods"]], ["right", "right", "left", "left"]
        )
        ur = pods["ur"]
        self.assertEqual(ur["center"][:2], list(SPEC.pod_center[:2]))  # x/y exact
        self.assertGreater(
            ur["center"][0], 2.0 * ur["center"][1]
        )  # struts about 20 deg off horizontal
        for name, axes in (("lr", "y"), ("ul", "x"), ("ll", "xy")):
            other = pods[name]
            np.testing.assert_allclose(
                other["center"], mirrored(ur["center"], axes), atol=SYM_TOL
            )
            for nozzle in ("main", "retro"):
                np.testing.assert_allclose(
                    other[nozzle]["position"],
                    mirrored(ur[nozzle]["position"], axes),
                    atol=SYM_TOL,
                )
                np.testing.assert_allclose(
                    other[nozzle]["exhaust"], ur[nozzle]["exhaust"], atol=SYM_TOL
                )
                self.assertEqual(other[nozzle]["radius"], ur[nozzle]["radius"])
        for p in self.hp["pods"]:
            self.assertEqual(p["main"]["exhaust"], [0.0, 0.0, 1.0])
            self.assertEqual(p["retro"]["exhaust"], [0.0, 0.0, -1.0])
            self.assertGreater(p["main"]["position"][2], p["center"][2])
            self.assertLess(p["retro"]["position"][2], p["center"][2])
            self.assertEqual(
                p["main"]["position"][:2], p["center"][:2]
            )  # on the nozzle axis
            self.assertEqual(p["retro"]["position"][:2], p["center"][:2])
            self.assertEqual(p["main"]["radius"], SPEC.pod.main.exit_r)
            self.assertEqual(p["retro"]["radius"], SPEC.pod.retro.exit_r)

    def test_center_of_mass_is_on_the_thrust_axis(self) -> None:
        com = self.hp["center_of_mass"]
        self.assertEqual(com[:2], [0.0, 0.0])
        self.assertLess(abs(com[2]), 1.0)
        inertia = self.hp["inertia_estimate_kg_m2"]
        self.assertTrue(all(1e5 < i < 2e6 for i in inertia), inertia)
        self.assertLess(
            inertia[0], inertia[1]
        )  # pods far out in x, close in y: pitch is the easy axis

    def test_muzzles_and_camera(self) -> None:
        muzzles = self.hp["muzzles"]
        self.assertEqual([m["name"] for m in muzzles], ["left", "right"])
        np.testing.assert_allclose(
            muzzles[0]["position"], mirrored(muzzles[1]["position"], "x"), atol=SYM_TOL
        )
        self.assertAlmostEqual(
            muzzles[1]["position"][0], SPEC.gun_mount.barrel_x, delta=SYM_TOL
        )
        cam = np.array(self.hp["cockpit_camera"]["position"])
        nose = float(self.part("fuselage")[:, 2].min())
        for m in muzzles:
            self.assertEqual(m["direction"], [0.0, 0.0, -1.0])
            self.assertLess(m["position"][1], cam[1] - 1.0)  # under the nose
            self.assertLess(m["position"][2], nose)  # ahead of it
        self.assertEqual(cam[0], 0.0)
        self.assertLess(cam[2], self.hp["center_of_mass"][2] - 2.0)  # well forward
        # Inside the cockpit, behind the front pane and clear of every splat.
        glass = self.splats.alpha < 0.5
        self.assertLess(float(self.godot_xyz[glass, 2].min()), cam[2] - 0.5)
        self.assertGreater(
            float(np.linalg.norm(self.godot_xyz - cam, axis=1).min()), 0.2
        )

    def test_cockpit_view_is_clear_but_for_the_window_frame(self) -> None:
        """No opaque splat, soft edge (2.5 sigma) included, reaches into the central view; the
        panes cover it; the guns are below the sill line, so the chin hides them."""
        cam = np.array(self.hp["cockpit_camera"]["position"])
        ahead, az, el = eye_angles(self.godot_xyz, cam)
        opaque = (self.splats.alpha > 0.5) & (ahead > 0.0)
        halo = np.degrees(
            2.5 * self.splats.scale[:, 0] / np.linalg.norm(self.godot_xyz - cam, axis=1)
        )
        lo, hi = CLEAR_ELEVATION_DEG
        intrudes = (
            opaque
            & (np.abs(az) - halo < CLEAR_AZIMUTH_DEG)
            & (el + halo > lo)
            & (el - halo < hi)
        )
        self.assertEqual(int(intrudes.sum()), 0)
        glass = (self.splats.alpha < 0.5) & (ahead > 0.0)
        self.assertGreater(
            int(
                (glass & (np.abs(az) < CLEAR_AZIMUTH_DEG) & (el > lo) & (el < hi)).sum()
            ),
            200,
        )
        # The panes reach past the clear box on every side (they are what the eye looks through).
        self.assertLess(float(az[glass].min()), -CLEAR_AZIMUTH_DEG)
        self.assertGreater(float(az[glass].max()), CLEAR_AZIMUTH_DEG)
        self.assertLess(float(el[glass].min()), lo)
        self.assertGreater(float(el[glass].max()), hi)
        # The opaque splats that frame the view above the sill are the window's own: the fuselage
        # and cockpit slices (the guns are further down, behind the chin).
        near = opaque & (np.abs(az) < 53.6) & (el > lo) & (el < 37.5) & (ahead < 2.0)
        a, b = self.slices["fuselage"][0], self.slices["cockpit"][1]
        self.assertFalse(near[:a].any() or near[b:].any())
        for m in self.hp["muzzles"]:
            _, _, muzzle_el = eye_angles(
                np.array([m["position"]]) + [0.0, SPEC.gun_mount.barrel.radius, 0.0],
                cam,
            )
            self.assertLess(float(muzzle_el[0]), lo)

    def test_rcs_nozzles_sit_on_the_claws_with_pilot_term_tags(self) -> None:
        rcs = {r["name"]: r for r in self.hp["rcs"]}
        self.assertEqual(len(rcs), 16)
        self.assertEqual({n.split("_")[0] for n in rcs}, set(POD_NAMES))
        for name, r in rcs.items():
            self.assertTrue(set(r["tags"]) <= PILOT_TERMS, name)
            self.assertTrue(
                any(t.startswith(("sway", "heave")) for t in r["tags"]), name
            )
            self.assertAlmostEqual(float(np.linalg.norm(r["exhaust"])), 1.0, places=6)
            self.assertEqual(
                sorted(abs(c) for c in r["exhaust"]), [0.0, 0.0, 1.0], name
            )  # axis-aligned
            self.assertIn(r["pod"], POD_NAMES)
            self.assertEqual(
                name,
                f"{r['pod']}_{'p' if max(r['exhaust']) > 0 else 'n'}{'xy'[int(np.argmax(np.abs(r['exhaust'])))]}",
            )
        self.assertEqual(
            set(rcs["ur_px"]["tags"]), {"sway_left", "yaw_right", "roll_left"}
        )  # milestone example
        self.assertEqual(
            set(rcs["ul_nx"]["tags"]), {"sway_right", "yaw_left", "roll_right"}
        )
        self.assertEqual(
            set(rcs["ur_py"]["tags"]), {"heave_down", "pitch_up", "roll_right"}
        )
        self.assertEqual(
            set(rcs["lr_ny"]["tags"]), {"heave_up", "pitch_down", "roll_left"}
        )
        np.testing.assert_allclose(
            rcs["ur_px"]["position"],
            mirrored(rcs["ul_nx"]["position"], "x"),
            atol=SYM_TOL,
        )
        np.testing.assert_allclose(
            rcs["ur_py"]["position"],
            mirrored(rcs["lr_ny"]["position"], "y"),
            atol=SYM_TOL,
        )
        np.testing.assert_allclose(
            rcs["ur_px"]["position"],
            mirrored(rcs["ll_nx"]["position"], "xy"),
            atol=SYM_TOL,
        )
        # Each cone sits on its pod's claw: behind the pod centre, outside the pod, on claw splats.
        pods = {p["name"]: np.array(p["center"]) for p in self.hp["pods"]}
        for name, r in rcs.items():
            pos = np.array(r["position"])
            offset = pos - pods[r["pod"]]
            self.assertGreater(offset[2], 1.0, name)
            self.assertGreater(
                float(np.hypot(offset[0], offset[1])), SPEC.pod.radius, name
            )
            claw = self.part(f"claw_{r['pod']}")
            self.assertLess(float(np.linalg.norm(claw - pos, axis=1).min()), 0.06, name)

    def test_collision_primitives(self) -> None:
        shapes = {c["name"]: c for c in self.hp["collision"]}
        names = ["fuselage", "gun_mount"] + [
            f"{p}_{n}" for p in ("pod", "strut", "claw") for n in POD_NAMES
        ]
        self.assertEqual([c["name"] for c in self.hp["collision"]], names)
        pods = {p["name"]: p["center"] for p in self.hp["pods"]}
        for name in POD_NAMES:
            cap = shapes[f"pod_{name}"]
            self.assertEqual(
                (cap["type"], cap["radius"], cap["axis"]),
                ("capsule", SPEC.pod.radius, "z"),
            )
            self.assertAlmostEqual(cap["height"], SPEC.pod.capsule_height, places=5)
            self.assertGreater(
                cap["height"], SPEC.pod.length
            )  # the caps wrap the flat end faces
            self.assertEqual(cap["position"], pods[name])
        for c in shapes.values():
            basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
            np.testing.assert_allclose(basis.T @ basis, np.eye(3), atol=1e-4)
            self.assertAlmostEqual(float(np.linalg.det(basis)), 1.0, places=3)
            if c["type"] == "box":
                self.assertTrue(all(v > 0.0 for v in c["size"]), c["name"])
        for name in (
            "strut_ur",
            "claw_ur",
        ):  # rotated boxes along the swept strut / the splayed vanes
            x_col = shapes[name]["basis"]["x"]
            self.assertTrue(all(abs(v) > 0.2 for v in x_col), (name, x_col))
        # Every primitive wraps its part: the splats of that part lie inside (5 cm slack). The claw
        # box wraps the outboard prong pair, about half the claw; the inboard vane and the thruster
        # blocks hug the pod.
        for name, minimum in (
            ("fuselage", 0.999),
            ("gun_mount", 0.999),
            ("pod_ur", 0.97),
            ("strut_ur", 0.99),
            ("claw_ur", 0.45),
        ):
            c = shapes[name]
            basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
            local = (self.part(name) - np.array(c["position"])) @ basis
            if c["type"] == "box":
                inside = np.all(
                    np.abs(local) <= 0.5 * np.array(c["size"]) + 0.05, axis=1
                )
            else:
                half = 0.5 * c["height"] - c["radius"]
                along = np.clip(local[:, 2], -half, half)
                inside = (
                    np.linalg.norm(
                        local
                        - np.column_stack(
                            [np.zeros_like(along), np.zeros_like(along), along]
                        ),
                        axis=1,
                    )
                    <= c["radius"] + 0.05
                )
            self.assertGreaterEqual(float(inside.mean()), minimum, name)

    def test_hardpoints_agree_with_the_splats(self) -> None:
        xyz = self.godot_xyz

        def nearest(point: list[float]) -> float:
            return float(np.linalg.norm(xyz - np.array(point), axis=1).min())

        for m in self.hp["muzzles"]:
            self.assertLess(
                nearest(m["position"]), 0.08
            )  # the bore disc sits 6 cm behind the lip
        for p in self.hp["pods"]:
            own = self.part(f"pod_{p['name']}")
            # Nothing is buried in the pod (strut tips, claw roots and bell walls inside are dropped).
            self.assertGreater(nearest(p["center"]), SPEC.pod.rear_radius - 0.01)
            # The bell lips are sampled rings in the exit planes, centred on the exhaust anchors.
            for key, nozzle in (("main", SPEC.pod.main), ("retro", SPEC.pod.retro)):
                d = own - np.array(p[key]["position"])
                r = np.hypot(d[:, 0], d[:, 1])
                lip = (
                    (np.abs(d[:, 2]) < 0.03)
                    & (r > nozzle.exit_r - 0.01)
                    & (r < nozzle.exit_r + nozzle.wall + 0.01)
                )
                self.assertGreater(int(lip.sum()), 50, (p["name"], key))
                np.testing.assert_allclose(
                    d[lip, :2].mean(axis=0), [0.0, 0.0], atol=0.03
                )
            # The main exit is the rearmost point of the pod: the visible end of the nozzle.
            self.assertAlmostEqual(
                float(own[:, 2].max()), p["main"]["position"][2], delta=0.002
            )
            self.assertAlmostEqual(
                float(own[:, 2].min()), p["retro"]["position"][2], delta=0.002
            )

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
        for name in ("ef_hazard", "ef_canopy_glass", "ef_canopy_frame", "ef_nozzle"):
            self.assertIn(name, obj.materials)
        np.testing.assert_allclose(
            obj.vertices.min(axis=0), self.manifest["aabb_min"], atol=0.05
        )
        np.testing.assert_allclose(
            obj.vertices.max(axis=0), self.manifest["aabb_max"], atol=0.05
        )
        # Mirror symmetric mesh in x.
        self.assertAlmostEqual(
            float(obj.vertices[:, 0].min()), -float(obj.vertices[:, 0].max()), places=5
        )

    def test_cockpit_interior_obj_frames_the_view_without_blocking_it(self) -> None:
        obj = read_obj(self.dir_a / ship.COCKPIT_NAME)
        self.assertGreater(len(obj.faces), 50)
        self.assertLess(int(obj.faces.max()), len(obj.vertices))
        self.assertEqual(obj.mtllib, "cockpit_interior.mtl")
        cam = np.array(self.hp["cockpit_camera"]["position"])
        lo, hi = obj.vertices.min(axis=0), obj.vertices.max(axis=0)
        self.assertTrue(
            np.all(lo[:2] < cam[:2]) and np.all(hi[:2] > cam[:2])
        )  # around the pilot
        self.assertLess(float(lo[2]), cam[2])  # reaches forward to the front pane
        self.assertLess(float(np.linalg.norm(obj.vertices - cam, axis=1).min()), 1.2)
        ahead, az, el = eye_angles(obj.vertices, cam)
        lo_el, hi_el = CLEAR_ELEVATION_DEG
        in_view = (
            (ahead > 0.0)
            & (np.abs(az) < CLEAR_AZIMUTH_DEG)
            & (el > lo_el)
            & (el < hi_el)
        )
        self.assertEqual(int(in_view.sum()), 0)
        off_axis = np.degrees(
            np.arctan2(np.hypot(*(obj.vertices - cam)[:, :2].T), ahead)
        )
        self.assertGreater(float(off_axis[ahead > 0.0].min()), 15.0)

    # --- determinism ------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        for path in self.dir_a.iterdir():
            self.assertEqual(sha256(path), sha256(self.dir_b / path.name), path.name)

    def test_a_different_seed_changes_the_splats_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = ship.build(BuildContext(Path(tmp), seed=7))
            self.assertNotEqual(
                sha256(Path(tmp) / ship.PLY_NAME), sha256(self.dir_a / ship.PLY_NAME)
            )
            self.assertAlmostEqual(
                other.splat_count,
                self.out_a.splat_count,
                delta=0.01 * self.out_a.splat_count,
            )
            # The origin is the sampled centroid, so it moves by millimetres with the seed;
            # the design (every pod x/y, every z difference) does not.
            hp = json.loads(
                (Path(tmp) / ship.HARDPOINTS_NAME).read_text(encoding="utf-8")
            )
            for mine, theirs in zip(self.hp["pods"], hp["pods"], strict=True):
                self.assertEqual(mine["center"][:2], theirs["center"][:2])
                self.assertAlmostEqual(
                    mine["center"][2], theirs["center"][2], delta=0.02
                )
                self.assertAlmostEqual(
                    mine["main"]["position"][2] - mine["retro"]["position"][2],
                    theirs["main"]["position"][2] - theirs["retro"]["position"][2],
                    places=4,
                )
            for mine, theirs in zip(self.hp["muzzles"], hp["muzzles"], strict=True):
                self.assertEqual(mine["position"][0], theirs["position"][0])
                self.assertAlmostEqual(
                    mine["position"][1], theirs["position"][1], delta=0.005
                )  # y-balance shift
            self.assertAlmostEqual(
                hp["muzzles"][0]["position"][2] - hp["pods"][0]["main"]["position"][2],
                self.hp["muzzles"][0]["position"][2]
                - self.hp["pods"][0]["main"]["position"][2],
                places=4,
            )


class StarfuryOptionTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def test_spacing_option_scales_the_count_and_is_recorded(self) -> None:
        coarse = ship.build(
            BuildContext(self.dir / "c", seed=42, options={"spacing": 0.1})
        )
        self.assertEqual(coarse.manifest["lods"][0]["spacing_m"], 0.1)
        self.assertAlmostEqual(
            coarse.manifest["sampling"]["cockpit_spacing_m"],
            ship.COCKPIT_SPACING_FACTOR * 0.1,
        )
        fine = ship.build(
            BuildContext(self.dir / "f", seed=42, options={"spacing": 0.07})
        )
        ratio = fine.splat_count / coarse.splat_count
        self.assertAlmostEqual(ratio, (0.1 / 0.07) ** 2, delta=0.1)
        self.assertEqual(
            coarse.warnings, ()
        )  # the budget only applies at the default spacing
        splats = read_ply(self.dir / "c" / ship.PLY_NAME).to_splats()
        a, b = slices(coarse.manifest)["cockpit"]
        np.testing.assert_allclose(
            np.delete(splats.scale[:, 0], np.s_[a:b]), DEFAULT_OVERLAP * 0.1, rtol=1e-4
        )
        np.testing.assert_allclose(
            splats.scale[a:b, 0], DEFAULT_OVERLAP * ship.COCKPIT_SPACING_FACTOR * 0.1, rtol=1e-4
        )

    def test_overlap_thickness_and_cockpit_spacing_options(self) -> None:
        options = {
            "spacing": 0.1,
            "cockpit_spacing": 0.08,
            "overlap": 1.0,
            "thickness": 0.1,
        }
        out = ship.build(BuildContext(self.dir / "o", seed=1, options=options))
        splats = read_ply(self.dir / "o" / ship.PLY_NAME).to_splats()
        a, b = slices(out.manifest)["cockpit"]
        np.testing.assert_allclose(
            np.delete(splats.scale[:, 0], np.s_[a:b]), 0.1, rtol=1e-4
        )
        np.testing.assert_allclose(splats.scale[a:b, 0], 0.08, rtol=1e-4)
        np.testing.assert_allclose(
            np.delete(splats.scale[:, 2], np.s_[a:b]), 0.01, rtol=1e-3
        )
        self.assertEqual(
            out.manifest["sampling"],
            {
                "spacing_m": 0.1,
                "cockpit_spacing_m": 0.08,
                "overlap": 1.0,
                "thickness": 0.1,
            },
        )

    def test_invalid_options_are_rejected(self) -> None:
        for bad in (
            {"spacing": 0.0},
            {"spacing": -1.0},
            {"overlap": 0.0},
            {"thickness": -0.1},
            {"cockpit_spacing": 0.0},
        ):
            with self.subTest(bad), self.assertRaises(ValueError):
                ship.build(BuildContext(self.dir / "bad", seed=1, options=bad))


if __name__ == "__main__":
    unittest.main()
