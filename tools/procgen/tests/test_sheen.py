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
        self.assertEqual(organic.LOOKS, ("vorlon", "shadow", "hex"))
        plain, red = organic.organic("vorlon").surface["sheen"], organic.organic("vorlon", variant=True).surface["sheen"]
        self.assertEqual((plain["variant_all"], red["variant_all"]), (0.0, 1.0))
        self.assertEqual({k: v for k, v in plain.items() if k != "variant_all"}, {k: v for k, v in red.items() if k != "variant_all"},
                         "the same sheen, every ship in its second colouring")
        with self.assertRaises(ValueError):
            organic.organic("vorlon_red")
        with self.assertRaises(ValueError, msg="the Shadows have one colouring"):
            organic.organic("shadow", variant=True)

    def test_the_vorlons_and_the_shadows_are_seamless_and_the_hex_look_is_plated(self) -> None:
        self.assertIsInstance(organic.organic("vorlon").skin, Seamless)  # Q46
        self.assertIsInstance(organic.organic("shadow").skin, Seamless)
        self.assertIsInstance(organic.organic("hex").skin, HexGrid)  # Q45, Q47
        self.assertTrue(organic.organic("hex").style.material("hull").paneled)
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
        self.assertGreater(red[0], 3.0 * red[1], "red-based")
        self.assertGreater(red[1], red[2])
        both = [sheen.sh_colour(worn[key], sheen.sphere_directions(200)).mean(axis=0) for key in ("iri_sh", "variant_sh")]
        self.assertGreater(both[0][1], both[0][0], "green-gold on the yellow-green hulls")
        self.assertGreater(both[1][0], both[1][1], "a red-gold sheen on the red ones")

    def test_the_shadows_are_black_scaled_and_wet_between_the_scales(self) -> None:
        shadow = organic.organic("shadow")
        worn = shadow.surface["sheen"]
        self.assertLess(max(shadow.style.material("hull").albedo), 0.03, "the Shadows are black")
        self.assertEqual(worn["pattern_cells"], 1.0, "scales")
        self.assertGreaterEqual(worn["pattern_scale_m"], 4.0, "big ones")
        self.assertGreater(worn["pattern_speed_mps"], 0.0, "that move")
        self.assertLessEqual(worn["pattern_speed_mps"], 0.2, "slowly")
        self.assertEqual(worn["liquid"], 1.0, "a glossy black liquid in the gaps")
        self.assertGreater(worn["liquid_flow_mps"], 0.0, "that flows")
        self.assertEqual(worn["pattern_tint"], [0.0, 0.0, 0.0])
        violet = sheen.sh_colour(worn["iri_sh"], sheen.sphere_directions(200)).mean(axis=0)
        self.assertGreater(violet[2], violet[0])
        self.assertGreater(violet[0], violet[1], "a purple sheen: blue over red over green")
        self.assertLessEqual(worn["iri_strength"], 0.3, "and only a hint of it")
        self.assertEqual(worn["variant_share"], 0.0)

    def test_the_hex_look_has_a_hint_of_sheen_and_soft_mottling(self) -> None:
        worn = organic.organic("hex").surface["sheen"]
        self.assertEqual(worn["iri_base"], 0.0, "at the rim only")
        self.assertLessEqual(worn["iri_strength"], 0.25)
        self.assertGreater(worn["pattern_dark"], 0.0)
        self.assertLess(worn["pattern_edge"], 0.5, "soft-edged")
        self.assertEqual((worn["liquid"], worn["glow_energy"]), (0.0, 0.0))


if __name__ == "__main__":
    unittest.main()
