"""``ea_hyperion`` (M10-T22, Q49, Q53; D12.1): the Hyperion-class heavy cruiser on the capital framework. Files, size, the
sections, the hardpoints against the loadout (16 mounts, three Starfury bays a side in the hangar bump and a shuttle bay in the
tower's aft face, Q58), a symmetric hull,
collision coverage, the class budget, its own style and looks on the fleet's mosaic, the name and the renegades' marks, and each
part's sections against the reference STL (CLAUDE.md, "STL fidelity").

The expected numbers are typed in from docs/assets-capital.md, data/capitals/loadouts.json and the generator's docstring.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS, BUILD_ALONE
from tools.procgen.assets import ea_hyperion as eh
from tools.procgen.core import capital as cap
from tools.procgen.core import hull_decals as hd
from tools.procgen.core import loadout
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.budgets import low_set_mb, over_budget, texture_mb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Mesh
from tools.procgen.parts import capital as cp
from tools.procgen.parts import ea_hyperion as hy
from tools.procgen.parts import ea_hyperion_fidelity as fid
from tools.procgen.styles.ea_capital import LOOKS as OMEGA_LOOKS
from tools.procgen.styles.ea_hyperion import DEFAULT_LOOK, LOOKS, PLATING, ea_hyperion, hyperion_mosaic
from tools.procgen.tests.budget_table import read_budgets
from tools.refview.sections import PASS_IOU, section_score

ROOT = Path(__file__).resolve().parents[3]
STL = ROOT / "references" / fid.REFERENCE
TEST_OPTIONS = {"atlas_px": 512, "detail_px": 128}  # the default sample spacing: the coverage check needs it
LENGTH, SPAN, HEIGHT = 1025.39, 254.4, 319.5  # T01's length; the engine block, the tower's turret to the big pod's interceptor
SECTIONS = ("bow", "magazine", "bridge", "hangar_r", "hangar_l", "truss", "reactor", "spine_aft", "fuel_r", "fuel_l", "engines")
MOUNTS = {"turret": 8, "beam": 2, "missile": 2, "interceptor": 4}
LAUNCHES = {"starfury_ally": 6, "ea_shuttle": 2}


class HyperionBuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name) / "ea_hyperion"
        cls.out = eh.build(BuildContext(cls.dir, seed=42, options=TEST_OPTIONS))
        cls.manifest = manifest_io.read_manifest(cls.dir)
        cls.hp = json.loads((cls.dir / "hardpoints.json").read_text(encoding="utf-8"))
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.sections = {s["name"]: s for s in cls.manifest["sections"]}

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def authored(self, v: list[float]) -> np.ndarray:
        """A body-frame point in the generator's frame (the bow guns' muzzles at z = 0, the hull's axis on x = 0)."""
        return np.array(v) + self.offset

    def test_registered_built_alone_and_covered(self) -> None:
        self.assertIs(ASSETS["ea_hyperion"], eh.build)
        self.assertIn("ea_hyperion", BUILD_ALONE, "a 4 096 px atlas: built alone")
        self.assertEqual(self.out.warnings, (), "the collision covers the hull")
        manifest_io.validate_manifest(self.manifest)
        cover = self.manifest["collision"]["coverage"]
        self.assertEqual((cover["covered"], cover["within_reach"]), (1.0, 1.0))

    def test_size(self) -> None:
        dims = self.manifest["dimensions_m"]
        self.assertAlmostEqual(dims["length"], LENGTH + hy.ARRAY_SHIFT, places=2, msg="the hull and the antenna array ahead of its bow")
        self.assertAlmostEqual(dims["span"], SPAN, delta=0.01 * SPAN)
        self.assertAlmostEqual(dims["height"], HEIGHT, delta=0.01 * HEIGHT)

    def test_the_sections(self) -> None:
        self.assertEqual(tuple(self.sections), SECTIONS)
        self.assertAlmostEqual(sum(s["hull_share"] for s in self.sections.values()), 1.0, places=9)
        for name in ("magazine", "fuel_r", "fuel_l", "reactor"):
            self.assertGreater(self.sections[name]["blast_energy_j"], 0.0, name)
        self.assertEqual(list(self.manifest["pieces"]), ["hull"], "no rotating section")

    def test_the_mounts_and_bays_are_the_loadouts(self) -> None:
        self.assertEqual(loadout.problems(self.hp, loadout.read(), "ea_hyperion"), [])
        kinds: dict[str, int] = {}
        for w in self.hp["weapons"]:
            kinds[w["kind"]] = kinds.get(w["kind"], 0) + 1
        self.assertEqual(kinds, MOUNTS)
        launched: dict[str, int] = {}
        for bay in self.hp["bays"]:
            launched[bay["craft"]] = launched.get(bay["craft"], 0) + bay["capacity"]
            if bay["craft"] == "starfury_ally":
                self.assertIn(bay["section"], ("hangar_r", "hangar_l"))
                self.assertEqual(bay["capacity"], 1, "one Starfury per bay, re-docking in its own")
                side = 1.0 if bay["section"] == "hangar_r" else -1.0
                self.assertGreater(side * (bay["exit"][0] - bay["position"][0]), 0.0, f"{bay['name']} opens outward through the bump's flank")
            else:
                self.assertEqual(bay["section"], "bridge")
                self.assertGreater(bay["exit"][2] - bay["position"][2], 0.0, "the shuttle bay opens aft, over the Starfury bays")
                exit_z = float(self.authored(bay["exit"])[2])
                self.assertAlmostEqual(exit_z, hy.TOWER_Z[1], delta=0.5, msg="in the tower's aft face")
        self.assertEqual(launched, LAUNCHES)
        self.assertEqual(len(self.hp["bays"]), 7, "six Starfury bays and one shuttle bay")
        heavy = [w for w in self.hp["weapons"] if w["weapon"] == "ea_plasma_heavy"]
        self.assertTrue(all(w["traverse_deg"] <= 5.0 for w in heavy), "the heavy plasma cannons are fixed forward (X)")

    def test_engines_lights_and_bay_lights(self) -> None:
        engines = self.hp["engines"]
        self.assertEqual(len(engines), 3)
        self.assertAlmostEqual(sum(e["share"] for e in engines), 1.0)
        xs = sorted(float(self.authored(e["position"])[0]) for e in engines)
        np.testing.assert_allclose(xs, sorted(eh.hy.NOZZLE_XS), atol=1e-3)
        self.assertAlmostEqual(xs[0], -xs[2], msg="the bells stand symmetric about the hull's axis")
        roles = sorted(light["role"] for light in self.hp["lights"])
        self.assertEqual(roles, ["bay"] * 7 + ["beacon", "beacon"] + ["flood"] * 7 + ["port", "starboard", "top"],
                         "one red light in each bay and the seven flood lamps")
        port = next(light for light in self.hp["lights"] if light["role"] == "port")
        self.assertLess(port["position"][0], 0.0, "red to port")

    def test_the_renegades_red_x_marks_are_for_renegades_only(self) -> None:
        xs = [m for m in self.hp["marks"] if m.get("text") == "X"]
        self.assertEqual(sorted(m["name"] for m in xs), ["mark_x_l", "mark_x_r", "mark_x_roof"], "one on each flank of the tower, one on the deck")
        for m in xs:
            self.assertEqual(m["only_faction"], "renegades")
            self.assertGreater(m["colour"][0], 0.6)
            self.assertLess(m["colour"][1], 0.2)

    def test_the_ship_wears_its_name_on_the_roof_and_the_tower(self) -> None:
        names = {m["name"]: m for m in self.hp["marks"] if m.get("text") == "name"}
        self.assertEqual(sorted(names), ["mark_name_l", "mark_name_r", "mark_name_roof"], "as the stills paint HYPERION")
        for m in names.values():
            self.assertNotIn("only_faction", m, "every faction's hull carries its name")
        for key in ("mark_name_r", "mark_name_l"):
            self.assertGreater(names[key]["colour"][2], names[key]["colour"][0], "the tower's in the bands' blue")
        self.assertGreater(min(names["mark_name_roof"]["colour"]), 0.8, "light across the bow's roof")
        self.assertTrue(names["mark_name_roof"].get("outline"), "outlined in black, as the stills print it")
        self.assertNotIn("outline", names["mark_name_r"], "the tower's name is not")
        numbers = [m for m in self.hp["marks"] if m.get("text") == "number"]
        self.assertTrue(numbers and all(m.get("outline") for m in numbers), "the hull number is outlined too")
        self.assertTrue(all(min(m["colour"]) > 0.8 for m in numbers), "the hull number is white, like the bow's name (Q65)")
        self.assertTrue((self.dir / self.hp["mark_atlas"]["outlined_file"]).is_file(), "the outlined print is written beside the plain one")
        roof_z = float(self.authored(names["mark_name_roof"]["position"])[2])
        self.assertTrue(hy.BOW_Z < roof_z < hy.FORE_BANDS[0][0], "between the bow face and the bow band")
        muzzle = min(float(m.part.mesh.bounds()[0][2]) for m in eh.modules() if m.name == "particle_top")
        self.assertLess(roof_z + 0.5 * hy.NAME_HEIGHT_M["roof"], muzzle, "ahead of the top cannon, so its barrels never hide it")
        self.assertGreater(roof_z - 0.5 * hy.NAME_HEIGHT_M["roof"], hy.NOSE_RING[1], "on grey, behind the nose ring")
        r, l = self.authored(names["mark_name_r"]["position"]), self.authored(names["mark_name_l"]["position"])
        self.assertAlmostEqual(float(r[0]), -float(l[0]), places=3)
        self.assertGreater(float(r[1]), hy.ROOF_Y + 10.0, "on the tower, above the roof")

    def test_the_emblem_is_a_sharp_picture_on_both_tower_flanks_under_the_name(self) -> None:
        """The maintainer's call: drawn by the game from its own image, not baked into the hull at the plating's texels."""
        self.assertFalse([m for _, m in eh.spec().markings if m.kind == "emblem"], "no emblem baked into the hull")
        emblems = [m for m in self.hp["marks"] if "image" in m]
        self.assertEqual(sorted(m["name"] for m in emblems), ["mark_emblem_l", "mark_emblem_r"])
        name = next(m for m in self.hp["marks"] if m["name"] == "mark_name_r")
        name_at = self.authored(name["position"])
        for e in emblems:
            at, normal = self.authored(e["position"]), np.asarray(e["normal"])
            self.assertGreater(abs(float(normal[0])), 0.99, "on a flank")
            self.assertAlmostEqual(abs(float(at[0])), abs(float(name_at[0])), delta=1.0, msg="on the tower's face")
            self.assertAlmostEqual(float(at[2]), float(name_at[2]), places=3, msg="centred under the name")
            self.assertAlmostEqual(e["width_m"] / e["height_m"], hd.DESIGN_W / hd.DESIGN_H, places=2)
            self.assertLess(float(at[1]) + 0.5 * e["height_m"], float(name_at[1]) - 0.5 * hy.NAME_HEIGHT_M["tower"], "below the name")
            self.assertGreater(float(at[1]) - 0.5 * e["height_m"], hy.ROOF_Y, "above the bow's roof")
            self.assertTrue((self.dir / e["image"]).is_file() and (self.dir / (e["image"] + ".import")).is_file())
            self.assertTrue((self.dir / e["glow"]["file"]).is_file(), "lit by the lamp under it")
            self.assertGreater(e["glow"]["energy"], 0.0)

    def test_the_floods_lamps_stand_where_their_pools_are_thrown_from(self) -> None:
        lamps = [light for light in self.hp["lights"] if light["role"] == "flood"]
        pools = [m for _, m in eh.spec().markings if m.kind == "flood"]
        thrown = {tuple(np.round(p.params["centre"], 3)) for p in pools}
        self.assertEqual((len(lamps), len(thrown)), (7, 5), "a pool for each tower and roof lamp; the bow's two light the array")
        for pool in pools:
            lamp = min(lamps, key=lambda light: float(np.linalg.norm(self.authored(light["position"]) - np.asarray(pool.params["centre"]))))
            self.assertLess(float(np.linalg.norm(self.authored(lamp["position"]) - np.asarray(pool.params["centre"]))), 2.0, lamp["name"])
            self.assertGreater(float(np.dot(lamp["direction"], pool.params["direction"])), 0.99, "the lamp shines where its pool is")
        bow = [light for light in lamps if light["name"].startswith("flood_bow")]
        self.assertEqual(len(bow), 2)
        for light in bow:
            self.assertLess(float(light["direction"][2]), -0.99, "the bow's lamps shine ahead")

    def test_a_lamp_under_each_emblem_shines_up_onto_it_and_one_lights_the_bows_name(self) -> None:
        lamps = {light["name"]: light for light in self.hp["lights"] if light["role"] == "flood"}
        emblem = next(m for m in self.hp["marks"] if m["name"] == "mark_emblem_r")
        under = lamps["flood_emblem_r"]
        at, centre = self.authored(under["position"]), self.authored(emblem["position"])
        self.assertAlmostEqual(float(at[2]), float(centre[2]), delta=0.5, msg="directly below the emblem")
        self.assertLess(float(at[1]), float(centre[1]) - 0.5 * emblem["height_m"], "under it")
        self.assertGreater(float(under["direction"][1]), 0.7, "shining up")
        self.assertTrue(hy.SPONSON_Z[1] < float(centre[2]) - 0.5 * hy.EMBLEM_WIDTH_M and float(centre[2]) + 0.5 * hy.EMBLEM_WIDTH_M < hy.TOWER_Z[1],
                        "the emblem is on the smooth flank, aft of the forward hull and the sponson")
        bow = lamps["flood_name_roof"]
        name = next(m for m in self.hp["marks"] if m["name"] == "mark_name_roof")
        lamp_at, name_at = self.authored(bow["position"]), self.authored(name["position"])
        self.assertAlmostEqual(float(lamp_at[0]), 0.0, places=3)
        self.assertTrue(hy.BOW_Z < float(lamp_at[2]) < float(name_at[2]), "at the front of the roof, ahead of the name")
        self.assertGreater(float(bow["direction"][2]), 0.9, "shining aft over it")
        self.assertIn("flood_name_roof_bracket", {m.name for m in eh.modules()}, "it stands on a post")

    def test_every_bay_has_a_shut_roll_up_door_and_no_glowing_rim(self) -> None:
        doors = {d["name"]: d for d in self.hp["doors"]}
        self.assertEqual(len(doors), 7, "six Starfury bays and the shuttle bay")
        for bay in self.hp["bays"]:
            door = doors[bay["name"] + "_door"]
            self.assertEqual(door["section"], bay["section"])
            shut, mouth = np.asarray(door["position"]), np.asarray(bay["exit"])
            out = np.asarray(door["forward"])
            self.assertAlmostEqual(float(out @ np.asarray(bay["forward"])), 1.0, places=5, msg="it faces out of the bay")
            self.assertGreater(float((shut - mouth) @ out), 0.0, "shut, it is just outside the mouth")
            self.assertLess(float(np.linalg.norm((shut - mouth) - ((shut - mouth) @ out) * out)), 0.5 * bay["mouth_m"][1], "over the mouth")
            self.assertGreaterEqual(door["size_m"][1], bay["mouth_m"][1], "it covers the whole mouth")
            self.assertGreaterEqual(door["slats"], 4)
        lamps = [m for m in self.hp["lights"] if m["role"] == "bay"]
        self.assertEqual(len(lamps), 7, "the red stays inside: one light a bay")

    def test_the_hull_number_is_painted_on_both_flanks_aft_of_the_bow_band(self) -> None:
        nums = {m["name"]: m for m in self.hp["marks"] if m.get("text") == "number"}
        self.assertEqual(sorted(nums), ["mark_number_l", "mark_number_r"])
        r, l = self.authored(nums["mark_number_r"]["position"]), self.authored(nums["mark_number_l"]["position"])
        self.assertAlmostEqual(float(r[0]), -float(l[0]), places=3)
        self.assertTrue(hy.FORE_BANDS[0][1] < hy.NUMBER_Z < 263.0, "between the bow band and the flank dome turret")
        n = np.asarray(nums["mark_number_r"]["normal"])
        self.assertGreater(float(n[0]), 0.98, "on the starboard flank")
        # Every digit stands proud of the widening flank: the mark's plane is outside the hull at both ends of the number.
        tangent = np.array([-n[2], 0.0, n[0]])
        for end in (-1.0, 1.0):
            p = r + end * 0.6 * hy.NUMBER_HEIGHT_M * tangent
            self.assertGreater(float(p[0]) + 0.6, hy._lerp(float(p[2]), hy.HALF_W), f"the {'fore' if end < 0 else 'aft'} digit is clear of the hull")

    def test_the_bands_wrap_the_hull_belly_included(self) -> None:
        keels = hy.keel(ea_hyperion(DEFAULT_LOOK).style)
        ends = {round(float(m.part.mesh.bounds()[1][2]), 1) for m in keels}
        self.assertIn(hy.FORE_BANDS[0][1], ends, "the keel is cut at the bow band so the ring closes under the belly")

    def test_both_bands_are_painted_round_the_hull_and_the_nose_is_grey(self) -> None:
        hull = hy.fore_hull(ea_hyperion(DEFAULT_LOOK).style)
        painted = [m for m in hull if m.name.startswith("fore_band_")]
        nose = min(hull, key=lambda m: float(m.part.mesh.bounds()[0][2]))
        self.assertTrue(nose.name.startswith("fore_hull_"), "the maintainer's call: the face is hull grey, as the stills paint it")
        self.assertLess(float(nose.part.mesh.bounds()[1][2]) - hy.BOW_Z, 0.5, "a thin grey lip only")
        ring = [m for m in hull if m.name in ("nose_ring_lip", "nose_ring")]
        self.assertEqual((round(min(float(m.part.mesh.bounds()[0][2]) for m in ring), 2), round(max(float(m.part.mesh.bounds()[1][2]) for m in ring), 2)),
                         hy.NOSE_RING, "the blue ring round the nose, just behind the face")
        face = next(m for m in hull if m.name == "nose_face")
        grey = {ea_hyperion(DEFAULT_LOOK).style.material(r).name for r in ("hull", "hull_panel")}
        self.assertLessEqual({m.name for m in face.part.mesh.materials}, grey, "the recess's floor is grey too")
        self.assertGreater(min(float(m.part.mesh.bounds()[0][2]) for m in painted), hy.BOW_Z + 30.0, "no band near the face")
        for lo, hi in hy.FORE_BANDS:
            inside = [m for m in painted if lo - 0.01 <= float(m.part.mesh.bounds()[0][2]) and float(m.part.mesh.bounds()[1][2]) <= hi + 0.01]
            self.assertTrue(inside, f"the band from {lo} to {hi} m is painted")

    def test_the_hull_is_inside_the_capital_budget(self) -> None:
        budget = self.manifest["budget"]
        self.assertEqual(budget["class"], "capital")
        row = read_budgets()["capital"]
        self.assertLessEqual(budget["triangles"], row.triangles)
        self.assertEqual([p.atlas_px for p in eh.PIECES], [4096])
        self.assertEqual(over_budget("capital", budget["triangles"], texture_mb([4096], 1024), low_set_mb([4096], 1024)), [])
        self.assertAlmostEqual(budget["texture_mb"], texture_mb([512], 128), delta=0.01, msg="this build's")


class HyperionSpecTests(unittest.TestCase):
    def test_the_spec_has_no_problems_in_any_look(self) -> None:
        for look in LOOKS:
            self.assertEqual(cap.problems(eh.spec(look)), [], look)

    def test_the_hull_is_symmetric(self) -> None:
        """The maintainer's call: every centre part sits on the axis, and the only lone parts are the running lights, the two
        ventral interceptors (one on each pod, the loadout's count) and the front antenna array (lopsided, as the first STL's)."""
        lone = sorted(m.name for m in eh.modules() if m.side == cp.LONE)
        self.assertEqual(lone, ["front_array", "interceptor_pod_1", "interceptor_pod_2", "light_port", "light_starboard"])
        for m in eh.modules():
            if m.side != cp.CENTRE or m.part.mesh.vertices.size == 0:
                continue
            lo, hi = m.part.mesh.bounds()
            self.assertAlmostEqual(float(lo[0]), -float(hi[0]), delta=0.05, msg=f"{m.name} is off the axis")

    def test_the_nose_face_is_recessed_inside_a_lip(self) -> None:
        """The maintainer's call, after the V5c's nose: the face's centre set back inside a lip round its edge."""
        hull = hy.fore_hull(ea_hyperion(DEFAULT_LOOK).style)
        face = next(m for m in hull if m.name == "nose_face")
        self.assertAlmostEqual(float(face.part.mesh.bounds()[1][2]), hy.BOW_Z + hy.NOSE_RECESS_M, places=3, msg="the floor, set back")
        self.assertAlmostEqual(hy.NOSE_RECESS_M, 3.26, delta=0.05, msg="as deep as the V5c's")
        lip = [m for m in hull if float(m.part.mesh.bounds()[1][2]) <= hy.NOSE_FLOOR_Z + 1e-6 and m.name != "nose_face"]
        self.assertEqual(sorted(m.name for m in lip), ["fore_hull_1", "nose_ring_lip"], "grey at the face, the ring's blue behind it")
        outline, recess = np.asarray(hy.fore_outline(hy.BOW_Z)), np.asarray(hy.nose_recess())
        for k in (0, 1):
            self.assertAlmostEqual(float(outline[:, k].max() - recess[:, k].max()), hy.NOSE_LIP_M, places=3, msg="the lip's width")
        for m in lip:
            verts = m.part.mesh.vertices
            front = verts[np.abs(verts[:, 2] - hy.BOW_Z) < 1e-6] if m.name == "fore_hull_1" else verts
            near_axis = front[(np.abs(front[:, 0]) < 20.0) & (np.abs(front[:, 1] + 5.0) < 10.0)]
            self.assertEqual(len(near_axis), 0, f"{m.name} leaves the face's centre open")

    def test_every_antenna_rod_roots_inside_the_recess(self) -> None:
        """The maintainer's call: the first STL's array, lowered a little, every rod rooted in the recess's floor, none above the roof."""
        face = np.asarray(hy.nose_recess())
        edges = list(zip(face, np.roll(face, -1, axis=0)))
        array = next(m for m in eh.modules() if m.name == "front_array")
        lo, hi = array.part.mesh.bounds()
        self.assertLessEqual(float(hi[1]), hy.ROOF_Y - 2.0, "no rod stands above the roof")
        self.assertGreater(float(hi[2]), hy.NOSE_FLOOR_Z, "into the floor")
        self.assertEqual(hy.ARRAY_DROP, hy.ROOF_Y - 29.2 - hy.ARRAY_LOWER_M)
        for x, y_old, stages in hy.ARRAY_RODS:
            r = max(radius for _, radius in stages)
            for dx, dy in ((r, 0.0), (-r, 0.0), (0.0, r), (0.0, -r)):
                p = np.array([x + dx, y_old + hy.ARRAY_DROP + dy])
                sides = [np.sign((b - a)[0] * (p - a)[1] - (b - a)[1] * (p - a)[0]) for a, b in edges]
                self.assertTrue(all(v >= 0 for v in sides) or all(v <= 0 for v in sides), f"the rod at x={x} roots in the recess")

    def test_every_gun_barrel_is_plain_smooth_metal(self) -> None:
        """The maintainer's call: no weathering on the barrels (the turrets', the particle cannons' and the array's rods)."""
        style = ea_hyperion(DEFAULT_LOOK).style
        for role in ("barrel", "bore"):
            self.assertTrue(style.material(role).smooth, role)
        self.assertFalse(style.material("hull").smooth)
        for name in ("pulse_deck", "particle_top", "front_array"):
            m = next(m for m in eh.modules() if m.name == name)
            guns = {mat.name for mat in m.part.mesh.materials} - {style.material(r).name for r in ("hull_dark", "hull_panel", "hull")}
            self.assertTrue(guns and all(style.materials[r].smooth for r in style.materials if style.materials[r].name in guns), name)

    def test_a_forward_dish_hangs_under_the_crown_saucer(self) -> None:
        """Both STLs have it; measured off the V5c: a flat face 11.3 m in radius at 346.1 m, square to the bow."""
        parts = {m.name: m for m in eh.modules()}
        dish = parts["tower_dish_fwd"]
        lo, hi = dish.part.mesh.bounds()
        self.assertAlmostEqual(float(lo[2]), hy.DISH_FWD_Z, places=2, msg="its face forward")
        self.assertAlmostEqual(float(hi[1] - lo[1]) / 2.0, hy.DISH_FWD_R, delta=0.1)
        self.assertAlmostEqual(float(hi[0]), -float(lo[0]), places=3, msg="on the axis")
        saucer = parts["tower_dish"].part.mesh.bounds()
        self.assertLess(float(hi[1]), float(saucer[0][1]), "under the saucer")
        self.assertGreater(float(parts["tower_dish_post"].part.mesh.bounds()[1][1]), float(saucer[0][1]), "its post reaches the saucer")
        self.assertLess(float(parts["tower_dish_feed"].part.mesh.bounds()[0][2]), hy.DISH_FWD_Z - 9.0, "its feed ahead of it")
        self.assertEqual({parts[n].section for n in ("tower_dish_fwd", "tower_dish_feed", "tower_dish_boom", "tower_dish_post")}, {"bridge"})

    def test_its_own_style_and_looks(self) -> None:
        self.assertEqual(sorted(LOOKS), ["a", "b", "c"])
        self.assertEqual(DEFAULT_LOOK, "a", "the maintainer's")
        self.assertNotIn(DEFAULT_LOOK, PLATING, "look A wears the Hyperion's own mosaic")
        self.assertEqual(ea_hyperion(DEFAULT_LOOK).skin, hyperion_mosaic(LOOKS[DEFAULT_LOOK]))
        self.assertEqual(sorted(PLATING), ["b", "c"])
        style = ea_hyperion(DEFAULT_LOOK)
        self.assertTrue(style.name.startswith("ea_hyperion_"))
        self.assertTrue(all(m.name.startswith("eah_") for m in style.style.materials.values() if not m.name.startswith("lamp")))
        omega_paint = {look.paint["hull"] for look in OMEGA_LOOKS.values()}
        for key, look in LOOKS.items():
            self.assertNotIn(look.paint["hull"], omega_paint, f"look {key} is not an Omega grey")
            self.assertIn("bay_light", ea_hyperion(key).style.materials, "the fleet's red-lit bays")
        marked = ea_hyperion(DEFAULT_LOOK, livery={"stripe": 0x101010}).style
        self.assertNotEqual(style.style.material("stripe").albedo, marked.material("stripe").albedo, "the livery repaints its role")
        with self.assertRaises(ValueError):
            ea_hyperion("d")


@unittest.skipUnless(STL.is_file(), "the reference STL is gitignored; it is on the maintainer's machine")
class HyperionSectionTests(unittest.TestCase):
    """Each part's sections against the STL: IoU >= 0.90, or an exemption with its accepted reason."""

    @classmethod
    def setUpClass(cls) -> None:
        from tools.refview import refview  # noqa: PLC0415

        raw, _ = refview.read_stl(STL)
        axes = fid.REFERENCE_MAPPING
        model, _ = refview.to_ship_frame(raw, refview.frame_matrix(axes["right"], axes["up"], axes["aft"]), LENGTH)
        cls.stl = np.asarray(model).reshape(-1, 3, 3)
        mesh = Mesh.concatenate([m.part.mesh for m in cp.with_twins(eh.modules())])
        cls.model = mesh.vertices[mesh.faces]

    def test_every_part_passes(self) -> None:
        for part, planes in fid.PLANES.items():
            with self.subTest(part=part):
                reference = fid.reference_for(part, self.stl)
                failures = [f"{p.name} {s.iou:.3f}" for p in planes if (s := section_score(reference, self.model, p)).iou < PASS_IOU
                            and p.name not in fid.EXEMPT]
                self.assertEqual(failures, [], f"{part}: sections under {PASS_IOU}")

    def test_every_part_has_its_axis(self) -> None:
        self.assertEqual(sorted(fid.PART_AXIS_X), sorted(fid.PLANES))

    def test_every_exemption_names_a_plane_and_a_reason(self) -> None:
        names = {p.name for planes in fid.PLANES.values() for p in planes}
        for name, reason in fid.EXEMPT.items():
            self.assertIn(name, names)
            self.assertGreater(len(reason), 20, name)


if __name__ == "__main__":
    unittest.main()
