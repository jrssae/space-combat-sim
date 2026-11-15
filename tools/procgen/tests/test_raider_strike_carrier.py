"""``raider_strike_carrier`` (M12-T19, Q25 to Q30; D12.1, M7's D73): files, the mesh contract, frames, symmetry, chunk cuts, the
hardpoint contract with its eighteen cradles, engine and jump point, the compound collision (budget, coverage, open rings, a
Delta-V's way to every cradle), the surface and determinism.

The expected numbers are typed in from docs/assets-capital.md and docs/design-references.md ("Raider strike carrier"), not read
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
from tools.procgen.assets import raider_strike_carrier as rsc
from tools.procgen.core import collision as col
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.obj import read_obj
from tools.procgen.styles.raider_capital import SURFACE
from tools.procgen.tests.mesh_checks import MAP_KEYS, assert_chunks_cut_the_hull, assert_hull_mesh, assert_mirror_symmetric

TEST_OPTIONS = {"atlas_px": 512, "spacing": 1.0}
CHUNKS = ("drum", "ring_mid", "ring_outer", "core", "box_l", "box_r")
TRIANGLE_BUDGET = 20_000  # 10 440 as built; the importer adds the levels of detail
LENGTH, SPAN, HEIGHT = 112.0, 85.63, 84.47  # Q26 and the reference's box at 112 m
# The cradles: ring, how many, the pad's distance from the axis and the dock point's station (m; 1 m forward of the pad's centre).
RINGS = {"outer": (9, 42.23, 37.37), "mid": (6, 34.28, 27.93), "drum": (3, 26.33, 18.19)}
CLOCKS = {"outer": (0, 40, 80, 120, 160), "mid": (0, 60, 120, 180), "drum": (0, 120)}
DELTA_V = (17.0, 2.01, 7.2)  # the raider fighter's box: span, height, length (docs/assets-raider.md)
DOCK_GAP_M = 0.05
RING_HOLES = ((18.77, 16.5), (27.2, 23.0), (32.4, 24.0))  # station and radius (% of length) of points in the rings' openings


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


class RaiderStrikeCarrierTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = rsc.build(BuildContext(cls.dir_a, seed=42, options=TEST_OPTIONS))
        cls.out_b = rsc.build(BuildContext(cls.dir_b, seed=42, options=TEST_OPTIONS))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.hp = json.loads((cls.dir_a / rsc.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / rsc.OBJ_NAME)
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.shapes = col.shapes_of(cls.manifest["collision"])  # body frame

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def authored(self, v: list[float]) -> np.ndarray:
        """A hardpoint back in the design references' frame (the bow spikes' tips at z = 0, x and y on the axis)."""
        return np.array(v) + self.offset

    # --- files, manifest, budgets ------------------------------------------------------------------------------------
    def test_registered_and_named(self) -> None:
        self.assertIs(ASSETS["raider_strike_carrier"], rsc.build)
        self.assertEqual(self.out_a.asset_id, "raider_strike_carrier")
        self.assertEqual(self.out_a.warnings, (), "the collision covers the hull")

    def test_all_files_are_written_and_listed(self) -> None:
        on_disk = {p.name for p in self.dir_a.iterdir()}
        self.assertEqual({p.name for p in self.out_a.files}, on_disk)
        for name in ("manifest.json", "hardpoints.json", "raider_strike_carrier.glb", "raider_strike_carrier.obj"):
            self.assertIn(name, on_disk)
        manifest_io.validate_manifest(self.manifest)

    def test_the_hull_is_its_textured_mesh_inside_the_budget(self) -> None:
        assert_hull_mesh(self, self.dir_a, self.manifest, rsc.OBJ_NAME)
        self.assertLessEqual(self.manifest["mesh"]["triangles"], TRIANGLE_BUDGET)

    def test_low_and_high_texture_sets_are_written(self) -> None:
        low = self.manifest["mesh"]["surfaces"][0]["detail"]["low"]
        for key in ("albedo", "normal", "orm"):
            self.assertTrue((self.dir_a / low[key]).is_file(), key)
            self.assertNotEqual(sha256(self.dir_a / low[key]), sha256(self.dir_a / self.manifest["mesh"]["surfaces"][0][key]), key)
        for key in MAP_KEYS:
            self.assertTrue((self.dir_a / self.manifest["mesh"]["surfaces"][0][key]).is_file(), key)

    def test_dimensions_match_the_design(self) -> None:
        dims = self.manifest["dimensions_m"]
        self.assertAlmostEqual(dims["length"], LENGTH, places=2)
        self.assertAlmostEqual(dims["span"], SPAN, delta=0.01 * SPAN)
        self.assertAlmostEqual(dims["height"], HEIGHT, delta=0.01 * HEIGHT)

    def test_the_bow_is_the_ring_end_and_the_boxes_are_aft(self) -> None:
        v = self.obj.vertices + self.offset
        self.assertAlmostEqual(float(v[:, 2].min()), 0.0, places=3)
        wide = v[np.abs(v[:, 0]) > 35.0]  # only the boxes and the outer cradles reach this far out
        self.assertGreater(float(wide[:, 2].max()), 0.85 * LENGTH)
        ring = v[(np.hypot(v[:, 0], v[:, 1]) > 29.5) & (np.abs(v[:, 1]) > 23.3) & (np.abs(v[:, 0]) < 10.9)]
        self.assertLess(float(ring[:, 2].max()), 0.40 * LENGTH, "the rings stand in the bow third")

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
                    "turrets", "cradles", "jump_point", "chunks"):  # fmt: skip
            self.assertIn(key, self.hp)
        self.assertEqual((self.hp["muzzles"], self.hp["turrets"]), ([], []), "no weapons (Q25)")
        self.assertEqual(self.hp["length_m"], self.manifest["dimensions_m"]["length"])

    def test_eighteen_cradles_on_the_drum_and_the_rings(self) -> None:
        cradles = self.hp["cradles"]
        self.assertEqual(len(cradles), 18)
        self.assertEqual(self.manifest["cradle_count"], 18)
        self.assertEqual(len({c["name"] for c in cradles}), 18)
        for ring, (count, radius, station) in RINGS.items():
            here = [c for c in cradles if c["ring"] == ring]
            self.assertEqual(len(here), count, ring)
            self.assertEqual(sorted({abs(c["clock_deg"]) for c in here}), list(CLOCKS[ring]), ring)
            for c in here:
                at = self.authored(c["position"])
                self.assertAlmostEqual(float(np.hypot(at[0], at[1])), radius, delta=0.05, msg=c["name"])
                self.assertAlmostEqual(float(at[2]), station, delta=0.05, msg=c["name"])

    def test_a_cradle_holds_its_fighter_nose_forward_and_back_outward(self) -> None:
        for c in self.hp["cradles"]:
            at, up = self.authored(c["position"]), np.array(c["up"])
            self.assertEqual(c["forward"], [0.0, 0.0, -1.0], c["name"])
            self.assertAlmostEqual(float(np.linalg.norm(up)), 1.0, places=4)
            np.testing.assert_allclose(up[:2], at[:2] / np.hypot(at[0], at[1]), atol=1e-3, err_msg=c["name"])
            clock = np.degrees(np.arctan2(up[0], up[1]))
            self.assertAlmostEqual(float(clock), c["clock_deg"], delta=0.01, msg=c["name"])
            np.testing.assert_allclose(c["approach"], -up, atol=1e-6)
            np.testing.assert_allclose(c["release"], up, atol=1e-6)
            np.testing.assert_allclose(np.array(c["approach_from"]) - np.array(c["position"]), 60.0 * up, atol=1e-3)

    def test_the_cradles_mirror_in_x(self) -> None:
        by_name = {c["name"]: c for c in self.hp["cradles"]}
        for name, c in by_name.items():
            if name.endswith("_r"):
                twin = by_name[name[:-2] + "_l"]
                np.testing.assert_allclose(twin["position"], np.array(c["position"]) * [-1, 1, 1], atol=1e-4)
                np.testing.assert_allclose(twin["up"], np.array(c["up"]) * [-1, 1, 1], atol=1e-4)
            elif not name.endswith("_l"):
                self.assertAlmostEqual(c["position"][0], 0.0, places=4)

    def test_a_delta_v_reaches_every_cradle_without_touching_the_carrier(self) -> None:
        local = box_points(DELTA_V, 0.5)
        for c in self.hp["cradles"]:
            up, fwd = np.array(c["up"]), np.array(c["forward"])
            basis = np.stack([np.cross(fwd, up), up, -fwd], axis=1)  # the docked fighter's right, up and back
            docked = np.array(c["position"]) + local @ basis.T
            for height in (60.0, 30.0, 15.0, 8.0, 4.0, 2.0, 1.0, 0.5, 0.2, DOCK_GAP_M):
                gap = col.gaps(self.shapes, docked + height * up)
                self.assertGreater(float(gap.min()), 0.0, f"{c['name']} at {height} m")
            self.assertLess(float(col.gaps(self.shapes, docked + DOCK_GAP_M * up).min()), 0.1, f"{c['name']}: it rests on the pad")

    def test_one_main_engine_at_the_stern_on_the_axis(self) -> None:
        (pod,) = self.hp["pods"]
        at = self.authored(pod["main"]["position"])
        np.testing.assert_allclose(at[:2], [0.0, 0.0], atol=1e-4)
        self.assertGreater(at[2], 0.95 * LENGTH)
        self.assertEqual(pod["main"]["exhaust"], [0.0, 0.0, 1.0])
        np.testing.assert_allclose(self.authored(self.hp["center_of_mass"])[:2], [0.0, 0.0], atol=1e-4)

    def test_the_jump_point_opens_ahead_of_the_bow_and_clears_the_hull(self) -> None:
        jump = self.hp["jump_point"]
        at = self.authored(jump["position"])
        np.testing.assert_allclose(at, [0.0, 0.0, -250.0], atol=1e-3)
        self.assertEqual(jump["forward"], [0.0, 0.0, -1.0])
        v = self.obj.vertices + self.offset
        self.assertGreater(jump["mouth_radius_m"], 1.5 * float(np.hypot(v[:, 0], v[:, 1]).max()))

    def test_lights_and_the_bridge(self) -> None:
        lights = self.hp["nav_lights"]
        self.assertAlmostEqual(lights["port"][0], -lights["starboard"][0], places=4)
        self.assertGreater(lights["starboard"][0], 41.0, "on the box's outer flank")
        self.assertLess(self.authored(self.hp["cockpit_camera"]["position"])[2], 0.12 * LENGTH)
        self.assertEqual(self.hp["cockpit_camera"]["forward"], [0.0, 0.0, -1.0])

    # --- collision ---------------------------------------------------------------------------------------------------
    def test_collision_has_a_piece_per_chunk_inside_the_budget(self) -> None:
        section = self.manifest["collision"]
        col.validate_section(section)
        self.assertEqual([p["name"] for p in section["pieces"]], list(CHUNKS))
        self.assertEqual(section["budget"], {"max_pieces": 64, "max_hull_points": 32})
        for piece in section["pieces"]:
            self.assertLessEqual(len(piece["shapes"]), 64, piece["name"])
            self.assertEqual(len({s["name"] for s in piece["shapes"]}), len(piece["shapes"]), piece["name"])
        self.assertEqual(self.hp["collision"], [], "the compound is the manifest's")

    def test_collision_covers_the_hull_and_stays_close(self) -> None:
        cover = self.manifest["collision"]["coverage"]
        self.assertEqual((cover["covered"], cover["within_reach"]), (1.0, 1.0))
        self.assertLessEqual(cover["worst_gap_m"], 1.0)
        self.assertLessEqual(cover["worst_excess_m"], 2.5)
        gap = col.gaps(self.shapes, self.obj.vertices)
        self.assertLessEqual(float(gap.max()), 1.0, "every corner of the mesh")

    def test_the_rings_stay_open(self) -> None:
        u = LENGTH / 100.0
        for station, radius in RING_HOLES:
            turn = np.radians(np.arange(5.0, 360.0, 10.0) + 0.0)
            turn = turn[np.abs(np.sin(turn)) > 0.3]  # the spokes lie along x
            probe = np.stack([radius * u * np.cos(turn), radius * u * np.sin(turn), np.full(len(turn), station * u)], axis=1) - self.offset
            self.assertGreater(float(col.gaps(self.shapes, probe).min()), 0.5, f"station {station}")

    def test_collision_is_mirror_symmetric(self) -> None:
        shapes = [s for piece in self.manifest["collision"]["pieces"] for s in piece["shapes"]]
        rows = {(s["type"], *np.round(s["position"], 3), round(s["bound_radius"], 3)) for s in shapes}
        for s in shapes:
            x, y, z = np.round(s["position"], 3)
            self.assertIn((s["type"], -x + 0.0, y, z, round(s["bound_radius"], 3)), rows, s["name"])

    # --- options and determinism ---------------------------------------------------------------------------------------
    def test_same_seed_gives_byte_identical_output(self) -> None:
        self.assertEqual(sorted(p.name for p in self.out_a.files), sorted(p.name for p in self.out_b.files))
        for path in self.out_a.files:
            self.assertEqual(sha256(path), sha256(self.dir_b / path.name), path.name)

    def test_the_surface_is_the_show_green(self) -> None:
        hull = np.array(SURFACE.style.material("hull").albedo)
        self.assertGreater(hull[1], hull[0], "green flanks")
        self.assertGreater(hull[1], hull[2])
        self.assertLess(SURFACE.style.material("hazard").emissive_strength, 0.5, "the lit slats do not bloom to white")
        self.assertNotIn("surface", self.manifest)

    def test_invalid_options_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, "spacing must be positive"):
                rsc.build(BuildContext(Path(tmp), seed=1, options={"spacing": 0.0}))


if __name__ == "__main__":
    unittest.main()
