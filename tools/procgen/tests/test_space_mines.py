"""``space_mines``: the three kinds' meshes, their sizes, the manifest's ``mines`` sections and determinism."""

from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS, space_mines
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class SpaceMinesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.out_a = space_mines.build(BuildContext(root / "a", seed=42))
        cls.out_b = space_mines.build(BuildContext(root / "b", seed=42))
        cls.manifest = manifest_io.read_manifest(root / "a")
        cls.dir = root / "a"

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_it_is_registered_and_writes_one_mesh_a_kind(self) -> None:
        self.assertIn("space_mines", ASSETS)
        for kind in space_mines.KINDS:
            section = self.manifest["mines"][kind]
            self.assertTrue((self.dir / section["file"]).is_file(), f"{kind}'s glb")
            self.assertEqual(section["file"], f"space_mines_{kind}.glb")
            self.assertTrue(section["surfaces"], "its surfaces are listed for the importer")

    def test_each_kind_is_a_small_object_the_size_of_its_blast_row_asks(self) -> None:
        sizes = {}
        for kind, builder in space_mines.BUILDERS.items():
            from tools.procgen.core.geometry import Mesh

            lo, hi = Mesh.concatenate([p.mesh for p in builder()]).bounds()
            sizes[kind] = float(np.max(hi - lo))
        self.assertTrue(2.0 < sizes["mine_prox"] < 4.0, sizes)
        self.assertTrue(4.0 < sizes["mine_energy"] < 7.0, sizes)
        self.assertTrue(3.0 < sizes["mine_guided"] < 5.0, sizes)

    def test_the_same_seed_gives_the_same_files(self) -> None:
        names_a = sorted(p.name for p in self.out_a.files)
        names_b = sorted(p.name for p in self.out_b.files)
        self.assertEqual(names_a, names_b)
        for a in sorted(self.out_a.files, key=lambda p: p.name):
            b = next(p for p in self.out_b.files if p.name == a.name)
            self.assertEqual(sha256(a), sha256(b), a.name)


if __name__ == "__main__":
    unittest.main()
