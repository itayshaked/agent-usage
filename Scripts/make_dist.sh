#!/bin/bash
set -euo pipefail

# Builds a universal (Apple Silicon + Intel) .app, signs it, and zips it for
# sharing. Set DEVELOPER_ID to a "Developer ID Application: ..." identity to
# produce a Gatekeeper-friendly build; otherwise it's ad-hoc signed (teammates
# will need to clear quarantine — see README).
#
# Optional notarization: set NOTARY_PROFILE to a stored `notarytool` keychain
# profile name and this script will submit, wait, and staple.

cd "$(dirname "$0")/.."

APP_NAME="CursorUsageBar"
APP_DIR="dist/${APP_NAME}.app"
ZIP_PATH="dist/${APP_NAME}.zip"

echo "Building universal release binary…"
swift build -c release --arch arm64 --arch x86_64
BIN=".build/apple/Products/Release/${APP_NAME}"

echo "Assembling ${APP_DIR}…"
rm -rf "dist"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>Cursor Usage</string>
    <key>CFBundleIdentifier</key><string>com.local.cursorusagebar</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "Signing with Developer ID: ${DEVELOPER_ID}"
    codesign --force --deep --options runtime --timestamp \
        --sign "${DEVELOPER_ID}" "${APP_DIR}"
else
    echo "No DEVELOPER_ID set — ad-hoc signing (Gatekeeper will warn on other Macs)."
    codesign --force --deep --sign - "${APP_DIR}"
fi

echo "Zipping to ${ZIP_PATH}…"
ditto -c -k --keepParent "${APP_DIR}" "${ZIP_PATH}"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "Submitting for notarization (profile: ${NOTARY_PROFILE})…"
    xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
    xcrun stapler staple "${APP_DIR}"
    rm -f "${ZIP_PATH}"
    ditto -c -k --keepParent "${APP_DIR}" "${ZIP_PATH}"
    echo "Notarized + stapled."
fi

echo ""
echo "Done → ${ZIP_PATH}"
echo "Share that zip with your team."
