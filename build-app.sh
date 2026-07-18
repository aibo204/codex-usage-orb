#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

mkdir -p "$ROOT/.build/release"
for ARCH in arm64 x86_64; do
  xcrun swiftc \
    -O \
    -target "$ARCH-apple-macos12.0" \
    -framework AppKit \
    -framework SwiftUI \
    "$ROOT"/Sources/CodexUsageOrb/*.swift \
    -o "$ROOT/.build/release/CodexUsageOrb-$ARCH"
done

xcrun lipo -create \
  "$ROOT/.build/release/CodexUsageOrb-arm64" \
  "$ROOT/.build/release/CodexUsageOrb-x86_64" \
  -output "$ROOT/.build/release/CodexUsageOrb"

APP="$ROOT/dist/Codex Usage Orb.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/CodexUsageOrb" "$APP/Contents/MacOS/CodexUsageOrb"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

IDENTITY="${CODE_SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
echo "$APP"
