#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache 'dist/Sticky Notes.app/Contents/MacOS'
# Remove only our custom icon metadata before signing the next build.
swift -module-cache-path .build/module-cache scripts/set-app-icon.swift --clear
xattr -d com.apple.FinderInfo 'dist/Sticky Notes.app' 2>/dev/null || true
swiftc -O -module-cache-path .build/module-cache Sources/StickyNotes/*.swift -o 'dist/Sticky Notes.app/Contents/MacOS/StickyNotes'
mkdir -p .build/AppIcon.iconset 'dist/Sticky Notes.app/Contents/Resources'
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/AppIcon.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Assets/AppIcon.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 scripts/package-icon.py
cp Assets/AppIcon.png 'dist/Sticky Notes.app/Contents/Resources/DockIcon.png' 
cat > 'dist/Sticky Notes.app/Contents/Info.plist'  <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>StickyNotes</string>
<key>CFBundleIdentifier</key><string>local.stickynotes.mac</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Sticky Notes</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 scripts/version.py
codesign --force --sign - 'dist/Sticky Notes.app'

codesign --verify --deep --strict 'dist/Sticky Notes.app'
# Finder custom icons bypass the system's legacy icon background treatment.
swift -module-cache-path .build/module-cache scripts/set-app-icon.swift
codesign --verify --deep 'dist/Sticky Notes.app'
python3 scripts/version.py --commit
