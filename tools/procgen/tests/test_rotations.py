"""The quaternion and matrix helpers that orient the sky's nebula blobs (`core/rotations.py`)."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.core import rotations


def random_rotations(n: int, seed: int = 3) -> np.ndarray:
    return rotations.quat_to_matrix(np.random.default_rng(seed).normal(size=(n, 4)))


class RotationTests(unittest.TestCase):
    def test_identity_quaternions_give_identity_matrices(self) -> None:
        q = rotations.quat_identity(3)
        np.testing.assert_array_equal(q, [[1.0, 0.0, 0.0, 0.0]] * 3)
        np.testing.assert_allclose(rotations.quat_to_matrix(q), np.tile(np.eye(3), (3, 1, 1)), atol=1e-15)

    def test_known_quarter_turns(self) -> None:
        h = np.sqrt(0.5)
        # A quarter turn about +Z takes +X to +Y; about +X takes +Y to +Z; about +Y takes +Z to +X.
        cases = {
            (h, 0.0, 0.0, h): ([1.0, 0.0, 0.0], [0.0, 1.0, 0.0]),
            (h, h, 0.0, 0.0): ([0.0, 1.0, 0.0], [0.0, 0.0, 1.0]),
            (h, 0.0, h, 0.0): ([0.0, 0.0, 1.0], [1.0, 0.0, 0.0]),
        }
        for q, (v, expected) in cases.items():
            np.testing.assert_allclose(rotations.quat_to_matrix(np.array(q)) @ v, expected, atol=1e-12, err_msg=str(q))
            np.testing.assert_allclose(rotations.matrix_to_quat(rotations.quat_to_matrix(np.array(q))), q, atol=1e-12)

    def test_quaternions_are_normalised_first(self) -> None:
        np.testing.assert_allclose(rotations.quat_to_matrix(np.array([2.0, 0.0, 0.0, 2.0])),
                                   rotations.quat_to_matrix(np.array([1.0, 0.0, 0.0, 1.0])), atol=1e-15)

    def test_random_rotations_are_proper(self) -> None:
        m = random_rotations(200)
        np.testing.assert_allclose(m @ np.swapaxes(m, -1, -2), np.tile(np.eye(3), (200, 1, 1)), atol=1e-12)
        np.testing.assert_allclose(np.linalg.det(m), 1.0, atol=1e-12)

    def test_matrix_to_quat_round_trips_random_rotations(self) -> None:
        m = random_rotations(500)
        q = rotations.matrix_to_quat(m)
        np.testing.assert_allclose(np.linalg.norm(q, axis=1), 1.0, atol=1e-12)
        self.assertTrue(np.all(q[:, 0] >= 0.0))
        np.testing.assert_allclose(rotations.quat_to_matrix(q), m, atol=1e-10)

    def test_matrix_to_quat_handles_every_branch_and_half_turns(self) -> None:
        # The identity takes the trace pivot; each half turn takes one diagonal pivot.
        half_turns = [np.diag(d) for d in ([1.0, -1.0, -1.0], [-1.0, 1.0, -1.0], [-1.0, -1.0, 1.0])]
        cases = np.stack([np.eye(3), *half_turns])
        q = rotations.matrix_to_quat(cases)
        np.testing.assert_allclose(q, np.eye(4), atol=1e-12)
        np.testing.assert_allclose(rotations.quat_to_matrix(q), cases, atol=1e-12)
        self.assertEqual(rotations.matrix_to_quat(np.eye(3)).shape, (4,))


if __name__ == "__main__":
    unittest.main()
