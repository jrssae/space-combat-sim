"""Print kits assembled into one reference mesh (M10-T68), so a ship sold as several printed parts can be compared like a one-piece STL.

A kit is a JSON file (``tools/refview/kits/<name>.json``) listing its parts: each part's STL under ``references/``, the file axes
that point to the ship's starboard, up and aft, a ``pivot_mm`` in the file that lands on ``at_mm`` in the kit (millimetres, x
starboard, y up from the spine's axis, z aft), and an optional ``follows``: the part whose ``at_mm`` this one's is measured from, so
moving the middle of a stack moves everything after it. Parts marked ``rotor`` turn together by the kit's ``rotor_roll_deg`` about the
spine (a drum's pose). ``plugs`` fill print-only sockets and peg holes with closed cylinders along the file's z; ``drop_voids``
removes closed hollows left to save filament (inward-facing shells). The assembled kit is scaled so its length is ``length_m`` (or
by a fixed ``metres_per_mm``) and
written in the generator's frame (nose at z = 0, the spine's axis at x = y = 0) as an STL and an ``.npy`` of triangles, which
``tools.refview.fidelity`` reads directly.

``fit`` places the parts against a guide STL (a whole-ship model good for layout only) by silhouette IoU, varying the offsets named
on the command line, and prints the values to copy into the kit file. Development only; outputs go under the gitignored
``references/``.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

try:
    from . import compare, refview
except ImportError:  # run as a script
    import compare  # type: ignore[no-redef]
    import refview  # type: ignore[no-redef]

ROOT = Path(__file__).resolve().parents[2]
REFERENCES = ROOT / "references"
KITS = Path(__file__).resolve().parent / "kits"
PLUG_SEGMENTS = 24
PLUG_MARGIN_MM = 0.02  # a plug a hair wider than its hole, so the union has no seam


@dataclass
class Plug:
    """A closed cylinder along the part file's z axis filling a socket or a peg hole."""

    center: tuple[float, float]
    radius: float
    z: tuple[float, float]


@dataclass
class Part:
    label: str
    file: str
    axes: tuple[str, str, str]
    pivot_mm: tuple[float, float, float]
    at_mm: tuple[float, float, float]
    follows: str | None = None
    rotor: bool = False
    plugs: list[Plug] = field(default_factory=list)


@dataclass
class Kit:
    name: str
    length_m: float
    parts: list[Part]
    rotor_roll_deg: float = 0.0
    drop_voids: bool = True
    out: str | None = None
    guide: dict | None = None
    metres_per_mm: float | None = None  # a fixed scale in place of ``length_m`` (the kit's thin tips may be printed short)


def _vec(values, n: int, what: str) -> tuple[float, ...]:
    if not isinstance(values, (list, tuple)) or len(values) != n:
        raise ValueError(f"{what}: expected {n} numbers, got {values!r}")
    return tuple(float(v) for v in values)


def parse_kit(data: dict) -> Kit:
    parts = []
    for p in data["parts"]:
        label = p["label"]
        plugs = [Plug(_vec(q["center"], 2, f"{label} plug center"), float(q["radius"]), _vec(q["z"], 2, f"{label} plug z")) for q in p.get("plugs", [])]
        parts.append(Part(label, p["file"], tuple(p.get("axes", ("+x", "+y", "+z"))), _vec(p.get("pivot_mm", (0, 0, 0)), 3, f"{label} pivot_mm"),
                          _vec(p.get("at_mm", (0, 0, 0)), 3, f"{label} at_mm"), p.get("follows"), bool(p.get("rotor", False)), plugs))
    labels = [p.label for p in parts]
    if len(set(labels)) != len(labels):
        raise ValueError("kit part labels must be unique")
    seen: set[str] = set()
    for p in parts:  # a part follows one listed before it, so positions resolve in one pass
        if p.follows is not None and p.follows not in seen:
            raise ValueError(f"{p.label} follows {p.follows!r}, which is not listed before it")
        seen.add(p.label)
    return Kit(data["name"], float(data["length_m"]), parts, float(data.get("rotor_roll_deg", 0.0)), bool(data.get("drop_voids", True)),
               data.get("out"), data.get("guide"), float(data["metres_per_mm"]) if data.get("metres_per_mm") else None)


def load_kit(path: Path) -> Kit:
    return parse_kit(json.loads(Path(path).read_text()))


# --- geometry --------------------------------------------------------------------------------------------------------
def cylinder(center: tuple[float, float], radius: float, z0: float, z1: float, segments: int = PLUG_SEGMENTS) -> np.ndarray:
    """A closed cylinder along z, wound outward."""
    a = np.linspace(0.0, 2.0 * math.pi, segments, endpoint=False)
    ring = np.stack([center[0] + radius * np.cos(a), center[1] + radius * np.sin(a)], axis=1)
    tris = []
    for i in range(segments):
        (xa, ya), (xb, yb) = ring[i], ring[(i + 1) % segments]
        tris += [[[xa, ya, z0], [xb, yb, z1], [xa, ya, z1]], [[xa, ya, z0], [xb, yb, z0], [xb, yb, z1]]]
        tris += [[[center[0], center[1], z0], [xb, yb, z0], [xa, ya, z0]], [[center[0], center[1], z1], [xa, ya, z1], [xb, yb, z1]]]
    return np.asarray(tris, dtype=float)


def signed_volumes(tris: np.ndarray) -> np.ndarray:
    return np.einsum("ij,ij->i", tris[:, 0], np.cross(tris[:, 1], tris[:, 2])) / 6.0


def without_voids(tris: np.ndarray) -> np.ndarray:
    """The mesh less its closed hollows: a shell wound inward (negative volume) is a cavity inside the part, not a surface of it."""
    labels = refview.shells(tris)
    vol = signed_volumes(tris)
    ids, inverse = np.unique(labels, return_inverse=True)
    per_shell = np.bincount(inverse, weights=vol, minlength=len(ids))
    return tris[per_shell[inverse] >= 0.0]


def roll_matrix(deg: float) -> np.ndarray:
    a = math.radians(deg)
    return np.array([[math.cos(a), -math.sin(a), 0.0], [math.sin(a), math.cos(a), 0.0], [0.0, 0.0, 1.0]])


def resolved_at(kit: Kit) -> dict[str, np.ndarray]:
    """Each part's ``at_mm`` in the kit frame, ``follows`` chains added up."""
    out: dict[str, np.ndarray] = {}
    for p in kit.parts:
        base = out[p.follows] if p.follows else np.zeros(3)
        out[p.label] = base + np.asarray(p.at_mm)
    return out


def part_in_file(part: Part, tris: np.ndarray, drop_voids: bool) -> np.ndarray:
    """The part's triangles in its own file frame, hollows dropped and sockets plugged."""
    if drop_voids:
        tris = without_voids(tris)
    plugs = [cylinder(q.center, q.radius + PLUG_MARGIN_MM, *q.z) for q in part.plugs]
    return np.concatenate([tris, *plugs]) if plugs else tris


def place(part: Part, tris_file: np.ndarray, at: np.ndarray, roll_deg: float) -> np.ndarray:
    """File-frame triangles to the kit frame (mm): the axes mapping about the pivot, moved to ``at``, a rotor turned about the spine."""
    m = refview.frame_matrix(*part.axes)
    out = (tris_file - np.asarray(part.pivot_mm)) @ m.T + at
    if part.rotor and roll_deg:
        out = out @ roll_matrix(roll_deg).T
    return out


def read_part(part: Part, root: Path) -> np.ndarray:
    raw, _ = refview.read_stl(Path(root) / part.file)
    return np.asarray(raw, dtype=float).reshape(-1, 3, 3)


@dataclass
class Assembly:
    tris: np.ndarray  # (n, 3, 3) metres, generator frame
    labels: np.ndarray  # part index per triangle
    metres_per_mm: float
    length_mm: float


def assemble(kit: Kit, root: Path = REFERENCES, cache: dict[str, np.ndarray] | None = None) -> Assembly:
    """The whole kit in the generator's frame, scaled to ``kit.length_m`` (or by ``kit.metres_per_mm``)."""
    at = resolved_at(kit)
    placed, labels = [], []
    for i, part in enumerate(kit.parts):
        if cache is not None and part.label in cache:
            file_tris = cache[part.label]
        else:
            file_tris = part_in_file(part, read_part(part, root), kit.drop_voids)
            if cache is not None:
                cache[part.label] = file_tris
        t = place(part, file_tris, at[part.label], kit.rotor_roll_deg)
        placed.append(t)
        labels.append(np.full(len(t), i, dtype=np.int32))
    tris = np.concatenate(placed)
    z = tris[:, :, 2]
    z0, z1 = float(z.min()), float(z.max())
    scale = kit.metres_per_mm or kit.length_m / (z1 - z0)
    tris = tris * scale
    tris[:, :, 2] -= z0 * scale
    return Assembly(tris, np.concatenate(labels), scale, z1 - z0)


def write_outputs(kit: Kit, asm: Assembly, out_stem: Path) -> list[Path]:
    out_stem.parent.mkdir(parents=True, exist_ok=True)
    stl, npy, info = out_stem.with_suffix(".stl"), out_stem.with_suffix(".npy"), out_stem.with_suffix(".json")
    refview.write_binary_stl(stl, asm.tris.astype(np.float32), header=f"{kit.name} assembled kit".encode())
    np.save(npy, asm.tris)
    lo, hi = asm.tris.reshape(-1, 3).min(axis=0), asm.tris.reshape(-1, 3).max(axis=0)
    info.write_text(json.dumps({
        "kit": kit.name, "length_m": kit.length_m, "length_mm": round(asm.length_mm, 4), "metres_per_mm": round(asm.metres_per_mm, 5),
        "rotor_roll_deg": kit.rotor_roll_deg, "triangles": int(len(asm.tris)), "bbox_m": [lo.round(2).tolist(), hi.round(2).tolist()],
        "parts": {p.label: int((asm.labels == i).sum()) for i, p in enumerate(kit.parts)},
    }, indent=1) + "\n")
    return [stl, npy, info]


# --- fitting against a guide -----------------------------------------------------------------------------------------
def load_guide(kit: Kit, root: Path = REFERENCES) -> np.ndarray:
    """The kit's guide STL (``guide``: ``stl``, ``mapping``, ``axis``) in the generator frame at the kit's length."""
    g = kit.guide
    if not g:
        raise ValueError(f"kit {kit.name} names no guide")
    raw, _ = refview.read_stl(Path(root) / g["stl"])
    ship, _ = refview.to_ship_frame(raw, refview.frame_matrix(*g["mapping"]), kit.length_m)
    return np.asarray(ship).reshape(-1, 3, 3) - np.asarray(g.get("axis", (0.0, 0.0, 0.0)))


def silhouette_score(guide: np.ndarray, tris: np.ndarray, length: float, pixel_fraction: float) -> dict[str, float]:
    comp = compare.compare_shapes(guide, tris, length, pixel_fraction=pixel_fraction)
    return {name: v.iou for name, v in comp.views.items()}


def parse_vary(spec: str) -> tuple[str, int | None, float, float]:
    """``label:axis:span:step`` (``middle:z:3:0.25``) or ``roll:span:step`` (degrees about the current roll)."""
    bits = spec.split(":")
    if bits[0] == "roll" and len(bits) == 3:
        return "roll", None, float(bits[1]), float(bits[2])
    if len(bits) != 4 or bits[1] not in "xyz":
        raise ValueError(f"--vary {spec!r}: expected label:axis:span:step or roll:span:step")
    return bits[0], "xyz".index(bits[1]), float(bits[2]), float(bits[3])


def fit(kit: Kit, guide: np.ndarray, varies: list[str], passes: int = 2, pixel_fraction: float = 0.004, root: Path = REFERENCES,
        log=print) -> Kit:
    """Coordinate search: each named offset in turn over its span, keeping the best mean silhouette IoU; returns the moved kit."""
    by_label = {p.label: p for p in kit.parts}
    cache: dict[str, np.ndarray] = {}

    def score() -> float:
        s = silhouette_score(guide, assemble(kit, root, cache).tris, kit.length_m, pixel_fraction)
        return float(np.mean(list(s.values())))

    best = score()
    log(f"start: mean IoU {best:.4f}")
    for _ in range(passes):
        for spec in varies:
            label, axis, span, step = parse_vary(spec)
            if label != "roll" and label not in by_label:
                raise ValueError(f"--vary {spec!r}: no part {label!r}")
            start = kit.rotor_roll_deg if label == "roll" else by_label[label].at_mm[axis]
            best_v = start
            for d in np.arange(-span, span + step / 2, step):
                v = start + float(d)
                _set(kit, by_label, label, axis, v)
                s = score()
                if s > best + 1e-6:
                    best, best_v = s, v
            _set(kit, by_label, label, axis, best_v)
            log(f"{spec}: {best_v:.3f} (mean IoU {best:.4f})")
    return kit


def _set(kit: Kit, by_label: dict[str, Part], label: str, axis: int | None, value: float) -> None:
    if label == "roll":
        kit.rotor_roll_deg = value
        return
    at = list(by_label[label].at_mm)
    at[axis] = value
    by_label[label].at_mm = tuple(at)


def kit_path(name: str) -> Path:
    p = Path(name)
    return p if p.suffix == ".json" else KITS / f"{name}.json"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python3 -m tools.refview.kit", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="assemble the kit and write the STL, .npy and a summary")
    b.add_argument("kit", help="a kit name under tools/refview/kits/ or a path to its JSON")
    b.add_argument("--roll", type=float, default=None, help="rotor roll in degrees (default: the kit's)")
    b.add_argument("--out", type=Path, default=None, help="output stem (default: references/<kit's out>)")
    f = sub.add_parser("fit", help="place parts against the kit's guide STL by silhouette IoU")
    f.add_argument("kit")
    f.add_argument("--vary", action="append", required=True, help="label:axis:span:step (mm) or roll:span:step (deg), repeatable")
    f.add_argument("--passes", type=int, default=2)
    f.add_argument("--pixel-frac", type=float, default=0.004)
    args = ap.parse_args(argv)
    kit = load_kit(kit_path(args.kit))
    if args.cmd == "build":
        if args.roll is not None:
            kit.rotor_roll_deg = args.roll
        asm = assemble(kit)
        stem = args.out or REFERENCES / (kit.out or f"{kit.name} assembled")
        for p in write_outputs(kit, asm, stem):
            print(p)
        print(f"{len(asm.tris)} triangles, {asm.length_mm:.3f} mm long, {asm.metres_per_mm:.4f} m per mm")
        return 0
    guide = load_guide(kit)
    fit(kit, guide, args.vary, args.passes, args.pixel_frac)
    print(json.dumps({"rotor_roll_deg": kit.rotor_roll_deg, "at_mm": {p.label: [round(v, 3) for v in p.at_mm] for p in kit.parts}}, indent=1))
    s = silhouette_score(guide, assemble(kit).tris, kit.length_m, compare.PIXEL_FRACTION)
    print("silhouette IoU at the default pixel:", {k: round(v, 4) for k, v in s.items()})
    return 0


if __name__ == "__main__":
    sys.exit(main())
