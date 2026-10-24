#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${MARKETING_VERSION:-$(< VERSION)}"
VERSION="${VERSION#v}"
BUILD="${BUILD_NUMBER:-1}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "Version must be X.Y.Z and build number must be numeric." >&2
  exit 1
fi
if [[ -n "${NOTARY_PROFILE:-}" && -z "${SIGNING_IDENTITY:-}" ]]; then
  echo "Notarization requires a Developer ID signing identity." >&2
  exit 1
fi
if [[ "${REQUIRE_NOTARIZATION:-0}" == 1 && ( -z "${SIGNING_IDENTITY:-}" || -z "${NOTARY_PROFILE:-}" ) ]]; then
  echo "Public distribution requires SIGNING_IDENTITY and NOTARY_PROFILE." >&2
  exit 1
fi

swift build -c release --arch arm64 --arch x86_64
PRODUCT_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
PRODUCT="$PRODUCT_DIR/TicketOrganizer"
[[ -f "$PRODUCT" ]] || { echo "Built executable not found: $PRODUCT" >&2; exit 1; }
ARCHITECTURES="$(lipo -archs "$PRODUCT")"
for EXPECTED_ARCH in arm64 x86_64; do
  case " $ARCHITECTURES " in
    *" $EXPECTED_ARCH "*) ;;
    *) echo "Missing architecture: $EXPECTED_ARCH" >&2; exit 1 ;;
  esac
done

mkdir -p "$ROOT/dist"
STAGING="$(mktemp -d "$ROOT/dist/.package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Ticket Organizer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCT" "$APP/Contents/MacOS/TicketOrganizer"
chmod +x "$APP/Contents/MacOS/TicketOrganizer"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
ARCHIVE="$STAGING/Ticket-Organizer-$VERSION.zip"
ditto -c -k --norsrc --keepParent "$APP" "$ARCHIVE"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
  ditto -c -k --norsrc --keepParent "$APP" "$ARCHIVE"
fi
unzip -t "$ARCHIVE" >/dev/null
if [[ -d "$ROOT/dist/Ticket Organizer.app" ]]; then
  mv "$ROOT/dist/Ticket Organizer.app" "$STAGING/previous.app"
fi
mv "$APP" "$ROOT/dist/Ticket Organizer.app"
mv "$ARCHIVE" "$ROOT/dist/Ticket-Organizer-$VERSION.zip"
(cd "$ROOT/dist" && shasum -a 256 "Ticket-Organizer-$VERSION.zip") > "$ROOT/dist/SHA256SUMS"
(cd "$ROOT/dist" && shasum -c SHA256SUMS)
echo "Built: $ROOT/dist/Ticket Organizer.app"
echo "Archive: $ROOT/dist/Ticket-Organizer-$VERSION.zip"
if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
  echo "Local build only: ad-hoc signed, not Developer ID signed or notarized."
fi
