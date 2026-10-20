"""core.geometry: primitives, windings, transforms, normals, materials."""

from __future__ import annotations

import math
import unittest

import numpy as np

from tools.procgen.core import geometry as g

HULL = g.Material("hull", (0.6, 0.6, 0.6), paneled=True)
DARK = g.Material("dark", (0.1, 0.1, 0.1))


def outward(mesh: g.Mesh, centre) -> bool:
    """Every face normal points away from ``centre`` (convex solids)."""
    d = np.einsum("ij,ij->i", mesh.face_normals(), mesh.face_centroids() - np.asarray(centre, float))
    return bool(np.all(d > -1e-9))


class MaterialTests(unittest.TestCase):
    def test_validation(self) -> None:
        with self.assertRaises(ValueError):
            g.Material("", (1, 1, 1))
        with self.assertRaises(ValueError):
            g.Material("m", (1, -1, 1))
        with self.assertRaises(ValueError):
            g.Material("m", (1, 1, 1), transmittance=1.0)
        self.assertEqual(g.Material("m", (1, 1, 1)).transmittance, 0.0)


class PrimitiveTests(unittest.TestCase):
    def test_box_is_a_closed_hard_edged_solid(self) -> None:
        mesh = g.box((1.0, 2.0, 3.0), HULL, center=(1.0, 0.0, 0.0))
        self.assertEqual((mesh.vertex_count, mesh.face_count), (24, 12))
        self.assertAlmostEqual(mesh.area(), 2 * (1 * 2 + 2 * 3 + 1 * 3))
        np.testing.assert_allclose(mesh.area_centroid(), [1.0, 0.0, 0.0], atol=1e-12)
        self.assertTrue(outward(mesh, [1.0, 0.0, 0.0]))
        # Hard edges: every vertex normal equals its face normal.
        vn = mesh.vertex_normals()
        for k in range(3):
            np.testing.assert_allclose(vn[mesh.faces[:, k]], mesh.face_normals(), atol=1e-12)

    def test_tapered_box_offsets_the_back_face_and_assigns_face_materials(self) -> None:
        mesh = g.tapered_box(2.0, (1.0, 1.0), (0.5, 0.5), HULL, offset_b=(0.3, 0.0), materials_by_face={"back": DARK})
        lo, hi = mesh.bounds()
        np.testing.assert_allclose(lo, [-0.5, -0.5, -1.0])
        np.testing.assert_allclose(hi, [0.55, 0.5, 1.0])
        self.assertEqual([m.name for m in mesh.materials], ["hull", "dark"])
        back = mesh.face_centroids()[:, 2] > 0.99
        self.assertTrue(np.all(mesh.face_material[back] == 1))
        self.assertTrue(np.all(mesh.face_material[~back] == 0))

    def test_lathe_cylinder_area_normals_and_creases(self) -> None:
        profile = [(0.0, 0.0), (0.0, 0.5), (2.0, 0.5), (2.0, 0.0)]
        smooth = g.lathe(profile, 64, HULL)
        hard = g.lathe(profile, 64, HULL, creases={1, 2})
        expect = 2 * math.pi * 0.5 * 2.0 + 2 * math.pi * 0.25
        self.assertAlmostEqual(smooth.area(), expect, delta=0.02 * expect)
        self.assertTrue(outward(smooth, [0.0, 0.0, 1.0]))
        self.assertTrue(outward(hard, [0.0, 0.0, 1.0]))
        self.assertEqual(hard.vertex_count - smooth.vertex_count, 2 * 64)  # two duplicated rings
        # Shared rim vertices get normals that lean towards the caps; duplicated (crease) rim
        # vertices on the side stay purely radial.
        rim = np.hypot(smooth.vertices[:, 0], smooth.vertices[:, 1]) > 0.4
        self.assertTrue(np.all(np.abs(smooth.vertex_normals()[rim, 2]) > 0.05))  # area-weighted: small lean
        vn_h = hard.vertex_normals()
        rim_h = np.hypot(hard.vertices[:, 0], hard.vertices[:, 1]) > 0.4
        self.assertEqual(int((np.abs(vn_h[rim_h, 2]) < 1e-9).sum()), 2 * 64)  # the two side rings
        self.assertEqual(int((np.abs(vn_h[rim_h, 2]) > 0.99).sum()), 2 * 64)  # the two cap rings

    def test_lathe_poles_and_segment_materials(self) -> None:
        profile = [(-1.0, 0.0), (0.0, 0.5), (1.0, 0.5), (2.0, 0.0)]
        mesh = g.lathe(profile, 12, [HULL, DARK, HULL])
        self.assertTrue(outward(mesh, [0.0, 0.0, 0.5]))
        self.assertEqual(mesh.vertex_count, 1 + 12 + 12 + 1)
        mid = (mesh.face_centroids()[:, 2] > 0.0) & (mesh.face_centroids()[:, 2] < 1.0)
        self.assertTrue(np.all(mesh.face_material[mid] == 1))
        self.assertTrue(np.all(mesh.face_material[~mid] == 0))

    def test_lathe_rejects_bad_input(self) -> None:
        with self.assertRaises(ValueError):
            g.lathe([(0.0, 1.0)], 8, HULL)
        with self.assertRaises(ValueError):
            g.lathe([(0.0, 1.0), (1.0, 1.0)], 2, HULL)
        with self.assertRaises(ValueError):
            g.lathe([(0.0, 0.0), (1.0, 0.0)], 8, HULL)
        with self.assertRaises(ValueError):
            g.lathe([(0.0, 1.0), (1.0, 1.0)], 8, [HULL, DARK])

    def test_loft_and_superellipse_ring(self) -> None:
        ring = g.superellipse_ring(2.0, 1.0, 32)
        self.assertEqual(ring.shape, (32, 2))
        self.assertTrue(np.all(np.abs(ring[:, 0]) <= 1.0 + 1e-12))
        self.assertTrue(np.all(np.abs(ring[:, 1]) <= 0.5 + 1e-12))
        # On the curve |x/a|^4 + |y/b|^4 = 1.
        np.testing.assert_allclose(np.abs(ring[:, 0]) ** 4 + np.abs(ring[:, 1] / 0.5) ** 4, 1.0, atol=1e-9)
        # CCW: positive signed area.
        x, y = ring[:, 0], ring[:, 1]
        self.assertGreater(float(0.5 * np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y)), 0.0)
        sections = [np.column_stack([ring, np.full(32, z)]) for z in (-1.0, 0.0, 1.0)]
        tube = g.loft(sections, HULL, cap_material=DARK)
        self.assertTrue(outward(tube, [0.0, 0.0, 0.0]))
        self.assertEqual(tube.face_count, 2 * 32 * 2 + 2 * 32)
        self.assertEqual({m.name for m in tube.materials}, {"hull", "dark"})
        pointed = g.loft([np.array([[0.0, 0.0, -2.0]]), *sections], HULL, cap_start=False)
        self.assertTrue(outward(pointed, [0.0, 0.0, 0.0]))
        with self.assertRaises(ValueError):
            g.loft(sections[:1], HULL)

    def test_ellipsoid_cap(self) -> None:
        cap = g.ellipsoid_cap((1.0, 0.5, 2.0), 0.0, HULL)
        self.assertTrue(outward(cap, [0.0, 0.0, 0.0]))
        lo, hi = cap.bounds()
        np.testing.assert_allclose(lo, [-1.0, 0.0, -2.0], atol=1e-9)
        np.testing.assert_allclose(hi, [1.0, 0.5, 2.0], atol=1e-9)
        with self.assertRaises(ValueError):
            g.ellipsoid_cap((1.0, 0.5, 2.0), 0.6, HULL)


class MeshOperationTests(unittest.TestCase):
    def test_transform_translate_mirror_keep_normals_outward(self) -> None:
        mesh = g.box((1.0, 1.0, 1.0), HULL)
        rotated = mesh.transformed(g.rotation_z(0.3), (2.0, 0.0, 0.0))
        self.assertTrue(outward(rotated, [2.0, 0.0, 0.0]))
        self.assertTrue(outward(mesh.mirrored("x"), [0.0, 0.0, 0.0]))
        self.assertTrue(outward(mesh.translated((0.0, 5.0, 0.0)), [0.0, 5.0, 0.0]))
        self.assertFalse(outward(mesh.flipped(), [0.0, 0.0, 0.0]))
        np.testing.assert_allclose(mesh.mirrored("y").vertices[:, 1], -mesh.vertices[:, 1])

    def test_concatenate_merges_materials_by_name(self) -> None:
        a = g.box((1.0, 1.0, 1.0), HULL)
        b = g.box((1.0, 1.0, 1.0), DARK, center=(3.0, 0.0, 0.0))
        c = g.box((1.0, 1.0, 1.0), HULL, center=(6.0, 0.0, 0.0))
        merged = g.Mesh.concatenate([a, b, c])
        self.assertEqual([m.name for m in merged.materials], ["hull", "dark"])
        self.assertEqual(merged.vertex_count, 72)
        self.assertEqual(list(merged.face_material[:12]), [0] * 12)
        self.assertEqual(list(merged.face_material[12:24]), [1] * 12)
        self.assertEqual(list(merged.face_material[24:]), [0] * 12)
        self.assertEqual(merged.faces.max(), 71)
        other = g.Material("hull", (0.1, 0.1, 0.1))
        with self.assertRaises(ValueError):
            g.Mesh.concatenate([a, g.box((1, 1, 1), other)])
        self.assertEqual(g.Mesh.concatenate([]).face_count, 0)

    def test_validate_rejects_bad_indices(self) -> None:
        with self.assertRaises(ValueError):
            g.Mesh(np.zeros((3, 3)), [[0, 1, 5]], [0], (HULL,))
        with self.assertRaises(ValueError):
            g.Mesh(np.zeros((3, 3)), [[0, 1, 2]], [1], (HULL,))
        with self.assertRaises(ValueError):
            g.Mesh(np.zeros((3, 3)), [[0, 1, 2]], [0, 0], (HULL,))

    def test_assign_material_by_predicate_and_with_material(self) -> None:
        mesh = g.box((1.0, 1.0, 1.0), HULL)
        top = mesh.face_centroids()[:, 1] > 0.49
        recoloured = g.assign_material_by_predicate(mesh, DARK, top)
        self.assertEqual(recoloured.material_index("dark"), 1)
        self.assertEqual(int((recoloured.face_material == 1).sum()), 2)
        self.assertEqual(mesh.with_material(DARK).materials, (DARK,))
        with self.assertRaises(KeyError):
            mesh.material_index("nope")

    def test_area_centroid_is_area_weighted(self) -> None:
        big = g.box((2.0, 2.0, 2.0), HULL)
        small = g.box((0.2, 0.2, 0.2), HULL, center=(10.0, 0.0, 0.0))
        c = g.Mesh.concatenate([big, small]).area_centroid()
        expected = (24.0 * 0.0 + 0.24 * 10.0) / 24.24
        self.assertAlmostEqual(float(c[0]), expected, places=9)


class LinearAlgebraTests(unittest.TestCase):
    def test_tangent_basis_is_right_handed_orthonormal(self) -> None:
        n = np.random.default_rng(0).normal(size=(300, 3))
        n = np.vstack([g.unit(n), np.eye(3), -np.eye(3)])
        e1, e2 = g.tangent_basis(n)
        np.testing.assert_allclose(np.linalg.norm(e1, axis=1), 1.0, atol=1e-12)
        np.testing.assert_allclose(np.linalg.norm(e2, axis=1), 1.0, atol=1e-12)
        np.testing.assert_allclose(np.einsum("ij,ij->i", e1, n), 0.0, atol=1e-12)
        np.testing.assert_allclose(np.einsum("ij,ij->i", e1, e2), 0.0, atol=1e-12)
        np.testing.assert_allclose(np.cross(e1, e2), n, atol=1e-12)

    def test_rotations_and_basis_from_z(self) -> None:
        np.testing.assert_allclose(g.rotation_x(math.pi / 2) @ [0, 1, 0], [0, 0, 1], atol=1e-12)
        np.testing.assert_allclose(g.rotation_y(math.pi / 2) @ [0, 0, 1], [1, 0, 0], atol=1e-12)
        np.testing.assert_allclose(g.rotation_z(math.pi / 2) @ [1, 0, 0], [0, 1, 0], atol=1e-12)
        for r in (g.rotation_x(0.4), g.rotation_y(1.1), g.rotation_z(-2.0)):
            self.assertAlmostEqual(float(np.linalg.det(r)), 1.0)
        b = g.basis_from_z([0, 0, 2], x_hint=[1, 1, 0])
        np.testing.assert_allclose(b[:, 2], [0, 0, 1])
        np.testing.assert_allclose(b[:, 0], [math.sqrt(0.5), math.sqrt(0.5), 0], atol=1e-12)
        self.assertAlmostEqual(float(np.linalg.det(b)), 1.0)
        self.assertAlmostEqual(float(np.linalg.det(g.basis_from_z([1, 2, 3]))), 1.0)
        self.assertAlmostEqual(float(np.linalg.det(g.mirror_matrix("y"))), -1.0)
        self.assertEqual(g.unit(np.zeros(3)).tolist(), [0.0, 0.0, 0.0])


if __name__ == "__main__":
    unittest.main()
