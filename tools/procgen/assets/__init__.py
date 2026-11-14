"""Asset registry: one entry per buildable asset id.

To add an asset, create ``assets/<asset_id>.py`` exposing ``build(ctx: BuildContext) ->
AssetOutputs`` and register it below (see tools/procgen/README.md).
"""

from __future__ import annotations

from collections.abc import Callable

from ..core.context import AssetOutputs, BuildContext
from . import asteroids, b5_interior, babylon5_station, brakiri_bokmai, capital_hulls, centauri_brezebel
from . import jumpgate, planet, saturn_family, skylark_transport
from . import maintenance_bot, narn_transport, nav_buoy, raider_fighter, sfx_combat, sfx_ui, sfx_world, sky_default, starfury_aurora

ASSETS: dict[str, Callable[[BuildContext], AssetOutputs]] = {
    "asteroids": asteroids.build,
    "b5_interior": b5_interior.build,
    "babylon5_station": babylon5_station.build,
    "brakiri_bokmai": brakiri_bokmai.build,
    "capital_hulls": capital_hulls.build,
    "centauri_brezebel": centauri_brezebel.build,
    "jumpgate": jumpgate.build,
    "maintenance_bot": maintenance_bot.build,
    "narn_transport": narn_transport.build,
    "nav_buoy": nav_buoy.build,
    "raider_fighter": raider_fighter.build,
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
BUILD_ALONE: frozenset[str] = frozenset({"babylon5_station"})
