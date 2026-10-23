#!/usr/bin/env python3
"""Builds game/branding/rfm-icon-macos.icns from the geometry of rfm-icon.svg,
and rfm-icon-server-macos.icns, the same logo with its two colours swapped, for
the dedicated server app (docs/DEDICATED_SERVER.md).

Godot stretches a plain SVG edge to edge, so the Dock shows a square that is
larger than every other app. This draws the logo on Apple's icon grid instead:
a 1024 canvas with an 824 squircle body, a 100 px transparent margin and a soft
shadow. Needs Pillow: python3 scripts/make-macos-icon.py
"""
import io
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
BRANDING = ROOT / "game" / "branding"

ORANGE = (0xFF, 0x3B, 0x0A, 255)
WHITE = (255, 255, 255, 255)
SS = 4  # supersampling
CANVAS = 1024 * SS
BODY = 824 * SS
INSET = (CANVAS - BODY) / 2
SCALE = BODY / 180  # rfm-icon.svg viewBox is 180x180

# Speed lines from rfm-icon.svg, one polygon per stripe.
STRIPES = [
    [(23, 42.3), (23, 56.7), (101.5, 87.8), (106.8, 74.4)],
    [(23, 65), (23, 79.1), (85.8, 103.9), (91, 90.5)],
    [(32.3, 92.9), (32.3, 107.2), (81.1, 126.5), (86.3, 113.1)],
]


def pt(x, y):
    return (INSET + x * SCALE, INSET + y * SCALE)


def squircle(size, n=5.0, steps=720):
    import math

    r = size / 2
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = r * (abs(c) ** (2 / n)) * (1 if c >= 0 else -1)
        y = r * (abs(s) ** (2 / n)) * (1 if s >= 0 else -1)
        pts.append((INSET + r + x, INSET + r + y))
    return pts


def render(back, front):
    body = squircle(BODY)

    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x, y + 10 * SS) for x, y in body], fill=(0, 0, 0, 80))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14 * SS))

    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(icon)
    draw.polygon(body, fill=back)
    for stripe in STRIPES:
        draw.polygon([pt(x, y) for x, y in stripe], fill=front)
    cx, cy = pt(114.6, 105.9)
    for radius, colour in ((34.6, front), (13.1, back)):
        r = radius * SCALE
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=colour)

    return Image.alpha_composite(shadow, icon).resize((1024, 1024), Image.LANCZOS)


def png(image, size):
    buf = io.BytesIO()
    image.resize((size, size), Image.LANCZOS).save(buf, "PNG", optimize=True)
    return buf.getvalue()


def write(out, master):
    # (OSType, pixel size): 1x and @2x variants from 16 to 512 pt.
    chunks = [
        ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64),
        ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512),
        ("ic09", 512), ("ic10", 1024),
    ]
    body = b"".join(
        kind.encode() + struct.pack(">I", 8 + len(data)) + data
        for kind, data in ((kind, png(master, size)) for kind, size in chunks)
    )
    out.write_bytes(b"icns" + struct.pack(">I", 8 + len(body)) + body)
    print(f"wrote {out.relative_to(ROOT)} ({out.stat().st_size} bytes)")


def main():
    write(BRANDING / "rfm-icon-macos.icns", render(ORANGE, WHITE))
    write(BRANDING / "rfm-icon-server-macos.icns", render(WHITE, ORANGE))


if __name__ == "__main__":
    main()
