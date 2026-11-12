"""``sfx_world`` (AC5 of M5, Q12): the world's own sounds, first ``jump_in`` (a jump point opening). 48 kHz mono 16-bit, peaks
at most -1 dBFS, seeded and byte-identical per seed; the jump rises to the moment the point opens, then bursts and dies away."""

from __future__ import annotations

import hashlib
import tempfile
import unittest
import wave
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS, sfx_world
from tools.procgen.core import audio
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext

SR = audio.SAMPLE_RATE


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def centroid_hz(samples: np.ndarray) -> float:
    """The spectral centroid of a stretch of sound."""
    mag = np.abs(np.fft.rfft(samples * np.hanning(len(samples))))
    freqs = np.fft.rfftfreq(len(samples), 1.0 / SR)
    return float(np.sum(freqs * mag) / max(float(np.sum(mag)), 1e-12))


def rms(samples: np.ndarray) -> float:
    return float(np.sqrt(np.mean(samples**2)))


class SfxWorldTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b, cls.dir_c = root / "a", root / "b", root / "c"
        cls.out_a = sfx_world.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = sfx_world.build(BuildContext(cls.dir_b, seed=42))
        cls.out_c = sfx_world.build(BuildContext(cls.dir_c, seed=7))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.jump, _ = audio.read_wav(cls.dir_a / "jump_in.wav")

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_it_is_registered(self) -> None:
        self.assertIs(ASSETS["sfx_world"], sfx_world.build)

    def test_the_wav_and_the_manifest_are_written(self) -> None:
        self.assertEqual({p.name for p in self.dir_a.iterdir()}, {"jump_in.wav", "manifest.json"})
        self.assertEqual({p.name for p in self.out_a.files}, {"jump_in.wav", "manifest.json"})
        self.assertTrue(self.out_a.summary.startswith("1 sound"), self.out_a.summary)

    def test_the_manifest_is_an_audio_manifest(self) -> None:
        m = self.manifest
        self.assertEqual(m["kind"], "audio")
        self.assertEqual(m["asset_id"], "sfx_world")
        self.assertEqual(set(m["sounds"]), {"jump_in"})
        entry = m["sounds"]["jump_in"]
        self.assertAlmostEqual(entry["duration_s"], sfx_world.JUMP_S, places=3)
        self.assertNotIn("loop_begin", entry, "a one-shot")

    def test_mono_16_bit_48k_with_the_manifest_length(self) -> None:
        entry = self.manifest["sounds"]["jump_in"]
        with wave.open(str(self.dir_a / "jump_in.wav"), "rb") as f:
            self.assertEqual((f.getnchannels(), f.getsampwidth(), f.getframerate()), (1, 2, 48_000))
            self.assertEqual(f.getnframes(), entry["samples"])

    def test_peak_is_at_most_minus_one_dbfs_and_matches_the_manifest(self) -> None:
        peak = audio.peak_dbfs(self.jump)
        self.assertLessEqual(peak, -1.0)
        self.assertGreater(peak, -3.0, "not needlessly quiet")
        self.assertAlmostEqual(peak, self.manifest["sounds"]["jump_in"]["peak_dbfs"], places=2)

    def test_the_same_seed_gives_the_same_bytes_and_another_seed_other_noise(self) -> None:
        self.assertEqual(sha256(self.dir_a / "jump_in.wav"), sha256(self.dir_b / "jump_in.wav"))
        self.assertNotEqual(sha256(self.dir_a / "jump_in.wav"), sha256(self.dir_c / "jump_in.wav"))

    def test_it_starts_and_ends_quietly_and_has_no_dc(self) -> None:
        self.assertLess(abs(float(self.jump[0])), 0.02)
        self.assertLess(abs(float(self.jump[-1])), 0.02)
        self.assertLess(abs(float(np.mean(self.jump))), 0.02)
        self.assertGreater(float(np.std(self.jump)), 0.02)

    def test_it_rises_to_the_opening_then_dies_away(self) -> None:
        open_at = int(sfx_world.OPEN_S * SR)
        quarter = open_at // 4
        early, late = self.jump[:quarter], self.jump[open_at - quarter : open_at]
        self.assertGreater(rms(late), 2.0 * rms(early), "louder as the point opens")
        self.assertGreater(centroid_hz(late), 1.5 * centroid_hz(early), "and brighter: a rising sweep")
        burst = self.jump[open_at : open_at + quarter]
        tail = self.jump[-quarter:]
        self.assertGreater(rms(burst), 4.0 * rms(tail), "the burst dies away")
        loudest = int(np.argmax(np.abs(self.jump)))
        self.assertGreater(loudest, open_at - SR // 20, "its peak is at the opening, not before")


if __name__ == "__main__":
    unittest.main()
