#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="SimulationPositioning.app"
NAME="SimulationPositioning"

if [ ! -f AppIcon.png ]; then
    echo "==> 生成 AppIcon.png"
    swift make_icon.swift AppIcon.png
fi

echo "==> 生成 AppIcon.icns"
rm -rf AppIcon.iconset
mkdir AppIcon.iconset
sips -z 16 16   AppIcon.png --out AppIcon.iconset/icon_16x16.png        >/dev/null
sips -z 32 32   AppIcon.png --out AppIcon.iconset/icon_16x16@2x.png     >/dev/null
sips -z 32 32   AppIcon.png --out AppIcon.iconset/icon_32x32.png        >/dev/null
sips -z 64 64   AppIcon.png --out AppIcon.iconset/icon_32x32@2x.png     >/dev/null
sips -z 128 128 AppIcon.png --out AppIcon.iconset/icon_128x128.png      >/dev/null
sips -z 256 256 AppIcon.png --out AppIcon.iconset/icon_128x128@2x.png   >/dev/null
sips -z 256 256 AppIcon.png --out AppIcon.iconset/icon_256x256.png      >/dev/null
sips -z 512 512 AppIcon.png --out AppIcon.iconset/icon_256x256@2x.png   >/dev/null
sips -z 512 512 AppIcon.png --out AppIcon.iconset/icon_512x512.png      >/dev/null
cp AppIcon.png AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns AppIcon.iconset -o AppIcon.icns

echo "==> 编译"
swiftc -O -framework AppKit -framework CoreLocation -framework MapKit main.swift -o "$NAME"

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$NAME" "$APP/Contents/MacOS/$NAME"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Simulation Positioning</string>
	<key>CFBundleDisplayName</key><string>模拟定位</string>
	<key>CFBundleIdentifier</key><string>local.simulationpositioning</string>
	<key>CFBundleVersion</key><string>1.0</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleExecutable</key><string>SimulationPositioning</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>LSMinimumSystemVersion</key><string>11.0</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> 签名"
codesign --force --deep --sign - "$APP"

echo "==> 完成: $APP"
