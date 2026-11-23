"""The capital ships' build pipeline (M10-T05, D12.1; docs/assets-capital.md, "Capital framework").

A capital generator composes modules of the capital parts library (``parts/capital.py``), names the damage section each
belongs to and hands a :class:`CapitalSpec` to :func:`build`, which writes the whole output contract:

* **pieces**: the hull, and one piece per rotating section (a pivot on its axis and a spin), each a textured mesh on an atlas
  of its own with the high texture set and the low one a mip level down (Q38), through the civilians' writer
  (``core/civilian.py``). All pieces share one
  near-field detail tile laid in their own space by the renderer (D72's two texel tiers), named by every opaque surface's
  ``world_detail``;
* **sections** (``manifest.sections[]``): the damage sections. A section is whole modules: its break-up chunk is cut from
  its piece's mesh along its modules' boundaries (``core/chunks.py``) and its collision is one entry of
  ``manifest.collision.pieces`` (M7's builder, ``core/collision.py``), so a chunk keeps its collision;
* **hardpoints** (``hardpoints.json``): the ships' contract plus ``weapons``, ``bays``, ``engines``, ``rotors`` and
  ``lights``, each naming its section.

Frames: modules are placed in the authored frame (x to starboard, y up, z aft from the bow). The body frame is centred on
the visible surface's centroid (``manifest.centroid_offset``); a rotating piece's mesh and collision are in its own frame,
on its pivot. Hardpoints, chunk offsets and section boxes are all in the body frame with the rotating pieces at rest.

Starboard modules (``side`` RIGHT) and sections named ``..._r`` get their port twins here.
"""

from __future__ import annotations

import dataclasses
import json
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..parts import capital as cp
from ..parts import mass_centroid, total_mass
from ..styles.capital import CapitalStyle
from . import civilian as cv
from . import collision as col
from . import glyphs
from .budgets import LOW_SHRINK, low_set_mb, texture_mb
from .context import AssetOutputs, BuildContext
from .image import write_png
from .manifest import build_manifest, write_manifest
from .silhouette import far_section
from .textured_mesh import import_sidecar
from .textures import Marking

Vec3 = tuple[float, float, float]

SECTION_KINDS = ("reactor", "magazine", "fuel", "bridge", "hangar", "engine", "habitat", "structure")
EXPLOSIVE_KINDS = ("reactor", "magazine", "fuel")  # a section of these blows the ship up (D12.5)
HULL_PIECE = "hull"
HARDPOINTS_NAME = "hardpoints.json"
DETAIL_KEYS = ("albedo", "normal")
SHARE_TOLERANCE = 1e-6
CHASE_ANCHOR_SHARE = (0.3, 1.2)
CABIN_RANGE_SHARE = 0.05
MIN_SPACING_M, MAX_SPACING_M, SPACING_PER_LENGTH = 0.5, 4.0, 1.0 / 300.0


@dataclass(frozen=True)
class Section:
    """A damage section: its kind, its share of the hull's points, the energy of its blast (explosive kinds only), the piece
    it is part of and where its chunk breaks away (authored frame; by default the point of its box nearest the ship's
    middle)."""

    name: str
    kind: str
    hull_share: float
    blast_energy_j: float = 0.0
    piece: str = HULL_PIECE
    joint: Vec3 | None = None

    def twin(self) -> Section:
        joint = None if self.joint is None else (-self.joint[0], self.joint[1], self.joint[2])
        return dataclasses.replace(self, name=cp.left_name(self.name), joint=joint)


@dataclass(frozen=True)
class PieceSpec:
    """A render piece: its atlas, and for a rotating one its pivot (authored frame, on its axis), axis and spin."""

    name: str = HULL_PIECE
    atlas_px: int = 2048
    pivot: Vec3 = (0.0, 0.0, 0.0)
    axis: Vec3 = (0.0, 0.0, 1.0)
    spin_rad_s: float = 0.0


@dataclass(frozen=True)
class Pose:
    position: Vec3
    forward: Vec3 = (0.0, 0.0, -1.0)
    up: Vec3 = (0.0, 1.0, 0.0)


@dataclass(frozen=True)
class JumpPoint:
    """Where the ship opens its own jump point: this far ahead of its bow on the axis, with this mouth."""

    ahead_m: float
    mouth_radius_m: float


@dataclass(frozen=True)
class CapitalSpec:
    """What a capital generator hands the framework. ``ship_class`` names its budget class (``core/budgets.py``);
    ``bridge`` is the view from its bridge (the cockpit camera); ``collision`` what one section's body part may carry;
    ``cover_*`` how close the collision must sit to the skin; ``notes`` are written into the manifest (what is not final)."""

    asset_id: str
    generator_version: int
    ship_class: str
    modules: tuple[cp.Module, ...]
    sections: tuple[Section, ...]
    style: CapitalStyle
    bridge: Pose
    pieces: tuple[PieceSpec, ...] = (PieceSpec(),)
    jump_point: JumpPoint | None = None
    collision: col.Budget = col.Budget(max_shapes=64)
    cover_tolerance_m: float = 1.0
    cover_reach_m: float = 2.5
    detail_px: int = 1024
    notes: tuple[str, ...] = ()
    markings: tuple[tuple[str, Marking], ...] = ()  # painted or lit decals baked into the hull's maps, by the module they belong to


# --- the section model (pure) ------------------------------------------------------------------------------------------
def all_sections(spec: CapitalSpec) -> list[Section]:
    """The sections with the port twin of every ``..._r`` one, twin after original."""
    out: list[Section] = []
    for s in spec.sections:
        out.append(s)
        if s.name.endswith("_r"):
            out.append(s.twin())
    return out


def all_modules(spec: CapitalSpec) -> list[cp.Module]:
    return cp.with_twins(spec.modules)


def problems(spec: CapitalSpec) -> list[str]:
    """Everything wrong with the spec's section model, in words; empty when it holds together."""
    out: list[str] = []
    sections = all_sections(spec)
    names = [s.name for s in sections]
    pieces = {p.name: p for p in spec.pieces}
    if len(pieces) != len(spec.pieces) or HULL_PIECE not in pieces:
        out.append(f"pieces must have unique names and include {HULL_PIECE!r}")
    if len(set(names)) != len(names):
        out.append("section names must be unique")
    for s in sections:
        if s.kind not in SECTION_KINDS:
            out.append(f"section {s.name!r}: unknown kind {s.kind!r}")
        if s.hull_share <= 0.0:
            out.append(f"section {s.name!r}: its hull share must be above zero")
        if s.piece not in pieces:
            out.append(f"section {s.name!r}: unknown piece {s.piece!r}")
        if s.kind in EXPLOSIVE_KINDS and s.blast_energy_j <= 0.0:
            out.append(f"section {s.name!r}: a {s.kind} section needs a blast energy")
        if s.kind not in EXPLOSIVE_KINDS and s.blast_energy_j != 0.0:
            out.append(f"section {s.name!r}: only reactor, magazine and fuel sections have a blast energy")
    total = sum(s.hull_share for s in sections)
    if abs(total - 1.0) > SHARE_TOLERANCE:
        out.append(f"the sections' hull shares add up to {total:.6f}, not 1")
    modules = all_modules(spec)
    module_names = [m.name for m in modules]
    if len(set(module_names)) != len(module_names):
        out.append("module names must be unique")
    held = {m.section for m in modules}
    for m in spec.modules:
        if m.side == cp.RIGHT and not m.name.endswith("_r"):
            out.append(f"module {m.name!r}: a starboard module's name ends in _r")
    for m in modules:
        if m.section not in names:
            out.append(f"module {m.name!r}: unknown section {m.section!r}")
    for s in sections:
        if s.name not in held:
            out.append(f"section {s.name!r} has no module")
    points = [h for m in modules for h in m.hardpoints]
    point_names = [h.name for h in points]
    if len(set(point_names)) != len(point_names):
        out.append("hardpoint names must be unique")
    engines = [h for h in points if h.kind == cp.ENGINE]
    thrust = sum(float(h.params.get("share", 0.0)) for h in engines)
    if engines and abs(thrust - 1.0) > SHARE_TOLERANCE:
        out.append(f"the engines' thrust shares add up to {thrust:.6f}, not 1")
    for p in spec.pieces:
        if p.name != HULL_PIECE and p.spin_rad_s == 0.0:
            out.append(f"piece {p.name!r}: a piece beside the hull is a rotating one and needs a spin")
        if p.name == HULL_PIECE and p.spin_rad_s != 0.0:
            out.append("the hull piece does not spin")
    return out


def dressed(spec: CapitalSpec, seed: int) -> list[cp.Module]:
    """The spec's modules (twins not yet made) wearing the style's skin: a layout per module in its own box."""
    skin = spec.style.skin
    out = []
    for k, m in enumerate(spec.modules):
        lo, hi = (tuple(float(c) for c in v) for v in m.part.mesh.bounds())
        if m.skin == cp.SKIN_HULL:
            layout = skin.hull_layout(lo, hi, seed + 131 * (k + 1))
        elif m.skin == cp.SKIN_FITTING:
            layout = skin.fitting_layout(lo, hi, seed + 131 * (k + 1))
        else:
            layout = m.part.seams
        out.append(dataclasses.replace(m, part=m.part.with_seams(layout)))
    return out


def section_shapes(modules: Sequence[cp.Module], sections: Sequence[Section], budget: col.Budget) -> dict[str, list[col.Shape]]:
    """Each section's convex shapes (authored frame), its modules' own, merged down to the budget."""
    out: dict[str, list[col.Shape]] = {s.name: [] for s in sections}
    for m in modules:
        out[m.section] += list(m.shapes)
    return {name: col.merge_to_budget(shapes, budget) for name, shapes in out.items()}


def default_spacing(length_m: float) -> float:
    """The surface samples' spacing for a hull this long: a three-hundredth of it, within half a metre and four."""
    return float(min(MAX_SPACING_M, max(MIN_SPACING_M, length_m * SPACING_PER_LENGTH)))


# --- hardpoints ----------------------------------------------------------------------------------------------------------
def _json_params(params: dict[str, Any], offset: np.ndarray) -> dict[str, Any]:
    return {k: cv.r(np.asarray(v, dtype=float) - offset) if k in cp.POINT_PARAMS else v for k, v in params.items()}


def hardpoint_lists(modules: Sequence[cp.Module], offset: np.ndarray) -> dict[str, list[dict[str, Any]]]:
    """The capital hardpoints by list (body frame): ``weapons``, ``bays``, ``engines``, ``lights``, ``marks`` (painted
    lettering, ``core/glyphs.py``) and, when a bay has one, ``doors`` (its roll-up door), in module order."""
    out: dict[str, list[dict[str, Any]]] = {"weapons": [], "bays": [], "engines": [], "lights": [], "marks": [], "doors": []}
    for m in modules:
        for h in m.hardpoints:
            base = {"name": h.name, "section": m.section, "position": cv.r(h.position - offset)}
            params = _json_params(dict(h.params), offset)
            if h.kind in cp.WEAPON_KINDS:
                out["weapons"].append({**base, "kind": h.kind, "forward": cv.r(h.forward), "up": cv.r(h.up), **params})
            elif h.kind in cp.LAUNCH_KINDS:
                out["bays"].append({**base, "kind": h.kind, "forward": cv.r(h.forward), "up": cv.r(h.up), **params})
            elif h.kind == cp.ENGINE:
                out["engines"].append({**base, "thrust": cv.r(h.forward), "exhaust": cv.r(-h.forward), **params})
            elif h.kind == cp.MARK:
                out["marks"].append({**base, "normal": cv.r(h.forward), "up": cv.r(h.up), **params})
            elif h.kind == cp.DOOR:
                out["doors"].append({**base, "forward": cv.r(h.forward), "up": cv.r(h.up), **params})
            else:
                out["lights"].append({**base, "direction": cv.r(h.forward), **params})
    if not out["doors"]:
        del out["doors"]  # a hull without doors writes what it always did
    return out


def _legacy_pods(engines: Sequence[dict[str, Any]]) -> list[dict[str, Any]]:
    """The engines in the ships' ``pods[]`` form, which the game's plumes read."""
    side = lambda x: "centre" if abs(x) < 1e-6 else ("right" if x > 0.0 else "left")  # noqa: E731
    return [{"name": e["name"], "side": side(e["position"][0]), "center": e["position"],
             "main": {"position": e["position"], "exhaust": e["exhaust"], "radius": e["radius_m"]}} for e in engines]


def _legacy_nav_lights(lights: Sequence[dict[str, Any]], bridge: list[float], length: float) -> dict[str, Any]:
    """The lamps in the ships' ``nav_lights`` form, which the game's light rig reads: the first port, starboard and top lamp,
    the first beacon as the top lamp and the bridge as the cabin's glow. Empty unless the hull has all four lamps (the
    game's parser takes the whole set or none)."""
    first: dict[str, dict[str, Any]] = {}
    for light in lights:
        first.setdefault(light["role"], light)
    if any(role not in first for role in ("port", "starboard", "top", "beacon")):
        return {}
    return {"port": first["port"]["position"], "starboard": first["starboard"]["position"], "top": first["top"]["position"],
            "top_lamp": first["beacon"]["position"], "top_lamp_range_m": first["beacon"]["range_m"],
            "cabin": bridge, "cabin_range_m": round(CABIN_RANGE_SHARE * length, 2)}


# --- the build -----------------------------------------------------------------------------------------------------------
@dataclass
class _Piece:
    spec: PieceSpec
    stem: str  # the file stem: the asset id for the hull, ``<id>_<piece>`` for the others
    frame: np.ndarray  # the piece's origin in the authored frame
    sections: list[str]
    hull: cv.HullFiles | None = None


def _write_detail(out_dir: Path, spec: CapitalSpec, seed: int, px: int) -> tuple[list[Path], dict[str, Any]]:
    """The shared near-field tile's maps and the entry every opaque surface names them by; none for a seamless skin."""
    maps = spec.style.skin.detail_tile(px, seed)
    if maps is None:
        return [], {}
    files: list[Path] = []
    names: dict[str, Any] = {}
    for key in DETAIL_KEYS:
        name = f"{spec.asset_id}_detail_{key}.png"
        png = write_png(out_dir / name, maps[key])
        sidecar = Path(str(png) + ".import")
        sidecar.write_text(import_sidecar(key), encoding="utf-8", newline="\n")
        files += [png, sidecar]
        names[key] = name
    return files, {**names, "tile_m": float(spec.style.skin.tile_m), "px": int(px)}


def _joint(section: Section, shapes: Sequence[col.Shape], centre: np.ndarray) -> np.ndarray:
    if section.joint is not None:
        return np.asarray(section.joint, dtype=float)
    lo = np.min([s.bounds()[0] for s in shapes], axis=0)
    hi = np.max([s.bounds()[1] for s in shapes], axis=0)
    return np.clip(centre, lo, hi)


def build(spec: CapitalSpec, ctx: BuildContext) -> AssetOutputs:
    """Generate the capital hull into ``ctx.out_dir``. Options: ``spacing`` (m, the surface samples'), ``atlas_px`` (every
    piece's atlas, for small test builds), ``detail_px`` (the shared tile)."""
    wrong = problems(spec)
    if wrong:
        raise ValueError(f"{spec.asset_id}: " + "; ".join(wrong))
    out_dir = Path(ctx.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{spec.asset_id} generator v{spec.generator_version} seed {ctx.seed}",)
    sections = all_sections(spec)
    by_name = {s.name: s for s in sections}
    originals = dressed(spec, ctx.seed)
    modules = cp.with_twins(originals)

    whole_lo, whole_hi = np.min([m.part.mesh.bounds()[0] for m in modules], axis=0), np.max([m.part.mesh.bounds()[1] for m in modules], axis=0)
    length = float(whole_hi[2] - whole_lo[2])
    spacing = float(ctx.option("spacing", default_spacing(length)))
    if spacing <= 0.0:
        raise ValueError("spacing must be positive")

    pieces_in = [cv.Piece(m.part.renamed(m.name, group=m.section), m.solid, m.side, m.fine) for m in originals]
    sampled = cv.sample_pieces(pieces_in, ctx, spacing)
    offset = cv.centroid(sampled)

    detail_files, detail = _write_detail(out_dir, spec, ctx.seed, int(ctx.option("detail_px", spec.detail_px)))
    files: list[Path] = list(detail_files)
    pieces: list[_Piece] = []
    chunks: list[dict[str, Any]] = []
    shapes = section_shapes(modules, sections, spec.collision)
    marks: dict[str, tuple[Marking, ...]] = {}
    for module_name, marking in spec.markings:
        marks[module_name] = (*marks.get(module_name, ()), marking)
    for p in spec.pieces:
        hull_piece = p.name == HULL_PIECE
        piece = _Piece(p, spec.asset_id if hull_piece else f"{spec.asset_id}_{p.name}", offset if hull_piece else np.asarray(p.pivot, dtype=float),
                       [s.name for s in sections if s.piece == p.name])
        mine = [s for s in sampled if by_name[s.piece.group].piece == p.name]
        piece_ctx = dataclasses.replace(ctx, options={"atlas_px": p.atlas_px, **ctx.options})
        piece.hull = cv.write_hull(out_dir, piece.stem, cv.hull_parts(mine, piece.frame, marks), piece.sections, spec.style.style, piece_ctx, comments,
                                   low_shrink=LOW_SHRINK)
        files += piece.hull.files
        for surface in piece.hull.mesh_section["surfaces"]:
            if not surface["blend"]:
                if detail:
                    surface["world_detail"] = dict(detail)
                surface.update(spec.style.surface)
        at = piece.frame - offset  # the piece's origin in the body frame
        for chunk in piece.hull.chunks:
            joint = _joint(by_name[chunk["name"]], shapes[chunk["name"]], offset)
            chunks.append({**chunk, "offset": cv.r(np.asarray(chunk["offset"]) + at), "piece": p.name, "joint": cv.r(joint - offset)})
        pieces.append(piece)
    piece_of = {name: piece for piece in pieces for name in piece.sections}

    skin = np.concatenate([s.samples.positions for s in sampled])
    cover = col.skin_coverage([s for group in shapes.values() for s in group], skin, spec.cover_tolerance_m, spec.cover_reach_m, spacing)
    collision = col.section({name: [s.translated(-piece_of[name].frame) for s in group] for name, group in shapes.items()}, spec.collision)
    for entry in collision["pieces"]:
        entry["piece"] = by_name[entry["name"]].piece
    collision["coverage"] = cover.to_json()

    lists = hardpoint_lists(modules, offset)
    parts = [m.part for m in modules]
    com = np.array([0.0, 0.0, float(mass_centroid(parts)[2])])
    bridge = cv.r(np.asarray(spec.bridge.position, dtype=float) - offset)
    rotors = [{"name": p.spec.name, "piece": p.spec.name, "pivot": cv.r(p.frame - offset), "axis": cv.r(p.spec.axis),
               "spin_rad_s": float(p.spec.spin_rad_s), "sections": list(p.sections)} for p in pieces if p.spec.name != HULL_PIECE]
    hp: dict[str, Any] = {
        "asset_id": spec.asset_id,
        "generator_version": spec.generator_version,
        "frame": "godot",
        "units": "m",
        "length_m": round(length, 3),
        "span_m": round(float(whole_hi[0] - whole_lo[0]), 3),
        "height_m": round(float(whole_hi[1] - whole_lo[1]), 3),
        "mass_kg": round(total_mass(parts), 1),
        "inertia_estimate_kg_m2": cv.r(cv.inertia_estimate(parts, com)),
        "center_of_mass": cv.r(com - offset),
        "cockpit_camera": {"position": bridge, "forward": cv.r(spec.bridge.forward),
                           "up": cv.r(spec.bridge.up)},
        "chase_anchor": {"position": cv.r((0.0, CHASE_ANCHOR_SHARE[0] * length, CHASE_ANCHOR_SHARE[1] * length))},
        "muzzles": [],
        "pods": _legacy_pods(lists["engines"]),
        "rcs": [],
        "collision": [],
        "nav_lights": _legacy_nav_lights(lists["lights"], bridge, length),
        "turrets": [],
        **lists,
        "rotors": rotors,
        "chunks": chunks,
    }
    if spec.jump_point is not None:
        hp["jump_point"] = {"position": cv.r(np.array([0.0, 0.0, float(whole_lo[2]) - spec.jump_point.ahead_m]) - offset),
                            "forward": [0.0, 0.0, -1.0], "mouth_radius_m": float(spec.jump_point.mouth_radius_m)}
    if lists["marks"]:
        mark_files, hp["mark_atlas"] = glyphs.write_atlas(out_dir, spec.asset_id)
        files += mark_files
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    held: dict[str, list[str]] = {s.name: [] for s in sections}
    for group in lists.values():
        for entry in group:
            held[entry["section"]].append(entry["name"])
    collision_by_name = {entry["name"]: entry for entry in collision["pieces"]}
    section_entries = []
    for s in sections:
        box = shapes[s.name]
        lo = np.min([q.bounds()[0] for q in box], axis=0) - offset
        hi = np.max([q.bounds()[1] for q in box], axis=0) - offset
        entry: dict[str, Any] = {
            "name": s.name,
            "kind": s.kind,
            "hull_share": round(float(s.hull_share), 6),
            "piece": s.piece,
            "chunk": s.name,
            "collision": s.name,
            "shapes": len(collision_by_name[s.name]["shapes"]),
            "hit_volumes": len(collision_by_name[s.name]["hit_volumes"]),
            "hardpoints": held[s.name],
            "modules": [m.name for m in modules if m.section == s.name],
            "aabb_min": cv.r(lo),
            "aabb_max": cv.r(hi),
        }
        if s.kind in EXPLOSIVE_KINDS:
            entry["blast_energy_j"] = float(s.blast_energy_j)
        section_entries.append(entry)

    piece_entries: dict[str, Any] = {}
    triangles = 0
    for piece in pieces:
        mesh = piece.hull.mesh_section
        entry = {"mesh": mesh, "aabb_min": cv.r(piece.hull.aabb_min), "aabb_max": cv.r(piece.hull.aabb_max), "sections": list(piece.sections)}
        if piece.spec.name != HULL_PIECE:
            entry.update({"pivot": cv.r(piece.frame - offset), "axis": cv.r(piece.spec.axis), "spin_rad_s": float(piece.spec.spin_rad_s)})
        piece_entries[piece.spec.name] = entry
        triangles += int(mesh["triangles"])
    hull = next(p for p in pieces if p.spec.name == HULL_PIECE)
    at_rest = np.concatenate([p.hull.mesh.vertices + (p.frame - offset) for p in pieces])
    faces, base = [], 0
    for p in pieces:
        faces.append(p.hull.mesh.faces + base)
        base += len(p.hull.mesh.vertices)
    atlases, tile_px = [int(p.hull.mesh_section["atlas_px"]) for p in pieces], int(detail.get("px", 0))
    manifest = build_manifest(
        asset_id=spec.asset_id,
        generator_version=spec.generator_version,
        seed=ctx.seed,
        aabb_min=at_rest.min(axis=0),
        aabb_max=at_rest.max(axis=0),
        centroid_offset=offset,
        files={"obj": f"{spec.asset_id}.obj", "mesh": hull.hull.mesh_section["file"], "hardpoints": HARDPOINTS_NAME,
               **({f"detail_{k}": detail[k] for k in DETAIL_KEYS} if detail else {})},
        extra={
            "mesh": hull.hull.mesh_section,
            "pieces": piece_entries,
            "sections": section_entries,
            "chunks": [c["name"] for c in chunks],
            "surface_spacing_m": spacing,
            "dimensions_m": {"length": hp["length_m"], "span": hp["span_m"], "height": hp["height_m"]},
            "budget": {"class": spec.ship_class, "triangles": triangles, "texture_mb": round(texture_mb(atlases, tile_px), 2),
                       "texture_mb_low": round(low_set_mb(atlases, tile_px), 2)},
            "skin": spec.style.skin.name,
            **({"notes": list(spec.notes)} if spec.notes else {}),
            "far": far_section(at_rest, np.concatenate(faces)),
            "collision": collision,
        },
    )
    files.append(write_manifest(out_dir, manifest))
    warnings = () if cover.ok else (f"collision coverage: {cover.to_json()}",)
    return AssetOutputs(spec.asset_id, out_dir, manifest, tuple(files), warnings)


__all__ = ["EXPLOSIVE_KINDS", "HULL_PIECE", "SECTION_KINDS", "CapitalSpec", "JumpPoint", "PieceSpec", "Pose", "Section", "all_modules",
           "all_sections", "build", "default_spacing", "dressed", "hardpoint_lists", "problems", "section_shapes"]
