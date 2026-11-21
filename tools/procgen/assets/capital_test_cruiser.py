"""``capital_test_cruiser``: the capital framework's test hull (M10-T05), the stand-ins' cruiser class (``capital_hulls``:
300 m long, about 60 by 40 m) rebuilt on the framework, so M10-T07 has a capital hull before the first real one.

Not a ship of the show: one of every part of the capital library (``parts/capital*.py``) on a plain grey hull
(``styles/capital.FRAMEWORK_GREY``), with every section kind, every hardpoint kind and a rotating section, written by
``core/capital.py`` (docs/assets-capital.md, "Capital framework").

Layout (authored frame, metres; -z forward, the bow's tip at z = 0, the hull's axis on y = 0): a prow and the bow hull with a
gun turret, two beam emitters and two launch tubes on its flanks; the bridge tower on its deck; the launch bay slung under
the magazine hull, which carries the missile battery; a narrow spine through the rotating habitat section; the fuel and
reactor hulls with their turrets, interceptors and the mine layer; an engine nacelle on each quarter.

Options: ``spacing``, ``atlas_px`` and ``detail_px`` (``core/capital.build``).
"""

from __future__ import annotations

import numpy as np

from ..core import capital as cap
from ..core.context import AssetOutputs, BuildContext
from ..parts import capital as cp
from ..parts import capital_bays as bays
from ..parts import capital_engines as engines
from ..parts import capital_fittings as fittings
from ..parts import capital_hull as hull
from ..parts import capital_weapons as weapons
from ..styles.capital import FRAMEWORK_GREY

ASSET_ID = "capital_test_cruiser"
GENERATOR_VERSION = 2  # 2: the low texture set a mip level down, the manifest's notes (stage 2)
SHIP_CLASS = "cruiser"
LENGTH_M = 300.0
STYLE = FRAMEWORK_GREY

# The hull's cross-sections: half width, half height, corner cut.
BODY = (22.0, 11.0, 4.0)
DECK_Y, KEEL_Y, FLANK_X = 11.0, -11.0, 22.0
ROTOR_PIVOT = (0.0, 0.0, 162.5)
ROTOR_SPIN_RAD_S = 0.35  # about 0.2 g at the blocks' 16 m
# The explosive sections' blasts, J: placeholders of the right order until M10-T03 sets them (Q18).
BLAST_J = {"reactor": 4.0e14, "magazine": 1.5e14, "fuel": 8.0e13}
NOTES = ("sections[].blast_energy_j: placeholders until M10-T03 sets the blast sizes (Q18)",)

SECTIONS = (
    cap.Section("bow", "structure", 0.12),
    cap.Section("bridge", "bridge", 0.06),
    cap.Section("hangar", "hangar", 0.08),
    cap.Section("magazine", "magazine", 0.14, BLAST_J["magazine"]),
    cap.Section("spine", "structure", 0.08),
    cap.Section("habitat", "habitat", 0.08, piece="rotor"),
    cap.Section("fuel", "fuel", 0.12, BLAST_J["fuel"]),
    cap.Section("reactor", "reactor", 0.16, BLAST_J["reactor"]),
    cap.Section("engine_r", "engine", 0.08),  # and its port twin, engine_l
)
PIECES = (cap.PieceSpec(cap.HULL_PIECE, 2048), cap.PieceSpec("rotor", 1024, ROTOR_PIVOT, (0.0, 0.0, 1.0), ROTOR_SPIN_RAD_S))


def _station(z: float, scale: float = 1.0, y: float = 0.0) -> hull.Station:
    return hull.Station(z, BODY[0] * scale, BODY[1] * scale, BODY[2] * scale, y)


def modules() -> list[cp.Module]:
    """Every module in its place and section (centre modules and the starboard one of each pair)."""
    s = STYLE.style
    up, down, right = (0.0, 1.0, 0.0), (0.0, -1.0, 0.0), (1.0, 0.0, 0.0)
    out: list[cp.Module] = []

    def add(section: str, m: cp.Module, side: str = cp.CENTRE) -> None:
        out.append(m.in_section(section).on_side(side))

    # The hull, bow to stern. A section that ends inside its neighbour is left open there.
    bow_base = hull.Station(45.0, 20.0, BODY[1], BODY[2])
    add("bow", hull.prow("prow", bow_base, 45.0, s, nose=(0.3, 0.45), drop=2.0))
    add("bow", hull.hull_section("bow_hull", (bow_base, _station(95.0)), s, caps=(False, False)))
    add("magazine", hull.hull_section("magazine_hull", (_station(95.0), _station(140.0)), s, caps=(False, True)))
    add("spine", hull.hull_section("spine_hull", (hull.Station(138.0, 7.0, 7.0, 2.0), hull.Station(187.0, 7.0, 7.0, 2.0)), s, caps=(False, False)))
    add("fuel", hull.hull_section("fuel_hull", (_station(185.0), _station(225.0)), s, caps=(True, False)))
    add("reactor", hull.hull_section("reactor_hull", (_station(225.0), _station(250.0), _station(272.0, 0.8)), s, caps=(False, True)))
    add("bridge", hull.hull_section("bridge_tower", (hull.Station(70.0, 6.0, 2.5, 1.2, 13.5), hull.Station(92.0, 7.0, 3.0, 1.2, 13.5)), s))
    add("bow", hull.armour_plates("bow_armour", (24.0, 30.0), (3, 4), 0.5, s).mounted((0.0, DECK_Y, 40.0 + 15.0), up))

    # Weapons: one of every kind.
    add("bow", weapons.turret_mount("turret_fore", 5.0, s).mounted((0.0, DECK_Y + 0.5, 50.0), up))
    add("magazine", weapons.turret_mount("turret_mid_r", 5.0, s).mounted((10.0, DECK_Y, 112.0), up), cp.RIGHT)
    add("fuel", weapons.turret_mount("turret_fuel_r", 5.0, s).mounted((10.0, DECK_Y, 205.0), up), cp.RIGHT)
    add("reactor", weapons.turret_mount("turret_aft", 5.0, s).mounted((0.0, DECK_Y, 240.0), up, (0.0, 0.0, 1.0)))
    add("bow", weapons.beam_emitter("beam_r", 14.0, s).mounted((21.0, 0.0, 78.0), right), cp.RIGHT)
    add("magazine", weapons.interceptor_dome("interceptor_fore", 1.8, s).mounted((0.0, DECK_Y, 100.0), up))
    add("reactor", weapons.interceptor_dome("interceptor_aft", 1.8, s).mounted((0.0, DECK_Y, 228.0), up))
    add("fuel", weapons.interceptor_dome("interceptor_keel", 1.8, s).mounted((0.0, KEEL_Y, 205.0), down))
    add("magazine", weapons.missile_launcher("missiles", (4, 3), 1.6, s).mounted((0.0, DECK_Y, 128.0), up))
    add("reactor", weapons.mine_layer("mines", (4.0, 2.5), 6.0, s).mounted((0.0, KEEL_Y * 0.8, 266.0), down))

    # Launches: a bay for fighters under the magazine, its hall below the keel, and a tube on each bow flank.
    bay = bays.launch_bay("bay", (14.0, 9.0), 30.0, s)
    add("hangar", bay.translated((0.0, KEEL_Y - 6.1, 100.0)))
    add("bow", bays.launch_tube("tube_r", 1.5, 12.0, s).translated((21.6, -5.0, 60.0)), cp.RIGHT)

    # The rotating section round the spine, and the engines on the quarters, their bells' mouths at the stern.
    rotor = fittings.rotating_section("habitat_ring", (9.5, 12.0, 22.0), (4.0, 13.5), (8.0, 5.0, 20.0), s)
    add("habitat", rotor.translated(ROTOR_PIVOT))
    nacelle = engines.engine_block("engine_r", (10.0, 14.0, 28.0), (1, 2), s, share=0.5)
    add("engine_r", nacelle.translated((25.0, 0.0, LENGTH_M - float(nacelle.part.mesh.bounds()[1][2]))), cp.RIGHT)

    # Fittings: an antenna on the tower and the running lights.
    add("bridge", fittings.antenna("antenna", 5.0, s, dish_m=2.0).mounted((0.0, 16.5, 76.0), up))
    add("bridge", fittings.lamp("light_top", "top", (1.0, 1.0, 1.0), 90.0).mounted((0.0, 16.5, 88.0), up))
    add("magazine", fittings.lamp("light_starboard", "starboard", (0.05, 1.0, 0.1), 90.0).mounted((FLANK_X, 0.0, 120.0), right))
    add("magazine", fittings.lamp("light_port", "port", (1.0, 0.05, 0.03), 90.0).mounted((-FLANK_X, 0.0, 120.0), (-1.0, 0.0, 0.0)))
    add("reactor", fittings.lamp("light_beacon", "beacon", (1.0, 1.0, 1.0), 150.0).mounted((0.0, DECK_Y * 0.8, 270.0), up))
    return out


def spec() -> cap.CapitalSpec:
    return cap.CapitalSpec(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        ship_class=SHIP_CLASS,
        modules=tuple(modules()),
        sections=SECTIONS,
        style=STYLE,
        bridge=cap.Pose((0.0, 14.0, 69.5)),
        pieces=PIECES,
        jump_point=cap.JumpPoint(ahead_m=500.0, mouth_radius_m=200.0),
        notes=NOTES,
    )


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the test hull into ``ctx.out_dir``."""
    return cap.build(spec(), ctx)


__all__ = ["ASSET_ID", "GENERATOR_VERSION", "LENGTH_M", "PIECES", "SECTIONS", "SHIP_CLASS", "build", "modules", "spec"]
