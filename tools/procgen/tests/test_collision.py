"""``core/collision.py`` (M7's D73, built in M12-T19): the convex shapes, hulls inside a point budget, concave parts cut into
sectors, merging down to a piece budget, coverage both ways, the manifest's section and determinism."""

from __future__ import annotations

import json
import math
import unittest

import numpy as np

from tools.procgen.core import collision as col
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.geometry import Material, box, lathe
from tools.procgen.core.sampling import sample_mesh

GREY = Material("grey", (0.5, 0.5, 0.5))


def surface_of(mesh, spacing: float = 0.1) -> np.ndarray:
    return sample_mesh(mesh, spacing, np.random.default_rng(3), systematic=True).positions


def ring_mesh(r_inner: float, r_outer: float, z0: float, z1: float):
    """A square-section ring about z: outer wall, back face, inner wall, front face."""
    return lathe([(z0, r_inner), (z0, r_outer), (z1, r_outer), (z1, r_inner), (z0, r_inner)], 96, GREY, creases=(1, 2, 3))


class ShapeTests(unittest.TestCase):
    def test_a_box_measures_distance_exactly(self) -> None:
        b = col.Shape.box("b", (1.0, 0.0, 0.0), (2.0, 4.0, 6.0))
        d = b.distance(np.array([[1.0, 0.0, 0.0], [3.0, 0.0, 0.0], [2.0, 2.0, 3.0], [3.0, 3.0, 4.0]]))
        np.testing.assert_allclose(d, [-1.0, 1.0, 0.0, math.sqrt(3.0)], atol=1e-12)
        self.assertAlmostEqual(b.volume(), 48.0)
        self.assertAlmostEqual(b.bound_radius(), math.sqrt(1 + 4 + 9))

    def test_a_capsule_runs_between_its_end_points(self) -> None:
        c = col.Shape.capsule("c", (0.0, 0.0, 0.0), (0.0, 10.0, 0.0), 1.0)
        self.assertAlmostEqual(c.height, 12.0)
        d = c.distance(np.array([[0.0, 5.0, 0.0], [2.0, 5.0, 0.0], [0.0, 12.0, 0.0], [0.0, -1.0, 0.0]]))
        np.testing.assert_allclose(d, [-1.0, 1.0, 1.0, 0.0], atol=1e-12)
        lo, hi = c.bounds()
        np.testing.assert_allclose(lo, [-1.0, -1.0, -1.0], atol=1e-12)
        np.testing.assert_allclose(hi, [1.0, 11.0, 1.0], atol=1e-12)
        np.testing.assert_allclose(np.abs(c.distance(c.surface_points(0.3))).max(), 0.0, atol=1e-9)

    def test_a_hull_keeps_only_its_corners(self) -> None:
        cube = col.Shape.box("b", (0.0, 0.0, 0.0), (2.0, 2.0, 2.0)).corners()
        inside = np.random.default_rng(0).uniform(-0.9, 0.9, (40, 3))
        on_a_face = np.array([[1.0, 0.2, -0.3], [0.0, 1.0, 0.0]])
        h = col.Shape.hull("h", np.concatenate([cube, inside, on_a_face]))
        self.assertEqual(len(h.points), 8)
        self.assertAlmostEqual(h.volume(), 8.0)
        np.testing.assert_allclose(h.distance(np.array([[0.0, 0.0, 0.0], [1.5, 0.0, 0.0]])), [-1.0, 0.5], atol=1e-9)
        np.testing.assert_allclose(np.abs(h.distance(h.surface_points(0.25))).max(), 0.0, atol=1e-9)

    def test_a_flat_point_set_is_refused(self) -> None:
        flat = np.array([[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [1.0, 1.0, 0.0], [0.5, 0.5, 0.0]])
        with self.assertRaisesRegex(ValueError, "not in one plane"):
            col.Shape.hull("flat", flat)

    def test_a_hull_holds_to_its_point_budget(self) -> None:
        rng = np.random.default_rng(1)
        ball = rng.normal(size=(4000, 3))
        ball /= np.linalg.norm(ball, axis=1, keepdims=True)
        for limit in (12, 32):
            h = col.Shape.hull("ball", ball, limit)
            self.assertLessEqual(len(h.points), limit)
            self.assertGreater(len(h.points), limit // 2)
            # Every kept corner is one of the given points, so the cut hull is inside the full one.
            self.assertLess(h.distance(ball).max(), 0.6 if limit == 12 else 0.25)
            self.assertLessEqual(h.volume(), 4.0 / 3.0 * math.pi)

    def test_moves_and_mirrors_keep_the_shape(self) -> None:
        probe = np.array([[0.3, 0.2, 0.1], [4.0, 1.0, -2.0]])
        mirror = np.diag([-1.0, 1.0, 1.0])
        for shape in (
            col.Shape.box("b", (2.0, 1.0, 0.0), (1.0, 2.0, 3.0)),
            col.Shape.capsule("c", (1.0, 0.0, 0.0), (4.0, 2.0, 1.0), 0.5),
            col.Shape.hull("h", np.array([[0.0, 0.0, 0.0], [3.0, 0.0, 0.0], [0.0, 2.0, 0.0], [0.0, 0.0, 1.0], [3.0, 2.0, 1.0]])),
        ):
            twin = shape.mirrored("x")
            np.testing.assert_allclose(twin.distance(probe @ mirror), shape.distance(probe), atol=1e-9, err_msg=shape.kind)
            moved = shape.translated((0.0, 5.0, 0.0))
            np.testing.assert_allclose(moved.distance(probe + [0.0, 5.0, 0.0]), shape.distance(probe), atol=1e-9, err_msg=shape.kind)
            self.assertAlmostEqual(twin.volume(), shape.volume(), places=9)


class RingTests(unittest.TestCase):
    def test_a_ring_is_covered_and_its_hole_stays_open(self) -> None:
        sectors = col.ring_sectors("ring", (0.0, 0.0, 0.0), (0.0, 0.0, 1.0), 9.0, 10.0, 0.0, 2.0, 12)
        self.assertEqual(len(sectors), 12)
        self.assertTrue(all(len(s.points) == 10 for s in sectors))
        surface = surface_of(ring_mesh(9.0, 10.0, 0.0, 2.0))
        self.assertLessEqual(col.gaps(sectors, surface).max(), 1e-9, "the whole ring is inside its sectors")
        # A fighter's worth of room through the middle: nothing within 8.5 m of the axis.
        axis = np.array([[x, y, 1.0] for x in np.linspace(-6.0, 6.0, 13) for y in np.linspace(-6.0, 6.0, 13)])
        self.assertGreater(col.gaps(sectors, axis).min(), 9.0 * math.cos(math.pi / 12.0) - 8.5 - 1e-9)
        cover = col.coverage(sectors, surface, tolerance_m=0.05, reach_m=0.4, spacing_m=0.1)
        self.assertTrue(cover.ok, cover)
        self.assertLess(cover.worst_excess_m, 9.0 * (1.0 - math.cos(math.pi / 12.0)) + 0.05)

    def test_one_hull_round_a_ring_fails_the_reach_check(self) -> None:
        surface = surface_of(ring_mesh(9.0, 10.0, 0.0, 2.0))
        plug = [col.Shape.hull("plug", col.prism_points((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), [(0.0, 10.0), (2.0, 10.0)], 16))]
        cover = col.coverage(plug, surface, tolerance_m=0.05, reach_m=0.5, spacing_m=0.25)
        self.assertEqual(cover.covered, 1.0)
        self.assertFalse(cover.ok, "the hull fills the hole")
        self.assertGreater(cover.worst_excess_m, 8.0)

    def test_prism_points_hold_the_round_part(self) -> None:
        drum = lathe([(0.0, 0.0), (0.0, 3.0), (5.0, 3.0), (5.0, 0.0)], 64, GREY, creases=(1, 2))
        hull = col.Shape.hull("drum", col.prism_points((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), [(0.0, 3.0), (5.0, 3.0)], 16))
        self.assertEqual(len(hull.points), 32)
        cover = col.coverage([hull], surface_of(drum), tolerance_m=0.02, reach_m=0.2, spacing_m=0.1)
        self.assertTrue(cover.ok, cover)


class CoverageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.mesh = box((2.0, 2.0, 6.0), GREY)
        self.surface = surface_of(self.mesh)

    def test_an_exact_fit_is_covered_with_no_excess(self) -> None:
        cover = col.coverage([col.Shape.box("b", (0.0, 0.0, 0.0), (2.0, 2.0, 6.0))], self.surface, 0.05, 0.3, 0.1)
        self.assertTrue(cover.ok)
        self.assertLessEqual(cover.worst_gap_m, 1e-9)
        self.assertLessEqual(cover.worst_excess_m, 0.05)

    def test_a_short_shape_leaves_a_gap(self) -> None:
        cover = col.coverage([col.Shape.box("b", (0.0, 0.0, -1.0), (2.0, 2.0, 4.0))], self.surface, 0.05, 0.3, 0.1)
        self.assertFalse(cover.ok)
        self.assertLess(cover.covered, 0.8)
        self.assertAlmostEqual(cover.worst_gap_m, 2.0, delta=0.02)

    def test_an_oversized_shape_is_out_of_reach(self) -> None:
        cover = col.coverage([col.Shape.box("b", (0.0, 0.0, 0.0), (2.0, 6.0, 6.0))], self.surface, 0.05, 0.3, 0.1)
        self.assertEqual(cover.covered, 1.0)
        self.assertFalse(cover.ok)
        self.assertAlmostEqual(cover.worst_excess_m, 2.0, delta=0.15)

    def test_nearest_distance_agrees_with_a_direct_search(self) -> None:
        rng = np.random.default_rng(5)
        points, queries = rng.uniform(0.0, 10.0, (3000, 3)), rng.uniform(-3.0, 13.0, (400, 3))
        direct = np.array([np.linalg.norm(points - q, axis=1).min() for q in queries])
        found = col.nearest_distance(queries, points, 0.5)
        near = direct <= 0.5
        np.testing.assert_allclose(found[near], direct[near], atol=1e-9, err_msg="exact within a cell")
        self.assertTrue(np.all(found[~near] >= direct[~near] - 1e-9), "never short")
        self.assertLess(np.max(found[~near] / direct[~near]), 1.5, "a far one is good to about half")


class BudgetTests(unittest.TestCase):
    def row(self, count: int) -> list[col.Shape]:
        """Boxes in a row along x, in touching pairs with a wide gap between pairs."""
        return [col.Shape.box(f"b{k}", (5.0 * (k // 2) + (k % 2), 0.0, 0.0), (1.0, 1.0, 1.0)) for k in range(count)]

    def test_shapes_inside_the_budget_are_left_alone(self) -> None:
        shapes = self.row(6)
        out = col.fit_budget(shapes, col.Budget(max_pieces=6))
        self.assertEqual([s.name for s in out], [s.name for s in shapes])
        self.assertTrue(all(a is b for a, b in zip(out, shapes, strict=True)))

    def test_the_cheapest_neighbours_are_merged_first(self) -> None:
        shapes = self.row(8)
        out = col.fit_budget(shapes, col.Budget(max_pieces=4))
        self.assertEqual(len(out), 4)
        # Each touching pair became one box-shaped hull; no hull bridges the wide gaps.
        for k, s in enumerate(out):
            self.assertEqual(s.kind, col.HULL)
            self.assertAlmostEqual(s.volume(), 2.0, places=6)
            lo, hi = s.bounds()
            np.testing.assert_allclose([lo[0], hi[0]], [5.0 * k - 0.5, 5.0 * k + 1.5], atol=1e-9)
        corners = np.concatenate([s.corners() for s in shapes])
        self.assertLessEqual(col.gaps(out, corners).max(), 1e-9, "every original corner is still inside")

    def test_build_enforces_both_budgets(self) -> None:
        compound = col.build({"hull": self.row(8)}, col.Budget(max_pieces=3))
        self.assertEqual(len(compound.pieces["hull"]), 3)
        many = np.random.default_rng(2).normal(size=(200, 3))
        many /= np.linalg.norm(many, axis=1, keepdims=True)
        fat = col.Shape(col.HULL, "fat", (0.0, 0.0, 0.0), np.eye(3), points=col.reduce_points(many, 40))
        with self.assertRaisesRegex(ValueError, "over the budget of 32"):
            col.build({"hull": [fat]})
        with self.assertRaisesRegex(ValueError, "one name"):
            col.build({"hull": [self.row(1)[0], self.row(1)[0]]})
        with self.assertRaisesRegex(ValueError, "no shape"):
            col.build({"hull": []})


class SectionTests(unittest.TestCase):
    def parts(self) -> dict[str, list[col.Shape]]:
        ring = col.ring_sectors("ring", (0.0, 0.0, 4.0), (0.0, 0.0, 1.0), 4.0, 5.0, -0.5, 0.5, 8)
        arm = col.Shape.capsule("arm", (5.0, 0.0, 4.0), (9.0, 0.0, 4.0), 0.4)
        return {"body": [col.Shape.box("body", (0.0, 0.0, 0.0), (2.0, 2.0, 6.0))], "ring": [*ring, arm, arm.mirrored("x").renamed("arm_l")]}

    def test_the_section_lists_pieces_and_shapes_in_the_body_frame(self) -> None:
        offset = np.array([0.0, 0.5, 1.0])
        compound = col.build(self.parts())
        section = compound.to_json(offset)
        col.validate_section(section)
        self.assertEqual([p["name"] for p in section["pieces"]], ["body", "ring"])
        self.assertEqual(section["shape_count"], 11)
        self.assertEqual(section["budget"], {"max_pieces": 64, "max_hull_points": 32})
        body = section["pieces"][0]["shapes"][0]
        self.assertEqual((body["type"], body["position"], body["size"]), ("box", [0.0, -0.5, -1.0], [2.0, 2.0, 6.0]))
        arm = section["pieces"][1]["shapes"][8]
        self.assertEqual((arm["type"], arm["axis"], arm["radius"], arm["height"]), ("capsule", "z", 0.4, 4.8))
        np.testing.assert_allclose(arm["basis"]["z"], [1.0, 0.0, 0.0], atol=1e-9)
        sector = section["pieces"][1]["shapes"][0]
        self.assertEqual((sector["type"], len(sector["points"])), ("hull", 10))
        self.assertNotIn("coverage", section)

    def test_a_manifest_with_the_section_validates_and_a_broken_one_does_not(self) -> None:
        section = col.build(self.parts()).to_json()
        manifest = manifest_io.build_manifest("probe", 1, 0, (-1, -1, -1), (1, 1, 1), (0, 0, 0), extra={"collision": section})
        self.assertEqual(manifest["collision"]["shape_count"], 11)
        broken = json.loads(json.dumps(section))
        broken["pieces"][1]["shapes"][0]["points"] = broken["pieces"][1]["shapes"][0]["points"][:3]
        with self.assertRaisesRegex(ValueError, "needs 4 to 32 points"):
            manifest_io.build_manifest("probe", 1, 0, (-1, -1, -1), (1, 1, 1), (0, 0, 0), extra={"collision": broken})
        with self.assertRaisesRegex(ValueError, "non-empty 'pieces'"):
            col.validate_section({"budget": {"max_pieces": 1, "max_hull_points": 8}, "pieces": []})

    def test_the_section_reads_back_as_the_same_shapes(self) -> None:
        offset = np.array([0.0, 0.5, 1.0])
        compound = col.build(self.parts())
        back = col.shapes_of(compound.to_json(offset))
        probe = np.random.default_rng(3).uniform(-10.0, 10.0, (400, 3))
        self.assertEqual([s.name for s in back], [s.name for s in compound.shapes])
        for was, now in zip(compound.shapes, back, strict=True):
            np.testing.assert_allclose(now.distance(probe - offset), was.distance(probe), atol=1e-4, err_msg=was.name)

    def test_the_same_parts_give_the_same_section(self) -> None:
        def text() -> str:
            compound = col.build(self.parts(), col.Budget(max_pieces=6))
            surface = surface_of(box((2.0, 2.0, 6.0), GREY), 0.25)
            return json.dumps(compound.to_json((0.0, 0.0, 0.0), col.coverage(compound.shapes, surface, 0.1, 0.5, 0.25)), sort_keys=True)

        self.assertEqual(text(), text())


if __name__ == "__main__":
    unittest.main()
