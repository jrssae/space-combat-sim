"""The loudness reference (M8-T12): the meter reads BS.1770's calibration tone right, ignores silence around a sound, reads a
loop as its steady level, and the normaliser hits the target unless the peak ceiling stops it."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.core import audio, loudness

SR = audio.SAMPLE_RATE


def tone(freq_hz: float, amplitude: float, seconds: float) -> np.ndarray:
    return amplitude * np.sin(2.0 * np.pi * freq_hz * np.arange(int(seconds * SR)) / SR)


class LoudnessTest(unittest.TestCase):
    def test_a_full_scale_997_hz_tone_reads_minus_3_lufs(self) -> None:
        # BS.1770's calibration: a 0 dBFS sine at 997 Hz is -3.01 LKFS.
        self.assertAlmostEqual(loudness.loudness_lufs(tone(997.0, 1.0, 2.0)), -3.01, delta=0.05)

    def test_level_scales_with_gain(self) -> None:
        self.assertAlmostEqual(loudness.loudness_lufs(tone(997.0, 0.1, 2.0)), -23.01, delta=0.05)

    def test_the_k_weighting_lifts_highs_and_cuts_lows(self) -> None:
        mid = loudness.loudness_lufs(tone(997.0, 0.5, 1.0))
        self.assertGreater(loudness.loudness_lufs(tone(4000.0, 0.5, 1.0)), mid + 2.0)
        self.assertLess(loudness.loudness_lufs(tone(40.0, 0.5, 1.0)), mid - 5.0)

    def test_silence_after_a_sound_does_not_change_it(self) -> None:
        shot = tone(1500.0, 0.3, 0.1) * np.exp(-np.arange(int(0.1 * SR)) / (0.03 * SR))
        padded = np.concatenate([shot, np.zeros(SR)])
        self.assertAlmostEqual(loudness.loudness_lufs(padded), loudness.loudness_lufs(shot), delta=0.3)

    def test_a_loop_reads_as_its_steady_level(self) -> None:
        loop = tone(1000.0, 0.2, 1.0)  # whole cycles: seamless
        self.assertAlmostEqual(loudness.loudness_lufs(loop, loop=True), loudness.loudness_lufs(tone(1000.0, 0.2, 3.0)), delta=0.05)

    def test_silence_is_minus_infinity(self) -> None:
        self.assertEqual(loudness.loudness_lufs(np.zeros(SR)), -float("inf"))

    def test_normalise_hits_the_target(self) -> None:
        rng = np.random.default_rng(1)
        noise = rng.normal(0.0, 0.05, SR)
        out = loudness.normalize_loudness(noise, -20.0, -1.0)
        self.assertAlmostEqual(loudness.loudness_lufs(out), -20.0, delta=0.01)

    def test_the_peak_ceiling_wins_over_the_target(self) -> None:
        click = np.zeros(SR)
        click[100] = 0.5  # all crest: reaching -20 LUFS would need a peak far above full scale
        out = loudness.normalize_loudness(click, -20.0, -1.0)
        self.assertAlmostEqual(audio.peak_dbfs(out), -1.0, places=6)
        self.assertLess(loudness.loudness_lufs(out), -20.0)


if __name__ == "__main__":
    unittest.main()
