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
        for wrong in ({"iri_strength": 1.5}, {"pattern_cover": -0.1}, {"pattern_scale_m": 0.0}, {"iri_sh": ((0.0, 0.0, 0.0),) * 8}, {"coat": 2.0}):
            with self.assertRaises(ValueError, msg=str(wrong)):
                sheen.Sheen(**wrong)
        changed = sheen.Sheen(glow_energy=0.1).but(glow_energy=0.2, pattern_cells=1.0)
        self.assertEqual((changed.glow_energy, changed.pattern_cells), (0.2, 1.0))

    def test_the_manifest_entry_is_plain_json_under_the_uniforms_names(self) -> None:
        entry = organic.organic("vorlon").surface["sheen"]
        self.assertEqual(json.loads(json.dumps(entry)), entry)
        self.assertEqual(np.asarray(entry["iri_sh"]).shape, (9, 3))
        declared = {name: kind for kind, name in re.findall(r"^uniform (\w+) (\w+)", LAYER.read_text(encoding="utf-8"), flags=re.MULTILINE)}
        self.assertEqual(set(entry), set(declared), "every number of a sheen is a uniform of the layer, and the other way round")
        for name, value in entry.items():
            self.assertEqual(declared[name], "float" if isinstance(value, float) else "vec3", name)

    def test_the_games_material_sets_every_number(self) -> None:
        source = MATERIAL.read_text(encoding="utf-8")
        lists = {name: re.findall(r'"(\w+)"', body) for name, body in re.findall(r"const (SCALARS|COLOURS): Array\[String\] = \[(.*?)\]", source, flags=re.DOTALL)}
        entry = sheen.Sheen().to_json()
        self.assertEqual(set(lists["SCALARS"]), {k for k, v in entry.items() if isinstance(v, float)})
        self.assertEqual(set(lists["COLOURS"]), {k for k, v in entry.items() if isinstance(v, list) and k != "iri_sh"})
        self.assertIn('const IRIDESCENCE: String = "iri_sh"', source)
        self.assertIn('#include "res://assets/shaders/hull_sheen_layer.gdshaderinc"', SHADER.read_text(encoding="utf-8"))


class OrganicStyleTests(unittest.TestCase):
    def test_every_look_has_three_options_that_differ(self) -> None:
        self.assertEqual(organic.LOOKS, ("vorlon", "shadow", "hex"))
        for look in organic.LOOKS:
            entries = [json.dumps(organic.organic(look, option).surface["sheen"], sort_keys=True) for option in organic.OPTIONS]
            self.assertEqual(len(set(entries)), 3, look)
        with self.assertRaises(ValueError):
            organic.organic("vorlon", "d")

    def test_the_vorlons_and_the_shadows_are_seamless_and_the_hex_look_is_plated(self) -> None:
        self.assertIsInstance(organic.organic("vorlon").skin, Seamless)  # Q46
        self.assertIsInstance(organic.organic("shadow").skin, Seamless)
        self.assertIsInstance(organic.organic("hex").skin, HexGrid)  # Q45, Q47
        self.assertTrue(organic.organic("hex").style.material("hull").paneled)
        self.assertFalse(organic.organic("vorlon").style.material("hull").paneled)

    def test_the_looks_are_the_shows(self) -> None:
        vorlon, shadow = (organic.organic(look) for look in ("vorlon", "shadow"))
        self.assertGreater(vorlon.surface["sheen"]["glow_energy"], 0.0, "the Vorlons glow faintly (Q46)")
        self.assertLess(vorlon.surface["sheen"]["glow_energy"], 0.2)
        self.assertLess(max(shadow.style.material("hull").albedo), 0.03, "the Shadows are black")
        self.assertGreater(shadow.surface["sheen"]["pattern_speed_mps"], 0.0, "and their skin moves")
        violet = sheen.sh_colour(shadow.surface["sheen"]["iri_sh"], sheen.sphere_directions(200)).mean(axis=0)
        self.assertGreater(violet[2], violet[0])
        self.assertGreater(violet[0], violet[1], "a purple sheen: blue over red over green")
        skin = vorlon.style.material("hull").albedo
        self.assertTrue(skin[0] > skin[2] and skin[1] > skin[2], "yellow-green")
        petal = vorlon.style.material("hull_panel").albedo
        self.assertGreater(petal[2], 3.0 * petal[0], "deep blue petals")
        self.assertEqual(vorlon.style.edge_wear, 0.0, "living skin does not chip")


if __name__ == "__main__":
    unittest.main()
