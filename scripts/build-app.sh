#!/bin/bash
# Builds "AWS Account Mixer.app" in build/. With --install it also copies the app to /Applications.
# Custom bundle identifier: BUNDLE_ID=com.example.aws-account-mixer ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/AWS Account Mixer.app"
ICON="build/AppIcon.icns"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/AWSAccountMixer"

if [ ! -f "$ICON" ] || [ scripts/make-icon.swift -nt "$ICON" ]; then
    ICONSET="build/AppIcon.iconset"
    rm -rf "$ICONSET" && mkdir -p "$ICONSET"
    swift scripts/make-icon.swift build/icon-1024.png
    for size in 16 32 128 256 512; do
        sips -z $size $size build/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) build/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$ICON"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AWSAccountMixer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${BUNDLE_ID:-}" ]; then
    plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# A stable certificate keeps the Keychain from asking for access after every rebuild. Without one: ad hoc signature.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
echo "Built: $APP (signed with: ${IDENTITY:-ad hoc})"

if [ "${1:-}" = "--install" ]; then
    rm -rf "/Applications/AWS Account Mixer.app"
    cp -R "$APP" /Applications/
    echo "Installed: /Applications/AWS Account Mixer.app"
fi
