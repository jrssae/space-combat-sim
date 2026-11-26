"""tools/refview/kit (M10-T68): print kits assembled into one reference mesh, on synthetic STLs so no reference file is needed."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

try:
    import PIL  # noqa: F401
except ImportError:  # the tool draws with Pillow, which procgen treats as optional (tools/procgen/README.md)
    kt = None
    refview = None
else:
    from tools.refview import kit as kt  # a broken tool must fail here, not skip
    from tools.refview import refview

needs_pillow = unittest.skipIf(kt is None, "tools/refview needs Pillow")


def box(lo: tuple[float, float, float], hi: tuple[float, float, float], inward: bool = False) -> np.ndarray:
    """A closed box as outward-wound triangles (n, 3, 3); ``inward`` winds it as a cavity."""
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    v = np.array([[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0], [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]], float)
    tris = []
    for a, b, c, d in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (3, 7, 6, 2), (0, 4, 7, 3), (1, 2, 6, 5)):
        tris += [[v[a], v[b], v[c]], [v[a], v[c], v[d]]]
    out = np.array(tris)
    return out[:, ::-1] if inward else out


@needs_pillow
class KitTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        # A 10 mm long "head" with its nose at file z = 10 (printed standing on its join face) and a 20 mm "tail" stood the right way.
        refview.write_binary_stl(self.root / "head.stl", box((-1, -1, 0), (1, 2, 10)).astype(np.float32))
        refview.write_binary_stl(self.root / "tail.stl", box((-2, -2, 0), (2, 2, 20)).astype(np.float32))
        # A wing stood on its glue face: long along file y, reaching out along file z, with a closed hollow inside.
        wing = np.concatenate([box((0, -6, 0), (2, 0, 4)), box((0.5, -5, 1), (1.5, -1, 3), inward=True)])
        refview.write_binary_stl(self.root / "wing.stl", wing.astype(np.float32))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def kit(self, **extra) -> dict:
        data = {
            "name": "test", "length_m": 300.0,
            "parts": [
                {"label": "head", "file": "head.stl", "axes": ["-x", "+y", "-z"], "at_mm": [0, 0, 10]},
                {"label": "tail", "file": "tail.stl", "follows": "head", "at_mm": [0, 0, 0]},
                {"label": "wing", "file": "wing.stl", "follows": "tail", "rotor": True, "axes": ["-x", "+z", "+y"],
                 "pivot_mm": [1, -3, 0], "at_mm": [0, 2, 10]},
            ],
        }
        data.update(extra)
        return data

    def test_parts_stack_flush_and_scale_to_the_length(self) -> None:
        asm = kt.assemble(kt.parse_kit(self.kit()), self.root)
        self.assertAlmostEqual(asm.length_mm, 30.0, places=6)
        self.assertAlmostEqual(asm.metres_per_mm, 10.0, places=6)
        z = asm.tris[:, :, 2]
        self.assertAlmostEqual(float(z.min()), 0.0, places=6)
        self.assertAlmostEqual(float(z.max()), 300.0, places=6)
        head = asm.tris[asm.labels == 0]
        self.assertAlmostEqual(float(head[:, :, 2].max()), 100.0, places=6)  # the head's join face meets the tail at 10 mm

    def test_the_head_is_turned_not_mirrored(self) -> None:
        # Turned half round about y: file x -> -x, file y stays up, the file's z = 10 nose lands at the front.
        asm = kt.assemble(kt.parse_kit(self.kit()), self.root)
        head = asm.tris[asm.labels == 0].reshape(-1, 3) / 10.0
        self.assertAlmostEqual(float(head[:, 1].min()), -1.0, places=6)
        self.assertAlmostEqual(float(head[:, 1].max()), 2.0, places=6)
        with self.assertRaises(ValueError):
            refview.frame_matrix("-x", "+y", "+z")  # a mapping that would mirror a part is refused

    def test_a_wing_stands_out_from_its_glue_face_and_turns_with_the_rotor(self) -> None:
        asm = kt.assemble(kt.parse_kit(self.kit()), self.root)
        wing = asm.tris[asm.labels == 2].reshape(-1, 3) / 10.0
        self.assertAlmostEqual(float(wing[:, 1].min()), 2.0, places=6)  # the glue face on the hub's top
        self.assertAlmostEqual(float(wing[:, 1].max()), 6.0, places=6)  # reaching 4 mm up
        self.assertAlmostEqual(float(wing[:, 2].min()), 17.0, places=6)  # 6 mm long, centred on the tail's middle
        turned = kt.assemble(kt.parse_kit(self.kit(rotor_roll_deg=90.0)), self.root)
        w90 = turned.tris[turned.labels == 2].reshape(-1, 3) / 10.0
        self.assertAlmostEqual(float(w90[:, 0].min()), -6.0, places=6)  # turned to port about the spine
        tail = turned.tris[turned.labels == 1].reshape(-1, 3) / 10.0
        self.assertAlmostEqual(float(tail[:, 0].max()), 2.0, places=6)  # a part that is not a rotor stays put

    def test_closed_hollows_are_dropped_and_sockets_plugged(self) -> None:
        wing = kt.read_part(kt.parse_kit(self.kit()).parts[2], self.root)
        self.assertEqual(len(kt.without_voids(wing)), 12)
        self.assertGreater(kt.signed_volumes(kt.cylinder((0.0, 0.0), 1.0, 0.0, 2.0)).sum(), 6.0)  # outward, about 2 pi
        data = self.kit()
        data["parts"][1]["plugs"] = [{"center": [0, 0], "radius": 0.5, "z": [0, 3]}]
        asm = kt.assemble(kt.parse_kit(data), self.root)
        self.assertEqual(int((asm.labels == 1).sum()), 12 + 4 * kt.PLUG_SEGMENTS)

    def test_a_fixed_scale_replaces_the_length(self) -> None:
        asm = kt.assemble(kt.parse_kit(self.kit(metres_per_mm=5.0)), self.root)
        self.assertAlmostEqual(float(asm.tris[:, :, 2].max()), 150.0, places=6)

    def test_bad_kits_are_refused(self) -> None:
        data = self.kit()
        data["parts"][1]["follows"] = "wing"  # listed after it
        with self.assertRaises(ValueError):
            kt.parse_kit(data)
        data = self.kit()
        data["parts"][2]["label"] = "head"
        with self.assertRaises(ValueError):
            kt.parse_kit(data)
        with self.assertRaises(ValueError):
            kt.parse_vary("head:w:1:0.1")

    def test_build_writes_the_mesh_the_npy_and_a_summary(self) -> None:
        path = self.root / "k.json"
        path.write_text(json.dumps(self.kit()))
        kit = kt.load_kit(path)
        files = kt.write_outputs(kit, kt.assemble(kit, self.root), self.root / "out" / "test assembled")
        stl, npy, info = files
        raw, _ = refview.read_stl(stl)
        self.assertEqual(len(np.asarray(raw).reshape(-1, 3, 3)), len(np.load(npy)))
        summary = json.loads(info.read_text())
        self.assertEqual(summary["parts"], {"head": 12, "tail": 12, "wing": 12})

    def test_fit_finds_a_moved_part_against_a_guide(self) -> None:
        guide = kt.assemble(kt.parse_kit(self.kit()), self.root).tris
        data = self.kit()
        data["parts"][2]["at_mm"] = [0, 2, 8]  # the wing 2 mm forward of where the guide has it
        kit = kt.parse_kit(data)
        kt.fit(kit, guide, ["wing:z:3:1"], passes=1, pixel_fraction=0.005, root=self.root, log=lambda _m: None)
        self.assertAlmostEqual(kit.parts[2].at_mm[2], 10.0, places=6)


if __name__ == "__main__":
    unittest.main()
