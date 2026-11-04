"""Asset registry: one entry per buildable asset id.

To add an asset, create ``assets/<asset_id>.py`` exposing ``build(ctx: BuildContext) ->
AssetOutputs`` and register it below (see tools/procgen/README.md).
"""

from __future__ import annotations

from collections.abc import Callable

from ..core.context import AssetOutputs, BuildContext
from . import b5_station, capital_hulls, nav_buoy, raider_fighter, sfx_combat, sky_default, starfury_aurora

ASSETS: dict[str, Callable[[BuildContext], AssetOutputs]] = {
    "b5_station": b5_station.build,
    "capital_hulls": capital_hulls.build,
    "nav_buoy": nav_buoy.build,
    "raider_fighter": raider_fighter.build,
    "sfx_combat": sfx_combat.build,
    "sky_default": sky_default.build,
    "starfury_aurora": starfury_aurora.build,
}
