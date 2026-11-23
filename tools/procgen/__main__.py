"""Command line: ``python3 -m tools.procgen list | build <asset_id>... | build all``.

``--option key=value`` lands in ``BuildContext.options``; assets read what they understand
(``starfury_aurora``: ``render_triangles``, ``atlas_px``, ``texel_m``) and ignore the rest.
``--jobs N`` builds up to N assets at once in worker processes (M4-T30d: the textured hulls made a
one-at-a-time ``build all`` too slow); every asset's output is the same either way.
A build starts only while the running builds' measured peaks fit ``PROCGEN_MEM_MB`` (else 80% of the free memory).
"""

from __future__ import annotations

import argparse
import multiprocessing
import os
import json
import sys
from concurrent.futures import FIRST_COMPLETED, Future, ProcessPoolExecutor, wait
from concurrent.futures.process import BrokenProcessPool
from multiprocessing.context import BaseContext
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from .assets import ASSETS, BUILD_ALONE, DEFAULT_PEAK_MB, PEAK_MB
from .core.context import DEFAULT_OUT_ROOT, DEFAULT_SEED
from .build import BuildResult, timed_build

WORKER_DIED = "its worker process died (killed, or out of memory?)"

EXIT_OK = 0
EXIT_BUILD_FAILED = 1
EXIT_USAGE = 2


def _seed(text: str) -> int:
    try:
        value = int(text)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            f"invalid seed {text!r}: expected an integer"
        ) from exc
    if value < 0:
        raise argparse.ArgumentTypeError(f"invalid seed {text!r}: must be >= 0")
    return value


def _jobs(text: str) -> int:
    try:
        value = int(text)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid jobs {text!r}: expected an integer") from exc
    if value < 1:
        raise argparse.ArgumentTypeError(f"invalid jobs {text!r}: must be >= 1")
    return value


def _option(text: str) -> tuple[str, Any]:
    """``key=value`` with the value parsed as JSON when possible (so ``overlap=1.2`` is a number)."""
    key, sep, raw = text.partition("=")
    if not sep or not key:
        raise argparse.ArgumentTypeError(f"invalid option {text!r}: expected key=value")
    try:
        value: Any = json.loads(raw)
    except json.JSONDecodeError:
        value = raw
    return key, value


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python3 -m tools.procgen",
        description="Procedural asset generators (docs/architecture.md section 9).",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="print the registered asset ids, one per line")

    build = sub.add_parser("build", help="generate assets into <out>/<asset_id>/")
    build.add_argument(
        "assets",
        nargs="+",
        metavar="asset_id",
        help="asset ids to build, or 'all' for every registered asset in sorted order",
    )
    build.add_argument(
        "--seed",
        type=_seed,
        default=DEFAULT_SEED,
        help=f"random seed (default {DEFAULT_SEED})",
    )
    build.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT_ROOT,
        help="output root (default: <repo>/assets/generated)",
    )
    build.add_argument(
        "--jobs",
        type=_jobs,
        default=1,
        metavar="N",
        help="build up to N assets at once in worker processes (default 1: one after another, in this process)",
    )
    build.add_argument(
        "--option",
        type=_option,
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="extra BuildContext option (JSON value), e.g. --option overlap=1.2; repeatable",
    )
    return parser


def _resolve_ids(requested: Sequence[str]) -> list[str]:
    """Expand 'all' and keep the user's order otherwise; raise KeyError on unknown ids."""
    if "all" in requested:
        return sorted(ASSETS)
    unknown = [name for name in requested if name not in ASSETS]
    if unknown:
        raise KeyError(unknown)
    # Build each id once even if it was repeated.
    return list(dict.fromkeys(requested))


def _pool_context() -> BaseContext | None:
    """The process start method for ``--jobs`` workers: the platform's default (tests fork, to carry a patched registry)."""
    return None


def memory_budget_mb() -> int:
    """The memory the pooled builds may share: PROCGEN_MEM_MB, else 80% of what the machine has free now (M10-T21: CI's 16 GB
    runner died running two 6 GB bakes side by side)."""
    if os.environ.get("PROCGEN_MEM_MB"):
        return int(os.environ["PROCGEN_MEM_MB"])
    try:
        with open("/proc/meminfo", encoding="ascii") as meminfo:
            fields = dict(line.split(":", 1) for line in meminfo)
        return int(fields["MemAvailable"].split()[0]) * 8 // 10240
    except (OSError, KeyError, ValueError):
        return 1 << 30  # no way to know: the job count is the only limit


def _parallel(asset_ids: Sequence[str], jobs: int, seed: int, out_root: Path, options: dict[str, Any]) -> list[BuildResult]:
    """Build ``asset_ids`` in up to ``jobs`` workers, starting a build only while the running ones' measured peaks
    (``PEAK_MB``) fit the memory budget, so the machine never swaps or kills the job. Each build gets a fresh worker, so no
    worker carries one build's memory into the next. When a worker dies, every asset that had not finished is built again in a
    worker of its own, so only the one that kills its worker is reported failed. The ``BUILD_ALONE`` assets, and any too big
    for the budget beside another, wait for the pool and are then built one at a time."""
    budget = memory_budget_mb()
    results: dict[str, BuildResult] = {}
    alone = [a for a in asset_ids if a in BUILD_ALONE or PEAK_MB.get(a, DEFAULT_PEAK_MB) * 2 > budget]
    pending = [a for a in asset_ids if a not in alone]
    unfinished: list[str] = []
    if pending:
        context = _pool_context() or multiprocessing.get_context("spawn")
        fresh = {} if context.get_start_method() == "fork" else {"max_tasks_per_child": 1}  # tests fork, which cannot recycle
        with ProcessPoolExecutor(max_workers=min(jobs, len(pending)), mp_context=context, **fresh) as executor:
            running: dict[Future[BuildResult], str] = {}
            while pending or running:
                in_use = sum(PEAK_MB.get(a, DEFAULT_PEAK_MB) for a in running.values())
                fits = [a for a in pending if not running or in_use + PEAK_MB.get(a, DEFAULT_PEAK_MB) <= budget]
                if fits and len(running) < jobs:
                    pending.remove(fits[0])
                    running[executor.submit(timed_build, fits[0], seed, out_root, options)] = fits[0]
                    continue
                done, _ = wait(running, return_when=FIRST_COMPLETED)
                for future in done:
                    asset_id = running.pop(future)
                    try:
                        results[asset_id] = future.result()
                    except BrokenProcessPool:
                        unfinished.append(asset_id)
                if unfinished:
                    # A dead worker breaks the pool: everything still running or waiting is built alone below.
                    for future, asset_id in running.items():
                        try:
                            results[asset_id] = future.result()
                        except BrokenProcessPool:
                            unfinished.append(asset_id)
                    unfinished += pending
                    pending, running = [], {}
    for asset_id in [a for a in asset_ids if a in unfinished or a in alone]:
        with ProcessPoolExecutor(max_workers=1, mp_context=_pool_context()) as single:
            try:
                results[asset_id] = single.submit(timed_build, asset_id, seed, out_root, options).result()
            except BrokenProcessPool:
                results[asset_id] = (None, WORKER_DIED, 0.0)
    return [results[asset_id] for asset_id in asset_ids]


def _display(path: Path) -> str:
    try:
        return str(Path(path).resolve().relative_to(Path.cwd().resolve()))
    except ValueError:
        return str(path)


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if args.command == "list":
        for asset_id in sorted(ASSETS):
            print(asset_id)
        return EXIT_OK

    try:
        asset_ids = _resolve_ids(args.assets)
    except KeyError as exc:
        known = ", ".join(sorted(ASSETS)) or "(none)"
        print(
            f"error: unknown asset id(s): {', '.join(exc.args[0])}; known: {known}",
            file=sys.stderr,
        )
        return EXIT_USAGE

    options: dict[str, Any] = dict(args.option)

    if args.jobs > 1 and len(asset_ids) > 1:
        results = _parallel(asset_ids, args.jobs, args.seed, args.out, options)
    else:
        results = (timed_build(asset_id, args.seed, args.out, options) for asset_id in asset_ids)

    failed = 0
    for asset_id, (outputs, error, elapsed) in zip(asset_ids, results):
        if outputs is None:
            print(
                f"error: {asset_id} failed: {error}",
                file=sys.stderr,
            )
            failed += 1
            continue
        print(
            f"built {asset_id}: {outputs.summary}, {len(outputs.files)} files "
            f"-> {_display(outputs.out_dir)} ({elapsed:.1f}s)"
        )
        for warning in outputs.warnings:
            print(f"  warning: {warning}", file=sys.stderr)
    return EXIT_BUILD_FAILED if failed else EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
