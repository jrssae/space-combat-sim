"""The Starfury's cockpit interior (M3-T29, AC40): the opening it records, a shell with no gaps, and screens that face the pilot.

Everything here is measured with rays from the eye, because the camera never leaves it: what a ray hits first is what the pilot sees."""

from __future__ import annotations

import unittest

import numpy as np

from ..parts import cockpit
from ..styles.earthforce import EARTHFORCE as S

SPEC = cockpit.CockpitSpec()
EYE = (0.0, 0.7, -3.85)
FOCAL_PX = SPEC.focal_px


def directions(screen: np.ndarray) -> np.ndarray:
    """Unit rays through 1080p screen points, centred with Y up, for the camera looking along -Z."""
    points = np.asarray(screen, dtype=float).reshape(-1, 2)
    out = np.column_stack([points[:, 0] / FOCAL_PX, points[:, 1] / FOCAL_PX, -np.ones(len(points))])
    return out / np.linalg.norm(out, axis=1, keepdims=True)


def sphere(count: int) -> np.ndarray:
    index = np.arange(count) + 0.5
    polar = np.arccos(1.0 - 2.0 * index / count)
    turn = np.pi * (1.0 + 5.0**0.5) * index
    return np.column_stack([np.cos(turn) * np.sin(polar), np.sin(turn) * np.sin(polar), np.cos(polar)])


def first_hit(origin: np.ndarray, rays: np.ndarray, triangles: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Per ray, the distance to the first triangle and that triangle's index (inf and -1 for a miss)."""
    corner, e1, e2 = triangles[:, 0] - origin, triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0]
    best, which = np.full(len(rays), np.inf), np.full(len(rays), -1)
    for start in range(0, len(rays), 256):
        chunk = rays[start : start + 256]
        p = np.cross(chunk[:, None, :], e2[None, :, :])
        det = np.einsum("ijk,jk->ij", p, e1)
        safe = np.where(np.abs(det) < 1e-12, 1e-12, det)
        tvec = -corner
        u = np.einsum("jk,ijk->ij", tvec, p) / safe
        q = np.cross(tvec, e1)
        v = np.einsum("ik,jk->ij", chunk, q) / safe
        t = np.einsum("jk,jk->j", e2, q)[None, :] / safe
        hit = (np.abs(det) > 1e-12) & (u >= 0.0) & (v >= 0.0) & (u + v <= 1.0) & (t > 1e-4)
        t = np.where(hit, t, np.inf)
        nearest = t.argmin(axis=1)
        distance = t[np.arange(len(chunk)), nearest]
        best[start : start + 256] = distance
        which[start : start + 256] = np.where(np.isfinite(distance), nearest, -1)
    return best, which


class CockpitInteriorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.eye = np.array(EYE)
        cls.mesh = cockpit.cockpit_interior(SPEC, EYE, S)
        cls.triangles = cls.mesh.vertices[cls.mesh.faces]
        cls.names = [cls.mesh.materials[i].name for i in cls.mesh.face_material]

    def hits(self, screen) -> np.ndarray:
        return first_hit(self.eye, directions(screen), self.triangles)[0]

    # --- the opening ---------------------------------------------------------------------------
    def test_the_v_is_narrow_at_the_console_and_wide_above(self) -> None:
        opening = SPEC.opening_half_px
        self.assertLess(opening(SPEC.opening_floor_y_px), opening(0.0))
        self.assertLess(opening(0.0), opening(SPEC.bar_y_px))
        # The recorded numbers: wider at the horizon than Q29's first +-10 deg, since the struts now land on the octagon.
        self.assertAlmostEqual(cockpit.opening_half_deg(SPEC, 0.0), 15.9, delta=0.2)
        self.assertAlmostEqual(cockpit.opening_half_deg(SPEC, SPEC.bar_y_px), 29.3, delta=0.2)
        self.assertAlmostEqual(cockpit.opening_half_deg(SPEC, SPEC.opening_floor_y_px), 11.2, delta=0.3)

    def test_nothing_of_the_interior_is_inside_the_v(self) -> None:
        rows = np.linspace(SPEC.opening_floor_y_px + 2.0, SPEC.bar_y_px - 2.0, 60)
        points = []
        for y in rows:
            half = SPEC.opening_half_px(float(y)) - 2.0
            points += [(float(x), float(y)) for x in np.linspace(-half, half, 21)]
        self.assertFalse(np.isfinite(self.hits(np.array(points))).any())

    def test_the_crosshairs_area_is_clear(self) -> None:
        box = cockpit.CROSSHAIR_CLEAR_PX
        self.assertGreater(SPEC.opening_half_px(-box), box, "the V's width holds the box at its lower edge")
        self.assertLess(SPEC.opening_floor_y_px, -box, "and the octagon stops below it")

    def test_struts_flank_the_v_and_side_panes_lie_beyond_them(self) -> None:
        for y in (-40.0, 0.0, 150.0, 300.0):
            inner = SPEC.opening_half_px(y)
            outer = SPEC.strut_outer_px(y)
            self.assertGreater(outer - inner, 80.0, "a strut with depth")
            for sign in (-1.0, 1.0):
                on_strut = np.array([(sign * (inner + 6.0), y), (sign * 0.5 * (inner + outer), y), (sign * (outer - 6.0), y)])
                self.assertTrue(np.isfinite(self.hits(on_strut)).all(), (sign, y))
                in_pane = np.array([(sign * (outer + 8.0), y), (sign * 800.0, y)])
                self.assertFalse(np.isfinite(self.hits(in_pane)).any(), (sign, y))

    def test_a_bar_closes_the_top_and_sills_close_the_bottom_across_the_width(self) -> None:
        for x in (-900.0, -500.0, 0.0, 500.0, 900.0):
            self.assertTrue(np.isfinite(self.hits(np.array([(x, 535.0)]))).all(), f"top bar at {x}")
            self.assertTrue(np.isfinite(self.hits(np.array([(x, -535.0)]))).all(), f"below at {x}")
        self.assertFalse(np.isfinite(self.hits(np.array([(800.0, -60.0), (-800.0, -60.0)]))).any(), "open space over the sills")

    def test_the_sill_line_falls_away_from_the_console(self) -> None:
        self.assertGreater(SPEC.sill_y_px(300.0), SPEC.sill_y_px(900.0))
        self.assertLess(SPEC.sill_y_px(900.0), SPEC.opening_floor_y_px)

    # --- the struts land on the octagon, and no console stands above it -----------------------------
    def bezel_px(self) -> np.ndarray:
        """The octagon's bezel on a 1080p screen, eight corners, port top first."""
        screen = cockpit.cockpit_screens(SPEC, EYE)["octagon"]
        centre, up, normal = (np.array(screen[k]) for k in ("center", "up", "normal"))
        right = np.cross(up, normal)
        hw, hh, c = 0.5 * screen["size"][0] + 0.022, 0.5 * screen["size"][1] + 0.022, screen["corner"] + 0.022 * 0.6
        shape = ((-hw + c, hh), (hw - c, hh), (hw, hh - c), (hw, -hh + c), (hw - c, -hh), (-hw + c, -hh), (-hw, -hh + c), (-hw, hh - c))
        # On the bezel's face, which stands off the screen.
        rel = np.array([centre + a * right + b * up + normal * 0.009 for a, b in shape]) - self.eye
        return FOCAL_PX * rel[:, :2] / -rel[:, 2:]

    def test_the_opening_runs_down_to_the_octagons_top_edge(self) -> None:
        top_edge = float(self.bezel_px()[0, 1])
        self.assertAlmostEqual(SPEC.opening_floor_y_px, top_edge, delta=1.5, msg="the recorded floor is the bezel's top")
        self.assertFalse(np.isfinite(self.hits(np.array([(0.0, top_edge + 3.0)]))).any(), "open just above it")
        self.assertTrue(np.isfinite(self.hits(np.array([(0.0, top_edge - 3.0)]))).all(), "the bezel just below it")
        for x, y in ((0.0, -100.0), (60.0, -120.0), (-60.0, -120.0), (100.0, -150.0), (-100.0, -150.0)):
            self.assertFalse(np.isfinite(self.hits(np.array([(x, y)]))).any(), f"no console hump at {x}, {y}")

    def test_each_strut_lands_on_the_octagons_side(self) -> None:
        bezel = self.bezel_px()
        top_right, side_top = bezel[1], bezel[2]
        names = [self.mesh.materials[i].name for i in self.mesh.face_material]
        for sign in (-1.0, 1.0):
            # Its inner edge meets the cut corner, not the top edge and not out past the octagon.
            foot_x = SPEC.opening_half_px(SPEC.strut_foot_y_px)
            self.assertGreater(foot_x, float(top_right[0]), "clear of the octagon's top edge")
            self.assertLess(foot_x, float(side_top[0]) + 2.0, "and on the octagon, not beside it")
            # Between the feet and the frame's edge there is no gap: rays just above the rim hit strut, and it is the strut's red face.
            along = 0.5 * (top_right + side_top)
            _, which = first_hit(self.eye, directions(np.array([(sign * float(along[0]), float(along[1]) + 14.0)])), self.triangles)
            self.assertGreaterEqual(int(which[0]), 0, "the strut stands on the rim")
            self.assertTrue(names[which[0]].startswith(("ef_cockpit_red", "ef_cockpit_dark", "ef_cockpit_metal")), names[which[0]])

    def test_the_struts_outer_edge_meets_the_octagons_side_too(self) -> None:
        bezel = self.bezel_px()
        side_top = bezel[2]
        outer_at_side = SPEC.strut_outer_px(float(side_top[1]))
        self.assertLess(abs(outer_at_side - float(side_top[0])), 14.0, "at the corner where the cut meets the side")

    # --- the maintainer's change to Q29: slim struts, low sills, a thin bar -------------------------
    def test_the_struts_are_slim(self) -> None:
        # About 200 px where they leave the top of the frame, tapering to about 100 px at the octagon.
        top_of_frame, at_octagon = 540.0, SPEC.strut_foot_y_px
        self.assertLessEqual(SPEC.strut_outer_px(top_of_frame) - SPEC.opening_half_px(top_of_frame), 200.0)
        self.assertLessEqual(SPEC.strut_outer_px(at_octagon) - SPEC.opening_half_px(at_octagon), 105.0)

    def test_outside_the_screens_the_sills_are_75_px_tall_at_1080p(self) -> None:
        # Their top edge is at y 1005 of 1080, 465 px below the centre, measured with rays so the mesh is held to it and not only the numbers.
        top = -465.0
        self.assertEqual(cockpit.SILL_HEIGHT_PX, 75.0)
        for x in (740.0, 800.0, 900.0, 955.0):
            self.assertEqual(SPEC.sill_y_px(x), top)
            for sign in (-1.0, 1.0):
                self.assertFalse(np.isfinite(self.hits(np.array([(sign * x, top + 2.0)]))).any(), f"open space just above the sill at {sign * x}")
                self.assertTrue(np.isfinite(self.hits(np.array([(sign * x, top - 2.0)]))).all(), f"the sill just below its top edge at {sign * x}")
                self.assertTrue(np.isfinite(self.hits(np.array([(sign * x, -538.0)]))).all(), f"and it runs to the frame's bottom at {sign * x}")

    def test_the_round_lamps_fit_inside_the_sills_band(self) -> None:
        lamps = [i for i, m in enumerate(self.mesh.materials) if m.name == "ef_cockpit_lamp"][0]
        points = self.mesh.vertices[np.unique(self.mesh.faces[self.mesh.face_material == lamps])] - self.eye
        screen_y = FOCAL_PX * points[:, 1] / -points[:, 2]
        self.assertLess(float(screen_y.max()), -465.0, "below the sill's top edge")
        self.assertGreater(float(screen_y.min()), -540.0, "above the frame's bottom")
        screen_x = FOCAL_PX * np.abs(points[:, 0]) / -points[:, 2]
        self.assertLess(float(screen_x.max()), 960.0, "inside the frame at 16:9")
        # They read round: as wide as tall on screen.
        right = points[points[:, 0] > 0.0]
        wide = FOCAL_PX * np.ptp(right[:, 0] / -right[:, 2])
        tall = FOCAL_PX * np.ptp(right[:, 1] / -right[:, 2])
        self.assertAlmostEqual(wide / tall, 1.0, delta=0.1)
        # And nothing buries them: the ray through a lamp's middle meets the lamp first, and its collar's edge is whole too.
        names = [self.mesh.materials[i].name for i in self.mesh.face_material]
        middle = right.mean(axis=0)
        _, which = first_hit(self.eye, (middle / np.linalg.norm(middle))[None, :], self.triangles)
        self.assertEqual(names[which[0]], "ef_cockpit_lamp")
        for offset in ((0.0, -20.0), (0.0, 20.0), (-20.0, 0.0), (20.0, 0.0)):
            point = np.array([FOCAL_PX * middle[0] / -middle[2] + offset[0], FOCAL_PX * middle[1] / -middle[2] + offset[1]])
            _, ring = first_hit(self.eye, directions(point[None, :]), self.triangles)
            self.assertEqual(names[ring[0]], "ef_cockpit_dark", offset)

    def test_nothing_stands_above_the_sill_outside_the_screens(self) -> None:
        # The view past the screens is open from the sill up to the top bar.
        for sign in (-1.0, 1.0):
            column = np.array([(sign * 850.0, y) for y in np.linspace(-460.0, SPEC.bar_y_px - 3.0, 60)])
            self.assertFalse(np.isfinite(self.hits(column)).any())

    def test_the_top_bar_is_thin(self) -> None:
        self.assertLessEqual(540.0 - SPEC.bar_y_px, 20.0)
        self.assertTrue(np.isfinite(self.hits(np.array([(0.0, SPEC.bar_y_px + 3.0)]))).all())
        self.assertFalse(np.isfinite(self.hits(np.array([(0.0, SPEC.bar_y_px - 3.0)]))).any())

    # --- free look ---------------------------------------------------------------------------
    def test_the_shell_has_no_gaps_outside_the_openings(self) -> None:
        # Free look reaches 135 deg to the side and 80 deg up and down, so every direction can come on screen.
        rays = sphere(8000)
        distance, _ = first_hit(self.eye, rays, self.triangles)
        misses = rays[~np.isfinite(distance)]
        self.assertGreater(len(misses), 300, "the openings are open")
        azimuth = np.degrees(np.arctan2(np.abs(misses[:, 0]), -misses[:, 2]))
        elevation = np.degrees(np.arctan2(misses[:, 1], np.hypot(misses[:, 0], misses[:, 2])))
        self.assertLess(float(azimuth.max()), cockpit.PANE_AFT_DEG, "nothing open aft of the side panes")
        self.assertLess(float(elevation.max()), 37.5, "nothing open above the top bar")
        self.assertGreater(float(elevation.min()), -45.0, "nothing open below the sills")

    def test_the_shell_is_close_to_the_pilot(self) -> None:
        rays = sphere(2000)
        distance, _ = first_hit(self.eye, rays, self.triangles)
        hit = np.isfinite(distance)
        self.assertGreater(float(distance[hit].min()), 0.12, "clear of the head and the near plane")
        self.assertLess(float(distance[rays[:, 2] > 0.5].max()), 1.5, "the bulkhead is just behind the pilot")

    # --- what it is built from -----------------------------------------------------------------
    def test_the_parts_are_all_there(self) -> None:
        names = set(self.names)
        for material in ("ef_cockpit_red", "ef_cockpit_dark", "ef_cockpit_metal", "ef_cockpit_lamp", "ef_cockpit_rim"):
            self.assertIn(material, names)
        for lamp in cockpit.INDICATORS:
            self.assertIn(f"ef_cockpit_ind_{lamp}", names)

    def test_the_struts_inner_faces_are_the_red_ones_and_the_lamps_are_on_the_sills(self) -> None:
        y = 120.0
        inner = SPEC.opening_half_px(y)
        outer = SPEC.strut_outer_px(y)
        _, which = first_hit(self.eye, directions(np.array([(inner + 0.47 * (outer - inner), y)])), self.triangles)
        self.assertTrue(self.names[which[0]].startswith("ef_cockpit_red"), self.names[which[0]])
        lamp_index = next(i for i, m in enumerate(self.mesh.materials) if m.name == "ef_cockpit_lamp")
        lamps = self.mesh.vertices[np.unique(self.mesh.faces[self.mesh.face_material == lamp_index])] - self.eye
        self.assertGreater(float(np.abs(lamps[:, 0]).min()), 0.4, "out on the sills, not on the console")
        self.assertLess(float(lamps[:, 1].max()), 0.0, "below the eye")
        self.assertAlmostEqual(float(lamps[:, 0].min()), -float(lamps[:, 0].max()), places=5)

    def test_the_mesh_is_mirror_symmetric_and_deterministic(self) -> None:
        again = cockpit.cockpit_interior(SPEC, EYE, S)
        np.testing.assert_array_equal(self.mesh.vertices, again.vertices)
        np.testing.assert_array_equal(self.mesh.faces, again.faces)
        v = self.mesh.vertices
        self.assertAlmostEqual(float(v[:, 0].min()), -float(v[:, 0].max()), places=6)
        # Lamps carry a state each, so the row need not mirror; everything else does.
        plain = [i for i, m in enumerate(self.mesh.materials) if "_ind_" not in m.name]
        kept = np.isin(self.mesh.face_material, plain)
        points = v[np.unique(self.mesh.faces[kept])]
        rows = {tuple(np.round(p, 5) + 0.0) for p in points}
        self.assertTrue(all((round(-p[0], 5) + 0.0, p[1], p[2]) in rows for p in rows))

    def test_the_indicator_row_is_thin_and_on_the_octagons_top_rim(self) -> None:
        octagon = cockpit.cockpit_screens(SPEC, EYE)["octagon"]
        top = np.array(octagon["center"]) + 0.5 * octagon["size"][1] * np.array(octagon["up"]) - self.eye
        top_px = FOCAL_PX * top[1] / -top[2]
        rim_px = float(self.bezel_px()[0, 1])
        spans = []
        for lamp in cockpit.INDICATORS:
            index = next(i for i, m in enumerate(self.mesh.materials) if m.name == f"ef_cockpit_ind_{lamp}")
            points = self.mesh.vertices[np.unique(self.mesh.faces[self.mesh.face_material == index])] - self.eye
            screen = FOCAL_PX * points[:, :2] / -points[:, 2:]
            self.assertGreater(float(screen[:, 1].min()), top_px, f"{lamp}: above the screen")
            self.assertLess(float(screen[:, 1].max()), rim_px + 0.5, f"{lamp}: on the rim, not above it")
            self.assertLess(float(np.ptp(screen[:, 1])), 14.0, f"{lamp}: thin")
            spans.append(float(screen[:, 0].mean()))
        self.assertEqual(spans, sorted(spans), "port to starboard")
        self.assertLess(max(abs(s) for s in spans), float(self.bezel_px()[1, 0]), "all along the top edge")


class CockpitScreenTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.eye = np.array(EYE)
        cls.screens = cockpit.cockpit_screens(SPEC, EYE)
        cls.mesh = cockpit.cockpit_interior(SPEC, EYE, S)
        cls.triangles = cls.mesh.vertices[cls.mesh.faces]

    def corners(self, screen: dict) -> np.ndarray:
        centre, up, normal = (np.array(screen[k]) for k in ("center", "up", "normal"))
        right = np.cross(up, normal)
        w, h = screen["size"]
        return np.array([centre + sign_x * 0.5 * w * right + sign_y * 0.5 * h * up for sign_x, sign_y in ((-1, 1), (1, 1), (1, -1), (-1, -1))])

    def on_screen(self, points: np.ndarray) -> np.ndarray:
        rel = points - self.eye
        return FOCAL_PX * rel[:, :2] / -rel[:, 2:]

    def test_three_screens_with_a_frame_each(self) -> None:
        self.assertEqual(sorted(self.screens), ["left", "octagon", "right"])
        for name, screen in self.screens.items():
            self.assertEqual(sorted(screen), ["center", "corner", "normal", "size", "up"], name)
            self.assertAlmostEqual(float(np.linalg.norm(screen["normal"])), 1.0, places=5)
            self.assertAlmostEqual(float(np.linalg.norm(screen["up"])), 1.0, places=5)
            self.assertAlmostEqual(float(np.dot(screen["normal"], screen["up"])), 0.0, places=5)
        self.assertGreater(self.screens["octagon"]["corner"], 0.0, "cut corners")
        self.assertEqual(self.screens["left"]["corner"], 0.0)

    def test_left_is_port_and_right_is_starboard_with_the_octagon_between(self) -> None:
        self.assertLess(self.screens["left"]["center"][0], 0.0)
        self.assertGreater(self.screens["right"]["center"][0], 0.0)
        self.assertEqual(self.screens["octagon"]["center"][0], 0.0)
        self.assertEqual(self.screens["left"]["center"][0], -self.screens["right"]["center"][0])

    def test_right_of_a_screen_is_the_pilots_right(self) -> None:
        # The texture must not read mirrored: the viewport's +X runs to the pilot's right on every screen.
        for name, screen in self.screens.items():
            right = np.cross(np.array(screen["up"]), np.array(screen["normal"]))
            self.assertGreater(float(right[0]), 0.5, name)

    def test_each_screen_faces_the_eye(self) -> None:
        for name, screen in self.screens.items():
            to_eye = self.eye - np.array(screen["center"])
            to_eye /= np.linalg.norm(to_eye)
            self.assertGreater(float(np.dot(to_eye, screen["normal"])), np.cos(np.radians(35.0)), name)

    def test_the_screens_are_large_enough_to_read_and_do_not_overlap(self) -> None:
        boxes = {}
        for name, screen in self.screens.items():
            pixels = self.on_screen(self.corners(screen))
            lo, hi = pixels.min(axis=0), pixels.max(axis=0)
            boxes[name] = (lo, hi)
            self.assertLess(float(hi[1]), SPEC.opening_floor_y_px, f"{name}: below the V")
            self.assertGreater(float(lo[1]), -540.0, f"{name}: on screen at 1080p")
            self.assertLess(float(np.abs(pixels[:, 0]).max()), 960.0, f"{name}: on screen at 1080p")
            self.assertGreater(float(hi[0] - lo[0]), cockpit.MIN_SCREEN_PX[0], name)
            self.assertGreater(float(hi[1] - lo[1]), cockpit.MIN_SCREEN_PX[1], name)
        self.assertLess(float(boxes["left"][1][0]), float(boxes["octagon"][0][0]))
        self.assertLess(float(boxes["octagon"][1][0]), float(boxes["right"][0][0]))

    def outline(self, screen: dict) -> list[np.ndarray]:
        """A screen's real corners: a cut one has eight."""
        centre, up, normal = (np.array(screen[k]) for k in ("center", "up", "normal"))
        right = np.cross(up, normal)
        hw, hh, c = 0.5 * screen["size"][0], 0.5 * screen["size"][1], screen["corner"]
        shape = ((-hw + c, hh), (hw - c, hh), (hw, hh - c), (hw, -hh + c), (hw - c, -hh), (-hw + c, -hh), (-hw, -hh + c), (-hw, hh - c)) if c > 0.0 else ((-hw, hh), (hw, hh), (hw, -hh), (-hw, -hh))
        return [centre + a * right + b * up for a, b in shape]

    def test_nothing_of_the_interior_stands_in_front_of_a_screen(self) -> None:
        for name, screen in self.screens.items():
            corners = self.outline(screen)
            centre = np.array(screen["center"])
            samples = [centre] + [centre + 0.92 * (c - centre) for c in corners]
            rays = np.array(samples) - self.eye
            lengths = np.linalg.norm(rays, axis=1)
            distance, _ = first_hit(self.eye, rays / lengths[:, None], self.triangles)
            self.assertTrue(np.all(distance > lengths - 1e-4), (name, distance, lengths))

    def test_side_screens_read_square_on(self) -> None:
        # At this field of view a screen turned to the eye reads slanted; nearly parallel to the view plane its text stays upright.
        for name in ("left", "right"):
            corners = self.on_screen(self.corners(self.screens[name]))
            inner, outer = (corners[1], corners[2]) if name == "right" else (corners[0], corners[3])
            lean = abs(float(outer[0] - inner[0])) / abs(float(outer[1] - inner[1]))
            self.assertLess(lean, 0.12, name)
            top = corners[1] - corners[0]
            self.assertLess(abs(float(top[1] / top[0])), 0.08, f"{name}: its lines of text stay level")

    def test_the_console_stands_behind_each_screen(self) -> None:
        for name, screen in self.screens.items():
            centre = np.array(screen["center"])
            rays = (centre - self.eye)[None, :]
            length = float(np.linalg.norm(rays))
            distance, _ = first_hit(self.eye, rays / length, self.triangles)
            self.assertLess(float(distance[0]) - length, 0.03, name)
            self.assertGreater(float(distance[0]), length, name)


def saturation(rgb) -> float:
    """How far a linear colour is from grey: (max - min) / max, 0 for black."""
    c = np.asarray(rgb, dtype=float)
    return 0.0 if c.max() <= 0.0 else float((c.max() - c.min()) / c.max())


class CabinGlowTests(unittest.TestCase):
    """Q36 (maintainer, 2026-11-04): the cabin is grey, lit by a dark red glow, from inside and through the canopy."""

    COCKPIT_SURFACES = ("cockpit_red", "cockpit_red_dim", "cockpit_dark", "cockpit_sill", "cockpit_metal")

    def test_the_cockpit_surfaces_are_neutral_grey(self) -> None:
        for key in self.COCKPIT_SURFACES:
            self.assertLess(saturation(S.material(key).albedo), 0.08, key)

    def test_the_hulls_interior_lining_is_grey_and_glows_red(self) -> None:
        interior = S.material("interior")
        self.assertLess(saturation(interior.albedo), 0.08)
        self.assertGreater(interior.emissive_strength, 0.0)
        r, g, b = interior.emissive
        self.assertGreater(r, 3.0 * max(g, b))

    def test_the_canopy_glass_glows_red_and_its_tint_is_neutral(self) -> None:
        glass = S.material("canopy_glass")
        r, g, b = glass.emissive
        self.assertGreater(glass.emissive_strength, 0.0)
        self.assertGreater(r, 3.0 * max(g, b))
        self.assertLess(saturation(glass.albedo), 0.15)


if __name__ == "__main__":
    unittest.main()
