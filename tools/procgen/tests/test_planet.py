"""``epsilon_iii`` (the ``planet`` generator, M6-T11), standard tier: one full-size build checked against the output contract, the
seam, the poles, the palette, the relief and the wisps; small builds for determinism and the size options."""

from __future__ import annotations

import hashlib
import math
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS, planet
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.image import read_png

SPEC = planet.EPSILON_III
SMALL = {"map_size": [256, 128], "cloud_size": [128, 64]}


def _digests(out_dir: Path) -> dict[str, str]:
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out_dir.iterdir())}


def _hue_deg(rgb: np.ndarray) -> np.ndarray:
    r, g, b = (rgb[..., k] for k in range(3))
    return np.degrees(np.arctan2(math.sqrt(3.0) * (g - b), 2.0 * r - g - b)) % 360.0


class EpsilonIIIBuildTests(unittest.TestCase):
    """Builds the full-size asset once for the whole class."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.out_dir = Path(cls._tmp.name) / "epsilon_iii"
        cls.outputs = ASSETS["epsilon_iii"](BuildContext(cls.out_dir, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.out_dir)
        cls.maps = {key: read_png(cls.out_dir / f"epsilon_iii_{key}.png") for key in planet.MAP_KEYS}

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    # --- the contract ----------------------------------------------------------------------------
    def test_the_files_sizes_and_formats(self) -> None:
        names = sorted(p.name for p in self.out_dir.iterdir())
        expected = sorted([f"epsilon_iii_{k}.png" for k in planet.MAP_KEYS] + [f"epsilon_iii_{k}.png.import" for k in planet.MAP_KEYS]
                          + ["manifest.json"])
        self.assertEqual(names, expected)
        self.assertEqual(sorted(str(p.name) for p in self.outputs.files), expected)
        w, h = SPEC.map_size
        cw, ch = SPEC.cloud_size
        self.assertEqual((w, h), (4096, 2048))
        self.assertEqual(self.maps["albedo"].shape, (h, w, 3))
        self.assertEqual(self.maps["normal"].shape, (h, w, 3))
        self.assertEqual(self.maps["height"].shape, (h, w))
        self.assertEqual(self.maps["clouds"].shape, (ch, cw))
        sidecar = (self.out_dir / "epsilon_iii_normal.png.import").read_text()
        self.assertIn("compress/normal_map=1", sidecar)
        self.assertIn("mipmaps/generate=true", (self.out_dir / "epsilon_iii_albedo.png.import").read_text())

    def test_the_manifest(self) -> None:
        m = self.manifest
        self.assertEqual((m["asset_id"], m["seed"], m["frame"], m["units"]), ("epsilon_iii", 42, "godot", "m"))
        self.assertEqual(m["generator_version"], planet.GENERATOR_VERSION)
        self.assertEqual(m["files"], {k: f"epsilon_iii_{k}.png" for k in planet.MAP_KEYS})
        r = SPEC.radius_m
        self.assertEqual((m["aabb_min"], m["aabb_max"], m["centroid_offset"]), ([-r, -r, -r], [r, r, r], [0.0, 0.0, 0.0]))
        p = m["planet"]
        self.assertEqual(p["radius_m"], 4_780_000.0)
        self.assertEqual(p["projection"], "equirectangular")
        self.assertEqual(p["maps"]["albedo"]["size"], [4096, 2048])
        self.assertEqual(p["maps"]["clouds"]["size"], [2048, 1024])
        self.assertEqual(p["maps"]["height"]["range_m"], [-0.5 * SPEC.height_range_m, 0.5 * SPEC.height_range_m])
        self.assertEqual(p["normal_exaggeration"], SPEC.normal_exaggeration)
        self.assertEqual((p["atmosphere"]["ocean"], p["atmosphere"]["night_lights"]), (False, False))
        self.assertNotIn("mesh", m)
        self.assertEqual(self.outputs.summary, "planet maps 4096x2048")
        self.assertEqual(self.outputs.manifest, m)

    # --- the sphere ------------------------------------------------------------------------------
    def test_the_longitude_seam_is_like_any_other_neighbouring_columns(self) -> None:
        for key, image in self.maps.items():
            f = image.astype(np.float64)
            seam = float(np.abs(f[:, 0] - f[:, -1]).mean())
            neighbours = float(np.abs(np.diff(f, axis=1)).mean())
            self.assertLessEqual(seam, 1.5 * neighbours + 0.5, key)

    def test_the_poles_are_points_not_pinwheels(self) -> None:
        for key in ("albedo", "height"):
            f = self.maps[key].astype(np.float64)
            equator = float(f[f.shape[0] // 2].std(axis=0).mean())
            for row in (0, -1):
                self.assertLess(float(f[row].std(axis=0).mean()), 0.1 * equator + 1.0, (key, row))
        clouds = self.maps["clouds"]
        self.assertEqual(int(clouds[:2].max()), 0)
        self.assertEqual(int(clouds[-2:].max()), 0)
        # The pole row's normals, turned into the planet's frame, all lean the same way.
        n = planet.decode_normals(self.maps["normal"])
        h, w = self.maps["height"].shape
        for row in (0, -1):
            d = planet.sphere_directions(w, h)[row].astype(np.float64)
            east, north = planet.tangent_frame(d)
            world = n[row, :, :1] * east + n[row, :, 1:2] * north + n[row, :, 2:3] * d
            mean = world.mean(axis=0) / np.linalg.norm(world.mean(axis=0))
            self.assertGreater(float((world @ mean).min()), 0.8, row)

    # --- the look --------------------------------------------------------------------------------
    def test_the_palette_is_warm_and_has_no_water(self) -> None:
        rgb = self.maps["albedo"].reshape(-1, 3)[::7].astype(np.float64)
        r, g, b = rgb.T
        self.assertEqual(int((b > r).sum()), 0)  # no blue water anywhere
        self.assertEqual(int((b > g).sum()), 0)
        sat = (rgb.max(axis=1) - rgb.min(axis=1)) / np.maximum(rgb.max(axis=1), 1.0)
        hue = _hue_deg(rgb[sat > 0.08])
        self.assertTrue(np.all(hue < 45.0), float(hue.max()))
        self.assertGreater(float(np.percentile(sat, 50)), 0.3)  # rust and tan, not grey
        luma = rgb @ [0.2126, 0.7152, 0.0722]
        self.assertLess(float(np.percentile(luma, 3)), 90.0)  # dark brown lowlands
        self.assertGreater(float(np.percentile(luma, 99.5)), 175.0)  # beige-cream highlands
        mean = self.manifest["planet"]["mean_albedo"]
        self.assertTrue(all(0.1 < v < 0.45 for v in mean), mean)

    def test_the_north_has_more_pale_ground(self) -> None:
        luma = self.maps["albedo"].astype(np.float64) @ [0.2126, 0.7152, 0.0722]
        lat = np.degrees(planet.latitudes(luma.shape[0]))
        north = luma[(lat > 30) & (lat < 70)]
        south = luma[(lat < -30) & (lat > -70)]
        self.assertGreater(float((north > 185).mean()), 1.5 * float((south > 185).mean()))

    def test_the_relief_is_strong(self) -> None:
        n = planet.decode_normals(self.maps["normal"])
        tilt = np.degrees(np.arccos(np.clip(n[..., 2], -1.0, 1.0)))
        self.assertGreater(float(tilt.mean()), 10.0)
        self.assertGreater(float(np.percentile(tilt, 99)), 30.0)
        self.assertGreater(float(np.ptp(self.maps["height"])), 200)

    def test_the_normals_are_the_heights(self) -> None:
        lo, hi = self.manifest["planet"]["maps"]["height"]["range_m"]
        height_m = lo + self.maps["height"].astype(np.float64) / 255.0 * (hi - lo)
        again = planet.normals_from_height(height_m, SPEC.radius_m, self.manifest["planet"]["normal_exaggeration"])
        stored = planet.decode_normals(self.maps["normal"])
        # Away from the poles, where an 8-bit height step over a few metres of longitude is a cliff.
        band = np.abs(np.degrees(planet.latitudes(height_m.shape[0]))) < 60.0
        agree = (again[band] * stored[band]).sum(axis=-1)
        self.assertGreater(float(agree.mean()), 0.995)
        self.assertGreater(float(np.percentile(agree, 1)), 0.98)

    def test_the_wisps_are_thin_sparse_and_over_the_bright_ground(self) -> None:
        clouds = self.maps["clouds"].astype(np.float64) / 255.0
        self.assertLess(float(clouds.mean()), 0.03)
        self.assertLessEqual(float(clouds.max()), SPEC.cloud_peak + 1.0 / 255.0)
        self.assertGreater(float((clouds > 0.05).mean()), 0.005)
        height = self.maps["height"][::2, ::2].astype(np.float64)
        self.assertGreater(float(height[clouds > 0.1].mean()), float(height.mean()) + 20.0)


class SmallBuildTests(unittest.TestCase):
    def test_the_same_seed_gives_the_same_bytes_and_another_seed_does_not(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            dirs = [Path(tmp) / name for name in ("a", "b", "c")]
            for out, seed in zip(dirs, (42, 42, 7)):
                planet.build_planet("epsilon_iii", BuildContext(out, seed=seed, options=SMALL))
            a, b, c = (_digests(d) for d in dirs)
            self.assertEqual(a, b)
            self.assertNotEqual(a["epsilon_iii_albedo.png"], c["epsilon_iii_albedo.png"])
            self.assertEqual(read_png(dirs[0] / "epsilon_iii_albedo.png").shape, (128, 256, 3))
            self.assertEqual(manifest_io.read_manifest(dirs[0])["planet"]["maps"]["clouds"]["size"], [128, 64])

    def test_a_map_must_be_twice_as_wide_as_tall(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, self.assertRaises(ValueError):
            planet.build_planet("epsilon_iii", BuildContext(Path(tmp), options={"map_size": [256, 256]}))


if __name__ == "__main__":
    unittest.main()
