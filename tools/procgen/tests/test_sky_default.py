"""``sky_default``: counts, the stars and nebula blobs, frames, manifest, star file, panorama, determinism."""

from __future__ import annotations

import hashlib
import math
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import sky_default
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core import rotations
from tools.procgen.core import panorama as panorama_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.image import read_png

N_STARS = sky_default.DEFAULT_STARS
N_NEBULA = sky_default.DEFAULT_NEBULA
R = sky_default.DEFAULT_RADIUS_M


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def angle_deg(dirs: np.ndarray, axis: np.ndarray) -> np.ndarray:
    return np.degrees(np.arccos(np.clip(dirs @ axis, -1.0, 1.0)))


class SkyDefaultTests(unittest.TestCase):
    """Builds the full-size asset twice (same seed) once for the whole class."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = sky_default.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = sky_default.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        # The blobs the build drew its files from: the same seed's streams.
        cls.stars = sky_default.generate_stars(BuildContext(Path("."), 42).rng("stars"), N_STARS, R)
        cls.nebula = sky_default.generate_nebula(BuildContext(Path("."), 42).rng("nebula"), N_NEBULA, R)
        cls.godot_xyz = np.concatenate([cls.stars.xyz, cls.nebula.xyz])  # the authoring frame

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    # --- manifest ------------------------------------------------------------------------------
    def test_manifest_basics(self) -> None:
        m = self.manifest
        self.assertEqual(m["asset_id"], "sky_default")
        self.assertEqual((m["frame"], m["units"], m["seed"]), ("godot", "m", 42))
        self.assertEqual(m["counts"], {"stars": N_STARS, "nebula": N_NEBULA})
        self.assertEqual(m["sky_radius_m"], R)
        self.assertEqual(self.out_a.manifest, m)
        self.assertNotIn("lods", m)
        self.assertEqual(self.out_a.summary, f"{N_STARS} stars")
        self.assertEqual(sorted(p.name for p in self.dir_a.iterdir()),
                         ["manifest.json", "sky_default_panorama.png", "sky_default_panorama.png.import", "sky_default_stars.f32"])

    def test_the_blobs_are_sane(self) -> None:
        for blobs in (self.stars, self.nebula):
            self.assertTrue(np.all((blobs.alpha > 0) & (blobs.alpha <= 1)))
            self.assertTrue(np.all(blobs.rgb >= -1e-6))
            self.assertTrue(np.all(blobs.scale > 0))
            np.testing.assert_allclose(np.linalg.norm(blobs.rot, axis=1), 1.0, atol=1e-5)

    def test_manifest_box_and_offset_are_the_blobs_about_their_centroid(self) -> None:
        centroid = self.godot_xyz.mean(axis=0)
        np.testing.assert_allclose(self.manifest["centroid_offset"], centroid, atol=1e-3)
        np.testing.assert_allclose(self.manifest["aabb_min"], (self.godot_xyz - centroid).min(axis=0), atol=2e-3)
        np.testing.assert_allclose(self.manifest["aabb_max"], (self.godot_xyz - centroid).max(axis=0), atol=2e-3)

    def test_centroid_offset_restores_the_authored_sky_sphere(self) -> None:
        radii = np.linalg.norm(self.godot_xyz[:N_STARS], axis=1)
        np.testing.assert_allclose(radii, R, atol=0.05)
        nebula_r = np.linalg.norm(self.godot_xyz[N_STARS:], axis=1) / R
        self.assertTrue(
            np.all((nebula_r > 0.75) & (nebula_r < 1.2)),
            (nebula_r.min(), nebula_r.max()),
        )
        # One-sided content: the offset is large, which is why the node needs it (see module docstring).
        self.assertGreater(
            float(np.linalg.norm(self.manifest["centroid_offset"])), 1000.0
        )

    # --- stars ---------------------------------------------------------------------------------
    def test_stars_are_small_isotropic_and_opaque(self) -> None:
        stars = self.stars.scale
        np.testing.assert_allclose(stars[:, 0], stars[:, 1], rtol=1e-5)
        np.testing.assert_allclose(stars[:, 0], stars[:, 2], rtol=1e-5)
        self.assertTrue(
            np.all((stars[:, 0] > 6.0) & (stars[:, 0] <= 12.01))
        )  # 12 m = 0.6 mrad at 20 km
        self.assertGreater(
            float(stars.max()), 11.0
        )  # the brightest star reaches the nominal size
        self.assertTrue(np.all(self.stars.alpha >= 0.999))

    def test_bright_stars_are_rare_big_and_bright(self) -> None:
        luminance = self.stars.rgb.mean(axis=1)
        sigma = self.stars.scale[:, 0]
        self.assertGreater(float(np.corrcoef(luminance, sigma)[0, 1]), 0.8)
        self.assertLess(
            float((luminance > 0.75).mean()), 0.08
        )  # dim stars dominate (dN/dm ~ 10^(0.5 m))
        self.assertGreater(float((luminance < 0.4).mean()), 0.6)
        self.assertGreater(float(luminance.max()), 1.0)

    def test_star_colours_span_red_to_blue(self) -> None:
        rgb = self.stars.rgb
        self.assertGreater(float((rgb[:, 0] > rgb[:, 2] * 1.3).mean()), 0.10)  # reddish
        self.assertGreater(float((rgb[:, 2] > rgb[:, 0] * 1.05).mean()), 0.10)  # bluish

    def test_milky_way_band_has_more_stars_than_uniform(self) -> None:
        dirs = self.godot_xyz[:N_STARS] / R
        latitude = 90.0 - angle_deg(dirs, sky_default.GALACTIC_NORMAL)
        in_band = float((np.abs(latitude) < 10.0).mean())
        uniform = math.sin(
            math.radians(10.0)
        )  # share of the sphere within +-10 degrees of a great circle
        self.assertGreater(in_band, 1.5 * uniform)

    def test_stars_cover_the_whole_sphere(self) -> None:
        dirs = self.godot_xyz[:N_STARS] / R
        for axis in np.vstack([np.eye(3), -np.eye(3)]):
            self.assertGreater(int((dirs @ axis > 0.8).sum()), 50, axis)

    # --- nebula --------------------------------------------------------------------------------
    def test_nebula_opacities_are_within_0_02_and_0_08(self) -> None:
        alpha = self.nebula.alpha
        self.assertGreaterEqual(float(alpha.min()), 0.02)
        self.assertLessEqual(float(alpha.max()), 0.08)
        self.assertGreater(
            float(alpha.max() - alpha.min()), 0.02
        )  # a real spread, not a constant

    def test_nebula_blobs_are_large_soft_and_slightly_anisotropic(self) -> None:
        scale = self.nebula.scale
        self.assertGreaterEqual(float(scale.min()), 299.0)
        self.assertLessEqual(float(scale.max()), 2001.0)
        ratio = scale.max(axis=1) / scale.min(axis=1)
        self.assertGreater(float(ratio.max()), 1.3)  # filaments
        self.assertLessEqual(float(ratio.max()), 1.85)  # but only slightly

    def test_nebula_fills_one_region_about_forty_degrees_across(self) -> None:
        dirs = self.godot_xyz[N_STARS:]
        dirs = dirs / np.linalg.norm(dirs, axis=1, keepdims=True)
        away = angle_deg(dirs, sky_default.NEBULA_CENTER)
        self.assertLess(float(np.percentile(away, 90)), 25.0)
        self.assertLess(float(np.percentile(away, 99)), 38.0)
        self.assertGreater(float(np.percentile(away, 90)), 10.0)  # but not a point

    def test_nebula_uses_a_two_tone_palette_and_stays_dim(self) -> None:
        rgb = self.nebula.rgb
        self.assertLess(float(rgb.max()), 0.7)
        teal_ish = (rgb[:, 1] > rgb[:, 0] * 1.5).mean()
        magenta_ish = (rgb[:, 0] > rgb[:, 1] * 1.5).mean()
        self.assertGreater(float(teal_ish), 0.1)
        self.assertGreater(float(magenta_ish), 0.1)

    def test_nebula_is_in_view_of_a_forward_camera(self) -> None:
        # Centre of the region is 35 degrees right of -Z and 12 up: within a 75 degree FOV start view.
        centre = sky_default.NEBULA_CENTER
        self.assertAlmostEqual(
            float(np.degrees(np.arctan2(centre[0], -centre[2]))), 35.0, places=3
        )
        self.assertAlmostEqual(float(np.degrees(np.arcsin(centre[1]))), 12.0, places=3)

    # --- star file (M4-T30c) ------------------------------------------------------------------
    def _star_records(self, directory: Path) -> np.ndarray:
        raw = np.fromfile(directory / "sky_default_stars.f32", dtype="<f4")
        return raw.reshape(-1, len(self.manifest["star_field"]["record"]))

    def test_star_file_is_listed_with_its_layout(self) -> None:
        field = self.manifest["star_field"]
        self.assertEqual(self.manifest["files"]["stars"], "sky_default_stars.f32")
        self.assertEqual(field["file"], "sky_default_stars.f32")
        self.assertEqual(field["count"], N_STARS)
        self.assertEqual(field["format"], "float32 little-endian")
        self.assertEqual(
            field["record"],
            ["dir_x", "dir_y", "dir_z", "red", "green", "blue", "brightness"],
        )
        self.assertGreater(field["radius_mrad"], 0.0)
        self.assertEqual(field["floor_px"], 1.0)
        self.assertIn(self.dir_a / "sky_default_stars.f32", self.out_a.files)

    def test_star_file_parses_to_one_unit_direction_per_star(self) -> None:
        records = self._star_records(self.dir_a)
        self.assertEqual(records.shape, (self.manifest["counts"]["stars"], 7))
        np.testing.assert_allclose(np.linalg.norm(records[:, :3], axis=1), 1.0, atol=1e-5)
        self.assertTrue(np.all(records[:, 3:6] > 0.0))
        np.testing.assert_allclose(records[:, 3:6].max(axis=1), 1.0, atol=1e-5)  # the colour is a tint
        self.assertTrue(np.all(records[:, 6] > 0.0))

    def test_star_file_holds_the_stars_of_the_m3_sky(self) -> None:
        records = self._star_records(self.dir_a)
        directions = self.godot_xyz[:N_STARS] / R
        np.testing.assert_allclose(records[:, :3], directions, atol=1e-4)
        # Brighter stars give brighter points, in the same order.
        light = self.stars.rgb.max(axis=1)
        order = np.argsort(light)
        self.assertGreater(float(records[order[-1], 6]), 5.0 * float(records[order[0], 6]))

    def test_a_point_shows_the_colour_and_light_its_m3_star_had(self) -> None:
        # The M3 renderer decoded a star's colour from sRGB before compositing, so a star of raw colour c showed decode(c),
        # spread over 2 pi (sigma^2 + 0.3 px^2 of spread) at 1 080 lines and 70 degrees. The point's disc of radius rho
        # delivers pi / 3 rho^2 per unit brightness.
        def decode(c: np.ndarray) -> np.ndarray:
            return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

        self.assertAlmostEqual(float(decode(np.array(0.5))), 0.21404, places=4)
        records = self._star_records(self.dir_a)
        rho = self.manifest["star_field"]["radius_mrad"] * 1e-3
        focal = 540.0 / math.tan(math.radians(35.0))
        raw = self.stars.rgb.astype(float)
        shown = decode(raw)
        sigma = self.stars.scale[:, 0] / R
        expected_light = shown.max(axis=1) * 2.0 * math.pi * (sigma**2 + 0.3 / focal**2)
        np.testing.assert_allclose(records[:, 6] * math.pi / 3.0 * rho**2, expected_light, rtol=1e-3)
        np.testing.assert_allclose(records[:, 3:6], shown / shown.max(axis=1, keepdims=True), atol=1e-4)

    def test_blue_and_orange_stars_keep_their_tints(self) -> None:
        records = self._star_records(self.dir_a)
        tint = records[:, 3:6]
        bright = records[:, 6] > np.percentile(records[:, 6], 80)
        bluest = int(np.argmin(np.where(bright, tint[:, 0], 9.0)))
        reddest = int(np.argmin(np.where(bright, tint[:, 2], 9.0)))
        self.assertEqual(float(tint[bluest, 2]), 1.0)
        self.assertLess(float(tint[bluest, 0]), 0.55)  # a hot star: blue, little red
        self.assertEqual(float(tint[reddest, 0]), 1.0)
        self.assertLess(float(tint[reddest, 2]), 0.35)  # a cool star: orange, little blue
        # And the sky as a whole is coloured, not white: half the stars at least 30 % from grey.
        saturation = (tint.max(axis=1) - tint.min(axis=1)) / tint.max(axis=1)
        self.assertGreater(float(np.median(saturation)), 0.3)

    # --- panorama ------------------------------------------------------------------------------
    def test_panorama_is_a_4096_by_2048_png_listed_in_the_manifest(self) -> None:
        path = self.dir_a / "sky_default_panorama.png"
        self.assertEqual(self.manifest["files"]["panorama"], "sky_default_panorama.png")
        self.assertIn(path, self.out_a.files)
        self.assertIn(Path(str(path) + ".import"), self.out_a.files)
        pixels = read_png(path).astype(float)[..., :3] / 255.0
        self.assertEqual(read_png(path).shape, (2048, 4096, 4))
        self.assertGreater(float(pixels.mean()), 0.003)  # not black
        self.assertLess(float(pixels.mean()), 0.2)  # but a night sky

        def patch(lon_deg: float, lat_deg: float) -> float:
            x = int((lon_deg / 360.0 + 0.5) * 4096)
            y = int((0.5 - lat_deg / 180.0) * 2048)
            return float(pixels[y - 100 : y + 100, x - 100 : x + 100].mean())

        # Godot's panorama convention: centre = +Z, so the nebula (35 degrees right of -Z, 12 up) sits at lon -145, lat +12.
        self.assertGreater(patch(-145.0, 12.0), 3.0 * patch(35.0, -12.0))

    def test_panorama_brightest_region_lies_toward_the_nebulas_centroid(self) -> None:
        # The centre of the panorama's light (each texel weighted by its brightness and its solid angle) against the blobs'
        # centroid, which the nebula dominates; the gas spreads over about 40 degrees.
        light = read_png(self.dir_a / "sky_default_panorama.png")[..., :3].astype(float).max(axis=2)
        grid = panorama_io.direction_grid(4096, 2048).astype(float)
        weight = light * np.sqrt(np.maximum(1.0 - grid[..., 1] ** 2, 0.0))
        centre = (grid * weight[..., None]).sum(axis=(0, 1))
        centre /= np.linalg.norm(centre)
        centroid = np.array(self.manifest["centroid_offset"], dtype=float)
        centroid /= np.linalg.norm(centroid)
        self.assertLess(float(angle_deg(centre[None, :], centroid)[0]), 10.0)

    def test_panorama_holds_the_gas_and_leaves_the_stars_to_the_point_field(self) -> None:
        pixels = read_png(self.dir_a / "sky_default_panorama.png")[..., :3]
        # No star pixels: the gas is smooth, so no texel stands far above its four neighbours (the dither is one level).
        lum = pixels.astype(float).max(axis=2)
        spikes = lum[1:-1, 1:-1] - np.maximum.reduce(
            [lum[:-2, 1:-1], lum[2:, 1:-1], lum[1:-1, :-2], lum[1:-1, 2:]]
        )
        self.assertLess(float(spikes.max()), 12.0)
        # Coloured: teal and magenta, never grey starlight.
        bright = pixels[lum > np.percentile(lum, 99.5)].astype(float)
        self.assertGreater(float(np.mean(bright.max(axis=1) - bright.min(axis=1))), 10.0)

    def test_panorama_alpha_is_the_nebulas_opacity_over_the_stars(self) -> None:
        image = read_png(self.dir_a / "sky_default_panorama.png").astype(float)
        light = image[..., :3].max(axis=2)
        alpha = image[..., 3] / 255.0
        # Opaque where the gas is brightest (up to the generator's limit), clear where there is no gas.
        dense = light >= np.percentile(light, 99.9)
        self.assertGreater(float(alpha[dense].mean()), 0.7)
        self.assertLessEqual(float(alpha.max()), sky_default.NEBULA_STAR_OPACITY + 1.5 / 255.0)
        self.assertLess(float(alpha[light <= 1.0].max()), 0.02)
        # Denser-looking gas hides more: the opacity rises with the gas's brightness.
        order = np.argsort(light.ravel())
        quartiles = [float(alpha.ravel()[part].mean()) for part in np.array_split(order[-200000:], 4)]
        self.assertEqual(quartiles, sorted(quartiles))
        self.assertEqual(self.manifest["star_field"]["occlusion"], "panorama alpha")

    # --- determinism ---------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        self.assertEqual(
            sorted(p.name for p in self.dir_a.iterdir()),
            sorted(p.name for p in self.dir_b.iterdir()),
        )
        for path in self.dir_a.iterdir():
            self.assertEqual(sha256(path), sha256(self.dir_b / path.name), path.name)

    def test_a_different_seed_changes_the_sky(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            opts = {"panorama": False}
            other = sky_default.build(BuildContext(Path(tmp), seed=43, options=opts))
            self.assertEqual(other.manifest["seed"], 43)
            self.assertNotEqual(
                sha256(Path(tmp) / "sky_default_stars.f32"),
                sha256(self.dir_a / "sky_default_stars.f32"),
            )
            self.assertEqual(other.manifest["counts"], self.manifest["counts"])  # same counts either way


class SkyDefaultOptionTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name) / "sky"
        self.small = {"stars": 300, "nebula": 120}

    def build(self, **extra):
        return sky_default.build(
            BuildContext(self.dir, seed=5, options={**self.small, **extra})
        )

    def test_counts_are_options(self) -> None:
        out = self.build(panorama=False)
        self.assertEqual(out.manifest["counts"], {"stars": 300, "nebula": 120})

    def test_invalid_counts_are_rejected(self) -> None:
        for bad in ({"stars": 0}, {"nebula": 0}, {"radius_m": 0}):
            with self.subTest(bad), self.assertRaises(ValueError):
                self.build(**bad)

    def test_panorama_can_be_switched_off(self) -> None:
        self.dir.mkdir()
        stale = self.dir / "sky_default_panorama.png"
        stale.write_bytes(b"stale")
        out = self.build(panorama=False)
        self.assertEqual(out.manifest["files"], {"stars": "sky_default_stars.f32"})
        self.assertEqual(out.warnings, ())
        self.assertFalse(stale.exists())  # the directory never holds a panorama the manifest omits
        self.assertFalse((self.dir / "sky_default_panorama.png.import").exists())

    def test_the_panorama_needs_no_pillow(self) -> None:
        source = Path(sky_default.__file__).read_text() + Path(panorama_io.__file__).read_text()
        self.assertNotIn("PIL", source)
        out = self.build(panorama_size=(256, 128))
        self.assertEqual(out.warnings, ())
        self.assertEqual(read_png(self.dir / "sky_default_panorama.png").shape, (128, 256, 4))

    def test_the_star_file_is_unaffected_by_the_panorama_switch(self) -> None:
        self.build(panorama=False)
        plain = sha256(self.dir / "sky_default_stars.f32")
        self.build(panorama_size=(256, 128))
        self.assertEqual(sha256(self.dir / "sky_default_stars.f32"), plain)

    def test_star_count_option_reaches_the_star_file(self) -> None:
        out = self.build(panorama=False)
        self.assertEqual(out.manifest["star_field"]["count"], 300)
        self.assertEqual((self.dir / "sky_default_stars.f32").stat().st_size, 300 * 7 * 4)

    def test_options_scale_the_sky_radius(self) -> None:
        out = self.build(panorama=False, radius_m=1000.0)
        stars = sky_default.generate_stars(BuildContext(Path("."), 5).rng("stars"), 300, 1000.0)
        np.testing.assert_allclose(np.linalg.norm(stars.xyz, axis=1), 1000.0, atol=0.05)
        records = np.fromfile(self.dir / "sky_default_stars.f32", dtype="<f4").reshape(-1, 7)
        np.testing.assert_allclose(records[:, :3], stars.xyz / 1000.0, atol=1e-4)
        self.assertEqual(out.manifest["sky_radius_m"], 1000.0)


class SkyHelperTests(unittest.TestCase):
    def test_tangent_basis_is_orthonormal(self) -> None:
        n = np.random.default_rng(0).normal(size=(200, 3))
        n = np.vstack(
            [
                n / np.linalg.norm(n, axis=1, keepdims=True),
                [[0, 1, 0], [0, -1, 0], [1, 0, 0]],
            ]
        )
        e1, e2 = sky_default.tangent_basis(n)
        np.testing.assert_allclose(np.linalg.norm(e1, axis=1), 1.0, atol=1e-12)
        np.testing.assert_allclose(np.linalg.norm(e2, axis=1), 1.0, atol=1e-12)
        np.testing.assert_allclose(np.einsum("ij,ij->i", e1, n), 0.0, atol=1e-12)
        np.testing.assert_allclose(np.einsum("ij,ij->i", e1, e2), 0.0, atol=1e-12)

    def test_galactic_plane_passes_through_the_nebula(self) -> None:
        self.assertAlmostEqual(
            float(sky_default.GALACTIC_NORMAL @ sky_default.NEBULA_CENTER),
            0.0,
            places=12,
        )

    def test_render_panorama_small_image_has_nebula_where_expected(self) -> None:
        rng_s, rng_n = (
            BuildContext(Path("."), 1).rng("stars"),
            BuildContext(Path("."), 1).rng("nebula"),
        )
        sky_default.generate_stars(rng_s, 400, R)
        nebula = sky_default.generate_nebula(rng_n, 200, R)
        image = sky_default.render_panorama(nebula, 256, 128)[..., :3]
        self.assertEqual(image.dtype, np.uint8)
        # 35 degrees right of -Z: with the image centre on +Z that is longitude -145 degrees (Godot's panorama convention)
        x, y = int((-145 / 360 + 0.5) * 256), int((0.5 - 12 / 180) * 128)
        near = image[y - 8 : y + 8, x - 8 : x + 8].astype(float).mean()
        far = (
            image[128 - y - 8 : 128 - y + 8, (x + 128) % 256 - 8 : (x + 128) % 256 + 8]
            .astype(float)
            .mean()
        )
        self.assertGreater(near, 2.0 * far)


    def test_the_panorama_shows_a_gas_blob_as_the_m3_sky_did(self) -> None:
        # The M3 renderer composited the raw colours and decoded the result from sRGB: a lone blob of colour c and peak opacity
        # a showed decode(c) * a at its centre. The texel holds that radiance, sRGB-encoded, with no extra gain.
        def decode(c: np.ndarray) -> np.ndarray:
            return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

        raw = np.array([[0.5, 0.25, 0.75]])
        one = sky_default.Blobs(
            xyz=np.array([[0.0, 0.0, R]]),
            rgb=raw,
            alpha=np.array([0.5]),
            scale=np.full((1, 3), 0.15 * R),
            rot=rotations.quat_identity(1),
        )
        image = sky_default.render_panorama(one, 256, 128)
        centre = image[63:65, 127:129, :3].astype(float).mean(axis=(0, 1)) / 255.0
        np.testing.assert_allclose(decode(centre), decode(raw[0]) * 0.5, rtol=0.03)


if __name__ == "__main__":
    unittest.main()
