"""``core/sound_match`` (M10-T87): the log-mel, loudness-envelope and length measure behind "sounds like the reference"."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.core import audio, sound_match

SR = audio.SAMPLE_RATE


def _shot(seed: int, duration: float = 0.6) -> np.ndarray:
    """A noise burst that decays, the kind of sound the measure is for."""
    t = audio.time_axis(duration)
    return audio.bandpass(audio.white_noise(np.random.default_rng(seed), len(t)), 500.0, 6000.0) * audio.exp_decay(t, 0.12)


class SoundMatchTests(unittest.TestCase):
    def test_a_sound_matches_itself_exactly(self) -> None:
        shot = _shot(1)
        m = sound_match.compare(shot, shot)
        self.assertAlmostEqual(m.mel, 1.0, places=6)
        self.assertAlmostEqual(m.envelope, 1.0, places=6)
        self.assertAlmostEqual(m.length_ratio, 1.0, places=6)
        self.assertTrue(m.passes())

    def test_level_does_not_count(self) -> None:
        shot = _shot(1)
        loud, quiet = sound_match.compare(shot, shot), sound_match.compare(shot, shot * 0.1)
        self.assertAlmostEqual(loud.mel, quiet.mel, places=4)
        self.assertAlmostEqual(loud.envelope, quiet.envelope, places=4)

    def test_another_noise_of_the_same_shape_still_matches(self) -> None:
        self.assertTrue(sound_match.compare(_shot(1), _shot(2)).passes(), "two takes of one sound")

    def test_a_tone_does_not_match_noise(self) -> None:
        t = audio.time_axis(0.6)
        tone = audio.sine(audio.phase_from_frequency(np.full_like(t, 200.0))) * audio.exp_decay(t, 0.12)
        m = sound_match.compare(_shot(1), tone)
        self.assertLess(m.mel, 0.6)
        self.assertFalse(m.passes())

    def test_a_missing_tail_fails_on_length(self) -> None:
        shot = _shot(1)
        held = np.concatenate([shot, 0.3 * _shot(3, 0.4)])  # rings on 0.4 s longer
        m = sound_match.compare(held, shot)
        self.assertLess(m.length_ratio, 0.8)
        self.assertFalse(m.passes())

    def test_a_dull_middle_fails_on_the_top_alone(self) -> None:
        # The maintainer's A/B, round 2: a shot whose top dips mid-way can pass the whole-sound number.
        t = audio.time_axis(1.0)
        rng = np.random.default_rng(5)
        body = audio.lowpass(audio.white_noise(rng, len(t)), 2000.0, order=4) * audio.exp_decay(t, 0.4)
        top = audio.highpass(audio.white_noise(rng, len(t)), 3500.0, order=4) * 0.3 * audio.exp_decay(t, 0.4)
        swell = 1.0 + 3.0 * np.exp(-0.5 * ((t - 0.5) / 0.08) ** 2)  # the top brightens through the middle
        reference = body + top * swell
        dull = body + top
        m = sound_match.compare(reference, dull)
        self.assertLess(m.high, 0.95)
        self.assertGreater(m.mel, m.high, "the whole-sound number misses most of it")
        self.assertFalse(m.passes())
        self.assertGreaterEqual(sound_match.compare(reference, reference).high, 0.999)

    def test_resampling_keeps_a_tones_pitch_and_level(self) -> None:
        rate = 22_050
        t = np.arange(rate // 2) / rate
        tone = 0.5 * np.sin(2.0 * np.pi * 1000.0 * t)
        up = sound_match.resample(tone, rate)
        self.assertEqual(len(up), SR // 2)
        spectrum = np.abs(np.fft.rfft(up * np.hanning(len(up))))
        self.assertAlmostEqual(float(np.fft.rfftfreq(len(up), 1.0 / SR)[np.argmax(spectrum)]), 1000.0, delta=3.0)
        middle = up[len(up) // 4 : 3 * len(up) // 4]
        self.assertAlmostEqual(float(np.sqrt(np.mean(middle**2))), 0.5 / np.sqrt(2.0), delta=0.01)


if __name__ == "__main__":
    unittest.main()
