"""``sfx_combat`` (AC14 of M2, AC15 of M5): eight sounds, 48 kHz mono 16-bit, peaks at most -1 dBFS, seeded, the engine loop
seamless; the guns and the impact keep the shapes measured from the reference (docs/design-references.md "Combat sounds")."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
import wave
from pathlib import Path
from typing import NamedTuple

import numpy as np

from tools.procgen.assets import sfx_combat
from tools.procgen.core import audio
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext

EXPECTED = {
    "pulse_fire": 0.105, "raider_fire": 0.15, "hit_hull": 0.14, "explosion": 1.8,
    "engine_loop": 2.0, "thruster_loop": 2.0, "warning_beep": 0.3, "target_blip": 0.08,
}  # fmt: skip


SR = audio.SAMPLE_RATE


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# --- measures of a sound's shape (M5-T18) ------------------------------------------------------------------------------
class Shot(NamedTuple):
    attack_s: float  # until the level is within 1 dB of the hold
    hold_s: float  # how long it stays there
    hold_end_s: float
    cut_s: float  # from the end of the hold to 30 dB under it, or to the end of the file
    flatness_db: float  # spread of the 5 ms levels inside the hold


def frame_levels(samples: np.ndarray, frame_s: float) -> np.ndarray:
    """The RMS level (dB re full scale) of consecutive frames."""
    n = int(round(frame_s * SR))
    frames = samples[: len(samples) // n * n].reshape(-1, n)
    return 20.0 * np.log10(np.maximum(np.sqrt(np.mean(frames**2, axis=1)), 1e-12))


def shot_shape(samples: np.ndarray) -> Shot:
    """Attack, hold and cut of a held shot, read off a 1 ms envelope; the hold level is its median over 20-80 ms."""
    env = frame_levels(samples, 0.001)
    level = float(np.median(env[20:80]))
    within = np.nonzero(env >= level - 1.0)[0]
    start, end = int(within[0]), int(within[-1]) + 1
    quiet = np.nonzero(env[end:] <= level - 30.0)[0]
    cut_end = end + int(quiet[0]) if len(quiet) else len(samples) / SR * 1000.0
    inside = frame_levels(samples[int(0.010 * SR) : (end - 5) * SR // 1000], 0.005)
    flatness = float(inside.max() - inside.min())
    return Shot(start / 1000.0, (end - start) / 1000.0, end / 1000.0, (cut_end - end) / 1000.0, flatness)


def spectrum_peaks(samples: np.ndarray, floor_db: float) -> list[tuple[float, float]]:
    """Spectral peaks within ``floor_db`` of the strongest, as (Hz, dB re the strongest), strongest first. A Hann window,
    16 times zero padding and a parabolic fit on the log magnitude place each peak to a fraction of a hertz."""
    n = 16 * len(samples)
    mag = np.abs(np.fft.rfft(samples * np.hanning(len(samples)), n))
    log = np.log(np.maximum(mag, 1e-30))
    i = np.nonzero((mag[1:-1] > mag[:-2]) & (mag[1:-1] >= mag[2:]))[0] + 1
    i = i[mag[i] >= mag.max() * 10.0 ** (floor_db / 20.0)]
    offset = 0.5 * (log[i - 1] - log[i + 1]) / (log[i - 1] - 2.0 * log[i] + log[i + 1])
    peaks = sorted(zip((i + offset) * SR / n, 20.0 * np.log10(mag[i] / mag.max())), key=lambda p: -p[1])
    return [(float(f), float(level)) for f, level in peaks]


def harmonic_misfit(freqs: list[float], lowest_f0: float = 40.0) -> float:
    """How far the partials are from the best harmonic series whose fundamental is at least ``lowest_f0``: the distance of the
    worst-placed partial from its nearest harmonic, in fundamentals. 0 is harmonic, 0.5 as far off as a partial can be."""
    f = np.asarray(freqs)
    f0 = lowest_f0 * np.exp(np.arange(0.0, np.log(f.max() / lowest_f0), 2e-5))
    ratios = f[None, :] / f0[:, None]
    return float(np.min(np.max(np.abs(ratios - np.round(ratios)), axis=1)))


def power_spectrum(samples: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    n = 8 * len(samples)
    return np.fft.rfftfreq(n, 1.0 / SR), np.abs(np.fft.rfft(samples, n)) ** 2


def band_share(samples: np.ndarray, low_hz: float, high_hz: float) -> float:
    """The fraction of the sound's energy between ``low_hz`` and ``high_hz``."""
    freqs, power = power_spectrum(samples)
    return float(power[(freqs >= low_hz) & (freqs < high_hz)].sum() / power.sum())


def energy_median(samples: np.ndarray) -> float:
    """The frequency below which half the energy lies (a click's broadband noise would swamp a spectral centroid)."""
    freqs, power = power_spectrum(samples)
    return float(freqs[np.searchsorted(np.cumsum(power) / power.sum(), 0.5)])


def power_centroid(samples: np.ndarray) -> float:
    freqs, power = power_spectrum(samples * np.hanning(len(samples)))
    return float(np.sum(freqs * power) / np.sum(power))


def high_band_energy(samples: np.ndarray, start_s: float, end_s: float) -> float:
    """Energy above 3.5 kHz in a window: the click's noise reaches there, the guns' partials do not."""
    high = audio.highpass(samples, 3500.0, order=8)
    return float(np.sum(high[int(round(start_s * SR)) : int(round(end_s * SR))] ** 2))


def onsets(samples: np.ndarray) -> int:
    """How many times the 2 ms level jumps by 10 dB within 6 ms (silence before the file counts)."""
    env = np.concatenate([np.full(3, -120.0), frame_levels(samples, 0.002)])
    rising = env[3:] - env[:-3] >= 10.0
    return int(rising[0]) + int(np.sum(rising[1:] & ~rising[:-1]))


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

    def test_all_eight_wavs_and_the_manifest_are_written(self) -> None:
        names = {p.name for p in self.dir_a.iterdir()}
        self.assertEqual(names, {f"{n}.wav" for n in EXPECTED} | {"manifest.json"})
        self.assertEqual({p.name for p in self.out_a.files}, names)
        self.assertEqual(self.out_a.summary, "8 sounds")

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
            if name in ("engine_loop", "thruster_loop"):
                continue
            samples, _ = audio.read_wav(self.dir_a / f"{name}.wav")
            self.assertLess(abs(float(samples[-1])), 0.02, f"{name}: ends at silence")
            self.assertLess(abs(float(samples[0])), 0.35, f"{name}: no hard start")

    def test_the_engine_loop_is_seamless_and_its_points_are_the_whole_file(self) -> None:
        entry = self.manifest["sounds"]["engine_loop"]
        self.assertEqual((entry["loop_begin"], entry["loop_end"]), (0, entry["samples"]))
        for name in ("engine_loop", "thruster_loop"):
            samples, _ = audio.read_wav(self.dir_a / f"{name}.wav")
            step = float(np.max(np.abs(np.diff(samples))))
            seam = abs(float(samples[0] - samples[-1]))
            self.assertLessEqual(seam, 1.2 * step, f"{name}: the jump from the last sample to the first is an ordinary step")
        for name in EXPECTED:
            if name not in ("engine_loop", "thruster_loop"):
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
        # Measured as the energy median: the explosion's crackle and noise would swamp a spectral centroid.
        boom, clank = (audio.read_wav(self.dir_a / f"{name}.wav")[0] for name in ("explosion", "hit_hull"))
        self.assertLess(energy_median(boom), 0.25 * energy_median(clank), "an explosion is a low rumble, a clank bright")
        self.assertLess(spectral_centroid("engine_loop"), 150.0, "the engine is a low rumble")
        self.assertLess(spectral_centroid("engine_loop"), spectral_centroid("thruster_loop"), "the thrusters are brighter than the engine")
        beep, rate = audio.read_wav(self.dir_a / "warning_beep.wav")
        peak_freq = np.fft.rfftfreq(len(beep), 1.0 / rate)[int(np.argmax(np.abs(np.fft.rfft(beep))))]
        self.assertAlmostEqual(float(peak_freq), 880.0, delta=15.0)

    def test_the_guns_and_the_impact_are_two_octaves_below_their_design(self) -> None:
        # M3-T15 (Q17), kept by M5 (D60): every frequency a quarter of the design's, the length unchanged (not a resample).
        self.assertEqual(sfx_combat.GUN_PITCH, 0.25)
        for make in (sfx_combat.pulse_fire, sfx_combat.raider_fire, sfx_combat.hit_hull):
            low = make(np.random.default_rng(3))
            design = make(np.random.default_rng(3), pitch=1.0)
            self.assertEqual(len(low), len(design), make.__name__)
            ratio = energy_median(low) / energy_median(design)
            self.assertTrue(0.24 <= ratio <= 0.26, (make.__name__, ratio))
        hold = slice(int(0.010 * SR), int(0.095 * SR))
        for make in (sfx_combat.pulse_fire, sfx_combat.raider_fire):
            low = spectrum_peaks(make(np.random.default_rng(3))[hold], -10.0)
            design = [f for f, _ in spectrum_peaks(make(np.random.default_rng(3), pitch=1.0)[hold], -40.0)]
            for f, _ in low:  # every strong partial sits at four times its frequency in the design
                nearest = min(design, key=lambda d, f=f: abs(d - 4.0 * f))
                self.assertAlmostEqual(nearest / (4.0 * f), 1.0, delta=0.005, msg=(make.__name__, f))
        # Designed near the reference: the Starfury's main tone before the register is within 5 % of its 4.79 kHz.
        design = sfx_combat.pulse_fire(np.random.default_rng(3), pitch=1.0)[hold]
        self.assertAlmostEqual(spectrum_peaks(design, -1.0)[0][0], 4790.0, delta=0.05 * 4790.0)

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


class GunAndImpactShapeTests(unittest.TestCase):
    """M5-T18 (AC15, D60): the shapes the reference measured, in numbers. The reference's figures are before the register;
    every frequency here is a quarter of them (``GUN_PITCH``)."""

    @classmethod
    def setUpClass(cls) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sfx_combat.build(BuildContext(Path(tmp), seed=42))
            cls.wav = {name: audio.read_wav(Path(tmp) / f"{name}.wav")[0] for name in ("pulse_fire", "raider_fire", "hit_hull")}
        cls.shot = {name: shot_shape(cls.wav[name]) for name in ("pulse_fire", "raider_fire")}

    def _hold(self, name: str) -> np.ndarray:
        return self.wav[name][int(0.010 * SR) : int((self.shot[name].hold_end_s - 0.005) * SR)]

    def test_the_starfury_shot_holds_flat_for_about_100_ms_then_cuts_hard(self) -> None:
        # Reference: attack under 10 ms, a flat hold of 95-105 ms, then the next shot cuts in.
        shot = self.shot["pulse_fire"]
        self.assertLessEqual(shot.attack_s, 0.005)
        self.assertTrue(0.090 <= shot.hold_s <= 0.110, shot)
        self.assertLessEqual(shot.flatness_db, 1.0, "flat, not a decay")
        self.assertLessEqual(shot.cut_s, 0.008, "a hard cut")

    def test_the_raider_shot_is_built_the_same_way_with_a_longer_hold_and_a_softer_cut(self) -> None:
        shot, starfury = self.shot["raider_fire"], self.shot["pulse_fire"]
        self.assertLessEqual(shot.attack_s, 0.005)
        self.assertTrue(0.110 <= shot.hold_s <= 0.135, shot)
        self.assertLessEqual(shot.flatness_db, 1.0)
        self.assertTrue(0.012 <= shot.cut_s <= 0.040, shot)
        self.assertGreaterEqual(shot.cut_s, 2.0 * starfury.cut_s, "a different cut from the Starfury's")

    def test_each_shot_opens_with_a_click(self) -> None:
        for name, shot in self.shot.items():
            click = high_band_energy(self.wav[name], 0.0, 0.003)
            starts = np.arange(0.010, shot.hold_end_s - 0.008, 0.003)
            held = max(high_band_energy(self.wav[name], s, s + 0.003) for s in starts)
            self.assertGreaterEqual(click, 4.0 * held, f"{name}: broadband at the attack, tonal in the hold")

    def test_the_pitch_holds_still_through_a_shot(self) -> None:
        # Reference: constant within 10 Hz across a shot, 2.5 Hz after the register; no falling sweep.
        for name in self.shot:
            hold = self._hold(name)
            early, late = hold[: len(hold) // 2], hold[len(hold) // 2 :]
            main = spectrum_peaks(early, -1.0)[0][0]
            later = min((f for f, _ in spectrum_peaks(late, -40.0)), key=lambda f: abs(f - main))
            self.assertLessEqual(abs(later - main), 2.5, name)
            self.assertAlmostEqual(power_centroid(late) / power_centroid(early), 1.0, delta=0.01, msg=name)

    def test_the_starfury_gun_sits_in_the_reference_band_after_the_register(self) -> None:
        # Reference: main tone 4.79 kHz, most energy at 4-6.5 kHz, more at 2.5-4 and 6.5-10 kHz, none below 1 kHz.
        pulse = self.wav["pulse_fire"]
        self.assertAlmostEqual(spectrum_peaks(self._hold("pulse_fire"), -1.0)[0][0], 1200.0, delta=60.0)
        bands = [band_share(pulse, lo, hi) for lo, hi in ((625.0, 1000.0), (1000.0, 1625.0), (1625.0, 2500.0))]
        self.assertEqual(int(np.argmax(bands)), 1, bands)
        self.assertGreaterEqual(bands[1], 0.5)
        self.assertGreaterEqual(sum(bands), 0.9)
        self.assertLessEqual(band_share(pulse, 0.0, 250.0), 0.01, "no thump")

    def test_the_raider_gun_is_lower_and_buzzier(self) -> None:
        raider, pulse = self.wav["raider_fire"], self.wav["pulse_fire"]
        self.assertLess(energy_median(raider), 0.7 * energy_median(pulse))
        main = {name: spectrum_peaks(self._hold(name), -1.0)[0][0] for name in self.shot}
        self.assertLess(main["raider_fire"], main["pulse_fire"])
        dense = len(spectrum_peaks(self._hold("raider_fire"), -10.0))
        self.assertGreaterEqual(dense, 2 * len(spectrum_peaks(self._hold("pulse_fire"), -10.0)), "a denser, buzzier cluster")
        self.assertGreaterEqual(band_share(raider, 250.0, 1625.0), 0.85)
        self.assertLessEqual(band_share(raider, 0.0, 150.0), 0.02, "no thump")

    def test_the_partials_are_inharmonic(self) -> None:
        # The measure reads 0 for a harmonic cluster: the same FM with a ratio of exactly 3.
        t = audio.time_axis(0.085)
        harmonic = audio.fm(t, 7.0 * 165.0, ((3.0 * 165.0, 0.8), (165.0, 0.9)))
        self.assertLess(harmonic_misfit([f for f, _ in spectrum_peaks(harmonic, -16.0)]), 0.01)
        for name in self.shot:
            partials = [f for f, _ in spectrum_peaks(self._hold(name), -16.0)]
            self.assertGreaterEqual(len(partials), 6, name)
            self.assertGreaterEqual(harmonic_misfit(partials), 0.05, name)
        strike = [f for f, _ in spectrum_peaks(self.wav["hit_hull"][int(0.003 * SR) : int(0.060 * SR)], -16.0)]
        self.assertGreaterEqual(harmonic_misfit(strike), 0.05, "the hit rings like metal")

    def test_a_sound_is_one_attack_with_no_burst_rhythm(self) -> None:
        # The guns follow the cannon's own rate of fire: one shot per bolt.
        for name, samples in self.wav.items():
            self.assertEqual(onsets(samples), 1, name)

    def test_the_hit_is_short_bright_and_metallic(self) -> None:
        hit = self.wav["hit_hull"]
        self.assertLessEqual(len(hit) / SR, 0.15)
        env = frame_levels(hit, 0.002)
        loudest = int(np.argmax(env))
        fallen = np.nonzero(env[loudest:] <= env[loudest] - 30.0)[0]
        self.assertTrue(len(fallen) > 0 and fallen[0] * 0.002 <= 0.110, "30 dB down within 110 ms")
        self.assertGreaterEqual(band_share(hit, 250.0, 4000.0), 0.85)
        self.assertLessEqual(band_share(hit, 0.0, 150.0), 0.01, "no low body: that is the explosion's")
        self.assertTrue(1000.0 <= energy_median(hit) <= 2000.0, energy_median(hit))


if __name__ == "__main__":
    unittest.main()
