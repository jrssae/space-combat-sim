"""``ea_omega``: the Earth Alliance Omega-class destroyer (M10-T21), the first real hull on the capital framework
(``core/capital.py``; docs/assets-capital.md, "Capital framework"). 1 714.3 m long, a capital by its budget class.

The structure is ``parts/ea_omega.py`` (measured off the reference model); this file stands the weapons, bays and lights on
it and names the damage sections. The loadout is ``data/capitals/loadouts.json``, ``ea_omega`` (M10-T03, Q53): each mount's
``weapon`` names the weapon that stands on it and each bay's ``craft`` and ``capacity`` what it launches.

* 4 heavy plasma turrets on the forward spine's centre line, two above and two below;
* 12 pulse turrets on the spines' corners: one ring of four forward, two rings aft;
* 6 sweeping beams: one on each shield's pod covering the fore hemisphere, four on the skirt's corners covering the aft;
* 2 missile batteries on the aft spine, above and below, over the magazine;
* 8 interceptors along the flanks;
* 1 launch bay facing the bow from the command block's fore face, above the retro thrusters (the maintainer, 2026-11-21),
  in the bow section: all 32 Starfuries.

Sections: bow, bridge, fuel (the tankage under the command block), the fore spine, the rotating section's hub and its two
arms (the hangars), the magazine (the aft spine's forward half), the aft spine (the jump engine's place), the reactor (the
engine housing) and an engine pair each side.

Options: ``look`` (``styles/ea_capital.LOOKS``), ``drum_deg`` (the rotating section turned from its rest, for the compare
against the reference, which has it at -45 degrees), and ``spacing``, ``atlas_px``, ``detail_px`` (``core/capital.build``).
"""

from __future__ import annotations

import dataclasses
import math

import numpy as np

from ..core import capital as cap
from ..core import collision as col
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import rotation_z
from ..parts import capital as cp
from ..parts import capital_fittings as fittings
from ..parts import capital_solids as cs
from ..parts import capital_weapons as weapons
from ..parts import ea_omega as om
from ..parts import ea_omega_bow as bow
from ..parts import ea_omega_marks as marks
from ..parts.capital_flush import set_back_flush_parts
from ..styles import Style
from ..styles.ea_capital import DEFAULT_LOOK
from ..styles.ea_omega import ea_omega as ea_omega_style

ASSET_ID = "ea_omega"
GENERATOR_VERSION = 1
SHIP_CLASS = "capital"
LENGTH_M = om.LENGTH_M
DRUM_SPIN_RAD_S = 0.1  # about a third of a g at the arms' bodies, a turn a minute as the show's
REST_DRUM_DEG = 90.0  # the rotating section at rest: its arms up and down, the kit's pose (M10-T68)
ATLAS_PX = 4096

# Blast energies (docs/assets-capital.md, "Sections, mounts and blasts": 5e6 J a point of D0; a capital's rows).
BLAST_J = {"magazine": 5.0e6 * 1800.0, "fuel": 5.0e6 * 1200.0, "reactor": 5.0e6 * 4500.0}
SECTIONS = (
    cap.Section("bow", "structure", 0.07),
    cap.Section("bridge", "bridge", 0.05),
    cap.Section("fuel", "fuel", 0.08, BLAST_J["fuel"]),
    cap.Section("spine_fore", "structure", 0.09),
    cap.Section("drum_hub", "habitat", 0.04, piece="drum"),
    cap.Section("hangar_r", "hangar", 0.10, piece="drum"),  # and its port twin, hangar_l
    cap.Section("magazine", "magazine", 0.10, BLAST_J["magazine"]),
    cap.Section("spine_aft", "structure", 0.08),
    cap.Section("reactor", "reactor", 0.14, BLAST_J["reactor"]),
    cap.Section("engine_r", "engine", 0.075),  # and its port twin, engine_l
)
PIECES = (cap.PieceSpec(cap.HULL_PIECE, ATLAS_PX), cap.PieceSpec("drum", ATLAS_PX, om.DRUM_PIVOT, (0.0, 0.0, 1.0), DRUM_SPIN_RAD_S))
MAGAZINE_Z = (om.AFT_SPINE_Z[0], om.MAGAZINE_END_Z)

PLASMA_Z = (440.0, 505.0)  # the heavy plasma turrets' places along the forward spine
TURRET_ARC = (-10.0, 90.0)  # T: a 200 degree cone round the mount's up
HEMISPHERE_DEG = 90.0
PULSE, PLASMA, BEAM, MISSILE, INTERCEPTOR = "ea_pulse_medium", "ea_plasma_heavy", "ea_sweep_beam", "ea_missile", "ea_interceptor"
UP, DOWN, RIGHT = (0.0, 1.0, 0.0), (0.0, -1.0, 0.0), (1.0, 0.0, 0.0)
RUNNING_RED = (1.0, 0.22, 0.05)  # the show's red-orange


def _turret(name: str, at: tuple[float, float, float], up: tuple[float, float, float], size: float, weapon: str, s: Style,
            pedestal: tuple[float, float]) -> cp.Module:
    """A gun turret on a pedestal (half width, height) standing on the hull at ``at``."""
    half, tall = pedestal
    sign = up[1]
    y0, y1 = sorted((at[1], at[1] + sign * tall))
    base = cs.box("pedestal", (at[0] - half, y0, at[2] - half), (at[0] + half, y1, at[2] + half), s, om.DARK, skin=cp.SKIN_FITTING)
    gun = weapons.turret_mount(name, size, s, elevation_deg=TURRET_ARC).mounted((at[0], at[1] + sign * tall, at[2]), up)
    turret = cs.compound(name, [gun, base]).with_params(weapon=weapon)
    # The pedestal in the turret's body hull (one shape fewer a mount, for the hull's shape budget); the barrels keep theirs.
    body, *rest = gun.shapes
    joined = col.hull(f"{name}_0", np.concatenate([body.points, base.shapes[0].points]))
    return dataclasses.replace(turret, shapes=(joined, *(q.renamed(f"{name}_{k + 1}") for k, q in enumerate(rest))))


def weapon_modules(s: Style) -> list[cp.Module]:
    """Every weapon mount in its place and section (centre mounts and the starboard one of each pair)."""
    out: list[cp.Module] = []

    def add(section: str, m: cp.Module, side: str = cp.CENTRE) -> None:
        out.append(m.in_section(section).on_side(side))

    # The heavies stand aft of the shields' ends and clear of the forward pulse ring's line, so the forward quarter is theirs too
    # (M10-T68: at 388 and 474 m the rebuilt shields and the pulse turrets hid a target 50 degrees off the bow).
    for k, z in enumerate(PLASMA_Z):
        add("spine_fore", _turret(f"plasma_top_{k + 1}", (0.0, 57.0, z), UP, 24.0, PLASMA, s, (12.0, 9.0)))
        add("spine_fore", _turret(f"plasma_low_{k + 1}", (0.0, -57.0, z), DOWN, 24.0, PLASMA, s, (12.0, 9.0)))
    for tag, section, z in (("fore", "spine_fore", 420.0), ("mid", "magazine", 1030.0), ("aft", "spine_aft", 1135.0)):
        add(section, _turret(f"pulse_{tag}_top_r", (46.0, 60.0, z), UP, 20.0, PULSE, s, (10.0, 6.0)), cp.RIGHT)
        add(section, _turret(f"pulse_{tag}_low_r", (46.0, -60.0, z), DOWN, 20.0, PULSE, s, (10.0, 6.0)), cp.RIGHT)

    # The beams: fore on the shields' pods, aft on the skirt's corners at its stern edge.
    fore = weapons.beam_emitter("beam_fore_r", 34.0, s, arc_deg=HEMISPHERE_DEG).mounted((88.0, 0.0, 226.0), RIGHT)
    add("bow", fore.with_params(weapon=BEAM), cp.RIGHT)
    for tag, sign in (("top", 1.0), ("low", -1.0)):
        normal = (0.47, 0.88 * sign, 0.0)  # off the reactor cage's corner plate
        aft = weapons.beam_emitter(f"beam_aft_{tag}_r", 30.0, s, arc_deg=HEMISPHERE_DEG).mounted((70.0, 84.6 * sign, 1385.0), normal, (0.0, 0.0, 1.0))
        add("reactor", aft.with_params(weapon=BEAM), cp.RIGHT)

    for tag, up, y in (("top", UP, 57.0), ("low", DOWN, -57.0)):
        battery = weapons.missile_launcher(f"missile_{tag}", (3, 4), 5.0, s).mounted((0.0, y, 975.0), up)  # on the deck plate
        add("magazine", battery.with_params(weapon=MISSILE))

    for name, section, at in (("interceptor_bow_r", "bow", (68.0, 30.0, 310.0)), ("interceptor_fore_r", "spine_fore", (41.0, 0.0, 400.0)),
                              ("interceptor_aft_r", "spine_aft", (41.0, 0.0, 1150.0)), ("interceptor_stern_r", "engine_r", (68.0, 0.0, 1560.0))):
        add(section, weapons.interceptor_dome(name, 4.5, s).mounted(at, RIGHT).with_params(weapon=INTERCEPTOR), cp.RIGHT)
    return out


def light_modules() -> list[cp.Module]:
    """The running lights: red to port and green to starboard on the shields, white on the roof, the show's red-orange
    beacons at the keel and the stern."""
    lamp = fittings.lamp
    return [
        lamp("light_starboard", "starboard", (0.05, 1.0, 0.1), 400.0, 4.0).mounted((68.0, 40.0, 330.0), RIGHT).in_section("bow").on_side(cp.LONE),
        lamp("light_port", "port", (1.0, 0.05, 0.03), 400.0, 4.0).mounted((-68.0, 40.0, 330.0), (-1.0, 0.0, 0.0)).in_section("bow").on_side(cp.LONE),
        lamp("light_top", "top", (1.0, 1.0, 1.0), 400.0, 4.0).mounted((0.0, 62.5, 240.0 + 12.0), UP).in_section("bridge"),
        lamp("light_keel", "beacon", RUNNING_RED, 600.0, 4.0).mounted((0.0, -207.0, 240.0), DOWN).in_section("bow"),
        lamp("light_stern", "beacon", RUNNING_RED, 600.0, 4.0).mounted((0.0, 71.0, 1640.0), UP).in_section("reactor"),
    ]


def _drum(s: Style, deg: float) -> list[cp.Module]:
    """The rotating section's modules, its arms turned ``deg`` from port and starboard (at rest they stand up and down, the kit's
    pose), both built where they stand; at 0 the port arm is the starboard one's twin."""
    parts = [*om.drum_hub(s, "drum_hub"), *om.drum_arm(s, "hangar_r")]
    if deg == 0.0:
        return parts
    turn = rotation_z(math.radians(deg))
    both = [q for m in parts for q in ((m, m.twin()) if m.side == cp.RIGHT else (m,))]
    return [m.transformed(turn).on_side(cp.LONE) for m in both]


def style(look: str = DEFAULT_LOOK) -> cap.CapitalStyle:
    """The fleet's look in the Agamemnon pattern (Q98, ``styles/ea_omega.py``), the bay lined in grey metal."""
    return ea_omega_style(look)


def modules(look: str = DEFAULT_LOOK, drum_deg: float = REST_DRUM_DEG) -> list[cp.Module]:
    """Every module in its place and section (centre modules and the starboard one of each pair)."""
    s = style(look).style
    aft_a, aft_b = (om.AFT_SPINE_Z[0], MAGAZINE_Z[1]), (MAGAZINE_Z[1], om.AFT_SPINE_Z[1])
    return set_back_flush_parts([_with_marks(m) for m in [
        *om.shields(s), *om.command_block(s), *bow.bay(s), *bow.decks(s), *bow.under_bay(s), *om.aerials(s),
        *om.spine(s, "spine_fore", "spine_fore", om.FORE_SPINE_Z, strakes=((471.0, om.FORE_SPINE_Z[1]),)),
        om.spine_block(s, "spine_fore_block", "spine_fore", (494.0, om.FORE_SPINE_Z[1]), 55.0),
        om.collar(s, "collar_fore", "spine_fore", om.FORE_COLLAR_Z), om.axle(s, "spine_fore"),
        *_drum(s, drum_deg),
        om.collar(s, "collar_aft", "magazine", om.AFT_COLLAR_Z),
        *om.spine(s, "spine_mid", "magazine", aft_a, strakes=((aft_a[0], 961.0), (1053.0, aft_a[1]))),
        om.spine_block(s, "spine_mid_block", "magazine", (aft_a[0], 932.0), 55.0),
        *om.spine(s, "spine_aft", "spine_aft", aft_b, strakes=((aft_b[0], 1106.0), (1196.0, aft_b[1]))),
        om.spine_block(s, "spine_aft_block", "spine_aft", (1196.0, aft_b[1]), 62.0),
        *om.housing(s, "reactor"), *om.tail(s, "reactor"),
        om.engine(s, "engine_top_r", "engine_r", 1.0), om.engine(s, "engine_low_r", "engine_r", -1.0), *om.engine_frame(s, "engine_r"),
        *weapon_modules(s), *light_modules(), *marks.lamps(s), *marks.red_fittings(),
    ]])  # fmt: skip


def _with_marks(m: cp.Module) -> cp.Module:
    """The parts that wear paint marks: the starboard shield's vertical panel its name and emblem, the spine blocks their warning
    stickers (``parts/ea_omega_marks.py``)."""
    (fore, fore_x, fore_z, _), (aft, aft_x, aft_z, _) = marks.STICKERS
    extra = {"shield_mid_r": (marks.name_mark(), marks.emblem_mark()), "spine_fore_block": marks.stickers(fore, fore_x, fore_z),
             "spine_aft_block": marks.stickers(aft, aft_x, aft_z)}
    if m.name not in extra:
        return m
    return dataclasses.replace(m, hardpoints=(*m.hardpoints, *extra[m.name]))


def markings(look: str = DEFAULT_LOOK) -> tuple:
    """What the hull's maps bake beyond the plating: the floods' pools and the big plates' edge band."""
    return (*marks.flood_pools(), *marks.bands(modules(look), style(look).style.materials["hull"].albedo))


def spec(look: str = DEFAULT_LOOK, drum_deg: float = REST_DRUM_DEG) -> cap.CapitalSpec:
    return cap.CapitalSpec(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        ship_class=SHIP_CLASS,
        modules=tuple(modules(look, drum_deg)),
        sections=SECTIONS,
        style=style(look),
        bridge=cap.Pose((0.0, 0.0, 180.0)),
        pieces=PIECES,
        jump_point=cap.JumpPoint(ahead_m=1500.0, mouth_radius_m=450.0),
        notes=("the renegades' red X marks (M10-T02) are `mark` hardpoints with `only_faction`: the game draws them on a renegade ship",
               "the floods' pools of light and the big plates' darker edge band are baked into the hull's maps; the name, the Earth Alliance "
               "emblem and the warning stickers are marks the game draws sharp (M10-T68)"),
        markings=markings(look),
    )


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the Omega into ``ctx.out_dir``."""
    return cap.build(spec(str(ctx.option("look", DEFAULT_LOOK)), float(ctx.option("drum_deg", REST_DRUM_DEG))), ctx)


__all__ = ["ASSET_ID", "GENERATOR_VERSION", "LENGTH_M", "PIECES", "REST_DRUM_DEG", "SECTIONS", "SHIP_CLASS", "build", "modules", "spec"]
