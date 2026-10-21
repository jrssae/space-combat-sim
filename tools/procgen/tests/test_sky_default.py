"""``sky_default``: counts, PLY content, nebula opacity, frames, manifest, panorama, determinism."""

from __future__ import annotations

import hashlib
import math
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

from tools.procgen.assets import sky_default
from tools.procgen.core import frames
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.ply import PROPERTY_NAMES, SplatData, read_ply

try:
    from PIL import Image
except ImportError:  # the panorama is optional
    Image = None

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
        cls.ply = read_ply(cls.dir_a / "sky_default.ply")
        cls.splats = cls.ply.to_splats()
        # Back to the authoring frame: undo the Rz(180) and the re-centring.
        cls.godot_xyz = frames.flip_xy(cls.splats.xyz) + np.array(
            cls.manifest["centroid_offset"]
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    # --- manifest ------------------------------------------------------------------------------
    def test_manifest_has_lods_zero_pointing_at_the_ply(self) -> None:
        lod0 = self.manifest["lods"][0]
        self.assertEqual(lod0["level"], 0)
        self.assertEqual(lod0["file"], "sky_default.ply")
        self.assertEqual(lod0["splats"], N_STARS + N_NEBULA)
        self.assertGreater(lod0["spacing_m"], 0)
        self.assertEqual(len(self.manifest["lods"]), 1)  # M1 emits LOD 0 only

    def test_manifest_basics(self) -> None:
        m = self.manifest
        self.assertEqual(m["asset_id"], "sky_default")
        self.assertEqual((m["frame"], m["units"], m["seed"]), ("godot", "m", 42))
        self.assertEqual(m["counts"], {"stars": N_STARS, "nebula": N_NEBULA})
        self.assertEqual(m["sky_radius_m"], R)
        self.assertEqual(self.out_a.manifest, m)
        self.assertEqual(self.out_a.splat_count, N_STARS + N_NEBULA)

    def test_splat_count_is_within_the_specified_budget(self) -> None:
        self.assertTrue(10_000 <= self.manifest["lods"][0]["splats"] <= 25_000)
        self.assertEqual(self.ply.count, self.manifest["lods"][0]["splats"])

    # --- PLY layout ----------------------------------------------------------------------------
    def test_ply_parses_back_with_the_expected_fields(self) -> None:
        self.assertEqual(self.ply.format, "binary_little_endian 1.0")
        self.assertEqual(self.ply.names, list(PROPERTY_NAMES))
        for name in PROPERTY_NAMES:
            self.assertTrue(np.all(np.isfinite(self.ply.column(name))), name)

    def test_decoded_splats_are_sane(self) -> None:
        s = self.splats
        self.assertTrue(np.all((s.alpha > 0) & (s.alpha <= 1)))
        self.assertTrue(np.all(s.rgb >= -1e-6))
        self.assertTrue(np.all(s.scale > 0))
        np.testing.assert_allclose(np.linalg.norm(s.rot, axis=1), 1.0, atol=1e-5)

    def test_manifest_aabb_matches_the_written_positions_after_the_flip(self) -> None:
        # What the Godot-side import test will compare: AABB of the PLY positions == Rz(180) of manifest AABB.
        lo, hi = frames.aabb_godot_to_3dgs(
            self.manifest["aabb_min"], self.manifest["aabb_max"]
        )
        np.testing.assert_allclose(self.splats.xyz.min(axis=0), lo, atol=2e-3)
        np.testing.assert_allclose(self.splats.xyz.max(axis=0), hi, atol=2e-3)

    def test_positions_are_centred_so_the_gdgs_import_centring_is_a_no_op(self) -> None:
        self.assertLess(float(np.abs(self.splats.xyz.mean(axis=0)).max()), 1e-3)

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

    def test_file_is_the_authored_sky_in_the_3dgs_frame(self) -> None:
        stars = sky_default.generate_stars(
            BuildContext(Path("."), 42).rng("stars"), N_STARS, R
        )
        nebula = sky_default.generate_nebula(
            BuildContext(Path("."), 42).rng("nebula"), N_NEBULA, R
        )
        authored = SplatData.concatenate([stars, nebula])
        np.testing.assert_allclose(self.godot_xyz, authored.xyz, atol=0.02)
        want = frames.quat_to_matrix(frames.godot_to_3dgs_quats(authored.rot))
        got = frames.quat_to_matrix(self.splats.rot)
        np.testing.assert_allclose(got, want, atol=1e-5)

    # --- stars ---------------------------------------------------------------------------------
    def test_stars_are_small_isotropic_and_opaque(self) -> None:
        stars = self.splats.scale[:N_STARS]
        np.testing.assert_allclose(stars[:, 0], stars[:, 1], rtol=1e-5)
        np.testing.assert_allclose(stars[:, 0], stars[:, 2], rtol=1e-5)
        self.assertTrue(
            np.all((stars[:, 0] > 6.0) & (stars[:, 0] <= 12.01))
        )  # 12 m = 0.6 mrad at 20 km
        self.assertGreater(
            float(stars.max()), 11.0
        )  # the brightest star reaches the nominal size
        self.assertTrue(np.all(self.splats.alpha[:N_STARS] >= 0.999))

    def test_bright_stars_are_rare_big_and_bright(self) -> None:
        stars = self.splats
        luminance = stars.rgb[:N_STARS].mean(axis=1)
        sigma = stars.scale[:N_STARS, 0]
        self.assertGreater(float(np.corrcoef(luminance, sigma)[0, 1]), 0.8)
        self.assertLess(
            float((luminance > 0.75).mean()), 0.08
        )  # dim stars dominate (dN/dm ~ 10^(0.5 m))
        self.assertGreater(float((luminance < 0.4).mean()), 0.6)
        self.assertGreater(float(luminance.max()), 1.0)

    def test_star_colours_span_red_to_blue(self) -> None:
        rgb = self.splats.rgb[:N_STARS]
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
        alpha = self.splats.alpha[N_STARS:]
        self.assertGreaterEqual(float(alpha.min()), 0.02)
        self.assertLessEqual(float(alpha.max()), 0.08)
        self.assertGreater(
            float(alpha.max() - alpha.min()), 0.02
        )  # a real spread, not a constant

    def test_nebula_splats_are_large_soft_and_slightly_anisotropic(self) -> None:
        scale = self.splats.scale[N_STARS:]
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
        rgb = self.splats.rgb[N_STARS:]
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

    # --- panorama ------------------------------------------------------------------------------
    @unittest.skipIf(Image is None, "Pillow not installed")
    def test_panorama_is_a_4096_by_2048_png_listed_in_the_manifest(self) -> None:
        path = self.dir_a / "sky_default_panorama.png"
        self.assertEqual(
            self.manifest["files"], {"panorama": "sky_default_panorama.png"}
        )
        self.assertIn(path, self.out_a.files)
        with Image.open(path) as img:
            self.assertEqual(
                (img.size, img.mode, img.format), ((4096, 2048), "RGB", "PNG")
            )
            pixels = np.asarray(img, dtype=float) / 255.0
        self.assertGreater(float(pixels.mean()), 0.005)  # not black
        self.assertLess(float(pixels.mean()), 0.2)  # but a night sky

        def patch(lon_deg: float, lat_deg: float) -> float:
            x = int((lon_deg / 360.0 + 0.5) * 4096)
            y = int((0.5 - lat_deg / 180.0) * 2048)
            return float(pixels[y - 100 : y + 100, x - 100 : x + 100].mean())

        # Godot's panorama convention: centre = +Z, so the nebula (35 degrees right of -Z, 12 up) sits at lon -145, lat +12.
        self.assertGreater(patch(-145.0, 12.0), 3.0 * patch(35.0, -12.0))

    @unittest.skipIf(Image is None, "Pillow not installed")
    def test_nebula_pixels_are_coloured_and_stars_are_visible(self) -> None:
        with Image.open(self.dir_a / "sky_default_panorama.png") as img:
            pixels = np.asarray(img, dtype=float)
        bright = (pixels.max(axis=2) > 160).mean()
        self.assertGreater(float(bright), 1e-4)  # star pixels
        self.assertLess(float(bright), 0.02)  # on a mostly dark sky

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
                sha256(Path(tmp) / "sky_default.ply"),
                sha256(self.dir_a / "sky_default.ply"),
            )
            self.assertEqual(
                other.splat_count, self.out_a.splat_count
            )  # same budget either way


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
        self.assertEqual(read_ply(self.dir / "sky_default.ply").count, 420)

    def test_invalid_counts_are_rejected(self) -> None:
        for bad in ({"stars": 0}, {"nebula": 0}, {"radius_m": 0}):
            with self.subTest(bad), self.assertRaises(ValueError):
                self.build(**bad)

    def test_panorama_can_be_switched_off(self) -> None:
        out = self.build(panorama=False)
        self.assertEqual(out.manifest["files"], {})
        self.assertEqual(out.warnings, ())
        self.assertFalse((self.dir / "sky_default_panorama.png").exists())

    def test_missing_pillow_skips_the_panorama_with_a_warning_but_builds_the_ply(
        self,
    ) -> None:
        self.dir.mkdir()
        stale = self.dir / "sky_default_panorama.png"
        stale.write_bytes(b"stale")
        with mock.patch.dict(sys.modules, {"PIL": None, "PIL.Image": None}):
            out = self.build()
        self.assertEqual(len(out.warnings), 1)
        self.assertIn("Pillow", out.warnings[0])
        self.assertIn("sky_default_panorama.png", out.warnings[0])
        self.assertEqual(out.manifest["files"], {})
        self.assertFalse(
            stale.exists()
        )  # the directory never lists a panorama the manifest omits
        self.assertTrue((self.dir / "sky_default.ply").is_file())
        self.assertEqual(
            [p.name for p in out.files], ["sky_default.ply", "manifest.json"]
        )
        self.assertEqual(manifest_io.read_manifest(self.dir)["lods"][0]["splats"], 420)

    def test_the_ply_is_unaffected_by_pillow_or_the_panorama_switch(self) -> None:
        self.build(panorama=False)
        plain = sha256(self.dir / "sky_default.ply")
        with mock.patch.dict(sys.modules, {"PIL": None, "PIL.Image": None}):
            self.build()
        self.assertEqual(sha256(self.dir / "sky_default.ply"), plain)

    def test_options_scale_the_sky_radius(self) -> None:
        out = self.build(panorama=False, radius_m=1000.0)
        stars = read_ply(self.dir / "sky_default.ply").to_splats()
        godot = frames.flip_xy(stars.xyz) + np.array(out.manifest["centroid_offset"])
        np.testing.assert_allclose(
            np.linalg.norm(godot[:300], axis=1), 1000.0, atol=0.05
        )
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
        stars = sky_default.generate_stars(rng_s, 400, R)
        nebula = sky_default.generate_nebula(rng_n, 200, R)
        image = sky_default.render_panorama(stars, nebula, 256, 128)
        self.assertEqual((image.shape, image.dtype), ((128, 256, 3), np.uint8))
        # 35 degrees right of -Z: with the image centre on +Z that is longitude -145 degrees (Godot's panorama convention)
        x, y = int((-145 / 360 + 0.5) * 256), int((0.5 - 12 / 180) * 128)
        near = image[y - 8 : y + 8, x - 8 : x + 8].astype(float).mean()
        far = (
            image[128 - y - 8 : 128 - y + 8, (x + 128) % 256 - 8 : (x + 128) % 256 + 8]
            .astype(float)
            .mean()
        )
        self.assertGreater(near, 2.0 * far)


if __name__ == "__main__":
    unittest.main()
