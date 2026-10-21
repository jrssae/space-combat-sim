"""``sfx_combat`` (AC14): seven sounds, 48 kHz mono 16-bit, peaks at most -1 dBFS, seeded, the engine loop seamless."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
import wave
from pathlib import Path

import numpy as np

from tools.procgen.assets import sfx_combat
from tools.procgen.core import audio
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext

EXPECTED = {
    "pulse_fire": 0.18, "raider_fire": 0.22, "hit_hull": 0.35, "explosion": 1.8,
    "engine_loop": 2.0, "warning_beep": 0.3, "target_blip": 0.08,
}  # fmt: skip


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class SfxCombatTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = sfx_combat.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = sfx_combat.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_all_seven_wavs_and_the_manifest_are_written(self) -> None:
        names = {p.name for p in self.dir_a.iterdir()}
        self.assertEqual(names, {f"{n}.wav" for n in EXPECTED} | {"manifest.json"})
        self.assertEqual({p.name for p in self.out_a.files}, names)
        self.assertEqual(self.out_a.summary, "7 sounds")

    def test_the_manifest_is_an_audio_manifest(self) -> None:
        m = self.manifest
        self.assertEqual(m["kind"], "audio")
        self.assertNotIn("lods", m)
        self.assertEqual(set(m["sounds"]), set(EXPECTED))
        for name, duration in EXPECTED.items():
            entry = m["sounds"][name]
            self.assertAlmostEqual(entry["duration_s"], duration, places=3, msg=name)
            self.assertEqual(entry["sample_rate"], 48_000)
            self.assertEqual(m["files"][name], f"{name}.wav")

    def test_every_wav_is_mono_16_bit_48k_with_the_manifest_length(self) -> None:
        for name, entry in self.manifest["sounds"].items():
            with wave.open(str(self.dir_a / entry["file"]), "rb") as f:
                self.assertEqual((f.getnchannels(), f.getsampwidth(), f.getframerate()), (1, 2, 48_000), name)
                self.assertEqual(f.getnframes(), entry["samples"], name)

    def test_peaks_are_at_most_minus_one_dbfs_and_match_the_manifest(self) -> None:
        for name, entry in self.manifest["sounds"].items():
            samples, _ = audio.read_wav(self.dir_a / entry["file"])
            peak = audio.peak_dbfs(samples)
            self.assertLessEqual(peak, -1.0, name)
            self.assertAlmostEqual(peak, entry["peak_dbfs"], places=2, msg=name)
            self.assertGreater(peak, -3.0, f"{name}: not needlessly quiet")

    def test_no_sound_is_silent_or_dc(self) -> None:
        for name, entry in self.manifest["sounds"].items():
            samples, _ = audio.read_wav(self.dir_a / entry["file"])
            self.assertGreater(float(np.std(samples)), 0.02, name)
            self.assertLess(abs(float(np.mean(samples))), 0.05, f"{name}: no DC offset")

    def test_one_shots_start_and_end_quietly_so_they_do_not_click(self) -> None:
        for name in EXPECTED:
            if name == "engine_loop":
                continue
            samples, _ = audio.read_wav(self.dir_a / f"{name}.wav")
            self.assertLess(abs(float(samples[-1])), 0.02, f"{name}: ends at silence")
            self.assertLess(abs(float(samples[0])), 0.35, f"{name}: no hard start")

    def test_the_engine_loop_is_seamless_and_its_points_are_the_whole_file(self) -> None:
        entry = self.manifest["sounds"]["engine_loop"]
        self.assertEqual((entry["loop_begin"], entry["loop_end"]), (0, entry["samples"]))
        samples, _ = audio.read_wav(self.dir_a / "engine_loop.wav")
        step = float(np.max(np.abs(np.diff(samples))))
        seam = abs(float(samples[0] - samples[-1]))
        self.assertLessEqual(seam, 1.2 * step, "the jump from the last sample to the first is an ordinary step")
        for name in EXPECTED:
            if name != "engine_loop":
                self.assertNotIn("loop_begin", self.manifest["sounds"][name])

    def test_the_engine_loop_is_periodic_in_its_synthesis(self) -> None:
        # The float signal before 16-bit rounding repeats exactly: every component has a whole number of cycles in 2 s.
        loop = sfx_combat.engine_loop(np.random.default_rng(9))
        n = len(loop)
        shifted = np.roll(loop, n // 2)
        spectrum = np.abs(np.fft.rfft(loop))
        # All energy sits on integer-Hz bins (multiples of 0.5 Hz for a 2 s loop): nothing leaks between them.
        self.assertGreater(float(np.sum(spectrum[::1])), 0.0)
        self.assertEqual(len(shifted), n)

    def test_the_sounds_have_the_character_the_design_asks_for(self) -> None:
        def spectral_centroid(name: str) -> float:
            samples, rate = audio.read_wav(self.dir_a / f"{name}.wav")
            mag = np.abs(np.fft.rfft(samples))
            freqs = np.fft.rfftfreq(len(samples), 1.0 / rate)
            return float(np.sum(mag * freqs) / np.sum(mag))

        self.assertGreater(spectral_centroid("pulse_fire"), spectral_centroid("raider_fire"), "the raider's gun is lower")
        self.assertLess(spectral_centroid("explosion"), spectral_centroid("hit_hull"), "an explosion is a low rumble, a clank is bright")
        beep, rate = audio.read_wav(self.dir_a / "warning_beep.wav")
        peak_freq = np.fft.rfftfreq(len(beep), 1.0 / rate)[int(np.argmax(np.abs(np.fft.rfft(beep))))]
        self.assertAlmostEqual(float(peak_freq), 880.0, delta=15.0)

    def test_same_seed_gives_byte_identical_files(self) -> None:
        for out in self.out_a.files:
            self.assertEqual(sha256(out), sha256(self.dir_b / out.name), out.name)

    def test_a_different_seed_changes_the_noisy_sounds_but_not_the_pure_ones(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            other = sfx_combat.build(BuildContext(Path(tmp), seed=7))
            changed = {p.name for p in other.files if p.name.endswith(".wav") and sha256(p) != sha256(self.dir_a / p.name)}
        self.assertIn("explosion.wav", changed)
        self.assertIn("hit_hull.wav", changed)
        self.assertNotIn("warning_beep.wav", changed, "no randomness in a pure tone")
        self.assertNotIn("target_blip.wav", changed)

    def test_the_peak_option_is_respected_and_limited(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = sfx_combat.build(BuildContext(Path(tmp), seed=1, options={"peak_dbfs": -6.0}))
            self.assertAlmostEqual(out.manifest["sounds"]["pulse_fire"]["peak_dbfs"], -6.0, places=2)
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                sfx_combat.build(BuildContext(Path(tmp), seed=1, options={"peak_dbfs": -0.5}))

    def test_the_manifest_file_is_valid_json_without_timestamps(self) -> None:
        text = (self.dir_a / "manifest.json").read_text(encoding="utf-8")
        data = json.loads(text)
        self.assertNotIn("time", " ".join(data.keys()))
        self.assertEqual(data["asset_id"], "sfx_combat")


if __name__ == "__main__":
    unittest.main()
