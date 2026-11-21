"""The CI splits of the Python tests (scripts/python_shards.py) and of the GUT tests (scripts/gut_shards.py) must never drop or
double a test file."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def _load_script(name: str = "python_shards"):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PythonShardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.shards = _load_script()
        cls.modules = cls.shards.discover()

    def test_every_module_runs_in_exactly_one_shard(self) -> None:
        buckets = self.shards.assign(self.modules, self.shards.SHARDS)
        self.assertEqual(self.shards.problems(self.modules, buckets), [])
        self.assertEqual(sorted(m for b in buckets for m in b), self.modules)

    def test_a_new_module_lands_in_a_shard(self) -> None:
        modules = self.modules + ["test_not_yet_written"]
        buckets = self.shards.assign(modules, self.shards.SHARDS)
        self.assertEqual(self.shards.problems(modules, buckets), [])

    def test_the_split_is_deterministic(self) -> None:
        first = self.shards.assign(self.modules, self.shards.SHARDS)
        self.assertEqual(first, self.shards.assign(list(reversed(self.modules)), self.shards.SHARDS))

    def test_no_shard_is_empty(self) -> None:
        for bucket in self.shards.assign(self.modules, self.shards.SHARDS):
            self.assertTrue(bucket)

    def test_the_check_fails_for_a_module_in_a_subfolder(self) -> None:
        # `discover` only sees the folder's own files; the check must still notice a test that would run in no shard.
        # A temporary folder stands in for the real one, so parallel test runs never see the extra file.
        real = self.shards.TESTS_DIR
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "test_flat.py").write_text("", encoding="utf-8")
            (Path(tmp) / "sub").mkdir()
            (Path(tmp) / "sub" / "test_orphan.py").write_text("", encoding="utf-8")
            self.shards.TESTS_DIR = Path(tmp)
            try:
                buckets = self.shards.assign(self.shards.discover(), self.shards.SHARDS)
                self.assertEqual(self.shards.problems(self.shards.on_disk(), buckets), ["sub.test_orphan runs in no shard"])
                self.assertEqual(self.shards.main(["check"]), 1)
            finally:
                self.shards.TESTS_DIR = real

    def test_the_check_passes_on_the_real_folder(self) -> None:
        self.assertEqual(self.shards.main(["check"]), 0)

    def test_the_workflow_runs_the_shards(self) -> None:
        text = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
        self.assertIn("scripts/python_shards.py modules", text)
        self.assertIn("scripts/python_shards.py matrix", text)
        self.assertIn("scripts/python_shards.py check", text)


class GutShardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.shards = _load_script("gut_shards")
        cls.files = cls.shards.discover()

    def test_every_file_runs_in_exactly_one_shard(self) -> None:
        for count in (1, 3, self.shards.SHARDS):
            buckets = self.shards.assign(self.files, count)
            self.assertEqual(self.shards.problems(self.files, buckets), [])
            self.assertEqual(sorted(f for b in buckets for f in b), self.files)

    def test_discovery_matches_the_folder_gut_walks(self) -> None:
        on_disk = sorted("res://" + p.relative_to(ROOT).as_posix() for p in (ROOT / "tests").rglob("test_*.gd"))
        self.assertEqual(self.files, on_disk)
        self.assertTrue(self.files)

    def test_a_new_file_lands_in_a_shard(self) -> None:
        files = self.files + ["res://tests/integration/test_not_yet_written.gd"]
        buckets = self.shards.assign(files, self.shards.SHARDS)
        self.assertEqual(self.shards.problems(files, buckets), [])

    def test_the_split_is_deterministic(self) -> None:
        first = self.shards.assign(self.files, self.shards.SHARDS)
        self.assertEqual(first, self.shards.assign(list(reversed(self.files)), self.shards.SHARDS))

    def test_no_shard_is_empty(self) -> None:
        for bucket in self.shards.assign(self.files, self.shards.SHARDS):
            self.assertTrue(bucket)

    def test_the_problems_name_a_dropped_and_a_doubled_file(self) -> None:
        files = ["res://tests/a/test_a.gd", "res://tests/a/test_b.gd", "res://tests/a/test_c.gd"]
        buckets = [["res://tests/a/test_a.gd"], ["res://tests/a/test_a.gd", "res://tests/a/test_b.gd"]]
        self.assertEqual(
            self.shards.problems(files, buckets),
            ["res://tests/a/test_c.gd runs in no shard", "res://tests/a/test_a.gd runs in 2 shards"],
        )

    def test_the_check_walks_the_folder_again_for_a_file_in_a_subfolder(self) -> None:
        # A stand-in folder, so parallel test runs never see the extra file; `check` must walk the folder again and
        # notice the file the (stale) buckets lack.
        real_root, real_tests = self.shards.ROOT, self.shards.TESTS_DIR
        with tempfile.TemporaryDirectory() as tmp:
            tests = Path(tmp) / "tests"
            (tests / "deep" / "er").mkdir(parents=True)
            (tests / "test_flat.gd").write_text("", encoding="utf-8")
            self.shards.ROOT, self.shards.TESTS_DIR = Path(tmp), tests
            try:
                stale = self.shards.assign(self.shards.discover(), 2)
                (tests / "deep" / "er" / "test_orphan.gd").write_text("", encoding="utf-8")
                self.assertEqual(
                    self.shards.problems(self.shards.discover(), stale), ["res://tests/deep/er/test_orphan.gd runs in no shard"]
                )
                self.assertEqual(self.shards.main(["check"]), 0)
            finally:
                self.shards.ROOT, self.shards.TESTS_DIR = real_root, real_tests

    def test_the_check_passes_on_the_real_folder(self) -> None:
        self.assertEqual(self.shards.main(["check"]), 0)

    def test_files_prints_the_shards_res_paths_comma_separated(self) -> None:
        buckets = self.shards.assign(self.files, self.shards.SHARDS)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(self.shards.main(["files", "2"]), 0)
        self.assertEqual(out.getvalue().strip().split(","), buckets[1])
        self.assertEqual(self.shards.main(["files", str(self.shards.SHARDS + 1)]), 2)

    def test_the_matrix_lists_every_shard_number(self) -> None:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(self.shards.main(["matrix"]), 0)
        self.assertEqual(json.loads(out.getvalue()), list(range(1, self.shards.SHARDS + 1)))

    def test_the_heaviest_shard_stays_close_to_the_average(self) -> None:
        # The balance this planner exists for: one slow file moving shards must not push one over the GUT timeout.
        buckets = self.shards.assign(self.files, self.shards.SHARDS)
        loads = [self.shards.load(b, i) for i, b in enumerate(buckets, 1)]
        self.assertLess(max(loads), 1.1 * sum(loads) / len(loads))
        self.assertLess(max(loads), 0.6 * 2400)

    def test_the_heaviest_files_are_spread_over_the_shards(self) -> None:
        heavy = sorted(self.files, key=lambda f: -self.shards.weight(f))[:3]
        buckets = self.shards.assign(self.files, self.shards.SHARDS)
        for path in heavy:
            self.assertEqual(sum(path in b for b in buckets), 1)
        self.assertEqual(len({next(i for i, b in enumerate(buckets) if p in b) for p in heavy}), len(heavy))

    def test_the_workflow_and_run_tests_use_the_planner(self) -> None:
        text = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
        self.assertIn("scripts/gut_shards.py matrix", text)
        self.assertIn("scripts/gut_shards.py check", text)
        self.assertIn("needs.assets.outputs.gut_shards", text)
        self.assertIn("strategy.job-total", text)
        script = (ROOT / "scripts" / "run_tests.sh").read_text(encoding="utf-8")
        self.assertIn("scripts/gut_shards.py files", script)


if __name__ == "__main__":
    unittest.main()
