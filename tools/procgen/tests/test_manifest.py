"""Manifest contract and build context."""

from __future__ import annotations

import copy
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.core import manifest
from tools.procgen.core.context import BuildContext


def sample() -> dict:
    return manifest.build_manifest(
        asset_id="demo",
        generator_version=3,
        seed=42,
        aabb_min=[-1.0, -2.0, -3.0],
        aabb_max=[1.0, 2.0, 3.0],
        centroid_offset=[0.0, 0.1, 0.6],
        files={"obj": "demo.obj"},
    )


class ManifestTests(unittest.TestCase):
    def test_contains_the_contract_keys(self) -> None:
        m = sample()
        for key in ("asset_id", "generator_version", "seed", "frame", "units",
                    "aabb_min", "aabb_max", "centroid_offset", "files"):  # fmt: skip
            self.assertIn(key, m)
        self.assertEqual((m["frame"], m["units"]), ("godot", "m"))
        self.assertNotIn("lods", m, "no level ladder: the textured mesh's levels are the importer's (M4-T31)")

    def test_numpy_scalars_become_plain_json_numbers(self) -> None:
        m = manifest.build_manifest(
            "demo", 1, 42, np.array([-1.0, -1.0, -1.0], dtype=np.float32), np.ones(3, dtype=np.float32), np.zeros(3),
            extra={"count": int(np.int64(5))},
        )  # fmt: skip
        self.assertIs(type(m["aabb_min"][0]), float)
        self.assertIs(type(m["centroid_offset"][0]), float)

    def test_extra_keys_are_added_but_cannot_shadow_reserved_ones(self) -> None:
        m = manifest.build_manifest("demo", 1, 1, [0, 0, 0], [0, 0, 0], [0, 0, 0], extra={"counts": {"a": 1}})
        self.assertEqual(m["counts"], {"a": 1})
        with self.assertRaises(ValueError):
            manifest.build_manifest("demo", 1, 1, [0, 0, 0], [0, 0, 0], [0, 0, 0], extra={"seed": 5})

    def test_validation_rejects_contract_violations(self) -> None:
        def broken(mutate) -> dict:
            m = copy.deepcopy(sample())
            mutate(m)
            return m

        cases = {
            "frame": lambda m: m.update(frame="3dgs"),
            "units": lambda m: m.update(units="cm"),
            "seed type": lambda m: m.update(seed="42"),
            "kind": lambda m: m.update(kind="points"),
            "aabb length": lambda m: m.update(aabb_min=[0, 0]),
            "aabb order": lambda m: m.update(aabb_min=[5, 0, 0]),
            "centroid type": lambda m: m.update(centroid_offset=["a", 0, 0]),
            "missing centroid": lambda m: m.pop("centroid_offset"),
            "files type": lambda m: m.update(files={"x": 3}),
            "mesh type": lambda m: m.update(mesh="demo.glb"),
        }
        for name, mutate in cases.items():
            with self.subTest(name), self.assertRaises(ValueError):
                manifest.validate_manifest(broken(mutate))

    def test_non_finite_numbers_are_rejected_naming_the_field(self) -> None:
        def with_value(mutate, value: float) -> dict:
            m = copy.deepcopy(sample())
            mutate(m, value)
            return m

        cases = {
            "aabb_min": lambda m, v: m.update(aabb_min=[-1.0, v, -3.0]),
            "aabb_max": lambda m, v: m.update(aabb_max=[1.0, 2.0, v]),
            "centroid_offset": lambda m, v: m.update(centroid_offset=[v, 0.1, 0.6]),
        }
        for name, mutate in cases.items():
            for value in (float("nan"), float("inf"), float("-inf")):
                with self.subTest(field=name, value=value), self.assertRaises(ValueError) as ctx:
                    manifest.validate_manifest(with_value(mutate, value))
                self.assertIn(name, str(ctx.exception))

    def test_non_finite_peak_dbfs_is_rejected(self) -> None:
        for value in (float("nan"), float("inf"), float("-inf")):
            with self.subTest(value=value), self.assertRaises(ValueError) as ctx:
                manifest.build_audio_manifest(
                    "snd", 1, 7, {"beep": manifest.sound_entry("beep.wav", 100, 48000, value)}
                )
            self.assertIn("peak_dbfs", str(ctx.exception))

    def test_write_and_read_round_trip_with_stable_text(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            a = manifest.write_manifest(Path(tmp), sample())
            text = a.read_text(encoding="utf-8")
            self.assertTrue(text.endswith("}\n"))
            self.assertEqual(a.name, "manifest.json")
            self.assertEqual(manifest.read_manifest(Path(tmp)), sample())
            self.assertEqual(manifest.read_manifest(a), sample())
            manifest.write_manifest(Path(tmp), sample())
            self.assertEqual(a.read_text(encoding="utf-8"), text)


class BuildContextTests(unittest.TestCase):
    def test_default_rng_is_numpy_default_rng_of_the_seed(self) -> None:
        ctx = BuildContext(out_dir=Path("x"), seed=7)
        np.testing.assert_array_equal(
            ctx.rng().random(5), np.random.default_rng(7).random(5)
        )

    def test_named_streams_are_stable_and_independent(self) -> None:
        a = BuildContext(Path("x"), seed=1)
        np.testing.assert_array_equal(
            a.rng("stars").random(4), a.rng("stars").random(4)
        )
        self.assertFalse(
            np.array_equal(a.rng("stars").random(4), a.rng("nebula").random(4))
        )
        b = BuildContext(Path("x"), seed=2)
        self.assertFalse(
            np.array_equal(a.rng("stars").random(4), b.rng("stars").random(4))
        )

    def test_seed_must_be_a_non_negative_int(self) -> None:
        for bad in (-1, 1.5, "42", True, None):
            with self.subTest(bad), self.assertRaises(ValueError):
                BuildContext(Path("x"), seed=bad)  # type: ignore[arg-type]

    def test_options_with_defaults(self) -> None:
        ctx = BuildContext(Path("x"), options={"stars": 10})
        self.assertEqual(ctx.option("stars", 5), 10)
        self.assertEqual(ctx.option("nebula", 5), 5)


if __name__ == "__main__":
    unittest.main()
