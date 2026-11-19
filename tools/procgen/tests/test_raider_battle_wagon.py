"""``raider_battle_wagon`` (M8-T09, D83; M7's D73): files, the mesh contract with an atlas per chunk, frames, symmetry, chunk
cuts, the hardpoint contract (two launch tubes with four lanes and twenty berths, eight turret mounts, four missile racks,
eight nozzles, the jump point), the compound collision (budget, coverage, the tubes and the ring open, a Delta-V's way down
every lane), the surface and determinism.

The expected numbers are typed in from docs/assets-capital.md and docs/design-references.md ("Raider Battle Wagon"), not read
from the generator.
"""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import raider_battle_wagon as rbw
from tools.procgen.core import collision as col
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.glb import read_glb
from tools.procgen.core.obj import read_obj
from tools.procgen.styles.raider_capital import WAGON_SURFACE
from tools.procgen.tests.mesh_checks import MAP_KEYS, assert_chunks_cut_the_hull, assert_hull_mesh, assert_mirror_symmetric

TEST_OPTIONS = {"atlas_scale": 0.25, "spacing": 2.0}
CHUNKS = ("bow", "core", "ring", "tube_upper", "tube_lower", "engines")
TRIANGLE_BUDGET = 20_000  # 9 948 as built; the importer adds the levels of detail
LENGTH, SPAN, HEIGHT = 275.0, 160.6, 160.6  # over the antenna spikes; the ring's outer rim both ways
RING_STATION, RING_INNER_R, RING_OUTER_R = 157.3, 58.0, 80.3  # m from the spikes' tips; the ring's opening and rim
TUBE_Y, TUBE_Z = 45.65, (69.85, 246.95)  # a tube's axis above the ship's, its bow and stern mouths
TUBE_CLEAR = (19.44, 3.66)  # the clear way through at the axis level: half width, and half height at the walls
LANE_X = 9.7
BERTH_ROWS, BERTH_FIRST, BERTH_PITCH = 5, 14.0, 12.0
EXIT_M, ENTRY_M = 20.0, 40.0  # a lane's ends: ahead of the bow mouth, behind the stern mouth
DELTA_V = (17.0, 2.01, 7.2)  # the raider fighter's box: span, height, length (docs/assets-raider.md)
TURRET_X, TURRET_Y, TURRET_Z = (47.575, 46.75), 3.9875, (111.375, 204.875)  # the mounts on the arms: fore, aft
RACK_CLOCKS = (45, 135, 225, 315)
NOZZLE_X, NOZZLE_Y = (7.15, 21.725), 11.4125


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def box_points(size: tuple[float, float, float], spacing: float) -> np.ndarray:
    """Points over a box's surface, the box centred on x and z and standing on y = 0."""
    axes = [np.linspace(-0.5 * s, 0.5 * s, max(2, round(s / spacing) + 1)) for s in size]
    axes[1] = axes[1] + 0.5 * size[1]
    grid = np.stack(np.meshgrid(*axes, indexing="ij"), axis=-1).reshape(-1, 3)
    edge = np.zeros(len(grid), dtype=bool)
    for k in range(3):
        edge |= np.isclose(grid[:, k], axes[k][0]) | np.isclose(grid[:, k], axes[k][-1])
    return grid[edge]


class RaiderBattleWagonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = rbw.build(BuildContext(cls.dir_a, seed=42, options=TEST_OPTIONS))
        cls.out_b = rbw.build(BuildContext(cls.dir_b, seed=42, options=TEST_OPTIONS))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.hp = json.loads((cls.dir_a / rbw.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / rbw.OBJ_NAME)
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.shapes = col.shapes_of(cls.manifest["collision"])  # body frame

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def authored(self, v: list[float]) -> np.ndarray:
        """A hardpoint back in the design references' frame (the antenna spikes' tips at z = 0, x and y on the axis)."""
        return np.array(v) + self.offset

    # --- files, manifest, budgets ------------------------------------------------------------------------------------
    def test_registered_and_named(self) -> None:
        self.assertIs(ASSETS["raider_battle_wagon"], rbw.build)
        self.assertEqual(self.out_a.asset_id, "raider_battle_wagon")
        self.assertEqual(self.out_a.warnings, (), "the collision covers the hull")

    def test_all_files_are_written_and_listed(self) -> None:
        on_disk = {p.name for p in self.dir_a.iterdir()}
        self.assertEqual({p.name for p in self.out_a.files}, on_disk)
        for name in ("manifest.json", "hardpoints.json", "raider_battle_wagon.glb", "raider_battle_wagon.obj", "raider_battle_wagon_turret.glb"):
            self.assertIn(name, on_disk)
        manifest_io.validate_manifest(self.manifest)

    def test_the_hull_is_its_textured_mesh_inside_the_budget(self) -> None:
        assert_hull_mesh(self, self.dir_a, self.manifest, rbw.OBJ_NAME)
        self.assertLessEqual(self.manifest["mesh"]["triangles"], TRIANGLE_BUDGET)

    def test_every_chunk_has_its_own_atlas_and_surface(self) -> None:
        mesh = self.manifest["mesh"]
        self.assertEqual([a["chunk"] for a in mesh["atlases"]], list(CHUNKS))
        self.assertEqual([s["name"] for s in mesh["surfaces"]], [f"hull_{chunk}" for chunk in CHUNKS])
        drawn = [p.material for p in read_glb(self.dir_a / mesh["file"]).primitives if len(p.indices)]
        self.assertEqual(drawn, [f"hull_{chunk}" for chunk in CHUNKS], "the hull's file draws each chunk with its own maps")
        for chunk, surface, atlas in zip(CHUNKS, mesh["surfaces"], mesh["atlases"], strict=True):
            self.assertEqual(surface["albedo"], f"raider_battle_wagon_{chunk}_albedo.png")
            self.assertLessEqual(atlas["atlas_px"], 2048, "no bake above 2 048 px: its memory goes with the atlas's texels")
            self.assertFalse((self.dir_a / f"raider_battle_wagon_{chunk}.glb").exists(), "a chunk's faces are in the hull's file")
        self.assertEqual(mesh["texel_m"], max(a["texel_m"] for a in mesh["atlases"]))

    def test_low_and_high_texture_sets_are_written(self) -> None:
        for surface in self.manifest["mesh"]["surfaces"]:
            low = surface["detail"]["low"]
            for key in ("albedo", "normal", "orm"):
                self.assertTrue((self.dir_a / low[key]).is_file(), key)
            for key in MAP_KEYS:
                self.assertTrue((self.dir_a / surface[key]).is_file(), key)
        core = self.manifest["mesh"]["surfaces"][1]  # the plated core: its drawn seams differ between the sets
        self.assertNotEqual(sha256(self.dir_a / core["detail"]["low"]["albedo"]), sha256(self.dir_a / core["albedo"]))

    def test_dimensions_match_the_design(self) -> None:
        dims = self.manifest["dimensions_m"]
        self.assertAlmostEqual(dims["length"], LENGTH, places=2)
        self.assertAlmostEqual(dims["span"], SPAN, delta=0.1)
        self.assertAlmostEqual(dims["height"], HEIGHT, delta=0.1)

    def test_the_spikes_lead_the_ring_is_aft_of_the_middle_and_the_nozzles_end_it(self) -> None:
        v = self.obj.vertices + self.offset
        self.assertAlmostEqual(float(v[:, 2].min()), 0.0, places=3)
        self.assertAlmostEqual(float(v[:, 2].max()), LENGTH, places=2)
        rim = v[np.hypot(v[:, 0], v[:, 1]) > 79.0]  # only the ring's rim reaches this far out
        self.assertGreater(float(rim[:, 2].min()), 0.5 * LENGTH, "the ring stands just aft of the middle")
        self.assertLess(float(rim[:, 2].max()), 0.62 * LENGTH)
        self.assertAlmostEqual(float(np.hypot(v[:, 0], v[:, 1]).max()), RING_OUTER_R, delta=0.05)
        self.assertAlmostEqual(2.0 * RING_OUTER_R / LENGTH, 0.584, delta=0.005, msg="the ring is 0.58 of the length across")

    def test_the_mesh_is_mirror_symmetric_in_x(self) -> None:
        assert_mirror_symmetric(self, self.obj.vertices, "hull")

    def test_chunks_cut_the_hull_and_have_joints(self) -> None:
        assert_chunks_cut_the_hull(self, self.dir_a, self.manifest, self.hp, CHUNKS)
        lo, hi = np.array(self.manifest["aabb_min"]), np.array(self.manifest["aabb_max"])
        for chunk in self.hp["chunks"]:
            joint = np.array(chunk["joint"])
            self.assertTrue(np.all(joint >= lo) and np.all(joint <= hi), chunk["name"])

    # --- hardpoints --------------------------------------------------------------------------------------------------
    def test_hardpoints_schema(self) -> None:
        for key in ("mass_kg", "center_of_mass", "cockpit_camera", "chase_anchor", "muzzles", "pods", "rcs", "collision", "nav_lights",
                    "turrets", "missile_racks", "cradles", "tubes", "jump_point", "chunks"):  # fmt: skip
            self.assertIn(key, self.hp)
        self.assertEqual(self.hp["muzzles"], [], "its guns are its turrets")
        self.assertEqual(self.hp["length_m"], self.manifest["dimensions_m"]["length"])

    def test_two_tubes_above_and_below_with_two_lanes_each(self) -> None:
        tubes = self.hp["tubes"]
        self.assertEqual([t["name"] for t in tubes], ["upper", "lower"])
        self.assertEqual((self.manifest["tube_count"], self.manifest["lane_count"]), (2, 4))
        for tube, sign in zip(tubes, (1.0, -1.0), strict=True):
            np.testing.assert_allclose(self.authored(tube["mouth_fore"]), [0.0, sign * TUBE_Y, TUBE_Z[0]], atol=0.01)
            np.testing.assert_allclose(self.authored(tube["mouth_aft"]), [0.0, sign * TUBE_Y, TUBE_Z[1]], atol=0.01)
            np.testing.assert_allclose(tube["clear_half_m"], TUBE_CLEAR, atol=0.01)
            self.assertEqual((tube["forward"], tube["up"]), ([0.0, 0.0, -1.0], [0.0, 1.0, 0.0]))
            self.assertEqual([lane["name"] for lane in tube["lanes"]], [f"{tube['name']}_r", f"{tube['name']}_l"])
            for lane, x in zip(tube["lanes"], (LANE_X, -LANE_X), strict=True):
                np.testing.assert_allclose(self.authored(lane["exit"]), [x, sign * TUBE_Y, TUBE_Z[0] - EXIT_M], atol=0.01)
                np.testing.assert_allclose(self.authored(lane["approach_from"]), [x, sign * TUBE_Y, TUBE_Z[1] + ENTRY_M], atol=0.01)
                self.assertEqual(len(lane["berths"]), BERTH_ROWS)
        self.assertLess(2.0 * (LANE_X + 0.5 * DELTA_V[0]), 2.0 * TUBE_CLEAR[0], "two Delta-Vs abreast fit the tube")

    def test_twenty_berths_row_by_row_from_the_bow_mouths(self) -> None:
        cradles = self.hp["cradles"]
        self.assertEqual(len(cradles), 4 * BERTH_ROWS)
        self.assertEqual(self.manifest["cradle_count"], 20)
        self.assertEqual(len({c["name"] for c in cradles}), 20)
        self.assertEqual([c["row"] for c in cradles], [row for row in range(1, BERTH_ROWS + 1) for _ in range(4)], "the front row first")
        self.assertEqual([c["name"] for c in cradles[:4]], ["upper_r_1", "upper_l_1", "lower_r_1", "lower_l_1"])
        named = {name for tube in self.hp["tubes"] for lane in tube["lanes"] for name in lane["berths"]}
        self.assertEqual(named, {c["name"] for c in cradles})
        for c in cradles:
            at = self.authored(c["position"])
            sign = 1.0 if c["tube"] == "upper" else -1.0
            x = LANE_X if c["lane"].endswith("_r") else -LANE_X
            want = [x, sign * TUBE_Y - 1.0, TUBE_Z[0] + BERTH_FIRST + (c["row"] - 1) * BERTH_PITCH]
            np.testing.assert_allclose(at, want, atol=0.01, err_msg=c["name"])
            self.assertEqual((c["forward"], c["up"]), ([0.0, 0.0, -1.0], [0.0, 1.0, 0.0]), c["name"])

    def test_a_berths_fighter_leaves_by_the_bow_mouth_and_comes_home_by_the_stern_mouth(self) -> None:
        for c in self.hp["cradles"]:
            at, out, home = (self.authored(c[key]) for key in ("position", "release_to", "approach_from"))
            np.testing.assert_allclose(out[:2], at[:2], atol=1e-4, err_msg=c["name"])
            np.testing.assert_allclose(home[:2], at[:2], atol=1e-4, err_msg=c["name"])
            self.assertAlmostEqual(float(out[2]), TUBE_Z[0] - EXIT_M, delta=0.01, msg="ahead of the bow mouth")
            self.assertAlmostEqual(float(home[2]), TUBE_Z[1] + ENTRY_M, delta=0.01, msg="behind the stern mouth")

    def test_a_delta_v_flies_every_lane_end_to_end_without_touching_the_ship(self) -> None:
        local = box_points(DELTA_V, 1.0)  # the fighter's right, up and back are the ship's
        for c in self.hp["cradles"]:
            if c["row"] != 1:
                continue
            at, out, home = (np.array(c[key]) for key in ("position", "release_to", "approach_from"))
            for share in np.linspace(0.0, 1.0, 41):
                box = home + share * (out - home) + local
                self.assertGreater(float(col.gaps(self.shapes, box).min()), 0.5, f"{c['lane']} at {share:.2f} of its way")
            self.assertGreater(float(col.gaps(self.shapes, at + local).min()), 0.5, c["name"])

    def test_eight_turret_mounts_one_to_each_octant(self) -> None:
        turrets = self.hp["turrets"]
        self.assertEqual(len(turrets), 8)
        octants = set()
        for t in turrets:
            where, face, side = t["name"].split("_")
            at = self.authored(t["position"])
            k = 0 if where == "fore" else 1
            want = [TURRET_X[k] * (1.0 if side == "r" else -1.0), TURRET_Y * (1.0 if face == "dorsal" else -1.0), TURRET_Z[k]]
            np.testing.assert_allclose(at, want, atol=0.01, err_msg=t["name"])
            self.assertEqual(t["up"], [0.0, 1.0 if face == "dorsal" else -1.0, 0.0], t["name"])
            self.assertEqual((t["arc_deg"], t["barrel_m"]), (200.0, 11.25), t["name"])
            self.assertLess(float(col.gaps(self.shapes, np.array([t["position"]])).min()), 0.05, f"{t['name']} stands on its arm's deck")
            octants.add((where, face, side))
        self.assertEqual(len(octants), 8)
        self.assertEqual(self.manifest["turret"]["barrel_m"], 11.25, "the shared turret at two and a half times its size")

    def test_four_missile_racks_in_the_diagonal_bays_of_the_rings_bow_face(self) -> None:
        racks = self.hp["missile_racks"]
        self.assertEqual([r["name"] for r in racks], [f"rack_{clock:03d}" for clock in RACK_CLOCKS])
        for rack, clock in zip(racks, RACK_CLOCKS, strict=True):
            at, way = self.authored(rack["position"]), np.array(rack["forward"])
            self.assertAlmostEqual(float(np.degrees(np.arctan2(at[0], at[1])) % 360.0), clock, delta=0.01)
            self.assertGreater(float(np.hypot(at[0], at[1])), RING_INNER_R)
            self.assertLess(float(np.hypot(at[0], at[1])), RING_OUTER_R)
            self.assertLess(float(at[2]), RING_STATION, "on the bow face")
            self.assertAlmostEqual(float(np.linalg.norm(way)), 1.0, places=4)
            self.assertAlmostEqual(float(np.degrees(np.arccos(-way[2]))), 39.3, delta=0.5, msg="ahead and outward")
            self.assertGreater(float(way[:2] @ at[:2]), 0.0, "outward")
            self.assertEqual(rack["cells"], 6)
            self.assertGreater(float(col.gaps(self.shapes, np.array([rack["position"]]) + 3.0 * way).min()), 2.0, "its missiles leave clear")

    def test_eight_nozzles_in_two_rows_of_four(self) -> None:
        pods = self.hp["pods"]
        self.assertEqual(len(pods), 8)
        at = np.array([self.authored(p["main"]["position"]) for p in pods])
        self.assertEqual(sorted({round(abs(float(x)), 2) for x in at[:, 0]}), [round(x, 2) for x in NOZZLE_X])
        self.assertEqual(sorted({round(float(y), 2) for y in at[:, 1]}), [round(-NOZZLE_Y, 2), round(NOZZLE_Y, 2)])
        self.assertTrue(np.all(at[:, 2] > 0.95 * LENGTH))
        for pod in pods:
            self.assertEqual(pod["main"]["exhaust"], [0.0, 0.0, 1.0])
            self.assertEqual(pod["side"], "left" if pod["main"]["position"][0] < 0 else "right")
        np.testing.assert_allclose(self.authored(self.hp["center_of_mass"])[:2], [0.0, 0.0], atol=0.01)

    def test_the_jump_point_opens_ahead_of_the_bow_and_clears_the_ring(self) -> None:
        jump = self.hp["jump_point"]
        np.testing.assert_allclose(self.authored(jump["position"]), [0.0, 0.0, -450.0], atol=1e-3)
        self.assertEqual(jump["forward"], [0.0, 0.0, -1.0])
        self.assertGreater(jump["mouth_radius_m"], 1.5 * RING_OUTER_R)

    def test_lights_and_the_bridge(self) -> None:
        lights = self.hp["nav_lights"]
        self.assertAlmostEqual(lights["port"][0], -lights["starboard"][0], places=4)
        self.assertGreater(lights["starboard"][0], RING_OUTER_R, "on the ring's rim")
        self.assertLess(self.authored(self.hp["cockpit_camera"]["position"])[2], 0.10 * LENGTH, "at the eye")
        self.assertEqual(self.hp["cockpit_camera"]["forward"], [0.0, 0.0, -1.0])

    # --- collision ---------------------------------------------------------------------------------------------------
    def test_collision_has_a_piece_per_chunk_inside_the_budget(self) -> None:
        section = self.manifest["collision"]
        manifest_io.validate_collision_section(section)
        self.assertEqual([p["name"] for p in section["pieces"]], list(CHUNKS))
        self.assertEqual((section["max_shapes"], section["max_hull_points"]), (64, 32))
        for piece in section["pieces"]:
            self.assertLessEqual(len(piece["shapes"]), 64, piece["name"])
            self.assertEqual(len({s["name"] for s in piece["shapes"]}), len(piece["shapes"]), piece["name"])
        self.assertEqual(self.hp["collision"], [], "the compound is the manifest's")

    def test_collision_covers_the_hull_and_stays_close(self) -> None:
        cover = self.manifest["collision"]["coverage"]
        self.assertEqual((cover["covered"], cover["within_reach"]), (1.0, 1.0))
        self.assertLessEqual(cover["worst_gap_m"], 2.0)
        self.assertLessEqual(cover["worst_excess_m"], 5.0)
        gap = col.gaps(self.shapes, self.obj.vertices)
        self.assertLessEqual(float(gap.max()), 2.0, "every corner of the mesh")

    def test_the_tubes_and_the_rings_openings_stay_open(self) -> None:
        z = np.linspace(TUBE_Z[0] - 5.0, TUBE_Z[1] + 5.0, 40)
        for sign in (1.0, -1.0):
            for x in (-12.0, 0.0, 12.0):
                probe = np.stack([np.full(len(z), x), np.full(len(z), sign * TUBE_Y), z], axis=1) - self.offset
                self.assertGreater(float(col.gaps(self.shapes, probe).min()), 3.0, f"the way through the tube at x {x}")
        # Between the core, the lattice and the ring: the quarters' open bays, clear of the beams.
        for clock in (22.0, 68.0, 112.0, 158.0, 202.0, 248.0, 292.0, 338.0):
            a = np.radians(clock)
            probe = np.array([[48.0 * np.sin(a), 48.0 * np.cos(a), RING_STATION]]) - self.offset
            self.assertGreater(float(col.gaps(self.shapes, probe).min()), 1.0, f"the ring's opening at {clock} degrees")

    def test_collision_is_mirror_symmetric(self) -> None:
        def row(kind: str, lo: np.ndarray, hi: np.ndarray) -> tuple:
            return (kind, *(np.round(lo, 3) + 0.0), *(np.round(hi, 3) + 0.0))

        rows = {row(s.kind, *s.bounds()) for s in self.shapes}
        for s in self.shapes:
            lo, hi = s.bounds()
            self.assertIn(row(s.kind, np.array([-hi[0], lo[1], lo[2]]), np.array([-lo[0], hi[1], hi[2]])), rows, s.name)

    # --- options and determinism ---------------------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        self.assertEqual(sorted(p.name for p in self.out_a.files), sorted(p.name for p in self.out_b.files))
        for path in self.out_a.files:
            self.assertEqual(sha256(path), sha256(self.dir_b / path.name), path.name)

    def test_the_surface_is_the_salvaged_one(self) -> None:
        hull, deck = (np.array(WAGON_SURFACE.style.material(key).albedo) for key in ("hull", "hull_panel"))
        self.assertLess(float(np.ptp(hull)), 0.02, "grey plates")
        self.assertGreater(deck[0], 1.5 * deck[2], "oxide-red decks")
        self.assertGreater(WAGON_SURFACE.tone, 0.15, "plate to plate tone, as if taken from several ships")
        self.assertNotIn("surface", self.manifest)

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, "spacing must be positive"):
                rbw.build(BuildContext(Path(tmp), seed=1, options={"spacing": 0.0}))


if __name__ == "__main__":
    unittest.main()
