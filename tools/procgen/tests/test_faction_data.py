"""``data/factions.json`` profiles (M10-T02, D12.3): what a faction names must exist, so hulls can read it as data."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FACTIONS = json.loads((ROOT / "data" / "factions.json").read_text())
LOADOUTS = json.loads((ROOT / "data" / "capitals" / "loadouts.json").read_text())
CATALOGUE = json.loads((ROOT / "data" / "ships" / "catalogue.json").read_text())

# The paint families procgen knows (styles/*.py); a faction's `style` is one of them or "" (neutral).
STYLES = {"earthforce", "raider", "narn", "centauri", "minbari", "drazi", "brakiri", "vree", "isa", "shadow", "vorlon", "drakh"}
# The renegades fly the alliance's hulls and guns.
HULLS_OF = {"renegades": "earth_alliance"}


class FactionDataTests(unittest.TestCase):
    def test_the_fourteen_factions_are_listed_once(self) -> None:
        ids = [f["id"] for f in FACTIONS["factions"]]
        self.assertEqual(len(ids), 14)
        self.assertEqual(len(set(ids)), 14)

    def test_every_relation_names_listed_factions_once(self) -> None:
        ids = {f["id"] for f in FACTIONS["factions"]}
        seen = set()
        for r in FACTIONS["relations"]:
            self.assertTrue({r["a"], r["b"]} <= ids, r)
            self.assertNotEqual(r["a"], r["b"])
            key = frozenset((r["a"], r["b"]))
            self.assertNotIn(key, seen, r)
            seen.add(key)

    def test_styles_fighters_weapons_and_mines_exist(self) -> None:
        for f in FACTIONS["factions"]:
            owner = HULLS_OF.get(f["id"], f["id"])
            self.assertIn(f.get("style", ""), STYLES | {""}, f["id"])
            for hull in f.get("fighters", []):
                self.assertIn(hull, LOADOUTS["hulls"], f"{f['id']}: {hull}")
                self.assertEqual(LOADOUTS["hulls"][hull]["class"], "fighter", hull)
            for weapon in f.get("weapons", []):
                self.assertEqual(LOADOUTS["weapons"][weapon]["faction"], owner, f"{f['id']}: {weapon}")
            for key, kinds in (("mine", {"mine_prox"}), ("battle_mine", {"mine_energy", "mine_guided"})):
                if f.get(key):
                    spec = LOADOUTS["weapons"][f[key]]
                    self.assertEqual(spec["faction"], owner, f["id"])
                    self.assertIn(spec["kind"], kinds, f"{f['id']}.{key}")

    def test_a_marking_is_the_name_of_a_livery_row_the_hulls_may_carry(self) -> None:
        for f in FACTIONS["factions"]:
            if f.get("marking"):
                self.assertEqual(f["marking"], f["id"], "the row is named for the faction")

    def test_the_catalogue_flies_each_faction_it_names(self) -> None:
        ids = {f["id"] for f in FACTIONS["factions"]}
        for ship in CATALOGUE["ships"]:
            self.assertIn(ship["faction"], ids, ship["id"])


if __name__ == "__main__":
    unittest.main()
