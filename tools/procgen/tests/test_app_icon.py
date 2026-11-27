"""``app_icon``: the registry, the .ico's structure and every image in it, the .png, determinism, the corners and the centre."""

from __future__ import annotations

import hashlib
import struct
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import app_icon as icon
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.image import read_png


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_ico(data: bytes) -> list[tuple[int, int, bytes]]:
    """Each directory entry as (width, bit depth, image data); a 256 px entry's width byte is 0 in the file."""
    reserved, kind, count = struct.unpack_from("<HHH", data, 0)
    assert (reserved, kind) == (0, 1)
    entries = []
    for i in range(count):
        width, height, _colors, zero, planes, bits, length, offset = struct.unpack_from("<BBBBHHII", data, 6 + 16 * i)
        assert width == height and zero == 0 and planes == 1
        entries.append((width or 256, bits, data[offset : offset + length]))
    return entries


class AppIconTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = icon.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = icon.build(BuildContext(cls.dir_b, seed=7))  # the seed must not matter

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_it_is_registered(self) -> None:
        self.assertIs(ASSETS["app_icon"], icon.build)

    def test_files_and_manifest(self) -> None:
        self.assertEqual(sorted(p.name for p in self.dir_a.iterdir()), ["icon.ico", "icon.png", "manifest.json"])
        manifest = manifest_io.read_manifest(self.dir_a / "manifest.json")
        self.assertEqual(manifest["files"], {"ico": "icon.ico", "png": "icon.png"})
        self.assertEqual(manifest["icon"]["sizes"], list(icon.SIZES))
        self.assertEqual(self.out_a.summary, "icon, 7 sizes")

    def test_the_ico_holds_every_size_once_in_32_bit_colour(self) -> None:
        entries = read_ico((self.dir_a / "icon.ico").read_bytes())
        self.assertEqual([width for width, _, _ in entries], sorted(icon.SIZES))
        self.assertTrue(all(bits == 32 for _, bits, _ in entries))

    def test_each_image_in_the_ico_decodes_to_its_size(self) -> None:
        for width, _, blob in read_ico((self.dir_a / "icon.ico").read_bytes()):
            if width >= icon.PNG_MIN_SIZE:
                pixels = read_png(blob)
                self.assertEqual(pixels.shape, (width, width, 4))
                self.assertTrue(np.array_equal(pixels, icon.render_icon(width)))
            else:
                size, height, planes, bits = struct.unpack_from("<4xiiHH", blob)
                self.assertEqual((size, height, planes, bits), (width, width * 2, 1, 32))
                self.assertEqual(len(blob), 40 + width * width * 4 + ((width + 31) // 32) * 4 * width)

    def test_the_bitmap_entries_are_bottom_up_bgra(self) -> None:
        blob = next(b for w, _, b in read_ico((self.dir_a / "icon.ico").read_bytes()) if w == 16)
        rows = np.frombuffer(blob, np.uint8, count=16 * 16 * 4, offset=40).reshape(16, 16, 4)
        expected = icon.render_icon(16)[::-1, :, [2, 1, 0, 3]]
        self.assertTrue(np.array_equal(rows, expected))

    def test_the_png_is_the_largest_size(self) -> None:
        pixels = read_png(self.dir_a / "icon.png")
        self.assertEqual(pixels.shape, (256, 256, 4))
        self.assertTrue(np.array_equal(pixels, icon.render_icon(256)))

    def test_the_corners_are_clear_and_the_centre_is_solid(self) -> None:
        for size in icon.SIZES:
            pixels = icon.render_icon(size)
            self.assertEqual(int(pixels[0, 0, 3]), 0, size)
            self.assertEqual(int(pixels[-1, -1, 3]), 0, size)
            self.assertEqual(int(pixels[size // 2, size // 2, 3]), 255, size)

    def test_the_mark_is_not_blank(self) -> None:
        pixels = icon.render_icon(64)
        inside = pixels[..., 3] == 255
        self.assertGreater(pixels[..., :3][inside].astype(float).std(axis=0).min(), 20.0)

    def test_the_same_build_twice_is_byte_identical_whatever_the_seed(self) -> None:
        for name in ("icon.ico", "icon.png"):
            self.assertEqual(sha256(self.dir_a / name), sha256(self.dir_b / name), name)


if __name__ == "__main__":
    unittest.main()
