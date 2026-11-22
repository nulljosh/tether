#!/bin/sh
# Builds Tether and installs it to /Applications.
# ./build.sh release also notarizes it and publishes Tether.zip as a GitHub release for the version in the plist.
set -e
cd "$(dirname "$0")"
OUT="build/Tether.app"
rm -rf build
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources/Fonts"
cp fonts/*.ttf fonts/OFL.txt "$OUT/Contents/Resources/Fonts/"
# Universal: Apple silicon from macOS 11, Intel from 10.15 (the oldest with Swift and CBManager.authorization built in).
swiftc -O -target arm64-apple-macos11.0 Tether.swift -o build/Tether-arm64
swiftc -O -target x86_64-apple-macos10.15 Tether.swift -o build/Tether-x86_64
lipo -create build/Tether-arm64 build/Tether-x86_64 -output "$OUT/Contents/MacOS/Tether"
xcrun actool Tether.icon --compile "$OUT/Contents/Resources" --app-icon Tether --platform macosx \
  --minimum-deployment-target 10.15 --output-partial-info-plist build/icon.plist >/dev/null
cat > "$OUT/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Tether</string>
  <key>CFBundleDisplayName</key><string>Tether</string>
  <key>CFBundleIdentifier</key><string>com.nulljosh.tether</string>
  <key>CFBundleExecutable</key><string>Tether</string>
  <key>CFBundleIconFile</key><string>Tether</string>
  <key>CFBundleIconName</key><string>Tether</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2.0</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>ATSApplicationFontsPath</key><string>Fonts</string>
  <key>LSMinimumSystemVersion</key><string>10.15</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Tether uses Bluetooth to reconnect your mouse.</string>
</dict></plist>
EOF
# Developer ID keeps the Bluetooth permission across rebuilds; ad-hoc asks again every build.
# CI has no signing identity, so it signs ad-hoc and stops before installing.
ID="Developer ID Application: Joshua Trommel (QMM486NPYC)"
if security find-identity -v -p codesigning | grep -qF "$ID"; then
  codesign -f -o runtime --timestamp -s "$ID" "$OUT"
elif [ -n "$CI" ]; then
  codesign -f -s - "$OUT"
else
  echo "No Developer ID in the keychain (locked?). Refusing to install an ad-hoc build: it would lose the Bluetooth grant." >&2
  exit 1
fi
[ -n "$CI" ] && { echo "Built $OUT"; exit 0; }
rm -rf "/Applications/Tether.app" "/Applications/Connect Mouse.app"
cp -R "$OUT" "/Applications/Tether.app"
echo "Installed /Applications/Tether.app"

[ "$1" = release ] || exit 0
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$OUT/Contents/Info.plist")
# A version ships once. Bump CFBundleShortVersionString for a new release; REPLACE=1 swaps the zip on purpose.
if gh release view "v$VERSION" >/dev/null 2>&1 && [ -z "$REPLACE" ]; then echo "v$VERSION is already released. Bump the version." >&2; exit 1; fi
[ -z "$(git status --porcelain)" ] || { echo "Commit first, so the tag matches what was built." >&2; exit 1; }
ditto -c -k --keepParent "$OUT" build/Tether.zip
asc notarization submit --file build/Tether.zip --wait --poll-interval 20s --timeout 30m
xcrun stapler staple "$OUT"
rm build/Tether.zip && ditto -c -k --keepParent "$OUT" build/Tether.zip
spctl -a -vv "$OUT"
gh release create "v$VERSION" build/Tether.zip --title "Tether $VERSION" --notes "Download Tether.zip, unzip, drag Tether to Applications. Signed and notarized. macOS 10.15 or later, Intel and Apple silicon." --generate-notes --target "$(git rev-parse HEAD)" 2>/dev/null \
  || { [ -n "$REPLACE" ] && gh release upload "v$VERSION" build/Tether.zip --clobber; }
