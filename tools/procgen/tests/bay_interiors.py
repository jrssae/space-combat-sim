"""The checks every capital with bays shares (M10-T72, Q68): its bays' halls are on the interior layer, written apart from the
hull's own glb, so the game keeps the sun out of them."""

from __future__ import annotations

import unittest
from pathlib import Path
from typing import Any

import numpy as np

from tools.procgen.core.glb import read_glb
from tools.procgen.parts import capital as cp
from tools.procgen.parts import capital_bays as bays

MIN_FACES = 10  # a hall's four walls and its back, two triangles each


def halls(hp: dict[str, Any]) -> list[bays.Hall]:
    """The halls of a built hull's ``bays`` hardpoints (body frame)."""
    out = []
    for b in hp.get("bays", []):
        if b.get("kind") != cp.BAY:
            continue
        point = cp.Hardpoint(b["name"], cp.BAY, b["position"], b["forward"], b["up"],
                             {bays.EXIT: b[bays.EXIT], "mouth_m": b["mouth_m"], "depth_m": b["depth_m"]})
        out.append(bays.hall_of(point))
    return out


def _centroids(path: Path, opaque_only: bool = False) -> np.ndarray:
    prims = [p for p in read_glb(path).primitives if not (opaque_only and p.blend)]
    tris = [np.asarray(p.positions, dtype=float)[np.asarray(p.indices).reshape(-1, 3)].mean(axis=1) for p in prims if len(p.indices)]
    return np.concatenate(tris) if tris else np.zeros((0, 3))


def check(test: unittest.TestCase, out_dir: Path, manifest: dict[str, Any], hp: dict[str, Any], bay_count: int) -> None:
    """Every bay's hall is in the hull's ``interior_file`` and nowhere in its own glb, and nothing else is."""
    entry = manifest["pieces"]["hull"]["mesh"]
    listed = halls(hp)
    test.assertEqual(len(listed), bay_count)
    test.assertEqual(entry.get("interior_file"), f"{manifest['asset_id']}_interior.glb")
    inner = _centroids(out_dir / entry["interior_file"])
    test.assertEqual(len(inner), entry["interior_triangles"])
    test.assertTrue(np.all(bays.inside_halls(listed, inner)), "only the halls' faces are on the interior layer")
    for hall in listed:
        test.assertGreaterEqual(int(bays.inside_halls([hall], inner).sum()), MIN_FACES, f"{hall.name}'s walls, deck and back")
    outer = _centroids(out_dir / entry["file"], opaque_only=True)
    test.assertFalse(np.any(bays.inside_halls(listed, outer)), "no hall's face is left in the sun's light")
    test.assertEqual(manifest["mesh"].get("interior_file"), entry["interior_file"], "the whole-hull viewers see it too")


__all__ = ["MIN_FACES", "check", "halls"]
