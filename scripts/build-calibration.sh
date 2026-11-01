#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
output="${1:-$root/dist/149 Calibration.app}"
case "$output" in /*) ;; *) output="$PWD/$output" ;; esac
[[ "$output" == *.app && ! -e "$output" ]] || { echo 'Choose a new .app output path.' >&2; exit 2; }
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
scene="$root/resources/calibration/calibration.scn.lzfse"
if [[ ! -f "$scene" || ! -f "$root/resources/calibration/calibration.metadata.json" ]] || [[ -n "$(find "$root/assets/calibration" "$root/tools/BuildCalibrationAssets.swift" "$root/src/calibration/CalibrationEdges.swift" -type f -newer "$scene" -print -quit)" ]]; then
  "$root/scripts/build-calibration-assets.sh"
fi
build=$(mktemp -d "${TMPDIR:-/tmp}/149-calibration.XXXXXX")
trap 'rm -rf "$build"' EXIT
app="$build/149 Calibration.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/resources/calibration/Info.plist" "$app/Contents/Info.plist"
cp "$scene" "$root/resources/calibration/calibration.metadata.json" "$root/resources/149.icns" "$app/Contents/Resources/"
if [[ -d "$root/resources/en.lproj" ]]; then ditto "$root/resources/en.lproj" "$app/Contents/Resources/en.lproj"; fi
sources=()
while IFS= read -r -d '' source; do sources+=("$source"); done < <(find "$root/src/calibration" "$root/src/shared" -name '*.swift' -print0)
/usr/bin/swiftc -target arm64-apple-macos13.0 -module-cache-path "$build/cache" \
  -parse-as-library -O -whole-module-optimization \
  -framework SwiftUI -framework AppKit -framework SceneKit -framework Metal -framework Charts \
  "${sources[@]}" -o "$app/Contents/MacOS/149-Calibration"
/usr/bin/xattr -cr "$app"
/usr/bin/codesign --force --deep --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
mkdir -p "$(dirname "$output")"
mv "$app" "$output"
printf 'Built: %s\n' "$output"
