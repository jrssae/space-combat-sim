"""tools/refview compare (M5-T23): the fidelity check of a built asset against its reference STL, on synthetic shapes
(no reference file and no generated asset is needed, except the one test that reads a built raider when it exists).

The verdict (Q18) scores the asset's fallback mesh against the STL; a second check holds the LOD0 splats to 0.85 against
that mesh. The calibration tests pin what the tool reads for a perfect copy: a mesh against itself is 1.0, and splats
sampled from a mesh with the generators' convention read at least the pinned floors against it."""

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
from unittest import mock

import numpy as np

from tools.procgen.core import frames
from tools.procgen.core.geometry import Material, Mesh
from tools.procgen.core.manifest import build_manifest, lod_entry, write_manifest
from tools.procgen.core.ply import SplatData, write_ply
from tools.procgen.core.sampling import sample_mesh, to_splats

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


def _boxes(boxes: list[tuple[tuple, tuple]]) -> np.ndarray:
    return np.concatenate([_box(lo, hi) for lo, hi in boxes])


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


def mesh_of(tris: np.ndarray) -> Mesh:
    n = len(tris)
    return Mesh(tris.reshape(-1, 3), np.arange(3 * n).reshape(-1, 3), np.zeros(n, dtype=int), (Material("m", (0.5, 0.5, 0.5)),))


def sampled_splats(tris: np.ndarray, spacing: float, seed: int = 1) -> "compare.SplatSet":
    """Splats of a mesh as the generators make them: ``sample_mesh`` at ``spacing``, then ``to_splats`` with the default
    overlap and thickness."""
    samples = sample_mesh(mesh_of(tris), spacing, np.random.default_rng(seed), smooth=False)
    data = to_splats(samples, np.full((len(samples), 3), 0.5), spacing)
    return compare.splat_set(data.xyz, data.scale, data.rot)


def write_obj_triangles(path: Path, tris: np.ndarray) -> None:
    """A minimal OBJ of ``tris`` (vertices as given, one triangle per ``f`` line)."""
    lines = [f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}" for v in tris.reshape(-1, 3)]
    lines += [f"f {3 * i + 1} {3 * i + 2} {3 * i + 3}" for i in range(len(tris))]
    path.write_text("\n".join(lines) + "\n")


def write_asset(
    folder: Path,
    asset_id: str,
    centres: np.ndarray,
    scales: np.ndarray,
    offset: tuple[float, float, float] = (0.0, 0.0, 0.0),
    rot: np.ndarray | None = None,
    ply_name: str | None = None,
    mesh_tris: np.ndarray | None = None,
) -> Path:
    """An asset folder written the way a generator does it: authored positions minus ``centroid_offset``, the LOD0 PLY
    after the Godot -> 3DGS flip (``core.frames``), the fallback mesh ``<id>.obj`` in the centred Godot frame (when
    ``mesh_tris``, authored, is given) and ``manifest.json``."""
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
    files = {}
    if mesh_tris is not None:
        write_obj_triangles(folder / f"{asset_id}.obj", mesh_tris - np.asarray(offset))
        files["fallback_mesh"] = f"{asset_id}.obj"
    centred = centres - np.asarray(offset)
    manifest = build_manifest(asset_id, 1, 1, [lod_entry(0, name, n, SPACING)], centred.min(axis=0), centred.max(axis=0), offset, files=files)
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

    def asset(self, boxes: list[tuple[tuple, tuple]], asset_id: str = "ship", mesh_boxes: list | None = None, **kwargs) -> Path:
        """An asset whose splats tile ``boxes`` and whose mesh is ``mesh_boxes`` (default: the same boxes)."""
        centres, scales = lattice_splats(boxes)
        return write_asset(self.dir / asset_id, asset_id, centres, scales, mesh_tris=_boxes(mesh_boxes or boxes), **kwargs)

    def pod(self, box: tuple[tuple, tuple], name: str = "pod") -> tuple[str, str]:
        """A pod model (splats and mesh) in its own frame; returns the paths of its PLY and OBJ."""
        centres, scales = lattice_splats([box])
        write_asset(self.dir / name, name, centres, scales, mesh_tris=_box(*box))
        return str(self.dir / name / f"{name}.ply"), str(self.dir / name / f"{name}.obj")

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

    def test_a_face_lying_in_a_crop_plane_inside_the_ship_is_not_kept(self) -> None:
        # Two parts touching at z = 6: the front part's rear cap lies in the plane and must not show face-on in the rear
        # part's front view (the rear part's own front cap lies there too and goes with it; its rear cap stays).
        tris = _boxes([((-2.0, -1.0, 0.0), (2.0, 1.0, 6.0)), ((-1.0, -0.5, 6.0), (1.0, 0.5, 12.0))])
        rear = compare.crop_triangles(tris, 6.0, 12.0, 0.0, 12.0)
        self.assertFalse(np.all(np.abs(rear[..., 2] - 6.0) < 1e-3, axis=1).any())
        self.assertLessEqual(float(np.abs(rear[..., 0]).max()), 1.0 + 1e-9)  # nothing of the 4 m wide cap
        self.assertTrue(np.all(np.abs(rear[..., 2] - 12.0) < 1e-3, axis=1).any())  # the rear cap at the ship's own end

    def test_a_plane_at_the_ships_own_end_keeps_the_cap_there(self) -> None:
        tris = _boxes([((-2.0, -1.0, 0.0), (2.0, 1.0, 6.0)), ((-1.0, -0.5, 6.0), (1.0, 0.5, 12.0))])
        front = compare.crop_triangles(tris, 0.0, 6.0, 0.0, 12.0)
        self.assertTrue(np.all(np.abs(front[..., 2] - 0.0) < 1e-3, axis=1).any())  # the nose cap stays

    def test_splats_are_cropped_by_centre_with_the_same_planes(self) -> None:
        splats = compare.splat_set(np.array([[0, 0, 5.99999], [0, 0, 6.0], [0, 0, 6.5], [0, 0, 11.0]]), np.full((4, 3), 0.1))
        lo, hi = compare.crop_planes(6.0, 12.0, 0.0, 12.0)
        self.assertEqual(len(splats.cropped(2, lo, hi)), 2)  # the centre on the plane counts as the neighbour's


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

    def test_the_mesh_returns_to_the_authored_frame_unflipped(self) -> None:
        # The OBJ is in the centred Godot frame, not the GDGS-flipped one: an off-axis shape must come back unmirrored.
        tris = _boxes([((1.0, 2.0, 10.0), (4.0, 3.0, 30.0))])
        write_asset(self.dir / "a", "a", np.array([[0.0, 0.0, 0.0]]), np.full((1, 3), 0.1), offset=(0.0, -0.4468, 38.0806), mesh_tris=tris)
        np.testing.assert_allclose(compare.load_asset_mesh(self.dir / "a"), tris, atol=2e-4)

    def test_the_mesh_file_comes_from_the_manifest_or_the_asset_id(self) -> None:
        folder = self.asset([HULL], asset_id="m")
        (folder / "m.obj").rename(folder / "hull.obj")
        with self.assertRaisesRegex(ValueError, "fallback mesh"):
            compare.load_asset_mesh(folder)
        manifest = json.loads((folder / "manifest.json").read_text())
        manifest["files"]["fallback_mesh"] = "hull.obj"
        (folder / "manifest.json").write_text(json.dumps(manifest))
        self.assertEqual(len(compare.load_asset_mesh(folder)), 12)

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
class GeometryCheckTests(TmpCase):
    """The verdict: the asset's mesh against the STL's triangles."""

    def test_a_mesh_against_itself_scores_exactly_one_with_no_shift(self) -> None:
        tris = _boxes([HULL, ((-6.0, -0.3, 3.0), (6.0, 0.3, 8.0)), ((-0.3, 1.0, 9.0), (0.3, 3.0, 11.0))])
        result = compare.compare_shapes(tris, tris.copy(), 12.0)
        for name in ("top", "side", "front"):
            self.assertEqual(result.views[name].iou, 1.0, name)
            self.assertEqual(result.views[name].iou_unshifted, 1.0, name)
        for ratio in result.ratios.values():
            self.assertAlmostEqual(ratio, 1.0, places=9)
        np.testing.assert_array_equal(result.shift_m, [0.0, 0.0, 0.0])

    def test_a_longer_asset_gets_the_known_overlap_and_length_ratio(self) -> None:
        longer = _box((-2.0, -1.0, 0.0), (2.0, 1.0, 14.4))  # 1.2 times the length
        result = compare.compare_shapes(_box(*HULL), longer, 12.0)
        self.assertAlmostEqual(result.views["top"].iou, 12.0 / 14.4, delta=0.01)
        self.assertAlmostEqual(result.views["side"].iou, 12.0 / 14.4, delta=0.01)
        self.assertAlmostEqual(result.views["front"].iou, 1.0, delta=0.005)
        self.assertAlmostEqual(result.ratios["length"], 1.2, places=6)
        self.assertAlmostEqual(result.ratios["width"], 1.0, places=6)

    def test_a_shift_beyond_the_window_leaves_the_rest_as_error(self) -> None:
        moved = _box((-2.0, -1.0, 0.6), (2.0, 1.0, 12.6))  # 5 % of the length; the search reaches 2 %
        result = compare.compare_shapes(_box(*HULL), moved, 12.0)
        self.assertAlmostEqual(float(result.shift_m[2]), -0.24, delta=0.04)
        self.assertAlmostEqual(result.views["top"].iou, (12.0 - 0.36) / (12.0 + 0.36), delta=0.01)
        self.assertGreater(result.views["front"].iou, 0.995)  # the front view does not see the z shift
        self.assertLess(result.views["top"].iou_unshifted, result.views["top"].iou)
        self.assertEqual(result.at_limit, (False, False, True))

    def test_a_small_offset_is_recovered_and_reported(self) -> None:
        moved = _box((-1.95, -1.0, 0.12), (2.05, 1.0, 12.12))  # 0.05 m across, 1 % of the length along
        result = compare.compare_shapes(_box(*HULL), moved, 12.0)
        np.testing.assert_allclose(result.shift_m, [-0.05, 0.0, -0.12], atol=0.035)
        for name in ("top", "side", "front"):
            self.assertGreater(result.views[name].iou, 0.98, name)

    def test_a_missing_part_costs_its_share_of_the_silhouette(self) -> None:
        pod = ((-2.0, 1.0, 4.0), (2.0, 3.0, 8.0))  # on top of the hull: 4 x 4 in plan, 2 high
        result = compare.compare_shapes(_boxes([HULL, pod]), _box(*HULL), 12.0)
        self.assertAlmostEqual(result.views["top"].iou, 1.0, delta=0.01)  # the pod hides in the hull's plan
        self.assertAlmostEqual(result.views["side"].iou, 24.0 / 32.0, delta=0.02)
        self.assertAlmostEqual(result.views["front"].iou, 8.0 / 16.0, delta=0.02)
        self.assertAlmostEqual(result.ratios["height"], 2.0 / 4.0, delta=0.01)

    def test_the_search_window_is_two_percent_of_the_length_per_axis(self) -> None:
        self.assertEqual(compare.SHIFT_FRACTION, 0.02)
        self.assertLessEqual(compare.PIXEL_FRACTION, 0.005)

    def test_the_pixel_cannot_be_coarser_than_half_a_percent(self) -> None:
        with self.assertRaisesRegex(ValueError, "pixel"):
            compare.compare_shapes(_box(*HULL), _box(*HULL), 12.0, pixel_fraction=0.01)

    def test_the_hint_comes_from_the_silhouettes_not_the_box_centres(self) -> None:
        # The asset is 1 m too high (8 % of the length) and carries a mast the model lacks, which moves its box centre to 3 m.
        asset = _boxes([((-2.0, 0.0, 0.0), (2.0, 2.0, 12.0)), ((-0.1, 2.0, 5.0), (0.1, 6.0, 5.2))])
        gap, best, unmoved = compare.suggest_offset(_box(*HULL), asset, 12.0)
        self.assertAlmostEqual(float(gap[1]), -1.0, delta=0.13)  # the asset must come down; the model's offset is minus that
        self.assertAlmostEqual(float(gap[0]), 0.0, delta=0.13)
        self.assertEqual(float(gap[2]), 0.0)
        self.assertGreater(best, unmoved + 0.1)


@needs_pillow
class SplatCheckTests(TmpCase):
    """The splats against their own mesh: coverage of the mesh silhouette and precision within a one-spacing band, and the
    calibration of how a perfect copy reads."""

    WING = ((-20.0, -0.3, 10.0), (20.0, 0.3, 25.0))  # 0.6 m thick: two splat spacings at 0.31 m
    HULL_40 = ((-3.0, -2.0, 0.0), (3.0, 2.0, 40.0))

    def check(self, mesh: np.ndarray, splats: "compare.SplatSet", length: float, spacing: float) -> "compare.SplatCheck":
        return compare.check_splats(mesh, splats, length, spacing, "test")

    def passes(self, check: "compare.SplatCheck") -> bool:
        return not compare.judge_splats({n: v.coverage for n, v in check.views.items()}, {n: v.precision for n, v in check.views.items()})

    def test_the_lattice_of_a_box_matches_its_mesh_in_all_views(self) -> None:
        check = self.check(_box(*HULL), compare.splat_set(*lattice_splats([HULL])), 12.0, SPACING)
        for name in ("top", "side", "front"):
            self.assertGreater(check.views[name].coverage, 0.99, name)
            self.assertGreater(check.views[name].precision, 0.99, name)

    def test_sampled_splats_of_a_box_pass_both_numbers_with_margin(self) -> None:
        # Pinned from measurement (a 46 x 18 x 70 m box, the Narn's size): coverage 0.998 to 1.000, precision 1.000.
        tris = _box((-23.0, -9.0, 0.0), (23.0, 9.0, 70.0))
        for spacing in (0.31, 0.5):
            check = self.check(tris, sampled_splats(tris, spacing), 70.0, spacing)
            for name, v in check.views.items():
                self.assertGreater(v.coverage, 0.99, (spacing, name))
                self.assertGreater(v.precision, 0.99, (spacing, name))
            self.assertTrue(self.passes(check))

    def test_sampled_splats_of_a_thin_wing_pass_both_numbers_where_plain_overlap_did_not(self) -> None:
        # A hull with a 0.6 m wing, two splats thick at 0.31 m: the splats reach about 0.75 spacings past each edge, so a
        # plain overlap of a perfect copy read 0.77 in front (0.70 at 0.5 m). Within a one-spacing band it is faithful.
        tris = _boxes([self.HULL_40, self.WING])
        for spacing, floor in ((0.31, 0.985), (0.5, 0.96)):  # measured coverage 0.994 and 0.977 at worst, precision 1.000
            check = self.check(tris, sampled_splats(tris, spacing), 40.0, spacing)
            for name, v in check.views.items():
                self.assertGreater(v.coverage, floor, (spacing, name))
                self.assertGreater(v.precision, 0.99, (spacing, name))
            self.assertTrue(self.passes(check))
            self.assertLess(check.views["front"].iou, 0.85 if spacing == 0.31 else 0.75)  # what plain IoU said, kept for the record

    def test_a_part_removed_from_the_splats_fails_coverage(self) -> None:
        tris = _boxes([self.HULL_40, self.WING])
        check = self.check(tris, sampled_splats(_box(*self.HULL_40), 0.31), 40.0, 0.31)
        self.assertLess(check.views["top"].coverage, 0.5)  # the wing is most of the plan
        self.assertLess(check.views["front"].coverage, 0.95)
        self.assertGreater(check.views["top"].precision, 0.99)  # what is there is where it should be
        self.assertFalse(self.passes(check))
        self.assertTrue(any("coverage" in f for f in compare.judge_splats({n: v.coverage for n, v in check.views.items()}, {n: v.precision for n, v in check.views.items()})))

    def test_a_part_shifted_by_several_spacings_fails_banded_precision(self) -> None:
        spacing = 0.31
        tris = _boxes([self.HULL_40, self.WING])
        shifted = lambda n: _boxes([self.HULL_40, ((-20.0, -0.3, 10.0 + n * spacing), (20.0, 0.3, 25.0 + n * spacing))])  # noqa: E731
        far = self.check(tris, sampled_splats(shifted(8), spacing), 40.0, spacing)
        self.assertLess(far.views["top"].precision, 0.95)
        self.assertFalse(self.passes(far))
        self.assertTrue(any("precision" in f for f in compare.judge_splats({n: v.coverage for n, v in far.views.items()}, {n: v.precision for n, v in far.views.items()})))
        near = self.check(tris, sampled_splats(shifted(3), spacing), 40.0, spacing)  # a few spacings of slack is the band's job
        self.assertTrue(self.passes(near))

    def test_a_one_spacing_edge_fringe_passes_and_a_wide_one_does_not(self) -> None:
        spacing = 0.31
        tris = _box((-23.0, -9.0, 0.0), (23.0, 9.0, 70.0))

        def grown(by: float) -> "compare.SplatSet":
            g = by * spacing
            return sampled_splats(_box((-23.0 - g, -9.0 - g, -g), (23.0 + g, 9.0 + g, 70.0 + g)), spacing)

        # Splats of a box grown by a spacing reach 1.75 spacings past the mesh: about the band and a fraction more.
        for name, v in self.check(tris, grown(1.0), 70.0, spacing).views.items():
            self.assertGreater(v.precision, 0.95, name)
            self.assertGreater(v.coverage, 0.99, name)
        wide = self.check(tris, grown(3.0), 70.0, spacing)
        self.assertFalse(self.passes(wide))
        self.assertTrue(all(v.coverage > 0.99 for v in wide.views.values()))  # nothing missing, only too wide

    def test_a_lattice_fringe_of_about_a_spacing_passes_and_two_spacings_more_fails(self) -> None:
        def fringe(spacings: float) -> "compare.SplatCheck":
            lo = tuple(np.array(HULL[0]) - spacings * SPACING)
            hi = tuple(np.array(HULL[1]) + spacings * SPACING)
            return self.check(_box(*HULL), compare.splat_set(*lattice_splats([(lo, hi)])), 12.0, SPACING)

        self.assertTrue(self.passes(fringe(0.7)))  # the lattice disc reaches 0.22 spacings past its grown edge: 0.92 in all
        self.assertFalse(self.passes(fringe(2.0)))

    def test_the_band_is_one_spacing_rounded_up_to_whole_pixels(self) -> None:
        check = self.check(_box(*HULL), compare.splat_set(*lattice_splats([HULL])), 12.0, SPACING)  # pixel 0.03 m
        self.assertEqual(check.views["top"].band_px, 3.0)  # 0.08 / 0.03 = 2.67
        check = self.check(_box(*HULL), compare.splat_set(*lattice_splats([HULL])), 12.0, 0.01)
        self.assertEqual(check.views["top"].band_px, 1.0)  # never under a pixel

    def test_a_zero_spacing_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "spacing"):
            self.check(_box(*HULL), compare.splat_set(*lattice_splats([HULL])), 12.0, 0.0)

    def test_dilate_grows_a_pixel_into_a_disc_without_wrapping(self) -> None:
        mask = np.zeros((21, 21), dtype=bool)
        mask[10, 10] = True
        for r, count in ((1, 5), (2, 13), (3, 29)):
            grown = compare.dilate(mask, r)
            self.assertEqual(int(grown.sum()), count, r)
            self.assertTrue(grown[10, 10 + r] and not grown[10, 10 + r + 1])
        edge = np.zeros((9, 9), dtype=bool)
        edge[0, 0] = True
        grown = compare.dilate(edge, 2)
        self.assertEqual(int(grown.sum()), 6)  # the quarter disc inside the grid: (0,0) (0,1) (0,2) (1,0) (1,1) (2,0)
        self.assertFalse(grown[8, 8] or grown[0, 8] or grown[8, 0])

    def test_the_spacing_comes_from_the_manifest_sampling_or_the_splat_scales(self) -> None:
        splats = compare.splat_set(np.zeros((5, 3)), np.tile([0.31, 0.31, 0.025], (5, 1)))
        spacing, source = compare.splat_spacing({"sampling": {"spacing_m": 0.4, "overlap": 1.0}}, splats)
        self.assertEqual((spacing, source), (0.4, "manifest sampling.spacing_m"))
        spacing, source = compare.splat_spacing({}, splats)
        self.assertAlmostEqual(spacing, 0.31, places=6)
        self.assertIn("derived", source)
        spacing, source = compare.splat_spacing({"sampling": {"overlap": 1.4}}, splats)  # sampling present, spacing missing
        self.assertAlmostEqual(spacing, 0.31 / 1.4, places=6)
        self.assertIn("derived", source)
        spacing, source = compare.splat_spacing({"sampling": {"spacing_m": "wide"}}, splats)
        self.assertIn("derived", source)

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
class PlacementTests(unittest.TestCase):
    def test_the_part_scale_keeps_the_boxes_centre_and_start(self) -> None:
        tris = _box((2.0, 3.0, 5.0), (6.0, 5.0, 15.0))  # centre (4, 4), starts at z = 5
        scaled = compare.scale_about_part(tris, np.array([2.0, 1.5, 0.5]))
        lo, hi = scaled.reshape(-1, 3).min(axis=0), scaled.reshape(-1, 3).max(axis=0)
        np.testing.assert_allclose(lo, [0.0, 2.5, 5.0])
        np.testing.assert_allclose(hi, [8.0, 5.5, 10.0])

    def test_a_part_is_moved_in_x_and_y_onto_the_model_partss_box_centre(self) -> None:
        model = _box((-2.0, -1.0, 0.0), (2.0, 1.0, 6.0))
        asset = _box((-1.0, 3.0, 0.0), (5.0, 5.0, 6.0))  # centre (2, 4)
        np.testing.assert_allclose(compare.part_alignment(model, asset), [-2.0, -4.0, 0.0])

    def test_a_pod_is_turned_up_onto_up_and_forward_onto_forward(self) -> None:
        r = compare.pod_rotation(np.array([0.0, 1.0, 0.0]), np.array([1.0, 0.0, 0.0]))
        np.testing.assert_allclose(r @ [0.0, 0.0, -1.0], [1.0, 0.0, 0.0], atol=1e-12)
        np.testing.assert_allclose(r @ [0.0, 1.0, 0.0], [0.0, 1.0, 0.0], atol=1e-12)
        self.assertAlmostEqual(float(np.linalg.det(r)), 1.0)
        tilted = compare.pod_rotation(np.array([1.0, 1.0, 0.0]), np.array([0.0, 0.0, 1.0]))
        np.testing.assert_allclose(tilted @ [0.0, 1.0, 0.0], np.array([1.0, 1.0, 0.0]) / np.sqrt(2.0), atol=1e-12)
        np.testing.assert_allclose(tilted @ [0.0, 0.0, -1.0], [0.0, 0.0, 1.0], atol=1e-12)
        np.testing.assert_allclose(compare.pod_rotation(np.array([0.0, 1.0, 0.0])), np.eye(3), atol=1e-12)  # no forward: the shortest turn
        np.testing.assert_allclose(compare.pod_rotation(np.array([0.0, 1.0, 0.0]), np.array([0.0, 1.0, 0.0])), np.eye(3), atol=1e-12)


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

    def test_the_splat_bars_are_95_percent_and_inclusive(self) -> None:
        self.assertEqual((compare.SPLAT_COVERAGE_MIN, compare.SPLAT_PRECISION_MIN), (0.95, 0.95))
        ok = {"top": 0.99, "side": 0.95, "front": 1.0}
        self.assertEqual(compare.judge_splats(ok, ok), [])
        failures = compare.judge_splats({**ok, "side": 0.9499}, ok)
        self.assertEqual(len(failures), 1)
        self.assertIn("side coverage", failures[0])
        failures = compare.judge_splats(ok, {**ok, "front": 0.9499})
        self.assertEqual(len(failures), 1)
        self.assertIn("front precision", failures[0])
        self.assertEqual(len(compare.judge_splats({"top": 0.2, "side": 0.2, "front": 0.2}, {"top": 0.2, "side": 0.99, "front": 0.99})), 4)


@needs_pillow
class MainTests(TmpCase):
    def test_identical_shapes_pass_both_checks_with_exit_zero_and_write_the_report(self) -> None:
        code, out, err = self.compare(self.stl(_box(*HULL)), self.asset([HULL]))
        self.assertEqual(code, 0, out + err)
        lines = out.strip().splitlines()
        for view in ("top", "side", "front"):
            self.assertEqual(sum(1 for line in lines if line.startswith(view)), 1, out)  # the geometry lines
            self.assertEqual(sum(1 for line in lines if line.startswith(f"splats {view}")), 1, out)
        self.assertIn("geometry verdict: PASS", out)
        self.assertIn("splats verdict: PASS", out)
        self.assertEqual(lines[-1], "verdict: PASS")
        for name in ("overlay_top.png", "overlay_side.png", "overlay_front.png", "splats_top.png", "splats_side.png", "splats_front.png", "fidelity.json"):
            self.assertTrue((self.dir / "out" / name).is_file(), name)
        report = self.report()
        self.assertEqual(report["verdict"], "pass")
        self.assertEqual(report["basis"], "mesh")
        self.assertEqual((report["geometry"]["verdict"], report["splat_check"]["verdict"]), ("pass", "pass"))
        self.assertEqual(
            report["thresholds"],
            {"iou_min": 0.9, "dimension_tolerance": 0.1, "shift_fraction": 0.02, "splat_coverage_min": 0.95, "splat_precision_min": 0.95},
        )
        self.assertEqual(sorted(report["views"]), ["front", "side", "top"])
        splat_check = report["splat_check"]
        self.assertEqual(sorted(splat_check["views"]), ["front", "side", "top"])
        for v in splat_check["views"].values():  # both numbers per view, in the report and (below) in the console line
            self.assertGreater(v["coverage"], 0.99)
            self.assertGreater(v["precision"], 0.99)
        self.assertEqual((splat_check["coverage_min"], splat_check["precision_min"]), (0.95, 0.95))
        self.assertIn("derived", splat_check["spacing_source"])  # these synthetic manifests carry no sampling entry
        self.assertGreater(splat_check["spacing_m"], 0.0)
        splat_lines = [line for line in lines if line.startswith("splats top")]
        self.assertRegex(splat_lines[0], r"coverage 1\.000 ok\s+precision 1\.000 ok")
        self.assertTrue(any("band one spacing" in line and "derived" in line for line in lines))
        self.assertEqual(sorted(report["dimensions"]), ["height", "length", "width"])
        self.assertLessEqual(report["pixel_m"], 0.005 * 12.0)
        self.assertEqual(len(report["shift_m"]), 3)
        top = report["views"]["top"]
        self.assertEqual(top["iou"], 1.0)  # the mesh is the STL
        self.assertEqual(top["both_px"] + top["model_only_px"], top["model_px"])
        self.assertEqual(top["both_px"] + top["asset_only_px"], top["asset_px"])

    def test_the_band_uses_the_manifest_sampling_spacing_when_there_is_one(self) -> None:
        folder = self.asset([HULL])
        manifest = json.loads((folder / "manifest.json").read_text())
        manifest["sampling"] = {"spacing_m": 0.5, "overlap": 1.0, "thickness": 0.08}
        (folder / "manifest.json").write_text(json.dumps(manifest))
        code, out, _ = self.compare(self.stl(_box(*HULL)), folder)
        self.assertEqual(code, 0, out)
        check = self.report()["splat_check"]
        self.assertEqual((check["spacing_m"], check["spacing_source"]), (0.5, "manifest sampling.spacing_m"))
        self.assertEqual(check["band_px"], 17.0)  # 0.5 / 0.03 = 16.7 pixels, rounded up
        self.assertIn("0.500 m (manifest sampling.spacing_m)", out)

    def test_the_overlay_marks_model_only_asset_only_and_both_in_three_colours(self) -> None:
        from PIL import Image

        model = _boxes([HULL, ((-2.0, -1.0, 12.0), (2.0, 1.0, 14.0))])  # a tail the asset lacks
        fin = ((-3.0, -0.5, 4.0), (-2.0, 0.5, 8.0))  # a part the model lacks
        code, _, _ = self.compare(self.stl(model), self.asset([HULL, fin]), length=14.0)
        self.assertEqual(code, 1)
        for name in ("overlay_top.png", "splats_top.png"):
            arr = np.asarray(Image.open(self.dir / "out" / name).convert("RGB"))
            for colour in (compare.MODEL_ONLY, compare.ASSET_ONLY, compare.BOTH):
                self.assertGreater(int((arr == np.array(colour)).all(axis=2).sum()), 20, (name, colour))
        top = self.report()["views"]["top"]
        self.assertGreater(top["model_only_px"], 0)
        self.assertGreater(top["asset_only_px"], 0)

    def test_a_dimension_off_by_more_than_ten_percent_exits_one_even_with_a_good_overlap(self) -> None:
        # A thin mast makes the model 1.12 times longer; the silhouettes still overlap by about 99 %.
        mast = ((-0.05, -0.05, 12.0), (0.05, 0.05, 13.44))
        code, out, _ = self.compare(self.stl(_boxes([HULL, mast])), self.asset([HULL]), length=13.44)
        self.assertEqual(code, 1, out)
        report = self.report()
        self.assertGreater(report["views"]["top"]["iou"], 0.95)
        self.assertLess(report["dimensions"]["length"]["ratio"], 0.9)
        self.assertTrue(any("length" in f for f in report["failures"]))
        self.assertEqual(report["geometry"]["verdict"], "fail")
        self.assertEqual(report["splat_check"]["verdict"], "fail" if report["splat_check"]["failures"] else "pass")
        self.assertIn("FAIL", out.strip().splitlines()[-1])

    def test_an_undersized_part_fails_the_geometry_check_while_the_splats_agree_with_the_mesh(self) -> None:
        # The STL has a wing 16 m across; the asset's wing, mesh and splats alike, is 60 % of that.
        wing, small = ((-8.0, -0.3, 3.0), (8.0, 0.3, 9.0)), ((-4.8, -0.3, 3.0), (4.8, 0.3, 9.0))
        code, out, _ = self.compare(self.stl(_boxes([HULL, wing])), self.asset([HULL, small]))
        self.assertEqual(code, 1, out)
        report = self.report()
        self.assertEqual(report["geometry"]["verdict"], "fail")
        self.assertEqual(report["splat_check"]["verdict"], "pass")
        self.assertLess(report["dimensions"]["width"]["ratio"], 0.7)
        self.assertLess(report["views"]["top"]["iou"], 0.9)
        self.assertIn("geometry verdict: FAIL", out)
        self.assertIn("splats verdict: PASS", out)

    def test_splats_that_do_not_follow_their_mesh_fail_the_splat_check_alone(self) -> None:
        # The mesh is the model, so the geometry passes; the splats put the wing three metres aft of it.
        wing, moved = ((-6.0, -0.5, 1.0), (6.0, 0.5, 4.0)), ((-6.0, -0.5, 7.0), (6.0, 0.5, 10.0))
        code, out, _ = self.compare(self.stl(_boxes([HULL, wing])), self.asset([HULL, moved], mesh_boxes=[HULL, wing]))
        self.assertEqual(code, 1, out)
        report = self.report()
        self.assertEqual(report["geometry"]["verdict"], "pass")
        self.assertEqual(report["splat_check"]["verdict"], "fail")
        self.assertIn("geometry verdict: PASS", out)
        self.assertIn("splats verdict: FAIL", out)

    def test_an_overlap_under_the_bar_exits_one_with_the_right_dimensions(self) -> None:
        # The asset has the model's length, width and height but its middle third is half as wide.
        narrow = [((-2.0, -1.0, 0.0), (2.0, 1.0, 4.0)), ((-1.0, -1.0, 4.0), (1.0, 1.0, 8.0)), ((-2.0, -1.0, 8.0), (2.0, 1.0, 12.0))]
        code, out, _ = self.compare(self.stl(_box(*HULL)), self.asset(narrow))
        self.assertEqual(code, 1, out)
        report = self.report()
        self.assertAlmostEqual(report["views"]["top"]["iou"], 10.0 / 12.0, delta=0.02)
        self.assertGreater(report["views"]["front"]["iou"], 0.98)
        for d in report["dimensions"].values():
            self.assertAlmostEqual(d["ratio"], 1.0, delta=0.01)

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
        model = _boxes([front_part, rear_part])
        both = self.asset([front_part, rear_part], asset_id="both")
        # The rear part of both sides, each cropped by its own range.
        code, out, _ = self.compare(self.stl(model), both, "--model-zrange", "6", "12", "--asset-zrange", "6", "12")
        self.assertEqual(code, 0, out)
        self.assertAlmostEqual(self.report()["dimensions"]["width"]["model_m"], 2.0, places=2)
        # The model's rear part against an asset made of that part alone, which starts at its own z = 0.
        alone = self.asset([((-1.0, -0.5, 0.2), (1.0, 0.5, 6.0))], asset_id="alone")
        code, out, _ = self.compare(self.stl(model), alone, "--model-zrange", "6", "12")
        self.assertEqual(code, 0, out)
        self.assertAlmostEqual(self.report()["dimensions"]["length"]["asset_m"], 5.8, delta=0.01)
        # The front part against the wrong crop of the asset (its rear part): the widths differ by a factor of two.
        code, out, _ = self.compare(self.stl(model), both, "--model-zrange", "0", "6", "--asset-zrange", "6", "12")
        self.assertEqual(code, 1, out)
        self.assertAlmostEqual(self.report()["dimensions"]["width"]["ratio"], 0.5, delta=0.01)

    def test_a_cropped_part_is_aligned_on_its_own_and_scored_on_shape(self) -> None:
        # The asset's pod group sits 4 m higher than the model's, by design (the Saturn 3's raised stack).
        lead = ((-2.0, -1.0, 0.0), (2.0, 1.0, 5.8))
        model = _boxes([lead, ((-3.0, -1.0, 6.2), (3.0, 1.0, 12.0))])
        raised = ((-3.0, 3.0, 6.2), (3.0, 5.0, 12.0))
        asset = self.asset([lead, raised], asset_id="raised")
        code, out, _ = self.compare(self.stl(model), asset)
        self.assertEqual(code, 1, out)  # the whole ship does not forgive a 4 m rise
        code, out, _ = self.compare(self.stl(model), asset, "--model-zrange", "6", "12", "--asset-zrange", "6", "12", "--part", "pods")
        self.assertEqual(code, 0, out)
        report = json.loads((self.dir / "out" / "pods" / "fidelity.json").read_text())
        np.testing.assert_allclose(report["part_align_m"], [0.0, -4.0, 0.0], atol=0.01)
        self.assertIn("align  part moved (+0.00, -4.00, +0.00)", out)
        # A part of another shape is still caught after the alignment: the asset's pods are half as wide.
        narrow = self.asset([lead, ((-1.5, 3.0, 6.2), (1.5, 5.0, 12.0))], asset_id="narrow")
        code, out, _ = self.compare(self.stl(model), narrow, "--model-zrange", "6", "12", "--asset-zrange", "6", "12", "--part", "pods")
        self.assertEqual(code, 1, out)

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
        # A generator that authors y from an axis 1 m above the model's box centre (the Saturns' spine axis is 2 to 3 %
        # of their length above theirs; here 8 %, beyond the 2 % shift window but inside the hint's 10 %).
        raised = ((-2.0, 0.0, 0.0), (2.0, 2.0, 12.0))
        asset = self.asset([raised])
        code, out, _ = self.compare(self.stl(_box(*HULL)), asset)
        self.assertEqual(code, 1, out)
        report = self.report()
        self.assertEqual(len(report["shift_at_limit"]), 3)
        np.testing.assert_allclose(report["suggested_model_offset_m"], [0.0, 1.0, 0.0], atol=0.13)
        suggested = ",".join(f"{v:.2f}" for v in report["suggested_model_offset_m"])
        self.assertIn(f"--model-offset {suggested}", out)  # the hint names the value to pass
        code, out, _ = self.compare(self.stl(_box(*HULL)), asset, "--model-offset", "0,1,0")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.report()["model"]["offset_m"], [0.0, 1.0, 0.0])
        self.assertIsNone(self.report()["suggested_model_offset_m"])
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
        model = _boxes([thin] + [(placed[i], placed[i + 1]) for i in range(0, len(placed), 2)])
        hull_dir = self.asset([thin], asset_id="bokmai", offset=tuple(offset))
        (hull_dir / "hardpoints.json").write_text(
            json.dumps({"cargo_pods": [{"name": f"pod_{i}", "position": list(m), "up": [0, 1, 0]} for i, m in enumerate(mounts)]})
        )
        pod_ply, pod_obj = self.pod(pod)

        code, out, _ = self.compare(self.stl(model), hull_dir, "--pod-ply", pod_ply, "--pods-from-hardpoints")  # the mesh beside the splats
        self.assertEqual(code, 0, out)
        self.assertGreater(self.report()["views"]["top"]["iou"], 0.99)
        self.assertEqual(self.report()["asset"]["extra_parts"], 3)
        self.assertEqual(self.report()["splat_check"]["verdict"], "pass")
        # The pod files beside the asset (<id>_pod.ply and <id>_pod.obj) are the default.
        shutil.copy(pod_ply, hull_dir / "bokmai_pod.ply")
        shutil.copy(pod_obj, hull_dir / "bokmai_pod.obj")
        code, out, _ = self.compare(self.stl(model), hull_dir, "--pods-from-hardpoints")
        self.assertEqual(code, 0, out)
        # The same mounts given on the command line, the two files named.
        argv = ["--pod-ply", pod_ply, "--pod-obj", pod_obj] + [a for m in mounts for a in ("--pod-at", ",".join(str(v) for v in m))]
        code, out, _ = self.compare(self.stl(model), hull_dir, *argv)
        self.assertEqual(code, 0, out)
        # Without the pods the hull alone misses them.
        code, out, _ = self.compare(self.stl(model), hull_dir)
        self.assertEqual(code, 1, out)
        self.assertLess(self.report()["views"]["top"]["iou"], 0.9)

    def test_a_pod_follows_its_up_vector(self) -> None:
        # A pod taller above its origin than below, one mounted up on the top and one hanging down from the belly.
        pod_ply, _ = self.pod(((-0.5, -0.5, -1.0), (0.5, 3.5, 1.0)))
        model = _boxes([HULL, ((-0.5, 0.5, 2.0), (0.5, 4.5, 4.0)), ((-0.5, -4.5, 8.0), (0.5, -0.5, 10.0))])

        def score(up_down: list[int]) -> int:
            hull_dir = self.asset([HULL], asset_id="ship")
            pods = [{"name": "a", "position": [0.0, 1.0, 3.0], "up": [0, 1, 0]}, {"name": "b", "position": [0.0, -1.0, 9.0], "up": up_down}]
            (hull_dir / "hardpoints.json").write_text(json.dumps({"cargo_pods": pods}))
            return self.compare(self.stl(model), hull_dir, "--pod-ply", pod_ply, "--pods-from-hardpoints")[0]

        self.assertEqual(score([0, -1, 0]), 0)
        self.assertEqual(score([0, 1, 0]), 1)  # the same pod standing on the belly instead

    def test_a_pod_follows_its_forward_vector(self) -> None:
        # A pod that is not fore-aft symmetric (3 m behind its origin, 1 m ahead of it), mounted facing aft. A keel under
        # the hull keeps the model's box centred in y, as the asset's authored frame is.
        pod_ply, _ = self.pod(((-0.5, -0.5, -1.0), (0.5, 0.5, 3.0)))
        keel = ((-0.5, -2.0, 4.0), (0.5, -1.0, 8.0))
        model = _boxes([HULL, keel, ((-0.5, 1.0, 4.0), (0.5, 2.0, 8.0))])  # the pod: 3 m ahead of z = 7, 1 m behind it

        def score(forward: list[float] | None) -> int:
            hull_dir = self.asset([HULL, keel], asset_id="ship")
            pod = {"name": "a", "position": [0.0, 1.5, 7.0], "up": [0, 1, 0]}
            if forward is not None:
                pod["forward"] = forward
            (hull_dir / "hardpoints.json").write_text(json.dumps({"cargo_pods": [pod]}))
            return self.compare(self.stl(model), hull_dir, "--pod-ply", pod_ply, "--pods-from-hardpoints")[0]

        self.assertEqual(score([0, 0, 1]), 0)  # facing aft: its long side runs forward of the mount
        self.assertEqual(score(None), 1)  # no forward given: the pod keeps its own orientation

    def test_it_runs_as_a_script_in_isolated_mode(self) -> None:
        # The documented command line: `python3 -I tools/refview/compare.py`, where the repo root is not on the path.
        argv = [sys.executable, "-I", str(Path(compare.__file__)), str(self.stl(_box(*HULL))), str(self.asset([HULL])), "--length", "12", "--out", str(self.dir / "out")]
        done = subprocess.run(argv, capture_output=True, text=True, cwd=self.dir, check=False)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("verdict: PASS", done.stdout)

    def test_malformed_data_is_bad_input_not_a_crash(self) -> None:
        good_stl = self.stl(_box(*HULL))
        folder = self.asset([HULL], asset_id="bad")
        (folder / "hardpoints.json").write_text(json.dumps({"cargo_pods": [{"name": "no position"}]}))  # KeyError inside
        pod_ply, _ = self.pod(((-0.5, -0.5, -1.0), (0.5, 0.5, 1.0)))
        code, _, err = run([str(good_stl), str(folder), "--length", "12", "--pod-ply", pod_ply, "--pods-from-hardpoints", "--out", str(self.dir / "out")])
        self.assertEqual((code, "cargo_pods" in err, "KeyError" in err), (2, True, True), err)
        (folder / "hardpoints.json").write_text(json.dumps({"cargo_pods": [{"position": [0, 0, 0], "up": "high"}]}))  # a string for a vector
        code, _, err = run([str(good_stl), str(folder), "--length", "12", "--pod-ply", pod_ply, "--pods-from-hardpoints", "--out", str(self.dir / "out")])
        self.assertEqual(code, 2, err)
        # Any other KeyError, IndexError or TypeError out of the readers is reported the same way.
        for exc in (KeyError("lods"), IndexError("list index out of range"), TypeError("not subscriptable")):
            with self.subTest(exc=type(exc).__name__), mock.patch.object(compare, "load_asset_mesh", side_effect=exc):
                code, _, err = run([str(good_stl), str(folder), "--length", "12", "--out", str(self.dir / "out")])
                self.assertEqual(code, 2, err)
                self.assertIn(type(exc).__name__, err)

    def test_bad_input_exits_two_with_a_message(self) -> None:
        good_stl, good_asset = self.stl(_box(*HULL)), self.asset([HULL])
        empty = self.dir / "empty.stl"
        empty.write_bytes(b"")
        bare = self.dir / "bare"
        bare.mkdir()
        broken = self.dir / "broken"
        broken.mkdir()
        (broken / "manifest.json").write_text("{not json")
        no_mesh = self.asset([HULL], asset_id="nomesh")
        (no_mesh / "nomesh.obj").unlink()
        bad_mesh = self.asset([HULL], asset_id="badmesh")
        (bad_mesh / "badmesh.obj").write_text("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 99\n")
        cases = {
            "missing stl": ([str(self.dir / "nope.stl"), str(good_asset)], "nope.stl"),
            "empty stl": ([str(empty), str(good_asset)], "no triangles"),
            "missing asset": ([str(good_stl), str(self.dir / "ghost")], "ghost"),
            "no manifest": ([str(good_stl), str(bare)], "manifest"),
            "broken manifest": ([str(good_stl), str(broken)], "manifest"),
            "no fallback mesh": ([str(good_stl), str(no_mesh)], "fallback mesh"),
            "a mesh face past the vertices": ([str(good_stl), str(bad_mesh)], "fallback mesh"),
            "mirrored mapping": ([str(good_stl), str(good_asset), "--right=+x", "--up=+z", "--aft=+y"], "mirrors"),
            "empty model crop": ([str(good_stl), str(good_asset), "--model-zrange", "50", "60"], "model"),
            "empty asset crop": ([str(good_stl), str(good_asset), "--asset-zrange", "50", "60"], "asset"),
            "backwards crop": ([str(good_stl), str(good_asset), "--model-zrange", "6", "2"], "zrange"),
            "coarse pixel": ([str(good_stl), str(good_asset), "--pixel-frac", "0.02"], "pixel"),
            "missing pod file": ([str(good_stl), str(good_asset), "--pod-ply", str(self.dir / "no.ply"), "--pod-at", "0,0,0"], "no.ply"),
            "bad model offset": ([str(good_stl), str(good_asset), "--model-offset", "1,2"], "x,y,z"),
            "pods without a file": ([str(good_stl), str(good_asset), "--pod-at", "0,0,0"], "pod-ply"),
            "a pod file without mounts": ([str(good_stl), str(good_asset), "--pod-ply", str(self.dir / "no.ply")], "mounts"),
        }
        for label, (argv, needle) in cases.items():
            with self.subTest(label):
                code, _, err = run(argv + ["--length", "12", "--out", str(self.dir / "out")])
                self.assertEqual(code, 2, err)
                self.assertIn(needle, err)


@unittest.skipUnless((REPO_ROOT / "assets" / "generated" / "raider_fighter" / "manifest.json").is_file(), "needs the built raider_fighter")
@needs_pillow
class BuiltAssetTests(unittest.TestCase):
    """The frame of a real generator's output: a built raider's fallback mesh and splats."""

    def setUp(self) -> None:
        self.dir = REPO_ROOT / "assets" / "generated" / "raider_fighter"
        self.offset = np.asarray(json.loads((self.dir / "manifest.json").read_text())["centroid_offset"])

    def test_the_obj_is_in_the_centred_godot_frame_and_the_offset_gives_the_authored_frame(self) -> None:
        obj = compare.read_obj(self.dir / "raider_fighter.obj")
        centred = obj.vertices[obj.faces]
        mesh = compare.load_asset_mesh(self.dir)
        # Authored: the nose tip at z = 0 and x symmetric. As written the OBJ is centred on the splat centroid instead.
        self.assertLess(abs(float(mesh[..., 2].min())), 0.05)
        self.assertLess(float(centred[..., 2].min()), -1.0)
        self.assertLess(abs(float(mesh[..., 0].min() + mesh[..., 0].max())), 1e-3)
        np.testing.assert_allclose(mesh, centred + self.offset, atol=1e-9)

    def test_the_built_splats_follow_their_own_mesh_in_the_same_frame(self) -> None:
        mesh, splats = compare.load_asset_mesh(self.dir), compare.load_asset_splats(self.dir)
        lo, hi = splats.bounds()
        self.assertLess(abs(float(lo[2] - mesh[..., 2].min())), 0.5)
        self.assertLess(abs(float(hi[2] - mesh[..., 2].max())), 0.5)
        spacing, source = compare.splat_spacing(json.loads((self.dir / "manifest.json").read_text()), splats)
        self.assertEqual(source, "manifest sampling.spacing_m")
        length = float(np.ptp(mesh[..., 2]))
        check = compare.check_splats(mesh, splats, length, spacing, source)
        for name, v in check.views.items():
            self.assertGreater(v.coverage, 0.93, name)  # 0.997 / 0.952 / 0.992: the wings are 0.1 to 0.35 m, a few spacings thick
            self.assertGreater(v.precision, 0.99, name)
        # With the splats left in the centred frame (the offset not added back) they miss the mesh by half the ship.
        lost = compare.check_splats(mesh, compare.SplatSet(splats.centres - self.offset, splats.cov), length, spacing, source)
        self.assertLess(lost.views["top"].coverage, 0.7)
        self.assertLess(lost.views["top"].precision, 0.7)


if __name__ == "__main__":
    unittest.main()
