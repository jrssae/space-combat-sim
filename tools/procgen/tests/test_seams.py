"""``core/seams.py`` and ``parts/layouts.py`` (M5-T40): the drawn surface features, the plating, a layout following its part, the
civilians' layouts pinned per part (and the Starfury's and the raider's, M7-T15), and the two texture sets a hull with layouts is
written with."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import centauri_brezebel, narn_transport, raider_fighter, saturn_family, starfury_aurora
from tools.procgen.core import geometry as g
from tools.procgen.core.civilian import DETAIL_LEVELS
from tools.procgen.core.seams import EMPTY, FULL, MAJOR, PLATING, Cut, Hatch, Hoop, Path as SeamPath, Plates, SeamLayout, Spoke, every
from tools.procgen.core.textured_mesh import TexturedPart, atlas_of, write_textured_mesh
from tools.procgen.core.textures import bake_maps, seam_size
from tools.procgen.parts import Part, brakiri, layouts, narn, saturn, skylark
from tools.procgen.styles.brakiri import BRAKIRI
from tools.procgen.styles.centauri import CENTAURI
from tools.procgen.styles.ea_civilian import EA_CIVILIAN
from tools.procgen.styles.narn import NARN

GREY = EA_CIVILIAN.material("hull")
LINE, DEPTH = 0.2, 0.06
UP = np.array([[0.0, 1.0, 0.0]])


def _relief(features, points, normals=None):
    points = np.atleast_2d(np.asarray(points, dtype=float))
    normals = np.repeat(UP, len(points), axis=0) if normals is None else np.atleast_2d(np.asarray(normals, dtype=float))
    return SeamLayout.of(features).evaluate(points, normals, LINE, DEPTH)


def _cloud(count: int = 4000, span: float = 30.0, seed: int = 5) -> tuple[np.ndarray, np.ndarray]:
    """Points on a horizontal plate and their up normals."""
    rng = np.random.default_rng(seed)
    p = np.column_stack([rng.uniform(-span, span, count), np.zeros(count), rng.uniform(-span, span, count)])
    return p, np.repeat(UP, count, axis=0)


class FeatureTests(unittest.TestCase):
    def test_a_cut_is_a_groove_where_its_plane_meets_the_surface(self) -> None:
        r = _relief([Cut(axis=2, at=5.0)], [(0, 0, 5.0), (3, 0, 5.04), (0, 0, 5.5)])
        self.assertAlmostEqual(r.height[0], -DEPTH)
        self.assertAlmostEqual(r.line[0], 1.0)
        self.assertTrue(-DEPTH < r.height[1] < 0.0)
        self.assertEqual((r.height[2], r.line[2]), (0.0, 0.0))

    def test_a_cut_keeps_its_width_on_a_slope_and_leaves_faces_square_to_it(self) -> None:
        slope = np.array([0.0, 0.6, 0.8])  # the surface leans towards the cut's axis: the plane's distance is not the surface's
        flat = _relief([Cut(axis=2, at=0.0)], [(0, 0, 0.06)])
        leaning = _relief([Cut(axis=2, at=0.0)], [(0, 0, 0.06 * 0.6)], [slope])
        self.assertAlmostEqual(flat.height[0], leaning.height[0], places=6)
        end_face = _relief([Cut(axis=2, at=0.0)], [(0, 0, 0.0)], [(0.0, 0.0, 1.0)])
        self.assertEqual(end_face.line[0], 0.0)

    def test_a_feature_paints_only_inside_its_box_and_on_the_side_it_faces(self) -> None:
        cut = Cut(axis=2, at=0.0, lo=(-1.0, -9.0, -9.0), hi=(1.0, 9.0, 9.0), facing=(0.0, 1.0, 0.0))
        r = _relief([cut], [(0, 0, 0), (2, 0, 0), (0, 0, 0)], [(0, 1, 0), (0, 1, 0), (0, -1, 0)])
        self.assertEqual(list(r.line), [1.0, 0.0, 0.0])

    def test_a_rib_stands_proud(self) -> None:
        r = _relief([Cut(axis=2, at=0.0, depth=-0.8, flat_m=0.1)], [(0, 0, 0.0), (0, 0, 0.08), (0, 0, 2.0)])
        self.assertAlmostEqual(r.height[0], 0.8 * DEPTH)
        self.assertAlmostEqual(r.height[1], 0.8 * DEPTH, msg="flat across its crown")
        self.assertEqual(r.height[2], 0.0)

    def test_a_spoke_runs_along_a_barrel_between_its_span_and_reach(self) -> None:
        spoke = Spoke(axis=2, centre=(0.0, 0.0, 0.0), angle_deg=90.0, span=(0.0, 10.0), reach=(1.0, 5.0))
        r = _relief([spoke], [(0, 2, 5), (0, 2, 11), (0, 6, 5), (0, -2, 5), (2, 0, 5)])
        self.assertEqual(list(r.line), [1.0, 0.0, 0.0, 0.0, 0.0])

    def test_a_hoop_is_a_circle_on_a_face(self) -> None:
        r = _relief([Hoop(axis=1, centre=(0.0, 0.0, 10.0), radius=4.0)], [(4, 0, 10), (0, 0, 14), (0, 0, 10)])
        self.assertEqual(list(r.line), [1.0, 1.0, 0.0])

    def test_a_path_follows_its_polyline_seen_from_its_side(self) -> None:
        path = SeamPath(points=((0, 0, 0), (4, 0, 0), (4, 0, 4)), facing=(0.0, 1.0, 0.0))
        r = _relief([path], [(2, 7, 0), (4, 0, 2), (2, 0, 2), (5, 0, 0)])
        self.assertEqual(list(r.line), [1.0, 1.0, 0.0, 0.0])

    def test_a_hatch_has_a_groove_round_it_and_a_sunk_toned_plate(self) -> None:
        hatch = Hatch(centre=(0, 0, 0), right=(1, 0, 0), up=(0, 0, 1), size=(2.0, 1.0), facing=(0.0, 1.0, 0.0), sunk=0.5, tone=0.9)
        r = _relief([hatch], [(1.0, 0, 0), (0, 0, 0), (3, 0, 0)])
        self.assertAlmostEqual(r.line[0], 1.0)
        self.assertAlmostEqual(r.height[1], -0.5 * DEPTH)
        self.assertAlmostEqual(r.tint[1], 0.9)
        self.assertEqual((r.height[2], r.tint[2]), (0.0, 1.0))

    def test_louvres_cut_a_hatch_into_slats(self) -> None:
        hatch = Hatch(centre=(0, 0, 0), right=(1, 0, 0), up=(0, 0, 1), size=(2.0, 4.0), facing=(0.0, 1.0, 0.0), slats=8)
        z = np.linspace(-1.9, 1.9, 400)
        r = _relief([hatch], np.column_stack([np.zeros(400), np.zeros(400), z]))
        steps = int(np.sum(np.abs(np.diff(r.height)) > 0.3 * DEPTH))
        self.assertEqual(steps, 7, "one step between each pair of the eight slats")

    def test_every_gives_evenly_spaced_stations_with_both_ends(self) -> None:
        self.assertEqual(every(2.0, 8.0, 2.0), [2.0, 4.0, 6.0, 8.0])


class PlatesTests(unittest.TestCase):
    PLATES = Plates(wrap="planar", right=(1, 0, 0), up=(0, 0, 1), cell=(6.0, 3.4), splits=3, min_m=0.7, keep=0.2, tone=0.1, sheen=0.05, seed=7)

    def test_no_plate_is_smaller_than_the_least_size_and_sizes_are_mixed(self) -> None:
        p, n = _cloud()
        _, u0, u1, v0, v1, u, v = self.PLATES.cells(p, n)
        self.assertGreaterEqual(float(np.minimum(u1 - u0, v1 - v0).min()), 0.7 - 1e-9)
        self.assertTrue(np.all((u >= u0) & (u <= u1) & (v >= v0) & (v <= v1)), "every point lies on its own plate")
        areas = np.unique(np.round((u1 - u0) * (v1 - v0), 4))
        self.assertGreater(len(areas), 20, "plates of many sizes, not one brick")
        self.assertGreater(areas.max() / areas.min(), 8.0)

    def test_the_plating_is_the_same_every_time_and_another_seed_differs(self) -> None:
        p, n = _cloud(1500)
        a, b = _relief([self.PLATES], p, n), _relief([self.PLATES], p, n)
        np.testing.assert_array_equal(a.tint, b.tint)
        np.testing.assert_array_equal(a.height, b.height)
        other = _relief([Plates(**{**self.PLATES.__dict__, "seed": 8})], p, n)
        self.assertGreater(float(np.mean(np.abs(other.tint - a.tint) > 1e-6)), 0.5)

    def test_a_plates_tone_stays_inside_its_share_and_is_one_value_a_plate(self) -> None:
        p, n = _cloud()
        key, *_ = self.PLATES.cells(p, n)
        r = _relief([self.PLATES], p, n)
        self.assertLessEqual(float(np.abs(r.tint - 1.0).max()), 0.1 + 1e-9)
        self.assertGreater(float(r.tint.max() - r.tint.min()), 0.15, "most of the range is used")
        for k in np.unique(key)[:40]:
            self.assertLess(float(np.ptp(r.tint[key == k])), 1e-9)

    def test_plating_by_sides_mirrors_across_the_centre_plane(self) -> None:
        plates = Plates(wrap="sides", cell=(5.0, 3.0), splits=2, min_m=0.6, tone=0.1, seed=3)
        p, n = _cloud(1500)
        mirrored = p * np.array([-1.0, 1.0, 1.0])
        a, b = _relief([plates], p, n), _relief([plates], mirrored, n)
        np.testing.assert_allclose(a.tint, b.tint)
        np.testing.assert_allclose(a.height, b.height)

    def test_plating_round_a_barrel_closes_on_itself(self) -> None:
        plates = Plates(wrap="barrel", axis=2, radius=4.0, around=8, cell=(3.0, 0.0), splits=0, tone=0.1, seed=3)
        just_under, just_over = (-4.0, -1e-6, 1.0), (-4.0, 1e-6, 1.0)  # either side of the angle where the wrap starts
        key, _, _, v0, v1, _, _ = plates.cells(np.array([just_under, just_over]), np.repeat(UP, 2, axis=0))
        self.assertNotEqual(key[0], key[1], "a field ends at the wrap")
        self.assertAlmostEqual(float((v1 - v0)[0]), 2.0 * np.pi * 4.0 / 8)
        whole = Plates(wrap="barrel", axis=2, radius=4.0, around=1, cell=(3.0, 0.0), splits=0, seed=3)
        key, *_ = whole.cells(np.array([just_under, just_over]), np.repeat(UP, 2, axis=0))
        self.assertEqual(key[0], key[1], "the same field met from both sides")

    def test_scattered_hatches_cover_about_their_share_and_stand_proud(self) -> None:
        plates = Plates(wrap="planar", right=(1, 0, 0), up=(0, 0, 1), cell=(1.6, 1.0), splits=0, scatter=0.1, inset_m=0.16, depth=0.7, seed=9)
        p, n = _cloud(20000)
        r = _relief([plates], p, n)
        self.assertTrue(np.all(r.height >= 0.0))
        share = float(np.mean(r.height > 0.0))
        self.assertTrue(0.01 < share < 0.1, share)


class LayoutTests(unittest.TestCase):
    FEATURES = [Cut(axis=2, at=3.0, level=MAJOR), Cut(axis=0, at=1.5, level=FULL),
                Plates(level=PLATING, wrap="sides", cell=(4.0, 2.0), splits=2, min_m=0.5, tone=0.1, seed=1)]

    def test_a_layout_bakes_up_to_a_level(self) -> None:
        layout = SeamLayout.of(self.FEATURES)
        self.assertEqual([len(layout.up_to(k).features()) for k in (0, MAJOR, FULL, PLATING)], [0, 1, 2, 3])
        self.assertFalse(layout.up_to(0))
        self.assertFalse(EMPTY)

    def test_a_layout_follows_its_part_through_moves_turns_and_mirrors(self) -> None:
        layout = SeamLayout.of(self.FEATURES)
        p, n = _cloud(800, 8.0)
        want = layout.evaluate(p, n, LINE, DEPTH)
        turn = g.rotation_y(0.7)
        for matrix, shift in ((np.eye(3), (5.0, -2.0, 9.0)), (turn, (1.0, 2.0, 3.0)), (g.mirror_matrix("x"), (0.0, 0.0, 0.0))):
            moved = layout.transformed(matrix, shift)
            got = moved.evaluate(p @ np.asarray(matrix).T + np.asarray(shift), n @ np.asarray(matrix).T, LINE, DEPTH)
            np.testing.assert_allclose(got.height, want.height, atol=1e-9)
            np.testing.assert_allclose(got.tint, want.tint, atol=1e-9)

    def test_a_part_carries_its_layout_through_every_copy(self) -> None:
        part = Part("panel", g.box((2.0, 2.0, 2.0), GREY)).with_seams(SeamLayout.of(self.FEATURES))
        for copy in (part.translated((1.0, 0.0, 0.0)), part.mirrored("x"), part.renamed("other", group="x"), part.with_anchors({})):
            self.assertEqual(len(copy.seams.features()), 3)
        self.assertFalse(Part("plain", g.box((1.0, 1.0, 1.0), GREY)).seams)

    def test_drawn_on_one_side_and_mirrored_gives_both(self) -> None:
        both = SeamLayout.of([Cut(axis=0, at=1.5)]).mirrored_too(0)
        r = both.evaluate(np.array([(1.5, 0, 0), (-1.5, 0, 0), (0.0, 0, 0)]), np.repeat(UP, 3, axis=0), LINE, DEPTH)
        self.assertEqual(list(r.line), [1.0, 1.0, 0.0])


# Features per part at each level (major, full, plating): the low texture set draws the first, the full set all three.
PINNED = {
    "saturn": {
        "cylinder": (4, 35, 2), "tank": (4, 35, 2), "pod": (3, 19, 2), "disc": (2, 14, 1),
        "junction_module": (0, 1, 1), "junction_spine": (0, 1, 1), "junction_low": (0, 1, 1), "pod_block_low": (0, 1, 1),
        "pod_block_top": (0, 1, 1), "drum_top": (0, 2, 1), "drum_low": (0, 2, 1), "drum_truss": (0, 2, 1),
    },
    "saturn_engine": {"engine_collar": (1, 12, 1), "engine_core_tank": (1, 2, 0)},
    "skylark": {
        "capsule": (5, 49, 3), "tank_r": (4, 16, 1), "nacelle_r": (2, 20, 1), "body": (6, 20, 2), "dorsal_fin": (0, 2, 0),
        "collar": (0, 5, 0), "claw_out_r": (0, 0, 1), "claw_in_r": (0, 0, 1),
    },
    "narn": {
        "crescent_r": (8, 10, 4), "crescent_centre": (10, 9, 4), "box": (6, 11, 4), "cockpit": (0, 0, 4), "tower_r": (0, 0, 4),
        "fin_r": (0, 0, 4), "dorsal": (0, 0, 4),
    },
    "centauri": {"bow": (5, 3, 1), "arm_r": (3, 1, 1), "fairing_r": (0, 1, 1), "fin_top_r": (1, 4, 1), "fin_bot_r": (1, 4, 1), "dorsal": (0, 1, 1)},
    "brakiri": {
        "bow": (3, 1, 2), "spine": (2, 1, 2), "arm_r": (0, 1, 2), "strut_r": (0, 1, 2), "web_r": (0, 1, 2), "post_r": (0, 1, 2),
        "nacelle_r": (2, 1, 2), "fin_top_r": (2, 4, 1), "fin_bot_r": (3, 5, 1),
    },
    "brakiri_pod": {"pod": (2, 5, 2)},
    "starfury": {"strut_ur": (5, 15, 2), "strut_lr": (5, 19, 1), "pod": (2, 17, 1), "fuselage": (2, 15, 1), "claw": (0, 15, 0)},
    "raider": {"wing_r": (4, 33, 2), "hump": (2, 6, 2), "nacelle_r": (2, 15, 1)},
}
# Structure that stays plain (the maintainer, 2026-11-12). The Bokmai's arms and fork struts are its hull limbs, not structure: drawn.
PLAIN_WORDS = ("truss", "brace", "antenna", "bell", "nozzle", "turret", "pad_", "frame_", "vane", "rail", "ribs", "grille", "spindle")


def _layouts() -> dict[str, dict[str, SeamLayout]]:
    return {"saturn": saturn_family.LAYOUTS, "saturn_engine": layouts.saturn_engine(1.0), "skylark": layouts.skylark(), "narn": layouts.narn(),
            "centauri": layouts.centauri(), "brakiri": layouts.brakiri(), "brakiri_pod": {"pod": layouts.brakiri_pod()},
            "starfury": layouts.starfury(), "raider": raider_fighter.surface_layouts(raider_fighter.DEFAULT_SPEC)}


def _positions(layout: SeamLayout, kind: type, level: int, **match: object) -> list[float]:
    return sorted(f.at for f in layout.features() if isinstance(f, kind) and f.level == level and all(getattr(f, k) == v for k, v in match.items()))


class CivilianLayoutTests(unittest.TestCase):
    def test_every_part_has_the_pinned_features_at_each_level(self) -> None:
        got = {ship: {name: tuple(sum(1 for f in lay.features() if f.level == k) for k in (MAJOR, FULL, PLATING)) for name, lay in parts.items()}
               for ship, parts in _layouts().items()}
        self.assertEqual(got, PINNED)

    def test_the_layouts_are_the_same_every_time(self) -> None:
        self.assertEqual(repr(layouts.narn()["box"].features()), repr(layouts.narn()["box"].features()))
        p, n = _cloud(600, 20.0)
        a = layouts.narn()["crescent_centre"].evaluate(p + (0.0, 0.0, 30.0), n, LINE, DEPTH)
        b = layouts.narn()["crescent_centre"].evaluate(p + (0.0, 0.0, 30.0), n, LINE, DEPTH)
        np.testing.assert_array_equal(a.tint, b.tint)

    def test_a_saturn_cylinders_major_seams_are_its_paint_bands_edges(self) -> None:
        length = saturn.CYLINDER_Z[1] - saturn.CYLINDER_Z[0]
        b0, b1 = saturn.DOME_DEPTH, length - saturn.DOME_DEPTH
        want = [b0, b0 + (b1 - b0) / 3.0, b0 + 2.0 * (b1 - b0) / 3.0, b1]
        np.testing.assert_allclose(_positions(saturn_family.LAYOUTS["cylinder"], Cut, MAJOR, axis=2), want)
        mesh = saturn.hull_cylinder(saturn_family.BANDS, EA_CIVILIAN).part.mesh
        band_edges = np.unique(np.round(mesh.vertices[np.isclose(np.hypot(mesh.vertices[:, 0], mesh.vertices[:, 1]), saturn.CYLINDER_RADIUS), 2], 3))
        for z in want:
            self.assertLess(float(np.abs(band_edges - z).min()), 0.01, "a seam on every band edge")

    def test_a_saturn_pods_slats_run_its_length_inside_the_frame(self) -> None:
        pod = saturn_family.LAYOUTS["pod"]
        frame = _positions(pod, Cut, MAJOR, axis=2)
        self.assertEqual(len(frame), 3)
        self.assertAlmostEqual(frame[1], 0.5 * saturn.POD.length)
        slats = [f for f in pod.features() if isinstance(f, Cut) and f.axis == 0]
        self.assertEqual(len(slats), 12)
        for f in slats:
            self.assertTrue(0.0 < f.at < saturn.POD.width)
            self.assertEqual((f.lo[2], f.hi[2]), (frame[0], frame[2]))
        plates = next(f for f in pod.features() if isinstance(f, Plates) and f.scatter == 0.0)
        self.assertAlmostEqual(plates.cell[1], slats[1].at - slats[0].at, msg="a plank is a slat wide")

    def test_the_skylarks_capsule_seams_sit_beside_its_bands(self) -> None:
        capsule = layouts.skylark()["capsule"]
        self.assertEqual(_positions(capsule, Cut, MAJOR, axis=2), sorted([*skylark.BAND_Z[0], *skylark.BAND_Z[1], 11.7]))

    def test_the_narn_trim_line_follows_the_crescents_rim(self) -> None:
        spec = narn.CrescentSpec()
        self.assertEqual(layouts.NARN_RIM, spec.outer[1:])
        trims = [f for f in layouts.narn()["crescent_r"].features() if isinstance(f, SeamPath) and f.level == MAJOR]
        self.assertEqual(len(trims), 2, "top and belly")
        for x, _, z in trims[0].points:
            self.assertAlmostEqual(float(spec.half_width(z)) - x, 2.2)

    def test_the_narn_plating_is_small_rectangles_in_slightly_varied_shades(self) -> None:
        for name, most in (("crescent_r", 0.10), ("crescent_centre", 0.10), ("box", 0.07), ("tower_r", 0.10)):
            toned = [f for f in layouts.narn()[name].features() if isinstance(f, Plates) and f.scatter == 0.0 and f.tone > 0.0]
            self.assertEqual(len(toned), 1, name)
            self.assertLessEqual(toned[0].tone, most)
            self.assertLessEqual(max(toned[0].cell), 3.2)
            self.assertGreaterEqual(toned[0].min_m, 0.5)

    def test_centre_parts_are_the_same_on_both_sides(self) -> None:
        rng = np.random.default_rng(11)
        cases = (("skylark", "capsule", (0, 0, 12), 4.0), ("skylark", "body", (0, 2, 42), 10.0), ("narn", "crescent_centre", (0, 3, 33), 12.0),
                 ("narn", "box", (0, 5, 51), 12.0), ("centauri", "bow", (0, 4, 10), 18.0), ("brakiri", "bow", (0, 6, 8), 6.0),
                 ("brakiri", "spine", (0, 13, 30), 4.0), ("brakiri_pod", "pod", (0, 6, 0), 6.0), ("starfury", "fuselage", (0, 0, -2), 1.2),
                 ("raider", "hump", (0, 0.6, 3.5), 1.0))
        for ship, name, centre, span in cases:
            layout = _layouts()[ship][name]
            p = np.asarray(centre) + rng.uniform(-span, span, (1500, 3)) * np.array([1.0, 0.0, 1.0])
            n = np.repeat(UP, len(p), axis=0)
            a = layout.evaluate(p, n, LINE, DEPTH)
            b = layout.evaluate(p * np.array([-1.0, 1.0, 1.0]), n, LINE, DEPTH)
            np.testing.assert_allclose(a.height, b.height, atol=1e-9, err_msg=f"{ship} {name}")
            np.testing.assert_allclose(a.tint, b.tint, atol=1e-9, err_msg=f"{ship} {name}")
            self.assertGreater(float(np.abs(a.height).max()), 0.0, f"{ship} {name}: the probe meets a feature")

    def test_no_layouts_plate_is_under_its_least_size(self) -> None:
        p, n = _cloud(3000, 40.0)
        for ship, parts in _layouts().items():
            for name, layout in parts.items():
                for f in layout.features():
                    if isinstance(f, Plates) and f.wrap != "polar":
                        _, u0, u1, v0, v1, _, _ = f.cells(p + (9.0, 0.0, 30.0), n)
                        least = min(f.min_m, *[c for c in f.cell if c > 0.0])
                        self.assertGreaterEqual(float(np.minimum(u1 - u0, v1 - v0).min()), least - 1e-9, f"{ship} {name}")

    def test_the_layouts_name_real_parts_and_twins_mirror(self) -> None:
        skylark_parts = {p.name: p.part for p in skylark.assemble(EA_CIVILIAN)}
        brakiri_parts = {p.name: p.part for p in brakiri.assemble(BRAKIRI)}
        centauri_parts = {p.part.name: p.part for p in centauri_brezebel.assemble(centauri_brezebel.DEFAULT_SPEC, CENTAURI)}
        for ship, parts in (("skylark", skylark_parts), ("brakiri", brakiri_parts), ("centauri", centauri_parts)):
            drawn = {name for name, part in parts.items() if part.seams}
            self.assertEqual(drawn, set(PINNED[ship]), ship)
            for name in parts:
                if any(word in name for word in PLAIN_WORDS):
                    self.assertFalse(parts[name].seams, f"{ship} {name} stays plain")
        self.assertEqual(set(narn_transport.NARN_LAYOUTS), set(PINNED["narn"]))
        twin = skylark_parts["tank_r"].mirrored("x")
        p = np.array([(5.44, 1.71, 24.4)])
        right = skylark_parts["tank_r"].seams.evaluate(p, UP, LINE, DEPTH)
        left = twin.seams.evaluate(p * np.array([-1.0, 1.0, 1.0]), UP, LINE, DEPTH)
        np.testing.assert_allclose(left.tint, right.tint)
        np.testing.assert_allclose(left.height, right.height)

    def test_a_saturn_places_its_layouts_with_its_parts_and_leaves_structure_plain(self) -> None:
        v = saturn_family.VARIANTS["saturn_8_transport"]
        pieces = saturn_family.with_twins(saturn_family.assemble(v, EA_CIVILIAN))
        drawn = {p.name for p in pieces if p.part.seams}
        self.assertEqual(sum(1 for name in drawn if name.endswith("cylinder")), 2)
        self.assertEqual(sum(1 for name in drawn if "pod" in name), 8, "four pods and their twins")
        self.assertIn("disc", drawn)
        for p in pieces:
            if (any(word in p.name for word in PLAIN_WORDS) and not p.name.startswith("drum_")) or p.name.endswith(("arm", "arm_r", "arm_l")):
                self.assertFalse(p.part.seams, f"{p.name} stays plain")
        second = next(p for p in pieces if p.name == "s2_cylinder")
        ring = next(f for f in saturn_family.LAYOUTS["cylinder"].features() if isinstance(f, Cut) and f.level == MAJOR)
        z = v.section_start(1) + saturn.CYLINDER_Z[0] + ring.at
        on_ring = second.part.seams.evaluate(np.array([(0.0, saturn.CYLINDER_RADIUS, z)]), UP, LINE, DEPTH)
        self.assertAlmostEqual(float(on_ring.line[0]), 1.0, msg="the ring moved aft with its cylinder")


class FighterLayoutTests(unittest.TestCase):
    """The Starfury's and the raider's drawn surfaces (M7-T15): the maintainer's option A of each, its low set the major seams."""

    def test_the_generators_draw_the_layouts_from_parts_layouts(self) -> None:
        self.assertEqual(repr(starfury_aurora.LAYOUTS), repr(layouts.starfury()))
        self.assertEqual(starfury_aurora.DETAIL_LEVELS, {"low": MAJOR})
        self.assertEqual(raider_fighter.DETAIL_LEVELS, {"low": MAJOR})

    def test_the_layouts_are_the_same_every_time(self) -> None:
        self.assertEqual(repr(layouts.starfury()), repr(layouts.starfury()))
        spec = raider_fighter.DEFAULT_SPEC
        self.assertEqual(repr(raider_fighter.surface_layouts(spec)), repr(raider_fighter.surface_layouts(spec)))

    def test_the_starfurys_low_set_is_its_deck_frames_joints_and_pod_grooves(self) -> None:
        fury = layouts.starfury()
        for name in ("strut_ur", "strut_lr"):
            self.assertEqual(_positions(fury[name], Cut, MAJOR, axis=0), [1.97, 3.4], name)
            self.assertEqual(_positions(fury[name], Cut, MAJOR, axis=2), [-2.95, -1.45], name)
            frame = [f for f in fury[name].features() if isinstance(f, SeamPath) and f.level == MAJOR]
            self.assertEqual(len(frame), 1, name)
            for x, _, z in frame[0].points:  # inside the deck's outline, between its leading and trailing edges
                self.assertGreater(z, float(np.interp(x, *zip(*layouts._FURY_LE))), name)
                self.assertLess(z, float(np.interp(x, *zip(*reversed(layouts._FURY_TE)))), name)
        self.assertEqual(_positions(fury["fuselage"], Cut, MAJOR, axis=2), [-2.95, -1.45])
        self.assertEqual(_positions(fury["pod"], Cut, MAJOR, axis=2), [-0.95, 0.2])
        self.assertFalse([f for f in fury["claw"].features() if f.level == MAJOR], "the claws' teeth are full detail only")

    def test_the_starfurys_upper_decks_are_framed_and_its_lower_decks_swept(self) -> None:
        fury = layouts.starfury()
        channels = [f for f in fury["strut_ur"].features() if isinstance(f, SeamPath) and f.level == FULL]
        self.assertEqual(len(channels), 2, "two bent channels on each upper deck")
        self.assertTrue(all(len(f.points) == 4 and f.width == 2.6 for f in channels))
        strakes = [f for f in fury["strut_lr"].features() if isinstance(f, SeamPath) and f.level == FULL]
        self.assertEqual(len(strakes), 3)
        for f, inset in zip(strakes, (0.85, 1.5, 2.15)):
            for (x, _, z), (lx, lz) in zip(f.points, layouts._FURY_LE):
                self.assertAlmostEqual(x, lx)
                self.assertAlmostEqual(z - lz, inset / 0.847, msg="parallel to the leading edge")
        ports = [f for f in fury["strut_ur"].features() if isinstance(f, Hatch) and f.sunk > 1.0]
        self.assertEqual(len(ports), 2, "the oblong port and the cabin roof's round one")
        tones = {name: [f.tone for f in lay.features() if isinstance(f, Plates) and f.scatter == 0.0] for name, lay in fury.items()}
        self.assertEqual(tones, {"strut_ur": [0.06], "strut_lr": [0.045], "pod": [0.07], "fuselage": [0.06], "claw": []})

    def test_the_raiders_bays_each_hold_a_panel_and_the_outer_two_a_smaller_one_inside(self) -> None:
        spec = raider_fighter.DEFAULT_SPEC
        wing = raider_fighter.surface_layouts(spec)["wing_r"]
        self.assertEqual(_positions(wing, Cut, MAJOR, axis=0), [3.0, 5.7])
        band = [f for f in wing.features() if isinstance(f, SeamPath) and f.level == MAJOR]
        self.assertEqual(sorted(tuple(map(float, f.facing)) for f in band), [(0.0, -1.0, 0.0), (0.0, 1.0, 0.0)], "the edge band on top and belly")
        slope = 1.0 / np.tan(np.radians(spec.wing.sweep_deg))
        x, _, z = band[0].points[0]
        self.assertAlmostEqual(z - x * slope, layouts.RAIDER_EDGE_M / np.sin(np.radians(spec.wing.sweep_deg)))
        panels = [f for f in wing.features() if isinstance(f, SeamPath) and f.level == FULL and float(f.facing[1]) > 0.0]
        self.assertEqual(len(panels), 5)
        spans = sorted((round(min(p[0] for p in f.points), 2), round(max(p[0] for p in f.points), 2)) for f in panels)
        self.assertEqual(spans, [(2.12, 2.78), (3.28, 5.42), (3.75, 4.95), (5.95, 7.85), (6.3, 7.5)])
        teeth = [f for f in wing.features() if isinstance(f, Cut) and f.level == FULL and f.axis == 0]
        self.assertEqual(len(teeth), 19, "a row of teeth along the leading edge")
        louvres = [f for f in wing.features() if isinstance(f, Hatch) and f.slats]
        self.assertEqual(len(louvres), 2)
        plates = next(f for f in wing.features() if isinstance(f, Plates) and f.scatter == 0.0)
        self.assertEqual((plates.cell, plates.tone), ((2.2, 1.35), 0.07), "large plates, 7 % tone")


class BakedLayoutTests(unittest.TestCase):
    LAYOUT = SeamLayout.of([Cut(axis=2, at=0.0, level=MAJOR), Cut(axis=0, at=0.7, level=FULL),
                            Plates(level=PLATING, wrap="sides", cell=(1.5, 1.0), splits=1, min_m=0.3, tone=0.1, depth=0.0, dark=0.0, seed=2)])

    def _part(self, layout: SeamLayout = LAYOUT) -> list[TexturedPart]:
        return [TexturedPart(g.box((4.0, 4.0, 4.0), GREY), (0, 0, 0), name="hull", seams=layout)]

    def test_a_layout_is_baked_into_the_normal_roughness_and_colour_maps(self) -> None:
        atlas = atlas_of(self._part(), atlas_px=256, texel_m=0.04, style=EA_CIVILIAN, grid=False)
        plain = atlas_of(self._part(EMPTY), atlas_px=256, texel_m=0.04, style=EA_CIVILIAN, grid=False)
        drawn = bake_maps(atlas, EA_CIVILIAN, 1, occlusion=False, normal_scale=1)
        bare = bake_maps(plain, EA_CIVILIAN, 1, occlusion=False, normal_scale=1)
        b = atlas.buffers
        on_seam = b.filled & (np.abs(b.position[..., 2]) < 0.02) & (np.abs(b.normal[..., 2]) < 0.5)
        away = b.filled & (np.abs(b.position[..., 2]) > 0.5) & (np.abs(b.position[..., 0] - 0.7) > 0.5) & (np.abs(b.normal[..., 1]) > 0.9)
        self.assertGreater(int(on_seam.sum()), 20)
        self.assertLess(drawn["albedo"][on_seam].mean(), 0.92 * bare["albedo"][on_seam].mean(), "a darker line")
        self.assertGreater(drawn["orm"][on_seam, 1].mean(), bare["orm"][on_seam, 1].mean() + 20, "rougher in the groove")
        tilt = np.abs(drawn["normal"].astype(int) - np.array([128, 128, 255]))[..., :2].max(axis=-1)
        beside = b.filled & (np.abs(np.abs(b.position[..., 2]) - 0.5 * seam_size(0.04)[0] * 0.5) < 0.03) & (np.abs(b.normal[..., 2]) < 0.5)
        self.assertGreater(tilt[beside].max(), 20, "the groove's walls lean")
        self.assertGreater(len(np.unique(drawn["albedo"][away][:, 0])), len(np.unique(bare["albedo"][away][:, 0])), "plates of their own tone")

    def test_a_hull_with_layouts_is_written_with_a_low_set_beside_the_full_one(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            paths, section = write_textured_mesh(out, "probe", self._part(), EA_CIVILIAN, atlas_px=128, texel_m=0.08, occlusion=False,
                                                 normal_scale=1, grid=False, detail_levels=DETAIL_LEVELS)
            self.assertEqual(DETAIL_LEVELS, {"low": MAJOR})
            surface = section["surfaces"][0]
            self.assertEqual(surface["detail"], {"low": {"albedo": "probe_albedo_low.png", "normal": "probe_normal_low.png", "orm": "probe_orm_low.png"}})
            names = {p.name for p in paths}
            for file in surface["detail"]["low"].values():
                self.assertIn(file, names)
                self.assertTrue((out / (file + ".import")).is_file())
                self.assertEqual((out / (file + ".import")).read_text(), (out / (file.replace("_low", "") + ".import")).read_text())
            self.assertNotIn("probe_emissive_low.png", names, "the glow is one map for both sets")
            self.assertNotEqual((out / "probe_albedo_low.png").read_bytes(), (out / "probe_albedo.png").read_bytes())
            self.assertNotEqual((out / "probe_normal_low.png").read_bytes(), (out / "probe_normal.png").read_bytes())
            json.dumps(section)

    def test_a_model_without_layouts_gets_one_set(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            paths, section = write_textured_mesh(Path(tmp), "plain", self._part(EMPTY), EA_CIVILIAN, atlas_px=128, texel_m=0.08, occlusion=False,
                                                 normal_scale=1, grid=False, detail_levels=DETAIL_LEVELS)
            self.assertNotIn("detail", section["surfaces"][0])
            self.assertFalse([p for p in paths if "_low" in p.name])


if __name__ == "__main__":
    unittest.main()
