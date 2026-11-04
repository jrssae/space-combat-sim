"""The painted mesh (M4-T27): the glb writer, the paint codes in the UVs, and the fighters' meshes against their splats and OBJs."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import raider_fighter as raider
from tools.procgen.assets import starfury_aurora as starfury
from tools.procgen.core import frames
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Material, box, lathe
from tools.procgen.core.glb import GlbPrimitive, glb_bytes, read_glb, write_glb
from tools.procgen.core.obj import read_obj
from tools.procgen.core.paint_mesh import PHASE_STEPS, PaintPart, build_paint_mesh, phase_of, phase_steps
from tools.procgen.core.ply import read_ply
from tools.procgen.styles.earthforce import EARTHFORCE
from tools.procgen.styles.raider import RAIDER

GREY = Material("grey", (0.5, 0.5, 0.5), paneled=True)
RED = Material("red", (0.5, 0.05, 0.02), paneled=True)
GLASS = Material("glass", (0.01, 0.02, 0.01), transmittance=0.7)


def decode(uv: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """(phase steps (n, 3), material index (n,)) from the UV codes."""
    u, v = np.rint(uv[:, 0]).astype(int), np.rint(uv[:, 1]).astype(int)
    return np.stack([u % PHASE_STEPS, u // PHASE_STEPS, v % PHASE_STEPS], axis=1), v // PHASE_STEPS


class GlbTests(unittest.TestCase):
    def test_round_trip_and_determinism(self) -> None:
        tri = GlbPrimitive([[0, 0, 0], [1, 0, 0], [0, 1, 0]], [[0, 0, 1]] * 3, [[1, 2], [3, 4], [5, 6]], [0, 1, 2], "paint")
        with tempfile.TemporaryDirectory() as tmp:
            path = write_glb(Path(tmp) / "a.glb", [tri], "thing")
            mesh = read_glb(path)
        self.assertEqual(len(mesh.primitives), 1)
        p = mesh.primitives[0]
        np.testing.assert_array_equal(p.positions, tri.positions)
        np.testing.assert_array_equal(p.uv, tri.uv)
        np.testing.assert_array_equal(p.indices, tri.indices)
        self.assertEqual(p.material, "paint")
        self.assertEqual(glb_bytes([tri], "thing"), glb_bytes([tri], "thing"))
        self.assertEqual(len(glb_bytes([tri], "thing")) % 4, 0)

    def test_empty_primitives_are_left_out_and_none_at_all_is_an_error(self) -> None:
        tri = GlbPrimitive([[0, 0, 0], [1, 0, 0], [0, 1, 0]], [[0, 0, 1]] * 3, [[0, 0]] * 3, [0, 1, 2], "paint")
        empty = GlbPrimitive(np.zeros((0, 3)), np.zeros((0, 3)), np.zeros((0, 2)), [], "glass", blend=True)
        with tempfile.TemporaryDirectory() as tmp:
            mesh = read_glb(write_glb(Path(tmp) / "a.glb", [tri, empty], "thing"))
        self.assertEqual([p.material for p in mesh.primitives], ["paint"])
        with self.assertRaises(ValueError):
            glb_bytes([empty], "thing")


class PaintMeshTests(unittest.TestCase):
    def test_phase_steps_give_the_assets_own_phase(self) -> None:
        for name in ("fuselage", "pod_ur", "strut_lr", "cockpit"):
            self.assertEqual(phase_of(phase_steps(name, True), EARTHFORCE), starfury._phase(name, EARTHFORCE))
        for name in ("wing_l", "hump", "nacelle_r"):
            self.assertEqual(phase_of(phase_steps(name, False), RAIDER), raider._phase(name, RAIDER))

    def test_a_vertex_shared_by_two_materials_is_split_and_codes_decode(self) -> None:
        banded = lathe([(0.0, 1.0), (1.0, 1.0), (2.0, 1.0)], 8, [GREY, RED])  # the middle ring is shared by both bands
        paint = build_paint_mesh([PaintPart(banded, (3, 5, 7))])
        self.assertEqual(paint.triangles, banded.face_count)
        steps, mat = decode(paint.opaque.uv)
        np.testing.assert_array_equal(steps, np.tile([3, 5, 7], (len(steps), 1)))
        self.assertEqual(len(paint.opaque.positions), 8 * 4, "the shared ring once per band")
        names = [paint.materials[k].name for k in mat]
        self.assertEqual(sorted(set(names)), ["grey", "red"])
        # Every triangle's three vertices carry one material.
        tri_mats = mat[paint.opaque.indices.reshape(-1, 3)]
        self.assertTrue(np.all(tri_mats == tri_mats[:, :1]))

    def test_glass_faces_go_to_their_own_primitive(self) -> None:
        hull = box((1.0, 1.0, 1.0), GREY)
        pane = box((0.5, 0.5, 0.1), GLASS, center=(0.0, 0.8, 0.0))
        paint = build_paint_mesh([PaintPart(hull, (0, 0, 0)), PaintPart(pane, (1, 2, 3))])
        self.assertEqual(len(paint.opaque.indices) // 3, 12)
        self.assertEqual(len(paint.glass.indices) // 3, 12)
        _, mat = decode(paint.glass.uv)
        self.assertTrue(all(paint.materials[k].transmittance > 0.0 for k in mat))


class FighterPaintMeshTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.raider_dir = root / "raider"
        cls.fury_dir = root / "fury"
        raider.build(BuildContext(cls.raider_dir, seed=42))
        starfury.build(BuildContext(cls.fury_dir, seed=42, options={"hero": False}))
        raider.build(BuildContext(root / "raider_b", seed=42))
        cls.raider_b = root / "raider_b"

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def _check(self, out_dir: Path, asset_id: str, obj_name: str, ply_name: str) -> None:
        manifest = manifest_io.read_manifest(out_dir)
        entry = manifest["paint_mesh"]
        self.assertEqual(manifest["files"]["paint_mesh"], f"{asset_id}_mesh.glb")
        self.assertEqual(entry["file"], manifest["files"]["paint_mesh"])
        mesh = read_glb(out_dir / entry["file"])
        obj = read_obj(out_dir / obj_name)
        tris = sum(len(p.indices) for p in mesh.primitives) // 3
        self.assertEqual(tris, len(obj.faces), "the triangle budget is the fallback surface's")
        self.assertEqual(entry["triangles"], tris)
        positions = np.concatenate([p.positions for p in mesh.primitives])
        splat_xyz = frames.flip_xy(read_ply(out_dir / ply_name).to_splats().xyz)
        lo, hi = splat_xyz.min(axis=0), splat_xyz.max(axis=0)
        size = hi - lo
        # Every splat lies on the mesh, so the mesh's box holds the splats' and is at most a little larger (buried faces).
        self.assertTrue(np.all(positions.min(axis=0) <= lo + 1e-3), (positions.min(axis=0), lo))
        self.assertTrue(np.all(positions.max(axis=0) >= hi - 1e-3), (positions.max(axis=0), hi))
        np.testing.assert_allclose(positions.min(axis=0), lo, atol=0.02 * float(size.max()))
        np.testing.assert_allclose(positions.max(axis=0), hi, atol=0.02 * float(size.max()))
        # The table carries every material the shader indexes, in linear albedo.
        for p in mesh.primitives:
            _, mat = decode(p.uv)
            self.assertLess(int(mat.max()), len(entry["materials"]))
        self.assertGreater(entry["panel"]["size_m"], 0.0)

    def test_the_raider_mesh_matches_its_splats_and_obj(self) -> None:
        self._check(self.raider_dir, raider.ASSET_ID, raider.OBJ_NAME, raider.PLY_NAME)

    def test_the_starfury_mesh_matches_its_splats_and_obj_with_the_glass_apart(self) -> None:
        self._check(self.fury_dir, starfury.ASSET_ID, starfury.OBJ_NAME, starfury.PLY_NAME)
        manifest = manifest_io.read_manifest(self.fury_dir)
        obj = read_obj(self.fury_dir / starfury.OBJ_NAME)
        glass_faces = sum(1 for m in obj.face_materials if m == "ef_canopy_glass")
        self.assertGreater(glass_faces, 0)
        self.assertEqual(manifest["paint_mesh"]["glass_triangles"], glass_faces)

    def test_the_mesh_is_deterministic(self) -> None:
        name = f"{raider.ASSET_ID}_mesh.glb"
        self.assertEqual((self.raider_dir / name).read_bytes(), (self.raider_b / name).read_bytes())


if __name__ == "__main__":
    unittest.main()
