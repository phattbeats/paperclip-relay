#!/usr/bin/env bash
# build-ios.sh — build Paperclip Relay for iOS and package an unsigned .ipa.
#
# macOS only (it needs Xcode's iOS SDK). CI runs it on a macOS runner; a
# human with a Mac runs it the same way.
#
# What it produces:
#
#   build/DerivedData/Build/Products/Release-iphoneos/Relay.app
#   build/Relay-unsigned.ipa
#
# The build is unsigned on purpose. "Sideloaded only, no licensing" is the
# point: no Apple Developer Program account, no App Store record, no
# provisioning profile. The .ipa is installed with AltStore/SideStore or
# signed locally with a personal team — the same shape as the Chlorophone
# iOS build (PHA-4552).

set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$IOS_DIR/build"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "build-ios.sh: missing dependency: $1" >&2
    exit 1
  }
}
need xcrun
need xcodebuild
need xcodegen
need zip

echo "build-ios.sh: Xcode $(xcodebuild -version | head -1 | sed 's/^Xcode //')"
xcrun --sdk iphoneos --show-sdk-path

echo "build-ios.sh: generating the Xcode project from project.yml"
cd "$IOS_DIR"
xcodegen generate
ls -la Relay.xcodeproj

echo "build-ios.sh: building the app (unsigned, device)"
set -o pipefail
xcodebuild \
  -project Relay.xcodeproj \
  -scheme Relay \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build | tee "$BUILD_DIR/xcodebuild-device.log"

APP="$BUILD_DIR/DerivedData/Build/Products/Release-iphoneos/Relay.app"
test -d "$APP"

echo "build-ios.sh: packaging the .ipa"
rm -rf "$BUILD_DIR/Payload" "$BUILD_DIR/Relay-unsigned.ipa"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP" "$BUILD_DIR/Payload/"
cd "$BUILD_DIR"
# The app bundle has to sit under Payload/ — that is what every installer
# (AltStore, SideStore, Apple Configurator) looks for.
zip -qry Relay-unsigned.ipa Payload
ls -la Relay-unsigned.ipa
unzip -l Relay-unsigned.ipa | head -25
unzip -l Relay-unsigned.ipa | grep -q "Payload/Relay.app/Info.plist" \
  || { echo "build-ios.sh: ERROR — the .ipa has no Payload/Relay.app/Info.plist" >&2; exit 1; }

echo "build-ios.sh: done -> $BUILD_DIR/Relay-unsigned.ipa"
