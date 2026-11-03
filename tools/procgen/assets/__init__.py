"""Asset registry: one entry per buildable asset id.

To add an asset, create ``assets/<asset_id>.py`` exposing ``build(ctx: BuildContext) ->
AssetOutputs`` and register it below (see tools/procgen/README.md).
"""

from __future__ import annotations

from collections.abc import Callable

from ..core.context import AssetOutputs, BuildContext
from . import narn_transport
from . import nav_buoy, raider_fighter, sfx_combat, sfx_ui, sfx_world, sky_default, starfury_aurora

ASSETS: dict[str, Callable[[BuildContext], AssetOutputs]] = {
    "narn_transport": narn_transport.build,
    "nav_buoy": nav_buoy.build,
    "raider_fighter": raider_fighter.build,
    "sfx_combat": sfx_combat.build,
    "sfx_ui": sfx_ui.build,
    "sfx_world": sfx_world.build,
    "sky_default": sky_default.build,
    "starfury_aurora": starfury_aurora.build,
}
