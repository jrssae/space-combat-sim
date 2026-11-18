"""``grid_heavy_cannon`` (M7-T43): the station's heavy cannon. The parts ``TurretMount`` turns, the maintainer's sizes within 10%
(about 30 m long, an oval muzzle about 9 x 4 m), the one muzzle at the barrel's end, the files and the manifest's ``turret`` entry,
and that the gun clears its recess. Built once on the default seed at a small atlas."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import grid_heavy_cannon as gun
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Mesh
from tools.procgen.parts.station import signed_volume

SPEC = gun.DEFAULT_SPEC


def _within(test: unittest.TestCase, value: float, target: float, what: str) -> None:
    test.assertLessEqual(abs(value - target), 0.1 * target, f"{what}: {value:.2f} m against {target} m")


class CannonShapeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.parts = gun.cannon_parts(SPEC, gun.fine_style(SPEC))
        cls.whole = {part: Mesh.concatenate(m for _, m in meshes) for part, meshes in cls.parts.items()}

    def test_the_three_parts_turret_mount_turns(self) -> None:
        self.assertEqual(tuple(self.parts), gun.PARTS)
        for part, meshes in self.parts.items():
            self.assertTrue(meshes, part)
            names = [n for n, _ in meshes]
            self.assertEqual(len(names), len(set(names)), f"{part}: names are unique")

    def test_every_closed_piece_faces_out(self) -> None:
        # The muzzle, its bore and the tube close only together (the bore runs from the mouth down into the tube).
        barrel = ("muzzle", "bore", "barrel")
        for part, meshes in self.parts.items():
            for name, mesh in meshes:
                if name not in barrel:
                    self.assertGreater(signed_volume(mesh), 0.0, f"{part}/{name}")
        together = Mesh.concatenate(m for n, m in self.parts["pitch"] if n in barrel)
        self.assertGreater(signed_volume(together), 0.0, "the barrel and its bore")

    def test_the_bore_is_deep(self) -> None:
        bore = dict(self.parts["pitch"])["bore"]
        depth = float(bore.bounds()[1][2]) - SPEC.muzzle_z
        self.assertGreaterEqual(depth, 10.0, f"the bore runs {depth:.1f} m back from the mouth")
        self.assertLess(float(bore.bounds()[1][2]), SPEC.body_front_z, "and stays inside the tube")

    def test_nothing_shuts_the_bore_before_its_back_plate(self) -> None:
        # Looking down the bore from the mouth, the first surface crossing its axis is the back plate.
        pitch = self.whole["pitch"]
        tris = pitch.vertices[pitch.faces]
        back = SPEC.muzzle_z + SPEC.bore_depth_m
        for x, y in ((0.0, SPEC.trunnion_y), (2.5, SPEC.trunnion_y + 0.6), (-2.5, SPEC.trunnion_y - 0.6)):
            hits = []
            for t in tris:
                lo, hi = t.min(axis=0), t.max(axis=0)
                if not (lo[0] <= x <= hi[0] and lo[1] <= y <= hi[1]):
                    continue
                # Where the line along z through (x, y) meets the triangle's plane, if inside it.
                a, b, c = t
                nrm = np.cross(b - a, c - a)
                if abs(nrm[2]) < 1e-9:
                    continue
                z = a[2] - (nrm[0] * (x - a[0]) + nrm[1] * (y - a[1])) / nrm[2]
                p = np.array([x, y, z])
                w = [np.dot(np.cross(t[(i + 1) % 3] - t[i], p - t[i]), nrm) for i in range(3)]
                if all(v >= -1e-9 for v in w) or all(v <= 1e-9 for v in w):
                    hits.append(z)
            front = min(z for z in hits if z > SPEC.muzzle_z + 1e-3)
            self.assertAlmostEqual(front, back, places=3, msg=f"at ({x}, {y})")

    def test_about_thirty_metres_long(self) -> None:
        lo = min(m.bounds()[0][2] for m in self.whole.values())
        hi = max(m.bounds()[1][2] for m in self.whole.values())
        _within(self, float(hi - lo), 30.0, "length")
        self.assertAlmostEqual(SPEC.length_m, float(hi - lo), places=6)

    def test_the_oval_muzzle_is_about_nine_by_four(self) -> None:
        # The mouth: the housing's front, up to the back of its chamfered lip.
        muzzle = dict(self.parts["pitch"])["muzzle"].vertices
        mouth = muzzle[muzzle[:, 2] <= SPEC.muzzle_z + 0.4 + 1e-6]
        lo, hi = mouth.min(axis=0), mouth.max(axis=0)
        _within(self, float(hi[0] - lo[0]), 9.0, "muzzle width")
        _within(self, float(hi[1] - lo[1]), 4.0, "muzzle height")

    def test_the_muzzle_point_is_at_the_barrels_end(self) -> None:
        pitch = self.whole["pitch"]
        lo, hi = pitch.bounds()
        x, y, z = SPEC.muzzle()
        self.assertAlmostEqual(z, float(lo[2]), places=6, msg="the muzzle is the gun's foremost point")
        muzzle = dict(self.parts["pitch"])["muzzle"]
        mlo, mhi = muzzle.bounds()
        self.assertAlmostEqual(x, 0.5 * float(mlo[0] + mhi[0]), places=3, msg="on the bore's axis across")
        self.assertAlmostEqual(y, 0.5 * float(mlo[1] + mhi[1]), places=3, msg="and up")
        self.assertEqual(SPEC.pitch_muzzle(), (x, y - SPEC.trunnion_y, z))

    def test_the_racetrack_is_an_oval_of_its_size(self) -> None:
        ring = gun.racetrack(9.0, 4.0, 40)
        self.assertEqual(ring.shape, (40, 2))
        self.assertLessEqual(float(np.abs(ring[:, 0]).max()), 4.5 + 1e-9)
        self.assertLessEqual(float(np.abs(ring[:, 1]).max()), 2.0 + 1e-9)
        self.assertTrue(np.allclose(ring[:, 1][np.abs(ring[:, 0]) < 2.4], np.sign(ring[:, 1][np.abs(ring[:, 0]) < 2.4]) * 2.0),
                        "the middle of the top and bottom is straight")
        area = 0.5 * float(np.sum(ring[:, 0] * np.roll(ring[:, 1], -1) - np.roll(ring[:, 0], -1) * ring[:, 1]))
        self.assertGreater(area, 0.0, "counter-clockwise")

    def test_the_yoke_holds_the_body_and_the_base_sits_on_the_floor(self) -> None:
        base_lo, base_hi = self.whole["base"].bounds()
        self.assertAlmostEqual(float(base_lo[1]), 0.0, places=6)
        yaw_lo, yaw_hi = self.whole["yaw"].bounds()
        self.assertGreater(float(yaw_hi[1]), SPEC.trunnion_y, "the cheeks reach the trunnion")
        body = Mesh.concatenate(m for n, m in self.parts["pitch"] if n in ("body", "ribs"))
        self.assertLess(float(np.abs(body.vertices[:, 0]).max()), SPEC.cheek_inner_x, "the body turns between the cheeks")

    def test_the_breech_clears_the_turntable_straight_up(self) -> None:
        # Raised 90 degrees about the trunnion, a point z behind the trunnion swings down to z below it.
        behind = float(self.whole["pitch"].vertices[:, 2].max())
        table_top = float(self.whole["yaw"].bounds()[0][1]) + 0.8
        self.assertGreater(SPEC.trunnion_y - behind, table_top, "the breech stays over the turntable")

    def test_level_it_clears_the_deck_over_its_recess(self) -> None:
        pitch = self.whole["pitch"]
        self.assertGreater(float(pitch.bounds()[0][1]), gun.RECESS_DEPTH_M, "nothing that lifts sinks below the deck")
        self.assertLess(float(self.whole["yaw"].bounds()[1][1]), gun.RECESS_DEPTH_M + 5.0)


class CannonBuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name) / gun.ASSET_ID
        cls.out = gun.build(BuildContext(cls.dir, seed=42, options={"model_atlas_px": 256}))
        cls.manifest = manifest_io.read_manifest(cls.dir)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_registered_under_its_id(self) -> None:
        self.assertIs(ASSETS[gun.ASSET_ID], gun.build)

    def test_the_whole_mesh_and_a_cut_per_part_are_written(self) -> None:
        names = {p.name for p in self.dir.iterdir()}
        self.assertIn(f"{gun.ASSET_ID}.glb", names)
        self.assertIn(gun.OBJ_NAME, names)
        for part in gun.PARTS:
            self.assertIn(f"{gun.ASSET_ID}_chunk_{part}.glb", names)
        self.assertEqual(sorted(p.name for p in self.out.files), sorted(n for n in names))

    def test_the_turret_entry(self) -> None:
        entry = self.manifest["turret"]
        self.assertEqual(entry["parts"], {p: f"{gun.ASSET_ID}_chunk_{p}.glb" for p in gun.PARTS})
        self.assertEqual(entry["trunnion"], [0.0, SPEC.trunnion_y, 0.0])
        self.assertEqual(entry["muzzles"], [list(SPEC.muzzle())])
        self.assertEqual(entry["pitch_muzzles"], [list(SPEC.pitch_muzzle())])
        self.assertAlmostEqual(entry["barrel_m"], -SPEC.muzzle_z)
        self.assertEqual(entry["muzzle_size_m"], [SPEC.muzzle_w, SPEC.muzzle_h])

    def test_dimensions(self) -> None:
        dims = self.manifest["dimensions_m"]
        _within(self, dims["length"], 30.0, "length")


if __name__ == "__main__":
    unittest.main()
