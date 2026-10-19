"""``manifest.json``: the contract between a generator and the game (docs/architecture.md section 9)."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

MANIFEST_NAME = "manifest.json"
FRAME = "godot"
UNITS = "m"


def lod_entry(level: int, file: str, splats: int, spacing_m: float) -> dict[str, Any]:
    return {
        "level": int(level),
        "file": file,
        "splats": int(splats),
        "spacing_m": float(spacing_m),
    }


def _vec3(value: Sequence[float], digits: int = 4) -> list[float]:
    return [round(float(v), digits) for v in value]


def build_manifest(
    asset_id: str,
    generator_version: int,
    seed: int,
    lods: Sequence[Mapping[str, Any]],
    aabb_min: Sequence[float],
    aabb_max: Sequence[float],
    centroid_offset: Sequence[float],
    files: Mapping[str, str] | None = None,
    extra: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Assemble and validate a manifest dict.

    ``aabb_*`` bound the written splat centres in the Godot frame after re-centring (the
    box GDGS reports for the imported resource, up to the Rz(180) flip).
    ``centroid_offset`` is the Godot-frame vector that was subtracted from the authored
    positions: placing the node at ``anchor + centroid_offset`` restores the authored frame.
    ``extra`` adds asset-specific keys (e.g. per-population splat counts).
    """
    manifest: dict[str, Any] = {
        "asset_id": asset_id,
        "generator_version": int(generator_version),
        "seed": int(seed),
        "frame": FRAME,
        "units": UNITS,
        "lods": [dict(entry) for entry in lods],
        "aabb_min": _vec3(aabb_min),
        "aabb_max": _vec3(aabb_max),
        "centroid_offset": _vec3(centroid_offset),
        "files": dict(files or {}),
    }
    for key, value in (extra or {}).items():
        if key in manifest:
            raise ValueError(f"extra manifest key {key!r} collides with a reserved key")
        manifest[key] = value
    validate_manifest(manifest)
    return manifest


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _check_vec3(manifest: Mapping[str, Any], key: str) -> None:
    value = manifest.get(key)
    if not (
        isinstance(value, list)
        and len(value) == 3
        and all(_is_number(v) for v in value)
    ):
        raise ValueError(f"manifest {key!r} must be a list of 3 numbers")


def validate_manifest(manifest: Mapping[str, Any]) -> None:
    """Raise ``ValueError`` unless ``manifest`` honours the output contract."""
    if not isinstance(manifest.get("asset_id"), str) or not manifest["asset_id"]:
        raise ValueError("manifest 'asset_id' must be a non-empty string")
    for key in ("generator_version", "seed"):
        if not isinstance(manifest.get(key), int) or isinstance(manifest[key], bool):
            raise ValueError(f"manifest {key!r} must be an integer")  # noqa: TRY004
    if manifest.get("frame") != FRAME:
        raise ValueError(f"manifest 'frame' must be {FRAME!r}")
    if manifest.get("units") != UNITS:
        raise ValueError(f"manifest 'units' must be {UNITS!r}")

    lods = manifest.get("lods")
    if not isinstance(lods, list) or not lods:
        raise ValueError("manifest 'lods' must be a non-empty list (lods[0] is LOD 0)")
    for index, entry in enumerate(lods):
        if not isinstance(entry, dict):
            raise ValueError(f"manifest lods[{index}] must be an object")  # noqa: TRY004
        if entry.get("level") != index:
            raise ValueError(f"manifest lods[{index}].level must equal {index}")
        if not isinstance(entry.get("file"), str) or not entry["file"]:
            raise ValueError(f"manifest lods[{index}].file must be a non-empty string")
        splats = entry.get("splats")
        if not isinstance(splats, int) or isinstance(splats, bool) or splats <= 0:
            raise ValueError(
                f"manifest lods[{index}].splats must be a positive integer"
            )
        if not _is_number(entry.get("spacing_m")) or entry["spacing_m"] <= 0:
            raise ValueError(
                f"manifest lods[{index}].spacing_m must be a positive number"
            )

    for key in ("aabb_min", "aabb_max", "centroid_offset"):
        _check_vec3(manifest, key)
    if any(lo > hi for lo, hi in zip(manifest["aabb_min"], manifest["aabb_max"])):
        raise ValueError("manifest aabb_min must not exceed aabb_max")

    files = manifest.get("files")
    if not isinstance(files, dict) or not all(
        isinstance(k, str) and isinstance(v, str) for k, v in files.items()
    ):
        raise ValueError("manifest 'files' must map names to file names")


def write_manifest(out_dir: Path, manifest: Mapping[str, Any]) -> Path:
    """Write ``manifest.json`` (stable key order, LF newlines, no timestamps)."""
    validate_manifest(manifest)
    path = Path(out_dir) / MANIFEST_NAME
    path.write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n"
    )
    return path


def read_manifest(path: Path) -> dict[str, Any]:
    """Read a manifest from a file or from the asset directory holding it."""
    path = Path(path)
    if path.is_dir():
        path = path / MANIFEST_NAME
    manifest = json.loads(path.read_text(encoding="utf-8"))
    validate_manifest(manifest)
    return manifest
