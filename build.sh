#!/bin/zsh
set -e
cd "$(dirname "$0")"
A=build/RaccoonPrint.app; rm -rf build; mkdir -p $A/Contents/MacOS $A/Contents/Resources build/i.iconset dist
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 -o $A/Contents/MacOS/RaccoonPrint Sources/*.swift
cp Info.plist $A/Contents/
swift icon.swift build/icon.png
for s in 16 32 128 256 512; do sips -z $s $s build/icon.png --out build/i.iconset/icon_${s}x${s}.png >/dev/null; sips -z $((s*2)) $((s*2)) build/icon.png --out build/i.iconset/icon_${s}x${s}@2x.png >/dev/null; done
iconutil -c icns build/i.iconset -o $A/Contents/Resources/AppIcon.icns
codesign --force --options runtime --entitlements RaccoonPrint.entitlements -s - $A
mkdir build/dmg; cp -R $A build/dmg/; ln -s /Applications build/dmg/Applications
hdiutil create -quiet -ov -volname RaccoonPrint -srcfolder build/dmg -format UDZO dist/RaccoonPrint.dmg
(cd dist && shasum -a 256 RaccoonPrint.dmg > RaccoonPrint.dmg.sha256)
codesign --verify --strict $A && ls -lh dist
