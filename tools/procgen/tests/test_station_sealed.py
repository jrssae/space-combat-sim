"""The station is solid to the eye (M7): no line of sight through its hull, its halls closed behind their doors, and the faces
inside its halls and bays told apart so the game keeps the sun off them."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.assets import babylon5_station as b5
from tools.procgen.parts import station as st
from tools.procgen.parts import station_detail as sd
from tools.procgen.parts import station_layouts as sl
from tools.procgen.parts import station_props as sp
from tools.procgen.tests.coplanar_checks import mesh_triangles
from tools.procgen.tests.sealed_checks import escapes, see_through, sphere_directions

MATERIALS = b5.STYLE.materials


def arm_with_closed_doors() -> np.ndarray:
    """One Cobra arm on top of the drum (+y) with its lit sills and its twelve leaves shut."""
    floor = st.ARM_HATCH[4] - st.DOOR_DEPTH
    tris = [mesh_triangles(st.arm_mesh(MATERIALS["drum_grey"])), mesh_triangles(st.door_glow(MATERIALS["bay_light"]))]
    for number, centre in enumerate(st.launch_door_centres(), start=1):
        for side in (1.0, -1.0):
            tris.append(mesh_triangles(sp.door_leaf(number, side)) + np.array([st.LAUNCH_STRIP_X, floor, centre]))
    return np.concatenate(tris)


class HallTests(unittest.TestCase):
    def test_no_line_of_sight_leaves_a_launch_hall_with_its_doors_closed(self) -> None:
        tris = arm_with_closed_doors()
        directions = sphere_directions(400)
        _, _, z0, z1 = st.LAUNCH_HALL
        floor = st.ARM_HATCH[4] - st.DOOR_DEPTH
        upper_y, lower_y = 0.5 * (st.HALL_UPPER_R + floor), 0.5 * (st.HALL_CEILING_R + st.HALL_UPPER_R)
        centres = st.launch_door_centres()
        eyes = [(x, upper_y, z) for z in (z0 + 3.0, centres[0], 0.5 * (centres[2] + centres[3]), centres[5], z1 - 3.0) for x in (-15.0, 0.0, 15.0)]
        eyes += [(x, lower_y, z) for z in (centres[1], centres[4]) for x in (-35.0, 0.0, 35.0)]
        for eye in eyes:
            out = escapes(tris, np.array(eye), directions)
            self.assertFalse(out.any(), f"from {eye}: {int(out.sum())} rays reach space, e.g. toward {np.round(directions[out][:3], 2).tolist()}")

    def test_an_open_door_is_the_way_out(self) -> None:
        tris = np.concatenate([mesh_triangles(st.arm_mesh(MATERIALS["drum_grey"])), mesh_triangles(st.door_glow(MATERIALS["bay_light"]))])
        eye = np.array([0.0, st.ARM_HATCH[4] - st.DOOR_DEPTH - 6.0, st.launch_door_centres()[2]])
        self.assertTrue(escapes(tris, eye, np.array([[0.0, 1.0, 0.0]]))[0], "straight out through the door's hole, its leaves away")

    def test_the_leaves_meet_and_the_sills_reach_under_them(self) -> None:
        dx, dz = st.LAUNCH_DOOR_HALF
        right, left = sp.door_leaf(1, 1.0).bounds(), sp.door_leaf(1, -1.0).bounds()
        self.assertAlmostEqual(float(right[0][0]), 0.0)
        self.assertAlmostEqual(float(left[1][0]), 0.0)
        self.assertLess(dx - st.DOOR_SILL_M, float(right[1][0]) - 0.2, "the sill reaches in under the leaf's outer edge")
        self.assertLess(dz - st.DOOR_SILL_M, float(right[1][2]) - 0.2)


class BayTests(unittest.TestCase):
    """The two open bays: their mouths are the only way out."""

    def _only_through(self, tris: np.ndarray, eye: np.ndarray, mouth_z: float, inside) -> None:
        directions = sphere_directions(1500)
        out = directions[escapes(tris, eye, directions)]
        self.assertGreater(len(out), 0, "the mouth is open")
        for d in out:
            self.assertLess(d[2], 0.0, f"{d}: out of the back")
            s = (mouth_z - eye[2]) / d[2]
            self.assertTrue(inside(eye[0] + s * d[0], eye[1] + s * d[1]), f"{np.round(d, 3)}: not through the mouth")

    def test_the_main_docking_bay_opens_only_at_its_mouth(self) -> None:
        tris = np.concatenate([mesh_triangles(s.mesh) for s in st.drum_shapes(MATERIALS)])
        for eye in ((0.0, 0.0, 600.0), (20.0, -10.0, 520.0)):
            self._only_through(tris, np.array(eye), sd.layer_z(0), lambda x, y: abs(y) < sd.half_height(sd.MOUTH, x))

    def test_the_cargo_bay_opens_only_at_its_throat(self) -> None:
        tris = np.concatenate([mesh_triangles(s.mesh) for s in st.frame_shapes(MATERIALS)])
        (hx, _), (y0, y1) = sd.ZG_THROAT, sd.ZG_THROAT_Y
        for eye in ((0.0, sd.ZG_CENTRE_Y, 470.0), (30.0, 345.0, 480.0)):
            self._only_through(tris, np.array(eye), sd.ZG_FRONT_Z, lambda x, y: abs(x) < hx and y0 < y < y1)


class HullTests(unittest.TestCase):
    """The sun showed through the drum (M7): rings left open where two of its shells met, slits through the hollow hull."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.tris = np.concatenate([mesh_triangles(s.mesh) for s in st.drum_shapes(MATERIALS) + st.frame_shapes(MATERIALS)])

    def test_the_drums_shells_end_in_flanges_onto_each_other(self) -> None:
        profiles = (st.SPHERE_PROFILE, st.BODY_PROFILE, st.FWD_BAND_PROFILE, st.GREEN_PROFILE, st.AFT_BAND_PROFILE)
        for a, b in zip(profiles[:-1], profiles[1:], strict=True):
            end = st.sealed_profile(a, None, b)[-1]
            start = st.sealed_profile(b, a)[0]
            self.assertEqual(end[0], b[0][0])
            self.assertLessEqual(end[1], min(a[-1][1], b[0][1]) - st.SHELL_FLANGE_M + 1e-9)
            self.assertEqual(start, end, "the two flanges cover the same ring, back to back")
        with self.assertRaises(ValueError):
            st.sealed_profile([(0.0, 5.0), (10.0, 5.0)], None, [(11.0, 5.0), (20.0, 5.0)])

    def test_no_line_passes_through_a_joint_between_the_drums_shells(self) -> None:
        rng = np.random.default_rng(7)
        origins, directions = [], []
        for z, r in ((945.0, 192.0), (1692.0, 330.0), (2348.0, 332.0), (4782.0, 334.0)):
            for _ in range(250):
                turn = rng.uniform(0.0, 2.0 * np.pi)
                through = np.array([np.cos(turn) * (r + rng.uniform(-3.0, 3.0)), np.sin(turn) * (r + rng.uniform(-3.0, 3.0)), z])
                d = rng.normal(size=3)
                d /= np.linalg.norm(d)
                origins.append(through - d * 20_000.0)
                directions.append(d)
        leaks = see_through(self.tris, np.array(origins), np.array(directions))
        self.assertEqual(int(leaks.sum()), 0, f"lines through the hull: toward {np.round(np.array(directions)[leaks][:3], 2).tolist()}")

    def test_no_line_passes_through_the_station(self) -> None:
        rng = np.random.default_rng(11)
        origins, directions = [], []
        for _ in range(1500):
            through = np.array([rng.uniform(-900.0, 900.0), rng.uniform(-900.0, 900.0), rng.uniform(0.0, b5.LENGTH_M)])
            d = rng.normal(size=3)
            d /= np.linalg.norm(d)
            origins.append(through - d * 20_000.0)
            directions.append(d)
        leaks = see_through(self.tris, np.array(origins), np.array(directions))
        self.assertEqual(int(leaks.sum()), 0, f"lines through the hull: toward {np.round(np.array(directions)[leaks][:3], 2).tolist()}")


class InteriorTests(unittest.TestCase):
    """Which faces the game draws out of the sun's light."""

    def _flags(self, points: list[tuple[float, float, float]], normals: list[tuple[float, float, float]], frame: bool = False) -> list[bool]:
        test = sl.frame_interior if frame else sl.drum_interior
        return [bool(v) for v in test(np.array(points, dtype=float), np.array(normals, dtype=float))]

    def test_the_halls_wells_and_sills_are_inside_and_the_deck_is_not(self) -> None:
        top = st.ARM_HATCH[4]
        floor = top - st.DOOR_DEPTH
        z = st.launch_door_centres()[2]
        between = 0.5 * (st.launch_door_centres()[2] + st.launch_door_centres()[3])
        up, side = (0.0, 1.0, 0.0), (-1.0, 0.0, 0.0)
        flags = self._flags([
            (20.0, 0.5 * (st.HALL_UPPER_R + floor), z),  # the upper hall's wall
            (st.HALL_LOWER_HALF, 0.5 * (st.HALL_CEILING_R + st.HALL_UPPER_R), z),  # the lower hall's wall
            (st.LAUNCH_DOOR_HALF[0], floor + 2.0, z),  # a well's wall
            (st.LAUNCH_DOOR_HALF[0] - 0.4, floor + st.DOOR_GLOW_TOP_M, z),  # a sill's top
            (0.0, top, between),  # the deck between two doors
            (30.0, top - 3.0, z),  # the arm's chamfer outside
            (0.0, 0.5 * (st.HALL_UPPER_R + floor), st.LAUNCH_HALL[2]),  # the hall's fore end wall
        ], [side, side, side, up, up, (0.7, 0.7, 0.0), (0.0, 0.0, 1.0)])
        self.assertEqual(flags, [True, True, True, True, False, False, True])

    def test_every_arm_is_told_the_same(self) -> None:
        floor = st.ARM_HATCH[4] - st.DOOR_DEPTH
        r, z = 0.5 * (st.HALL_UPPER_R + floor), st.launch_door_centres()[0]
        points = [(0.0, r, z), (r, 0.0, z), (0.0, -r, z), (-r, 0.0, z)]
        self.assertEqual(self._flags(points, [(0.0, 0.0, 1.0)] * 4), [True] * 4)

    def test_the_docking_bay_is_inside_from_its_mouth_to_the_airlock(self) -> None:
        x = sd.tunnel()[0][0]
        flags = self._flags([(x, 0.0, 600.0), (0.0, 0.0, sd.AIRLOCK_Z), (60.0, 40.0, sd.BLOCK[2]), (0.0, 300.0, 600.0)],
                            [(-1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)])
        self.assertEqual(flags, [True, True, False, False], "the tunnel's wall, the airlock, the block's face outside, the sphere's skin")

    def test_the_cargo_bay_is_inside_behind_its_throat(self) -> None:
        flags = self._flags([(sd.ZG_HALF_X, sd.ZG_CENTRE_Y, 470.0), (0.0, sd.ZG_THROAT_Y[0], 430.0), (0.0, sd.ZG_CENTRE_Y + 60.0, sd.ZG_FRONT_Z),
                             (0.0, 480.0, 470.0)],
                            [(-1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)], frame=True)
        self.assertEqual(flags, [True, True, False, False], "the compartment's wall, the throat's floor, the spine's front, its top")

    def test_the_leaves_and_gantries_are_inside_and_the_clamps_on_the_deck_are_not(self) -> None:
        inside = {k.name: k.interior for k in sp.kinds()}
        self.assertTrue(all(v for name, v in inside.items() if name != "clamp"))
        self.assertFalse(inside["clamp"])
        self.assertFalse(any(k.interior for k in sp.frame_kinds()), "the command section's windows are outside")


if __name__ == "__main__":
    unittest.main()
