"""Coordinate frames and quaternions: Godot <-> 3DGS (GDGS) conventions.

Godot frame: +X right, +Y up, -Z forward, metres. Splat PLYs are written in the
GDGS/3DGS orientation, which differs by a rotation of 180 degrees about Z, because GDGS rotates
every identity-basis ``GaussianSplatNode`` by Rz(180) on entering the tree. Writing the data
pre-rotated therefore lets the node stay at identity (docs/research-notes.md).

Rz(180) is its own inverse, so one function serves both directions.

Quaternions are ``(w, x, y, z)`` (the PLY ``rot_0..rot_3`` order), Hamilton product, and act on
column vectors: the rotation matrix of ``q`` maps local axes to world axes, which is the matrix
3DGS uses in ``Sigma = R S S^T R^T``.
"""

from __future__ import annotations

import numpy as np

# Rotation of 180 degrees about +Z: (w, x, y, z) = (cos 90, 0, 0, sin 90).
RZ180_QUAT = np.array([0.0, 0.0, 0.0, 1.0])


def flip_xy(xyz: np.ndarray) -> np.ndarray:
    """Apply Rz(180) to positions or vectors: negate x and y."""
    out = np.array(xyz, copy=True)
    out[..., 0] *= -1
    out[..., 1] *= -1
    return out


def godot_to_3dgs_positions(xyz: np.ndarray) -> np.ndarray:
    return flip_xy(xyz)


def gdgs_to_godot_positions(xyz: np.ndarray) -> np.ndarray:
    return flip_xy(xyz)


def quat_identity(count: int) -> np.ndarray:
    out = np.zeros((count, 4))
    out[:, 0] = 1.0
    return out


def quat_normalize(q: np.ndarray) -> np.ndarray:
    return q / np.linalg.norm(q, axis=-1, keepdims=True)


def quat_multiply(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Hamilton product ``a * b`` (apply ``b`` first, then ``a``); broadcasts over leading axes."""
    aw, ax, ay, az = np.moveaxis(np.asarray(a, dtype=float), -1, 0)
    bw, bx, by, bz = np.moveaxis(np.asarray(b, dtype=float), -1, 0)
    return np.stack(
        [
            aw * bw - ax * bx - ay * by - az * bz,
            aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
        ],
        axis=-1,
    )


def godot_to_3dgs_quats(q: np.ndarray) -> np.ndarray:
    """Re-express orientations after Rz(180) of the whole scene: ``q' = qz * q``."""
    return quat_multiply(RZ180_QUAT, q)


def gdgs_to_godot_quats(q: np.ndarray) -> np.ndarray:
    return quat_multiply(RZ180_QUAT, q)


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


def aabb_godot_to_3dgs(
    aabb_min: np.ndarray | list[float], aabb_max: np.ndarray | list[float]
) -> tuple[np.ndarray, np.ndarray]:
    """AABB after Rz(180): negate x and y, then re-sort min/max (what the importer reports)."""
    lo = flip_xy(np.asarray(aabb_min, dtype=float))
    hi = flip_xy(np.asarray(aabb_max, dtype=float))
    return np.minimum(lo, hi), np.maximum(lo, hi)
