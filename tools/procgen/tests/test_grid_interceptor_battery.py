"""``grid_interceptor_battery`` (M7-T42): the parts ``TurretMount`` turns, the maintainer's sizes, the muzzles at the barrels' ends,
the symmetry, the barrels' clearance at any elevation and the output contract. One build at a small atlas (a few seconds)."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import grid_interceptor_battery as gib
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Mesh

SPEC = gib.DEFAULT_SPEC
# The maintainer's sizes (2026-11-15), each to be met within 10 %.
TALL_M, PEDESTAL_M, WIDE_M, BARREL_M = 15.0, 8.0, 10.0, 9.0


def _within(test: unittest.TestCase, value: float, target: float, what: str) -> None:
    test.assertLessEqual(abs(value - target), 0.1 * target, f"{what}: {value:.2f} m against {target} m")


class GridInterceptorBatteryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name) / gib.ASSET_ID
        cls.out = gib.build(BuildContext(cls.dir, seed=42, options={"model_atlas_px": 512}))
        cls.manifest = manifest_io.read_manifest(cls.dir)
        groups = gib.battery_parts(SPEC, gib.fine_style(SPEC))
        cls.parts = {part: Mesh.concatenate(m for _, m in groups[part]) for part in gib.PARTS}
        cls.named = {name: m for part in gib.PARTS for name, m in groups[part]}

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_registered_under_its_id(self) -> None:
        self.assertIs(ASSETS[gib.ASSET_ID], gib.build)

    def test_the_turret_entry_names_three_parts_written_beside_it(self) -> None:
        entry = self.manifest["turret"]
        self.assertEqual(sorted(entry["parts"]), sorted(gib.PARTS))
        for file in entry["parts"].values():
            self.assertTrue((self.dir / file).is_file(), file)
        self.assertTrue((self.dir / self.manifest["mesh"]["file"]).is_file())
        self.assertEqual(sorted(p.name for p in self.out.files), sorted(p.name for p in self.dir.iterdir()))
        manifest_io.validate_manifest(self.manifest)

    def test_every_part_has_geometry_and_the_base_stays_below_the_turntable(self) -> None:
        for part, mesh in self.parts.items():
            self.assertGreater(mesh.face_count, 100, part)
        self.assertAlmostEqual(float(self.parts["base"].bounds()[1][1]), SPEC.pedestal_m, places=3)
        self.assertGreaterEqual(float(self.parts["yaw"].bounds()[0][1]), SPEC.pedestal_m - 1e-6)

    def test_sizes_are_the_maintainers(self) -> None:
        lo, hi = Mesh.concatenate(self.parts.values()).bounds()
        _within(self, float(hi[1] - lo[1]), TALL_M, "height")
        _within(self, float(hi[0] - lo[0]), WIDE_M, "width")
        _within(self, float(self.parts["base"].bounds()[1][1]), PEDESTAL_M, "pedestal")
        blo, bhi = self.named["barrels"].bounds()
        _within(self, float(bhi[2] - blo[2]), BARREL_M, "barrel length")
        self.assertEqual(self.manifest["dimensions_m"]["height"], round(float(hi[1] - lo[1]), 3))

    def test_four_muzzles_sit_at_the_barrels_ends(self) -> None:
        entry = self.manifest["turret"]
        trunnion = np.array(entry["trunnion"])
        self.assertEqual(len(entry["pitch_muzzles"]), 4)
        barrels = self.named["barrels"].vertices - [0.0, SPEC.trunnion_y, 0.0]  # the pitch frame
        self.assertAlmostEqual(float(barrels[:, 2].min()), SPEC.muzzle_z, places=4)
        for local, mount in zip(entry["pitch_muzzles"], entry["muzzles"], strict=True):
            np.testing.assert_allclose(np.array(local) + trunnion, mount, atol=1e-4)
            # The barrel's front face: its vertices on the muzzle plane round this muzzle, centred on it.
            near = barrels[(np.abs(barrels[:, 2] - local[2]) < 1e-4)
                           & (np.hypot(barrels[:, 0] - local[0], barrels[:, 1] - local[1]) < SPEC.barrel_radius + 0.05)]
            self.assertGreater(len(near), 8, local)
            np.testing.assert_allclose(near[:, :2].mean(axis=0), local[:2], atol=1e-3)
        corners = {(np.sign(x), np.sign(y)) for x, y, _ in entry["pitch_muzzles"]}
        self.assertEqual(len(corners), 4, "a muzzle in each corner of the rectangle")

    def test_the_battery_is_mirror_symmetric(self) -> None:
        for part, mesh in self.parts.items():
            v = np.round(mesh.vertices, 4)
            self.assertEqual({tuple(p) for p in v}, {tuple(p) for p in v * [-1.0, 1.0, 1.0]}, part)
        muzzles = {tuple(m) for m in self.manifest["turret"]["pitch_muzzles"]}
        self.assertEqual(muzzles, {(-x + 0.0, y, z) for x, y, z in muzzles})

    def test_the_barrels_swing_clear_of_the_bracket_at_any_elevation(self) -> None:
        # What lifts lies outside the cradle plates' inner faces, but for the axle turning in place; what does not lift and lies
        # within the barrels' swing stays inside them.
        lifted = self.parts["pitch"].vertices - [0.0, SPEC.trunnion_y, 0.0]
        off_axis = np.hypot(lifted[:, 1], lifted[:, 2])
        on_axle = off_axis <= 0.8 + 1e-6  # the axle and its hubs
        self.assertTrue(np.all(np.abs(lifted[~on_axle, 0]) >= SPEC.cradle_x - 1e-6))
        swing = float(off_axis.max())
        fixed = np.concatenate([self.parts["yaw"].vertices, self.parts["base"].vertices])
        within = fixed[np.hypot(fixed[:, 1] - SPEC.trunnion_y, fixed[:, 2]) <= swing]
        self.assertGreater(len(within), 100)
        self.assertTrue(np.all(np.abs(within[:, 0]) < SPEC.cradle_x - 0.05))


if __name__ == "__main__":
    unittest.main()
