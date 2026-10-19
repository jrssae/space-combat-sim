"""Command line: ``python3 -m tools.procgen list | build <asset_id>... | build all``."""

from __future__ import annotations

import argparse
import sys
import time
from collections.abc import Sequence
from pathlib import Path

from .assets import ASSETS
from .core.context import DEFAULT_OUT_ROOT, DEFAULT_SEED, AssetOutputs, BuildContext
from .core.manifest import MANIFEST_NAME, validate_manifest

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


def _build_one(asset_id: str, seed: int, out_root: Path) -> AssetOutputs:
    out_dir = out_root / asset_id
    out_dir.mkdir(parents=True, exist_ok=True)
    outputs = ASSETS[asset_id](BuildContext(out_dir=out_dir, seed=seed))
    manifest_path = out_dir / MANIFEST_NAME
    if not manifest_path.is_file():
        raise RuntimeError(f"{asset_id}: build() did not write {MANIFEST_NAME}")
    validate_manifest(outputs.manifest)
    missing = [str(p) for p in outputs.files if not Path(p).is_file()]
    if missing:
        raise RuntimeError(
            f"{asset_id}: build() reported files that do not exist: {missing}"
        )
    return outputs


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

    failed = 0
    for asset_id in asset_ids:
        started = time.perf_counter()
        try:
            outputs = _build_one(asset_id, args.seed, args.out)
        except Exception as exc:  # noqa: BLE001 - report which asset failed, keep building the rest
            print(
                f"error: {asset_id} failed: {type(exc).__name__}: {exc}",
                file=sys.stderr,
            )
            failed += 1
            continue
        elapsed = time.perf_counter() - started
        print(
            f"built {asset_id}: {outputs.splat_count} splats, {len(outputs.files)} files "
            f"-> {_display(outputs.out_dir)} ({elapsed:.1f}s)"
        )
        for warning in outputs.warnings:
            print(f"  warning: {warning}", file=sys.stderr)
    return EXIT_BUILD_FAILED if failed else EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
