"""``centauri_shuttle`` and ``minbari_flyer`` (M10-T58, stage 1): files, the mesh contract with both texture sets, the small-craft
budget, sizes and frames, outward faces, symmetry, chunk cuts, the hardpoint contract, the three looks and determinism.
The expected numbers are typed in from docs/design-references.md ("Centauri shuttle", "Minbari Flyer") and M10 Q67, not read
from the generators.
"""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import centauri_shuttle as cs
from tools.procgen.assets import ea_shuttles as es
from tools.procgen.assets import minbari_flyer as mf
from tools.procgen.assets import minbari_flyer_pattern as mfp
from tools.procgen.parts import centauri_shuttle as cp
from tools.procgen.parts import minbari_flyer as mp
from tools.procgen.core import civilian as cv
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.budgets import LOW_SHRINK, low_set_mb, over_budget, texture_mb
from tools.procgen.core.color import capture_albedo
from tools.procgen.core.context import BuildContext
from tools.procgen.core.image import read_png
from tools.procgen.core.obj import read_obj
from tools.procgen.core.seams import Hexes
from tools.procgen.core.textured_mesh import TexturedPart, phase_steps
from tools.procgen.styles import centauri_shuttle as cs_style
from tools.procgen.styles import minbari_flyer as mf_style
from tools.procgen.tests.mesh_checks import TEST_OPTIONS, assert_chunks_cut_the_hull, assert_hull_mesh, assert_mirror_symmetric, glowing_points

TEXEL_MAX_M = 0.04  # a small craft at the default 2 048 px atlas


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mirrored(v: list[float]) -> list[float]:
    return [-v[0], v[1], v[2]]


class CraftChecks:
    """The checks both craft share; a subclass names the craft and its expected numbers."""

    CRAFT: es.Craft
    BUILD = None
    LOOKS = None
    LENGTH: float
    SPAN: float
    HEIGHT: float
    CHUNKS: tuple[str, ...]
    THRUST_Y: float
    GLOW_FROM = 0.8  # the glow lies aft of this share of the length

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
        cls.obj = read_obj(cls.dir_a / f"{cls.asset_id}.obj")
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.pieces = cls.CRAFT.assemble(cls.CRAFT.look.style)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def authored(self, v: list[float]) -> np.ndarray:
        """A hardpoint back in the design references' frame (the nose at z = 0, x and y from the box centre)."""
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
        self.assertFalse([n for n in names if "turret" in n], "unarmed")
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

    def test_the_hull_is_inside_the_small_craft_budget(self) -> None:
        budget = self.manifest["budget"]
        self.assertEqual((budget["class"], budget["triangles"]), ("small_craft", self.manifest["mesh"]["triangles"]))
        atlas = [cv.HULL_ATLAS_PX]  # the default build's one atlas; the test build's is smaller
        self.assertEqual(over_budget("small_craft", budget["triangles"], texture_mb(atlas), low_set_mb(atlas)), [])

    def test_the_default_atlas_lands_under_four_centimetres_a_texel(self) -> None:
        parts = [TexturedPart(p.part.mesh, phase_steps(p.name, False), (), p.name) for p in cv.with_twins(self.pieces)]
        self.assertLess(cv.texel_of(parts, cv.HULL_ATLAS_PX), TEXEL_MAX_M)

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
        self.assertAlmostEqual(lo[2], 0.0, delta=0.01, msg="the nose at z = 0")
        self.assertAlmostEqual(hi[2], self.LENGTH, delta=0.02)
        self.assertAlmostEqual(lo[0] + hi[0], 0.0, delta=0.01, msg="x centred")
        self.assertAlmostEqual(lo[1] + hi[1], 0.0, delta=0.03 * self.HEIGHT, msg="y centred on the reference's box")
        self.assertAlmostEqual(self.offset[0], 0.0, places=6)

    def test_every_closed_piece_faces_outward(self) -> None:
        for p in self.pieces:
            a, b, c = p.part.mesh.corners()
            volume = float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum()) / 6.0
            self.assertGreater(volume, 0.0, p.name)

    def test_the_mesh_is_mirror_symmetric_in_x(self) -> None:
        assert_mirror_symmetric(self, np.concatenate([p.part.mesh.vertices for p in cv.with_twins(self.pieces)]), "hull")

    def test_the_cockpit_is_forward_and_the_engines_aft(self) -> None:
        eye = self.authored(self.hp["cockpit_camera"]["position"])
        self.assertLess(eye[2], 0.25 * self.LENGTH)
        for pod in self.hp["pods"]:
            self.assertGreater(self.authored(pod["main"]["position"])[2], 0.8 * self.LENGTH, pod["name"])

    def test_the_drives_and_nothing_else_glow(self) -> None:
        glow = glowing_points(self.dir_a, self.manifest["mesh"]) + self.offset
        self.assertGreater(len(glow), 0)
        self.assertTrue(bool(np.all(glow[:, 2] > self.GLOW_FROM * self.LENGTH)), "the glow is aft")

    # --- chunks and hardpoints ---------------------------------------------------------------------------------------------
    def test_chunks_cut_the_hull_and_have_joints(self) -> None:
        assert_chunks_cut_the_hull(self, self.dir_a, self.manifest, self.hp, self.CHUNKS)

    def test_pods_on_both_sides_fire_aft_on_the_thrust_line(self) -> None:
        by_name = {pod["name"]: pod for pod in self.hp["pods"]}
        self.assertEqual(set(by_name), {"l", "r"})
        for pod in self.hp["pods"]:
            main = self.authored(pod["main"]["position"])
            self.assertEqual(pod["main"]["exhaust"], [0.0, 0.0, 1.0], pod["name"])
            self.assertAlmostEqual(main[1], self.THRUST_Y, places=4, msg=pod["name"])
            self.assertEqual(pod["side"], "left" if main[0] < 0.0 else "right", pod["name"])
        np.testing.assert_allclose(by_name["l"]["main"]["position"], mirrored(by_name["r"]["main"]["position"]), atol=1e-4)

    def test_hardpoints_are_unarmed_and_mirror(self) -> None:
        self.assertEqual((self.hp["muzzles"], self.hp["turrets"]), ([], []))
        ports = {port["name"]: port for port in self.hp["rcs"]}
        self.assertEqual(len(ports), len(self.hp["rcs"]), "unique names")
        for name, port in ports.items():
            self.assertTrue(port["tags"], name)
            if name.startswith("r_"):
                np.testing.assert_allclose(ports["l_" + name[2:]]["position"], mirrored(port["position"]), atol=1e-4, err_msg=name)
        lights = self.hp["nav_lights"]
        np.testing.assert_allclose(lights["port"], mirrored(lights["starboard"]), atol=1e-4)
        self.assertGreater(lights["top_lamp"][1], lights["top"][1])

    # --- looks, determinism ---------------------------------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        for out in self.out_a.files:
            self.assertEqual(sha256(out), sha256(self.dir_b / out.name), out.name)

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                self.BUILD(BuildContext(Path(tmp), options={"spacing": 0.0}))


class CentauriShuttleTests(CraftChecks, unittest.TestCase):
    CRAFT = cs.CRAFT
    BUILD = staticmethod(cs.build)
    LENGTH, SPAN, HEIGHT = 36.0, 51.97, 13.51  # T01's length and the reference's box at it
    CHUNKS = ("body", "stern", "wing_l", "wing_r")
    THRUST_Y = -2.28  # the nozzles' axes

    def test_the_chosen_look_is_d2(self) -> None:
        """Q89: the maintainer chose D2."""
        self.assertIs(self.CRAFT.look, cs_style.SHUTTLE_LOOK)
        self.assertEqual((self.CRAFT.look.name, self.CRAFT.look.style.name), ("d2", "centauri_shuttle"))

    def test_every_look_has_the_gold_a_crest_and_running_lights(self) -> None:
        for look in (self.CRAFT.look,):
            _, marks = cs.dress(self.pieces, look)
            self.assertEqual({m.kind for m in marks["body"]}, {"rect", "paint"}, look.name)
            self.assertGreater(len(marks["body"]), 30, "dense gold detailing")
            (strip,) = marks["spine"]
            self.assertLess(strip.params["size_m"][0], 2.0 * cp.SPINE_HALF[1], "a strip down the spine's middle, not the whole crown")
            lamp = look.style.material("running_light")
            r, g, b = lamp.emissive
            self.assertTrue(r > 3.0 * g and g >= b, f"{look.name}: red with an orange tinge")
        wing = next(p for p in self.pieces if p.name == "wing_r").part.mesh
        bare = next(p for p in cs.CRAFT.assemble(replace(self.CRAFT.look.style, materials={k: v for k, v in self.CRAFT.look.style.materials.items()
                                                                                             if k != "running_light"})) if p.name == "wing_r").part.mesh
        self.assertGreater(len(wing.faces), len(bare.faces), "the lamps stand on the wing")

    def test_the_crest(self) -> None:
        crest = next(m for m in cs.dress(self.pieces, self.CRAFT.look)[1]["body"] if m.kind == "paint").params["cover"]
        x, z = cs.CREST_AT
        up = np.array([[0.0, 1.0, 0.0]] * 4)
        cover = crest(np.array([[x + cs.CREST_R, 0.0, z], [-x - cs.CREST_R, 0.0, z], [0.0, 0.0, 10.0], [x, 0.0, z - 0.6]]), up)
        self.assertGreater(cover[0], 0.5, "the ring")
        self.assertAlmostEqual(cover[0], cover[1], msg="both sides alike")
        self.assertEqual(cover[2], 0.0, "nothing far from the crest")
        self.assertEqual(crest(np.array([[x + cs.CREST_R, 0.0, z]]), -up[:1])[0], 0.0, "only on upward faces")

    def test_the_lamps_glow_red_on_the_atlas(self) -> None:
        glow = read_png(self.dir_a / self.manifest["mesh"]["surfaces"][0]["emissive"])[..., :3].astype(int)
        self.assertGreater(int(np.sum((glow[..., 0] > 100) & (glow[..., 1] < 0.6 * glow[..., 0]))), 20)

    def test_the_skin_is_a_soft_darker_mottle_not_a_mosaic(self) -> None:
        """Q83: solid violet with darker clouds at a few sizes; no seam lines."""
        dressed, _ = cs.dress(self.pieces, self.CRAFT.look)
        for p in dressed:
            features = p.part.seams.features()
            self.assertTrue(features and all(isinstance(f, cs.Mottle) for f in features), p.name)
            self.assertGreaterEqual(len({f.size_m for f in features}), 2, p.name)
            self.assertTrue(all(0.0 < f.darker <= 0.3 for f in features), p.name)

    def test_the_wings_rise_to_the_tips(self) -> None:
        starboard = self.authored(self.hp["nav_lights"]["starboard"])
        self.assertGreater(starboard[0], 25.0)
        self.assertGreater(starboard[1], 5.0, "the tips stand high over the body")

    def test_the_look_is_violet(self) -> None:
        r, g, b = self.CRAFT.look.style.material("hull").albedo[:3]
        self.assertTrue(b > r > g)


class MinbariFlyerTests(CraftChecks, unittest.TestCase):
    CRAFT = mf.CRAFT
    BUILD = staticmethod(mf.build)
    LOOKS = staticmethod(mf_style.looks)
    LENGTH, SPAN, HEIGHT = 40.0, 18.48, 8.2  # Q67's length and the reference's box at it
    CHUNKS = ("body", "bow", "tail", "crossbar", "spindle_l", "spindle_r")
    THRUST_Y = 0.0  # the spindles' axes
    GLOW_FROM = 0.7  # the panel under the crossbar glows too
    OPTIONS = ("p1",)

    def test_one_look_the_bluer_one(self) -> None:
        """The maintainer's choice among the three shown (2026-11-25): P1, purple bands inside blue outlines on a pale body."""
        looks = self.LOOKS()
        self.assertEqual(tuple(looks), self.OPTIONS)
        look = self.CRAFT.look
        self.assertEqual(look.name, "p1")
        r, g, b = look.style.material("hull").albedo[:3]
        self.assertTrue(b > r and b > g, "a pale blue body")
        self.assertLess(look.style.material("hull").metallic, 0.2, "low gloss: the colour holds in full light")
        red, blue = (lambda c: c >> 16), (lambda c: c & 0xFF)
        self.assertGreater(red(look.purple), red(look.band_blue), "the core is purple, its outline blue")
        self.assertGreater(blue(look.band_blue), red(look.band_blue) + 100, "a clear blue")
        self.assertGreater(blue(look.fin_outer), blue(look.fins), "the fins' outboard faces are the brighter blue")

    def test_the_look_is_named_or_refused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            self.BUILD(BuildContext(Path(tmp), seed=42, options={**TEST_OPTIONS, "look": "p1"}))
            albedo = self.manifest["mesh"]["surfaces"][0]["albedo"]
            self.assertEqual(sha256(Path(tmp) / albedo), sha256(self.dir_a / albedo), "p1 is the default")
            for gone in ("p2", "z"):
                with self.assertRaises(ValueError):
                    self.BUILD(BuildContext(Path(tmp), options={"look": gone}))

    def test_the_skin_is_the_hexagonal_grid(self) -> None:
        """Q45: hexagons on every piece, their shades in the low set; off the fins the seams are cut heavier, so they read on
        the pale body as they do on the fins (round 3)."""
        dressed, marks = mf.dress(self.pieces, self.CRAFT.look)
        seams = {}
        for p in dressed:
            features = p.part.seams.features()
            self.assertTrue(features and all(isinstance(f, Hexes) for f in features), p.name)
            self.assertIn(1, {f.level for f in features}, p.name)
            self.assertEqual({f.cell_m for f in features}, {self.CRAFT.look.hex_m}, f"{p.name}: one grid everywhere")
            seams[p.name] = features[1]
        fin = seams["blade_r"]
        self.assertEqual((fin.width, fin.depth, fin.dark), (1.0, 1.0, 0.6), "the fins' seams as the maintainer passed them")
        self.assertEqual(seams["spindle_r"], fin)
        for name in ("body", "pod_r", "web_r", "strake_r", "waist_r", "crossbar"):
            seam = seams[name]
            self.assertTrue(seam.width > fin.width and seam.depth > fin.depth and seam.dark > fin.dark, name)
        for name in mf.LOBES:
            self.assertTrue(marks[name], f"{name}: painted")

    def test_dark_fins_and_a_glowing_panel(self) -> None:
        _, marks = mf.dress(self.pieces, self.CRAFT.look)
        for name in mf.FINS:
            self.assertEqual(len(marks[name]), 2 + len(mfp.LAYERS), f"{name}: the fins' blue, their outboard blue, then the pattern")
        floods = [m for m in marks["crossbar"] if m.kind == "flood"]
        self.assertEqual(len(floods), mf.PANEL_LAMPS, "a soft mottled glow from scattered pools, not a grid")
        self.assertTrue(all(m.params["centre"][1] < mp.CROSSBAR[2] - mp.CROSSBAR[3] for m in floods), "lit from below")

    def test_the_fins_outboard_faces_are_the_bright_blue(self) -> None:
        pts = np.array([[8.0, 0.0, 4.0], [8.0, 0.0, 4.0], [-8.0, 0.0, 4.0], [-8.0, 0.0, 4.0], [8.0, 3.0, 4.0]])
        nrm = np.array([[1.0, 0.0, 0.0], [-1.0, 0.0, 0.0], [-1.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]])
        np.testing.assert_allclose(mfp.outboard(pts, nrm), [1.0, 0.0, 1.0, 0.0, 0.0])
        _, marks = mf.dress(self.pieces, self.CRAFT.look)
        outer = marks["blade_l"][1]
        self.assertEqual(outer.colour, tuple(capture_albedo(self.CRAFT.look.fin_outer)))
        self.assertIs(outer.params["cover"], mfp.outboard)

    def test_the_pattern_is_a_line_with_branching_bands(self) -> None:
        """Q90: a dark line along each lobe, thick curved bands branching from it and fading out, each a purple core inside a
        wider blue outline; soft everywhere."""
        lobe = mfp.Tube(0.0)
        rng = np.random.default_rng(1)
        z = rng.uniform(6.0, 20.0, 6000)
        angle = rng.uniform(0.0, 2.0 * np.pi, 6000)
        pts = np.column_stack([2.8 * np.cos(angle), 2.8 * np.sin(angle), z])
        k = mfp.strokes(pts, lobe, 1.0)
        crown = np.abs(np.sin(angle)) > np.cos(0.2)  # within 0.2 rad of the crown or the keel
        self.assertGreater(int(np.sum(k.line > 0.5)), 50, "a line")
        self.assertTrue(bool(np.all(crown[k.line > 0.5])), "the lines run along the crown and the keel, meandering a little")
        sides = np.abs(np.cos(angle)) > 0.99
        self.assertLess(float(k.line[sides].max()), 0.01, "and not down the flanks")
        self.assertTrue(0.05 < float(np.mean(k.core > 0.5)) < 0.5, "bands cover part of the lobe")
        self.assertGreater(float(np.mean((k.outline > 0.05) & (k.outline < 0.95))), 0.05, "soft edges")
        self.assertTrue(bool(np.all(k.outline >= k.core - 1e-9)), "the blue outline wraps the purple core")
        self.assertGreater(float(np.mean(k.outline > 0.5)), 1.5 * float(np.mean(k.core > 0.5)), "and is much the wider")
        self.assertGreater(float(k.root[(k.core > 0.5) & ~crown].mean()), 0.0)
        far = (k.core > 0.05) & (np.abs(k.distance) > 0.85 * 2.8 * 0.5 * np.pi)
        self.assertFalse(bool(far.any()), "bands fade out before the flanks")
        covers = {layer: mfp.cover(pts, pts, lobe, 1.0, layer) for layer in mfp.LAYERS}
        self.assertEqual(tuple(covers), ("blue", "purple", "dark"), "painted outline first, the core over it, the line last")
        self.assertTrue(all(bool(np.all((c >= 0.0) & (c <= 1.0))) for c in covers.values()))
        twin = mfp.strokes(pts * np.array([-1.0, 1.0, 1.0]), lobe, 1.0).core
        self.assertGreater(float(np.mean(np.abs(k.core - twin) > 0.5)), 0.02, "the bands differ left and right")

    def test_the_body_has_wide_outlines_and_few_lines(self) -> None:
        """Round 3 (2026-11-25): off the fins the blue outlines are much wider and fuller; only the fuselage, the pods and the
        crossbar keep a line, and the lobes without one keep their bands."""
        for name in mf.FINS:
            lobe = mf.LOBES[name]
            self.assertEqual((lobe.outline, lobe.edge, lobe.line), (1.0, 3.0, True), f"{name}: the fins stay as they were")
        lined = {name for name, lobe in mf.LOBES.items() if lobe.line and name not in mf.FINS}
        self.assertEqual(lined, {"body", "pod_r", "pod_l", "crossbar"})
        for name, lobe in mf.LOBES.items():
            if name not in mf.FINS:
                self.assertGreaterEqual(lobe.outline, 1.5, name)
        rng = np.random.default_rng(3)
        angle = rng.uniform(0.0, 2.0 * np.pi, 8000)
        pts = np.column_stack([2.8 * np.cos(angle), 2.8 * np.sin(angle), rng.uniform(6.0, 20.0, 8000)])
        old, new = mfp.Tube(0.0), mfp.Tube(0.0, outline=mf.BODY_OUTLINE, edge=mf.BODY_EDGE)
        was, now = mfp.strokes(pts, old, 1.0), mfp.strokes(pts, new, 1.0)
        np.testing.assert_array_equal(was.core, now.core, "the purple cores are the same bands")
        self.assertGreater(float(np.mean(now.outline > 0.5)), 1.5 * float(np.mean(was.outline > 0.5)), "the blue is much the wider")
        bare = mfp.Tube(0.0, line=False)
        crown = np.abs(mfp.strokes(pts, bare, 1.0).distance) < 0.05
        self.assertGreater(int(crown.sum()), 20)
        for layer in mfp.LAYERS:
            self.assertLess(float(mfp.cover(pts, pts, bare, 1.0, layer)[crown].max()), 0.05, f"{layer}: nothing along the line")
        self.assertGreater(float(np.mean(mfp.cover(pts, pts, bare, 1.0, "purple") > 0.5)), 0.4 * float(np.mean(was.core > 0.5)),
                           "the bands are still there")

    def test_the_bands_are_thick_and_uneven(self) -> None:
        """Round 2 (2026-11-25): about three times the first pattern's 0.12 m strokes, no two alike."""
        self.assertGreaterEqual(mfp.STROKE_WIDTH_M * mfp.OUTLINE_WIDTHS, 3.0 * 0.12)
        self.assertGreater(mfp.STROKE_PITCH_M, 2.0 * mfp.STROKE_WIDTH_M * mfp.OUTLINE_WIDTHS, "the fins' bands stay apart")
        sheet = mfp.Sheet(along=2, across=1, centre=0.0, reach_m=3.0)
        z = np.linspace(0.0, 60.0, 24000)
        core = mfp.strokes(np.column_stack([np.zeros_like(z), np.full_like(z, 0.6), z]), sheet, 2.0).core > 0.5
        edges = np.flatnonzero(np.diff(core.astype(int)))
        widths = np.diff(z[edges])[:: 2] if core[0] == 0 else np.diff(z[edges])[1::2]
        self.assertGreater(len(widths), 15)
        self.assertGreater(float(np.median(widths)), 0.2, "thick")
        self.assertGreater(float(widths.max() / widths.min()), 1.5, "uneven")

    def test_a_flat_sheet_keeps_its_thin_edge_clean(self) -> None:
        """A band across a web's 0.4 m edge was cut into bars: blocks, seen from the side."""
        sheet = mfp.Sheet(2, 0, 6.0, 1.3, mirror=True, flat=True)
        z = np.linspace(4.0, 18.0, 400)
        pts = np.column_stack([np.full_like(z, 6.0), np.zeros_like(z), z])
        edge, face = np.tile([1.0, 0.0, 0.0], (len(z), 1)), np.tile([0.0, 1.0, 0.0], (len(z), 1))
        for layer in mfp.LAYERS:
            self.assertEqual(float(mfp.cover(pts, edge, sheet, 1.0, layer).max()), 0.0, layer)
        self.assertGreater(float(mfp.cover(pts, face, sheet, 1.0, "dark").max()), 0.9)
        self.assertTrue(all(mf.LOBES[name].flat for name in ("web_r", "web_l", "strake_r", "strake_l", "crossbar")))

    def test_the_crossbar_carries_a_spindle_at_each_tip(self) -> None:
        starboard = self.authored(self.hp["nav_lights"]["starboard"])
        self.assertGreater(starboard[0], 9.0)
        self.assertTrue(0.7 * self.LENGTH < starboard[2] < 0.9 * self.LENGTH)


if __name__ == "__main__":
    unittest.main()
