#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

: "${CODE_SIGN_IDENTITY:?请设置 Developer ID Application 证书名称}"
: "${NOTARY_PROFILE:?请设置 notarytool 钥匙串配置名称}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
APP="$ROOT/dist/Codex Usage Orb.app"
DMG="$ROOT/dist/CodexUsageOrb-$VERSION.dmg"
STAGE="$ROOT/.build/dmg-stage"

CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" "$ROOT/build-app.sh"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
  -volname "Codex Usage Orb $VERSION" \
  -srcfolder "$STAGE" \
  -format UDZO \
  -ov \
  "$DMG"

codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
hdiutil verify "$DMG"
shasum -a 256 "$DMG" | tee "$DMG.sha256"

echo "正式发布包：$DMG"
