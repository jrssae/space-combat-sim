"""A capital hull's built mounts against its loadout (M10-T03's ``data/capitals/loadouts.json``): each hull task checks that
its manifest carries the weapons, interceptors and launch bays its loadout row names, on mounts of the right kind.

Pure: it reads the two JSON documents as dicts, so a hull's Python test and any later tool share one rule.
"""

from __future__ import annotations

import json
from collections import Counter
from collections.abc import Mapping
from pathlib import Path
from typing import Any

LOADOUTS = Path(__file__).resolve().parents[3] / "data" / "capitals" / "loadouts.json"
# Which hardpoint kind (parts/capital.py) carries each weapon kind of the loadout file.
MOUNT_FOR_KIND = {
    "bolt_light": "turret", "bolt_medium": "turret", "bolt_heavy": "turret", "bolt_fixed": "turret",
    "beam_pulsed": "beam", "beam_sustained": "beam",
    "missile": "missile", "torpedo": "missile",
    "interceptor": "interceptor",
    "mine_energy": "mine", "mine_guided": "mine",
}  # fmt: skip


def read(path: Path = LOADOUTS) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def problems(hardpoints: Mapping[str, Any], loadouts: Mapping[str, Any], hull_id: str) -> list[str]:
    """What differs between a built hull's ``hardpoints.json`` and its loadout row; empty when they agree."""
    out: list[str] = []
    entry = loadouts["hulls"].get(hull_id)
    if entry is None:
        return [f"{hull_id}: no loadout row"]
    weapons = loadouts["weapons"]
    wanted = Counter({**entry["weapons"], **entry["interceptors"]})
    built: Counter[str] = Counter()
    for mount in hardpoints.get("weapons", []):
        wid = mount.get("weapon")
        if wid is None:
            out.append(f"mount {mount['name']!r} names no weapon")
            continue
        built[wid] += 1
        if wid not in weapons:
            out.append(f"mount {mount['name']!r}: unknown weapon {wid!r}")
        elif MOUNT_FOR_KIND.get(weapons[wid]["kind"]) != mount["kind"]:
            out.append(f"mount {mount['name']!r} is a {mount['kind']}, {wid!r} needs a {MOUNT_FOR_KIND.get(weapons[wid]['kind'])}")
    if built != wanted:
        out.append(f"weapons built {dict(sorted(built.items()))}, the loadout has {dict(sorted(wanted.items()))}")
    launched: Counter[str] = Counter()
    for bay in hardpoints.get("bays", []):
        launched[bay.get("craft", "?")] += int(bay.get("capacity", 0))
    if launched != Counter(entry["launches"]):
        out.append(f"bays launch {dict(sorted(launched.items()))}, the loadout has {dict(sorted(entry['launches'].items()))}")
    return out


__all__ = ["LOADOUTS", "MOUNT_FOR_KIND", "problems", "read"]
