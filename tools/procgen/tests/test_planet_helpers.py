"""``planet``'s pure helpers on small grids (quick tier): the map grid and its frame, the noise, the sampler's layers and caps,
normals from height and the colour ramp."""

from __future__ import annotations

import math
import unittest
from unittest import mock

import numpy as np

from tools.procgen.assets import planet


class GridTests(unittest.TestCase):
    def test_texel_centres_are_unit_directions_that_map_back_to_their_uv(self) -> None:
        w, h = 64, 32
        d = planet.sphere_directions(w, h)
        np.testing.assert_allclose(np.linalg.norm(d, axis=-1), 1.0, atol=1e-6)
        u, v = planet.direction_to_uv(d.astype(np.float64))
        np.testing.assert_allclose(u, np.broadcast_to((np.arange(w) + 0.5) / w, (h, w)), atol=1e-6)
        np.testing.assert_allclose(v, np.broadcast_to(((np.arange(h) + 0.5) / h)[:, None], (h, w)), atol=1e-6)

    def test_the_mapping_is_sphere_meshs(self) -> None:
        # u = 0 looks toward +Z, a quarter turn toward +X; the top row is the north pole (+Y).
        u, v = planet.direction_to_uv(np.array([[0.0, 0.0, 1.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]]))
        np.testing.assert_allclose(u[:2], [0.0, 0.25], atol=1e-9)
        np.testing.assert_allclose(v, [0.5, 0.5, 0.0], atol=1e-9)

    def test_east_and_north_are_orthonormal_tangents_along_the_grid(self) -> None:
        d = planet.sphere_directions(48, 24).astype(np.float64)
        east, north = planet.tangent_frame(d)
        for a, b in ((east, north), (east, d), (north, d)):
            np.testing.assert_allclose((a * b).sum(-1), 0.0, atol=1e-6)
        np.testing.assert_allclose(np.linalg.norm(east, axis=-1), 1.0, atol=1e-6)
        np.testing.assert_allclose(np.linalg.norm(north, axis=-1), 1.0, atol=1e-6)
        # East points to the next column, north to the row above.
        step_e = d[:, 1] - d[:, 0]
        step_n = d[5] - d[6]
        self.assertTrue(np.all((step_e * east[:, 0]).sum(-1) > 0))
        self.assertTrue(np.all((step_n * north[5]).sum(-1) > 0))


class NoiseTests(unittest.TestCase):
    def test_noise_is_seeded_bounded_smooth_and_zero_on_the_lattice(self) -> None:
        rng = np.random.default_rng(1)
        p = rng.uniform(-40.0, 40.0, (20_000, 3)).astype(np.float32)
        a = planet.gradient_noise(p, 7)
        np.testing.assert_array_equal(a, planet.gradient_noise(p.copy(), 7))
        self.assertGreater(float(np.abs(a - planet.gradient_noise(p, 8)).mean()), 0.1)
        self.assertLess(float(np.abs(a).max()), 1.2)
        self.assertGreater(float(a.std()), 0.15)
        step = planet.gradient_noise(p + np.float32(1e-3), 7)
        self.assertLess(float(np.abs(step - a).max()), 0.02)
        lattice = rng.integers(-50, 50, (100, 3)).astype(np.float32)
        np.testing.assert_allclose(planet.gradient_noise(lattice, 7), 0.0, atol=1e-6)

    def test_far_lattice_cells_do_not_repeat(self) -> None:
        # A periodic table would make the highest octave repeat across the sphere; the hash has no period.
        p = np.random.default_rng(2).uniform(0.0, 20.0, (20_000, 3)).astype(np.float32)
        for shift in (256.0, 512.0, 4096.0):
            other = planet.gradient_noise(p + np.float32(shift), 3)
            self.assertLess(abs(float(np.corrcoef(planet.gradient_noise(p, 3), other)[0, 1])), 0.05, shift)


class SamplerTests(unittest.TestCase):
    def test_layers_are_computed_as_coarse_as_their_frequency_allows(self) -> None:
        s = planet.SphereSampler(4096, 2048, 1)
        self.assertEqual(s.layer_width(1.0), planet.MIN_LAYER_WIDTH)
        self.assertEqual(s.layer_width(16.0), 1024)
        self.assertEqual(s.layer_width(64.0), 4096)
        self.assertEqual(s.layer_width(1000.0), 4096)
        self.assertLess(s.layer_width(16.0, planet.COLOUR_TEXELS_PER_CELL), s.layer_width(16.0))

    def test_threads_change_nothing(self) -> None:
        def layer(threads: int) -> np.ndarray:
            with mock.patch.object(planet, "THREADS", threads):
                return planet.SphereSampler(256, 128, 5, chunk_rows=16).fbm(3.0, 3, salt=1)

        np.testing.assert_array_equal(layer(1), layer(4))

    def test_an_enlarged_layer_is_seamless_and_exact_at_the_poles(self) -> None:
        s = planet.SphereSampler(1024, 512, 9)
        coarse = s.noise(4.0, salt=2)  # computed at 256 wide and enlarged
        self.assertEqual(s.layer_width(4.0), 256)
        exact = planet.gradient_noise(planet.sphere_directions(1024, 512) * np.float32(4.0), (9 * 0x9E3779B1 + 2 * 0x85EBCA77) & 0xFFFFFFFF)
        # Near the poles the cap is the exact noise; elsewhere bilinear enlarging stays within a few per cent of the swing.
        np.testing.assert_allclose(coarse[:2], exact[:2], atol=1e-6)
        np.testing.assert_allclose(coarse[-2:], exact[-2:], atol=1e-6)
        self.assertLess(float(np.abs(coarse - exact).max()), 0.05 * float(np.ptp(exact)))
        seam = float(np.abs(coarse[:, 0] - coarse[:, -1]).mean())
        self.assertLess(seam, 1.5 * float(np.abs(np.diff(coarse, axis=1)).mean()))

    def test_a_warp_bends_the_sample_points(self) -> None:
        s = planet.SphereSampler(128, 64, 3)
        plain = s.noise(4.0, salt=1)
        s.set_warp(np.full((64, 128, 3), 0.3, dtype=np.float32))
        bent = s.noise(4.0, salt=1)
        s.set_warp(None)
        self.assertGreater(float(np.abs(plain - bent).mean()), 0.05)
        np.testing.assert_array_equal(s.noise(4.0, salt=1), plain)


class NormalTests(unittest.TestCase):
    def test_flat_ground_points_straight_up(self) -> None:
        n = planet.normals_from_height(np.full((32, 64), 123.0), 1000.0, 5.0)
        np.testing.assert_allclose(n, np.broadcast_to([0.0, 0.0, 1.0], n.shape), atol=1e-6)

    def test_a_slope_tilts_the_normal_away_from_the_rise(self) -> None:
        # Height rising to the north (h = A * y on the sphere): the slope at latitude phi is A cos(phi) / R northward.
        w, h, radius, amp, k = 256, 128, 1000.0, 50.0, 3.0
        d = planet.sphere_directions(w, h).astype(np.float64)
        n = planet.normals_from_height(amp * d[..., 1], radius, k)
        lat = planet.latitudes(h)
        slope = k * amp * np.cos(lat) / radius
        expect_north = -slope / np.sqrt(1.0 + slope**2)
        np.testing.assert_allclose(n[:, :, 1], np.broadcast_to(expect_north[:, None], (h, w)), atol=2e-3)
        np.testing.assert_allclose(n[:, :, 0], 0.0, atol=1e-6)
        self.assertTrue(np.all(np.isfinite(n)))

    def test_normals_survive_eight_bits(self) -> None:
        n = planet.normals_from_height(np.random.default_rng(4).normal(0.0, 30.0, (32, 64)), 1000.0, 2.0)
        back = planet.decode_normals(planet.encode_normals(n))
        self.assertGreater(float((back * n).sum(-1).min()), 0.9995)


class ColourTests(unittest.TestCase):
    def test_the_ramp_hits_its_stops(self) -> None:
        ramp = planet.EPSILON_III.ramp
        got = planet.ramp_colour(ramp, np.array([0.0, 1.0], dtype=np.float32))
        for row, (_, srgb) in zip(got, (ramp[0], ramp[-1])):
            np.testing.assert_allclose(row, planet._linear(srgb), atol=1e-5)

    def test_epsilon_iii_is_warm_and_dry(self) -> None:
        spec = planet.EPSILON_III
        colours = [c for _, c in spec.ramp] + [spec.rust, spec.ochre, spec.pale]
        for r, g, b in colours:
            self.assertGreater(r, g)
            self.assertGreater(g, b)
            hue = math.degrees(math.atan2(math.sqrt(3) * (g - b), 2 * r - g - b)) % 360
            self.assertLess(hue, 45.0, (r, g, b))
        self.assertFalse(spec.ocean)
        self.assertFalse(spec.night_lights)
        self.assertEqual(spec.map_size[0], 2 * spec.map_size[1])


if __name__ == "__main__":
    unittest.main()
