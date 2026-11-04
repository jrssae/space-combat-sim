"""Every other hull as a textured mesh (M4-T30d): window rows, scaled wear, chunk meshes on the parent's atlas, and the raider, the nav
buoy, the capital hulls, the station's pieces and the Starfury's chunks under the textured contract."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import b5_station, capital_hulls, nav_buoy
from tools.procgen.assets import raider_fighter as raider
from tools.procgen.assets import starfury_aurora as starfury
from tools.procgen.core import geometry as g
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.chunks import ChunkCut, chunk_mesh_name
from tools.procgen.core.context import BuildContext
from tools.procgen.core.glb import read_glb
from tools.procgen.core.image import read_png
from tools.procgen.core.textured_mesh import TexturedPart, atlas_of, write_textured_mesh
from tools.procgen.core.textures import Marking, bake_maps
from tools.procgen.styles import Style
from tools.procgen.styles.earthforce import EARTHFORCE

GREY = EARTHFORCE.material("hull")
WINDOW = (1.0, 0.85, 0.6)


def _uv_rows(primitive) -> set[tuple[float, float]]:
    return {(round(float(u), 5), round(float(v), 5)) for u, v in primitive.uv}


def _sample(image: np.ndarray, uv: np.ndarray) -> np.ndarray:
    """The texel under each UV (0..1, v down as the writer lays the atlas out)."""
    size = image.shape[0]
    cols = np.clip((uv[:, 0] * size).astype(int), 0, size - 1)
    rows = np.clip((uv[:, 1] * size).astype(int), 0, size - 1)
    return image[rows, cols]


def _glowing_vertices(out: Path, section: dict) -> np.ndarray:
    """The hull vertices whose texel in the emissive map glows."""
    hull = read_glb(out / section["file"]).primitives[0]
    emissive = read_png(out / section["surfaces"][0]["emissive"])
    lit = _sample(emissive, hull.uv)[:, :3].max(axis=1) > 40
    return hull.positions[lit]


class WindowMarkingTests(unittest.TestCase):
    def test_window_rows_glow_on_the_side_they_face_only(self) -> None:
        box = g.box((10.0, 4.0, 20.0), GREY)
        marks = (Marking.windows("box", (5.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0), (18.0, 2.0), (1.0, 1.0),
                                 (0.5, 0.4), WINDOW, 2.0, lit=0.7),)
        atlas = atlas_of([TexturedPart(box, (0, 0, 0), marks, "box")], atlas_px=256, texel_m=0.06)
        maps = bake_maps(atlas, EARTHFORCE, seed=3, occlusion=False)
        b = atlas.buffers
        glow = maps["emissive"].max(axis=2) > 30
        self.assertTrue(glow.any(), "the windows glow")
        self.assertTrue(np.all(b.normal[glow][:, 0] > 0.9), "only the +X side has windows")
        self.assertTrue(np.all(np.abs(b.position[glow][:, 1]) <= 1.05), "inside the 2 m tall band")
        side = b.filled & (b.normal[..., 0] > 0.9) & (np.abs(b.position[..., 1]) < 0.15)
        self.assertLess(glow[side].mean(), 0.5, "rows of windows, not a lit strip: frames between them and some dark")

    def test_window_rings_glow_round_an_axis(self) -> None:
        drum = g.lathe([(-10.0, 0.0), (-10.0, 6.0), (10.0, 6.0), (10.0, 0.0)], 48, GREY, creases=(1, 2))
        marks = (Marking.window_rings("drum", (0.0, 0.0, 0.0), (0.0, 0.0, 1.0), 0.0, 3.0, (1.5, 1.0), (0.6, 0.5), WINDOW, 2.0),)
        atlas = atlas_of([TexturedPart(drum, (0, 0, 0), marks, "drum")], atlas_px=256, texel_m=0.08)
        maps = bake_maps(atlas, EARTHFORCE, seed=3, occlusion=False)
        b = atlas.buffers
        glow = maps["emissive"].max(axis=2) > 30
        self.assertTrue(glow.any())
        p = b.position[glow]
        self.assertTrue(np.all(np.abs(p[:, 2]) <= 1.6), "inside the 3 m band round the middle")
        angles = np.arctan2(p[:, 1], p[:, 0])
        self.assertGreater(np.ptp(angles), 5.0, "all the way round")

    def test_the_surface_strength_covers_the_windows(self) -> None:
        box = g.box((10.0, 4.0, 20.0), GREY)
        marks = (Marking.windows("box", (5.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0), (18.0, 2.0), (1.0, 1.0),
                                 (0.5, 0.4), WINDOW, 2.5),)
        with tempfile.TemporaryDirectory() as tmp:
            _, section = write_textured_mesh(Path(tmp), "thing", [TexturedPart(box, (0, 0, 0), marks, "box")], EARTHFORCE,
                                             atlas_px=256, texel_m=0.06, occlusion=False)
        self.assertAlmostEqual(section["surfaces"][0]["emissive_strength"], 2.5)


class ScaleTests(unittest.TestCase):
    def test_normal_scale_one_bakes_the_normal_map_at_the_atlas_size(self) -> None:
        box = g.box((3.0, 3.0, 3.0), GREY)
        with tempfile.TemporaryDirectory() as tmp:
            _, section = write_textured_mesh(Path(tmp), "thing", [TexturedPart(box, (0, 0, 0), name="box")], EARTHFORCE,
                                             atlas_px=128, texel_m=0.05, occlusion=False, normal_scale=1)
        self.assertEqual(section["map_px"]["normal"], 128)
        self.assertEqual(section["map_px"]["albedo"], 128)

    def test_a_big_hull_with_wear_scaled_has_no_texel_speckle(self) -> None:
        # The weathering's noise is sized for a fighter texelled at a centimetre; on a hull texelled at half a metre it turns to
        # texel-to-texel speckle unless ``wear_scale`` scales it with the hull.
        def speckle(scale: float) -> float:
            big = Style("big", dict(EARTHFORCE.materials), panel_size_m=12.0, panel_line_width_m=0.8, streaks=0.38, grime=0.1,
                        extra={"wear_scale": scale, "bare_metal": 0.0, "speckle": 0.07, "smudge": 0.38})
            box = g.box((60.0, 60.0, 60.0), EARTHFORCE.material("hull"))
            atlas = atlas_of([TexturedPart(box, (0, 0, 0), name="box")], atlas_px=512, texel_m=0.5, style=big)
            grey = bake_maps(atlas, big, seed=1, occlusion=False, normal_scale=1)["albedo"][..., :3].astype(float).mean(axis=2)
            both = atlas.buffers.filled[:, 1:] & atlas.buffers.filled[:, :-1]
            return float(np.abs(grey[:, 1:] - grey[:, :-1])[both].mean())

        self.assertLess(speckle(40.0), 0.5 * speckle(1.0))


class ChunkMeshTests(unittest.TestCase):
    def test_a_chunk_is_the_parents_faces_on_the_parents_uvs(self) -> None:
        a = g.box((2.0, 1.0, 1.0), GREY, center=(-2.0, 0.0, 0.0))
        b = g.box((1.0, 1.0, 3.0), GREY, center=(2.0, 0.0, 0.0))
        offset = (-2.0, 0.1, 0.0)
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            paths, section = write_textured_mesh(out, "thing", [TexturedPart(a, (0, 0, 0), name="a"), TexturedPart(b, (1, 2, 3), name="b")],
                                                 EARTHFORCE, atlas_px=128, texel_m=0.05, occlusion=False,
                                                 chunks=[ChunkCut("left", ("a",), offset)])
            name = chunk_mesh_name("thing", "left")
            self.assertEqual(name, "thing_chunk_left.glb")
            self.assertIn(out / name, paths)
            parent = read_glb(out / section["file"]).primitives[0]
            chunk = read_glb(out / name)
            self.assertEqual(len(chunk.primitives), 1, "no glass in it")
            hull = chunk.primitives[0]
            self.assertEqual(hull.material, parent.material, "the parent's surface, so it takes the parent's maps")
            self.assertEqual(len(hull.indices) // 3, a.face_count)
            self.assertTrue(_uv_rows(hull) <= _uv_rows(parent), "a chunk's UVs are a subset of its parent's")
            np.testing.assert_allclose(hull.positions.min(axis=0) + offset, [-3.0, -0.5, -0.5], atol=1e-5)
            self.assertEqual(sorted(p.name for p in out.iterdir() if p.name.startswith("thing_chunk")), [name], "no maps of its own")


class RaiderTexturedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.out = Path(cls._tmp.name) / "raider"
        cls.outputs = raider.build(BuildContext(cls.out, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.out)
        cls.section = cls.manifest["mesh"]
        cls.hp = json.loads((cls.out / raider.HARDPOINTS_NAME).read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_the_mesh_section_and_its_maps(self) -> None:
        manifest_io.validate_mesh_section(self.section)
        self.assertEqual(self.manifest["files"]["mesh"], "raider_fighter.glb")
        self.assertNotIn("livery", self.section, "raiders take no wing livery")
        self.assertEqual([s["name"] for s in self.section["surfaces"]], ["hull"], "the canopy is opaque: no glass surface")
        for key in ("albedo", "normal", "orm", "emissive"):
            self.assertTrue((self.out / self.section["surfaces"][0][key]).is_file(), key)
            self.assertTrue((self.out / (self.section["surfaces"][0][key] + ".import")).is_file(), key)
        names = {p.name for p in self.outputs.files}
        self.assertIn("raider_fighter.glb", names)

    def test_two_engine_glows_at_the_rear(self) -> None:
        glowing = _glowing_vertices(self.out, self.section)
        self.assertGreater(len(glowing), 0)
        self.assertTrue((glowing[:, 0] > 0.3).any() and (glowing[:, 0] < -0.3).any(), "one in each nacelle")
        rear = max(p["main"]["position"][2] for p in self.hp["pods"])
        self.assertTrue(np.all(glowing[:, 2] > rear - 1.0), "only the nozzles glow")

    def test_worn_grey_brown(self) -> None:
        r, g_, b = self.section["mean_albedo"]
        self.assertGreaterEqual(r, b, "warm, not blue")

    def test_every_chunk_has_a_mesh_on_the_parents_atlas(self) -> None:
        parent = read_glb(self.out / self.section["file"]).primitives[0]
        uvs = _uv_rows(parent)
        names = []
        for entry in self.hp["chunks"]:
            self.assertEqual(entry["mesh"], chunk_mesh_name("raider_fighter", entry["name"]))
            chunk = read_glb(self.out / entry["mesh"]).primitives[0]
            self.assertTrue(_uv_rows(chunk) <= uvs, entry["name"])
            centred = chunk.positions.astype(float) + np.array(entry["offset"])
            lo, hi = parent.positions.min(axis=0), parent.positions.max(axis=0)
            self.assertTrue(np.all(centred >= lo - 1e-3) and np.all(centred <= hi + 1e-3), "back in place it is inside the hull's box")
            names.append(entry["name"])
        self.assertEqual(names, list(raider.CHUNK_ORDER))
        total = sum(len(read_glb(self.out / e["mesh"]).primitives[0].indices) // 3 for e in self.hp["chunks"])
        self.assertEqual(total, self.section["triangles"], "the chunks share out the hull's triangles")

    def test_a_coarse_render_mesh_on_request(self) -> None:
        coarse_dir = Path(self._tmp.name) / "coarse"
        raider.build(BuildContext(coarse_dir, seed=42, options={"render_triangles": 2500, "occlusion": False}))
        section = manifest_io.read_manifest(coarse_dir)["mesh"]
        self.assertLess(section["triangles"], self.section["triangles"])
        self.assertEqual(section["render_triangles"], 2500)
        self.assertEqual(section["fine_triangles"], self.section["triangles"])


class NavBuoyTexturedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.out = Path(cls._tmp.name) / "buoy"
        nav_buoy.build(BuildContext(cls.out, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.out)
        cls.section = cls.manifest["mesh"]
        cls.hp = json.loads((cls.out / nav_buoy.HARDPOINTS_NAME).read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_the_mesh_section_and_its_maps(self) -> None:
        manifest_io.validate_mesh_section(self.section)
        self.assertEqual(self.manifest["files"]["mesh"], "nav_buoy.glb")

    def test_only_the_beacons_lens_glows(self) -> None:
        glowing = _glowing_vertices(self.out, self.section)
        self.assertGreater(len(glowing), 0)
        beacon = np.array(self.hp["beacon"]["position"])
        self.assertTrue(np.all(np.linalg.norm(glowing - beacon, axis=1) < 0.3), "the lens under the beacon, nothing else")

    def test_the_hazard_stripes_are_painted(self) -> None:
        albedo = read_png(self.out / self.section["surfaces"][0]["albedo"]).astype(float)
        orange = (albedo[..., 0] > 90) & (albedo[..., 0] > 1.8 * albedo[..., 2])
        self.assertGreater(orange.mean(), 0.01)


class PieceTexturedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.station_dir, cls.capital_dir = root / "station", root / "capitals"
        b5_station.build(BuildContext(cls.station_dir, seed=42))
        capital_hulls.build(BuildContext(cls.capital_dir, seed=42))
        cls.station = manifest_io.read_manifest(cls.station_dir)
        cls.capitals = manifest_io.read_manifest(cls.capital_dir)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_each_station_piece_has_a_textured_mesh(self) -> None:
        for name in ("drum", "frame"):
            section = self.station["pieces"][name]["mesh"]
            manifest_io.validate_mesh_section(section)
            self.assertEqual(section["file"], f"b5_station_{name}.glb")
            for key in ("albedo", "normal", "orm", "emissive"):
                self.assertTrue((self.station_dir / section["surfaces"][0][key]).is_file())

    def test_the_station_keeps_its_8_km_and_its_drum_axis(self) -> None:
        drum, frame = self.station["pieces"]["drum"], self.station["pieces"]["frame"]
        pivot = np.array(drum["pivot"])
        lo = np.minimum(np.array(frame["mesh"]["aabb_min"]), np.array(drum["mesh"]["aabb_min"]) + pivot)
        hi = np.maximum(np.array(frame["mesh"]["aabb_max"]), np.array(drum["mesh"]["aabb_max"]) + pivot)
        self.assertAlmostEqual(float(hi[2] - lo[2]), 8000.0, delta=80.0)
        d_lo, d_hi = np.array(drum["mesh"]["aabb_min"]), np.array(drum["mesh"]["aabb_max"])
        np.testing.assert_allclose((d_lo + d_hi)[:2] * 0.5, [0.0, 0.0], atol=1.0, err_msg="the drum is centred on its axis")
        self.assertAlmostEqual(float(d_hi[0] - d_lo[0]), 8000.0 / 9.0, delta=5.0)

    def test_the_command_sphere_has_lit_windows(self) -> None:
        glowing = _glowing_vertices(self.station_dir, self.station["pieces"]["frame"]["mesh"])
        self.assertGreater(len(glowing), 0)
        near_command = np.abs(glowing[:, 2] - b5_station.COMMAND_Z) < 700.0
        self.assertGreater(near_command.mean(), 0.5, "most of the frame's lights are the command section's windows")

    def test_each_capital_class_is_a_textured_box_with_window_rows(self) -> None:
        for cls, (w, h, length) in capital_hulls.CLASSES.items():
            section = self.capitals["classes"][cls]["mesh"]
            manifest_io.validate_mesh_section(section)
            size = np.array(section["aabb_max"]) - np.array(section["aabb_min"])
            np.testing.assert_allclose(size, [w, h, length], atol=1e-3)
            glowing = _glowing_vertices(self.capital_dir, section)
            hull = read_glb(self.capital_dir / section["file"]).primitives[0]
            self.assertEqual(len(hull.indices) // 3, 12, "still a 12-triangle box")
            emissive = read_png(self.capital_dir / section["surfaces"][0]["emissive"])
            self.assertGreater(int(emissive.max()), 60, f"{cls}: the window rows glow")
            del glowing


class StarfuryChunkMeshTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.out = Path(cls._tmp.name) / "starfury"
        starfury.build(BuildContext(cls.out, seed=42, options={"hero": False, "occlusion": False}))
        cls.manifest = manifest_io.read_manifest(cls.out)
        cls.hp = json.loads((cls.out / starfury.HARDPOINTS_NAME).read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_every_chunk_has_a_mesh_on_the_parents_atlas_where_its_obj_is(self) -> None:
        parent = read_glb(self.out / self.manifest["mesh"]["file"])
        uvs = set().union(*(_uv_rows(p) for p in parent.primitives))
        materials = {p.material for p in parent.primitives}
        for entry in self.hp["chunks"]:
            chunk = read_glb(self.out / entry["mesh"])
            for primitive in chunk.primitives:
                self.assertIn(primitive.material, materials)
                self.assertTrue(_uv_rows(primitive) <= uvs, entry["name"])
            from tools.procgen.core.obj import read_obj
            obj = read_obj(self.out / entry["obj"])
            positions = np.concatenate([p.positions for p in chunk.primitives]).astype(float)
            np.testing.assert_allclose(positions.min(axis=0), obj.vertices.min(axis=0), atol=2e-3, err_msg=entry["name"])
            np.testing.assert_allclose(positions.max(axis=0), obj.vertices.max(axis=0), atol=2e-3, err_msg=entry["name"])


if __name__ == "__main__":
    unittest.main()
