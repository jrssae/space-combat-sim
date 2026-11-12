"""``saturn_family`` (AC12, Q16, D61; textured meshes from M5-T27): the five Saturn hulls against ``docs/assets-civilian.md``
and the design references.

Per variant: files, the mesh contract and its budget, frames, mirror symmetry, the chunk cuts, collision coverage, the
hardpoints contract (with ``turrets[]``), the turret model, the paint. Across variants: the Q16 length rule and the shared
lead ship; determinism. The expected numbers below are typed in from the design documents, not read from the generator.
The visible surface (the samples that place the body origin) stands in for the hull's skin where a test asks what the eye
sees.
"""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any, ClassVar

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.core.color import capture_albedo
from tools.procgen.assets import saturn_family as saturn
from tools.procgen.parts import saturn as sp
from tools.procgen.core import civilian as cv
from tools.procgen.core import manifest as manifest_io
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
    painted_faces,
)

PILOT_TERMS = {
    "sway_left", "sway_right", "heave_up", "heave_down", "pitch_up", "pitch_down",
    "yaw_left", "yaw_right", "roll_left", "roll_right",
}  # fmt: skip
SYM_TOL = 1e-5
POS_TOL = 2e-3  # hardpoints are rounded to 5 decimals, the centroid offset to 4
LEAD_FORE_M = 49.3  # lead ship ahead of the first cargo section
SECTION_M = 100.0  # one Saturn 4 cargo section (Q16)
ENGINE_TAIL_M = 9.18  # the engine section behind the last section
ENGINE_M = 22.6
UP, DOWN = (0.0, 1.0, 0.0), (0.0, -1.0, 0.0)
# Q32: the command section's two flank turrets on the disc rim (supersedes Q19's dorsal_fwd on the hub).
LEAD_TURRETS = {"flank_l": ((-14.43, 0.0, 19.1), (-1.0, 0.0, 0.0)), "flank_r": ((14.43, 0.0, 19.1), (1.0, 0.0, 0.0))}
SLIM = 2.8 / 4.8  # Q20: the Saturn 3's engine, the shared section scaled to fit between its lower pods
STACK_REAR_Z = 95.30  # the Saturn 3's pods' aft faces (64.24 + the shared pod's 31.06 m turned)

# docs/assets-civilian.md: budgets, hardpoints, chunks; docs/design-references.md: turrets.
DESIGN: dict[str, dict[str, Any]] = {
    "saturn_4_transport": {
        "length": 158.48,
        "engine": 1.0,
        "turrets": {**LEAD_TURRETS, "dorsal_aft": ((0.0, 9.3, 124.4), UP)},
        "starboard": (53.4, -7.29, 74.3),
        "lamp": ((0.0, 16.6, 99.4), 48.0),
        "chunks": ("bow", "hull", "engine", "pods_l", "pods_r"),
    },
    "saturn_4_tanker": {
        "length": 158.48,
        "engine": 1.0,
        "turrets": {**LEAD_TURRETS, "dorsal_aft": ((0.0, 9.3, 124.4), UP)},
        "starboard": (25.6, -13.53, 99.4),
        "lamp": ((0.0, 16.6, 99.4), 48.0),
        "chunks": ("bow", "spine", "engine", "tank_l", "tank_r"),
    },
    "saturn_8_transport": {
        "length": 258.48,
        "engine": 1.0,
        "turrets": {**LEAD_TURRETS, "dorsal_mid": ((0.0, 7.2, 149.4), UP)},
        "starboard": (53.4, -7.29, 74.3),
        "lamp": ((0.0, 21.5, 149.4), 78.0),
        "chunks": ("bow", "hull_1", "junction", "hull_2", "engine", "pods_1l", "pods_1r", "pods_2l", "pods_2r"),
    },
    "saturn_8_tanker": {
        "length": 258.48,
        "engine": 1.0,
        "turrets": {**LEAD_TURRETS, "dorsal_mid": ((0.0, 9.0, 149.4), UP)},
        "starboard": (25.6, -13.53, 99.4),
        "lamp": ((0.0, 21.5, 149.4), 78.0),
        "chunks": ("bow", "spine_1", "junction", "spine_2", "engine", "tanks_1l", "tanks_1r", "tanks_2l", "tanks_2r"),
    },
    "saturn_3_freighter": {
        "length": STACK_REAR_Z + 1.5,  # Q20: the bell's exit 1.5 m behind the pods
        "engine": SLIM,
        "turrets": dict(LEAD_TURRETS),
        "starboard": (46.8, -5.46, 79.7),
        "lamp": ((0.0, 27.8, 79.7), 36.0),
        "chunks": ("bow", "pod_top", "pod_l", "pod_r", "engine"),
    },
}
TRIANGLE_BUDGET = 70_000  # every hull (41 518 to 54 998 as built); the importer adds the levels of detail
TURRET_TRIANGLE_BUDGET = 5_000
TEXEL_MAX_M = 0.2  # the biggest hull (the Saturn 8 transport, 19 cm as built) at the default 2 048 px atlas

_TMP = tempfile.TemporaryDirectory()
_BUILDS: dict[tuple[str, str], Any] = {}


def build_once(asset_id: str, tag: str = "default", **options: Any) -> Path:
    """Builds a variant once per test run (the full builds are the slow part) and returns its directory."""
    key = (asset_id, tag)
    if key not in _BUILDS:
        out = Path(_TMP.name) / tag / asset_id
        _BUILDS[key] = ASSETS[asset_id](BuildContext(out, seed=42, options={**TEST_OPTIONS, **options}))
    return _BUILDS[key].out_dir


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


class SaturnVariantChecks:
    """The output contract for one variant; a subclass per variant sets ``ASSET_ID``."""

    ASSET_ID: ClassVar[str] = ""

    @classmethod
    def setUpClass(cls) -> None:
        cls.design = DESIGN[cls.ASSET_ID]
        cls.dir = build_once(cls.ASSET_ID)
        cls.out = _BUILDS[(cls.ASSET_ID, "default")]
        cls.manifest = manifest_io.read_manifest(cls.dir)
        cls.hp = json.loads((cls.dir / saturn.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.spacing = float(cls.manifest["surface_spacing_m"])
        variant = saturn.VARIANTS[cls.ASSET_ID]
        sampled = saturn.sample_hull(saturn.assemble(variant, saturn.EA_CIVILIAN), BuildContext(cls.dir, seed=42), cls.spacing)
        cls.xyz = np.concatenate([s.samples.positions for s in sampled]) - cls.offset  # the visible surface, body frame

    def authored(self, v: list[float]) -> np.ndarray:
        """A hardpoint back in the design references' frame (nose at z = 0, y from the spine axis)."""
        return np.array(v) + self.offset

    # --- files, manifest, budget ------------------------------------------------------------------
    def test_registered_and_named(self) -> None:
        self.assertIn(self.ASSET_ID, ASSETS)
        self.assertEqual(self.manifest["asset_id"], self.ASSET_ID)
        self.assertEqual(self.hp["asset_id"], self.ASSET_ID)

    def test_all_files_are_written_and_listed(self) -> None:
        aid = self.ASSET_ID
        expected = {f"{aid}.obj", f"{aid}.mtl", saturn.HARDPOINTS_NAME, "manifest.json"}
        for stem in (aid, f"{aid}_turret"):
            expected |= {f"{stem}.glb"} | {f"{stem}_{k}.png{x}" for k in ("albedo", "normal", "orm", "emissive") for x in ("", ".import")}
        # The hull's low texture set (M5-T40); the turret has no layouts, so one set.
        expected |= {f"{aid}_{k}_low.png{x}" for k in ("albedo", "normal", "orm") for x in ("", ".import")}
        for entry in self.hp["chunks"]:
            expected |= {entry["mesh"], entry["obj"], entry["obj"].replace(".obj", ".mtl")}
        turret = self.manifest["turret"]
        expected |= {turret["obj"], turret["obj"].replace(".obj", ".mtl")}
        self.assertEqual(turret["obj"], f"{aid}_turret.obj")
        self.assertEqual({p.name for p in self.dir.iterdir()}, expected)
        self.assertEqual({p.name for p in self.out.files}, expected)

    def test_the_hull_is_its_textured_mesh_inside_the_budget(self) -> None:
        assert_hull_mesh(self, self.dir, self.manifest, f"{self.ASSET_ID}.obj")
        self.assertLessEqual(self.manifest["mesh"]["triangles"], TRIANGLE_BUDGET)
        self.assertEqual(self.out.warnings, ())
        for key in ("lods", "counts", "sampling", "paint_mesh", "chunk_lod"):
            self.assertNotIn(key, self.manifest)
        self.assertEqual(self.manifest["chunks"], list(self.design["chunks"]))
        self.assertEqual(self.manifest["dimensions_m"]["length"], self.hp["length_m"])

    # --- frames, symmetry ---------------------------------------------------------------------------
    def test_the_body_origin_is_the_visible_surfaces_centroid(self) -> None:
        np.testing.assert_allclose(self.xyz.mean(axis=0), [0.0, 0.0, 0.0], atol=2e-3)
        v = read_obj(self.dir / f"{self.ASSET_ID}.obj").vertices
        np.testing.assert_allclose(v.min(axis=0), self.manifest["aabb_min"], atol=2e-4)
        np.testing.assert_allclose(v.max(axis=0), self.manifest["aabb_max"], atol=2e-4)

    def test_the_visible_surface_is_mirror_symmetric_in_x(self) -> None:
        assert_mirror_symmetric(self, self.xyz, "visible surface", decimals=4)

    # --- chunks ----------------------------------------------------------------------------------------
    def test_chunks_cut_the_hull(self) -> None:
        assert_chunks_cut_the_hull(self, self.dir, self.manifest, self.hp, self.design["chunks"])
        for entry in self.hp["chunks"]:
            self.assertEqual(len(entry["joint"]), 3)

    def test_paired_chunks_mirror_each_other(self) -> None:
        offsets = {c["name"]: np.array(c["offset"]) for c in self.hp["chunks"]}
        for name, offset in offsets.items():
            if name.endswith("r"):
                twin = offsets[name[:-1] + "l"]
                np.testing.assert_allclose(twin, offset * np.array([-1.0, 1.0, 1.0]), atol=1e-3)
                self.assertGreater(offset[0], 5.0, name)
            elif not name.endswith("l"):
                self.assertAlmostEqual(float(offset[0]), 0.0, places=3)

    # --- fallback mesh -----------------------------------------------------------------------------------
    def test_the_fallback_mesh_and_chunk_meshes_hold_every_piece(self) -> None:
        parts = [p.part for p in saturn.with_twins(saturn.assemble(saturn.VARIANTS[self.ASSET_ID], saturn.EA_CIVILIAN))]
        self.assertTrue(all(p.mesh.face_count > 0 for p in parts))
        obj = read_obj(self.dir / f"{self.ASSET_ID}.obj")
        self.assertEqual(len(obj.faces), sum(p.mesh.face_count for p in parts), "the hull OBJ is every piece")
        for entry in self.hp["chunks"]:
            expected = sum(p.mesh.face_count for p in parts if p.group == entry["name"])
            self.assertEqual(len(read_obj(self.dir / entry["obj"]).faces), expected, entry["name"])

    def test_the_drawn_mesh_is_mirror_symmetric_in_x(self) -> None:
        v = read_obj(self.dir / f"{self.ASSET_ID}.obj").vertices
        np.testing.assert_allclose(sorted_rows(np.round(v, 4)), sorted_rows(np.round(v * np.array([-1.0, 1.0, 1.0]), 4)), atol=2e-4)

    def test_the_frames_lower_bars_meet_the_truss_drum_at_both_ends(self) -> None:
        if saturn.VARIANTS[self.ASSET_ID].cargo == "stack":
            self.skipTest("the Saturn 3 has its truss behind the drum frame, no aft frame")
        pieces = {p.name: p for p in saturn.with_twins(saturn.assemble(saturn.VARIANTS[self.ASSET_ID], saturn.EA_CIVILIAN))}
        v = pieces["drum_truss_neck"].part.mesh.vertices
        (x, y, end) = sp.FWD_LOWER_BAR[1]
        mid = 0.5 * sum(sp.DRUM_FRAME_Z)
        for z, half in ((end, v[v[:, 2] < mid]), (sp.FRAME_MIRROR_Z - end, v[v[:, 2] > mid])):
            self.assertGreater(len(half), 0, f"a truss drum neck on that side of the drum frame (z {z:.1f})")
            self.assertTrue(float(half[:, 2].min()) <= z <= float(half[:, 2].max()), f"a neck reaches the bar's end at z {z:.1f}")
            self.assertLessEqual(float(np.hypot(x - sp.TRUSS_DRUM[0], y - sp.TRUSS_DRUM[1])), sp.TRUSS_DRUM_NECK_R, z)

    def test_the_aft_frame_lands_in_the_first_domes_brackets(self) -> None:
        if saturn.VARIANTS[self.ASSET_ID].cargo == "stack":
            self.skipTest("the Saturn 3 has its truss behind the drum frame, no aft frame")
        pieces = {p.name: p for p in saturn.with_twins(saturn.assemble(saturn.VARIANTS[self.ASSET_ID], saturn.EA_CIVILIAN))}
        brackets = next(p for name, p in pieces.items() if name.endswith("front_dome_brackets") and name.startswith("s1_"))
        start = float(brackets.part.mesh.bounds()[0][2])
        for name in ("frame_aft_centre", "frame_aft_upper_r"):
            self.assertGreater(float(pieces[name].part.mesh.bounds()[1][2]), start, f"{name} reaches the brackets at z {start:.2f}")

    def test_fallback_mesh_holds_the_visible_surface(self) -> None:
        v = read_obj(self.dir / f"{self.ASSET_ID}.obj").vertices
        np.testing.assert_allclose(v.min(axis=0), self.xyz.min(axis=0), atol=2.0 * self.spacing)
        np.testing.assert_allclose(v.max(axis=0), self.xyz.max(axis=0), atol=2.0 * self.spacing)

    def test_the_paint_reads_grey_plating_with_red_and_white_bands(self) -> None:
        # Area-weighted over the paint (the coarse test atlas's wear is broad): the disc is cool grey, the cylinders banded.
        at, rgb, area, metal = painted_faces(self.dir, self.manifest["mesh"])
        authored = at + self.offset
        keep = metal < 0.3
        disc = keep & (authored[:, 2] > 6.0) & (authored[:, 2] < 30.0) & (np.abs(authored[:, 0]) > 7.5) & (authored[:, 1] < -0.5)
        grey = np.average(rgb[disc], axis=0, weights=area[disc])
        self.assertLess(float(np.ptp(grey)), 0.1, "the disc's underside is a neutral grey")
        self.assertGreater(float(grey.mean()), 0.18, "a mid grey (darker than the capture, which shows lit paint)")
        red = keep & (rgb[:, 0] > 1.6 * rgb[:, 1]) & (rgb[:, 0] > 0.2)  # the darkened red (capture_albedo)
        self.assertGreater(int(red.sum()), 10, "the red bands")
        self.assertLess(float(np.abs(authored[red, 0]).mean()), 30.0, "on the cylinders and the disc's ring, not the pods")

    def test_the_rim_windows_and_the_engine_glow(self) -> None:
        glowing = glowing_points(self.dir, self.manifest["mesh"]) + self.offset
        rim = glowing[np.abs(glowing[:, 2] - 19.1) < 15.0]
        self.assertGreater(float(np.hypot(rim[:, 0], rim[:, 2] - 19.1).max()), 12.0, "the windows round the disc's rim")
        self.assertTrue((glowing[:, 2] > self.design["length"] - 25.0 * self.design["engine"]).any(), "the engine's throat")
        self.assertEqual(saturn.EA_CIVILIAN.material("nozzle_throat").emissive_strength, 3.0)

    # --- hardpoints ----------------------------------------------------------------------------------------
    def test_hardpoints_schema(self) -> None:
        for key in ("asset_id", "generator_version", "frame", "units", "length_m", "span_m", "height_m", "mass_kg",
                    "inertia_estimate_kg_m2", "center_of_mass", "cockpit_camera", "chase_anchor", "muzzles", "pods",
                    "rcs", "collision", "nav_lights", "chunks", "turrets"):
            self.assertIn(key, self.hp)
        self.assertEqual((self.hp["frame"], self.hp["units"]), ("godot", "m"))
        self.assertEqual(self.hp["muzzles"], [], "turrets carry their own barrels")
        self.assertGreater(self.hp["mass_kg"], 0.0)

    def test_length_follows_the_design(self) -> None:
        self.assertAlmostEqual(self.hp["length_m"], self.design["length"], delta=0.02)

    def test_two_pods_main_at_the_bell_retro_at_the_disc_rim(self) -> None:
        pods = {p["name"]: p for p in self.hp["pods"]}
        self.assertEqual(set(pods), {"l", "r"})
        self.assertEqual((pods["l"]["side"], pods["r"]["side"]), ("left", "right"))
        length, k = self.design["length"], self.design["engine"]
        for name, sx in (("l", -1.0), ("r", 1.0)):
            p = pods[name]
            np.testing.assert_allclose(self.authored(p["main"]["position"]), [sx * 0.95 * k, 0.0, length], atol=0.02)
            np.testing.assert_allclose(self.authored(p["retro"]["position"]), [sx * 9.51, 0.0, 8.56], atol=POS_TOL)
            self.assertEqual(p["main"]["exhaust"], [0.0, 0.0, 1.0])
            self.assertEqual(p["retro"]["exhaust"], [0.0, 0.0, -1.0])
            self.assertAlmostEqual(p["main"]["radius"], round(2.2 * k, 5))
            self.assertAlmostEqual(p["retro"]["radius"], 0.95)

    def test_centre_of_mass_on_the_spine_axis(self) -> None:
        com = self.authored(self.hp["center_of_mass"])
        self.assertAlmostEqual(float(com[0]), 0.0, places=3)
        self.assertAlmostEqual(float(com[1]), 0.0, delta=POS_TOL, msg="main thrust makes no pitch torque")
        self.assertTrue(0.0 < com[2] < self.design["length"])

    def test_the_main_exits_are_the_rearmost_points(self) -> None:
        main = np.array(self.hp["pods"][0]["main"]["position"])
        self.assertAlmostEqual(float(self.xyz[:, 2].max()), float(main[2]), delta=0.05)

    def test_cockpit_camera_and_cabin_light_on_the_bridge(self) -> None:
        cam = self.hp["cockpit_camera"]
        np.testing.assert_allclose(self.authored(cam["position"]), [0.0, 0.8, 8.0], atol=POS_TOL)
        self.assertEqual((cam["forward"], cam["up"]), ([0.0, 0.0, -1.0], [0.0, 1.0, 0.0]))
        nav = self.hp["nav_lights"]
        np.testing.assert_allclose(nav["cabin"], cam["position"], atol=1e-6)
        self.assertAlmostEqual(nav["cabin_range_m"], 0.05 * self.design["length"], delta=0.1)

    def test_chase_anchor_above_and_behind(self) -> None:
        length = self.design["length"]
        np.testing.assert_allclose(self.hp["chase_anchor"]["position"], [0.0, 0.3 * length, 1.2 * length], atol=0.05)

    def test_running_lights(self) -> None:
        nav = self.hp["nav_lights"]
        np.testing.assert_allclose(self.authored(nav["starboard"]), self.design["starboard"], atol=POS_TOL)
        np.testing.assert_allclose(nav["port"], [-nav["starboard"][0], *nav["starboard"][1:]], atol=1e-9)
        lamp, lamp_range = self.design["lamp"]
        np.testing.assert_allclose(self.authored(nav["top_lamp"]), lamp, atol=POS_TOL)
        self.assertAlmostEqual(nav["top_lamp_range_m"], lamp_range)
        top = np.array(nav["top"])
        self.assertEqual(top[0], 0.0)
        self.assertLess(top[1], nav["top_lamp"][1], "the lamp stands over the top light")
        below = np.linalg.norm(self.xyz[:, [0, 2]] - top[[0, 2]], axis=1) < 1.5
        self.assertTrue(below.any())
        self.assertGreater(top[1], float(self.xyz[below, 1].max()), "the top light sits on the hull, not in it")
        self.assertLess(top[1], float(self.xyz[below, 1].max()) + 1.0)

    def test_rcs_ports_carry_pilot_terms(self) -> None:
        rcs = self.hp["rcs"]
        self.assertEqual(len(rcs), 11, "five drum ends (not the top drum's front, behind the plates), two disc flanks, four on the collar")
        self.assertEqual(len({r["name"] for r in rcs}), len(rcs))
        for port in rcs:
            self.assertTrue(set(port["tags"]) <= PILOT_TERMS, port)
            self.assertIn(port["pod"], ("l", "r"))
            self.assertAlmostEqual(float(np.linalg.norm(port["exhaust"])), 1.0, places=4)
            self.assertTrue(port["tags"], f"{port['name']} turns or moves the ship")
        k = self.design["engine"]
        engine_z = self.design["length"] - k * (ENGINE_M - 3.0)
        collar = [self.authored(r["position"]) for r in rcs if abs(self.authored(r["position"])[2] - engine_z) < 0.01]
        self.assertEqual(len(collar), 4)
        for p in collar:
            self.assertAlmostEqual(float(np.hypot(p[0], p[1])), 4.78 * k, delta=0.01)

    def test_turrets_as_tabulated(self) -> None:
        turrets = {t["name"]: t for t in self.hp["turrets"]}
        self.assertEqual(set(turrets), set(self.design["turrets"]))
        self.assertEqual(len(turrets), 2 if self.ASSET_ID == "saturn_3_freighter" else 3, "Q32: two flanks, a cargo dorsal")
        for name, t in turrets.items():
            self.assertEqual(t["up"], list(LEAD_TURRETS[name][1]) if name in LEAD_TURRETS else list(UP), name)
        for name, (position, up) in self.design["turrets"].items():
            t = turrets[name]
            np.testing.assert_allclose(self.authored(t["position"]), position, atol=POS_TOL, err_msg=name)
            self.assertEqual(t["up"], list(up), name)
            self.assertEqual(t["arc_deg"], 200.0, name)
            self.assertEqual(t["barrel_m"], 4.5, name)

    def test_each_turret_stands_on_the_hull(self) -> None:
        for t in self.hp["turrets"]:
            p, up = np.array(t["position"]), np.array(t["up"])
            d = self.xyz - p
            along = d @ up
            across = np.linalg.norm(d - np.outer(along, up), axis=1)
            seat = (across < 1.0) & (np.abs(along) < 2.0 * self.spacing)
            self.assertTrue(seat.any(), f"{t['name']}: hull surface under the mount")
            clear = (across < 1.5) & (along > 0.3)
            self.assertFalse(clear.any(), f"{t['name']}: nothing of the hull above the mount")

    def test_no_barrel_enters_the_hull_at_any_traverse(self) -> None:
        # Q32: the barrels sweep their whole arc (every azimuth, from the arc's lowest elevation to straight up) clear of the
        # hull's solids, the pads aside (the barrels' roots stand above their own pad).
        pieces = saturn.with_twins(saturn.assemble(saturn.VARIANTS[self.ASSET_ID], saturn.EA_CIVILIAN))
        solids = [p.solid for p in pieces if p.solid is not None and not p.name.startswith("pad_")]
        turret = saturn.TURRET
        for t in self.hp["turrets"]:
            up = np.array(t["up"], dtype=float)
            a = np.array([1.0, 0.0, 0.0]) if abs(up[0]) < 0.9 else np.array([0.0, 0.0, 1.0])
            a -= (a @ up) * up
            a /= np.linalg.norm(a)
            b = np.cross(up, a)
            pivot = self.authored(t["position"]) + turret.trunnion_height * up
            lowest = np.radians(90.0 - 0.5 * t["arc_deg"])
            az, el = np.meshgrid(np.radians(np.arange(0.0, 360.0, 5.0)), np.linspace(lowest, 0.5 * np.pi, 20))
            dirs = (np.cos(el)[..., None] * (np.cos(az)[..., None] * a + np.sin(az)[..., None] * b) + np.sin(el)[..., None] * up)
            points = (pivot + np.linspace(0.3, t["barrel_m"], 10)[:, None, None, None] * dirs).reshape(-1, 3)
            inside = np.zeros(len(points), dtype=bool)
            for solid in solids:
                inside |= solid.contains(points, 0.0)
            self.assertFalse(inside.any(), f"{t['name']}: {int(inside.sum())} barrel points inside the hull")

    # --- collision --------------------------------------------------------------------------------------------
    def test_collision_covers_the_visible_surface_and_stays_close(self) -> None:
        shapes = self.hp["collision"]
        names = [c["name"] for c in shapes]
        self.assertEqual(len(names), len(set(names)), "unique names")
        inside = np.zeros(len(self.xyz), dtype=bool)
        for c in shapes:
            inside |= inside_primitive(self.xyz, c, inflate=self.spacing)
        self.assertGreaterEqual(float(inside.mean()), 0.97, "AC12: at least 97 % of the visible surface")
        lo, hi = self.xyz.min(axis=0), self.xyz.max(axis=0)
        for c in shapes:
            basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
            np.testing.assert_allclose(basis.T @ basis, np.eye(3), atol=1e-4)
            self.assertAlmostEqual(float(np.linalg.det(basis)), 1.0, places=3)
            if c["type"] == "box":
                corners = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]) * 0.5 * np.array(c["size"])
                extent = corners @ basis.T + np.array(c["position"])
            else:
                self.assertEqual(c["axis"], "z")
                self.assertGreaterEqual(c["height"], 2.0 * c["radius"])
                half = 0.5 * c["height"] - c["radius"]
                ends = np.array([[0, 0, -half], [0, 0, half]]) @ basis.T + np.array(c["position"])
                extent = np.concatenate([ends - c["radius"], ends + c["radius"]])
            self.assertTrue(np.all(extent.min(axis=0) >= lo - 1.0) and np.all(extent.max(axis=0) <= hi + 1.0), c["name"])

    # --- turret model ------------------------------------------------------------------------------------------
    def test_turret_model_is_its_own_textured_mesh(self) -> None:
        t = self.manifest["turret"]
        self.assertEqual(set(t), {"obj", "mesh", "barrel_m", "trunnion", "muzzles"})
        assert_model_mesh(self, self.dir, t["mesh"], t["obj"], "turret")
        self.assertLessEqual(t["mesh"]["triangles"], TURRET_TRIANGLE_BUDGET)
        model = read_obj(self.dir / t["obj"]).vertices  # the turret frame: base on y = 0, the pivot at the origin
        self.assertAlmostEqual(float(model[:, 1].min()), 0.0, delta=0.05)
        self.assertAlmostEqual(float(np.ptp(model[:, 0])), 3.6, delta=0.1, msg="a base 3.6 m across")
        self.assertAlmostEqual(float(model[:, 2].min()), -4.5, delta=0.05, msg="barrels reach 4.5 m forward")
        np.testing.assert_allclose(model.min(axis=0), [-1.8, 0.0, -4.5], atol=0.05)
        assert_mirror_symmetric(self, model, "turret")
        self.assertEqual(t["barrel_m"], 4.5)
        muzzles = np.array(t["muzzles"])
        np.testing.assert_allclose(muzzles[:, 0], [-0.4, 0.4], atol=1e-6)
        np.testing.assert_allclose(muzzles[:, 2], [-4.5, -4.5], atol=1e-6)


class SaturnFourTransportTests(SaturnVariantChecks, unittest.TestCase):
    ASSET_ID = "saturn_4_transport"


class SaturnFourTankerTests(SaturnVariantChecks, unittest.TestCase):
    ASSET_ID = "saturn_4_tanker"


class SaturnEightTransportTests(SaturnVariantChecks, unittest.TestCase):
    ASSET_ID = "saturn_8_transport"


class SaturnEightTankerTests(SaturnVariantChecks, unittest.TestCase):
    ASSET_ID = "saturn_8_tanker"


class SaturnThreeFreighterTests(SaturnVariantChecks, unittest.TestCase):
    ASSET_ID = "saturn_3_freighter"


class SaturnFamilyTests(unittest.TestCase):
    """Q16 across the family: one lead ship, cargo in 100 m sections, lengths that follow from the parts."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.hp: dict[str, dict[str, Any]] = {}
        cls.offset: dict[str, np.ndarray] = {}
        for asset_id in DESIGN:
            directory = build_once(asset_id)
            cls.hp[asset_id] = json.loads((directory / saturn.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            cls.offset[asset_id] = np.array(manifest_io.read_manifest(directory)["centroid_offset"])

    def length(self, asset_id: str) -> float:
        return float(self.hp[asset_id]["length_m"])

    def test_the_five_ids_are_registered(self) -> None:
        self.assertEqual(set(saturn.BUILDERS), set(DESIGN))
        for asset_id in DESIGN:
            self.assertIs(ASSETS[asset_id], saturn.BUILDERS[asset_id])

    def test_length_is_lead_ship_plus_cargo(self) -> None:
        lead = LEAD_FORE_M + ENGINE_TAIL_M
        for asset_id, sections in (("saturn_4_transport", 1), ("saturn_4_tanker", 1), ("saturn_8_transport", 2), ("saturn_8_tanker", 2)):
            self.assertAlmostEqual(self.length(asset_id), lead + sections * SECTION_M, delta=0.02, msg=asset_id)
        for four, eight in (("saturn_4_transport", "saturn_8_transport"), ("saturn_4_tanker", "saturn_8_tanker")):
            self.assertAlmostEqual(self.length(eight) - lead, 2.0 * (self.length(four) - lead), delta=0.02, msg=eight)

    def test_the_saturn_3_ends_just_behind_its_pods(self) -> None:
        # Q20: a slim engine between the lower pods, under the top pod, its exhaust 1.5 m behind the pods' aft faces.
        self.assertAlmostEqual(self.length("saturn_3_freighter"), STACK_REAR_Z + 1.5, delta=0.02)
        hp, off = self.hp["saturn_3_freighter"], self.offset["saturn_3_freighter"]
        engine = next(c for c in hp["collision"] if c["name"].startswith("engine"))
        self.assertLess(engine["radius"], 3.5 - 0.5, "clear of the lower pods' inner faces at x 3.5")
        self.assertLess(engine["radius"], 4.52 - 0.5, "clear of the top pod's underside at y 4.52")
        self.assertGreater(engine["position"][2] + off[2] - 0.5 * engine["height"], 64.24, "under the top pod")

    def test_one_lead_ship_on_every_variant(self) -> None:
        def lead_points(asset_id: str) -> np.ndarray:
            hp, off = self.hp[asset_id], self.offset[asset_id]
            points = [hp["cockpit_camera"]["position"]] + [p["retro"]["position"] for p in hp["pods"]]
            points += [r["position"] for r in hp["rcs"] if np.array(r["position"])[2] + off[2] < 60.0]
            points += [t["position"] for t in hp["turrets"] if t["name"] in LEAD_TURRETS]
            return np.array(points) + off

        reference = lead_points("saturn_4_transport")
        self.assertEqual(len(reference), 1 + 2 + 7 + 2)  # camera, retros, the lead ship's seven RCS ports, two flank turrets
        for asset_id in DESIGN:
            np.testing.assert_allclose(lead_points(asset_id), reference, atol=POS_TOL, err_msg=asset_id)

    def test_the_default_atlas_lands_under_twenty_centimetres_a_texel(self) -> None:
        variant = saturn.VARIANTS["saturn_8_transport"]
        parts = [TexturedPart(p.part.mesh, phase_steps(p.name, False), (), p.name)
                 for p in saturn.with_twins(saturn.assemble(variant, saturn.EA_CIVILIAN))]  # fmt: skip
        self.assertLess(cv.texel_of(parts, cv.HULL_ATLAS_PX), TEXEL_MAX_M)

    def test_every_variant_has_the_same_engine_section(self) -> None:
        # The Saturn 3's is the same section scaled down (Q20).
        for asset_id, design in DESIGN.items():
            hp, off, length, k = self.hp[asset_id], self.offset[asset_id], self.length(asset_id), design["engine"]
            engine = next(c for c in hp["collision"] if c["name"].startswith("engine"))
            self.assertEqual(engine["type"], "capsule", asset_id)
            self.assertAlmostEqual(engine["radius"], 4.8 * k, places=4)
            self.assertAlmostEqual(engine["height"], 22.6 * k, places=4)
            self.assertAlmostEqual(engine["position"][2] + off[2], length - 0.5 * ENGINE_M * k, delta=0.02)


class SaturnDeterminismTests(unittest.TestCase):
    """Same seed, same bytes. Every variant shares the code path it checks."""

    def test_same_seed_gives_byte_identical_output(self) -> None:
        for asset_id in DESIGN:
            a = build_once(asset_id, "coarse_a", spacing=2.0)
            b = build_once(asset_id, "coarse_b", spacing=2.0)
            names = sorted(p.name for p in a.iterdir())
            self.assertEqual(names, sorted(p.name for p in b.iterdir()), asset_id)
            for name in names:
                self.assertEqual(sha256(a / name), sha256(b / name), f"{asset_id}/{name}")

    def test_a_different_seed_changes_the_wear_not_the_design(self) -> None:
        a = build_once("saturn_3_freighter", "coarse_a", spacing=2.0)
        with tempfile.TemporaryDirectory() as tmp:
            ASSETS["saturn_3_freighter"](BuildContext(Path(tmp), seed=7, options={**TEST_OPTIONS, "spacing": 2.0}))
            self.assertNotEqual(sha256(Path(tmp) / "saturn_3_freighter_albedo.png"), sha256(a / "saturn_3_freighter_albedo.png"))
            hp_a = json.loads((a / saturn.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            hp_b = json.loads((Path(tmp) / saturn.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            self.assertEqual([t["name"] for t in hp_a["turrets"]], [t["name"] for t in hp_b["turrets"]])
            self.assertEqual([c["name"] for c in hp_a["collision"]], [c["name"] for c in hp_b["collision"]])

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for bad in ({"spacing": 0.0}, {"spacing": -1.0}):
                with self.assertRaises(ValueError):
                    ASSETS["saturn_4_tanker"](BuildContext(Path(tmp), seed=1, options=bad))


class EaCivilianStyleTests(unittest.TestCase):
    def test_every_role_and_the_written_scheme(self) -> None:
        from tools.procgen.core.color import linear_to_srgb
        from tools.procgen.styles import REQUIRED_ROLES
        from tools.procgen.styles.ea_civilian import EA_CIVILIAN

        for role in REQUIRED_ROLES:
            self.assertIn(role, EA_CIVILIAN.materials)
        scheme = {
            "hull": 0xA4A7AA, "hull_panel": 0x8A8D90, "hull_patch": 0x72757A, "hull_dark": 0x4F5256,
            "stripe": 0xA8322C, "band_light": 0xDADCDE, "hazard": 0xD6AE2A, "hazard_dark": 0x262626,
            "disc_ring": 0x9A5248, "disc_fin": 0x3B3735, "disc_hub": 0xE2E3E4, "window": 0xF2E6C8,
            "nozzle": 0x4A4946, "nozzle_throat": 0x1C1B1A, "rcs": 0x6E6C68, "barrel": 0x5A5955, "bore": 0x101010,
            "canopy_frame": 0x4F5256,
        }  # fmt: skip
        for role, hex_rgb in scheme.items():
            # The scheme is what a lit face shows; the paint is the albedo that shows it (core/color.py, capture_albedo).
            np.testing.assert_allclose(EA_CIVILIAN.material(role).albedo, capture_albedo(hex_rgb), atol=1e-6, err_msg=role)
        self.assertAlmostEqual(EA_CIVILIAN.panel_size_m, 3.6)
        self.assertAlmostEqual(EA_CIVILIAN.panel_line_width_m, 0.4)
        # The texture pack (M5-T27, Achilles.jpg, Red Star 9.jpg, Epsilon.JPG): fine dark seams, a light patchwork, edges worn
        # to primer, not bare metal; the rim windows and the throats glow.
        self.assertLess(EA_CIVILIAN.panel_line_darkness, 0.8)
        self.assertGreater(EA_CIVILIAN.panel_tint_jitter, 0.0)
        self.assertEqual(EA_CIVILIAN.extra["bare_metal"], 0.0)
        self.assertGreater(EA_CIVILIAN.material("window").emissive_strength, 0.0)
        glow = linear_to_srgb(np.array(EA_CIVILIAN.material("nozzle_throat").emissive)) * 255.0
        np.testing.assert_allclose(glow, [0xDC, 0xE8, 0xFF], atol=1.0, err_msg="blue-white, Valjean.JPG")

    def test_a_hull_can_repaint_roles_without_clashing_names(self) -> None:
        from tools.procgen.styles.ea_civilian import EA_CIVILIAN, ea_civilian

        sand = ea_civilian({"hull": 0xB3A982})
        self.assertNotEqual(sand.material("hull"), EA_CIVILIAN.material("hull"))
        self.assertNotEqual(sand.material("hull").name, EA_CIVILIAN.material("hull").name)
        self.assertEqual(sand.material("stripe"), EA_CIVILIAN.material("stripe"))


def tearDownModule() -> None:
    _TMP.cleanup()


if __name__ == "__main__":
    unittest.main()
