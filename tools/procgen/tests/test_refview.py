"""tools/refview (M5-T11): the STL reader, the frame and scale step, sections, shells and the rasteriser on tiny
synthetic models (no reference file is read)."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

try:
    from tools.refview import refview
except ImportError:  # refview draws with Pillow, which procgen treats as optional (tools/procgen/README.md)
    refview = None

needs_pillow = unittest.skipIf(refview is None, "tools/refview needs Pillow")


def _box(lo: tuple[float, float, float], hi: tuple[float, float, float]) -> np.ndarray:
    """Twelve triangles of an axis-aligned box."""
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    v = np.array(
        [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0], [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]],
        dtype=float,
    )
    faces = [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4), (2, 3, 7), (2, 7, 6), (1, 2, 6), (1, 6, 5), (0, 4, 7), (0, 7, 3)]
    return np.array([[v[a], v[b], v[c]] for a, b, c in faces])


@needs_pillow
class StlReaderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.tris = _box((0.0, 0.0, 0.0), (1.0, 2.0, 4.0))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_binary_and_ascii_give_the_same_triangles(self) -> None:
        refview.write_binary_stl(self.dir / "b.stl", self.tris)
        refview.write_ascii_stl(self.dir / "a.stl", self.tris)
        binary, kind_b = refview.read_stl(self.dir / "b.stl")
        ascii_, kind_a = refview.read_stl(self.dir / "a.stl")
        self.assertEqual((kind_b, kind_a), ("binary", "ascii"))
        np.testing.assert_allclose(binary, self.tris, atol=1e-6)
        np.testing.assert_allclose(ascii_, self.tris, atol=1e-6)

    def test_a_binary_file_whose_header_says_solid_is_read_as_binary(self) -> None:
        refview.write_binary_stl(self.dir / "s.stl", self.tris, header=b"solid exported by some tool")
        tris, kind = refview.read_stl(self.dir / "s.stl")
        self.assertEqual(kind, "binary")
        self.assertEqual(len(tris), 12)


@needs_pillow
class FrameTests(unittest.TestCase):
    def test_mapping_must_be_a_rotation(self) -> None:
        m = refview.frame_matrix("-x", "+z", "+y")
        self.assertAlmostEqual(float(np.linalg.det(m)), 1.0)
        with self.assertRaises(ValueError):
            refview.frame_matrix("+x", "+z", "+y")  # a mirror
        with self.assertRaises(ValueError):
            refview.frame_matrix("+x", "+x", "+y")  # two axes the same
        with self.assertRaises(ValueError):
            refview.axis_vector("+w")

    def test_scaled_to_the_length_along_aft_with_the_nose_at_zero(self) -> None:
        tris = _box((10.0, 20.0, 30.0), (12.0, 28.0, 31.0))  # long along file y
        ship, scale = refview.to_ship_frame(tris, refview.frame_matrix("-x", "+z", "+y"), 100.0)
        pts = ship.reshape(-1, 3)
        self.assertAlmostEqual(scale, 12.5)
        np.testing.assert_allclose(pts.min(axis=0), [-12.5, -6.25, 0.0], atol=1e-9)
        np.testing.assert_allclose(pts.max(axis=0), [12.5, 6.25, 100.0], atol=1e-9)

    def test_no_length_keeps_file_units(self) -> None:
        tris = _box((0.0, 0.0, 0.0), (1.0, 2.0, 4.0))
        ship, scale = refview.to_ship_frame(tris, np.eye(3), None)
        self.assertEqual(scale, 1.0)
        self.assertAlmostEqual(float(np.ptp(ship[..., 2])), 4.0)


@needs_pillow
class GeometryTests(unittest.TestCase):
    def test_a_cut_through_a_box_is_its_rectangle(self) -> None:
        tris = _box((-1.0, -2.0, 0.0), (1.0, 2.0, 10.0))
        segs = refview.section_segments(tris, 2, 5.0)
        pts = segs.reshape(-1, 3)
        self.assertEqual(len(segs), 8)  # two triangles per side wall
        np.testing.assert_allclose(pts[:, 2], 5.0, atol=1e-6)
        self.assertEqual(refview.extent(pts, 0), [-1.0, 1.0])
        self.assertEqual(refview.extent(pts, 1), [-2.0, 2.0])
        self.assertEqual(len(refview.section_segments(tris, 2, 11.0)), 0)

    def test_separate_boxes_are_separate_shells_largest_first(self) -> None:
        tris = np.concatenate([_box((0, 0, 0), (1, 1, 1)), _box((5, 0, 0), (8, 3, 3))])
        rows, rank = refview.shell_table(tris, refview.shells(tris))
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["size"], [3.0, 3.0, 3.0])
        self.assertEqual(rows[0]["area_m2"], 54.0)
        self.assertTrue(np.all(rank[:12] == 1) and np.all(rank[12:] == 0))
        self.assertAlmostEqual(refview.surface_area(tris), 60.0)

    def test_rasteriser_fills_a_square_and_keeps_the_nearest(self) -> None:
        def quad(x0: float, x1: float, depth: float) -> np.ndarray:
            a, b, c, d = [x0, x0, depth], [x1, x0, depth], [x1, x1, depth], [x0, x1, depth]
            return np.array([[a, b, c], [a, c, d]], dtype=float)

        screen = np.concatenate([quad(2.0, 8.0, 5.0), quad(4.0, 6.0, 1.0)])  # a near square in front of a far one
        depth, index = refview.rasterize(screen, 10, 10)
        self.assertEqual(int((index >= 0).sum()), 36)
        self.assertTrue(np.all(depth[4:6, 4:6] == 1.0))
        self.assertTrue(np.all(index[4:6, 4:6] >= 2))
        self.assertTrue(np.all(depth[2, 2:8] == 5.0))


if __name__ == "__main__":
    unittest.main()
