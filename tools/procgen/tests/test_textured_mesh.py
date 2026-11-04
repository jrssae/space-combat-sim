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
                px = 512 if key == "normal" else 256  # M4-T30b: the normal map at twice the atlas
                self.assertEqual(image.shape, (px, px, 3), key)
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
                channels = 4 if key == "albedo" else 3  # the albedo's alpha is where a livery may paint (M4-T30b)
                px = 2 * section["atlas_px"] if key == "normal" else section["atlas_px"]  # Q34: the fine detail at 4 096
                self.assertEqual(image.shape, (px, px, channels), key)
                self.assertEqual(section["map_px"][key], px, key)
        self.assertLess(section["texel_m"], 0.02, "about a centimetre a texel")
        emissive = read_png(self.out / section["surfaces"][0]["emissive"])
        self.assertGreater(int((emissive.max(axis=2) > 128).sum()), 500, "the nozzle throats glow")
        print(f"\n[textured_mesh] starfury_aurora built in {self.seconds:.1f} s, texel {section['texel_m'] * 100:.2f} cm, "
              f"fill {section['atlas_fill']:.2f}")

    def test_the_plain_starfury_is_all_grey(self) -> None:
        # Q41: without a livery the hull is grey, no hazard yellow anywhere; colour comes only from the livery layer.
        section = self.manifest["mesh"]
        albedo = read_png(self.out / section["surfaces"][0]["albedo"])[..., :3].astype(float) / 255.0
        emissive = read_png(self.out / section["surfaces"][0]["emissive"]).max(axis=2)
        hull = emissive == 0  # the throats and the glass glow; everything else is paint, metal or primer
        top, low = albedo.max(axis=2), albedo.min(axis=2)
        saturation = np.where(top > 0.04, (top - low) / np.maximum(top, 1e-6), 0.0)[hull]
        self.assertLess(float(np.percentile(saturation, 99.9)), 0.3, "no saturated texels on the hull")
        yellow = (albedo[..., 0] > 0.45) & (albedo[..., 1] > 0.35) & (albedo[..., 2] < 0.2) & hull
        self.assertEqual(int(yellow.sum()), 0, "no hazard yellow")

    def test_the_import_sidecars_sit_beside_the_maps(self) -> None:
        for name in ("albedo", "normal", "orm", "emissive"):
            self.assertTrue((self.out / f"starfury_aurora_{name}.png.import").is_file(), name)
        with (self.out / "hardpoints.json").open() as f:
            json.load(f)


class LiveryOutputTests(unittest.TestCase):
    """M4-T30b: with paintable materials the glb carries each vertex's zone, the albedo's alpha the paintable texels, and the digit
    atlas and the ``livery`` section are written; the section validates."""

    def test_zones_paint_alpha_digits_and_section(self) -> None:
        hull = g.box((2.0, 1.0, 3.0), GREY)
        dark = g.box((0.4, 0.4, 0.4), EARTHFORCE.material("hull_dark"), center=(0.0, 0.0, 2.0))
        pane = g.box((0.5, 0.3, 0.05), GLASS, center=(0.0, 0.6, -1.0))
        parts = [TexturedPart(hull, (0, 0, 0), name="fuselage", zone=1), TexturedPart(dark, (0, 0, 0), name="block", zone=0),
                 TexturedPart(pane, (1, 1, 1), name="pane", zone=1)]
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            paths, section = write_textured_mesh(out, "thing", parts, EARTHFORCE, atlas_px=256, texel_m=0.02, seed=3, occlusion=False,
                                                 paintable=("ef_hull",))
            names = {p.name for p in paths}
            self.assertIn("thing_digits.png", names)
            self.assertIn("thing_digits.png.import", names)
            self.assertIn("compress/mode=0", (out / "thing_digits.png.import").read_text(), "lossless: a distance field")
            mesh = read_glb(out / "thing.glb")
            hull_prim = mesh.primitives[0]
            self.assertIsNotNone(hull_prim.colors)
            zones = np.rint(hull_prim.colors[:, 0] * 255.0).astype(int)
            near_block = np.linalg.norm(hull_prim.positions - np.array([0.0, 0.0, 2.0]), axis=1) < 0.35
            self.assertTrue(np.all(zones[near_block] == 0))
            self.assertTrue(np.all(zones[~near_block] == 1))
            albedo = read_png(out / "thing_albedo.png")
            self.assertEqual(albedo.shape, (256, 256, 4))
            alpha = albedo[..., 3]
            self.assertGreater(int((alpha > 200).sum()), 1000, "the grey hull may be painted")
            # The dark block's texels may not: its UVs' centre texel has no paint.
            block_faces = np.flatnonzero(near_block[hull_prim.indices.reshape(-1, 3)].all(axis=1))
            uv = hull_prim.uv[hull_prim.indices.reshape(-1, 3)[block_faces]].mean(axis=1)
            px = np.clip((uv * 256).astype(int), 0, 255)
            self.assertTrue(np.all(alpha[px[:, 1], px[:, 0]] < 30))
            self.assertIn("livery", section)
            self.assertEqual(section["livery"]["digits"]["file"], "thing_digits.png")
            self.assertEqual(len(section["livery"]["hull_paint"]), 3)
            manifest = manifest_io.build_manifest("thing", 1, 3, [manifest_io.lod_entry(0, "x.ply", 1, 0.1)], [0, 0, 0], [1, 1, 1],
                                                  [0, 0, 0], extra={"mesh": section})
            manifest_io.validate_manifest(manifest)
            broken = dict(manifest, mesh=dict(section, livery=dict(section["livery"], digits={})))
            with self.assertRaises(ValueError):
                manifest_io.validate_manifest(broken)
            broken = dict(manifest, mesh=dict(section, livery=dict(section["livery"], patterns={"plain": [{"zones": [1]}]})))
            with self.assertRaises(ValueError):
                manifest_io.validate_manifest(broken)


class StarfuryAtlasTests(unittest.TestCase):
    """The T30a review's checks on the real Starfury atlas (Q34): no two charts share a texel, and the texel density is even
    across the parts and inside each part (the unwrapped curved parts stretch less)."""

    @classmethod
    def setUpClass(cls) -> None:
        from tools.procgen.core.raster import rasterize, sharp_edges
        from tools.procgen.core.textured_mesh import pack_parts

        parts = starfury.textured_parts(starfury.DEFAULT_SPEC, BuildContext(Path(tempfile.gettempdir())))
        cls.packed = pack_parts(parts, starfury.ATLAS_PX, starfury.TEXEL_M)
        mesh = cls.packed.mesh
        cls.buffers = rasterize(starfury.ATLAS_PX, cls.packed.face_uv01, mesh.vertices[mesh.faces], mesh.vertex_normals()[mesh.faces],
                                cls.packed.face_part, mesh.face_material, cls.packed.face_chart, sharp_edges(mesh))
        cls.parts = parts

    def test_no_two_charts_overlap(self) -> None:
        self.assertEqual(int(self.buffers.overlaps), 0)

    def test_texel_density_is_even_across_and_inside_the_parts(self) -> None:
        mesh = self.packed.mesh
        uv = self.packed.face_uv01 * starfury.ATLAS_PX
        px_area = np.abs(uv_area(uv))
        m_area = mesh.face_areas()
        big = m_area > 1e-4
        per_face = np.sqrt(px_area[big] / m_area[big])
        part_of = self.packed.face_part[big]
        overall = []
        for k in np.unique(part_of):
            d = per_face[part_of == k]
            overall.append(float(np.sqrt((px_area[big][part_of == k]).sum() / (m_area[big][part_of == k]).sum())))
            p5, p95 = np.percentile(d, [5, 95])
            self.assertLess(p95 / p5, 1.25, f"{self.parts[k].name}: {p5:.1f} to {p95:.1f} texels a metre")
        self.assertLess(max(overall) / min(overall), 1.15, overall)


class CoarseTrackingTests(unittest.TestCase):
    """The review's Minor 6: ``coarse_placed`` follows the target above the floor, and gives the floor below it."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.ctx = BuildContext(Path(tempfile.gettempdir()))
        cls.offset = np.zeros(3)

    def _count(self, target: int) -> int:
        placed = starfury.coarse_placed(starfury.DEFAULT_SPEC, EARTHFORCE, self.ctx, target, self.offset)
        return sum(p.part.mesh.face_count for p in placed if p.hull)

    def test_it_tracks_the_target_above_the_floor(self) -> None:
        low, high = self._count(21000), self._count(28000)
        self.assertLess(abs(low - 21000) / 21000.0, 0.06, low)
        self.assertLess(abs(high - 28000) / 28000.0, 0.06, high)
        self.assertGreater(high - low, 5000, "a higher target gives more triangles")

    def test_below_the_floor_it_gives_the_floor(self) -> None:
        floor = self._count(5000)
        self.assertGreater(floor, 15000)
        self.assertLess(floor, 21000)
        self.assertEqual(self._count(1000), floor)


class RenderTrianglesTests(unittest.TestCase):
    """Q34: ``render_triangles`` builds a coarser render mesh with the fine mesh's normals in its normal map."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.out = Path(cls._tmp.name)
        starfury.build(BuildContext(cls.out, seed=42, options={"hero": False, "occlusion": False, "render_triangles": 20000}))
        cls.manifest = manifest_io.read_manifest(cls.out)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_the_coarse_build_has_about_the_asked_triangles(self) -> None:
        section = self.manifest["mesh"]
        # 20 000: the round parts' segments scale down; the strut plates and fittings floor the Starfury at about 18 000.
        self.assertLess(abs(section["triangles"] - 20000) / 20000.0, 0.15, section["triangles"])
        self.assertEqual(section["render_triangles"], 20000)
        self.assertEqual(section["fine_triangles"], self.manifest["paint_mesh"]["triangles"])
        mesh = read_glb(self.out / section["file"])
        self.assertEqual(sum(len(p.indices) for p in mesh.primitives) // 3, section["triangles"])
        manifest_io.validate_manifest(self.manifest)


if __name__ == "__main__":
    unittest.main()
