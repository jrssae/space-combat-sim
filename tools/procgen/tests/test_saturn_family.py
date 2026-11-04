"""``saturn_family`` (AC12, Q16, D61): the five Saturn hulls against ``docs/assets-civilian.md`` and the design references.

Per variant: files, budgets, frames, mirror symmetry, the chunk partition of LOD1, collision coverage, the hardpoints contract
(with ``turrets[]``), the turret model, determinism. Across variants: the Q16 length rule and the shared lead ship. The
expected numbers below are typed in from the design documents, not read from the generator.
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
from tools.procgen.assets import saturn_family as saturn
from tools.procgen.parts import saturn as sp
from tools.procgen.core import frames, lighting
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.obj import read_obj
from tools.procgen.tests.mesh_checks import assert_painted_mesh
from tools.procgen.core.ply import read_ply

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
LEAD_TURRETS = {"dorsal_fwd": ((0.0, 3.8, 19.1), UP)}  # Q19: dorsal mounts only
SLIM = 2.8 / 4.8  # Q20: the Saturn 3's engine, the shared section scaled to fit between its lower pods
STACK_REAR_Z = 95.30  # the Saturn 3's pods' aft faces (64.24 + the shared pod's 31.06 m turned)

# docs/assets-civilian.md: budgets, hardpoints, chunks; docs/design-references.md: turrets.
DESIGN: dict[str, dict[str, Any]] = {
    "saturn_4_transport": {
        "length": 158.48,
        "engine": 1.0,
        "budget": (105_000, 155_000),
        "turrets": {**LEAD_TURRETS, "dorsal_aft": ((0.0, 9.3, 124.4), UP)},
        "starboard": (53.4, -7.29, 74.3),
        "lamp": ((0.0, 16.6, 99.4), 48.0),
        "chunks": ("bow", "hull", "engine", "pods_l", "pods_r"),
    },
    "saturn_4_tanker": {
        "length": 158.48,
        "engine": 1.0,
        "budget": (55_000, 85_000),
        "turrets": {**LEAD_TURRETS, "dorsal_aft": ((0.0, 9.3, 124.4), UP)},
        "starboard": (25.6, -13.53, 99.4),
        "lamp": ((0.0, 16.6, 99.4), 48.0),
        "chunks": ("bow", "spine", "engine", "tank_l", "tank_r"),
    },
    "saturn_8_transport": {
        "length": 258.48,
        "engine": 1.0,
        "budget": (170_000, 250_000),
        "turrets": {**LEAD_TURRETS, "dorsal_mid": ((0.0, 7.2, 149.4), UP)},
        "starboard": (53.4, -7.29, 74.3),
        "lamp": ((0.0, 21.5, 149.4), 78.0),
        "chunks": ("bow", "hull_1", "junction", "hull_2", "engine", "pods_1l", "pods_1r", "pods_2l", "pods_2r"),
    },
    "saturn_8_tanker": {
        "length": 258.48,
        "engine": 1.0,
        "budget": (95_000, 145_000),
        "turrets": {**LEAD_TURRETS, "dorsal_mid": ((0.0, 9.0, 149.4), UP)},
        "starboard": (25.6, -13.53, 99.4),
        "lamp": ((0.0, 21.5, 149.4), 78.0),
        "chunks": ("bow", "spine_1", "junction", "spine_2", "engine", "tanks_1l", "tanks_1r", "tanks_2l", "tanks_2r"),
    },
    "saturn_3_freighter": {
        "length": STACK_REAR_Z + 1.5,  # Q20: the bell's exit 1.5 m behind the pods
        "engine": SLIM,
        "budget": (60_000, 90_000),
        "turrets": dict(LEAD_TURRETS),
        "starboard": (46.8, -5.46, 79.7),
        "lamp": ((0.0, 27.8, 79.7), 36.0),
        "chunks": ("bow", "pod_top", "pod_l", "pod_r", "engine"),
    },
}
LOD_SHARES = {1: (0.20, 0.30), 2: (0.04, 0.09), 3: (0.01, 0.025)}
TURRET_BUDGET = (1_500, 3_500)

_TMP = tempfile.TemporaryDirectory()
_BUILDS: dict[tuple[str, str], Any] = {}


def build_once(asset_id: str, tag: str = "default", **options: Any) -> Path:
    """Builds a variant once per test run (the full builds are the slow part) and returns its directory."""
    key = (asset_id, tag)
    if key not in _BUILDS:
        out = Path(_TMP.name) / tag / asset_id
        _BUILDS[key] = ASSETS[asset_id](BuildContext(out, seed=42, options=options))
    return _BUILDS[key].out_dir


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def godot_xyz(path: Path) -> np.ndarray:
    return frames.flip_xy(read_ply(path).to_splats().xyz)


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
        cls.xyz = godot_xyz(cls.dir / cls.manifest["lods"][0]["file"])
        cls.splats = read_ply(cls.dir / cls.manifest["lods"][0]["file"]).to_splats()
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.spacing = float(cls.manifest["lods"][0]["spacing_m"])

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
        expected |= {lod["file"] for lod in self.manifest["lods"]} | {lod["lighting"] for lod in self.manifest["lods"]}
        for entry in self.hp["chunks"]:
            expected |= {entry["ply"], entry["lighting"], entry["obj"], entry["obj"].replace(".obj", ".mtl")}
        turret = self.manifest["turret"]
        expected |= {turret["ply"], turret["lighting"], turret["obj"], turret["obj"].replace(".obj", ".mtl")}
        expected |= {f"{aid}_mesh.glb", f"{aid}_turret_mesh.glb"}
        self.assertEqual(turret["ply"], f"{aid}_turret.ply")
        self.assertEqual({p.name for p in self.dir.iterdir()}, expected)
        self.assertEqual({p.name for p in self.out.files}, expected)

    def test_four_levels_with_their_records_and_the_budget(self) -> None:
        lods = self.manifest["lods"]
        aid = self.ASSET_ID
        self.assertEqual([lod["level"] for lod in lods], [0, 1, 2, 3])
        self.assertEqual([lod["file"] for lod in lods], [f"{aid}.ply", f"{aid}_lod1.ply", f"{aid}_lod2.ply", f"{aid}_lod3.ply"])
        self.assertEqual([lod["lighting"] for lod in lods], [lighting.lod_file_name(aid, k) for k in range(4)])
        lo, hi = self.design["budget"]
        self.assertTrue(lo <= lods[0]["splats"] <= hi, f"LOD0 {lods[0]['splats']} outside {self.design['budget']}")
        self.assertEqual(lods[0]["splats"], len(self.xyz))
        for level, (a, b) in LOD_SHARES.items():
            share = lods[level]["splats"] / lods[0]["splats"]
            self.assertTrue(a <= share <= b, (level, share))
            self.assertAlmostEqual(lods[level]["spacing_m"], (2**level) * self.spacing, places=6)
        self.assertEqual(self.out.warnings, ())

    def test_manifest_counts_chunks_and_files(self) -> None:
        m = self.manifest
        self.assertEqual(list(m["counts"]), list(self.design["chunks"]))
        self.assertEqual(sum(m["counts"].values()), m["lods"][0]["splats"], "LOD0 is the chunk groups concatenated")
        self.assertEqual(m["chunks"], list(self.design["chunks"]))
        self.assertEqual(m["chunk_lod"], 1)
        self.assertEqual(m["files"], {"fallback_mesh": f"{self.ASSET_ID}.obj", "paint_mesh": f"{self.ASSET_ID}_mesh.glb", "hardpoints": saturn.HARDPOINTS_NAME})
        self.assertEqual(m["dimensions_m"]["length"], self.hp["length_m"])

    def test_every_ply_has_matching_lighting_records(self) -> None:
        pairs = [(lod["file"], lod["lighting"]) for lod in self.manifest["lods"]]
        pairs += [(c["ply"], c["lighting"]) for c in self.hp["chunks"]]
        pairs.append((self.manifest["turret"]["ply"], self.manifest["turret"]["lighting"]))
        for ply_name, light_name in pairs:
            splats = read_ply(self.dir / ply_name).to_splats()
            records = lighting.read_lighting(self.dir / light_name)
            self.assertEqual(len(records), len(splats), light_name)
            cos = np.einsum("ij,ij->i", lighting.decode_normals(records), splats.normals)
            self.assertGreater(float(cos.min()), np.cos(np.radians(1.5)), light_name)

    # --- frames, symmetry ---------------------------------------------------------------------------
    def test_lod0_is_centred_and_its_box_is_the_manifest_box(self) -> None:
        np.testing.assert_allclose(self.xyz.mean(axis=0), [0.0, 0.0, 0.0], atol=2e-3)
        np.testing.assert_allclose(self.xyz.min(axis=0), self.manifest["aabb_min"], atol=2e-4)
        np.testing.assert_allclose(self.xyz.max(axis=0), self.manifest["aabb_max"], atol=2e-4)

    def test_lower_levels_are_centred_inside_the_lod0_box(self) -> None:
        lo, hi = np.array(self.manifest["aabb_min"]), np.array(self.manifest["aabb_max"])
        for lod in self.manifest["lods"][1:]:
            xyz = godot_xyz(self.dir / lod["file"])
            np.testing.assert_allclose(xyz.mean(axis=0), [0.0, 0.0, 0.0], atol=2e-3)
            # A coarse level only loses the extremes it misses; a frame slip would push it out of LOD0's box. Each piece
            # rounds to whole samples, so a level's centroid may wander a fraction of its spacing, never more.
            slip = max(0.3, 0.25 * lod["spacing_m"])
            self.assertTrue(np.all(xyz.min(axis=0) >= lo - slip) and np.all(xyz.max(axis=0) <= hi + slip), lod["level"])
            self.assertTrue(np.all(xyz.min(axis=0) <= lo + 2.0 * lod["spacing_m"]), lod["level"])
            self.assertTrue(np.all(xyz.max(axis=0) >= hi - 2.0 * lod["spacing_m"]), lod["level"])

    def test_every_level_is_mirror_symmetric_in_x(self) -> None:
        for lod in self.manifest["lods"]:
            xyz = godot_xyz(self.dir / lod["file"])
            np.testing.assert_allclose(sorted_rows(xyz), sorted_rows(xyz * np.array([-1.0, 1.0, 1.0])), atol=SYM_TOL)

    def test_splats_are_flat_opaque_discs(self) -> None:
        s = self.splats
        self.assertTrue(np.all(s.scale[:, 2] < s.scale[:, 0]))
        self.assertTrue(np.all(np.isfinite(s.rgb)))
        self.assertGreater(float(np.median(s.alpha)), 0.9)

    # --- chunks ----------------------------------------------------------------------------------------
    def test_chunks_partition_lod1_exactly(self) -> None:
        self.assertEqual([c["name"] for c in self.hp["chunks"]], list(self.design["chunks"]))
        lod1 = read_ply(self.dir / self.manifest["lods"][1]["file"]).to_splats()
        lod1_xyz = frames.flip_xy(lod1.xyz)
        start = 0
        for entry in self.hp["chunks"]:
            chunk = read_ply(self.dir / entry["ply"]).to_splats()
            n = entry["splats"]
            self.assertEqual(len(chunk), n, entry["name"])
            np.testing.assert_allclose(chunk.xyz.mean(axis=0), [0.0, 0.0, 0.0], atol=1e-3)
            body = frames.flip_xy(chunk.xyz) + np.array(entry["offset"])
            np.testing.assert_allclose(body, lod1_xyz[start : start + n], atol=1e-4)
            np.testing.assert_allclose(chunk.rgb, lod1.rgb[start : start + n], atol=1e-4)
            self.assertEqual(len(entry["joint"]), 3)
            start += n
        self.assertEqual(start, len(lod1), "the chunks hold exactly LOD1's splats")

    def test_paired_chunks_mirror_each_other(self) -> None:
        offsets = {c["name"]: np.array(c["offset"]) for c in self.hp["chunks"]}
        for name, offset in offsets.items():
            if name.endswith("r"):
                twin = offsets[name[:-1] + "l"]
                np.testing.assert_allclose(twin, offset * np.array([-1.0, 1.0, 1.0]), atol=1e-3)
                self.assertGreater(offset[0], 5.0, name)
            elif not name.endswith("l"):
                self.assertAlmostEqual(float(offset[0]), 0.0, places=3)

    def test_chunk_objs_are_valid_and_recentred(self) -> None:
        for entry in self.hp["chunks"]:
            obj = read_obj(self.dir / entry["obj"])
            self.assertGreater(len(obj.vertices), 0, entry["name"])
            chunk = godot_xyz(self.dir / entry["ply"])
            lo, hi = obj.vertices.min(axis=0), obj.vertices.max(axis=0)
            self.assertTrue(np.all(chunk.min(axis=0) >= lo - 0.3) and np.all(chunk.max(axis=0) <= hi + 0.3), entry["name"])

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
        # The game draws the mesh, not the symmetrised splats: its vertices must mirror too.
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

    def test_the_painted_mesh_is_the_fallback_mesh(self) -> None:
        # The ship as the game draws it (ships are meshes, the 2026-11-04 directive): the fallback mesh's triangles and paint.
        assert_painted_mesh(self, self.dir, self.manifest["paint_mesh"], f"{self.ASSET_ID}.obj", "hull")
        turret = self.manifest["turret"]
        assert_painted_mesh(self, self.dir, turret["paint_mesh"], turret["obj"], "turret")

    def test_fallback_mesh_matches_the_splat_bounds(self) -> None:
        v = read_obj(self.dir / f"{self.ASSET_ID}.obj").vertices
        np.testing.assert_allclose(v.min(axis=0), self.xyz.min(axis=0), atol=2.0 * self.spacing)
        np.testing.assert_allclose(v.max(axis=0), self.xyz.max(axis=0), atol=2.0 * self.spacing)

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

    def test_the_main_exits_are_the_rearmost_splats(self) -> None:
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
        self.assertTrue(1 <= len(turrets) <= 2, "Q19: dorsal mounts only")
        self.assertTrue(all(t["up"] == list(UP) for t in turrets.values()))
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
            self.assertTrue(seat.any(), f"{t['name']}: hull splats under the mount")
            clear = (across < 1.5) & (along > 0.3)
            self.assertFalse(clear.any(), f"{t['name']}: nothing of the hull above the mount")

    # --- collision --------------------------------------------------------------------------------------------
    def test_collision_covers_the_splats_and_stays_close(self) -> None:
        shapes = self.hp["collision"]
        names = [c["name"] for c in shapes]
        self.assertEqual(len(names), len(set(names)), "unique names")
        inside = np.zeros(len(self.xyz), dtype=bool)
        for c in shapes:
            inside |= inside_primitive(self.xyz, c, inflate=self.spacing)
        self.assertGreaterEqual(float(inside.mean()), 0.97, "AC12: at least 97 % of the splat centres")
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
    def test_turret_model_is_written_like_a_chunk(self) -> None:
        t = self.manifest["turret"]
        splats = read_ply(self.dir / t["ply"]).to_splats()
        self.assertEqual(len(splats), t["splats"])
        self.assertTrue(TURRET_BUDGET[0] <= t["splats"] <= TURRET_BUDGET[1], t["splats"])
        np.testing.assert_allclose(splats.xyz.mean(axis=0), [0.0, 0.0, 0.0], atol=1e-3)
        model = frames.flip_xy(splats.xyz) + np.array(t["offset"])  # back in the turret frame: base on y = 0
        self.assertAlmostEqual(float(model[:, 1].min()), 0.0, delta=0.05)
        self.assertAlmostEqual(float(np.ptp(model[:, 0])), 3.6, delta=0.1, msg="a base 3.6 m across")
        self.assertAlmostEqual(float(model[:, 2].min()), -4.5, delta=0.05, msg="barrels reach 4.5 m forward")
        self.assertEqual(t["barrel_m"], 4.5)
        muzzles = np.array(t["muzzles"])
        np.testing.assert_allclose(muzzles[:, 0], [-0.4, 0.4], atol=1e-6)
        np.testing.assert_allclose(muzzles[:, 2], [-4.5, -4.5], atol=1e-6)
        obj = read_obj(self.dir / t["obj"])
        np.testing.assert_allclose(obj.vertices.min(axis=0) + t["offset"], [-1.8, 0.0, -4.5], atol=0.05)


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
        self.assertEqual(len(reference), 1 + 2 + 7 + 1)  # camera, retros, the lead ship's seven RCS ports, dorsal_fwd
        for asset_id in DESIGN:
            np.testing.assert_allclose(lead_points(asset_id), reference, atol=POS_TOL, err_msg=asset_id)

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
    """Same seed, same bytes; a coarse spacing keeps it quick. Every variant shares the code path it checks."""

    def test_same_seed_gives_byte_identical_output(self) -> None:
        for asset_id in DESIGN:
            a = build_once(asset_id, "coarse_a", spacing=2.0)
            b = build_once(asset_id, "coarse_b", spacing=2.0)
            names = sorted(p.name for p in a.iterdir())
            self.assertEqual(names, sorted(p.name for p in b.iterdir()), asset_id)
            for name in names:
                self.assertEqual(sha256(a / name), sha256(b / name), f"{asset_id}/{name}")

    def test_a_different_seed_moves_the_splats_not_the_design(self) -> None:
        a = build_once("saturn_3_freighter", "coarse_a", spacing=2.0)
        with tempfile.TemporaryDirectory() as tmp:
            ASSETS["saturn_3_freighter"](BuildContext(Path(tmp), seed=7, options={"spacing": 2.0}))
            self.assertNotEqual(sha256(Path(tmp) / "saturn_3_freighter.ply"), sha256(a / "saturn_3_freighter.ply"))
            hp_a = json.loads((a / saturn.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            hp_b = json.loads((Path(tmp) / saturn.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            self.assertEqual([t["name"] for t in hp_a["turrets"]], [t["name"] for t in hp_b["turrets"]])
            self.assertEqual([c["name"] for c in hp_a["collision"]], [c["name"] for c in hp_b["collision"]])

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for bad in ({"spacing": 0.0}, {"overlap": -1.0}, {"thickness": 0}):
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
            srgb = linear_to_srgb(np.array(EA_CIVILIAN.material(role).albedo)) * 255.0
            expected = [(hex_rgb >> 16) & 255, (hex_rgb >> 8) & 255, hex_rgb & 255]
            np.testing.assert_allclose(srgb, expected, atol=1.0, err_msg=role)
        self.assertAlmostEqual(EA_CIVILIAN.panel_size_m, 3.6)
        self.assertAlmostEqual(EA_CIVILIAN.panel_line_width_m, 0.4)
        # No painted grid (the maintainer, 2026-11-04).
        self.assertEqual((EA_CIVILIAN.panel_line_darkness, EA_CIVILIAN.panel_tint_jitter), (1.0, 0.0))

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
