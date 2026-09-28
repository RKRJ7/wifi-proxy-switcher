#!/usr/bin/env bash
# build.sh — Build and package WiFi Proxy Switcher as a .app bundle
# Usage: ./build.sh [--release]

set -euo pipefail

CONFIG="${1:-debug}"
if [[ "$CONFIG" == "--release" ]]; then
    CONFIG="release"
    SWIFT_FLAGS="--configuration release"
else
    SWIFT_FLAGS="--configuration debug"
fi

echo "==> Building WiFi Proxy Switcher (${CONFIG})..."
swift build $SWIFT_FLAGS 2>&1

BINARY=".build/${CONFIG}/ProxyToggle"
APP_DIR="WiFiProxySwitcher.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "==> Creating .app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

cp "${BINARY}" "${MACOS}/ProxyToggle"
cp "Resources/Info.plist" "${CONTENTS}/Info.plist"

# Ad-hoc code sign (works without a Developer ID for local use)
echo "==> Code signing (ad-hoc)..."
codesign --force --deep --sign - "${APP_DIR}"

# Remove quarantine flag so macOS Gatekeeper doesn't block local builds
echo "==> Removing quarantine attribute..."
xattr -cr "${APP_DIR}" 2>/dev/null || true

echo ""
echo "✅  Build complete: ${APP_DIR}"
echo ""
echo "To run:"
echo "   open ${APP_DIR}"
echo ""
echo "To install permanently:"
echo "   cp -r ${APP_DIR} /Applications/"
echo "   open /Applications/${APP_DIR}"
