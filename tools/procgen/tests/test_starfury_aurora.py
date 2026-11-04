"""``starfury_aurora``: files, frames, hardpoints schema and symmetry, the cockpit view, OBJ validity, determinism, and the
break-up chunks (AC6): their parts, offsets and joints."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import starfury_aurora as ship
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.obj import read_obj
from tools.procgen.parts import cockpit
from tools.procgen.styles.earthforce import EARTHFORCE
from tools.procgen.tests.test_cockpit import first_hit, sphere

PILOT_TERMS = {
    "sway_left", "sway_right", "heave_up", "heave_down", "pitch_up", "pitch_down",
    "yaw_left", "yaw_right", "roll_left", "roll_right",
}  # fmt: skip
SYM_TOL = 1e-6
POD_NAMES = ("ur", "lr", "ul", "ll")
SPEC = ship.DEFAULT_SPEC
# Cockpit view (camera FOV 75 deg vertical, 16:9, M3-T29): the opening the hull's opaque surface and the cockpit mesh stay out
# of is the V, narrow at the octagon and wide above. What it records, half widths off the nose at the octagon's top edge, the horizon and
# the top bar; the elevations of that edge and the bar; and the box around the crosshair that must stay clear, 1080p pixels.
V_HALF_DEG = {"octagon": 11.2, "horizon": 15.9, "bar": 29.3}
V_ELEVATION_DEG = (-13.3, 36.7)
CROSSHAIR_CLEAR_PX = 60.0
COCKPIT = ship.STARFURY_COCKPIT
# The hull's own window, for the hull seen from outside: below this elevation the chin hides the guns.
CHIN_ELEVATION_DEG = -12.0
CHUNK_NAMES = ("cabin", "arm_ur", "arm_lr", "arm_ul", "arm_ll")
def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mirrored(v: list[float], axes: str, axis_y: float = 0.0) -> list[float]:
    """``v`` mirrored across x = 0 and/or the horizontal plane y = ``axis_y`` (the pods' centre line)."""
    out = list(v)
    for axis in axes:
        k = "xyz".index(axis)
        out[k] = 2.0 * axis_y - out[k] if axis == "y" else -out[k]
    return out


def slices(placed: list) -> dict[str, tuple[int, int]]:
    """The surface samples in placement order: each sampled part is a contiguous slice."""
    out, start = {}, 0
    for p in placed:
        if p.samples is not None:
            out[p.part.name] = (start, start + len(p.samples))
            start += len(p.samples)
    return out


def in_the_v(rel_screen: np.ndarray, margin_px: np.ndarray | float = 0.0) -> np.ndarray:
    """Which 1080p screen points (centred, Y up) lie inside the V, within ``margin_px`` of it counting as inside."""
    x, y = rel_screen[:, 0], rel_screen[:, 1]
    half = COCKPIT.opening_px_at_horizon + COCKPIT.opening_px_per_y * y
    return (np.abs(x) - margin_px < half) & (y + margin_px > COCKPIT.opening_floor_y_px) & (y - margin_px < COCKPIT.bar_y_px)


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
    """Builds the default asset twice (same seed) once for the whole class, and its surface samples (the hull's measure)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = ship.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = ship.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        spacing = ship.DEFAULT_SPACING_M
        cls.placed, _ = ship.centre(ship.build_parts(SPEC, EARTHFORCE, BuildContext(cls.dir_a, seed=42), spacing,
                                                     ship.COCKPIT_SPACING_FACTOR * spacing))
        sampled = [p.samples for p in cls.placed if p.samples is not None]
        cls.godot_xyz = np.concatenate([s.positions for s in sampled])  # centred Godot frame (the hardpoints frame)
        cls.glass = np.concatenate([s.transmittance() for s in sampled]) > 0.0
        cls.albedo = np.concatenate([s.albedo() for s in sampled])
        cls.hp = json.loads(
            (cls.dir_a / ship.HARDPOINTS_NAME).read_text(encoding="utf-8")
        )
        cls.obj = read_obj(cls.dir_a / ship.OBJ_NAME)
        cls.slices = slices(cls.placed)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def axis_y(self) -> float:
        """The pods' centre line (the cross is symmetric about it; the origin is the samples' centroid)."""
        return float(np.mean([p["center"][1] for p in self.hp["pods"]]))

    def part(self, name: str) -> np.ndarray:
        a, b = self.slices[name]
        return self.godot_xyz[a:b]

    def chunk_xyz(self) -> dict[str, np.ndarray]:
        """Each chunk's surface samples, body frame."""
        out: dict[str, list[np.ndarray]] = {}
        for p in self.placed:
            if p.samples is not None:
                out.setdefault(ship.chunk_of(p.part.name), []).append(p.samples.positions)
        return {name: np.concatenate(parts) for name, parts in out.items()}

    # --- files and manifest -----------------------------------------------------------------
    def test_all_ship_files_are_written_and_listed(self) -> None:
        names = sorted(p.name for p in self.dir_a.iterdir())
        chunk_files = [
            f"starfury_aurora_chunk_{c}.{ext}"
            for c in CHUNK_NAMES
            for ext in ("mtl", "obj", "glb")  # glb: the chunk's textured mesh (M4-T30d)
        ]
        self.assertEqual(
            names,
            sorted(
                [
                    "cockpit_interior.mtl",
                    "cockpit_interior.obj",
                    "hardpoints.json",
                    "manifest.json",
                    "starfury_aurora.mtl",
                    "starfury_aurora.obj",
                    # M4-T30a: the textured mesh, its four maps and their import sidecars
                    "starfury_aurora.glb",
                    "starfury_aurora_albedo.png",
                    "starfury_aurora_albedo.png.import",
                    "starfury_aurora_normal.png",
                    "starfury_aurora_normal.png.import",
                    "starfury_aurora_orm.png",
                    "starfury_aurora_orm.png.import",
                    "starfury_aurora_emissive.png",
                    "starfury_aurora_emissive.png.import",
                    # M4-T30b: the livery's digit atlas
                    "starfury_aurora_digits.png",
                    "starfury_aurora_digits.png.import",
                ]
                + chunk_files
            ),
        )
        self.assertEqual(sorted(p.name for p in self.out_a.files), names)
        self.assertEqual(self.out_a.warnings, ())
        self.assertEqual(
            self.manifest["files"],
            {
                "obj": "starfury_aurora.obj",
                "mesh": "starfury_aurora.glb",
                "cockpit_mesh": "cockpit_interior.obj",
                "hardpoints": "hardpoints.json",
            },
        )

    def test_the_manifest_names_the_textured_mesh_and_no_level_ladder(self) -> None:
        self.assertEqual(
            (self.manifest["asset_id"], self.manifest["frame"], self.manifest["seed"]),
            ("starfury_aurora", "godot", 42),
        )
        for gone in ("lods", "hero", "paint_mesh", "counts", "sampling", "chunk_lod"):
            self.assertNotIn(gone, self.manifest)
        self.assertEqual(self.out_a.triangle_count, self.manifest["mesh"]["triangles"])
        expected = ["fuselage", "cockpit", "gun_mount", "fittings"] + [
            f"{p}_{n}" for p in ("pod", "strut", "claw") for n in POD_NAMES
        ]
        self.assertEqual(list(self.slices), expected)
        counts = {name: b - a for name, (a, b) in self.slices.items()}
        for prefix in ("pod", "claw"):
            self.assertEqual(len({counts[f"{prefix}_{n}"] for n in POD_NAMES}), 1, prefix)
        self.assertEqual(counts["strut_ur"], counts["strut_ul"])  # the upper struts are one pair, the lower another
        self.assertEqual(counts["strut_lr"], counts["strut_ll"])

    def test_the_samples_are_centred_within_1e_4(self) -> None:
        self.assertLess(float(np.abs(self.godot_xyz.mean(axis=0)).max()), 1e-4)  # exact by construction
        self.assertEqual(self.manifest["centroid_offset"][0], 0.0)

    def test_manifest_aabb_is_the_hulls(self) -> None:
        np.testing.assert_allclose(self.obj.vertices.min(axis=0), self.manifest["aabb_min"], atol=1e-4)
        np.testing.assert_allclose(self.obj.vertices.max(axis=0), self.manifest["aabb_max"], atol=1e-4)

    def test_the_sample_set_is_exactly_mirror_symmetric_in_x_and_the_pods_in_y(
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
        # The pods and claws below the centre line mirror those above it, sample for sample; the
        # lower struts are their own (their brace is rooted lower on the fuselage).
        axis = self.axis_y()
        for prefix in ("pod", "claw"):
            for upper, lower in (("ur", "lr"), ("ul", "ll")):
                a, b = self.part(f"{prefix}_{upper}"), self.part(f"{prefix}_{lower}")
                np.testing.assert_allclose(a[:, [0, 2]], b[:, [0, 2]], atol=1e-6)
                np.testing.assert_allclose(a[:, 1] + b[:, 1], 2.0 * axis, atol=2e-5)

    def test_the_glass_is_the_window_at_the_nose(self) -> None:
        glass = self.glass
        self.assertTrue(0.002 < glass.mean() < 0.03, glass.mean())
        self.assertLess(float(self.albedo[glass].max()), 0.05)  # dark and neutral since Q36 (the red is the cabin's glow, not the glass)
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
            SPEC.fuselage.stations[SPEC.fuselage.window_end].shoulder_half_width,
        )

    def test_the_base_paint_is_grey_with_no_hazard_stripes(self) -> None:
        rgb = self.albedo
        self.assertTrue(np.all(rgb >= 0.0))
        self.assertLess(float(rgb.max()), 1.0)
        yellow = (rgb[:, 2] < 0.2 * rgb[:, 0]) & (rgb[:, 1] > 0.4 * rgb[:, 0]) & (rgb[:, 0] > 0.1)
        self.assertFalse(yellow.any())  # Q41: no hazard stripes; the base hull is plain grey, colour is the livery's
        chroma = (rgb.max(axis=1) - rgb.min(axis=1)) / np.maximum(rgb.max(axis=1), 1e-9)
        grey = (chroma < 0.45) & (rgb[:, 2] >= rgb[:, 0]) & (rgb.max(axis=1) > 0.06)
        self.assertGreater(float(grey.mean()), 0.3)  # most of the hull is the blue-grey of Q37

    # --- hardpoints -------------------------------------------------------------------------
    def test_hardpoints_schema(self) -> None:
        hp = self.hp
        for key in (
            "frame", "units", "length_m", "center_of_mass", "cockpit_camera", "chase_anchor",
            "muzzles", "pods", "rcs", "collision", "mass_kg", "screens",
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
        self.assertEqual(ur["center"][0], SPEC.pod_center[0])  # x exact, y less the centroid's
        self.assertAlmostEqual(
            ur["center"][1], SPEC.pod_center[1] - self.manifest["centroid_offset"][1], places=4
        )
        axis = self.axis_y()
        self.assertGreater(
            ur["center"][0], 2.0 * ur["center"][1]
        )  # struts about 20 deg off horizontal
        for name, axes in (("lr", "y"), ("ul", "x"), ("ll", "xy")):
            other = pods[name]
            np.testing.assert_allclose(
                other["center"], mirrored(ur["center"], axes, axis), atol=2e-5
            )
            for nozzle in ("main", "retro"):
                np.testing.assert_allclose(
                    other[nozzle]["position"],
                    mirrored(ur[nozzle]["position"], axes, axis),
                    atol=2e-5,
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
        self.assertEqual(com[0], 0.0)
        self.assertAlmostEqual(com[1], self.axis_y(), places=4)  # trimmed onto the pods' centre line
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
        for m in muzzles:
            self.assertEqual(m["direction"], [0.0, 0.0, -1.0])
            self.assertLess(m["position"][1], cam[1] - 1.0)  # under the nose
            # Nothing of the hull lies ahead of a muzzle within 30 cm of its line of fire.
            ahead = self.godot_xyz[:, 2] < m["position"][2] - 0.05
            near = np.hypot(*(self.godot_xyz[:, :2] - np.array(m["position"][:2])).T) < 0.3
            self.assertFalse(np.any(ahead & near), m["name"])
        self.assertEqual(cam[0], 0.0)
        self.assertLess(cam[2], self.hp["center_of_mass"][2] - 2.0)  # well forward
        # Inside the cockpit, behind the front pane and clear of the hull's surface.
        glass = self.glass
        self.assertLess(float(self.godot_xyz[glass, 2].min()), cam[2] - 0.5)
        self.assertGreater(
            float(np.linalg.norm(self.godot_xyz - cam, axis=1).min()), 0.2
        )

    def test_the_opening_records_the_v(self) -> None:
        """The numbers Q29 and the maintainer's change set: about +-16 deg at the horizon, narrower at the console, wider above."""
        self.assertAlmostEqual(cockpit.opening_half_deg(COCKPIT, COCKPIT.opening_floor_y_px), V_HALF_DEG["octagon"], delta=0.2)
        self.assertAlmostEqual(cockpit.opening_half_deg(COCKPIT, 0.0), V_HALF_DEG["horizon"], delta=0.1)
        self.assertAlmostEqual(cockpit.opening_half_deg(COCKPIT, COCKPIT.bar_y_px), V_HALF_DEG["bar"], delta=0.1)
        f = COCKPIT.focal_px
        self.assertAlmostEqual(float(np.degrees(np.arctan2(COCKPIT.opening_floor_y_px, f))), V_ELEVATION_DEG[0], delta=0.2)
        self.assertAlmostEqual(float(np.degrees(np.arctan2(COCKPIT.bar_y_px, f))), V_ELEVATION_DEG[1], delta=0.1)
        self.assertGreater(COCKPIT.opening_half_px(-CROSSHAIR_CLEAR_PX), CROSSHAIR_CLEAR_PX, "the crosshair's area is inside it")
        self.assertLess(COCKPIT.opening_floor_y_px, -CROSSHAIR_CLEAR_PX)

    def test_cockpit_view_is_clear_but_for_the_window_frame(self) -> None:
        """No opaque part of the hull's surface reaches into the V; the panes cover it; the guns are below the sill line, so the
        chin hides them."""
        cam = np.array(self.hp["cockpit_camera"]["position"])
        ahead, az, el = eye_angles(self.godot_xyz, cam)
        opaque = ~self.glass & (ahead > 0.0)
        rel = self.godot_xyz - cam
        front = ahead > 1e-6
        screen = np.full((len(rel), 2), 1e9)
        screen[front] = COCKPIT.focal_px * rel[front, :2] / ahead[front, None]
        intrudes = opaque & front & in_the_v(screen)
        self.assertEqual(int(intrudes.sum()), 0)
        glass = self.glass & (ahead > 0.0)
        self.assertGreater(int((glass & in_the_v(screen)).sum()), 20)
        # The panes reach past the V on every side (they are what the eye looks through).
        top = V_HALF_DEG["bar"]
        self.assertLess(float(az[glass].min()), -top)
        self.assertGreater(float(az[glass].max()), top)
        self.assertLess(float(el[glass].min()), V_ELEVATION_DEG[0])
        self.assertGreater(float(el[glass].max()), V_ELEVATION_DEG[1])
        # The opaque samples that frame the view above the sill are the window's own: the fuselage
        # and cockpit slices (the guns are further down, behind the chin).
        lo = CHIN_ELEVATION_DEG
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
            mirrored(rcs["lr_ny"]["position"], "y", self.axis_y()),
            atol=2e-5,
        )
        np.testing.assert_allclose(
            rcs["ur_px"]["position"],
            mirrored(rcs["ll_nx"]["position"], "xy", self.axis_y()),
            atol=2e-5,
        )
        # Each cone sits on its pod's claw: behind the pod centre, outside the pod, on the claw's surface.
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
                ("capsule", SPEC.pod.collision_radius, "z"),
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
        # Rotated boxes: along the swept strut (out, up and aft), and along the claw's outboard
        # prongs, which lie nearly level with the pod (out and aft).
        x_col = shapes["strut_ur"]["basis"]["x"]
        self.assertTrue(all(abs(v) > 0.2 for v in x_col), x_col)
        x_col = shapes["claw_ur"]["basis"]["x"]
        self.assertTrue(abs(x_col[0]) > 0.2 and abs(x_col[2]) > 0.2, x_col)
        # Every primitive wraps its part: the surface samples of that part lie inside (5 cm slack). The claw
        # box wraps the outboard pincer, about half the claw; the inboard blade and the thruster
        # blocks hug the pod. The pod's dome and sensor bulb stand out of its capsule.
        for name, minimum in (
            ("fuselage", 0.999),
            ("gun_mount", 0.999),
            ("pod_ur", 0.9),
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

    def test_hardpoints_agree_with_the_surface(self) -> None:
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
                    d[lip, :2].mean(axis=0), [0.0, 0.0], atol=0.06
                )  # a ring of about a hundred samples: its mean wanders a few centimetres
            # The main exit is the rearmost point of the pod: the visible end of the nozzle.
            self.assertAlmostEqual(
                float(own[:, 2].max()), p["main"]["position"][2], delta=0.002
            )
            self.assertAlmostEqual(
                float(own[:, 2].min()), p["retro"]["position"][2], delta=0.002
            )

    # --- meshes -----------------------------------------------------------------------------
    def test_the_obj_is_valid_and_symmetric(self) -> None:
        obj = self.obj
        self.assertGreater(len(obj.vertices), 0)
        self.assertGreater(len(obj.faces), 0)
        self.assertGreaterEqual(int(obj.faces.min()), 0)
        self.assertLess(int(obj.faces.max()), len(obj.vertices))
        self.assertEqual(obj.mtllib, "starfury_aurora.mtl")
        mtl = (self.dir_a / "starfury_aurora.mtl").read_text(encoding="ascii")
        for name in obj.materials:
            self.assertIn(f"newmtl {name}", mtl)
        for name in ("ef_canopy_glass", "ef_canopy_frame", "ef_nozzle"):
            self.assertIn(name, obj.materials)
        self.assertNotIn("ef_hazard", obj.materials)  # Q41: no hazard stripes on the base hull
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
        rel = obj.vertices - cam
        ahead = -rel[:, 2]
        front = ahead > 1e-6
        screen = COCKPIT.focal_px * rel[front, :2] / ahead[front, None]
        self.assertEqual(int(in_the_v(screen, -0.5).sum()), 0, "half a pixel in: its corners lie on the edge")
        off_axis = np.degrees(np.arctan2(np.hypot(*rel[:, :2].T), ahead))
        self.assertGreater(float(off_axis[front].min()), 8.0, "the crosshair's area is clear")

    def test_the_hull_never_stands_inside_the_interior(self) -> None:
        # The cockpit camera draws the hull mesh too, with its glass and window frames cleared; whatever else of it the shell does not
        # hold out would cut into the cabin from outside.
        cam = np.array(self.hp["cockpit_camera"]["position"])
        hull = read_obj(self.dir_a / ship.OBJ_NAME)
        materials = np.array(hull.face_materials)
        kept = ~np.isin(materials, ["ef_canopy_glass", "ef_canopy_frame"])
        triangles = hull.vertices[hull.faces[kept]]
        triangles = triangles[np.linalg.norm(triangles - cam, axis=2).min(axis=1) < 2.2]
        interior = read_obj(self.dir_a / ship.COCKPIT_NAME)
        rays = sphere(3000)
        to_hull, _ = first_hit(cam, rays, triangles)
        to_interior, _ = first_hit(cam, rays, interior.vertices[interior.faces])
        both = np.isfinite(to_hull) & np.isfinite(to_interior)
        # Out past the walls the sill only hides what lies below the side panes: hull seen through a pane is meant to be there.
        finite = np.where(np.isfinite(to_interior), to_interior, 0.0)
        both &= np.abs(rays[:, 0] * finite) < COCKPIT.wall_x + 0.01
        self.assertGreater(int(both.sum()), 300, "the shell and the hull overlap in many directions")
        self.assertTrue(np.all(to_interior[both] < to_hull[both]), rays[both][to_interior[both] >= to_hull[both]][:5])

    # --- the console's screens (M3-T29) ---------------------------------------------------------
    def test_hardpoints_carry_the_screens_the_interior_was_built_around(self) -> None:
        screens = self.hp["screens"]
        self.assertEqual(sorted(screens), ["left", "octagon", "right"])
        eye = self.hp["cockpit_camera"]["position"]
        built = cockpit.cockpit_screens(COCKPIT, eye)
        for name, screen in screens.items():
            self.assertEqual(sorted(screen), ["center", "corner", "normal", "size", "up"], name)
            for key in ("center", "normal", "up", "size"):
                np.testing.assert_allclose(screen[key], built[name][key], atol=1e-4, err_msg=f"{name}.{key}")

    def test_port_and_starboard_screens_are_on_the_right_sides(self) -> None:
        # -X is the ship's left, as for the running lights.
        screens, eye = self.hp["screens"], self.hp["cockpit_camera"]["position"]
        self.assertLess(screens["left"]["center"][0], -0.2)
        self.assertGreater(screens["right"]["center"][0], 0.2)
        self.assertEqual(screens["octagon"]["center"][0], 0.0)
        self.assertEqual(screens["left"]["center"][1:], screens["right"]["center"][1:], "a mirrored pair")
        for name, screen in screens.items():
            self.assertLess(screen["center"][1], eye[1], f"{name}: below the eye")
            self.assertLess(screen["center"][2], eye[2], f"{name}: ahead of the pilot")

    def test_a_new_interior_leaves_the_hull_alone(self) -> None:
        # M4-T30a's version 6 added the textured mesh, M4-T30b's 7 the liveries, M4-T30d's 8 the chunk meshes and M4-T31's 9 dropped the
        # point-cloud outputs and renamed the sample stream, which moves the centring by 1.5 mm; the design is unchanged. The hull's OBJ
        # has none of the interior's materials.
        self.assertEqual(ship.GENERATOR_VERSION, 9)
        hull = read_obj(self.dir_a / ship.OBJ_NAME)
        self.assertFalse([m for m in hull.materials if "ef_cockpit" in m])

    # --- chunks (AC6) -----------------------------------------------------------------------
    def test_each_chunk_sits_at_its_samples_centroid(self) -> None:
        chunks = self.hp["chunks"]
        self.assertEqual([c["name"] for c in chunks], list(CHUNK_NAMES))
        self.assertEqual(self.manifest["chunks"], list(CHUNK_NAMES))
        parts = self.chunk_xyz()
        for entry in chunks:
            name = entry["name"]
            self.assertEqual(set(entry), {"name", "obj", "offset", "mesh", "joint"}, name)
            self.assertEqual(entry["obj"], f"starfury_aurora_chunk_{name}.obj")
            np.testing.assert_allclose(entry["offset"], parts[name].mean(axis=0), atol=1e-4)
        self.assertEqual(sum(len(v) for v in parts.values()), len(self.godot_xyz), "the chunks share out every sample")

    def test_chunks_are_the_cabin_and_four_arms(self) -> None:
        chunks = {c["name"]: c for c in self.hp["chunks"]}
        parts = self.chunk_xyz()
        cabin = chunks["cabin"]["offset"]
        self.assertEqual(cabin[0], 0.0)  # on the centre line by symmetry
        self.assertLess(cabin[1], self.axis_y())  # the chin hangs below the pods' centre line
        self.assertLess(cabin[2], -1.0)  # the fuselage is ahead of the X
        # The cabin is the fuselage and the gun pod, inside DamageZones' cabin band (|x| <= 2 m).
        self.assertLess(float(np.abs(parts["cabin"][:, 0]).max()), 2.0)
        pods = {p["name"]: np.array(p["center"]) for p in self.hp["pods"]}
        axis = np.array([0.0, self.axis_y()])
        for pod in POD_NAMES:
            arm, sign = parts[f"arm_{pod}"] - np.array([0.0, axis[1], 0.0]), np.sign(pods[pod][:2] - axis)
            # Every sample of an arm outside the cabin band is on its pod's side of both centre
            # planes (the deck reaches the centre line and the upper brace dips under the pods'
            # centre line by the fuselage's shoulder), from the fuselage's flank to the claw tips ...
            outside = np.abs(arm[:, 0]) > 2.0
            self.assertTrue(np.all(arm[outside, :2] * sign > 0.0), pod)
            self.assertLess(float(np.abs(arm[:, 0]).min()), 1.7, pod)
            self.assertGreater(
                float(np.abs(arm[:, 0]).max()), abs(pods[pod][0]) + 1.5, pod
            )
            # ... and its centroid lies between the cabin and the pod.
            offset = np.array(chunks[f"arm_{pod}"]["offset"])[:2] - axis
            self.assertTrue(np.all(offset * sign > 0.0), pod)
            self.assertTrue(np.all(np.abs(offset) < np.abs(pods[pod][:2] - axis)), pod)
        for right, left in (("ur", "ul"), ("lr", "ll")):
            self.assertEqual(len(parts[f"arm_{right}"]), len(parts[f"arm_{left}"]))
            np.testing.assert_allclose(
                chunks[f"arm_{left}"]["offset"], mirrored(chunks[f"arm_{right}"]["offset"], "x"), atol=SYM_TOL
            )

    def test_chunk_joints_are_where_each_part_meets_the_body(self) -> None:
        """M3-T28: every chunk names its detachment point, in the body frame, beside its offset."""
        chunks = {c["name"]: c for c in self.hp["chunks"]}
        for entry in chunks.values():
            self.assertEqual(len(entry["joint"]), 3, entry["name"])
        # An arm leaves the fuselage at its flank, on its own side of both centre planes.
        axis = np.array([0.0, self.axis_y(), 0.0])
        pods = {p["name"]: np.array(p["center"]) for p in self.hp["pods"]}
        for pod in POD_NAMES:
            joint = np.array(chunks[f"arm_{pod}"]["joint"])
            self.assertAlmostEqual(abs(joint[0]), 1.0, delta=0.15, msg=pod)
            self.assertEqual(np.sign(joint[0]), np.sign(pods[pod][0]), pod)
            self.assertEqual(np.sign(joint[1] - axis[1]), np.sign(pods[pod][1] - axis[1]), pod)
            # Inside the fuselage's height, well inboard of the arm's own centroid.
            self.assertLess(abs(joint[0]), abs(chunks[f"arm_{pod}"]["offset"][0]))
        # The cabin leaves the body on the centre line, at the strut roots' middle.
        cabin = np.array(chunks["cabin"]["joint"])
        self.assertEqual(cabin[0], 0.0)
        arms = np.array([chunks[f"arm_{pod}"]["joint"] for pod in POD_NAMES])
        np.testing.assert_allclose(cabin[1:], arms[:, 1:].mean(axis=0), atol=SYM_TOL)
        for right, left in (("ur", "ul"), ("lr", "ll")):
            np.testing.assert_allclose(
                chunks[f"arm_{left}"]["joint"], mirrored(chunks[f"arm_{right}"]["joint"], "x"), atol=SYM_TOL
            )

    def test_chunk_objs_are_the_hull_split_by_chunk(self) -> None:
        vertices = []
        for entry in self.hp["chunks"]:
            obj = read_obj(self.dir_a / entry["obj"])
            self.assertGreater(len(obj.faces), 0, entry["name"])
            self.assertTrue(np.all(np.isfinite(obj.vertices)))
            self.assertLess(int(obj.faces.max()), len(obj.vertices))
            self.assertEqual(obj.mtllib, entry["obj"].replace(".obj", ".mtl"))
            chunk = self.chunk_xyz()[entry["name"]] - np.array(entry["offset"])
            lo, hi = obj.vertices.min(axis=0), obj.vertices.max(axis=0)
            self.assertTrue(
                np.all(chunk.min(axis=0) >= lo - 0.2)
                and np.all(chunk.max(axis=0) <= hi + 0.2),
                entry["name"],
            )
            vertices.append(obj.vertices + np.array(entry["offset"]))
        # Back at their offsets they are the hull's mesh: the same vertex count and bounds.
        body = np.concatenate(vertices)
        self.assertEqual(len(body), len(self.obj.vertices))
        np.testing.assert_allclose(
            body.min(axis=0), self.obj.vertices.min(axis=0), atol=0.01
        )
        np.testing.assert_allclose(
            body.max(axis=0), self.obj.vertices.max(axis=0), atol=0.01
        )
        cabin = read_obj(self.dir_a / "starfury_aurora_chunk_cabin.obj")
        self.assertIn("ef_canopy_glass", cabin.materials)
        arm = read_obj(self.dir_a / "starfury_aurora_chunk_arm_ur.obj")
        self.assertIn("ef_nozzle", arm.materials)
        self.assertNotIn("ef_canopy_glass", arm.materials)

    def test_hardpoints_and_manifest_only_gain_the_new_keys_at_the_end(self) -> None:
        self.assertEqual(list(self.hp)[-1], "chunks")
        self.assertEqual(list(self.manifest)[-3:], ["dimensions_m", "chunks", "mesh"])
        self.assertEqual(self.out_a.warnings, ())

    # --- determinism ------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        for path in self.dir_a.iterdir():
            self.assertEqual(sha256(path), sha256(self.dir_b / path.name), path.name)

    def test_a_different_seed_changes_the_wear_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = ship.build(BuildContext(Path(tmp), seed=7))
            albedo = "starfury_aurora_albedo.png"
            self.assertNotEqual(sha256(Path(tmp) / albedo), sha256(self.dir_a / albedo))
            self.assertEqual(other.triangle_count, self.out_a.triangle_count)
            # The origin is the sampled centroid, so it moves by millimetres with the seed;
            # the design (every pod x, every y and z difference) does not.
            hp = json.loads(
                (Path(tmp) / ship.HARDPOINTS_NAME).read_text(encoding="utf-8")
            )
            for mine, theirs in zip(self.hp["pods"], hp["pods"], strict=True):
                self.assertEqual(mine["center"][0], theirs["center"][0])
                self.assertAlmostEqual(mine["center"][1], theirs["center"][1], delta=0.005)
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


class StarfuryNavLightTests(unittest.TestCase):
    """Running lights (M3-T27, Q27): read from a generated ``hardpoints.json``, never from typed-in positions."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        out = Path(cls._tmp.name) / "a"
        ship.build(BuildContext(out, seed=42))
        cls.hp = json.loads((out / ship.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.nav = cls.hp["nav_lights"]
        cls.pods = {pod["name"]: pod for pod in cls.hp["pods"]}

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_port_is_the_ships_left_and_starboard_its_right(self) -> None:
        # -X is the ship's left (DamageZones: +X right, +Y up, -Z forward). Pod sides are the generator's own labels.
        self.assertEqual(self.pods["ul"]["side"], "left")
        self.assertEqual(self.pods["ur"]["side"], "right")
        self.assertLess(self.nav["port"][0], -4.0, "port is on the left upper pod")
        self.assertGreater(self.nav["starboard"][0], 4.0, "starboard on the right one")
        self.assertEqual(self.nav["port"], [-self.nav["starboard"][0], *self.nav["starboard"][1:]], "a mirrored pair")

    def test_the_side_lights_sit_on_the_upper_arms_clear_of_the_hull(self) -> None:
        for key, pod in (("port", "ul"), ("starboard", "ur")):
            centre = self.pods[pod]["center"]
            self.assertGreater(self.nav[key][1], centre[1], f"{key}: above the upper pod, where a claw cannot hide it")
            self.assertLess(abs(self.nav[key][0] - centre[0]), 1.0, f"{key}: on the pod, not floating off it")
            self.assertLess(self.nav[key][1] - centre[1], 2.0, f"{key}: on the pod, not floating over it")

    def test_the_top_light_is_behind_the_canopy_on_the_centre_line(self) -> None:
        top, eye = self.nav["top"], self.hp["cockpit_camera"]["position"]
        self.assertEqual(top[0], 0.0)
        self.assertGreater(top[1], eye[1], "above the pilot")
        self.assertGreater(top[2], eye[2], "behind the pilot: +Z is aft")
        self.assertGreater(top[1], 1.4, "clear of the struts' root, the highest hull on the centre line")

    def test_the_top_lamp_stands_over_the_cabin_top_and_reaches_it(self) -> None:
        lamp, top = self.nav["top_lamp"], self.nav["top"]
        self.assertEqual(lamp[0], 0.0)
        self.assertGreater(lamp[1], top[1], "it shines down on the section")
        self.assertGreater(self.nav["top_lamp_range_m"], lamp[1] - top[1], "the section is within its range")

    def test_the_cabin_glow_is_in_the_cockpit(self) -> None:
        cabin, eye = self.nav["cabin"], self.hp["cockpit_camera"]["position"]
        self.assertEqual(cabin, eye)
        self.assertLess(self.nav["cabin_range_m"], 3.0, "it stays in the cabin section: the arms are outside it")


class StarfuryOptionTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def test_invalid_options_are_rejected(self) -> None:
        for bad in (
            {"spacing": 0.0},
            {"spacing": -1.0},
            {"cockpit_spacing": 0.0},
        ):
            with self.subTest(bad), self.assertRaises(ValueError):
                ship.build(BuildContext(self.dir / "bad", seed=1, options=bad))



if __name__ == "__main__":
    unittest.main()
