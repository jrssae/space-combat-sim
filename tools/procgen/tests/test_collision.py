"""``core/collision.py`` (M7-T03, D73): convex shapes from parts, the merge down to a budget, the coverage measure, the
manifest section and the hit volumes. The Saturns' own collision pieces are checked in ``test_saturn_family.py``."""

from __future__ import annotations

import copy
import itertools
import json
import math
import unittest

import numpy as np

from tools.procgen.core import collision as col
from tools.procgen.core import manifest
from tools.procgen.core.geometry import Material, box as box_mesh, rotation_y

GREY = Material("grey", (0.5, 0.5, 0.5))


def cube_points(size: float = 2.0, at: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> np.ndarray:
    return np.array(list(itertools.product((-0.5 * size, 0.5 * size), repeat=3))) + np.array(at)


def sphere_points(count: int, radius: float = 1.0) -> np.ndarray:
    k = np.arange(count) + 0.5
    polar, turn = np.arccos(1.0 - 2.0 * k / count), np.pi * (1.0 + 5.0**0.5) * k
    return radius * np.column_stack([np.sin(polar) * np.cos(turn), np.sin(polar) * np.sin(turn), np.cos(polar)])


def triangles_of(mesh) -> np.ndarray:
    return np.stack(mesh.corners(), axis=1)


class HullTests(unittest.TestCase):
    def test_a_cube_keeps_its_eight_corners_however_many_points_fill_it(self) -> None:
        rng = np.random.default_rng(1)
        points = np.concatenate([cube_points(), rng.uniform(-1.0, 1.0, (500, 3))])
        corners, residual = col.convex_points(points)
        self.assertEqual(len(corners), 8)
        self.assertEqual(residual, 0.0)
        faces = col.hull_faces(corners)
        self.assertEqual(len(faces.normals), 6, "one plane per face, not one per triangle")
        self.assertEqual(len(faces.edges), 12)
        self.assertTrue(all(len(ring) == 4 for ring in faces.polygons))

    def test_a_round_shape_is_cut_to_the_point_budget_and_says_what_it_lost(self) -> None:
        points = sphere_points(2000)
        corners, residual = col.convex_points(points, 32)
        self.assertEqual(len(corners), 32)
        self.assertGreater(residual, 0.0)
        self.assertLess(residual, 0.15, "32 well chosen corners hold a unit sphere within 15 cm")
        more, less_lost = col.convex_points(points, 64)
        self.assertEqual(len(more), 64)
        self.assertLess(less_lost, residual)
        # Every corner kept is one of the points given, never an invented one.
        self.assertTrue(all(np.any(np.all(points == c, axis=1)) for c in corners))

    def test_flat_or_too_few_points_are_refused(self) -> None:
        flat = np.array([[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [1.0, 1.0, 0.0], [0.3, 0.6, 0.0]])
        with self.assertRaises(ValueError):
            col.hull("flat", flat)
        with self.assertRaises(ValueError):
            col.hull("few", flat[:3])

    def test_points_that_start_flat_along_the_axes_still_make_a_hull(self) -> None:
        # A tetrahedron's axis extremes can repeat; the builder must still find a fourth corner.
        tetra = np.array([[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]])
        self.assertEqual(len(col.hull("tetra", tetra).points), 4)


class DistanceTests(unittest.TestCase):
    def test_a_box_measures_from_faces_edges_and_corners(self) -> None:
        shape = col.box("b", (1.0, 0.0, 0.0), (2.0, 4.0, 6.0))
        points = np.array([[1.0, 0.0, 0.0], [3.0, 0.0, 0.0], [3.0, 3.0, 0.0], [3.0, 3.0, 4.0]])
        np.testing.assert_allclose(shape.distance(points), [0.0, 1.0, math.sqrt(2.0), math.sqrt(3.0)])

    def test_a_turned_box_measures_in_its_own_axes(self) -> None:
        shape = col.box("b", (0.0, 0.0, 0.0), (2.0, 2.0, 10.0), rotation_y(math.pi / 2.0))
        np.testing.assert_allclose(shape.distance(np.array([[6.0, 0.0, 0.0], [0.0, 0.0, 3.0]])), [1.0, 2.0], atol=1e-12)

    def test_a_capsule_runs_along_its_z_with_round_ends(self) -> None:
        shape = col.capsule("c", (0.0, 0.0, 0.0), 1.0, 6.0)
        points = np.array([[0.0, 0.0, 3.0], [0.0, 0.0, 4.0], [2.0, 0.0, 0.0], [1.0, 0.0, 3.0]])
        np.testing.assert_allclose(shape.distance(points), [0.0, 1.0, 1.0, math.sqrt(2.0) - 1.0])

    def test_a_hull_measures_like_the_box_it_is(self) -> None:
        rng = np.random.default_rng(3)
        as_box, as_hull = col.box("b", (0.5, -1.0, 2.0), (2.0, 3.0, 4.0)), col.hull("h", cube_points(1.0) * (2.0, 3.0, 4.0) + (0.5, -1.0, 2.0))
        points = rng.uniform(-6.0, 6.0, (400, 3))
        np.testing.assert_allclose(as_hull.distance(points), as_box.distance(points), atol=1e-9)


class MergeTests(unittest.TestCase):
    def row(self) -> list[col.Shape]:
        """Four unit cubes in a row: two touching pairs, 10 m apart."""
        return [col.box(f"b{i}", (x, 0.0, 0.0), (1.0, 1.0, 1.0)) for i, x in enumerate((0.0, 1.0, 10.0, 11.0))]

    def test_shapes_inside_the_budget_are_left_alone(self) -> None:
        shapes = self.row()
        self.assertEqual(col.merge_to_budget(shapes, col.Budget(max_shapes=4)), shapes)

    def test_neighbours_are_joined_first(self) -> None:
        merged = col.merge_to_budget(self.row(), col.Budget(max_shapes=2))
        self.assertEqual([s.kind for s in merged], ["hull", "hull"])
        self.assertEqual([s.name for s in merged], ["b0", "b2"])
        np.testing.assert_allclose(merged[0].bounds(), ([-0.5, -0.5, -0.5], [1.5, 0.5, 0.5]))
        np.testing.assert_allclose(merged[1].bounds(), ([9.5, -0.5, -0.5], [11.5, 0.5, 0.5]))

    def test_a_merged_hull_holds_both_shapes_and_the_point_budget(self) -> None:
        shapes = [col.capsule("tank", (0.0, 0.0, 0.0), 2.0, 12.0), col.hull("ball", sphere_points(400, 2.0) + (5.0, 0.0, 0.0))]
        budget = col.Budget(max_shapes=1, max_hull_points=16)
        (merged,) = col.merge_to_budget(shapes, budget)
        self.assertLessEqual(len(merged.points), 16)
        col.check_budget("piece", [merged], budget)
        # Cut to 16 corners it sits a little inside the two round shapes (2 m radius), never far.
        self.assertLess(merged.distance(np.concatenate([s.corners() for s in shapes])).max(), 1.0)

    def test_over_budget_is_an_error(self) -> None:
        with self.assertRaisesRegex(ValueError, "5 collision shapes"):
            col.check_budget("piece", [col.box(f"b{i}", (i, 0, 0), (1, 1, 1)) for i in range(5)], col.Budget(max_shapes=4))
        with self.assertRaisesRegex(ValueError, "points"):
            col.check_budget("piece", [col.hull("ball", sphere_points(200), 32)], col.Budget(max_hull_points=16))

    def test_the_defaults_are_the_documented_budget(self) -> None:
        self.assertEqual((col.Budget().max_shapes, col.Budget().max_hull_points), (128, 32))


class CoverageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.render = triangles_of(box_mesh((4.0, 2.0, 10.0), GREY))

    def test_a_shape_that_is_the_render_box_fits_exactly(self) -> None:
        fit = col.coverage(self.render, [col.box("b", (0.0, 0.0, 0.0), (4.0, 2.0, 10.0))], 0.5)
        self.assertAlmostEqual(fit.max_gap_m, 0.0)
        self.assertLess(fit.max_excess_m, 0.5, "the excess is measured to the probes, so it reads up to a step long")
        fit.check(0.01, 0.5)

    def test_render_surface_left_uncovered_is_a_gap(self) -> None:
        # The shape stops 3 m short of the render box's far end; the big end triangles are probed inside, not only at corners.
        fit = col.coverage(self.render, [col.box("b", (0.0, 0.0, -1.5), (4.0, 2.0, 7.0))], 0.5)
        self.assertAlmostEqual(fit.max_gap_m, 3.0)
        self.assertEqual(fit.gap_at[2], 5.0)
        with self.assertRaisesRegex(ValueError, "from any collision shape"):
            fit.check(1.0, 1.0)

    def test_a_shape_reaching_past_the_render_surface_is_excess(self) -> None:
        shapes = [col.box("b", (0.0, 0.0, 0.0), (4.0, 2.0, 10.0)), col.box("stray", (0.0, 6.0, 0.0), (1.0, 1.0, 1.0))]
        fit = col.coverage(self.render, shapes, 0.5)
        self.assertAlmostEqual(fit.max_gap_m, 0.0)
        self.assertAlmostEqual(fit.max_excess_m, 5.5, delta=0.3)
        self.assertEqual(fit.excess_shape, "stray")
        with self.assertRaisesRegex(ValueError, "'stray'"):
            fit.check(1.0, 1.0)

    def test_any_one_shape_near_a_point_covers_it(self) -> None:
        halves = [col.box("fore", (0.0, 0.0, -2.5), (4.0, 2.0, 5.0)), col.capsule("aft", (0.0, 0.0, 2.5), 2.3, 9.6)]
        self.assertLess(col.coverage(self.render, halves, 0.5).max_gap_m, 0.05)

    def test_probes_cover_big_triangles_at_the_step(self) -> None:
        probes = col.surface_probes(self.render, 0.5)
        end = probes[np.isclose(probes[:, 2], 5.0)]
        self.assertGreater(len(end), 40, "a 4 x 2 m end face probed every 0.5 m")
        self.assertTrue(np.any(np.all(np.abs(end[:, :2]) < 0.6, axis=1)), "and in its middle")


class SectionTests(unittest.TestCase):
    def shapes(self) -> list[col.Shape]:
        return [
            col.box("deck", (0.0, 0.0, 0.0), (4.0, 1.0, 8.0), rotation_y(0.3)),
            col.capsule("tank", (0.0, 3.0, 0.0), 1.5, 9.0),
            col.hull("wedge", np.array([[0.0, 0.0, 6.0], [2.0, 0.0, 6.0], [0.0, 1.0, 6.0], [0.0, 0.0, 9.0], [2.0, 0.0, 9.0]])),
        ]

    def test_the_section_passes_the_manifest_contract(self) -> None:
        section = col.section({"frame": self.shapes(), "drum": self.shapes()[:1]})
        self.assertEqual((section["max_shapes"], section["max_hull_points"]), (128, 32))
        self.assertEqual([p["name"] for p in section["pieces"]], ["frame", "drum"])
        self.assertEqual([s["type"] for s in section["pieces"][0]["shapes"]], ["box", "capsule", "hull"])
        manifest.build_manifest("demo", 1, 1, [-9, -9, -9], [9, 9, 9], [0, 0, 0], extra={"collision": section})

    def test_the_piece_bounds_hold_every_shape(self) -> None:
        piece = col.piece_entry("frame", self.shapes())
        lo, hi, centre = (np.array(v) for v in (piece["aabb_min"], piece["aabb_max"], piece["bound"]["center"]))
        radius = piece["bound"]["radius"]
        for shape in self.shapes():
            corners = shape.corners()
            self.assertTrue(np.all(corners >= lo - 1e-4) and np.all(corners <= hi + 1e-4), shape.name)
            self.assertLessEqual(np.linalg.norm(corners - centre, axis=1).max(), radius + 1e-4, shape.name)

    def test_hit_volumes_are_boxes_and_capsules_around_the_same_shapes(self) -> None:
        shapes = self.shapes()
        piece = col.piece_entry("frame", shapes)
        self.assertEqual([v["type"] for v in piece["hit_volumes"]], ["box", "capsule", "box"])
        self.assertEqual([v["name"] for v in piece["hit_volumes"]], [s.name for s in shapes])
        self.assertEqual(piece["hit_volumes"][:2], piece["shapes"][:2], "a box and a capsule are their own hit volume")
        volumes = col.shapes_from_entry(piece, "hit_volumes")
        for shape, volume in zip(shapes, volumes):
            self.assertLess(volume.distance(shape.corners()).max(), 1e-4, f"{shape.name} is inside its hit volume")

    def test_a_slanted_hull_gets_a_box_along_its_own_axes(self) -> None:
        turn = rotation_y(0.6)
        slab = col.hull("slab", (cube_points(1.0) * (10.0, 1.0, 2.0)) @ turn.T)
        volume = slab.hit_volume()
        self.assertAlmostEqual(float(np.prod(volume.size)), 20.0, places=6, msg="the slab's own volume, not its axis-aligned box's")

    def test_the_section_reads_back_as_the_same_shapes(self) -> None:
        piece = col.piece_entry("frame", self.shapes())
        rng = np.random.default_rng(5)
        points = rng.uniform(-8.0, 8.0, (300, 3))
        for shape, back in zip(self.shapes(), col.shapes_from_entry(piece)):
            np.testing.assert_allclose(back.distance(points), shape.distance(points), atol=1e-3)

    def test_the_same_shapes_give_the_same_bytes(self) -> None:
        a = json.dumps(col.section({"frame": self.shapes()}))
        b = json.dumps(col.section({"frame": self.shapes()}))
        self.assertEqual(a, b)
        self.assertNotIn("-0.0,", a)

    def test_the_section_merges_down_to_its_budget(self) -> None:
        row = [col.box(f"b{i}", (2.0 * i, 0.0, 0.0), (1.0, 1.0, 1.0)) for i in range(9)]
        section = col.section({"row": row}, col.Budget(max_shapes=4, max_hull_points=8))
        self.assertEqual(len(section["pieces"][0]["shapes"]), 4)
        self.assertEqual(len(section["pieces"][0]["hit_volumes"]), 4)
        manifest.validate_collision_section(section)

    def test_an_empty_piece_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            col.section({"frame": []})


class ManifestCollisionTests(unittest.TestCase):
    def section(self) -> dict:
        return col.section({"frame": SectionTests().shapes()})

    def broken(self, edit) -> dict:
        section = copy.deepcopy(self.section())
        edit(section)
        return section

    def test_values_that_are_not_finite_are_refused(self) -> None:
        for bad in (float("nan"), float("inf")):
            for edit in (
                lambda s, v=bad: s["pieces"][0]["shapes"][0]["position"].__setitem__(0, v),
                lambda s, v=bad: s["pieces"][0]["shapes"][1].__setitem__("radius", v),
                lambda s, v=bad: s["pieces"][0]["shapes"][2]["points"][0].__setitem__(1, v),
                lambda s, v=bad: s["pieces"][0]["hit_volumes"][2]["size"].__setitem__(2, v),
                lambda s, v=bad: s["pieces"][0]["bound"].__setitem__("radius", v),
                lambda s, v=bad: s["pieces"][0]["aabb_min"].__setitem__(0, v),
            ):
                with self.assertRaises(ValueError):
                    manifest.validate_collision_section(self.broken(edit))

    def test_a_piece_over_the_stated_budget_is_refused(self) -> None:
        with self.assertRaisesRegex(ValueError, "over the budget"):
            manifest.validate_collision_section(self.broken(lambda s: s.__setitem__("max_shapes", 2)))
        with self.assertRaisesRegex(ValueError, "points"):
            manifest.validate_collision_section(self.broken(lambda s: s.__setitem__("max_hull_points", 4)))

    def test_malformed_sections_are_refused(self) -> None:
        for edit in (
            lambda s: s.__setitem__("pieces", []),
            lambda s: s["pieces"].append(copy.deepcopy(s["pieces"][0])),  # a name twice
            lambda s: s["pieces"][0]["shapes"][0].__setitem__("type", "sphere"),
            lambda s: s["pieces"][0]["hit_volumes"][0].__setitem__("type", "hull"),
            lambda s: s["pieces"][0]["shapes"][0].__setitem__("size", [1.0, 0.0, 1.0]),
            lambda s: s["pieces"][0]["shapes"][1].__setitem__("height", 1.0),
            lambda s: s["pieces"][0]["shapes"][0].pop("basis"),
            lambda s: s["pieces"][0].pop("hit_volumes"),
            lambda s: s.pop("max_shapes"),
        ):
            with self.assertRaises(ValueError):
                manifest.validate_collision_section(self.broken(edit))

    def test_a_manifest_carries_the_section_through_validation(self) -> None:
        m = manifest.build_manifest("demo", 1, 1, [-9, -9, -9], [9, 9, 9], [0, 0, 0], extra={"collision": self.section()})
        m["collision"]["pieces"][0]["shapes"][0]["position"][0] = float("nan")
        with self.assertRaises(ValueError):
            manifest.validate_manifest(m)


if __name__ == "__main__":
    unittest.main()
