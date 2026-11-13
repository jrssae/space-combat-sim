"""The far view's silhouette table (M6-T15): the outline's area along each direction, the directions themselves, the section."""

import math
import unittest

import numpy as np

from tools.procgen.core.geometry import Material, Mesh, box
from tools.procgen.core.silhouette import AXIS_RING_POINTS, AXIS_RINGS_DEG, far_section, silhouette_area, view_directions

PLAIN = Material("plain", (0.5, 0.5, 0.5))


class SilhouetteTest(unittest.TestCase):
    def test_a_unit_cube_seen_face_on_and_corner_on(self) -> None:
        cube = box((1.0, 1.0, 1.0), PLAIN)
        self.assertAlmostEqual(silhouette_area(cube.vertices, cube.faces, np.array([0.0, 0.0, 1.0])), 1.0, delta=0.01)
        # Down the diagonal a cube's outline is a hexagon of area sqrt(3).
        self.assertAlmostEqual(silhouette_area(cube.vertices, cube.faces, np.array([1.0, 1.0, 1.0])), math.sqrt(3.0), delta=0.02)

    def test_a_thin_plate_edge_on_covers_almost_nothing(self) -> None:
        plate = box((100.0, 100.0, 1.0), PLAIN)
        face = silhouette_area(plate.vertices, plate.faces, np.array([0.0, 0.0, 1.0]))
        edge = silhouette_area(plate.vertices, plate.faces, np.array([1.0, 0.0, 0.0]))
        self.assertAlmostEqual(face, 10000.0, delta=100.0)
        self.assertLess(edge, face * 0.02)

    def test_two_boxes_one_behind_the_other_count_once(self) -> None:
        pair = Mesh.concatenate([box((10.0, 10.0, 10.0), PLAIN), box((10.0, 10.0, 10.0), PLAIN, (0.0, 0.0, 50.0))])
        self.assertAlmostEqual(silhouette_area(pair.vertices, pair.faces, np.array([0.0, 0.0, 1.0])), 100.0, delta=2.0)
        self.assertAlmostEqual(silhouette_area(pair.vertices, pair.faces, np.array([1.0, 0.0, 0.0])), 200.0, delta=4.0)

    def test_the_directions_hold_the_axes_their_rings_and_a_hemisphere(self) -> None:
        d = view_directions(64)
        self.assertEqual(len(d), 3 + 3 * len(AXIS_RINGS_DEG) * AXIS_RING_POINTS + 64)
        np.testing.assert_allclose(np.linalg.norm(d, axis=1), 1.0, atol=1e-12)
        np.testing.assert_allclose(d[:3], np.eye(3))
        ring = d[3:3 + AXIS_RING_POINTS]
        np.testing.assert_allclose(ring @ np.array([1.0, 0.0, 0.0]), math.cos(math.radians(AXIS_RINGS_DEG[0])), atol=1e-12)
        self.assertTrue(np.all(d[-64:, 1] > 0.0), "the spiral covers one hemisphere")

    def test_the_section(self) -> None:
        slab = box((200.0, 20.0, 60.0), PLAIN, (0.0, 0.0, 30.0))
        section = far_section(slab.vertices, slab.faces, spiral=16, res=256)
        self.assertEqual(section["centre"], [0.0, 0.0, 30.0])
        self.assertAlmostEqual(section["radius_m"], math.sqrt(100.0**2 + 10.0**2 + 30.0**2), places=2)
        self.assertEqual(len(section["directions"]), len(section["areas_m2"]))
        self.assertAlmostEqual(section["areas_m2"][0], 20.0 * 60.0, delta=40.0)  # along x: the slab's end
        self.assertAlmostEqual(section["areas_m2"][2], 200.0 * 20.0, delta=80.0)  # along z: its face


if __name__ == "__main__":
    unittest.main()
