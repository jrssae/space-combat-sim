"""``b5_station``: a stand-in of the Babylon 5 station for the render comparison (M4-T27, Q24).

Shape only, built from primitives and the written proportions in ``docs/design-references.md``: no franchise asset is used. About
8 km along Z (bow at -Z), in two pieces so the game can turn one:

* ``drum`` (rotates about the Z axis): the habitat cylinder, 3 345 m long and 890 m across (1/9 of the length), in alternating grey
  and blue-purple bands with end caps.
* ``frame`` (stationary): the reactor drum with its flared cap at the stern, the truss spine, the funnel with three pairs of dark blue
  vanes, the top bar over the drum with its row of red cargo modules, the command sphere with its ring, Cobra-bay arms and masts, and
  the forked bow spike.

Each piece is written as a chain of splat levels (4, 8, 16 and 32 m spacing) with lighting records, as a painted mesh and, from
M4-T30d, as a textured mesh on a 2 048 px atlas of its own (``core/pieces.py``): the drum's bands, the frame's plating, the cargo
modules' red, the command sphere's rows of lit windows. The drum's frame is centred on its axis, so turning its node about local Z
turns the drum in place.
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np

from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Material, Mesh, box, lathe, rotation_x, tapered_box
from ..core.manifest import build_manifest, write_manifest
from ..core.paint_mesh import phase_steps
from ..core.pieces import PieceTexture, write_piece
from ..core.textured_mesh import TexturedPart
from ..core.textures import Marking
from ..styles import Style

ASSET_ID = "b5_station"
GENERATOR_VERSION = 2  # 2: the textured pieces (M4-T30d)
LOD_SPACINGS_M = (4.0, 8.0, 16.0, 32.0)
LENGTH_M = 8000.0
DRUM_RADIUS_M = LENGTH_M / 18.0  # diameter 1/9 of the length
DRUM_FRONT_Z = -2450.0
DRUM_BACK_Z = 895.0
DRUM_BANDS = 12
TOP_BAR_Y = DRUM_RADIUS_M + 65.0
# Every level's splats over these is the budget the game can draw at once with a dozen capitals (`splat_budget` 2 000 000).
LOD0_BUDGET = (600_000, 1_400_000)
SEGMENTS = 96
COMMAND_Z = -2900.0
COMMAND_RADIUS_M = 420.0
# The textured pieces (M4-T30d): a 2 048 px atlas each (about 2 m a texel) and the texel the packer starts from.
ATLAS_PX = 2048
TEXEL_M = 1.4
# The command sphere's windows: rows round it at these heights along the axis (from its centre), each this tall, m.
WINDOW_ROWS_AT_M = (-260.0, -150.0, -40.0, 70.0, 180.0)
WINDOW_ROW_M = 40.0
WINDOW_PITCH_M = (24.0, 12.0)
WINDOW_M = (12.0, 6.0)
WINDOW_GLOW = (1.0, 0.88, 0.66)
WINDOW_STRENGTH = 2.5


def _lin(hex_rgb: int) -> tuple[float, float, float]:
    srgb = np.array([(hex_rgb >> 16) & 255, (hex_rgb >> 8) & 255, hex_rgb & 255], dtype=float) / 255.0
    lin = np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)
    return (float(lin[0]), float(lin[1]), float(lin[2]))


# Grey plating, blue-purple bands, dark blue vanes, red cargo modules, a blue-grey command section.
STATION = Style(
    name="station",
    materials={
        "hull": Material("st_hull", _lin(0x9A9CA2), paneled=True),
        "hull_dark": Material("st_hull_dark", _lin(0x3A3C42), paneled=True),
        "hull_panel": Material("st_hull_panel", _lin(0x6E7076), paneled=True),
        "stripe": Material("st_band", _lin(0x5A5A8C), paneled=True),
        "hazard": Material("st_cargo", _lin(0x8C3C30), paneled=True),
        "hazard_dark": Material("st_vane", _lin(0x1E2A5A), paneled=True),
        "canopy_glass": Material("st_glass", (0.01, 0.012, 0.016)),
        "canopy_frame": Material("st_command", _lin(0x6E7C92), paneled=True),
        "nozzle": Material("st_reactor", _lin(0x585A60), paneled=True),
        "nozzle_throat": Material("st_throat", _lin(0x18181A)),
        "barrel": Material("st_truss", _lin(0x707276)),
        "bore": Material("st_bore", (0.01, 0.01, 0.01)),
        "interior": Material("st_interior", (0.02, 0.02, 0.022)),
        "rcs": Material("st_mast", _lin(0x84868C)),
    },
    panel_size_m=60.0,
    panel_line_width_m=6.0,
    panel_line_darkness=0.6,
    panel_tint_jitter=0.08,
    # The fighters' wear is sized for a centimetre texel; the station is texelled at about 2 m (M4-T30d).
    groove_depth_m=0.8,
    hatch_depth_m=0.3,
    edge_wear_width_m=4.0,
    grime_scale_m=120.0,
    streaks=0.2,
    grime=0.1,
    extra={"wear_scale": 120.0, "rivets": 0.0, "bare_metal": 0.0, "smudge": 0.2, "speckle": 0.04, "paint_roughness": 0.8,
           "streak_length_m": 0.25},
)


def _m(role: str) -> Material:
    return STATION.material(role)


def _part(name: str, mesh: Mesh, markings: tuple[Marking, ...] = ()) -> TexturedPart:
    return TexturedPart(mesh, phase_steps(name, False), markings, name)


def command_windows() -> tuple[Marking, ...]:
    """Rows of lit windows round the command sphere."""
    return tuple(Marking.window_rings("command", (0.0, 0.0, COMMAND_Z), (0.0, 0.0, 1.0), at, WINDOW_ROW_M, WINDOW_PITCH_M, WINDOW_M,
                                      WINDOW_GLOW, WINDOW_STRENGTH, lit=0.6) for at in WINDOW_ROWS_AT_M)


def drum_parts() -> list[TexturedPart]:
    """The habitat drum, centred on its own axis (z from the drum's middle)."""
    mid = 0.5 * (DRUM_FRONT_Z + DRUM_BACK_Z)
    zs = np.linspace(DRUM_FRONT_Z, DRUM_BACK_Z, DRUM_BANDS + 1) - mid
    r = DRUM_RADIUS_M
    profile = [(float(zs[0]), 0.0)] + [(float(z), r) for z in zs] + [(float(zs[-1]), 0.0)]
    bands = [_m("hull_dark")] + [_m("stripe") if i % 2 else _m("hull") for i in range(DRUM_BANDS)] + [_m("hull_dark")]
    mesh = lathe(profile, SEGMENTS, bands, creases=(1, DRUM_BANDS + 1))
    return [_part("drum", mesh)]


def drum_centre() -> list[float]:
    """Where the drum's axis frame sits in the station frame."""
    return [0.0, 0.0, 0.5 * (DRUM_FRONT_Z + DRUM_BACK_Z)]


def _upright(mesh: Mesh, at: tuple[float, float, float], down: bool = False) -> Mesh:
    """A mesh built along local Z stood up along +Y (or -Y) and moved to ``at``."""
    return mesh.transformed(rotation_x(math.pi / 2.0 if down else -math.pi / 2.0), at)


def frame_parts() -> list[TexturedPart]:
    """Every stationary part, in the station frame."""
    parts: list[TexturedPart] = []
    # Reactor drum and flared cap at the stern.
    reactor = lathe(
        [(3400.0, 0.0), (3400.0, 300.0), (3480.0, 350.0), (3880.0, 350.0), (3960.0, 420.0), (4000.0, 470.0), (4000.0, 0.0)],
        64,
        [_m("nozzle"), _m("nozzle"), _m("nozzle"), _m("hull_panel"), _m("hull_panel"), _m("nozzle_throat")],
        creases=(1, 3, 5),
    )
    parts.append(_part("reactor", reactor))
    # Truss spine: four longerons and square frames every 150 m.
    spine = [box((16.0, 16.0, 2100.0), _m("barrel"), (sx * 50.0, sy * 50.0, 2350.0)) for sx in (-1, 1) for sy in (-1, 1)]
    for z in np.arange(1375.0, 3400.0, 150.0):
        spine += [
            box((116.0, 10.0, 10.0), _m("barrel"), (0.0, 50.0, float(z))),
            box((116.0, 10.0, 10.0), _m("barrel"), (0.0, -50.0, float(z))),
            box((10.0, 116.0, 10.0), _m("barrel"), (50.0, 0.0, float(z))),
            box((10.0, 116.0, 10.0), _m("barrel"), (-50.0, 0.0, float(z))),
        ]
    parts.append(_part("spine", Mesh.concatenate(spine)))
    # Funnel from the drum's stern to the spine.
    funnel = lathe([(905.0, 0.0), (905.0, DRUM_RADIUS_M - 5.0), (1300.0, 80.0), (1300.0, 0.0)], 64, _m("hull_panel"), creases=(1, 2))
    parts.append(_part("funnel", funnel))
    # Three pairs of paddle vanes, above and below, spanning 2.5 drum diameters tip to tip.
    tip = 1.25 * 2.0 * DRUM_RADIUS_M
    vanes = []
    for z in (1000.0, 1120.0, 1240.0):
        for down in (False, True):
            paddle = tapered_box(tip - 120.0, (10.0, 50.0), (10.0, 150.0), _m("hazard_dark"))
            centre_y = (120.0 + 0.5 * (tip - 120.0)) * (-1.0 if down else 1.0)
            vanes.append(_upright(paddle, (0.0, centre_y, z), down))
    parts.append(_part("vanes", Mesh.concatenate(vanes)))
    # The top bar over the drum, clear of it, with its struts and the row of cargo modules.
    bar_front, bar_back = DRUM_FRONT_Z - 150.0, DRUM_BACK_Z + 200.0
    bar = [box((60.0, 60.0, bar_back - bar_front), _m("hull_panel"), (0.0, TOP_BAR_Y, 0.5 * (bar_front + bar_back)))]
    bar.append(box((40.0, TOP_BAR_Y, 40.0), _m("hull_panel"), (0.0, 0.5 * TOP_BAR_Y, bar_back - 20.0)))
    bar.append(box((40.0, TOP_BAR_Y - 380.0, 40.0), _m("hull_panel"), (0.0, 380.0 + 0.5 * (TOP_BAR_Y - 380.0), bar_front + 20.0)))
    for z in np.arange(bar_front + 120.0, bar_back - 100.0, 100.0):
        bar.append(box((34.0, 24.0, 60.0), _m("hazard"), (0.0, TOP_BAR_Y + 42.0, float(z))))
    parts.append(_part("topbar", Mesh.concatenate(bar)))
    # Command section: sphere, ring, Cobra-bay arms and masts.
    centre_z, radius = COMMAND_Z, COMMAND_RADIUS_M
    angles = np.linspace(0.0, math.pi, 25)
    sphere_profile = [(centre_z - radius * math.cos(a), radius * math.sin(a)) for a in angles]
    sphere_profile[0] = (sphere_profile[0][0], 0.0)
    sphere_profile[-1] = (sphere_profile[-1][0], 0.0)
    parts.append(_part("command", lathe(sphere_profile, SEGMENTS, _m("canopy_frame")), command_windows()))
    ring = lathe([(centre_z - 60.0, 470.0), (centre_z - 60.0, 560.0), (centre_z + 60.0, 560.0), (centre_z + 60.0, 470.0)], SEGMENTS,
            _m("hull"), creases=(1, 2))
    ring_inner = lathe([(centre_z - 60.0, 470.0), (centre_z + 60.0, 470.0)], SEGMENTS, _m("hull_dark")).flipped()
    arms = [box((300.0, 60.0, 90.0), _m("hull_panel"), (sx * 700.0, 0.0, centre_z)) for sx in (-1, 1)]
    masts = [box((10.0, 2400.0, 10.0), _m("rcs"), (sx * 120.0, 0.0, centre_z + 100.0)) for sx in (-1, 1)]
    parts.append(_part("ring", Mesh.concatenate([ring, ring_inner] + arms + masts)))
    # Forked bow spike.
    spikes = [tapered_box(680.0, (4.0, 4.0), (30.0, 30.0), _m("rcs"), center=(sx * 40.0, 0.0, -3660.0)) for sx in (-1, 1)]
    parts.append(_part("bow", Mesh.concatenate(spikes)))
    return parts


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate both pieces into ``ctx.out_dir``. Option: ``spacing`` (LOD0 spacing, m; each coarser level doubles it)."""
    lod0 = float(ctx.option("spacing", LOD_SPACINGS_M[0]))
    if lod0 <= 0.0:
        raise ValueError("spacing must be positive")
    spacings = tuple(lod0 * 2.0**k for k in range(len(LOD_SPACINGS_M)))
    out_dir: Path = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}", "frame: 3dgs (Rz180 of godot), centred on its own splats")
    texture = PieceTexture(ATLAS_PX, TEXEL_M, ctx.seed)
    files, drum = write_piece(out_dir, f"{ASSET_ID}_drum", drum_parts(), STATION, spacings, ctx.rng, comments, texture)
    drum["pivot"] = drum_centre()
    drum["axis"] = [0.0, 0.0, 1.0]
    frame_files, frame = write_piece(out_dir, f"{ASSET_ID}_frame", frame_parts(), STATION, spacings, ctx.rng, comments, texture)
    files += frame_files
    warnings: list[str] = []
    total = drum["lods"][0]["splats"] + frame["lods"][0]["splats"]
    if abs(lod0 - LOD_SPACINGS_M[0]) < 1e-9 and not LOD0_BUDGET[0] <= total <= LOD0_BUDGET[1]:
        warnings.append(f"{total} LOD0 splats is outside {LOD0_BUDGET}")
    lo = np.minimum(np.array(frame["aabb_min"]), np.array(drum["aabb_min"]) + drum["pivot"])
    hi = np.maximum(np.array(frame["aabb_max"]), np.array(drum["aabb_max"]) + drum["pivot"])
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        lods=[{k: v for k, v in e.items() if k != "centroid"} for e in frame["lods"]],
        aabb_min=lo,
        aabb_max=hi,
        centroid_offset=(0.0, 0.0, 0.0),
        files={"drum_mesh": drum["paint_mesh"]["file"], "frame_mesh": frame["paint_mesh"]["file"]},
        extra={
            "kind_note": "stand-in, shape only (M4-T27)",
            "length_m": LENGTH_M,
            "pieces": {"drum": drum, "frame": frame},
            "lod0_splats": total,
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), tuple(warnings))
