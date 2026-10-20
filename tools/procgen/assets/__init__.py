"""Asset registry: one entry per buildable asset id.

To add an asset, create ``assets/<asset_id>.py`` exposing ``build(ctx: BuildContext) ->
AssetOutputs`` and register it below (see tools/procgen/README.md).
"""

from __future__ import annotations

from collections.abc import Callable

from ..core.context import AssetOutputs, BuildContext
from . import nav_buoy, raider_fighter, sky_default, starfury_aurora

ASSETS: dict[str, Callable[[BuildContext], AssetOutputs]] = {
    "nav_buoy": nav_buoy.build,
    "raider_fighter": raider_fighter.build,
    "sky_default": sky_default.build,
    "starfury_aurora": starfury_aurora.build,
}
