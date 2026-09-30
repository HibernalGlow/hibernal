#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:a:h}
APP_NAME="Hibernate Control"
BUILD_DIR="$SCRIPT_DIR/build"
DIST_DIR="$SCRIPT_DIR/dist"
RELEASES_DIR="$SCRIPT_DIR/releases"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
SOURCES_DIR="$SCRIPT_DIR/Sources/HibernateControl"
HELPER_SOURCES_DIR="$SCRIPT_DIR/Sources/HibernateHelper"
SHARED_SOURCES_DIR="$SCRIPT_DIR/Sources/Shared"
VERSION=$(cat "$SCRIPT_DIR/VERSION")

# swiftc/ld only leaves an ad-hoc *linker* signature on each executable, which seals
# neither Info.plist nor resources; such a bundle reads as "damaged" once it arrives
# through a quarantined download. Ad-hoc is the floor, not the ceiling: a Developer ID
# identity here is what lets other machines open it without a Gatekeeper override.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
HELPER_IDENTIFIER="com.hibernatecontrol.helper"
BUNDLE_IDENTIFIER="com.hibernatecontrol.app"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" \
  "$DIST_DIR/$APP_NAME.app/Contents/MacOS" \
  "$DIST_DIR/$APP_NAME.app/Contents/Resources" \
  "$DIST_DIR/$APP_NAME.app/Contents/Library/LaunchServices" \
  "$RELEASES_DIR"

SDK=$(xcrun --show-sdk-path)
TARGET="$(uname -m)-apple-macos13.0"

swiftc -O \
  -sdk "$SDK" \
  -target "$TARGET" \
  -o "$BUILD_DIR/HibernateHelper" \
  "$SHARED_SOURCES_DIR/HibernateHelperProtocol.swift" \
  "$HELPER_SOURCES_DIR/main.swift" \
  -framework Foundation

swiftc -O \
  -sdk "$SDK" \
  -target "$TARGET" \
  -o "$BUILD_DIR/HibernateControl" \
  "$SHARED_SOURCES_DIR/HibernateHelperProtocol.swift" \
  "$SOURCES_DIR"/*.swift \
  -framework AppKit \
  -framework Carbon \
  -framework ServiceManagement \
  -framework SwiftUI

cp "$BUILD_DIR/HibernateControl" "$APP_BUNDLE/Contents/MacOS/HibernateControl"
chmod +x "$APP_BUNDLE/Contents/MacOS/HibernateControl"

cp "$BUILD_DIR/HibernateHelper" "$APP_BUNDLE/Contents/Library/LaunchServices/HibernateHelper"
chmod +x "$APP_BUNDLE/Contents/Library/LaunchServices/HibernateHelper"

ICON_SOURCE="$SCRIPT_DIR/Resources/AppIcon.icns"
if [[ -f "$ICON_SOURCE" ]]; then
    cp "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>HibernateControl</string>
    <key>CFBundleIdentifier</key>
    <string>com.hibernatecontrol.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Hibernate Control</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

ARCHIVE_PATH="$RELEASES_DIR/$APP_NAME-$VERSION.app"

# Inside-out: nested Mach-O first, then the bundle seal.
codesign --force --sign "$SIGN_IDENTITY" \
  --identifier "$HELPER_IDENTIFIER" \
  "$APP_BUNDLE/Contents/Library/LaunchServices/HibernateHelper"

codesign --force --sign "$SIGN_IDENTITY" \
  --identifier "$BUNDLE_IDENTIFIER" \
  "$APP_BUNDLE"

# Gate: this is exactly the check LaunchServices applies before it calls an app damaged.
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -rf "$ARCHIVE_PATH"
ditto "$APP_BUNDLE" "$ARCHIVE_PATH"
codesign --verify --deep --strict "$ARCHIVE_PATH"

echo "Built $APP_BUNDLE"
echo "Archived $ARCHIVE_PATH"
echo "Signed with: $SIGN_IDENTITY"
echo "Open with: open \"$APP_BUNDLE\""