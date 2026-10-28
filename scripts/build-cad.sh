#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
vendor="$root/vendor/cad"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
command -v cmake >/dev/null || { echo 'CMake is required to rebuild Open CASCADE.' >&2; exit 2; }
build=$(mktemp -d "${TMPDIR:-/tmp}/149-cad.XXXXXX")
trap 'rm -rf "$build"' EXIT
archive="$build/occt.tar.gz"
curl --fail --location --retry 3 'https://codeload.github.com/Open-Cascade-SAS/OCCT/tar.gz/refs/tags/V7_9_3' --output "$archive"
printf '%s  %s\n' '5ecf094ec6b12d5413dfb851d8c3590c354058aee556e32e408bdfbf8c357d57' "$archive" | shasum -a 256 -c -
tar -xzf "$archive" -C "$build"
cmake -S "$build/OCCT-7_9_3" -B "$build/occt" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DBUILD_LIBRARY_TYPE=Shared -DBUILD_CPP_STANDARD=C++17 -DBUILD_ADDITIONAL_TOOLKITS='TKDESTEP TKMesh' \
  -DBUILD_MODULE_FoundationClasses=OFF -DBUILD_MODULE_ModelingData=OFF -DBUILD_MODULE_ModelingAlgorithms=OFF \
  -DBUILD_MODULE_Visualization=OFF -DBUILD_MODULE_ApplicationFramework=OFF -DBUILD_MODULE_DataExchange=OFF \
  -DBUILD_MODULE_DETools=OFF -DBUILD_MODULE_Draw=OFF -DBUILD_RESOURCES=OFF \
  -DUSE_TBB=OFF -DUSE_FREETYPE=OFF -DUSE_XLIB=OFF
cmake --build "$build/occt" --parallel "${CAD_JOBS:-$(sysctl -n hw.logicalcpu)}"
libraries="$build/occt/mac64/clang/lib"
xcrun clang++ -std=c++17 -O2 -arch arm64 -mmacosx-version-min=13.0 \
  -I "$build/occt/include/opencascade" "$root/src/cad/StepImport.cpp" -L "$libraries" \
  -lTKDESTEP -lTKMesh -lTKBRep -lTKTopAlgo -lTKMath -lTKernel \
  -Wl,-rpath,"$libraries" -Wl,-headerpad_max_install_names -o "$build/149-step"
xcrun swiftc -O -parse-as-library -module-cache-path "$build/module-cache" "$root/tools/BundleCAD.swift" -o "$build/bundle-cad"
"$build/bundle-cad" "$build/149-step" "$libraries" "$build/bundle"
# Publish only after the entire dependency closure has been verified.
rm -rf "$vendor/bin" "$vendor/lib"
mv "$build/bundle/bin" "$vendor/bin"
mv "$build/bundle/lib" "$vendor/lib"
mv "$build/bundle/provenance.json" "$vendor/provenance.json"
mkdir -p "$vendor/licenses"
cp "$build/OCCT-7_9_3/LICENSE_LGPL_21.txt" "$build/OCCT-7_9_3/OCCT_LGPL_EXCEPTION.txt" "$vendor/licenses/"
printf 'Rebuilt native STEP importer: %s\n' "$vendor/bin/149-step"
