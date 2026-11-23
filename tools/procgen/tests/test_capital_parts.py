"""The capital parts library (M10-T05, D12.1; ``parts/capital*.py``): every part gives a module whose mesh, collision shapes
and hardpoints agree and move together, names its hardpoint's kind and numbers, and refuses sizes that make no part."""

from __future__ import annotations

import math
import unittest

import numpy as np

from tools.procgen.core import collision as col
from tools.procgen.core.geometry import rotation_y
from tools.procgen.parts import capital as cp
from tools.procgen.parts import capital_bays as bays
from tools.procgen.parts import capital_engines as engines
from tools.procgen.parts import capital_fittings as fittings
from tools.procgen.parts import capital_hull as hull
from tools.procgen.parts import capital_weapons as weapons
from tools.procgen.styles.capital import FRAMEWORK_GREY
from tools.procgen.styles.ea_capital import ea_capital

STYLE = FRAMEWORK_GREY.style
STATIONS = (hull.Station(0.0, 20.0, 10.0, 3.0), hull.Station(40.0, 22.0, 11.0, 4.0), hull.Station(70.0, 15.0, 8.0, 2.0, 1.0))


def library() -> dict[str, cp.Module]:
    """One module of every part of the library."""
    return {
        "hull_section": hull.hull_section("hull", STATIONS, STYLE),
        "prow": hull.prow("prow", STATIONS[1], 30.0, STYLE),
        "armour_plates": hull.armour_plates("armour", (20.0, 30.0), (3, 4), 0.5, STYLE),
        "turret_mount": weapons.turret_mount("turret", 5.0, STYLE),
        "beam_emitter": weapons.beam_emitter("beam", 14.0, STYLE),
        "interceptor_dome": weapons.interceptor_dome("interceptor", 1.8, STYLE),
        "missile_launcher": weapons.missile_launcher("missiles", (4, 3), 1.6, STYLE),
        "mine_layer": weapons.mine_layer("mines", (4.0, 2.5), 6.0, STYLE),
        "launch_bay": bays.launch_bay("bay", (14.0, 9.0), 30.0, STYLE),
        "launch_tube": bays.launch_tube("tube", 1.5, 12.0, STYLE),
        "engine_block": engines.engine_block("engine", (10.0, 14.0, 28.0), (2, 2), STYLE),
        "rotating_section": fittings.rotating_section("ring", (9.5, 12.0, 22.0), (4.0, 13.5), (8.0, 5.0, 20.0), STYLE, arms=3),
        "antenna": fittings.antenna("antenna", 5.0, STYLE, dish_m=2.0),
        "lamp": fittings.lamp("lamp", "port", (1.0, 0.05, 0.03), 90.0),
    }


class CapitalPartsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.parts = library()

    def test_every_part_is_a_valid_mesh_with_mass(self) -> None:
        for name, m in self.parts.items():
            m.part.mesh.validate()
            self.assertGreater(m.part.mesh.face_count, 0, name)
            self.assertTrue(np.all(np.isfinite(m.part.mesh.vertices)), name)
            self.assertGreater(float(m.part.mesh.face_areas().min()), 1e-9, f"{name}: no empty triangle")
            self.assertGreater(m.part.mass_kg, 0.0, name)

    def test_the_collision_shapes_hold_the_mesh_and_stay_close(self) -> None:
        for name, m in self.parts.items():
            lo, hi = m.part.mesh.bounds()
            size = float(np.linalg.norm(hi - lo))
            gap = col.gaps(m.shapes, m.part.mesh.vertices)
            self.assertLessEqual(float(gap.max()), max(0.3, 0.03 * size), f"{name}: every corner of the mesh is in or near a shape")
            slo = np.min([s.bounds()[0] for s in m.shapes], axis=0)
            shi = np.max([s.bounds()[1] for s in m.shapes], axis=0)
            self.assertTrue(np.all(slo >= lo - 0.06 * size - 0.3) and np.all(shi <= hi + 0.06 * size + 0.3), f"{name}: no shape far outside")
            self.assertEqual(len({s.name for s in m.shapes}), len(m.shapes), f"{name}: shape names are unique")

    def test_each_weapon_kind_has_its_mount_and_numbers(self) -> None:
        wanted = {"turret_mount": (cp.TURRET, ("traverse_deg", "elevation_deg", "barrel_m", "barrels")),
                  "beam_emitter": (cp.BEAM, ("arc_deg", "aperture_m")),
                  "interceptor_dome": (cp.INTERCEPTOR, ("traverse_deg", "elevation_deg", "radius_m")),
                  "missile_launcher": (cp.MISSILE, ("cells", "cell_m")),
                  "mine_layer": (cp.MINE, ("mouth_m",))}
        self.assertEqual({kind for kind, _ in wanted.values()}, set(cp.WEAPON_KINDS), "a mount for every weapon kind")
        for name, (kind, keys) in wanted.items():
            (point,) = self.parts[name].hardpoints
            self.assertEqual(point.kind, kind, name)
            for key in keys:
                self.assertIn(key, point.params, name)
            self.assertAlmostEqual(float(np.linalg.norm(point.forward)), 1.0, places=9)
            self.assertLessEqual(float(col.gaps(self.parts[name].shapes, point.position[None]).max()), 0.6, f"{name}: the hardpoint is on its mount")

    def test_a_turret_and_a_beam_point_forward_missiles_leave_upward_mines_aft(self) -> None:
        for name, forward in (("turret_mount", (0, 0, -1)), ("beam_emitter", (0, 0, -1)), ("missile_launcher", (0, 1, 0)), ("mine_layer", (0, 0, 1))):
            np.testing.assert_allclose(self.parts[name].hardpoints[0].forward, forward, atol=1e-9, err_msg=name)
        turret = self.parts["turret_mount"]
        muzzle = turret.part.mesh.vertices[:, 2].min()
        self.assertAlmostEqual(turret.hardpoints[0].position[2] - muzzle, turret.hardpoints[0].params["barrel_m"], delta=0.01)

    def test_a_bay_has_a_start_pose_an_exit_and_an_open_hall(self) -> None:
        bay = self.parts["launch_bay"]
        (point,) = bay.hardpoints
        self.assertEqual(point.kind, cp.BAY)
        np.testing.assert_allclose(point.forward, (0.0, 0.0, -1.0))
        exit_ = np.array(point.params["exit"])
        self.assertAlmostEqual(float(exit_[2]), 0.0, msg="the exit is the mouth's centre plane")
        self.assertAlmostEqual(float(point.position[2]), 15.0, msg="a craft starts half way down the hall")
        # A Starfury's box flown from the start out through the mouth touches no shape.
        box = np.array([[x, y, z] for x in (-5.5, 5.5) for y in (-2.0, 5.0) for z in (-4.5, 4.5)])
        for z in np.linspace(float(point.position[2]), -12.0, 12):
            path = box + (0.0, float(point.position[1]), z)
            inside = path[path[:, 2] > 0.0]
            if len(inside):
                self.assertGreater(float(col.gaps(bay.shapes, inside).min()), 0.2, f"hall clear at z = {z:.1f}")
        self.assertEqual(float(col.gaps(bay.shapes, np.array([[0.0, 0.0, 30.5]])).max()), 0.0, "the hall has a back wall")

    def test_a_lit_bay_keeps_the_hull_paint_and_glows_red(self) -> None:
        ea = ea_capital().style
        plain = bays.launch_bay("bay", (18.0, 12.0), 30.0, ea, 2.0)
        lit = bays.launch_bay("bay", (18.0, 12.0), 30.0, ea, 2.0, lit=True)

        def used(m: cp.Module) -> set[str]:
            mesh = m.part.mesh
            return {mesh.materials[i].name for i in set(mesh.face_material.tolist())}

        roles = {role: ea.material(role).name for role in ("hull", "hazard", "hazard_dark", *bays.BAY_LIGHT_ROLES)}
        self.assertTrue({roles["hazard_dark"], roles["hazard"]} <= used(plain))
        self.assertFalse({roles["hazard_dark"], roles["hazard"]} & used(lit), "no dark frame or warm deck: the hull's paint round the mouth")
        self.assertTrue({roles[r] for r in bays.BAY_LIGHT_ROLES} <= used(lit), "the mouth's band, the hall's strips and the corner lamps")
        for role in bays.BAY_LIGHT_ROLES:
            glow = ea.material(role)
            self.assertGreater(glow.emissive_strength, 0.0, role)
            self.assertGreater(glow.emissive[0], 4.0 * glow.emissive[1], f"{role} is red")
        self.assertEqual([s.name for s in lit.shapes], [s.name for s in plain.shapes], "the light adds no collision")
        launch, light = lit.hardpoints
        self.assertEqual((launch.kind, light.kind, light.params["role"]), (cp.BAY, cp.LIGHT, bays.BAY_LIGHT_ROLE))
        self.assertTrue(0.0 < float(light.position[2]) < 30.0, "the light is in the hall")
        np.testing.assert_allclose(light.forward, (0.0, 0.0, -1.0), err_msg="shining out of the mouth")
        lo, hi = lit.part.mesh.bounds()
        self.assertGreater(float(lo[2]), -1.0, "nothing stands more than a lamp proud of the mouth")
        self.assertLessEqual(float(hi[0]), 11.0 + 1e-6, "nor outside the housing")

    def test_a_bay_door_and_an_unlit_rim_are_off_unless_asked_for(self) -> None:
        ea = ea_capital().style
        lit = bays.launch_bay("bay", (18.0, 10.0), 10.5, ea, 1.0, lit=True)
        np.testing.assert_array_equal(bays.launch_bay("bay", (18.0, 10.0), 10.5, ea, 1.0, lit=True, rim=True, door=False).part.mesh.vertices,
                                      lit.part.mesh.vertices, err_msg="the defaults build what they always did")
        self.assertNotIn(cp.DOOR, [h.kind for h in lit.hardpoints])
        quiet = bays.launch_bay("bay", (18.0, 10.0), 10.5, ea, 1.0, lit=True, rim=False, door=True)
        band = ea.material("bay_light").name
        mesh = quiet.part.mesh
        faces = [i for i, m in enumerate(mesh.face_material.tolist()) if mesh.materials[m].name == band]
        self.assertGreater(float(mesh.vertices[mesh.faces[faces]].reshape(-1, 3)[:, 2].min()), 0.0, "the red stays inside the hall")
        door = next(h for h in quiet.hardpoints if h.kind == cp.DOOR)
        self.assertEqual(door.name, "bay_door")
        self.assertLess(float(door.position[2]), 0.0, "the shutter hangs just outside the mouth")
        self.assertGreaterEqual(door.params["size_m"][1], 10.0, "and covers it")
        lo, hi = mesh.bounds()
        self.assertLess(float(lo[2]), float(door.position[2]), "the roll housing stands proud of the shutter")
        self.assertGreater(float(hi[1]), 5.0 + 1.0, "over the mouth")

    def test_a_tube_starts_at_its_breech_and_its_bore_is_open(self) -> None:
        tube = self.parts["launch_tube"]
        (point,) = tube.hardpoints
        self.assertEqual(point.kind, cp.TUBE)
        self.assertGreater(float(point.position[2]), 0.8 * 12.0)
        bore = np.array([[0.0, 0.0, z] for z in np.linspace(0.0, 10.0, 11)])
        self.assertGreater(float(col.gaps(tube.shapes, bore).min()), 1.0)

    def test_an_engine_block_shares_its_thrust_between_its_bells(self) -> None:
        block = self.parts["engine_block"]
        self.assertEqual([h.kind for h in block.hardpoints], [cp.ENGINE] * 4)
        self.assertAlmostEqual(sum(h.params["share"] for h in block.hardpoints), 1.0)
        stern = float(block.part.mesh.vertices[:, 2].max())
        for h in block.hardpoints:
            np.testing.assert_allclose(h.forward, (0.0, 0.0, -1.0), err_msg="the push is forward, the exhaust aft")
            self.assertAlmostEqual(float(h.position[2]), stern, delta=1e-6, msg="at the bell's mouth")
        half = engines.engine_block("half", (10.0, 14.0, 28.0), (1, 2), STYLE, share=0.5)
        self.assertAlmostEqual(sum(h.params["share"] for h in half.hardpoints), 0.5)

    def test_a_rotating_section_is_round_its_axis_with_an_open_bore(self) -> None:
        ring = self.parts["rotating_section"]
        v = ring.part.mesh.vertices
        self.assertGreaterEqual(float(np.hypot(v[:, 0], v[:, 1]).min()), 9.5 - 1e-6, "nothing inside the collar's bore")
        axis = np.array([[0.0, 0.0, z] for z in (-10.0, 0.0, 10.0)])
        self.assertGreater(float(col.gaps(ring.shapes, axis).min()), 9.0, "the hull runs through it")
        turned = ring.part.mesh.vertices @ np.array([[math.cos(2.0 * math.pi / 3.0), -math.sin(2.0 * math.pi / 3.0), 0.0],
                                                     [math.sin(2.0 * math.pi / 3.0), math.cos(2.0 * math.pi / 3.0), 0.0], [0.0, 0.0, 1.0]]).T
        self.assertAlmostEqual(float(np.hypot(turned[:, 0], turned[:, 1]).max()), float(np.hypot(v[:, 0], v[:, 1]).max()), places=6)

    def test_a_lamp_carries_its_role_colour_and_range(self) -> None:
        (point,) = self.parts["lamp"].hardpoints
        self.assertEqual((point.kind, point.params["role"], point.params["range_m"]), (cp.LIGHT, "port", 90.0))
        self.assertGreater(point.params["colour"][0], point.params["colour"][1], "port is red")
        with self.assertRaisesRegex(ValueError, "role"):
            fittings.lamp("bad", "sideways", (1.0, 1.0, 1.0), 10.0)

    def test_a_module_moves_its_mesh_shapes_and_hardpoints_together(self) -> None:
        for name in ("turret_mount", "launch_bay", "engine_block"):
            m = self.parts[name]
            turn, shift = rotation_y(0.7), np.array([12.0, -3.0, 40.0])
            moved = m.transformed(turn, shift)
            np.testing.assert_allclose(moved.part.mesh.vertices, m.part.mesh.vertices @ turn.T + shift, atol=1e-9)
            for a, b in zip(m.hardpoints, moved.hardpoints, strict=True):
                np.testing.assert_allclose(b.position, turn @ a.position + shift, atol=1e-9)
                np.testing.assert_allclose(b.forward, turn @ a.forward, atol=1e-9)
            self.assertLessEqual(float(col.gaps(moved.shapes, moved.part.mesh.vertices).max()), float(col.gaps(m.shapes, m.part.mesh.vertices).max()) + 1e-6)
        bay = self.parts["launch_bay"].translated((1.0, 2.0, 3.0))
        np.testing.assert_allclose(bay.hardpoints[0].params["exit"], (1.0, 0.5, 3.0), err_msg="the exit moves with the bay")

    def test_mounted_stands_a_part_on_any_face(self) -> None:
        turret = self.parts["turret_mount"].mounted((30.0, 0.0, 50.0), up=(1.0, 0.0, 0.0), forward=(0.0, 0.0, -1.0))
        np.testing.assert_allclose(turret.hardpoints[0].up, (1.0, 0.0, 0.0), atol=1e-9)
        np.testing.assert_allclose(turret.hardpoints[0].forward, (0.0, 0.0, -1.0), atol=1e-9)
        self.assertGreaterEqual(float(turret.part.mesh.vertices[:, 0].min()), 30.0 - 1e-9, "it stands out from the face")
        basis = cp.mount_basis((0.0, -1.0, 0.0), (0.2, 0.3, -1.0))
        np.testing.assert_allclose(basis.T @ basis, np.eye(3), atol=1e-9)
        self.assertAlmostEqual(float(np.linalg.det(basis)), 1.0, places=9)
        with self.assertRaisesRegex(ValueError, "forward"):
            cp.mount_basis((0.0, 1.0, 0.0), (0.0, 2.0, 0.0))

    def test_a_twin_is_the_mirror_image_with_port_names(self) -> None:
        m = weapons.turret_mount("turret_2_r", 5.0, STYLE).mounted((10.0, 11.0, 100.0)).in_section("engine_r").on_side(cp.RIGHT)
        twin = m.twin()
        self.assertEqual((twin.name, twin.section, twin.hardpoints[0].name), ("turret_2_l", "engine_l", "turret_2_l"))
        self.assertEqual([s.name for s in twin.shapes], ["turret_2_l", "turret_2_l_guns"])
        np.testing.assert_allclose(twin.hardpoints[0].position, m.hardpoints[0].position * (-1.0, 1.0, 1.0))
        np.testing.assert_allclose(np.sort(twin.part.mesh.vertices[:, 0]), np.sort(-m.part.mesh.vertices[:, 0]))
        self.assertEqual(cp.with_twins([m, self.parts["antenna"]])[1].name, "turret_2_l")
        self.assertEqual([cp.port_name(n) for n in ("engine_r_2", "turret_2_r_guns", "rotor", "radar")], ["engine_l_2", "turret_2_l_guns", "rotor", "radar"])

    def test_a_hull_section_paints_decks_keels_and_flanks_by_their_facing(self) -> None:
        mesh = self.parts["hull_section"].part.mesh
        normals = mesh.face_normals()
        names = np.array([m.name for m in mesh.materials])[mesh.face_material]
        walls = np.abs(normals[:, 2]) < 0.9  # not the end caps
        self.assertTrue(np.all(names[walls & (normals[:, 1] > 0.7)] == STYLE.material("hull_panel").name), "decks")
        self.assertTrue(np.all(names[walls & (normals[:, 1] < -0.7)] == STYLE.material("hull_dark").name), "keels")
        self.assertTrue(np.all(names[walls & (np.abs(normals[:, 0]) > 0.9)] == STYLE.material("hull").name), "flanks")
        centre = mesh.vertices.mean(axis=0)
        self.assertGreater(float(np.min(np.einsum("ij,ij->i", normals, mesh.face_centroids() - centre))), 0.0, "every face looks outward")
        open_end = hull.hull_section("open", STATIONS, STYLE, caps=(False, True))
        self.assertEqual(mesh.face_count - open_end.part.mesh.face_count, 6, "an open end leaves its cap out")

    def test_a_hull_sections_solid_is_its_volume(self) -> None:
        solid = self.parts["hull_section"].solid
        inside = np.array([[0.0, 0.0, 20.0], [19.0, 0.0, 30.0], [0.0, 8.5, 69.0]])
        outside = np.array([[21.5, 10.5, 39.0], [0.0, 0.0, -1.0], [0.0, 11.5, 20.0], [16.0, 0.0, 69.5]])
        self.assertTrue(solid.contains(inside).all())
        self.assertFalse(solid.contains(outside).any())

    def test_sizes_that_make_no_part_are_refused(self) -> None:
        for make in (lambda: hull.Station(0.0, 10.0, 5.0, 6.0), lambda: hull.hull_section("x", STATIONS[:1], STYLE),
                     lambda: hull.hull_section("x", STATIONS[::-1], STYLE), lambda: hull.armour_plates("x", (2.0, 2.0), (8, 8), 0.5, STYLE),
                     lambda: weapons.turret_mount("x", 0.0, STYLE), lambda: weapons.missile_launcher("x", (0, 2), 1.0, STYLE),
                     lambda: bays.launch_bay("x", (10.0, 0.0), 20.0, STYLE), lambda: bays.launch_tube("x", 2.0, 3.0, STYLE),
                     lambda: engines.engine_block("x", (10.0, 10.0, 20.0), (1, 1), STYLE, share=1.5),
                     lambda: fittings.rotating_section("x", (9.0, 12.0, 20.0), (4.0, 11.0), (8.0, 5.0, 20.0), STYLE),
                     lambda: cp.Hardpoint("x", "cannon", (0, 0, 0), (0, 0, -1), (0, 1, 0)),
                     lambda: cp.Hardpoint("x", cp.TURRET, (0, 0, 0), (0, 0, 0), (0, 1, 0))):
            with self.assertRaises(ValueError):
                make()


if __name__ == "__main__":
    unittest.main()
