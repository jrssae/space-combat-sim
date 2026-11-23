"""``ea_hyperion``: the Earth Alliance Hyperion-class heavy cruiser (M10-T22) on the capital framework (``core/capital.py``;
docs/assets-capital.md, "Capital framework"). 1 025.39 m long, a capital by its budget class. A different class from the Omega:
its own parts and its own style (``styles/ea_hyperion.py``), with the fleet's shared features (red-lit bays, the renegades'
red X marks, the loadout check).

The structure is ``parts/ea_hyperion.py`` (measured off the reference model); this file stands the weapons and lights on it
and names the damage sections. The loadout is ``data/capitals/loadouts.json``, ``ea_hyperion`` (M10-T03, Q49, Q53):

* 2 heavy plasma cannons, fixed forward: the muzzles of two rods of the front antenna array (not symmetric), rooted in the
  recess in the bow's face;
* 2 particle cannons (beams, the fore cone): twin barrels raised from the deck's slope, and lowered from under the keel;
* 2 medium plasma dome turrets, one on each flank;
* 4 light pulse dome turrets: on the turret deck, the tower's drum, the reactor module and the engine block;
* 2 torpedo tubes in the bow face's recess;
* 4 interceptors: one on each pod under the tower and one on each sponson's aft face;
* three single-Starfury bays in each flank of the hangar bump on the spine, and a shuttle bay for both shuttles in the
  tower's aft face (Q58): 6 Starfuries and 2 shuttles.

Sections: bow, magazine (the forward hull's aft half and the sponsons, over the torpedo stowage), bridge (the tower, its
pods and the shuttle bay), the hangar bays either side, the truss, the reactor (the module), the aft spine, the fuel tanks
either side and the engines.

Options: ``look`` (``styles/ea_hyperion.LOOKS``), ``spacing``, ``atlas_px``, ``detail_px`` (``core/capital.build``).
"""

from __future__ import annotations

from ..core import capital as cap
from ..core.context import AssetOutputs, BuildContext
from ..parts import capital as cp
from ..parts import capital_fittings as fittings
from ..parts import capital_weapons as weapons
from ..parts import ea_hyperion as hy
from ..styles import Style
from ..styles.ea_hyperion import DEFAULT_LOOK, ea_hyperion

ASSET_ID = "ea_hyperion"
GENERATOR_VERSION = 1
SHIP_CLASS = "capital"
LENGTH_M = hy.LENGTH_M
ATLAS_PX = 4096

# Blast energies (docs/assets-capital.md, "Sections, mounts and blasts": 5e6 J a point of D0; a capital's rows).
BLAST_J = {"magazine": 5.0e6 * 1000.0, "fuel": 5.0e6 * 700.0, "reactor": 5.0e6 * 2600.0}
SECTIONS = (
    cap.Section("bow", "structure", 0.12),
    cap.Section("magazine", "magazine", 0.12, BLAST_J["magazine"]),
    cap.Section("bridge", "bridge", 0.07),
    cap.Section("hangar_r", "hangar", 0.05),  # and its port twin, hangar_l
    cap.Section("truss", "structure", 0.09),
    cap.Section("reactor", "reactor", 0.15, BLAST_J["reactor"]),
    cap.Section("spine_aft", "structure", 0.08),
    cap.Section("fuel_r", "fuel", 0.04, BLAST_J["fuel"]),  # and its port twin, fuel_l
    cap.Section("engines", "engine", 0.19),
)
PIECES = (cap.PieceSpec(cap.HULL_PIECE, ATLAS_PX),)

PULSE, PLASMA_MEDIUM, PLASMA_HEAVY = "ea_pulse_light", "ea_plasma_medium", "ea_plasma_heavy"
PARTICLE, TORPEDO, INTERCEPTOR = "ea_particle_cannon", "ea_torpedo", "ea_interceptor"
UP, DOWN, RIGHT, FORE, AFT = (0.0, 1.0, 0.0), (0.0, -1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 0.0, 1.0)
RUNNING_RED = (1.0, 0.22, 0.05)  # the show's red-orange
FLOOD_LAMP = (1.0, 0.92, 0.82)  # every flood lamp's warm white face


def weapon_modules(s: Style) -> list[cp.Module]:
    """Every weapon mount in its place and section (centre mounts and the starboard one of each pair)."""
    out: list[cp.Module] = []

    def add(section: str, m: cp.Module, side: str = cp.CENTRE) -> None:
        out.append(m.in_section(section).on_side(side))

    add("bow", hy.front_array(s).with_params(weapon=PLASMA_HEAVY), cp.LONE)  # lopsided: the first STL's rods
    add("bow", weapons.missile_launcher("torpedo_r", (1, 1), 6.0, s).mounted((7.0, 8.0, hy.NOSE_FLOOR_Z), FORE, UP).with_params(weapon=TORPEDO), cp.RIGHT)
    add("bow", hy.particle_cannon("particle_top", (0.0, 33.0, 125.0), (0.0, 41.0, 70.0), s).with_params(weapon=PARTICLE))
    add("bow", hy.particle_cannon("particle_low", (0.0, -44.0, 118.0), (0.0, -46.0, 60.0), s, spread=3.7, normal=DOWN).with_params(weapon=PARTICLE))
    add("magazine", hy.dome_turret("plasma_flank_r", 14.0, s).mounted((62.2, -22.0, 283.0), RIGHT).with_params(weapon=PLASMA_MEDIUM), cp.RIGHT)
    # The deck's and the tower's turrets rest facing forward, the module's and the engine block's aft (the reference's).
    # The engine block's turret counts in the aft spine's section, as the sponsons' lamps in the bridge's: the engines' and the
    # magazine's sections are full (64 collision shapes) and a merged shape would bridge the hull's hollows.
    for name, section, at, r, collar, rest in (("pulse_deck", "magazine", (0.0, hy.DECK_H - 0.5, 283.0), 16.0, 3.0, FORE),
                                               ("pulse_tower", "bridge", (0.0, hy.TOWER_DRUM_Y, hy.TOWER_DRUM_Z), 12.0, 3.0, FORE),
                                               ("pulse_module", "reactor", (0.0, hy.MODULE_Y[1] - 0.5, 697.0), 14.0, 6.0, AFT),
                                               ("pulse_engines", "spine_aft", (0.0, hy.BLOCK_Y[1] - 0.5, 935.0), 15.0, 6.0, AFT)):
        add(section, hy.dome_turret(name, r, s, collar).mounted(at, UP, rest).with_params(weapon=PULSE))
    add("bridge", weapons.interceptor_dome("interceptor_pod_1", 4.5, s).mounted((10.0, -140.0, 407.5), RIGHT).with_params(weapon=INTERCEPTOR), cp.LONE)
    add("bridge", weapons.interceptor_dome("interceptor_pod_2", 4.5, s).mounted((-21.0, -140.0, 444.0), (-1.0, 0.0, 0.0)).with_params(weapon=INTERCEPTOR),
        cp.LONE)
    sponson = weapons.interceptor_dome("interceptor_sponson_r", 4.5, s).mounted((66.0, -47.5, hy.SPONSON_Z[1]), AFT, UP).with_params(weapon=INTERCEPTOR)
    out.append(sponson.in_section("bridge").on_side(cp.RIGHT))
    return out


def light_modules() -> list[cp.Module]:
    """The running lights: red to port and green to starboard on the sponsons, white on the tower, the show's red-orange
    beacons under the big pod and on the engine block; and the flood lamps (``hy.FLOODS``), whose pools are baked into the hull."""
    lamp = fittings.lamp
    return [
        lamp("light_starboard", "starboard", (0.05, 1.0, 0.1), 300.0, 3.0).mounted((88.3, -47.0, 400.0), RIGHT).in_section("bridge").on_side(cp.LONE),
        lamp("light_port", "port", (1.0, 0.05, 0.03), 300.0, 3.0).mounted((-88.3, -47.0, 400.0), (-1.0, 0.0, 0.0)).in_section("bridge")
        .on_side(cp.LONE),
        lamp("light_top", "top", (1.0, 1.0, 1.0), 300.0, 3.0).mounted((0.0, hy.TOWER_TOP, 425.0), UP).in_section("bridge"),
        lamp("light_keel", "beacon", RUNNING_RED, 450.0, 3.0).mounted((0.0, hy.FIN_BOTTOM, 444.0), DOWN).in_section("bridge"),
        lamp("light_stern", "beacon", RUNNING_RED, 450.0, 3.0).mounted((0.0, hy.BLOCK_Y[1], 958.0), UP).in_section("engines"),
        *(lamp(f"{f.name}" if f.centre else f"{f.name}_r", "flood", FLOOD_LAMP, f.range_m, 1.6, 6.0).mounted(f.lamp, tuple(f.direction()))
          .in_section(f.section).on_side(cp.CENTRE if f.centre else cp.RIGHT) for f in hy.FLOODS),
        # The white lamps on the bow's face (the stills light it there), shining out along the antenna array.
        lamp("flood_bow_r", "flood", FLOOD_LAMP, 120.0, 1.4, 6.0).mounted(hy.BOW_LAMP, FORE, UP).in_section("bow").on_side(cp.RIGHT),
    ]


def modules(look: str = DEFAULT_LOOK) -> list[cp.Module]:
    """Every module in its place and section (centre modules and the starboard one of each pair)."""
    s = ea_hyperion(look).style
    return [
        *hy.fore_hull(s), *hy.deck(s), *hy.keel(s), *hy.sponson(s), *hy.tower(s),
        *hy.truss(s), *hy.module(s), *hy.aft_spine(s), *hy.tanks(s), *hy.engines(s),
        *weapon_modules(s), *light_modules(), *hy.flood_brackets(s),
    ]  # fmt: skip


def spec(look: str = DEFAULT_LOOK) -> cap.CapitalSpec:
    return cap.CapitalSpec(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        ship_class=SHIP_CLASS,
        modules=tuple(modules(look)),
        sections=SECTIONS,
        style=ea_hyperion(look),
        bridge=cap.Pose((0.0, 96.0, 385.0)),
        pieces=PIECES,
        jump_point=cap.JumpPoint(ahead_m=1000.0, mouth_radius_m=300.0),
        notes=("the renegades' red X marks (M10-T02) are `mark` hardpoints with `only_faction`: the game draws them on a renegade ship",
               "the floods' pools of light are baked into the hull's maps; the Earth Alliance emblem on the tower's flanks is a picture mark the "
               "game draws as a sharp decal, lit as the pools are (M10-T22)"),
        markings=tuple(hy.flood_pools()),
    )


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the Hyperion into ``ctx.out_dir``."""
    return cap.build(spec(str(ctx.option("look", DEFAULT_LOOK))), ctx)


__all__ = ["ASSET_ID", "GENERATOR_VERSION", "LENGTH_M", "PIECES", "SECTIONS", "SHIP_CLASS", "build", "modules", "spec"]
