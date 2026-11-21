"""``ea_omega`` (M10-T21, Q53; D12.1): the Omega-class destroyer on the capital framework. Files and pieces, size, the
sections and the rotating section's piece, the hardpoints against the loadout (32 mounts, 8 bays of 4 Starfuries), the
lone sensor boom, collision coverage, the class budget, the looks and the renegade livery hook, and each part's sections
against the reference STL (CLAUDE.md, "STL fidelity").

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
from tools.procgen.tests.budget_table import read_budgets
from tools.refview.sections import PASS_IOU, section_score

ROOT = Path(__file__).resolve().parents[3]
STL = ROOT / "references" / "EA Omega Destroyer.stl"
TEST_OPTIONS = {"atlas_px": 512, "detail_px": 128}  # the default sample spacing: the coverage check needs it
LENGTH, SPAN, HEIGHT = 1714.3, 620.0, 478.0  # T01's length; the drum's reach across, the sensor mast to the keel mast
SECTIONS = ("bow", "bridge", "fuel", "spine_fore", "drum_hub", "hangar_r", "hangar_l", "magazine", "spine_aft", "reactor",
            "engine_r", "engine_l")
DRUM_SECTIONS = ["drum_hub", "hangar_r", "hangar_l"]
MOUNTS = {"turret": 16, "beam": 6, "missile": 2, "interceptor": 8}
BAYS, STARFURIES = 8, 32


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
        for bay in self.hp["bays"]:
            self.assertIn(bay["section"], ("hangar_r", "hangar_l"))
            side = 1.0 if bay["section"] == "hangar_r" else -1.0
            self.assertGreater(side * (bay["exit"][0] - bay["position"][0]), 0.0, f"{bay['name']} opens outward through its rim")
            self.assertAlmostEqual(abs(self.authored(bay["exit"])[0]), eo.om.DRUM_REACH, delta=0.5)

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

    def test_the_drum_turned_for_the_compare_builds_both_arms_where_they_stand(self) -> None:
        turned = [m for m in eo.modules(drum_deg=eo.REFERENCE_DRUM_DEG) if m.section in DRUM_SECTIONS]
        self.assertTrue(turned and all(m.side == cp.LONE for m in turned))
        self.assertEqual({m.section for m in turned}, set(DRUM_SECTIONS))
        rest = [m for m in cp.with_twins(eo.modules()) if m.section in DRUM_SECTIONS]
        self.assertEqual(len(turned), len(rest), "the same modules, only turned")

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


@unittest.skipUnless(STL.is_file(), "the reference STL is gitignored; it is on the maintainer's machine")
class OmegaSectionTests(unittest.TestCase):
    """Each part's sections against the STL: IoU >= 0.90, or an exemption with its accepted reason."""

    @classmethod
    def setUpClass(cls) -> None:
        from tools.refview import refview  # noqa: PLC0415

        raw, _ = refview.read_stl(STL)
        axes = fid.REFERENCE_MAPPING
        model, _ = refview.to_ship_frame(raw, refview.frame_matrix(axes["right"], axes["up"], axes["aft"]), LENGTH)
        cls.stl = np.asarray(model).reshape(-1, 3, 3) - np.array([0.0, fid.REFERENCE_AXIS_Y, 0.0])
        mesh = Mesh.concatenate([m.part.mesh for m in cp.with_twins(eo.modules(drum_deg=eo.REFERENCE_DRUM_DEG))])
        cls.model = mesh.vertices[mesh.faces]

    def test_every_part_passes(self) -> None:
        for part, planes in fid.PLANES.items():
            with self.subTest(part=part):
                failures = [f"{p.name} {s.iou:.3f}" for p in planes if (s := section_score(self.stl, self.model, p)).iou < PASS_IOU
                            and p.name not in fid.EXEMPT]
                self.assertEqual(failures, [], f"{part}: sections under {PASS_IOU}")

    def test_every_exemption_names_a_plane_and_a_reason(self) -> None:
        names = {p.name for planes in fid.PLANES.values() for p in planes}
        for name, reason in fid.EXEMPT.items():
            self.assertIn(name, names)
            self.assertGreater(len(reason), 20, name)


if __name__ == "__main__":
    unittest.main()
