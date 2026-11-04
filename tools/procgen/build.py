"""One asset's build, checked (``python3 -m tools.procgen build``): importable, so ``--jobs`` can run it in worker processes
(M4-T30d)."""

from __future__ import annotations

import time
from pathlib import Path
from typing import Any

from .assets import ASSETS
from .core.context import AssetOutputs, BuildContext
from .core.manifest import MANIFEST_NAME, validate_manifest


def build_one(asset_id: str, seed: int, out_root: Path, options: dict[str, Any] | None = None) -> AssetOutputs:
    """Build ``asset_id`` into ``out_root/<asset_id>`` and check what it wrote: its manifest, valid, and every file it reported."""
    out_dir = out_root / asset_id
    out_dir.mkdir(parents=True, exist_ok=True)
    outputs = ASSETS[asset_id](BuildContext(out_dir=out_dir, seed=seed, options=dict(options or {})))
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


def timed_build(asset_id: str, seed: int, out_root: Path, options: dict[str, Any]) -> tuple[AssetOutputs | None, str, float]:
    """One asset's build: its outputs (or why it failed) and how long it took."""
    started = time.perf_counter()
    try:
        outputs = build_one(asset_id, seed, out_root, options)
    except Exception as exc:  # noqa: BLE001 - report which asset failed, keep building the rest
        return None, f"{type(exc).__name__}: {exc}", time.perf_counter() - started
    return outputs, "", time.perf_counter() - started
