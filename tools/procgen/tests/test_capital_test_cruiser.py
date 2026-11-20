"""``capital_test_cruiser`` (M10-T05, D12.1): the capital framework's whole output contract on its test hull: files and pieces,
both texture sets and the shared detail tile, the sections (they cover the hull, their shares, kinds and blasts), hardpoints
that agree with their sections, collision per section (budget, coverage, the bay and the collar's bore open), the rotating
piece, the class budget and determinism.

The expected numbers are typed in from the generator's docstring and docs/assets-capital.md ("Capital framework"), not read from
the generator.
"""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import capital_test_cruiser as ctc
from tools.procgen.core import collision as col
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.budgets import over_budget, texture_mb
from tools.procgen.core.capital import EXPLOSIVE_KINDS, SECTION_KINDS
from tools.procgen.core.context import BuildContext
from tools.procgen.core.glb import read_glb
from tools.procgen.core.obj import read_obj
from tools.procgen.tests.mesh_checks import MAP_KEYS, assert_mirror_symmetric, assert_model_mesh, glb_triangles

ID = "capital_test_cruiser"
TEST_OPTIONS = {"atlas_px": 512, "detail_px": 128, "spacing": 2.0}
SECTIONS = ("bow", "bridge", "hangar", "magazine", "spine", "habitat", "fuel", "reactor", "engine_r", "engine_l")
KINDS = {"bow": "structure", "bridge": "bridge", "hangar": "hangar", "magazine": "magazine", "spine": "structure", "habitat": "habitat",
         "fuel": "fuel", "reactor": "reactor", "engine_r": "engine", "engine_l": "engine"}
LENGTH, SPAN, HEIGHT = 300.0, 60.0, 45.6  # the stand-in cruiser's 300 by 60 by 40 m, plus the bay below and the antenna above
WEAPONS = {"turret": 6, "beam": 2, "interceptor": 3, "missile": 1, "mine": 1}
ROTOR_Z = 162.5  # the rotating section's middle, from the bow
STARFURY = (11.0, 7.0, 9.0)  # a fighter's box: span, height, length


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class CapitalTestCruiserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = ctc.build(BuildContext(cls.dir_a, seed=42, options=TEST_OPTIONS))
        cls.out_b = ctc.build(BuildContext(cls.dir_b, seed=42, options=TEST_OPTIONS))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.hp = json.loads((cls.dir_a / "hardpoints.json").read_text(encoding="utf-8"))
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.sections = {s["name"]: s for s in cls.manifest["sections"]}
        cls.pieces = cls.manifest["pieces"]
        # Every collision shape in the body frame, the rotating piece at rest: by section.
        cls.shapes = {}
        for entry in cls.manifest["collision"]["pieces"]:
            pivot = np.array(cls.pieces[entry["piece"]].get("pivot", (0.0, 0.0, 0.0)))
            cls.shapes[entry["name"]] = [s.translated(pivot) for s in col.shapes_from_entry(entry)]
        cls.all_shapes = [s for group in cls.shapes.values() for s in group]

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def authored(self, v: list[float]) -> np.ndarray:
        """A body-frame point in the generator's frame (the bow's tip at z = 0, the hull's axis on y = 0)."""
        return np.array(v) + self.offset

    def chunk_points(self, name: str) -> np.ndarray:
        """A section's chunk mesh corners, back in place in the body frame."""
        chunk = next(c for c in self.hp["chunks"] if c["name"] == name)
        return glb_triangles(self.dir_a / chunk["mesh"]).reshape(-1, 3) + np.array(chunk["offset"])

    # --- files, pieces, texel tiers ------------------------------------------------------------------------------------
    def test_registered_built_and_listed(self) -> None:
        self.assertIs(ASSETS[ID], ctc.build)
        self.assertEqual(self.out_a.warnings, (), "the collision covers the hull")
        on_disk = {p.name for p in self.dir_a.iterdir()}
        self.assertEqual({p.name for p in self.out_a.files}, on_disk)
        manifest_io.validate_manifest(self.manifest)
        self.assertEqual(self.manifest["files"]["mesh"], f"{ID}.glb")

    def test_the_hull_and_the_rotating_section_are_pieces_with_their_own_atlases(self) -> None:
        self.assertEqual(list(self.pieces), ["hull", "rotor"])
        self.assertEqual(self.manifest["mesh"], self.pieces["hull"]["mesh"], "the manifest's mesh is the hull piece's")
        assert_model_mesh(self, self.dir_a, self.pieces["hull"]["mesh"], f"{ID}.obj", "hull")
        assert_model_mesh(self, self.dir_a, self.pieces["rotor"]["mesh"], f"{ID}_rotor.obj", "rotor")
        maps = {piece["mesh"]["surfaces"][0]["albedo"] for piece in self.pieces.values()}
        self.assertEqual(len(maps), 2, "an atlas a piece")
        self.assertEqual([s for p in self.pieces.values() for s in p["sections"]],
                         [s for s in SECTIONS if s != "habitat"] + ["habitat"], "every section is in one piece")

    def test_low_and_high_texture_sets_are_written_for_every_piece(self) -> None:
        for name, piece in self.pieces.items():
            surface = piece["mesh"]["surfaces"][0]
            for key in MAP_KEYS:
                self.assertTrue((self.dir_a / surface[key]).is_file(), f"{name} {key}")
            for key in ("albedo", "normal", "orm"):
                low = surface["detail"]["low"][key]
                self.assertTrue((self.dir_a / low).is_file() and (self.dir_a / (low + ".import")).is_file(), f"{name} {key}")
                self.assertNotEqual(sha256(self.dir_a / low), sha256(self.dir_a / surface[key]), f"{name}: the low {key} map differs")

    def test_every_piece_shares_one_detail_tile_laid_in_world_space(self) -> None:
        tiles = [s["world_detail"] for p in self.pieces.values() for s in p["mesh"]["surfaces"] if not s["blend"]]
        self.assertEqual(len(tiles), 2)
        self.assertEqual(tiles[0], tiles[1], "one tile for both pieces")
        self.assertEqual((tiles[0]["tile_m"], tiles[0]["px"]), (16.0, 128))
        for key in ("albedo", "normal"):
            self.assertTrue((self.dir_a / tiles[0][key]).is_file() and (self.dir_a / (tiles[0][key] + ".import")).is_file(), key)
        # A 300 m hull's atlas texel is tens of centimetres; the tile brings plates of one to three metres at centimetres a texel.
        self.assertGreater(self.pieces["hull"]["mesh"]["texel_m"], 10.0 * tiles[0]["tile_m"] / 1024.0)
        self.assertEqual(self.manifest["skin"], "panel_mosaic")

    def test_dimensions_and_the_bow_forward(self) -> None:
        dims = self.manifest["dimensions_m"]
        self.assertAlmostEqual(dims["length"], LENGTH, places=3)
        self.assertAlmostEqual(dims["span"], SPAN, delta=0.01 * SPAN)
        self.assertAlmostEqual(dims["height"], HEIGHT, delta=0.02 * HEIGHT)
        v = read_obj(self.dir_a / f"{ID}.obj").vertices + self.offset
        self.assertAlmostEqual(float(v[:, 2].min()), 0.0, places=3)
        self.assertAlmostEqual(float(v[:, 2].max()), LENGTH, places=3)
        self.assertLess(float(np.abs(v[v[:, 2] < 20.0][:, 0]).max()), 12.0, "the bow tapers")
        assert_mirror_symmetric(self, np.round(v[np.abs(v[:, 0]) > 23.0], 3), "the nacelles and the tubes mirror")

    # --- sections ------------------------------------------------------------------------------------------------------
    def test_the_sections_are_named_kinded_and_share_out_the_hull_points(self) -> None:
        self.assertEqual(tuple(self.sections), SECTIONS)
        self.assertEqual({name: s["kind"] for name, s in self.sections.items()}, KINDS)
        self.assertEqual({s["kind"] for s in self.sections.values()}, set(SECTION_KINDS), "the test hull has every kind")
        self.assertAlmostEqual(sum(s["hull_share"] for s in self.sections.values()), 1.0, places=9)
        self.assertEqual(self.sections["engine_r"]["hull_share"], self.sections["engine_l"]["hull_share"])

    def test_only_explosive_sections_have_a_blast_energy(self) -> None:
        for name, s in self.sections.items():
            if s["kind"] in EXPLOSIVE_KINDS:
                self.assertGreater(s["blast_energy_j"], 0.0, name)
            else:
                self.assertNotIn("blast_energy_j", s, name)
        self.assertGreater(self.sections["reactor"]["blast_energy_j"], self.sections["fuel"]["blast_energy_j"])

    def test_the_sections_cover_the_hull(self) -> None:
        # Every triangle of every piece is in exactly one section's chunk, on its piece's atlas, back in place inside its box.
        self.assertEqual([c["name"] for c in self.hp["chunks"]], [s for p in self.pieces.values() for s in p["sections"]])
        self.assertEqual(self.manifest["chunks"], [c["name"] for c in self.hp["chunks"]])
        for piece_name, piece in self.pieces.items():
            parent = read_glb(self.dir_a / piece["mesh"]["file"])
            uvs = {(round(float(u), 5), round(float(w), 5)) for p in parent.primitives for u, w in p.uv}
            total = 0
            for name in piece["sections"]:
                chunk = next(c for c in self.hp["chunks"] if c["name"] == name)
                self.assertEqual(chunk["piece"], piece_name)
                cut = read_glb(self.dir_a / chunk["mesh"])
                for primitive in cut.primitives:
                    self.assertTrue({(round(float(u), 5), round(float(w), 5)) for u, w in primitive.uv} <= uvs, f"{name}: on its piece's atlas")
                tris = glb_triangles(self.dir_a / chunk["mesh"])
                self.assertEqual(len(tris), len(read_obj(self.dir_a / chunk["obj"]).faces), name)
                total += len(tris)
                pts = self.chunk_points(name)
                lo, hi = np.array(self.sections[name]["aabb_min"]), np.array(self.sections[name]["aabb_max"])
                self.assertTrue(np.all(pts >= lo - 1.0) and np.all(pts <= hi + 1.0), f"{name}: its chunk lies in its box")
                joint = np.array(chunk["joint"])
                self.assertTrue(np.all(joint >= lo - 1e-3) and np.all(joint <= hi + 1e-3), f"{name}: it breaks away at its own box")
            self.assertEqual(total, piece["mesh"]["triangles"], f"{piece_name}: the sections share out its triangles")
        self.assertEqual(sum(p["mesh"]["triangles"] for p in self.pieces.values()), self.manifest["budget"]["triangles"])

    def test_the_sections_lie_bow_to_stern(self) -> None:
        mid = {name: 0.5 * (self.authored(s["aabb_min"])[2] + self.authored(s["aabb_max"])[2]) for name, s in self.sections.items()}
        order = ["bow", "magazine", "spine", "fuel", "reactor", "engine_r"]
        self.assertEqual(sorted(order, key=mid.get), order)
        self.assertAlmostEqual(mid["habitat"], ROTOR_Z, delta=0.5)
        self.assertLess(self.sections["hangar"]["aabb_max"][1], self.sections["bridge"]["aabb_min"][1], "the bay hangs below, the bridge stands above")

    # --- hardpoints ----------------------------------------------------------------------------------------------------
    def test_hardpoints_keep_the_ships_contract(self) -> None:
        for key in ("mass_kg", "center_of_mass", "cockpit_camera", "chase_anchor", "muzzles", "pods", "rcs", "collision", "nav_lights",
                    "turrets", "chunks", "jump_point", "weapons", "bays", "engines", "rotors", "lights"):
            self.assertIn(key, self.hp)
        self.assertEqual((self.hp["muzzles"], self.hp["turrets"], self.hp["collision"]), ([], [], []))
        self.assertEqual([p["name"] for p in self.hp["pods"]], [e["name"] for e in self.hp["engines"]], "the plumes read the engines as pods")
        self.assertEqual(set(self.hp["nav_lights"]), {"port", "starboard", "top", "top_lamp", "top_lamp_range_m", "cabin", "cabin_range_m"})
        self.assertEqual(self.hp["nav_lights"]["cabin"], self.hp["cockpit_camera"]["position"], "the cabin's glow is the bridge")
        self.assertLess(self.hp["nav_lights"]["port"][0], 0.0)
        bridge = self.authored(self.hp["cockpit_camera"]["position"])
        self.assertTrue(60.0 < bridge[2] < 75.0 and bridge[1] > 11.0, "the view from the tower's front")
        jump = self.hp["jump_point"]
        self.assertAlmostEqual(self.authored(jump["position"])[2], -500.0, places=3)
        half_diagonal = 0.5 * float(np.linalg.norm([LENGTH, SPAN, HEIGHT]))
        self.assertGreater(jump["mouth_radius_m"], half_diagonal, "the mouth clears the hull")

    def test_a_mount_for_every_weapon_kind(self) -> None:
        counts: dict[str, int] = {}
        for w in self.hp["weapons"]:
            counts[w["kind"]] = counts.get(w["kind"], 0) + 1
            self.assertAlmostEqual(float(np.linalg.norm(w["forward"])), 1.0, places=4)
            self.assertAlmostEqual(float(np.linalg.norm(w["up"])), 1.0, places=4)
        self.assertEqual(counts, WEAPONS)
        turrets = [w for w in self.hp["weapons"] if w["kind"] == "turret"]
        self.assertTrue(all(w["up"] == [0.0, 1.0, 0.0] for w in turrets), "gun turrets are dorsal")
        aft = next(w for w in turrets if w["name"] == "turret_aft")
        self.assertEqual(aft["forward"], [0.0, 0.0, 1.0], "the aft turret rests facing aft")

    def test_every_hardpoint_is_held_by_the_section_it_stands_on(self) -> None:
        names = []
        for group in ("weapons", "bays", "engines", "lights"):
            for entry in self.hp[group]:
                names.append(entry["name"])
                section = self.sections[entry["section"]]
                self.assertIn(entry["name"], section["hardpoints"], entry["name"])
                at = np.array(entry["position"])
                if entry.get("kind") == "bay":  # a craft starts in the hall's open middle
                    self.assertTrue(np.all(at > np.array(section["aabb_min"])) and np.all(at < np.array(section["aabb_max"])), "in its hall")
                    continue
                gap = float(col.gaps(self.shapes[entry["section"]], at[None]).max())
                self.assertLessEqual(gap, 1.5, f"{entry['name']} stands on {entry['section']}'s collision")
        self.assertEqual(len(set(names)), len(names), "hardpoint names are unique")
        self.assertEqual(sorted(n for s in self.sections.values() for n in s["hardpoints"]), sorted(names), "and each is held once")

    def test_port_twins_mirror_their_starboard_hardpoints(self) -> None:
        by_name = {e["name"]: e for group in ("weapons", "bays", "engines") for e in self.hp[group]}
        pairs = [(n, n.replace("_r", "_l")) for n in by_name if n.endswith("_r") or "_r_" in n]
        self.assertEqual(len(pairs), 6)
        for right, left in pairs:
            r, l = np.array(by_name[right]["position"]), np.array(by_name[left]["position"])
            np.testing.assert_allclose(l, r * (-1.0, 1.0, 1.0), atol=1e-5, err_msg=right)
            self.assertGreater(r[0], 0.0, right)

    def test_the_bay_and_the_tubes_give_a_start_pose_and_a_way_out(self) -> None:
        self.assertEqual([(b["name"], b["kind"]) for b in self.hp["bays"]], [("bay", "bay"), ("tube_r", "tube"), ("tube_l", "tube")])
        for b in self.hp["bays"]:
            start, way_out = np.array(b["position"]), np.array(b["exit"])
            np.testing.assert_allclose((way_out - start) / np.linalg.norm(way_out - start), b["forward"], atol=1e-5, err_msg="it leaves along its nose")
            self.assertEqual(b["up"], [0.0, 1.0, 0.0])
        bay = self.hp["bays"][0]
        self.assertEqual((bay["mouth_m"], bay["depth_m"], bay["section"]), ([14.0, 9.0], 30.0, "hangar"))
        # A fighter's box from the bay's start pose out through the mouth and 60 m on touches nothing of the ship.
        w, h, d = STARFURY
        box = np.array([[x, y, z] for x in (-0.5 * w, 0.0, 0.5 * w) for y in (-2.5, h - 2.5) for z in (-0.5 * d, 0.0, 0.5 * d)])
        for step in np.linspace(0.0, 75.0, 40):
            at = np.array(bay["position"]) + step * np.array(bay["forward"])
            self.assertGreater(float(col.gaps(self.all_shapes, box + at).min()), 0.3, f"{step:.0f} m out of the bay")

    def test_the_engines_share_the_thrust_and_push_forward_from_the_stern(self) -> None:
        self.assertEqual([e["name"] for e in self.hp["engines"]], ["engine_r_1", "engine_r_2", "engine_l_1", "engine_l_2"])
        self.assertAlmostEqual(sum(e["share"] for e in self.hp["engines"]), 1.0, places=9)
        for e in self.hp["engines"]:
            self.assertEqual((e["thrust"], e["exhaust"]), ([0.0, 0.0, -1.0], [0.0, 0.0, 1.0]))
            self.assertAlmostEqual(self.authored(e["position"])[2], LENGTH, delta=0.01)
            self.assertIn(e["section"], ("engine_r", "engine_l"))
        lost = sum(e["share"] for e in self.hp["engines"] if e["section"] == "engine_r")
        self.assertAlmostEqual(lost, 0.5, msg="an engine section lost takes half the thrust")

    def test_the_lights_have_roles_colours_and_ranges(self) -> None:
        roles = {light["role"]: light for light in self.hp["lights"]}
        self.assertEqual(set(roles), {"port", "starboard", "top", "beacon"})
        self.assertGreater(roles["port"]["colour"][0], roles["port"]["colour"][1], "red to port")
        self.assertGreater(roles["starboard"]["colour"][1], roles["starboard"]["colour"][0], "green to starboard")
        self.assertEqual(roles["starboard"]["direction"], [1.0, 0.0, 0.0])
        self.assertTrue(all(light["range_m"] > 0.0 for light in self.hp["lights"]))

    # --- the rotating piece --------------------------------------------------------------------------------------------
    def test_the_rotating_section_turns_on_the_hulls_axis(self) -> None:
        rotor = self.pieces["rotor"]
        np.testing.assert_allclose(self.authored(rotor["pivot"]), (0.0, 0.0, ROTOR_Z), atol=1e-4)
        self.assertEqual(rotor["axis"], [0.0, 0.0, 1.0])
        self.assertGreater(rotor["spin_rad_s"], 0.0)
        self.assertNotIn("pivot", self.pieces["hull"])
        self.assertEqual(self.hp["rotors"], [{"name": "rotor", "piece": "rotor", "pivot": rotor["pivot"], "axis": rotor["axis"],
                                              "spin_rad_s": rotor["spin_rad_s"], "sections": ["habitat"]}])
        v = glb_triangles(self.dir_a / rotor["mesh"]["file"]).reshape(-1, 3)
        self.assertLess(abs(float(v[:, 2].min() + v[:, 2].max())), 1e-3, "its mesh is centred on its pivot")
        self.assertGreaterEqual(float(np.hypot(v[:, 0], v[:, 1]).min()), 9.5 - 1e-3, "nothing of it inside the collar's bore")

    def test_the_spine_runs_through_the_collar_with_room_at_any_turn(self) -> None:
        spine = self.chunk_points("spine") - np.array(self.pieces["rotor"]["pivot"])
        self.assertTrue(float(spine[:, 2].min()) < -11.0 and float(spine[:, 2].max()) > 11.0, "it passes right through")
        self.assertLess(float(np.hypot(spine[:, 0], spine[:, 1]).max()), 9.0, "and clears the bore's 9.5 m all round")
        entry = next(e for e in self.manifest["collision"]["pieces"] if e["name"] == "habitat")
        self.assertEqual(entry["piece"], "rotor")
        own = col.shapes_from_entry(entry)  # in the rotor's frame: on its axis
        axis = np.array([[0.0, 0.0, z] for z in np.linspace(-10.0, 10.0, 9)])
        self.assertGreater(float(col.gaps(own, axis).min()), 9.0, "the collar's bore is open in its collision too")

    # --- collision per section -----------------------------------------------------------------------------------------
    def test_collision_has_a_piece_per_section_inside_the_budget(self) -> None:
        section = self.manifest["collision"]
        manifest_io.validate_collision_section(section)
        self.assertEqual([p["name"] for p in section["pieces"]], list(SECTIONS))
        self.assertEqual((section["max_shapes"], section["max_hull_points"]), (64, 32))
        for piece in section["pieces"]:
            self.assertEqual(piece["piece"], self.sections[piece["name"]]["piece"])
            self.assertLessEqual(len(piece["shapes"]), 64, piece["name"])
            self.assertEqual(len({s["name"] for s in piece["shapes"]}), len(piece["shapes"]), piece["name"])
            self.assertEqual(len(piece["hit_volumes"]), len(piece["shapes"]), "a hit volume a shape")
            self.assertTrue(all(v["type"] in ("box", "capsule") for v in piece["hit_volumes"]))
            self.assertEqual((self.sections[piece["name"]]["shapes"], self.sections[piece["name"]]["hit_volumes"]),
                             (len(piece["shapes"]), len(piece["hit_volumes"])))

    def test_each_sections_own_collision_covers_its_own_skin(self) -> None:
        # What a chunk keeps when it breaks away: its own shapes hold its own mesh.
        for name in SECTIONS:
            gap = col.gaps(self.shapes[name], self.chunk_points(name))
            self.assertLessEqual(float(gap.max()), 1.0, f"{name}: every corner of its mesh within a metre of its own shapes")

    def test_the_whole_collision_covers_the_hull_and_stays_close(self) -> None:
        cover = self.manifest["collision"]["coverage"]
        self.assertEqual((cover["covered"], cover["within_reach"]), (1.0, 1.0))
        self.assertLessEqual(cover["worst_gap_m"], 1.0)
        self.assertLessEqual(cover["worst_excess_m"], 2.5)

    def test_collision_is_mirror_symmetric(self) -> None:
        def row(kind: str, lo: np.ndarray, hi: np.ndarray) -> tuple:
            return (kind, *(np.round(lo, 3) + 0.0), *(np.round(hi, 3) + 0.0))

        rows = {row(s.kind, *s.bounds()) for s in self.all_shapes}
        for s in self.all_shapes:
            if s.name.startswith("light_"):
                continue  # the port and starboard lamps are two parts, not twins
            lo, hi = s.bounds()
            self.assertIn(row(s.kind, np.array([-hi[0], lo[1], lo[2]]), np.array([-lo[0], hi[1], hi[2]])), rows, s.name)

    # --- budget, far, determinism ----------------------------------------------------------------------------------------
    def test_the_hull_is_inside_its_class_budget(self) -> None:
        budget = self.manifest["budget"]
        self.assertEqual(budget["class"], "cruiser")
        # As shipped: the hull's 2 048 px atlas, the rotating section's 1 024 px and the 1 024 px tile.
        self.assertEqual([p.atlas_px for p in ctc.PIECES], [2048, 1024])
        shipped = texture_mb([2048, 1024], 1024)
        self.assertEqual(over_budget("cruiser", budget["triangles"], shipped), [])
        self.assertAlmostEqual(budget["texture_mb"], texture_mb([512, 512], 128), places=2, msg="the manifest records this build's")

    def test_a_far_representation_is_written(self) -> None:
        far = self.manifest["far"]
        self.assertGreater(far["radius_m"], 150.0)
        self.assertLess(far["radius_m"], 160.0)
        self.assertEqual(len(far["areas_m2"]), len(far["directions"]))
        self.assertGreater(max(far["areas_m2"]), 2.0 * min(far["areas_m2"]), "side on it shows far more than end on")

    def test_same_seed_gives_byte_identical_output(self) -> None:
        self.assertEqual(sorted(p.name for p in self.out_a.files), sorted(p.name for p in self.out_b.files))
        for path in self.out_a.files:
            self.assertEqual(sha256(path), sha256(self.dir_b / path.name), path.name)

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, self.assertRaisesRegex(ValueError, "spacing must be positive"):
            ctc.build(BuildContext(Path(tmp), seed=1, options={"spacing": 0.0}))


if __name__ == "__main__":
    unittest.main()
