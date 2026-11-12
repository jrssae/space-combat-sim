"""Colour helpers."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.core import color


class ColorTests(unittest.TestCase):
    def test_blackbody_hue_follows_temperature(self) -> None:
        cool, mid, hot = (color.blackbody_rgb(t) for t in (3000.0, 6500.0, 15000.0))
        self.assertGreater(cool[0], cool[2] * 2.0)  # red-orange
        self.assertGreater(hot[2], hot[0])  # blue-white
        self.assertLess(float(np.ptp(mid)), 0.15)  # ~white at 6500 K
        self.assertGreater(cool[0], cool[1])

    def test_blackbody_is_normalised_non_negative_and_vectorised(self) -> None:
        temps = np.array([2400.0, 3300.0, 5700.0, 9000.0, 33000.0])
        rgb = color.blackbody_rgb(temps)
        self.assertEqual(rgb.shape, (5, 3))
        self.assertTrue(np.all(rgb >= 0.0))
        np.testing.assert_allclose(rgb.max(axis=1), 1.0)
        np.testing.assert_allclose(color.blackbody_rgb(5700.0), rgb[2])
        self.assertEqual(color.blackbody_rgb(5700.0).shape, (3,))

    def test_blue_fraction_rises_monotonically_with_temperature(self) -> None:
        temps = np.linspace(2500.0, 30000.0, 40)
        rgb = color.blackbody_rgb(temps)
        blue_share = rgb[:, 2] / rgb.sum(axis=1)
        self.assertTrue(np.all(np.diff(blue_share) >= -1e-9))

    def test_srgb_round_trip(self) -> None:
        x = np.linspace(0.0, 1.0, 101)
        np.testing.assert_allclose(
            color.srgb_to_linear(color.linear_to_srgb(x)), x, atol=1e-9
        )
        self.assertAlmostEqual(float(color.linear_to_srgb(0.5)), 0.7354, places=3)
        self.assertAlmostEqual(
            float(color.linear_to_srgb(2.0)), 1.0, places=12
        )  # clipped

    def test_lerp(self) -> None:
        np.testing.assert_allclose(
            color.lerp([0, 0, 0], [1, 2, 4], 0.5), [0.5, 1.0, 2.0]
        )


if __name__ == "__main__":
    unittest.main()


class CaptureAlbedoTests(unittest.TestCase):
    """A colour read off a lit screen capture becomes the darker albedo that shows it in the game's light."""

    def test_a_capture_grey_becomes_a_darker_neutral_albedo(self) -> None:
        from tools.procgen.core.color import capture_albedo

        albedo = capture_albedo(0xA4A7AA, darken=1.0)
        shown = color.linear_to_srgb(np.array(albedo)) * 255.0
        np.testing.assert_allclose(shown, [0x73, 0x75, 0x77], atol=1.5)  # measured: 0x75 grey shows as 0xA7 at 45 degrees

    def test_the_paint_is_darkened_by_the_maintainers_choice(self) -> None:
        from tools.procgen.core.color import PAINT_DARKEN, capture_albedo

        self.assertEqual(PAINT_DARKEN, 0.5)
        np.testing.assert_allclose(capture_albedo(0xA4A7AA), np.array(capture_albedo(0xA4A7AA, darken=1.0)) * 0.5)

    def test_hue_is_kept_and_black_stays_black(self) -> None:
        from tools.procgen.core.color import capture_albedo, srgb_to_linear

        red = np.array(capture_albedo(0xA8322C))
        source = srgb_to_linear(np.array([0xA8, 0x32, 0x2C]) / 255.0)
        np.testing.assert_allclose(red / red.sum(), source / source.sum(), atol=1e-9)
        self.assertEqual(capture_albedo(0x000000), (0.0, 0.0, 0.0))

    def test_darker_never_lighter(self) -> None:
        from tools.procgen.core.color import capture_albedo, srgb_to_linear

        for hex_rgb in (0x101010, 0x4F5256, 0x8A8D90, 0xDADCDE, 0xF2E6C8, 0xFFFFFF):
            source = srgb_to_linear(np.array([(hex_rgb >> 16) & 255, (hex_rgb >> 8) & 255, hex_rgb & 255]) / 255.0)
            self.assertTrue(np.all(np.array(capture_albedo(hex_rgb)) <= source + 1e-12), f"{hex_rgb:06x}")
