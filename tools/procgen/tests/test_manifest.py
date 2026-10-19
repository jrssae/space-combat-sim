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
        lods=[manifest.lod_entry(0, "demo.ply", 1000, 0.06)],
        aabb_min=[-1.0, -2.0, -3.0],
        aabb_max=[1.0, 2.0, 3.0],
        centroid_offset=[0.0, 0.1, 0.6],
        files={"fallback_mesh": "demo.obj"},
    )


class ManifestTests(unittest.TestCase):
    def test_contains_the_contract_keys_with_lods_zero(self) -> None:
        m = sample()
        for key in ("asset_id", "generator_version", "seed", "frame", "units", "lods",
                    "aabb_min", "aabb_max", "centroid_offset", "files"):  # fmt: skip
            self.assertIn(key, m)
        self.assertEqual((m["frame"], m["units"]), ("godot", "m"))
        self.assertEqual(
            m["lods"][0],
            {"level": 0, "file": "demo.ply", "splats": 1000, "spacing_m": 0.06},
        )

    def test_numpy_scalars_become_plain_json_numbers(self) -> None:
        m = manifest.build_manifest(
            "demo", 1, 42, [manifest.lod_entry(0, "d.ply", np.int64(5), np.float32(0.5))],
            np.array([-1.0, -1.0, -1.0], dtype=np.float32), np.ones(3, dtype=np.float32), np.zeros(3),
        )  # fmt: skip
        self.assertIs(type(m["lods"][0]["splats"]), int)
        self.assertIs(type(m["aabb_min"][0]), float)

    def test_extra_keys_are_added_but_cannot_shadow_reserved_ones(self) -> None:
        m = manifest.build_manifest(
            "demo", 1, 1, [manifest.lod_entry(0, "d.ply", 1, 1.0)], [0, 0, 0], [0, 0, 0], [0, 0, 0],
            extra={"counts": {"a": 1}},
        )  # fmt: skip
        self.assertEqual(m["counts"], {"a": 1})
        with self.assertRaises(ValueError):
            manifest.build_manifest(
                "demo", 1, 1, [manifest.lod_entry(0, "d.ply", 1, 1.0)], [0, 0, 0], [0, 0, 0], [0, 0, 0],
                extra={"seed": 5},
            )  # fmt: skip

    def test_validation_rejects_contract_violations(self) -> None:
        def broken(mutate) -> dict:
            m = copy.deepcopy(sample())
            mutate(m)
            return m

        cases = {
            "missing lods": lambda m: m.pop("lods"),
            "empty lods": lambda m: m.update(lods=[]),
            "lods[0] level": lambda m: m["lods"][0].update(level=1),
            "zero splats": lambda m: m["lods"][0].update(splats=0),
            "float splats": lambda m: m["lods"][0].update(splats=1.5),
            "no file": lambda m: m["lods"][0].pop("file"),
            "bad spacing": lambda m: m["lods"][0].update(spacing_m=0),
            "frame": lambda m: m.update(frame="3dgs"),
            "units": lambda m: m.update(units="cm"),
            "seed type": lambda m: m.update(seed="42"),
            "aabb length": lambda m: m.update(aabb_min=[0, 0]),
            "aabb order": lambda m: m.update(aabb_min=[5, 0, 0]),
            "centroid type": lambda m: m.update(centroid_offset=["a", 0, 0]),
            "files type": lambda m: m.update(files={"x": 3}),
        }
        for name, mutate in cases.items():
            with self.subTest(name), self.assertRaises(ValueError):
                manifest.validate_manifest(broken(mutate))

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
