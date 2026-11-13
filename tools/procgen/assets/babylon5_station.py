"""``babylon5_station``: the Babylon 5 station (M7-T04, D72), replacing M4's ``b5_station`` stand-in.

Built from the measurements of the maintainer's references (docs/assets-station.md; nothing from the references is used), 8 km
along Z with the bow at -Z, in two pieces so the game can turn one:

* ``frame`` (stationary): the bow spike and the docking aperture's ring, the dorsal spine with its radiators, cargo modules, dome
  and lamps, the hub and cone with the delta fins, the vane booms and their twelve vanes, the truss, the torus disc, the shaft and
  the reactor.
* ``drum`` (turns about the station's long axis; its node sits on that axis): the docking sphere with the aperture's door, the
  waist, the four Cobra-bay arms, the forward body, the rings and bands and the green zone.

Texel tiers (D72): each piece has its own atlas for the broad paint, the panel seams and the windows (about a metre a texel), and
both share one detail tile laid in their own space by the renderer (``core/detail_layer.py``), so a fighter 50 m off a bay sees
plating a few metres across. The bays' and aperture's near-field geometry and every hardpoint come in T05.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from ..core.context import AssetOutputs, BuildContext
from ..core.detail_layer import DEFAULT_TILE_M, detail_tile
from ..core.geometry import Mesh
from ..core.image import write_png
from ..core.manifest import build_manifest, write_manifest
from ..core.pieces import PieceTexture, write_piece
from ..core.seams import EMPTY
from ..core.silhouette import far_section
from ..core.textured_mesh import TexturedPart, import_sidecar, phase_steps
from ..parts import station as st
from ..parts import station_layouts as sl
from ..styles.earth_alliance_station import EARTH_ALLIANCE_STATION as STYLE

ASSET_ID = "babylon5_station"
GENERATOR_VERSION = 1
LENGTH_M = 8000.0
# The asset's origin in the station frame: on the drum's axis, half way along. The drum's own frame sits on the axis at its middle.
ORIGIN = np.array([0.0, 0.0, 0.5 * LENGTH_M])
DRUM_CENTRE = np.array([0.0, 0.0, 3000.0])
DRUM_SPIN_RAD_S = 0.148  # Q9: about 62 m/s at the bands' r 417
# Each piece's atlas; the packer starts at this texel and grows it until every chart fits.
DRUM_ATLAS_PX = 4096
FRAME_ATLAS_PX = 4096
START_TEXEL_M = 0.8
DETAIL_PX = 1024
DETAIL_KEYS = ("albedo", "normal")


def _parts(shapes: list[st.Shape], shift: np.ndarray) -> list[TexturedPart]:
    """The shapes moved by ``-shift`` into their piece's frame, each with its seams, paint and windows."""
    layouts = sl.layouts()
    out = []
    for shape in shapes:
        mesh = shape.mesh.translated(-shift)
        seams = layouts.get(shape.name, EMPTY).transformed(np.eye(3), -shift)
        markings = sl.paint_markings(shape.name, shift) + sl.window_markings(shape.name, shift)
        out.append(TexturedPart(mesh, phase_steps(shape.name, False), markings, shape.name, seams=seams))
    return out


def drum_parts() -> list[TexturedPart]:
    """What turns, in the drum's frame: centred on the axis at ``DRUM_CENTRE``."""
    return _parts(st.drum_shapes(STYLE.materials), DRUM_CENTRE)


def frame_parts() -> list[TexturedPart]:
    """What stands still, in the asset's frame."""
    return _parts(st.frame_shapes(STYLE.materials), ORIGIN)


def drum_pivot() -> list[float]:
    """Where the drum's frame sits in the asset's frame."""
    return [float(v) for v in DRUM_CENTRE - ORIGIN]


def whole_station(drum_turn_rad: float = 0.0) -> Mesh:
    """Both pieces as one mesh in the asset's frame, the drum turned by ``drum_turn_rad`` about the axis."""
    c, s = np.cos(drum_turn_rad), np.sin(drum_turn_rad)
    turn = np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])
    drum = Mesh.concatenate(p.mesh for p in drum_parts()).transformed(turn, drum_pivot())
    return Mesh.concatenate([drum] + [p.mesh for p in frame_parts()])


def _write_detail(out_dir: Path, seed: int, px: int) -> tuple[list[Path], dict[str, object]]:
    """The shared detail tile's maps, and the entry every surface names them by."""
    maps = detail_tile(px, DEFAULT_TILE_M, seed)
    files, names = [], {}
    for key in DETAIL_KEYS:
        name = f"{ASSET_ID}_detail_{key}.png"
        png = write_png(out_dir / name, maps[key])
        sidecar = Path(str(png) + ".import")
        sidecar.write_text(import_sidecar(key), encoding="utf-8", newline="\n")
        files += [png, sidecar]
        names[key] = name
    return files, {**names, "tile_m": DEFAULT_TILE_M, "px": px}


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate both pieces and the detail tile into ``ctx.out_dir``."""
    return build_at(ctx, DRUM_ATLAS_PX, FRAME_ATLAS_PX, DETAIL_PX)


def build_at(ctx: BuildContext, drum_px: int, frame_px: int, detail_px: int) -> AssetOutputs:
    """The build with the atlases at other sizes: the tests bake small ones, since the geometry and the manifest do not change."""
    out_dir: Path = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    files, detail = _write_detail(out_dir, ctx.seed, detail_px)
    drum_files, drum = write_piece(out_dir, f"{ASSET_ID}_drum", drum_parts(), STYLE,
                                   PieceTexture(drum_px, START_TEXEL_M, ctx.seed, grid=False))
    drum["pivot"] = drum_pivot()
    drum["axis"] = [0.0, 0.0, 1.0]
    drum["spin_rad_s"] = DRUM_SPIN_RAD_S
    frame_files, frame = write_piece(out_dir, f"{ASSET_ID}_frame", frame_parts(), STYLE,
                                     PieceTexture(frame_px, START_TEXEL_M, ctx.seed, grid=False))
    files += drum_files + frame_files
    for entry in (drum, frame):
        for surface in entry["mesh"]["surfaces"]:
            surface["world_detail"] = dict(detail)
    lo = np.minimum(np.array(frame["aabb_min"]), np.array(drum["aabb_min"]) + drum["pivot"])
    hi = np.maximum(np.array(frame["aabb_max"]), np.array(drum["aabb_max"]) + drum["pivot"])
    whole = whole_station()
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=lo,
        aabb_max=hi,
        centroid_offset=ORIGIN,
        files={"drum_mesh": drum["mesh"]["file"], "frame_mesh": frame["mesh"]["file"], "detail_albedo": detail["albedo"],
               "detail_normal": detail["normal"]},
        extra={
            "length_m": LENGTH_M,
            "pieces": {"drum": drum, "frame": frame},
            "far": far_section(whole.vertices, whole.faces),
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
