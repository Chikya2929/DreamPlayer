#!/usr/bin/env python3
"""Generate the four iOS alternate appiconsets from real 1024x1024 sources.

Why this exists
---------------
The alternate appiconsets shipped as PLACEHOLDER STUBS. Every PNG was N x N
pixels where N is the scale factor, so `Icon-App-60x60@2x.png` was a 2 x 2
image and `Icon-App-1024x1024@1x.png` was 1 x 1. Their Contents.json was
perfect -- 25 entries, every idiom/size/scale present, every filename resolving
-- and the primary AppIcon.appiconset was correct, so every structural check
passed. `actool` found the entries, judged the images inapplicable, and emitted:

    No applicable app icon found with name "AppIconMark".   (x4)

silently dropping all four. The built IPA therefore had no
CFBundleAlternateIcons at all, and `setAlternateIconName` failed on every iOS
device with "Could not change icon on this device" -- the same error UIKit
returns on an iPad, where alternate icons are unsupported anyway, so the two
causes were indistinguishable.

Target size is POINTS x SCALE, read from the primary's own Contents.json so the
mapping can never drift from what the primary actually ships.

Run:  python3 tool/gen_app_iconsets.py
Verify afterwards with:  python3 tool/verify_app_iconsets.py
"""

from __future__ import annotations

import json
import shutil
import struct
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "ios/Runner/Assets.xcassets"
PRIMARY = "AppIcon"

# Alternate set -> 1024x1024 source. Must match AppIconVariant in
# ios/Runner/IconSwitcher.swift and ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES.
SOURCES = {
    "AppIconMark": ROOT / "assets/app_icon_mark.png",
    "AppIconRed": ROOT / "assets/app_icon_mark_red.png",
    "AppIconGreen": ROOT / "assets/app_icon_mark_green.png",
    "AppIconCyan": ROOT / "assets/app_icon_mark_cyan.png",
}


def points(entry: dict) -> float:
    return float(str(entry["size"]).split("x")[0])


def scale(entry: dict) -> int:
    return int(str(entry["scale"]).rstrip("x"))


def png_dims(path: Path) -> tuple[int, int]:
    with path.open("rb") as fh:
        head = fh.read(33)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    return struct.unpack(">II", head[16:24])


def main() -> int:
    primary_dir = CATALOG / f"{PRIMARY}.appiconset"
    spec = json.loads((primary_dir / "Contents.json").read_text())

    # filename -> pixel size, taken from the PRIMARY so it cannot drift.
    wanted: dict[str, tuple[int, int]] = {}
    for entry in spec["images"]:
        name = entry.get("filename")
        if not name:
            continue
        px = (round(points(entry) * scale(entry)),) * 2
        prior = wanted.get(name)
        if prior is not None and prior != px:
            raise SystemExit(
                f"primary maps {name} to both {prior} and {px}; a single file "
                f"cannot serve two sizes, so the primary's Contents.json needs fixing"
            )
        wanted[name] = px

    if not wanted:
        raise SystemExit("primary Contents.json lists no filenames")

    for set_name, source in SOURCES.items():
        if not source.is_file():
            raise SystemExit(f"missing source image: {source}")
        out_dir = CATALOG / f"{set_name}.appiconset"
        out_dir.mkdir(parents=True, exist_ok=True)

        with Image.open(source) as img:
            src = img.convert("RGBA")
            if src.width != src.height:
                raise SystemExit(f"{source} is not square: {src.size}")
            for name, (w, h) in sorted(wanted.items()):
                resized = src.resize((w, h), Image.LANCZOS)
                target = out_dir / name
                if resized.mode == "RGBA":
                    resized.save(target, "PNG", optimize=True)
                else:  # pragma: no cover - sources are all RGBA-able
                    resized.convert("RGB").save(target, "PNG", optimize=True)
                got = png_dims(target)
                if got != (w, h):
                    raise SystemExit(f"{target} is {got}, expected {(w, h)}")

        shutil.copyfile(primary_dir / "Contents.json", out_dir / "Contents.json")
        print(f"{set_name:12} wrote {len(wanted)} images at correct point x scale")

    print(f"\nDone. Verify with: python3 tool/verify_app_iconsets.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())