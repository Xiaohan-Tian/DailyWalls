#!/usr/bin/env bash
# Usage: ./ci/package_dmg.sh <output.dmg> <DailyWalls.app>
set -euo pipefail

OUTPUT="$1"
APP_SRC="$2"
VOLNAME="DailyWalls"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ICON_SRC="$REPO_ROOT/Sources/DailyWalls/Resources/AppIcon.png"
VOLPATH="/Volumes/$VOLNAME"

WORK=$(mktemp -d)
RW_DMG="$WORK/rw.dmg"
BG_PNG="$WORK/background.png"

cleanup() {
    hdiutil detach "$VOLPATH" -force 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> Generating background image..."
BG_PATH="$BG_PNG" python3 << 'PYEOF'
import struct, zlib, os

def write_png(path, w, h, rows):
    def chunk(name, data):
        crc = zlib.crc32(name + data) & 0xffffffff
        return struct.pack('>I', len(data)) + name + data + struct.pack('>I', crc)
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
    raw = b''.join(b'\x00' + bytes([c for px in row for c in px]) for row in rows)
    idat = chunk(b'IDAT', zlib.compress(raw, 9))
    iend = chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(sig + ihdr + idat + iend)

w, h = 600, 380
rows = [[(int(25+(y/h)*15), int(28+(y/h)*15), int(40+(y/h)*22)) for _ in range(w)] for y in range(h)]
write_png(os.environ['BG_PATH'], w, h, rows)
PYEOF

echo "==> Building volume icon..."
ICONSET="$WORK/vol.iconset"
mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512; do
    sips -s format png -z $size $size "$ICON_SRC" \
        --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
    sips -s format png -z $((size*2)) $((size*2)) "$ICON_SRC" \
        --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1
done
iconutil -c icns "$ICONSET" -o "$WORK/VolumeIcon.icns" 2>/dev/null
rm -rf "$ICONSET"

echo "==> Creating read-write DMG..."
hdiutil create -volname "$VOLNAME" -fs HFS+ -format UDRW -size 100m -ov "$RW_DMG"
hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG"
sleep 2

echo "==> Populating volume..."
cp -r "$APP_SRC" "$VOLPATH/DailyWalls.app"
ln -s /Applications "$VOLPATH/Applications"
mkdir -p "$VOLPATH/.background"
cp "$BG_PNG" "$VOLPATH/.background/background.png"
cp "$WORK/VolumeIcon.icns" "$VOLPATH/.VolumeIcon.icns"

echo "==> Configuring Finder window..."
osascript << 'ASEOF'
tell application "Finder"
    tell disk "DailyWalls"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 100, 1000, 480}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "DailyWalls.app" to {160, 190}
        set position of item "Applications" to {440, 190}
        close
        open
        update without registering applications
        delay 3
    end tell
end tell
ASEOF

echo "==> Setting volume icon flag..."
/usr/bin/SetFile -a C "$VOLPATH" 2>/dev/null || \
    xattr -wx com.apple.FinderInfo \
        "0000000000000000040000000000000000000000000000000000000000000000" \
        "$VOLPATH" 2>/dev/null || true

sync
sleep 1

echo "==> Converting to compressed read-only DMG..."
hdiutil detach "$VOLPATH"
rm -f "$OUTPUT"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT"

echo "==> Created $OUTPUT"
