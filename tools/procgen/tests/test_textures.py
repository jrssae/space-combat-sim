"""``core/raster.py`` and ``core/textures.py`` (M4-T30a): the atlas buffers, the maps baked from them, markings and the stroke font."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.core import geometry as g
from tools.procgen.core.raster import rasterize, sharp_edges
from tools.procgen.core.color import linear_to_srgb
from tools.procgen.core.textures import (
    Marking,
    bake_maps,
    decode_normal,
    glyph_strokes,
    plating_for,
    plating_lattice,
    srgb_to_linear8,
)
from tools.procgen.core.textured_mesh import TexturedPart, atlas_of
from tools.procgen.styles.earthforce import EARTHFORCE

GREY = EARTHFORCE.material("hull")
GLOW = EARTHFORCE.material("nozzle_throat")
GLASS = EARTHFORCE.material("canopy_glass")


def _panel_box(size: float = 3.0) -> g.Mesh:
    return g.box((size, size, size), GREY)


class RasterTests(unittest.TestCase):
    def test_sharp_edges_are_the_creases_and_open_edges(self) -> None:
        box = g.box((1.0, 1.0, 1.0), GREY)
        sharp = sharp_edges(box, angle_deg=35.0)
        self.assertEqual(sharp.shape, (12, 3))
        # Each face's quad diagonal is shared by two coplanar triangles: never sharp; the 12 box edges are.
        self.assertEqual(int(sharp.sum()), 24, "12 edges, each seen from two triangles")
        smooth = g.lathe([(0.0, 0.5), (1.0, 0.5)], 32, GREY)
        inner = sharp_edges(smooth, angle_deg=35.0)
        self.assertEqual(int(inner[:, :].sum()), 2 * 32, "only the two open rims are sharp on a smooth tube")

    def test_the_buffers_hold_world_positions_normals_and_ids_on_the_charts(self) -> None:
        mesh = _panel_box(1.0)
        parts = [TexturedPart(mesh, (0, 0, 0), name="box")]
        atlas = atlas_of(parts, atlas_px=128, texel_m=0.02)
        buffers = atlas.buffers
        covered = buffers.mask
        self.assertGreater(covered.mean(), 0.5, "six 1 m faces at 2 cm fill most of a 128 px atlas")
        self.assertEqual(int(buffers.overlaps), 0)
        pos = buffers.position[covered]
        self.assertTrue(np.all(np.abs(pos).max(axis=1) <= 0.5 + 1e-3), "every texel's position is on the box")
        normals = buffers.normal[covered]
        np.testing.assert_allclose(np.linalg.norm(normals, axis=1), 1.0, atol=1e-5)
        self.assertTrue(np.all(buffers.part[covered] == 0))
        self.assertTrue(np.all(buffers.material[covered] == 0))
        # Texels at the middle of a face are far from any sharp edge, texels at its rim are close.
        self.assertGreater(float(buffers.edge_distance[covered].max()), 0.4)
        self.assertLess(float(buffers.edge_distance[covered].min()), 0.03)

    def test_a_triangle_smaller_than_a_texel_still_marks_one(self) -> None:
        tiny = g.Mesh([[0, 0, 0], [0.001, 0, 0], [0, 0.001, 0]], [[0, 1, 2]], [0], (GREY,))
        uv = np.array([[[0.3, 0.3], [0.3004, 0.3], [0.3, 0.3004]]])
        buffers = rasterize(64, uv, tiny.vertices[tiny.faces], tiny.vertex_normals()[tiny.faces], np.zeros(1, dtype=np.int64),
                            tiny.face_material, np.zeros(1, dtype=np.int64), np.zeros((1, 3), dtype=bool))
        self.assertEqual(int(buffers.mask.sum()), 1)


class MapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        hull = _panel_box(3.0)
        glass = g.box((0.6, 0.6, 0.1), GLASS, center=(0.0, 1.55, 0.0))
        throat = g.lathe([(0.0, 0.3), (0.4, 0.2)], 12, GLOW).translated((0.0, 0.0, 1.7))
        cls.parts = [TexturedPart(hull, (0, 0, 0), name="hull"), TexturedPart(glass, (1, 2, 3), name="glass"),
                     TexturedPart(throat, (4, 5, 6), name="throat")]
        cls.atlas = atlas_of(cls.parts, atlas_px=512, texel_m=0.01)
        cls.maps = bake_maps(cls.atlas, EARTHFORCE, seed=42, occlusion=False)

    def test_maps_are_the_atlas_size_and_eight_bit(self) -> None:
        for name in ("albedo", "orm", "emissive"):
            self.assertEqual(self.maps[name].shape, (512, 512, 3), name)
            self.assertEqual(self.maps[name].dtype, np.uint8, name)
        # Q34: the normal map carries the fine detail (grooves, rivets) at twice the atlas's resolution.
        self.assertEqual(self.maps["normal"].shape, (1024, 1024, 3))

    def test_the_normal_map_is_unit_length_and_flat_at_a_panel_centre(self) -> None:
        normal = decode_normal(self.maps["normal"][::2, ::2])  # the normal map is twice the atlas: its even texels sit on the atlas's
        covered = self.atlas.buffers.mask
        np.testing.assert_allclose(np.linalg.norm(normal[covered], axis=1), 1.0, atol=0.02)
        # A texel in the middle of a panel, away from any line, hatch or edge: straight up.
        b = self.atlas.buffers
        lattice = plating_lattice(EARTHFORCE, b.position[covered], b.normal[covered], self.atlas.part_platings[0], self.atlas.part_phases[0])
        flat = (lattice["edge_m"] > 0.12) & (lattice["rivet_m"] > 0.03) & (b.edge_distance[covered] > 0.1) & (b.part[covered] == 0)
        self.assertTrue(flat.any())
        flat_normals = normal[covered][flat]
        np.testing.assert_allclose(flat_normals.mean(axis=0), [0.0, 0.0, 1.0], atol=0.03)
        self.assertGreater(float(flat_normals[:, 2].min()), 0.9)

    def test_the_emissive_map_is_black_but_for_the_glass_and_the_throat(self) -> None:
        emissive = self.maps["emissive"]
        b = self.atlas.buffers
        material_names = [m.name for m in self.atlas.materials]
        glowing = np.isin(b.material, [material_names.index(GLOW.name), material_names.index(GLASS.name)])
        self.assertTrue(np.all(emissive[b.mask & ~glowing] == 0), "black where nothing glows")
        self.assertGreater(float(emissive[b.mask & glowing].max()), 100.0)

    def test_the_albedo_at_a_panel_centre_is_the_materials_within_the_jitter(self) -> None:
        b = self.atlas.buffers
        covered = b.mask
        lattice = plating_lattice(EARTHFORCE, b.position[covered], b.normal[covered], self.atlas.part_platings[0], self.atlas.part_phases[0])
        centre = (lattice["edge_m"] > 0.12) & (b.edge_distance[covered] > 0.15) & (b.part[covered] == 0) & ~lattice["hatch"]
        albedo = srgb_to_linear8(self.maps["albedo"][covered][centre][:, :3])
        expected = np.array(GREY.albedo)
        ratio = albedo / expected
        # Q37: weathered, so the paint varies (grime, smudges, streaks) but stays the paint on average and never brightens much.
        self.assertGreater(float(np.median(ratio)), 0.75)
        self.assertTrue(np.all(ratio < 1.0 + EARTHFORCE.panel_tint_jitter + 0.12), float(ratio.max()))
        # A panel line is darker than the paint around it.
        on_line = lattice["on_line"] & (b.part[covered] == 0)
        self.assertLess(float(srgb_to_linear8(self.maps["albedo"][covered][on_line][:, :3]).mean()), 0.8 * float(albedo.mean()))

    def test_orm_carries_occlusion_roughness_and_metal(self) -> None:
        orm = self.maps["orm"]
        b = self.atlas.buffers
        material_names = [m.name for m in self.atlas.materials]
        throat = b.mask & (b.material == material_names.index(GLOW.name))
        hull = b.mask & (b.material == 0)
        self.assertGreater(float(orm[throat][:, 2].mean()), 180.0, "the throat is metal")
        self.assertLess(float(orm[hull][:, 2].mean()), 60.0, "paint is not")
        self.assertGreater(float(orm[hull][:, 1].mean()), float(orm[throat][:, 1].mean()), "paint is rougher than metal")
        self.assertEqual(int(orm[b.mask][:, 0].min()), 255, "occlusion off: fully open")

    def test_two_bakes_with_one_seed_are_identical_and_seeds_differ(self) -> None:
        again = bake_maps(self.atlas, EARTHFORCE, seed=42, occlusion=False)
        for name in ("albedo", "normal", "orm", "emissive"):
            np.testing.assert_array_equal(again[name], self.maps[name])
        other = bake_maps(self.atlas, EARTHFORCE, seed=7, occlusion=False)
        self.assertFalse(np.array_equal(other["albedo"], self.maps["albedo"]), "the wear is seeded")


class MarkingTests(unittest.TestCase):
    def test_glyph_strokes_exist_for_digits_and_letters(self) -> None:
        for ch in "0123456789AE":
            strokes = glyph_strokes(ch)
            self.assertTrue(strokes, ch)
            for stroke in strokes:
                self.assertGreaterEqual(len(stroke), 2)
        self.assertEqual(glyph_strokes(" "), ())

    def test_a_band_and_a_decal_paint_their_texels(self) -> None:
        pod = g.lathe([(0.0, 0.5), (4.0, 0.5)], 24, GREY)
        red = (0.5, 0.05, 0.02)
        markings = (
            Marking.band("pod", centre=(0.0, 0.0, 0.0), axis=(0.0, 0.0, 1.0), at_m=1.0, width_m=0.4, colour=red),
            Marking.text("pod", "7", centre=(0.5, 0.0, 3.0), right=(0.0, 0.0, 1.0), up=(0.0, 1.0, 0.0), facing=(1.0, 0.0, 0.0),
                         height_m=0.5, colour=(0.02, 0.02, 0.02)),
        )
        atlas = atlas_of([TexturedPart(pod, (0, 0, 0), markings=markings, name="pod")], atlas_px=512, texel_m=0.01)
        maps = bake_maps(atlas, EARTHFORCE, seed=1, occlusion=False)
        b = atlas.buffers
        albedo = srgb_to_linear8(maps["albedo"])
        in_band = b.mask & (np.abs(b.position[..., 2] - 1.0) < 0.15)
        self.assertGreater(float(albedo[in_band][:, 0].mean()), 3.0 * float(albedo[in_band][:, 1].mean()), "red band")
        off_band = b.mask & (np.abs(b.position[..., 2] - 1.0) > 0.3) & (b.position[..., 2] < 2.0)
        self.assertLess(float(albedo[off_band][:, 0].mean()), 1.3 * float(albedo[off_band][:, 1].mean()), "grey elsewhere")
        # The digit sits on the +X flank: some texels there are near black, the -X flank has none.
        flank = b.mask & (b.position[..., 0] > 0.4) & (np.abs(b.position[..., 2] - 3.0) < 0.3)
        other = b.mask & (b.position[..., 0] < -0.4) & (np.abs(b.position[..., 2] - 3.0) < 0.3)
        self.assertGreater(int((albedo[flank].max(axis=1) < 0.05).sum()), 20)
        self.assertEqual(int((albedo[other].max(axis=1) < 0.05).sum()), 0)


class PlatingTests(unittest.TestCase):
    """Q34 and Q37: the panels read as plating (rows of panels of varied length with staggered seams, sized per part, rivet rows
    beside the seams), not a uniform square grid, and the panels keep their size on a tilted face."""

    @staticmethod
    def _plate_points(tilt_deg: float = 0.0, size: float = 6.0, step: float = 0.004) -> tuple[np.ndarray, np.ndarray]:
        xs = np.arange(-0.5 * size, 0.5 * size, step)
        u, v = np.meshgrid(xs, xs)
        t = np.radians(tilt_deg)
        points = np.column_stack([u.ravel(), (v.ravel() * np.sin(t)), v.ravel() * np.cos(t)])
        normal = np.array([0.0, np.cos(t), -np.sin(t)])
        return points, np.tile(normal, (len(points), 1))

    def test_panel_lengths_vary_and_rows_are_staggered(self) -> None:
        box = g.box((6.0, 0.2, 6.0), GREY)
        plating = plating_for("fuselage", box, EARTHFORCE)
        points, normals = self._plate_points()
        lattice = plating_lattice(EARTHFORCE, points, normals, plating)
        lengths = np.unique(np.round(lattice["panel_length_m"], 3))
        self.assertGreater(len(lengths), 4)
        self.assertGreater(float(np.std(lengths) / np.mean(lengths)), 0.1, "panels of varied length")
        self.assertNotAlmostEqual(plating.length_m, plating.width_m, delta=0.05, msg="oblong plates, not squares")
        # Two neighbouring rows do not share their seams.
        rows = np.unique(lattice["row"])[:2]
        seams = [set(np.round(lattice["seam_u"][lattice["row"] == r], 2)) for r in rows]
        self.assertLess(len(seams[0] & seams[1]), max(1, len(seams[0]) // 3))

    def test_parts_get_their_own_plating_and_mirrors_share_it(self) -> None:
        pod = g.lathe([(0.0, 0.8), (5.0, 0.8)], 24, GREY)
        strut = g.box((4.0, 0.1, 1.5), GREY)
        a, b = plating_for("pod_ur", pod, EARTHFORCE), plating_for("strut_ur", strut, EARTHFORCE)
        self.assertNotEqual((a.length_m, a.width_m), (b.length_m, b.width_m))
        self.assertEqual(plating_for("pod_ll", pod, EARTHFORCE), a)
        self.assertEqual(a.row_axis, 2, "a pod's rows run along its length")
        self.assertEqual(b.row_axis, 0, "a strut's along its span")

    def test_rivet_rows_run_beside_the_seams(self) -> None:
        box = g.box((6.0, 0.2, 6.0), GREY)
        plating = plating_for("fuselage", box, EARTHFORCE)
        points, normals = self._plate_points()
        lattice = plating_lattice(EARTHFORCE, points, normals, plating)
        rivets = lattice["rivet_m"] < 0.004
        self.assertGreater(int(rivets.sum()), 200)
        self.assertTrue(np.all(lattice["edge_m"][rivets] < 0.06), "rivets sit near a seam")
        self.assertTrue(np.all(lattice["edge_m"][rivets] > 0.5 * EARTHFORCE.panel_line_width_m), "beside it, not in the groove")

    def test_a_tilted_plate_keeps_its_panel_size(self) -> None:
        box = g.box((6.0, 0.2, 6.0), GREY)
        plating = plating_for("fuselage", box, EARTHFORCE)
        flat = plating_lattice(EARTHFORCE, *self._plate_points(0.0), plating)
        tilted = plating_lattice(EARTHFORCE, *self._plate_points(40.0), plating)
        # Rows across the slope: measured on the surface, as many rows on the tilted plate as on the flat one.
        self.assertLess(abs(len(np.unique(tilted["row"])) - len(np.unique(flat["row"]))), 2)

    def test_a_groove_tilts_the_normal_map_towards_its_centre(self) -> None:
        # The T30a review's handedness check: decode with the texel's tangent (+u) and bitangent (-v, Godot's +Y up).
        atlas = atlas_of([TexturedPart(g.box((3.0, 3.0, 3.0), GREY), (0, 0, 0), name="hull")], atlas_px=512, texel_m=0.01)
        maps = bake_maps(atlas, EARTHFORCE, seed=1, occlusion=False)
        b = atlas.buffers
        normal = decode_normal(maps["normal"][::2, ::2])
        lattice_all = np.full(b.position.shape[:2], np.inf)
        covered = b.mask
        lattice = plating_lattice(EARTHFORCE, b.position[covered], b.normal[covered], atlas.part_platings[0], atlas.part_phases[0])
        lattice_all[covered] = lattice["edge_m"]
        rows, cols = np.nonzero(covered[1:-1, 1:-1])
        rows, cols = rows + 1, cols + 1
        inner = covered[rows, cols + 1] & covered[rows, cols - 1] & covered[rows + 1, cols] & covered[rows - 1, cols]
        rows, cols = rows[inner], cols[inner]
        edge = lattice_all[rows, cols]
        wall = (edge > 0.004) & (edge < 0.016) & (b.edge_distance[rows, cols] > 0.1)
        rows, cols = rows[wall], cols[wall]
        tangent = b.position[rows, cols + 1] - b.position[rows, cols - 1]
        bitangent = -(b.position[rows + 1, cols] - b.position[rows - 1, cols])
        tangent /= np.linalg.norm(tangent, axis=1, keepdims=True)
        bitangent /= np.linalg.norm(bitangent, axis=1, keepdims=True)
        n = normal[rows, cols]
        tilt = n[:, 0:1] * tangent + n[:, 1:2] * bitangent
        away = np.stack([lattice_all[rows, cols + 1] - lattice_all[rows, cols - 1], lattice_all[rows - 1, cols] - lattice_all[rows + 1, cols]], axis=1)
        away_world = away[:, 0:1] * tangent + away[:, 1:2] * bitangent  # the way out of the groove
        both = np.isfinite(away_world).all(axis=1) & (np.linalg.norm(away_world, axis=1) > 0)
        self.assertGreater(int(both.sum()), 100)
        towards_centre = np.einsum("ij,ij->i", tilt[both], away_world[both]) < 0.0
        self.assertGreater(float(towards_centre.mean()), 0.9, "the groove's walls face its centre")


class WeatheringTests(unittest.TestCase):
    """Q37: a medium blue-grey hull with dark streaks, smudges and grime, no bare metal, and less gloss (Q34)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas = atlas_of([TexturedPart(_panel_box(4.0), (0, 0, 0), name="fuselage")], atlas_px=512, texel_m=0.012)
        cls.maps = bake_maps(cls.atlas, EARTHFORCE, seed=11, occlusion=False)

    def test_the_hull_is_a_medium_blue_grey(self) -> None:
        srgb = linear_to_srgb(np.asarray(GREY.albedo)) * 255.0
        np.testing.assert_allclose(srgb, [130.0, 140.0, 155.0], atol=12.0)
        self.assertGreater(srgb[2], srgb[0])

    def test_no_bare_metal_shows(self) -> None:
        orm = self.maps["orm"][self.atlas.buffers.mask]
        self.assertLess(int(orm[:, 2].max()), 30, "the paint never wears to metal")

    def test_streaks_and_smudges_darken_the_paint(self) -> None:
        albedo = srgb_to_linear8(self.maps["albedo"][self.atlas.buffers.mask][:, :3]).mean(axis=1)
        median = float(np.median(albedo))
        self.assertLess(float(np.percentile(albedo, 5)), 0.75 * median, "dark streaks and smudges")
        self.assertGreater(float(np.percentile(albedo, 50)), 0.6 * float(np.mean(GREY.albedo)))

    def test_the_paint_is_matte(self) -> None:
        orm = self.maps["orm"][self.atlas.buffers.mask]
        self.assertGreater(float(orm[:, 1].mean()), 0.8 * 255.0)


if __name__ == "__main__":
    unittest.main()
