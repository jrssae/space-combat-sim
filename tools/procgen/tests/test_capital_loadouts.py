"""Weapons and loadouts (M10-T03, Q53; ``data/capitals/loadouts.json``): the file the hull tasks build their weapon mounts to
and T12 to T16 read their numbers from stays whole. Light on purpose: each hull task adds its own manifest-against-loadout
check."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from tools.procgen.core import loadout

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
        # Q71: no beams on the Nova; 14 fixed pulse cannons and the 4 blocked midship pods as interceptors.
        self.assertEqual(h["ea_nova"]["weapons"], {"ea_pulse_cannon_fixed": 14})
        self.assertEqual(h["ea_nova"]["interceptors"], {"ea_interceptor_pod": 4})
        self.assertNotIn("ea_sweep_beam_nova", self.weapons)
        self.assertEqual(self.weapons["ea_pulse_cannon_fixed"]["kind"], "bolt_fixed")
        self.assertEqual(h["ea_panama"]["weapons"], {})
        self.assertEqual({k for k, v in h.items() if v["lays_mines"]}, {"narn_gquan", "centauri_vorchan"})
        self.assertNotIn("pierce", self.data["traits"])
        self.assertNotIn("trait", self.weapons["centauri_ion_cannon"])


class ManifestCheckTests(unittest.TestCase):
    """``core/loadout.problems``: a built hull's mounts and bays against its row (each hull task's check, M10-T21 on)."""

    LOADOUTS = {
        "weapons": {"gun": {"kind": "bolt_medium"}, "beam": {"kind": "beam_sustained"}, "pd": {"kind": "interceptor"}},
        "hulls": {"ship": {"weapons": {"gun": 2, "beam": 1}, "interceptors": {"pd": 1}, "launches": {"starfury_ally": 4}}},
    }

    @staticmethod
    def built(**changes: object) -> dict:
        hp = {"weapons": [{"name": "g1", "kind": "turret", "weapon": "gun"}, {"name": "g2", "kind": "turret", "weapon": "gun"},
                          {"name": "b", "kind": "beam", "weapon": "beam"}, {"name": "p", "kind": "interceptor", "weapon": "pd"}],
              "bays": [{"name": "bay", "craft": "starfury_ally", "capacity": 4}]}
        hp.update(changes)
        return hp

    def test_a_hull_built_to_its_row_has_no_problems(self) -> None:
        self.assertEqual(loadout.problems(self.built(), self.LOADOUTS, "ship"), [])

    def test_each_kind_of_difference_is_named(self) -> None:
        self.assertEqual(loadout.problems(self.built(), self.LOADOUTS, "other"), ["other: no loadout row"])
        short = self.built(weapons=self.built()["weapons"][1:])
        self.assertIn("weapons built", loadout.problems(short, self.LOADOUTS, "ship")[0])
        wrong = self.built(weapons=[{**w, "kind": "turret"} for w in self.built()["weapons"]])
        self.assertTrue(any("needs a beam" in p for p in loadout.problems(wrong, self.LOADOUTS, "ship")))
        unnamed = self.built(weapons=[{"name": "x", "kind": "turret"}, *self.built()["weapons"]])
        self.assertIn("mount 'x' names no weapon", loadout.problems(unnamed, self.LOADOUTS, "ship"))
        small = self.built(bays=[{"name": "bay", "craft": "starfury_ally", "capacity": 2}])
        self.assertIn("bays launch", loadout.problems(small, self.LOADOUTS, "ship")[0])

    def test_a_fixed_gun_turns_no_further_than_its_arc(self) -> None:
        data = {"weapons": {"bow": {"kind": "bolt_fixed"}, "gimbal": {"kind": "bolt_fixed", "arc_deg": 16}},
                "hulls": {"ship": {"weapons": {"bow": 1, "gimbal": 1}, "interceptors": {}, "launches": {}}}}
        mounts = [{"name": "f", "kind": "turret", "weapon": "bow", "traverse_deg": 0.0}, {"name": "g", "kind": "turret", "weapon": "gimbal", "traverse_deg": 8.0}]
        self.assertEqual(loadout.problems({"weapons": mounts}, data, "ship"), [])
        turning = [{**mounts[0], "traverse_deg": 180.0}, mounts[1]]
        self.assertTrue(any("traverses 180.0 deg" in p for p in loadout.problems({"weapons": turning}, data, "ship")))

    def test_every_loadout_weapon_kind_has_a_mount(self) -> None:
        data = loadout.read()
        mounted = set(loadout.MOUNT_FOR_KIND)
        for wid, spec in data["weapons"].items():
            if spec["kind"] not in ("mine_prox", "fighter_gun"):  # a scenario mine and a fighter's gun stand on no capital mount
                self.assertIn(spec["kind"], mounted, wid)


if __name__ == "__main__":
    unittest.main()
