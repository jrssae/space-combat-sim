"""``core/textured_mesh.py`` (M4-T30a): the textured ``.glb`` contract, its four maps, the manifest section and the Starfury's own."""

from __future__ import annotations

import json
import tempfile
import time
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import starfury_aurora as starfury
from tools.procgen.core import geometry as g
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.glb import read_glb
from tools.procgen.core.image import read_png
from tools.procgen.core.obj import read_obj
from tools.procgen.core.textured_mesh import TexturedPart, write_textured_mesh
from tools.procgen.core.uv_atlas import uv_area
from tools.procgen.styles.earthforce import EARTHFORCE

GREY = EARTHFORCE.material("hull")
GLASS = EARTHFORCE.material("canopy_glass")


class WriterTests(unittest.TestCase):
    def test_the_contract_files_and_section(self) -> None:
        hull = g.box((2.0, 1.0, 3.0), GREY)
        pane = g.box((0.5, 0.3, 0.05), GLASS, center=(0.0, 0.6, -1.0))
        parts = [TexturedPart(hull, (0, 0, 0), name="hull"), TexturedPart(pane, (1, 1, 1), name="pane")]
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            paths, section = write_textured_mesh(out, "thing", parts, EARTHFORCE, atlas_px=256, texel_m=0.02, seed=3, occlusion=False)
            names = sorted(p.name for p in paths)
            self.assertEqual(names, sorted(["thing.glb", "thing_albedo.png", "thing_albedo.png.import", "thing_normal.png",
                                            "thing_normal.png.import", "thing_orm.png", "thing_orm.png.import", "thing_emissive.png",
                                            "thing_emissive.png.import"]))
            mesh = read_glb(out / "thing.glb")
            self.assertEqual([p.material for p in mesh.primitives], ["hull", "glass"])
            self.assertFalse(mesh.primitives[0].blend)
            self.assertTrue(mesh.primitives[1].blend)
            for p in mesh.primitives:
                self.assertTrue(np.all(p.uv >= 0.0) and np.all(p.uv <= 1.0))
                self.assertEqual(p.indices.dtype, np.uint32)
                tri_uv = p.uv[p.indices.reshape(-1, 3)]
                self.assertTrue(np.all(np.abs(uv_area(tri_uv)) > 1e-12))
            self.assertEqual(sum(len(p.indices) for p in mesh.primitives) // 3, hull.face_count + pane.face_count)
            for key in ("albedo", "normal", "orm", "emissive"):
                image = read_png(out / f"thing_{key}.png")
                self.assertEqual(image.shape, (256, 256, 3), key)
                sidecar = (out / f"thing_{key}.png.import").read_text()
                self.assertIn('importer="texture"', sidecar)
                self.assertIn("compress/mode=2", sidecar)
                self.assertIn("mipmaps/generate=true", sidecar)
            self.assertIn("compress/normal_map=1", (out / "thing_normal.png.import").read_text())
            self.assertIn("compress/normal_map=2", (out / "thing_albedo.png.import").read_text())
            self.assertIn("compress/channel_pack=1", (out / "thing_orm.png.import").read_text())
            self.assertIn("compress/channel_pack=0", (out / "thing_albedo.png.import").read_text())
            self.assertEqual(section["file"], "thing.glb")
            self.assertEqual(section["triangles"], hull.face_count + pane.face_count)
            self.assertEqual(section["atlas_px"], 256)
            self.assertGreaterEqual(section["texel_m"], 0.02)
            self.assertEqual(len(section["mean_albedo"]), 3)
            self.assertEqual([s["name"] for s in section["surfaces"]], ["hull", "glass"])
            self.assertEqual(section["surfaces"][1]["blend"], True)
            self.assertAlmostEqual(section["surfaces"][1]["transmittance"], GLASS.transmittance)
            self.assertEqual(section["surfaces"][0]["albedo"], "thing_albedo.png")
            self.assertEqual(section["lods"], [])
            np.testing.assert_allclose(section["aabb_min"], [-1.0, -0.5, -1.5], atol=1e-4)
            np.testing.assert_allclose(section["aabb_max"], [1.0, 0.75, 1.5], atol=1e-4)
            # The section validates inside a manifest, and a broken one does not.
            manifest = manifest_io.build_manifest("thing", 1, 3, [manifest_io.lod_entry(0, "x.ply", 1, 0.1)], [0, 0, 0], [1, 1, 1],
                                                  [0, 0, 0], extra={"mesh": section})
            manifest_io.validate_manifest(manifest)
            broken = dict(manifest, mesh=dict(section, surfaces=[]))
            with self.assertRaises(ValueError):
                manifest_io.validate_manifest(broken)
            broken = dict(manifest, mesh=dict(section, texel_m=0.0))
            with self.assertRaises(ValueError):
                manifest_io.validate_manifest(broken)

    def test_one_seed_gives_identical_bytes(self) -> None:
        hull = g.lathe([(0.0, 0.0), (0.5, 0.4), (1.5, 0.4), (2.0, 0.0)], 16, GREY)
        parts = [TexturedPart(hull, (2, 3, 4), name="pod")]
        with tempfile.TemporaryDirectory() as tmp:
            out_a, out_b = Path(tmp) / "a", Path(tmp) / "b"
            out_a.mkdir()
            out_b.mkdir()
            paths_a, _ = write_textured_mesh(out_a, "pod", parts, EARTHFORCE, atlas_px=128, texel_m=0.02, seed=5, occlusion=True)
            paths_b, _ = write_textured_mesh(out_b, "pod", parts, EARTHFORCE, atlas_px=128, texel_m=0.02, seed=5, occlusion=True)
            for a, b in zip(sorted(paths_a), sorted(paths_b), strict=True):
                self.assertEqual(a.read_bytes(), b.read_bytes(), a.name)


class StarfuryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.out = Path(cls._tmp.name)
        started = time.perf_counter()
        starfury.build(BuildContext(cls.out, seed=42, options={"hero": False}))
        cls.seconds = time.perf_counter() - started
        cls.manifest = manifest_io.read_manifest(cls.out)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_the_textured_mesh_is_the_painted_meshs_triangles_and_box(self) -> None:
        section = self.manifest["mesh"]
        paint = self.manifest["paint_mesh"]
        self.assertEqual(self.manifest["files"]["mesh"], "starfury_aurora.glb")
        self.assertEqual(section["triangles"], paint["triangles"])
        self.assertEqual(section["triangles"], len(read_obj(self.out / starfury.OBJ_NAME).faces))
        np.testing.assert_allclose(section["aabb_min"], paint["aabb_min"], atol=1e-4)
        np.testing.assert_allclose(section["aabb_max"], paint["aabb_max"], atol=1e-4)
        mesh = read_glb(self.out / section["file"])
        self.assertEqual([p.material for p in mesh.primitives], ["hull", "glass"])
        self.assertEqual(sum(len(p.indices) for p in mesh.primitives) // 3, section["triangles"])
        for p in mesh.primitives:
            self.assertTrue(np.all(p.uv >= 0.0) and np.all(p.uv <= 1.0))

    def test_the_maps_are_the_atlas_size_and_the_section_knows_them(self) -> None:
        section = self.manifest["mesh"]
        self.assertEqual(section["atlas_px"], starfury.ATLAS_PX)
        for surface in section["surfaces"]:
            for key in ("albedo", "normal", "orm", "emissive"):
                image = read_png(self.out / surface[key])
                self.assertEqual(image.shape, (section["atlas_px"], section["atlas_px"], 3))
        self.assertLess(section["texel_m"], 0.02, "about a centimetre a texel")
        emissive = read_png(self.out / section["surfaces"][0]["emissive"])
        self.assertGreater(int((emissive.max(axis=2) > 128).sum()), 500, "the nozzle throats glow")
        print(f"\n[textured_mesh] starfury_aurora built in {self.seconds:.1f} s, texel {section['texel_m'] * 100:.2f} cm, "
              f"fill {section['atlas_fill']:.2f}")

    def test_the_import_sidecars_sit_beside_the_maps(self) -> None:
        for name in ("albedo", "normal", "orm", "emissive"):
            self.assertTrue((self.out / f"starfury_aurora_{name}.png.import").is_file(), name)
        with (self.out / "hardpoints.json").open() as f:
            json.load(f)


if __name__ == "__main__":
    unittest.main()
