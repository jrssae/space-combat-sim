#!/usr/bin/env python3
"""Split the generator's unittest modules into CI shards.

Goal: keep every "python tests" job well under its timeout while guaranteeing that each
tools/procgen/tests/test_*.py module runs in exactly one shard, so a new test file is
never silently skipped.

Usage:
    python3 scripts/python_shards.py modules K   # dotted module names of shard K (1..SHARDS), one per line
    python3 scripts/python_shards.py matrix      # JSON list of shard numbers, for the workflow's matrix
    python3 scripts/python_shards.py plan        # every shard with its estimated time
    python3 scripts/python_shards.py check       # exit 1 unless the shards cover every module exactly once

SHARDS is the only place the shard count lives; the workflow reads it through `matrix`.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS_DIR = ROOT / "tools" / "procgen" / "tests"
PACKAGE = "tools.procgen.tests"

# Rough seconds per module on a CI runner, from the run log of 2026-11-13 and a local timing of each module on its own.
# Only the heavy modules need an entry; the balance is a heuristic, coverage never depends on it. A module with no
# entry counts as DEFAULT_WEIGHT, so a new heavy test file lands somewhere sensible even before someone adds it here.
WEIGHTS: dict[str, float] = {
    "test_saturn_family": 460,
    "test_starfury_aurora": 440,
    "test_raider_fighter": 360,
    "test_textured_hulls": 350,
    "test_textured_mesh": 250,
    "test_babylon5_station": 200,
    "test_jumpgate": 100,
    "test_render_pieces": 100,
    "test_asteroids": 90,
    "test_planet": 53,
    "test_textures": 40,
    "test_skylark_transport": 35,
    "test_sky_default": 31,
    "test_centauri_brezebel": 24,
    "test_brakiri_bokmai": 21,
    "test_parallel_build": 21,
    "test_narn_transport": 19,
    "test_nav_buoy": 17,
}
DEFAULT_WEIGHT = 10.0

# Four shards: the whole suite took about 24 minutes on one runner (the 30-minute job limit), so each shard stays
# far under its timeout with room for the station and raider tests.
SHARDS = 4


def discover() -> list[str]:
    """Every test module name, sorted, found the way `unittest discover` finds them."""
    return sorted(p.stem for p in TESTS_DIR.glob("test*.py"))


def assign(modules: list[str], shards: int) -> list[list[str]]:
    """Heaviest module first onto the lightest shard; ties break by name, so the split is deterministic."""
    ordered = sorted(modules, key=lambda m: (-WEIGHTS.get(m, DEFAULT_WEIGHT), m))
    buckets: list[list[str]] = [[] for _ in range(shards)]
    loads = [0.0] * shards
    for module in ordered:
        lightest = min(range(shards), key=lambda i: (loads[i], i))
        buckets[lightest].append(module)
        loads[lightest] += WEIGHTS.get(module, DEFAULT_WEIGHT)
    return [sorted(b) for b in buckets]


def load(bucket: list[str]) -> float:
    return sum(WEIGHTS.get(m, DEFAULT_WEIGHT) for m in bucket)


def problems(modules: list[str], buckets: list[list[str]]) -> list[str]:
    """Empty when the buckets hold every module exactly once."""
    seen: dict[str, int] = {}
    for bucket in buckets:
        for module in bucket:
            seen[module] = seen.get(module, 0) + 1
    out = [f"{m} runs in no shard" for m in modules if m not in seen]
    out += [f"{m} runs in {n} shards" for m, n in sorted(seen.items()) if n != 1]
    out += [f"{m} is not a test module" for m in sorted(seen) if m not in modules]
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("modules").add_argument("shard", type=int, help="1..SHARDS")
    sub.add_parser("matrix")
    sub.add_parser("plan")
    sub.add_parser("check")
    args = parser.parse_args(argv)

    if args.cmd == "matrix":
        print(json.dumps(list(range(1, SHARDS + 1))))
        return 0

    modules = discover()
    if not modules:
        print(f"no test modules under {TESTS_DIR}", file=sys.stderr)
        return 1
    buckets = assign(modules, SHARDS)

    if args.cmd == "modules":
        if not 1 <= args.shard <= SHARDS:
            print(f"shard {args.shard} out of range 1..{SHARDS}", file=sys.stderr)
            return 2
        for module in buckets[args.shard - 1]:
            print(f"{PACKAGE}.{module}")
        return 0

    if args.cmd == "plan":
        for i, bucket in enumerate(buckets, 1):
            print(f"shard {i}/{SHARDS}: ~{load(bucket):.0f}s, {len(bucket)} modules")
            for module in bucket:
                print(f"    {module}  ({WEIGHTS.get(module, DEFAULT_WEIGHT):.0f}s)")
        return 0

    found = problems(modules, buckets)
    for line in found:
        print(f"python_shards: {line}", file=sys.stderr)
    if not found:
        print(f"python_shards: {len(modules)} modules, each in exactly one of {SHARDS} shards")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
