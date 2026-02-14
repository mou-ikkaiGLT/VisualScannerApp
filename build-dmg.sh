#!/bin/bash
set -e

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/VisualScanner-*/Build/Products/Release -name "VisualScanner.app" -maxdepth 1 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Error: No Release build found. Build with Release configuration in Xcode first."
    exit 1
fi

echo "Found app at: $APP_PATH"

# Work on a copy so we don't modify the Xcode build output
STAGING="/tmp/VisualScanner-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/VisualScanner.app"
STAGED_APP="$STAGING/VisualScanner.app"

# Sign the app bundle
echo "Signing app bundle..."
codesign --force --sign - "$STAGED_APP"

# Verify
echo "Verifying signature..."
codesign --verify --verbose "$STAGED_APP"

# Build DMG
echo "Creating DMG..."
DMG_DIR="/tmp/VisualScanner-dmg"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$STAGED_APP" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

DMG_OUTPUT=~/Desktop/VisualScanner.dmg
rm -f "$DMG_OUTPUT"
hdiutil create -volname "VisualScanner" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_OUTPUT"

# Clean up
rm -rf "$STAGING" "$DMG_DIR"

echo ""
echo "Done! DMG created at: $DMG_OUTPUT"
echo ""
echo "Note: Recipients should right-click → Open on first launch."
echo "If they still get 'damaged' error, they can run:"
echo "  xattr -cr /Applications/VisualScanner.app"
