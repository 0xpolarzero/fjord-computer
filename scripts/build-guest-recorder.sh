#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="${GUEST_RECORDER_ARCH:-arm64}"
OUT="build/GuestRuns"
APP="$OUT/GuestRecorder.app"
SOURCE="Resources/GuestRuns/GuestRecorder.swift"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

xcrun swiftc -O -parse-as-library -target "$ARCH-apple-macosx14.0" \
  -framework AppKit -framework AVFoundation -framework CoreMedia -framework ScreenCaptureKit \
  -o "$APP/Contents/MacOS/GuestRecorder" "$SOURCE"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.fjord.guestruns.recorder</string>
  <key>CFBundleName</key><string>GuestRecorder</string>
  <key>CFBundleExecutable</key><string>GuestRecorder</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSBackgroundOnly</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSScreenCaptureUsageDescription</key><string>Fjord records the guest computer while a Triage run is in progress.</string>
</dict>
</plist>
PLIST
IDENTITY="${SIGN_IDENTITY:-Fjord Dev}"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --timestamp=none --sign "$IDENTITY" "$APP"
elif [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "Signing identity \"$IDENTITY\" not found" >&2
  exit 1
else
  codesign --force --sign - "$APP"
fi
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/GuestRecorder.app.zip"
echo "Built $OUT/GuestRecorder.app.zip for $ARCH"
