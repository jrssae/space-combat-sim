"""``parts/wing``: the delta wing's planform, thickness taper, mesh orientation, burial test, collision steps and grille."""

from __future__ import annotations

import math
import unittest

import numpy as np

from tools.procgen.core.geometry import stats
from tools.procgen.parts.wing import WingSpec, delta_wing, vent_grille, wing_mesh
from tools.procgen.styles.raider import RAIDER

SPEC = WingSpec()


class WingSpecTests(unittest.TestCase):
    def test_planform_follows_the_leading_edge_angle(self) -> None:
        self.assertAlmostEqual(SPEC.tip_leading_z, SPEC.half_span / math.tan(math.radians(60.0)), places=9)
        self.assertAlmostEqual(SPEC.tip_trailing_z - SPEC.tip_leading_z, SPEC.tip_chord, places=9)
        self.assertAlmostEqual(float(SPEC.leading_z(0.0)), 0.0)
        self.assertAlmostEqual(float(SPEC.trailing_z(0.0)), SPEC.root_chord)
        self.assertAlmostEqual(float(SPEC.trailing_z(SPEC.half_span)), SPEC.tip_trailing_z)
        # Both halves are the same wing.
        self.assertAlmostEqual(float(SPEC.leading_z(-3.0)), float(SPEC.leading_z(3.0)))

    def test_leading_edge_angle_is_the_sweep_from_the_centre_line(self) -> None:
        for deg in (45.0, 56.0, 60.0):
            spec = WingSpec(sweep_deg=deg)
            angle = math.degrees(math.atan2(spec.half_span, spec.tip_leading_z))
            self.assertAlmostEqual(angle, deg, places=6)

    def test_thickness_tapers_linearly_from_root_to_tip(self) -> None:
        self.assertAlmostEqual(float(SPEC.thickness(0.0)), SPEC.root_thickness)
        self.assertAlmostEqual(float(SPEC.thickness(SPEC.half_span)), SPEC.tip_thickness)
        mid = float(SPEC.thickness(0.5 * SPEC.half_span))
        self.assertAlmostEqual(mid, 0.5 * (SPEC.root_thickness + SPEC.tip_thickness))

    def test_contains_is_the_slab_shrunk_by_the_margin(self) -> None:
        inside = np.array([[2.0, 0.0, 3.5], [-2.0, 0.05, 3.5]])
        outside = np.array([[2.0, 0.3, 3.5], [2.0, 0.0, 0.5], [9.0, 0.0, 5.0], [2.0, 0.0, 6.5]])
        self.assertTrue(SPEC.contains(inside).all())
        self.assertFalse(SPEC.contains(outside).any())
        # A margin of 0.1 m rejects the point 0.05 m inside the top surface at x = 0 (half thickness 0.175).
        self.assertTrue(SPEC.contains(np.array([[0.0, 0.1, 3.0]]), 0.05).all())
        self.assertFalse(SPEC.contains(np.array([[0.0, 0.17, 3.0]]), 0.05).any())


class WingMeshTests(unittest.TestCase):
    def setUp(self) -> None:
        self.mesh = wing_mesh(SPEC, RAIDER)

    def test_bounds_are_the_right_half_planform(self) -> None:
        s = stats(self.mesh)
        np.testing.assert_allclose(s.bounds_min, [0.0, -0.5 * SPEC.root_thickness, 0.0], atol=1e-9)
        np.testing.assert_allclose(s.bounds_max, [SPEC.half_span, 0.5 * SPEC.root_thickness, SPEC.tip_trailing_z], atol=1e-9)

    def test_faces_point_outwards(self) -> None:
        centre = np.array([0.5 * SPEC.half_span, 0.0, 0.5 * SPEC.tip_trailing_z])
        outward = np.einsum("ij,ij->i", self.mesh.face_normals(), self.mesh.face_centroids() - centre)
        self.assertTrue((outward > 0.0).all())

    def test_top_and_bottom_are_planar_and_the_edges_use_the_panel_band_material(self) -> None:
        normals = self.mesh.face_normals()
        top = normals[:, 1] > 0.99
        self.assertEqual(int(top.sum()), 2)
        names = [m.name for m in self.mesh.materials]
        hull = names.index("rd_hull")
        edge = names.index("rd_hull_panel")
        self.assertTrue((self.mesh.face_material[top] == hull).all())
        self.assertTrue((self.mesh.face_material[np.abs(normals[:, 1]) < 0.5] == edge).all())

    def test_the_planform_area_matches_the_polygon(self) -> None:
        # Right half: trapezoid-ish polygon apex -> tip leading -> tip trailing -> root trailing; both faces plus walls.
        pts = np.array([[0, 0], [SPEC.half_span, SPEC.tip_leading_z], [SPEC.half_span, SPEC.tip_trailing_z], [0, SPEC.root_chord]])
        x, z = pts[:, 0], pts[:, 1]
        planform = 0.5 * abs(float(np.dot(x, np.roll(z, -1)) - np.dot(z, np.roll(x, -1))))
        top_bottom = float(self.mesh.face_areas()[np.abs(self.mesh.face_normals()[:, 1]) > 0.99].sum())
        self.assertAlmostEqual(top_bottom, 2.0 * planform, delta=0.01 * planform)


class DeltaWingPartTests(unittest.TestCase):
    def test_collision_boxes_wrap_every_vertex(self) -> None:
        part = delta_wing(SPEC, RAIDER, steps=5)
        self.assertEqual(len(part.collision), 5)
        v = part.mesh.vertices
        covered = np.zeros(len(v), dtype=bool)
        for c in part.collision:
            half = 0.5 * c.size + 1e-9
            covered |= np.all(np.abs(v - c.center) <= half, axis=1)
        self.assertTrue(covered.all(), "every wing vertex is inside a step box")

    def test_collision_steps_move_outwards_and_stay_unique(self) -> None:
        part = delta_wing(SPEC, RAIDER, steps=4)
        xs = [float(c.center[0]) for c in part.collision]
        self.assertEqual(xs, sorted(xs))
        self.assertEqual(len({c.name for c in part.collision}), 4)

    def test_anchors_and_group(self) -> None:
        part = delta_wing(SPEC, RAIDER)
        np.testing.assert_allclose(part.anchor("tip_te").position, [SPEC.half_span, 0.0, SPEC.tip_trailing_z])
        self.assertEqual(part.group, "wing")


class VentGrilleTests(unittest.TestCase):
    def test_grille_is_centred_with_its_base_on_the_surface(self) -> None:
        mesh = vent_grille(1.0, 1.2, 6, RAIDER, slat_height=0.05)
        lo, hi = mesh.bounds()
        self.assertAlmostEqual(float(lo[1]), 0.0)
        self.assertAlmostEqual(float(hi[1]), 0.05)
        self.assertAlmostEqual(float(lo[2]), -0.6, places=6)
        self.assertAlmostEqual(float(hi[2]), 0.6, places=6)
        self.assertEqual(mesh.face_count, 12 * (1 + 6))  # a plate and six slats, 12 triangles each

    def test_along_x_runs_the_bars_along_z(self) -> None:
        mesh = vent_grille(1.0, 1.2, 6, RAIDER, along="x")
        lo, hi = mesh.bounds()
        self.assertAlmostEqual(float(hi[0] - lo[0]), 1.2, places=6)
        self.assertAlmostEqual(float(hi[2] - lo[2]), 1.0, places=6)


if __name__ == "__main__":
    unittest.main()
