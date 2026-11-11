"""``jumpgate``'s pure helpers and its geometry without the texture bake (quick tier): the layout, the markers and the vortex's
colours, the four-fold symmetry, the collision boxes covering every vertex and the vortex left clear."""

from __future__ import annotations

import math
import unittest

import numpy as np

from tools.procgen.assets import jumpgate as jg
from tools.procgen.core.geometry import Mesh, polygon_area_2d


def rounded_set(vertices: np.ndarray, digits: int = 3) -> set[tuple[float, float, float]]:
    """Vertices as a set at millimetre precision (rotations leave float dust)."""
    return {tuple(row) for row in (np.round(vertices, digits) + 0.0).tolist()}


def boxes_contain(shapes: list[dict], points: np.ndarray, tol: float) -> np.ndarray:
    """Per point: inside at least one of the collision boxes (hardpoints schema), within ``tol`` metres."""
    inside = np.zeros(len(points), dtype=bool)
    for s in shapes:
        basis = np.stack([s["basis"]["x"], s["basis"]["y"], s["basis"]["z"]], axis=1)
        local = (points - np.array(s["position"])) @ basis
        inside |= np.all(np.abs(local) <= 0.5 * np.array(s["size"]) + tol, axis=1)
    return inside


class LayoutTests(unittest.TestCase):
    def test_the_default_scale(self) -> None:
        layout = jg.GateLayout()
        self.assertEqual(layout.arm_length_m, 1200.0)
        self.assertAlmostEqual(layout.inner_radius_m, 800.0)
        self.assertAlmostEqual(layout.vortex_radius_m, 720.0)
        self.assertAlmostEqual(layout.outer_radius_m, 2000.0)

    def test_stations_are_evenly_pitched_about_the_arms_middle(self) -> None:
        s = jg.station_offsets()
        self.assertEqual(len(s), 5)
        np.testing.assert_allclose(np.diff(s), jg.STATION_PITCH)
        self.assertAlmostEqual(float(s.mean()), 0.5)
        self.assertGreater(float(s.min()), 0.1)  # clear of the end caps

    def test_arm_rotations_are_exact_quarter_turns(self) -> None:
        up = np.array([0.0, 1.0, 0.0])
        dirs = [jg.arm_rotation(k) @ up for k in range(4)]
        np.testing.assert_array_equal(dirs, [[0, 1, 0], [-1, 0, 0], [0, -1, 0], [1, 0, 0]])
        for k in range(4):
            self.assertEqual(np.linalg.det(jg.arm_rotation(k)), 1.0)

    def test_the_fin_is_a_convex_hexagon_counter_clockwise(self) -> None:
        outline = jg.fin_outline()
        self.assertEqual(len(outline), 6)
        self.assertGreater(polygon_area_2d(outline), 0.0)
        edges = np.roll(outline, -1, axis=0) - outline
        turns = edges[:, 0] * np.roll(edges, -1, axis=0)[:, 1] - edges[:, 1] * np.roll(edges, -1, axis=0)[:, 0]
        self.assertTrue(np.all(turns > 0.0))

    def test_fins_sweep_forward_by_twenty_degrees(self) -> None:
        for side in (1.0, -1.0):
            basis = jg.fin_basis(side)
            np.testing.assert_allclose(basis.T @ basis, np.eye(3), atol=1e-12)
            span = basis[:, 0]
            self.assertAlmostEqual(math.degrees(math.asin(-span[2])), 20.0)  # the tip toward the front (-Z)
            self.assertEqual(np.sign(span[0]), side)


class MarkerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = jg.GateLayout()
        self.m = jg.markers(self.layout)

    def test_the_vortex_is_the_origin_facing_the_front(self) -> None:
        v = self.m["vortex"]
        self.assertEqual(v["center"], [0.0, 0.0, 0.0])
        self.assertEqual(v["normal"], [0.0, 0.0, -1.0])
        self.assertEqual(v["up"], [0.0, 1.0, 0.0])
        self.assertAlmostEqual(v["radius_m"], 720.0)

    def test_the_vortex_colour_follows_the_direction(self) -> None:
        v = self.m["vortex"]
        self.assertEqual(v["colour_space"], "linear")
        blue, orange = v["colours"]["arrival"]["colour"], v["colours"]["departure"]["colour"]
        self.assertGreater(blue[2], 2.0 * max(blue[0], blue[1]))  # arrivals: blue
        self.assertGreater(orange[0], orange[1])  # departures: orange-yellow
        self.assertGreater(orange[1], 2.0 * orange[2])
        self.assertEqual(self.m["arrival"]["vortex"], "arrival")
        self.assertEqual(self.m["departure"]["vortex"], "departure")
        for entry in v["colours"].values():
            self.assertEqual(set(entry), {"colour", "highlight"})

    def test_arrivals_leave_along_the_normal_and_departures_fly_in_against_it(self) -> None:
        arrival, departure = self.m["arrival"], self.m["departure"]
        self.assertEqual(arrival["forward"], [0.0, 0.0, -1.0])
        self.assertEqual(departure["forward"], [0.0, 0.0, 1.0])
        for marker in (arrival, departure):
            p = np.array(marker["position"])
            self.assertEqual((p[0], p[1]), (0.0, 0.0))  # on the axis, so inside the ring
            self.assertLess(p[2], 0.0)  # on the front side
        self.assertLess(-arrival["position"][2], self.layout.vortex_radius_m)

    def test_each_emitter_is_on_an_inner_tip_pointing_at_the_centre(self) -> None:
        emitters = self.m["emitters"]
        self.assertEqual(len(emitters), 4)
        for e in emitters:
            p, d = np.array(e["position"]), np.array(e["direction"])
            r = float(np.linalg.norm(p))
            self.assertTrue(self.layout.vortex_radius_m < r < self.layout.inner_radius_m, r)
            np.testing.assert_allclose(d, -p / r, atol=1e-9)


class GeometryTests(unittest.TestCase):
    """The placed parts without the bake (about a second)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.layout = jg.GateLayout()
        cls.parts = jg.gate_parts(cls.layout)
        cls.body = Mesh.concatenate(p.mesh for p in cls.parts)
        cls.collision = jg.collision(cls.layout)

    def test_every_arm_has_its_parts(self) -> None:
        names = [p.name for p in self.parts]
        for k in range(4):
            for part in ("spine", "longeron", "collar", "fin", "cap", "emitter", "lamp"):
                self.assertIn(f"{part}_{k}", names)

    def test_the_gate_is_four_fold_symmetric_and_mirror_symmetric(self) -> None:
        v = self.body.vertices
        ref = rounded_set(v)
        self.assertEqual(rounded_set(v @ jg.arm_rotation(1).T), ref)
        self.assertEqual(rounded_set(v * np.array([-1.0, 1.0, 1.0])), ref)
        self.assertEqual(rounded_set(v * np.array([1.0, -1.0, 1.0])), ref)

    def test_the_dimensions_follow_the_layout(self) -> None:
        lo, hi = self.body.bounds()
        self.assertAlmostEqual(float(hi[0]), self.layout.outer_radius_m, places=6)
        self.assertAlmostEqual(float(-lo[1]), self.layout.outer_radius_m, places=6)
        depth = float(hi[2] - lo[2])
        self.assertTrue(0.05 * self.layout.arm_length_m < depth < 0.1 * self.layout.arm_length_m, depth)

    def test_the_vortex_is_clear_of_the_structure(self) -> None:
        radial = np.hypot(self.body.vertices[:, 0], self.body.vertices[:, 1])
        self.assertGreater(float(radial.min()), self.layout.vortex_radius_m)
        # Every collision box too: sample each one through its volume.
        grid = np.stack(np.meshgrid(*[np.linspace(-0.5, 0.5, 7)] * 3, indexing="ij"), axis=-1).reshape(-1, 3)
        for s in self.collision:
            basis = np.stack([s["basis"]["x"], s["basis"]["y"], s["basis"]["z"]], axis=1)
            pts = np.array(s["position"]) + (grid * np.array(s["size"])) @ basis.T
            self.assertGreater(float(np.hypot(pts[:, 0], pts[:, 1]).min()), self.layout.vortex_radius_m, s["name"])

    def test_the_collision_boxes_cover_every_vertex(self) -> None:
        tol = 1e-3 * self.layout.arm_length_m
        inside = boxes_contain(self.collision, self.body.vertices, tol)
        self.assertTrue(inside.all(), self.body.vertices[~inside][:5])

    def test_collision_is_one_truss_and_ten_fins_per_arm(self) -> None:
        self.assertEqual(len(self.collision), 4 * 11)
        self.assertTrue(all(s["type"] == "box" for s in self.collision))
        self.assertEqual(sum("truss" in s["name"] for s in self.collision), 4)
        for s in self.collision:
            basis = np.stack([s["basis"]["x"], s["basis"]["y"], s["basis"]["z"]], axis=1)
            self.assertAlmostEqual(float(np.linalg.det(basis)), 1.0, places=3)

    def test_the_lamps_sit_on_both_faces_of_every_station(self) -> None:
        lamps = jg.lights(self.layout)
        self.assertEqual(len(lamps), 4 * 5 * 2)
        for lamp in lamps:
            p, n = np.array(lamp["position"]), np.array(lamp["normal"])
            self.assertEqual(abs(n[2]), 1.0)
            self.assertEqual(np.sign(p[2]), n[2])
            self.assertEqual(lamp["name"].endswith("front"), n[2] < 0.0)
        tol = 1e-3 * self.layout.arm_length_m
        self.assertTrue(boxes_contain(self.collision, np.array([lamp["position"] for lamp in lamps]), tol).all())


if __name__ == "__main__":
    unittest.main()
