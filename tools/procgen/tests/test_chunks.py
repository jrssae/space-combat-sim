"""``core/chunks``: one PLY and OBJ per group, re-centred on the group's centroid, in the hull's frame convention."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.core import frames
from tools.procgen.core.chunks import ChunkSource, chunk_file_names, write_chunks
from tools.procgen.core.geometry import Material, box
from tools.procgen.core.obj import read_obj
from tools.procgen.core.ply import SplatData, read_ply

MAT = Material("m", (0.5, 0.5, 0.5))


def make_splats(centre: np.ndarray, n: int = 40, seed: int = 1) -> SplatData:
    rng = np.random.default_rng(seed)
    xyz = centre + rng.normal(0.0, 0.3, (n, 3))
    q = frames.quat_normalize(rng.normal(size=(n, 4)))
    return SplatData(xyz, rng.uniform(0.1, 0.9, (n, 3)), rng.uniform(0.2, 0.9, n), rng.uniform(0.01, 0.1, (n, 3)), q, rng.normal(size=(n, 3)))


class ChunkTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)
        self.sources = [
            ChunkSource("left", make_splats(np.array([-3.0, 0.2, 1.0]), seed=1), box((1, 1, 1), MAT, center=(-3.0, 0.2, 1.0))),
            ChunkSource("right", make_splats(np.array([3.0, 0.2, 1.5]), 55, seed=2), box((1, 1, 1), MAT, center=(3.0, 0.2, 1.5))),
        ]
        self.files, self.entries = write_chunks(self.dir, "thing", self.sources, ("test",))

    def test_files_and_entries(self) -> None:
        self.assertEqual([e["name"] for e in self.entries], ["left", "right"])
        for entry in self.entries:
            ply, obj = chunk_file_names("thing", entry["name"])
            self.assertEqual((entry["ply"], entry["obj"]), (ply, obj))
            self.assertTrue((self.dir / ply).exists())
            self.assertTrue((self.dir / obj).exists())
        self.assertEqual([e["splats"] for e in self.entries], [40, 55])
        self.assertTrue(all(f.exists() for f in self.files))

    def test_offset_is_the_centroid_in_the_body_frame(self) -> None:
        for entry, source in zip(self.entries, self.sources, strict=True):
            np.testing.assert_allclose(entry["offset"], source.splats.xyz.mean(axis=0), atol=1e-5)

    def test_chunk_ply_is_recentred_and_flipped_like_the_hull(self) -> None:
        for entry, source in zip(self.entries, self.sources, strict=True):
            written = read_ply(self.dir / entry["ply"]).to_splats()
            np.testing.assert_allclose(written.xyz.mean(axis=0), [0.0, 0.0, 0.0], atol=1e-5)
            body = frames.flip_xy(written.xyz) + np.array(entry["offset"])
            np.testing.assert_allclose(body, source.splats.xyz, atol=1e-5)
            np.testing.assert_allclose(written.rgb, source.splats.rgb, atol=1e-4)

    def test_chunk_obj_is_recentred_on_the_same_centroid(self) -> None:
        for entry in self.entries:
            obj = read_obj(self.dir / entry["obj"])
            lo, hi = obj.vertices.min(axis=0), obj.vertices.max(axis=0)
            # The 1 m box sat at the splat cloud's neighbourhood; after centring it is near the origin.
            self.assertLess(float(np.linalg.norm(0.5 * (lo + hi))), 1.0)
            self.assertAlmostEqual(float(hi[0] - lo[0]), 1.0, places=5)

    def test_an_empty_chunk_is_an_error(self) -> None:
        empty = SplatData(np.zeros((0, 3)), np.zeros((0, 3)), np.zeros(0), np.zeros((0, 3)), np.zeros((0, 4)), np.zeros((0, 3)))
        with self.assertRaises(ValueError):
            write_chunks(self.dir, "thing", [ChunkSource("none", empty, box((1, 1, 1), MAT))])


if __name__ == "__main__":
    unittest.main()
