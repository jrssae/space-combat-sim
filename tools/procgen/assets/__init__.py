"""Asset registry: one entry per buildable asset id.

To add an asset, create ``assets/<asset_id>.py`` exposing ``build(ctx: BuildContext) ->
AssetOutputs`` and register it below (see tools/procgen/README.md).
"""

from __future__ import annotations

from collections.abc import Callable

from ..core.context import AssetOutputs, BuildContext
from . import asteroids, b5_interior, babylon5_station, brakiri_bokmai, capital_hulls, capital_test_cruiser, cargo_pod_craft
from . import centauri_brezebel, centauri_shuttle
from . import ea_hyperion, ea_nova, ea_omega, ea_shuttles, ea_thunderbolt, ea_work_ships
from . import grid_heavy_cannon
from . import grid_interceptor_battery, jumpgate, planet, saturn_family, skylark_transport
from . import maintenance_bot, minbari_flyer, narn_transport, nav_buoy, organic_test_hull, raider_fighter, raider_strike_carrier
from . import sfx_combat, sfx_ui, sfx_world, sky_default
from . import starfury_aurora

ASSETS: dict[str, Callable[[BuildContext], AssetOutputs]] = {
    "asteroids": asteroids.build,
    "b5_interior": b5_interior.build,
    "babylon5_station": babylon5_station.build,
    "brakiri_bokmai": brakiri_bokmai.build,
    "capital_hulls": capital_hulls.build,
    "capital_test_cruiser": capital_test_cruiser.build,
    "cargo_pod_craft": cargo_pod_craft.build,
    "centauri_brezebel": centauri_brezebel.build,
    "centauri_shuttle": centauri_shuttle.build,
    "ea_atmo_shuttle": ea_shuttles.build_atmo,
    "ea_construction_tender": ea_work_ships.build_tender,
    "ea_hyperion": ea_hyperion.build,
    "ea_nova": ea_nova.build,
    "ea_omega": ea_omega.build,
    "ea_panama": ea_work_ships.build_panama,
    "ea_shuttle": ea_shuttles.build_shuttle,
    "ea_thunderbolt": ea_thunderbolt.build,
    "grid_heavy_cannon": grid_heavy_cannon.build,
    "grid_interceptor_battery": grid_interceptor_battery.build,
    "jumpgate": jumpgate.build,
    "maintenance_bot": maintenance_bot.build,
    "minbari_flyer": minbari_flyer.build,
    "narn_transport": narn_transport.build,
    "nav_buoy": nav_buoy.build,
    "organic_test_hull": organic_test_hull.build,
    "raider_fighter": raider_fighter.build,
    "raider_strike_carrier": raider_strike_carrier.build,
    "sfx_combat": sfx_combat.build,
    "sfx_ui": sfx_ui.build,
    "sfx_world": sfx_world.build,
    "sky_default": sky_default.build,
    "skylark_transport": skylark_transport.build,
    "starfury_aurora": starfury_aurora.build,
    **saturn_family.BUILDERS,
    **planet.BUILDERS,
}

# Assets whose bake needs the machine's memory to itself (M7-T04: the station's two 4 096 px atlases peak near 9 GB): with --jobs
# they are built after the pool, one at a time, so a 16 GB machine never holds them beside other bakes.
BUILD_ALONE: frozenset[str] = frozenset({"babylon5_station", "ea_hyperion", "ea_nova", "ea_omega", "organic_test_hull"})

# Each heavy asset's measured peak memory in MB (M10-T21: one build alone, /usr/bin/time, 4 096 px atlases), so ``--jobs`` only
# starts builds that fit the memory left: CI's 16 GB runner was killed running two 6 GB bakes beside each other.
PEAK_MB: dict[str, int] = {
    "babylon5_station": 7300, "ea_hyperion": 7200, "ea_nova": 6600, "ea_omega": 6200, "ea_panama": 6500,
    "raider_strike_carrier": 6300, "organic_test_hull": 4100, "epsilon_iii": 2300, "gamma_leporis_ii": 2300,
    "ea_thunderbolt": 2200, "b5_interior": 1900, "starfury_aurora": 1900, "ea_shuttle": 1900, "capital_test_cruiser": 1800,
    "skylark_transport": 1800, "ea_construction_tender": 1700, "saturn_4_tanker": 1700, "saturn_8_tanker": 1700,
    "saturn_4_transport": 1700, "saturn_8_transport": 1700, "grid_heavy_cannon": 1700, "raider_fighter": 1700,
    "capital_hulls": 1600, "narn_transport": 1600, "saturn_3_freighter": 1600, "grid_interceptor_battery": 1500,
    "centauri_brezebel": 1400, "jumpgate": 1300, "ea_atmo_shuttle": 1300, "brakiri_bokmai": 1300,
}
DEFAULT_PEAK_MB = 1300  # an asset not measured yet: about the lighter textured hulls
