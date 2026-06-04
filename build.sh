#!/usr/bin/env bash
# =============================================================================
# build.sh — Build and install DailyWalls.app
# Usage:
#   ./build.sh                        — build only, output to ./DailyWalls.app
#   ./build.sh --arch arm64           — build for Apple Silicon
#   ./build.sh --arch x86_64          — build for Intel
#   ./build.sh install                — build + copy to /Applications
#   ./build.sh --arch arm64 install   — build arm64 + copy to /Applications
# =============================================================================
set -euo pipefail

APP_NAME="DailyWalls"
BUNDLE_NAME="DailyWalls.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments: optional --arch <arm64|x86_64> and optional "install"
ARCH=""
INSTALL=false
TAKE_ARCH=false
for arg in "$@"; do
    if [[ "$TAKE_ARCH" == true ]]; then
        ARCH="$arg"
        TAKE_ARCH=false
    elif [[ "$arg" == "--arch" ]]; then
        TAKE_ARCH=true
    elif [[ "$arg" == "install" ]]; then
        INSTALL=true
    fi
done

if [[ -n "$ARCH" ]]; then
    echo "==> Building ${APP_NAME} (release, ${ARCH})..."
    swift build -c release --product "${APP_NAME}" --arch "${ARCH}"
    BINARY_PATH="${SCRIPT_DIR}/.build/${ARCH}-apple-macosx/release/${APP_NAME}"
    RESOURCES_BUNDLE="${SCRIPT_DIR}/.build/${ARCH}-apple-macosx/release/DailyWalls_DailyWalls.bundle"
else
    echo "==> Building ${APP_NAME} (release)..."
    swift build -c release --product "${APP_NAME}"
    BINARY_PATH="${SCRIPT_DIR}/.build/release/${APP_NAME}"
    RESOURCES_BUNDLE="${SCRIPT_DIR}/.build/release/DailyWalls_DailyWalls.bundle"
fi

if [[ ! -f "${BINARY_PATH}" ]]; then
    echo "ERROR: Binary not found at ${BINARY_PATH}"
    exit 1
fi

# --------------------------------------------------------------------------
# Assemble .app bundle
# --------------------------------------------------------------------------
APP_DIR="${SCRIPT_DIR}/${BUNDLE_NAME}"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "==> Assembling ${BUNDLE_NAME}..."

# Binary
cp "${BINARY_PATH}" "${MACOS_DIR}/DailyWalls"

# Info.plist
cp "${SCRIPT_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist"

# Icon — convert PNG to ICNS for the .app bundle Finder icon
APP_ICON_PNG="${SCRIPT_DIR}/Sources/${APP_NAME}/Resources/AppIcon.png"
if [ -f "${APP_ICON_PNG}" ]; then
    # Create .icns if sips + iconutil are available
    ICONSET_DIR="/tmp/${APP_NAME}.iconset"
    mkdir -p "${ICONSET_DIR}"
    for size in 16 32 64 128 256 512; do
        sips -s format png -z ${size} ${size} "${APP_ICON_PNG}" --out "${ICONSET_DIR}/icon_${size}x${size}.png" > /dev/null 2>&1
        sips -s format png -z $((size*2)) $((size*2)) "${APP_ICON_PNG}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" > /dev/null 2>&1
    done
    iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns" 2>/dev/null || true
    rm -rf "${ICONSET_DIR}"
fi

# Copy the raw monochrome PNG for menu bar use
MENUBAR_PNG="${SCRIPT_DIR}/Sources/${APP_NAME}/Resources/menubar_icon.png"
if [ -f "${MENUBAR_PNG}" ]; then
    cp "${MENUBAR_PNG}" "${RESOURCES_DIR}/menubar_icon.png"
fi

# Copy SPM-generated bundle resources (the .resources directory, if any)
if [[ -d "${RESOURCES_BUNDLE}" ]]; then
    cp -r "${RESOURCES_BUNDLE}" "${RESOURCES_DIR}/"
fi

# Ad-hoc code sign so Gatekeeper doesn't block on first launch
echo "==> Code signing (ad-hoc)..."
codesign --force --sign - --deep "${APP_DIR}" 2>/dev/null || true

echo "==> Built: ${APP_DIR}"

# --------------------------------------------------------------------------
# Optional install
# --------------------------------------------------------------------------
if [[ "$INSTALL" == true ]]; then
    INSTALL_PATH="/Applications/${BUNDLE_NAME}"
    echo "==> Installing to ${INSTALL_PATH}..."

    # Remove old version and stop it if running
    pkill -x "DailyWalls" 2>/dev/null || true
    rm -rf "${INSTALL_PATH}"
    cp -r "${APP_DIR}" "${INSTALL_PATH}"

    echo "==> Installed successfully."
    echo ""
    echo "    First launch: right-click → Open (Gatekeeper requires this once for ad-hoc signed apps)"
    echo "    Or run:  open /Applications/${BUNDLE_NAME}"
    echo ""
    open "${INSTALL_PATH}"
fi

echo "==> Done."
