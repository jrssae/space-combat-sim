"""``b5_interior``: the inside of one Babylon 5 Cobra-bay arm, the front end's backdrop (M7-T09, D77, Q7).

A long hall along the arm with seven launch positions, each a closed launch door in the floor (the arm's doors from T04, seen from
inside) under a gantry crane whose clamps hold three Starfuries side by side above it (``parts/cobra_bay.py`` says which reference drove what). The
fighters are not in this asset: the scene places the real ``starfury_aurora`` at each rack's transform (``racks``), so their
liveries and texture detail apply.

Three pieces, each one textured mesh on its own atlas with the ``cobra_bay`` style (metallic paint and bare steel, D72):

* ``bay``: one launch position, its door at its origin, drawn seven times (``instances``) so the atlas spends its texels once.
* ``ends``: the two end walls with their pressure doors and lit booths, in the hall frame.
* ``signs``: the big red bay numbers on the walls and the plates on the cranes, in the hall frame.

The manifest also carries the hall's lights for the scene (``lights``: one work lamp per position, so all seven fit the light
rig's omni slots and none ever swaps; ``fill``: the key light's dim red from above), the camera's rail beside the racks
(``camera``) and the hall's place on a Cobra arm (``to_arm``) for M8's launch from the menu.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np

from ..core.color import linear_to_srgb
from ..core.context import AssetOutputs, BuildContext
from ..core.detail_layer import detail_tile
from ..core.geometry import Mesh
from ..core.image import write_png
from ..core.manifest import build_manifest, write_manifest
from ..core.pieces import PieceTexture, write_piece
from ..core.textured_mesh import TexturedPart, import_sidecar, phase_steps
from ..core.textures import Marking
from ..parts import cobra_bay as cb
from ..styles.cobra_bay import COBRA_BAY as STYLE
from ..styles.cobra_bay import SCHEME, WORK_GLOW

ASSET_ID = "b5_interior"
GENERATOR_VERSION = 1
# Each piece's atlas and the texel its packer starts from (it grows the texel until every chart fits).
BAY_ATLAS_PX = 2048
ENDS_ATLAS_PX = 2048
SIGNS_ATLAS_PX = 1024
START_TEXEL_M = 0.02
# The shared detail tile (D72, as the station's): plating a metre or a few across with fine seams, laid in each piece's own space
# by the renderer, so the walls read up close although the atlases are texelled at 5 to 10 cm.
DETAIL_PX = 1024
DETAIL_TILE_M = 8.0
DETAIL_KEYS = ("albedo", "normal")
# The work lamps (one per position, under the crane's bridge over the fighter, alternating sides; the show's white lamps among
# the gantries) and the key light's dim red fill from above (its red lamps).
WORK_ENERGY = 9.0
WORK_RANGE_M = 30.0
# The fill is kept faint and only a little red, so the floor reads dark grey and the red stays on the lamps and machinery
# (the maintainer, 2026-11-13).
FILL = {"colour": [1.0, 0.66, 0.6], "energy": 0.1, "direction": [0.25, -1.0, 0.35]}
BOOTH_GLOW = (1.0, 0.55, 0.3)
BOOTH_STRENGTH = 2.0
# Budgets: a backdrop behind a menu.
MAX_TRIANGLES = {"bay": 20_000, "ends": 6_000, "signs": 2_000}


def _srgb(hex_rgb: int) -> list[float]:
    return [round(((hex_rgb >> s) & 255) / 255.0, 4) for s in (16, 8, 0)]


def _textured(shapes: list[cb.Shape], extra: dict[str, tuple[Marking, ...]] | None = None) -> list[TexturedPart]:
    """The shapes as the textured mesh takes them: each with its own panel phase, its paint and any other markings."""
    out = []
    for shape in shapes:
        marks = tuple(Marking.paint(shape.name, colour, cover) for colour, cover in shape.paint)
        marks += (extra or {}).get(shape.name, ())
        out.append(TexturedPart(shape.mesh, phase_steps(shape.name, False), marks, shape.name))
    return out


def bay_parts() -> list[TexturedPart]:
    """One launch position, in its own frame (its door's middle on the floor at the origin)."""
    return _textured(cb.slice_shapes(STYLE.materials))


def end_parts() -> list[TexturedPart]:
    """Both end walls, in the hall frame, with the booths' lit windows."""
    extra = {}
    for tag in ("head", "root"):
        w = cb.booth_windows(tag)
        right = np.cross(np.asarray(w["facing"]) * -1.0, [0.0, 1.0, 0.0])
        extra[f"{tag}_glass"] = (Marking.windows(f"{tag}_glass", w["centre"], right, (0.0, 1.0, 0.0), w["facing"], w["size"],
                                                 (2.5, 2.8), (2.2, 2.4), BOOTH_GLOW, BOOTH_STRENGTH, lit=1.0),)
    return _textured(cb.end_shapes(STYLE.materials), extra)


def sign_parts() -> list[TexturedPart]:
    """The bay numbers, in the hall frame: big and red on both walls, small and white on both faces of each crane's bridge."""
    marks: dict[str, tuple[Marking, ...]] = {}
    for k, z in enumerate(cb.bay_centres(), start=1):
        big, small = cb.number_text(k)
        _, y0, y1 = cb.NUMBER_PANEL
        y = 0.5 * (y0 + y1)
        panel, plate = f"number_panels_{k}", f"bridge_plates_{k}"
        marks[panel] = tuple(Marking.text(panel, big, (sx * (cb.HALF_W - 0.3), y, z), (0.0, 0.0, sx), (0.0, 1.0, 0.0), (-sx, 0.0, 0.0),
                                          4.4, cb.NUMBER_RED, 0.75) for sx in (-1.0, 1.0))
        _, py0, py1 = cb.PLATE
        marks[plate] = tuple(Marking.text(plate, small, (0.0, 0.5 * (py0 + py1), z + sz * (cb.BRIDGE_HALF_Z + 0.1)), (sz, 0.0, 0.0),
                                          (0.0, 1.0, 0.0), (0.0, 0.0, sz), 1.1, cb.PLATE_WHITE) for sz in (-1.0, 1.0))
    return _textured(cb.sign_shapes(STYLE.materials), marks)


def _in_arm(p: list[float]) -> list[float]:
    """A hall point in the frame of a Cobra arm standing on top of the drum (``to_arm``)."""
    arm = cb.to_arm()
    q = np.asarray(arm["basis"], dtype=float) @ np.asarray(p, dtype=float) + np.asarray(arm["origin"], dtype=float)
    return [round(float(v), 5) + 0.0 for v in q]


def racks() -> list[dict[str, Any]]:
    """Every held Starfury (hall frame), three a door: its id, its door (1 at the arm's head) and slot (1 to 3 across the hall
    from -x), its livery number in Alpha wing, where it hangs (nose toward the arm's head, -z, belly to its door) and where a
    launch lets it go below the door; the last two also in the arm's frame, for M7-T08's launch steps and M8's squadron launch."""
    out = []
    for door, z in enumerate(cb.bay_centres(), start=1):
        for slot, x in enumerate(cb.SLOT_X, start=1):
            at = [x, cb.HANG_Y, round(z, 5)]
            release = [x, cb.RELEASE_Y, round(z, 5)]
            out.append({"id": f"door{door}_slot{slot}", "door": door, "slot": slot, "number": (door - 1) * len(cb.SLOT_X) + slot,
                        "position": at, "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0], "release": release,
                        "position_arm": _in_arm(at), "release_arm": _in_arm(release)})
    return out


def lights() -> list[dict[str, Any]]:
    """One work lamp per position, under its crane's bridge, the side alternating down the hall."""
    x, y = cb.BRIDGE_LAMP
    return [{"name": f"work_{k}", "position": [(-1.0 if k % 2 else 1.0) * x, y - 0.8, round(z, 5)], "colour": _srgb(WORK_GLOW),
             "energy": WORK_ENERGY, "range_m": WORK_RANGE_M} for k, z in enumerate(cb.bay_centres(), start=1)]


def materials() -> dict[str, dict[str, Any]]:
    """The paints and glows by role, for the look sheet's swatches and the docs: the capture colour each paint was read from, its
    metallic and roughness; each glow's colour and strength."""
    out: dict[str, dict[str, Any]] = {}
    for role, (hex_rgb, _, metallic, roughness) in SCHEME.items():
        out[role] = {"capture_srgb": f"#{hex_rgb:06X}", "metallic": metallic, "roughness": roughness}
    for role in ("bay_light", "lamp", "work_light", "panel_light"):
        m = STYLE.materials[role]
        out[role] = {"emissive_srgb": [round(float(c), 4) for c in linear_to_srgb(np.asarray(m.emissive))],
                     "strength": m.emissive_strength}
    return out


def whole_hall() -> Mesh:
    """Every piece in the hall frame, the bay at each position: what the tests measure."""
    bay = Mesh.concatenate(p.mesh for p in bay_parts())
    return Mesh.concatenate([bay.translated((0.0, 0.0, z)) for z in cb.bay_centres()] + [p.mesh for p in end_parts()]
                            + [p.mesh for p in sign_parts()])


def _write_detail(out_dir: Path, seed: int, px: int) -> tuple[list[Path], dict[str, Any]]:
    """The shared detail tile's maps, and the entry every surface names them by."""
    maps = detail_tile(px, DETAIL_TILE_M, seed)
    files, names = [], {}
    for key in DETAIL_KEYS:
        name = f"{ASSET_ID}_detail_{key}.png"
        png = write_png(out_dir / name, maps[key])
        sidecar = Path(str(png) + ".import")
        sidecar.write_text(import_sidecar(key), encoding="utf-8", newline="\n")
        files += [png, sidecar]
        names[key] = name
    return files, {**names, "tile_m": DETAIL_TILE_M, "px": px}


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the three pieces into ``ctx.out_dir``."""
    return build_at(ctx, BAY_ATLAS_PX, ENDS_ATLAS_PX, SIGNS_ATLAS_PX, DETAIL_PX)


def build_at(ctx: BuildContext, bay_px: int, ends_px: int, signs_px: int, detail_px: int = DETAIL_PX) -> AssetOutputs:
    """The build with the atlases at other sizes: the tests bake small ones, since the geometry and the manifest do not change."""
    out_dir: Path = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    files, detail = _write_detail(out_dir, ctx.seed, detail_px)
    pieces: dict[str, Any] = {}
    for name, parts, px, occlusion in (("bay", bay_parts(), bay_px, True), ("ends", end_parts(), ends_px, True),
                                       ("signs", sign_parts(), signs_px, False)):
        written, entry = write_piece(out_dir, f"{ASSET_ID}_{name}", parts, STYLE,
                                     PieceTexture(px, START_TEXEL_M, ctx.seed, occlusion=occlusion))
        files += written
        for surface in entry["mesh"]["surfaces"]:
            if name != "signs":
                surface["world_detail"] = dict(detail)
        pieces[name] = entry
    pieces["bay"]["instances"] = [{"name": f"bay_{k}", "origin": [0.0, 0.0, round(z, 5)]}
                                  for k, z in enumerate(cb.bay_centres(), start=1)]
    hall = whole_hall()
    lo, hi = hall.bounds()
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=lo,
        aabb_max=hi,
        centroid_offset=np.zeros(3),
        files={**{f"{name}_mesh": entry["mesh"]["file"] for name, entry in pieces.items()}, "detail_albedo": detail["albedo"],
               "detail_normal": detail["normal"]},
        extra={
            "hall": {"half_width_m": cb.HALF_W, "height_m": cb.HEIGHT, "end_z_m": round(cb.END_Z, 5), "pitch_m": round(cb.PITCH_M, 5),
                     "bays": cb.BAYS},
            "pieces": pieces,
            "racks": racks(),
            "launch": {"doors": cb.BAYS, "slots_per_door": len(cb.SLOT_X), "release_y_m": cb.RELEASE_Y},
            "fighter": "starfury_aurora",
            "lights": lights(),
            "fill": dict(FILL),
            "camera": {"rail": dict(cb.CAMERA_RAIL)},
            "to_arm": cb.to_arm(),
            "materials": materials(),
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
