#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
trial_app=build/HiddenBarIntegration.app
mkdir -p "$trial_app/Contents/MacOS"
cat > "$trial_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.tradzero.hidden.integration</string>
<key>CFBundleExecutable</key><string>HiddenBarIntegration</string>
<key>CFBundleName</key><string>HiddenBarIntegration</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc -swift-version 5 -module-cache-path build/module-cache \
  hidden/Features/StatusBar/*.swift \
  hidden/Common/{Assets,Constant,Preferences}.swift \
  hidden/Models/GlobalKeybindingPreferences.swift \
  hidden/Extensions/{String,Notification.Name,UserDefault}+Extension.swift \
  hidden/Views/NSView+Extension.swift \
  tests/ControllerIntegration.swift -o "$trial_app/Contents/MacOS/HiddenBarIntegration"
echo "$trial_app/Contents/MacOS/HiddenBarIntegration"
