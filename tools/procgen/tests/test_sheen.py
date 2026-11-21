"""The sheen layer's parameters (M10-T06, D12.2): ``core/sheen.py`` and ``styles/organic.py``.

The spherical-harmonic fit draws the colours it is asked for; a sheen's numbers are checked, and reach the manifest under
exactly the names the shader's uniforms and the game's material have, so the three cannot drift apart.
"""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.core import sheen
from tools.procgen.styles import organic
from tools.procgen.styles.capital import HexGrid, Seamless

ROOT = Path(__file__).resolve().parents[3]
LAYER = ROOT / "assets" / "shaders" / "hull_sheen_layer.gdshaderinc"
SHADER = ROOT / "assets" / "shaders" / "hull_organic.gdshader"
MATERIAL = ROOT / "src" / "rendering" / "hull_sheen_material.gd"


class SphericalHarmonicTests(unittest.TestCase):
    def test_the_nine_functions_are_orthonormal_over_the_sphere(self) -> None:
        basis = sheen.sh_basis(sheen.sphere_directions(20_000))
        gram = basis.T @ basis * (4.0 * np.pi / len(basis))
        np.testing.assert_allclose(gram, np.eye(9), atol=2e-3)

    def test_an_ambient_colour_alone_is_the_same_every_way(self) -> None:
        coefficients = sheen.sh_from_lobes((0.2, 0.4, 0.6), [])
        colours = sheen.sh_colour(coefficients, sheen.sphere_directions(500))
        np.testing.assert_allclose(colours, np.tile([0.2, 0.4, 0.6], (500, 1)), atol=1e-4)
        self.assertEqual(len(coefficients), sheen.SH_COUNT)

    def test_a_lobe_colours_its_own_side(self) -> None:
        coefficients = sheen.sh_from_lobes((0.1, 0.1, 0.1), [((0.0, 1.0, 0.0), (0.8, 0.0, 0.0), 100.0), ((0.0, -1.0, 0.0), (0.0, 0.0, 0.8), 100.0)])
        up, down, side = sheen.sh_colour(coefficients, np.array([[0.0, 1.0, 0.0], [0.0, -1.0, 0.0], [1.0, 0.0, 0.0]]))
        self.assertGreater(up[0], 0.5)
        self.assertGreater(down[2], 0.5)
        self.assertLess(up[2], 0.2)
        self.assertLess(side[0], 0.5 * up[0], "the colour fades away from its lobe")
        self.assertTrue(np.all(sheen.sh_colour(coefficients, sheen.sphere_directions(500)) >= 0.0), "never below black")


class SheenTests(unittest.TestCase):
    def test_a_sheen_checks_its_numbers(self) -> None:
        self.assertEqual(sheen.Sheen().iri_strength, 0.0, "everything is off until asked for")
        for wrong in ({"iri_strength": 1.5}, {"pattern_cover": -0.1}, {"pattern_scale_m": 0.0}, {"iri_sh": ((0.0, 0.0, 0.0),) * 8}, {"coat": 2.0},
                      {"variant_sh": ((0.0, 0.0, 0.0),) * 3}, {"variant_share": 1.2}, {"liquid": -1.0}):
            with self.assertRaises(ValueError, msg=str(wrong)):
                sheen.Sheen(**wrong)
        changed = sheen.Sheen(glow_energy=0.1).but(glow_energy=0.2, pattern_cells=1.0)
        self.assertEqual((changed.glow_energy, changed.pattern_cells), (0.2, 1.0))

    def test_the_manifest_entry_is_plain_json_under_the_uniforms_names(self) -> None:
        entry = organic.organic("vorlon").surface["sheen"]
        self.assertEqual(json.loads(json.dumps(entry)), entry)
        for key in sheen.SH_FIELDS:
            self.assertEqual(np.asarray(entry[key]).shape, (9, 3), key)
        declared = {name: kind for kind, name in re.findall(r"^uniform (\w+) (\w+)", LAYER.read_text(encoding="utf-8"), flags=re.MULTILINE)}
        self.assertEqual(set(entry) - set(sheen.GAME_ONLY), set(declared), "every number of a sheen is a uniform of the layer, and the other way round")
        for name in declared:
            self.assertEqual(declared[name], "float" if isinstance(entry[name], float) else "vec3", name)
        self.assertEqual(sheen.GAME_ONLY, ("variant_share",), "the share of ships in the second colouring is the game's to draw")

    def test_the_games_material_sets_every_number(self) -> None:
        source = MATERIAL.read_text(encoding="utf-8")
        lists = {name: re.findall(r'"(\w+)"', body)
                 for name, body in re.findall(r"const (SCALARS|COLOURS|HARMONICS): Array\[String\] = \[(.*?)\]", source, flags=re.DOTALL)}
        entry = sheen.Sheen().to_json()
        self.assertEqual(set(lists["SCALARS"]), {k for k, v in entry.items() if isinstance(v, float)} - set(sheen.GAME_ONLY))
        self.assertEqual(set(lists["COLOURS"]), {k for k, v in entry.items() if isinstance(v, list) and k not in sheen.SH_FIELDS})
        self.assertEqual(tuple(lists["HARMONICS"]), sheen.SH_FIELDS)
        self.assertIn('const VARIANT_SHARE: String = "variant_share"', source)
        shader = SHADER.read_text(encoding="utf-8")
        self.assertIn('#include "res://assets/shaders/hull_sheen_layer.gdshaderinc"', shader)
        self.assertIn("instance uniform float skin_variant", shader, "the second colouring is chosen per drawn ship")
        self.assertIn('const VARIANT_PARAMETER: StringName = &"skin_variant"', source)


class OrganicStyleTests(unittest.TestCase):
    def test_the_looks_and_the_second_colouring(self) -> None:
        self.assertEqual(organic.LOOKS, ("vorlon", "shadow", "minbari", "white_star", "victory"))
        plain, red = organic.organic("vorlon").surface["sheen"], organic.organic("vorlon", variant=True).surface["sheen"]
        self.assertEqual((plain["variant_all"], red["variant_all"]), (0.0, 1.0))
        self.assertEqual({k: v for k, v in plain.items() if k != "variant_all"}, {k: v for k, v in red.items() if k != "variant_all"},
                         "the same sheen, every ship in its second colouring")
        with self.assertRaises(ValueError):
            organic.organic("vorlon_red")
        with self.assertRaises(ValueError, msg="the Shadows have one colouring"):
            organic.organic("shadow", variant=True)

    def test_the_vorlons_and_the_shadows_are_seamless_and_the_hex_looks_are_plated(self) -> None:
        self.assertIsInstance(organic.organic("vorlon").skin, Seamless)  # Q46
        self.assertIsInstance(organic.organic("shadow").skin, Seamless)
        for look in organic.HEX_COLOURS:
            self.assertIsInstance(organic.organic(look).skin, HexGrid)  # Q45, Q47
            self.assertTrue(organic.organic(look).style.material("hull").paneled)
        self.assertFalse(organic.organic("vorlon").style.material("hull").paneled)

    def test_the_vorlons_are_mottled_alive_and_a_fifth_of_them_red(self) -> None:
        vorlon = organic.organic("vorlon")
        worn = vorlon.surface["sheen"]
        self.assertGreater(worn["glow_energy"], 0.0, "the Vorlons glow faintly (Q46)")
        self.assertLess(worn["glow_energy"], 0.2)
        skin = vorlon.style.material("hull").albedo
        self.assertTrue(skin[0] > skin[2] and skin[1] > skin[2], "yellow-green")
        petal = vorlon.style.material("hull_panel").albedo
        self.assertGreater(petal[2], 3.0 * petal[0], "deep blue petals")
        self.assertEqual(vorlon.style.edge_wear, 0.0, "living skin does not chip")
        # The maintainer's pick (2026-11-21): the bold mottling, alive as a cuttlefish's skin.
        self.assertGreater(worn["pattern_dark"], 0.8, "bold dark mottling")
        self.assertGreater(worn["pattern_pulse"], 0.5, "that swells and fades")
        self.assertGreater(worn["pattern_pulse_s"], 8.0, "slowly")
        self.assertGreater(worn["pattern_spots"], 0.5, "with spots between the blotches")
        self.assertGreater(worn["iri_wave"], 0.0, "and colours that wander")
        self.assertEqual(worn["variant_share"], 0.2, "a fifth of the hulls are red-based")
        luma = 0.2126 * skin[0] + 0.7152 * skin[1] + 0.0722 * skin[2]
        red = np.array(worn["variant_tint"]) * luma
        self.assertGreater(red[0], 2.0 * red[1], "red-based")
        self.assertGreater(red[1], red[2])
        self.assertLess(red[0], 0.25, "a copper-brown, not an orange (the show's heavy cruiser)")
        both = [sheen.sh_colour(worn[key], sheen.sphere_directions(200)).mean(axis=0) for key in ("iri_sh", "variant_sh")]
        self.assertGreater(both[0][1], both[0][0], "green-gold on the yellow-green hulls")
        self.assertGreater(both[1][0], both[1][1], "a red-gold sheen on the red ones")

    def test_the_shadows_are_black_with_ridged_seams_and_a_pool_of_liquid_in_every_cell(self) -> None:
        shadow = organic.organic("shadow")
        worn = shadow.surface["sheen"]
        self.assertLess(max(shadow.style.material("hull").albedo), 0.03, "the Shadows are black")
        self.assertEqual(worn["pattern_cells"], 1.0, "cells with seams between them")
        self.assertGreaterEqual(worn["pattern_scale_m"], 4.0, "big ones")
        self.assertGreater(worn["pattern_speed_mps"], 0.0, "that move")
        self.assertLessEqual(worn["pattern_speed_mps"], 0.2, "slowly")
        # The maintainer's correction (2026-11-21): the seams are the high points, the liquid is the cells' own surface.
        self.assertGreater(worn["pattern_relief"], 0.5, "the seams stand up as ridges")
        self.assertEqual(worn["liquid"], 1.0, "each cell a glossy wet surface")
        self.assertGreater(worn["liquid_dish"], 0.5, "drawn up at its edges, lower in its middle")
        self.assertGreater(worn["liquid_flow_mps"], 0.0, "that flows")
        self.assertEqual(worn["liquid_tint"], [0.0, 0.0, 0.0], "black")
        self.assertGreater(shadow.style.material("hull").roughness_value, 0.6, "the ridges are matt: the gloss is the liquid's")
        self.assertLess(max(worn["pattern_tint"]), min(shadow.style.material("hull").albedo), "and darker than the skin: no bright web up close")
        self.assertGreater(worn["pattern_dark"], 0.8)
        self.assertLessEqual(worn["iri_strength"], 0.1, "with only a trace of the sheen on them")
        self.assertGreater(worn["glow_energy"], 0.0, "a faint violet in the seams")
        self.assertLess(worn["glow_energy"], 0.02)
        self.assertEqual(worn["glow_veins"], 1.0)
        self.assertGreater(worn["glow_colour"][2], worn["glow_colour"][0])
        violet = sheen.sh_colour(worn["iri_sh"], sheen.sphere_directions(200)).mean(axis=0)
        self.assertGreater(violet[2], violet[0])
        self.assertGreater(violet[0], violet[1], "a purple sheen: blue over red over green")
        self.assertLessEqual(worn["iri_strength"], 0.3, "and only a hint of it")
        self.assertEqual(worn["variant_share"], 0.0)

    def test_a_hexagonal_hull_wears_its_own_colour_set(self) -> None:
        self.assertEqual(tuple(organic.HEX_COLOURS), ("minbari", "white_star", "victory"))
        for name, colours in organic.HEX_COLOURS.items():
            style = organic.organic(name)
            self.assertEqual(style.surface, organic.hex_style(colours).surface)
            worn = style.surface["sheen"]
            self.assertEqual(worn["iri_base"], 0.0, "a hint of sheen, at the rim only")
            self.assertLessEqual(worn["iri_strength"], 0.25)
            self.assertGreater(worn["pattern_dark"], 0.0, "soft mottling")
            self.assertEqual(worn["pattern_tint"], list(colours.mottle))
            self.assertEqual((worn["liquid"], worn["glow_energy"], worn["variant_share"]), (0.0, 0.0, 0.0))
            self.assertEqual(style.style.material("hull").albedo, colours.skin)
            with self.assertRaises(ValueError):
                organic.organic(name, variant=True)
        # A hull task hands its own set and its own hexagon size.
        own = organic.HexColours("drakh", (0.05, 0.08, 0.04), (0.04, 0.06, 0.03), (0.03, 0.05, 0.03), (0.01, 0.02, 0.01), (0.1, 0.3, 0.1),
                                 (0.0, 0.1, 0.0), (0.0, 0.0, 0.0))
        style = organic.hex_style(own, cell_m=8.0)
        self.assertEqual((style.skin.cell_m, style.style.material("hull").albedo, style.name), (8.0, (0.05, 0.08, 0.04), "organic_drakh"))

    def test_the_minbari_are_blue_the_white_star_silver_and_violet_the_victory_charcoal_and_red(self) -> None:
        minbari, white_star, victory = (organic.organic(name) for name in ("minbari", "white_star", "victory"))
        # The Minbari: blue everywhere: the paint, the mottling and every colour the sheen can show (no purple: red under green).
        skin, mottle = minbari.style.material("hull").albedo, minbari.surface["sheen"]["pattern_tint"]
        self.assertTrue(skin[2] > 2.0 * skin[1] > 2.0 * skin[0], "blue")
        self.assertTrue(mottle[2] > 3.0 * mottle[1] and mottle[1] > mottle[0] and mottle[2] < skin[2], "dark blue")
        colours = sheen.sh_colour(minbari.surface["sheen"]["iri_sh"], sheen.sphere_directions(400))
        self.assertTrue(np.all(colours[:, 2] > colours[:, 1]) and np.all(colours[:, 1] > colours[:, 0]), "blue over green over red, every way")
        # The White Star: a near-grey silver, its veins violet-blue.
        silver, veins = white_star.style.material("hull").albedo, white_star.surface["sheen"]["pattern_tint"]
        self.assertLess(max(silver) - min(silver), 0.08)
        self.assertGreater(min(silver), 0.3)
        self.assertGreater(white_star.style.material("hull").metallic, 0.6)
        self.assertTrue(veins[2] > 3.0 * veins[0] and veins[0] > veins[1], "violet-blue")
        # The Victory class: charcoal, its markings a dull red.
        charcoal, marks = victory.style.material("hull").albedo, victory.surface["sheen"]["pattern_tint"]
        self.assertLess(max(charcoal), 0.06)
        self.assertLess(max(charcoal) - min(charcoal), 0.015)
        self.assertTrue(marks[0] > marks[1] > marks[2] and marks[0] < 2.5 * marks[1] and marks[0] < 0.06, "a dull, muted red")
        self.assertLessEqual(victory.surface["sheen"]["pattern_dark"], 0.6, "and faint")


if __name__ == "__main__":
    unittest.main()
