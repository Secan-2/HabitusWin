#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="dist/HabitusWin.app"

echo "==> building ($CONFIG)"
if ! swift build -c "$CONFIG" --disable-sandbox --arch arm64 --arch x86_64 2>/dev/null; then
  echo "==> universal build unavailable, building native arch only"
  swift build -c "$CONFIG" --disable-sandbox
fi

BIN_DIR="$(swift build -c "$CONFIG" --disable-sandbox --show-bin-path 2>/dev/null | tail -1)"
BIN="$BIN_DIR/HabitusWin"

echo "==> assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HabitusWin"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Snip.wav "$APP/Contents/Resources/Snip.wav"
cp -R Resources/zh-Hans.lproj "$APP/Contents/Resources/zh-Hans.lproj"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  echo "!! ad-hoc signing failed, app may be blocked by Gatekeeper"

echo "==> done: $APP"
echo "    open \"$APP\""
