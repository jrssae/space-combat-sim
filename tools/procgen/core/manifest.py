"""``manifest.json``: the contract between a generator and the game (docs/architecture.md section 9)."""

from __future__ import annotations

import json
import math
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

MANIFEST_NAME = "manifest.json"
KIND_ASSET = "asset"  # the default: a generated model (``aabb_*``, ``centroid_offset``, usually a textured ``mesh``)
KIND_AUDIO = "audio"  # a sound set: ``sounds`` and no bounds
FRAME = "godot"
UNITS = "m"


def sound_entry(
    file: str, samples: int, sample_rate: int, peak_dbfs: float, loop: tuple[int, int] | None = None
) -> dict[str, Any]:
    """One sound of an audio manifest: its WAV, length, rate, peak level and, for a loop, the loop points in samples."""
    entry: dict[str, Any] = {
        "file": file,
        "samples": int(samples),
        "sample_rate": int(sample_rate),
        "duration_s": round(int(samples) / int(sample_rate), 6),
        "peak_dbfs": round(float(peak_dbfs), 3),
    }
    if loop is not None:
        entry["loop_begin"], entry["loop_end"] = int(loop[0]), int(loop[1])
    return entry


def build_audio_manifest(
    asset_id: str,
    generator_version: int,
    seed: int,
    sounds: Mapping[str, Mapping[str, Any]],
    extra: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Assemble and validate the manifest of a sound set (``kind`` ``audio``): ``sounds`` maps names to `sound_entry`s."""
    manifest: dict[str, Any] = {
        "asset_id": asset_id,
        "generator_version": int(generator_version),
        "seed": int(seed),
        "kind": KIND_AUDIO,
        "frame": FRAME,
        "units": UNITS,
        "sounds": {name: dict(entry) for name, entry in sounds.items()},
        "files": {name: str(entry["file"]) for name, entry in sounds.items()},
    }
    for key, value in (extra or {}).items():
        if key in manifest:
            raise ValueError(f"extra manifest key {key!r} collides with a reserved key")
        manifest[key] = value
    validate_manifest(manifest)
    return manifest


def _vec3(value: Sequence[float], digits: int = 4) -> list[float]:
    return [round(float(v), digits) for v in value]


def build_manifest(
    asset_id: str,
    generator_version: int,
    seed: int,
    aabb_min: Sequence[float],
    aabb_max: Sequence[float],
    centroid_offset: Sequence[float],
    files: Mapping[str, str] | None = None,
    extra: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Assemble and validate a manifest dict.

    ``aabb_*`` bound the asset in the Godot frame after re-centring.
    ``centroid_offset`` is the Godot-frame vector that was subtracted from the authored
    positions: placing the node at ``anchor + centroid_offset`` restores the authored frame.
    ``extra`` adds asset-specific keys (the textured ``mesh`` section, counts, chunks).
    """
    manifest: dict[str, Any] = {
        "asset_id": asset_id,
        "generator_version": int(generator_version),
        "seed": int(seed),
        "frame": FRAME,
        "units": UNITS,
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
    """A real, finite number: NaN and infinity would slip past every ``<= 0`` check."""
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return True
    return isinstance(value, float) and math.isfinite(value)


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

    kind = manifest.get("kind", KIND_ASSET)
    if kind not in (KIND_ASSET, KIND_AUDIO):
        raise ValueError(f"manifest 'kind' must be {KIND_ASSET!r} or {KIND_AUDIO!r}, got {kind!r}")
    if kind == KIND_AUDIO:
        _validate_sounds(manifest)
        return

    if "mesh" in manifest:
        validate_mesh_section(manifest["mesh"])

    for key in ("aabb_min", "aabb_max", "centroid_offset"):
        _check_vec3(manifest, key)
    if any(lo > hi for lo, hi in zip(manifest["aabb_min"], manifest["aabb_max"])):
        raise ValueError("manifest aabb_min must not exceed aabb_max")

    files = manifest.get("files")
    if not isinstance(files, dict) or not all(
        isinstance(k, str) and isinstance(v, str) for k, v in files.items()
    ):
        raise ValueError("manifest 'files' must map names to file names")


MESH_SURFACE_KEYS = ("name", "blend", "albedo", "normal", "orm", "emissive", "transmittance")


def validate_mesh_section(entry: Any) -> None:
    """The textured mesh contract (M4-T30a, the milestone's "The contract M5 builds against"): the ``.glb``, its counts and box,
    the atlas's texel and size, the mean albedo, one surface entry per primitive naming the four maps, and the lods list."""
    if not isinstance(entry, dict):
        raise ValueError("manifest 'mesh' must be an object")  # noqa: TRY004
    if not isinstance(entry.get("file"), str) or not entry["file"].endswith(".glb"):
        raise ValueError("manifest mesh.file must be a .glb file name")
    for key in ("triangles", "vertices", "atlas_px"):
        value = entry.get(key)
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise ValueError(f"manifest mesh.{key} must be a positive integer")
    if not _is_number(entry.get("texel_m")) or entry["texel_m"] <= 0:
        raise ValueError("manifest mesh.texel_m must be a positive number")
    for key in ("aabb_min", "aabb_max", "mean_albedo"):
        _check_vec3(entry, key)
    if any(lo > hi for lo, hi in zip(entry["aabb_min"], entry["aabb_max"])):
        raise ValueError("manifest mesh.aabb_min must not exceed aabb_max")
    surfaces = entry.get("surfaces")
    if not isinstance(surfaces, list) or not surfaces:
        raise ValueError("manifest mesh.surfaces must be a non-empty list")
    for index, surface in enumerate(surfaces):
        if not isinstance(surface, dict):
            raise ValueError(f"manifest mesh.surfaces[{index}] must be an object")  # noqa: TRY004
        missing = [key for key in MESH_SURFACE_KEYS if key not in surface]
        if missing:
            raise ValueError(f"manifest mesh.surfaces[{index}] lacks {missing}")
        for key in ("albedo", "normal", "orm", "emissive"):
            if not isinstance(surface[key], str) or not surface[key].endswith(".png"):
                raise ValueError(f"manifest mesh.surfaces[{index}].{key} must be a .png file name")
        if not isinstance(surface["name"], str) or not surface["name"]:
            raise ValueError(f"manifest mesh.surfaces[{index}].name must be a non-empty string")
        if not isinstance(surface["blend"], bool):
            raise ValueError(f"manifest mesh.surfaces[{index}].blend must be a bool")
        if not _is_number(surface["transmittance"]) or not 0.0 <= surface["transmittance"] < 1.0:
            raise ValueError(f"manifest mesh.surfaces[{index}].transmittance must be in [0, 1)")
    if "livery" in entry:
        _validate_livery(entry["livery"])
    lods = entry.get("lods")
    if not isinstance(lods, list):
        raise ValueError("manifest mesh.lods must be a list")
    for index, lod in enumerate(lods):
        if not isinstance(lod, dict) or not isinstance(lod.get("file"), str) or not _is_number(lod.get("from_m")):
            raise ValueError(f"manifest mesh.lods[{index}] must name a file, triangles and from_m")
        if not isinstance(lod.get("triangles"), int) or lod["triangles"] <= 0:
            raise ValueError(f"manifest mesh.lods[{index}].triangles must be a positive integer")


def _validate_livery(livery: Any) -> None:
    """The ``mesh.livery`` section (M4-T30b): the hull paint, the digit atlas, each pattern's stripes, the number fields and the
    liveries naming patterns and fields that exist."""
    if not isinstance(livery, dict):
        raise ValueError("manifest mesh.livery must be an object")  # noqa: TRY004
    _check_vec3(livery, "hull_paint")
    digits = livery.get("digits")
    if not isinstance(digits, dict) or not isinstance(digits.get("file"), str) or not digits["file"].endswith(".png"):
        raise ValueError("manifest mesh.livery.digits must name a .png file")
    patterns, fields = livery.get("patterns"), livery.get("number_fields")
    if not isinstance(patterns, dict) or "plain" not in patterns or not isinstance(fields, dict):
        raise ValueError("manifest mesh.livery needs patterns (with plain) and number_fields")
    for name, stripes in patterns.items():
        for index, stripe in enumerate(stripes if isinstance(stripes, list) else [None]):
            if not isinstance(stripe, dict) or not all(key in stripe for key in ("zones", "axis", "lo", "hi", "slot", "facing", "min_facing")):
                raise ValueError(f"manifest mesh.livery.patterns.{name}[{index}] must have zones, axis, lo, hi, slot, facing, min_facing")
    for name, field in fields.items():
        if not isinstance(field, dict) or not all(key in field for key in ("zones", "centre", "right", "up", "facing", "height_m")):
            raise ValueError(f"manifest mesh.livery.number_fields.{name} must have zones, centre, right, up, facing, height_m")
    rows = dict(livery.get("liveries", {}))
    rows["plain"] = livery.get("plain")
    for name, row in rows.items():
        if not isinstance(row, dict) or row.get("pattern") not in patterns or any(f not in fields for f in row.get("numbers", [])):
            raise ValueError(f"manifest mesh.livery livery {name!r} must name a pattern and number fields that exist")


def _validate_sounds(manifest: Mapping[str, Any]) -> None:
    """An audio manifest has ``sounds``; every sound names a file and has positive length and rate."""
    sounds = manifest.get("sounds")
    if not isinstance(sounds, dict) or not sounds:
        raise ValueError("an audio manifest needs a non-empty 'sounds' object")
    for name, entry in sounds.items():
        if not isinstance(entry, dict):
            raise ValueError(f"manifest sounds[{name!r}] must be an object")  # noqa: TRY004
        if not isinstance(entry.get("file"), str) or not entry["file"].endswith(".wav"):
            raise ValueError(f"manifest sounds[{name!r}].file must be a .wav file name")
        for key in ("samples", "sample_rate"):
            value = entry.get(key)
            if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
                raise ValueError(f"manifest sounds[{name!r}].{key} must be a positive integer")
        if not _is_number(entry.get("peak_dbfs")):
            raise ValueError(f"manifest sounds[{name!r}].peak_dbfs must be a number")
        if ("loop_begin" in entry) != ("loop_end" in entry):
            raise ValueError(f"manifest sounds[{name!r}] needs both loop_begin and loop_end or neither")
        if "loop_begin" in entry and not 0 <= entry["loop_begin"] < entry["loop_end"] <= entry["samples"]:
            raise ValueError(f"manifest sounds[{name!r}] loop points must satisfy 0 <= begin < end <= samples")
    files = manifest.get("files")
    if not isinstance(files, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in files.items()):
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
