"""``ea_omega`` (M10-T21, Q53; D12.1; rebuilt on the four-part kit in M10-T68): the Omega-class destroyer on the capital framework.
Files and pieces, size, the sections and the rotating section's piece (its arms up and down at rest), the hardpoints against the
loadout (32 mounts, one forward bay of 32 Starfuries), the lone sensor boom, collision coverage and its shape budget, the class
budget, the looks and the renegade livery hook, and the 90 % rule against the assembled kit (CLAUDE.md, "STL fidelity"): three
silhouettes and the sizes, each part's sections, and the open-frame bow's face sweeps and depth map.

The expected numbers are typed in from docs/assets-capital.md, data/capitals/loadouts.json and the generator's docstring.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS, BUILD_ALONE
from tools.procgen.assets import ea_omega as eo
from tools.procgen.core import capital as cap
from tools.procgen.core import loadout
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.budgets import over_budget, texture_mb, low_set_mb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Mesh
from tools.procgen.parts import capital as cp
from tools.procgen.parts import ea_omega_fidelity as fid
from tools.procgen.styles.ea_capital import DEFAULT_LOOK, LOOKS, ea_capital
from tools.procgen.tests import bay_interiors
from tools.procgen.tests.budget_table import read_budgets
from tools.refview.sections import PASS_IOU, section_score

ROOT = Path(__file__).resolve().parents[3]
KIT = ROOT / "references" / fid.KIT
TEST_OPTIONS = {"atlas_px": 512, "detail_px": 128}  # the default sample spacing: the coverage check needs it
LENGTH, SPAN, HEIGHT = 1714.3, 206.0, 616.0  # T01's length; the drum's arms across and their reach up and down (at rest)
SHAPE_BUDGET = 400  # the hull's collision shapes, all sections (the maintainer, M10-T68)
SECTIONS = ("bow", "bridge", "fuel", "spine_fore", "drum_hub", "hangar_r", "hangar_l", "magazine", "spine_aft", "reactor",
            "engine_r", "engine_l")
DRUM_SECTIONS = ["drum_hub", "hangar_r", "hangar_l"]
MOUNTS = {"turret": 16, "beam": 6, "missile": 2, "interceptor": 8}
BAYS, STARFURIES = 1, 32


class OmegaBuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name) / "ea_omega"
        cls.out = eo.build(BuildContext(cls.dir, seed=42, options=TEST_OPTIONS))
        cls.manifest = manifest_io.read_manifest(cls.dir)
        cls.hp = json.loads((cls.dir / "hardpoints.json").read_text(encoding="utf-8"))
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.sections = {s["name"]: s for s in cls.manifest["sections"]}

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def authored(self, v: list[float]) -> np.ndarray:
        """A body-frame point in the generator's frame (the boom's tip at z = 0, the spine's axis on y = 0)."""
        return np.array(v) + self.offset

    def test_registered_built_alone_and_covered(self) -> None:
        self.assertIs(ASSETS["ea_omega"], eo.build)
        self.assertIn("ea_omega", BUILD_ALONE, "two 4 096 px atlases: built alone")
        self.assertEqual(self.out.warnings, (), "the collision covers the hull")
        manifest_io.validate_manifest(self.manifest)
        cover = self.manifest["collision"]["coverage"]
        self.assertEqual((cover["covered"], cover["within_reach"]), (1.0, 1.0))
        shapes = sum(len(p["shapes"]) for p in self.manifest["collision"]["pieces"])
        self.assertLess(shapes, SHAPE_BUDGET, "box hulls under the shape budget")

    def test_the_bays_are_on_the_interior_layer(self) -> None:
        """M10-T72 (Q68): its forward bay's hall out of the sun's light."""
        bay_interiors.check(self, self.dir, self.manifest, self.hp, 1)

    def test_size(self) -> None:
        dims = self.manifest["dimensions_m"]
        self.assertAlmostEqual(dims["length"], LENGTH, places=2)
        self.assertAlmostEqual(dims["span"], SPAN, delta=0.01 * SPAN)
        self.assertAlmostEqual(dims["height"], HEIGHT, delta=0.01 * HEIGHT)

    def test_the_sections_and_the_drum_piece(self) -> None:
        self.assertEqual(tuple(self.sections), SECTIONS)
        self.assertAlmostEqual(sum(s["hull_share"] for s in self.sections.values()), 1.0, places=9)
        for name in ("fuel", "magazine", "reactor"):
            self.assertGreater(self.sections[name]["blast_energy_j"], 0.0, name)
        pieces = self.manifest["pieces"]
        self.assertEqual(list(pieces), ["hull", "drum"])
        self.assertEqual(pieces["drum"]["sections"], DRUM_SECTIONS)
        np.testing.assert_allclose(self.authored(pieces["drum"]["pivot"]), eo.om.DRUM_PIVOT, atol=1e-3)
        self.assertEqual(pieces["drum"]["axis"], [0.0, 0.0, 1.0])
        self.assertAlmostEqual(pieces["drum"]["spin_rad_s"], eo.DRUM_SPIN_RAD_S)
        self.assertEqual(self.hp["rotors"][0]["sections"], DRUM_SECTIONS)

    def test_the_mounts_and_bays_are_the_loadouts(self) -> None:
        self.assertEqual(loadout.problems(self.hp, loadout.read(), "ea_omega"), [])
        kinds: dict[str, int] = {}
        for w in self.hp["weapons"]:
            kinds[w["kind"]] = kinds.get(w["kind"], 0) + 1
        self.assertEqual(kinds, MOUNTS)
        self.assertEqual(len(self.hp["bays"]), BAYS)
        self.assertEqual(sum(b["capacity"] for b in self.hp["bays"]), STARFURIES)
        # The one bay faces the bow from the command block's fore face, above the retro thrusters (the maintainer, 2026-11-21).
        bay = self.hp["bays"][0]
        self.assertEqual(bay["section"], "bow")
        np.testing.assert_allclose(bay["forward"], [0.0, 0.0, -1.0], atol=1e-6, err_msg="it launches forward")
        exit_at = self.authored(bay["exit"])
        self.assertAlmostEqual(exit_at[2], eo.om.BAY_MOUTH_Z, places=3, msg="its mouth in the fore face")
        self.assertAlmostEqual(exit_at[0], 0.0, places=3)
        retros = [m for m in cp.with_twins(eo.modules()) if m.name.startswith("retro_")]
        self.assertEqual(len(retros), 2, "two oval retro thrusters")
        retro_top = max(float(m.part.mesh.bounds()[1][1]) for m in retros)
        self.assertGreater(eo.om.BAY_Y - 0.5 * eo.om.BAY_MOUTH[1], retro_top, "the mouth above the retro thrusters")
        self.assertNotIn(bay["section"], DRUM_SECTIONS, "the drum's rims have no bays")

    def test_engines_and_lights(self) -> None:
        self.assertEqual(len(self.hp["engines"]), 4)
        self.assertAlmostEqual(sum(e["share"] for e in self.hp["engines"]), 1.0)
        for e in self.hp["engines"]:
            self.assertAlmostEqual(self.authored(e["position"])[2], eo.om.ENGINE_MOUTH_Z, places=3)
        roles = sorted(light["role"] for light in self.hp["lights"])
        self.assertEqual(roles, ["bay"] * BAYS + ["beacon", "beacon", "port", "starboard", "top"], "and one red light in each bay")
        bay_lights = {light["name"]: light for light in self.hp["lights"] if light["role"] == "bay"}
        for bay in self.hp["bays"]:
            light = bay_lights[f"{bay['name']}_light"]
            self.assertEqual(light["section"], bay["section"])
            self.assertNotIn("craft", light, "a bay's craft and capacity are its launch point's alone")
        port = next(light for light in self.hp["lights"] if light["role"] == "port")
        self.assertLess(port["position"][0], 0.0, "red to port")

    def test_each_shield_wears_the_name_letter_on_its_lower_panel(self) -> None:
        marks = {m["name"]: m for m in self.hp["marks"]}
        self.assertEqual(sorted(marks), ["mark_initial_l", "mark_initial_r", "mark_x_l", "mark_x_r", "mark_x_roof"])
        right, left = marks["mark_initial_r"], marks["mark_initial_l"]
        self.assertEqual((right["text"], right["section"], right["height_m"]), ("initial", "bow", eo.om.MARK_HEIGHT_M))
        self.assertGreater(right["normal"][0], 0.9, "the starboard letter faces outward")
        self.assertAlmostEqual(left["position"][0], -right["position"][0], places=3)
        self.assertAlmostEqual(left["normal"][0], -right["normal"][0], places=3)
        self.assertLess(self.authored(right["position"])[1], -120.0, "at the bottom of the shield, on the leaning panel")
        self.assertAlmostEqual(float(np.dot(right["normal"], right["up"])), 0.0, places=3)
        self.assertGreater(right["up"][1], 0.9, "the letter stands upright")
        atlas = self.hp["mark_atlas"]
        self.assertTrue((self.dir / atlas["file"]).is_file())
        self.assertTrue((self.dir / (atlas["file"] + ".import")).is_file())

    def test_the_renegades_red_x_marks_are_for_renegades_only(self) -> None:
        xs = [m for m in self.hp["marks"] if m["text"] == "X"]
        self.assertEqual(len(xs), 3, "one on each shield and one on the roof")
        for m in xs:
            self.assertEqual(m["only_faction"], "renegades")
            self.assertGreater(m["colour"][0], 0.6)
            self.assertLess(m["colour"][1], 0.2)
        self.assertNotIn("only_faction", next(m for m in self.hp["marks"] if m["name"] == "mark_initial_r"), "the name letter is for everyone")

    def test_the_hull_is_inside_the_capital_budget(self) -> None:
        budget = self.manifest["budget"]
        self.assertEqual(budget["class"], "capital")
        row = read_budgets()["capital"]
        self.assertLessEqual(budget["triangles"], row.triangles)
        self.assertEqual([p.atlas_px for p in eo.PIECES], [4096, 4096])
        high, low = texture_mb([4096, 4096], 1024), low_set_mb([4096, 4096], 1024)
        self.assertEqual(over_budget("capital", budget["triangles"], high, low), [])
        self.assertAlmostEqual(budget["texture_mb"], texture_mb([512, 512], 128), places=2, msg="this build's")


class OmegaSpecTests(unittest.TestCase):
    def test_the_spec_has_no_problems_in_any_look(self) -> None:
        for look in LOOKS:
            self.assertEqual(cap.problems(eo.spec(look)), [], look)

    def test_the_sensor_boom_is_one_sided(self) -> None:
        boom = [m for m in eo.modules() if m.name == "sensor_boom"]
        self.assertEqual(len(boom), 1)
        self.assertEqual(boom[0].side, cp.LONE)
        self.assertLess(float(boom[0].part.mesh.bounds()[1][0]), 0.0, "it hangs to port")
        self.assertNotIn("sensor_boom_l", [m.name for m in cp.with_twins(eo.modules())])

    def test_the_launch_path_ahead_of_the_bay_is_clear(self) -> None:
        """Nothing of the hull stands in the mouth's way out to the bow (T17 launches through it)."""
        hw, hh = 0.5 * eo.om.BAY_MOUTH[0], 0.5 * eo.om.BAY_MOUTH[1]
        lo, hi = np.array([-hw, eo.om.BAY_Y - hh, -1.0]), np.array([hw, eo.om.BAY_Y + hh, eo.om.BAY_MOUTH_Z - 0.01])
        for m in cp.with_twins(eo.modules()):
            if m.name.startswith("bay_fore"):
                continue
            low, high = m.part.mesh.bounds()
            self.assertFalse(bool(np.all(low < hi) and np.all(high > lo)), f"{m.name} stands ahead of the bay")

    def test_the_drum_rests_with_its_arms_up_and_down(self) -> None:
        """The kit's pose (M10-T68): both arms built where they stand, the starboard-built one up; turned to 0 the port arm
        is the starboard one's twin, the same modules only turned."""
        rest = [m for m in eo.modules() if m.section in DRUM_SECTIONS]
        self.assertTrue(rest and all(m.side == cp.LONE for m in rest))
        self.assertEqual({m.section for m in rest}, set(DRUM_SECTIONS))
        top = [m for m in rest if m.section == "hangar_r"]
        self.assertGreater(min(float(m.part.mesh.bounds()[0][1]) for m in top), 70.0, "hangar_r stands above the hub")
        flat = [m for m in cp.with_twins(eo.modules(drum_deg=0.0)) if m.section in DRUM_SECTIONS]
        self.assertEqual(len(rest), len(flat), "the same modules, only turned")

    def test_the_bow_is_the_kits_open_frame(self) -> None:
        """M10-T68 (Q62): the bay's octagonal frame and its wedge fins, the deck plates and the interior modules are there."""
        names = {m.name for m in cp.with_twins(eo.modules())}
        self.assertTrue({"bay_fore_frame", "bay_fin_top_r", "bay_fin_low_l", "deck_plate_top", "deck_plate_mid", "roof_frame_1"} <= names)
        for name in eo.bow.INTERIOR_MODULES:
            self.assertIn(name, names)
        self.assertNotIn("command_head", names, "no solid plate round the bay")

    def test_the_looks_and_the_livery_hook(self) -> None:
        self.assertEqual(sorted(LOOKS), ["a", "b", "c"])
        self.assertIn(DEFAULT_LOOK, LOOKS)
        plain = ea_capital(DEFAULT_LOOK).style
        marked = ea_capital(DEFAULT_LOOK, livery={"stripe": 0x101010}).style
        self.assertNotEqual(plain.material("stripe").albedo, marked.material("stripe").albedo, "the livery repaints its role")
        self.assertEqual(plain.material("hull").albedo, marked.material("hull").albedo, "and only that role")
        self.assertNotEqual(plain.material("stripe").name, marked.material("stripe").name, "under its own material name")
        with self.assertRaises(ValueError):
            ea_capital("d")
        with self.assertRaises(ValueError):
            ea_capital(DEFAULT_LOOK, livery={"no_such_role": 0})


def _box(lo: tuple[float, float, float], hi: tuple[float, float, float]) -> np.ndarray:
    """A closed box as triangles (n, 3, 3)."""
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    v = np.array([[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0], [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]], float)
    quads = ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (3, 7, 6, 2), (0, 4, 7, 3), (1, 2, 6, 5))
    return np.array([t for a, b, c, d in quads for t in ([v[a], v[b], v[c]], [v[a], v[c], v[d]])])


@unittest.skipUnless(KIT.is_file(), "the assembled kit is gitignored: python3 -m tools.refview.kit build ea_omega (the STLs are on the maintainer's machine)")
class OmegaSectionTests(unittest.TestCase):
    """The 90 % rule against the assembled kit: three silhouettes and the sizes, each part's sections (IoU >= 0.90, or an
    exemption with its accepted reason) and the bow face's floors."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.stl = np.load(KIT)
        mesh = Mesh.concatenate([m.part.mesh for m in cp.with_twins(eo.modules())])
        cls.model = mesh.vertices[mesh.faces]

    def test_silhouettes_and_sizes(self) -> None:
        from tools.refview import compare  # noqa: PLC0415

        comparison = compare.compare_shapes(self.stl, self.model, LENGTH)
        self.assertEqual(compare.judge({k: v.iou for k, v in comparison.views.items()}, comparison.ratios), [])

    def test_every_part_passes(self) -> None:
        for part, planes in fid.PLANES.items():
            with self.subTest(part=part):
                failures = [f"{p.name} {s.iou:.3f}" for p in planes if (s := section_score(self.stl, self.model, p)).iou < PASS_IOU
                            and p.name not in fid.EXEMPT]
                self.assertEqual(failures, [], f"{part}: sections under {PASS_IOU}")

    def test_the_bow_face_holds_its_floors(self) -> None:
        """T66's sweeps and depth map over the open-frame bow (M10-T68, as the Nova's): each sweep's mean IoU (the x cuts by face
        depth) and the face's depth agreement, the build's hall scored as closed at the kit's back wall."""
        from tools.refview import fidelity  # noqa: PLC0415

        model = np.concatenate([self.model, _box(*fid.BAY_PLUG)])
        for axis, (span, step, window) in fid.FACE_SWEEPS.items():
            by_depth = fid.FACE_BY_DEPTH[axis]
            scores = fidelity.sweep(self.stl, model, "xyz".index(axis), span, step, 1.0, window, outline=not by_depth, face=by_depth)
            with self.subTest(axis=axis):
                self.assertGreaterEqual(float(np.mean([s.iou for s in scores])), fid.FACE_MEAN_IOU[axis])
        maps = [fidelity.depth_map(m, "front", fid.FACE_BOX, 1.0) for m in (self.stl, model)]
        summary = fidelity.depth_diff(*maps, fidelity.DEFAULT_TOLERANCE_M, 1.0).summary
        self.assertGreaterEqual(summary["within_tolerance"], fid.FACE_DEPTH["within_tolerance"])
        self.assertLessEqual(summary["mean_abs_depth_diff_m"], fid.FACE_DEPTH["mean_abs_depth_diff_m"])

    def test_every_exemption_names_a_plane_and_a_reason(self) -> None:
        names = {p.name for planes in fid.PLANES.values() for p in planes}
        for name, reason in fid.EXEMPT.items():
            self.assertIn(name, names)
            self.assertGreater(len(reason), 20, name)


if __name__ == "__main__":
    unittest.main()
