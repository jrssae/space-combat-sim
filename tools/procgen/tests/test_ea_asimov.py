"""``ea_asimov`` (M10-T53, Q84, Q86, Q87): the Asimov-class liner on the capital framework. Files and pieces, size, the sections and
the habitat band's turning piece, an unarmed loadout, the open hexagonal mouth, the halves the mining variant will part, collision
coverage, the class budget, the look (the patch skin, no seam lines), the band liveries and bars, the forward bowl, and each
part's sections against the reference STL (CLAUDE.md, "STL fidelity"; the face's planes exempted by Q95).

The expected numbers are typed in from docs/assets-capital.md, data/capitals/loadouts.json and the generator's docstring.
"""

from __future__ import annotations

import json
import math
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS, BUILD_ALONE
from tools.procgen.assets import ea_asimov as ea
from tools.procgen.core import capital as cap
from tools.procgen.core import loadout
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.budgets import over_budget, texture_mb, low_set_mb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Mesh
from tools.procgen.core.seams import Plates
from tools.procgen.parts import capital as cp
from tools.procgen.parts import ea_asimov as asi
from tools.procgen.parts import ea_asimov_fidelity as fid
from tools.procgen.styles import ea_asimov as st
from tools.procgen.tests.budget_table import read_budgets
from tools.refview.sections import PASS_IOU, section_score

ROOT = Path(__file__).resolve().parents[3]
STL = ROOT / "references" / "EA Asimov liner 600m.stl"
NAMES = ROOT / "data" / "ships" / "names.json"
TEST_OPTIONS = {"atlas_px": 512, "detail_px": 128}
LENGTH, SPAN, HEIGHT = 600.0, 347.4, 347.4
SECTIONS = ("bridge", "spine", "face", "habitat", "sphere_aft", "reactor", "engine_r", "engine_l")


class AsimovBuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name) / "ea_asimov"
        cls.out = ea.build(BuildContext(cls.dir, seed=42, options=TEST_OPTIONS))
        cls.manifest = manifest_io.read_manifest(cls.dir)
        cls.hp = json.loads((cls.dir / "hardpoints.json").read_text(encoding="utf-8"))
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.sections = {s["name"]: s for s in cls.manifest["sections"]}

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_registered_built_alone_and_covered(self) -> None:
        self.assertIs(ASSETS["ea_asimov"], ea.build)
        self.assertIn("ea_asimov", BUILD_ALONE, "two 4 096 px atlases: built alone")
        self.assertEqual(self.out.warnings, (), "the collision covers the hull")
        manifest_io.validate_manifest(self.manifest)
        cover = self.manifest["collision"]["coverage"]
        self.assertEqual((cover["covered"], cover["within_reach"]), (1.0, 1.0))

    def test_size(self) -> None:
        dims = self.manifest["dimensions_m"]
        self.assertAlmostEqual(dims["length"], LENGTH, delta=0.005 * LENGTH)
        self.assertAlmostEqual(dims["span"], SPAN, delta=0.01 * SPAN)
        self.assertAlmostEqual(dims["height"], HEIGHT, delta=0.01 * HEIGHT)

    def test_the_sections_and_the_turning_band(self) -> None:
        self.assertEqual(tuple(self.sections), SECTIONS)
        self.assertAlmostEqual(sum(s["hull_share"] for s in self.sections.values()), 1.0, places=9)
        self.assertGreater(self.sections["reactor"]["blast_energy_j"], 0.0)
        pieces = self.manifest["pieces"]
        self.assertEqual(list(pieces), ["hull", "band"])
        self.assertEqual(pieces["band"]["sections"], ["habitat"])
        np.testing.assert_allclose(np.array(pieces["band"]["pivot"]) + self.offset, asi.BAND_PIVOT, atol=1e-3)
        self.assertEqual(pieces["band"]["axis"], [0.0, 0.0, 1.0])
        self.assertAlmostEqual(pieces["band"]["spin_rad_s"], ea.BAND_SPIN_RAD_S)

    def test_unarmed_with_four_engines_and_its_lights(self) -> None:
        self.assertEqual(loadout.problems(self.hp, loadout.read(), "ea_asimov"), [])
        self.assertEqual((self.hp["weapons"], self.hp["bays"]), ([], []))
        self.assertEqual(len(self.hp["engines"]), 4)
        self.assertAlmostEqual(sum(e["share"] for e in self.hp["engines"]), 1.0)
        roles = sorted(light["role"] for light in self.hp["lights"])
        self.assertEqual(roles, ["beacon", "beacon", "port", "starboard", "top"])

    def test_the_hull_is_inside_the_capital_budget(self) -> None:
        budget = self.manifest["budget"]
        self.assertEqual(budget["class"], "capital")
        row = read_budgets()["capital"]
        self.assertLessEqual(budget["triangles"], row.triangles)
        self.assertEqual([p.atlas_px for p in ea.PIECES], [4096, 4096])
        self.assertEqual(over_budget("capital", budget["triangles"], texture_mb([4096, 4096], 1024), low_set_mb([4096, 4096], 1024)), [])

    def test_every_opaque_surface_carries_the_band_liveries(self) -> None:
        for piece in self.manifest["pieces"].values():
            for surface in piece["mesh"]["surfaces"]:
                if not surface["blend"]:
                    self.assertEqual(surface["band_tint"], st.band_tint())

    def test_only_the_band_carries_the_bars(self) -> None:
        """The game's shader draws a ship's bars where ``band_bars`` says, in the band's own frame (Q95): no atlas a count."""
        pieces = self.manifest["pieces"]
        for surface in pieces["band"]["mesh"]["surfaces"]:
            if not surface["blend"]:
                self.assertEqual(surface["band_bars"], st.band_bars())
        self.assertFalse(any("band_bars" in surface for surface in pieces["hull"]["mesh"]["surfaces"]))
        bars = st.band_bars()
        self.assertAlmostEqual(bars["radius_m"], asi.SPHERE_R)
        self.assertEqual(bars["span_m"], [st.PATTERN.ring_end_z - asi.SPHERE_Z, asi.AFT_SEAM_Z - asi.SEAM_WIDTH - asi.SPHERE_Z])
        self.assertEqual(st.band_tint()["bar_counts"], [6, 8])


class AsimovSpecTests(unittest.TestCase):
    def test_the_spec_has_no_problems(self) -> None:
        self.assertEqual(cap.problems(ea.spec()), [])

    def test_only_the_liner_variant_so_far(self) -> None:
        self.assertEqual(ea.VARIANTS, ("liner",))
        with self.assertRaises(ValueError):
            ea.modules(variant="mining")

    def test_the_band_is_two_halves_split_at_the_equator(self) -> None:
        """T56's mining transport parts its sphere there: each half its own closed part."""
        band = [m for m in ea.modules() if m.section == "habitat" and m.name in ("band_fore", "band_aft")]
        self.assertEqual(sorted(m.name for m in band), ["band_aft", "band_fore"])
        lo, hi = ({m.name: m.part.mesh.bounds()[k][2] for m in band} for k in (0, 1))
        self.assertAlmostEqual(hi["band_fore"], asi.SPHERE_Z, places=6)
        self.assertAlmostEqual(lo["band_aft"], asi.SPHERE_Z, places=6)

    def test_the_hexagonal_mouth_is_open(self) -> None:
        """Nothing stands in the mouth from the bow back to its floor (stage 2 puts the shuttle bay behind it)."""
        hex_pts = np.array(asi.HEX)
        centre = hex_pts.mean(axis=0)
        mesh = Mesh.concatenate([m.part.mesh for m in cp.with_twins(ea.modules())])
        tris = mesh.vertices[mesh.faces]
        ray = np.array([centre[0], centre[1]])
        hit_z = []
        def cross(u: np.ndarray, v: np.ndarray) -> float:
            return float(u[0] * v[1] - u[1] * v[0])

        for t in tris:
            a, b, c = t[:, :2]
            d = cross(b - a, c - a)
            if abs(d) < 1e-9:
                continue
            w1, w2 = cross(ray - a, c - a) / d, cross(b - a, ray - a) / d
            if w1 >= 0.0 and w2 >= 0.0 and w1 + w2 <= 1.0:
                hit_z.append(float(t[0, 2] + w1 * (t[1, 2] - t[0, 2]) + w2 * (t[2, 2] - t[0, 2])))
        self.assertAlmostEqual(min(hit_z), asi.HEX_BACK_Z, places=3, msg="the first surface down the mouth's axis is its floor")

    def test_the_forward_face_is_a_deep_bowl_with_the_mouth_in_its_floor(self) -> None:
        """Q95: the show's cavity. The bowl narrows terrace by terrace to a floor wide enough for the mouth, and its collision
        leaves it open: no shape of the face reaches into it past the ribs' depth."""
        self.assertGreaterEqual(asi.BOWL_FLOOR_Z - asi.COLLAR[0], 35.0, "deep, not the reference's shallow disc")
        radii = [r for _, top, foot in asi.BOWL for r in (top, foot)]
        self.assertEqual(radii, sorted(radii, reverse=True))
        self.assertGreater(radii[-1], max(float(np.hypot(*p)) for p in asi.HEX), "the floor holds the whole mouth")
        self.assertLess(asi.HEX_BACK_Z, asi.FORE_SEAM_Z, "the mouth ends ahead of the turning band")
        cap_module = next(m for m in ea.modules() if m.name == "forward_cap")
        ends = [t[0] for t in asi.BOWL[1:]] + [asi.BOWL_FLOOR_Z]
        for (z0, top, foot), z1 in zip(asi.BOWL, ends, strict=True):
            for shape in (q for q in cap_module.shapes if q.name.startswith("cap_bowl")):
                pts = np.asarray(shape.points)
                inside = pts[(pts[:, 2] > z0 + 0.01) & (pts[:, 2] < z1 - 0.01)]
                if len(inside):
                    self.assertGreater(float(np.hypot(inside[:, 0], inside[:, 1]).min()), foot - asi.RIB_DEPTH, shape.name)

    def test_the_skin_is_patches_without_seams(self) -> None:
        layout = st.SKIN.hull_layout((0.0, 0.0, 0.0), (1.0, 1.0, 1.0), 7)
        for feature in (f for _, _, group in layout.groups for f in group):
            with self.subTest(feature=type(feature).__name__):
                self.assertTrue(feature.dark == 0.0, "no seam lines")
                if isinstance(feature, Plates) and feature.scatter == 0.0:
                    self.assertEqual(feature.depth, 0.0, "no grooves round the plates")
        self.assertIsNone(st.SKIN.detail_tile(64, 7))

    def test_the_paint_is_the_shows_layout(self) -> None:
        """Q95: a band-coloured ring round the forward face behind a white rim, about as wide as a bar; behind it white skin that
        turns with the band (its bars are the game's), window rows on the band standing clear of both bar counts."""
        cap_mesh = next(m for m in ea.modules() if m.name == "forward_cap").part.mesh
        names = [m.name for m in cap_mesh.materials]
        z = cap_mesh.vertices[cap_mesh.faces][:, :, 2].mean(axis=1)
        on_sphere = np.linalg.norm(cap_mesh.vertices[cap_mesh.faces].mean(axis=1) - np.array([0.0, 0.0, asi.SPHERE_Z]), axis=1) > asi.SPHERE_R - 1.0
        stripe = np.array([names[k].endswith("_stripe") for k in cap_mesh.face_material])
        self.assertTrue(stripe[on_sphere & (z > st.PATTERN.ring_z)].all(), "the ring")
        self.assertFalse(stripe[z < st.PATTERN.ring_z].any(), "the white rim and the grey collar inside it")
        self.assertAlmostEqual(float(cap_mesh.vertices[:, 2][np.linalg.norm(cap_mesh.vertices - np.array([0.0, 0.0, asi.SPHERE_Z]), axis=1)
                                                             > asi.SPHERE_R - 0.01].max()), st.PATTERN.ring_end_z, places=6, msg="the ring ends the cap's skin")
        polar = [math.acos((asi.SPHERE_Z - z) / asi.SPHERE_R) for z in (st.PATTERN.ring_z, st.PATTERN.ring_end_z)]
        self.assertAlmostEqual(asi.SPHERE_R * (polar[1] - polar[0]), 2.0 * st.PATTERN.bar_half_m, delta=2.0, msg="the ring is a bar wide")
        lead = next(m for m in ea.modules() if m.name == "band_lead")
        self.assertEqual(lead.section, "habitat", "the skin behind the ring turns with the band, so the bars meet the ring")
        lo, hi = lead.part.mesh.bounds()
        self.assertAlmostEqual(float(lo[2]), st.PATTERN.ring_end_z, places=6)
        self.assertAlmostEqual(float(hi[2]), asi.FORE_SEAM_Z, places=6)
        for m in ea.modules():
            if m.name in ("band_fore", "band_aft", "band_lead"):
                self.assertFalse(any(mat.name.endswith("_stripe") for mat in m.part.mesh.materials), "no bars baked")
            if m.name.endswith("_windows") and m.name.startswith("band_"):
                v = m.part.mesh.vertices
                deg = np.degrees(np.arctan2(v[:, 1], v[:, 0]))
                for count in st.PATTERN.bar_counts:
                    sector = 360.0 / count
                    off = np.abs((deg + 0.5 * sector) % sector - 0.5 * sector)
                    self.assertGreater(float((np.radians(off) * np.hypot(v[:, 0], v[:, 1])).min()), st.PATTERN.bar_half_m, f"{m.name}, {count} bars")

    def test_the_liveries(self) -> None:
        self.assertGreaterEqual(len(st.LIVERIES), 4, "the show's green and at least three more (Q86)")
        self.assertEqual(st.LIVERIES[0].key, "green", "the show's green is the default")
        self.assertEqual(len({lv.band for lv in st.LIVERIES}), len(st.LIVERIES))
        tint = st.band_tint()
        self.assertEqual(tint["liveries"][0], "green")
        self.assertEqual(len(tint["colours"]), len(st.LIVERIES))
        self.assertEqual(st.PAINT["stripe"], st.LIVERIES[0].band, "baked in the default green")
        names = json.loads(NAMES.read_text(encoding="utf-8"))["names"][st.NAMES_TYPE]
        self.assertEqual(names[0], "Asimov")
        self.assertEqual(names[1], "Callisto")  # the show's other liner, the one name that is no author (Q88)
        self.assertGreaterEqual(len(names), 15)


@unittest.skipUnless(STL.is_file(), "the reference STL is gitignored; it is on the maintainer's machine")
class AsimovSectionTests(unittest.TestCase):
    """The silhouettes and each part's sections against the STL: IoU >= 0.90."""

    @classmethod
    def setUpClass(cls) -> None:
        from tools.refview import refview  # noqa: PLC0415

        raw, _ = refview.read_stl(STL)
        axes = fid.REFERENCE_MAPPING
        model, _ = refview.to_ship_frame(raw, refview.frame_matrix(axes["right"], axes["up"], axes["aft"]), LENGTH)
        cls.stl = np.asarray(model).reshape(-1, 3, 3)
        mesh = Mesh.concatenate([m.part.mesh for m in cp.with_twins(ea.modules())])
        cls.model = mesh.vertices[mesh.faces]

    def test_every_part_passes(self) -> None:
        for part, planes in fid.PLANES.items():
            with self.subTest(part=part):
                failures = [f"{p.name} {s.iou:.3f}" for p in planes if (s := section_score(self.stl, self.model, p)).iou < PASS_IOU
                            and p.name not in fid.EXEMPT]
                self.assertEqual(failures, [], f"{part}: sections under {PASS_IOU}")

    def test_only_the_forward_face_is_exempt(self) -> None:
        """Q95: the show's bowl replaces the reference's shallow face; nothing else may miss, and the mouth holds in the floor."""
        face = {p.name for part in ("forward_face", "hex_mouth") for p in fid.PLANES[part]}
        self.assertLessEqual(set(fid.EXEMPT), face)
        self.assertNotIn("mouth_z215", fid.EXEMPT)
        for reason in fid.EXEMPT.values():
            self.assertIn("Q95", reason)

    def test_the_silhouettes(self) -> None:
        from tools.refview.compare import compare_shapes, judge  # noqa: PLC0415

        result = compare_shapes(self.stl, self.model, LENGTH)
        self.assertEqual(judge({k: v.iou for k, v in result.views.items()}, result.ratios), [])


if __name__ == "__main__":
    unittest.main()
