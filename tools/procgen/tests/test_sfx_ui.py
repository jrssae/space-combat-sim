"""``sfx_ui`` (AC2 and AC6 of M5): the menu sounds and the comms squelches, 48 kHz mono 16-bit, peaks at most -1 dBFS, seeded
and byte-identical per seed. Move is a tick, accept rises and back falls, so the three tell apart without looking; the radio
open and close are bursts of band-limited static that end or begin on a tone going up or down."""

from __future__ import annotations

import tempfile
import unittest
import wave
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS, sfx_ui
from tools.procgen.core import audio
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext

MENU = ("ui_move", "ui_accept", "ui_back")
RADIO = ("radio_open", "radio_close")
EXPECTED = MENU + RADIO
SR = audio.SAMPLE_RATE


def dominant_hz(samples: np.ndarray) -> float:
    """The strongest frequency of a short sound (a Hann window, zero padded for a finer grid)."""
    n = 8 * len(samples)
    mag = np.abs(np.fft.rfft(samples * np.hanning(len(samples)), n))
    return float(np.fft.rfftfreq(n, 1.0 / SR)[int(np.argmax(mag))])


def band_energy_share(samples: np.ndarray, low_hz: float, high_hz: float) -> float:
    """The share of a sound's energy between ``low_hz`` and ``high_hz``."""
    power = np.abs(np.fft.rfft(samples)) ** 2
    freqs = np.fft.rfftfreq(len(samples), 1.0 / SR)
    return float(np.sum(power[(freqs >= low_hz) & (freqs <= high_hz)]) / np.sum(power))


def tonal_share(samples: np.ndarray, top_fraction: float = 0.01) -> float:
    """The share of the energy held by the strongest ``top_fraction`` of the frequency bins (a tone concentrates, static spreads)."""
    power = np.sort(np.abs(np.fft.rfft(samples)) ** 2)[::-1]
    return float(np.sum(power[: max(1, int(len(power) * top_fraction))]) / np.sum(power))


class SfxUiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = sfx_ui.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = sfx_ui.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def wav(self, name: str) -> np.ndarray:
        return audio.read_wav(self.dir_a / f"{name}.wav")[0]

    def test_it_is_registered_for_gen_assets(self) -> None:
        self.assertIs(ASSETS["sfx_ui"], sfx_ui.build)

    def test_the_five_wavs_and_an_audio_manifest_are_written(self) -> None:
        names = {p.name for p in self.dir_a.iterdir()}
        self.assertEqual(names, {f"{n}.wav" for n in EXPECTED} | {"manifest.json"})
        self.assertEqual(self.manifest["kind"], "audio")
        self.assertEqual(set(self.manifest["sounds"]), set(EXPECTED))
        self.assertEqual(self.out_a.summary, "5 sounds")
        for name in EXPECTED:
            self.assertEqual(self.manifest["files"][name], f"{name}.wav")
            self.assertNotIn("loop_begin", self.manifest["sounds"][name], "one-shots, not loops")

    def test_every_wav_is_mono_16_bit_48k_with_the_manifest_length(self) -> None:
        for name, entry in self.manifest["sounds"].items():
            with wave.open(str(self.dir_a / entry["file"]), "rb") as f:
                self.assertEqual((f.getnchannels(), f.getsampwidth(), f.getframerate()), (1, 2, 48_000), name)
                self.assertEqual(f.getnframes(), entry["samples"], name)

    def test_peaks_are_at_most_minus_one_dbfs_and_match_the_manifest(self) -> None:
        for name, entry in self.manifest["sounds"].items():
            peak = audio.peak_dbfs(self.wav(name))
            self.assertLessEqual(peak, -1.0, name)
            self.assertGreater(peak, -3.0, f"{name}: not needlessly quiet")
            self.assertAlmostEqual(peak, entry["peak_dbfs"], places=2, msg=name)

    def test_menu_sounds_are_short_and_move_is_the_shortest(self) -> None:
        lengths = {name: len(self.wav(name)) / SR for name in EXPECTED}
        for name, seconds in lengths.items():
            self.assertLessEqual(seconds, 0.25, f"{name}: a menu sound must not outlast the next key press")
        self.assertLessEqual(lengths["ui_move"], 0.06)
        self.assertEqual(min(lengths, key=lengths.get), "ui_move")

    def test_they_start_and_end_quietly_so_they_do_not_click(self) -> None:
        for name in EXPECTED:
            samples = self.wav(name)
            self.assertLess(abs(float(samples[0])), 0.05, f"{name}: no hard start")
            self.assertLess(abs(float(samples[-1])), 0.02, f"{name}: ends at silence")
            self.assertGreater(float(np.std(samples)), 0.02, f"{name}: not silent")
            self.assertLess(abs(float(np.mean(samples))), 0.05, f"{name}: no DC offset")

    def test_accept_rises_and_back_falls(self) -> None:
        for name, rising in (("ui_accept", True), ("ui_back", False)):
            samples = self.wav(name)
            half = len(samples) // 2
            first, second = dominant_hz(samples[:half]), dominant_hz(samples[half:])
            self.assertTrue(second > 1.2 * first if rising else second < first / 1.2, (name, first, second))

    def test_move_is_a_high_soft_tick(self) -> None:
        self.assertGreater(dominant_hz(self.wav("ui_move")), 1000.0)
        # Quieter on the ear than accept: less energy, so a held D-pad is not a nuisance.
        self.assertLess(float(np.sum(self.wav("ui_move") ** 2)), float(np.sum(self.wav("ui_accept") ** 2)))

    # --- the comms squelches (M5-T06, D53) -------------------------------------------------------------------------------

    def test_the_squelches_are_band_limited_static_with_nothing_low(self) -> None:
        for name in RADIO:
            samples = self.wav(name)
            self.assertGreaterEqual(band_energy_share(samples, 400.0, 4500.0), 0.85, f"{name}: a radio's voice band")
            self.assertLess(band_energy_share(samples, 0.0, 200.0), 0.01, f"{name}: no rumble")
            self.assertLess(tonal_share(samples), 0.45, f"{name}: static, not a pure tone")

    def test_the_squelches_frame_a_line_without_outlasting_its_start_or_end(self) -> None:
        opens, closes = len(self.wav("radio_open")) / SR, len(self.wav("radio_close")) / SR
        self.assertGreaterEqual(opens, 0.15)
        self.assertGreaterEqual(closes, 0.10)
        self.assertLessEqual(opens, 0.30)
        self.assertLessEqual(closes, 0.25)
        self.assertGreater(opens, closes, "the open carries the key-up tone, the close is the shorter tail")

    def test_open_ends_on_a_rising_tone_and_close_starts_on_a_falling_one(self) -> None:
        opened, closed = self.wav("radio_open"), self.wav("radio_close")
        tail = opened[int(0.09 * SR) : int(0.19 * SR)]
        half = len(tail) // 2
        self.assertGreater(dominant_hz(tail[half:]), 1.1 * dominant_hz(tail[:half]), "open: the key-up chirp rises")
        head = closed[: int(0.07 * SR)]
        half = len(head) // 2
        self.assertLess(dominant_hz(head[half:]), dominant_hz(head[:half]) / 1.1, "close: the key-down chirp falls")

    def test_the_static_comes_from_the_seed(self) -> None:
        other = Path(self._tmp.name) / "other"
        sfx_ui.build(BuildContext(other, seed=7))
        for name in RADIO:
            self.assertFalse(np.array_equal(self.wav(name), audio.read_wav(other / f"{name}.wav")[0]), name)

    def test_same_seed_gives_byte_identical_files(self) -> None:
        for name in EXPECTED:
            self.assertEqual((self.dir_a / f"{name}.wav").read_bytes(), (self.dir_b / f"{name}.wav").read_bytes(), name)
        self.assertEqual((self.dir_a / "manifest.json").read_bytes(), (self.dir_b / "manifest.json").read_bytes())


if __name__ == "__main__":
    unittest.main()
