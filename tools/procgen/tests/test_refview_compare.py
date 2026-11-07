"""tools/refview compare (M5-T23; on the textured mesh from M5-T27): the fidelity check of a built asset against its
reference STL, on synthetic shapes (no reference file and no generated asset is needed, except the one test that reads a
built raider when it exists).

The verdict (Q18) scores the asset's mesh (its textured ``.glb``, else its fallback OBJ) against the STL. The calibration
tests pin what the tool reads for a perfect copy: a mesh against itself is 1.0.
"""

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

from tools.procgen.core.glb import GlbPrimitive, write_glb
from tools.procgen.core.manifest import build_manifest, write_manifest

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


def write_obj_triangles(path: Path, tris: np.ndarray) -> None:
    """A minimal OBJ of ``tris`` (vertices as given, one triangle per ``f`` line)."""
    lines = [f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}" for v in tris.reshape(-1, 3)]
    lines += [f"f {3 * i + 1} {3 * i + 2} {3 * i + 3}" for i in range(len(tris))]
    path.write_text("\n".join(lines) + "\n")


def write_glb_triangles(path: Path, tris: np.ndarray) -> None:
    """A one-primitive glb of ``tris``, as ``core/glb.py`` writes a hull."""
    n = len(tris)
    positions = tris.reshape(-1, 3)
    write_glb(path, [GlbPrimitive(positions, np.tile([0.0, 1.0, 0.0], (3 * n, 1)), np.zeros((3 * n, 2)), np.arange(3 * n), "hull")], path.stem)


def write_asset(
    folder: Path,
    asset_id: str,
    mesh_tris: np.ndarray,
    offset: tuple[float, float, float] = (0.0, 0.0, 0.0),
    with_obj: bool = True,
) -> Path:
    """An asset folder written the way a generator does it: the textured mesh ``<id>.glb`` and the fallback ``<id>.obj``
    in the centred Godot frame (authored positions minus ``centroid_offset``) and ``manifest.json`` naming both."""
    folder.mkdir(parents=True, exist_ok=True)
    centred = mesh_tris - np.asarray(offset)
    write_glb_triangles(folder / f"{asset_id}.glb", centred)
    files = {"mesh": f"{asset_id}.glb"}
    if with_obj:
        write_obj_triangles(folder / f"{asset_id}.obj", centred)
        files["obj"] = f"{asset_id}.obj"
    lo, hi = centred.reshape(-1, 3).min(axis=0), centred.reshape(-1, 3).max(axis=0)
    maps = {key: f"{asset_id}_{key}.png" for key in ("albedo", "normal", "orm", "emissive")}
    mesh = {"file": f"{asset_id}.glb", "triangles": len(mesh_tris), "vertices": 3 * len(mesh_tris), "aabb_min": [float(v) for v in lo],
            "aabb_max": [float(v) for v in hi], "texel_m": 0.01, "atlas_px": 64, "mean_albedo": [0.5, 0.5, 0.5],
            "surfaces": [{"name": "hull", "blend": False, "transmittance": 0.0, **maps}], "lods": []}  # fmt: skip
    write_manifest(folder, build_manifest(asset_id, 1, 1, lo, hi, offset, files=files, extra={"mesh": mesh}))
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
        """An asset whose mesh is ``boxes``."""
        return write_asset(self.dir / asset_id, asset_id, _boxes(boxes), **kwargs)

    def pod(self, box: tuple[tuple, tuple], name: str = "pod") -> str:
        """A pod's textured mesh in its own frame; returns its path."""
        (self.dir / name).mkdir(parents=True, exist_ok=True)
        path = self.dir / name / f"{name}.glb"
        write_glb_triangles(path, _box(*box))
        return str(path)

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



@needs_pillow
class AssetFrameTests(TmpCase):
    def test_the_mesh_returns_to_the_authored_frame_unflipped(self) -> None:
        # The mesh is in the centred Godot frame: an off-axis shape must come back where it was authored, unmirrored.
        tris = _boxes([((1.0, 2.0, 10.0), (4.0, 3.0, 30.0))])
        write_asset(self.dir / "a", "a", tris, offset=(0.0, -0.4468, 38.0806))
        np.testing.assert_allclose(compare.load_asset_mesh(self.dir / "a"), tris, atol=2e-4)  # float32 positions, four-digit offset

    def test_the_glb_and_the_obj_read_the_same(self) -> None:
        tris = _boxes([((1.0, 2.0, 10.0), (4.0, 3.0, 30.0)), ((-2.0, -1.0, 0.0), (2.0, 1.0, 12.0))])
        write_asset(self.dir / "a", "a", tris, offset=(0.0, 0.25, 6.0))
        glb = compare.mesh_from_file(self.dir / "a" / "a.glb", np.zeros(3))
        obj = compare.mesh_from_file(self.dir / "a" / "a.obj", np.zeros(3))
        np.testing.assert_allclose(glb, obj, atol=1e-5)

    def test_the_mesh_file_comes_from_the_mesh_section_then_the_obj(self) -> None:
        folder = self.asset([HULL], asset_id="m")
        manifest = json.loads((folder / "manifest.json").read_text())
        self.assertEqual(compare.asset_mesh_name(manifest), "m.glb")
        (folder / "m.glb").rename(folder / "hull.glb")
        with self.assertRaisesRegex(ValueError, "cannot read the mesh"):
            compare.load_asset_mesh(folder)
        manifest["mesh"]["file"] = "hull.glb"
        (folder / "manifest.json").write_text(json.dumps(manifest))
        self.assertEqual(len(compare.load_asset_mesh(folder)), 12)
        del manifest["mesh"]
        self.assertEqual(compare.asset_mesh_name(manifest), "m.obj")  # an asset without a textured mesh: its OBJ
        self.assertEqual(compare.asset_mesh_name({"asset_id": "x"}), "x.obj")

    def test_an_asset_id_is_looked_up_under_the_generated_folder(self) -> None:
        write_asset(self.dir / "gen" / "ship", "ship", _box(*HULL))
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


@needs_pillow
class MainTests(TmpCase):
    def test_identical_shapes_pass_with_exit_zero_and_write_the_report(self) -> None:
        code, out, err = self.compare(self.stl(_box(*HULL)), self.asset([HULL]))
        self.assertEqual(code, 0, out + err)
        lines = out.strip().splitlines()
        for view in ("top", "side", "front"):
            self.assertEqual(sum(1 for line in lines if line.startswith(view)), 1, out)
        self.assertFalse(any("splat" in line for line in lines), out)
        self.assertEqual(lines[-1], "verdict: PASS")
        self.assertIn("ship.glb", lines[0])
        for name in ("overlay_top.png", "overlay_side.png", "overlay_front.png", "fidelity.json"):
            self.assertTrue((self.dir / "out" / name).is_file(), name)
        self.assertEqual(sorted(p.name for p in (self.dir / "out").iterdir() if p.suffix == ".png"),
                         ["overlay_front.png", "overlay_side.png", "overlay_top.png"])  # fmt: skip
        report = self.report()
        self.assertEqual(report["verdict"], "pass")
        self.assertEqual(report["basis"], "mesh")
        self.assertEqual(report["asset"]["mesh"], "ship.glb")
        self.assertNotIn("splat_check", report)
        self.assertEqual(report["thresholds"], {"iou_min": 0.9, "dimension_tolerance": 0.1, "shift_fraction": 0.02})
        self.assertEqual(sorted(report["views"]), ["front", "side", "top"])
        self.assertEqual(sorted(report["dimensions"]), ["height", "length", "width"])
        self.assertLessEqual(report["pixel_m"], 0.005 * 12.0)
        self.assertEqual(len(report["shift_m"]), 3)
        top = report["views"]["top"]
        self.assertEqual(top["iou"], 1.0)  # the mesh is the STL
        self.assertEqual(top["both_px"] + top["model_only_px"], top["model_px"])
        self.assertEqual(top["both_px"] + top["asset_only_px"], top["asset_px"])

    def test_the_glb_is_scored_not_the_obj(self) -> None:
        # The fallback OBJ is the hull alone; the textured mesh adds a wing the STL has. The verdict follows the glb.
        wing = ((-6.0, -0.3, 3.0), (6.0, 0.3, 9.0))
        folder = self.asset([HULL, wing])
        write_obj_triangles(folder / "ship.obj", _box(*HULL))
        code, out, _ = self.compare(self.stl(_boxes([HULL, wing])), folder)
        self.assertEqual(code, 0, out)

    def test_an_output_folder_that_cannot_be_written_is_bad_input(self) -> None:
        blocker = self.dir / "a_file"
        blocker.write_text("not a folder")
        argv = [str(self.stl(_box(*HULL))), str(self.asset([HULL])), "--length", "12", "--out", str(blocker / "out")]
        code, _, err = run(argv)
        self.assertEqual(code, 2, err)
        self.assertIn("cannot write", err)

    def test_the_overlay_marks_model_only_asset_only_and_both_in_three_colours(self) -> None:
        from PIL import Image

        model = _boxes([HULL, ((-2.0, -1.0, 12.0), (2.0, 1.0, 14.0))])  # a tail the asset lacks
        fin = ((-3.0, -0.5, 4.0), (-2.0, 0.5, 8.0))  # a part the model lacks
        code, _, _ = self.compare(self.stl(model), self.asset([HULL, fin]), length=14.0)
        self.assertEqual(code, 1)
        arr = np.asarray(Image.open(self.dir / "out" / "overlay_top.png").convert("RGB"))
        for colour in (compare.MODEL_ONLY, compare.ASSET_ONLY, compare.BOTH):
            self.assertGreater(int((arr == np.array(colour)).all(axis=2).sum()), 20, colour)
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
        self.assertEqual(report["verdict"], "fail")
        self.assertIn("FAIL", out.strip().splitlines()[-1])

    def test_an_undersized_part_fails(self) -> None:
        # The STL has a wing 16 m across; the asset's is 60 % of that.
        wing, small = ((-8.0, -0.3, 3.0), (8.0, 0.3, 9.0)), ((-4.8, -0.3, 3.0), (4.8, 0.3, 9.0))
        code, out, _ = self.compare(self.stl(_boxes([HULL, wing])), self.asset([HULL, small]))
        self.assertEqual(code, 1, out)
        report = self.report()
        self.assertEqual(report["verdict"], "fail")
        self.assertLess(report["dimensions"]["width"]["ratio"], 0.7)
        self.assertLess(report["views"]["top"]["iou"], 0.9)
        self.assertIn("verdict: FAIL", out)

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
        pod_mesh = self.pod(pod)

        code, out, _ = self.compare(self.stl(model), hull_dir, "--pod-mesh", pod_mesh, "--pods-from-hardpoints")
        self.assertEqual(code, 0, out)
        self.assertGreater(self.report()["views"]["top"]["iou"], 0.99)
        self.assertEqual(self.report()["asset"]["extra_parts"], 3)
        # The asset's own pod (the manifest's pod.mesh.file, else <id>_pod.glb beside it) is the default.
        shutil.copy(pod_mesh, hull_dir / "bokmai_pod.glb")
        code, out, _ = self.compare(self.stl(model), hull_dir, "--pods-from-hardpoints")
        self.assertEqual(code, 0, out)
        manifest = json.loads((hull_dir / "manifest.json").read_text())
        manifest["pod"] = {"mesh": {"file": "cargo.glb"}}
        (hull_dir / "bokmai_pod.glb").rename(hull_dir / "cargo.glb")
        (hull_dir / "manifest.json").write_text(json.dumps(manifest))
        code, out, _ = self.compare(self.stl(model), hull_dir, "--pods-from-hardpoints")
        self.assertEqual(code, 0, out)
        # The same mounts given on the command line, the two files named.
        argv = ["--pod-mesh", pod_mesh] + [a for m in mounts for a in ("--pod-at", ",".join(str(v) for v in m))]
        code, out, _ = self.compare(self.stl(model), hull_dir, *argv)
        self.assertEqual(code, 0, out)
        # Without the pods the hull alone misses them.
        code, out, _ = self.compare(self.stl(model), hull_dir)
        self.assertEqual(code, 1, out)
        self.assertLess(self.report()["views"]["top"]["iou"], 0.9)

    def test_a_pod_follows_its_up_vector(self) -> None:
        # A pod taller above its origin than below, one mounted up on the top and one hanging down from the belly.
        pod_mesh = self.pod(((-0.5, -0.5, -1.0), (0.5, 3.5, 1.0)))
        model = _boxes([HULL, ((-0.5, 0.5, 2.0), (0.5, 4.5, 4.0)), ((-0.5, -4.5, 8.0), (0.5, -0.5, 10.0))])

        def score(up_down: list[int]) -> int:
            hull_dir = self.asset([HULL], asset_id="ship")
            pods = [{"name": "a", "position": [0.0, 1.0, 3.0], "up": [0, 1, 0]}, {"name": "b", "position": [0.0, -1.0, 9.0], "up": up_down}]
            (hull_dir / "hardpoints.json").write_text(json.dumps({"cargo_pods": pods}))
            return self.compare(self.stl(model), hull_dir, "--pod-mesh", pod_mesh, "--pods-from-hardpoints")[0]

        self.assertEqual(score([0, -1, 0]), 0)
        self.assertEqual(score([0, 1, 0]), 1)  # the same pod standing on the belly instead

    def test_a_pod_follows_its_forward_vector(self) -> None:
        # A pod that is not fore-aft symmetric (3 m behind its origin, 1 m ahead of it), mounted facing aft. A keel under
        # the hull keeps the model's box centred in y, as the asset's authored frame is.
        pod_mesh = self.pod(((-0.5, -0.5, -1.0), (0.5, 0.5, 3.0)))
        keel = ((-0.5, -2.0, 4.0), (0.5, -1.0, 8.0))
        model = _boxes([HULL, keel, ((-0.5, 1.0, 4.0), (0.5, 2.0, 8.0))])  # the pod: 3 m ahead of z = 7, 1 m behind it

        def score(forward: list[float] | None) -> int:
            hull_dir = self.asset([HULL, keel], asset_id="ship")
            pod = {"name": "a", "position": [0.0, 1.5, 7.0], "up": [0, 1, 0]}
            if forward is not None:
                pod["forward"] = forward
            (hull_dir / "hardpoints.json").write_text(json.dumps({"cargo_pods": [pod]}))
            return self.compare(self.stl(model), hull_dir, "--pod-mesh", pod_mesh, "--pods-from-hardpoints")[0]

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
        pod_mesh = self.pod(((-0.5, -0.5, -1.0), (0.5, 0.5, 1.0)))
        code, _, err = run([str(good_stl), str(folder), "--length", "12", "--pod-mesh", pod_mesh, "--pods-from-hardpoints", "--out", str(self.dir / "out")])
        self.assertEqual((code, "cargo_pods" in err, "KeyError" in err), (2, True, True), err)
        (folder / "hardpoints.json").write_text(json.dumps({"cargo_pods": [{"position": [0, 0, 0], "up": "high"}]}))  # a string for a vector
        code, _, err = run([str(good_stl), str(folder), "--length", "12", "--pod-mesh", pod_mesh, "--pods-from-hardpoints", "--out", str(self.dir / "out")])
        self.assertEqual(code, 2, err)
        # Any other KeyError, IndexError or TypeError out of the readers is reported the same way.
        for exc in (KeyError("lods"), IndexError("list index out of range"), TypeError("not subscriptable")):
            with self.subTest(exc=type(exc).__name__), mock.patch.object(compare, "mesh_from_file", side_effect=exc):
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
        (no_mesh / "nomesh.glb").unlink()
        bad_mesh = self.asset([HULL], asset_id="badmesh")
        (bad_mesh / "badmesh.glb").write_bytes(b"glTF not really")
        bad_obj = self.asset([HULL], asset_id="badobj")
        manifest = json.loads((bad_obj / "manifest.json").read_text())
        del manifest["mesh"]
        (bad_obj / "manifest.json").write_text(json.dumps(manifest))
        (bad_obj / "badobj.obj").write_text("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 99\n")
        cases = {
            "missing stl": ([str(self.dir / "nope.stl"), str(good_asset)], "nope.stl"),
            "empty stl": ([str(empty), str(good_asset)], "no triangles"),
            "missing asset": ([str(good_stl), str(self.dir / "ghost")], "ghost"),
            "no manifest": ([str(good_stl), str(bare)], "manifest"),
            "broken manifest": ([str(good_stl), str(broken)], "manifest"),
            "no mesh": ([str(good_stl), str(no_mesh)], "nomesh.glb"),
            "a broken glb": ([str(good_stl), str(bad_mesh)], "cannot read the mesh"),
            "an OBJ face past the vertices": ([str(good_stl), str(bad_obj)], "cannot read the mesh"),
            "mirrored mapping": ([str(good_stl), str(good_asset), "--right=+x", "--up=+z", "--aft=+y"], "mirrors"),
            "empty model crop": ([str(good_stl), str(good_asset), "--model-zrange", "50", "60"], "model"),
            "empty asset crop": ([str(good_stl), str(good_asset), "--asset-zrange", "50", "60"], "asset"),
            "backwards crop": ([str(good_stl), str(good_asset), "--model-zrange", "6", "2"], "zrange"),
            "coarse pixel": ([str(good_stl), str(good_asset), "--pixel-frac", "0.02"], "pixel"),
            "missing pod file": ([str(good_stl), str(good_asset), "--pod-mesh", str(self.dir / "no.glb"), "--pod-at", "0,0,0"], "no.glb"),
            "bad model offset": ([str(good_stl), str(good_asset), "--model-offset", "1,2"], "x,y,z"),
            "pods without a mesh": ([str(good_stl), str(good_asset), "--pod-at", "0,0,0"], "pod-mesh"),
            "a pod mesh without mounts": ([str(good_stl), str(good_asset), "--pod-mesh", str(self.dir / "no.glb")], "mounts"),
        }
        for label, (argv, needle) in cases.items():
            with self.subTest(label):
                code, _, err = run(argv + ["--length", "12", "--out", str(self.dir / "out")])
                self.assertEqual(code, 2, err)
                self.assertIn(needle, err)


@unittest.skipUnless((REPO_ROOT / "assets" / "generated" / "raider_fighter" / "manifest.json").is_file(), "needs the built raider_fighter")
@needs_pillow
class BuiltAssetTests(unittest.TestCase):
    """The frame of a real generator's output: a built raider's textured mesh."""

    def setUp(self) -> None:
        self.dir = REPO_ROOT / "assets" / "generated" / "raider_fighter"
        self.offset = np.asarray(json.loads((self.dir / "manifest.json").read_text())["centroid_offset"])

    def test_the_glb_is_in_the_centred_godot_frame_and_the_offset_gives_the_authored_frame(self) -> None:
        centred = compare.mesh_from_file(self.dir / "raider_fighter.glb", np.zeros(3))
        mesh = compare.load_asset_mesh(self.dir)
        # Authored: the nose tip at z = 0 and x symmetric. As written the mesh is centred on the body origin instead.
        self.assertLess(abs(float(mesh[..., 2].min())), 0.05)
        self.assertLess(float(centred[..., 2].min()), -1.0)
        self.assertLess(abs(float(mesh[..., 0].min() + mesh[..., 0].max())), 1e-3)
        np.testing.assert_allclose(mesh, centred + self.offset, atol=1e-9)

    def test_the_glb_holds_the_fallback_objs_triangles(self) -> None:
        glb = compare.mesh_from_file(self.dir / "raider_fighter.glb", np.zeros(3))
        obj = compare.mesh_from_file(self.dir / "raider_fighter.obj", np.zeros(3))
        self.assertEqual(len(glb), len(obj))
        np.testing.assert_allclose(glb.reshape(-1, 3).min(axis=0), obj.reshape(-1, 3).min(axis=0), atol=1e-3)
        np.testing.assert_allclose(glb.reshape(-1, 3).max(axis=0), obj.reshape(-1, 3).max(axis=0), atol=1e-3)


if __name__ == "__main__":
    unittest.main()
