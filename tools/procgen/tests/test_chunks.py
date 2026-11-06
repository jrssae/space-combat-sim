"""``core/chunks``: one OBJ per group, re-centred on the group's surface samples' centroid, which places it on the ship."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.core.chunks import ChunkSource, chunk_file_name, chunk_mesh_name, chunk_offsets, write_chunks
from tools.procgen.core.geometry import Material, box
from tools.procgen.core.obj import read_obj

MAT = Material("m", (0.5, 0.5, 0.5))


def make_points(centre: np.ndarray, n: int = 40, seed: int = 1) -> np.ndarray:
    return centre + np.random.default_rng(seed).normal(0.0, 0.3, (n, 3))


class ChunkTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)
        self.sources = [
            ChunkSource("left", make_points(np.array([-3.0, 0.2, 1.0]), seed=1), box((1, 1, 1), MAT, center=(-3.0, 0.2, 1.0))),
            ChunkSource("right", make_points(np.array([3.0, 0.2, 1.5]), 55, seed=2), box((1, 1, 1), MAT, center=(3.0, 0.2, 1.5))),
        ]
        self.files, self.entries = write_chunks(self.dir, "thing", self.sources, ("test",))

    def test_files_and_entries(self) -> None:
        self.assertEqual([e["name"] for e in self.entries], ["left", "right"])
        for entry in self.entries:
            self.assertEqual(set(entry), {"name", "obj", "offset"})
            self.assertEqual(entry["obj"], chunk_file_name("thing", entry["name"]))
            self.assertTrue((self.dir / entry["obj"]).exists())
        self.assertTrue(all(f.exists() for f in self.files))

    def test_offset_is_the_samples_centroid_in_the_body_frame(self) -> None:
        offsets = chunk_offsets(self.sources)
        for entry, source in zip(self.entries, self.sources, strict=True):
            np.testing.assert_allclose(entry["offset"], source.points.mean(axis=0), atol=1e-5)
            np.testing.assert_allclose(entry["offset"], offsets[source.name], atol=1e-5)

    def test_chunk_obj_is_recentred_on_the_same_centroid(self) -> None:
        for entry in self.entries:
            obj = read_obj(self.dir / entry["obj"])
            lo, hi = obj.vertices.min(axis=0), obj.vertices.max(axis=0)
            # The 1 m box sat at the samples' neighbourhood; after centring it is near the origin.
            self.assertLess(float(np.linalg.norm(0.5 * (lo + hi))), 1.0)
            self.assertAlmostEqual(float(hi[0] - lo[0]), 1.0, places=5)

    def test_with_meshes_names_each_chunks_textured_mesh(self) -> None:
        _, entries = write_chunks(self.dir, "thing", self.sources, ("test",), with_meshes=True)
        self.assertEqual([e["mesh"] for e in entries], [chunk_mesh_name("thing", "left"), chunk_mesh_name("thing", "right")])

    def test_an_empty_chunk_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            write_chunks(self.dir, "thing", [ChunkSource("none", np.zeros((0, 3)), box((1, 1, 1), MAT))])


if __name__ == "__main__":
    unittest.main()
