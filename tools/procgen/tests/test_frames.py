"""Frame conversion (Godot <-> 3DGS) and quaternion helpers."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.core import frames

RZ180 = np.diag([-1.0, -1.0, 1.0])


def random_rotations(n: int, seed: int = 3) -> np.ndarray:
    q = np.random.default_rng(seed).normal(size=(n, 4))
    return frames.quat_to_matrix(q)


class FrameTests(unittest.TestCase):
    def test_flip_negates_x_and_y_only_and_is_an_involution(self) -> None:
        p = np.array([[1.0, 2.0, 3.0], [-4.0, 5.0, -6.0]])
        flipped = frames.godot_to_3dgs_positions(p)
        np.testing.assert_array_equal(flipped, [[-1.0, -2.0, 3.0], [4.0, -5.0, -6.0]])
        np.testing.assert_array_equal(frames.gdgs_to_godot_positions(flipped), p)
        np.testing.assert_array_equal(
            p, [[1.0, 2.0, 3.0], [-4.0, 5.0, -6.0]]
        )  # input untouched

    def test_flip_works_on_a_single_vector(self) -> None:
        np.testing.assert_array_equal(
            frames.flip_xy(np.array([1.0, 2.0, 3.0])), [-1.0, -2.0, 3.0]
        )

    def test_rz180_quaternion_is_the_matrix_diag_minus1_minus1_1(self) -> None:
        np.testing.assert_allclose(
            frames.quat_to_matrix(frames.RZ180_QUAT), RZ180, atol=1e-12
        )

    def test_gdgs_node_correction_restores_the_godot_frame(self) -> None:
        # GDGS applies Rz(180) to an identity node: written data flipped then rotated = authored data.
        authored = np.random.default_rng(0).uniform(-50, 50, (20, 3))
        written = frames.godot_to_3dgs_positions(authored)
        np.testing.assert_allclose(written @ RZ180.T, authored, atol=1e-12)

    def test_quaternion_conversion_equals_left_multiplying_by_rz180(self) -> None:
        q = np.random.default_rng(7).normal(size=(50, 4))
        q /= np.linalg.norm(q, axis=1, keepdims=True)
        expected = RZ180 @ frames.quat_to_matrix(q)
        np.testing.assert_allclose(
            frames.quat_to_matrix(frames.godot_to_3dgs_quats(q)), expected, atol=1e-12
        )
        # Converting back is the same rotation (the quaternion may differ by an overall sign).
        back = frames.gdgs_to_godot_quats(frames.godot_to_3dgs_quats(q))
        np.testing.assert_allclose(
            frames.quat_to_matrix(back), frames.quat_to_matrix(q), atol=1e-12
        )

    def test_covariance_transforms_like_the_positions(self) -> None:
        q = np.random.default_rng(9).normal(size=(10, 4))
        scale = np.random.default_rng(10).uniform(0.1, 5.0, (10, 3))
        r = frames.quat_to_matrix(q)
        cov = np.einsum("nij,nj,nkj->nik", r, scale**2, r)
        r2 = frames.quat_to_matrix(frames.godot_to_3dgs_quats(q))
        cov2 = np.einsum("nij,nj,nkj->nik", r2, scale**2, r2)
        np.testing.assert_allclose(cov2, RZ180 @ cov @ RZ180.T, atol=1e-10)

    def test_identity_quaternion_becomes_a_half_turn_about_z(self) -> None:
        q = frames.godot_to_3dgs_quats(frames.quat_identity(2))
        np.testing.assert_allclose(q, [[0, 0, 0, 1], [0, 0, 0, 1]], atol=1e-12)

    def test_quat_multiply_matches_matrix_product_and_has_an_identity(self) -> None:
        rng = np.random.default_rng(11)
        a, b = rng.normal(size=(30, 4)), rng.normal(size=(30, 4))
        a /= np.linalg.norm(a, axis=1, keepdims=True)
        b /= np.linalg.norm(b, axis=1, keepdims=True)
        np.testing.assert_allclose(
            frames.quat_to_matrix(frames.quat_multiply(a, b)),
            frames.quat_to_matrix(a) @ frames.quat_to_matrix(b),
            atol=1e-12,
        )
        np.testing.assert_allclose(
            frames.quat_multiply(frames.quat_identity(30), a), a, atol=1e-15
        )

    def test_matrix_to_quat_round_trips_random_rotations(self) -> None:
        m = random_rotations(500)
        q = frames.matrix_to_quat(m)
        np.testing.assert_allclose(np.linalg.norm(q, axis=1), 1.0, atol=1e-12)
        self.assertTrue(np.all(q[:, 0] >= 0.0))
        np.testing.assert_allclose(frames.quat_to_matrix(q), m, atol=1e-10)

    def test_matrix_to_quat_handles_every_branch_and_half_turns(self) -> None:
        half_turns = [np.diag(d) for d in ([1, -1, -1], [-1, 1, -1], [-1, -1, 1])]
        cases = np.stack([np.eye(3), *half_turns])
        q = frames.matrix_to_quat(cases)
        np.testing.assert_allclose(frames.quat_to_matrix(q), cases, atol=1e-12)
        self.assertEqual(
            frames.matrix_to_quat(np.eye(3)).shape, (4,)
        )  # a single matrix works too
        np.testing.assert_allclose(
            frames.matrix_to_quat(np.eye(3)), [1, 0, 0, 0], atol=1e-12
        )

    def test_aabb_flip_negates_x_and_y_and_resorts(self) -> None:
        lo, hi = frames.aabb_godot_to_3dgs([-1.0, -2.0, -3.0], [4.0, 5.0, 6.0])
        np.testing.assert_array_equal(lo, [-4.0, -5.0, -3.0])
        np.testing.assert_array_equal(hi, [1.0, 2.0, 6.0])

    def test_aabb_of_flipped_points_equals_flipped_aabb(self) -> None:
        pts = np.random.default_rng(5).uniform(-9, 9, (100, 3))
        lo, hi = frames.aabb_godot_to_3dgs(pts.min(axis=0), pts.max(axis=0))
        flipped = frames.godot_to_3dgs_positions(pts)
        np.testing.assert_allclose(lo, flipped.min(axis=0))
        np.testing.assert_allclose(hi, flipped.max(axis=0))


if __name__ == "__main__":
    unittest.main()
