"""tools/refview compare (M5-T23): the fidelity check of a built asset against its reference STL, on synthetic shapes
(no reference file and no generated asset is needed, except the one test that reads a built raider when it exists)."""

from __future__ import annotations

import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import numpy as np

from tools.procgen.core import frames
from tools.procgen.core.manifest import build_manifest, lod_entry, write_manifest
from tools.procgen.core.ply import SplatData, write_ply

try:
    import PIL  # noqa: F401
except ImportError:  # the tool draws with Pillow, which procgen treats as optional (tools/procgen/README.md)
    compare = refview = None
else:
    from tools.refview import compare, refview  # a broken tool must fail here, not skip

needs_pillow = unittest.skipIf(compare is None, "tools/refview needs Pillow")

REPO_ROOT = Path(__file__).resolve().parents[3]


def _box(lo: tuple[float, float, float], hi: tuple[float, float, float]) -> np.ndarray:
    """Twelve triangles of an axis-aligned box."""
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    v = np.array(
        [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0], [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]],
        dtype=float,
    )
    faces = [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4), (2, 3, 7), (2, 7, 6), (1, 2, 6), (1, 6, 5), (0, 4, 7), (0, 7, 3)]
    return np.array([[v[a], v[b], v[c]] for a, b, c in faces])


SPACING = 0.08  # the synthetic splats' lattice spacing (m)


def shell_centres(lo: tuple[float, float, float], hi: tuple[float, float, float], spacing: float = SPACING) -> np.ndarray:
    """Splat centres on a lattice over the box's boundary layer, so every view of the box is tiled."""
    n = [max(1, round((h - l) / spacing)) for l, h in zip(lo, hi)]
    grids = np.meshgrid(*[np.arange(c) for c in n], indexing="ij")
    on_shell = np.zeros(grids[0].shape, dtype=bool)
    for g, c in zip(grids, n):
        on_shell |= (g == 0) | (g == c - 1)
    idx = np.stack([g[on_shell] for g in grids], axis=1)
    return np.asarray(lo) + (idx + 0.5) * spacing


def lattice_splats(boxes: list[tuple[tuple, tuple]], spacing: float = SPACING) -> tuple[np.ndarray, np.ndarray]:
    """Centres and round per-axis sigmas of splats that tile each box's silhouettes, as the tool draws them (a disc of
    ``SPLAT_SIGMAS`` sigmas covering a lattice cell of ``spacing``)."""
    centres = np.concatenate([shell_centres(lo, hi, spacing) for lo, hi in boxes])
    sigma = 0.72 * spacing / compare.SPLAT_SIGMAS
    return centres, np.full(centres.shape, sigma)


def write_asset(
    folder: Path,
    asset_id: str,
    centres: np.ndarray,
    scales: np.ndarray,
    offset: tuple[float, float, float] = (0.0, 0.0, 0.0),
    rot: np.ndarray | None = None,
    ply_name: str | None = None,
    extra_files: bool = True,
) -> Path:
    """An asset folder written the way a generator does it: authored positions minus ``centroid_offset``, then the
    Godot -> 3DGS flip (``core.frames``), the LOD0 PLY and ``manifest.json``."""
    folder.mkdir(parents=True, exist_ok=True)
    n = len(centres)
    quats = frames.quat_identity(n) if rot is None else rot
    written = SplatData(
        xyz=frames.godot_to_3dgs_positions(centres - np.asarray(offset)),
        rgb=np.full((n, 3), 0.5),
        alpha=np.full(n, 0.98),
        scale=scales,
        rot=frames.godot_to_3dgs_quats(quats),
    )
    name = ply_name or f"{asset_id}.ply"
    write_ply(folder / name, written)
    if extra_files:
        centred = centres - np.asarray(offset)
        manifest = build_manifest(
            asset_id, 1, 1, [lod_entry(0, name, n, SPACING)], centred.min(axis=0), centred.max(axis=0), offset
        )
        write_manifest(folder, manifest)
    return folder


def run(argv: list[str]) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        code = compare.main(argv)
    return code, out.getvalue(), err.getvalue()


class TmpCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def stl(self, tris: np.ndarray, name: str = "ship.stl") -> Path:
        path = self.dir / name
        refview.write_binary_stl(path, tris)
        return path

    def asset(self, boxes: list[tuple[tuple, tuple]], asset_id: str = "ship", **kwargs) -> Path:
        centres, scales = lattice_splats(boxes)
        return write_asset(self.dir / asset_id, asset_id, centres, scales, **kwargs)

    def compare(self, stl: Path, asset: Path, *extra: str, length: float = 12.0) -> tuple[int, str, str]:
        argv = [str(stl), str(asset), "--length", str(length), "--out", str(self.dir / "out"), *extra]
        return run(argv)

    def report(self) -> dict:
        return json.loads((self.dir / "out" / "fidelity.json").read_text())


# The test ship: a 4 x 2 x 12 m hull, nose at z = 0, centred in x and y.
HULL = ((-2.0, -1.0, 0.0), (2.0, 1.0, 12.0))


@needs_pillow
class ClipTests(unittest.TestCase):
    def test_a_slab_clip_cuts_triangles_exactly_and_keeps_the_inside(self) -> None:
        tris = _box((-1.0, -1.0, 0.0), (1.0, 1.0, 10.0))
        cut = compare.clip_slab(tris, 2, 2.0, 5.0)
        pts = cut.reshape(-1, 3)
        self.assertAlmostEqual(float(pts[:, 2].min()), 2.0, places=9)
        self.assertAlmostEqual(float(pts[:, 2].max()), 5.0, places=9)
        self.assertAlmostEqual(refview.surface_area(cut), 4 * 2 * 3, places=6)  # the four walls between the planes; a cut leaves a surface open

    def test_triangles_outside_are_dropped_and_inside_ones_kept_whole(self) -> None:
        tris = _box((0.0, 0.0, 0.0), (1.0, 1.0, 1.0))
        self.assertEqual(len(compare.clip_slab(tris, 2, 5.0, 6.0)), 0)
        np.testing.assert_allclose(compare.clip_slab(tris, 2, -1.0, 2.0), tris)

    def test_a_long_thin_triangle_is_cut_at_the_planes_not_kept_whole(self) -> None:
        strip = np.array([[[0.0, 0.0, 0.0], [1.0, 0.0, 100.0], [0.0, 1.0, 100.0]]])
        cut = compare.clip_slab(strip, 2, 40.0, 60.0)
        pts = cut.reshape(-1, 3)
        self.assertAlmostEqual(float(pts[:, 2].min()), 40.0, places=9)
        self.assertAlmostEqual(float(pts[:, 2].max()), 60.0, places=9)


@needs_pillow
class AssetFrameTests(TmpCase):
    def test_positions_return_to_the_authored_frame(self) -> None:
        centres = np.array([[1.5, -0.7, 20.0], [-3.0, 2.0, 5.5], [0.0, 0.0, 69.0]])
        write_asset(self.dir / "a", "a", centres, np.full((3, 3), 0.1), offset=(0.0, -0.4468, 38.0806))
        splats = compare.load_asset_splats(self.dir / "a")
        np.testing.assert_allclose(splats.centres, centres, atol=2e-4)  # the manifest keeps four digits

    def test_orientation_is_not_mirrored(self) -> None:
        # A flat splat whose normal leans from +z toward +x by 30 degrees; its long axis then lies along (cos 30, 0, -sin 30).
        a = np.radians(30.0)
        normal = np.array([np.sin(a), 0.0, np.cos(a)])
        t1 = np.array([np.cos(a), 0.0, -np.sin(a)])
        t2 = np.cross(normal, t1)
        quat = frames.matrix_to_quat(np.stack([t1, t2, normal], axis=-1))[None]
        write_asset(self.dir / "a", "a", np.array([[0.0, 0.0, 10.0]]), np.array([[3.0, 3.0, 0.01]]), rot=quat)
        cov = compare.load_asset_splats(self.dir / "a").cov[0]
        self.assertLess(cov[0, 2], 0.0)  # a mirrored read would lean the other way
        self.assertAlmostEqual(float(cov[0, 2]), 9.0 * np.cos(a) * -np.sin(a), places=3)
        self.assertAlmostEqual(float(cov[1, 1]), 9.0, places=3)

    def test_the_lod0_file_comes_from_the_manifest(self) -> None:
        centres, scales = lattice_splats([HULL])
        write_asset(self.dir / "b", "b", centres, scales, ply_name="b_hull.ply")
        self.assertEqual(len(compare.load_asset_splats(self.dir / "b")), len(centres))

    def test_an_asset_id_is_looked_up_under_the_generated_folder(self) -> None:
        centres, scales = lattice_splats([HULL])
        write_asset(self.dir / "gen" / "ship", "ship", centres, scales)
        self.assertEqual(compare.resolve_asset("ship", self.dir / "gen"), self.dir / "gen" / "ship")
        with self.assertRaisesRegex(ValueError, "nothing"):
            compare.resolve_asset("nothing", self.dir / "gen")


@needs_pillow
class ShapeTests(TmpCase):
    def test_identical_boxes_score_about_one_with_no_shift(self) -> None:
        centres, scales = lattice_splats([HULL])
        splats = compare.splat_set(centres, scales)
        result = compare.compare_shapes(_box(*HULL), splats, 12.0)
        for name in ("top", "side", "front"):
            self.assertGreater(result.views[name].iou, 0.95, name)
        for ratio in result.ratios.values():
            self.assertAlmostEqual(ratio, 1.0, delta=0.02)
        self.assertLessEqual(float(np.abs(result.shift_m).max()), 0.05)

    def test_a_longer_asset_gets_the_known_overlap_and_length_ratio(self) -> None:
        longer = ((-2.0, -1.0, 0.0), (2.0, 1.0, 14.4))  # 1.2 times the length
        splats = compare.splat_set(*lattice_splats([longer]))
        result = compare.compare_shapes(_box(*HULL), splats, 12.0)
        self.assertAlmostEqual(result.views["top"].iou, 12.0 / 14.4, delta=0.03)
        self.assertAlmostEqual(result.views["side"].iou, 12.0 / 14.4, delta=0.03)
        self.assertGreater(result.views["front"].iou, 0.97)
        self.assertAlmostEqual(result.ratios["length"], 1.2, delta=0.02)
        self.assertAlmostEqual(result.ratios["width"], 1.0, delta=0.02)

    def test_a_shift_beyond_the_window_leaves_the_rest_as_error(self) -> None:
        moved = ((-2.0, -1.0, 0.6), (2.0, 1.0, 12.6))  # 5 % of the length; the search reaches 2 %
        splats = compare.splat_set(*lattice_splats([moved]))
        result = compare.compare_shapes(_box(*HULL), splats, 12.0)
        self.assertAlmostEqual(float(result.shift_m[2]), -0.24, delta=0.04)
        self.assertAlmostEqual(result.views["top"].iou, (12.0 - 0.36) / (12.0 + 0.36), delta=0.03)
        self.assertGreater(result.views["front"].iou, 0.97)  # the front view does not see the z shift
        self.assertLess(result.views["top"].iou_unshifted, result.views["top"].iou)

    def test_a_small_offset_is_recovered_and_reported(self) -> None:
        moved = ((-1.95, -1.0, 0.12), (2.05, 1.0, 12.12))  # 0.05 m across, 1 % of the length along
        splats = compare.splat_set(*lattice_splats([moved]))
        result = compare.compare_shapes(_box(*HULL), splats, 12.0)
        np.testing.assert_allclose(result.shift_m, [-0.05, 0.0, -0.12], atol=0.035)
        for name in ("top", "side", "front"):
            self.assertGreater(result.views[name].iou, 0.95, name)

    def test_a_missing_part_costs_its_share_of_the_silhouette(self) -> None:
        pod = ((-2.0, 1.0, 4.0), (2.0, 3.0, 8.0))  # on top of the hull: 4 x 4 in plan, 2 high
        model = np.concatenate([_box(*HULL), _box(*pod)])
        splats = compare.splat_set(*lattice_splats([HULL]))
        result = compare.compare_shapes(model, splats, 12.0)
        self.assertAlmostEqual(result.views["top"].iou, 1.0, delta=0.03)  # the pod hides in the hull's plan
        self.assertAlmostEqual(result.views["side"].iou, 24.0 / 32.0, delta=0.04)
        self.assertAlmostEqual(result.views["front"].iou, 8.0 / 16.0, delta=0.04)
        self.assertAlmostEqual(result.ratios["height"], 2.0 / 4.0, delta=0.03)

    def test_the_search_window_is_two_percent_of_the_length_per_axis(self) -> None:
        self.assertEqual(compare.SHIFT_FRACTION, 0.02)
        self.assertLessEqual(compare.PIXEL_FRACTION, 0.005)

    def test_the_pixel_cannot_be_coarser_than_half_a_percent(self) -> None:
        splats = compare.splat_set(*lattice_splats([HULL]))
        with self.assertRaisesRegex(ValueError, "pixel"):
            compare.compare_shapes(_box(*HULL), splats, 12.0, pixel_fraction=0.01)

    def test_a_rotated_ellipse_covers_its_own_area(self) -> None:
        a = np.radians(30.0)
        quat = np.array([[np.cos(a / 2), 0.0, np.sin(a / 2), 0.0]])  # turned about y: long axis slanted in the top view
        splats = compare.splat_set(np.array([[0.0, 0.0, 5.0]]), np.array([[2.0, 1.0, 1.0]]), quat)
        lo, hi = splats.bounds()
        k = compare.SPLAT_SIGMAS
        self.assertAlmostEqual(float(hi[0]), k * np.sqrt((2 * np.cos(a)) ** 2 + np.sin(a) ** 2), places=6)
        grid = compare.view_grid("top", lo, hi, 0.02, 3)
        mask = compare.splat_mask(splats, grid)
        self.assertAlmostEqual(mask.sum() * 0.02**2, np.pi * k * k * 2.0 * 1.0, delta=0.03 * np.pi * k * k * 2.0)

    def test_a_flat_splat_edge_on_still_draws_a_thin_line(self) -> None:
        splats = compare.splat_set(np.array([[0.0, 0.0, 5.0]]), np.array([[1.0, 1.0, 0.001]]))  # a plate in the x-y plane
        lo, hi = splats.bounds()
        grid = compare.view_grid("top", lo, hi, 0.02, 3)  # seen from above it is a line along x, a pixel or two wide
        mask = compare.splat_mask(splats, grid)
        self.assertLessEqual(len(np.flatnonzero(mask.any(axis=0))), 3)
        self.assertGreater(int(mask.any(axis=1).sum()), 0.6 * 2 * compare.SPLAT_SIGMAS / 0.02)  # most of its length is drawn (the tips taper)


@needs_pillow
class VerdictTests(unittest.TestCase):
    OK = {"top": 0.95, "side": 0.95, "front": 0.95}
    SIZE = {"length": 1.0, "width": 1.0, "height": 1.0}

    def test_the_bar_is_inclusive(self) -> None:
        self.assertEqual(compare.judge({**self.OK, "side": 0.90}, self.SIZE), [])
        self.assertEqual(compare.judge(self.OK, {**self.SIZE, "length": 1.10}), [])
        self.assertEqual(compare.judge(self.OK, {**self.SIZE, "width": 0.90}), [])

    def test_just_under_the_bar_fails_and_names_the_measure(self) -> None:
        failures = compare.judge({**self.OK, "front": 0.8999}, self.SIZE)
        self.assertEqual(len(failures), 1)
        self.assertIn("front", failures[0])
        failures = compare.judge(self.OK, {**self.SIZE, "height": 1.1001})
        self.assertEqual(len(failures), 1)
        self.assertIn("height", failures[0])
        self.assertEqual(len(compare.judge(self.OK, {**self.SIZE, "length": 0.8999})), 1)

    def test_several_failures_are_all_listed(self) -> None:
        self.assertEqual(len(compare.judge({"top": 0.5, "side": 0.5, "front": 0.95}, {**self.SIZE, "width": 2.0})), 3)


@needs_pillow
class MainTests(TmpCase):
    def test_identical_shapes_pass_with_exit_zero_and_write_the_report(self) -> None:
        code, out, err = self.compare(self.stl(_box(*HULL)), self.asset([HULL]))
        self.assertEqual(code, 0, out + err)
        lines = out.strip().splitlines()
        for view in ("top", "side", "front"):
            self.assertEqual(sum(1 for line in lines if line.startswith(view)), 1, out)
        self.assertIn("PASS", lines[-1])
        for name in ("overlay_top.png", "overlay_side.png", "overlay_front.png", "fidelity.json"):
            self.assertTrue((self.dir / "out" / name).is_file(), name)
        report = self.report()
        self.assertEqual(report["verdict"], "pass")
        self.assertEqual(report["thresholds"], {"iou_min": 0.9, "dimension_tolerance": 0.1, "shift_fraction": 0.02})
        self.assertEqual(sorted(report["views"]), ["front", "side", "top"])
        self.assertEqual(sorted(report["dimensions"]), ["height", "length", "width"])
        self.assertLessEqual(report["pixel_m"], 0.005 * 12.0)
        self.assertEqual(len(report["shift_m"]), 3)
        top = report["views"]["top"]
        self.assertLessEqual(top["both_px"], min(top["model_px"], top["asset_px"]))
        self.assertEqual(top["both_px"] + top["model_only_px"], top["model_px"])
        self.assertEqual(top["both_px"] + top["asset_only_px"], top["asset_px"])

    def test_the_overlay_marks_model_only_asset_only_and_both_in_three_colours(self) -> None:
        from PIL import Image

        model = np.concatenate([_box(*HULL), _box((-2.0, -1.0, 12.0), (2.0, 1.0, 14.0))])  # a tail the asset lacks
        fin = ((-3.0, -0.5, 4.0), (-2.0, 0.5, 8.0))  # a part the model lacks
        code, _, _ = self.compare(self.stl(model), self.asset([HULL, fin]), length=14.0)
        self.assertEqual(code, 1)
        arr = np.asarray(Image.open(self.dir / "out" / "overlay_top.png").convert("RGB"))
        top = self.report()["views"]["top"]
        self.assertGreater(top["model_only_px"], 0)
        self.assertGreater(top["asset_only_px"], 0)
        for colour in (compare.MODEL_ONLY, compare.ASSET_ONLY, compare.BOTH):
            self.assertGreater(int((arr == np.array(colour)).all(axis=2).sum()), 100, colour)

    def test_a_dimension_off_by_more_than_ten_percent_exits_one_even_with_a_good_overlap(self) -> None:
        # A thin mast makes the model 1.12 times longer; the silhouettes still overlap by about 99 %.
        mast = _box((-0.05, -0.05, 12.0), (0.05, 0.05, 13.44))
        code, out, _ = self.compare(self.stl(np.concatenate([_box(*HULL), mast])), self.asset([HULL]), length=13.44)
        self.assertEqual(code, 1, out)
        report = self.report()
        self.assertGreater(report["views"]["top"]["iou"], 0.95)
        self.assertLess(report["dimensions"]["length"]["ratio"], 0.9)
        self.assertTrue(any("length" in f for f in report["failures"]))
        self.assertIn("FAIL", out.strip().splitlines()[-1])

    def test_an_overlap_under_the_bar_exits_one_with_the_right_dimensions(self) -> None:
        # The asset has the model's length, width and height but its middle third is half as wide.
        narrow = [((-2.0, -1.0, 0.0), (2.0, 1.0, 4.0)), ((-1.0, -1.0, 4.0), (1.0, 1.0, 8.0)), ((-2.0, -1.0, 8.0), (2.0, 1.0, 12.0))]
        code, out, _ = self.compare(self.stl(_box(*HULL)), self.asset(narrow))
        self.assertEqual(code, 1, out)
        report = self.report()
        self.assertAlmostEqual(report["views"]["top"]["iou"], 10.0 / 12.0, delta=0.04)
        self.assertGreater(report["views"]["front"]["iou"], 0.95)
        for d in report["dimensions"].values():
            self.assertAlmostEqual(d["ratio"], 1.0, delta=0.02)

    def test_a_slightly_short_asset_still_passes(self) -> None:
        short = ((-2.0, -1.0, 0.0), (2.0, 1.0, 11.52))  # 96 % of the length
        code, out, _ = self.compare(self.stl(_box(*HULL)), self.asset([short]))
        self.assertEqual(code, 0, out)

    def test_the_stl_axis_mapping_and_length_are_applied_like_refview(self) -> None:
        rotation = refview.frame_matrix("-x", "+z", "+y")  # the Saturn mapping
        file_tris = (_box(*HULL) @ rotation) * 3.7 + np.array([10.0, -4.0, 25.0])  # in the file's own axes, units and origin
        code, out, _ = self.compare(self.stl(file_tris), self.asset([HULL]), "--right=-x", "--up=+z", "--aft=+y")
        self.assertEqual(code, 0, out)
        report = self.report()
        self.assertEqual(report["mapping"], {"right": "-x", "up": "+z", "aft": "+y"})
        self.assertAlmostEqual(report["dimensions"]["length"]["model_m"], 12.0, places=3)

    def test_model_and_asset_crops_are_set_apart_and_meet_at_the_crop_start(self) -> None:
        # Two parts with a small gap between them, like the lead ship and a cargo section.
        front_part = ((-2.0, -1.0, 0.0), (2.0, 1.0, 5.8))
        rear_part = ((-1.0, -0.5, 6.2), (1.0, 0.5, 12.0))
        model = np.concatenate([_box(*front_part), _box(*rear_part)])
        both = self.asset([front_part, rear_part], asset_id="both")
        # The rear part of both sides, each cropped by its own range.
        code, out, _ = self.compare(self.stl(model), both, "--model-zrange", "6", "12", "--asset-zrange", "6", "12")
        self.assertEqual(code, 0, out)
        self.assertAlmostEqual(self.report()["dimensions"]["width"]["model_m"], 2.0, places=2)
        # The model's rear part against an asset made of that part alone, which starts at its own z = 0.
        alone = self.asset([((-1.0, -0.5, 0.2), (1.0, 0.5, 6.0))], asset_id="alone")
        code, out, _ = self.compare(self.stl(model), alone, "--model-zrange", "6", "12")
        self.assertEqual(code, 0, out)
        self.assertAlmostEqual(self.report()["dimensions"]["length"]["asset_m"], 5.8, delta=0.15)
        # The front part against the wrong crop of the asset (its rear part): the widths differ by a factor of two.
        code, out, _ = self.compare(self.stl(model), both, "--model-zrange", "0", "6", "--asset-zrange", "6", "12")
        self.assertEqual(code, 1, out)
        self.assertAlmostEqual(self.report()["dimensions"]["width"]["ratio"], 0.5, delta=0.03)

    def test_model_scale_grows_the_cropped_model_to_the_asset_size(self) -> None:
        # Q20 (M5-T12): a part the maintainer sized apart from the model is scored at the asset's size.
        bigger = ((-2.5, -1.2, 0.0), (2.5, 1.2, 12.0))
        code, out, _ = self.compare(self.stl(_box(*HULL)), self.asset([bigger]))
        self.assertEqual(code, 1, out)
        code, out, _ = self.compare(self.stl(_box(*HULL)), self.asset([bigger]), "--model-scale", "1.25,1.2,1")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.report()["model"]["scale"], [1.25, 1.2, 1.0])
        code, out, _ = self.compare(self.stl(_box(*HULL)), self.asset([bigger]), "--model-scale", "1,0,1")
        self.assertEqual(code, 2, out)

    def test_an_authored_origin_off_the_box_centre_is_given_with_model_offset(self) -> None:
        # A generator that authors y from an axis 5 m above the model's box centre (the Saturns' spine axis).
        raised = ((-2.0, 4.0, 0.0), (2.0, 6.0, 12.0))
        asset = self.asset([raised])
        code, out, _ = self.compare(self.stl(_box(*HULL)), asset)
        self.assertEqual(code, 1, out)
        report = self.report()
        np.testing.assert_allclose(report["centre_gap_m"], [0.0, 5.0, 0.0], atol=0.05)
        self.assertEqual(len(report["shift_at_limit"]), 3)
        self.assertIn("--model-offset 0.00,5.00,0.00", out)  # the hint names the value to pass
        code, out, _ = self.compare(self.stl(_box(*HULL)), asset, "--model-offset", "0,5,0")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.report()["model"]["offset_m"], [0.0, 5.0, 0.0])
        self.assertNotIn("--model-offset", out)

    def test_part_runs_write_to_their_own_folder(self) -> None:
        argv = [str(self.stl(_box(*HULL))), str(self.asset([HULL])), "--length", "12", "--name", "ship", "--part", "lead", "--out", str(self.dir / "rep")]
        code, _, _ = run(argv)
        self.assertEqual(code, 0)
        self.assertTrue((self.dir / "rep" / "lead" / "fidelity.json").is_file())
        self.assertEqual(json.loads((self.dir / "rep" / "lead" / "fidelity.json").read_text())["part"], "lead")

    def test_pods_are_drawn_with_the_hull_at_their_mounts(self) -> None:
        # A narrow hull and three wide pods in a row, at mounts given in the body frame (the centroid offset subtracted),
        # as hardpoints.json lists them.
        thin = ((-1.0, -1.0, 0.0), (1.0, 1.0, 12.0))
        pod = ((-2.0, -0.5, -1.0), (2.0, 0.5, 1.0))
        offset = np.array([0.0, 0.3, 6.1])
        mounts = [(0.0, -0.3, z) for z in (-3.0, 0.0, 3.0)]
        placed = [tuple(np.asarray(corner) + np.asarray(m) + offset) for m in mounts for corner in pod]
        model = np.concatenate([_box(*thin)] + [_box(placed[i], placed[i + 1]) for i in range(0, len(placed), 2)])
        hull_dir = self.asset([thin], asset_id="bokmai", offset=tuple(offset))
        (hull_dir / "hardpoints.json").write_text(
            json.dumps({"cargo_pods": [{"name": f"pod_{i}", "position": list(m), "up": [0, 1, 0]} for i, m in enumerate(mounts)]})
        )
        pod_centres, pod_scales = lattice_splats([pod])
        write_asset(self.dir / "pod", "pod", pod_centres, pod_scales)
        pod_ply = str(self.dir / "pod" / "pod.ply")

        code, out, _ = self.compare(self.stl(model), hull_dir, "--pod-ply", pod_ply, "--pods-from-hardpoints")
        self.assertEqual(code, 0, out)
        self.assertGreater(self.report()["views"]["top"]["iou"], 0.95)
        self.assertEqual(self.report()["asset"]["extra_parts"], 3)
        # The pod file beside the asset (<id>_pod.ply) is the default.
        shutil.copy(pod_ply, hull_dir / "bokmai_pod.ply")
        code, out, _ = self.compare(self.stl(model), hull_dir, "--pods-from-hardpoints")
        self.assertEqual(code, 0, out)
        # The same mounts given on the command line.
        argv = ["--pod-ply", pod_ply] + [a for m in mounts for a in ("--pod-at", ",".join(str(v) for v in m))]
        code, out, _ = self.compare(self.stl(model), hull_dir, *argv)
        self.assertEqual(code, 0, out)
        # Without the pods the hull alone misses them.
        code, out, _ = self.compare(self.stl(model), hull_dir)
        self.assertEqual(code, 1, out)
        self.assertLess(self.report()["views"]["top"]["iou"], 0.9)

    def test_a_pod_follows_its_up_vector(self) -> None:
        # A pod taller above its origin than below, one mounted up on the top and one hanging down from the belly.
        pod_box = ((-0.5, -0.5, -1.0), (0.5, 3.5, 1.0))
        centres, scales = lattice_splats([pod_box])
        write_asset(self.dir / "pod", "pod", centres, scales)
        pod_ply = str(self.dir / "pod" / "pod.ply")
        model = np.concatenate([_box(*HULL), _box((-0.5, 0.5, 2.0), (0.5, 4.5, 4.0)), _box((-0.5, -4.5, 8.0), (0.5, -0.5, 10.0))])

        def score(up_down: list[int]) -> int:
            hull_dir = self.asset([HULL], asset_id="ship")
            pods = [{"name": "a", "position": [0.0, 1.0, 3.0], "up": [0, 1, 0]}, {"name": "b", "position": [0.0, -1.0, 9.0], "up": up_down}]
            (hull_dir / "hardpoints.json").write_text(json.dumps({"cargo_pods": pods}))
            return self.compare(self.stl(model), hull_dir, "--pod-ply", pod_ply, "--pods-from-hardpoints")[0]

        self.assertEqual(score([0, -1, 0]), 0)
        self.assertEqual(score([0, 1, 0]), 1)  # the same pod standing on the belly instead

    def test_it_runs_as_a_script_in_isolated_mode(self) -> None:
        # The documented command line: `python3 -I tools/refview/compare.py`, where the repo root is not on the path.
        argv = [sys.executable, "-I", str(Path(compare.__file__)), str(self.stl(_box(*HULL))), str(self.asset([HULL])), "--length", "12", "--out", str(self.dir / "out")]
        done = subprocess.run(argv, capture_output=True, text=True, cwd=self.dir, check=False)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("verdict: PASS", done.stdout)

    def test_bad_input_exits_two_with_a_message(self) -> None:
        good_stl, good_asset = self.stl(_box(*HULL)), self.asset([HULL])
        empty = self.dir / "empty.stl"
        empty.write_bytes(b"")
        bare = self.dir / "bare"
        bare.mkdir()
        broken = self.dir / "broken"
        broken.mkdir()
        (broken / "manifest.json").write_text("{not json")
        cases = {
            "missing stl": ([str(self.dir / "nope.stl"), str(good_asset)], "nope.stl"),
            "empty stl": ([str(empty), str(good_asset)], "no triangles"),
            "missing asset": ([str(good_stl), str(self.dir / "ghost")], "ghost"),
            "no manifest": ([str(good_stl), str(bare)], "manifest"),
            "broken manifest": ([str(good_stl), str(broken)], "manifest"),
            "mirrored mapping": ([str(good_stl), str(good_asset), "--right=+x", "--up=+z", "--aft=+y"], "mirrors"),
            "empty model crop": ([str(good_stl), str(good_asset), "--model-zrange", "50", "60"], "model"),
            "empty asset crop": ([str(good_stl), str(good_asset), "--asset-zrange", "50", "60"], "asset"),
            "backwards crop": ([str(good_stl), str(good_asset), "--model-zrange", "6", "2"], "zrange"),
            "coarse pixel": ([str(good_stl), str(good_asset), "--pixel-frac", "0.02"], "pixel"),
            "missing pod file": ([str(good_stl), str(good_asset), "--pod-ply", str(self.dir / "no.ply"), "--pod-at", "0,0,0"], "no.ply"),
            "bad model offset": ([str(good_stl), str(good_asset), "--model-offset", "1,2"], "x,y,z"),
            "pods without a file": ([str(good_stl), str(good_asset), "--pod-at", "0,0,0"], "pod-ply"),
        }
        for label, (argv, needle) in cases.items():
            with self.subTest(label):
                code, _, err = run(argv + ["--length", "12", "--out", str(self.dir / "out")])
                self.assertEqual(code, 2, err)
                self.assertIn(needle, err)


@unittest.skipUnless((REPO_ROOT / "assets" / "generated" / "raider_fighter" / "manifest.json").is_file(), "needs the built raider_fighter")
@needs_pillow
class BuiltAssetTests(unittest.TestCase):
    """The frame of a real generator's output: a built raider against its own fallback mesh."""

    def setUp(self) -> None:
        self.dir = REPO_ROOT / "assets" / "generated" / "raider_fighter"
        manifest = json.loads((self.dir / "manifest.json").read_text())
        self.offset = np.asarray(manifest["centroid_offset"])
        verts, faces = [], []
        for line in (self.dir / "raider_fighter.obj").read_text().splitlines():
            if line.startswith("v "):
                verts.append([float(v) for v in line.split()[1:4]])
            elif line.startswith("f "):
                faces.append([int(p.split("/")[0]) - 1 for p in line.split()[1:4]])
        self.mesh = np.asarray(verts)[np.asarray(faces)]  # the centred Godot frame, like the splats after the flip
        self.length = float(np.ptp(self.mesh[..., 2]))

    def test_the_built_splats_match_their_own_mesh_after_the_frame_is_undone(self) -> None:
        splats = compare.load_asset_splats(self.dir)
        lo, hi = splats.bounds()
        self.assertLess(abs(float(lo[2] - (self.mesh[..., 2].min() + self.offset[2]))), 0.5)
        result = compare.compare_shapes(self.mesh + self.offset, splats, self.length)
        for name in ("top", "side", "front"):
            self.assertGreater(result.views[name].iou_unshifted, 0.8, name)  # the thin wings cost the front view most
        self.assertGreater(result.views["top"].iou, 0.95)
        for ratio in result.ratios.values():
            self.assertAlmostEqual(ratio, 1.0, delta=0.06)
        self.assertLess(float(np.abs(result.shift_m).max()), 0.1)
        # Left in the centred frame (the offset not added back), the same splats miss the mesh by half the ship.
        lost = compare.compare_shapes(self.mesh + self.offset, compare.SplatSet(splats.centres - self.offset, splats.cov), self.length)
        self.assertLess(lost.views["top"].iou, 0.7)


if __name__ == "__main__":
    unittest.main()
