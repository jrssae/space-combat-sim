"""``jumpgate``'s pure helpers and its geometry without the texture bake (quick tier): the layout (four arms parallel to the vortex's
axis, the side arms further out so the mouth is an ellipse, T19), the markers and the vortex's colours, the symmetry, the collision
boxes covering every vertex and the vortex left clear."""

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
        self.assertAlmostEqual(layout.arm_radius_m, 800.0)
        self.assertAlmostEqual(layout.side_radius_m, jg.MOUTH_ASPECT * 800.0)
        self.assertGreater(jg.MOUTH_ASPECT, 1.0)  # wider than tall

    def test_the_side_arms_stand_further_out_than_the_top_and_bottom_ones(self) -> None:
        layout = jg.GateLayout(1000.0, 1.5)
        out = np.array([0.0, 0.0, 1.0])
        for k in range(4):
            r, t = jg._placement(layout, k)
            back = t[:2]
            np.testing.assert_allclose(back, (jg.arm_rotation(k) @ out)[:2] * layout.radius_of(k), atol=1e-9)
        self.assertEqual([layout.radius_of(k) for k in range(4)], [layout.arm_radius_m, layout.side_radius_m] * 2)
        self.assertAlmostEqual(layout.side_radius_m / layout.arm_radius_m, 1.5)

    def test_stations_are_evenly_pitched_about_the_arms_middle(self) -> None:
        s = jg.station_offsets()
        self.assertEqual(len(s), 5)
        np.testing.assert_allclose(np.diff(s), jg.STATION_PITCH)
        self.assertAlmostEqual(float(s.mean()), 0.5)
        self.assertGreater(float(s.min()), 0.1)  # clear of the end caps

    def test_arm_rotations_run_every_arm_to_the_front_at_quarter_turns(self) -> None:
        along, out = np.array([0.0, 1.0, 0.0]), np.array([0.0, 0.0, 1.0])
        for k in range(4):
            np.testing.assert_array_equal(jg.arm_rotation(k) @ along, [0, 0, -1])  # parallel to the axis, toward the front
        outs = [jg.arm_rotation(k) @ out for k in range(4)]
        np.testing.assert_array_equal(outs, [[0, 1, 0], [-1, 0, 0], [0, -1, 0], [1, 0, 0]])
        for k in range(4):
            self.assertEqual(np.linalg.det(jg.arm_rotation(k)), 1.0)

    def test_the_fin_is_a_convex_hexagon_counter_clockwise(self) -> None:
        outline = jg.fin_outline()
        self.assertEqual(len(outline), 6)
        self.assertGreater(polygon_area_2d(outline), 0.0)
        edges = np.roll(outline, -1, axis=0) - outline
        turns = edges[:, 0] * np.roll(edges, -1, axis=0)[:, 1] - edges[:, 1] * np.roll(edges, -1, axis=0)[:, 0]
        self.assertTrue(np.all(turns > 0.0))

    def test_fins_sweep_toward_the_axis_by_twenty_degrees(self) -> None:
        for side in (1.0, -1.0):
            basis = jg.fin_basis(side)
            np.testing.assert_allclose(basis.T @ basis, np.eye(3), atol=1e-12)
            span = basis[:, 0]
            self.assertAlmostEqual(math.degrees(math.asin(-span[2])), 20.0)  # the tip in toward the axis (-z, the arm's frame)
            self.assertEqual(np.sign(span[0]), side)


class MarkerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = jg.GateLayout()
        self.rim = 750.0
        self.half_width = 1030.0
        self.m = jg.markers(self.layout, (self.half_width, self.rim))

    def test_the_vortex_mouth_is_at_the_front_ends_facing_the_front(self) -> None:
        v = self.m["vortex"]
        self.assertEqual(v["center"], [0.0, 0.0, 0.0])
        self.assertEqual(v["normal"], [0.0, 0.0, -1.0])
        self.assertEqual(v["up"], [0.0, 1.0, 0.0])
        self.assertAlmostEqual(v["radius_m"], self.rim)  # the half height: the largest circle inside the mouth
        self.assertEqual(v["semi_axes_m"], [self.half_width, self.rim])
        self.assertAlmostEqual(v["depth_m"], self.layout.arm_length_m)  # the funnel ends at the arms' back ends

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
            self.assertLess(p[2], 0.0)  # in front of the mouth
        self.assertLess(-arrival["position"][2], self.rim)

    def test_each_emitter_is_on_a_back_end_facing_back(self) -> None:
        emitters = self.m["emitters"]
        self.assertEqual(len(emitters), 4)
        for k, e in enumerate(emitters):
            p, d = np.array(e["position"]), np.array(e["direction"])
            self.assertAlmostEqual(float(np.hypot(p[0], p[1])), self.layout.radius_of(k), places=6)
            self.assertGreaterEqual(p[2], self.layout.arm_length_m)
            np.testing.assert_allclose(d, [0.0, 0.0, 1.0], atol=1e-9)


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

    def test_the_gate_is_mirror_symmetric_and_its_arms_are_copies(self) -> None:
        v = self.body.vertices
        ref = rounded_set(v)
        self.assertEqual(rounded_set(v * np.array([-1.0, -1.0, 1.0])), ref)  # a half turn about the vortex's axis
        # A quarter turn carries the top arm onto a side arm once that is drawn in to the top arm's distance.
        quarter = np.array([[0.0, -1.0, 0.0], [1.0, 0.0, 0.0], [0.0, 0.0, 1.0]])
        top = Mesh.concatenate(p.mesh for p in self.parts if p.name.endswith("_0")).vertices
        side = Mesh.concatenate(p.mesh for p in self.parts if p.name.endswith("_1")).vertices
        shift = np.array([self.layout.side_radius_m - self.layout.arm_radius_m, 0.0, 0.0])
        self.assertEqual(rounded_set(top @ quarter.T), rounded_set(side + shift))
        self.assertEqual(rounded_set(v * np.array([-1.0, 1.0, 1.0])), ref)
        self.assertEqual(rounded_set(v * np.array([1.0, -1.0, 1.0])), ref)

    def test_the_arms_run_from_the_front_plane_back_one_arm_length(self) -> None:
        lo, hi = self.body.bounds()
        self.assertAlmostEqual(float(lo[2]), 0.0, places=6)  # nothing in front of the mouth's plane
        self.assertTrue(self.layout.arm_length_m <= float(hi[2]) < 1.02 * self.layout.arm_length_m)  # the back end and its lens
        across, tall = float(hi[0] - lo[0]), float(hi[1] - lo[1])
        self.assertTrue(2.0 * self.layout.side_radius_m < across < 2.2 * self.layout.side_radius_m, across)
        self.assertTrue(2.0 * self.layout.arm_radius_m < tall < 2.2 * self.layout.arm_radius_m, tall)

    def test_the_rim_is_an_ellipse_within_a_metre_of_the_arms(self) -> None:
        half_width, half_height = jg.mouth_semi_axes(self.body)
        self.assertEqual(jg.RIM_CLEARANCE_M, 1.0)
        self.assertTrue(0.9 * self.layout.arm_radius_m < half_height < self.layout.arm_radius_m, half_height)
        self.assertTrue(0.9 * self.layout.side_radius_m < half_width < self.layout.side_radius_m, half_width)
        v = self.body.vertices
        for arms in (np.abs(v[:, 0]) > np.abs(v[:, 1]), np.abs(v[:, 0]) <= np.abs(v[:, 1])):  # the sides, then top and bottom
            # How far outside the rim each vertex is, measured along its ray from the axis.
            radial = np.hypot(v[arms, 0], v[arms, 1])
            scale = np.sqrt((v[arms, 0] / half_width) ** 2 + (v[arms, 1] / half_height) ** 2)
            gap = radial * (1.0 - 1.0 / scale)
            self.assertGreater(float(gap.min()), 0.0)  # it meets no arm
            self.assertLessEqual(float(gap.min()), jg.RIM_CLEARANCE_M + 1e-2)  # and comes within a metre of each pair
            self.assertGreater(float(gap.min()), 0.5 * jg.RIM_CLEARANCE_M)

    def test_a_square_gate_gets_a_round_mouth(self) -> None:
        body = Mesh.concatenate(p.mesh for p in jg.gate_parts(jg.GateLayout(1200.0, 1.0)))
        half_width, half_height = jg.mouth_semi_axes(body)
        self.assertAlmostEqual(half_width, half_height, places=6)

    def test_the_vortex_is_clear_of_the_structure(self) -> None:
        half_width, half_height = jg.mouth_semi_axes(self.body)
        # Every collision box too: sample each one through its volume.
        grid = np.stack(np.meshgrid(*[np.linspace(-0.5, 0.5, 7)] * 3, indexing="ij"), axis=-1).reshape(-1, 3)
        for s in self.collision:
            basis = np.stack([s["basis"]["x"], s["basis"]["y"], s["basis"]["z"]], axis=1)
            pts = np.array(s["position"]) + (grid * np.array(s["size"])) @ basis.T
            outside = (pts[:, 0] / half_width) ** 2 + (pts[:, 1] / half_height) ** 2
            self.assertGreater(float(outside.min()), 1.0, s["name"])

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

    def test_the_lamps_sit_on_both_faces_of_every_station_front_to_back(self) -> None:
        lamps = jg.lights(self.layout)
        self.assertEqual(len(lamps), 4 * 5 * 2)
        for k in range(4):
            arm = [lamp for lamp in lamps if lamp["arm"] == k]
            zs = [lamp["position"][2] for lamp in arm]
            self.assertEqual(zs, sorted(zs))  # listed from the front end to the back end
            self.assertEqual([lamp["station"] for lamp in arm], [i // 2 for i in range(10)])
        for lamp in lamps:
            p, n = np.array(lamp["position"]), np.array(lamp["normal"])
            radial = np.hypot(p[0], p[1])
            self.assertEqual(n[2], 0.0)  # facing toward or away from the axis
            self.assertEqual(lamp["name"].endswith("inner"), radial < self.layout.radius_of(lamp["arm"]))
            self.assertTrue(0.0 < p[2] < self.layout.arm_length_m)
        tol = 1e-3 * self.layout.arm_length_m
        self.assertTrue(boxes_contain(self.collision, np.array([lamp["position"] for lamp in lamps]), tol).all())


if __name__ == "__main__":
    unittest.main()
