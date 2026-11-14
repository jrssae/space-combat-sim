"""The station's near field and hardpoints (M7-T05): the main docking bay (its tunnel open to traffic, closed at the airlock), the
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

SMALL = (1024, 1024, 64)
# D75 as approved (docs/milestones/m7-babylon-5-station.md), station frame: name, kind, body, position, up.
D75 = [
    ("L1", "light_pulse", "drum", (-41, 292, 690), (0, 1, 0)), ("L2", "light_pulse", "drum", (41, 292, 690), (0, 1, 0)),
    ("L3", "light_pulse", "drum", (292, 41, 690), (1, 0, 0)), ("L4", "light_pulse", "drum", (292, -41, 690), (1, 0, 0)),
    ("L5", "light_pulse", "drum", (41, -292, 690), (0, -1, 0)), ("L6", "light_pulse", "drum", (-41, -292, 690), (0, -1, 0)),
    ("L7", "light_pulse", "drum", (-292, -41, 690), (-1, 0, 0)), ("L8", "light_pulse", "drum", (-292, 41, 690), (-1, 0, 0)),
    ("L9", "light_pulse", "frame", (0, 507, 1500), (0, 0.98, -0.21)), ("L10", "light_pulse", "frame", (0, 537, 2650), (0, 1, 0)),
    ("L11", "light_pulse", "frame", (0, 537, 4500), (0, 1, 0)), ("L12", "light_pulse", "frame", (0, 472, 5650), (0, 1, 0)),
    ("H1", "heavy_cannon", "frame", (-45, 375, 515), (0, 0.99, -0.13)), ("H2", "heavy_cannon", "frame", (45, 375, 515), (0, 0.99, -0.13)),
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
        self.assertEqual(kinds, {"beacon": 14, "running": 8, "ring": 7, "bay": 24, "main_docking_bay": 2, "cargo_bay": 2})
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
            # Looking down its up from above, the first surface is its plinth's face just over the pivot, on its own piece.
            n = np.asarray(m["up"])
            down = ray_hit(self.tris[body], self.at(m) + 20.0 * n, -n)
            self.assertAlmostEqual(20.0 - down, sd.PLINTH_TOP_M, delta=0.05, msg=f"{name} sits on its plinth")
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
            for hinge in bay["leaves"]:  # each leaf hinges on its outer edge, on the doors' plane, along the arm
                p = np.asarray(hinge["point"]) + self.shift["drum"]
                self.assertAlmostEqual(float(p @ n), floor, delta=0.01)
                self.assertAlmostEqual(abs(float((p - door) @ np.asarray(bay["across"]))), 9.6, delta=0.01)
                self.assertEqual(hinge["axis"], [0.0, 0.0, 1.0])
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

    def test_the_main_docking_bay_runs_down_the_axis_to_the_airlock(self) -> None:
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
        self.assertAlmostEqual(float(self.at(bay, "main_docking_bay_mouth")[2]), sd.BLOCK[2])
        # The mouth's face is the drum's front: nothing of the drum stands ahead of it but the grilles.
        self.assertGreater(float(self.tris["drum"][:, :, 2].min()), sd.BLOCK[2] - 2.0)
        # Straight down the axis, the first thing met is the airlock's doors.
        self.assertAlmostEqual(ray_hit(self.tris["drum"], path[0], np.array([0.0, 0.0, 1.0])), sd.AIRLOCK_Z - path[0][2], delta=0.01)

    def test_the_tunnel_is_open_in_collision_and_closed_at_the_airlock(self) -> None:
        drum = next(e for e in self.manifest["collision"]["pieces"] if e["name"] == "drum")
        shapes = col.shapes_from_entry(drum)
        hw, hh = self.hp["main_docking_bay"]["main_docking_bay_clear_half_m"]
        self.assertGreaterEqual(2.0 * hw, 80.0, "the clear passage takes the small civilians")
        self.assertGreaterEqual(2.0 * hh, 30.0)
        zs = np.arange(sd.BLOCK[2] - 60.0, sd.AIRLOCK_Z - 0.5, 2.0)
        inside = np.array([[x, y, z] for z in zs for x in np.linspace(-hw + 0.5, hw - 0.5, 9) for y in np.linspace(-hh + 0.5, hh - 0.5, 5)])
        inside = inside - station.DRUM_CENTRE
        for shape in shapes:
            gap = shape.distance(inside)
            self.assertGreater(float(gap.min()), 0.3, f"{shape.name} blocks the tunnel at {inside[int(np.argmin(gap))] + station.DRUM_CENTRE}")
        past = np.array([[0.0, 0.0, sd.AIRLOCK_Z + 5.0]]) - station.DRUM_CENTRE
        self.assertTrue(any(float(s.distance(past)[0]) <= 0.0 for s in shapes), "the airlock closes the tunnel")
        for side in ((hw + 1.5, 0.0), (-hw - 1.5, 0.0), (0.0, hh + 1.5), (0.0, -hh - 1.5)):
            wall = np.array([[side[0], side[1], 560.0]]) - station.DRUM_CENTRE
            self.assertTrue(any(float(s.distance(wall)[0]) <= 0.0 for s in shapes), f"a wall beside the passage at {side}")

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
            if light["kind"] in ("beacon", "running", "ring"):
                self.assertLess(distance_to(self.tris[body], p), 3.0, f"{light['name']} on the hull")
                self.assertGreater(distance_to(self.tris[other], p), 5.0, f"{light['name']} on the right piece")
            elif light["kind"] == "bay":
                r = float(np.hypot(p[0], p[1]))
                self.assertTrue(st.ARM_HATCH[3] < r < st.ARM_HATCH[4] - st.DOOR_DEPTH, f"{light['name']} inside its bay")
            elif light["kind"] == "main_docking_bay":
                self.assertTrue(sd.BLOCK[2] < p[2] < sd.AIRLOCK_Z, light["name"])
                self.assertAlmostEqual(float(np.hypot(p[0], p[1])), 0.0)
            else:
                self.assertEqual(light["kind"], "cargo_bay")
                self.assertTrue(sd.ZG_FRONT_Z < p[2] < sd.ZG_BACK_Z and abs(p[0]) < sd.ZG_HALF_X, light["name"])
            if light["kind"] == "beacon":
                self.assertTrue(light.get("blink"))
            if light["kind"] == "ring":
                self.assertAlmostEqual(float(np.hypot(p[0], p[1])), light["radius"], delta=0.01)
                self.assertEqual(light["axis"], [0.0, 0.0, 1.0])
        tips = [light for light in self.hp["lights"] if light["name"].startswith("beacon_vane")]
        self.assertEqual(len(tips), 12)
        for light in tips:
            self.assertAlmostEqual(abs(self.at(light)[1]), st.VANE_TIP_Y, delta=0.01)

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

    def test_the_mouth_is_a_stepped_cross_stepping_in_to_the_tunnel(self) -> None:
        outer, inner = sd.mouth(0), sd.tunnel()
        self.assertEqual(len(outer), 3, "three steps a quadrant: notched corners")
        for (xa, ya), (xb, yb) in zip(outer[:-1], outer[1:], strict=True):
            self.assertGreater(xa, xb)
            self.assertLess(ya, yb)
        for k in range(1, sd.MOUTH_LAYERS):
            for (xa, ya), (xb, yb) in zip(sd.mouth(k - 1), sd.mouth(k), strict=True):
                self.assertAlmostEqual(xa - xb, sd.MOUTH_INSET)
                self.assertAlmostEqual(ya - yb, sd.MOUTH_INSET)
        self.assertEqual(sd.half_height(inner, 0.0), inner[-1][1])
        self.assertEqual(sd.half_height(inner, inner[0][0] + 1.0), 0.0)

    def test_the_frames_glow_red_and_dimmer_the_deeper(self) -> None:
        strengths = []
        for k in range(6):
            m = station.STYLE.materials[f"bay_red_{k}"]
            self.assertGreater(m.emissive[0], 4.0 * m.emissive[1], "red")
            strengths.append(m.emissive_strength)
        self.assertEqual(strengths, sorted(strengths, reverse=True))
        used = {m.name for m in self.bay.materials}
        for role in ("bay_red_0", "bay_red_5", "bay_wall", "bay_door", "bay_pink", "bay_dark", "bay_frame", "lamp"):
            self.assertIn(station.STYLE.materials[role].name, used, role)

    def test_the_airlock_doors_meet_on_a_sawtooth_with_a_gap(self) -> None:
        xs = np.linspace(-40.0, 40.0, 801)
        edge = sd.saw_edge(xs)
        height, period, gap = sd.SAW
        self.assertAlmostEqual(float(edge.max() - edge.min()), height, places=6)
        self.assertGreaterEqual(int(np.sum(np.diff(np.sign(np.diff(edge))) != 0)), 2 * int(80.0 / period), "teeth across the tunnel")
        self.assertGreater(gap, 0.5)
        # Through the seam the eye meets the dark wall behind the doors; elsewhere the doors.
        tris = self.bay.vertices[self.bay.faces]
        seam = np.array([0.5, float(sd.saw_edge(0.5)) - 0.5 * gap, sd.BLOCK[2] - 10.0])
        door = np.array([0.5, 15.0, sd.BLOCK[2] - 10.0])  # between the door's ribs
        ahead = np.array([0.0, 0.0, 1.0])
        self.assertAlmostEqual(ray_hit(tris, seam, ahead) + seam[2], sd.TUNNEL_BACK_Z, delta=0.01)
        self.assertAlmostEqual(ray_hit(tris, door, ahead) + door[2], sd.AIRLOCK_Z, delta=0.01)

    def test_the_cargo_bay_is_a_roofed_compartment_dark_with_red_edges(self) -> None:
        p = self.cargo.vertices
        self.assertLess(float(np.abs(p[:, 0]).max()), sd.ZG_HALF_X + 0.01, "inside the spine")
        self.assertTrue(np.all((p[:, 2] >= sd.ZG_FRONT_Z - sd.ZG_RING[1] - 1e-6) & (p[:, 2] <= sd.ZG_BACK_Z + 1e-6)))
        used = {m.name for m in self.cargo.materials}
        mats = station.STYLE.materials
        for role in ("bay_frame", "bay_wall", "bay_red_2", "bay_pink", "lamp"):
            self.assertIn(mats[role].name, used, role)
        self.assertEqual(mats["bay_wall"].emissive_strength, 0.0, "dark machinery; only edges and lamps glow")
        walls = sd.cargo_bay_walls(mats["spine"]).vertices
        self.assertGreaterEqual(float(walls[:, 1].min()), 290.0 - 1e-6, "nothing under the keel (the STL's, down to the bow's pylon)")
        outline = np.array(sd.throat_outline())
        self.assertEqual(len(outline), 8, "the STL's octagonal throat")
        self.assertGreaterEqual(2.0 * sd.ZG_THROAT[0] - 31.1, 10.0, "a pod square-on through the throat")

    def test_the_bay_turns_inside_the_frames_ring(self) -> None:
        # The door turns with the drum; ahead of the frame's ring (z 488) it may reach past the ring's bore, behind it never.
        p = self.bay.vertices
        r = np.hypot(p[:, 0], p[:, 1])
        behind = p[:, 2] > st.RING_FRAME[0] - 8.0
        self.assertLessEqual(float(r[behind].max()), st.DOOR_R + 1e-6)
        self.assertLess(float(r.max()), st.RING_FRAME[2] + 1.0)
        self.assertLess(float(p[r > st.DOOR_R + 1e-6][:, 2].max()), st.RING_FRAME[0] - 8.0)


if __name__ == "__main__":
    unittest.main()
