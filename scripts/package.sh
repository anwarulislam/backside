#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Backside macOS Packaging Script
# Builds universal binary, creates Backside.app, packages .zip & .dmg, and
# generates SHA-256 checksums.
# -----------------------------------------------------------------------------

VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
ARCH="${ARCH:-universal}"
CREATE_DMG=true
CREATE_ZIP=true

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --identity)
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --arch)
      ARCH="$2"
      shift 2
      ;;
    --no-dmg)
      CREATE_DMG=false
      shift
      ;;
    --no-zip)
      CREATE_ZIP=false
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--version <ver>] [--build-number <num>] [--identity <id>] [--output-dir <dir>] [--arch <universal|arm64|x86_64|host>] [--no-dmg] [--no-zip]"
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# Auto-detect version if not supplied
if [ -z "$VERSION" ]; then
  if git describe --tags --exact-match 2>/dev/null; then
    VERSION="$(git describe --tags --exact-match | sed 's/^v//')"
  elif git describe --tags --abbrev=0 2>/dev/null; then
    VERSION="$(git describe --tags --abbrev=0 | sed 's/^v//')"
  else
    VERSION="1.0.0"
  fi
fi

# Auto-detect build number if not supplied
if [ -z "$BUILD_NUMBER" ]; then
  if git rev-list --count HEAD 2>/dev/null; then
    BUILD_NUMBER="$(git rev-list --count HEAD)"
  else
    BUILD_NUMBER="1"
  fi
fi

echo "=========================================="
echo " Packaging Backside macOS App"
echo " Version:       $VERSION"
echo " Build Number:  $BUILD_NUMBER"
echo " Architecture:  $ARCH"
echo " Sign Identity: $SIGN_IDENTITY"
echo " Output Dir:    $OUTPUT_DIR"
echo "=========================================="

# Build Swift executable
echo "==> Building Backside executable with Swift..."
if [ "$ARCH" = "universal" ]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN_PATH=".build/apple/Products/Release/Backside"
elif [ "$ARCH" = "host" ]; then
  swift build -c release
  BIN_PATH=".build/release/Backside"
else
  swift build -c release --arch "$ARCH"
  BIN_PATH=".build/apple/Products/Release/Backside"
fi

if [ ! -f "$BIN_PATH" ]; then
  echo "Error: Binary not found at $BIN_PATH"
  exit 1
fi

echo "==> Binary verified: $BIN_PATH"
file "$BIN_PATH"

# Setup Application Bundle structure
APP_NAME="Backside"
APP_BUNDLE="$OUTPUT_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Constructing ${APP_BUNDLE}..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Copy AppIcon if available
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Generate Info.plist
INFO_PLIST_TEMPLATE="Resources/Info.plist"
if [ -f "$INFO_PLIST_TEMPLATE" ]; then
  sed -e "s/__VERSION__/$VERSION/g" \
      -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" \
      "$INFO_PLIST_TEMPLATE" > "$CONTENTS_DIR/Info.plist"
else
  cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Backside</string>
    <key>CFBundleIdentifier</key>
    <string>com.backside.Backside</string>
    <key>CFBundleName</key>
    <string>Backside</string>
    <key>CFBundleDisplayName</key>
    <string>Backside</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Backside Contributors. All rights reserved.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>Backside requires Accessibility access to detect target window positions and attach scratchpads.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF
fi

# Code Signing
echo "==> Code signing bundle..."
if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "Applying ad-hoc code signature..."
  codesign --force --deep --sign - "$APP_BUNDLE"
else
  echo "Applying signature with identity: $SIGN_IDENTITY..."
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

mkdir -p "$OUTPUT_DIR"

# Package ZIP
if [ "$CREATE_ZIP" = true ]; then
  ZIP_NAME="${APP_NAME}-${VERSION}.zip"
  echo "==> Creating ZIP archive: $OUTPUT_DIR/$ZIP_NAME..."
  (cd "$OUTPUT_DIR" && ditto -c -k --keepParent "${APP_NAME}.app" "$ZIP_NAME")
fi

# Package DMG
if [ "$CREATE_DMG" = true ]; then
  DMG_NAME="${APP_NAME}-${VERSION}.dmg"
  echo "==> Creating DMG image: $OUTPUT_DIR/$DMG_NAME..."
  DMG_STAGE="$OUTPUT_DIR/dmg_stage"
  rm -rf "$DMG_STAGE"
  mkdir -p "$DMG_STAGE"
  cp -R "$APP_BUNDLE" "$DMG_STAGE/"
  ln -s /Applications "$DMG_STAGE/Applications"
  rm -f "$OUTPUT_DIR/$DMG_NAME"
  hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$OUTPUT_DIR/$DMG_NAME"
  rm -rf "$DMG_STAGE"
fi

# Generate Checksums
echo "==> Generating checksums..."
(
  cd "$OUTPUT_DIR"
  rm -f checksums.txt
  for f in "${APP_NAME}-${VERSION}"*.zip "${APP_NAME}-${VERSION}"*.dmg; do
    if [ -f "$f" ]; then
      shasum -a 256 "$f" > "${f}.sha256"
      shasum -a 256 "$f" >> checksums.txt
    fi
  done
)

echo "=========================================="
echo " Packaging completed successfully!"
echo " Artifacts in: $OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR"
echo "=========================================="
