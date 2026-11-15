"""The bow spine's rook tower (M7-T43): narrow enough for the heavy cannons to cover each other round it, a smooth round top that
mounts I5, and its own collision hulls (never merged into a wider one) that hold the mesh."""

from __future__ import annotations

import math
import unittest

import numpy as np

from tools.procgen.core import collision as col
from tools.procgen.core.geometry import Material
from tools.procgen.parts import station_hardpoints as sh
from tools.procgen.parts import station_tower as tw
from tools.procgen.parts.station import signed_volume

GREY = Material("grey", (0.5, 0.5, 0.5))


class TowerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mesh = tw.tower_mesh(GREY)

    def test_a_closed_solid(self) -> None:
        self.assertGreater(signed_volume(self.mesh), 0.0)

    def test_a_rook_slim_shaft_flared_base_and_round_top(self) -> None:
        radii = dict(tw.PROFILE[1:-1])
        shaft = min(r for _, r in tw.PROFILE[1:-1])
        self.assertLessEqual(shaft, 9.0, "the shaft is 18 m across")
        self.assertGreater(radii[tw.FOOT_Y], 1.5 * shaft, "the base flares out where it meets the spine")
        top = [r for y, r in tw.PROFILE[1:-1] if y >= tw.CROWN_Y - 10.0]
        self.assertTrue(all(abs(r - top[0]) < 1e-9 for r in top), "the top is a plain cylinder")
        self.assertGreater(top[0], shaft, "wider than the shaft")
        self.assertAlmostEqual(float(self.mesh.bounds()[1][1]), tw.CROWN_Y, msg="nothing stands on the top but I5")

    def test_i5_stands_on_the_top(self) -> None:
        i5 = next(p for name, _, _, p, _ in sh.GRID_MOUNTS if name == "I5")
        self.assertLess(math.hypot(i5[0], i5[2] - tw.CENTRE_Z), tw.PROFILE[-2][1] - 6.5, "its plinth fits the top")
        self.assertGreater(i5[1], tw.CROWN_Y)

    def test_the_hulls_hold_the_mesh_and_stay_narrow(self) -> None:
        pieces = tw.collision_pieces()
        faces = []
        for _, pts in pieces:
            self.assertLessEqual(len(pts), 32, "inside the hull point budget")
            faces.append(col.hull_faces(pts))
        v = self.mesh.vertices
        inside = np.zeros(len(v), bool)
        for f in faces:
            inside |= np.all(v @ f.normals.T - f.offsets <= 1e-3, axis=1)
        self.assertTrue(inside.all(), f"{int((~inside).sum())} vertices outside every hull")
        self.assertLess(max(np.abs(p[:, 0]).max() for _, p in pieces), 16.0, "no hull reaches the recesses")


class FrameCollisionTests(unittest.TestCase):
    def test_the_tower_keeps_its_own_hulls(self) -> None:
        from tools.procgen.assets import babylon5_station as station  # noqa: PLC0415

        frame = next(e for e in station.collision_section()["pieces"] if e["name"] == "frame")
        towers = [s for s in frame["shapes"] if "/tower." in s["name"]
                  and abs(float(np.mean(np.asarray(s["points"])[:, 2]) + station.ORIGIN[2] - tw.CENTRE_Z)) < 30.0]
        self.assertEqual(len(towers), len(tw.collision_pieces()), "none merged into a wider hull")
        for s in towers:
            pts = np.asarray(s["points"]) + station.ORIGIN
            self.assertLess(float(np.abs(pts[:, 0]).max()), 16.0, s["name"])


if __name__ == "__main__":
    unittest.main()
