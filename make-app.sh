#!/bin/bash
# 打包成可双击运行的 CharDiff.app
set -e
cd "$(dirname "$0")"

swift build -c release

APP="CharDiff.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CharDiff "$APP/Contents/MacOS/CharDiff"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>CharDiff</string>
	<key>CFBundleIdentifier</key>
	<string>local.chardiff</string>
	<key>CFBundleName</key>
	<string>字体字符对比</string>
	<key>CFBundleDisplayName</key>
	<string>字体字符对比</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

echo "已生成：$(pwd)/$APP"
