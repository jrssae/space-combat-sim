"""``sfx_gun`` (M10-T87, Q82): our own Starfury shot, close to the reference by the 95 % rule, and its pitched family."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import sfx_gun
from tools.procgen.core import audio, sound_match

SR = audio.SAMPLE_RATE
REFERENCE = Path(__file__).resolve().parents[3] / "references" / "starfurybolt.wav"


def centroid(samples: np.ndarray) -> float:
    power = np.abs(np.fft.rfft(samples)) ** 2
    freqs = np.fft.rfftfreq(len(samples), 1.0 / SR)
    return float(np.sum(power * freqs) / np.sum(power))


class GunShotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.shot = sfx_gun.gun_shot(np.random.default_rng(87))

    def test_the_table_covers_every_band_and_moment(self) -> None:
        self.assertEqual(sfx_gun.LEVELS_DB.shape, (len(sfx_gun.BANDS_HZ), len(sfx_gun.TIMES_S)))
        self.assertTrue(np.all(np.diff(sfx_gun.BANDS_HZ) > 0) and np.all(np.diff(sfx_gun.TIMES_S) > 0))
        self.assertEqual(sfx_gun.TIMES_S[-1], sfx_gun.DURATION_S)
        self.assertEqual(float(sfx_gun.LEVELS_DB.max()), 0.0)

    def test_full_length_and_seeded(self) -> None:
        self.assertEqual(len(self.shot), round(sfx_gun.DURATION_S * SR))
        np.testing.assert_array_equal(self.shot, sfx_gun.gun_shot(np.random.default_rng(87)))
        self.assertEqual(float(self.shot[0]), 0.0, "fades in from silence")
        self.assertLess(abs(float(self.shot[-1])), 1e-9, "and out, no click")

    @unittest.skipUnless(REFERENCE.exists(), "the reference clip is local only (references/, never committed)")
    def test_it_sounds_like_the_reference_by_the_95_percent_rule(self) -> None:
        reference, rate = audio.read_wav(REFERENCE)
        m = sound_match.compare(reference, self.shot, rate)
        self.assertGreaterEqual(m.mel, 0.95)
        self.assertGreaterEqual(m.envelope, 0.95)
        self.assertLessEqual(abs(m.length_ratio - 1.0), 0.05)

    def test_the_raiders_shot_is_three_semitones_up_and_as_long(self) -> None:
        raider = sfx_gun.weapon_shot(np.random.default_rng(87), "raider")
        self.assertEqual(len(raider), len(self.shot))
        self.assertAlmostEqual(centroid(raider) / centroid(self.shot), 2.0 ** (3.0 / 12.0), delta=0.06)

    def test_a_bigger_gun_is_lower_and_longer(self) -> None:
        heavy = sfx_gun.gun_shot(np.random.default_rng(87), sfx_gun.semitones(-12.0), 2.0)
        self.assertEqual(len(heavy), 2 * len(self.shot))
        self.assertAlmostEqual(centroid(heavy) / centroid(self.shot), 0.5, delta=0.06)

    def test_the_family_keeps_its_order(self) -> None:
        self.assertEqual(sfx_gun.WEAPONS["starfury"][:2], (0.0, 1.0))
        self.assertEqual(sfx_gun.WEAPONS["raider"][:2], (3.0, 1.0))
        for name, (steps, stretch, _) in sfx_gun.WEAPONS.items():
            if name not in ("starfury", "raider"):
                self.assertLess(steps, 0.0, f"{name} is lower")
                self.assertGreater(stretch, 1.0, f"{name} is longer")

    def test_a_burst_fades_each_tail_at_the_next_shot(self) -> None:
        rate, fade = 8.0, 0.04
        burst = sfx_gun.burst(np.random.default_rng(1), rate, 3, fade)
        gap = round(SR / rate)
        self.assertEqual(len(burst), 2 * gap + len(self.shot))
        alone = sfx_gun.burst(np.random.default_rng(1), rate, 1, fade)
        self.assertEqual(len(alone), len(self.shot), "the last shot rings in full")

    def test_the_listening_set_renders(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            paths = sfx_gun.render_samples(Path(tmp))
            self.assertEqual(len(paths), len(sfx_gun.WEAPONS) + 1)
            self.assertTrue(all(p.exists() for p in paths))


if __name__ == "__main__":
    unittest.main()
