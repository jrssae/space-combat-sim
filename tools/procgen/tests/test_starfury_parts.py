"""parts/starfury.py: the section loft and plate outlines, and the Starfury's pod, claw, strut, guns and fittings."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.assets import starfury_aurora as ship
from tools.procgen.core import geometry as g
from tools.procgen.parts import starfury as sf
from tools.procgen.styles.earthforce import EARTHFORCE

S = EARTHFORCE
HULL, DARK = S.material("hull"), S.material("hull_dark")


def closed(mesh: g.Mesh) -> bool:
    """Every edge is shared by exactly two faces (vertices compared by position)."""
    keys = {tuple(v): i for i, v in enumerate(np.round(mesh.vertices, 9))}
    ids = np.array([keys[tuple(v)] for v in np.round(mesh.vertices, 9)])
    edges: dict[tuple[int, int], int] = {}
    for f in ids[mesh.faces]:
        for a, b in ((f[0], f[1]), (f[1], f[2]), (f[2], f[0])):
            key = (min(a, b), max(a, b))
            edges[key] = edges.get(key, 0) + 1
    return all(n == 2 for n in edges.values())


class SectionLoftTests(unittest.TestCase):
    def square(self, z: float, size: float = 1.0) -> np.ndarray:
        h = 0.5 * size
        return np.array([[-h, -h, z], [h, -h, z], [h, h, z], [-h, h, z]])

    def test_a_closed_box_winds_outwards_whatever_the_ring_order(self) -> None:
        for rings in ([self.square(0.0), self.square(2.0)], [self.square(2.0), self.square(0.0)],
                      [self.square(0.0)[::-1], self.square(2.0)[::-1]]):  # fmt: skip
            mesh = sf.section_loft(rings, [HULL] * 4, DARK)
            self.assertTrue(closed(mesh))
            self.assertAlmostEqual(sf.signed_volume(mesh), 2.0, places=9)

    def test_edges_carry_their_materials_and_creases_split_vertices(self) -> None:
        rings = [self.square(0.0), self.square(1.0)]
        mesh = sf.section_loft(rings, [HULL, DARK, HULL, DARK], HULL)
        dark = mesh.face_material == mesh.material_index(DARK.name)
        self.assertEqual(int(dark.sum()), 2 * 2 + 0)  # two quads, two triangles each; the caps are hull
        self.assertTrue(np.allclose(np.abs(mesh.face_normals()[dark][:, 0]), 1.0))  # the x faces
        flat = sf.section_loft(rings, [HULL] * 4, DARK)  # every point a crease: four columns per point
        smooth = sf.section_loft(rings, [HULL] * 4, DARK, creases=())
        self.assertGreater(flat.vertex_count, smooth.vertex_count)
        self.assertAlmostEqual(sf.signed_volume(flat), sf.signed_volume(smooth), places=9)

    def test_strip_caps_stay_inside_a_bent_section(self) -> None:
        bent = sf.thick_polyline(np.array([[0.0, 1.0], [1.0, 0.0], [1.0, -1.0]]), 0.1)
        rings = [np.column_stack([bent, np.full(len(bent), z)]) for z in (0.0, 1.0)]
        mesh = sf.section_loft(rings, [HULL] * len(bent), DARK, strip_caps=True)
        self.assertTrue(closed(mesh))
        # A thin bent plate: about its centre line's length times the thickness, nothing bridging the bend.
        self.assertAlmostEqual(sf.signed_volume(mesh), (np.sqrt(2.0) + 1.0) * 0.1, delta=0.02)


class OutlineTests(unittest.TestCase):
    def test_plate_ring_is_flat_between_chamfered_edges(self) -> None:
        ring = sf.plate_ring(-2.0, 1.0, 0.4, points=10)
        self.assertEqual(ring.shape, (20, 2))
        top, bottom = ring[:10], ring[10:]
        self.assertTrue(np.allclose(top[1:-1, 1], 0.2) and np.allclose(bottom[1:-1, 1], -0.2))
        self.assertAlmostEqual(float(top[0, 0]), -2.0)
        self.assertAlmostEqual(float(top[-1, 0]), 1.0)
        self.assertAlmostEqual(float(top[1, 0] - top[0, 0]), 0.6 * 0.4)  # the chamfer
        self.assertEqual(sf.plate_creases(10), [0, 1, 8, 9, 10, 11, 18, 19])

    def test_thick_polyline_keeps_its_thickness_round_a_bend(self) -> None:
        outline = sf.thick_polyline(np.array([[0.0, 0.0], [1.0, 0.0], [1.0, 1.0]]), 0.2)
        self.assertEqual(len(outline), 6)
        self.assertTrue(np.allclose(outline[0], [0.0, 0.1]) and np.allclose(outline[-1], [0.0, -0.1]))
        self.assertTrue(np.allclose(outline[1], [0.9, 0.1]))  # the inner mitre corner


class StarfuryPartTests(unittest.TestCase):
    spec = ship.DEFAULT_SPEC

    def test_pod_exits_are_its_ends_and_it_contains_its_axis(self) -> None:
        pod = sf.fury_pod(self.spec.pod, S)
        lo, hi = pod.mesh.bounds()
        self.assertAlmostEqual(float(pod.anchor("main").position[2]), self.spec.pod.rear_z)
        self.assertAlmostEqual(float(pod.anchor("retro").position[2]), self.spec.pod.front_z)
        self.assertAlmostEqual(float(hi[2]), self.spec.pod.rear_z, places=6)
        self.assertAlmostEqual(float(lo[2]), self.spec.pod.front_z, places=6)
        np.testing.assert_allclose(pod.anchor("main").direction, [0.0, 0.0, 1.0])
        np.testing.assert_allclose(pod.anchor("retro").direction, [0.0, 0.0, -1.0])
        self.assertTrue(self.spec.pod.contains(np.array([[0.0, 0.0, 0.0]]))[0])
        self.assertFalse(self.spec.pod.contains(np.array([[0.0, 1.0, 0.0]]))[0])
        # The knuckle's dome and bulb stand out of the body: up and outboard, 1.44 m from the axis.
        self.assertGreater(float(hi[1]), 1.4)
        self.assertGreater(float(hi[0]), 1.4)
        self.assertLess(float(lo[0]), -0.9)  # inboard only the body and clamps
        cap = pod.collision[0]
        self.assertAlmostEqual(cap.radius, self.spec.pod.radius)
        self.assertGreater(cap.height, self.spec.pod.length)

    def test_claw_blades_are_closed_and_carry_four_rcs_cones(self) -> None:
        claw = sf.fury_claw(self.spec.claw, S)
        self.assertEqual(sorted(k for k in claw.anchors if k.startswith("rcs_")), ["rcs_nx", "rcs_ny", "rcs_px", "rcs_py"])
        for face, axis, sign in (("px", 0, 1.0), ("nx", 0, -1.0), ("py", 1, 1.0), ("ny", 1, -1.0)):
            a = claw.anchor(f"rcs_{face}")
            self.assertAlmostEqual(float(a.direction[axis]), sign)
            self.assertGreater(float(np.hypot(*a.position[:2])), self.spec.pod.radius_at(a.position[2]))
        for blade in self.spec.claw.blades:
            rings = blade.rings()
            mesh = sf.section_loft(rings, [HULL] * len(rings[0]), DARK, strip_caps=True)
            self.assertTrue(closed(mesh))
            self.assertGreater(sf.signed_volume(mesh), 0.0)
        box = claw.collision[0]
        self.assertGreater(float(box.basis[2, 0]), 0.9)  # along the pincer: aft

    def test_struts_are_closed_plates_with_hazard_bands_and_a_box_along_the_beam(self) -> None:
        for spec in (self.spec.strut, self.spec.lower_strut):
            strut = sf.fury_strut(spec, S)
            names = {m.name for m in strut.mesh.materials}
            self.assertIn("ef_hazard", names)
            box = strut.collision[0]
            local = (strut.mesh.vertices - box.center) @ box.basis
            self.assertTrue(np.all(np.abs(local) <= 0.5 * box.size + 1e-6))
            self.assertTrue(np.all(np.abs(box.basis[:, 0]) > 0.15))  # out, up and aft
            lo, hi = strut.mesh.bounds()
            self.assertAlmostEqual(float(lo[0]), 0.0)  # the deck reaches the centre line
            self.assertAlmostEqual(float(hi[0]), spec.deck[-1].x, places=6)  # and runs into the pod
        # The lower brace is rooted higher than the upper one, close under its deck.
        self.assertGreater(self.spec.lower_strut.brace[0].y, self.spec.strut.brace[0].y + 0.5)

    def test_guns_put_the_muzzles_at_the_barrel_tips(self) -> None:
        guns = sf.fury_guns(self.spec.gun_mount, S)
        for name, sign in (("right", 1.0), ("left", -1.0)):
            a = guns.anchor(f"muzzle_{name}")
            np.testing.assert_allclose(
                a.position, [sign * self.spec.gun_mount.barrel_x, self.spec.gun_mount.barrel_y, self.spec.gun_mount.muzzle_z]
            )
            np.testing.assert_allclose(a.direction, [0.0, 0.0, -1.0])
        lo, _ = guns.mesh.bounds()
        self.assertAlmostEqual(float(lo[2]), self.spec.gun_mount.keel[3])  # the keel box's prow is foremost

    def test_fittings_are_mirror_symmetric(self) -> None:
        mesh = sf.fury_fittings(self.spec.fittings, S).mesh
        v = np.round(mesh.vertices, 6)
        mirrored = v * np.array([-1.0, 1.0, 1.0])
        self.assertEqual(sorted(map(tuple, v)), sorted(map(tuple, np.round(mirrored, 6) + 0.0)))


if __name__ == "__main__":
    unittest.main()
