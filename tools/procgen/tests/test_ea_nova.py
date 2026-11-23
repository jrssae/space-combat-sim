"""``ea_nova`` (M10-T23, Q53): the Nova-class dreadnought on the capital framework, in the Omega's parts and look. Files and
piece, size, the sections, the hardpoints against the loadout (30 mounts, one forward bay of 24 Starfuries), the lone sensor boom, the
name letter and the renegades' marks, collision coverage, the class budget, and each part's sections against the reference STL
(CLAUDE.md, "STL fidelity").

The expected numbers are typed in from docs/assets-capital.md, data/capitals/loadouts.json and the generator's docstring.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS, BUILD_ALONE
from tools.procgen.assets import ea_nova as en
from tools.procgen.core import capital as cap
from tools.procgen.core import loadout
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.budgets import low_set_mb, over_budget, texture_mb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Mesh
from tools.procgen.parts import capital as cp
from tools.procgen.parts import ea_nova_fidelity as fid
from tools.procgen.styles.ea_capital import LOOKS
from tools.procgen.tests.budget_table import read_budgets
from tools.refview.sections import PASS_IOU, section_score

ROOT = Path(__file__).resolve().parents[3]
STL = ROOT / "references" / "EA Nova class destroyer.STL"
TEST_OPTIONS = {"atlas_px": 1024, "detail_px": 128}  # the default sample spacing: the coverage check needs it; the open bow's charts need 1 024 px
LENGTH, SPAN, HEIGHT = 1502.1, 208.0, 443.7  # T01's length; the beam's tips across, the roof masts to the keel mast
SECTIONS = ("bow", "bridge", "fuel", "spine_fore", "hangar", "spine_mid", "spine_aft", "reactor", "engine_r", "engine_l")
MOUNTS = {"turret": 18, "beam": 6, "interceptor": 6}
BAYS, STARFURIES = 1, 24


class NovaBuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name) / "ea_nova"
        cls.out = en.build(BuildContext(cls.dir, seed=42, options=TEST_OPTIONS))
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
        self.assertIs(ASSETS["ea_nova"], en.build)
        self.assertIn("ea_nova", BUILD_ALONE, "a 4 096 px atlas: built alone")
        self.assertEqual(self.out.warnings, (), "the collision covers the hull")
        manifest_io.validate_manifest(self.manifest)
        cover = self.manifest["collision"]["coverage"]
        self.assertEqual((cover["covered"], cover["within_reach"]), (1.0, 1.0))

    def test_size(self) -> None:
        dims = self.manifest["dimensions_m"]
        self.assertAlmostEqual(dims["length"], LENGTH, places=2)
        self.assertAlmostEqual(dims["span"], SPAN, delta=0.01 * SPAN)
        self.assertAlmostEqual(dims["height"], HEIGHT, delta=0.01 * HEIGHT)

    def test_the_sections_and_the_one_piece(self) -> None:
        self.assertEqual(tuple(self.sections), SECTIONS)
        self.assertAlmostEqual(sum(s["hull_share"] for s in self.sections.values()), 1.0, places=9)
        for name in ("fuel", "reactor"):
            self.assertGreater(self.sections[name]["blast_energy_j"], 0.0, name)
        self.assertEqual(list(self.manifest["pieces"]), ["hull"])

    def test_the_mounts_and_bays_are_the_loadouts(self) -> None:
        self.assertEqual(loadout.problems(self.hp, loadout.read(), "ea_nova"), [])
        kinds: dict[str, int] = {}
        for w in self.hp["weapons"]:
            kinds[w["kind"]] = kinds.get(w["kind"], 0) + 1
        self.assertEqual(kinds, MOUNTS)
        self.assertEqual({w["weapon"] for w in self.hp["weapons"] if w["kind"] == "beam"}, {"ea_sweep_beam_nova"}, "the Omega's beams at 80 %")
        beams = [self.authored(w["position"])[2] for w in self.hp["weapons"] if w["kind"] == "beam"]
        self.assertEqual((sum(z < 700.0 for z in beams), sum(z > 700.0 for z in beams)), (2, 4), "two fore, four aft")
        self.assertEqual(len(self.hp["bays"]), BAYS)
        self.assertEqual(sum(b["capacity"] for b in self.hp["bays"]), STARFURIES)
        # The one bay faces the bow from the bridge tube's front, above the retro thrusters (the maintainer, 2026-11-21).
        bay = self.hp["bays"][0]
        self.assertEqual(bay["section"], "bow")
        self.assertLess(bay["exit"][2] - bay["position"][2], -1.0, "it opens toward the bow")
        np.testing.assert_allclose(bay["forward"], [0.0, 0.0, -1.0], atol=1e-6, err_msg="it launches forward")
        exit_at = self.authored(bay["exit"])
        self.assertAlmostEqual(exit_at[2], en.nv.BAY_MOUTH_Z, places=3, msg="its mouth at the bridge tube's front")
        self.assertAlmostEqual(exit_at[0], 0.0, places=3)
        retros = [m for m in cp.with_twins(en.modules()) if m.name.startswith("retro_") and "strut" not in m.name]
        self.assertEqual(len(retros), 2, "two oval retro thrusters")
        retro_top = max(float(m.part.mesh.bounds()[1][1]) for m in retros)
        self.assertGreater(en.nv.BAY_Y - 0.5 * en.nv.BAY_MOUTH[1], retro_top, "the mouth above the retro thrusters")

    def test_engines_and_lights(self) -> None:
        self.assertEqual(len(self.hp["engines"]), 4)
        self.assertAlmostEqual(sum(e["share"] for e in self.hp["engines"]), 1.0)
        for e in self.hp["engines"]:
            self.assertAlmostEqual(self.authored(e["position"])[2], en.nv.ENGINE_MOUTH_Z, places=3)
        roles = sorted(light["role"] for light in self.hp["lights"])
        self.assertEqual(roles, ["bay"] * BAYS + ["beacon", "beacon", "port", "starboard", "top"], "and one red light in each bay")
        port = next(light for light in self.hp["lights"] if light["role"] == "port")
        self.assertLess(port["position"][0], 0.0, "red to port")

    def test_the_name_letter_and_the_renegades_red_x(self) -> None:
        marks = {m["name"]: m for m in self.hp["marks"]}
        self.assertEqual(sorted(marks), ["mark_initial_l", "mark_initial_r", "mark_x_l", "mark_x_r", "mark_x_roof"])
        right, left = marks["mark_initial_r"], marks["mark_initial_l"]
        self.assertEqual((right["text"], right["section"]), ("initial", "bow"))
        self.assertNotIn("only_faction", right, "the name letter is for everyone")
        self.assertGreater(right["normal"][0], 0.9, "the starboard letter faces outward, on the lower plate")
        self.assertLess(right["normal"][1], -0.2, "the lower plate leans in towards the keel")
        self.assertAlmostEqual(left["position"][0], -right["position"][0], places=3)
        self.assertAlmostEqual(float(np.dot(right["normal"], right["up"])), 0.0, places=3)
        xs = [m for m in self.hp["marks"] if m["text"] == "X"]
        self.assertEqual(len(xs), 3, "one on each vertical plate and one on the roof")
        for m in xs:
            self.assertEqual(m["only_faction"], "renegades")

    def test_the_hull_is_inside_the_capital_budget(self) -> None:
        budget = self.manifest["budget"]
        self.assertEqual(budget["class"], "capital")
        self.assertLessEqual(budget["triangles"], read_budgets()["capital"].triangles)
        self.assertEqual([p.atlas_px for p in en.PIECES], [4096])
        self.assertEqual(over_budget("capital", budget["triangles"], texture_mb([4096], 1024), low_set_mb([4096], 1024)), [])


class NovaSpecTests(unittest.TestCase):
    def test_the_spec_has_no_problems_in_any_look(self) -> None:
        for look in LOOKS:
            self.assertEqual(cap.problems(en.spec(look)), [], look)

    def test_the_sensor_boom_is_one_sided(self) -> None:
        boom = [m for m in en.modules() if m.name == "sensor_boom"]
        self.assertEqual(len(boom), 1)
        self.assertEqual(boom[0].side, cp.LONE)
        self.assertLess(float(boom[0].part.mesh.bounds()[1][0]), 0.0, "it hangs to port")
        self.assertEqual(float(boom[0].part.mesh.bounds()[0][2]), 0.0, "its tip is the ship's bow")

    def test_the_soft_finish_and_the_metal_bay(self) -> None:
        """Q64: the Hyperion's skin in the Omega's colours, the bay lined in grey metal lit red, no glowing rim and no door."""
        from tools.procgen.styles.ea_capital import ea_capital  # noqa: PLC0415
        from tools.procgen.styles.ea_hyperion import HyperionMosaic  # noqa: PLC0415

        nova, omega = en.style(), ea_capital()
        self.assertIsInstance(nova.skin, HyperionMosaic)
        self.assertNotIsInstance(omega.skin, HyperionMosaic, "the Omega keeps the fleet's finish until T68")
        self.assertEqual(nova.style.materials["hull"].albedo, omega.style.materials["hull"].albedo, "the Omega's colours")
        self.assertNotIn("bay_metal", omega.style.materials)
        metal = nova.style.materials["bay_metal"]
        self.assertEqual((metal.metallic, metal.roughness), (0.7, 0.32))
        hall = next(m for m in en.modules() if m.name == "bay_fore")
        used = {mat.name for mat in hall.part.mesh.materials}
        self.assertIn(metal.name, used, "the hall is grey metal")
        self.assertNotIn(nova.style.materials["bay_light"].name, used, "no glowing band round the mouth")
        self.assertFalse(any(h.kind == cp.DOOR for m in en.modules() for h in m.hardpoints), "no doors")

    def test_the_open_bow_marks_its_interior_for_t72(self) -> None:
        """Q68: the hall and the decks behind the open frame are named for the interior layer T72 adds."""
        names = {m.name for m in en.modules()}
        for name in en.nv.bow.INTERIOR_MODULES:
            self.assertIn(name, names)

    def test_the_launch_path_ahead_of_the_bay_is_clear(self) -> None:
        """Nothing of the hull stands in the mouth's way out to the bow (T17 launches through it)."""
        hw, hh = 0.5 * en.nv.BAY_MOUTH[0], 0.5 * en.nv.BAY_MOUTH[1]
        lo, hi = np.array([-hw, en.nv.BAY_Y - hh, -1.0]), np.array([hw, en.nv.BAY_Y + hh, en.nv.BAY_MOUTH_Z - 0.01])
        for m in cp.with_twins(en.modules()):
            if m.name.startswith("bay_fore"):
                continue
            low, high = m.part.mesh.bounds()
            self.assertFalse(bool(np.all(low < hi) and np.all(high > lo)), f"{m.name} stands ahead of the bay")


@unittest.skipUnless(STL.is_file(), "the reference STL is gitignored; it is on the maintainer's machine")
class NovaSectionTests(unittest.TestCase):
    """Each part's sections against the STL: IoU >= 0.90, or an exemption with its accepted reason."""

    @classmethod
    def setUpClass(cls) -> None:
        from tools.refview import refview  # noqa: PLC0415

        raw, _ = refview.read_stl(STL)
        axes = fid.REFERENCE_MAPPING
        model, _ = refview.to_ship_frame(raw, refview.frame_matrix(axes["right"], axes["up"], axes["aft"]), LENGTH)
        cls.stl = np.asarray(model).reshape(-1, 3, 3) - np.array(fid.REFERENCE_AXIS)
        mesh = Mesh.concatenate([m.part.mesh for m in cp.with_twins(en.modules())])
        cls.model = mesh.vertices[mesh.faces]

    def test_every_part_passes(self) -> None:
        for part, planes in fid.PLANES.items():
            with self.subTest(part=part):
                failures = [f"{p.name} {s.iou:.3f}" for p in planes if (s := section_score(self.stl, self.model, p)).iou < PASS_IOU
                            and p.name not in fid.EXEMPT]
                self.assertEqual(failures, [], f"{part}: sections under {PASS_IOU}")

    def test_the_bow_face_holds_its_floors(self) -> None:
        """T66's sweeps and depth map over the open-frame bow (M10-T67): each sweep's mean IoU and the face's depth agreement."""
        from tools.refview import fidelity  # noqa: PLC0415

        for axis, (span, step, window) in fid.FACE_SWEEPS.items():
            scores = fidelity.sweep(self.stl, self.model, "xyz".index(axis), span, step, 1.0, window, outline=True)
            with self.subTest(axis=axis):
                self.assertGreaterEqual(float(np.mean([s.iou for s in scores])), fid.FACE_MEAN_IOU[axis])
        maps = [fidelity.depth_map(m, "front", fid.FACE_BOX, 1.0) for m in (self.stl, self.model)]
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
