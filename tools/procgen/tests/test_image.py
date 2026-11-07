"""``core/image.py`` (M4-T30a): the PNG writer and reader, exact round trips, byte-identical output."""

from __future__ import annotations

import tempfile
import unittest
import zlib
from pathlib import Path

import numpy as np

from tools.procgen.core.image import png_bytes, read_png, write_png


class PngTests(unittest.TestCase):
    def test_rgb_round_trip_is_exact(self) -> None:
        rng = np.random.default_rng(3)
        rgb = rng.integers(0, 256, size=(13, 17, 3), dtype=np.uint8)
        with tempfile.TemporaryDirectory() as tmp:
            path = write_png(Path(tmp) / "a.png", rgb)
            back = read_png(path)
        np.testing.assert_array_equal(back, rgb)
        self.assertEqual(back.dtype, np.uint8)

    def test_rgba_and_grey_round_trips(self) -> None:
        rng = np.random.default_rng(4)
        rgba = rng.integers(0, 256, size=(5, 9, 4), dtype=np.uint8)
        grey = rng.integers(0, 256, size=(6, 4), dtype=np.uint8)
        np.testing.assert_array_equal(read_png(png_bytes(rgba)), rgba)
        np.testing.assert_array_equal(read_png(png_bytes(grey)), grey)

    def test_same_pixels_give_the_same_bytes(self) -> None:
        rgb = np.zeros((4, 4, 3), dtype=np.uint8)
        rgb[1, 2] = (10, 20, 30)
        self.assertEqual(png_bytes(rgb), png_bytes(rgb.copy()))

    def test_the_file_starts_with_the_png_signature_and_its_chunks_check(self) -> None:
        data = png_bytes(np.full((2, 3, 3), 7, dtype=np.uint8))
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(data[12:16], b"IHDR")
        # The IHDR CRC covers type and data.
        self.assertEqual(int.from_bytes(data[29:33], "big"), zlib.crc32(data[12:29]) & 0xFFFFFFFF)

    def test_floats_are_rejected_and_the_reader_handles_filtered_rows(self) -> None:
        with self.assertRaises(TypeError):
            png_bytes(np.zeros((2, 2, 3), dtype=np.float32))
        # A hand-filtered file: row 0 with the Sub filter, row 1 with Up, so the reader's unfiltering is exercised.
        raw = bytes([1, 10, 20, 30, 5, 5, 5]) + bytes([2, 1, 1, 1, 1, 1, 1])
        data = png_bytes(np.zeros((2, 2, 3), dtype=np.uint8))
        ihdr = data[8:33]
        idat = zlib.compress(raw)
        idat_chunk = len(idat).to_bytes(4, "big") + b"IDAT" + idat + (zlib.crc32(b"IDAT" + idat) & 0xFFFFFFFF).to_bytes(4, "big")
        iend = data[-12:]
        back = read_png(b"\x89PNG\r\n\x1a\n" + ihdr + idat_chunk + iend)
        np.testing.assert_array_equal(back[0], [[10, 20, 30], [15, 25, 35]])
        np.testing.assert_array_equal(back[1], [[11, 21, 31], [16, 26, 36]])


if __name__ == "__main__":
    unittest.main()
