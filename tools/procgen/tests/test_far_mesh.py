"""The capitals' far meshes (M10-T89): a light skin of every piece, its outline kept, its paint baked from the piece's maps.

A small made-up hull (a body, a box buried in it, a thin fin and a mast) checks the shape rules, the paint and the manifest
entry; the test cruiser checks that every capital build writes one for each piece.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import capital_test_cruiser as ctc
from tools.procgen.core import far_mesh as fm
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Material, Mesh, box
from tools.procgen.core.glb import GlbPrimitive, read_glb, write_glb
from tools.procgen.core.image import read_png, write_png
from tools.procgen.core.isosurface import edge_faults

PAINT_PX = 64
RED, GREY = (200, 30, 20), (90, 90, 90)
GLOW = (255, 220, 120)
TOP_UV, SIDE_UV, LAMP_UV = (0.25, 0.25), (0.75, 0.75), (0.25, 0.75)
LENGTH = 200.0
LAMP_AT = (0.0, 0.0, -LENGTH / 2)  # the bow's face glows


def _hull() -> Mesh:
    m = Material("hull", (0.5, 0.5, 0.5))
    return Mesh.concatenate([
        box((40.0, 30.0, LENGTH), m),
        box((20.0, 10.0, 60.0), m, (0.0, 0.0, 20.0)),  # buried: no part of the outline or the paint
        box((1.5, 30.0, 60.0), m, (0.0, 30.0, 10.0)),  # a fin, thinner than a grid cell (2 m)
        box((2.0, 50.0, 2.0), m, (0.0, -40.0, -60.0)),  # a mast
    ])


def _write_piece(folder: Path) -> dict:
    """The hull as a piece's glb with its maps; each face reads one texel: the tops red, the bow's face glowing, the rest grey."""
    mesh = _hull()
    corners = mesh.vertices[mesh.faces]
    normal = mesh.face_normals()
    uv = np.tile(np.array(SIDE_UV), (len(corners), 1))
    uv[normal[:, 1] > 0.9] = TOP_UV
    uv[(normal[:, 2] < -0.9) & (np.abs(corners[:, :, 2].mean(axis=1) - LAMP_AT[2]) < 0.1)] = LAMP_UV
    primitive = GlbPrimitive(corners.reshape(-1, 3), np.repeat(normal, 3, axis=0), np.repeat(uv, 3, axis=0),
                             np.arange(len(corners) * 3), "hull")
    write_glb(folder / "toy.glb", [primitive], "toy")
    half = PAINT_PX // 2
    albedo = np.full((PAINT_PX, PAINT_PX, 3), GREY, dtype=np.uint8)
    albedo[:half, :half] = RED
    emissive = np.zeros((PAINT_PX, PAINT_PX, 3), dtype=np.uint8)
    emissive[half:, :half] = GLOW
    orm = np.full((PAINT_PX, PAINT_PX, 3), (255, 150, 60), dtype=np.uint8)
    normal_map = np.full((PAINT_PX, PAINT_PX, 3), (128, 128, 255), dtype=np.uint8)
    for key, image in (("albedo", albedo), ("emissive", emissive), ("orm", orm), ("normal", normal_map)):
        write_png(folder / f"toy_{key}.png", image)
    surface = {"name": "hull", "blend": False, "transmittance": 0.0, "emissive_strength": 4.0,
               **{key: f"toy_{key}.png" for key in ("albedo", "normal", "orm", "emissive")},
               "world_detail": {"albedo": "detail.png", "normal": "detail_n.png", "tile_m": 16.0, "px": 64}}
    return {"file": "toy.glb", "triangles": int(len(corners)), "surfaces": [surface]}


class FarMeshTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name)
        cls.entry = _write_piece(cls.dir)
        cls.lod, cls.files = fm.build_far(cls.dir, cls.entry, 400, fm.far_from_m(LENGTH), LENGTH, cells=96)
        far = read_glb(cls.dir / cls.lod["file"]).primitives[0]
        cls.positions = np.asarray(far.positions, dtype=float)
        cls.faces = np.asarray(far.indices, dtype=np.int64).reshape(-1, 3)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_budget_and_class_numbers(self) -> None:
        self.assertLessEqual(self.lod["triangles"], 2 * 400, "at most twice the asked triangles (BUDGET_STEPS)")
        self.assertEqual(len(self.faces), self.lod["triangles"])
        self.assertEqual(fm.far_triangles("capital"), 3000, "an Omega-size hull: about 3 k (maintainer, 2026-11-26)")
        self.assertLess(fm.far_triangles("cruiser"), fm.far_triangles("capital"))
        self.assertGreater(fm.far_triangles("dreadnought"), fm.far_triangles("capital"))
        self.assertAlmostEqual(fm.far_from_m(1714.3), 13543.0, delta=1.0)

    def test_outline_kept(self) -> None:
        iou = self.lod["outline_iou"]
        self.assertGreaterEqual(iou["top"], fm.OUTLINE_MIN)
        self.assertGreaterEqual(iou["side"], fm.OUTLINE_MIN)
        # Seen from ahead the toy is mostly its fin and mast edge on, each drawn about a cell (2 m) thick: a real hull's front
        # is mostly body.
        self.assertGreaterEqual(iou["front"], 0.9)

    def test_thin_parts_kept_and_buried_parts_gone(self) -> None:
        lo, hi = self.positions.min(axis=0), self.positions.max(axis=0)
        self.assertGreater(hi[1], 40.0, "the fin (up to y 40) is still there")
        self.assertLess(lo[1], -55.0, "most of the mast (down to y -65) is still there")
        self.assertEqual(edge_faults(self._welded()), 0, "the skin is closed")

    def _welded(self) -> np.ndarray:
        _, index = np.unique(np.round(self.positions, 4), axis=0, return_inverse=True)
        return index.reshape(-1, 3)

    def test_paint_follows_facing(self) -> None:
        albedo = read_png(self.dir / f"toy_far_albedo.png")
        emissive = read_png(self.dir / f"toy_far_emissive.png")
        far = read_glb(self.dir / self.lod["file"]).primitives[0]
        uv = np.asarray(far.uv, dtype=float).reshape(-1, 3, 2).mean(axis=1)
        normal = np.asarray(far.normals, dtype=float)[::3]
        centre = self.positions.reshape(-1, 3, 3).mean(axis=1)
        px = np.clip((uv * albedo.shape[0]).astype(int), 0, albedo.shape[0] - 1)
        colour = albedo[px[:, 1], px[:, 0]].astype(float)
        top = (normal[:, 1] > 0.9) & (np.abs(centre[:, 1] - 15.0) < 3.0)
        side = (np.abs(normal[:, 0]) > 0.9) & (np.abs(centre[:, 0]) > 15.0)
        self.assertTrue(top.any() and side.any())
        self.assertGreater(colour[top, 0].mean(), 1.5 * colour[top, 1].mean(), "the body's top bakes red")
        self.assertLess(abs(colour[side, 0].mean() - colour[side, 1].mean()), 20.0, "its sides bake grey")
        bow = (normal[:, 2] < -0.9) & (centre[:, 2] < -LENGTH / 2 + 3.0)
        glow = emissive[px[bow, 1], px[bow, 0]].astype(float).sum(axis=1)
        self.assertGreater(glow.mean(), 100.0, "the bow's face keeps its glow")

    def test_manifest_entry_and_files(self) -> None:
        manifest_io.validate_mesh_section({**{k: v for k, v in self.lod.items() if k not in ("from_m", "margin_m")}, "lods": []})
        self.assertEqual(self.lod["from_m"], fm.far_from_m(LENGTH))
        self.assertAlmostEqual(self.lod["margin_m"], fm.FAR_MARGIN_SHARE * self.lod["from_m"], places=1)
        surface = self.lod["surfaces"][0]
        self.assertNotIn("world_detail", surface, "no detail tile on the far mesh")
        self.assertEqual(surface["emissive_strength"], 4.0, "the glow's strength is the hull's")
        for key in ("albedo", "orm", "emissive", "normal"):
            self.assertTrue((self.dir / surface[key]).is_file(), key)
            self.assertTrue((self.dir / (surface[key] + ".import")).is_file(), key)
        self.assertTrue(all(Path(f).is_file() for f in self.files))
        self.assertLessEqual(self.lod["atlas_px"], fm.ATLAS_PX)

    def test_same_input_same_far_mesh(self) -> None:
        with tempfile.TemporaryDirectory() as other:
            folder = Path(other)
            entry = _write_piece(folder)
            lod, _ = fm.build_far(folder, entry, 400, fm.far_from_m(LENGTH), LENGTH, cells=96)
            self.assertEqual(lod, self.lod)
            self.assertEqual((folder / lod["file"]).read_bytes(), (self.dir / self.lod["file"]).read_bytes())

    def test_piece_shares(self) -> None:
        shares = fm.piece_shares({"hull": {"mesh": {"triangles": 9000}}, "drum": {"mesh": {"triangles": 1000}}}, 3000)
        self.assertEqual(shares, {"hull": 2700, "drum": 300})
        self.assertEqual(fm.piece_shares({"hull": {"mesh": {"triangles": 9900}}, "ring": {"mesh": {"triangles": 10}}}, 3000)["ring"],
                         fm.MIN_PIECE_TRIANGLES)

    def test_closing_fills_narrow_gaps(self) -> None:
        solid = np.zeros((9, 9, 9), dtype=bool)
        solid[2:7, 2:7, 2:4] = True
        solid[2:7, 2:7, 5:7] = True  # a one-cell slot between two slabs
        self.assertTrue(fm.closed(solid, 1)[4, 4, 4])
        self.assertFalse(fm.closed(solid, 1)[0, 0, 0])


class CapitalBuildTests(unittest.TestCase):
    """Every capital build writes a far mesh for each piece (``core/capital.build``)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name)
        cls.out = ctc.build(BuildContext(cls.dir, seed=42, options={"atlas_px": 512, "detail_px": 128, "spacing": 2.0}))

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_every_piece_has_a_far_level(self) -> None:
        manifest = json.loads((self.dir / "manifest.json").read_text())
        manifest_io.validate_manifest(manifest)
        shares = fm.piece_shares(manifest["pieces"], fm.far_triangles(ctc.SHIP_CLASS))
        for name, piece in manifest["pieces"].items():
            lods = piece["mesh"]["lods"]
            self.assertEqual(len(lods), 1, name)
            self.assertLessEqual(lods[0]["triangles"], 2 * shares[name], name)
            self.assertTrue((self.dir / lods[0]["file"]).is_file(), name)
            self.assertIn(Path(self.dir / lods[0]["file"]), [Path(p) for p in self.out.files], name)
        self.assertEqual(manifest["mesh"]["lods"], manifest["pieces"]["hull"]["mesh"]["lods"], "the top-level mesh is the hull's")
        self.assertGreaterEqual(min(manifest["pieces"]["hull"]["mesh"]["lods"][0]["outline_iou"].values()), fm.OUTLINE_MIN)

    def test_option_leaves_it_out(self) -> None:
        with tempfile.TemporaryDirectory() as other:
            out = ctc.build(BuildContext(Path(other), seed=42, options={"atlas_px": 256, "detail_px": 64, "spacing": 4.0,
                                                                          "far_mesh": False}))
            self.assertEqual(out.manifest["pieces"]["hull"]["mesh"]["lods"], [])


if __name__ == "__main__":
    unittest.main()
