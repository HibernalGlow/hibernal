#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:a:h}
APP_NAME="Hibernal"
BUILD_DIR="$SCRIPT_DIR/build"
DIST_DIR="$SCRIPT_DIR/dist"
RELEASES_DIR="$SCRIPT_DIR/releases"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
SOURCES_DIR="$SCRIPT_DIR/Sources/Hibernal"
HELPER_SOURCES_DIR="$SCRIPT_DIR/Sources/HibernalHelper"
SHARED_SOURCES="$SCRIPT_DIR/Sources/Shared/HibernalHelperProtocol.swift"
VERSION=$(cat "$SCRIPT_DIR/VERSION")
MIN_MACOS=13.0

# swiftc/ld only leaves an ad-hoc *linker* signature on each executable, which seals
# neither Info.plist nor resources; such a bundle reads as "damaged" once it arrives
# through a quarantined download. Ad-hoc is the floor, not the ceiling: a Developer ID
# identity here is what lets other machines open it without a Gatekeeper override.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
HELPER_IDENTIFIER="com.hibernal.helper"
BUNDLE_IDENTIFIER="com.hibernal.app"

# Universal by default so one DMG serves Apple Silicon and Intel; override with
# ARCHS=arm64 for a quick native-only build.
ARCHS=${ARCHS:-arm64 x86_64}
archs=(${=ARCHS})

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" \
  "$APP_BUNDLE/Contents/MacOS" \
  "$APP_BUNDLE/Contents/Resources" \
  "$APP_BUNDLE/Contents/Library/LaunchServices" \
  "$RELEASES_DIR"

SDK=$(xcrun --show-sdk-path)

helper_slices=()
app_slices=()
for arch in $archs; do
    swiftc -O \
      -sdk "$SDK" \
      -target "$arch-apple-macos$MIN_MACOS" \
      -o "$BUILD_DIR/HibernalHelper-$arch" \
      "$SHARED_SOURCES" \
      "$HELPER_SOURCES_DIR/main.swift" \
      -framework Foundation

    swiftc -O \
      -sdk "$SDK" \
      -target "$arch-apple-macos$MIN_MACOS" \
      -o "$BUILD_DIR/Hibernal-$arch" \
      "$SHARED_SOURCES" \
      "$SOURCES_DIR"/*.swift \
      -framework AppKit \
      -framework Carbon \
      -framework ServiceManagement \
      -framework SwiftUI

    helper_slices+=("$BUILD_DIR/HibernalHelper-$arch")
    app_slices+=("$BUILD_DIR/Hibernal-$arch")
done

lipo -create -output "$BUILD_DIR/HibernalHelper" "${helper_slices[@]}"
lipo -create -output "$BUILD_DIR/Hibernal" "${app_slices[@]}"

/bin/cp "$BUILD_DIR/Hibernal" "$APP_BUNDLE/Contents/MacOS/Hibernal"
chmod +x "$APP_BUNDLE/Contents/MacOS/Hibernal"

/bin/cp "$BUILD_DIR/HibernalHelper" "$APP_BUNDLE/Contents/Library/LaunchServices/HibernalHelper"
chmod +x "$APP_BUNDLE/Contents/Library/LaunchServices/HibernalHelper"

ICON_SOURCE="$SCRIPT_DIR/Resources/AppIcon.icns"
if [[ -f "$ICON_SOURCE" ]]; then
    cp "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# (N) = null glob: no .lproj directories must not abort the build.
languages=(en)
for lproj in "$SCRIPT_DIR"/Resources/*.lproj(N); do
    ditto "$lproj" "$APP_BUNDLE/Contents/Resources/${lproj:t}"
    lang=${${lproj:t}%.lproj}
    [[ ${languages[(Ie)$lang]} -ne 0 ]] && continue
    languages+=$lang
done

localization_entries=""
for lang in $languages; do
    localization_entries+="    <string>$lang</string>"$'\n'
done

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
${localization_entries}    </array>
    <key>CFBundleExecutable</key>
    <string>Hibernal</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
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
    <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# Inside-out: nested Mach-O first, then the bundle seal.
codesign --force --sign "$SIGN_IDENTITY" \
  --identifier "$HELPER_IDENTIFIER" \
  "$APP_BUNDLE/Contents/Library/LaunchServices/HibernalHelper"

codesign --force --sign "$SIGN_IDENTITY" \
  --identifier "$BUNDLE_IDENTIFIER" \
  "$APP_BUNDLE"

# Gate: this is exactly the check LaunchServices applies before it calls an app damaged.
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
echo "Architectures: $(lipo -archs "$APP_BUNDLE/Contents/MacOS/Hibernal")"
echo "Signed with: $SIGN_IDENTITY"
echo "Open with: open \"$APP_BUNDLE\""
