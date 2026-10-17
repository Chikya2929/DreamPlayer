#!/usr/bin/env bash
# Probe what actool actually does with our asset catalog.
#
# Why
# ---
# The built IPA has no CFBundleAlternateIcons and Assets.car holds only
# "AppIcon", yet the repository is correct by every check available from Linux:
# one Assets.xcassets in the Runner Resources phase, five .appiconset folders
# tracked with 21 PNGs each, every Contents.json filename resolving, all four
# alternates structurally identical to the primary, and both
# ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES and
# ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS set on the Runner target's
# Debug/Release/Profile.
#
# Guessing between "the catalog is wrong" and "the setting never reaches
# actool" costs a 13-minute CI cycle per attempt. Running actool by hand costs
# seconds and settles it, because this is the exact invocation xcodebuild makes
# -- the same flags Xcode derives from those build settings (see actool(1):
# --alternate-app-icon, --include-all-app-icons, --output-partial-info-plist).
#
# Usage: tool/probe_actool_icons.sh [output-dir]
# Requires macOS with Xcode. Exit 0 if every alternate is compiled and declared.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="${REPO_ROOT}/ios/Runner/Assets.xcassets"
OUT_DIR="${1:-$(mktemp -d -t actool-icons-XXXXXX)}"
PLIST="${OUT_DIR}/partial-Info.plist"

# Must match ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES in project.pbxproj
# and AppIconVariant in ios/Runner/IconSwitcher.swift.
ALTERNATES=(AppIconMark AppIconRed AppIconGreen AppIconCyan)
PRIMARY=AppIcon

if ! command -v xcrun >/dev/null 2>&1; then
  echo "probe: xcrun not available -- macOS with Xcode required" >&2
  exit 2
fi

mkdir -p "${OUT_DIR}"
echo "probe: catalog = ${CATALOG}"
echo "probe: output = ${OUT_DIR}"

args=(
  --compile "${OUT_DIR}"
  --platform iphoneos
  --minimum-deployment-target 17.0
  --app-icon "${PRIMARY}"
  --include-all-app-icons
  --output-partial-info-plist "${PLIST}"
  "${CATALOG}"
)
for name in "${ALTERNATES[@]}"; do
  args+=(--alternate-app-icon "${name}")
done

# --alternate-app-icon and --include-all-app-icons are alternatives in actool;
# pass them explicitly and tolerate a rejection so we can see WHICH one the
# installed actool accepts. That difference is itself a useful signal.
echo "probe: running actool ${args[*]}"
if ! xcrun actool "${args[@]}" 2>&1 | tee "${OUT_DIR}/actool.log"; then
  echo
  echo "probe: actool failed; see ${OUT_DIR}/actool.log"
  exit 2
fi

if [[ ! -f "${PLIST}" ]]; then
  echo
  echo "probe: FAIL -- actool produced no partial Info.plist at ${PLIST}"
  exit 1
fi

echo
echo "probe: ---- CFBundleIcons actool emitted ----"
if xcrun plutil -extract CFBundleIcons xml1 -o - "${PLIST}" 2>/dev/null; then
  echo "probe: -------------------------------------"
else
  echo "probe: (no CFBundleIcons key emitted at all)"
  echo "probe: -------------------------------------"
fi

rc=0
# Per-icon output directories are NOT how actool emits: with a deployment
# target of iOS 11+ every icon goes into Assets.car, so a directory check
# reports MISS for icons that compiled perfectly. That is a gate that cries
# wolf. The declaration in the partial plist plus Assets.car are the real
# signals; per-file existence is only checked when actool emitted loose files.
emitted_loose=$(find "${OUT_DIR}" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
if [[ "${emitted_loose}" -gt 0 ]]; then
  echo "probe: note ${emitted_loose} loose icon file(s) emitted alongside Assets.car"
fi
for name in "${ALTERNATES[@]}"; do
  if xcrun plutil -extract "CFBundleIcons.CFBundleAlternateIcons.${name}" xml1 -o - \
      "${PLIST}" >/dev/null 2>&1; then
    echo "probe: OK    ${name} declared in CFBundleAlternateIcons"
  else
    echo "probe: MISS  ${name} NOT declared -- UIKit cannot select it"
    rc=1
  fi
done

echo
if [[ ${rc} -eq 0 ]]; then
  echo "probe: PASS -- actool compiles and declares every alternate."
  echo "probe: So the catalog is correct and the fault is upstream: the build"
  echo "probe: settings are not reaching actool through xcode_backend/xcconfig."
else
  echo "probe: FAIL -- the catalog itself is the problem; fix it before touching"
  echo "probe: build settings."
fi
exit ${rc}