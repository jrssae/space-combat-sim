"""``asteroids`` (M5-T29, D63): twelve kinds of closed, outward rock, budgets, collision spheres that hug the rock, determinism."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import asteroids as rocks
from tools.procgen.core.context import BuildContext


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class IcosphereTests(unittest.TestCase):
    def test_each_level_quadruples_the_faces_and_stays_on_the_unit_sphere(self) -> None:
        for level in range(4):
            v, f = rocks.icosphere(level)
            self.assertEqual(len(f), 20 * 4**level)
            self.assertEqual(len(v), 10 * 4**level + 2)
            np.testing.assert_allclose(np.linalg.norm(v, axis=1), 1.0, atol=1e-12)


def _mesh(index: int, finish: bool = True):
    spec = rocks.spec_for(index, 42)
    return spec, rocks.rock_mesh(3, spec, 42, index, rocks.rock_materials(spec), finish=finish)


def _volume(mesh) -> float:
    v, f = mesh.vertices, mesh.faces
    return float(np.einsum("ij,ij->i", v[f[:, 0]], np.cross(v[f[:, 1]], v[f[:, 2]])).sum() / 6.0)


class RockMeshTests(unittest.TestCase):
    def test_the_shapes_cover_every_kind(self) -> None:
        kinds = {rocks.spec_for(k, 42).kind for k in range(rocks.SHAPE_COUNT)}
        self.assertEqual(kinds, set(rocks.KINDS))
        self.assertGreaterEqual(len(rocks.KINDS), 10)

    def test_every_shape_is_closed_and_faces_outward(self) -> None:
        for index in range(rocks.SHAPE_COUNT):
            spec, plain = _mesh(index, finish=False)
            f = plain.faces
            edges = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), axis=1)
            _, counts = np.unique(edges, axis=0, return_counts=True)
            self.assertTrue(np.all(counts == 2), f"{spec.kind}: every edge shared by two faces")
            outward = np.einsum("ij,ij->i", plain.face_normals(), plain.face_centroids())
            self.assertTrue(np.all(outward > 0.0), f"{spec.kind}: every face seen from the centre faces out")
            _, finished = _mesh(index)
            self.assertGreater(_volume(finished), 0.0, f"{spec.kind}: still outward after the bend or taper")

    def test_the_rocks_are_rough_and_about_the_author_radius(self) -> None:
        for index in range(rocks.SHAPE_COUNT):
            spec, mesh = _mesh(index)
            r = np.linalg.norm(mesh.vertices, axis=1)
            self.assertGreater(r.std() / r.mean(), 0.04, f"{spec.kind}: not a smooth ball")
            self.assertLess(r.max(), 1.6 * rocks.AUTHOR_RADIUS_M, spec.kind)

    def test_fragments_carry_fresh_fracture_faces_and_cratered_rocks_dark_floors(self) -> None:
        for index in range(len(rocks.KINDS)):
            spec = rocks.spec_for(index, 42)
            # The render level: a pitted rock's small craters span too few faces of the coarser test mesh.
            mesh = rocks.rock_mesh(4, spec, 42, index, rocks.rock_materials(spec))
            used = set(np.unique(mesh.face_material).tolist())
            if spec.kind in ("fragment", "boulder", "shard", "half"):
                self.assertIn(1, used, f"{spec.kind}: lighter fracture faces")
            if spec.kind in ("cratered", "pitted"):
                self.assertIn(2, used, f"{spec.kind}: crater floors")

    def test_a_peanut_has_a_waist(self) -> None:
        index = rocks.KINDS.index("peanut")
        _, mesh = _mesh(index)
        x = mesh.vertices[:, 0]
        span = np.ptp(x)
        middle = np.abs(x - np.median(x)) < 0.06 * span
        lobe = np.abs(x - (x.min() + 0.25 * span)) < 0.06 * span
        width = lambda sel: float(np.ptp(mesh.vertices[sel, 1]))  # noqa: E731
        self.assertLess(width(middle), 0.95 * width(lobe), "the neck is narrower than a lobe")

    def test_a_shard_is_long_and_thin(self) -> None:
        _, mesh = _mesh(rocks.KINDS.index("shard"))
        extent = np.sort(np.ptp(mesh.vertices, axis=0))
        self.assertGreater(extent[2] / extent[1], 2.5)

    def test_long_rocks_collide_as_several_spheres_round_ones_as_one(self) -> None:
        for kind, expect in (("cratered", 1), ("peanut", 2), ("shard", 2)):
            _, mesh = _mesh(rocks.KINDS.index(kind))
            count = len(rocks.collision_spheres(mesh.vertices))
            if expect == 1:
                self.assertEqual(count, 1, kind)
            else:
                self.assertGreaterEqual(count, expect, kind)

    def test_shapes_differ(self) -> None:
        specs = [rocks.spec_for(k, 42) for k in range(rocks.SHAPE_COUNT)]
        self.assertEqual(len({s.colour for s in specs}), rocks.SHAPE_COUNT)


class AsteroidsBuildTests(unittest.TestCase):
    """Builds two shapes twice with the same seed once for the class (about half a minute)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = rocks.build(BuildContext(cls.dir_a, seed=42, options={"shapes": 2}))
        cls.out_b = rocks.build(BuildContext(cls.dir_b, seed=42, options={"shapes": 2}))

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_it_is_registered(self) -> None:
        self.assertIs(ASSETS["asteroids"], rocks.build)

    def test_the_same_seed_writes_the_same_files(self) -> None:
        names = sorted(p.name for p in self.dir_a.iterdir())
        self.assertEqual(names, sorted(p.name for p in self.dir_b.iterdir()))
        for name in names:
            self.assertEqual(sha256(self.dir_a / name), sha256(self.dir_b / name), name)

    def test_every_shape_has_its_mesh_and_maps(self) -> None:
        for shape in self.out_a.manifest["shapes"]:
            for name in [shape["mesh"]["file"]] + [shape["mesh"]["surfaces"][0][k] for k in ("albedo", "normal", "orm", "emissive")]:
                self.assertTrue((self.dir_a / name).is_file(), name)

    def test_render_budget(self) -> None:
        for shape in self.out_a.manifest["shapes"]:
            self.assertEqual(shape["mesh"]["triangles"], 20 * 4**rocks.RENDER_LEVEL)
        self.assertEqual(self.out_a.triangle_count, 2 * 20 * 4**rocks.RENDER_LEVEL, "the build line counts every shape")

    def test_radii_and_spheres_match_the_mesh(self) -> None:
        for shape in self.out_a.manifest["shapes"]:
            lo, hi = np.array(shape["aabb_min"]), np.array(shape["aabb_max"])
            corner = np.max(np.abs(np.stack([lo, hi])), axis=0)
            self.assertLessEqual(shape["bounding_radius_m"], float(np.linalg.norm(corner)) + 1e-3)
            self.assertGreaterEqual(shape["bounding_radius_m"], float(np.abs(np.stack([lo, hi])).max()) - 1e-3)
            self.assertIn(shape["kind"], rocks.KINDS)
            self.assertGreaterEqual(len(shape["spheres"]), 1)
            for sphere in shape["spheres"]:
                centre = np.array(sphere["centre"])
                self.assertTrue(np.all(centre >= lo - 1e-3) and np.all(centre <= hi + 1e-3), "inside the rock's box")
                self.assertLessEqual(float(np.linalg.norm(centre)) + sphere["radius_m"], shape["bounding_radius_m"] * 1.15,
                                     "no sphere reaches far past the rock")

    def test_shapes_json_matches_the_manifest(self) -> None:
        doc = json.loads((self.dir_a / "shapes.json").read_text(encoding="utf-8"))
        self.assertEqual(doc["shapes"], self.out_a.manifest["shapes"])
        self.assertEqual(doc["author_radius_m"], rocks.AUTHOR_RADIUS_M)


if __name__ == "__main__":
    unittest.main()
