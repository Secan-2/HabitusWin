#!/usr/bin/env python3
"""生成切纸类音效候选，供人工试听后挑选。

每个候选由若干「事件」组成：
  burst   —— 带通噪声乘指数包络，可做频率扫描与起音淡入
  tone    —— 阻尼正弦，用来做金属共鸣
  crackle —— 一串随机微爆点，用来做纸张纤维的碎响

输出 wav 之外，同时写出 说明.txt 和 试听.html，保证三者不脱节。

用法：python3 Tools/MakeSoundCandidates.py <输出目录>
"""

import html
import math
import os
import random
import struct
import sys
import wave

FS = 44100


def bandpassed(seed, freq, q, length, sweep_to=None):
    rng = random.Random(seed)
    x1 = x2 = y1 = y2 = 0.0
    out = []
    for i in range(length):
        f = freq if sweep_to is None else freq + (sweep_to - freq) * (i / max(1, length - 1))
        w0 = 2.0 * math.pi * f / FS
        alpha = math.sin(w0) / (2.0 * q)
        b0, b1, b2 = alpha, 0.0, -alpha
        a0, a1, a2 = 1.0 + alpha, -2.0 * math.cos(w0), 1.0 - alpha
        x = rng.uniform(-1.0, 1.0)
        y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1 = x1, x
        y2, y1 = y1, y
        out.append(y)
    return out


def add_burst(buf, start, amp, decay, freq, q, seed, tail, sweep_to=None, attack=0.0, click_amp=0.5):
    i0 = int(start * FS)
    length = min(int(tail * FS), len(buf) - i0)
    if length <= 0:
        return
    noise = bandpassed(seed, freq, q, length, sweep_to)
    for i in range(length):
        t = i / FS
        env = math.exp(-t / decay)
        if attack > 0:
            env *= min(1.0, t / attack)
        click = math.exp(-t / 0.0008) * click_amp
        buf[i0 + i] += (noise[i] * env + click) * amp


def add_tone(buf, start, amp, decay, freq):
    i0 = int(start * FS)
    length = min(int(decay * 6 * FS), len(buf) - i0)
    for i in range(length):
        t = i / FS
        buf[i0 + i] += math.sin(2 * math.pi * freq * t) * math.exp(-t / decay) * amp


def lowpass(buf, cutoff, passes=1):
    """一阶低通，用来削掉刺耳的高频。多跑几遍斜率更陡。"""
    a = math.exp(-2 * math.pi * cutoff / FS)
    out = buf
    for _ in range(passes):
        y = 0.0
        filtered = []
        for v in out:
            y = (1 - a) * v + a * y
            filtered.append(y)
        out = filtered
    return out


def build(spec, duration, post=None):
    n = int(FS * duration)
    buf = [0.0] * n
    for ev in spec:
        kind = ev[0]
        if kind == "burst":
            _, start, amp, decay, freq, q, seed, tail = ev[:8]
            sweep = ev[8] if len(ev) > 8 else None
            attack = ev[9] if len(ev) > 9 else 0.0
            click = ev[10] if len(ev) > 10 else 0.5
            add_burst(buf, start, amp, decay, freq, q, seed, tail, sweep, attack, click)
        elif kind == "tone":
            _, start, amp, decay, freq = ev[:5]
            add_tone(buf, start, amp, decay, freq)
        elif kind == "crackle":
            _, start, end, count, amp, seed, decay = ev[:7]
            fmin = ev[7] if len(ev) > 7 else 1400.0
            fmax = ev[8] if len(ev) > 8 else 6200.0
            rng = random.Random(seed)
            for i in range(count):
                t = start + (end - start) * (i + rng.random() * 0.9) / count
                add_burst(buf,
                          t,
                          amp * rng.uniform(0.35, 1.0),
                          decay * rng.uniform(0.6, 1.4),
                          rng.uniform(fmin, fmax),
                          rng.uniform(0.7, 1.3),
                          seed + i,
                          0.018,
                          click_amp=0.25)
    if post:
        for step in post:
            if step[0] == "lowpass":
                buf = lowpass(buf, step[1], step[2] if len(step) > 2 else 1)
    return buf


def write(buf, path, peak_target=0.72):
    # 起音冲激会引入直流偏置，先去掉再归一化，避免首尾出现咔嗒
    mean = sum(buf) / len(buf)
    buf = [v - mean for v in buf]
    peak = max(abs(v) for v in buf) or 1.0
    scale = peak_target / peak
    frames = bytearray()
    for v in buf:
        s = max(-1.0, min(1.0, v * scale))
        frames += struct.pack("<h", int(s * 32767))
    with wave.open(path, "wb") as fh:
        fh.setnchannels(1)
        fh.setsampwidth(2)
        fh.setframerate(FS)
        fh.writeframes(bytes(frames))


def tear(duration, bed_freq, bed_decay, bed_q, bite_amp, crackle_count, crackle_amp, seed):
    """在撕裂底噪上铺一层随机微爆点，模拟纤维被一根根扯断。"""
    return [
        ("burst", 0.000, 0.70, bed_decay, bed_freq, bed_q, seed, duration),
        ("burst", 0.004, bite_amp, 0.0060, bed_freq * 1.7, 1.2, seed + 1, 0.050),
        ("crackle", 0.010, duration * 0.88, crackle_count, crackle_amp, seed + 7, 0.0060),
    ]


CANDIDATES = [
    ("01_双响清脆", 0.15,
     "两下剪刀咬合，最接近真实的「咔嚓」。高频为主，利落不刺耳。",
     [
         ("burst", 0.000, 1.00, 0.0032, 5200, 1.1, 11, 0.030),
         ("burst", 0.030, 0.72, 0.0028, 4300, 1.2, 23, 0.028),
         ("burst", 0.058, 0.30, 0.0022, 6800, 1.6, 37, 0.020),
     ]),

    ("02_单声极短", 0.08,
     "只响一下，80 毫秒走完。反馈最轻，连续剪切时不吵。",
     [
         ("burst", 0.000, 1.00, 0.0022, 6000, 1.1, 41, 0.024),
         ("burst", 0.010, 0.35, 0.0016, 7200, 1.5, 42, 0.016),
     ]),

    ("03_厚实剪刀", 0.18,
     "中心频率下移到 2.6kHz，声音更沉，有木头桌面的钝感。",
     [
         ("burst", 0.000, 1.00, 0.0050, 2600, 1.0, 51, 0.045),
         ("burst", 0.034, 0.70, 0.0045, 2200, 1.1, 52, 0.040),
         ("tone", 0.000, 0.18, 0.012, 780),
     ]),

    ("04_纸张撕裂", 0.30,
     "原始版。300 毫秒，噪声底在 2.5kHz，带随机碎响。",
     tear(0.30, 2500, 0.055, 0.7, 0.90, 10, 0.35, 61)),

    ("04a_短促撕裂", 0.18,
     "同样质感但只有 180 毫秒，像撕开一个小口，反馈更快。",
     tear(0.18, 2700, 0.030, 0.8, 0.95, 6, 0.28, 131)),

    ("04b_长撕裂", 0.52,
     "一路撕到底，520 毫秒慢衰减，像把整张纸扯成两半。",
     tear(0.52, 2300, 0.110, 0.6, 0.80, 20, 0.40, 141)),

    ("04c_牛皮纸开裂", 0.22,
     "噪声底上移到 4kHz，起音更硬，像撕牛皮纸或厚信封。",
     [
         ("burst", 0.000, 0.85, 0.035, 4000, 0.9, 151, 0.22),
         ("burst", 0.002, 1.00, 0.0045, 5200, 1.3, 152, 0.040),
         ("crackle", 0.008, 0.19, 12, 0.45, 158, 0.0045),
     ]),

    ("04d_薄纸细碎", 0.35,
     "噪声底降到 1.8kHz、Q 值更低，碎点更密更轻，像揉开的薄纸。",
     tear(0.35, 1800, 0.070, 0.5, 0.55, 26, 0.22, 161)),

    ("04e_纸板低鸣", 0.42,
     "1.2kHz 的低频底噪加少量碎点，撕的是硬纸板，带箱体共鸣。",
     [
         ("burst", 0.000, 0.80, 0.095, 1200, 0.6, 171, 0.42),
         ("burst", 0.003, 0.70, 0.0070, 2400, 1.1, 172, 0.050),
         ("crackle", 0.020, 0.36, 8, 0.20, 177, 0.0055),
         ("tone", 0.000, 0.12, 0.020, 420),
     ]),

    ("04f_撕裂收剪", 0.26,
     "先撕 220 毫秒，末尾补一记剪刀咬合，收尾干净。",
     tear(0.22, 2600, 0.045, 0.7, 0.90, 8, 0.32, 181) + [
         ("burst", 0.222, 0.85, 0.0028, 5000, 1.2, 189, 0.026),
         ("burst", 0.240, 0.40, 0.0022, 4200, 1.3, 190, 0.020),
     ]),

    ("04g_温和撕裂", 0.18,
     "在短促撕裂基础上压掉高频：底噪 2.4kHz，咬合点从 4.6kHz 降到 3.4kHz，碎点由 6 个减到 4 个且只在 3.4kHz 以下，末段加一级 3.8kHz 低通。",
     [
         ("burst", 0.000, 0.70, 0.032, 2400, 0.8, 201, 0.18),
         ("burst", 0.004, 0.80, 0.0055, 3400, 1.1, 202, 0.045, None, 0.0, 0.3),
         ("crackle", 0.010, 0.16, 4, 0.20, 207, 0.0060, 900, 3400),
     ],
     [("lowpass", 3800, 1)]),

    ("04h_低沉撕裂", 0.19,
     "再降一档：底噪 1.9kHz，咬合 2.6kHz，碎点只剩 3 个，补了 260Hz 的体感，低通收到 2.6kHz。最不刺耳，但会让出一点「纸感」。",
     [
         ("burst", 0.000, 0.70, 0.036, 1900, 0.7, 211, 0.19),
         ("burst", 0.004, 0.75, 0.0060, 2600, 1.0, 212, 0.048, None, 0.0, 0.25),
         ("crackle", 0.012, 0.17, 3, 0.16, 217, 0.0060, 700, 2600),
         ("tone", 0.000, 0.10, 0.025, 260),
     ],
     [("lowpass", 2600, 1)]),

    ("04i_柔化撕裂", 0.18,
     "结构和 04a 完全一致，只把整段过两遍 3kHz 低通。用来单独听「只去高频、不改结构」的效果。",
     tear(0.18, 2700, 0.030, 0.8, 0.95, 6, 0.28, 131),
     [("lowpass", 3000, 2)]),

    ("05_刀刃滑过", 0.16,
     "频率从 8kHz 扫到 3kHz，像刀片划开纸面，带摩擦感。",
     [
         ("burst", 0.000, 1.00, 0.020, 8000, 1.4, 71, 0.12, 3000),
         ("burst", 0.030, 0.35, 0.0040, 6000, 1.2, 72, 0.030),
     ]),

    ("06_金属共鸣", 0.22,
     "咬合后叠 3.2kHz 阻尼正弦，有明显的金属「叮」，辨识度最高。",
     [
         ("burst", 0.000, 1.00, 0.0026, 5400, 1.1, 81, 0.022),
         ("tone", 0.000, 0.30, 0.018, 3200),
         ("tone", 0.000, 0.16, 0.030, 4900),
     ]),

    ("07_相机快门", 0.09,
     "两段极短咔嗒，间隔 9 毫秒，像机械快门。最干脆。",
     [
         ("burst", 0.000, 1.00, 0.0016, 7000, 1.3, 91, 0.014),
         ("burst", 0.009, 0.55, 0.0014, 5600, 1.3, 92, 0.012),
     ]),

    ("08_轻柔版本", 0.16,
     "双响但整体能量更低，起音加了淡入，中心频率降到 3.5kHz。不打扰。",
     [
         ("burst", 0.000, 0.50, 0.0040, 3500, 1.0, 101, 0.035, None, 0.0015),
         ("burst", 0.032, 0.36, 0.0035, 3100, 1.1, 102, 0.032, None, 0.0015),
         ("burst", 0.060, 0.16, 0.0028, 5200, 1.4, 103, 0.022, None, 0.0015),
     ]),
]


def make_html(items):
    rows = []
    for entry in items:
        name, duration, desc = entry[:3]
        pretty = name.split("_", 1)[1]
        num = name.split("_", 1)[0]
        rows.append(f'''
    <div class="row">
      <button class="play" data-src="{html.escape(name)}.wav">&#9654;</button>
      <div class="meta">
        <div class="title">{html.escape(pretty)}<span class="num">{html.escape(num)}</span></div>
        <div class="desc">{html.escape(desc)}</div>
      </div>
    </div>''')

    return f'''<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>HabitusWin 剪切音效试听</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ margin:0; padding:32px; font:14px/1.6 -apple-system,"PingFang SC",sans-serif;
         background:#f5f5f7; color:#1d1d1f; }}
  @media (prefers-color-scheme: dark) {{ body {{ background:#1c1c1e; color:#f2f2f7; }} }}
  h1 {{ font-size:18px; margin:0 0 4px; }}
  .hint {{ font-size:12px; opacity:.6; margin-bottom:22px; }}
  .row {{ display:flex; align-items:center; gap:14px; padding:14px 16px; margin-bottom:10px;
          background:#fff; border:1px solid rgba(0,0,0,.08); border-radius:12px; }}
  @media (prefers-color-scheme: dark) {{ .row {{ background:#2c2c2e; border-color:rgba(255,255,255,.08); }} }}
  .play {{ width:36px; height:36px; flex:0 0 36px; border-radius:50%; border:none; cursor:pointer;
           background:#e8e8ed; color:#1d1d1f; font-size:13px; }}
  .play:active {{ transform:scale(.94); }}
  @media (prefers-color-scheme: dark) {{ .play {{ background:#3a3a3c; color:#f2f2f7; }} }}
  .title {{ font-size:14px; font-weight:600; display:flex; align-items:baseline; gap:8px; }}
  .num {{ font-size:11px; font-weight:400; opacity:.45; }}
  .desc {{ font-size:12px; opacity:.65; }}
</style></head>
<body>
  <h1>HabitusWin 剪切音效试听</h1>
  <div class="hint">点击左侧按钮播放。全部原创合成，44.1kHz / 16bit / 单声道，峰值统一到 -3dB。04 系列是纸张撕裂的不同版本，可直接横向比较。</div>
  {''.join(rows)}
<script>
  let current = null;
  let currentButton = null;
  document.querySelectorAll('.play').forEach(btn => {{
    btn.addEventListener('click', () => {{
      if (current) {{ current.pause(); if (currentButton) currentButton.innerHTML = '&#9654;'; }}
      const audio = new Audio(btn.dataset.src);
      audio.play();
      current = audio;
      currentButton = btn;
      btn.innerHTML = '&#10074;&#10074;';
      audio.onended = () => {{ btn.innerHTML = '&#9654;'; }};
    }});
  }});
</script>
</body></html>'''


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "sound-candidates"
    os.makedirs(out_dir, exist_ok=True)

    lines = []
    for entry in CANDIDATES:
        name, duration, desc, spec = entry[:4]
        post = entry[4] if len(entry) > 4 else None
        buf = build(spec, duration, post)
        write(buf, os.path.join(out_dir, name + ".wav"))
        rms = math.sqrt(sum(v * v for v in buf) / len(buf))
        lines.append(f"{name}.wav\t{duration * 1000:.0f}ms\trms {20 * math.log10(rms + 1e-9):.1f}dB\t{desc}")
        print(f"{name}.wav  {duration * 1000:.0f}ms  rms={rms:.3f}")

    with open(os.path.join(out_dir, "说明.txt"), "w", encoding="utf-8") as fh:
        fh.write("HabitusWin 剪切音效候选\n\n")
        fh.write("全部为原创合成，44.1kHz / 16bit / 单声道，峰值统一到 -3dB，已去直流。\n")
        fh.write("试听方式：双击 试听.html，点按钮逐个播放。也可以选中 wav 按空格键。\n")
        fh.write("04 系列是纸张撕裂的多个版本，可横向比较。\n\n")
        for line in lines:
            fh.write(line + "\n")

    with open(os.path.join(out_dir, "试听.html"), "w", encoding="utf-8") as fh:
        fh.write(make_html(CANDIDATES))

    print("written to", out_dir, f"({len(CANDIDATES)} candidates)")


if __name__ == "__main__":
    main()
