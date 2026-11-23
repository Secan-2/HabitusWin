#!/bin/bash
# 把 dist/HabitusWin.app 打成发布用的 DMG。
# 先跑 ./build.sh 产出 app，再执行本脚本，产物在 dist/HabitusWin-<版本>.dmg。
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/HabitusWin.app"
if [ ! -d "$APP" ]; then
  echo "!! 找不到 $APP，先执行 ./build.sh" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
OUT="dist/HabitusWin-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# 用 ditto 保留签名与扩展属性，cp -R 会丢一部分
ditto "$APP" "$STAGE/HabitusWin.app"
cp Resources/安装.command "$STAGE/"
cp Resources/安装说明.txt "$STAGE/"
ln -s /Applications "$STAGE/应用程序"

rm -f "$OUT"
hdiutil create -volname "HabitusWin" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null

echo "==> done: $OUT"
