"""parts/ and styles/: anchors, collision, transforms, every M1 part, pilot tags, panel shading."""

from __future__ import annotations

import math
import unittest
from itertools import pairwise

import numpy as np

from tools.procgen.core import geometry as g
from tools.procgen.parts import (
    Anchor,
    Collision,
    Part,
    hull,
    mass_centroid,
    propulsion,
    structure,
    total_mass,
    weapons,
)
from tools.procgen.styles import REQUIRED_ROLES, Style
from tools.procgen.styles.earthforce import EARTHFORCE

S = EARTHFORCE


def outward(mesh: g.Mesh, centre) -> float:
    """Fraction of faces whose normal points away from ``centre``."""
    d = np.einsum("ij,ij->i", mesh.face_normals(), mesh.face_centroids() - np.asarray(centre, float))
    return float((d > -1e-9).mean())


class AnchorCollisionPartTests(unittest.TestCase):
    def test_anchor_normalises_direction_and_transforms(self) -> None:
        a = Anchor([1, 2, 3], [0, 0, 2])
        np.testing.assert_allclose(a.direction, [0, 0, 1])
        self.assertIsNone(Anchor([0, 0, 0]).direction)
        with self.assertRaises(ValueError):
            Anchor([0, 0, 0], [0, 0, 0])
        t = a.transformed(g.rotation_y(math.pi / 2), [10, 0, 0])
        np.testing.assert_allclose(t.position, [13, 2, -1], atol=1e-12)
        np.testing.assert_allclose(t.direction, [1, 0, 0], atol=1e-12)

    def test_collision_validation_mirroring_and_json(self) -> None:
        with self.assertRaises(ValueError):
            Collision("sphere", [0, 0, 0])
        with self.assertRaises(ValueError):
            Collision("box", [0, 0, 0])
        with self.assertRaises(ValueError):
            Collision("capsule", [0, 0, 0], radius=1.0)
        box = Collision("box", [1, 0, 0], g.rotation_z(math.pi / 4), size=[2, 1, 3], name="b")
        mirrored = box.transformed(g.mirror_matrix("x"))
        self.assertAlmostEqual(float(np.linalg.det(mirrored.basis)), 1.0)
        np.testing.assert_allclose(mirrored.center, [-1, 0, 0])
        js = mirrored.to_json(offset=[0, 0, 1])
        self.assertEqual(js["type"], "box")
        self.assertEqual(js["position"], [-1.0, 0.0, -1.0])
        self.assertEqual(js["size"], [2.0, 1.0, 3.0])
        self.assertEqual(set(js["basis"]), {"x", "y", "z"})
        cap = Collision("capsule", [0, 0, 0], radius=0.5, height=3.0).to_json()
        self.assertEqual((cap["radius"], cap["height"], cap["axis"]), (0.5, 3.0, "z"))

    def test_part_transforms_everything_together(self) -> None:
        part = Part(
            "p",
            g.box((1, 1, 1), S.material("hull")),
            {"tip": Anchor([0.5, 0, 0], [1, 0, 0])},
            [Collision("box", [0, 0, 0], size=[1, 1, 1])],
            mass_kg=10.0,
            group="body",
        )
        moved = part.transformed(g.rotation_z(math.pi / 2), [0, 0, 5])
        np.testing.assert_allclose(moved.anchor("tip").position, [0, 0.5, 5], atol=1e-12)
        np.testing.assert_allclose(moved.anchor("tip").direction, [0, 1, 0], atol=1e-12)
        np.testing.assert_allclose(moved.collision[0].center, [0, 0, 5], atol=1e-12)
        np.testing.assert_allclose(moved.mesh.area_centroid(), [0, 0, 5], atol=1e-12)
        mirrored = part.mirrored("x").renamed("q")
        self.assertEqual((mirrored.name, mirrored.group, mirrored.mass_kg), ("q", "body", 10.0))
        np.testing.assert_allclose(mirrored.anchor("tip").direction, [-1, 0, 0])
        self.assertEqual(outward(mirrored.mesh, [0, 0, 0]), 1.0)
        with self.assertRaises(KeyError):
            part.anchor("nope")
        self.assertEqual(total_mass([part, moved]), 20.0)
        np.testing.assert_allclose(mass_centroid([part, moved]), [0, 0, 2.5], atol=1e-12)
        with self.assertRaises(ValueError):
            mass_centroid([Part("m", part.mesh)])


class HullPartTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fspec = hull.FuselageSpec(
            (
                hull.FuselageSection(-3.0, 0.0, 0.0),
                hull.FuselageSection(-2.5, 0.6, 0.5),
                hull.FuselageSection(0.0, 1.6, 1.4),
                hull.FuselageSection(3.0, 1.0, 0.9),
            ),
            mass_kg=100.0,
        )

    def test_fuselage_dimensions_anchors_and_queries(self) -> None:
        part = hull.fuselage(self.fspec, S)
        lo, hi = part.mesh.bounds()
        np.testing.assert_allclose([lo[2], hi[2]], [-3.0, 3.0])
        self.assertAlmostEqual(float(hi[0] - lo[0]), 1.6, delta=0.02)
        self.assertAlmostEqual(float(hi[1] - lo[1]), 1.4, delta=0.02)
        np.testing.assert_allclose(part.anchor("nose").position, [0, 0, -3.0])
        np.testing.assert_allclose(part.anchor("nose").direction, [0, 0, -1])
        np.testing.assert_allclose(part.anchor("tail").position, [0, 0, 3.0])
        self.assertAlmostEqual(self.fspec.top_y(0.0), 0.7)
        self.assertAlmostEqual(self.fspec.bottom_y(0.0), -0.7)
        self.assertLess(self.fspec.top_y(0.0, 0.7), 0.7)
        self.assertAlmostEqual(self.fspec.section_at(1.5).width, 1.3)
        self.assertEqual(self.fspec.length, 6.0)
        self.assertEqual(part.collision[0].kind, "box")
        np.testing.assert_allclose(part.collision[0].size, [1.6, 1.4, 6.0])
        self.assertEqual(part.mass_kg, 100.0)
        # Tail cap is the dark material, the rest hull.
        self.assertEqual({m.name for m in part.mesh.materials}, {"ef_hull", "ef_hull_dark"})
        centroids = part.mesh.face_centroids()
        on_axis = np.column_stack([np.zeros(len(centroids)), np.zeros(len(centroids)), centroids[:, 2]])
        facing_out = np.einsum("ij,ij->i", part.mesh.face_normals(), centroids - on_axis) > -1e-9
        self.assertGreater(float(facing_out.mean()), 0.99)
        with self.assertRaises(ValueError):
            hull.FuselageSpec((hull.FuselageSection(1.0, 1, 1), hull.FuselageSection(0.0, 1, 1)))

    def test_canopy_dome_frames_eye_and_interior(self) -> None:
        spec = hull.CanopySpec()
        part = hull.canopy(spec, S)
        lo, hi = part.mesh.bounds()
        self.assertAlmostEqual(float(hi[1]), spec.height, places=6)
        self.assertAlmostEqual(float(lo[1]), 0.0, places=9)
        self.assertLess(float(hi[2] - lo[2]), spec.length + 1e-9)
        self.assertGreater(float(hi[2] - lo[2]), 0.9 * spec.length)
        self.assertAlmostEqual(float(hi[0] - lo[0]), spec.width, delta=0.02)
        names = [m.name for m in part.mesh.materials]
        self.assertEqual(names, ["ef_canopy_glass", "ef_canopy_frame"])
        frame = part.mesh.face_material == 1
        self.assertTrue(0.05 < frame.mean() < 0.4)
        # Hoops sit where the spec says; panes between them are glass.
        z = part.mesh.face_centroids()[:, 2]
        y = part.mesh.face_centroids()[:, 1]
        for h in spec.hoops:
            band = np.abs(z - spec.hoop_z(h)) < 0.4 * spec.frame_width
            self.assertTrue(np.all(frame[band]), h)
        between = (np.abs(z - 0.5 * (spec.hoop_z(spec.hoops[0]) + spec.hoop_z(spec.hoops[1]))) < 0.1) & (y > 0.2)
        self.assertTrue(between.any())
        self.assertFalse(frame[between].any())
        self.assertEqual(outward(part.mesh, [0, -spec.sink, 0]), 1.0)
        # The eye is inside the dome, clear of the glass.
        eye = part.anchor("eye")
        np.testing.assert_allclose(eye.direction, [0, 0, -1])
        self.assertTrue(0.0 < eye.position[1] < spec.height)
        dist = np.linalg.norm(part.mesh.vertices - eye.position, axis=1).min()
        self.assertGreater(float(dist), 0.15)
        interior = hull.cockpit_interior(spec, S)
        self.assertGreater(interior.face_count, 50)
        ilo, ihi = interior.bounds()
        self.assertTrue(np.all(ilo >= lo - 1e-9) and np.all(ihi <= hi + 1e-9))
        # Dash slab ahead of and below the eye.
        self.assertLess(float(ihi[1]), spec.height)
        dash = interior.face_centroids()[interior.face_material == 0]
        self.assertTrue(np.all(dash[:, 2] < eye.position[2]))
        self.assertTrue(np.all(dash[:, 1] < eye.position[1]))
        tub = hull.cockpit_tub(spec, S)
        _, thi = tub.mesh.bounds()
        self.assertAlmostEqual(float(thi[1]), 0.03)
        self.assertLess(float(thi[0]), 0.5 * spec.width)
        self.assertEqual(outward(tub.mesh, [0, -0.15, 0]), 1.0)

    def test_cylinder_hull_stands_on_y_with_bands_anchors_and_capsule(self) -> None:
        spec = hull.CylinderHullSpec(
            barrel_height=2.0, radius=0.5, cap_height=0.25, end_radius=0.2, bands=((0.1, 0.2, "stripe"),), mass_kg=10.0
        )
        part = hull.cylinder_hull(spec, S)
        lo, hi = part.mesh.bounds()
        np.testing.assert_allclose([lo[1], hi[1]], [-1.25, 1.25], atol=1e-12)
        np.testing.assert_allclose([lo[0], hi[0], lo[2], hi[2]], [-0.5, 0.5, -0.5, 0.5], atol=1e-12)
        self.assertEqual(spec.total_height, 2.5)
        self.assertEqual(outward(part.mesh, [0, 0, 0]), 1.0)
        np.testing.assert_allclose(part.anchor("top").position, [0, 1.25, 0])
        np.testing.assert_allclose(part.anchor("top").direction, [0, 1, 0])
        np.testing.assert_allclose(part.anchor("bottom").direction, [0, -1, 0])
        np.testing.assert_allclose(part.anchor("side_right").position, [0.5, 0, 0])
        # The stripe is exactly the band: barrel faces between 10 % and 20 % of the height.
        stripe = part.mesh.face_material == part.mesh.material_index("ef_stripe")
        y = part.mesh.face_centroids()[stripe, 1]
        self.assertTrue(np.all((y > -1.0 + 0.2) & (y < -1.0 + 0.4)))
        self.assertEqual({m.name for m in part.mesh.materials}, {"ef_hull", "ef_hull_dark", "ef_stripe"})
        self.assertEqual(spec.role_at(0.15), "stripe")
        self.assertEqual(spec.role_at(0.5), "hull")
        cap = part.collision[0]
        self.assertEqual((cap.kind, cap.radius, cap.height), ("capsule", 0.5, 2.5))
        np.testing.assert_allclose(cap.basis[:, 2], [0, 1, 0], atol=1e-12)
        self.assertAlmostEqual(float(np.linalg.det(cap.basis)), 1.0)
        self.assertEqual(part.mass_kg, 10.0)
        for bad in ({"radius": 0.0}, {"end_radius": 0.6}, {"bands": ((0.5, 0.4, "stripe"),)}):
            with self.subTest(bad), self.assertRaises(ValueError):
                hull.CylinderHullSpec(**bad)


class PropulsionTests(unittest.TestCase):
    def test_nozzle_bell(self) -> None:
        spec = propulsion.NozzleSpec(throat_r=0.3, exit_r=0.5, length=0.6)
        part = propulsion.nozzle(spec, S)
        np.testing.assert_allclose(part.anchor("exit").position, [0, 0, 0.6])
        np.testing.assert_allclose(part.anchor("exit").direction, [0, 0, 1])
        _, hi = part.mesh.bounds()
        self.assertAlmostEqual(float(hi[0]), spec.exit_r + spec.wall)
        self.assertAlmostEqual(float(hi[2]), 0.6)
        self.assertEqual({m.name for m in part.mesh.materials}, {"ef_nozzle", "ef_nozzle_throat"})
        radii = [spec.radius_at(z) for z in np.linspace(0, 0.6, 7)]
        self.assertTrue(all(b >= a for a, b in pairwise(radii)))

    def test_engine_pod_anchors_materials_and_collision(self) -> None:
        spec = propulsion.PodSpec()
        pod = propulsion.engine_pod(spec, S)
        np.testing.assert_allclose(pod.anchor("center").position, [0, 0, 0])
        main, retro = pod.anchor("main"), pod.anchor("retro")
        np.testing.assert_allclose(main.direction, [0, 0, 1])
        np.testing.assert_allclose(retro.direction, [0, 0, -1], atol=1e-12)
        self.assertGreater(main.position[2], spec.rear_z - 0.01)
        self.assertLess(retro.position[2], spec.front_z + 0.01)
        np.testing.assert_allclose(main.position[:2], 0, atol=1e-12)
        for key, direction in (("rcs_px", [1, 0, 0]), ("rcs_nx", [-1, 0, 0]), ("rcs_py", [0, 1, 0]), ("rcs_ny", [0, -1, 0])):
            a = pod.anchor(key)
            np.testing.assert_allclose(a.direction, direction, atol=1e-12)
            self.assertAlmostEqual(float(np.linalg.norm(a.position[:2])), spec.radius + spec.rcs.length - 0.01, places=6)
        lo, hi = pod.mesh.bounds()
        self.assertAlmostEqual(float(hi[0] - lo[0]), 2 * (spec.radius + spec.rcs.length - 0.01), places=6)
        names = {m.name for m in pod.mesh.materials}
        self.assertTrue({"ef_hull", "ef_stripe", "ef_hull_dark", "ef_nozzle", "ef_nozzle_throat", "ef_rcs"} <= names)
        z = pod.mesh.face_centroids()[:, 2]
        stripe = pod.mesh.face_material == pod.mesh.material_index("ef_stripe")
        centre = spec.front_z + S.stripe_fraction * spec.length
        self.assertTrue(stripe.any())
        self.assertTrue(np.all(np.abs(z[stripe] - centre) <= 0.5 * S.stripe_width_m + 1e-9))
        self.assertEqual(pod.collision[0].kind, "capsule")
        self.assertEqual((pod.collision[0].radius, pod.collision[0].height), (spec.radius, spec.length))
        self.assertEqual(pod.mass_kg, spec.mass_kg)

    def test_pilot_tags_follow_the_milestone_convention(self) -> None:
        com = np.array([0.0, 0.0, 0.8])
        self.assertEqual(
            set(propulsion.pilot_tags([3.75, 3.18, 3.2], [1, 0, 0], com)), {"sway_left", "roll_left", "yaw_right"}
        )
        self.assertEqual(
            set(propulsion.pilot_tags([-3.75, 3.18, 3.2], [-1, 0, 0], com)), {"sway_right", "roll_right", "yaw_left"}
        )
        self.assertEqual(set(propulsion.pilot_tags([0, 0, 0.8], [0, 1, 0], com)), {"heave_down"})
        # Rotation tags need a lever: a nozzle right on the CoM axis produces none.
        self.assertEqual(propulsion.pilot_tags([0.1, 0.0, 0.8], [0, 0, 1], com), [])
        self.assertEqual(propulsion.pilot_tags([0.0, 0.0, 5.0], [0, 1, 0], com), ["heave_down", "pitch_up"])


class StructureAndWeaponTests(unittest.TestCase):
    def test_strut_geometry_anchors_and_collision(self) -> None:
        spec = structure.StrutSpec(length=3.0, thickness=0.2, chord_root=1.2, chord_tip=0.8, sweep=0.5)
        part = structure.strut(spec, S)
        np.testing.assert_allclose(part.anchor("root").position, [0, 0, 0])
        np.testing.assert_allclose(part.anchor("tip").position, [3.0, 0, 0.5])
        np.testing.assert_allclose(part.anchor("tip").direction, [1, 0, 0])
        lo, hi = part.mesh.bounds()
        np.testing.assert_allclose([lo[0], hi[0]], [0.0, 3.0], atol=1e-12)
        np.testing.assert_allclose([lo[1], hi[1]], [-0.1, 0.1], atol=1e-12)
        np.testing.assert_allclose([lo[2], hi[2]], [-0.6, 0.9], atol=1e-12)  # root chord 1.2 centred, tip swept
        self.assertEqual(outward(part.mesh, part.anchor("center").position), 1.0)
        self.assertEqual(part.collision[0].kind, "box")
        np.testing.assert_allclose(part.collision[0].size, [3.0, 0.2, 1.2])
        self.assertEqual({m.name for m in part.mesh.materials}, {"ef_hull", "ef_hull_dark"})

    def test_block_panel_and_mast(self) -> None:
        blk = structure.block(structure.BlockSpec(2.0, (1.0, 0.5), (0.6, 0.3), collide=True), S, "spine")
        lo, hi = blk.mesh.bounds()
        np.testing.assert_allclose(lo, [-0.5, -0.25, -1.0])
        np.testing.assert_allclose(hi, [0.5, 0.25, 1.0])
        self.assertEqual(blk.name, "spine")
        self.assertEqual(blk.collision[0].name, "spine")
        pnl = structure.panel(structure.PanelSpec(2.0, 1.0, 0.04), S)
        lo, hi = pnl.mesh.bounds()
        np.testing.assert_allclose(hi - lo, [2.0, 0.04, 1.0])
        mst = structure.mast(structure.MastSpec(height=1.5, radius=0.04), S)
        lo, hi = mst.mesh.bounds()
        np.testing.assert_allclose([lo[1], hi[1]], [0.0, 1.5], atol=1e-12)
        np.testing.assert_allclose(mst.anchor("tip").position, [0, 1.5, 0])
        self.assertEqual(outward(mst.mesh, [0, 0.75, 0]), 1.0)

    def test_gun_barrel_points_forward(self) -> None:
        spec = weapons.BarrelSpec(length=1.9, radius=0.11, base_radius=0.16)
        part = weapons.gun_barrel(spec, S)
        np.testing.assert_allclose(part.anchor("muzzle").position, [0, 0, -1.9])
        np.testing.assert_allclose(part.anchor("muzzle").direction, [0, 0, -1])
        lo, hi = part.mesh.bounds()
        np.testing.assert_allclose([lo[2], hi[2]], [-1.9, 0.0], atol=1e-12)
        self.assertAlmostEqual(float(hi[0]), 0.16)
        bore = part.mesh.face_material == part.mesh.material_index("ef_bore")
        self.assertTrue(np.all(part.mesh.face_centroids()[bore, 2] < -1.8))
        radial = part.mesh.face_centroids().copy()
        radial[:, 2] = 0.0
        d = np.einsum("ij,ij->i", part.mesh.face_normals(), radial)
        self.assertTrue(np.all(d[~bore] > -1e-9))


def _wedge_spec(**extra) -> hull.WedgeFuselageSpec:
    """A small Starfury-like nose: trapezoid front pane, side and roof panes, eye inside."""
    stations = (
        hull.WedgeStation(
            0.0, 0.9, 0.65, 0.75, 0.78, 0.5, 0.0, rake=math.radians(15.0)
        ),
        hull.WedgeStation(1.4, 1.1, 0.85, 1.3, 0.15, 0.6, -0.8),
        hull.WedgeStation(4.0, 1.2, 1.0, 1.5, 0.1, 0.7, -1.1),
    )
    args = {
        "stations": stations,
        "eye": (0.0, 0.35, 1.0),
        "glass_facets": ("lower", "upper", "top"),
        "mass_kg": 10.0,
    }
    return hull.WedgeFuselageSpec(**{**args, **extra})


class WedgeFuselageTests(unittest.TestCase):
    def test_station_ring_is_a_chamfered_counter_clockwise_shield(self) -> None:
        st = hull.WedgeStation(1.0, 1.0, 0.6, 0.9, 0.2, 0.4, -1.0)
        ring = st.ring_2d(0.05)
        self.assertEqual(ring.shape, (len(hull.WEDGE_FACETS), 2))
        self.assertGreater(g.polygon_area_2d(ring), 0.0)
        self.assertTrue(
            0.85 < float(ring[:, 0].max()) < 0.9
        )  # the shoulder corner is cut by the chamfer
        self.assertAlmostEqual(float(ring[:, 1].min()), -1.0)
        self.assertAlmostEqual(float(ring[:, 1].max()), 1.0)
        raked = hull.WedgeStation(
            0.0, 1.0, 0.6, 0.9, 0.2, 0.4, -1.0, rake=math.radians(45.0)
        ).lift(ring)
        np.testing.assert_allclose(
            raked[:, 2], ring[:, 1] + 1.0, atol=1e-12
        )  # leans back 1 m per metre up
        for bad in (
            (1.0, 1.0, 0.6, 0.9, 1.2, 0.4, -1.0),
            (1.0, 1.0, 0.6, 0.5, 0.2, 0.4, -1.0),
        ):
            with self.assertRaises(ValueError):
                hull.WedgeStation(*bad)
        with self.assertRaises(ValueError):
            st.ring_2d(0.5)

    def test_window_materials_frames_lining_and_anchors(self) -> None:
        spec = _wedge_spec()
        self.assertEqual(spec.glass, {"lower", "upper", "top"})
        self.assertEqual(
            spec.frames, {"keel_chamfer", "shoulder_chamfer", "top_chamfer"}
        )
        self.assertEqual(spec.lined, {"keel"})
        part = hull.wedge_fuselage(spec, S)
        mesh = part.mesh
        names = {m.name for m in mesh.materials}
        self.assertEqual(
            names,
            {
                "ef_hull",
                "ef_hull_dark",
                "ef_canopy_glass",
                "ef_canopy_frame",
                "ef_interior",
            },
        )
        c = mesh.face_centroids()
        glass = mesh.face_material == mesh.material_index("ef_canopy_glass")
        self.assertTrue(np.all(c[glass, 2] < 1.4))  # panes only in the window segment
        self.assertGreater(float(mesh.face_areas()[glass].sum()), 2.0)
        lo, hi = mesh.bounds()
        np.testing.assert_allclose([lo[2], hi[2]], [0.0, 4.0], atol=1e-9)
        np.testing.assert_allclose(part.anchor("eye").position, [0.0, 0.35, 1.0])
        np.testing.assert_allclose(part.anchor("eye").direction, [0.0, 0.0, -1.0])
        self.assertEqual(part.collision[0].kind, "box")
        self.assertEqual(part.mass_kg, 10.0)
        # Hull facets face outwards (from the axis); the lining faces inwards.
        axis = np.column_stack([np.zeros(len(c)), np.full(len(c), 0.1), c[:, 2]])
        side = (np.abs(mesh.face_normals()[:, 2]) < 0.9) & (
            mesh.face_areas() > 1e-9
        )  # collinear fan slivers have no area
        d = np.einsum("ij,ij->i", mesh.face_normals(), c - axis)
        lining = mesh.face_material == mesh.material_index("ef_interior")
        self.assertTrue(np.all(d[side & ~lining] > 0.0))
        self.assertTrue(np.all(d[side & lining] < 0.0))
        # The faces the pilot sees up close: frames, chin and lining of the window, never glass.
        near = hull.wedge_cockpit_faces(spec, mesh, S)
        self.assertFalse(np.any(near & glass))
        self.assertTrue(np.all(c[near, 2] < 1.4))
        self.assertTrue(
            np.any(
                near & (mesh.face_material == mesh.material_index("ef_canopy_frame"))
            )
        )

    def test_contains_and_validation(self) -> None:
        spec = _wedge_spec()
        inside = spec.contains(
            np.array(
                [
                    [0.0, 0.0, 2.0],
                    [1.0, 0.0, 2.0],
                    [0.0, 0.0, -0.1],
                    [0.0, 0.0, 3.99],
                    [2.0, 0.0, 2.0],
                ]
            ),
            0.02,
        )
        self.assertEqual(inside.tolist(), [True, True, False, False, False])
        self.assertFalse(
            spec.contains(np.array([[0.0, 0.85, 0.05]]))[0]
        )  # ahead of the raked front pane
        with self.assertRaises(ValueError):
            _wedge_spec(eye=(0.0, 0.35, 2.0))  # behind the window segment
        with self.assertRaises(ValueError):
            _wedge_spec(eye=(0.0, 3.0, 1.0))  # outside the hull
        with self.assertRaises(ValueError):
            _wedge_spec(glass_facets=("keel_chamfer",))
        with self.assertRaises(ValueError):
            _wedge_spec(frame_width=0.3)  # the front pane's inset would fold over

    def test_cockpit_interior_frames_the_view_and_leaves_the_centre_clear(self) -> None:
        spec = _wedge_spec()
        mesh = hull.wedge_cockpit_interior(spec, S, bar_width=0.09, sill_depth=0.4)
        self.assertEqual({m.name for m in mesh.materials}, {"ef_interior"})
        eye = np.array(spec.eye)
        v = mesh.vertices - eye
        ahead = -v[:, 2]
        off_axis = np.degrees(np.arctan2(np.hypot(v[:, 0], v[:, 1]), ahead))
        self.assertGreater(float(off_axis[ahead > 0.0].min()), 15.0)
        self.assertLess(float(mesh.vertices[:, 2].min()), 0.1)  # reaches the front pane
        self.assertLess(
            float(mesh.vertices[:, 2].max()), 1.4 + 0.1
        )  # nothing aft of the window
        with self.assertRaises(ValueError):
            hull.wedge_cockpit_interior(_wedge_spec(window_end=0), S)


class StarfuryPartTests(unittest.TestCase):
    def test_truss_strut_plate_bands_webs_and_box(self) -> None:
        spec = structure.TrussStrutSpec(
            length=4.0,
            chord_root=2.0,
            chord_tip=1.0,
            sweep=1.5,
            bands=((1.0, 1.5, "hazard"),),
        )
        part = structure.truss_strut(spec, S)
        lo, hi = part.mesh.bounds()
        np.testing.assert_allclose(
            [lo[0], hi[0]], [0.0, 4.0], atol=0.5 * spec.web_thickness
        )  # swept web ends
        self.assertAlmostEqual(float(hi[1]), 0.5 * spec.thickness)
        self.assertAlmostEqual(
            float(lo[1]), -(0.5 * spec.thickness + spec.web_depth_root), places=6
        )
        self.assertAlmostEqual(float(lo[2]), 0.0)
        self.assertAlmostEqual(float(hi[2]), spec.trailing_edge(4.0), places=6)
        hazard = part.mesh.face_material == part.mesh.material_index("ef_hazard")
        x = part.mesh.face_centroids()[hazard, 0]
        self.assertTrue(np.all((x > 1.0) & (x < 1.5)))
        # The webs are ladders: less area than solid webs by the cut-outs.
        web = part.mesh.face_centroids()[:, 1] < -0.5 * spec.thickness - 0.01
        self.assertTrue(web.any())
        np.testing.assert_allclose(part.anchor("tip_le").position, [4.0, 0.0, 1.5])
        box = part.collision[0]
        self.assertEqual(box.kind, "box")
        self.assertAlmostEqual(float(np.linalg.det(box.basis)), 1.0)
        local = (part.mesh.vertices - box.center) @ box.basis
        self.assertTrue(
            np.all(np.abs(local) <= 0.5 * box.size + 1e-9)
        )  # tight and complete
        with self.assertRaises(ValueError):
            structure.truss_strut(structure.TrussStrutSpec(cutouts=40), S)
        with self.assertRaises(ValueError):
            structure.TrussStrutSpec(web_depth_root=0.1)  # shallower than its two rails

    def test_ring_pod_faces_bells_bosses_and_capsule(self) -> None:
        spec = propulsion.RingPodSpec(bosses=(0.0, 90.0))
        pod = propulsion.ring_pod(spec, S)
        main, retro = pod.anchor("main"), pod.anchor("retro")
        np.testing.assert_allclose(
            main.position, [0.0, 0.0, spec.rear_z + spec.main_protrusion]
        )
        np.testing.assert_allclose(main.direction, [0.0, 0.0, 1.0])
        np.testing.assert_allclose(
            retro.position, [0.0, 0.0, spec.front_z - spec.retro_protrusion], atol=1e-12
        )
        np.testing.assert_allclose(retro.direction, [0.0, 0.0, -1.0], atol=1e-12)
        lo, hi = pod.mesh.bounds()
        self.assertAlmostEqual(
            float(hi[2]), main.position[2]
        )  # the main bell's exit is the rearmost point
        self.assertAlmostEqual(float(lo[2]), retro.position[2])
        np.testing.assert_allclose(
            pod.anchor("boss_1").direction, [0.0, 1.0, 0.0], atol=1e-12
        )
        self.assertGreater(float(hi[1]), spec.radius + 0.5 * spec.boss_height)
        names = {m.name for m in pod.mesh.materials}
        self.assertTrue(
            {
                "ef_hull",
                "ef_hull_dark",
                "ef_hull_panel",
                "ef_nozzle",
                "ef_nozzle_throat",
            }
            <= names
        )
        cap = pod.collision[0]
        self.assertEqual((cap.kind, cap.radius), ("capsule", spec.radius))
        self.assertGreater(cap.height, spec.length)
        self.assertEqual(
            spec.contains(
                np.array([[0.0, 0.0, 0.0], [0.0, 0.9, 0.0], [0.0, 0.0, 2.6]])
            ).tolist(),
            [True, False, False],
        )
        with self.assertRaises(ValueError):
            propulsion.RingPodSpec(ring_inner_radius=0.7)

    def test_claw_vanes_blocks_and_rcs_cones(self) -> None:
        spec = propulsion.ClawSpec(
            vanes=(propulsion.VaneSpec(0.0, 0.8, 1.0, ((1.0, 45.0), (1.0, 0.0))),),
            blocks=(
                propulsion.RcsBlockSpec(0.0, 0.9, 1.2, (0.4, 0.4, 0.6), ("px", "ny")),
            ),
        )
        claw = propulsion.claw_cluster(spec, S)
        tip = claw.anchor("vane_0")
        s = math.sqrt(0.5)
        np.testing.assert_allclose(
            tip.position, [0.8 + s, 0.0, 1.0 + s + 1.0], atol=1e-12
        )
        np.testing.assert_allclose(tip.direction, [0.0, 0.0, 1.0], atol=1e-12)
        px, ny = claw.anchor("rcs_px"), claw.anchor("rcs_ny")
        np.testing.assert_allclose(px.direction, [1.0, 0.0, 0.0], atol=1e-12)
        np.testing.assert_allclose(ny.direction, [0.0, -1.0, 0.0], atol=1e-12)
        self.assertAlmostEqual(
            float(px.position[0]), 0.9 + 0.2 - 0.01 + spec.rcs.length
        )
        with self.assertRaises(KeyError):
            claw.anchor("rcs_py")
        box = claw.collision[0]
        self.assertAlmostEqual(float(np.linalg.det(box.basis)), 1.0)
        np.testing.assert_allclose(
            box.center, 0.5 * (spec.vanes[0].path()[0] + tip.position), atol=1e-12
        )

    def test_gun_mount_points_both_barrels_forward(self) -> None:
        spec = weapons.GunMountSpec(barrel_mount_z=-0.6)
        part = weapons.gun_mount(spec, S)
        left, right = part.anchor("muzzle_left"), part.anchor("muzzle_right")
        np.testing.assert_allclose(
            left.position, [-spec.barrel_x, spec.barrel_y, -0.6 - spec.barrel.length]
        )
        np.testing.assert_allclose(
            right.position, [spec.barrel_x, spec.barrel_y, -0.6 - spec.barrel.length]
        )
        np.testing.assert_allclose(left.direction, [0.0, 0.0, -1.0])
        self.assertLess(
            float(right.position[2]), -0.5 * spec.length
        )  # out of the housing's front
        self.assertEqual(part.collision[0].kind, "box")
        self.assertIn("ef_barrel", {m.name for m in part.mesh.materials})
        with self.assertRaises(ValueError):
            weapons.GunMountSpec(barrel_mount_z=1.0)


class StyleTests(unittest.TestCase):
    def test_earthforce_has_every_role_and_a_warm_stripe(self) -> None:
        for role in REQUIRED_ROLES:
            self.assertIsInstance(S.material(role), g.Material)
        r, gg, b = S.material("stripe").albedo
        self.assertTrue(r > gg > b)
        hull_rgb = S.material("hull").albedo
        self.assertLess(max(hull_rgb) - min(hull_rgb), 0.05)  # grey
        self.assertGreater(S.material("canopy_glass").transmittance, 0.0)
        self.assertTrue(S.material("hull").paneled)
        self.assertFalse(S.material("canopy_glass").paneled)
        with self.assertRaises(ValueError):
            Style("broken", {"hull": S.material("hull")})

    def test_shade_panels_is_deterministic_bounded_and_selective(self) -> None:
        rng = np.random.default_rng(0)
        pos = rng.uniform(-3, 3, (5000, 3))
        normals = np.tile([0.0, 1.0, 0.0], (5000, 1))
        albedo = np.full((5000, 3), 0.6)
        paneled = np.arange(5000) % 2 == 0
        shaded = S.shade_panels(albedo, pos, normals, paneled)
        again = S.shade_panels(albedo, pos, normals, paneled)
        np.testing.assert_array_equal(shaded, again)
        np.testing.assert_array_equal(shaded[~paneled], 0.6)
        ratio = shaded[paneled, 0] / 0.6
        self.assertTrue(np.all(ratio <= 1.0 + S.panel_tint_jitter + 1e-12))
        self.assertTrue(np.all(ratio >= S.panel_line_darkness - 1e-12))
        on_line = np.isclose(ratio, S.panel_line_darkness)
        expected_line_fraction = 2 * S.panel_line_width_m / S.panel_size_m
        self.assertAlmostEqual(float(on_line.mean()), expected_line_fraction, delta=0.04)
        self.assertGreater(float(ratio[~on_line].std()), 0.01)  # per-panel tint varies
        np.testing.assert_array_equal(S.shade_panels(albedo, pos, normals, np.zeros(5000, bool)), albedo)
        # A different phase moves the lines.
        moved = S.shade_panels(albedo, pos, normals, paneled, phase=(0.3, 0.0, 0.3))
        self.assertFalse(np.array_equal(moved, shaded))


if __name__ == "__main__":
    unittest.main()
