"""No lamp or panel may z-fight (M7): the station's props, its drum with the props in place, its frame's detail and the hangar
behind the menu hold no two faces in one plane, facing the same way, one over the other."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.assets import b5_interior
from tools.procgen.assets import babylon5_station as b5
from tools.procgen.core.geometry import Material, Mesh
from tools.procgen.parts import station as st
from tools.procgen.parts import station_props as sp
from tools.procgen.parts.station import block
from tools.procgen.tests.coplanar_checks import coplanar_overlaps, describe, mesh_triangles

GREY = Material("grey", (0.5, 0.5, 0.5))
# The frame's hull parts that still overlap themselves in one paint (no lamp among them): to be rebuilt with the hull, not here.
HULL_SELF_OVERLAPS = {"radiators", "spine", "truss", "vanes", "bow"}


def boxes(*spans: tuple[tuple[float, float, float], tuple[float, float, float]]) -> np.ndarray:
    return mesh_triangles(Mesh.concatenate([block(lo, hi, GREY) for lo, hi in spans]))


class CheckerTests(unittest.TestCase):
    PANEL = ((19.0, -18.5, -3.0), (19.8, -2.0, 3.0))

    def test_a_lamp_flush_in_its_panel_is_found(self) -> None:
        found = coplanar_overlaps(boxes(self.PANEL, ((19.0, -12.0, -0.8), (19.8, -10.0, 0.8))))
        self.assertEqual(len(found), 8, "both shared faces, two triangles on two each")
        self.assertAlmostEqual(sum(o.area for o in found), 2 * 2.0 * 1.6, places=6)

    def test_a_lamp_proud_of_its_panel_is_clear(self) -> None:
        self.assertEqual(coplanar_overlaps(boxes(self.PANEL, ((18.7, -12.0, -0.8), (19.7, -10.0, 0.8)))), [])

    def test_faces_a_hair_apart_still_count(self) -> None:
        self.assertTrue(coplanar_overlaps(boxes(self.PANEL, ((18.99, -12.0, -0.8), (19.7, -10.0, 0.8)))))

    def test_boxes_side_by_side_or_back_to_back_are_clear(self) -> None:
        self.assertEqual(coplanar_overlaps(boxes(((0, 0, 0), (1, 1, 1)), ((1, 0, 0), (2, 1, 1)))), [], "touching, not overlapping")
        self.assertEqual(coplanar_overlaps(boxes(((0, 0, 0), (1, 1, 1)), ((0, 1, 0), (1, 2, 1)))), [], "stacked: the faces meet back to back")

    def test_a_box_set_on_another_s_edge_is_found(self) -> None:
        found = coplanar_overlaps(boxes(((0, 0, 0), (4, 1, 2)), ((0, 0.5, 0), (1, 3, 2))))
        self.assertTrue(found)
        self.assertTrue(all(abs(o.normal[1]) < 0.5 for o in found), "their shared side faces, not the tops")


class StationTests(unittest.TestCase):
    def test_no_prop_overlaps_itself(self) -> None:
        for kind in sp.kinds():
            found = coplanar_overlaps(mesh_triangles(kind.mesh))
            self.assertEqual(found, [], f"{kind.name}: {describe(found)}")

    def test_the_hall_lamps_stand_proud_of_their_panels(self) -> None:
        lamps = [(lo, hi) for lo, hi, swatch in sp.GANTRY_BLOCKS if swatch == len(sp.STATION_SWATCHES)]
        panels = [(lo, hi) for lo, hi, swatch in sp.GANTRY_BLOCKS if swatch == sp.STATION_SWATCHES.index("recess")]
        self.assertEqual(len(lamps), 3)
        for lo, hi in lamps:
            inner = min(abs(lo[0]), abs(hi[0]))
            for plo, phi in panels:
                if (plo[0] > 0) == (lo[0] > 0) and abs(lo[0]) < 30.0:
                    self.assertLess(inner, min(abs(plo[0]), abs(phi[0])) - 0.1, "the lamp's face is nearer the hall's middle than the panel's")

    def test_the_drum_with_its_props_in_place_has_no_overlap(self) -> None:
        tris = [mesh_triangles(s.mesh) for s in st.drum_shapes(b5.STYLE.materials)]
        kinds = {k.name: k.mesh for k in sp.kinds()}
        for group in sp.groups("waist", np.zeros(3)):
            for transform in group.transforms:
                t = np.asarray(transform)
                tris.append(mesh_triangles(kinds[group.kind]) @ t[:, :3].T + t[:, 3])
        found = coplanar_overlaps(np.concatenate(tris))
        self.assertEqual(found, [], describe(found))

    def test_the_door_glow_lies_under_the_leaves_faces(self) -> None:
        self.assertLess(st.DOOR_GLOW_TOP_M, sp.LEAF_FACE[1] - 0.05)

    def test_the_frame_overlaps_only_in_its_known_hull_parts(self) -> None:
        names, tris = [], []
        for shape in st.frame_shapes(b5.STYLE.materials):
            t = mesh_triangles(shape.mesh)
            tris.append(t)
            names += [shape.name] * len(t)
        found = coplanar_overlaps(np.concatenate(tris))
        stray = [o for o in found if names[o.first] != names[o.second] or names[o.first] not in HULL_SELF_OVERLAPS]
        self.assertEqual(stray, [], describe(stray))


class InteriorTests(unittest.TestCase):
    def test_the_whole_hall_has_no_overlap(self) -> None:
        found = coplanar_overlaps(mesh_triangles(b5_interior.whole_hall()))
        self.assertEqual(found, [], describe(found))


if __name__ == "__main__":
    unittest.main()
