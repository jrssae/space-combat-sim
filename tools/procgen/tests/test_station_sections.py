"""M7-T19: the station's sections, their skirts, the near-only props and the collision shapes by section."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import babylon5_station as station
from tools.procgen.core import collision as col
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Material, Mesh, box
from tools.procgen.core.glb import read_glb
from tools.procgen.core.image import read_png
from tools.procgen.core.sections import SectionCorners, cut_corners, cuts_from_planes, skirts
from tools.procgen.parts import station as st
from tools.procgen.parts import station_props as sp

SMALL = (1024, 1024, 64)


def _corners(mesh: Mesh) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    return (mesh.vertices[mesh.faces], mesh.vertex_normals()[mesh.faces], mesh.face_uv / 10.0,
            np.zeros(mesh.face_count, dtype=bool))


def _area(p: np.ndarray) -> float:
    return float(0.5 * np.linalg.norm(np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0]), axis=1).sum())


class CutTests(unittest.TestCase):
    """The cut on a small mesh."""

    def setUp(self) -> None:
        self.mesh = box((4.0, 3.0, 10.0), Material("m", (0.5, 0.5, 0.5)))
        self.cuts = cuts_from_planes(("a", "b", "c"), (-2.0, 1.5))

    def test_the_sections_tile_the_mesh_exactly(self) -> None:
        p, n, u, g = _corners(self.mesh)
        parts = cut_corners(p, n, u, g, self.cuts)
        self.assertAlmostEqual(sum(_area(s.positions) for s in parts), _area(p), places=9)
        for cut, part in zip(self.cuts, parts, strict=True):
            z = part.positions[:, :, 2]
            self.assertGreaterEqual(float(z.min()), max(cut.z0, -5.0) - 1e-9, cut.name)
            self.assertLessEqual(float(z.max()), min(cut.z1, 5.0) + 1e-9, cut.name)

    def test_a_cut_puts_the_same_points_on_both_sides(self) -> None:
        p, n, u, g = _corners(self.mesh)
        a, b, _ = cut_corners(p, n, u, g, self.cuts)

        def on(part: SectionCorners) -> np.ndarray:
            pts = part.positions.reshape(-1, 3)
            return np.unique(np.round(pts[np.abs(pts[:, 2] + 2.0) < 1e-9], 9), axis=0)

        np.testing.assert_array_equal(on(a), on(b))

    def test_uvs_and_normals_are_interpolated_along_the_cut_edges(self) -> None:
        # One slanted triangle whose UV is its x and y over ten and whose normals vary: every clipped corner keeps both maps.
        p = np.array([[[0.0, 0.0, -5.0], [6.0, 1.0, 4.0], [1.0, 7.0, 0.5]]])
        n = np.array([[[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]])
        u = p[:, :, :2] / 10.0
        parts = cut_corners(p, n, u, np.zeros(1, dtype=bool), self.cuts)
        self.assertAlmostEqual(sum(_area(s.positions) for s in parts), _area(p), places=9)
        for part in parts:
            np.testing.assert_allclose(part.uvs, part.positions[:, :, :2] / 10.0, atol=1e-12)
            np.testing.assert_allclose(np.linalg.norm(part.normals, axis=2), 1.0, atol=1e-12)

    def test_skirts_hang_inward_in_the_cut_plane_and_face_out_of_their_section(self) -> None:
        p, n, u, g = _corners(self.mesh)
        a, b, _ = cut_corners(p, n, u, g, self.cuts)
        wall = skirts(a, [(-2.0, 1.0)], depth=0.5)
        self.assertGreater(len(wall.positions), 0)
        np.testing.assert_allclose(wall.positions[:, :, 2], -2.0, atol=1e-9)
        normals = np.cross(wall.positions[:, 1] - wall.positions[:, 0], wall.positions[:, 2] - wall.positions[:, 0])
        self.assertTrue(np.all(normals[:, 2] > 0.0), "the fore section's wall at its aft cut faces aft")
        inside = np.all((np.abs(wall.positions[:, :, 0]) <= 2.0 + 1e-9) & (np.abs(wall.positions[:, :, 1]) <= 1.5 + 1e-9))
        self.assertTrue(inside, "inside the hull")
        back = skirts(b, [(-2.0, -1.0)], depth=0.5)
        normals = np.cross(back.positions[:, 1] - back.positions[:, 0], back.positions[:, 2] - back.positions[:, 0])
        self.assertTrue(np.all(normals[:, 2] < 0.0), "the aft section's wall at its fore cut faces forward")

    def test_planes_must_ascend_and_names_be_one_more(self) -> None:
        with self.assertRaises(ValueError):
            cuts_from_planes(("a", "b"), (1.0, 0.0))
        with self.assertRaises(ValueError):
            cuts_from_planes(("a", "b", "c"), (2.0, 1.0))


class StationSectionTests(unittest.TestCase):
    """The station's sections, props and collision in a small bake."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name)
        station.build_at(BuildContext(cls.dir, seed=42), *SMALL)
        cls.manifest = manifest_io.read_manifest(cls.dir)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def _glb(self, file: str) -> tuple[np.ndarray, np.ndarray]:
        """A glb's triangles as corners, and its corners' UVs."""
        mesh = read_glb(self.dir / file)
        tris, uvs = [], []
        for prim in mesh.primitives:
            if len(prim.indices):
                tris.append(prim.positions[np.asarray(prim.indices).reshape(-1, 3)])
                uvs.append(prim.uv[np.asarray(prim.indices).reshape(-1, 3)])
        return np.concatenate(tris), np.concatenate(uvs)

    def test_each_piece_is_cut_into_ten_to_twenty_sections_along_the_planned_lines(self) -> None:
        for piece, names in (("drum", station.DRUM_SECTIONS), ("frame", station.FRAME_SECTIONS)):
            sections = self.manifest["pieces"][piece]["mesh"]["sections"]
            self.assertEqual([s["name"] for s in sections], list(names), piece)
            self.assertTrue(10 <= len(sections) <= 20, piece)
            self.assertIsNone(sections[0]["z0"])
            self.assertIsNone(sections[-1]["z1"])
            for a, b in zip(sections[:-1], sections[1:], strict=True):
                self.assertEqual(a["z1"], b["z0"], f"{a['name']} meets {b['name']}")

    def test_the_sections_cover_the_piece_without_gaps_or_overlaps(self) -> None:
        for piece in ("drum", "frame"):
            entry = self.manifest["pieces"][piece]["mesh"]
            whole, _ = self._glb(entry["file"])
            total, lo, hi = 0.0, np.full(3, np.inf), np.full(3, -np.inf)
            for s in entry["sections"]:
                tris, _ = self._glb(s["file"])
                hull = tris[: s["triangles"]]  # the hull's triangles come first, then its skirt's
                self.assertEqual(len(tris), s["triangles"] + s["skirt_triangles"])
                origin = np.asarray(s["origin"])
                pts = hull.reshape(-1, 3) + origin
                z0 = -np.inf if s["z0"] is None else s["z0"]
                z1 = np.inf if s["z1"] is None else s["z1"]
                self.assertGreaterEqual(float(pts[:, 2].min()), z0 - 1e-3, s["name"])
                self.assertLessEqual(float(pts[:, 2].max()), z1 + 1e-3, s["name"])
                np.testing.assert_allclose(pts.min(axis=0), np.asarray(s["aabb_min"]) + origin, atol=1e-2)
                total += _area(hull)
                lo, hi = np.minimum(lo, pts.min(axis=0)), np.maximum(hi, pts.max(axis=0))
            self.assertAlmostEqual(total / _area(whole), 1.0, delta=1e-5, msg=piece)
            np.testing.assert_allclose(lo, whole.reshape(-1, 3).min(axis=0), atol=1e-2)
            np.testing.assert_allclose(hi, whole.reshape(-1, 3).max(axis=0), atol=1e-2)

    def test_neighbours_meet_on_the_same_points_and_uvs(self) -> None:
        # Where the cut split a triangle, the point it made is on both sides with the same UV; any other point on the plane is a
        # corner the whole piece already had (two shapes that merely meet there).
        def near(points: np.ndarray, others: np.ndarray) -> np.ndarray:
            if len(others) == 0:
                return np.zeros(len(points), dtype=bool)
            d = np.abs(points[:, None, :] - others[None, :, :])
            return np.any(np.all(d[:, :, :3] < 2e-3, axis=2) & np.all(d[:, :, 3:] < 1e-5, axis=2), axis=1)

        for piece in ("drum", "frame"):
            entry = self.manifest["pieces"][piece]["mesh"]
            whole, whole_uv = self._glb(entry["file"])
            whole_keys = np.concatenate([whole.reshape(-1, 3), whole_uv.reshape(-1, 2)], axis=1)
            sections = entry["sections"]
            for a, b in zip(sections[:-1], sections[1:], strict=True):
                c = a["z1"]
                sides = []
                for s in (a, b):
                    tris, uvs = self._glb(s["file"])
                    n = s["triangles"]
                    keys = np.concatenate([tris[:n].reshape(-1, 3) + np.asarray(s["origin"]), uvs[:n].reshape(-1, 2)], axis=1)
                    sides.append(np.unique(keys[np.abs(keys[:, 2] - c) < 1e-3], axis=0))
                known = whole_keys[np.abs(whole_keys[:, 2] - c) < 1e-3]
                for mine, other in ((sides[0], sides[1]), (sides[1], sides[0])):
                    made = mine[~near(mine, known)]
                    lost = made[~near(made, other)]
                    self.assertEqual(len(lost), 0, f"{a['name']} | {b['name']}: {lost[:3]}")

    def test_the_props_are_near_only_with_their_own_atlas_and_sit_on_the_doors(self) -> None:
        props = self.manifest["pieces"]["drum"]["props"]
        self.assertTrue(1000.0 <= props["near_m"] <= 2000.0)
        self.assertGreater(props["margin_m"], 0.0)
        leaves = {f"door_leaf_{n}_{s}" for n in range(1, 7) for s in "rl"}
        self.assertEqual(set(props["kinds"]), leaves | {"clamp", "gantry"})
        for kind in leaves:  # the leaves are the doors: drawn as far as the hull
            self.assertGreater(props["kinds"][kind]["near_m"], 10_000.0)
        self.assertNotIn("near_m", props["kinds"]["clamp"])
        for key in ("albedo", "normal", "orm", "emissive"):
            image = read_png(self.dir / props["surface"][key])
            self.assertEqual(image.shape[:2], (sp.ATLAS_H, sp.ATLAS_W), key)
            self.assertTrue((self.dir / (props["surface"][key] + ".import")).is_file())
        self.assertLess(1.0 / sp.PX_PER_M, 0.05, "a door's face is finer than 5 cm a texel")
        waist = next(s for s in self.manifest["pieces"]["drum"]["mesh"]["sections"] if s["name"] == "waist")
        origin = np.asarray(station.DRUM_CENTRE) + np.asarray(waist["origin"])
        floor = st.ARM_HATCH[4] - st.DOOR_DEPTH
        for n in range(1, 7):
            group = next(g for g in props["groups"] if g["kind"] == f"door_leaf_{n}_r")
            self.assertEqual(group["section"], "waist")
            self.assertEqual(len(group["transforms"]), 4)
            for flat in group["transforms"]:
                at = np.asarray(flat[9:12]) + origin
                self.assertAlmostEqual(float(np.hypot(at[0], at[1])), float(np.hypot(st.LAUNCH_STRIP_X, floor)), delta=1e-3)
                self.assertAlmostEqual(float(at[2]), st.launch_door_centres()[n - 1], delta=1e-3)
        clamps = next(g for g in props["groups"] if g["kind"] == "clamp")
        self.assertEqual(len(clamps["transforms"]), 24)
        for kind in props["kinds"]:
            mesh = read_glb(self.dir / props["kinds"][kind]["file"])
            uv = np.concatenate([p.uv for p in mesh.primitives])
            self.assertTrue(np.all((uv >= 0.0) & (uv <= 1.0)), kind)
        frame = self.manifest["pieces"]["frame"]["props"]
        self.assertEqual(set(frame["kinds"]), {"window_panel"})
        self.assertEqual(next(g for g in frame["groups"] if g["kind"] == "window_panel")["section"], "spine_sphere")

    def test_the_door_faces_carry_their_numbers_crisp(self) -> None:
        albedo = read_png(self.dir / self.manifest["pieces"]["drum"]["props"]["surface"]["albedo"]).astype(float)
        row, col = int(st.LAUNCH_DOOR_HALF[1] * sp.PX_PER_M), int(st.LAUNCH_DOOR_HALF[0] * sp.PX_PER_M)  # the door's middle in its cell
        for k in range(st.LAUNCH_DOORS):
            cell = albedo[k * sp.CELL_H: k * sp.CELL_H + sp.CELL_H, :, :3].mean(axis=2)
            middle = cell[row - 70: row + 70, col - 70: col + 70]
            self.assertGreater(float((middle > 90).mean()), 0.05, f"door {k + 1}'s number is pale paint")
            # A sharp edge: the stroke goes from door to paint within a few texels.
            self.assertGreater(float(np.abs(np.diff(middle, axis=1)).max()), 40.0)

    def test_collision_shapes_follow_the_sections(self) -> None:
        section = self.manifest["collision"]
        manifest_io.validate_collision_section(section)
        for entry in section["pieces"]:
            piece = entry["name"]
            sections = {s["name"]: s for s in self.manifest["pieces"][piece]["mesh"]["sections"]}
            spans = entry["sections"]
            self.assertEqual(list(spans), list(sections))
            self.assertLessEqual(len(entry["shapes"]), section["max_shapes"])
            shapes = col.shapes_from_entry(entry)
            for name, (first, count) in spans.items():
                self.assertGreater(count, 0, name)
                for shape in shapes[first: first + count]:
                    self.assertTrue(shape.name.startswith(name + "/"), shape.name)
                    lo, hi = shape.bounds()
                    z0 = -np.inf if sections[name]["z0"] is None else sections[name]["z0"]
                    z1 = np.inf if sections[name]["z1"] is None else sections[name]["z1"]
                    self.assertGreaterEqual(lo[2], z0 - 0.5, shape.name)
                    self.assertLessEqual(hi[2], z1 + 0.5, shape.name)

    def test_collision_covers_the_hull_within_tolerance(self) -> None:
        # The hull is a surface over solid shapes, so the excess is read only on the shapes' outer faces: a frustum's cap inside
        # the drum, shared with its neighbour, is no excess.
        for entry in self.manifest["collision"]["pieces"]:
            tris, _ = self._glb(self.manifest["pieces"][entry["name"]]["mesh"]["file"])
            shapes = col.shapes_from_entry(entry)
            probes = col.surface_probes(tris, STEP_M)
            gap = col._gaps(probes, shapes, 2.0 * STEP_M)
            self.assertLessEqual(float(gap.max()), GAP_M, f"{entry['name']}: render surface at {probes[int(np.argmax(gap))]}")
            for k, shape in enumerate(shapes):
                own = shape.probes()
                inner = np.min([o.distance(own) for j, o in enumerate(shapes) if j != k], axis=0) < 0.5
                if np.all(inner):
                    continue
                off = col._nearest(own[~inner], probes, 2.0 * STEP_M)
                self.assertLessEqual(float(off.max()), EXCESS_M, shape.name)

    def test_the_apertures_ring_stays_open(self) -> None:
        frame = next(e for e in self.manifest["collision"]["pieces"] if e["name"] == "frame")
        shapes = col.shapes_from_entry(frame)
        axis = np.array([[0.0, 0.0, z - station.ORIGIN[2]] for z in np.linspace(st.RING_FRAME[0], st.RING_FRAME[1], 7)])
        for shape in shapes:
            self.assertTrue(np.all(shape.distance(axis) > 50.0), f"{shape.name} closes the aperture's ring")


# The station's first collision pass (T05 refines the bays and the aperture): a 16-sided ring round each round body, small parts
# (ribs, rails' clamps, stringers, the doors' wells) within the gap, the vanes' root and tip notch and the waist's teeth filled.
STEP_M = 10.0
GAP_M = 14.0  # the reactor's ring of pipes on its aft face is the widest (12.8 m)
EXCESS_M = 60.0

if __name__ == "__main__":
    unittest.main()
