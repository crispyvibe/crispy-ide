#!/usr/bin/env bash
# Vendors the offline KaTeX runtime into the app bundle.
# Reproducible: installs the pinned deps from package.json, then copies the
# prebuilt KaTeX JS/CSS + the auto-render extension + the fonts subtree into
# Resources/LaTeXRuntime (the source of truth for the WYSIWYG LaTeX editor).
# The two KaTeX *scripts* are ALSO copied into Resources/MarkdownRuntime so the
# markdown editor can load them same-directory under CSP 'self' (no script-src
# file:). index.html and latex-bridge.js are hand-authored and are NOT touched
# by this script. No CDN is contacted at app runtime — all assets load from the
# bundle over file:// (no eval, no network).
#
# After vendoring, the copied assets are verified against the committed
# SHA256SUMS manifest to catch supply-chain drift. Regenerate the manifest
# intentionally (and review the diff) when bumping the pinned KaTeX version:
#   ( cd ../../crispyvibes/Resources/LaTeXRuntime && \
#       shasum -a 256 katex.min.js katex.min.css auto-render.min.js fonts/* ) > SHA256SUMS
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../../crispyvibes/Resources/LaTeXRuntime"
MD="$HERE/../../crispyvibes/Resources/MarkdownRuntime"
DIST="$HERE/node_modules/katex/dist"
MANIFEST="$HERE/SHA256SUMS"

echo "==> Installing pinned runtime dependencies"
( cd "$HERE" && npm ci --no-audit --no-fund )

echo "==> Refreshing vendored assets in $OUT"
mkdir -p "$OUT"
rm -rf "$OUT/fonts" \
       "$OUT/katex.min.js" \
       "$OUT/katex.min.css" \
       "$OUT/auto-render.min.js"

cp "$DIST/katex.min.js" "$OUT/"
cp "$DIST/katex.min.css" "$OUT/"
cp "$DIST/contrib/auto-render.min.js" "$OUT/"
cp -R "$DIST/fonts" "$OUT/"

echo "==> Verifying vendored assets against $MANIFEST"
if [ -f "$MANIFEST" ]; then
  ( cd "$OUT" && shasum -a 256 -c "$MANIFEST" )
else
  echo "    WARNING: $MANIFEST missing — skipping integrity check."
fi

echo "==> Co-locating KaTeX scripts into $MD (markdown inline-math, CSP 'self')"
cp "$OUT/katex.min.js" "$MD/katex.min.js"
cp "$OUT/auto-render.min.js" "$MD/auto-render.min.js"

echo "==> Done. Vendored files:"
( cd "$OUT" && du -sh . && ls -1 )
