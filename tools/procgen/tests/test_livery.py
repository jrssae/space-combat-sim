"""``core/livery.py`` (M4-T30b, Q35): the wing liveries, their stripe patterns and number fields, the digit atlas and the fallback."""

from __future__ import annotations

import itertools
import unittest

import numpy as np

from tools.procgen.core import livery as lv


def colour_distance(a, b) -> float:
    return float(np.linalg.norm(np.asarray(a, dtype=float) - np.asarray(b, dtype=float)))


class TableTests(unittest.TestCase):
    def test_the_named_wings_are_there(self) -> None:
        for name in ("alpha", "beta", "delta", "zeta"):
            self.assertIn(name, lv.LIVERIES)
            self.assertEqual(lv.livery_for(name.upper()).name, name)

    def test_every_named_wing_differs_in_colour_and_pattern(self) -> None:
        named = [lv.LIVERIES[n] for n in ("alpha", "beta", "delta", "zeta")]
        for a, b in itertools.combinations(named, 2):
            self.assertNotEqual(a.pattern, b.pattern, (a.name, b.name))
            self.assertGreater(colour_distance(a.primary, b.primary), 0.08, (a.name, b.name))

    def test_each_pattern_paints_with_two_colours_that_differ(self) -> None:
        for livery in lv.LIVERIES.values():
            self.assertGreater(colour_distance(livery.primary, livery.secondary), 0.08, livery.name)

    def test_the_fallback_is_stable_for_a_name_and_differs_between_names(self) -> None:
        self.assertEqual(lv.livery_for("Kilo"), lv.livery_for("KILO"))
        kilo, lima = lv.livery_for("Kilo"), lv.livery_for("Lima")
        self.assertNotEqual((kilo.primary, kilo.pattern), (lima.primary, lima.pattern))
        # 24 palette and pattern pairs: a dozen wing names spread over most of them.
        names = ("kilo", "lima", "mike", "omega", "sigma", "tango", "gamma", "epsilon", "eta", "theta", "iota", "kappa")
        looks = {(lv.livery_for(n).primary, lv.livery_for(n).pattern) for n in names}
        self.assertGreaterEqual(len(looks), 8)
        for n in names:
            self.assertNotIn(lv.livery_for(n).primary, [l.primary for l in lv.LIVERIES.values()], n)

    def test_every_wing_puts_its_number_on_the_deck_and_the_upper_left_wing(self) -> None:
        # Q37: the large number on the dorsal deck, the small repeat on the upper left wing; no pod numbers.
        for livery in list(lv.LIVERIES.values()) + [lv.livery_for("kilo")]:
            self.assertEqual(livery.numbers, ("dorsal", "wing"), livery.name)
        self.assertLess(lv.NUMBER_FIELDS["wing"].centre[0], 0.0, "the left wing is -x")

    def test_the_plain_livery_has_no_pattern_and_no_number(self) -> None:
        plain = lv.livery_for("")
        self.assertEqual(plain.pattern, lv.PLAIN_PATTERN)
        self.assertFalse(plain.numbered)

    def test_the_hash_is_fnv1a_32(self) -> None:
        # Godot's `Livery.fnv1a` must give the same; these are the published FNV-1a test vectors.
        self.assertEqual(lv.fnv1a32(""), 0x811C9DC5)
        self.assertEqual(lv.fnv1a32("a"), 0xE40C292C)
        self.assertEqual(lv.fnv1a32("foobar"), 0xBF9CF968)

    def test_the_number_is_two_digits_from_one(self) -> None:
        self.assertEqual(lv.number_text(1), "01")
        self.assertEqual(lv.number_text(12), "12")
        self.assertEqual(lv.number_text(0), "")


class PatternTests(unittest.TestCase):
    """The patterns paint where they should: wing patterns on the struts, nose bands on the fuselage, the numbers inside their parts."""

    def test_every_stripe_names_a_zone_and_a_colour_slot(self) -> None:
        for name, stripes in lv.PATTERNS.items():
            for s in stripes:
                self.assertTrue(s.zones, name)
                self.assertIn(s.slot, (1, 2), name)
                self.assertLess(s.lo, s.hi, name)

    def test_alpha_bands_cover_the_struts_only(self) -> None:
        points = np.array([[2.5, 1.4, -0.8], [-2.5, 1.4, -0.8], [0.0, 1.0, -2.0]])
        normals = np.array([[0.0, 1.0, 0.0]] * 3)
        zones = np.array([lv.ZONES["strut_upper"], lv.ZONES["strut_upper"], lv.ZONES["fuselage"]])
        slots = lv.paint_slots(lv.PATTERNS[lv.LIVERIES["alpha"].pattern], points, normals, zones)
        self.assertEqual(slots[0], slots[1])  # mirror symmetric
        self.assertGreater(slots[0], 0)
        self.assertEqual(slots[2], 0)

    def test_the_zone_of_each_starfury_part(self) -> None:
        self.assertEqual(lv.zone_of("fuselage"), lv.ZONES["fuselage"])
        self.assertEqual(lv.zone_of("strut_ul"), lv.ZONES["strut_upper"])
        self.assertEqual(lv.zone_of("strut_lr"), lv.ZONES["strut_lower"])
        self.assertEqual(lv.zone_of("pod_ll"), lv.ZONES["pod"])
        self.assertEqual(lv.zone_of("claw_ur"), lv.ZONES["claw"])
        self.assertEqual(lv.zone_of("cockpit_interior"), 0)

    def test_the_dorsal_number_field_reads_from_above_nose_up(self) -> None:
        field = lv.NUMBER_FIELDS["dorsal"]
        self.assertIn(lv.ZONES["strut_upper"], field.zones)  # the struts' roots cover the fuselage from above
        self.assertGreater(field.facing[1], 0.9)
        self.assertGreater(field.right[0], 0.9)  # read left to right across the ship
        self.assertLess(field.up[2], -0.9)  # the tops of the digits point at the nose


class DigitAtlasTests(unittest.TestCase):
    def test_the_atlas_covers_0_to_9(self) -> None:
        atlas = lv.digit_atlas()
        self.assertEqual(atlas.dtype, np.uint8)
        h, w = atlas.shape
        self.assertEqual(w, 10 * lv.DIGIT_CELL_PX[0])
        self.assertEqual(h, lv.DIGIT_CELL_PX[1])
        cells = [atlas[:, k * lv.DIGIT_CELL_PX[0] : (k + 1) * lv.DIGIT_CELL_PX[0]] for k in range(10)]
        for k, cell in enumerate(cells):
            self.assertGreater(int(cell.max()), 200, k)  # the stroke's centre line is in the cell
            self.assertLess(int(cell[0].max()), 128, k)  # the cell's border is outside every stroke
        for a, b in itertools.combinations(range(10), 2):
            self.assertGreater(int(np.abs(cells[a].astype(int) - cells[b].astype(int)).max()), 64, (a, b))


if __name__ == "__main__":
    unittest.main()
