#!/usr/bin/env python3
"""Verify an iOS IPA really ships its alternate app icons.

Why this exists
---------------
An iOS app that declares alternate app icons can still ship a bundle with none
of them. `setAlternateIconName` then fails at runtime with
`UIErrorAlternateIconUnavailable` -- whose `localizedDescription` reads
"Could not change icon on this device" -- which is indistinguishable from "this
device cannot switch icons" (iPad) and from "we forgot to configure the catalog".

That is exactly how the icon switch shipped broken on iPhone (issue #23): the
`.appiconset` folders were all present and tracked, and
`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` plus
`ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS` were set on the Runner
target's Debug/Release/Profile, yet `actool` compiled only the primary set. The
built `Info.plist` had no `CFBundleAlternateIcons` and `Assets.car` contained a
single "AppIcon" name.

`tool/ios_native_check.py` cannot catch this: it reads the project file, and
the project file was correct. Only the *built product* is wrong. So this script
inspects the IPA itself, which means it can run on Linux with no Mac -- the same
way the failure was originally found.

Usage
-----
    python3 tool/verify_ipa_icons.py path/to/App.ipa
    python3 tool/verify_ipa_icons.py --expect mark,red,green,cyan App.ipa

Exits non-zero and prints the discrepancy when an expected alternate icon is
missing, so it can be used as a CI gate.
"""

from __future__ import annotations

import argparse
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

# The CFBundleAlternateIcons KEYS are the asset-catalog set names, i.e.
# "AppIcon<Variant>". Those are what ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES
# lists and what AppIconVariant rawValue carries in IconSwitcher.swift. They are
# NOT the wire names Dart sends ("mark"), which are mapped to these on the
# native side -- comparing the plist against wire names reports a healthy build
# as broken.
DEFAULT_EXPECTED = ("AppIconMark", "AppIconRed", "AppIconGreen", "AppIconCyan")


def find_app(root: Path) -> Path:
    """Locate the single .app bundle inside the unzipped Payload."""
    payload = root / "Payload"
    if not payload.is_dir():
        raise SystemExit("no Payload/ directory -- is this an iOS archive?")
    apps = [p for p in payload.iterdir() if p.suffix == ".app"]
    if not apps:
        raise SystemExit("no .app bundle inside Payload/")
    if len(apps) > 1:
        raise SystemExit(
            "more than one .app in Payload/ (%s) -- refusing to guess"
            % ", ".join(p.name for p in apps)
        )
    return apps[0]


def strings_in(path: Path) -> set[str]:
    """Approximate `strings`: printable ASCII runs, for grepping binary assets."""
    try:
        out = subprocess.run(
            ["strings", "-n", "4", str(path)],
            capture_output=True,
            check=False,
        )
    except FileNotFoundError:
        # No binutils. Fall back to a regex over the raw bytes; good enough to
        # find asset names, which are long printable runs.
        data = path.read_bytes()
        return {m.decode() for m in re.findall(rb"[ -~]{4,}", data)}
    return {ln for ln in out.stdout.decode("utf-8", "replace").splitlines() if ln}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("ipa", type=Path, help="path to the .ipa to inspect")
    ap.add_argument(
        "--expect",
        default=",".join(DEFAULT_EXPECTED),
        help="comma-separated alternate icon names expected in CFBundleAlternateIcons",
    )
    args = ap.parse_args()

    expected = [e.strip() for e in args.expect.split(",") if e.strip()]
    if not args.ipa.is_file():
        raise SystemExit(f"no such file: {args.ipa}")

    tmp = Path(tempfile.mkdtemp(prefix="verify-ipa-"))
    try:
        with zipfile.ZipFile(args.ipa) as zf:
            zf.extractall(tmp)
        app = find_app(tmp)

        problems: list[str] = []

        # ---- 1. CFBundleAlternateIcons, the key UIKit actually reads -------
        # CFBundleAlternateIcons is NESTED under CFBundleIcons -- it is not a
        # top-level key. Reading it at the top level always yields None and
        # reports every build as broken, which is how this script cried wolf.
        # iPad needs the same set under CFBundleIcons~ipad; a build can be fine
        # on iPhone and dead on iPad.
        with (app / "Info.plist").open("rb") as fh:
            plist = plistlib.load(fh)

        def alternates(container_key: str) -> dict:
            container = (plist.get(container_key) or {}).get("CFBundleAlternateIcons") or {}
            return container

        problems: list[str] = []
        for container_key in ("CFBundleIcons", "CFBundleIcons~ipad"):
            alt = alternates(container_key)
            print(f"{container_key} CFBundleAlternateIcons: {sorted(alt) or 'ABSENT'}")
            for name in expected:
                entry = alt.get(name)
                if not entry:
                    problems.append(
                        f"{container_key} has no entry for {name!r} -- UIKit "
                        f"cannot select it"
                    )
                    continue
                files = entry.get("CFBundleIconFiles") or entry.get("CFBundleIconName") or []
                print(f"  {name:<8} -> {files}")
                if not files and not entry.get("CFBundleIconName"):
                    problems.append(f"{name!r} is declared but names no icon")

        # ---- 2. Assets.car, proving actool actually compiled them ----------
        car = app / "Assets.car"
        if car.is_file():
            names = strings_in(car)
            for name in expected:
                stem = name.replace("-", "")
                hit = any(
                    stem.lower() in n.lower() and "appicon" in n.lower() for n in names
                )
                if not hit:
                    problems.append(
                        f"Assets.car contains no compiled set for {name!r} -- the "
                        f".appiconset folder was not passed to actool"
                    )
        else:
            problems.append("no Assets.car -- the asset catalog was not compiled")

        # ---- verdict ------------------------------------------------------
        if problems:
            print("\nFAIL")
            for p in problems:
                print(f"  - {p}")
            return 1
        print("\nPASS: all alternate app icons are present and compiled")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())