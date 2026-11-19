#!/usr/bin/env python3
"""Generate Android launcher mipmap PNGs and Flutter/docs logo assets from a source square image."""

from __future__ import annotations

from pathlib import Path
import sys
from PIL import Image, ImageDraw


ANDROID_MIPMAPS = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def make_rounded_icon(img: Image.Image, size: int, radius_ratio: float = 0.22) -> Image.Image:
    resized = img.resize((size, size), Image.Resampling.LANCZOS).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    radius = max(1, int(size * radius_ratio))
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(resized, (0, 0), mask)
    return out


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <source_logo_image>", file=sys.stderr)
        return 2

    repo_root = Path(__file__).resolve().parent.parent
    src_path = Path(sys.argv[1])
    img = Image.open(src_path).convert("RGBA")

    # 1. Docs & Flutter assets (512x512 rounded PNG)
    docs_logo = repo_root / "docs" / "logo.png"
    docs_logo.parent.mkdir(parents=True, exist_ok=True)
    make_rounded_icon(img, 512).save(docs_logo, format="PNG", optimize=True)

    flutter_logo = repo_root / "mobile" / "assets" / "icon" / "uback_logo.png"
    flutter_logo.parent.mkdir(parents=True, exist_ok=True)
    make_rounded_icon(img, 256).save(flutter_logo, format="PNG", optimize=True)

    # 2. Android mipmap launcher icons (full-bleed square for adaptive masks + crisp legacy rounded)
    res_dir = repo_root / "mobile" / "android" / "app" / "src" / "main" / "res"
    for folder, px in ANDROID_MIPMAPS.items():
        out_dir = res_dir / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        make_rounded_icon(img, px).save(out_dir / "ic_launcher.png", format="PNG", optimize=True)

    print(f"Generated docs/logo.png, mobile/assets/icon/uback_logo.png, and {len(ANDROID_MIPMAPS)} Android mipmaps.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
