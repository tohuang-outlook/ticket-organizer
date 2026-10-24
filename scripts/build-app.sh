#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${MARKETING_VERSION:-1.0.0}"
VERSION="${VERSION#v}"
BUILD="${BUILD_NUMBER:-1}"
ARCH="$(uname -m)"
swift build -c release
PRODUCT="$ROOT/.build/${ARCH}-apple-macosx/release/TicketOrganizer"
if [ ! -f "$PRODUCT" ]; then PRODUCT="$ROOT/.build/arm64-apple-macosx/release/TicketOrganizer"; fi
if [ ! -f "$PRODUCT" ]; then PRODUCT="$ROOT/.build/out/Products/Release/TicketOrganizer"; fi
APP="$ROOT/dist/Ticket Organizer.app"
rm -rf "$ROOT/dist"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCT" "$APP/Contents/MacOS/TicketOrganizer"
chmod +x "$APP/Contents/MacOS/TicketOrganizer"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>Ticket Organizer</string>
<key>CFBundleExecutable</key><string>TicketOrganizer</string>
<key>CFBundleIdentifier</key><string>com.tohuang.ticket-organizer</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleName</key><string>Ticket Organizer</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>__VERSION__</string>
<key>CFBundleVersion</key><string>__BUILD__</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Huang Chen</string>
</dict></plist>
PLIST
sed -i '' "s/__VERSION__/$VERSION/g; s/__BUILD__/$BUILD/g" "$APP/Contents/Info.plist"
if [ -n "${SIGNING_IDENTITY:-}" ]; then codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"; fi
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/Ticket-Organizer-$VERSION.zip"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$ROOT/dist/Ticket-Organizer-$VERSION.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/Ticket-Organizer-$VERSION.zip"
fi
shasum -a 256 "$ROOT/dist/Ticket-Organizer-$VERSION.zip" > "$ROOT/dist/SHA256SUMS"
echo "Built: $APP"
echo "Archive: $ROOT/dist/Ticket-Organizer-$VERSION.zip"
