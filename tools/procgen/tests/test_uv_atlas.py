"""``core/uv_atlas.py`` (M4-T30a): charts from the primitives' UVs and the unwrapper, the shelf packer, texel density."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.core import geometry as g
from tools.procgen.core.raster import rasterize
from tools.procgen.core.uv_atlas import auto_charts, charts_of, pack, uv_area

GREY = g.Material("grey", (0.5, 0.5, 0.5), paneled=True)
DARK = g.Material("dark", (0.1, 0.1, 0.1))


def _cylinder() -> g.Mesh:
    return g.lathe([(0.0, 0.5), (2.0, 0.5)], 16, GREY)


class ChartTests(unittest.TestCase):
    def test_a_lathe_is_one_chart_with_the_arc_as_u_and_the_profile_as_v(self) -> None:
        mesh = _cylinder()
        self.assertEqual(mesh.chart_count, 1)
        uv = mesh.face_uv
        self.assertAlmostEqual(float(uv[..., 0].max()), 2.0 * np.pi * 0.5, places=6)
        self.assertAlmostEqual(float(uv[..., 1].max()), 2.0, places=6)
        self.assertTrue(np.all(uv_area(uv) > 1e-9), "every triangle has UV area")
        # Texel density is the surface's own: UV area is the 3D area, up to the chords of a 16-gon.
        self.assertAlmostEqual(float(uv_area(uv).sum()) / mesh.area(), 1.0, delta=0.01)

    def test_a_box_has_six_planar_charts_of_its_faces_sizes(self) -> None:
        mesh = g.box((1.0, 2.0, 3.0), GREY)
        self.assertEqual(mesh.chart_count, 6)
        charts = charts_of(mesh)
        self.assertEqual(len(charts), 6)
        sizes = sorted(tuple(np.round(sorted(c.size_m), 6)) for c in charts)
        self.assertEqual(sizes, sorted([(1.0, 2.0), (1.0, 2.0), (1.0, 3.0), (1.0, 3.0), (2.0, 3.0), (2.0, 3.0)]))

    def test_mirroring_keeps_the_corner_uvs_with_their_corners(self) -> None:
        mesh = g.lathe([(0.0, 0.0), (1.0, 0.6), (2.0, 0.0)], 12, GREY).translated((1.0, 0.0, 0.0))
        mirrored = mesh.mirrored("x")
        # The winding flipped, and so did the corner order of the UVs: the UV area is the same size with the opposite sign.
        np.testing.assert_allclose(uv_area(mirrored.face_uv), -uv_area(mesh.face_uv), atol=1e-12)
        both = g.Mesh.concatenate([mesh, mirrored])
        self.assertEqual(both.chart_count, 2, "a mirrored part gets charts of its own")
        self.assertEqual(len(charts_of(both)), 2)

    def test_faces_without_charts_are_unwrapped_by_normal_regions(self) -> None:
        # A hand-built open box (no UVs): six planar regions, one chart each.
        box = g.box((1.0, 1.0, 1.0), GREY)
        raw = g.Mesh(box.vertices, box.faces, box.face_material, box.materials)
        self.assertEqual(raw.chart_count, 0)
        charts = auto_charts(raw, np.ones(raw.face_count, dtype=bool))
        self.assertEqual(len(charts), 6)
        for chart in charts:
            self.assertEqual(len(chart.faces), 2)
            np.testing.assert_allclose(sorted(chart.size_m), [1.0, 1.0], atol=1e-9)
            self.assertAlmostEqual(float(np.abs(uv_area(chart.uv_m)).sum()), 1.0, places=9)

    def test_a_smooth_cylinder_without_uvs_splits_into_strips_not_one_fold(self) -> None:
        cyl = _cylinder()
        raw = g.Mesh(cyl.vertices, cyl.faces, cyl.face_material, cyl.materials)
        charts = auto_charts(raw, np.ones(raw.face_count, dtype=bool), angle_deg=40.0)
        self.assertGreaterEqual(len(charts), 4)
        for chart in charts:
            areas = uv_area(chart.uv_m)
            self.assertTrue(np.all(areas > 0.0) or np.all(areas < 0.0), "a chart never folds over itself")


class PackTests(unittest.TestCase):
    def test_packing_places_every_chart_inside_the_atlas_without_overlap(self) -> None:
        parts = [g.lathe([(0.0, 0.3), (1.5, 0.3)], 12, GREY), g.box((0.4, 0.4, 0.4), DARK).translated((2.0, 0.0, 0.0)),
                 g.lathe([(0.0, 0.0), (0.5, 0.2), (1.0, 0.0)], 10, GREY).translated((0.0, 2.0, 0.0))]
        mesh = g.Mesh.concatenate(parts)
        charts = charts_of(mesh)
        packed = pack(charts, texel_m=0.01, atlas_px=512, gutter_px=2)
        self.assertGreater(packed.fill, 0.2)
        self.assertGreaterEqual(packed.texel_m, 0.01)
        uv = packed.face_uv01(mesh.face_count)
        self.assertTrue(np.all(uv >= 0.0) and np.all(uv <= 1.0))
        self.assertTrue(np.all(np.abs(uv_area(uv)) > 1e-12))
        # Rasterised occupancy: no texel belongs to two charts.
        corners = mesh.vertices[mesh.faces]
        buffers = rasterize(512, uv, corners, mesh.vertex_normals()[mesh.faces], np.zeros(mesh.face_count, dtype=np.int64),
                            mesh.face_material, packed.face_chart(mesh.face_count), np.zeros((mesh.face_count, 3), dtype=bool))
        self.assertEqual(int(buffers.overlaps), 0)
        self.assertTrue(buffers.mask.any())

    def test_texel_density_is_the_same_on_every_part_within_twenty_percent(self) -> None:
        parts = [g.lathe([(0.0, 0.3), (1.5, 0.3)], 12, GREY), g.box((0.4, 0.4, 0.4), DARK).translated((2.0, 0.0, 0.0))]
        mesh = g.Mesh.concatenate(parts)
        packed = pack(charts_of(mesh), texel_m=0.005, atlas_px=1024)
        uv = packed.face_uv01(mesh.face_count) * 1024.0
        px_area = np.abs(uv_area(uv))
        m_area = mesh.face_areas()
        densities = []
        for part_faces in (np.arange(parts[0].face_count), parts[0].face_count + np.arange(parts[1].face_count)):
            densities.append(float(np.sqrt(px_area[part_faces].sum() / m_area[part_faces].sum())))
        self.assertLess(abs(densities[0] - densities[1]) / max(densities), 0.2, densities)

    def test_the_texel_grows_until_everything_fits(self) -> None:
        mesh = g.box((4.0, 4.0, 4.0), GREY)  # 96 m^2 cannot fit 1 cm texels into 256 px
        packed = pack(charts_of(mesh), texel_m=0.01, atlas_px=256)
        self.assertGreater(packed.texel_m, 0.03)
        uv = packed.face_uv01(mesh.face_count)
        self.assertTrue(np.all(uv >= 0.0) and np.all(uv <= 1.0))


if __name__ == "__main__":
    unittest.main()
