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
