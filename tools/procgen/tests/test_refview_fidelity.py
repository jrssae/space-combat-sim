"""tools/refview/fidelity (M10-T66): slice sweeps, depth maps and bow alignment on synthetic boxes, so no STL is needed."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

try:
    import PIL  # noqa: F401
except ImportError:  # the tool draws with Pillow, which procgen treats as optional (tools/procgen/README.md)
    fd = None
else:
    from tools.refview import fidelity as fd  # a broken tool must fail here, not skip

needs_pillow = unittest.skipIf(fd is None, "tools/refview needs Pillow")


def box(lo: tuple[float, float, float], hi: tuple[float, float, float]) -> np.ndarray:
    """A closed box as outward-wound triangles (n, 3, 3)."""
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    v = np.array([[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0], [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]], float)
    tris = []
    for a, b, c, d in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (3, 7, 6, 2), (0, 4, 7, 3), (1, 2, 6, 5)):
        tris += [[v[a], v[b], v[c]], [v[a], v[c], v[d]]]
    return np.array(tris)


@needs_pillow
class SweepTests(unittest.TestCase):
    def test_identical_meshes_score_one_everywhere(self) -> None:
        m = box((-5, -5, 0), (5, 5, 40))
        scores = fd.sweep(m, m, 2, (2.0, 38.0), 4.0, 0.5)
        self.assertEqual(len(scores), 10)
        self.assertTrue(all(s.iou == 1.0 for s in scores))

    def test_a_narrower_build_scores_its_area_ratio_and_rows_report_it(self) -> None:
        ref, mod = box((-6, -6, 0), (6, 6, 20)), box((-3, -6, 0), (3, 6, 20))
        scores = fd.sweep(ref, mod, 2, (5.0, 15.0), 5.0, 0.5)
        self.assertAlmostEqual(scores[0].iou, 0.5, places=2)
        row = fd.sweep_rows(scores, 0.5)[0]
        self.assertAlmostEqual(row["missing_m2"], 72.0, delta=2.0)
        self.assertEqual(row["extra_m2"], 0.0)

    def test_face_depth_scores_where_the_face_stands_not_what_lies_behind(self) -> None:
        """M10-T67: a thin plate at the face scores as a solid block behind it; a face set back scores its depth's share."""
        block, plate = box((-5, -5, 10), (5, 5, 40)), box((-5, -5, 10), (5, 5, 12))
        window = (0.0, 40.0, -6.0, 6.0)
        for axis in (0, 1):
            win = window if axis == 0 else (-6.0, 6.0, 0.0, 40.0)
            self.assertLess(fd.sweep(block, plate, axis, (0.0, 0.0), 1.0, 0.5, win)[0].iou, 0.2, "row fill sees the plate as thin")
            self.assertAlmostEqual(fd.sweep(block, plate, axis, (0.0, 0.0), 1.0, 0.5, win, face=True)[0].iou, 1.0, places=6)
        back = box((-5, -5, 25), (5, 5, 40))
        self.assertAlmostEqual(fd.sweep(block, back, 0, (0.0, 0.0), 1.0, 0.5, window, face=True)[0].iou, 0.5, places=2)

    def test_the_step_sets_the_plane_count(self) -> None:
        self.assertEqual(fd.plane_values((0.0, 100.0), 5.0)[-1], 100.0)
        self.assertEqual(len(fd.plane_values((0.0, 100.0), 1.0)), 101)

    def test_csv_and_strip_are_written(self) -> None:
        m = box((-5, -5, 0), (5, 5, 20))
        scores = fd.sweep(m, m, 2, (2.0, 18.0), 4.0, 0.5)
        with tempfile.TemporaryDirectory() as d:
            fd.write_csv(Path(d) / "s.csv", fd.sweep_rows(scores, 0.5))
            self.assertIn("position_m,iou", (Path(d) / "s.csv").read_text())
            try:
                fd.write_strip(Path(d) / "s.png", scores, ("a", "b"))
            except ImportError:
                self.skipTest("no Pillow")
            self.assertTrue((Path(d) / "s.png").is_file())


@needs_pillow
class DepthTests(unittest.TestCase):
    BOX = (-10.0, 10.0, -10.0, 10.0, 0.0, 50.0)

    def test_a_recessed_face_is_missing_and_a_proud_one_is_extra(self) -> None:
        ref = box((-10, -10, 10), (10, 10, 30))
        deep = box((-10, -10, 20), (10, 10, 30))  # build's face 10 m further aft: the reference stands nearer
        near = box((-10, -10, 4), (10, 10, 30))
        for model, field in ((deep, "missing_m2"), (near, "extra_m2")):
            diff = fd.depth_diff(fd.depth_map(ref, "front", self.BOX, 0.5), fd.depth_map(model, "front", self.BOX, 0.5), 2.0, 0.5)
            self.assertAlmostEqual(diff.summary[field], 400.0, delta=8.0)
            self.assertAlmostEqual(diff.summary["mean_abs_depth_diff_m"], 6.0 if model is near else 10.0, delta=0.5)

    def test_matching_faces_are_within_tolerance(self) -> None:
        ref = box((-10, -10, 10), (10, 10, 30))
        d = fd.depth_map(ref, "front", self.BOX, 1.0)
        self.assertEqual(fd.depth_diff(d, d, 1.0, 1.0).summary["within_tolerance"], 1.0)

    def test_views_see_their_own_face(self) -> None:
        m = box((-10, -10, 10), (10, 10, 30))
        side = fd.depth_map(m, "side", self.BOX, 1.0)
        self.assertAlmostEqual(float(side[side.shape[0] // 2, 20]), -10.0, delta=0.1)  # from starboard, the +x face is nearest
        top = fd.depth_map(m, "top", self.BOX, 1.0)
        self.assertAlmostEqual(float(top[top.shape[0] // 2, 10]), -10.0, delta=0.1)


@needs_pillow
class AlignmentTests(unittest.TestCase):
    def test_bow_tip_and_alignment_meet_in_z(self) -> None:
        a, b = box((-5, -5, 3), (5, 5, 30)), box((-5, -5, 0), (5, 5, 30))
        moved = fd.align_bow(a, b, 1.0, 0.0)
        self.assertAlmostEqual(float(moved.reshape(-1, 3)[:, 2].min()), 3.0)
        scaled = fd.align_bow(a, b, 2.0, 0.0)
        self.assertAlmostEqual(float(scaled.reshape(-1, 3)[:, 0].max()), 10.0)

    def test_scale_search_finds_the_scale_and_shift(self) -> None:
        base = np.concatenate([box((-1, -1, 0), (1, 1, 100)), box((-20, -10, 20), (20, 10, 100))])
        other = np.concatenate([box((-1, -1, 0), (1, 1, 100)), box((-10, -5, 10), (10, 5, 100))])
        scale, shift, iou, _ = fd.best_scale(base, other, 30.0, 90.0, 1.0, np.array([1.0, 1.5, 2.0]), np.array([0.0]))
        self.assertEqual((scale, shift), (2.0, 0.0))
        self.assertGreater(iou, 0.9)

    def test_turn_span_turns_only_the_span(self) -> None:
        m = np.concatenate([box((10, -1, 0), (12, 1, 10)), box((10, -1, 50), (12, 1, 60))])
        out = fd.turn_span(m, 40.0, 70.0, 90.0)
        np.testing.assert_allclose(out[:12], m[:12])
        self.assertAlmostEqual(float(out[12:, :, 1].max()), 12.0, places=6)


if __name__ == "__main__":
    unittest.main()
