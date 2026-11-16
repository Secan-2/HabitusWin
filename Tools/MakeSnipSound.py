#!/usr/bin/env python3
"""生成随包发布的剪切音效 Resources/Snip.wav。

音色与候选里的 04i_柔化撕裂 完全一致：短促撕裂结构 + 两遍 3kHz 低通。
配方只有 MakeSoundCandidates.py 一份，这里直接复用，避免两处参数走偏。

用法：python3 Tools/MakeSnipSound.py [输出路径]
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from MakeSoundCandidates import CANDIDATES, build, write  # noqa: E402

SOURCE_PREFIX = "04i_"


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Resources", "Snip.wav")

    entry = next((e for e in CANDIDATES if e[0].startswith(SOURCE_PREFIX)), None)
    if entry is None:
        raise SystemExit(f"找不到 {SOURCE_PREFIX} 候选")

    name, duration, _, spec = entry[:4]
    post = entry[4] if len(entry) > 4 else None
    buf = build(spec, duration, post)
    write(buf, out)
    print(f"{name} -> {out}  ({duration * 1000:.0f}ms)")


if __name__ == "__main__":
    main()
