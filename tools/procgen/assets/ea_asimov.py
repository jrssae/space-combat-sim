"""``ea_asimov``: the Earth Alliance Asimov-class liner (M10-T53, Q84) on the capital framework (``core/capital.py``). 600 m long,
a capital by its budget class; unarmed.

The structure is ``parts/ea_asimov.py`` (measured off the reference model); this file adds the lights and names the damage
sections. The loadout (``data/capitals/loadouts.json``, ``ea_asimov``) has no weapons, interceptors or bays. Four docking collars
stand on the rim's lower teeth (``docking_ports`` in its hardpoints, stage 2): a crew shuttle backs onto one and mates by its
stern hatch (``ShipDock`` in the game). The shuttle bay behind the hexagonal mouth is not built yet (docs/assets-capital.md).

Sections: the bridge (the saucer), the spine, the forward face, the habitat band (its own piece, turning slowly about the axis),
the aft cap with its window band, the reactor (the engine frame and the middle nacelles) and an engine pair each side.

Options: ``variant`` (only ``liner``; T56 adds the mining transport, whose sphere parts at the band's equator), and ``spacing``,
``atlas_px``, ``detail_px`` (``core/capital.build``).
"""

from __future__ import annotations

from ..core import capital as cap
from ..core import collision as col
from ..core.context import AssetOutputs, BuildContext
from ..parts import capital as cp
from ..parts import capital_fittings as fittings
from ..parts import ea_asimov as asi
from ..styles.ea_asimov import PATTERN, band_bars, ea_asimov

ASSET_ID = "ea_asimov"
GENERATOR_VERSION = 2
SHIP_CLASS = "capital"
LENGTH_M = asi.LENGTH_M
VARIANTS = ("liner",)
BAND_SPIN_RAD_S = 0.05  # a turn in about two minutes: slow, as the show's
ATLAS_PX = 4096

BLAST_J = {"reactor": 5.0e6 * 1500.0}
SECTIONS = (
    cap.Section("bridge", "bridge", 0.04),
    cap.Section("spine", "structure", 0.08),
    cap.Section("face", "structure", 0.14),
    cap.Section("habitat", "habitat", 0.40, piece="band"),
    cap.Section("sphere_aft", "structure", 0.14),
    cap.Section("reactor", "reactor", 0.08, BLAST_J["reactor"]),
    cap.Section("engine_r", "engine", 0.06),  # and its port twin, engine_l
)
PIECES = (cap.PieceSpec(cap.HULL_PIECE, ATLAS_PX), cap.PieceSpec("band", ATLAS_PX, asi.BAND_PIVOT, (0.0, 0.0, 1.0), BAND_SPIN_RAD_S))
COLLISION = col.Budget(max_shapes=96, max_excess_m=2.5)  # the bowl's sectored terraces, the collar's teeth and the shapes round the open mouth
UP, RIGHT = (0.0, 1.0, 0.0), (1.0, 0.0, 0.0)
RUNNING_RED = (1.0, 0.22, 0.05)


def light_modules() -> list[cp.Module]:
    """The running lights: red to port and green to starboard on the ring's flanks, white on the saucer's dome, a
    red-orange beacon at the keel of the face and on the engine frame's dorsal bar."""
    lamp = fittings.lamp
    side_z = PATTERN.ring_end_z - 3.0  # on the ring: the skin behind it turns
    side_x = asi.sphere_r(side_z) + 0.3
    return [
        lamp("light_starboard", "starboard", (0.05, 1.0, 0.1), 300.0, 3.0).mounted((side_x, 0.0, side_z), RIGHT).in_section("face").on_side(cp.LONE),
        lamp("light_port", "port", (1.0, 0.05, 0.03), 300.0, 3.0).mounted((-side_x, 0.0, side_z), (-1.0, 0.0, 0.0)).in_section("face").on_side(cp.LONE),
        lamp("light_top", "top", (1.0, 1.0, 1.0), 300.0, 2.0).mounted((0.0, asi.SAUCER_AT[1] + 34.5, asi.SAUCER_AT[2]), UP).in_section("bridge"),
        lamp("light_keel", "beacon", RUNNING_RED, 400.0, 3.0).mounted((0.0, -asi.sphere_r(side_z) - 0.3, side_z), (0.0, -1.0, 0.0)).in_section("face"),
        lamp("light_stern", "beacon", RUNNING_RED, 400.0, 3.0).mounted((0.0, 100.0, asi.BAR_Z[1] - 8.0), UP).in_section("reactor"),
    ]


def modules(variant: str = "liner") -> list[cp.Module]:
    """Every module in its place and section (centre modules and the starboard one of each pair)."""
    if variant not in VARIANTS:
        raise ValueError(f"ea_asimov has no variant {variant!r}; it has {list(VARIANTS)}")
    s = ea_asimov().style
    return [
        *asi.command(s), *asi.forward_face(s, PATTERN), *asi.docking_collars(s), asi.brackets(s, "brackets_fore", "habitat", (asi.FORE_SEAM_Z - 14.0, asi.FORE_SEAM_Z - 2.0), 15.0),
        *asi.band(s, PATTERN), *asi.aft_cap(s), asi.brackets(s, "brackets_aft", "sphere_aft", (asi.AFT_SEAM_Z + 2.0, asi.AFT_SEAM_Z + 14.0), 15.0),
        *asi.engine_frame(s), asi.engine(s, "engine_top_r", "engine_r", 1.0), asi.engine(s, "engine_low_r", "engine_r", -1.0),
        *light_modules(),
    ]  # fmt: skip


def spec(variant: str = "liner") -> cap.CapitalSpec:
    return cap.CapitalSpec(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        ship_class=SHIP_CLASS,
        modules=tuple(modules(variant)),
        sections=SECTIONS,
        style=ea_asimov(),
        bridge=cap.Pose((asi.SAUCER_AT[0], asi.SAUCER_AT[1] + 16.0, asi.SAUCER_AT[2])),
        pieces=PIECES,
        collision=COLLISION,
        piece_surface={"band": {"band_bars": band_bars()}},
        notes=("unarmed; no jump engine (it travels by the gates)",
               "four docking collars on the rim's lower teeth (docking_ports); the shuttle bay behind the hexagonal mouth is not built yet"),
    )


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the liner into ``ctx.out_dir``."""
    return cap.build(spec(str(ctx.option("variant", "liner"))), ctx)


__all__ = ["ASSET_ID", "BAND_SPIN_RAD_S", "GENERATOR_VERSION", "LENGTH_M", "PIECES", "SECTIONS", "SHIP_CLASS", "VARIANTS", "build", "modules", "spec"]
