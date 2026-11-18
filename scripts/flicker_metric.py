"""Flicker in a run of frames: how much each pixel's brightness goes one way and straight back on the next frame.

usage: flicker_metric.py <frames dir> [--from A] [--to B] [--heat out.png] [--strip out.png]
A light that z-fights, pops or shimmers reverses frame to frame; steady motion (a turning drum, a moving camera) mostly does not.
Prints the mean and peak reversal (0-255 levels), the share of pixels reversing by more than 5 and 10 levels on average, and the
worst 3 frames. --heat saves the per-pixel mean reversal (x20), --strip eight consecutive frames from the worst one.
"""
import argparse, glob
import numpy as np
from PIL import Image


def luma(path):
    return np.asarray(Image.open(path).convert("L"), dtype=np.float32)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("frames"); ap.add_argument("--from", dest="a", type=int, default=0); ap.add_argument("--to", dest="b", type=int)
    ap.add_argument("--heat"); ap.add_argument("--strip")
    args = ap.parse_args()
    files = sorted(glob.glob(args.frames + "/f*.png"))[args.a:args.b]
    # A window that changed size for a frame or two (a compositor's doing) would not compare: keep the run's usual size.
    size = Image.open(files[len(files) // 2]).size
    kept = [f for f in files if Image.open(f).size == size]
    if len(kept) != len(files):
        print(f"skipped {len(files) - len(kept)} frames of another size")
    files = kept
    prev2, prev1 = luma(files[0]), luma(files[1])
    acc = np.zeros_like(prev1); per_frame = []
    for path in files[2:]:
        cur = luma(path)
        d1, d2 = prev1 - prev2, cur - prev1
        rev = np.where(d1 * d2 < 0, np.minimum(np.abs(d1), np.abs(d2)), 0)
        acc += rev; per_frame.append(float((rev > 24).mean() * 100))
        prev2, prev1 = prev1, cur
    acc /= len(files) - 2
    worst = np.argsort(per_frame)[::-1][:3]
    print(f"{'/'.join(args.frames.rstrip('/').split('/')[-2:])} [{args.a},{args.a + len(files)}): mean {acc.mean():.3f} peak {acc.max():.1f} "
          f"px>5 {(acc > 5).mean() * 100:.3f}% px>10 {(acc > 10).mean() * 100:.4f}% "
          f"worst frames {[(int(w) + 1 + args.a, round(per_frame[w], 3)) for w in worst]}")
    if args.heat:
        Image.fromarray(np.clip(acc * 20, 0, 255).astype(np.uint8)).save(args.heat)
    if args.strip:
        first = max(0, min(int(worst[0]) - 2, len(files) - 8))
        ims = [Image.open(f) for f in files[first:first + 8]]
        w, h = ims[0].size
        sheet = Image.new("RGB", (w * 4, h * 2))
        for k, im in enumerate(ims):
            sheet.paste(im, ((k % 4) * w, (k // 4) * h))
        sheet.save(args.strip)


if __name__ == "__main__":
    main()
