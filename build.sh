#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) MeetingFlash.app into ./build.
# Usage: ./build.sh [version]
set -euo pipefail
cd "$(dirname "$0")"
VERSION=${1:-0.0.0-dev}
APP=build/MeetingFlash.app

rm -rf build
mkdir -p "$APP/Contents/MacOS" build/obj
cp Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macosx14.0 \
    -framework AppKit -framework EventKit -framework ServiceManagement \
    Sources/*.swift -o build/obj/MeetingFlash-$arch
done
lipo -create build/obj/MeetingFlash-* -output "$APP/Contents/MacOS/MeetingFlash"

codesign --force --sign - "$APP"
echo "Built $APP ($VERSION)"
