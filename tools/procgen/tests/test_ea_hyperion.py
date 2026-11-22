"""``ea_hyperion`` (M10-T22, Q49, Q53; D12.1): the Hyperion-class heavy cruiser on the capital framework. Files, size, the
sections, the hardpoints against the loadout (16 mounts, a Starfury bay and a shuttle bay in each sponson), a symmetric hull,
collision coverage, the class budget, its own style and looks on the fleet's mosaic, the name and the renegades' marks, and each
part's sections against the reference STL (CLAUDE.md, "STL fidelity").

The expected numbers are typed in from docs/assets-capital.md, data/capitals/loadouts.json and the generator's docstring.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS, BUILD_ALONE
from tools.procgen.assets import ea_hyperion as eh
from tools.procgen.core import capital as cap
from tools.procgen.core import loadout
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.budgets import low_set_mb, over_budget, texture_mb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Mesh
from tools.procgen.parts import capital as cp
from tools.procgen.parts import ea_hyperion as hy
from tools.procgen.parts import ea_hyperion_fidelity as fid
from tools.procgen.styles.ea_capital import LOOKS as OMEGA_LOOKS
from tools.procgen.styles.ea_capital import fleet_mosaic
from tools.procgen.styles.ea_hyperion import DEFAULT_LOOK, LOOKS, PLATING, ea_hyperion
from tools.procgen.tests.budget_table import read_budgets
from tools.refview.sections import PASS_IOU, section_score

ROOT = Path(__file__).resolve().parents[3]
STL = ROOT / "references" / "EA Hyperion Class Heavy Cruiser.stl"
TEST_OPTIONS = {"atlas_px": 512, "detail_px": 128}  # the default sample spacing: the coverage check needs it
LENGTH, SPAN, HEIGHT = 1025.39, 249.4, 266.25  # T01's length; the tank frame's outriggers, the tower's turret to the pods' domes
SECTIONS = ("bow", "magazine", "bridge", "hangar_r", "hangar_l", "truss", "reactor", "spine_aft", "fuel_r", "fuel_l", "engines")
MOUNTS = {"turret": 8, "beam": 2, "missile": 2, "interceptor": 4}
LAUNCHES = {"starfury_ally": 6, "ea_shuttle": 2}


class HyperionBuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name) / "ea_hyperion"
        cls.out = eh.build(BuildContext(cls.dir, seed=42, options=TEST_OPTIONS))
        cls.manifest = manifest_io.read_manifest(cls.dir)
        cls.hp = json.loads((cls.dir / "hardpoints.json").read_text(encoding="utf-8"))
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.sections = {s["name"]: s for s in cls.manifest["sections"]}

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def authored(self, v: list[float]) -> np.ndarray:
        """A body-frame point in the generator's frame (the bow guns' muzzles at z = 0, the hull's axis on x = 0)."""
        return np.array(v) + self.offset

    def test_registered_built_alone_and_covered(self) -> None:
        self.assertIs(ASSETS["ea_hyperion"], eh.build)
        self.assertIn("ea_hyperion", BUILD_ALONE, "a 4 096 px atlas: built alone")
        self.assertEqual(self.out.warnings, (), "the collision covers the hull")
        manifest_io.validate_manifest(self.manifest)
        cover = self.manifest["collision"]["coverage"]
        self.assertEqual((cover["covered"], cover["within_reach"]), (1.0, 1.0))

    def test_size(self) -> None:
        dims = self.manifest["dimensions_m"]
        self.assertAlmostEqual(dims["length"], LENGTH, places=2)
        self.assertAlmostEqual(dims["span"], SPAN, delta=0.01 * SPAN)
        self.assertAlmostEqual(dims["height"], HEIGHT, delta=0.01 * HEIGHT)

    def test_the_sections(self) -> None:
        self.assertEqual(tuple(self.sections), SECTIONS)
        self.assertAlmostEqual(sum(s["hull_share"] for s in self.sections.values()), 1.0, places=9)
        for name in ("magazine", "fuel_r", "fuel_l", "reactor"):
            self.assertGreater(self.sections[name]["blast_energy_j"], 0.0, name)
        self.assertEqual(list(self.manifest["pieces"]), ["hull"], "no rotating section")

    def test_the_mounts_and_bays_are_the_loadouts(self) -> None:
        self.assertEqual(loadout.problems(self.hp, loadout.read(), "ea_hyperion"), [])
        kinds: dict[str, int] = {}
        for w in self.hp["weapons"]:
            kinds[w["kind"]] = kinds.get(w["kind"], 0) + 1
        self.assertEqual(kinds, MOUNTS)
        launched: dict[str, int] = {}
        for bay in self.hp["bays"]:
            launched[bay["craft"]] = launched.get(bay["craft"], 0) + bay["capacity"]
            self.assertIn(bay["section"], ("hangar_r", "hangar_l"))
            side = 1.0 if bay["section"] == "hangar_r" else -1.0
            self.assertGreater(side * (bay["exit"][0] - bay["position"][0]), 0.0, f"{bay['name']} opens outward through the sponson's face")
        self.assertEqual(launched, LAUNCHES)
        heavy = [w for w in self.hp["weapons"] if w["weapon"] == "ea_plasma_heavy"]
        self.assertTrue(all(w["traverse_deg"] <= 5.0 for w in heavy), "the heavy plasma cannons are fixed forward (X)")

    def test_engines_lights_and_bay_lights(self) -> None:
        engines = self.hp["engines"]
        self.assertEqual(len(engines), 3)
        self.assertAlmostEqual(sum(e["share"] for e in engines), 1.0)
        xs = sorted(float(self.authored(e["position"])[0]) for e in engines)
        np.testing.assert_allclose(xs, sorted(eh.hy.NOZZLE_XS), atol=1e-3)
        self.assertAlmostEqual(xs[0], -xs[2], msg="the bells stand symmetric about the hull's axis")
        roles = sorted(light["role"] for light in self.hp["lights"])
        self.assertEqual(roles, ["bay"] * 4 + ["beacon", "beacon", "port", "starboard", "top"], "and one red light in each bay")
        port = next(light for light in self.hp["lights"] if light["role"] == "port")
        self.assertLess(port["position"][0], 0.0, "red to port")

    def test_the_renegades_red_x_marks_are_for_renegades_only(self) -> None:
        xs = [m for m in self.hp["marks"] if m["text"] == "X"]
        self.assertEqual(sorted(m["name"] for m in xs), ["mark_x_l", "mark_x_r", "mark_x_roof"], "one on each flank of the tower, one on the roof")
        for m in xs:
            self.assertEqual(m["only_faction"], "renegades")
            self.assertGreater(m["colour"][0], 0.6)
            self.assertLess(m["colour"][1], 0.2)

    def test_the_ship_wears_its_name_on_the_roof_and_the_tower(self) -> None:
        names = {m["name"]: m for m in self.hp["marks"] if m["text"] == "name"}
        self.assertEqual(sorted(names), ["mark_name_l", "mark_name_r", "mark_name_roof"], "as the show paints HYPERION")
        for m in names.values():
            self.assertNotIn("only_faction", m, "every faction's hull carries its name")
            self.assertGreater(m["colour"][2], m["colour"][0], "in the bands' blue")
        r, l = self.authored(names["mark_name_r"]["position"]), self.authored(names["mark_name_l"]["position"])
        self.assertAlmostEqual(float(r[0]), -float(l[0]), places=3)
        self.assertGreater(float(r[1]), 52.0, "on the tower, above the roof")

    def test_the_hull_number_is_painted_on_both_flanks_between_the_bands(self) -> None:
        nums = {m["name"]: m for m in self.hp["marks"] if m["text"] == "number"}
        self.assertEqual(sorted(nums), ["mark_number_l", "mark_number_r"])
        r, l = self.authored(nums["mark_number_r"]["position"]), self.authored(nums["mark_number_l"]["position"])
        self.assertAlmostEqual(float(r[0]), -float(l[0]), places=3)
        self.assertTrue(hy.FORE_BANDS[0][1] < hy.NUMBER_Z < 270.0, "between the bow band and the flank dome turret")
        self.assertEqual(nums["mark_number_r"]["normal"][0], 1.0)

    def test_the_bands_wrap_the_hull_belly_included(self) -> None:
        keels = hy.keel(ea_hyperion(DEFAULT_LOOK).style)
        self.assertGreaterEqual(len(keels), 4, "the keel is cut at the bands so they close under the belly")

    def test_the_aft_band_is_painted_in_every_length_it_spans(self) -> None:
        hull = hy.fore_hull(ea_hyperion(DEFAULT_LOOK).style)
        for k in (1, 2):
            self.assertTrue([m for m in hull if m.name.startswith(f"fore_band_{k}_")], f"band {k} is painted round the hull")

    def test_the_hull_is_inside_the_capital_budget(self) -> None:
        budget = self.manifest["budget"]
        self.assertEqual(budget["class"], "capital")
        row = read_budgets()["capital"]
        self.assertLessEqual(budget["triangles"], row.triangles)
        self.assertEqual([p.atlas_px for p in eh.PIECES], [4096])
        self.assertEqual(over_budget("capital", budget["triangles"], texture_mb([4096], 1024), low_set_mb([4096], 1024)), [])
        self.assertAlmostEqual(budget["texture_mb"], texture_mb([512], 128), delta=0.01, msg="this build's")


class HyperionSpecTests(unittest.TestCase):
    def test_the_spec_has_no_problems_in_any_look(self) -> None:
        for look in LOOKS:
            self.assertEqual(cap.problems(eh.spec(look)), [], look)

    def test_the_hull_is_symmetric(self) -> None:
        """The maintainer's call: every centre part sits on the axis, and the only lone parts are the running lights and the two
        ventral interceptors (one on each pod, the loadout's count)."""
        lone = sorted(m.name for m in eh.modules() if m.side == cp.LONE)
        self.assertEqual(lone, ["interceptor_pod_1", "interceptor_pod_2", "light_port", "light_starboard"])
        for m in eh.modules():
            if m.side != cp.CENTRE or m.part.mesh.vertices.size == 0:
                continue
            lo, hi = m.part.mesh.bounds()
            self.assertAlmostEqual(float(lo[0]), -float(hi[0]), delta=0.05, msg=f"{m.name} is off the axis")

    def test_its_own_style_and_looks(self) -> None:
        self.assertEqual(sorted(LOOKS), ["a", "b", "c"])
        self.assertEqual(DEFAULT_LOOK, "a", "the maintainer's")
        self.assertNotIn(DEFAULT_LOOK, PLATING, "look A wears the fleet's mosaic")
        self.assertEqual(ea_hyperion(DEFAULT_LOOK).skin, fleet_mosaic(LOOKS[DEFAULT_LOOK]))
        self.assertEqual(sorted(PLATING), ["b", "c"])
        style = ea_hyperion(DEFAULT_LOOK)
        self.assertTrue(style.name.startswith("ea_hyperion_"))
        self.assertTrue(all(m.name.startswith("eah_") for m in style.style.materials.values() if not m.name.startswith("lamp")))
        omega_paint = {look.paint["hull"] for look in OMEGA_LOOKS.values()}
        for key, look in LOOKS.items():
            self.assertNotIn(look.paint["hull"], omega_paint, f"look {key} is not an Omega grey")
            self.assertIn("bay_light", ea_hyperion(key).style.materials, "the fleet's red-lit bays")
        marked = ea_hyperion(DEFAULT_LOOK, livery={"stripe": 0x101010}).style
        self.assertNotEqual(style.style.material("stripe").albedo, marked.material("stripe").albedo, "the livery repaints its role")
        with self.assertRaises(ValueError):
            ea_hyperion("d")


@unittest.skipUnless(STL.is_file(), "the reference STL is gitignored; it is on the maintainer's machine")
class HyperionSectionTests(unittest.TestCase):
    """Each part's sections against the STL: IoU >= 0.90, or an exemption with its accepted reason."""

    @classmethod
    def setUpClass(cls) -> None:
        from tools.refview import refview  # noqa: PLC0415

        raw, _ = refview.read_stl(STL)
        axes = fid.REFERENCE_MAPPING
        model, _ = refview.to_ship_frame(raw, refview.frame_matrix(axes["right"], axes["up"], axes["aft"]), LENGTH)
        cls.stl = np.asarray(model).reshape(-1, 3, 3)
        mesh = Mesh.concatenate([m.part.mesh for m in cp.with_twins(eh.modules())])
        cls.model = mesh.vertices[mesh.faces]

    def test_every_part_passes(self) -> None:
        for part, planes in fid.PLANES.items():
            with self.subTest(part=part):
                reference = fid.reference_for(part, self.stl)
                failures = [f"{p.name} {s.iou:.3f}" for p in planes if (s := section_score(reference, self.model, p)).iou < PASS_IOU
                            and p.name not in fid.EXEMPT]
                self.assertEqual(failures, [], f"{part}: sections under {PASS_IOU}")

    def test_every_part_has_its_axis(self) -> None:
        self.assertEqual(sorted(fid.PART_AXIS_X), sorted(fid.PLANES))

    def test_every_exemption_names_a_plane_and_a_reason(self) -> None:
        names = {p.name for planes in fid.PLANES.values() for p in planes}
        for name, reason in fid.EXEMPT.items():
            self.assertIn(name, names)
            self.assertGreater(len(reason), 20, name)


if __name__ == "__main__":
    unittest.main()
