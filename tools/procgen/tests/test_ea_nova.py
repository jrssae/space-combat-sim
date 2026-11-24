"""``ea_nova`` (M10-T23, Q53): the Nova-class dreadnought on the capital framework, in the Omega's parts and look. Files and
piece, size, the sections, the hardpoints against the loadout (30 mounts, one forward bay of 24 Starfuries), the gun pods, the lone sensor boom, the
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
from tools.procgen.tests import bay_interiors
from tools.procgen.tests.budget_table import read_budgets
from tools.refview.sections import PASS_IOU, section_score

ROOT = Path(__file__).resolve().parents[3]
STL = ROOT / "references" / fid.REFERENCE
TEST_OPTIONS = {"atlas_px": 1024, "detail_px": 128}  # the default sample spacing: the coverage check needs it; the open bow's charts need 1 024 px
LENGTH, SPAN, HEIGHT = 1502.1, 383.0, 443.7  # T01's length; the wing guns' masts across, the roof masts to the keel mast
SECTIONS = ("bow", "bridge", "fuel", "spine_fore", "hangar", "spine_mid", "spine_aft", "reactor", "engine_r", "engine_l")
MOUNTS = {"turret": 14, "interceptor": 4}  # Q71: 14 fixed pulse cannons and the middle lug's 4 pods as interceptors; no beams
BAYS, STARFURIES = 1, 24
MOUTH_LO, MOUTH_HI = (-45.0, -25.0, 175.0), (45.0, 25.0, 235.0)  # round the bay's mouth: the frame, the hall's front, the fins and plates


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
        # M10-T67: the capital standard of 64 shapes a section, the gun pods' masts kept apart by the merge's excess limit.
        self.assertEqual(en.COLLISION.max_shapes, 64)
        self.assertTrue(all(len(p["shapes"]) <= 64 for p in self.manifest["collision"]["pieces"]))

    def test_the_bays_are_on_the_interior_layer(self) -> None:
        """M10-T72 (Q68): its forward bay's hall out of the sun's light."""
        bay_interiors.check(self, self.dir, self.manifest, self.hp, 1)

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
        retros = [m for m in cp.with_twins(en.modules()) if m.name.startswith("retro_")]
        self.assertEqual(len(retros), 2, "two oval retro thrusters")
        retro_top = max(float(m.part.mesh.bounds()[1][1]) for m in retros)
        self.assertGreater(en.nv.BAY_Y - 0.5 * en.nv.BAY_MOUTH[1], retro_top, "the mouth above the retro thrusters")
        # Q71: all 24 launch and land through this bay on a hidden lift in its floor, for T17.
        self.assertTrue(bay["recovers"])
        lift = self.authored(bay["elevator"])
        np.testing.assert_allclose(lift, [0.0, en.nv.BAY_Y - 0.5 * en.nv.BAY_MOUTH[1], en.nv.ELEVATOR_Z], atol=1e-3, err_msg="in the bay's floor")
        self.assertTrue(en.nv.BAY_MOUTH_Z < lift[2] < en.nv.BAY_BACK_Z, "inside the bay")
        self.assertGreater(bay["elevator_travel_m"], 0.0)

    def test_the_guns_are_the_references_pods(self) -> None:
        """M10-T67, Q71: the 18 twin pods of the reference with guns: two on each flank (beside the command block, on the wing's
        tip), one on each of the hangar block's and four on each ring lug, the aft lug's four facing the stern. Fourteen are
        fixed pulse cannons; the middle lug's four, their fire ahead blocked by the fore lug's pods, swivel as interceptors."""
        pods = [w for w in self.hp["weapons"] if w["kind"] in MOUNTS]
        self.assertEqual(len(pods), 18)
        self.assertTrue(all(w["barrels"] == 2 for w in pods))
        fixed = [w for w in pods if w["kind"] == "turret"]
        self.assertEqual({w["weapon"] for w in fixed}, {"ea_pulse_cannon_fixed"})
        for w in fixed:
            self.assertEqual((w["traverse_deg"], w["elevation_deg"]), (0.0, [0.0, 0.0]), f"{w['name']} is fixed")
        ups = [np.round(w["up"], 3).tolist() for w in fixed]
        self.assertEqual((sum(abs(u[0]) == 1.0 for u in ups), sum(abs(u[1]) == 1.0 for u in ups)), (6, 8), "six on the flanks, eight on the lugs")
        self.assertEqual(sum(w["forward"][2] > 0.5 for w in fixed), 4, "the aft lug's four face the stern")
        guards = [w for w in pods if w["kind"] == "interceptor"]
        self.assertEqual({w["weapon"] for w in guards}, {"ea_interceptor_pod"})
        self.assertEqual(sorted(w["name"] for w in guards), ["interceptor_mid_low_l", "interceptor_mid_low_r", "interceptor_mid_top_l", "interceptor_mid_top_r"])
        for w in guards:
            self.assertEqual(w["section"], "spine_mid")
            self.assertEqual((w["traverse_deg"], w["elevation_deg"]), (180.0, [0.0, 90.0]), "the half sphere over its plate")
            self.assertAlmostEqual(abs(w["up"][1]), 1.0, places=6, msg="facing out from the lug")
            self.assertGreater(self.authored(w["position"])[1] * w["up"][1], 0.0, "away from the girder")
        for w in pods:
            self.assertGreater(abs(self.authored(w["position"])[0]), 70.0, f"{w['name']} stands out on its pod")
        # Each interceptor's pod sits right behind a fore lug pod, so a fixed gun there would fire into it.
        fore = {(round(w["position"][0], 1), round(w["position"][1], 1)) for w in fixed if w["name"].startswith("pulse_fore_")}
        self.assertEqual({(round(w["position"][0], 1), round(w["position"][1], 1)) for w in guards}, fore)

    def test_engines_and_lights(self) -> None:
        self.assertEqual(len(self.hp["engines"]), 4)
        self.assertAlmostEqual(sum(e["share"] for e in self.hp["engines"]), 1.0)
        for e in self.hp["engines"]:
            self.assertAlmostEqual(self.authored(e["position"])[2], en.nv.ENGINE_MOUTH_Z, places=3)
        roles = sorted(light["role"] for light in self.hp["lights"])
        self.assertEqual(roles, ["bay"] * BAYS + ["beacon"] * 6 + ["flood"] * 4 + ["port", "starboard", "top"],
                         "one red light in each bay, the beacons at the tips and the bow's lamp, a flood under each name and emblem")
        bow = next(light for light in self.hp["lights"] if light["name"] == "light_bow")
        self.assertLess(self.authored(bow["position"])[2], en.nv.bow.DECKS[11][5], "the bow lamp stands on the deck's face, facing ahead")
        port = next(light for light in self.hp["lights"] if light["role"] == "port")
        self.assertLess(port["position"][0], 0.0, "red to port")

    def test_the_name_letter_and_the_renegades_red_x(self) -> None:
        marks = {m["name"]: m for m in self.hp["marks"]}
        self.assertEqual(sorted(marks), ["mark_emblem_l", "mark_emblem_r", "mark_initial_l", "mark_initial_r", "mark_name_l", "mark_name_r", "mark_x_l",
                                         "mark_x_r", "mark_x_roof"])
        right, left = marks["mark_initial_r"], marks["mark_initial_l"]
        self.assertEqual((right["text"], right["section"]), ("initial", "bow"))
        self.assertNotIn("only_faction", right, "the name letter is for everyone")
        self.assertGreater(right["normal"][0], 0.9, "the starboard letter faces outward, on the lower plate")
        self.assertLess(right["normal"][1], -0.2, "the lower plate leans in towards the keel")
        self.assertAlmostEqual(left["position"][0], -right["position"][0], places=3)
        self.assertAlmostEqual(float(np.dot(right["normal"], right["up"])), 0.0, places=3)
        self.assertAlmostEqual(right["up"][2], 0.0, places=3, msg="square to the plate's fore and aft edges")
        self.assertEqual(right.get("outline"), True, "light grey rimmed in black (M10-T67)")
        self.assertGreater(min(right["colour"]), 0.7)
        # The panel's lower half, halfway down it and halfway across the plate at that height (maintainer, M10-T67).
        (y0, z0, z1), (ky, kz0, kz1) = (en.nv.PLATE_Y[0], *en.nv.PLATE_Z), (en.nv.KEEL_EDGE[1], *en.nv.KEEL_Z)
        fore, aft = z0 + 0.75 * (kz0 - z0), z1 + 0.75 * (kz1 - z1)
        root, keel_x = en.nv.PLATE_ROOT_X, en.nv.KEEL_EDGE[0]
        want = np.array([root + 0.75 * (keel_x - root), y0 + 0.75 * (ky - y0), 0.5 * (fore + aft)])
        for mark, mirror in ((right, 1.0), (left, -1.0)):
            at = self.authored(mark["position"]) * np.array([mirror, 1.0, 1.0])
            self.assertLess(float(np.linalg.norm(at - want)), 0.05, f"centred in the lower plate's bottom half: {at} against {want}")
        xs = [m for m in self.hp["marks"] if m.get("text") == "X"]
        self.assertEqual(len(xs), 3, "one on each vertical plate and one on the roof")
        for m in xs:
            self.assertEqual(m["only_faction"], "renegades")

    def test_the_name_and_the_emblem_on_each_vertical_plate(self) -> None:
        """M10-T67: the name high on the plate above the pod, the emblem low under it, both lit by a flood; mirrored to port."""
        marks = {m["name"]: m for m in self.hp["marks"]}
        name, emblem = marks["mark_name_r"], marks["mark_emblem_r"]
        self.assertEqual((name["text"], name["section"]), ("name", "bow"))
        self.assertLess(max(name["colour"]), 0.1, "black print")
        board = name["placard"]
        self.assertGreater(min(board["colour"]), 0.7, "on a light grey board")
        self.assertLess(max(board["line_colour"]), 0.1, "ringed in black")
        self.assertGreater(self.authored(name["position"])[1] + (0.5 + board["margin"]) * name["height_m"], 55.0, "high under the plate's top")
        self.assertTrue(emblem["image"].endswith("ea_emblem.png"), "the Earth Alliance emblem")
        self.assertIn("glow", emblem, "lit by the flood under it")
        for m in (name, emblem):
            at = self.authored(m["position"])
            self.assertAlmostEqual(at[0], en.nv.PLATE_X + 0.05, places=2)
            self.assertTrue(en.nv.PLATE_Z[0] < at[2] < en.nv.PLATE_Z[1])
            self.assertAlmostEqual(marks[m["name"][:-1] + "l"]["position"][0], -m["position"][0], places=3)
        self.assertGreater(self.authored(name["position"])[1], 30.0, "above the gun pod")
        self.assertLess(self.authored(emblem["position"])[1], -30.0, "under the gun pod")

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

        from tools.procgen.core.color import capture_albedo  # noqa: PLC0415
        from tools.procgen.styles.ea_capital import SOFT_PAINT, SOFT_PATCH_TIERS  # noqa: PLC0415

        nova, omega = en.style(), ea_capital()
        self.assertEqual((nova.style.seam_depth, nova.style.seam_width, nova.skin.tile_soft), (0.22, 0.6, 0.5), "the Hyperion's seams")
        self.assertEqual((omega.style.seam_depth, omega.skin.patches), (1.0, 0.0), "the Omega keeps the fleet's finish until T68")
        self.assertEqual(nova.style.materials["hull"].albedo, capture_albedo(SOFT_PAINT["a"]["hull"]), "the stills' grey (M10-T67)")
        self.assertNotEqual(nova.style.materials["hull"].albedo, omega.style.materials["hull"].albedo, "the Omega's paint is T68's")
        self.assertEqual(nova.skin.patch_tiers, SOFT_PATCH_TIERS)
        self.assertNotIn("bay_metal", omega.style.materials)
        metal = nova.style.materials["bay_metal"]
        self.assertEqual((metal.metallic, metal.roughness), (0.7, 0.32))
        hall = next(m for m in en.modules() if m.name == "bay_fore")
        used = {mat.name for mat in hall.part.mesh.materials}
        self.assertIn(metal.name, used, "the hall is grey metal")
        self.assertNotIn(nova.style.materials["bay_light"].name, used, "no glowing band round the mouth")
        self.assertFalse(any(h.kind == cp.DOOR for m in en.modules() for h in m.hardpoints), "no doors")

    def test_the_bay_mouth_has_no_flickering_faces(self) -> None:
        """M10-T67: no two parts round the bay's mouth share a plane facing the same way (the frame's inner faces lay on the hall's
        walls and flickered)."""
        from tools.procgen.core.coplanar import coplanar_overlaps  # noqa: PLC0415

        parts = [(m.name, m.part.mesh) for m in cp.with_twins(en.modules())]
        self.assertEqual(coplanar_overlaps(parts, MOUTH_LO, MOUTH_HI), {})

    def test_no_two_parts_share_a_face_anywhere(self) -> None:
        """M10-T67: no two parts of the whole hull lie flush in one plane facing the same way (the spine's fins on its core, the keel's
        block on its wedge, the deck plates' wings on the flank wings flickered); each fitting is set back from the plate it sits on."""
        from tools.procgen.core.coplanar import coplanar_overlaps  # noqa: PLC0415

        parts = [(m.name, m.part.mesh) for m in cp.with_twins(en.modules())]
        self.assertEqual(coplanar_overlaps(parts, (-1e4,) * 3, (1e4,) * 3), {})

    def test_the_spine_wears_red_fittings_and_running_lights(self) -> None:
        """M10-T67: rows of red fittings beside the gun-deck bays and red running lights along the fins, glowing only (no lights)."""
        mods = {m.name: m for m in en.modules()}
        for prefix, rows in (("red_fittings", len(en.marks.RED_ROWS)), ("running_lights", len(en.marks.RUNNING_STRETCHES))):
            found = [m for name, m in mods.items() if name.startswith(prefix)]
            self.assertEqual(len(found), 2 * rows, prefix)
            for m in found:
                self.assertEqual(m.side, cp.RIGHT)
                self.assertFalse(m.hardpoints, "glowing paint, no light of its own")
                self.assertTrue(all(mat.emissive_strength > 0.0 for mat in m.part.mesh.materials))
        lit = [float(z) for m in found for z in m.part.mesh.vertices[:, 2]]
        self.assertGreater(len(lit), 8 * 40, "many lamps")

    def test_the_big_plates_wear_the_edge_band(self) -> None:
        """M10-T67: the band is painted round the armour's, the hangar block's, the collars' and the housing's plates, both sides."""
        bands = {name for name, m in en.markings() if m.kind == "paint"}
        for base in ("armour_side", "armour_upper", "armour_lower"):
            self.assertTrue({f"{base}_r", f"{base}_l"} <= bands, base)
        self.assertTrue({"hangar_roof", "hangar_keel", "collar_fore", "collar_aft", "housing_fore", "housing_aft"} <= bands)

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
        """T66's sweeps and depth map over the open-frame bow (M10-T67): each sweep's mean IoU (the x cuts by face depth) and
        the face's depth agreement."""
        from tools.refview import fidelity  # noqa: PLC0415

        for axis, (span, step, window) in fid.FACE_SWEEPS.items():
            by_depth = fid.FACE_BY_DEPTH[axis]
            scores = fidelity.sweep(self.stl, self.model, "xyz".index(axis), span, step, 1.0, window, outline=not by_depth, face=by_depth)
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
