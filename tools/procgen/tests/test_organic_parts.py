"""The organic part library (M10-T06, D12.2): ``core/sweep.py``, ``core/organic.py``, ``parts/organic.py`` and
``parts/organic_petal.py``.

Paths carry their frames without twisting; limbs and petals are closed skins with collision that follows them; a petal
morphs between its poses on one set of triangles and its closed pose matches M10-T01's measurements of the Vorlon
destroyer's; a body cut into sections is still one seamless skin, with collision part by part.
"""

from __future__ import annotations

import math
import unittest

import numpy as np

from tools.procgen.core import collision as col
from tools.procgen.core import organic, sdf
from tools.procgen.core.geometry import Material, mirror_matrix
from tools.procgen.core.isosurface import edge_faults
from tools.procgen.core.sweep import frames, spline, tube
from tools.procgen.parts import capital as cp
from tools.procgen.parts import organic as po
from tools.procgen.parts import organic_petal as petals

SKIN = Material("skin", (0.3, 0.3, 0.3))
# The Vorlon destroyer's petal as M10-T01 measured it (docs/design-references.md, "Vorlon destroyer"): closed, a shell 56 m long
# curled to radius 9.2 m with a chord of 17.8 m and a depth of 6.9 m; open, 32 m wide, 46 m long, 50 degrees out from the axis.
CLOSED = petals.PetalPose(length_m=56.0, width_m=24.1, curl_radius_m=9.2)
OPEN = petals.PetalPose(length_m=46.0, width_m=32.0, hinge_deg=50.0)


def volume(mesh) -> float:
    a, b, c = mesh.corners()
    return float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6.0)


class SweepTests(unittest.TestCase):
    def test_a_spline_runs_through_its_controls_evenly(self) -> None:
        controls = np.array([[0.0, 0.0, 0.0], [10.0, 0.0, 10.0], [10.0, 8.0, 30.0], [0.0, 8.0, 40.0]])
        path = spline(controls, 64)
        np.testing.assert_allclose(path.points[[0, -1]], controls[[0, -1]], atol=1e-9)
        for control in controls[1:-1]:
            self.assertLess(float(np.linalg.norm(path.points - control, axis=1).min()), 0.35, "near every control point")
        steps = np.linalg.norm(np.diff(path.points, axis=0), axis=1)
        self.assertLess(float(steps.max() / steps.min()), 1.05, "evenly spaced by length")
        self.assertAlmostEqual(path.t[0], 0.0)
        self.assertAlmostEqual(path.t[-1], 1.0)
        np.testing.assert_allclose(path.along([(0.0, 2.0), (1.0, 4.0)])[[0, -1]], [2.0, 4.0])

    def test_frames_are_square_right_handed_and_do_not_twist(self) -> None:
        turn = np.linspace(0.0, 1.5 * math.pi, 60)
        path = frames(np.stack([20.0 * np.cos(turn), np.zeros_like(turn), 20.0 * np.sin(turn)], axis=1), up=(0.0, 1.0, 0.0))
        for a, b in ((path.tangent, path.side), (path.tangent, path.up), (path.side, path.up)):
            np.testing.assert_allclose(np.einsum("ij,ij->i", a, b), 0.0, atol=1e-9)
        np.testing.assert_allclose(np.cross(path.side, path.up), path.tangent, atol=1e-9)
        np.testing.assert_allclose(path.up, np.tile([0.0, 1.0, 0.0], (60, 1)), atol=1e-9, err_msg="a flat curve keeps its up")
        aft = frames(np.array([[0.0, 0.0, 0.0], [0.0, 0.0, 5.0]]))
        np.testing.assert_allclose(aft.side[0], [1.0, 0.0, 0.0], atol=1e-12, err_msg="running aft, the side is starboard")
        mirrored = path.transformed(mirror_matrix("x"))
        np.testing.assert_allclose(np.cross(mirrored.side, mirrored.up), mirrored.tangent, atol=1e-9)

    def test_a_tube_is_a_closed_skin_with_a_point_where_its_section_ends(self) -> None:
        path = spline(np.array([[0.0, 0.0, 0.0], [0.0, 5.0, 20.0], [0.0, 0.0, 40.0]]), 30)
        width = path.along([(0.0, 3.0), (1.0, 0.0)])
        mesh = tube(path, width, 0.5 * width, SKIN, sides=10)
        self.assertEqual(edge_faults(mesh.faces), 0)
        self.assertGreater(volume(mesh), 0.0, "wound outward")
        self.assertAlmostEqual(volume(mesh), math.pi * 3.0 * 1.5 * path.length / 3.0, delta=0.12 * math.pi * 4.5 * path.length / 3.0)
        self.assertEqual(float(np.linalg.norm(mesh.vertices - path.points[-1], axis=1).min()), 0.0, "the tip is the path's end")
        self.assertEqual(mesh.chart_count, 1, "one chart along the limb")
        self.assertEqual(tube(path, width, None, SKIN, chart_m=10.0).chart_count, 4, "a 41 m limb in 10 m charts")
        blunt = tube(path, 2.0, None, SKIN, sides=8)
        self.assertEqual(edge_faults(blunt.faces), 0)
        self.assertLess(float(blunt.vertices[:, 2].min()), 0.0, "a domed end stands proud of the path's start")


class LimbTests(unittest.TestCase):
    def test_the_paths_start_and_end_where_they_are_asked_to(self) -> None:
        claw = po.claw_path((5.0, 0.0, 0.0), 40.0, (1.0, 0.0, 0.0), (0.0, 0.0, -1.0), 90.0)
        np.testing.assert_allclose(claw.points[0], [5.0, 0.0, 0.0], atol=1e-9)
        self.assertAlmostEqual(claw.length, 40.0, delta=0.5)
        np.testing.assert_allclose(claw.tangent[0], [1.0, 0.0, 0.0], atol=0.12)
        np.testing.assert_allclose(claw.tangent[-1], [0.0, 0.0, -1.0], atol=0.12, err_msg="curled a quarter turn")
        leg = po.leg_path((0.0, 0.0, 0.0), (20.0, 10.0, 0.0), (30.0, -30.0, 0.0))
        np.testing.assert_allclose(leg.points[[0, -1]], [[0.0, 0.0, 0.0], [30.0, -30.0, 0.0]], atol=1e-9)
        self.assertLess(float(np.linalg.norm(leg.points - (20.0, 10.0, 0.0), axis=1).min()), 1.0, "through its knee")
        tendril = po.tendril_path((0.0, 0.0, 0.0), (0.0, 0.0, 50.0), 3.0, 2.0)
        self.assertGreater(float(np.ptp(tendril.points[:, 1])), 3.0, "it sways")
        np.testing.assert_allclose(tendril.points[-1], [0.0, 0.0, 50.0], atol=1e-9)

    def test_taper_and_ribs(self) -> None:
        path = spline(np.array([[0.0, 0.0, 0.0], [0.0, 0.0, 60.0]]), 121)
        size = po.taper(path, 4.0, 1.0)
        np.testing.assert_allclose(size[[0, -1]], [4.0, 1.0])
        ribbed = po.ribs(path, np.full(121, 2.0), 10.0, 0.25)
        self.assertAlmostEqual(float(ribbed.max()), 2.5, places=6)
        self.assertAlmostEqual(float(ribbed.min()), 2.0, places=6)
        crests = np.flatnonzero((ribbed[1:-1] > ribbed[:-2]) & (ribbed[1:-1] > ribbed[2:])) + 1
        np.testing.assert_allclose(np.diff(path.arc[crests]), 10.0, atol=1e-6, err_msg="a rib every pitch")

    def test_a_limb_is_a_module_whose_collision_follows_its_curve(self) -> None:
        path = po.claw_path((0.0, 0.0, 0.0), 80.0, (1.0, 0.0, 0.0), (0.0, 0.0, -1.0), 100.0)
        width = po.taper(path, 5.0, 0.0, 0.8)
        limb = po.limb("claw_r", path, width, 0.5 * width, SKIN, pieces=6)
        self.assertEqual(edge_faults(limb.part.mesh.faces), 0)
        self.assertEqual([s.name for s in limb.shapes], [f"claw_r_{k:02d}" for k in range(6)])
        self.assertEqual(limb.skin, cp.SKIN_NONE, "bare of seams unless asked")
        self.assertLess(float(col.gaps(limb.shapes, limb.part.mesh.vertices).max()), 0.6, "the skin is inside its collision")
        middle = 0.5 * (path.points[0] + path.points[-1])  # across the curl: no hull may bridge it
        self.assertGreater(float(col.gaps(limb.shapes, middle[None])[0]), 5.0)
        twin = limb.on_side(cp.RIGHT).twin()
        self.assertEqual(twin.name, "claw_l")
        self.assertEqual(twin.shapes[0].name, "claw_l_00")

    def test_a_limbs_root_melts_into_a_body(self) -> None:
        path = spline(np.array([[8.0, 0.0, 0.0], [40.0, 0.0, 0.0]]), 33)
        width = po.taper(path, 3.0, 0.0)
        root = po.limb_root(path, width)
        self.assertLess(float(root((path.points[2] + 1.05 * width[2] * path.up[2])[None])[0]), 0.0, "a little fatter than the limb")
        self.assertGreater(float(root(path.points[-1][None])[0]), 0.0, "only the limb's start")
        melted = po.body([sdf.sphere(10.0), root], 3.0)
        crease = np.array([[10.5, 3.5, 0.0]])  # in the corner between the ball and the limb
        self.assertLess(float(melted(crease)[0]), float(sdf.union(sdf.sphere(10.0), root)(crease)[0]) - 0.05, "a fillet fills the corner")


class BodyPartTests(unittest.TestCase):
    def test_a_lobe_is_as_big_as_asked_and_tapers_aft(self) -> None:
        plain = po.lobe(40.0, 20.0, 10.0, centre=(0.0, 0.0, 5.0))
        np.testing.assert_allclose(plain(np.array([[10.0, 0.0, 5.0], [0.0, 5.0, 5.0], [0.0, 0.0, 25.0]])), 0.0, atol=1e-9)
        drop = po.lobe(40.0, 20.0, 10.0, taper=0.6)
        fore, aft = np.array([[6.0, 0.0, -8.0]]), np.array([[6.0, 0.0, 8.0]])
        self.assertLess(float(drop(fore)[0]), 0.0)
        self.assertGreater(float(drop(aft)[0]), 0.0, "narrower aft of the middle than ahead of it")
        with self.assertRaises(ValueError):
            po.lobe(40.0, 20.0, 10.0, taper=1.0)

    def test_a_pod_stands_on_its_stalk(self) -> None:
        pod = po.pod(4.0, 14.0, 6.0, 1.5, at=(10.0, 0.0, 0.0), out=(1.0, 0.0, 0.0))
        inside = np.array([[20.0, 0.0, 0.0], [20.0, 0.0, 6.5], [13.0, 0.0, 0.0]])  # the egg's middle, near its end, the stalk
        self.assertTrue(np.all(pod(inside) < 0.0))
        self.assertGreater(float(pod(np.array([[13.0, 3.5, 0.0]]))[0]), 0.0, "the stalk is thin")


class PetalTests(unittest.TestCase):
    def test_the_closed_pose_is_the_measured_shell(self) -> None:
        self.assertAlmostEqual(CLOSED.chord_m, 17.8, delta=0.1)
        self.assertAlmostEqual(CLOSED.depth_m, 6.9, delta=0.1)
        mesh = petals.petal_mesh(CLOSED, 0.6, SKIN)
        size = mesh.bounds()[1] - mesh.bounds()[0]
        self.assertAlmostEqual(float(size[0]), 17.8, delta=0.3)
        self.assertAlmostEqual(float(size[2]), 56.0, delta=0.1)
        self.assertAlmostEqual(float(mesh.vertices[:, 2].max()), 0.0, places=9, msg="its root at the origin, its length forward")

    def test_the_open_pose_is_flat_wide_and_stands_out(self) -> None:
        self.assertEqual(OPEN.depth_m, 0.0)
        mesh = petals.petal_mesh(OPEN, 0.6, SKIN)
        size = mesh.bounds()[1] - mesh.bounds()[0]
        self.assertAlmostEqual(float(size[0]), 32.0, delta=0.3)
        tip = mesh.vertices[np.argmax(np.linalg.norm(mesh.vertices, axis=1))]
        self.assertAlmostEqual(math.degrees(math.atan2(tip[1], -tip[2])), 50.0, delta=1.0, msg="50 degrees out, its tip forward")
        self.assertAlmostEqual(float(np.linalg.norm(tip)), 46.0, delta=0.2)

    def test_it_morphs_on_one_set_of_triangles_and_stays_closed(self) -> None:
        shells = [petals.petal("petal", CLOSED, OPEN, opening, 0.6, SKIN).part.mesh for opening in (0.0, 0.3, 0.7, 1.0)]
        for mesh in shells:
            self.assertEqual(edge_faults(mesh.faces), 0)
            self.assertGreater(volume(mesh), 0.0)
            np.testing.assert_array_equal(mesh.faces, shells[0].faces)
            self.assertEqual(mesh.chart_count, 2, "its outer and its inner face")
        widths = [float(np.ptp(mesh.vertices[:, 0])) for mesh in shells]
        self.assertEqual(widths, sorted(widths), "it widens as it opens")
        halfway = CLOSED.towards(OPEN, 0.5)
        self.assertAlmostEqual(halfway.curl_radius_m, 18.4, places=6, msg="curls mix by curvature: half the curl is twice the radius")
        with self.assertRaises(ValueError):
            petals.petal("petal", CLOSED, OPEN, 1.2, 0.6, SKIN)

    def test_its_collision_follows_the_curl(self) -> None:
        shell = petals.petal("petal", CLOSED, OPEN, 0.0, 0.6, SKIN, pieces=8)
        self.assertGreater(len(shell.shapes), 1, "a curled shell is not one hull")
        self.assertLess(float(col.gaps(shell.shapes, shell.part.mesh.vertices).max()), 0.3)
        hollow = np.array([[0.0, -6.0, -30.0]])  # inside the curl, where the ship's head is
        self.assertGreater(float(col.gaps(shell.shapes, hollow)[0]), 1.0)
        flat = petals.petal("petal", CLOSED, OPEN, 1.0, 0.6, SKIN)
        self.assertLess(len(flat.shapes), len(shell.shapes), "a flat one needs fewer")

    def test_a_ring_of_petals_stands_round_the_axis(self) -> None:
        ring = petals.ring_of(petals.petal("petal", CLOSED, OPEN, 0.0, 0.6, SKIN), 4, 9.0, 50.0, phase_deg=45.0)
        self.assertEqual([m.name for m in ring], ["petal_0", "petal_1", "petal_2", "petal_3"])
        centres = np.array([m.part.mesh.area_centroid() for m in ring])
        np.testing.assert_allclose(centres.mean(axis=0)[:2], 0.0, atol=1e-6)
        self.assertLess(float(np.ptp(np.hypot(centres[:, 0], centres[:, 1]))), 1e-6)
        self.assertEqual(len({s.name for m in ring for s in m.shapes}), sum(len(m.shapes) for m in ring), "every shape its own name")


class OrganicBodyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.parts = [po.lobe(60.0, 30.0, 24.0, centre=(0.0, 0.0, 30.0)), po.lobe(50.0, 20.0, 16.0, 0.4, (0.0, 0.0, 70.0)),
                     po.pod(5.0, 16.0, 5.0, 2.0, at=(13.0, 0.0, 30.0))]
        cls.body = po.body(cls.parts, 4.0, relief_m=0.3, relief_scale_m=5.0, seed=2)
        cls.regions = {"fore": sdf.box((200.0, 200.0, 50.0), (0.0, 0.0, 25.0)), "aft": sdf.box((200.0, 200.0, 50.0), (0.0, 0.0, 75.0))}
        cls.point = cp.Hardpoint("beam", cp.BEAM, (0.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0))
        cls.modules = organic.sectioned(cls.body, cls.regions, 1.0, 6000, SKIN, tolerance_m=1.5, hardpoints={"fore": [cls.point]}, parts=cls.parts)

    def test_the_sections_share_out_one_closed_skin(self) -> None:
        self.assertEqual([m.name for m in self.modules], ["fore", "aft"])
        self.assertEqual([m.section for m in self.modules], ["fore", "aft"])
        self.assertLessEqual(sum(m.part.mesh.face_count for m in self.modules), 6000)
        points = np.concatenate([m.part.mesh.vertices for m in self.modules])
        welded, index = np.unique(points, axis=0, return_inverse=True)
        faces, base = [], 0
        for m in self.modules:
            faces.append(index.reshape(-1)[m.part.mesh.faces + base])
            base += m.part.mesh.vertex_count
            self.assertGreater(edge_faults(m.part.mesh.faces), 0, "a section alone is open at its cut")
        self.assertEqual(edge_faults(np.concatenate(faces)), 0, "together they are the whole closed body")
        self.assertLess(float(self.modules[0].part.mesh.face_centroids()[:, 2].max()), 51.5)
        self.assertGreater(float(self.modules[1].part.mesh.face_centroids()[:, 2].min()), 48.5)

    def test_the_cut_does_not_show(self) -> None:
        fore, aft = (m.part.mesh for m in self.modules)
        shared = {tuple(v): k for k, v in enumerate(fore.vertices.tolist())}
        pairs = [(shared[tuple(v)], k) for k, v in enumerate(aft.vertices.tolist()) if tuple(v) in shared]
        self.assertGreater(len(pairs), 20, "the sections share the vertices along their cut")
        a, b = (np.array(k) for k in zip(*pairs, strict=True))
        np.testing.assert_array_equal(fore.vertex_normals()[a], aft.vertex_normals()[b])

    def test_collision_is_fitted_part_by_part_and_covers_the_skin(self) -> None:
        shapes = [s for m in self.modules for s in m.shapes]
        self.assertTrue(all(s.name.startswith(("fore_", "aft_")) for s in shapes))
        self.assertLessEqual(len(shapes), 12)
        skin = np.concatenate([m.part.mesh.vertices for m in self.modules])
        self.assertLess(float(col.gaps(shapes, skin).max()), 2.5, "no skin stands clear of the collision (a hull has 32 corners)")
        beside_pod = np.array([[16.0, 8.0, 30.0]])  # outside the body, beside the pod's stalk
        self.assertGreater(float(col.gaps(shapes, beside_pod)[0]), 1.0, "the pod is not bridged to the body")
        self.assertLess(float(col.gaps(shapes, np.array([[0.0, 0.0, 50.0]]))[0]), 1e-9, "no gap inside the body at the cut")

    def test_hardpoints_and_the_burying_volume(self) -> None:
        self.assertEqual([h.name for h in self.modules[0].hardpoints], ["beam"])
        self.assertEqual(self.modules[1].hardpoints, ())
        self.assertIsNotNone(self.modules[0].solid)
        self.assertTrue(bool(self.modules[0].solid.contains(np.array([[0.0, 0.0, 60.0]]))[0]), "the whole body buries, not one section")
        with self.assertRaises(ValueError):
            organic.sectioned(self.body, {**self.regions, "nowhere": sdf.box((1.0, 1.0, 1.0), (0.0, 0.0, 900.0))}, 2.0, 2000, SKIN, 1.5)

    def test_convex_pieces_cut_a_hollow_shape_and_leave_a_round_one_whole(self) -> None:
        ball = sdf.mesh(sdf.sphere(10.0), 1.0, SKIN).vertices
        grid = np.stack(np.meshgrid(*(np.arange(-10.0, 10.0, 1.0),) * 3, indexing="ij"), axis=-1).reshape(-1, 3)
        self.assertEqual(len(organic.convex_pieces("ball", ball, 1.0, filling=grid[np.linalg.norm(grid, axis=1) < 9.5])), 1)
        self.assertGreater(len(organic.convex_pieces("ball", ball, 1.0)), 1, "without its filling it is a hollow shell")
        horseshoe = sdf.mesh(sdf.subtract(sdf.torus(12.0, 3.0), sdf.box((40.0, 20.0, 10.0), (0.0, -10.0, 0.0))), 1.0, SKIN).vertices
        pieces = organic.convex_pieces("shoe", horseshoe, 1.0, max_pieces=8)
        self.assertGreater(len(pieces), 3)
        self.assertEqual([p.name for p in pieces], [f"shoe_{k:02d}" for k in range(len(pieces))])
        self.assertGreater(float(col.gaps(pieces, np.array([[0.0, 4.0, 0.0]]))[0]), 3.0, "the middle of the horseshoe stays open")


if __name__ == "__main__":
    unittest.main()
