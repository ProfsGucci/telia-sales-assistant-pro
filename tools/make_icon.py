#!/usr/bin/env python3
"""Generates the app icon and the Assets.xcassets catalog contents.

Renders a Telia-inspired purple gradient icon (matching DS.Purple in
Theme.swift) with a white chat-bubble + "T" mark, at 4x supersampling
for clean edges, then writes AppIcon / AccentColor / LaunchBackground
asset catalog entries.

Run from the repo root:  python3 tools/make_icon.py
Requires Pillow.
"""

from pathlib import Path

from PIL import Image, ImageDraw

# DS.Purple ramp from TeliaSalesAssistantPro/DesignSystem/Theme.swift
LIGHT = (140, 89, 235)   # #8C59EB
BASE = (117, 56, 219)    # #7538DB
DEEP = (84, 33, 168)     # #5421A8
INK = (56, 20, 107)      # #38146B

ROOT = Path(__file__).resolve().parent.parent
APP_DIR = ROOT / "TeliaSalesAssistantPro"
ASSETS = APP_DIR / "Resources" / "Assets.xcassets"
ICON_SIZE = 1024
SS = 4  # supersample factor


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(w, h, stops):
    """Diagonal (top-left -> bottom-right) multi-stop gradient."""
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / max(w - 1, 1) + y / max(h - 1, 1)) / 2
            seg = t * (len(stops) - 1)
            i = min(int(seg), len(stops) - 2)
            px[x, y] = lerp(stops[i], stops[i + 1], seg - i)
    return img


def rounded_bar(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def draw_icon():
    size = ICON_SIZE * SS
    img = gradient(size, size, [LIGHT, BASE, DEEP])

    draw = ImageDraw.Draw(img)

    # Soft radial glow, top-left (subtle, on-brand)
    glow = Image.new("L", (size, size), 0)
    gdraw = ImageDraw.Draw(glow)
    gdraw.ellipse((-size * 0.25, -size * 0.25, size * 0.55, size * 0.55), fill=70)
    glow = glow.filter(__import__("PIL.ImageFilter", fromlist=["GaussianBlur"]).GaussianBlur(size // 10))
    white = Image.new("RGB", (size, size), (255, 255, 255))
    img = Image.composite(white, img, glow.point(lambda v: v // 3))
    draw = ImageDraw.Draw(img)

    s = size / 1024  # design-unit scale

    # Chat bubble (white, rounded rect + tail)
    bubble = (232 * s, 236 * s, 792 * s, 672 * s)
    r = 118 * s
    draw.rounded_rectangle(bubble, radius=r, fill=(255, 255, 255))
    # Bubble tail (bottom-left)
    draw.polygon(
        [(318 * s, 660 * s), (452 * s, 660 * s), (350 * s, 796 * s)],
        fill=(255, 255, 255),
    )

    # "T" mark inside the bubble: horizontal bar + stem, purple gradient
    # (approximated with two solid tones that read as the ramp)
    bar_box = (330 * s, 350 * s, 694 * s, 438 * s)
    stem_box = (452 * s, 350 * s, 572 * s, 586 * s)
    rounded_bar(draw, bar_box, 44 * s, BASE)
    rounded_bar(draw, stem_box, 44 * s, DEEP)

    # AI spark, four-point star top-right of the bubble
    cx, cy, arm, waist = 760 * s, 232 * s, 74 * s, 20 * s
    star = [
        (cx, cy - arm), (cx + waist, cy - waist),
        (cx + arm, cy), (cx + waist, cy + waist),
        (cx, cy + arm), (cx - waist, cy + waist),
        (cx - arm, cy), (cx - waist, cy - waist),
    ]
    draw.polygon(star, fill=(255, 255, 255))

    # Downscale with high-quality filter, force opaque sRGB
    icon = img.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS).convert("RGB")
    return icon


CONTENTS_ROOT = """{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

CONTENTS_APPICON = """{
  "images" : [
    {
      "filename" : "AppIcon1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

CONTENTS_ACCENT = """{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.859",
          "green" : "0.220",
          "red" : "0.459"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.922",
          "green" : "0.349",
          "red" : "0.549"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

CONTENTS_LAUNCH = """{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "1.000",
          "green" : "1.000",
          "red" : "1.000"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.043",
          "green" : "0.031",
          "red" : "0.024"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""


def main():
    appicon_dir = ASSETS / "AppIcon.appiconset"
    accent_dir = ASSETS / "AccentColor.colorset"
    launch_dir = ASSETS / "LaunchBackground.colorset"

    for d in (ASSETS, appicon_dir, accent_dir, launch_dir):
        d.mkdir(parents=True, exist_ok=True)

    icon = draw_icon()
    icon.save(appicon_dir / "AppIcon1024.png", optimize=True)

    (ASSETS / "Contents.json").write_text(CONTENTS_ROOT)
    (appicon_dir / "Contents.json").write_text(CONTENTS_APPICON)
    (accent_dir / "Contents.json").write_text(CONTENTS_ACCENT)
    (launch_dir / "Contents.json").write_text(CONTENTS_LAUNCH)

    print(f"Icon written to {appicon_dir / 'AppIcon1024.png'} ({ICON_SIZE}x{ICON_SIZE}, opaque RGB)")
    print(f"Asset catalog at {ASSETS}")


if __name__ == "__main__":
    main()
