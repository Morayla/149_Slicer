#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
output="${1:-$root/dist/149.app}"
case "$output" in /*) ;; *) output="$PWD/$output" ;; esac
[[ "$output" == *.app ]] || { echo 'Output must end in .app' >&2; exit 2; }
[[ ! -e "$output" ]] || { echo 'Choose a new output path; existing applications are not overwritten.' >&2; exit 2; }
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
# Rebuild the generated WebKit page when absent or when its sources change.
page="$root/resources/calibration.html"
if [[ ! -f "$page" ]] || [[ -n "$(find "$root/web/calibration/src" "$root/web/calibration/assets" "$root/web/calibration/build.mjs" "$root/web/calibration/package.json" "$root/web/calibration/pnpm-lock.yaml" "$root/web/calibration/pnpm-workspace.yaml" -type f -newer "$page" -print -quit 2>/dev/null)" ]]; then
  "$root/scripts/build-calibration.sh"
fi
[[ -x "$root/vendor/cad/bin/149-step" ]] || { echo 'Native STEP helper is missing. Run scripts/build-cad.sh.' >&2; exit 2; }
build=$(mktemp -d "${TMPDIR:-/tmp}/149-build.XXXXXX")
trap 'rm -rf "$build"' EXIT
app="$build/149.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Helpers" "$app/Contents/Resources/CAD-Licenses"
cp "$root/resources/Info.plist" "$app/Contents/Info.plist"
ditto "$root/resources" "$app/Contents/Resources"
cp "$root/vendor/cad/bin/149-step" "$app/Contents/Helpers/149-step"
cp "$root/vendor/cad/lib/"*.dylib "$app/Contents/Frameworks/"
ditto "$root/vendor/cad/licenses" "$app/Contents/Resources/CAD-Licenses"
cp "$root/vendor/cad/provenance.json" "$app/Contents/Resources/CAD-Licenses/provenance.json"
mkdir -p "$build/native"
while IFS= read -r -d '' source; do
  relative="${source#"$root/src/app/"}"
  mkdir -p "$build/native/$(dirname "$relative")"
  cp "$source" "$build/native/$relative"
done < <(find "$root/src/app" -type f -name '*.swift' -print0)
sources=()
while IFS= read -r -d '' source; do sources+=("$source"); done < <(find "$build/native" -type f -name '*.swift' -print0)
/usr/bin/swiftc -target arm64-apple-macos13.0 -module-cache-path "$build/module-cache" \
  -parse-as-library -O -whole-module-optimization \
  -framework SwiftUI -framework AppKit -framework SceneKit -framework WebKit \
  "${sources[@]}" -o "$app/Contents/MacOS/149"
/usr/bin/xattr -cr "$app"
for library in "$app/Contents/Frameworks/"*.dylib; do /usr/bin/codesign --force --sign - "$library"; done
/usr/bin/codesign --force --sign - "$app/Contents/Helpers/149-step"
/usr/bin/codesign --force --deep --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
mkdir -p "$(dirname "$output")"
mv "$app" "$output"
printf 'Built: %s\n' "$output"
