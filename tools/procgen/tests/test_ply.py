"""PLY writer/reader: header layout, field encoding, round trip, determinism, malformed input."""

from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.core import ply
from tools.procgen.core.ply import SplatData

EXPECTED_PROPERTIES = [
    "x", "y", "z", "nx", "ny", "nz", "f_dc_0", "f_dc_1", "f_dc_2",
    "opacity", "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3",
]  # fmt: skip


def random_splats(n: int = 64, seed: int = 1) -> SplatData:
    rng = np.random.default_rng(seed)
    rot = rng.normal(size=(n, 4))
    return SplatData(
        xyz=rng.uniform(-100, 100, (n, 3)),
        rgb=rng.uniform(0.0, 1.5, (n, 3)),
        alpha=rng.uniform(0.01, 0.99, n),
        scale=np.exp(rng.uniform(np.log(0.01), np.log(500.0), (n, 3))),
        rot=rot / np.linalg.norm(rot, axis=1, keepdims=True),
        normals=rng.normal(size=(n, 3)),
    )


class PlyTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def test_header_is_standard_3dgs_binary_little_endian(self) -> None:
        path = ply.write_ply(self.dir / "a.ply", random_splats(10), comments=("hello",))
        raw = path.read_bytes()
        header, _, body = raw.partition(b"end_header\n")
        lines = header.decode("ascii").split("\n")
        self.assertEqual(lines[0], "ply")
        self.assertEqual(lines[1], "format binary_little_endian 1.0")
        self.assertIn("comment hello", lines)
        self.assertIn("element vertex 10", lines)
        props = [line.split()[2] for line in lines if line.startswith("property")]
        self.assertEqual(props, EXPECTED_PROPERTIES)
        self.assertTrue(
            all(
                line.startswith("property float ")
                for line in lines
                if "property" in line
            )
        )
        self.assertEqual(len(body), 10 * 17 * 4)

    def test_parses_back_with_the_expected_fields(self) -> None:
        splats = random_splats()
        parsed = ply.read_ply(ply.write_ply(self.dir / "a.ply", splats))
        self.assertEqual(parsed.names, EXPECTED_PROPERTIES)
        self.assertEqual(parsed.count, len(splats))
        self.assertEqual(parsed.format, "binary_little_endian 1.0")

    def test_round_trip_decodes_to_the_original_values(self) -> None:
        splats = random_splats()
        back = ply.read_ply(ply.write_ply(self.dir / "a.ply", splats)).to_splats()
        np.testing.assert_allclose(back.xyz, splats.xyz, rtol=1e-6, atol=1e-5)
        np.testing.assert_allclose(back.rgb, splats.rgb, rtol=1e-5, atol=2e-6)
        np.testing.assert_allclose(back.alpha, splats.alpha, rtol=1e-5, atol=1e-6)
        np.testing.assert_allclose(back.scale, splats.scale, rtol=1e-5)
        np.testing.assert_allclose(back.rot, splats.rot, atol=1e-6)
        np.testing.assert_allclose(back.normals, splats.normals, atol=1e-6)

    def test_encoding_matches_the_3dgs_convention(self) -> None:
        splats = SplatData(
            xyz=np.array([[1.0, 2.0, 3.0]]),
            rgb=np.array([[0.5, 0.5 + ply.SH_C0, 0.0]]),
            alpha=np.array([0.5]),
            scale=np.array([[1.0, np.e, 10.0]]),
            rot=np.array([[2.0, 0.0, 0.0, 0.0]]),  # un-normalised on purpose
        )
        v = ply.read_ply(ply.write_ply(self.dir / "a.ply", splats)).vertices[0]
        self.assertAlmostEqual(float(v["f_dc_0"]), 0.0, places=6)  # (0.5 - 0.5) / C0
        self.assertAlmostEqual(float(v["f_dc_1"]), 1.0, places=5)
        self.assertAlmostEqual(float(v["f_dc_2"]), -0.5 / ply.SH_C0, places=4)
        self.assertAlmostEqual(float(v["opacity"]), 0.0, places=6)  # logit(0.5)
        np.testing.assert_allclose(
            [v["scale_0"], v["scale_1"], v["scale_2"]],
            [0.0, 1.0, np.log(10.0)],
            atol=1e-6,
        )
        np.testing.assert_allclose(
            [v["rot_0"], v["rot_1"], v["rot_2"], v["rot_3"]], [1, 0, 0, 0]
        )  # (w, x, y, z)
        np.testing.assert_allclose(
            [v["nx"], v["ny"], v["nz"]], [0, 0, 0]
        )  # missing normals -> zeros

    def test_fully_opaque_and_transparent_alpha_stay_finite(self) -> None:
        splats = random_splats(4)
        splats.alpha = np.array([0.0, 1.0, 1e-9, 1.0 - 1e-12])
        parsed = ply.read_ply(ply.write_ply(self.dir / "a.ply", splats))
        self.assertTrue(np.all(np.isfinite(parsed.column("opacity"))))
        alpha = parsed.to_splats().alpha
        self.assertGreaterEqual(float(alpha[1]), 0.999)
        self.assertLessEqual(float(alpha[1]), 1.0)
        self.assertGreater(float(alpha[0]), 0.0)

    def test_negative_colour_is_clamped_and_tiny_scale_stays_finite(self) -> None:
        splats = random_splats(2)
        splats.rgb = np.array([[-1.0, 0.0, 0.2], [0.1, 0.1, 0.1]])
        splats.scale = np.array([[0.0, 1e-12, 1.0], [1.0, 1.0, 1.0]])
        back = ply.read_ply(ply.write_ply(self.dir / "a.ply", splats)).to_splats()
        self.assertTrue(np.all(back.rgb >= -1e-6))
        self.assertTrue(np.all(np.isfinite(back.scale)))
        self.assertTrue(np.all(back.scale > 0.0))

    def test_same_input_gives_identical_bytes(self) -> None:
        a = ply.write_ply(self.dir / "a.ply", random_splats(200, seed=5)).read_bytes()
        b = ply.write_ply(self.dir / "b.ply", random_splats(200, seed=5)).read_bytes()
        self.assertEqual(hashlib.sha256(a).hexdigest(), hashlib.sha256(b).hexdigest())

    def test_writer_does_not_modify_its_input(self) -> None:
        splats = random_splats(8)
        before = (splats.alpha.copy(), splats.rot.copy(), splats.scale.copy())
        ply.write_ply(self.dir / "a.ply", splats)
        for original, now in zip(before, (splats.alpha, splats.rot, splats.scale)):
            np.testing.assert_array_equal(original, now)

    def test_validate_rejects_mismatched_shapes(self) -> None:
        splats = random_splats(4)
        splats.alpha = splats.alpha[:3]
        with self.assertRaisesRegex(ValueError, "alpha"):
            ply.write_ply(self.dir / "a.ply", splats)

    def test_concatenate_keeps_order_and_fills_missing_normals(self) -> None:
        a, b = random_splats(3, seed=1), random_splats(2, seed=2)
        b.normals = None
        both = SplatData.concatenate([a, b])
        self.assertEqual(len(both), 5)
        np.testing.assert_array_equal(both.xyz[:3], a.xyz)
        np.testing.assert_array_equal(both.xyz[3:], b.xyz)
        np.testing.assert_array_equal(both.normals[3:], np.zeros((2, 3)))

    def test_reader_rejects_malformed_files(self) -> None:
        good = ply.write_ply(self.dir / "good.ply", random_splats(4)).read_bytes()
        cases = {
            "truncated body": good[:-4],
            "extra bytes": good + b"\0",
            "no end_header": good.replace(b"end_header\n", b""),
            "wrong magic": b"pla" + good[3:],
            "ascii format": good.replace(b"binary_little_endian", b"ascii"),
            "big endian": good.replace(b"binary_little_endian", b"binary_big_endian"),
        }
        for name, data in cases.items():
            with self.subTest(name):
                bad = self.dir / "bad.ply"
                bad.write_bytes(data)
                with self.assertRaises(ValueError):
                    ply.read_ply(bad)

    def test_reader_reports_missing_splat_properties(self) -> None:
        path = self.dir / "points.ply"
        header = b"ply\nformat binary_little_endian 1.0\nelement vertex 1\nproperty float x\nend_header\n"
        path.write_bytes(header + np.zeros(1, "<f4").tobytes())
        parsed = ply.read_ply(path)
        with self.assertRaisesRegex(ValueError, "missing"):
            parsed.to_splats()


if __name__ == "__main__":
    unittest.main()
