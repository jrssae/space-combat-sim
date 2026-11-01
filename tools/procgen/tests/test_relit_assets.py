"""AC30 on the real generators: every ship and buoy level and every chunk carries lighting records, and hull colours carry no
baked shading."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import nav_buoy as buoy
from tools.procgen.assets import raider_fighter as raider
from tools.procgen.assets import sky_default as sky
from tools.procgen.assets import starfury_aurora as ship
from tools.procgen.core import lighting
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import box
from tools.procgen.core.ply import read_ply
from tools.procgen.core.sampling import SurfaceSamples
from tools.procgen.parts import Part
from tools.procgen.styles.earthforce import EARTHFORCE
from tools.procgen.styles.raider import RAIDER

MAX_ROUND_TRIP_DEG = 1.5


def angle_deg(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return np.degrees(np.arccos(np.clip(np.einsum("ij,ij->i", a, b), -1.0, 1.0)))


def opposite_normals(paint) -> SurfaceSamples:
    """Two samples of one paint at one point, facing opposite ways."""
    return SurfaceSamples(
        np.array([[0.31, 0.47, 0.73], [0.31, 0.47, 0.73]]),
        np.array([[0.0, 1.0, 0.0], [0.0, -1.0, 0.0]]),
        np.zeros(2),
        np.zeros(2),
        (paint,),
    )


class RelitAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dirs = {}
        for module in (ship, raider, buoy):
            cls.dirs[module.ASSET_ID] = root / module.ASSET_ID
            module.build(BuildContext(cls.dirs[module.ASSET_ID], seed=42))

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def pairs(self, asset_id: str) -> list[tuple[str, str]]:
        """Every (ply, light) file pair an asset lists: each level from its manifest, each chunk from its hardpoints."""
        directory = self.dirs[asset_id]
        manifest = manifest_io.read_manifest(directory)
        out = [(lod["file"], lod["lighting"]) for lod in manifest["lods"]]
        hardpoints = json.loads((directory / manifest["files"]["hardpoints"]).read_text(encoding="utf-8"))
        out += [(chunk["ply"], chunk["lighting"]) for chunk in hardpoints.get("chunks", [])]
        return out

    def test_every_level_and_chunk_lists_its_records(self) -> None:
        expected = {ship.ASSET_ID: 4 + 5, raider.ASSET_ID: 4 + 5, buoy.ASSET_ID: 1}
        for asset_id, count in expected.items():
            pairs = self.pairs(asset_id)
            self.assertEqual(len(pairs), count, asset_id)
            for _ply, light in pairs:
                self.assertTrue(light.endswith(lighting.SUFFIX), light)
            levels = manifest_io.read_manifest(self.dirs[asset_id])["lods"]
            self.assertEqual(
                [lod["lighting"] for lod in levels],
                [lighting.lod_file_name(asset_id, lod["level"]) for lod in levels],
            )

    def test_records_match_their_ply_one_for_one(self) -> None:
        for asset_id in self.dirs:
            for ply_name, light_name in self.pairs(asset_id):
                splats = read_ply(self.dirs[asset_id] / ply_name).to_splats()
                records = lighting.read_lighting(self.dirs[asset_id] / light_name)
                self.assertEqual(len(records), len(splats), light_name)
                # The PLY stores the surface normal in the frame the shader expects, so a slip in order or frame shows here.
                error = angle_deg(lighting.decode_normals(records), splats.normals)
                self.assertLess(float(error.max()), MAX_ROUND_TRIP_DEG, light_name)

    def test_the_normal_is_the_thin_axis_of_its_splat(self) -> None:
        for asset_id in self.dirs:
            for ply_name, light_name in self.pairs(asset_id):
                splats = read_ply(self.dirs[asset_id] / ply_name).to_splats()
                normals = lighting.decode_normals(lighting.read_lighting(self.dirs[asset_id] / light_name))
                w, x, y, z = splats.rot.T
                local_z = np.column_stack([2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y)])
                self.assertLess(float(angle_deg(normals, local_z).max()), MAX_ROUND_TRIP_DEG, light_name)

    def test_surface_records_have_full_confidence_and_ao(self) -> None:
        for asset_id in self.dirs:
            for _ply, light_name in self.pairs(asset_id):
                records = lighting.read_lighting(self.dirs[asset_id] / light_name)
                self.assertTrue(np.all(records[:, 3] == 255), f"{light_name}: confidence 255 on the surface")
                self.assertTrue(np.all(records[:, 2] == 255), f"{light_name}: AO 1.0")

    def test_a_small_build_is_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            first = buoy.build(BuildContext(Path(tmp) / "a", seed=42))
            second = buoy.build(BuildContext(Path(tmp) / "b", seed=42))
            name = first.manifest["lods"][0]["lighting"]
            self.assertEqual((first.out_dir / name).read_bytes(), (second.out_dir / name).read_bytes())

    def test_the_sky_has_no_records(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = sky.build(BuildContext(Path(tmp) / "sky", seed=42, options={"stars": 200, "nebula": 50}))
            self.assertFalse([p for p in out.files if p.suffix == lighting.SUFFIX], "stars are emitters: never lit")
            self.assertNotIn("lighting", out.manifest["lods"][0])

    # --- flat colours --------------------------------------------------------------------------------------------

    def test_opposite_normals_of_one_paint_have_one_colour(self) -> None:
        mesh = box((1.0, 1.0, 1.0), EARTHFORCE.material("hull"))
        for role in ("hull", "hull_dark", "stripe", "hazard", "barrel", "nozzle"):
            samples = opposite_normals(EARTHFORCE.material(role))
            rgb = ship.colour_samples(ship.Placed(Part("fuselage", mesh), samples), EARTHFORCE)
            np.testing.assert_array_equal(rgb[0], rgb[1], role)
            rgb = buoy.colour_samples(Part("hull", mesh), samples, EARTHFORCE)
            np.testing.assert_array_equal(rgb[0], rgb[1], role)
        mesh = box((1.0, 1.0, 1.0), RAIDER.material("hull"))
        for role in ("hull", "hull_dark", "stripe", "barrel", "nozzle"):
            samples = opposite_normals(RAIDER.material(role))
            rgb = raider.colour_samples(raider.Placed(Part("hump", mesh), samples), RAIDER)
            np.testing.assert_array_equal(rgb[0], rgb[1], role)

    def test_a_plain_paint_is_one_colour_all_over_the_ship(self) -> None:
        ctx = BuildContext(Path("unused"), seed=42)
        placed = ship.build_parts(ship.DEFAULT_SPEC, EARTHFORCE, ctx, 0.15, 0.15)
        for p in placed:
            if p.samples is None:
                continue
            plain = p.samples.material_flag("paneled") < 0.5
            rgb = ship.colour_samples(p, EARTHFORCE)[plain]
            for index in np.unique(p.samples.material[plain]):
                paint = rgb[p.samples.material[plain] == index]
                self.assertEqual(len(np.unique(paint, axis=0)), 1, p.part.name)

    def test_paint_brightness_does_not_follow_the_normal(self) -> None:
        # A baked sun makes the top of a hull brighter than its belly; panel lines and tint jitter do not care which way it faces.
        for module, style, build in (
            (ship, EARTHFORCE, lambda ctx: ship.build_parts(ship.DEFAULT_SPEC, EARTHFORCE, ctx, 0.06, 0.06)),
            (raider, RAIDER, lambda ctx: raider.build_parts(raider.DEFAULT_SPEC, RAIDER, ctx, 0.09)),
        ):
            normals, lum = [], []
            for p in build(BuildContext(Path("unused"), seed=42)):
                if p.samples is None:
                    continue
                paint = p.samples.material == next(
                    (i for i, m in enumerate(p.samples.materials) if m.name == style.material("hull").name), -1
                )
                normals.append(p.samples.normals[paint])
                lum.append(module.colour_samples(p, style)[paint].mean(axis=1))
            normals, lum = np.concatenate(normals), np.concatenate(lum)
            self.assertGreater(len(lum), 1000, module.ASSET_ID)
            for axis in range(3):
                correlation = float(np.corrcoef(normals[:, axis], lum)[0, 1])
                self.assertLess(abs(correlation), 0.05, (module.ASSET_ID, axis))


class GeneratorVersionTests(unittest.TestCase):
    def test_colours_and_records_changed_the_generators(self) -> None:
        self.assertGreaterEqual(ship.GENERATOR_VERSION, 5)
        self.assertGreaterEqual(raider.GENERATOR_VERSION, 2)
        self.assertGreaterEqual(buoy.GENERATOR_VERSION, 2)


if __name__ == "__main__":
    unittest.main()
