"""CLI and registry: ``python3 -m tools.procgen list | build``."""

from __future__ import annotations

import contextlib
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools.procgen.__main__ import main
from tools.procgen.assets import ASSETS, sky_default
from tools.procgen.core.context import REPO_ROOT, AssetOutputs, BuildContext
from tools.procgen.core.manifest import build_manifest, lod_entry, write_manifest


def run(*argv: str) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = main(list(argv))
    return code, out.getvalue(), err.getvalue()


def make_fake(
    calls: list[tuple[str, int, Path]],
    asset_id: str,
    *,
    write: bool = True,
    fail: bool = False,
):
    def build(ctx: BuildContext) -> AssetOutputs:
        calls.append((asset_id, ctx.seed, ctx.out_dir))
        if fail:
            raise RuntimeError("boom")
        manifest = build_manifest(
            asset_id,
            1,
            ctx.seed,
            [lod_entry(0, f"{asset_id}.ply", 10, 1.0)],
            [0, 0, 0],
            [1, 1, 1],
            [0, 0, 0],
        )
        files = ()
        if write:
            files = (write_manifest(ctx.out_dir, manifest),)
        return AssetOutputs(asset_id, ctx.out_dir, manifest, files)

    return build


class RegistryTests(unittest.TestCase):
    def test_registry_maps_ids_to_callables(self) -> None:
        self.assertIn("sky_default", ASSETS)
        self.assertTrue(all(callable(build) for build in ASSETS.values()))
        self.assertIs(ASSETS["sky_default"], sky_default.build)


class ListTests(unittest.TestCase):
    def test_list_prints_every_asset_id_sorted(self) -> None:
        code, out, _ = run("list")
        self.assertEqual(code, 0)
        self.assertEqual(out.split(), sorted(ASSETS))
        self.assertIn("sky_default", out.split())

    def test_list_follows_the_registry(self) -> None:
        expected = sorted({*ASSETS, "alpha", "zeta"})
        with mock.patch.dict(
            ASSETS, {"zeta": make_fake([], "zeta"), "alpha": make_fake([], "alpha")}
        ):
            _, out, _ = run("list")
        self.assertEqual(out.split(), expected)

    def test_module_entry_point_works_from_the_repo_root(self) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "tools.procgen", "list"],
            cwd=REPO_ROOT, capture_output=True, text=True, timeout=60, check=False,
        )  # fmt: skip
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("sky_default", result.stdout.split())

    def test_no_arguments_is_a_usage_error(self) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "tools.procgen"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        self.assertEqual(result.returncode, 2)


class BuildTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.out = Path(self._tmp.name)
        self.calls: list[tuple[str, int, Path]] = []

    def fakes(self, **special):
        ids = ("charlie", "alpha", "bravo")
        return {i: make_fake(self.calls, i, **special.get(i, {})) for i in ids}

    def test_build_all_iterates_the_registry_in_sorted_order(self) -> None:
        with mock.patch.dict(ASSETS, self.fakes(), clear=True):
            code, out, _ = run("build", "all", "--out", str(self.out))
        self.assertEqual(code, 0)
        self.assertEqual([c[0] for c in self.calls], ["alpha", "bravo", "charlie"])
        self.assertIn("built alpha", out)

    def test_each_asset_gets_its_own_directory_under_out_and_the_default_seed(
        self,
    ) -> None:
        with mock.patch.dict(ASSETS, self.fakes(), clear=True):
            run("build", "bravo", "--out", str(self.out))
        self.assertEqual(self.calls, [("bravo", 42, self.out / "bravo")])
        self.assertTrue((self.out / "bravo" / "manifest.json").is_file())

    def test_seed_is_passed_through(self) -> None:
        with mock.patch.dict(ASSETS, self.fakes(), clear=True):
            run("build", "alpha", "--seed", "7", "--out", str(self.out))
        self.assertEqual(self.calls[0][1], 7)

    def test_named_assets_build_in_the_order_given_and_once(self) -> None:
        with mock.patch.dict(ASSETS, self.fakes(), clear=True):
            code, _, _ = run(
                "build", "charlie", "alpha", "charlie", "--out", str(self.out)
            )
        self.assertEqual(code, 0)
        self.assertEqual([c[0] for c in self.calls], ["charlie", "alpha"])

    def test_all_wins_when_mixed_with_names(self) -> None:
        with mock.patch.dict(ASSETS, self.fakes(), clear=True):
            run("build", "charlie", "all", "--out", str(self.out))
        self.assertEqual([c[0] for c in self.calls], ["alpha", "bravo", "charlie"])

    def test_unknown_asset_is_a_usage_error_and_builds_nothing(self) -> None:
        with mock.patch.dict(ASSETS, self.fakes(), clear=True):
            code, _, err = run("build", "alpha", "nope", "--out", str(self.out))
        self.assertEqual(code, 2)
        self.assertIn("nope", err)
        self.assertIn("alpha", err)  # lists the known ids
        self.assertEqual(self.calls, [])

    def test_a_failing_asset_gives_exit_1_but_the_rest_still_build(self) -> None:
        with mock.patch.dict(ASSETS, self.fakes(bravo={"fail": True}), clear=True):
            code, out, err = run("build", "all", "--out", str(self.out))
        self.assertEqual(code, 1)
        self.assertEqual([c[0] for c in self.calls], ["alpha", "bravo", "charlie"])
        self.assertIn("bravo failed", err)
        self.assertIn("built charlie", out)

    def test_an_asset_that_reports_files_it_did_not_write_fails(self) -> None:
        def liar(ctx: BuildContext) -> AssetOutputs:
            outputs = make_fake([], "liar")(ctx)
            return AssetOutputs(
                "liar",
                ctx.out_dir,
                outputs.manifest,
                (*outputs.files, ctx.out_dir / "ghost.ply"),
            )

        with mock.patch.dict(ASSETS, {"liar": liar}, clear=True):
            code, _, err = run("build", "liar", "--out", str(self.out))
        self.assertEqual(code, 1)
        self.assertIn("ghost.ply", err)

    def test_an_asset_without_a_manifest_fails(self) -> None:
        with mock.patch.dict(
            ASSETS, {"quiet": make_fake([], "quiet", write=False)}, clear=True
        ):
            code, _, err = run("build", "quiet", "--out", str(self.out))
        self.assertEqual(code, 1)
        self.assertIn("manifest.json", err)

    def test_warnings_are_printed_to_stderr(self) -> None:
        def warns(ctx: BuildContext) -> AssetOutputs:
            outputs = make_fake([], "warns")(ctx)
            return AssetOutputs(
                "warns", ctx.out_dir, outputs.manifest, outputs.files, ("heads up",)
            )

        with mock.patch.dict(ASSETS, {"warns": warns}, clear=True):
            code, out, err = run("build", "warns", "--out", str(self.out))
        self.assertEqual(code, 0)
        self.assertIn("warning: heads up", err)
        self.assertNotIn("heads up", out)

    def test_bad_seeds_and_missing_assets_are_argparse_errors(self) -> None:
        for argv in (
            ["build", "alpha", "--seed", "-1"],
            ["build", "alpha", "--seed", "x"],
            ["build"],
        ):
            with (
                self.subTest(argv),
                contextlib.redirect_stderr(io.StringIO()),
                self.assertRaises(SystemExit) as raised,
            ):
                main(argv)
            self.assertEqual(raised.exception.code, 2)

    def test_builds_the_real_sky_default_into_out(self) -> None:
        small = {"stars": 200, "nebula": 100, "panorama": False}

        def small_sky(ctx: BuildContext) -> AssetOutputs:
            return sky_default.build(BuildContext(ctx.out_dir, ctx.seed, small))

        with mock.patch.dict(ASSETS, {"sky_default": small_sky}, clear=True):
            code, out, _ = run("build", "all", "--out", str(self.out))
        self.assertEqual(code, 0)
        self.assertIn("built sky_default: 300 splats", out)
        self.assertEqual(
            sorted(p.name for p in (self.out / "sky_default").iterdir()),
            ["manifest.json", "sky_default.ply"],
        )


if __name__ == "__main__":
    unittest.main()
