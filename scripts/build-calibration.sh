#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
command -v node >/dev/null || { echo 'Node.js 22 or newer is required to build the calibration page.' >&2; exit 2; }
command -v pnpm >/dev/null || { echo 'pnpm is required. Install it with: npm install --global pnpm@11.25.0' >&2; exit 2; }
cd "$root/web/calibration"
pnpm install --frozen-lockfile
pnpm run build
cp dist/calibration.html "$root/resources/calibration.html"
printf 'Built: %s\n' "$root/resources/calibration.html"
