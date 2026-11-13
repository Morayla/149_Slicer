#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
output="${1:-$root/dist/149 Slicer.app}"
case "$output" in /*) ;; *) output="$PWD/$output" ;; esac
[[ "$output" == *.app ]] || { echo 'Output must end in .app' >&2; exit 2; }
[[ ! -e "$output" ]] || { echo 'Choose a new output path; existing applications are not overwritten.' >&2; exit 2; }
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
build=$(mktemp -d "${TMPDIR:-/tmp}/149-build.XXXXXX")
trap 'rm -rf "$build"' EXIT
app="$build/149 Slicer.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/resources/Info.plist" "$app/Contents/Info.plist"
for resource in g1-preview-config.txt definitions; do
  ditto "$root/resources/$resource" "$app/Contents/Resources/$resource"
done
if [[ -d "$root/resources/en.lproj" ]]; then ditto "$root/resources/en.lproj" "$app/Contents/Resources/en.lproj"; fi
for asset in app-icon.icns logo.pdf; do
  ditto "$root/assets/branding/$asset" "$app/Contents/Resources/$asset"
done
find "$app" -name .DS_Store -delete
# Every resource file the sources load by name must be present in the bundle.
missing=0
while IFS= read -r name; do
  if [[ -z "$(find "$app/Contents/Resources" -name "$name" -print -quit)" ]]; then
    echo "Missing bundled resource: $name" >&2
    missing=1
  fi
done < <(
  grep -oE '"[a-z0-9-]+\.[a-z0-9]+"' "$root/src/app/BundledResources.swift" | tr -d '"'
  grep -rhoE 'forResource: "[^"]+", withExtension: "[^"]+"' "$root/src/app" "$root/src/shared" |
    sed -E 's/forResource: "([^"]+)", withExtension: "([^"]+)"/\1.\2/'
)
[[ "$missing" -eq 0 ]] || exit 1
mkdir -p "$build/native"
while IFS= read -r -d '' source; do
  relative="${source#"$root/src/"}"
  mkdir -p "$build/native/$(dirname "$relative")"
  cp "$source" "$build/native/$relative"
done < <(find "$root/src/app" "$root/src/shared" -type f -name '*.swift' -print0)
sources=()
while IFS= read -r -d '' source; do sources+=("$source"); done < <(find "$build/native" -type f -name '*.swift' -print0)
/usr/bin/swiftc -target arm64-apple-macos13.0 -module-cache-path "$build/module-cache" \
  -parse-as-library -O -whole-module-optimization \
  -framework SwiftUI -framework AppKit -framework SceneKit -framework WebKit \
  "${sources[@]}" -o "$app/Contents/MacOS/149"
/usr/bin/xattr -cr "$app"
/usr/bin/codesign --force --deep --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
mkdir -p "$(dirname "$output")"
mv "$app" "$output"
printf 'Built: %s\n' "$output"
