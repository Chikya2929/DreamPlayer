#!/usr/bin/env python3
"""Check every iOS appiconset actually ships images of the right pixel size.

Why this exists
---------------
Four alternate appiconsets shipped as placeholder stubs -- every PNG was N x N
pixels where N is the scale factor, so @1x files were 1 x 1 and the 1024
marketing icon was 1 x 1. Their Contents.json was flawless and the primary was
correct, so all the structural checks passed, and the failure only surfaced as
actool's silent

    No applicable app icon found with name "AppIconMark".

which cost a signed CI cycle to see and a real build to diagnose.

Pixel dimensions are therefore asserted here, from the PNG IHDR chunk, against
POINTS x SCALE as declared in the same entry. This runs in milliseconds and
needs no Xcode, unlike tool/verify_ipa_icons.py which checks the built product.

Run:  python3 tool/verify_app_iconsets.py
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "ios/Runner/Assets.xcassets"
PRIMARY = "AppIcon"
EXPECTED_ALTERNATES = ("AppIconMark", "AppIconRed", "AppIconGreen", "AppIconCyan")


def png_dims(path: Path) -> tuple[int, int] | None:
    with path.open("rb") as fh:
        head = fh.read(33)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def expected_px(entry: dict) -> tuple[int, int]:
    pts = float(str(entry["size"]).split("x")[0])
    scale = int(str(entry["scale"]).rstrip("x"))
    return (round(pts * scale),) * 2


def check(set_name: str) -> list[str]:
    problems: list[str] = []
    d = CATALOG / f"{set_name}.appiconset"
    cj = d / "Contents.json"
    if not d.is_dir():
        return [f"{set_name}.appiconset is missing entirely"]
    if not cj.is_file():
        return [f"{set_name}.appiconset has no Contents.json"]

    spec = json.loads(cj.read_text())
    images = spec.get("images", [])
    if not images:
        return [f"{set_name}.appiconset lists no images"]

    seen: set[str] = set()
    for entry in images:
        name = entry.get("filename")
        if not name:
            continue
        seen.add(name)
        path = d / name
        if not path.is_file():
            problems.append(f"{set_name}/{name}: referenced but not on disk")
            continue
        got = png_dims(path)
        want = expected_px(entry)
        if got is None:
            problems.append(f"{set_name}/{name}: not a valid PNG")
        elif got != want:
            problems.append(
                f"{set_name}/{name}: {got[0]}x{got[1]} px but "
                f"{entry['size']} {entry['scale']} requires {want[0]}x{want[1]}"
            )

    for entry in images:
        if not entry.get("filename"):
            continue
    if not any(e.get("idiom") == "ios-marketing" for e in images):
        problems.append(f"{set_name}: no ios-marketing 1024 entry")

    stray = {p.name for p in d.glob("*.png")} - seen
    if stray:
        problems.append(f"{set_name}: unreferenced PNGs on disk: {sorted(stray)}")
    return problems


def main() -> int:
    all_problems: list[str] = []
    for name in (PRIMARY,) + EXPECTED_ALTERNATES:
        found = check(name)
        if found:
            all_problems.extend(found)
            print(f"FAIL {name}")
            for p in found[:8]:
                print(f"      {p}")
            if len(found) > 8:
                print(f"      ... and {len(found) - 8} more")
        else:
            print(f"OK   {name}")

    if all_problems:
        print(f"\nFAIL: {len(all_problems)} problem(s). "
              f"Run python3 tool/gen_app_iconsets.py to regenerate.")
        return 1
    print("\nPASS: every appiconset ships correct pixel dimensions.")
    return 0


if __name__ == "__main__":
    sys.exit(main())