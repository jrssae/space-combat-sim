"""``ea_nova``: the Earth Alliance Nova-class dreadnought (M10-T23) on the capital framework (``core/capital.py``), in the
Omega's parts and look (``assets/ea_omega.py``; docs/assets-capital.md, "`ea_omega`"). 1 502.1 m long, a capital by its
budget class.

The structure is ``parts/ea_nova.py`` (measured off the reference model); this file stands the weapons, bays and lights on
it and names the damage sections. The loadout is ``data/capitals/loadouts.json``, ``ea_nova`` (M10-T03, Q53): each mount's
``weapon`` names the weapon that stands on it and each bay's ``craft`` and ``capacity`` what it launches.

* 18 twin plasma turrets (TBP's twin cannons) along the girder: six on each flank's waist, three on the roof's channel and
  three under the keel;
* 6 sweeping beams at 80 % (the Omega's): one on each flank of the command block covering the fore hemisphere, four on the
  engine housing's corners covering the aft;
* 6 interceptors along the flanks;
* 6 launch bays facing the bow from the hangar block's fore face (the Omega's lit bay), 4 Starfuries each (24).

Sections: bow (the armour and aerials), bridge, fuel (the tankage), the fore spine, the hangar block, the mid spine, the aft
spine (the jump engine's place), the reactor (the engine housing) and an engine pair each side.

Options: ``look`` (``styles/ea_capital.LOOKS``), and ``spacing``, ``atlas_px``, ``detail_px`` (``core/capital.build``).
"""

from __future__ import annotations

from ..core import capital as cap
from ..core.context import AssetOutputs, BuildContext
from ..parts import capital as cp
from ..parts import capital_fittings as fittings
from ..parts import capital_solids as cs
from ..parts import capital_weapons as weapons
from ..parts import ea_nova as nv
from ..styles import Style
from ..styles.ea_capital import DEFAULT_LOOK, ea_capital
from .ea_omega import HEMISPHERE_DEG, RUNNING_RED, TURRET_ARC, _turret

ASSET_ID = "ea_nova"
GENERATOR_VERSION = 1
SHIP_CLASS = "capital"
LENGTH_M = nv.LENGTH_M
ATLAS_PX = 4096

# Blast energies (docs/assets-capital.md, "Sections, mounts and blasts": 5e6 J a point of D0; a capital's rows).
BLAST_J = {"fuel": 5.0e6 * 1200.0, "reactor": 5.0e6 * 4500.0}
SECTIONS = (
    cap.Section("bow", "structure", 0.07),
    cap.Section("bridge", "bridge", 0.06),
    cap.Section("fuel", "fuel", 0.06, BLAST_J["fuel"]),
    cap.Section("spine_fore", "structure", 0.13),
    cap.Section("hangar", "hangar", 0.14),
    cap.Section("spine_mid", "structure", 0.08),
    cap.Section("spine_aft", "structure", 0.09),
    cap.Section("reactor", "reactor", 0.17, BLAST_J["reactor"]),
    cap.Section("engine_r", "engine", 0.10),  # and its port twin, engine_l
)
PIECES = (cap.PieceSpec(cap.HULL_PIECE, ATLAS_PX),)

PLASMA, BEAM, INTERCEPTOR = "ea_plasma_medium", "ea_sweep_beam_nova", "ea_interceptor"
UP, DOWN, RIGHT = (0.0, 1.0, 0.0), (0.0, -1.0, 0.0), (1.0, 0.0, 0.0)
TURRET_M = 16.0
FLANK_Z = (("fore", "spine_fore", (434.0, 452.0)), ("mid", "spine_mid", (860.0, 880.0)), ("aft", "spine_aft", (960.0, 1022.0)))
MID_END_Z = 903.0  # where the mid spine (the first aft bay's gun deck) gives way to the aft spine
CHANNEL_Z = ((438.0, "spine_fore"), (876.0, "spine_mid"), (971.0, "spine_aft"))


def _flank_turret(name: str, z: float, s: Style) -> cp.Module:
    """A twin turret on the starboard waist, its pedestal standing out of the flank."""
    x0, x1 = 45.0, 47.0
    base = cs.box("pedestal", (x0, -8.0, z - 8.0), (x1, 8.0, z + 8.0), s, nv.DARK, skin=cp.SKIN_FITTING)
    gun = weapons.turret_mount(name, TURRET_M, s, elevation_deg=TURRET_ARC).mounted((x1, 0.0, z), RIGHT, (0.0, 0.0, -1.0))
    return cs.compound(name, [gun, base]).with_params(weapon=PLASMA)


def weapon_modules(s: Style) -> list[cp.Module]:
    """Every weapon mount in its place and section (centre mounts and the starboard one of each pair)."""
    out: list[cp.Module] = []

    def add(section: str, m: cp.Module, side: str = cp.CENTRE) -> None:
        out.append(m.in_section(section).on_side(side))

    for tag, section, zs in FLANK_Z:
        for k, z in enumerate(zs):
            add(section, _flank_turret(f"plasma_{tag}_{k + 1}_r", z, s), cp.RIGHT)
    for k, (z, section) in enumerate(CHANNEL_Z):
        add(section, _turret(f"plasma_top_{k + 1}", (0.0, nv.CORE_H, z), UP, TURRET_M, PLASMA, s, (9.0, 4.0)))
        add(section, _turret(f"plasma_low_{k + 1}", (0.0, -nv.CORE_H, z), DOWN, TURRET_M, PLASMA, s, (9.0, 4.0)))

    # The beams: fore on the command block's flanks, aft on the housing's corners at its stern edge.
    fore = weapons.beam_emitter("beam_fore_r", 30.0, s, arc_deg=HEMISPHERE_DEG).mounted((nv.PLATE_X, 32.0, 236.0), RIGHT)
    add("bow", fore.with_params(weapon=BEAM), cp.RIGHT)
    for tag, sign in (("top", 1.0), ("low", -1.0)):
        normal = (0.39, 0.92 * sign, 0.0)
        aft = weapons.beam_emitter(f"beam_aft_{tag}_r", 28.0, s, arc_deg=HEMISPHERE_DEG).mounted((76.0, 87.0 * sign, 1218.0), normal, (0.0, 0.0, 1.0))
        add("reactor", aft.with_params(weapon=BEAM), cp.RIGHT)

    for name, section, at, up in (("interceptor_bow_r", "bow", (nv.PLATE_X, -30.0, 340.0), RIGHT),
                                  ("interceptor_hangar_r", "hangar", (nv.HANGAR_W, 30.0, 740.0 - 12.0), RIGHT),
                                  ("interceptor_stern_r", "reactor", (88.0, 40.0, 1190.0), RIGHT)):
        add(section, weapons.interceptor_dome(name, 4.5, s).mounted(at, up).with_params(weapon=INTERCEPTOR), cp.RIGHT)
    return out


def light_modules() -> list[cp.Module]:
    """The running lights: red to port and green to starboard on the armour, white on the roof, the show's red-orange
    beacons under the keel and at the stern."""
    lamp = fittings.lamp
    return [
        lamp("light_starboard", "starboard", (0.05, 1.0, 0.1), 400.0, 4.0).mounted((nv.PLATE_X, 50.0, 360.0), RIGHT).in_section("bow").on_side(cp.LONE),
        lamp("light_port", "port", (1.0, 0.05, 0.03), 400.0, 4.0).mounted((-nv.PLATE_X, 50.0, 360.0), (-1.0, 0.0, 0.0)).in_section("bow").on_side(cp.LONE),
        lamp("light_top", "top", (1.0, 1.0, 1.0), 400.0, 4.0).mounted((0.0, 74.0, 290.0), UP).in_section("bridge"),
        lamp("light_keel", "beacon", RUNNING_RED, 600.0, 4.0).mounted((0.0, -171.0, 240.0), DOWN).in_section("bow"),
        lamp("light_stern", "beacon", RUNNING_RED, 600.0, 4.0).mounted((0.0, 106.0, 1290.0), UP).in_section("reactor"),
    ]


def modules(look: str = DEFAULT_LOOK) -> list[cp.Module]:
    """Every module in its place and section (centre modules and the starboard one of each pair)."""
    s = ea_capital(look).style
    (c0, c1), (r0, r1, r2) = nv.COLLARS_Z, nv.RINGS_Z
    return [
        *nv.armour(s), *nv.command_block(s), *nv.flank_strake(s), *nv.tankage(s), *nv.aerials(s),
        *nv.spine(s, "spine_fore", "spine_fore", (nv.SPINE_Z[0], c0[0]), shelf_x=62.0), *nv.ring(s, "ring_fore", "spine_fore", r0),
        *nv.flank_fittings(s, "spine_fore", "spine_fore", waists=((nv.SPINE_Z[0], 402.0),), decks=((402.0, 481.0),), strips=((456.0, 519.0),),
                           pods=((466.8, 508.2),)),
        nv.collar(s, "collar_fore", "spine_fore", c0),
        *nv.spine(s, "spine_hangar", "hangar", nv.HANGAR_Z), *nv.hangar_block(s, "hangar"),
        nv.collar(s, "collar_aft", "spine_mid", c1),
        *nv.spine(s, "spine_mid", "spine_mid", (c1[1], MID_END_Z)), *nv.ring(s, "ring_mid", "spine_mid", r1),
        *nv.flank_fittings(s, "spine_mid", "spine_mid", decks=((819.0, 903.0),), strips=((780.0, 843.0),), pods=((790.8, 832.2),)),
        *nv.spine(s, "spine_aft", "spine_aft", (MID_END_Z, nv.SPINE_Z[1])), *nv.ring(s, "ring_aft", "spine_aft", r2),
        *nv.flank_fittings(s, "spine_aft", "spine_aft", waists=((910.0, 940.0), (1038.0, nv.SPINE_Z[1])), decks=((946.0, 1031.0),),
                           strips=((936.0, 998.0), (1045.0, 1056.0)), pods=((944.8, 967.2),)),
        *nv.housing(s, "reactor"),
        nv.engine(s, "engine_top_r", "engine_r", 1.0), nv.engine(s, "engine_low_r", "engine_r", -1.0), *nv.engine_frame(s, "reactor"),
        *weapon_modules(s), *light_modules(),
    ]  # fmt: skip


def spec(look: str = DEFAULT_LOOK) -> cap.CapitalSpec:
    return cap.CapitalSpec(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        ship_class=SHIP_CLASS,
        modules=tuple(modules(look)),
        sections=SECTIONS,
        style=ea_capital(look),
        bridge=cap.Pose((0.0, 1.5, nv.PLATE_Z[0] + 2.0)),
        pieces=PIECES,
        jump_point=cap.JumpPoint(ahead_m=1500.0, mouth_radius_m=400.0),
        notes=("the renegades' red X marks (M10-T02) are `mark` hardpoints with `only_faction`: the game draws them on a renegade ship",),
    )


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the Nova into ``ctx.out_dir``."""
    return cap.build(spec(str(ctx.option("look", DEFAULT_LOOK))), ctx)


__all__ = ["ASSET_ID", "GENERATOR_VERSION", "LENGTH_M", "PIECES", "SECTIONS", "SHIP_CLASS", "build", "modules", "spec"]
