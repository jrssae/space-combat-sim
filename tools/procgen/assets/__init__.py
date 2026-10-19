"""Asset registry: one entry per buildable asset id.

To add an asset, create ``assets/<asset_id>.py`` exposing ``build(ctx: BuildContext) ->
AssetOutputs`` and register it below (see tools/procgen/README.md).
"""

from __future__ import annotations

from collections.abc import Callable

from ..core.context import AssetOutputs, BuildContext
from . import sky_default

ASSETS: dict[str, Callable[[BuildContext], AssetOutputs]] = {
    "sky_default": sky_default.build,
}
