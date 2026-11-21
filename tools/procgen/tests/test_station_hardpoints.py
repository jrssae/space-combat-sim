"""The station's near field and hardpoints (M7-T05): the main docking bay (M7-T25: its mouth open to traffic, the black void behind
its inner doors closed at the back), the
cargo bay (zero-gravity) between the bow's forks, the 28 Cobra-bay launch doors over their open hall with M7-T09's racks, D75's
mounts where the maintainer approved them, the lights, the tour points and the damage sections. Each hardpoint must exist, sit on or just off the hull (or inside its bay), and lie on the piece that carries
it, in that piece's frame."""

from __future__ import annotations

import math
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import babylon5_station as station
from tools.procgen.core import collision as col
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Mesh
from tools.procgen.parts import station as st
from tools.procgen.parts import station_detail as sd
from tools.procgen.parts import station_props as sp
from tools.procgen.parts import station_layouts as sl

SMALL = (1024, 1024, 64)
# D75 as approved (docs/milestones/m7-babylon-5-station.md), station frame: name, kind, body, position, up.
D75 = [
    # L1 to L8 on the side facets of each Cobra arm's forward head (M7-T24), facing out and toward the bow.
    ("L1", "light_pulse", "drum", (-40.4, 300.8, 745.5), (-0.451, 0.846, -0.283)),
    ("L2", "light_pulse", "drum", (40.4, 300.8, 745.5), (0.451, 0.846, -0.283)),
    ("L3", "light_pulse", "drum", (300.8, 40.4, 745.5), (0.846, 0.451, -0.283)),
    ("L4", "light_pulse", "drum", (300.8, -40.4, 745.5), (0.846, -0.451, -0.283)),
    ("L5", "light_pulse", "drum", (40.4, -300.8, 745.5), (0.451, -0.846, -0.283)),
    ("L6", "light_pulse", "drum", (-40.4, -300.8, 745.5), (-0.451, -0.846, -0.283)),
    ("L7", "light_pulse", "drum", (-300.8, -40.4, 745.5), (-0.846, -0.451, -0.283)),
    ("L8", "light_pulse", "drum", (-300.8, 40.4, 745.5), (-0.846, 0.451, -0.283)),
    ("L9", "light_pulse", "frame", (0, 507, 1500), (0, 0.98, -0.21)), ("L10", "light_pulse", "frame", (0, 537, 2650), (0, 1, 0)),
    ("L11", "light_pulse", "frame", (0, 537, 4500), (0, 1, 0)), ("L12", "light_pulse", "frame", (0, 472, 5650), (0, 1, 0)),
    ("H1", "heavy_cannon", "frame", (-45, 368.2, 522), (0, 1, 0)), ("H2", "heavy_cannon", "frame", (45, 368.2, 522), (0, 1, 0)),
    ("I1", "interceptor", "drum", (0, 324, 800), (0, 1, 0)), ("I2", "interceptor", "drum", (324, 0, 800), (1, 0, 0)),
    ("I3", "interceptor", "drum", (0, -324, 800), (0, -1, 0)), ("I4", "interceptor", "drum", (-324, 0, 800), (-1, 0, 0)),
    ("I5", "interceptor", "frame", (0, 438, 520), (0, 1, -0.02)), ("I6", "interceptor", "frame", (40, 459, 1500), (0, 1, -0.05)),
    ("I7", "interceptor", "frame", (-40, 537, 2650), (0, 1, 0)), ("I8", "interceptor", "frame", (40, 537, 4500), (0, 1, 0)),
    ("I9", "interceptor", "frame", (-40, 472, 5650), (0, 1, 0)),
]


def _triangles(parts) -> np.ndarray:
    mesh = Mesh.concatenate(p.mesh for p in parts)
    return mesh.vertices[mesh.faces]


def ray_hit(tris: np.ndarray, origin: np.ndarray, direction: np.ndarray) -> float:
    """The distance along a ray to the nearest triangle it meets (inf if none)."""
    d = np.asarray(direction, dtype=float)
    e1, e2 = tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    p = np.cross(d, e2)
    det = np.einsum("ij,ij->i", e1, p)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    s = origin - tris[:, 0]
    u = np.einsum("ij,ij->i", s, p) * inv
    q = np.cross(s, e1)
    v = (q @ d) * inv
    t = np.einsum("ij,ij->i", e2, q) * inv
    hit = ok & (u >= 0.0) & (v >= 0.0) & (u + v <= 1.0) & (t > 1e-6)
    return float(t[hit].min()) if hit.any() else math.inf


def _segment_distance(a: np.ndarray, b: np.ndarray, p: np.ndarray) -> np.ndarray:
    ab = b - a
    t = np.clip(np.einsum("ij,ij->i", p - a, ab) / np.maximum(np.einsum("ij,ij->i", ab, ab), 1e-12), 0.0, 1.0)
    return np.linalg.norm(a + ab * t[:, None] - p, axis=1)


def distance_to(tris: np.ndarray, point: np.ndarray) -> float:
    """The distance from a point to the nearest triangle: to its plane where the point projects inside it, else to its edges."""
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    p = np.asarray(point, dtype=float)[None, :]
    n = np.cross(b - a, c - a)
    area = np.linalg.norm(n, axis=1)
    n = n / np.maximum(area, 1e-12)[:, None]
    h = np.einsum("ij,ij->i", p - a, n)
    q = p - h[:, None] * n
    inside = np.ones(len(a), dtype=bool)
    for u, v in ((a, b), (b, c), (c, a)):
        inside &= np.einsum("ij,ij->i", np.cross(v - u, q - u), n) >= 0.0
    edge = np.minimum.reduce([_segment_distance(a, b, p), _segment_distance(b, c, p), _segment_distance(c, a, p)])
    return float(np.where(inside & (area > 1e-12), np.abs(h), edge).min())


class HardpointTests(unittest.TestCase):
    """The manifest's ``hardpoints`` from a small bake, against the shapes."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name)
        station.build_at(BuildContext(cls.dir, seed=42), *SMALL)
        cls.manifest = manifest_io.read_manifest(cls.dir)
        cls.hp = cls.manifest["hardpoints"]
        cls.shift = {"drum": station.DRUM_CENTRE, "frame": station.ORIGIN}
        cls.tris = {"drum": _triangles(station.drum_parts()) + station.DRUM_CENTRE,
                    "frame": _triangles(station.frame_parts()) + station.ORIGIN}

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def at(self, entry: dict, key: str = "position") -> np.ndarray:
        """A hardpoint's point in the station frame."""
        return np.asarray(entry[key], dtype=float) + self.shift[entry["body"]]

    def test_every_kind_is_there_and_counted(self) -> None:
        wings = ("alpha", "beta", "delta", "zeta")
        self.assertEqual([b["name"] for b in self.hp["cobra_bays"]], [f"cobra_bay_{w}_{k}" for w in wings for k in range(1, 7)])
        self.assertEqual(len(self.hp["grid_mounts"]), 23)
        kinds: dict[str, int] = {}
        for light in self.hp["lights"]:
            kinds[light["kind"]] = kinds.get(light["kind"], 0) + 1
        self.assertEqual(kinds, {"beacon": 15, "nav": 60, "bay": 24, "main_docking_bay": 8, "cargo_bay": 6, "flood": 74})
        self.assertEqual(sum(1 for light in self.hp["lights"] if "marker" in light), 85, "beacons, nav lights, ten bay lamps drawn")
        names = {t["name"] for t in self.hp["tour_points"]}
        self.assertTrue({"bow", "main_docking_bay", "cargo_bay", "cobra_arm", "grid_tower", "drum", "vanes", "reactor"} <= names)
        for key in ("cobra_bays", "grid_mounts", "lights", "tour_points", "damage_sections"):
            names = [h["name"] for h in self.hp[key]]
            self.assertEqual(len(names), len(set(names)), f"{key}: names are unique")
        for key in ("cobra_bays", "grid_mounts", "lights", "tour_points", "damage_sections"):
            for h in self.hp[key]:
                self.assertIn(h["body"], ("drum", "frame"), h["name"])
        self.assertAlmostEqual(self.hp["spin_rad_s"], self.manifest["pieces"]["drum"]["spin_rad_s"])

    def test_the_grid_mounts_are_d75s_on_their_plinths(self) -> None:
        by_name = {m["name"]: m for m in self.hp["grid_mounts"]}
        self.assertEqual(list(by_name), [m[0] for m in D75])
        for name, kind, body, pos, up in D75:
            m = by_name[name]
            self.assertEqual((m["kind"], m["body"]), (kind, body), name)
            np.testing.assert_allclose(self.at(m), pos, atol=0.01, err_msg=name)
            np.testing.assert_allclose(m["up"], np.asarray(up) / np.linalg.norm(up), atol=0.01, err_msg=name)
            # Looking down its up from above, the first surface is its plinth's face just over the pivot, on its own piece; a heavy
            # cannon stands on its recess's floor instead (M7-T43).
            n = np.asarray(m["up"])
            down = ray_hit(self.tris[body], self.at(m) + 20.0 * n, -n)
            face = 0.0 if kind == "heavy_cannon" else sd.PLINTH_TOP_M
            self.assertAlmostEqual(20.0 - down, face, delta=0.05, msg=f"{name} sits on its plinth or its recess's floor")
            other = "frame" if body == "drum" else "drum"
            self.assertGreater(distance_to(self.tris[other], self.at(m)), 5.0, f"{name} is clear of the other piece")

    def test_the_cobra_bays_launch_radially_out_of_their_doors(self) -> None:
        top, floor = st.ARM_HATCH[4], st.ARM_HATCH[4] - st.DOOR_DEPTH
        for bay in self.hp["cobra_bays"]:
            self.assertEqual(bay["body"], "drum")
            n = np.asarray(bay["normal"])
            door, release, start = self.at(bay, "door"), self.at(bay, "release"), self.at(bay, "rail_start")
            self.assertAlmostEqual(float(np.linalg.norm(n)), 1.0, places=4)
            self.assertAlmostEqual(float(n[2]), 0.0)
            self.assertAlmostEqual(float(door @ n), floor, delta=0.01, msg="on the doors' plane")
            np.testing.assert_allclose(bay["release_direction"], n, atol=1e-4)
            self.assertAlmostEqual(float(np.asarray(bay["across"]) @ n), 0.0, places=6)
            self.assertTrue(st.HALL_CEILING_R < float(start @ n) < floor, "the fighter hangs in the hall")
            np.testing.assert_allclose(self.at(bay, "rail_end"), door, atol=0.01)
            np.testing.assert_allclose(np.cross(start - door, n), 0.0, atol=1e-3, err_msg="the rail runs straight out through the door")
            # The door is open below the release point: the first hull under it is the hall's ceiling; the release point is clear.
            self.assertAlmostEqual(ray_hit(self.tris["drum"], release, -n), float(release @ n) - st.HALL_CEILING_R, delta=0.05)
            self.assertGreater(distance_to(self.tris["drum"], release), 4.0, bay["name"])
            self.assertGreater(float(release @ n), top)
            v = np.asarray(bay["surface_velocity"])  # released with the drum's surface velocity there (Q3)
            np.testing.assert_allclose(v, self.hp["spin_rad_s"] * np.cross([0, 0, 1], [release[0], release[1], 0]), atol=1e-3)
            self.assertEqual([h["leaf"] for h in bay["leaves"]], ["r", "l"])
            for leaf, side in zip(bay["leaves"], (1.0, -1.0), strict=True):  # each leaf slides across the arm, away from the middle
                np.testing.assert_allclose(leaf["slide"], side * np.asarray(bay["across"]), atol=1e-4)
                self.assertAlmostEqual(leaf["travel_m"], sp.LEAF_TRAVEL, places=4)
                self.assertAlmostEqual(leaf["reach_m"], 0.5 * sp.TOOTH_DEPTH, places=4)
                self.assertGreater(leaf["travel_m"] - leaf["reach_m"], bay["door_half_m"][0], "open, its teeth are out of the well")
        self.assertEqual(len({(b["arm"], b["door_number"]) for b in self.hp["cobra_bays"]}), 24)
        layout = self.hp["cobra_arm"]
        self.assertEqual((layout["doors"], layout["door_half_m"], len(layout["centres"])), (6, [10.0, 7.0], 6))
        top_arm = [b for b in self.hp["cobra_bays"] if b["arm"] == "top"]
        for (x, z), bay in zip(layout["centres"], top_arm, strict=True):
            np.testing.assert_allclose(self.at(bay, "door"), [x, layout["door_floor_r"], z], atol=1e-3)

    def test_each_arm_is_one_wing(self) -> None:
        # Seen from the bow: Alpha top, Beta starboard, Delta bottom, Zeta port (the maintainer, 2026-11-13).
        expected = {"top": "alpha", "starboard": "beta", "bottom": "delta", "port": "zeta"}
        for bay in self.hp["cobra_bays"]:
            self.assertEqual(bay["wing"], expected[bay["arm"]], bay["name"])
            self.assertEqual(bay["name"], f"cobra_bay_{bay['wing']}_{bay['door_number']}")
        arms = {a["name"]: a for a in self.hp["cobra_arm"]["arms"]}
        self.assertEqual({n: a["wing"] for n, a in arms.items()}, expected)
        self.assertEqual({a["wing"]: a["bow_view_deg"] for a in arms.values()}, {"alpha": 0.0, "beta": 90.0, "delta": 180.0, "zeta": 270.0})
        for arm in arms.values():
            n = np.array([math.cos(math.radians(arm["angle_deg"])), math.sin(math.radians(arm["angle_deg"])), 0.0])
            for name in arm["bays"]:
                bay = next(b for b in self.hp["cobra_bays"] if b["name"] == name)
                np.testing.assert_allclose(bay["normal"], n, atol=1e-4, err_msg=name)

    def test_the_second_row_waits_unseen_and_moves_onto_its_rack(self) -> None:
        # Twelve Starfuries an arm: the second six wait across the hall under the deck, then cross onto the empty racks.
        drum = next(e for e in self.manifest["collision"]["pieces"] if e["name"] == "drum")
        shapes = col.shapes_from_entry(drum)
        floor = st.ARM_HATCH[4] - st.DOOR_DEPTH
        hx0, hx1, hz0, hz1 = st.LAUNCH_HALL
        for bay in self.hp["cobra_bays"]:
            n, across = np.asarray(bay["normal"]), np.asarray(bay["across"])
            stage, door = self.at(bay, "staging"), self.at(bay, "door")
            x = float((stage - door) @ across) + st.LAUNCH_STRIP_X
            self.assertTrue(-st.HALL_LOWER_HALF + 7.7 < x and abs(x - st.LAUNCH_STRIP_X) - 7.7 > st.LAUNCH_DOOR_HALF[0], "in the lower hall")
            self.assertTrue(st.HALL_CEILING_R < float(stage @ n) < st.HALL_UPPER_R, "under the upper hall's floor line")
            self.assertLess(ray_hit(self.tris["drum"], stage, n), st.ARM_HATCH[4] - float(stage @ n) + 0.1, "no door over it")
            path = [np.asarray(p) + self.shift["drum"] for p in bay["staging_path"]]
            np.testing.assert_allclose(path[0], stage)
            np.testing.assert_allclose(path[-1], self.at(bay, "rail_start"))
            pts = np.concatenate([a + np.outer(np.linspace(0.0, 1.0, 8), b - a) for a, b in zip(path[:-1], path[1:], strict=True)])
            pts = np.concatenate([pts + d * across + e * np.array([0.0, 0.0, 1.0]) for d in (-7.7, 7.7) for e in (-4.9, 4.9)])
            for shape in shapes[::1]:
                self.assertGreater(float(shape.distance(pts - self.shift["drum"]).min()), 0.2, f"{shape.name} in {bay['name']}'s staging path")

    def test_a_launch_waits_while_its_arm_points_at_the_frame(self) -> None:
        # M7-T08's rule: the drop path from a door with its arm in the blocked sector meets the frame within the clear distance; well
        # outside it, nothing of the frame is in the way.
        clear = self.hp["launch_clearance"]
        self.assertEqual(len(clear["blocked_sectors_deg"]), 1, "the spine over the drum: one sector")
        a0, a1 = clear["blocked_sectors_deg"][0]
        self.assertTrue(a0 < 90.0 < a1, "the top arm at rest points at the dorsal spine")
        self.assertGreater(clear["margin_deg"], 0.0)
        floor = st.ARM_HATCH[4] - st.DOOR_DEPTH
        dist = clear["clear_distance_m"]

        def drop(angle: float) -> float:
            th = math.radians(angle)
            n, tangent = np.array([math.cos(th), math.sin(th), 0.0]), np.array([math.sin(th), -math.cos(th), 0.0])
            hits = []
            for z in st.launch_door_centres():
                door = st.LAUNCH_STRIP_X * tangent + floor * n + np.array([0.0, 0.0, z])
                hits.append(ray_hit(self.tris["frame"], door, n))
            return min(hits)

        self.assertLess(drop(0.5 * (a0 + a1)), dist, "at the sector's centre the frame is in the drop path")
        for angle in (0.5 * (a0 + a1) + 180.0, a1 + 20.0, a0 - 20.0):
            self.assertEqual(drop(angle), math.inf, f"well outside it the drop is clear ({angle:.0f} degrees)")
        # Nothing of the frame lies farther out than the clear distance over the strip, so a drop that far is clear.
        z0, z1 = st.LAUNCH_ROW
        tris = self.tris["frame"]
        near = tris[(tris[:, :, 2].max(axis=1) > z0) & (tris[:, :, 2].min(axis=1) < z1)]
        self.assertLess(float(np.hypot(near[:, :, 0], near[:, :, 1]).max()) - floor, dist)

    def test_each_door_fits_one_starfury_with_clearance(self) -> None:
        # A Starfury (15.4 m across its claws, 9.8 m long, span across the arm) in its pose drops through with 2 m or more each side.
        for bay in self.hp["cobra_bays"]:
            hx, hz = bay["door_half_m"]
            self.assertGreaterEqual(hx - 7.7, 2.0, bay["name"])
            self.assertGreaterEqual(hz - 4.9, 2.0, bay["name"])
            self.assertEqual(bay["forward"], [0.0, 0.0, -1.0], "its length along the arm, its span across")

    def test_the_hall_is_open_in_collision_for_a_drop(self) -> None:
        # AC3's half: a Starfury hanging over its door drops out through it without a contact.
        drum = next(e for e in self.manifest["collision"]["pieces"] if e["name"] == "drum")
        shapes = col.shapes_from_entry(drum)
        for bay in self.hp["cobra_bays"][::2]:
            n, across = np.asarray(bay["normal"]), np.asarray(bay["across"])
            hang, release = np.asarray(bay["rail_start"]), np.asarray(bay["release"])
            pts = np.array([hang + t * (release - hang) + x * across + z * np.array([0.0, 0.0, 1.0]) + h * n
                            for t in np.linspace(0.0, 1.0, 9) for x in (-7.7, 0.0, 7.7) for z in (-4.9, 0.0, 4.9) for h in (-2.0, 2.0)])
            for shape in shapes:
                self.assertGreater(float(shape.distance(pts).min()), 0.2, f"{shape.name} is in {bay['name']}'s drop")

    def test_the_main_docking_bay_runs_down_the_axis_into_the_void(self) -> None:
        bay = self.hp["main_docking_bay"]
        self.assertEqual(bay["body"], "drum")
        self.assertEqual(bay["spin_axis"], self.manifest["pieces"]["drum"]["axis"])
        self.assertAlmostEqual(bay["spin_rad_s"], self.manifest["pieces"]["drum"]["spin_rad_s"])
        self.assertEqual(bay["pivot"], self.manifest["pieces"]["drum"]["pivot"])
        path = [np.asarray(p) + self.shift["drum"] for p in bay["main_docking_bay_path"]]
        for p in path:
            self.assertAlmostEqual(float(np.hypot(p[0], p[1])), 0.0, places=6, msg="on the axis, so the drum's turn does not move it")
        self.assertTrue(all(b[2] > a[2] for a, b in zip(path[:-1], path[1:], strict=True)), "bow to stern")
        np.testing.assert_allclose(path[:2], [np.asarray(p) + self.shift["drum"] for p in bay["main_docking_bay_approach"]])
        np.testing.assert_allclose(path[2], self.at(bay, "main_docking_bay_mouth"))
        np.testing.assert_allclose(path[3], self.at(bay, "main_docking_bay_airlock"))
        self.assertAlmostEqual(float(self.at(bay, "main_docking_bay_mouth")[2]), sd.FACE_Z)
        self.assertAlmostEqual(float(self.at(bay, "main_docking_bay_doors")[2]), sd.DOORS_Z)
        self.assertAlmostEqual(float(self.at(bay, "main_docking_bay_airlock")[2]), sd.VOID_BACK_Z)
        self.assertEqual(bay["main_docking_bay_doors_open_m"], sd.DOOR_OPEN_M)
        np.testing.assert_allclose(bay["main_docking_bay_opening"], np.round(sd.opening(), 4))
        # Nothing of the drum stands ahead of the fans beside the block.
        self.assertGreater(float(self.tris["drum"][:, :, 2].min()), min(z for _, _, z in sd.FAN) - 0.5)
        # Straight down the axis the hull leaves the way open (the doors are props) to the black void's back wall.
        self.assertAlmostEqual(ray_hit(self.tris["drum"], path[0], np.array([0.0, 0.0, 1.0])), sd.VOID_BACK_Z - path[0][2], delta=0.01)

    def test_the_mouth_is_open_in_collision_and_the_void_closed_behind(self) -> None:
        drum = next(e for e in self.manifest["collision"]["pieces"] if e["name"] == "drum")
        shapes = col.shapes_from_entry(drum)
        bay = self.hp["main_docking_bay"]
        hw, hh = bay["main_docking_bay_clear_half_m"]
        self.assertGreaterEqual(2.0 * hw, 72.0, "the band: the STL's, scaled to an 80 m mouth (M7-T25)")
        self.assertGreaterEqual(2.0 * hh, 30.0, "the core")
        inner = sd.offset(sd.opening(), -0.5)
        grid = [(x, y) for x in np.linspace(-hw, hw, 25) for y in np.linspace(-hh, hh, 11) if sd.contains(inner, x, y)]
        zs = np.arange(sd.FACE_Z - 60.0, sd.VOID_BACK_Z - 0.5, 2.0)
        inside = np.array([[x, y, z] for z in zs for x, y in grid]) - station.DRUM_CENTRE
        vx, vy = sd.VOID_HALF
        void = np.array([[x, y, z] for z in np.arange(sd.DOORS_Z + sd.DOOR_SLAB_M + 0.5, sd.VOID_BACK_Z - 0.5, 4.0)
                         for x in np.linspace(-vx + 0.5, vx - 0.5, 9) for y in np.linspace(-vy + 0.5, vy - 0.5, 5)]) - station.DRUM_CENTRE
        for shape in shapes:
            for pts, where in ((inside, "the mouth"), (void, "the void")):
                gap = shape.distance(pts)
                self.assertGreater(float(gap.min()), 0.3, f"{shape.name} blocks {where} at {pts[int(np.argmin(gap))] + station.DRUM_CENTRE}")
        past = np.array([[0.0, 0.0, sd.VOID_BACK_Z + 5.0]]) - station.DRUM_CENTRE
        self.assertTrue(any(float(s.distance(past)[0]) <= 0.0 for s in shapes), "the void's back wall closes it")
        for side in ((hw + 1.5, 0.0), (-hw - 1.5, 0.0), (0.0, hh + 1.5), (0.0, -hh - 1.5)):
            wall = np.array([[side[0], side[1], 520.0]]) - station.DRUM_CENTRE
            self.assertTrue(any(float(s.distance(wall)[0]) <= 0.0 for s in shapes), f"a wall beside the mouth at {side}")

    def test_the_cargo_bay_takes_a_pod_down_the_slot(self) -> None:
        bay = self.hp["cargo_bay"]
        self.assertEqual(bay["body"], "frame")
        path = [np.asarray(p) + self.shift["frame"] for p in bay["cargo_bay_path"]]
        np.testing.assert_allclose(path[0], self.at(bay, "cargo_bay_release"))
        np.testing.assert_allclose(path[-1], self.at(bay, "cargo_bay_entry"))
        self.assertTrue(all(b[2] > a[2] for a, b in zip(path[:-1], path[1:], strict=True)), "toward the station")
        hold, release, entry = self.at(bay, "cargo_bay_hold"), self.at(bay, "cargo_bay_release"), self.at(bay, "cargo_bay_entry")
        np.testing.assert_allclose(np.asarray(bay["cargo_bay_approach"][-1]) + self.shift["frame"], hold, err_msg="the approach ends at the hold")
        # The freighter (158 m long) waits well clear of the hull and of the main docking bay's path on the axis.
        self.assertGreater(min(distance_to(self.tris[b], hold) for b in ("drum", "frame")), 300.0)
        self.assertGreater(float(np.hypot(hold[0], hold[1])), 200.0)
        self.assertGreater(min(distance_to(self.tris[b], release) for b in ("drum", "frame")), 300.0)
        # The entry point is inside the open bay, a whole pod (43 m) in from its front, and the bay is open above it.
        self.assertTrue(sd.ZG_COMPARTMENT_Z + 0.5 * 43.0 <= entry[2] <= sd.ZG_BACK_Z - 0.5 * 43.0, "the pod lies wholly inside")
        self.assertLess(abs(entry[0]), sd.ZG_HALF_X)
        # Roofed (M7-T21): closed above and to the sides; open only ahead, down the throat and the slot.
        self.assertLess(ray_hit(self.tris["frame"], entry, np.array([0.0, 1.0, 0.0])), sd.ZG_ROOF_Y - entry[1] + 0.5, "the roof over it")
        for side in (np.array([1.0, 0.0, 0.0]), np.array([-1.0, 0.0, 0.0])):
            self.assertLess(ray_hit(self.tris["frame"], entry, side), sd.ZG_HALF_X + 0.5, "its walls")
        self.assertEqual(ray_hit(self.tris["frame"], entry, np.array([0.0, 0.0, -1.0])), math.inf, "open ahead, down the slot")
        for p in ((60.0, entry[1], 430.0), (0.0, sd.ZG_ROOF_Y + 5.0, 430.0)):
            p = np.asarray(p)
            self.assertLess(ray_hit(self.tris["frame"], p - [0.0, 0.0, 30.0], np.array([0.0, 0.0, 1.0])), 30.0, f"closed beside the throat at {p}")
        # A Saturn pod (31.1 x 17.2 m square-on) flies the path without a contact, in collision and against the drawn hull.
        lo, hi = np.asarray(bay["cargo_bay_clear_min"]), np.asarray(bay["cargo_bay_clear_max"])
        self.assertGreaterEqual(hi[0] - lo[0], 31.1 + 10.0)  # a pod square-on with room each side (the STL's octagon: 68.2 x 31.4)
        self.assertGreaterEqual(hi[1] - lo[1], 17.2 + 8.0)
        frame = next(e for e in self.manifest["collision"]["pieces"] if e["name"] == "frame")
        shapes = col.shapes_from_entry(frame)
        pod = np.array([[x, y, 0.0] for x in np.linspace(-15.55, 15.55, 5) for y in np.linspace(-8.6, 8.6, 3)])
        zs = np.arange(release[2], entry[2] + 21.5, 3.0)
        pts = np.concatenate([pod + [0.0, entry[1], z] for z in zs]) - self.shift["frame"]
        for shape in shapes:
            self.assertGreater(float(shape.distance(pts).min()), 0.3, f"{shape.name} is in the pods' path")
        for p in pts[::7] + self.shift["frame"]:
            self.assertGreater(distance_to(self.tris["frame"], p), 0.3)

    def test_the_lights_sit_on_their_piece(self) -> None:
        for light in self.hp["lights"]:
            p, body = self.at(light), light["body"]
            other = "frame" if body == "drum" else "drum"
            if light["kind"] in ("beacon", "nav"):
                self.assertLess(distance_to(self.tris[body], p), 3.0, f"{light['name']} on the hull")
                self.assertGreater(distance_to(self.tris[other], p), 5.0, f"{light['name']} on the right piece")
            elif light["kind"] == "flood":
                # A flood's fixture is not drawn; what matters is that its beam lands on the station within its throw.
                d = np.asarray(light["direction"], dtype=float)
                side = np.cross(d, [0.0, 0.0, 1.0] if abs(d[2]) < 0.9 else [1.0, 0.0, 0.0])
                side /= np.linalg.norm(side)
                up = np.cross(d, side)
                spread = math.tan(math.radians(light["inner_deg"]))
                rays = [d] + [d + spread * (math.cos(a) * side + math.sin(a) * up) for a in np.linspace(0.0, 2.0 * math.pi, 8, endpoint=False)]
                hit = min(ray_hit(self.tris[b], p, r / np.linalg.norm(r)) for b in ("drum", "frame") for r in rays)
                self.assertLess(hit, light["range_m"], f"{light['name']}'s beam lands on the station")
            elif light["kind"] == "bay":
                r = float(np.hypot(p[0], p[1]))
                self.assertTrue(st.ARM_HATCH[3] < r < st.ARM_HATCH[4] - st.DOOR_DEPTH, f"{light['name']} inside its bay")
            elif light["kind"] == "main_docking_bay" and "entrance" in light["name"]:
                self.assertAlmostEqual(float(p[2]), sd.FACE_Z - 1.5, msg=light["name"])
                self.assertFalse(sd.contains(sd.opening(), float(p[0]), float(p[1])), f"{light['name']} on the block, by the mouth")
                self.assertTrue(sd.contains(sd.octagon(), float(p[0]), float(p[1])), light["name"])
            elif light["kind"] == "main_docking_bay":
                self.assertTrue(sd.FACE_Z < p[2] < sd.DOORS_Z, f"{light['name']} down the mouth, not in the black void")
                self.assertAlmostEqual(float(np.hypot(p[0], p[1])), 0.0)
            elif light["name"].startswith("cargo_bay_mouth"):
                self.assertLess(abs(float(p[2]) - sd.ZG_FRONT_Z), 2.0, f"{light['name']} at the mouth")
                self.assertLess(distance_to(self.tris["frame"], p), 3.0, f"{light['name']} on the mouth's frame")
            else:
                self.assertEqual(light["kind"], "cargo_bay")
                self.assertTrue(sd.ZG_FRONT_Z < p[2] < sd.ZG_BACK_Z and abs(p[0]) < sd.ZG_HALF_X, light["name"])
            if light["kind"] == "beacon":
                self.assertTrue(light.get("blink"))
                beat = (light["blink_period_s"], light["blink_off_s"], light["blink_ramp_s"], light["blink_full_s"])
                self.assertEqual(beat, (4.0, 1.0, 1.0, 1.0), "4 s: dark, fade up, full, fade down, 1 s each")
            if "marker" in light:
                self.assertGreater(light["marker"]["radius_m"], 0.0)
                self.assertEqual(len(light["marker"]["rgb"]), 3)
        tips = [light for light in self.hp["lights"] if light["name"].startswith("beacon_vane")]
        self.assertEqual(len(tips), 12)
        for light in tips:
            self.assertAlmostEqual(abs(self.at(light)[1]), st.VANE_TIP_Y, delta=0.01)

    def test_the_arms_nav_lights_are_red_pink(self) -> None:
        arms = [light for light in self.hp["lights"] if light["name"].startswith("nav_arm")]
        self.assertEqual(len(arms), 32, "four on each flank of each arm")
        for light in arms:
            r, g, b = light["marker"]["rgb"]
            hue = (360.0 - 60.0 * (b - g) / (r - g)) if r >= max(g, b) and b >= g else -1.0
            self.assertTrue(340.0 <= hue <= 360.0, f"{light['name']}: hue {hue:.0f}, red-pink")
            self.assertLess(max(g, b) / r, 0.15, "saturated, so the bloom keeps it red-pink")

    def flood_at(self, p, n) -> float:
        """The flood light (red channel) the hull shader sums at a station-frame point with normal ``n``."""
        p, n = np.asarray(p, dtype=float), np.asarray(n, dtype=float) / np.linalg.norm(n)
        total = 0.0
        for f in (light for light in self.hp["lights"] if light["kind"] == "flood"):
            to_light = self.at(f) - p
            d = float(np.linalg.norm(to_light))
            if d >= f["range_m"]:
                continue
            l = to_light / d
            lo, hi = math.cos(math.radians(f["outer_deg"])), math.cos(math.radians(f["inner_deg"]))
            x = min(max((float(np.dot(-l, f["direction"])) - lo) / (hi - lo), 0.0), 1.0)
            cone = x * x * (3.0 - 2.0 * x)
            fall = (1.0 - (d / f["range_m"]) ** 4) ** 2
            total += f["rgb"][0] * f["energy"] * cone * fall * max(float(np.dot(n, l)), 0.0)
        return total

    def test_the_floods_light_the_arms_and_keep_the_spheres_rear_face_dark(self) -> None:
        floods = [light for light in self.hp["lights"] if light["kind"] == "flood"]
        for f in floods:
            self.assertAlmostEqual(float(np.linalg.norm(f["direction"])), 1.0, places=3)
            self.assertLess(f["inner_deg"], f["outer_deg"], f["name"])
            self.assertTrue(all(0.0 <= c <= 1.0 for c in f["rgb"]) and f["energy"] > 0.0 and f["range_m"] > 0.0, f["name"])
        z = np.array([0.0, 0.0, 1.0])
        rear = max(self.flood_at([r * math.cos(a), r * math.sin(a), 941.0], z) for a in np.radians(np.arange(0, 360, 5))
                   for r in (200.0, 215.0, 230.0, 245.0))
        self.assertLess(rear, 0.05, "the arms capture shows the sphere's rear face dark")
        u, t = np.array([0.0, 1.0, 0.0]), np.array([-1.0, 0.0, 0.0])  # the top arm: out, across
        for zz in (1200.0, 1240.0, 1290.0):
            self.assertGreater(self.flood_at(u * 208.0 + t * 47.2 + [0.0, 0.0, zz], t), 1.0, f"the aft flank at z {zz:.0f}")
        for zz in (750.0, 800.0, 840.0):
            self.assertGreater(self.flood_at(u * 265.0 + t * 60.0 + [0.0, 0.0, zz], t), 1.0, f"the fore flank at z {zz:.0f}")

    def test_the_docking_ring_is_lit_in_pools_with_dark_gaps(self) -> None:
        lit = []
        for a in np.radians(np.arange(0.0, 360.0, 2.0)):
            radial = np.array([math.cos(a), math.sin(a), 0.0])
            lit.append(self.flood_at(radial * 118.0 + [0.0, 0.0, 474.5], [0.0, 0.0, -1.0]) > 0.3)  # the ring's face
        share = sum(lit) / len(lit)
        self.assertTrue(0.2 < share < 0.75, f"pools on the ring, not a wash: {share:.2f} of its face lit")
        runs = sum(1 for k in range(len(lit)) if lit[k] and not lit[k - 1])
        self.assertGreaterEqual(runs, 4, "separate pools round the ring")

    def test_the_tour_points_stand_clear_and_look_at_the_station(self) -> None:
        for tour in self.hp["tour_points"]:
            p, aim = self.at(tour), self.at(tour, "look_at")
            for body in ("drum", "frame"):
                self.assertGreater(distance_to(self.tris[body], p), 30.0, f"{tour['name']} is clear of the {body}")
            d = np.asarray(tour["direction"])
            np.testing.assert_allclose(d, (aim - p) / np.linalg.norm(aim - p), atol=1e-4)
            hit = min(ray_hit(self.tris[b], p, d) for b in ("drum", "frame"))
            self.assertLess(hit, 3000.0, f"{tour['name']} looks at the station")

    def test_a_tour_point_on_the_drum_clears_the_frame_through_a_whole_turn(self) -> None:
        for tour in self.hp["tour_points"]:
            if tour["body"] != "drum":
                continue
            p = self.at(tour)
            r = float(np.hypot(p[0], p[1]))
            for a in np.linspace(0.0, 2.0 * math.pi, 120, endpoint=False):
                turned = np.array([r * math.cos(a), r * math.sin(a), p[2]])
                self.assertGreater(distance_to(self.tris["frame"], turned), 30.0, f"{tour['name']} at {math.degrees(a):.0f} degrees")

    def test_the_damage_sections_cover_the_render_sections_once(self) -> None:
        for piece in ("drum", "frame"):
            names = [s["name"] for s in self.manifest["pieces"][piece]["mesh"]["sections"]]
            listed = [n for d in self.hp["damage_sections"] if d["body"] == piece for n in d["sections"]]
            self.assertEqual(listed, names, f"{piece}: every section once, bow to stern")
        for d in self.hp["damage_sections"]:
            self.assertTrue(np.all(np.asarray(d["aabb_max"]) > np.asarray(d["aabb_min"])), d["name"])

    def test_drum_hardpoints_turn_with_the_drum(self) -> None:
        # Given in the drum's frame, a bay stays over its door at any turn of the drum node.
        turn = math.radians(37.0)
        c, s = math.cos(turn), math.sin(turn)
        rot = np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])
        rest = _triangles(station.drum_parts())
        turned = rest @ rot.T
        for bay in self.hp["cobra_bays"][::5]:
            release, n = np.asarray(bay["release"]), np.asarray(bay["normal"])
            self.assertAlmostEqual(ray_hit(turned, rot @ release, -(rot @ n)), ray_hit(rest, release, -n), delta=1e-3, msg=bay["name"])


class BayShapeTests(unittest.TestCase):
    """The docking bay's geometry without a bake."""

    @classmethod
    def setUpClass(cls) -> None:
        mats = station.STYLE.materials
        cls.bay = sd.main_docking_bay(mats)
        cls.cargo = sd.cargo_bay(mats)

    def test_the_mouth_is_the_stls_scaled_to_80_m(self) -> None:
        # The STL's mouth (its band across a taller core, 45 m wide in the block's face) scaled with its block by 80/45 (M7-T25).
        self.assertAlmostEqual(sd.BAY_SCALE * 45.0, 80.0)
        hw, hh = sd.opening_half()
        self.assertAlmostEqual(hw, 20.6 * sd.BAY_SCALE)
        self.assertAlmostEqual(hh, 8.45 * sd.BAY_SCALE)
        outline = np.array(sd.opening())
        np.testing.assert_allclose(sorted(map(tuple, np.round(outline, 6))), sorted(map(tuple, np.round(outline * [-1.0, 1.0], 6))))
        np.testing.assert_allclose(sorted(map(tuple, np.round(outline, 6))), sorted(map(tuple, np.round(outline * [1.0, -1.0], 6))))
        self.assertTrue(sd.contains(outline, hw - 1.0, 0.0) and not sd.contains(outline, hw - 1.0, hh - 1.0), "the band is low")
        self.assertTrue(sd.contains(outline, 0.0, hh - 1.0), "the core is tall")
        self.assertAlmostEqual(sd.DOORS_Z - sd.FACE_Z, 40.5 * sd.BAY_SCALE, msg="the mouth's depth scaled with it")
        oct_ = np.array(sd.octagon())
        self.assertAlmostEqual(float(oct_[:, 0].max()), 47.5 * sd.BAY_SCALE)
        self.assertAlmostEqual(float(oct_[:, 1].max()), 25.5 * sd.BAY_SCALE)

    def test_no_self_lit_red_rings_round_the_mouth_only_lamps(self) -> None:
        # The maintainer (2026-11-14): the red is the lamps' light on grey metal, not glowing rings or bands. Of the bay's faces only
        # small lamps glow red more than the plating's faint tint; the frames are the plating.
        mats = station.STYLE.materials
        tint = mats["bay_tunnel"].emissive_strength
        tris = self.bay.vertices[self.bay.faces]
        area = 0.5 * np.linalg.norm(np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]), axis=1)
        red = np.array([m.emissive_strength > tint and m.emissive[0] > 4.0 * m.emissive[1] for m in self.bay.materials])
        glowing = red[self.bay.face_material]
        self.assertLess(float(area[glowing].max()), 4.0, "only lamp-sized faces glow red")
        self.assertLess(float(area[glowing].sum()), 200.0, "a few lamps (every side of their boxes), no rings")
        used = {m.name for m in self.bay.materials}
        for role in ("bay_tunnel", "bay_void", "bay_frame", "lamp"):
            self.assertIn(mats[role].name, used, role)
        for role in ("bay_red_0", "bay_red_1", "bay_red_3", "bay_red_4", "bay_red_5", "bay_pink", "bay_dark", "bay_wall"):
            self.assertNotIn(mats[role].name, used, f"{role}: no red strips, no black walls")
        void = mats["bay_void"]
        self.assertLess(max(void.albedo), 0.01, "the void behind the doors stays black")
        self.assertEqual(void.emissive_strength, 0.0)

    def test_the_doors_are_the_tunnels_grey_metal(self) -> None:
        swatch = sp.TUNNEL_SWATCH
        np.testing.assert_allclose(swatch.albedo, station.STYLE.materials["bay_tunnel"].albedo, atol=1e-6, err_msg="the plating's grey")
        self.assertEqual((swatch.metal, swatch.rough), (station.STYLE.materials["bay_tunnel"].metallic,
                                                         station.STYLE.materials["bay_tunnel"].roughness))
        self.assertLess(max(swatch.glow), 0.05, "only the faint tint, no glowing seam")
        v0, v1 = sp.PLATING_CELL * sp.CELL_H / sp.ATLAS_H, (sp.PLATING_CELL + 1) * sp.CELL_H / sp.ATLAS_H
        for upper in (True, False):
            uv = sp.airlock_leaf(upper).face_uv.reshape(-1, 2)
            self.assertTrue(np.all((uv[:, 1] > v0) & (uv[:, 1] < v1)), "every face of a leaf on the plating cell")
            self.assertGreater(float(np.ptp(uv[:, 0])), 0.9, "laid flat across it, not squeezed")
        cell = sp._plating_cell(7)
        np.testing.assert_allclose(np.median(cell["albedo"].reshape(-1, 3), axis=0), swatch.albedo, rtol=0.12, err_msg="the plating's grey")
        self.assertGreater(float(np.std(cell["albedo"][..., 0])), 0.003, "its tone drifts as the walls' does")
        self.assertTrue(all(k.world_detail for k in sp.kinds() if k.name.startswith("airlock_leaf")), "the walls' detail tile over it")
        self.assertFalse(any(k.world_detail for k in sp.kinds() if not k.name.startswith("airlock_leaf")), "and over nothing else")

    def test_the_mouth_is_metallic_grey_plating_with_a_faint_red_glow(self) -> None:
        # The show's look (the maintainer, 2026-11-14): grey metal lit red, not black walls with red strips. The lamps light it up
        # close; the faint glow is what it keeps at range.
        tunnel = station.STYLE.materials["bay_tunnel"]
        r, g, b = tunnel.albedo
        self.assertGreater(min(r, g, b), 0.15, "grey, not black")
        self.assertLess(max(r, g, b) - min(r, g, b), 0.05, "a neutral grey")
        self.assertGreaterEqual(tunnel.metallic, 0.6)
        self.assertLessEqual(tunnel.roughness, 0.4, "low roughness: the red lamps show in it")
        self.assertTrue(tunnel.paneled)
        self.assertGreater(tunnel.emissive[0], 4.0 * tunnel.emissive[1], "its glow is red")
        self.assertLess(tunnel.emissive_strength, station.STYLE.materials["bay_red_5"].emissive_strength, "and fainter than any frame")
        tris = self.bay.vertices[self.bay.faces]
        mats = [self.bay.materials[k].name for k in self.bay.face_material]
        centre = tris.mean(axis=1)
        inside = (centre[:, 2] > sd.FACE_Z + sd.LIP_M) & (centre[:, 2] < sd.DOORS_Z)
        grey = sum(1 for k in np.flatnonzero(inside) if mats[k] == tunnel.name)
        self.assertGreater(grey, 0.5 * int(inside.sum()), "most of the mouth's faces are the grey plating")

    def test_the_inner_doors_close_the_doorway_on_a_sawtooth_and_slide_clear(self) -> None:
        xs = np.linspace(-40.0, 40.0, 801)
        edge = sd.saw_edge(xs)
        height, period, gap = sd.SAW
        self.assertAlmostEqual(float(edge.max() - edge.min()), height, places=6)
        self.assertGreaterEqual(int(np.sum(np.diff(np.sign(np.diff(edge))) != 0)), 2 * int(70.0 / period), "teeth across the doorway")
        hw, hh = sd.opening_half()
        upper, lower = sd.door_leaf_outline(True), sd.door_leaf_outline(False)

        def covered(strips, x: float, y: float, shift: float = 0.0) -> bool:
            for a, b, ya, yb, far in strips:
                if a <= x <= b:
                    seam = ya + (yb - ya) * (x - a) / (b - a) + shift
                    return min(seam, far + shift) <= y <= max(seam, far + shift)
            return False

        outline = sd.opening()
        for x in np.linspace(-hw + 0.2, hw - 0.2, 61):
            for y in np.linspace(-hh + 0.2, hh - 0.2, 31):
                if not sd.contains(outline, x, y):
                    continue
                seam = float(sd.saw_edge(x))
                if seam - gap < y < seam:
                    continue  # the lit seam between the leaves
                self.assertTrue(covered(upper, x, y) or covered(lower, x, y), f"closed, ({x:.1f}, {y:.1f}) is behind a leaf")
                self.assertFalse(covered(upper, x, y, sd.DOOR_OPEN_M) or covered(lower, x, y, -sd.DOOR_OPEN_M),
                                 f"open, ({x:.1f}, {y:.1f}) is clear")
        # Through the doorway, with the doors open (they are props), the eye meets the black void's back wall.
        tris = self.bay.vertices[self.bay.faces]
        ray = np.array([0.5, float(sd.saw_edge(0.5)) - 0.5 * gap, sd.FACE_Z - 10.0])
        self.assertAlmostEqual(ray_hit(tris, ray, np.array([0.0, 0.0, 1.0])) + ray[2], sd.VOID_BACK_Z, delta=0.01)

    def test_the_void_holds_the_longest_tunnel_hull_behind_the_doors(self) -> None:
        depth = sd.VOID_BACK_Z - (sd.DOORS_Z + sd.DOOR_SLAB_M)
        self.assertGreaterEqual(depth, 70.0 + 20.0, "a 70 m hull wholly behind the doors with room fore and aft")
        hw, hh = sd.opening_half()
        self.assertGreater(sd.VOID_HALF[0], hw)
        self.assertGreater(sd.VOID_HALF[1], hh)

    def test_the_cargo_bay_is_a_roofed_compartment_in_red_lit_grey_metal(self) -> None:
        p = self.cargo.vertices
        self.assertLess(float(np.abs(p[:, 0]).max()), sd.ZG_HALF_X + 0.01, "inside the spine")
        self.assertTrue(np.all((p[:, 2] >= sd.ZG_FRONT_Z - sd.ZG_RING[1] - 1e-6) & (p[:, 2] <= sd.ZG_BACK_Z + 1e-6)))
        used = {m.name for m in self.cargo.materials}
        mats = station.STYLE.materials
        for role in ("bay_frame", "bay_tunnel", "machinery", "lamp"):
            self.assertIn(mats[role].name, used, role)
        for role in ("bay_wall", "bay_red_2", "bay_pink"):
            self.assertNotIn(mats[role].name, used, f"{role}: the docking bay's red-lit grey metal, no red strips (M7-T32)")
        tint = mats["bay_tunnel"].emissive_strength
        tris = self.cargo.vertices[self.cargo.faces]
        area = 0.5 * np.linalg.norm(np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]), axis=1)
        red = np.array([m.emissive_strength > tint and m.emissive[0] > 4.0 * m.emissive[1] for m in self.cargo.materials])
        self.assertLess(float(area[red[self.cargo.face_material]].max()), 4.0, "only lamp-sized faces glow red")
        spine = next(s.mesh for s in st.frame_shapes(mats) if s.name == "spine")
        names = np.array([spine.materials[k].name for k in spine.face_material])
        centre = spine.vertices[spine.faces].mean(axis=1)
        inside = sl.frame_interior(centre, spine.face_normals())
        self.assertTrue(np.all(names[inside] == mats["bay_tunnel"].name), "the walls, roof, floor and back wall inside lined with the grey metal")
        self.assertFalse(np.any(names[~inside] == mats["bay_tunnel"].name), "the spine outside keeps its paint")
        back = inside & (np.abs(centre[:, 2] - sd.ZG_BACK_Z) < 0.1)
        self.assertGreater(int(back.sum()), 0, "the back wall is lined too")
        walls = sd.cargo_bay_walls(mats["spine"]).vertices
        self.assertGreaterEqual(float(walls[:, 1].min()), 290.0 - 1e-6, "nothing under the keel (the STL's, down to the bow's pylon)")
        outline = np.array(sd.throat_outline())
        self.assertEqual(len(outline), 8, "the STL's octagonal throat")
        self.assertGreaterEqual(2.0 * sd.ZG_THROAT[0] - 31.1, 10.0, "a pod square-on through the throat")

    def test_the_drum_turns_inside_the_frames_ring(self) -> None:
        # In front of the ring's back face everything of the drum stays inside its bore, with room; the ring (frame) stays out of it.
        mats = station.STYLE.materials
        drum = np.concatenate([s.mesh.vertices for s in st.drum_shapes(mats)])
        ahead = drum[drum[:, 2] < st.RING_BACK_Z + 1.0]
        self.assertLessEqual(float(np.hypot(ahead[:, 0], ahead[:, 1]).max()), st.DRUM_FRONT_R + 1e-6)
        self.assertGreaterEqual(st.RING_INNER_R - st.DRUM_FRONT_R, 5.0)
        ring = next(s.mesh for s in st.frame_shapes(mats) if s.name == "bow").vertices
        near = ring[(ring[:, 2] > st.RING_FRONT_Z - 7.0) & (ring[:, 2] < st.RING_BACK_Z + 1.0) & (np.hypot(ring[:, 0], ring[:, 1]) < 150.0)]
        self.assertGreaterEqual(float(np.hypot(near[:, 0], near[:, 1]).min()), st.RING_INNER_R - 1e-6)


if __name__ == "__main__":
    unittest.main()
