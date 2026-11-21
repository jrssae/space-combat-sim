"""Weapons and loadouts (M10-T03, Q53; ``data/capitals/loadouts.json``): the file the hull tasks build their weapon mounts to
and T12 to T16 read their numbers from stays whole. Light on purpose: each hull task adds its own manifest-against-loadout
check."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LOADOUTS = ROOT / "data" / "capitals" / "loadouts.json"
CATALOGUE = ROOT / "data" / "ships" / "catalogue.json"
JUMPS = ("own", "gate", "shimmer", "none")
MINES = (None, "energy", "guided")  # Q53: only the G'Quan and the Vorchan lay mines in battle


class LoadoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.data = json.loads(LOADOUTS.read_text())
        cls.weapons = cls.data["weapons"]
        cls.hulls = cls.data["hulls"]

    def test_every_weapon_has_a_declared_kind_and_trait(self) -> None:
        for wid, spec in self.weapons.items():
            self.assertIn(spec["kind"], self.data["kinds"], wid)
            self.assertIn(spec.get("trait"), [None, *self.data["traits"]], wid)
            if spec["kind"] != "mine_prox":  # a scenario mine is laid, not fired
                self.assertGreater(spec["cycle_s"], 0.0, wid)

    def test_every_hull_names_declared_weapons_and_a_class(self) -> None:
        for hid, hull in self.hulls.items():
            self.assertIn(hull["class"], self.data["classes"], hid)
            self.assertGreater(hull["hull"], 0, hid)
            self.assertIn(hull["jump"], JUMPS, hid)
            self.assertIn(hull["lays_mines"], MINES, hid)
            for group in ("weapons", "interceptors"):
                for wid, count in hull[group].items():
                    self.assertIn(wid, self.weapons, f"{hid}: {wid}")
                    self.assertGreater(count, 0, f"{hid}: {wid}")
            for wid in hull["interceptors"]:
                self.assertEqual(self.weapons[wid]["kind"], "interceptor", f"{hid}: {wid}")

    def test_launches_name_fighters_or_small_craft_with_entries(self) -> None:
        for hid, hull in self.hulls.items():
            for craft, count in hull["launches"].items():
                self.assertGreater(count, 0, hid)
                if craft == "starfury_ally":  # the catalogue's pooled Starfury, no loadout row of its own
                    continue
                self.assertIn(craft, self.hulls, f"{hid} launches {craft}")
                self.assertIn(self.hulls[craft]["class"], ("fighter", "small_craft"), f"{hid} launches {craft}")

    def test_every_catalogued_capital_has_an_entry(self) -> None:
        ships = json.loads(CATALOGUE.read_text())["ships"]
        for ship in ships:
            if ship.get("role") == "capital":
                self.assertIn(ship["id"], self.hulls, ship["id"])

    def test_the_maintainers_answers_hold(self) -> None:
        h = self.hulls
        self.assertEqual(h["ea_omega"]["launches"]["starfury_ally"], 32)
        self.assertEqual(h["ea_nova"]["class"], "dreadnought")
        self.assertEqual(h["ea_nova"]["launches"]["starfury_ally"], 24)
        self.assertEqual(h["ea_nova"]["weapons"]["ea_sweep_beam_nova"], h["ea_omega"]["weapons"]["ea_sweep_beam"])
        self.assertEqual(h["ea_panama"]["weapons"], {})
        self.assertEqual({k for k, v in h.items() if v["lays_mines"]}, {"narn_gquan", "centauri_vorchan"})
        self.assertNotIn("pierce", self.data["traits"])
        self.assertNotIn("trait", self.weapons["centauri_ion_cannon"])


if __name__ == "__main__":
    unittest.main()
