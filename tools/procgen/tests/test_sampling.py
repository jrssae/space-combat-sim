"""core.sampling: density, uniformity, on-surface positions, symmetry, splat conversion."""

from __future__ import annotations

import math
import unittest

import numpy as np

from tools.procgen.core import frames
from tools.procgen.core import geometry as g
from tools.procgen.core import sampling as sp

HULL = g.Material("hull", (0.6, 0.6, 0.6), paneled=True)
GLASS = g.Material("glass", (0.02, 0.03, 0.06), transmittance=0.7)


def brute_nn(points: np.ndarray) -> np.ndarray:
    d = np.linalg.norm(points[:, None, :] - points[None, :, :], axis=2)
    np.fill_diagonal(d, np.inf)
    return d.min(axis=1)


class SequenceTests(unittest.TestCase):
    def test_r2_points_fill_the_unit_square_evenly(self) -> None:
        pts = sp.r2_points(4096, (0.3, 0.7))
        self.assertTrue(np.all((pts >= 0.0) & (pts < 1.0)))
        counts, _, _ = np.histogram2d(pts[:, 0], pts[:, 1], bins=8, range=[[0, 1], [0, 1]])
        self.assertLess(float(counts.max() - counts.min()), 0.12 * 64)  # low discrepancy: near-equal bins

    def test_square_to_triangle_is_uniform_and_in_range(self) -> None:
        bary = sp.square_to_triangle(sp.r2_points(20000))
        self.assertEqual(bary.shape, (20000, 3))
        self.assertTrue(np.all(bary >= -1e-12))
        np.testing.assert_allclose(bary.sum(axis=1), 1.0, atol=1e-12)
        np.testing.assert_allclose(bary.mean(axis=0), [1 / 3] * 3, atol=0.01)


class SampleMeshTests(unittest.TestCase):
    def setUp(self) -> None:
        self.rng = np.random.default_rng(7)

    def test_count_matches_area_over_spacing_squared(self) -> None:
        mesh = g.box((2.0, 1.0, 3.0), HULL)
        s = sp.sample_mesh(mesh, 0.05, self.rng)
        expected = mesh.area() / 0.05**2
        self.assertAlmostEqual(len(s), expected, delta=0.02 * expected)
        self.assertEqual(s.materials, (HULL,))
        self.assertTrue(np.all(s.material == 0))

    def test_stochastic_rounding_keeps_the_expectation_on_tiny_faces(self) -> None:
        # 7200 tiny faces with ~0.3 samples each: floor() would drop them all.
        mesh = g.lathe([(0.0, 0.0), (0.0, 0.5), (2.0, 0.5), (2.0, 0.0)], 300, HULL)
        s = sp.sample_mesh(mesh, 0.2, self.rng)
        expected = mesh.area() / 0.2**2
        self.assertGreater(float(sp.face_sample_counts(mesh.face_areas(), 0.2, self.rng).max()), 0)
        self.assertAlmostEqual(len(s), expected, delta=0.06 * expected)

    def test_samples_lie_on_their_faces(self) -> None:
        mesh = g.lathe([(-1.0, 0.0), (0.0, 0.6), (1.0, 0.6), (2.0, 0.0)], 24, HULL)
        s = sp.sample_mesh(mesh, 0.04, self.rng)
        a, b, c = mesh.corners()
        fn = mesh.face_normals()
        plane = np.einsum("ij,ij->i", s.positions - a[s.face], fn[s.face])
        self.assertLess(float(np.abs(plane).max()), 1e-9)
        # Inside the triangle: all three edge tests have the same sign as the normal.
        for p, q in ((a, b), (b, c), (c, a)):
            edge = np.cross(q[s.face] - p[s.face], s.positions - p[s.face])
            self.assertTrue(np.all(np.einsum("ij,ij->i", edge, fn[s.face]) > -1e-9))

    def test_density_is_uniform_across_face_sizes(self) -> None:
        big = g.box((3.0, 3.0, 3.0), HULL)
        small = g.box((0.3, 0.3, 0.3), HULL, center=(10.0, 0.0, 0.0))
        s = sp.sample_mesh(g.Mesh.concatenate([big, small]), 0.03, self.rng)
        in_small = s.positions[:, 0] > 5.0
        density_big = float((~in_small).sum()) / big.area()
        density_small = float(in_small.sum()) / small.area()
        self.assertAlmostEqual(density_small / density_big, 1.0, delta=0.08)

    def test_pattern_is_low_discrepancy_not_random(self) -> None:
        mesh = g.box((1.0, 1.0, 1.0), HULL)
        s = sp.sample_mesh(mesh, 0.04, self.rng)
        nn = sp.nearest_neighbour_distances(s.positions, 0.12) / 0.04
        self.assertGreater(float(np.median(nn)), 0.5)  # random points would give ~0.45
        self.assertLess(float((nn < 0.2).mean()), 0.03)  # few clumps
        self.assertLess(float(np.percentile(nn, 99)), 1.3)  # no holes

    def test_normals_are_smooth_on_curved_and_flat_on_hard_meshes(self) -> None:
        cyl = g.lathe([(0.0, 0.0), (0.0, 1.0), (2.0, 1.0), (2.0, 0.0)], 24, HULL, creases={1, 2})
        s = sp.sample_mesh(cyl, 0.05, self.rng)
        side = (s.positions[:, 2] > 0.05) & (s.positions[:, 2] < 1.95) & (np.abs(s.normals[:, 2]) < 0.5)
        radial = g.unit(np.column_stack([s.positions[side, 0], s.positions[side, 1], np.zeros(side.sum())]))
        angle = np.degrees(np.arccos(np.clip(np.einsum("ij,ij->i", radial, s.normals[side]), -1, 1)))
        self.assertLess(float(angle.max()), 8.0)  # 24-gon facets are 15 deg apart; interpolation halves that
        np.testing.assert_allclose(np.linalg.norm(s.normals, axis=1), 1.0, atol=1e-12)
        flat = sp.sample_mesh(cyl, 0.05, np.random.default_rng(1), smooth=False)
        np.testing.assert_allclose(flat.normals, cyl.face_normals()[flat.face], atol=1e-12)
        box = sp.sample_mesh(g.box((1, 1, 1), HULL), 0.05, self.rng)
        np.testing.assert_allclose(box.normals, g.box((1, 1, 1), HULL).face_normals()[box.face], atol=1e-12)

    def test_determinism_and_seed_sensitivity(self) -> None:
        mesh = g.box((1.0, 2.0, 3.0), HULL)
        a = sp.sample_mesh(mesh, 0.05, np.random.default_rng(3))
        b = sp.sample_mesh(mesh, 0.05, np.random.default_rng(3))
        c = sp.sample_mesh(mesh, 0.05, np.random.default_rng(4))
        np.testing.assert_array_equal(a.positions, b.positions)
        self.assertFalse(np.array_equal(a.positions[: len(c)], c.positions[: len(a)]))

    def test_invalid_spacing_and_empty_result(self) -> None:
        mesh = g.box((1.0, 1.0, 1.0), HULL)
        with self.assertRaises(ValueError):
            sp.sample_mesh(mesh, 0.0, self.rng)
        tiny = g.box((0.001, 0.001, 0.001), HULL)
        s = sp.sample_mesh(tiny, 10.0, np.random.default_rng(0))
        self.assertEqual(len(s), 0)
        self.assertEqual(len(sp.SurfaceSamples.concatenate([s, s])), 0)


class SymmetryAndTransformTests(unittest.TestCase):
    def test_symmetrized_is_exact_and_zero_mean(self) -> None:
        mesh = g.box((2.0, 2.0, 2.0), HULL)
        s = sp.sample_mesh(mesh, 0.05, np.random.default_rng(0))
        for axes in ("x", "y", "xy"):
            sym = s.symmetrized(axes)
            for axis in axes:
                k = "xyz".index(axis)
                self.assertLess(abs(float(sym.positions[:, k].mean())), 1e-12)
                mirrored = sym.positions.copy()
                mirrored[:, k] *= -1
                self.assertTrue(
                    np.array_equal(np.sort(sym.positions.view("f8,f8,f8"), axis=0), np.sort(mirrored.view("f8,f8,f8"), axis=0))
                )
            self.assertAlmostEqual(len(sym), len(s), delta=0.1 * len(s))

    def test_mirror_and_transform_move_normals_with_positions(self) -> None:
        mesh = g.box((1.0, 1.0, 1.0), HULL, center=(2.0, 0.0, 0.0))
        s = sp.sample_mesh(mesh, 0.1, np.random.default_rng(0))
        m = s.mirrored("x")
        np.testing.assert_allclose(m.positions[:, 0], -s.positions[:, 0])
        np.testing.assert_allclose(m.normals[:, 0], -s.normals[:, 0])
        r = s.transformed(g.rotation_z(math.pi / 2), (0.0, 0.0, 1.0))
        np.testing.assert_allclose(r.positions.mean(axis=0), [0.0, 2.0, 1.0], atol=0.02)
        np.testing.assert_allclose(np.linalg.norm(r.normals, axis=1), 1.0)
        self.assertEqual(len(s.subset(s.positions[:, 1] > 0)), int((s.positions[:, 1] > 0).sum()))

    def test_concatenate_merges_materials_by_name(self) -> None:
        a = sp.sample_mesh(g.box((1, 1, 1), HULL), 0.2, np.random.default_rng(0))
        b = sp.sample_mesh(g.box((1, 1, 1), GLASS), 0.2, np.random.default_rng(0))
        both = sp.SurfaceSamples.concatenate([a, b, a])
        self.assertEqual([m.name for m in both.materials], ["hull", "glass"])
        self.assertEqual(list(both.material[len(a) : len(a) + len(b)]), [1] * len(b))
        self.assertEqual(list(both.material[len(a) + len(b) :]), [0] * len(a))
        np.testing.assert_allclose(both.transmittance()[len(a)], 0.7)
        np.testing.assert_allclose(both.albedo()[0], HULL.albedo)
        self.assertEqual(float(both.material_flag("paneled")[len(a)]), 0.0)


class SplatConversionTests(unittest.TestCase):
    def test_to_splats_orientation_scale_and_alpha(self) -> None:
        mesh = g.Mesh.concatenate([g.box((1, 1, 1), HULL), g.box((1, 1, 1), GLASS, center=(3, 0, 0))])
        s = sp.sample_mesh(mesh, 0.1, np.random.default_rng(0))
        rgb = np.full((len(s), 3), 0.5)
        splats = sp.to_splats(s, rgb, 0.1, overlap=1.4, thickness=0.03)
        splats.validate()
        np.testing.assert_allclose(splats.scale[:, :2], 0.14)
        np.testing.assert_allclose(splats.scale[:, 2], 0.003)
        rot = frames.quat_to_matrix(splats.rot)
        np.testing.assert_allclose(rot[:, :, 2], s.normals, atol=1e-9)
        self.assertTrue(np.all(np.linalg.det(rot) > 0.99))
        glass = s.material == mesh.material_index("glass")
        self.assertTrue(np.all(splats.alpha[~glass] == 0.98))
        expected = 1.0 - 0.7 ** (1.0 / sp.effective_layers(1.4))
        np.testing.assert_allclose(splats.alpha[glass], expected)
        self.assertLess(expected, 0.05)

    def test_alpha_for_transmittance_is_monotonic(self) -> None:
        t = np.array([0.0, 0.2, 0.5, 0.9])
        a = sp.alpha_for_transmittance(t, 1.0)
        self.assertEqual(a[0], 0.98)
        self.assertTrue(np.all(np.diff(a[1:]) < 0))
        self.assertAlmostEqual(sp.effective_layers(1.0), 2 * math.pi)

    def test_nearest_neighbour_distances_match_brute_force(self) -> None:
        pts = np.random.default_rng(0).random((400, 3))
        np.testing.assert_allclose(sp.nearest_neighbour_distances(pts, 0.2), brute_nn(pts))
        self.assertTrue(np.all(np.isinf(sp.nearest_neighbour_distances(pts[:1], 1.0))))


if __name__ == "__main__":
    unittest.main()
