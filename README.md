
macOS 系统功能小工具，目前主要功能为：

1. 可将应用窗口的红绿灯按钮分别重映射为关闭应用、隐藏应用、缩放窗口。
2. ⌘X剪切。
3. 再次点击已启动软件的Dock栏图标，可将窗口在收起与展开之间切换。

## 下载

从 [Releases](../../releases) 下载最新的 `HabitusWin-x.y.z.dmg`。应用未做 Apple 公证，首次打开需要在「系统设置 → 隐私与安全性」点「仍要打开」。

## 构建与运行

```bash
cd HabitusWin
./build.sh              # 产出 dist/HabitusWin.app，通用二进制
./Tools/make-dmg.sh     # 打成 dist/HabitusWin-x.y.z.dmg
open dist/HabitusWin.app
```

## 资源占用

- 空闲 CPU 0%，全部由通知与事件驱动，无轮询。
- 常驻内存实测约 45 MB。

## 已知限制

- 自绘标题栏、或未向辅助功能暴露标准窗口按钮的应用不会被接管红灯关闭软件行为，点击仍走系统默认行为。
- 本机构建为 ad-hoc 签名，重新构建后系统可能重新要求授权。正式分发应使用 Developer ID 签名并公证。

