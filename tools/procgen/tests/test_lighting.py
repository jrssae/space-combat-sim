"""``core/lighting``: GDGS's 4-byte lighting record (AC30): the byte layout, normals against analytic surfaces, the file."""

from __future__ import annotations

import math
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.core import frames
from tools.procgen.core import lighting
from tools.procgen.core.geometry import Material, box, lathe
from tools.procgen.core.ply import SplatData
from tools.procgen.core.sampling import sample_mesh, to_splats

MAT = Material("m", (0.5, 0.5, 0.5))
MAX_ERROR_DEG = 5.0  # AC30


def angle_deg(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return np.degrees(np.arccos(np.clip(np.einsum("ij,ij->i", a, b), -1.0, 1.0)))


def splats_with_normals(normals: np.ndarray) -> SplatData:
    n = len(normals)
    return SplatData(np.zeros((n, 3)), np.full((n, 3), 0.5), np.full(n, 0.9), np.full((n, 3), 0.1), frames.quat_identity(n), normals)


class RecordLayoutTests(unittest.TestCase):
    """The values below come from running GDGS's own codec (`gaussian_lighting_resource.gd`) by hand."""

    def test_axis_normals_give_the_bytes_gdgs_expects(self) -> None:
        normals = np.array(
            [[0, 0, 1], [1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, -1]], dtype=float
        )
        records = lighting.lighting_records(normals)
        self.assertEqual(records.dtype, np.uint8)
        np.testing.assert_array_equal(
            records[:, :2], [[128, 128], [255, 128], [0, 128], [128, 255], [128, 0], [255, 255]]
        )

    def test_a_diagonal_normal_gives_the_bytes_gdgs_expects(self) -> None:
        records = lighting.lighting_records(np.array([[1.0, 1.0, 1.0]]))
        np.testing.assert_array_equal(records[0, :2], [170, 170])

    def test_halves_round_up_as_godot_does(self) -> None:
        # Godot's roundf takes 126.5 up to 127; numpy's round would take it down to 126.
        self.assertEqual(int(lighting.encode_signed_byte(np.array(126.5 / 255.0 * 2.0 - 1.0))), 127)

    def test_surface_splats_have_full_confidence_and_no_cavity_term(self) -> None:
        records = lighting.lighting_records(np.array([[0.0, 1.0, 0.0], [1.0, 0.0, 0.0]]))
        np.testing.assert_array_equal(records[:, 2], [255, 255], "AO 1.0")
        np.testing.assert_array_equal(records[:, 3], [255, 255], "confidence 1.0")

    def test_a_splat_without_a_normal_gets_no_directional_light(self) -> None:
        records = lighting.lighting_records(np.array([[0.0, 0.0, 0.0], [0.0, 2.0, 0.0]]))
        self.assertEqual(int(records[0, 3]), 0, "confidence 0: GDGS fades it to flat ambient")
        self.assertEqual(int(records[1, 3]), 255)
        np.testing.assert_array_equal(records[1, :2], [128, 255], "a normal is normalised first")

    def test_every_direction_survives_the_bytes(self) -> None:
        rng = np.random.default_rng(3)
        normals = rng.normal(size=(20_000, 3))
        normals /= np.linalg.norm(normals, axis=1, keepdims=True)
        decoded = lighting.decode_normals(lighting.lighting_records(normals))
        self.assertLess(float(angle_deg(normals, decoded).max()), 1.5, "an 8-bit pair is about 1 degree")


class AnalyticSurfaceTests(unittest.TestCase):
    """AC30: on a test shape each normal is within 5 degrees of the analytic surface normal."""

    def records_of(self, mesh, spacing: float, seed: int) -> tuple[SplatData, np.ndarray]:
        samples = sample_mesh(mesh, spacing, np.random.default_rng(seed))
        splats = to_splats(samples, np.full((len(samples), 3), 0.5), spacing)
        return splats, lighting.decode_normals(lighting.lighting_records(splats.normals))

    def test_a_sphere(self) -> None:
        rings = 64
        profile = [(-math.cos(math.pi * k / rings), math.sin(math.pi * k / rings)) for k in range(rings + 1)]
        splats, decoded = self.records_of(lathe(profile, 128, MAT), 0.03, 1)
        analytic = splats.xyz / np.linalg.norm(splats.xyz, axis=1, keepdims=True)
        self.assertGreater(len(splats), 5_000)
        self.assertLess(float(angle_deg(analytic, decoded).max()), MAX_ERROR_DEG)

    def test_a_box_keeps_its_hard_edges(self) -> None:
        splats, decoded = self.records_of(box((2.0, 2.0, 2.0), MAT), 0.04, 2)
        axis = np.argmax(np.abs(splats.xyz), axis=1)
        analytic = np.zeros_like(splats.xyz)
        analytic[np.arange(len(axis)), axis] = np.sign(splats.xyz[np.arange(len(axis)), axis])
        self.assertLess(float(angle_deg(analytic, decoded).max()), MAX_ERROR_DEG)


class LightingFileTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def test_the_file_is_four_bytes_per_splat_and_nothing_else(self) -> None:
        normals = np.array([[0.0, 0.0, 1.0], [1.0, 0.0, 0.0], [0.0, -1.0, 0.0]])
        path = lighting.write_lighting(self.dir / "x.light", splats_with_normals(normals))
        self.assertEqual(path.stat().st_size, 3 * lighting.BYTES_PER_SPLAT)
        self.assertEqual(path.read_bytes()[:4], bytes([128, 128, 255, 255]))
        np.testing.assert_array_equal(lighting.read_lighting(path), lighting.lighting_records(normals))

    def test_a_file_of_the_wrong_length_is_refused(self) -> None:
        path = self.dir / "bad.light"
        path.write_bytes(bytes(7))
        with self.assertRaises(ValueError):
            lighting.read_lighting(path)

    def test_splats_without_normals_are_written_without_directional_light(self) -> None:
        splats = splats_with_normals(np.zeros((2, 3)))
        splats.normals = None
        records = lighting.read_lighting(lighting.write_lighting(self.dir / "n.light", splats))
        np.testing.assert_array_equal(records[:, 3], [0, 0])

    def test_file_names(self) -> None:
        self.assertEqual(lighting.lod_file_name("thing", 2), "thing_lod2.light")
        self.assertEqual(lighting.chunk_file_name("thing", "arm_ur"), "thing_chunk_arm_ur.light")


if __name__ == "__main__":
    unittest.main()
