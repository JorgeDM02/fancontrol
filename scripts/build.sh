#!/bin/bash
# scripts/build.sh — release build + .app bundle assembly + ad-hoc signing.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="release"
BIN_DIR="$(swift build --show-bin-path -c "$CONFIG")"

APP_NAME="FanControl"
BUNDLE="build/${APP_NAME}.app"
HELPER_LABEL="com.fancontrol.helper"
HELPER_PLIST_SRC="Sources/FanControlHelper/Resources/${HELPER_LABEL}.plist"
INFO_PLIST="Sources/FanControlApp/Resources/Info.plist"

echo "==> swift build (release)"
swift build -c "$CONFIG"

echo "==> assembling ${BUNDLE}"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"
mkdir -p "${BUNDLE}/Contents/Library/LaunchDaemons"

cp "${BIN_DIR}/FanControl"        "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${BIN_DIR}/FanControlHelper"  "${BUNDLE}/Contents/MacOS/${HELPER_LABEL}"
cp "${INFO_PLIST}"                 "${BUNDLE}/Contents/Info.plist"
cp "${HELPER_PLIST_SRC}"           "${BUNDLE}/Contents/Library/LaunchDaemons/${HELPER_LABEL}.plist"

# Optionally bake an app icon if one exists (appicon.png or AppIcon.icns).
if [[ -f "appicon.png" ]]; then
    echo "==> generating AppIcon.icns from appicon.png"
    TMP_ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "${TMP_ICONSET}"
    for pair in \
        "16 icon_16x16.png" \
        "32 icon_16x16@2x.png" \
        "32 icon_32x32.png" \
        "64 icon_32x32@2x.png" \
        "128 icon_128x128.png" \
        "256 icon_128x128@2x.png" \
        "256 icon_256x256.png" \
        "512 icon_256x256@2x.png" \
        "512 icon_512x512.png" \
        "1024 icon_512x512@2x.png"; do
        set -- $pair
        sips -z "$1" "$1" "appicon.png" --out "${TMP_ICONSET}/$2" >/dev/null
    done
    iconutil -c icns "${TMP_ICONSET}" -o "${BUNDLE}/Contents/Resources/AppIcon.icns"
    rm -rf "${TMP_ICONSET}"
fi

echo "==> ad-hoc signing"
codesign --force --sign - --timestamp=none \
    "${BUNDLE}/Contents/MacOS/${HELPER_LABEL}"
codesign --force --sign - --timestamp=none \
    "${BUNDLE}/Contents/MacOS/${APP_NAME}"
if [[ -f "${BUNDLE}/Contents/Resources/AppIcon.icns" ]]; then
    codesign --force --sign - --timestamp=none \
        "${BUNDLE}/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi
codesign --force --sign - --timestamp=none "${BUNDLE}"

echo "==> verify"
codesign --verify --verbose "${BUNDLE}" || true

echo "==> done: ${BUNDLE}"
ls -lh "${BUNDLE}/Contents/MacOS/"