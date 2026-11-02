"""``core/audio``: envelopes, oscillators, filters, levels and the WAV writer; plus the audio manifest kind."""

from __future__ import annotations

import tempfile
import unittest
import wave
from pathlib import Path

import numpy as np

from tools.procgen.core import audio, manifest


def _at(seconds: float) -> int:
    return int(round(seconds * audio.SAMPLE_RATE))


class EnvelopeTests(unittest.TestCase):
    def test_time_axis_length_and_step(self) -> None:
        t = audio.time_axis(0.5)
        self.assertEqual(len(t), 24_000)
        self.assertAlmostEqual(float(t[1] - t[0]), 1.0 / audio.SAMPLE_RATE)

    def test_exp_decay_is_one_then_one_over_e(self) -> None:
        t = np.array([0.0, 0.1])
        np.testing.assert_allclose(audio.exp_decay(t, 0.1), [1.0, np.exp(-1.0)])

    def test_attack_decay_rises_then_falls(self) -> None:
        t = audio.time_axis(0.2)
        env = audio.attack_decay(t, 0.01, 0.05)
        self.assertEqual(float(env[0]), 0.0)
        self.assertAlmostEqual(float(env[int(0.01 * audio.SAMPLE_RATE)]), 1.0, places=3)
        self.assertGreater(float(env[int(0.01 * audio.SAMPLE_RATE)]), float(env[-1]))

    def test_fade_zeroes_the_ends_and_leaves_the_middle(self) -> None:
        out = audio.fade(np.ones(1000), 0.001, 0.001)
        self.assertEqual(float(out[0]), 0.0)
        self.assertEqual(float(out[-1]), 0.0)
        self.assertEqual(float(out[500]), 1.0)

    def test_hold_and_cut_rises_holds_flat_then_cuts_to_silence(self) -> None:
        t = audio.time_axis(0.12)
        env = audio.hold_and_cut(t, 0.002, 0.100, 0.005)
        self.assertEqual(float(env[0]), 0.0)
        self.assertAlmostEqual(float(env[_at(0.001)]), 0.5)
        np.testing.assert_allclose(env[_at(0.002) : _at(0.100) + 1], 1.0)
        self.assertAlmostEqual(float(env[_at(0.1025)]), 0.5)
        self.assertTrue(np.all(np.diff(env[_at(0.100) : _at(0.105)]) < 0.0), "the cut only falls")
        np.testing.assert_allclose(env[_at(0.105) :], 0.0, atol=1e-12)

    def test_hold_and_release_falls_exponentially_after_the_hold(self) -> None:
        t = audio.time_axis(0.2)
        env = audio.hold_and_release(t, 0.002, 0.120, 0.006)
        self.assertEqual(float(env[0]), 0.0)
        np.testing.assert_allclose(env[_at(0.002) : _at(0.120) + 1], 1.0)
        self.assertAlmostEqual(float(env[_at(0.126)]), np.exp(-1.0), places=6)
        self.assertTrue(np.all(np.diff(env[_at(0.120) :]) < 0.0))


class OscillatorTests(unittest.TestCase):
    def test_a_sine_of_a_steady_frequency_has_its_period(self) -> None:
        phase = audio.phase_from_frequency(np.full(audio.SAMPLE_RATE, 480.0))
        wave_ = audio.sine(phase)
        crossings = np.sum((wave_[:-1] < 0) & (wave_[1:] >= 0))
        self.assertAlmostEqual(float(crossings), 480.0, delta=1.5)

    def test_sweep_goes_from_start_to_end(self) -> None:
        t = audio.time_axis(1.0)
        f = audio.sweep(t, 1000.0, 100.0, 1.0)
        self.assertAlmostEqual(float(f[0]), 1000.0)
        self.assertAlmostEqual(float(f[-1]), 100.0, delta=0.05)
        self.assertTrue(np.all(np.diff(f) < 0.0))

    def test_saw_and_square_stay_in_range(self) -> None:
        phase = audio.phase_from_frequency(np.full(4800, 300.0))
        for shape in (audio.saw(phase), audio.square(phase)):
            self.assertLessEqual(float(np.max(np.abs(shape))), 1.0)


class FmTests(unittest.TestCase):
    # One second at whole-hertz frequencies: every partial falls on its own FFT bin, so its amplitude reads exactly.
    @staticmethod
    def _amplitudes(samples: np.ndarray) -> np.ndarray:
        return np.abs(np.fft.rfft(samples)) / (len(samples) / 2.0)

    def test_without_modulators_it_is_a_sine_at_the_carrier(self) -> None:
        t = audio.time_axis(1.0)
        np.testing.assert_allclose(audio.fm(t, 440.0, ()), np.sin(2.0 * np.pi * 440.0 * t), atol=1e-12)

    def test_one_modulator_gives_sidebands_with_bessel_amplitudes(self) -> None:
        amp = self._amplitudes(audio.fm(audio.time_axis(1.0), 1000.0, ((200.0, 1.0),)))
        self.assertAlmostEqual(float(amp[1000]), 0.7651977, places=5)  # J0(1)
        for sideband in (800, 1200):
            self.assertAlmostEqual(float(amp[sideband]), 0.4400506, places=5)  # J1(1)
        for sideband in (600, 1400):
            self.assertAlmostEqual(float(amp[sideband]), 0.1149035, places=5)  # J2(1)
        self.assertLess(float(amp[1100]), 1e-9, "nothing between the sidebands")

    def test_two_modulators_add_their_cross_sidebands(self) -> None:
        amp = self._amplitudes(audio.fm(audio.time_axis(1.0), 1000.0, ((200.0, 1.0), (37.0, 0.5))))
        self.assertAlmostEqual(float(amp[1000 + 200 - 37]), 0.4400506 * 0.2422685, places=5)  # J1(1) J1(0.5)
        self.assertAlmostEqual(float(amp[1000]), 0.7651977 * 0.9384698, places=5)  # J0(1) J0(0.5)

    def test_the_amplitude_is_constant_and_a_time_varying_index_is_accepted(self) -> None:
        t = audio.time_axis(0.5)
        out = audio.fm(t, 900.0, ((1270.0, 3.0 * np.exp(-t / 0.05)),))
        self.assertLessEqual(float(np.max(np.abs(out))), 1.0)
        self.assertAlmostEqual(float(np.sqrt(np.mean(out**2))), np.sqrt(0.5), places=2)


class FilterTests(unittest.TestCase):
    def test_lowpass_keeps_a_low_tone_and_kills_a_high_one(self) -> None:
        t = audio.time_axis(0.5)
        low, high = np.sin(2 * np.pi * 200 * t), np.sin(2 * np.pi * 12000 * t)
        self.assertGreater(float(np.std(audio.lowpass(low, 2000.0))), 0.9 * float(np.std(low)))
        self.assertLess(float(np.std(audio.lowpass(high, 2000.0))), 0.05 * float(np.std(high)))

    def test_highpass_is_the_mirror_image(self) -> None:
        t = audio.time_axis(0.5)
        low, high = np.sin(2 * np.pi * 100 * t), np.sin(2 * np.pi * 8000 * t)
        self.assertLess(float(np.std(audio.highpass(low, 2000.0))), 0.05 * float(np.std(low)))
        self.assertGreater(float(np.std(audio.highpass(high, 2000.0))), 0.9 * float(np.std(high)))

    def test_noise_is_deterministic_for_a_seed_and_bounded(self) -> None:
        a = audio.white_noise(np.random.default_rng(3), 1000)
        b = audio.white_noise(np.random.default_rng(3), 1000)
        np.testing.assert_array_equal(a, b)
        self.assertLessEqual(float(np.max(np.abs(a))), 1.0)

    def test_periodic_noise_repeats_exactly(self) -> None:
        n = 9600
        noise = audio.periodic_noise(np.random.default_rng(1), n, 10, 400)
        both = np.concatenate([noise, noise])
        spectrum = np.abs(np.fft.rfft(noise))
        self.assertLess(float(np.max(spectrum[:10])), 1e-6)  # nothing below the first bin
        self.assertAlmostEqual(float(np.max(np.abs(noise))), 1.0, places=6)
        # The seam between the end and the start is as smooth as anywhere else in the signal.
        seam = abs(float(both[n] - both[n - 1]))
        typical = float(np.max(np.abs(np.diff(noise))))
        self.assertLessEqual(seam, typical + 1e-12)


    def test_shaped_periodic_noise_repeats_and_follows_its_gain(self) -> None:
        n = 9600  # 0.2 s: bins every 5 Hz
        noise = audio.shaped_periodic_noise(np.random.default_rng(2), n, lambda f: np.where(f < 1000.0, 1.0, 0.1))
        power = np.abs(np.fft.rfft(noise)) ** 2
        freqs = np.fft.rfftfreq(n, 1.0 / audio.SAMPLE_RATE)
        low, high = power[(freqs > 0) & (freqs < 1000.0)].mean(), power[freqs >= 1000.0].mean()
        self.assertAlmostEqual(10.0 * np.log10(low / high), 20.0, places=6)  # every bin carries exactly its gain
        self.assertLess(float(power[0]), 1e-12, "no DC")
        self.assertAlmostEqual(float(np.max(np.abs(noise))), 1.0, places=6)
        both = np.concatenate([noise, noise])
        self.assertLessEqual(abs(float(both[n] - both[n - 1])), float(np.max(np.abs(np.diff(noise)))) + 1e-12)


class LevelAndFileTests(unittest.TestCase):
    def test_peak_dbfs_and_normalise(self) -> None:
        samples = np.array([0.0, 0.25, -0.5])
        self.assertAlmostEqual(audio.peak_dbfs(samples), 20 * np.log10(0.5))
        out = audio.normalize_peak(samples, -3.0)
        self.assertAlmostEqual(audio.peak_dbfs(out), -3.0, places=6)
        self.assertEqual(audio.peak_dbfs(np.zeros(4)), -float("inf"))
        self.assertEqual(float(np.max(np.abs(audio.normalize_peak(np.zeros(4), -3.0)))), 0.0)

    def test_int16_conversion_clips_and_rounds(self) -> None:
        pcm = audio.to_int16(np.array([0.0, 1.0, -1.0, 2.0, -2.0, 0.5]))
        self.assertEqual(pcm.tolist(), [0, 32767, -32767, 32767, -32767, 16384])
        self.assertEqual(pcm.dtype, np.dtype("<i2"))

    def test_the_wav_is_mono_16_bit_48k_and_reads_back(self) -> None:
        samples = 0.5 * np.sin(2 * np.pi * 440 * audio.time_axis(0.1))
        with tempfile.TemporaryDirectory() as tmp:
            path = audio.write_wav(Path(tmp) / "t.wav", samples)
            with wave.open(str(path), "rb") as f:
                self.assertEqual((f.getnchannels(), f.getsampwidth(), f.getframerate()), (1, 2, 48_000))
                self.assertEqual(f.getnframes(), len(samples))
            back, rate = audio.read_wav(path)
            self.assertEqual(rate, 48_000)
            np.testing.assert_allclose(back, samples, atol=1.0 / 32767)

    def test_equal_input_gives_identical_bytes(self) -> None:
        samples = audio.white_noise(np.random.default_rng(5), 2000)
        with tempfile.TemporaryDirectory() as tmp:
            a = audio.write_wav(Path(tmp) / "a.wav", samples).read_bytes()
            b = audio.write_wav(Path(tmp) / "b.wav", samples).read_bytes()
        self.assertEqual(a, b)


class AudioManifestTests(unittest.TestCase):
    def _sounds(self) -> dict:
        return {
            "beep": manifest.sound_entry("beep.wav", 4800, 48000, -2.0),
            "loop": manifest.sound_entry("loop.wav", 96000, 48000, -1.5, loop=(0, 96000)),
        }

    def test_an_audio_manifest_has_sounds_and_no_lods(self) -> None:
        m = manifest.build_audio_manifest("sfx", 1, 42, self._sounds())
        self.assertEqual(m["kind"], "audio")
        self.assertNotIn("lods", m)
        self.assertEqual(m["files"], {"beep": "beep.wav", "loop": "loop.wav"})
        self.assertEqual(m["sounds"]["beep"]["duration_s"], 0.1)
        self.assertEqual((m["sounds"]["loop"]["loop_begin"], m["sounds"]["loop"]["loop_end"]), (0, 96000))
        manifest.validate_manifest(m)

    def test_splat_manifests_are_unchanged_and_default_to_the_splat_kind(self) -> None:
        m = manifest.build_manifest("demo", 1, 1, [manifest.lod_entry(0, "d.ply", 1, 1.0)], [0, 0, 0], [0, 0, 0], [0, 0, 0])
        self.assertNotIn("kind", m)
        manifest.validate_manifest({**m, "kind": "splat"})

    def test_bad_audio_manifests_are_rejected(self) -> None:
        good = manifest.build_audio_manifest("sfx", 1, 42, self._sounds())
        bad_cases = {
            "lods present": {**good, "lods": [manifest.lod_entry(0, "x.ply", 1, 1.0)]},
            "no sounds": {**good, "sounds": {}},
            "unknown kind": {**good, "kind": "video"},
            "not a wav": {**good, "sounds": {"a": {**good["sounds"]["beep"], "file": "a.mp3"}}},
            "zero samples": {**good, "sounds": {"a": {**good["sounds"]["beep"], "samples": 0}}},
            "half a loop": {**good, "sounds": {"a": {**good["sounds"]["beep"], "loop_begin": 0}}},
            "loop past the end": {**good, "sounds": {"a": {**good["sounds"]["beep"], "loop_begin": 0, "loop_end": 999999}}},
            "peak not a number": {**good, "sounds": {"a": {**good["sounds"]["beep"], "peak_dbfs": "loud"}}},
        }
        for label, bad in bad_cases.items():
            with self.assertRaises(ValueError, msg=label):
                manifest.validate_manifest(bad)

    def test_extra_keys_cannot_shadow_reserved_ones(self) -> None:
        with self.assertRaises(ValueError):
            manifest.build_audio_manifest("sfx", 1, 42, self._sounds(), extra={"kind": "splat"})


if __name__ == "__main__":
    unittest.main()
