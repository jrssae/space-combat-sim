"""``build --jobs N`` (M4-T30d fix round 1): assets built in worker processes give the same bytes as one at a time; a failing asset
is named and the rest still build; a worker that dies hard is named too, the others are built, and the exit is nonzero."""

from __future__ import annotations

import multiprocessing
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools.procgen import __main__ as cli
from tools.procgen.assets import ASSETS
from tools.procgen.core.context import REPO_ROOT, AssetOutputs, BuildContext
from tools.procgen.tests.test_cli import make_fake, run

SMALL = ("nav_buoy", "sfx_combat")


def _files(root: Path) -> dict[str, bytes]:
    return {str(p.relative_to(root)): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file()}


def _dies(ctx: BuildContext) -> AssetOutputs:
    os._exit(3)  # a worker killed outright (an out-of-memory kill, say), not an exception


class SameBytesTests(unittest.TestCase):
    def test_two_jobs_write_the_same_files_as_one(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            serial, parallel = Path(tmp) / "serial", Path(tmp) / "parallel"
            for out, jobs in ((serial, "1"), (parallel, "2")):
                result = subprocess.run([sys.executable, "-m", "tools.procgen", "build", *SMALL, "--out", str(out), "--jobs", jobs],
                                        cwd=REPO_ROOT, capture_output=True, text=True, timeout=600, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                for asset_id in SMALL:
                    self.assertIn(f"built {asset_id}", result.stdout)
            a, b = _files(serial), _files(parallel)
            self.assertIn("nav_buoy/manifest.json", a)
            self.assertIn("nav_buoy/nav_buoy_albedo.png", a)
            self.assertEqual(sorted(a), sorted(b))
            for name in a:
                self.assertEqual(a[name], b[name], name)

    def test_jobs_must_be_a_positive_integer(self) -> None:
        import contextlib
        import io

        for bad in ("0", "x"):
            with self.subTest(bad), contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
                cli.main(["build", "nav_buoy", "--jobs", bad])
            self.assertEqual(raised.exception.code, 2)


class ParallelFailureTests(unittest.TestCase):
    """Fake assets in forked workers (``fork`` carries the patched registry into them)."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.out = Path(self._tmp.name)
        fork = mock.patch.object(cli, "_pool_context", lambda: multiprocessing.get_context("fork"))
        fork.start()
        self.addCleanup(fork.stop)

    def test_a_failing_asset_is_named_and_the_rest_build(self) -> None:
        fakes = {i: make_fake([], i, fail=(i == "bravo")) for i in ("alpha", "bravo", "charlie")}
        with mock.patch.dict(ASSETS, fakes, clear=True):
            code, out, err = run("build", "all", "--out", str(self.out), "--jobs", "2")
        self.assertEqual(code, 1)
        self.assertIn("bravo failed", err)
        self.assertIn("built alpha", out)
        self.assertIn("built charlie", out)
        self.assertTrue((self.out / "charlie" / "manifest.json").is_file())

    def test_a_worker_that_dies_is_named_and_the_others_still_build(self) -> None:
        fakes = {i: make_fake([], i) for i in ("alpha", "charlie", "delta")}
        fakes["bravo"] = _dies
        with mock.patch.dict(ASSETS, fakes, clear=True):
            code, out, err = run("build", "all", "--out", str(self.out), "--jobs", "2")
        self.assertEqual(code, 1)
        self.assertIn("bravo failed", err)
        self.assertIn("worker process died", err)
        self.assertNotIn("Traceback", err)
        for name in ("alpha", "charlie", "delta"):
            self.assertIn(f"built {name}", out)
            self.assertTrue((self.out / name / "manifest.json").is_file(), name)
        self.assertNotIn("alpha failed", err)


    def test_an_asset_that_builds_alone_waits_for_the_pool(self) -> None:
        # M7-T04: the station's bake needs the memory to itself, so it starts only once every pooled build has finished.
        import json
        import time

        def timed(name: str):
            inner = make_fake([], name)

            def builder(ctx: BuildContext) -> AssetOutputs:
                start = time.monotonic()
                time.sleep(0.3)
                out = inner(ctx)
                (self.out / f"{name}.json").write_text(json.dumps([start, time.monotonic()]))
                return out

            return builder

        fakes = {i: timed(i) for i in ("alpha", "bravo", "charlie")}
        with mock.patch.dict(ASSETS, fakes, clear=True), mock.patch.object(cli, "BUILD_ALONE", frozenset({"alpha"})):
            code, out, err = run("build", "all", "--out", str(self.out), "--jobs", "3")
        self.assertEqual(code, 0, err)
        spans = {i: json.loads((self.out / f"{i}.json").read_text()) for i in fakes}
        self.assertGreaterEqual(spans["alpha"][0], max(spans["bravo"][1], spans["charlie"][1]))
        self.assertLess(spans["bravo"][0], spans["charlie"][1], "the others still share the pool")
        self.assertEqual([line.split()[1].rstrip(":") for line in out.splitlines() if line.startswith("built")],
                         ["alpha", "bravo", "charlie"], "reported in the asked order")


class GenAssetsJobsTests(unittest.TestCase):
    def test_gen_assets_takes_its_jobs_from_the_cores_up_to_four(self) -> None:
        script = (REPO_ROOT / "scripts" / "gen_assets.sh").read_text(encoding="utf-8")
        self.assertIn("nproc", script)
        self.assertIn("--jobs", script)
        for cores, jobs in (("1", "1"), ("2", "2"), ("20", "4")):
            snippet = script[script.index("# jobs:") : script.index("# end jobs")]
            result = subprocess.run(["bash", "-c", f"nproc() {{ echo {cores}; }}; {snippet} echo \"$JOBS\""], capture_output=True,
                                    text=True, timeout=10, check=False)
            self.assertEqual(result.stdout.strip(), jobs, (cores, result.stderr))


if __name__ == "__main__":
    unittest.main()
