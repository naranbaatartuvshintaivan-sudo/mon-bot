#!/bin/bash
# DeskBot.app үүсгэнэ: `swift build -c release` → build/DeskBot.app (ad-hoc codesign).
#   scripts/bundle.sh            # build/DeskBot.app
#   open build/DeskBot.app
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="dev.deskbot.DeskBot"          # Log.swift-ийн os.Logger subsystem-тэй ижил
VERSION="${DESKBOT_VERSION:-0.2.0}"
BUILD_NUMBER="${DESKBOT_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="build/DeskBot.app"

swift build -c release --product DeskBot
BIN="$(swift build -c release --show-bin-path)/DeskBot"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DeskBot"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>            <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>                  <string>DeskBot</string>
    <key>CFBundleDisplayName</key>           <string>DeskBot</string>
    <key>CFBundleExecutable</key>            <string>DeskBot</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>${VERSION}</string>
    <key>CFBundleVersion</key>               <string>${BUILD_NUMBER}</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSHighResolutionCapable</key>       <true/>
</dict>
</plist>
EOF
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Ad-hoc гарын үсэг (-s -). Gatekeeper notarization биш — зөвхөн энэ Mac дээр ажиллуулахад.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "Built $APP ($BUNDLE_ID $VERSION ($BUILD_NUMBER))"
