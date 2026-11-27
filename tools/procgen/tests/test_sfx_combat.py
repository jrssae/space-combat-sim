"""``sfx_combat`` (AC14 of M2, AC15 and AC19 of M5, M10-T87): fourteen sounds, 48 kHz mono 16-bit, peaks at most -1 dBFS, one loudness reference (M8-T12), seeded, the engine bursts
seamless; the guns, the impact and the bursts keep the shapes measured from the reference (docs/design-references.md "Combat
sounds")."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
import wave
from pathlib import Path
from typing import NamedTuple

import numpy as np

from tools.procgen.assets import sfx_combat, sfx_gun
from tools.procgen.core import audio, loudness, sound_match
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext

EXPECTED = {
    "pulse_fire": 1.08, "raider_fire": 1.08, "turret_fire": 1.188, "gun_light": 1.296, "gun_medium": 1.512,
    "gun_railgun": 1.35, "gun_heavy": 1.944, "interceptor_fire": 0.075, "hit_hull": 0.14, "explosion": 1.8,
    "main_burst": 4.0, "rcs_burst": 2.0, "warning_beep": 0.3, "target_blip": 0.08,
}  # fmt: skip
LOOPS = ("main_burst", "rcs_burst")
REFERENCE = Path(__file__).resolve().parents[3] / "references" / "starfurybolt.wav"


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


def loop_power(samples: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """The power spectrum of a loop read as one period of a repeating signal (no window, no padding): a seam would spread
    energy across the spectrum, the low end included."""
    return np.fft.rfftfreq(len(samples), 1.0 / SR), np.abs(np.fft.rfft(samples)) ** 2


def loop_share(samples: np.ndarray, low_hz: float, high_hz: float) -> float:
    freqs, power = loop_power(samples)
    return float(power[(freqs >= low_hz) & (freqs < high_hz)].sum() / power.sum())


def octave_shares(samples: np.ndarray, edges: tuple[float, ...]) -> list[float]:
    """The loop's energy share in each octave between consecutive ``edges``."""
    return [loop_share(samples, lo, hi) for lo, hi in zip(edges[:-1], edges[1:])]


def psd_slope(samples: np.ndarray, low_hz: float, high_hz: float) -> float:
    """dB per octave of a straight line through the third-octave band levels (power per hertz) from ``low_hz`` to
    ``high_hz``: the spectrum's tilt."""
    freqs, power = loop_power(samples)
    centres = low_hz * 2.0 ** (np.arange(0, round(3.0 * np.log2(high_hz / low_hz)) + 1) / 3.0)
    levels = [10.0 * np.log10(power[(freqs >= c * 2.0 ** (-1 / 6)) & (freqs < c * 2.0 ** (1 / 6))].mean()) for c in centres]
    return float(np.polyfit(np.log2(centres / low_hz), levels, 1)[0])


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

    def test_all_fourteen_wavs_and_the_manifest_are_written(self) -> None:
        names = {p.name for p in self.dir_a.iterdir()}
        self.assertEqual(names, {f"{n}.wav" for n in EXPECTED} | {"manifest.json"})
        self.assertEqual({p.name for p in self.out_a.files}, names)
        self.assertEqual(self.out_a.summary, "14 sounds")

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

    def test_every_sound_is_at_the_loudness_reference(self) -> None:
        for name, entry in self.manifest["sounds"].items():
            samples, _ = audio.read_wav(self.dir_a / entry["file"])
            level = loudness.loudness_lufs(samples, "loop_begin" in entry)
            self.assertAlmostEqual(level, loudness.TARGET_LUFS, delta=loudness.TOLERANCE_LU, msg=name)
            self.assertAlmostEqual(level, entry["loudness_lufs"], places=2, msg=name)

    def test_no_sound_is_silent_or_dc(self) -> None:
        for name, entry in self.manifest["sounds"].items():
            samples, _ = audio.read_wav(self.dir_a / entry["file"])
            self.assertGreater(float(np.std(samples)), 0.02, name)
            self.assertLess(abs(float(np.mean(samples))), 0.05, f"{name}: no DC offset")

    def test_one_shots_start_and_end_quietly_so_they_do_not_click(self) -> None:
        for name in EXPECTED:
            if name in LOOPS:
                continue
            samples, _ = audio.read_wav(self.dir_a / f"{name}.wav")
            self.assertLess(abs(float(samples[-1])), 0.02, f"{name}: ends at silence")
            self.assertLess(abs(float(samples[0])), 0.35, f"{name}: no hard start")

    def test_the_bursts_are_seamless_loops_over_the_whole_file(self) -> None:
        for name in LOOPS:
            entry = self.manifest["sounds"][name]
            self.assertEqual((entry["loop_begin"], entry["loop_end"]), (0, entry["samples"]), name)
            samples, _ = audio.read_wav(self.dir_a / f"{name}.wav")
            step = float(np.max(np.abs(np.diff(samples))))
            seam = abs(float(samples[0] - samples[-1]))
            self.assertLessEqual(seam, 1.2 * step, f"{name}: the jump from the last sample to the first is an ordinary step")
        for name in EXPECTED:
            if name not in LOOPS:
                self.assertNotIn("loop_begin", self.manifest["sounds"][name])

    def test_the_main_bursts_wander_repeats_with_the_loop(self) -> None:
        # The float signal before 16-bit rounding: the slow level wander is whole cycles of the loop, so it meets itself.
        phases = np.random.default_rng(5).uniform(0.0, 2.0 * np.pi, len(sfx_combat.WANDER_CYCLES))
        ends = sfx_combat.wander_db(np.array([0.0, sfx_combat.MAIN_BURST_S]), phases)
        self.assertAlmostEqual(float(ends[0]), float(ends[1]), places=9)

    def test_the_sounds_have_the_character_the_design_asks_for(self) -> None:
        def spectral_centroid(name: str) -> float:
            samples, rate = audio.read_wav(self.dir_a / f"{name}.wav")
            mag = np.abs(np.fft.rfft(samples))
            freqs = np.fft.rfftfreq(len(samples), 1.0 / rate)
            return float(np.sum(mag * freqs) / np.sum(mag))

        self.assertLess(spectral_centroid("pulse_fire"), spectral_centroid("raider_fire"), "the raider's gun is higher (Q82)")
        # Measured as the energy median: the explosion's crackle and noise would swamp a spectral centroid.
        boom, clank = (audio.read_wav(self.dir_a / f"{name}.wav")[0] for name in ("explosion", "hit_hull"))
        self.assertLess(energy_median(boom), 0.25 * energy_median(clank), "an explosion is a low rumble, a clank bright")
        self.assertLess(spectral_centroid("main_burst"), spectral_centroid("rcs_burst"), "the jets are brighter than the mains")
        beep, rate = audio.read_wav(self.dir_a / "warning_beep.wav")
        peak_freq = np.fft.rfftfreq(len(beep), 1.0 / rate)[int(np.argmax(np.abs(np.fft.rfft(beep))))]
        self.assertAlmostEqual(float(peak_freq), 880.0, delta=15.0)

    def test_the_interceptor_and_the_impact_are_two_octaves_below_their_design(self) -> None:
        # M3-T15 (Q17), kept by M5 (D60): every frequency a quarter of the design's, the length unchanged (not a resample).
        self.assertEqual(sfx_combat.GUN_PITCH, 0.25)
        for make in (sfx_combat.interceptor_fire, sfx_combat.hit_hull):
            low = make(np.random.default_rng(3))
            design = make(np.random.default_rng(3), pitch=1.0)
            self.assertEqual(len(low), len(design), make.__name__)
            ratio = energy_median(low) / energy_median(design)
            self.assertTrue(0.24 <= ratio <= 0.26, (make.__name__, ratio))

    def test_the_interceptor_pulse_is_a_short_light_gun(self) -> None:
        # M5-T21's light turret shot (D61), the interceptors' own sound (M10-T87): a click, then a held FM cluster cut hard.
        pulse = audio.read_wav(self.dir_a / "interceptor_fire.wav")[0]
        shot = shot_shape(pulse)
        self.assertLessEqual(shot.attack_s, 0.005)
        self.assertTrue(0.050 <= shot.hold_s <= 0.070, shot)
        self.assertLessEqual(shot.cut_s, 0.008, "a hard cut")
        click = high_band_energy(pulse, 0.0, 0.003)
        held = max(high_band_energy(pulse, s, s + 0.003) for s in np.arange(0.010, 0.050, 0.003))
        self.assertGreaterEqual(click, 4.0 * held, "a click at the attack")

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

    def test_the_loudness_option_moves_the_target_under_the_peak_ceiling(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = sfx_combat.build(BuildContext(Path(tmp), seed=1, options={"loudness_lufs": -26.0}))
            self.assertAlmostEqual(out.manifest["sounds"]["pulse_fire"]["loudness_lufs"], -26.0, delta=loudness.TOLERANCE_LU)
            self.assertEqual(out.manifest["loudness_target_lufs"], -26.0)
        with tempfile.TemporaryDirectory() as tmp:
            out = sfx_combat.build(BuildContext(Path(tmp), seed=1, options={"loudness_lufs": 0.0}))
            for name, entry in out.manifest["sounds"].items():
                self.assertLessEqual(entry["peak_dbfs"], loudness.PEAK_CEILING_DBFS + 0.01, f"{name}: the ceiling holds")

    def test_the_manifest_file_is_valid_json_without_timestamps(self) -> None:
        text = (self.dir_a / "manifest.json").read_text(encoding="utf-8")
        data = json.loads(text)
        self.assertNotIn("time", " ".join(data.keys()))
        self.assertEqual(data["asset_id"], "sfx_combat")


def gun_centroid(samples: np.ndarray, pitch: float = 1.0) -> float:
    """Spectral centroid from 200 Hz to 11 kHz, both times ``pitch`` (the rumble under it sits at the edge of resolution)."""
    freqs, power = power_spectrum(samples)
    band = (freqs >= 200.0 * pitch) & (freqs <= 11000.0 * pitch)
    return float(np.sum(power[band] * freqs[band]) / np.sum(power[band]))


class GunTests(unittest.TestCase):
    """M10-T87 (Q82): the Starfury's shot, our own match for the reference, and its family for the other guns."""

    @classmethod
    def setUpClass(cls) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sfx_combat.build(BuildContext(Path(tmp), seed=42))
            cls.wav = {name: audio.read_wav(Path(tmp) / f"{name}.wav")[0] for name in sfx_combat.GUNS}
            cls.ref_dir = Path(tmp)

    @unittest.skipUnless(REFERENCE.exists(), "the reference clip is local only (references/, never committed)")
    def test_the_built_shot_passes_the_95_percent_rule(self) -> None:
        reference, rate = audio.read_wav(REFERENCE)
        m = sound_match.compare(reference, self.wav["pulse_fire"], rate)
        self.assertGreaterEqual(m.mel, 0.95)
        self.assertGreaterEqual(m.high, 0.95, "the top in the middle of the shot (the maintainer's A/B, round 2)")
        self.assertGreaterEqual(m.envelope, 0.95)
        self.assertLessEqual(abs(m.length_ratio - 1.0), 0.05)

    def test_every_gun_plays_its_row_of_the_family(self) -> None:
        for name, weapon in sfx_combat.GUNS.items():
            _, stretch, _ = sfx_gun.WEAPONS[weapon]
            self.assertEqual(len(self.wav[name]), round(sfx_gun.DURATION_S * stretch * SR), name)
        self.assertNotIn("particle", " ".join(sfx_combat.GUNS.values()), "particle cannons keep the beam sound")

    def test_the_raider_shot_is_three_semitones_up_and_as_long(self) -> None:
        raider, starfury = self.wav["raider_fire"], self.wav["pulse_fire"]
        self.assertEqual(len(raider), len(starfury))
        up = 2.0 ** (3.0 / 12.0)
        self.assertAlmostEqual(gun_centroid(raider, up) / gun_centroid(starfury), up, delta=0.05)

    def test_the_bigger_the_gun_the_lower(self) -> None:
        order = ["raider_fire", "pulse_fire", "turret_fire", "gun_light", "gun_medium", "gun_railgun", "gun_heavy"]
        medians = [gun_centroid(self.wav[name]) for name in order]
        for (a, fa), (b, fb) in zip(zip(order, medians), zip(order[1:], medians[1:])):
            self.assertGreater(fa, fb, f"{a} above {b}")


class ImpactShapeTests(unittest.TestCase):
    """M5-T18 (AC15, D60): the hit's shape, in numbers; its frequencies a quarter of the design (``GUN_PITCH``)."""

    @classmethod
    def setUpClass(cls) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sfx_combat.build(BuildContext(Path(tmp), seed=42))
            cls.hit = audio.read_wav(Path(tmp) / "hit_hull.wav")[0]

    def test_the_hit_rings_like_metal(self) -> None:
        # The measure reads 0 for a harmonic cluster: the same FM with a ratio of exactly 3.
        t = audio.time_axis(0.085)
        harmonic = audio.fm(t, 7.0 * 165.0, ((3.0 * 165.0, 0.8), (165.0, 0.9)))
        self.assertLess(harmonic_misfit([f for f, _ in spectrum_peaks(harmonic, -16.0)]), 0.01)
        strike = [f for f, _ in spectrum_peaks(self.hit[int(0.003 * SR) : int(0.060 * SR)], -16.0)]
        self.assertGreaterEqual(harmonic_misfit(strike), 0.05)

    def test_the_hit_is_one_attack(self) -> None:
        self.assertEqual(onsets(self.hit), 1)

    def test_the_hit_is_short_bright_and_metallic(self) -> None:
        hit = self.hit
        self.assertLessEqual(len(hit) / SR, 0.15)
        env = frame_levels(hit, 0.002)
        loudest = int(np.argmax(env))
        fallen = np.nonzero(env[loudest:] <= env[loudest] - 30.0)[0]
        self.assertTrue(len(fallen) > 0 and fallen[0] * 0.002 <= 0.110, "30 dB down within 110 ms")
        self.assertGreaterEqual(band_share(hit, 250.0, 4000.0), 0.85)
        self.assertLessEqual(band_share(hit, 0.0, 150.0), 0.01, "no low body: that is the explosion's")
        self.assertTrue(1000.0 <= energy_median(hit) <= 2000.0, energy_median(hit))


class EngineBurstTests(unittest.TestCase):
    """M5-T19 (AC15, D60, Q7): per-thruster bursts, bright only, shaped on the reference's roars and swells
    (docs/design-references.md "Roars and pass-bys"). Measured on the files as loops, so a seam would show too."""

    @classmethod
    def setUpClass(cls) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sfx_combat.build(BuildContext(Path(tmp), seed=42))
            cls.wav = {name: audio.read_wav(Path(tmp) / f"{name}.wav")[0] for name in LOOPS}

    def test_the_old_low_loops_are_gone(self) -> None:
        for name in ("engine_loop", "thruster_loop"):
            self.assertNotIn(name, sfx_combat.SOUNDS)
            self.assertFalse(hasattr(sfx_combat, name), name)
        self.assertEqual(set(sfx_combat.LOOPS), set(LOOPS))

    def test_nothing_below_300_hz(self) -> None:
        # Q7: bright bursts only, no rumble under them.
        for name, samples in self.wav.items():
            self.assertLessEqual(loop_share(samples, 0.0, 300.0), 1e-3, name)

    def test_the_main_burst_fills_400_hz_to_16_khz_with_its_peak_at_4_to_8_khz(self) -> None:
        # Reference roar: added noise 400 Hz-16 kHz, the peak at 4-8 kHz, -5 to -7.5 dB per octave above 1 kHz.
        burst = self.wav["main_burst"]
        self.assertGreaterEqual(loop_share(burst, 400.0, 16000.0), 0.98)
        octaves = octave_shares(burst, (500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0))
        self.assertEqual(int(np.argmax(octaves)), 3, octaves)
        self.assertGreaterEqual(octaves[3], 1.3 * sorted(octaves)[-2], "a clear peak, not a tie")
        slope = psd_slope(burst, 1000.0, 16000.0)
        self.assertTrue(-7.5 <= slope <= -5.0, slope)

    def test_the_main_burst_wanders_slowly_by_about_3_db(self) -> None:
        # Reference: held with slow swells of about 3 dB at 0.5-2 Hz, no decay.
        levels = frame_levels(self.wav["main_burst"], 0.1)
        self.assertTrue(2.0 <= float(levels.max() - levels.min()) <= 4.0, levels.max() - levels.min())
        swing = np.abs(np.fft.rfft(levels - levels.mean())) ** 2
        rates = np.fft.rfftfreq(len(levels), 0.1)
        slow = float(swing[(rates >= 0.4) & (rates <= 2.1)].sum() / swing.sum())
        self.assertGreaterEqual(slow, 0.8, "the swing is slow, not a flutter")

    def test_the_rcs_burst_is_brightest_at_6_to_16_khz(self) -> None:
        # Reference swell: added noise 2-16 kHz, the peak at 6-16 kHz.
        burst = self.wav["rcs_burst"]
        self.assertGreaterEqual(loop_share(burst, 2000.0, 16000.0), 0.97)
        self.assertGreaterEqual(loop_share(burst, 6000.0, 16000.0), 0.6)
        octaves = octave_shares(burst, (1000.0, 2000.0, 4000.0, 8000.0, 16000.0))
        self.assertEqual(int(np.argmax(octaves)), 3, octaves)

    def test_the_rcs_burst_an_octave_down_still_has_nothing_below_300_hz(self) -> None:
        # The game plays a jet an octave low at the start of its attack and the end of its release (the reference's
        # brightness follows the level), so the file must be clean down to 600 Hz.
        self.assertLessEqual(loop_share(self.wav["rcs_burst"], 0.0, 600.0), 1e-3)

    def test_the_rcs_burst_holds_flat(self) -> None:
        # Held for the firing time: the attack, the release and the brightness are shaped per voice in the game.
        levels = frame_levels(self.wav["rcs_burst"], 0.1)
        self.assertLessEqual(float(levels.max() - levels.min()), 1.0)


if __name__ == "__main__":
    unittest.main()
