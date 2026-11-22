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

import math

from ..core import capital as cap
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import rotation_z
from ..parts import capital as cp
from ..parts import capital_fittings as fittings
from ..parts import capital_solids as cs
from ..parts import capital_weapons as weapons
from ..parts import ea_omega as om
from ..styles import Style
from ..styles.ea_capital import DEFAULT_LOOK, ea_capital

ASSET_ID = "ea_omega"
GENERATOR_VERSION = 1
SHIP_CLASS = "capital"
LENGTH_M = om.LENGTH_M
DRUM_SPIN_RAD_S = 0.1  # about a third of a g at the arms' bodies, a turn a minute as the show's
REFERENCE_DRUM_DEG = -45.0  # how the reference model has the rotating section turned: its starboard arm low
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
MAGAZINE_Z = (om.AFT_SPINE_Z[0], om.RAILS_END_Z)

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
    return cs.compound(name, [gun, base]).with_params(weapon=weapon)


def weapon_modules(s: Style) -> list[cp.Module]:
    """Every weapon mount in its place and section (centre mounts and the starboard one of each pair)."""
    out: list[cp.Module] = []

    def add(section: str, m: cp.Module, side: str = cp.CENTRE) -> None:
        out.append(m.in_section(section).on_side(side))

    for k, z in enumerate((388.0, 474.0)):
        add("spine_fore", _turret(f"plasma_top_{k + 1}", (0.0, 45.0, z), UP, 24.0, PLASMA, s, (15.0, 21.0)))
        add("spine_fore", _turret(f"plasma_low_{k + 1}", (0.0, -45.0, z), DOWN, 24.0, PLASMA, s, (15.0, 21.0)))
    for tag, section, z in (("fore", "spine_fore", 420.0), ("mid", "magazine", 1030.0), ("aft", "spine_aft", 1135.0)):
        add(section, _turret(f"pulse_{tag}_top_r", (46.0, 60.0, z), UP, 20.0, PULSE, s, (16.0, 6.0)), cp.RIGHT)
        add(section, _turret(f"pulse_{tag}_low_r", (46.0, -60.0, z), DOWN, 20.0, PULSE, s, (16.0, 6.0)), cp.RIGHT)

    # The beams: fore on the shields' pods, aft on the skirt's corners at its stern edge.
    fore = weapons.beam_emitter("beam_fore_r", 34.0, s, arc_deg=HEMISPHERE_DEG).mounted((88.0, 0.0, 226.0), RIGHT)
    add("bow", fore.with_params(weapon=BEAM), cp.RIGHT)
    for tag, sign in (("top", 1.0), ("low", -1.0)):
        normal = (0.387, 0.922 * sign, 0.0)
        aft = weapons.beam_emitter(f"beam_aft_{tag}_r", 30.0, s, arc_deg=HEMISPHERE_DEG).mounted((68.2, 84.7 * sign, 1385.0), normal, (0.0, 0.0, 1.0))
        add("reactor", aft.with_params(weapon=BEAM), cp.RIGHT)

    for tag, up, y in (("top", UP, 51.0), ("low", DOWN, -51.0)):
        battery = weapons.missile_launcher(f"missile_{tag}", (3, 4), 5.0, s).mounted((0.0, y, 975.0), up)
        add("magazine", battery.with_params(weapon=MISSILE))

    for name, section, at in (("interceptor_bow_r", "bow", (68.0, 30.0, 310.0)), ("interceptor_fore_r", "spine_fore", (50.0, 0.0, 400.0)),
                              ("interceptor_aft_r", "spine_aft", (50.0, 0.0, 1150.0)), ("interceptor_stern_r", "engine_r", (72.0, 0.0, 1560.0))):
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
    """The rotating section's modules. At rest the arms reach to port and starboard and the port arm is the starboard one's
    twin; turned by ``deg`` both arms are built where they stand."""
    parts = [*om.drum_hub(s, "drum_hub"), *om.drum_arm(s, "hangar_r")]
    if deg == 0.0:
        return parts
    turn = rotation_z(math.radians(deg))
    both = [q for m in parts for q in ((m, m.twin()) if m.side == cp.RIGHT else (m,))]
    return [m.transformed(turn).on_side(cp.LONE) for m in both]


def modules(look: str = DEFAULT_LOOK, drum_deg: float = 0.0) -> list[cp.Module]:
    """Every module in its place and section (centre modules and the starboard one of each pair)."""
    s = ea_capital(look).style
    aft_a, aft_b = (om.AFT_SPINE_Z[0], MAGAZINE_Z[1]), (MAGAZINE_Z[1], om.AFT_SPINE_Z[1])
    return [
        *om.shields(s), *om.command_block(s), *om.tankage(s), *om.aerials(s),
        *om.spine(s, "spine_fore", "spine_fore", om.FORE_SPINE_Z, strake=(472.0, 504.0)),
        om.collar(s, "collar_fore", "spine_fore", om.FORE_COLLAR_Z), om.axle(s, "spine_fore"),
        *_drum(s, drum_deg),
        om.collar(s, "collar_aft", "magazine", om.AFT_COLLAR_Z),
        *om.spine(s, "spine_mid", "magazine", aft_a), *om.spine(s, "spine_aft", "spine_aft", aft_b, rails=False),
        *om.housing(s, "reactor"), *om.tail(s, "reactor"),
        om.engine(s, "engine_top_r", "engine_r", 1.0), om.engine(s, "engine_low_r", "engine_r", -1.0), *om.engine_frame(s, "engine_r"),
        *weapon_modules(s), *light_modules(),
    ]  # fmt: skip


def spec(look: str = DEFAULT_LOOK, drum_deg: float = 0.0) -> cap.CapitalSpec:
    return cap.CapitalSpec(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        ship_class=SHIP_CLASS,
        modules=tuple(modules(look, drum_deg)),
        sections=SECTIONS,
        style=ea_capital(look),
        bridge=cap.Pose((0.0, 0.0, 180.0)),
        pieces=PIECES,
        jump_point=cap.JumpPoint(ahead_m=1500.0, mouth_radius_m=450.0),
        notes=("the renegades' red X marks (M10-T02) are `mark` hardpoints with `only_faction`: the game draws them on a renegade ship",),
    )


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the Omega into ``ctx.out_dir``."""
    return cap.build(spec(str(ctx.option("look", DEFAULT_LOOK)), float(ctx.option("drum_deg", 0.0))), ctx)


__all__ = ["ASSET_ID", "GENERATOR_VERSION", "LENGTH_M", "PIECES", "REFERENCE_DRUM_DEG", "SECTIONS", "SHIP_CLASS", "build", "modules", "spec"]
