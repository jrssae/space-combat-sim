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
plating a few metres across.

Near field and hardpoints (M7-T05): the docking bay at the bow (``station_detail.py``: the cross housing, the stepped mouth, the
red-lit tunnel and the inner airlock, turning with the drum), plinths under the defence grid's mounts, and the manifest's
``hardpoints`` (``station_hardpoints.py``): the 28 Cobra-bay launch positions, the docking approach, D75's mounts, the lights for
T18, the tour points and the damage sections, each in the frame of the piece that carries it.

Sections (M7-T19, D72): each piece is also written cut across its length into sections along T01's section lines (band edges,
rings, the gaps between cargo modules and vanes), each a glb with its own origin, so the game picks a level of detail per section
and culls the ones out of view; the collision shapes (D73) follow the same sections. Props (``station_props.py``), instanced with
small atlases of their own: on the drum's waist section the Cobra-bay doors' leaves (drawn far: they are the doors), their clamps
and the launch hall seen through an open door (near only); on the frame's spine over the docking sphere the command section's
windows (near only).
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from ..core import collision as col
from ..core.context import AssetOutputs, BuildContext
from ..core.detail_layer import DEFAULT_TILE_M, detail_tile
from ..core.geometry import Mesh
from ..core.image import write_png
from ..core.manifest import build_manifest, write_manifest
from ..core.near_props import write_props
from ..core.pieces import PieceTexture, write_piece
from ..core.sections import SectionCut, cuts_from_planes
from ..core.seams import EMPTY
from ..core.silhouette import far_section
from ..core.textured_mesh import TexturedPart, import_sidecar, phase_steps
from ..parts import station as st
from ..parts import station_collision as sc
from ..parts import station_hardpoints as sh
from ..parts import station_layouts as sl
from ..parts import station_props as sp
from ..styles.earth_alliance_station import EARTH_ALLIANCE_STATION as STYLE

ASSET_ID = "babylon5_station"
GENERATOR_VERSION = 3
LENGTH_M = 8000.0
# The asset's origin in the station frame: on the drum's axis, half way along. The drum's own frame sits on the axis at its middle.
ORIGIN = np.array([0.0, 0.0, 0.5 * LENGTH_M])
DRUM_CENTRE = np.array([0.0, 0.0, 3000.0])
DRUM_SPIN_RAD_S = sh.DRUM_SPIN_RAD_S  # Q9: 0.148 rad/s, about 62 m/s at the bands' r 417
# Each piece's atlas; the packer starts at this texel and grows it until every chart fits.
DRUM_ATLAS_PX = 4096
FRAME_ATLAS_PX = 4096
START_TEXEL_M = 0.8
DETAIL_PX = 1024
DETAIL_KEYS = ("albedo", "normal")
# The sections (M7-T19): names and the cut planes between them, z in the station frame (aft from the bow tip). Cuts sit on the hull's
# own joints (band edges and rings, the sphere's widest ring, the gaps between cargo modules and between vanes) and split the long
# green zone at its blue blocks' joints; none cuts a small part.
DRUM_SECTIONS = ("aperture", "sphere_fore", "sphere_aft", "waist", "fwd_body", "fwd_band", "green_1", "green_2", "green_band", "green_3",
                 "green_4", "aft_band")
DRUM_PLANES = (560.0, 750.0, 945.0, 1340.0, 1692.0, 2348.0, 2840.0, 3340.0, 3800.0, 4290.0, 4782.0)
FRAME_SECTIONS = ("bow", "bow_ring", "spine_sphere", "ramp", "radiators", "cargo_1", "cargo_2", "cargo_3", "vanes_1", "vanes_2", "vanes_3",
                  "hub", "cone", "truss", "torus_shaft", "reactor")
FRAME_PLANES = (420.0, 700.0, 1300.0, 1725.0, 2340.0, 3068.0, 3577.0, 4087.0, 4585.0, 5030.0, 5460.0, 5735.0, 6360.0, 7110.0, 7704.0)
PROP_SECTION = "waist"  # the drum section the Cobra doors lie in
FRAME_PROP_SECTION = "spine_sphere"  # the frame section the command section's windows lie in
# Shapes a piece may have (T03's default is 128): the open bays (the docking tunnel, 28 launch doors over their halls, the zero-g
# bay) take pieces round each opening that a merge would close.
COLLISION_SHAPES = 192


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


def section_cuts(piece: str) -> tuple[SectionCut, ...]:
    """A piece's sections in its own frame."""
    names, planes, shift = ((DRUM_SECTIONS, DRUM_PLANES, DRUM_CENTRE) if piece == "drum" else (FRAME_SECTIONS, FRAME_PLANES, ORIGIN))
    return cuts_from_planes(names, [z - float(shift[2]) for z in planes])


def collision_section() -> dict[str, object]:
    """The manifest's ``collision`` (D73): each piece's convex shapes, named and listed by section (``sections``: first, count)."""
    budget = col.Budget(max_shapes=COLLISION_SHAPES)
    drum, drum_spans = sc.section_shapes(sc.drum_pieces(DRUM_PLANES), section_cuts("drum"), DRUM_CENTRE, budget)
    frame, frame_spans = sc.section_shapes(sc.frame_pieces(FRAME_PLANES), section_cuts("frame"), ORIGIN, budget)
    out = col.section({"drum": drum, "frame": frame}, budget)
    for entry, spans in zip(out["pieces"], (drum_spans, frame_spans), strict=True):
        entry["sections"] = spans
    return out


def hardpoints(pieces: dict[str, dict]) -> dict[str, object]:
    """The manifest's ``hardpoints``, the damage sections boxed from the pieces' written sections."""
    boxes = {name: {s["name"]: ([o + a for o, a in zip(s["origin"], s["aabb_min"], strict=True)],
                                [o + a for o, a in zip(s["origin"], s["aabb_max"], strict=True)])
                    for s in entry["mesh"]["sections"]} for name, entry in pieces.items()}
    return sh.section(sh.Frames(DRUM_CENTRE, ORIGIN), boxes)


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
                                   PieceTexture(drum_px, START_TEXEL_M, ctx.seed, grid=False), section_cuts("drum"))
    drum["pivot"] = drum_pivot()
    drum["axis"] = [0.0, 0.0, 1.0]
    drum["spin_rad_s"] = DRUM_SPIN_RAD_S
    frame_files, frame = write_piece(out_dir, f"{ASSET_ID}_frame", frame_parts(), STYLE,
                                     PieceTexture(frame_px, START_TEXEL_M, ctx.seed, grid=False), section_cuts("frame"))
    files += drum_files + frame_files
    home = next(e for e in drum["mesh"]["sections"] if e["name"] == PROP_SECTION)
    prop_files, drum["props"] = write_props(out_dir, ASSET_ID, sp.kinds(), sp.groups(PROP_SECTION, DRUM_CENTRE + home["origin"]),
                                            sp.prop_maps(ctx.seed), sp.EMISSIVE_STRENGTH, sp.NEAR_M, sp.MARGIN_M)
    files += prop_files
    home = next(e for e in frame["mesh"]["sections"] if e["name"] == FRAME_PROP_SECTION)
    prop_files, frame["props"] = write_props(out_dir, f"{ASSET_ID}_frame", sp.frame_kinds(),
                                             sp.frame_groups(FRAME_PROP_SECTION, ORIGIN + home["origin"]), sp.frame_maps(ctx.seed),
                                             sp.FRAME_EMISSIVE_STRENGTH, sp.NEAR_M, sp.MARGIN_M)
    files += prop_files
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
            "collision": collision_section(),
            "hardpoints": hardpoints({"drum": drum, "frame": frame}),
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
