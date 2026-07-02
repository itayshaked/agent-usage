#!/bin/bash
set -euo pipefail

# Builds a signed + notarized universal zip, creates a GitHub release with it
# attached, and prints the exact `version`/`sha256` lines to paste into
# Casks/cursorusagebar.rb. Requires this repo to be pushed to GitHub and `gh`
# authenticated.

cd "$(dirname "$0")/.."

VERSION="${1:?Usage: Scripts/cut_release.sh <version, e.g. 1.1>}"
TAG="v${VERSION}"
ZIP="dist/CursorUsageBar.zip"

export DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: Itay Shaked (J42P4FD379)}"
export NOTARY_PROFILE="${NOTARY_PROFILE:-CURSORBAR_NOTARY}"

echo "Building + signing + notarizing ${ZIP}…"
./Scripts/make_dist.sh

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')

echo ""
echo "Creating GitHub tag + release ${TAG}…"
gh release create "$TAG" "$ZIP" \
  --title "CursorUsageBar ${VERSION}" \
  --notes "Automated release for CursorUsageBar ${VERSION}."

echo ""
echo "════════════════════════════════════════════════════"
echo "Paste these into Casks/cursorusagebar.rb, then commit & push:"
echo ""
echo "  version \"${VERSION}\""
echo "  sha256 \"${SHA}\""
echo ""
echo "════════════════════════════════════════════════════"
