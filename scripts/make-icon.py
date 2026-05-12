#!/usr/bin/env python3
"""Generate a 1024x1024 Bond app icon: pink gradient background with a white heart."""
from PIL import Image, ImageDraw
import os
import sys

SIZE = 1024
OUT = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"


def make_icon():
    img = Image.new("RGB", (SIZE, SIZE))
    pixels = img.load()
    top = (235, 86, 124)      # pink
    bottom = (160, 28, 92)    # darker rose
    for y in range(SIZE):
        t = y / (SIZE - 1)
        r = int(top[0] * (1 - t) + bottom[0] * t)
        g = int(top[1] * (1 - t) + bottom[1] * t)
        b = int(top[2] * (1 - t) + bottom[2] * t)
        for x in range(SIZE):
            pixels[x, y] = (r, g, b)

    # Heart shape — two circles + a triangle.
    heart = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(heart)
    cx, cy = SIZE // 2, SIZE // 2
    r = 180
    lx, ly = cx - 130, cy - 70
    rx, ry = cx + 130, cy - 70
    d.ellipse((lx - r, ly - r, lx + r, ly + r), fill=(255, 255, 255, 255))
    d.ellipse((rx - r, ry - r, rx + r, ry + r), fill=(255, 255, 255, 255))
    d.polygon([
        (cx - 290, cy + 10),
        (cx + 290, cy + 10),
        (cx, cy + 360),
    ], fill=(255, 255, 255, 255))

    img.paste(heart, (0, 0), heart)
    img.save(OUT, format="PNG")
    print(f"Wrote {OUT} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    make_icon()
