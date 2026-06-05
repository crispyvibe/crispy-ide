#!/usr/bin/env bash
# Vendors the offline Excalidraw runtime into Resources/ExcalidrawRuntime.
# Reproducible: installs the pinned deps from package.json, then copies the
# prebuilt UMD bundle + React + the excalidraw-assets (fonts/locales/vendor
# chunk) into the app bundle. index.html is hand-authored and is NOT touched
# by this script. No CDN is contacted at app runtime — EXCALIDRAW_ASSET_PATH is
# pointed at the app's local scheme in index.html.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../../crispyvibes/Resources/ExcalidrawRuntime"
EXC="$HERE/node_modules/@excalidraw/excalidraw/dist"

echo "==> Installing pinned runtime dependencies"
( cd "$HERE" && npm ci --no-audit --no-fund )

echo "==> Refreshing vendored assets in $OUT"
mkdir -p "$OUT"
rm -rf "$OUT/excalidraw-assets" \
       "$OUT/excalidraw.production.min.js" \
       "$OUT/react.production.min.js" \
       "$OUT/react-dom.production.min.js" \
       "$OUT"/*.LICENSE.txt

cp "$EXC/excalidraw.production.min.js" "$OUT/"
cp "$EXC/excalidraw.production.min.js.LICENSE.txt" "$OUT/" 2>/dev/null || true
cp "$HERE/node_modules/react/umd/react.production.min.js" "$OUT/"
cp "$HERE/node_modules/react-dom/umd/react-dom.production.min.js" "$OUT/"
cp -R "$EXC/excalidraw-assets" "$OUT/"

echo "==> Done. Vendored files:"
( cd "$OUT" && du -sh . && ls -1 )
