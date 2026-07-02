#!/bin/bash
set -euo pipefail

# Builds a release binary and wraps it into a runnable, dock-less .app bundle.
cd "$(dirname "$0")/.."

APP_NAME="AgentUsage"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"

echo "Building release binary…"
swift build -c release

echo "Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Contents/Resources is the only location Apple's code signing seals for an
# .app — BrandIcon.swift knows to look here first (see its resourceBundle).
RESOURCE_BUNDLE="${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "${RESOURCE_BUNDLE}" ]; then
    cp -R "${RESOURCE_BUNDLE}" "${APP_DIR}/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle"
fi

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Agent Usage</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.agentusage</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS lets it use the Keychain and network without fuss.
codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || true

echo "Done: ${APP_DIR}"
echo "Launch with: open \"${APP_DIR}\""
