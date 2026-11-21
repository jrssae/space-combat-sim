"""Signed distance fields and their meshes (M10-T06, D12.2): ``core/sdf.py``, ``core/isosurface.py`` and ``core/decimate.py``.

The fields answer with the right distances and join as their docstrings say; the mesher is watertight for every one of the
256 corner patterns and gives the same mesh whatever its block size; the decimator reaches its budget without opening or
folding the skin; and a mesh carries its field's normals through every transform.
"""

from __future__ import annotations

import math
import unittest

import numpy as np

from tools.procgen.core import decimate, isosurface, sdf
from tools.procgen.core.geometry import Material, Mesh, mirror_matrix, rotation_y
from tools.procgen.core.sweep import spline

SKIN = Material("skin", (0.3, 0.3, 0.3))


def volume(vertices: np.ndarray, faces: np.ndarray) -> float:
    a, b, c = vertices[faces[:, 0]], vertices[faces[:, 1]], vertices[faces[:, 2]]
    return float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6.0)


def cloud(seed: int, count: int, span: float) -> np.ndarray:
    return np.random.default_rng(seed).uniform(-span, span, size=(count, 3))


class FieldTests(unittest.TestCase):
    def test_a_sphere_answers_with_the_true_distance(self) -> None:
        p = cloud(1, 200, 20.0)
        np.testing.assert_allclose(sdf.sphere(5.0, (1.0, 2.0, 3.0))(p), np.linalg.norm(p - (1.0, 2.0, 3.0), axis=1) - 5.0)

    def test_an_ellipsoid_is_zero_on_its_skin_and_signed_either_side(self) -> None:
        body = sdf.ellipsoid((8.0, 3.0, 5.0))
        directions = cloud(2, 300, 1.0)
        directions /= np.linalg.norm(directions, axis=1, keepdims=True)
        on_skin = directions * (8.0, 3.0, 5.0)
        np.testing.assert_allclose(body(on_skin), 0.0, atol=1e-9)
        self.assertTrue(np.all(body(on_skin * 0.9) < 0.0) and np.all(body(on_skin * 1.1) > 0.0))
        self.assertAlmostEqual(float(body(np.array([[10.0, 0.0, 0.0]]))[0]), 2.0, places=6, msg="exact along an axis")

    def test_a_round_cone_and_a_box_and_a_torus(self) -> None:
        cone = sdf.round_cone((0.0, 0.0, 0.0), (0.0, 0.0, 10.0), 3.0, 1.0)
        np.testing.assert_allclose(cone(np.array([[3.0, 0.0, 0.0], [0.0, 1.0, 10.0], [0.0, 0.0, -3.0], [0.0, 0.0, 5.0]])), [0.0, 0.0, 0.0, -2.0], atol=1e-9)
        block = sdf.box((4.0, 6.0, 8.0), rounding=1.0)
        np.testing.assert_allclose(block(np.array([[2.0, 0.0, 0.0], [0.0, 5.0, 0.0], [0.0, 0.0, 0.0]])), [0.0, 2.0, -2.0], atol=1e-9)
        ring = sdf.torus(10.0, 2.0)
        np.testing.assert_allclose(ring(np.array([[12.0, 0.0, 0.0], [10.0, 0.0, 0.0], [0.0, 0.0, 0.0]])), [0.0, -2.0, 8.0], atol=1e-9)

    def test_a_smooth_union_only_adds_and_only_near_the_join(self) -> None:
        a, b = sdf.sphere(5.0, (-4.0, 0.0, 0.0)), sdf.sphere(5.0, (4.0, 0.0, 0.0))
        p = cloud(3, 2000, 14.0)
        hard, soft = sdf.union(a, b)(p), sdf.smooth_union(a, b, blend=2.0)(p)
        self.assertTrue(np.all(soft <= hard + 1e-12), "melting never takes skin away")
        self.assertLessEqual(float((hard - soft).max()), 0.25 * 2.0 + 1e-12, "the fillet is at most a quarter of the blend deep")
        far = np.abs(a(p) - b(p)) >= 2.0
        np.testing.assert_allclose(soft[far], hard[far], err_msg="away from the join the bodies are as they were")

    def test_subtract_and_intersect(self) -> None:
        body, hole = sdf.sphere(5.0), sdf.sphere(2.0)
        p = np.array([[0.0, 0.0, 0.0], [3.0, 0.0, 0.0], [6.0, 0.0, 0.0]])
        self.assertEqual((sdf.subtract(body, hole)(p) < 0.0).tolist(), [False, True, False])
        self.assertEqual((sdf.intersect(body, sdf.sphere(5.0, (4.0, 0.0, 0.0)))(p) < 0.0).tolist(), [True, True, False])
        self.assertEqual((sdf.smooth_subtract(body, hole, 0.5)(p) < 0.0).tolist(), [False, True, False])

    def test_metaballs_swell_towards_each_other(self) -> None:
        centres = np.array([[-5.0, 0.0, 0.0], [5.0, 0.0, 0.0]])
        blobs = sdf.metaballs(centres, [4.0, 4.0], blend=1.5)
        between = np.array([[0.0, 0.0, 0.0]])
        self.assertLess(float(blobs(between)[0]), float(sdf.union(sdf.sphere(4.0, centres[0]), sdf.sphere(4.0, centres[1]))(between)[0]))
        self.assertAlmostEqual(float(sdf.metaballs(centres[:1], [4.0], 1.5)(np.array([[9.0, 0.0, 0.0]]))[0]), 10.0, places=9, msg="one blob is a sphere")
        outside = cloud(4, 500, 30.0)
        outside = outside[np.any((outside < blobs.lo) | (outside > blobs.hi), axis=1)]
        self.assertTrue(np.all(blobs(outside) > 0.0), "the box holds the whole body")

    def test_a_swept_body_follows_its_path_and_ends_in_a_point(self) -> None:
        path = spline(np.array([[0.0, 0.0, 0.0], [0.0, 0.0, 20.0], [10.0, 0.0, 40.0]]), 33)
        width = path.along([(0.0, 3.0), (1.0, 0.0)])
        limb = sdf.swept(path, width, 0.5 * width)
        self.assertTrue(np.all(limb(path.points[:-2]) < 0.0), "the path runs inside the body")
        root = path.points[0]
        self.assertAlmostEqual(float(limb((root + 3.0 * path.side[0])[None])[0]), 0.0, delta=0.05)
        self.assertAlmostEqual(float(limb((root + 1.5 * path.up[0])[None])[0]), 0.0, delta=0.05, msg="half as high as wide")
        self.assertGreater(float(limb((path.points[-1] + 0.3 * path.side[-1])[None])[0]), 0.0, "nothing left of it at its tip")

    def test_relief_stays_within_its_amplitude_and_is_seeded(self) -> None:
        body = sdf.sphere(10.0)
        p = cloud(5, 1000, 14.0)
        rough = sdf.displaced(body, 0.8, 4.0, seed=3)
        self.assertLessEqual(float(np.abs(rough(p) - body(p)).max()), 0.8 + 1e-9)
        np.testing.assert_array_equal(rough(p), sdf.displaced(body, 0.8, 4.0, seed=3)(p))
        self.assertFalse(np.array_equal(rough(p), sdf.displaced(body, 0.8, 4.0, seed=4)(p)))
        self.assertAlmostEqual(rough.slack, 0.8)
        ribs = sdf.ribbed(body, 1.0, 5.0)
        on_rib, between = np.array([[0.0, 10.5, 0.0]]), np.array([[0.0, 10.5, 2.5]])
        self.assertLess(float(ribs(on_rib)[0]), 0.0)
        self.assertGreater(float(ribs(between)[0]), 0.0, "a rib every pitch, a valley between")

    def test_a_field_moves_and_mirrors_with_its_box(self) -> None:
        body = sdf.ellipsoid((6.0, 2.0, 3.0), (10.0, 0.0, 0.0))
        turned = body.moved(rotation_y(0.5 * math.pi), (0.0, 5.0, 0.0))
        self.assertLess(float(turned(np.array([[0.0, 5.0, -10.0]]))[0]), 0.0)
        np.testing.assert_allclose(turned.lo, [-3.0, 3.0, -16.0], atol=1e-9)
        mirrored = body.mirrored(0)
        p = cloud(6, 200, 18.0)
        np.testing.assert_allclose(mirrored(p), body(p * (-1.0, 1.0, 1.0)))
        np.testing.assert_allclose(body.grown(1.0)(p), body(p) - 1.0)

    def test_beyond_its_reach_a_field_answers_with_its_boxs_distance(self) -> None:
        near = sdf.sphere(5.0).with_reach(2.0)
        p = np.array([[6.0, 0.0, 0.0], [30.0, 0.0, 0.0]])
        np.testing.assert_allclose(near(p), [1.0, 25.0])
        diagonal = np.array([[20.0, 20.0, 0.0]])
        self.assertLessEqual(float(near(diagonal)[0]), float(sdf.sphere(5.0)(diagonal)[0]), "never more than the true distance")
        self.assertGreater(float(near(diagonal)[0]), 0.0)

    def test_the_field_is_the_volume_that_buries_other_parts(self) -> None:
        volume_of = sdf.solid(sdf.sphere(5.0))
        self.assertEqual(volume_of.contains(np.array([[0.0, 0.0, 0.0], [4.99, 0.0, 0.0], [6.0, 0.0, 0.0]]), 0.05).tolist(), [True, False, False])


class IsosurfaceTests(unittest.TestCase):
    def test_every_corner_pattern_meets_its_neighbours(self) -> None:
        # Noise on the lattice makes every one of the 256 patterns, each beside every kind of neighbour.
        n = 22
        values = np.random.default_rng(7).normal(size=(n, n, n))
        values[[0, 1, -2, -1]] = values[:, [0, 1, -2, -1]] = values[:, :, [0, 1, -2, -1]] = 1.0
        seen: set[int] = set()

        def field(p: np.ndarray) -> np.ndarray:
            i = np.clip(np.rint(p).astype(int), 0, n - 1)
            return values[i[:, 0], i[:, 1], i[:, 2]]

        vertices, faces = isosurface.extract(field, np.full(3, 1.0), np.full(3, n - 2.0), 1.0, lipschitz=1e9)
        self.assertEqual(isosurface.edge_faults(faces), 0)
        corners = np.stack([values[c[0]:n - 1 + c[0], c[1]:n - 1 + c[1], c[2]:n - 1 + c[2]] for c in isosurface.CORNERS], axis=-1)
        seen.update(np.unique(((corners < 0.0) * (1 << np.arange(8))).sum(axis=-1)).tolist())
        self.assertEqual(len(seen), 256, "the field held every pattern")
        self.assertGreater(len(faces), 10_000)

    def test_the_table_is_empty_only_for_all_in_and_all_out(self) -> None:
        used = (isosurface.CASES[..., 0] >= 0).sum(axis=1)
        self.assertEqual(np.flatnonzero(used == 0).tolist(), [0, 255])
        self.assertLessEqual(int(used.max()), 5)

    def test_a_sphere_is_closed_wound_outward_and_the_right_size(self) -> None:
        ball = sdf.sphere(10.0)
        vertices, faces = isosurface.extract(ball, ball.lo, ball.hi, 0.5)
        self.assertEqual(isosurface.edge_faults(faces), 0)
        self.assertAlmostEqual(volume(vertices, faces), 4.0 / 3.0 * math.pi * 1000.0, delta=0.005 * 4189.0)
        np.testing.assert_allclose(np.linalg.norm(vertices, axis=1), 10.0, atol=0.03)

    def test_the_block_size_does_not_change_the_mesh(self) -> None:
        body = sdf.displaced(sdf.smooth_union(sdf.sphere(6.0, (-4.0, 0.0, 0.0)), sdf.ellipsoid((3.0, 8.0, 3.0), (5.0, 0.0, 0.0)), blend=2.0), 0.4, 3.0, 1)
        whole = isosurface.extract(body, body.lo, body.hi, 0.5, 1e9)  # every block worked through
        for block in (4, 8):
            sparse = isosurface.extract(body, body.lo, body.hi, 0.5, body.lipschitz, body.slack, block)
            np.testing.assert_array_equal(sparse[0], whole[0])
            np.testing.assert_array_equal(sparse[1], whole[1])

    def test_a_body_that_fills_its_box_is_still_closed_and_nothing_is_an_error(self) -> None:
        block = sdf.box((6.0, 6.0, 6.0), rounding=0.5)
        self.assertEqual(isosurface.edge_faults(isosurface.extract(block, block.lo, block.hi, 0.5)[1]), 0)
        with self.assertRaises(ValueError):
            isosurface.extract(lambda p: np.ones(len(p)), np.zeros(3), np.full(3, 4.0), 0.5)


class DecimateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.body = sdf.smooth_union(sdf.sphere(8.0, (-5.0, 0.0, 0.0)), sdf.sphere(6.0, (6.0, 0.0, 0.0)), blend=3.0)
        cls.vertices, cls.faces = isosurface.extract(cls.body, cls.body.lo, cls.body.hi, 0.4)

    def test_it_reaches_the_budget_and_keeps_the_skin_closed_and_in_place(self) -> None:
        for target in (6000, 1500, 400):
            vertices, faces = decimate.decimate(self.vertices, self.faces, target)
            self.assertLessEqual(len(faces), target)
            self.assertGreater(len(faces), 0.95 * target, "no further than asked")
            self.assertEqual(isosurface.edge_faults(faces), 0, f"closed at {target}")
            self.assertAlmostEqual(volume(vertices, faces) / volume(self.vertices, self.faces), 1.0, delta=0.02)
            self.assertLess(float(np.abs(self.body(vertices)).max()), 0.35, "the vertices stay on the body")

    def test_it_is_deterministic_and_leaves_a_mesh_under_budget_alone(self) -> None:
        once, twice = decimate.decimate(self.vertices, self.faces, 2000), decimate.decimate(self.vertices, self.faces, 2000)
        np.testing.assert_array_equal(once[0], twice[0])
        np.testing.assert_array_equal(once[1], twice[1])
        same = decimate.decimate(self.vertices, self.faces, len(self.faces))
        np.testing.assert_array_equal(same[0], self.vertices)
        np.testing.assert_array_equal(same[1], self.faces)

    def test_an_open_rim_keeps_its_shape(self) -> None:
        keep = self.vertices[self.faces].mean(axis=1)[:, 1] > 0.0  # the upper half: a rim along y = 0
        used, faces = np.unique(self.faces[keep], return_inverse=True)
        vertices, faces = self.vertices[used], faces.reshape(-1, 3)
        pairs = np.sort(np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]]), axis=1)
        edges, uses = np.unique(pairs, axis=0, return_counts=True)
        rim = vertices[np.unique(edges[uses == 1])]
        thinned, _ = decimate.decimate(vertices, faces, len(faces) // 4)
        gap = np.linalg.norm(rim[:, None, :] - thinned[None], axis=2).min(axis=1)
        self.assertEqual(float(gap.max()), 0.0, "every rim vertex is still there")


class MeshTests(unittest.TestCase):
    def test_a_field_meshes_within_budget_with_its_own_normals(self) -> None:
        body = sdf.ellipsoid((9.0, 5.0, 7.0))
        mesh = sdf.mesh(body, 0.5, SKIN, 3000)
        self.assertLessEqual(mesh.face_count, 3000)
        self.assertEqual(isosurface.edge_faults(mesh.faces), 0)
        normals = mesh.vertex_normals()
        np.testing.assert_allclose(np.linalg.norm(normals, axis=1), 1.0, atol=1e-9)
        exact = mesh.vertices / np.array([81.0, 25.0, 49.0])
        exact /= np.linalg.norm(exact, axis=1, keepdims=True)
        self.assertGreater(float(np.einsum("ij,ij->i", normals, exact).min()), 0.999, "the ellipsoid's true normals")
        again = sdf.mesh(body, 0.5, SKIN, 3000)
        np.testing.assert_array_equal(mesh.vertices, again.vertices)
        np.testing.assert_array_equal(mesh.faces, again.faces)

    def test_a_meshs_own_normals_ride_through_every_transform(self) -> None:
        mesh = sdf.mesh(sdf.sphere(4.0), 1.0, SKIN)
        moved = mesh.transformed(rotation_y(0.7), (5.0, 0.0, 0.0))
        np.testing.assert_allclose(moved.vertex_normals(), (moved.vertices - (5.0, 0.0, 0.0)) / 4.0, atol=0.02)
        mirrored = mesh.transformed(mirror_matrix("x"))
        np.testing.assert_allclose(mirrored.vertex_normals(), mirrored.vertices / 4.0, atol=0.02)
        np.testing.assert_allclose(mesh.flipped().vertex_normals(), -mesh.vertex_normals())
        half = mesh.face_subset(mesh.face_centroids()[:, 0] > 0.0)
        np.testing.assert_array_equal(half.vertex_normals(), mesh.vertex_normals())
        plain = Mesh(mesh.vertices + (20.0, 0.0, 0.0), mesh.faces, mesh.face_material, mesh.materials)
        both = Mesh.concatenate([mesh, plain])
        np.testing.assert_array_equal(both.vertex_normals()[:mesh.vertex_count], mesh.vertex_normals())
        np.testing.assert_allclose(both.vertex_normals()[mesh.vertex_count:], plain.vertex_normals())
        self.assertIsNone(Mesh.concatenate([plain, plain]).vertex_normal, "meshes without their own normals stay so")
        with self.assertRaises(ValueError):
            Mesh(mesh.vertices, mesh.faces, mesh.face_material, mesh.materials, vertex_normal=np.zeros((3, 3)))


if __name__ == "__main__":
    unittest.main()
