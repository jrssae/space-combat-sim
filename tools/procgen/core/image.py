"""8-bit PNG writer and reader with ``zlib`` alone (M4-T30a): the texture maps and, later, the sky panorama.

The writer stores every row unfiltered at one compression level, so the same pixels always give the same bytes. The
reader takes any non-interlaced 8-bit grey, grey-alpha, RGB or RGBA file (every row filter), enough to read back our
own maps and a Godot screenshot.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

import numpy as np

SIGNATURE = b"\x89PNG\r\n\x1a\n"
COMPRESSION_LEVEL = 6
_COLOUR_TYPE = {1: 0, 2: 4, 3: 2, 4: 6}  # channels -> PNG colour type
_CHANNELS = {value: key for key, value in _COLOUR_TYPE.items()}


def _chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def png_bytes(image: np.ndarray, level: int = COMPRESSION_LEVEL, row_filter: int = 0) -> bytes:
    """The PNG file for an 8-bit image of shape ``(h, w)``, ``(h, w, 3)`` or ``(h, w, 4)``.

    ``row_filter`` 0 stores rows as they are; 1 ("sub") stores each byte less its left neighbour, which shrinks noisy natural
    maps (the planet's) by about half. Either way the same pixels give the same bytes.
    """
    pixels = np.asarray(image)
    if pixels.dtype != np.uint8:
        raise TypeError(f"png_bytes wants uint8 pixels, got {pixels.dtype}")
    if pixels.ndim == 2:
        pixels = pixels[:, :, None]
    if pixels.ndim != 3 or pixels.shape[2] not in _COLOUR_TYPE:
        raise ValueError(f"png_bytes wants (h, w), (h, w, 3) or (h, w, 4) pixels, got {pixels.shape}")
    height, width, channels = pixels.shape
    if row_filter not in (0, 1):
        raise ValueError(f"png_bytes supports row filters 0 and 1, got {row_filter}")
    flat = pixels.reshape(height, width * channels)
    if row_filter == 1:
        flat = flat.copy()
        flat[:, channels:] -= pixels.reshape(height, width * channels)[:, :-channels]
    rows = np.concatenate([np.full((height, 1), row_filter, dtype=np.uint8), flat], axis=1)
    header = struct.pack(">IIBBBBB", width, height, 8, _COLOUR_TYPE[channels], 0, 0, 0)
    data = zlib.compress(np.ascontiguousarray(rows).tobytes(), level)
    return SIGNATURE + _chunk(b"IHDR", header) + _chunk(b"IDAT", data) + _chunk(b"IEND", b"")


def write_png(path: Path, image: np.ndarray) -> Path:
    path = Path(path)
    path.write_bytes(png_bytes(image))
    return path


def _paeth(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> np.ndarray:
    p = a.astype(np.int32) + b - c
    pa, pb, pc = np.abs(p - a), np.abs(p - b), np.abs(p - c)
    return np.where((pa <= pb) & (pa <= pc), a, np.where(pb <= pc, b, c)).astype(np.uint8)


def _unfilter(kind: int, row: np.ndarray, prior: np.ndarray, bpp: int) -> np.ndarray:
    out = row.copy()
    if kind == 0:
        return out
    if kind == 2:
        return (out.astype(np.int32) + prior) .astype(np.uint8)
    if kind == 1:
        for start in range(bpp):
            out[start::bpp] = np.cumsum(out[start::bpp], dtype=np.int64).astype(np.uint8)
        return out
    # Average and Paeth depend on the pixel just decoded: one pixel at a time, all channels together.
    n = len(out)
    for i in range(0, n, bpp):
        left = out[i - bpp : i] if i >= bpp else np.zeros(bpp, dtype=np.uint8)
        up = prior[i : i + bpp]
        if kind == 3:
            out[i : i + bpp] = (out[i : i + bpp].astype(np.int32) + (left.astype(np.int32) + up) // 2).astype(np.uint8)
        elif kind == 4:
            up_left = prior[i - bpp : i] if i >= bpp else np.zeros(bpp, dtype=np.uint8)
            out[i : i + bpp] = (out[i : i + bpp].astype(np.int32) + _paeth(left, up, up_left)).astype(np.uint8)
        else:
            raise ValueError(f"png: unknown row filter {kind}")
    return out


def read_png(source: Path | bytes) -> np.ndarray:
    """The pixels of a non-interlaced 8-bit PNG as ``(h, w)`` or ``(h, w, channels)`` uint8."""
    data = source if isinstance(source, (bytes, bytearray)) else Path(source).read_bytes()
    if data[:8] != SIGNATURE:
        raise ValueError("not a PNG file")
    offset = 8
    width = height = channels = 0
    idat = bytearray()
    while offset < len(data):
        length, kind = struct.unpack(">I4s", data[offset : offset + 8])
        body = data[offset + 8 : offset + 8 + length]
        offset += 12 + length
        if kind == b"IHDR":
            width, height, depth, colour, _compression, _filter, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or interlace != 0 or colour not in _CHANNELS:
                raise ValueError("png: only non-interlaced 8-bit grey, grey-alpha, RGB and RGBA are read")
            channels = _CHANNELS[colour]
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    if not width or not idat:
        raise ValueError("png: no image data")
    raw = np.frombuffer(zlib.decompress(bytes(idat)), dtype=np.uint8)
    stride = width * channels
    rows = raw.reshape(height, stride + 1)
    out = np.empty((height, stride), dtype=np.uint8)
    prior = np.zeros(stride, dtype=np.uint8)
    for y in range(height):
        prior = _unfilter(int(rows[y, 0]), rows[y, 1:], prior, channels)
        out[y] = prior
    return out.reshape(height, width) if channels == 1 else out.reshape(height, width, channels)


__all__ = ["png_bytes", "read_png", "write_png"]
