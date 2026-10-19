"""Build context handed to every asset generator, and the value it returns."""

from __future__ import annotations

import zlib
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np

# tools/procgen/core/context.py -> the repository root is three parents up.
REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_OUT_ROOT = REPO_ROOT / "assets" / "generated"
DEFAULT_SEED = 42


@dataclass(frozen=True)
class BuildContext:
    """Everything a generator may depend on, so a build is a pure function of this object.

    ``out_dir`` is the directory of the one asset being built (``<--out>/<asset_id>``); the
    CLI creates it. ``options`` carries per-asset overrides (tests use it for smaller builds).
    """

    out_dir: Path
    seed: int = DEFAULT_SEED
    options: Mapping[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        object.__setattr__(self, "out_dir", Path(self.out_dir))
        if (
            isinstance(self.seed, bool)
            or not isinstance(self.seed, int)
            or self.seed < 0
        ):
            raise ValueError(f"seed must be a non-negative integer, got {self.seed!r}")

    def rng(self, *stream: str | int) -> np.random.Generator:
        """Deterministic generator for this build.

        With no argument this is exactly ``numpy.random.default_rng(seed)``. Named streams
        (``ctx.rng("stars")``) are independent of each other, so changing how one part of an
        asset consumes randomness never shifts another part.
        """
        if not stream:
            return np.random.default_rng(self.seed)
        key = [self.seed]
        for part in stream:
            key.append(
                part if isinstance(part, int) else zlib.crc32(part.encode("utf-8"))
            )
        return np.random.default_rng(key)

    def option(self, name: str, default: Any) -> Any:
        return self.options.get(name, default)


@dataclass(frozen=True)
class AssetOutputs:
    """What ``build(ctx)`` returns: the manifest it wrote and every file it produced."""

    asset_id: str
    out_dir: Path
    manifest: dict[str, Any]
    files: tuple[Path, ...]
    warnings: tuple[str, ...] = ()

    @property
    def manifest_path(self) -> Path:
        return self.out_dir / "manifest.json"

    @property
    def splat_count(self) -> int:
        return int(self.manifest["lods"][0]["splats"])
