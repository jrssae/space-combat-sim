"""``capital_hulls``: the capital ship stand-ins' box hulls as textured meshes (M4-T27, Q24; textured in M4-T30d).

The bench's capitals (``src/perf/standins/capital_standin.gd``) are plain boxes; the station scene and the look sheets draw these
instead. One box per class, the sizes the stand-in uses, panelled in grey with a darker keel, its detail sized to 1/300 of the length
(1, 2 and 4 m). Each is plated to the hull, worn, its keel dark, with rows of lit windows along both flanks (the bow and stern ends
left plain), on an atlas of its own (1 024 or 2 048 px, under a metre a texel; ``core/pieces.py``).
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Material, tapered_box
from ..core.manifest import build_manifest, write_manifest
from ..core.pieces import PieceTexture, write_piece
from ..core.textured_mesh import TexturedPart, phase_steps
from ..core.textures import Marking
from ..styles import Style

ASSET_ID = "capital_hulls"
GENERATOR_VERSION = 3  # 3: the textured boxes only (M4-T31); 2: the textured boxes with window rows (M4-T30d)
# Width, height, length (m): CapitalStandin.CLASSES.
CLASSES: dict[str, tuple[float, float, float]] = {
    "cruiser": (60.0, 40.0, 300.0),
    "destroyer": (110.0, 70.0, 600.0),
    "carrier": (220.0, 140.0, 1200.0),
}
# The detail unit the style's panels and wear are sized by, per metre of length.
UNIT_PER_LENGTH = 1.0 / 300.0
# The textured boxes (M4-T30d): the atlas per class, so each lands at under a metre a texel, and the texel the packer starts from (it
# grows it until the box fits).
ATLAS_PX = {"cruiser": 1024, "destroyer": 1024, "carrier": 2048}
TEXEL_PER_LENGTH = 0.0006
# Window rows: a window's size and pitch, m (along the hull, up), the decks' share of the hull's height, how many are lit.
WINDOW_M = (2.0, 1.2)
WINDOW_PITCH_M = (5.0, 6.0)
DECKS_SHARE = 0.45
WINDOWS_LIT = 0.55
WINDOW_GLOW = (1.0, 0.86, 0.62)
WINDOW_STRENGTH = 2.5


def _style(unit: float) -> Style:
    grey = Material("cap_hull", (0.105, 0.11, 0.125), paneled=True)  # a medium blue-grey, the Starfury's range (M4-T30d)
    dark = Material("cap_keel", (0.08, 0.085, 0.09), paneled=True)
    roles = {r: grey for r in ("hull", "hull_panel", "stripe", "hazard", "canopy_frame", "nozzle", "barrel", "rcs")}
    roles.update({r: dark for r in ("hull_dark", "hazard_dark", "canopy_glass", "nozzle_throat", "bore", "interior")})
    k = 20.0 * unit  # the fighters' wear is sized for a centimetre texel; these hulls are texelled at tens of centimetres
    return Style(
        name="capital",
        materials=roles,
        panel_size_m=12.0 * unit,
        panel_line_width_m=1.5 * unit,
        panel_line_darkness=0.6,
        panel_tint_jitter=0.1,
        groove_depth_m=0.012 * k,
        hatch_depth_m=0.004 * k,
        edge_wear_width_m=0.035 * k,
        grime_scale_m=0.9 * k,
        streaks=0.25,
        grime=0.1,
        extra={"wear_scale": k, "rivets": 0.0, "bare_metal": 0.0, "smudge": 0.25, "speckle": 0.05, "paint_roughness": 0.8},
    )


def window_rows(cls: str) -> tuple[Marking, ...]:
    """Lit windows along both flanks: decks round the middle of the hull's height, the bow and stern ends plain."""
    w, h, length = CLASSES[cls]
    rows = []
    for side in (1.0, -1.0):
        rows.append(Marking.windows(cls, (side * 0.5 * w, 0.0, 0.0), (0.0, 0.0, -side), (0.0, 1.0, 0.0), (side, 0.0, 0.0),
                                    (0.8 * length, DECKS_SHARE * h), WINDOW_PITCH_M, WINDOW_M, WINDOW_GLOW, WINDOW_STRENGTH, WINDOWS_LIT))
    return tuple(rows)


def hull_parts(cls: str, style: Style) -> list[TexturedPart]:
    """The class's box, its keel face dark, centred on the origin like the stand-in's mesh, with its window rows."""
    w, h, length = CLASSES[cls]
    mesh = tapered_box(length, (w, h), (w, h), style.material("hull"), materials_by_face={"bottom": style.material("hull_dark")})
    return [TexturedPart(mesh, phase_steps(cls, False), window_rows(cls), cls)]


def build(ctx: BuildContext) -> AssetOutputs:
    out_dir: Path = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    files: list[Path] = []
    classes: dict[str, dict] = {}
    for cls, size in CLASSES.items():
        style = _style(size[2] * UNIT_PER_LENGTH)
        texture = PieceTexture(ATLAS_PX[cls], size[2] * TEXEL_PER_LENGTH, ctx.seed)
        piece_files, entry = write_piece(out_dir, f"{ASSET_ID}_{cls}", hull_parts(cls, style), style, texture)
        entry["size"] = list(size)
        files += piece_files
        classes[cls] = entry
    biggest = classes["carrier"]
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=np.array(biggest["aabb_min"]),
        aabb_max=np.array(biggest["aabb_max"]),
        centroid_offset=(0.0, 0.0, 0.0),
        files={f"{cls}_mesh": classes[cls]["mesh"]["file"] for cls in CLASSES},
        extra={"classes": classes},
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
