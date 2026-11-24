"""The seam and plating defaults (M10 Q69, T73): the Hyperion's subtle seams and patches are what a new style and skin wear, and
every hull built before Q69 pins its own finish until T74, so its build is unchanged."""

from __future__ import annotations

import dataclasses
import unittest

import numpy as np

from tools.procgen.assets import asteroids, capital_hulls, jumpgate, skylark_transport
from tools.procgen.assets import ea_nova as en
from tools.procgen.core import detail_layer
from tools.procgen.core import geometry as g
from tools.procgen.core.civilian import LINE_TEXELS, at_texel
from tools.procgen.core.seams import Cut, PatchPlates, Plates, SeamLayout
from tools.procgen.core.textured_mesh import TexturedPart, atlas_of
from tools.procgen.core.textures import bake_maps, worn_seams
from tools.procgen.styles import LEGACY_LINE_DARKNESS, LEGACY_SEAMS, SEAM_DEPTH_SHARE, SEAM_LINE_DARKNESS, SEAM_WIDTH_SHARE, Style
from tools.procgen.styles.brakiri import BRAKIRI, BRAKIRI_POD
from tools.procgen.styles.capital import FRAMEWORK_GREY, LEGACY_SKIN, PATCH_DARKEST, PATCH_SHARE, TILE_SOFT, CapitalStyle, HexGrid, PanelMosaic, pinned
from tools.procgen.styles.cargo_pod_craft import CARGO_POD_CRAFT
from tools.procgen.styles.centauri import CENTAURI
from tools.procgen.styles.cobra_bay import COBRA_BAY
from tools.procgen.styles.ea_capital import FLEET_LINE_DARKNESS, ea_capital
from tools.procgen.styles.ea_civilian import EA_CIVILIAN, ea_civilian
from tools.procgen.styles.ea_hyperion import ea_hyperion
from tools.procgen.styles.ea_shuttle import ATMO_LOOK, SHUTTLE_LOOK
from tools.procgen.styles.ea_thunderbolt import THUNDERBOLT
from tools.procgen.styles.ea_work_ships import PANAMA_LOOK, TENDER_LOOK
from tools.procgen.styles.earth_alliance_station import EARTH_ALLIANCE_STATION
from tools.procgen.styles.earthforce import EARTHFORCE, EARTHFORCE_FIGHTER
from tools.procgen.styles.maintenance_bot import MAINTENANCE_BOT
from tools.procgen.styles.narn import NARN
from tools.procgen.styles.organic import MINBARI, hex_style, organic
from tools.procgen.styles.raider import RAIDER
from tools.procgen.styles.raider_capital import SURFACE

GREY = EA_CIVILIAN.material("hull")


def _new_style() -> Style:
    """A style that names only its paint, as a new hull's would start."""
    return Style("new_hull", dict(EA_CIVILIAN.materials))


# Every style a hull built before Q69 is baked with: its seams stay as they were until T74 lifts the pin.
PINNED_STYLES: dict[str, Style] = {
    "brakiri_bokmai": BRAKIRI, "brakiri_bokmai pods": BRAKIRI_POD, "cargo_pod_craft": CARGO_POD_CRAFT, "centauri_brezebel": CENTAURI,
    "b5_interior": COBRA_BAY, "saturn family": EA_CIVILIAN, "ea_civilian()": ea_civilian(), "skylark_transport": skylark_transport.STYLE,
    "ea_shuttle": SHUTTLE_LOOK.style, "ea_atmo_shuttle": ATMO_LOOK.style, "ea_panama": PANAMA_LOOK.style, "ea_construction_tender": TENDER_LOOK.style,
    "ea_thunderbolt": THUNDERBOLT, "babylon5_station and the grid guns": EARTH_ALLIANCE_STATION, "starfury_aurora": EARTHFORCE_FIGHTER,
    "nav_buoy": EARTHFORCE, "maintenance_bot": MAINTENANCE_BOT, "narn_transport": NARN, "raider_fighter": RAIDER,
    "raider_strike_carrier": SURFACE.style, "jumpgate": jumpgate.JUMPGATE, "capital_hulls": capital_hulls._style(1.0),
    "asteroids": asteroids.rock_style((GREY, GREY, GREY)),
}
# The capital styles pinned with their skins (the fleet finish, the Hyperion's option looks, the framework's test hull, the organic test hull).
PINNED_CAPITALS: dict[str, CapitalStyle] = {
    "ea_omega (fleet finish)": ea_capital(), "ea_hyperion look b": ea_hyperion("b"), "ea_hyperion look c": ea_hyperion("c"),
    "capital_test_cruiser": FRAMEWORK_GREY, "organic_test_hull minbari": pinned(organic("minbari")), "organic_test_hull vorlon": pinned(organic("vorlon")),
}


class DefaultsTests(unittest.TestCase):
    def test_the_defaults_are_the_hyperions(self) -> None:
        """Q69: commit 5e083eb9's values: grooves 0.22 as deep, lines 0.6 as wide, lines 0.89 dark, the near tile half as deep and dark,
        a fifth of the plates painted up to half as dark."""
        self.assertEqual((SEAM_DEPTH_SHARE, SEAM_WIDTH_SHARE, SEAM_LINE_DARKNESS), (0.22, 0.6, 0.89))
        self.assertEqual((TILE_SOFT, PATCH_SHARE, PATCH_DARKEST), (0.5, 0.2, 0.5))
        hyperion = ea_hyperion()
        self.assertEqual((hyperion.style.seam_depth, hyperion.style.seam_width, hyperion.style.panel_line_darkness),
                         (SEAM_DEPTH_SHARE, SEAM_WIDTH_SHARE, SEAM_LINE_DARKNESS))
        skin, fresh = hyperion.skin, PanelMosaic()
        for name in ("tile_width", "tile_soft", "patches", "darkest", "patch_tiers"):
            self.assertEqual(getattr(skin, name), getattr(fresh, name), f"the Hyperion's skin is the default's in {name}")

    def test_a_new_style_and_skin_take_them(self) -> None:
        style, cap = _new_style(), CapitalStyle("new_capital", _new_style())
        self.assertEqual((style.seam_depth, style.seam_width, style.panel_line_darkness), (SEAM_DEPTH_SHARE, SEAM_WIDTH_SHARE, SEAM_LINE_DARKNESS))
        self.assertEqual((cap.skin.tile_width, cap.skin.tile_soft, cap.skin.patches), (SEAM_WIDTH_SHARE, TILE_SOFT, PATCH_SHARE))
        for hull in (hex_style(MINBARI), ea_capital(finish="soft"), en.style()):
            self.assertEqual((hull.style.seam_depth, hull.style.seam_width), (SEAM_DEPTH_SHARE, SEAM_WIDTH_SHARE), hull.name)
            self.assertEqual((hull.skin.tile_width, hull.skin.tile_soft), (SEAM_WIDTH_SHARE, TILE_SOFT), hull.name)
        self.assertEqual(ea_capital(finish="soft").style.panel_line_darkness, SEAM_LINE_DARKNESS)

    def test_a_new_skin_paints_patches_and_softens_its_tile(self) -> None:
        layout = PanelMosaic().hull_layout((-10.0, -10.0, 0.0), (10.0, 10.0, 100.0), 1)
        patches = [f for f in layout.features() if isinstance(f, PatchPlates)]
        self.assertEqual(len(patches), 1)
        self.assertEqual((patches[0].scatter, patches[0].darkest, patches[0].depth), (PATCH_SHARE, PATCH_DARKEST, 0.0), "flush, paint only")
        full, soft = detail_layer.detail_tile(64, detail_layer.DEFAULT_TILE_M, 3), PanelMosaic().detail_tile(64, 3)
        self.assertGreater(float(soft["albedo"][..., :3].mean()), float(full["albedo"][..., :3].mean()), "lighter seams")
        self.assertLess(float(np.abs(soft["normal"][..., :2].astype(float) - 128.0).mean()),
                        float(np.abs(full["normal"][..., :2].astype(float) - 128.0).mean()), "shallower grooves")
        hexes, hex_full = HexGrid().detail_tile(64, 3), dataclasses.replace(HexGrid(), tile_width=1.0, tile_soft=1.0).detail_tile(64, 3)
        self.assertGreater(float(hexes["albedo"][..., :3].mean()), float(hex_full["albedo"][..., :3].mean()), "the hex tile too")

    def test_the_bake_wears_the_seams_at_the_styles_shares(self) -> None:
        layout = SeamLayout.of([Cut(axis=2, at=0.0, width=0.8), Plates(level=3, depth=0.0, dark=0.0), Cut(axis=0, at=1.0, depth=-1.0)])
        part = [TexturedPart(g.box((4.0, 4.0, 4.0), GREY), (0, 0, 0), name="hull", seams=layout)]
        style = _new_style()
        atlas = atlas_of(part, atlas_px=128, texel_m=0.08, style=style, grid=False)
        worn, worn_atlas = worn_seams(style, atlas)
        groove, paint, rib = worn_atlas.part_seams[0].features()
        self.assertAlmostEqual(groove.depth, SEAM_DEPTH_SHARE)
        self.assertAlmostEqual(groove.width, 0.8 * SEAM_WIDTH_SHARE)
        self.assertEqual((paint.depth, rib.depth, rib.width), (0.0, -1.0, 1.0), "paint and ribs are not grooves")
        self.assertAlmostEqual(worn.groove_depth_m, style.groove_depth_m * SEAM_DEPTH_SHARE)
        self.assertAlmostEqual(worn.panel_line_width_m, style.panel_line_width_m * SEAM_WIDTH_SHARE)
        self.assertEqual((worn.seam_depth, worn.seam_width), (1.0, 1.0), "worn once, not again downstream")
        soft = bake_maps(atlas, style, 1, occlusion=False, normal_scale=1)
        full = bake_maps(atlas, dataclasses.replace(style, **LEGACY_SEAMS), 1, occlusion=False, normal_scale=1)
        flat = np.array([128, 128, 255])
        self.assertLess(float(np.abs(soft["normal"].astype(int) - flat)[..., :2].mean()), float(np.abs(full["normal"].astype(int) - flat)[..., :2].mean()))

    def test_a_softened_line_keeps_its_least_width(self) -> None:
        texel = 0.2
        worn, _ = worn_seams(at_texel(_new_style(), texel), atlas_of([TexturedPart(g.box((1.0, 1.0, 1.0), GREY), (0, 0, 0), name="hull")],
                                                                    atlas_px=64, texel_m=texel, style=_new_style()))
        self.assertGreaterEqual(worn.panel_line_width_m, LINE_TEXELS * texel - 1e-12)


class PinTests(unittest.TestCase):
    def test_every_hull_built_before_q69_keeps_its_seams(self) -> None:
        for name, style in PINNED_STYLES.items():
            self.assertEqual((style.seam_depth, style.seam_width), (1.0, 1.0), name)
        self.assertEqual(PINNED_STYLES["asteroids"].panel_line_darkness, LEGACY_LINE_DARKNESS, "it relied on the old default")
        for name, cap in PINNED_CAPITALS.items():
            self.assertEqual((cap.style.seam_depth, cap.style.seam_width), (1.0, 1.0), name)
            for key, value in LEGACY_SKIN.items():
                if hasattr(cap.skin, key):
                    self.assertEqual(getattr(cap.skin, key), value, f"{name}: {key}")
        for name in ("ea_omega (fleet finish)", "ea_hyperion look b", "ea_hyperion look c"):
            self.assertEqual(PINNED_CAPITALS[name].style.panel_line_darkness, FLEET_LINE_DARKNESS, name)

    def test_a_pinned_style_bakes_exactly_as_before(self) -> None:
        """At full shares the bake gets the very style and atlas it was given, so the pinned hulls' maps cannot change."""
        atlas = atlas_of([TexturedPart(g.box((1.0, 1.0, 1.0), GREY), (0, 0, 0), name="hull", seams=SeamLayout.of([Cut(axis=2, at=0.0)]))],
                         atlas_px=64, texel_m=0.05, style=EA_CIVILIAN, grid=False)
        style, same = worn_seams(EA_CIVILIAN, atlas)
        self.assertIs(style, EA_CIVILIAN)
        self.assertIs(same, atlas)
        layout = SeamLayout.of([Cut()])
        self.assertIs(layout.softened(1.0, 1.0), layout)

    def test_the_hyperions_finish_moved_without_a_change(self) -> None:
        """The softening the Hyperion's skin did itself before T73, now done by the bake: the same features."""
        skin, style = ea_hyperion().skin, ea_hyperion().style
        drawn = skin.hull_layout((-10.0, -10.0, 0.0), (10.0, 10.0, 200.0), 7).softened(style.seam_depth, style.seam_width).features()
        full = dataclasses.replace(skin, patches=0.0).hull_layout((-10.0, -10.0, 0.0), (10.0, 10.0, 200.0), 7).features()
        before = [dataclasses.replace(f, depth=f.depth * 0.22, width=f.width * 0.6) if f.depth > 0.0 else f for f in full]
        self.assertEqual(drawn[:-1], before)
        self.assertIsInstance(drawn[-1], PatchPlates)


if __name__ == "__main__":
    unittest.main()
