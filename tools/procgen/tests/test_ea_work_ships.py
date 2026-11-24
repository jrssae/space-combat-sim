"""``ea_panama`` and ``ea_construction_tender`` (M10-T51 and M10-T55): files, the mesh contract with both texture sets, class
budgets, sizes and frames, outward faces, the lopsided and the mirrored pieces, chunk cuts, collision coverage, the
hardpoint contract, the loadout (unarmed, Q53), the chosen looks and determinism.
The expected numbers are typed in from docs/design-references.md ("EA Panama-class transport", "EA construction tender")
and docs/assets-capital.md ("M10 lengths (T01)", "Class budgets"), not read from the generators.
"""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import ea_shuttles as es
from tools.procgen.assets import ea_work_ships as ws
from tools.procgen.core import civilian as cv
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.color import capture_albedo
from tools.procgen.core.budgets import CLASS_BUDGETS, LOW_SHRINK, low_set_mb, over_budget, texture_mb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.image import read_png
from tools.procgen.core.textured_mesh import TexturedPart, phase_steps
from tools.procgen.styles.ea_work_ships import PANAMA_LOOK, TENDER_LOOK
from tools.procgen.tests.mesh_checks import TEST_OPTIONS, assert_chunks_cut_the_hull, assert_hull_mesh, glowing_points

PILOT_TERMS = {
    "sway_left", "sway_right", "heave_up", "heave_down", "pitch_up", "pitch_down",
    "yaw_left", "yaw_right", "roll_left", "roll_right",
}  # fmt: skip
ROOT = Path(__file__).resolve().parents[3]
B5_BAY_CORE_M = (45.5, 30.0)  # the main docking bay's core, wide and tall (docs/assets-capital.md, "M10 lengths (T01)")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inside_primitive(points: np.ndarray, c: dict, inflate: float) -> np.ndarray:
    basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
    local = (points - np.array(c["position"])) @ basis
    if c["type"] == "box":
        return np.all(np.abs(local) <= 0.5 * np.array(c["size"]) + inflate, axis=1)
    half = 0.5 * c["height"] - c["radius"]
    along = np.clip(local[:, 2], -half, half)
    axis_point = np.column_stack([np.zeros_like(along), np.zeros_like(along), along])
    return np.linalg.norm(local - axis_point, axis=1) <= c["radius"] + inflate


def mirror_gap(vertices: np.ndarray) -> float:
    """How far the worst vertex is from its nearest twin across x = 0 (the round parts' vertices do not survive rounding)."""
    points = np.unique(np.round(vertices, 6), axis=0)
    twins = points * np.array([-1.0, 1.0, 1.0])
    worst = 0.0
    for start in range(0, len(twins), 512):
        gap = np.linalg.norm(twins[start : start + 512, None, :] - points[None, :, :], axis=2).min(axis=1)
        worst = max(worst, float(gap.max()))
    return worst


class WorkShipChecks:
    """The checks both hulls share; a subclass names the craft and its expected numbers."""

    CRAFT: es.Craft
    BUILD = None
    LENGTH: float
    SPAN: float
    HEIGHT: float
    SHIP_CLASS: str
    ATLAS_PX: int
    TEXEL_MAX_M: float
    CHUNKS: tuple[str, ...]
    THRUST_Y: float
    HULL_POINTS: int
    PAINT_SRGB: int  # the chosen look's hull colour
    NO_HIT_VOLUME: tuple[str, ...] = ()  # pieces too thin to be hit: aerials

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = cls.BUILD(BuildContext(cls.dir_a, seed=42, options=TEST_OPTIONS))
        cls.out_b = cls.BUILD(BuildContext(cls.dir_b, seed=42, options=TEST_OPTIONS))
        cls.asset_id = cls.CRAFT.asset_id
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.hp = json.loads((cls.dir_a / es.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.pieces = cv.scaled_pieces(cls.CRAFT.assemble(cls.CRAFT.look.style), cls.CRAFT.scale)  # at the built size
        cls.spacing = float(cls.manifest["surface_spacing_m"])
        solid = [p for p in cls.pieces if not p.name.startswith(cls.NO_HIT_VOLUME)] if cls.NO_HIT_VOLUME else cls.pieces
        sampled = cv.sample_pieces(solid, BuildContext(cls.dir_a, seed=42), cls.spacing, buried_margin=es.BURIED_MARGIN_M * cls.CRAFT.scale)
        cls.xyz = np.concatenate([s.samples.positions for s in sampled]) - cls.offset  # the visible surface, body frame

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def authored(self, v: list[float]) -> np.ndarray:
        """A hardpoint back in the design references' frame (the bow at z = 0, x and y from the box centre)."""
        return np.array(v) + self.offset

    # --- files, manifest, budgets ------------------------------------------------------------------------------------
    def test_registered_and_named(self) -> None:
        self.assertIs(ASSETS[self.asset_id], self.BUILD)
        self.assertEqual(self.out_a.asset_id, self.asset_id)
        self.assertEqual(self.out_a.warnings, ())

    def test_all_files_are_written_and_listed(self) -> None:
        names = {p.name for p in self.out_a.files}
        stem = self.asset_id
        expected = {"hardpoints.json", "manifest.json", f"{stem}.glb", f"{stem}.obj"}
        expected |= {f"{stem}_{k}.png" for k in ("albedo", "normal", "orm", "emissive")}
        expected |= {f"{stem}_{k}_low.png" for k in ("albedo", "normal", "orm", "emissive")}
        expected |= {f"{stem}_chunk_{c}.{ext}" for c in self.CHUNKS for ext in ("obj", "glb")}
        self.assertTrue(expected <= names, sorted(expected - names))
        self.assertFalse([n for n in names if "turret" in n], "no turret")
        for p in self.out_a.files:
            self.assertTrue(p.is_file(), p)

    def test_the_hull_is_its_textured_mesh(self) -> None:
        assert_hull_mesh(self, self.dir_a, self.manifest, f"{self.asset_id}.obj")
        self.assertEqual((self.manifest["asset_id"], self.manifest["frame"], self.manifest["seed"]), (self.asset_id, "godot", 42))

    def test_the_low_texture_set_is_a_mip_level_down(self) -> None:
        surface = self.manifest["mesh"]["surfaces"][0]
        low = surface["detail"]["low"]
        self.assertEqual(low, {k: f"{self.asset_id}_{k}_low.png" for k in ("albedo", "normal", "orm", "emissive")})
        for key, file in low.items():
            high = read_png(self.dir_a / surface[key])
            self.assertEqual(read_png(self.dir_a / file).shape[:2], (high.shape[0] // LOW_SHRINK, high.shape[1] // LOW_SHRINK), key)

    def test_the_hull_is_inside_its_class_budget(self) -> None:
        budget = self.manifest["budget"]
        self.assertEqual((budget["class"], budget["triangles"]), (self.SHIP_CLASS, self.manifest["mesh"]["triangles"]))
        self.assertEqual((self.CRAFT.ship_class, self.CRAFT.atlas_px), (self.SHIP_CLASS, self.ATLAS_PX))
        self.assertEqual(self.ATLAS_PX, CLASS_BUDGETS[self.SHIP_CLASS].atlas_px, "the class's one atlas")
        atlas = [self.ATLAS_PX]  # the default build's one atlas; the test build's is smaller
        self.assertEqual(over_budget(self.SHIP_CLASS, budget["triangles"], texture_mb(atlas), low_set_mb(atlas)), [])
        built = [TEST_OPTIONS["atlas_px"]]
        self.assertAlmostEqual(budget["texture_mb"], texture_mb(built), places=2, msg="the manifest records this build's")
        self.assertAlmostEqual(budget["texture_mb_low"], low_set_mb(built), places=2)

    def test_the_default_atlas_texel(self) -> None:
        parts = [TexturedPart(p.part.mesh, phase_steps(p.name, False), (), p.name) for p in cv.with_twins(self.pieces)]
        self.assertLess(cv.texel_of(parts, self.ATLAS_PX), self.TEXEL_MAX_M)

    # --- size, frame, shape ----------------------------------------------------------------------------------------------
    def test_dimensions_match_the_reference(self) -> None:
        dims = self.manifest["dimensions_m"]
        self.assertAlmostEqual(dims["length"], self.LENGTH, delta=0.02)
        self.assertAlmostEqual(dims["span"], self.SPAN, delta=0.02 * self.SPAN)
        self.assertAlmostEqual(dims["height"], self.HEIGHT, delta=0.03 * self.HEIGHT)
        self.assertEqual((self.hp["length_m"], self.hp["span_m"], self.hp["height_m"]), (dims["length"], dims["span"], dims["height"]))

    def test_the_authored_frame_is_the_references(self) -> None:
        lo = np.array(self.manifest["aabb_min"]) + self.offset
        hi = np.array(self.manifest["aabb_max"]) + self.offset
        self.assertAlmostEqual(lo[2], 0.0, delta=0.01, msg="the bow at z = 0")
        self.assertAlmostEqual(hi[2], self.LENGTH, delta=0.02)
        self.assertAlmostEqual(lo[0] + hi[0], 0.0, delta=0.02 * self.SPAN, msg="x centred on the reference's box")
        self.assertAlmostEqual(lo[1] + hi[1], 0.0, delta=0.03 * self.HEIGHT, msg="y centred on the reference's box")
        self.assertAlmostEqual(self.offset[0], 0.0, places=6, msg="the body origin stays on the box's centre plane")

    def test_every_piece_faces_outward(self) -> None:
        for p in self.pieces:
            a, b, c = p.part.mesh.corners()
            volume = float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum()) / 6.0
            self.assertGreater(volume, 0.0, p.name)

    def test_the_cockpit_is_forward_and_the_engines_aft(self) -> None:
        eye = self.authored(self.hp["cockpit_camera"]["position"])
        self.assertLess(eye[2], 0.3 * self.LENGTH)
        self.assertEqual(self.hp["cockpit_camera"]["forward"], [0.0, 0.0, -1.0])
        for pod in self.hp["pods"]:
            self.assertGreater(self.authored(pod["main"]["position"])[2], 0.9 * self.LENGTH, pod["name"])

    def test_the_engines_glow(self) -> None:
        glow = glowing_points(self.dir_a, self.manifest["mesh"]) + self.offset
        self.assertTrue(bool(np.any(glow[:, 2] > 0.9 * self.LENGTH)), "the bells' throats are lit")

    # --- chunks and hardpoints ---------------------------------------------------------------------------------------------
    def test_chunks_cut_the_hull_and_have_joints(self) -> None:
        assert_chunks_cut_the_hull(self, self.dir_a, self.manifest, self.hp, self.CHUNKS)
        lo, hi = np.array(self.manifest["aabb_min"]), np.array(self.manifest["aabb_max"])
        for entry in self.hp["chunks"]:
            joint = np.array(entry["joint"])
            self.assertTrue(np.all(joint >= lo) and np.all(joint <= hi), entry["name"])

    def test_hardpoints_schema(self) -> None:
        keys = {"asset_id", "generator_version", "frame", "units", "length_m", "span_m", "height_m", "mass_kg",
                "inertia_estimate_kg_m2", "center_of_mass", "cockpit_camera", "chase_anchor", "muzzles", "pods", "rcs",
                "collision", "nav_lights", "turrets", "docking_ports", "chunks"}  # fmt: skip
        self.assertEqual(set(self.hp), keys)
        self.assertEqual((self.hp["muzzles"], self.hp["turrets"]), ([], []), "unarmed (Q49)")
        self.assertGreater(self.hp["mass_kg"], 0.0)
        names = [c["name"] for c in self.hp["collision"]]
        self.assertEqual(len(names), len(set(names)), "unique collision names")

    def test_two_pods_fire_aft_on_the_thrust_line(self) -> None:
        self.assertEqual([pod["side"] for pod in self.hp["pods"]], ["left", "right"])
        for pod in self.hp["pods"]:
            main = self.authored(pod["main"]["position"])
            self.assertEqual(pod["main"]["exhaust"], [0.0, 0.0, 1.0], pod["name"])
            self.assertEqual(pod["retro"]["exhaust"], [0.0, 0.0, -1.0], pod["name"])
            self.assertAlmostEqual(main[1], self.THRUST_Y, places=4, msg=pod["name"])
            self.assertEqual(pod["side"], "left" if main[0] < 0.0 else "right", pod["name"])
        com = self.authored(self.hp["center_of_mass"])
        self.assertAlmostEqual(com[1], self.THRUST_Y, places=4, msg="main thrust makes no pitch torque")
        self.assertTrue(0.3 * self.LENGTH < com[2] < 0.8 * self.LENGTH, com)

    def test_cosmetic_rcs_ports_carry_pilot_terms(self) -> None:
        ports = {port["name"]: port for port in self.hp["rcs"]}
        self.assertEqual(len(ports), len(self.hp["rcs"]), "unique names")
        self.assertGreaterEqual(len(ports), 8)
        for name, port in ports.items():
            self.assertTrue(port["tags"], name)
            self.assertTrue(set(port["tags"]) <= PILOT_TERMS, name)
            self.assertAlmostEqual(float(np.linalg.norm(port["exhaust"])), 1.0, places=4, msg=name)

    def test_nav_lights_port_on_the_left_and_the_lamp_on_top(self) -> None:
        lights = self.hp["nav_lights"]
        self.assertLess(lights["port"][0], 0.0)
        self.assertGreater(lights["starboard"][0], 0.0)
        self.assertGreater(lights["top_lamp"][1], lights["top"][1])
        self.assertEqual(lights["cabin"], self.hp["cockpit_camera"]["position"])

    def test_collision_primitives_cover_the_visible_surface_and_stay_close(self) -> None:
        inside = np.zeros(len(self.xyz), dtype=bool)
        for c in self.hp["collision"]:
            inside |= inside_primitive(self.xyz, c, inflate=self.spacing)
        missed = self.xyz[~inside] + self.offset
        self.assertTrue(bool(inside.all()), f"every visible surface sample; {len(missed)} missed (authored frame): {np.round(missed[:10], 2).tolist()}")
        lo, hi = self.xyz.min(axis=0), self.xyz.max(axis=0)
        for c in self.hp["collision"]:
            basis = np.array([c["basis"][k] for k in ("x", "y", "z")]).T
            np.testing.assert_allclose(basis.T @ basis, np.eye(3), atol=1e-4, err_msg=c["name"])
            self.assertAlmostEqual(float(np.linalg.det(basis)), 1.0, places=3, msg=c["name"])
            if c["type"] == "box":
                corners = np.array([[a, b, d] for a in (-1, 1) for b in (-1, 1) for d in (-1, 1)]) * 0.5 * np.array(c["size"])
                extent = corners @ basis.T + np.array(c["position"])
            else:
                half = 0.5 * c["height"] - c["radius"]
                ends = np.array([[0, 0, -half], [0, 0, half]]) @ basis.T + np.array(c["position"])
                extent = np.concatenate([ends - c["radius"], ends + c["radius"]])
            self.assertTrue(np.all(extent.min(axis=0) >= lo - 0.5) and np.all(extent.max(axis=0) <= hi + 0.5), c["name"])

    def test_the_loadout_is_this_hull_unarmed(self) -> None:
        entry = json.loads((ROOT / "data" / "capitals" / "loadouts.json").read_text(encoding="utf-8"))["hulls"][self.asset_id]
        self.assertEqual((entry["weapons"], entry["interceptors"], entry["launches"], entry["lays_mines"]), ({}, {}, {}, None), "unarmed (Q53)")
        self.assertEqual(entry["class"], self.SHIP_CLASS, "the loadout's class is the budget's")
        self.assertEqual((entry["hull"], entry["jump"]), (self.HULL_POINTS, "gate"))
        spec = (ROOT / "assets" / "ships" / f"{self.asset_id}.tres").read_text(encoding="utf-8")
        self.assertIn(f'asset_id = "{self.asset_id}"', spec)
        self.assertIn(f"hull_max = {float(self.HULL_POINTS)}", spec, "the ShipSpec carries the loadout's hull points")

    # --- looks, determinism, options -----------------------------------------------------------------------------------------
    def test_the_look_is_the_maintainers_choice(self) -> None:
        look = self.CRAFT.look
        self.assertEqual(look.style.name, self.asset_id)
        np.testing.assert_allclose(look.style.material("hull").albedo, capture_albedo(self.PAINT_SRGB), atol=1e-9)

    def test_a_different_seed_changes_the_wear_but_not_the_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = self.BUILD(BuildContext(Path(tmp), seed=7, options=TEST_OPTIONS))
            albedo = self.manifest["mesh"]["surfaces"][0]["albedo"]
            self.assertNotEqual(sha256(Path(tmp) / albedo), sha256(self.dir_a / albedo))
            self.assertEqual(other.manifest["dimensions_m"], self.manifest["dimensions_m"])
            self.assertEqual(other.manifest["mesh"]["triangles"], self.manifest["mesh"]["triangles"])
            hp = json.loads((Path(tmp) / es.HARDPOINTS_NAME).read_text(encoding="utf-8"))
            self.assertEqual([c["name"] for c in hp["collision"]], [c["name"] for c in self.hp["collision"]])

    def test_same_seed_gives_byte_identical_output(self) -> None:
        for out in self.out_a.files:
            self.assertEqual(sha256(out), sha256(self.dir_b / out.name), out.name)

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for bad in (0.0, -1.0):
                with self.assertRaises(ValueError):
                    self.BUILD(BuildContext(Path(tmp), options={"spacing": bad}))


class EaPanamaTests(WorkShipChecks, unittest.TestCase):
    CRAFT = ws.PANAMA
    BUILD = staticmethod(ws.build_panama)
    K = 20.0 / 29.607  # Q66's height over the modelled hull's (Q49's 180 m)
    LENGTH, SPAN, HEIGHT = 180.0 * K, 44.86 * K, 20.0  # Q66's height and the reference's box at it
    SHIP_CLASS, ATLAS_PX, TEXEL_MAX_M = "cruiser", 4096, 0.06
    CHUNKS = ("bow", "hold_fore", "hold_aft", "stern")
    THRUST_Y = -0.175 * K  # the height the section is mirrored about
    HULL_POINTS = 185  # Q74: T51's 600 by the volume left
    PAINT_SRGB = 0x8A7F72  # the maintainer's choice (2026-11-21): brown-grey patchwork, pale roof, dark tanks
    NO_HIT_VOLUME = ("aerials",)

    def test_the_look_is_the_patchwork_with_a_pale_roof(self) -> None:
        self.assertIs(self.CRAFT.look, PANAMA_LOOK)
        self.assertEqual((PANAMA_LOOK.bands, PANAMA_LOOK.stripes), ((), None))
        self.assertGreater(PANAMA_LOOK.plate_tone, 0.15, "plates wander strongly in tone")
        paint = {role: PANAMA_LOOK.style.material(role).albedo for role in ("hull", "hull_patch", "hazard")}
        self.assertGreater(sum(paint["hull_patch"]), sum(paint["hull"]), "the roof is paler than the sides")
        self.assertLess(sum(paint["hazard"]), sum(paint["hull"]), "the tanks are dark")

    def test_only_the_bells_throats_are_lit_not_their_insides(self) -> None:
        glow = glowing_points(self.dir_a, self.manifest["mesh"]) + self.offset
        stern = glow[glow[:, 2] > 150.0 * self.K]
        self.assertGreater(len(stern), 0)
        self.assertLess(float(stern[:, 2].max()), 176.5 * self.K, "the glow stays deep in each bell, a collar round its throat")

    def test_every_piece_is_authored_where_it_sits(self) -> None:
        self.assertEqual({p.side for p in self.pieces}, {cv.LONE}, "a lopsided hull: nothing mirrored, nothing symmetrised")
        self.assertEqual(len(cv.with_twins(self.pieces)), len(self.pieces))

    def test_the_hull_is_lopsided_as_the_reference(self) -> None:
        by_name = {p.name: p.part.mesh.vertices for p in self.pieces}
        spine = by_name["bow_spine"]
        self.assertLess(float(spine[:, 0].max()), -10.0 * self.K, "the bow spine stands on the port side")
        self.assertAlmostEqual(float(spine[:, 2].min()), 0.0, places=6, msg="and leads the ship")
        hold = by_name["hold_fore"]
        port, starboard = hold[hold[:, 0] < -17.0 * self.K], hold[hold[:, 0] > 17.0 * self.K]
        self.assertGreater(float(np.ptp(port[:, 1])), 25.0 * self.K, "tall to port")
        self.assertLess(float(np.ptp(starboard[:, 1])), 8.0 * self.K, "a thin edge to starboard")

    def test_the_section_fits_babylon_5s_bay_core(self) -> None:
        hull = np.concatenate([p.part.mesh.vertices for p in self.pieces if not p.name.startswith("aerials")])
        self.assertLess(float(np.ptp(hull[:, 0])), B5_BAY_CORE_M[0])
        self.assertLess(float(np.ptp(hull[:, 1])), B5_BAY_CORE_M[1])

    def test_two_engines_either_side_of_the_core(self) -> None:
        mains = {pod["name"]: self.authored(pod["main"]["position"]) for pod in self.hp["pods"]}
        self.assertAlmostEqual(mains["l"][0], -11.7 * self.K, places=3)
        self.assertAlmostEqual(mains["r"][0], 11.5 * self.K, places=3)
        com = self.authored(self.hp["center_of_mass"])
        self.assertLess(abs(com[0] - 0.5 * (mains["l"][0] + mains["r"][0])), 0.2 * self.K, "between the engines: no yaw torque to speak of")

    def test_the_port_face_and_the_bow_carry_lit_ports(self) -> None:
        glow = glowing_points(self.dir_a, self.manifest["mesh"]) + self.offset
        face = glow[(glow[:, 0] < -20.0 * self.K) & (glow[:, 2] > 55.0 * self.K) & (glow[:, 2] < 131.0 * self.K)]
        self.assertGreater(len(face), 0, "rows of ports along the port face")
        self.assertGreater(len(glow[glow[:, 2] < 21.0 * self.K]), 0, "and on the bow spine")

    def test_the_cargo_lock_is_on_the_port_side_aft(self) -> None:
        (port,) = self.hp["docking_ports"]
        self.assertEqual((port["name"], port["out"]), ("port_lock", [-1.0, 0.0, 0.0]))
        at = self.authored(port["position"])
        self.assertLess(at[0], -22.0 * self.K)
        self.assertTrue(131.0 * self.K < at[2] < 154.5 * self.K)


class EaConstructionTenderTests(WorkShipChecks, unittest.TestCase):
    CRAFT = ws.TENDER
    BUILD = staticmethod(ws.build_tender)
    K = 8.0 / 50.0  # Q65's length over Q49's
    LENGTH, SPAN, HEIGHT = 8.0, 69.74 * K, 24.0 * K  # Q65's length and the reference's box at it
    SHIP_CLASS, ATLAS_PX, TEXEL_MAX_M = "small_craft", 2048, 0.08
    CHUNKS = ("body", "stern", "boom_l", "boom_r", "claws_l", "claws_r")
    THRUST_Y = 4.646 * K  # the pods' axes
    HULL_POINTS = 50  # Q65: an 8 m work craft
    PAINT_SRGB = 0xC29A2C  # the maintainer's choice (2026-11-21): ochre all over, yellow claws striped black

    def test_the_look_is_ochre_with_striped_claws(self) -> None:
        self.assertIs(self.CRAFT.look, TENDER_LOOK)
        self.assertEqual(TENDER_LOOK.stripes, 0x1E1E1E)
        albedo = read_png(self.dir_a / self.manifest["mesh"]["surfaces"][0]["albedo"])[..., :3].astype(int)
        yellow = (albedo[..., 0] > 40) & (albedo[..., 0] > albedo[..., 1]) & (albedo[..., 1] > 2 * albedo[..., 2])
        black = albedo.max(axis=2) < 24
        self.assertGreater(float(yellow.mean()), 0.2, "ochre and yellow paint (the atlas holds albedo, darker than the paint looks lit)")
        self.assertGreater(float(black.mean()), 0.005, "black stripes and dark machinery")

    def test_the_body_boom_and_pods_are_mirror_symmetric(self) -> None:
        keep = [p.part.mesh.vertices for p in cv.with_twins(self.pieces) if p.side != cv.LONE]
        self.assertLess(mirror_gap(np.concatenate(keep)), 1e-6, "every vertex has its twin across x = 0")
        lone = {p.name for p in self.pieces if p.side == cv.LONE}
        self.assertEqual(lone, {"shoulders", "gear", "claw_up_r", "claw_down_r", "claw_up_l", "claw_down_l"}, "what the reference has lopsided")

    def test_four_claws_stand_as_the_reference_poses_them(self) -> None:
        claws = {p.name: p for p in self.pieces if p.name.startswith("claw_")}
        self.assertEqual(set(claws), {"claw_up_r", "claw_down_r", "claw_up_l", "claw_down_l"})
        self.assertEqual({p.side for p in claws.values()}, {cv.LONE})
        tips = {name: p.part.anchor("tip") for name, p in claws.items()}
        for name, tip in tips.items():
            self.assertLess(tip.direction[2], -0.8, f"{name} reaches forward")
            self.assertEqual(tip.position[0] > 0.0, name.endswith("_r"), name)
        splay = {name: abs(float(tip.direction[0])) for name, tip in tips.items()}
        self.assertGreater(splay["claw_up_l"], splay["claw_up_r"] + 0.05, "the port claws are splayed wider than the starboard ones")

    def test_a_claw_has_three_blades(self) -> None:
        boxes = {c["name"][: len("claw_up_r_blade0")] for c in self.hp["collision"] if c["name"].startswith("claw_up_r_blade")}
        self.assertEqual(boxes, {"claw_up_r_blade0", "claw_up_r_blade1", "claw_up_r_blade2"})

    def test_the_pods_are_at_the_booms_tips_and_drive_the_ship(self) -> None:
        mains = {pod["name"]: self.authored(pod["main"]["position"]) for pod in self.hp["pods"]}
        self.assertAlmostEqual(mains["r"][0], 29.92 * self.K, places=3)
        self.assertAlmostEqual(mains["l"][0], -29.92 * self.K, places=3)
        for pod in self.hp["pods"]:
            self.assertLess(self.authored(pod["retro"]["position"])[2], 35.0 * self.K, "the forward bells brake")

    def test_the_landing_gear_stands_to_port_of_the_centre_line(self) -> None:
        gear = next(p for p in self.pieces if p.name == "gear")
        self.assertEqual(gear.side, cv.LONE)
        feet = gear.part.mesh.vertices[gear.part.mesh.vertices[:, 1] < -11.6 * self.K]
        self.assertAlmostEqual(float(feet[:, 1].min()), -12.0 * self.K, places=2, msg="the feet are the lowest point")
        self.assertAlmostEqual(0.5 * float(feet[:, 0].min() + feet[:, 0].max()), -0.95 * self.K, places=2)

    def test_no_docking_port(self) -> None:
        self.assertEqual(self.hp["docking_ports"], [])


if __name__ == "__main__":
    unittest.main()
