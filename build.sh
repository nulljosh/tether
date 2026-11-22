#!/bin/sh
# Builds Tether and installs it to /Applications.
set -e
cd "$(dirname "$0")"
OUT="build/Tether.app"
rm -rf build
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
swiftc -O -parse-as-library -target arm64-apple-macos26.0 Tether.swift -o "$OUT/Contents/MacOS/Tether"
xcrun actool Tether.icon --compile "$OUT/Contents/Resources" --app-icon Tether --platform macosx \
  --minimum-deployment-target 26.0 --output-partial-info-plist build/icon.plist >/dev/null
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
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Tether uses Bluetooth to reconnect your mouse.</string>
</dict></plist>
EOF
# Developer ID keeps the Bluetooth permission across rebuilds; ad-hoc asks again every build.
codesign -f -o runtime -s "Developer ID Application: Joshua Trommel (QMM486NPYC)" "$OUT"
rm -rf "/Applications/Tether.app" "/Applications/Connect Mouse.app"
cp -R "$OUT" "/Applications/Tether.app"
echo "Installed /Applications/Tether.app"
