#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
build=$(mktemp -d "${TMPDIR:-/tmp}/149-calibration-assets.XXXXXX")
trap 'rm -rf "$build"' EXIT
cp "$root/tools/BuildCalibrationAssets.swift" "$build/main.swift"
/usr/bin/swiftc -O -module-cache-path "$build/cache" -framework SceneKit "$build/main.swift" "$root/src/calibration/CalibrationEdges.swift" -o "$build/compiler"
"$build/compiler" "$root/assets/calibration" "$root/resources/calibration/calibration.scn"
