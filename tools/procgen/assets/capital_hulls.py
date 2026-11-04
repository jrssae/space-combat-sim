"""``capital_hulls``: the capital ship stand-ins' box hulls drawn both ways, for the render comparison (M4-T27, Q24).

The bench's capitals (``src/perf/standins/capital_standin.gd``) are plain boxes; the station scene draws them as splats or as a painted
mesh instead. One box per class, the sizes the stand-in uses, panelled in grey with a darker keel. Splats at a spacing of 1/300 of the
length (1, 2 and 4 m), so each class is about the same count, and two coarser levels at 2x and 4x that (``core/pieces.py``).
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Material, tapered_box
from ..core.manifest import build_manifest, write_manifest
from ..core.paint_mesh import PaintPart, phase_steps
from ..core.pieces import write_piece
from ..styles import Style

ASSET_ID = "capital_hulls"
GENERATOR_VERSION = 1
# Width, height, length (m): CapitalStandin.CLASSES.
CLASSES: dict[str, tuple[float, float, float]] = {
    "cruiser": (60.0, 40.0, 300.0),
    "destroyer": (110.0, 70.0, 600.0),
    "carrier": (220.0, 140.0, 1200.0),
}
SPACING_PER_LENGTH = 1.0 / 300.0
LOD_FACTORS = (1.0, 2.0, 4.0)


def _style(spacing: float) -> Style:
    grey = Material("cap_hull", (0.22, 0.23, 0.25), paneled=True)
    dark = Material("cap_keel", (0.08, 0.085, 0.09), paneled=True)
    roles = {r: grey for r in ("hull", "hull_panel", "stripe", "hazard", "canopy_frame", "nozzle", "barrel", "rcs")}
    roles.update({r: dark for r in ("hull_dark", "hazard_dark", "canopy_glass", "nozzle_throat", "bore", "interior")})
    return Style(
        name="capital",
        materials=roles,
        panel_size_m=12.0 * spacing,
        panel_line_width_m=1.5 * spacing,
        panel_line_darkness=0.6,
        panel_tint_jitter=0.1,
    )


def hull_parts(cls: str, style: Style) -> list[PaintPart]:
    """The class's box, its keel face dark, centred on the origin like the stand-in's mesh."""
    w, h, length = CLASSES[cls]
    mesh = tapered_box(length, (w, h), (w, h), style.material("hull"), materials_by_face={"bottom": style.material("hull_dark")})
    return [PaintPart(mesh, phase_steps(cls, False))]


def build(ctx: BuildContext) -> AssetOutputs:
    out_dir: Path = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}", "frame: 3dgs (Rz180 of godot), centred on its own splats")
    files: list[Path] = []
    classes: dict[str, dict] = {}
    for cls, size in CLASSES.items():
        spacing = size[2] * SPACING_PER_LENGTH
        style = _style(spacing)
        piece_files, entry = write_piece(
            out_dir, f"{ASSET_ID}_{cls}", hull_parts(cls, style), style, [spacing * f for f in LOD_FACTORS], ctx.rng, comments
        )
        entry["size"] = list(size)
        files += piece_files
        classes[cls] = entry
    first = classes["cruiser"]
    biggest = classes["carrier"]
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        lods=[{k: v for k, v in e.items() if k != "centroid"} for e in first["lods"]],
        aabb_min=np.array(biggest["aabb_min"]),
        aabb_max=np.array(biggest["aabb_max"]),
        centroid_offset=(0.0, 0.0, 0.0),
        files={f"{cls}_mesh": classes[cls]["paint_mesh"]["file"] for cls in CLASSES},
        extra={"classes": classes},
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
