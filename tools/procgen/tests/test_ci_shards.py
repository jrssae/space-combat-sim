"""The CI split of these tests (scripts/python_shards.py) must never drop or double a test module."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def _load_script():
    spec = importlib.util.spec_from_file_location("python_shards", ROOT / "scripts" / "python_shards.py")
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


if __name__ == "__main__":
    unittest.main()
