#!/bin/bash
# 构建 dist/HabitusWin.app。优先出通用二进制（arm64 + x86_64），
# 交叉编译不可用时退回本机架构。完整输出留在 build.log，便于排查 CI 上的失败。
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="dist/HabitusWin.app"
LOG="build.log"
: > "$LOG"

# 产物路径必须与构建时用的参数一致：带 --arch 的通用构建放在
# .build/out/Products/Release，不带 arch 的放在 .build/<triple>/release。
ARCH_ARGS=(--arch arm64 --arch x86_64)

echo "==> building ($CONFIG)"
if ! swift build -c "$CONFIG" --disable-sandbox "${ARCH_ARGS[@]}" >>"$LOG" 2>&1; then
  echo "==> universal build unavailable, building native arch only"
  printf '\n==> universal build unavailable, retrying native arch\n' >>"$LOG"
  ARCH_ARGS=()
  if ! swift build -c "$CONFIG" --disable-sandbox >>"$LOG" 2>&1; then
    echo "!! build failed, last lines of $LOG:"
    tail -40 "$LOG"
    exit 1
  fi
fi

BIN_DIR="$(swift build -c "$CONFIG" --disable-sandbox "${ARCH_ARGS[@]}" --show-bin-path 2>/dev/null | tail -1)"
BIN="$BIN_DIR/HabitusWin"
echo "==> binary: $BIN"

if [ ! -x "$BIN" ]; then
  echo "!! 找不到构建产物 $BIN"
  find .build -maxdepth 4 -name HabitusWin -type f 2>/dev/null | head -5
  exit 1
fi

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
