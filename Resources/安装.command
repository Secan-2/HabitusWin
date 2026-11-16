#!/bin/bash
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/HabitusWin.app"
DEST="/Applications/HabitusWin.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [ ! -d "$SRC" ]; then
  echo "找不到 HabitusWin.app，请把本脚本和它放在同一层。"
  exit 1
fi

echo "正在安装 HabitusWin…"
pkill -f "/Applications/HabitusWin.app/Contents/MacOS/HabitusWin" >/dev/null 2>&1
sleep 1

rm -rf "$DEST"
cp -R "$SRC" "$DEST" || { echo "复制失败，请检查 /Applications 写入权限"; exit 1; }
xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1

# 注册到 LaunchServices，否则启动台和访达可能显示旧图标或干脆看不到这个应用。
"$LSREGISTER" -f -R -trusted "$DEST" >/dev/null 2>&1
touch "$DEST"

# 重启 Dock 以刷新启动台缓存，这一步让应用立刻可见。
killall Dock >/dev/null 2>&1

echo "安装完成，正在启动…"
open "$DEST"
echo "首次使用请到菜单栏点图标打开设置，打开任一功能开关并按提示授予辅助功能权限。"
