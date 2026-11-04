"""Rotations as quaternions ``(w, x, y, z)`` and matrices, for the sky's nebula blobs (their orientation field)."""

from __future__ import annotations

import numpy as np


def quat_identity(count: int) -> np.ndarray:
    out = np.zeros((count, 4))
    out[:, 0] = 1.0
    return out


def quat_normalize(q: np.ndarray) -> np.ndarray:
    return q / np.linalg.norm(q, axis=-1, keepdims=True)


def quat_to_matrix(q: np.ndarray) -> np.ndarray:
    """Rotation matrices ``(..., 3, 3)`` from quaternions ``(..., 4)`` (normalised first)."""
    w, x, y, z = np.moveaxis(quat_normalize(np.asarray(q, dtype=float)), -1, 0)
    return np.stack(
        [
            np.stack(
                [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
                axis=-1,
            ),
            np.stack(
                [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
                axis=-1,
            ),
            np.stack(
                [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)],
                axis=-1,
            ),
        ],
        axis=-2,
    )


def matrix_to_quat(m: np.ndarray) -> np.ndarray:
    """Quaternions ``(..., 4)`` from proper rotation matrices ``(..., 3, 3)`` (w >= 0).

    Uses the numerically stable branch on the largest of the trace and the diagonal.
    """
    m = np.asarray(m, dtype=float)
    m00, m11, m22 = m[..., 0, 0], m[..., 1, 1], m[..., 2, 2]
    trace = m00 + m11 + m22

    # Four candidate quaternions, each scaled by 4 * its pivot component; pick the best pivot.
    with np.errstate(invalid="ignore"):
        s_w = 2.0 * np.sqrt(np.maximum(1.0 + trace, 0.0))
        s_x = 2.0 * np.sqrt(np.maximum(1.0 + m00 - m11 - m22, 0.0))
        s_y = 2.0 * np.sqrt(np.maximum(1.0 - m00 + m11 - m22, 0.0))
        s_z = 2.0 * np.sqrt(np.maximum(1.0 - m00 - m11 + m22, 0.0))

        def safe(value: np.ndarray, pivot: np.ndarray) -> np.ndarray:
            return value / np.where(pivot == 0.0, 1.0, pivot)

        cand_w = np.stack(
            [
                s_w / 4,
                safe(m[..., 2, 1] - m[..., 1, 2], s_w),
                safe(m[..., 0, 2] - m[..., 2, 0], s_w),
                safe(m[..., 1, 0] - m[..., 0, 1], s_w),
            ],
            axis=-1,
        )
        cand_x = np.stack(
            [
                safe(m[..., 2, 1] - m[..., 1, 2], s_x),
                s_x / 4,
                safe(m[..., 0, 1] + m[..., 1, 0], s_x),
                safe(m[..., 0, 2] + m[..., 2, 0], s_x),
            ],
            axis=-1,
        )
        cand_y = np.stack(
            [
                safe(m[..., 0, 2] - m[..., 2, 0], s_y),
                safe(m[..., 0, 1] + m[..., 1, 0], s_y),
                s_y / 4,
                safe(m[..., 1, 2] + m[..., 2, 1], s_y),
            ],
            axis=-1,
        )
        cand_z = np.stack(
            [
                safe(m[..., 1, 0] - m[..., 0, 1], s_z),
                safe(m[..., 0, 2] + m[..., 2, 0], s_z),
                safe(m[..., 1, 2] + m[..., 2, 1], s_z),
                s_z / 4,
            ],
            axis=-1,
        )

    pivots = np.stack([s_w, s_x, s_y, s_z], axis=-1)
    best = np.argmax(pivots, axis=-1)[..., None]
    candidates = np.stack([cand_w, cand_x, cand_y, cand_z], axis=-2)
    q = np.take_along_axis(candidates, best[..., None], axis=-2)[..., 0, :]
    q = quat_normalize(q)
    return np.where(q[..., :1] < 0.0, -q, q)
