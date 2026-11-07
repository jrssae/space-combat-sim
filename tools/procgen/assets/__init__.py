"""Asset registry: one entry per buildable asset id.

To add an asset, create ``assets/<asset_id>.py`` exposing ``build(ctx: BuildContext) ->
AssetOutputs`` and register it below (see tools/procgen/README.md).
"""

from __future__ import annotations

from collections.abc import Callable

from ..core.context import AssetOutputs, BuildContext
# The civilian generators (brakiri_bokmai, centauri_brezebel, narn_transport, saturn_family, skylark_transport) wait for
# M5-T27: they still write splats, which main dropped (M4-T31), and join the registry again on the textured-mesh pipeline.
from . import b5_station, capital_hulls
from . import nav_buoy, raider_fighter, sfx_combat, sfx_ui, sfx_world, sky_default, starfury_aurora

ASSETS: dict[str, Callable[[BuildContext], AssetOutputs]] = {
    "b5_station": b5_station.build,
    "capital_hulls": capital_hulls.build,
    "nav_buoy": nav_buoy.build,
    "raider_fighter": raider_fighter.build,
    "sfx_combat": sfx_combat.build,
    "sfx_ui": sfx_ui.build,
    "sfx_world": sfx_world.build,
    "sky_default": sky_default.build,
    "starfury_aurora": starfury_aurora.build,
}
