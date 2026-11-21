# -*- coding: utf-8 -*-
"""효과음 다듬기 (11/21 사운드 폴리싱)

1) 같은 이름의 변형(hit_1 … hit_10 등)끼리 크기를 맞춘다 —— 짧은 구간(100ms) 최대 RMS 를 그 묶음의 중앙값으로.
   피크는 -1 dBFS 를 넘지 않게 (예전 hit · crit 는 피크 +5~6 dB 로 찢어졌다).
2) 코드가 부르는데 파일이 없던 소리를 만든다 —— burn · splash · confuse · heal · debuff · lose.
   예전 합성 '삑' 소리는 유치하다고 뺐으니(10/31) 음정 있는 합성음은 쓰지 않는다:
   - burn   : 불 타닥임 (걸러 낸 잡음 + 무작위 튐) —— 음정 없음
   - splash : 물 튐 (잡음 터짐 + 낮아지는 대역 + 물방울 몇 개)
   - heal   : magic.wav(CC0 RPG Sound Pack) 를 높게 · 부드럽게
   - debuff : magic.wav 를 낮게 · 어둡게
   - confuse: magic.wav 에 음높이 흔들림
   - lose   : horn.wav(CC0 Horde War Drums) 를 낮고 짧게, 끝을 흐리게
3) 묶음마다 측정한 크기를 찍는다 —— scripts/game/sfx.gd 의 TUNE 을 이 값으로 맞춘다.

실행: python -I tools/scripts/polish_sfx.py          (assets/sfx 를 고쳐 쓴다 —— 예전 것은 깃 기록에 있다)
      python -I tools/scripts/polish_sfx.py --dry    (재기만)
필요: pip install numpy soundfile
"""
import os, re, sys
import numpy as np
import soundfile as sf

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SFX = os.path.join(ROOT, "solgukji_godot", "assets", "sfx")
SR = 44100
PEAK = 10 ** (-1.0 / 20)      # -1 dBFS
DRY = "--dry" in sys.argv
rng = np.random.default_rng(1121)


def load(path):
    x, sr = sf.read(path, always_2d=True)
    return x.mean(1), sr


def st_rms(x, sr):
    """짧은 구간(100ms) 최대 RMS (dB)"""
    w = max(1, int(sr * 0.1))
    if len(x) < w:
        return 20 * np.log10(np.sqrt((x * x).mean()) + 1e-12)
    return 20 * np.log10(np.sqrt(np.convolve(x * x, np.ones(w) / w, "valid").max()) + 1e-12)


def save(path, x, sr):
    m = np.abs(x).max()
    if m > PEAK:
        x = x * (PEAK / m)
    if DRY:
        return
    if path.endswith(".ogg"):
        sf.write(path, x.astype(np.float32), sr, format="OGG", subtype="VORBIS")
    else:
        sf.write(path, x.astype(np.float32), sr, subtype="PCM_16")


def fade(x, sr, a=0.005, b=0.05):
    n = len(x)
    ia, ib = min(n, int(sr * a)), min(n, int(sr * b))
    if ia:
        x[:ia] *= np.linspace(0, 1, ia)
    if ib:
        x[-ib:] *= np.linspace(1, 0, ib)
    return x


def lowpass(x, sr, hz):
    # 한 극 저역 통과 (부드러운)
    a = np.exp(-2 * np.pi * hz / sr)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, sr, hz):
    return x - lowpass(x, sr, hz)


def resample(x, ratio):
    """ratio > 1 이면 높고 짧게"""
    n = int(len(x) / ratio)
    return np.interp(np.arange(n) * ratio, np.arange(len(x)), x)


# ── 1) 변형끼리 크기 맞추기 ──
fams = {}
for f in sorted(os.listdir(SFX)):
    m = re.fullmatch(r"([a-z_]+?)(_\d+)?\.(wav|ogg)", f)
    if m:
        fams.setdefault(m[1], []).append(f)

for n, files in fams.items():
    if len(files) < 2:
        continue
    lv = {f: st_rms(*load(os.path.join(SFX, f))) for f in files}
    target = float(np.median(list(lv.values())))
    for f in files:
        x, sr = load(os.path.join(SFX, f))
        save(os.path.join(SFX, f), x * 10 ** ((target - lv[f]) / 20), sr)
    print(f"맞춤 {n}: {len(files)}개 {min(lv.values()):.1f}~{max(lv.values()):.1f} → {target:.1f} dB")

# 하나뿐인 소리도 피크만 고친다
for n, files in fams.items():
    if len(files) == 1:
        p = os.path.join(SFX, files[0])
        x, sr = load(p)
        if np.abs(x).max() > PEAK:
            save(p, x, sr)
            print(f"피크 고침 {files[0]}")

# ── 2) 빠진 소리 만들기 ──
def make_burn():
    d = 0.9
    n = int(SR * d)
    t = np.arange(n) / SR
    bed = highpass(lowpass(rng.standard_normal(n), SR, 2500), SR, 300) * 0.25
    bed *= np.minimum(1, t / 0.08) * np.exp(-t * 2.2)      # 확 붙었다 잦아든다
    cr = np.zeros(n)
    for _ in range(38):      # 타닥 —— 짧은 튐
        s = int(rng.uniform(0, 0.75) * SR)
        L = int(rng.uniform(0.002, 0.008) * SR)
        cr[s:s + L] += rng.standard_normal(min(L, n - s)) * np.exp(-np.arange(min(L, n - s)) / (L / 4)) * rng.uniform(0.3, 1.0)
    cr = highpass(cr, SR, 1500)
    return fade(bed + cr * 0.8, SR, 0.003, 0.2)


def make_splash():
    d = 0.75
    n = int(SR * d)
    t = np.arange(n) / SR
    burst = rng.standard_normal(n) * np.exp(-t * 7)
    lo = lowpass(burst, SR, 3200) * 0.7 + lowpass(burst, SR, 900) * 0.6
    drops = np.zeros(n)
    for _ in range(6):      # 물방울 —— 아주 짧고 높이가 내려가는 울림 (낮게 섞는다)
        s = int(rng.uniform(0.08, 0.55) * SR)
        L = int(0.04 * SR)
        k = np.arange(min(L, n - s)) / SR
        f0 = rng.uniform(900, 1600)
        drops[s:s + len(k)] += np.sin(2 * np.pi * (f0 * k - 3000 * k * k)) * np.exp(-k * 90) * 0.25
    return fade(highpass(lo + drops, SR, 120), SR, 0.002, 0.25)


def from_magic(kind):
    x, sr = load(os.path.join(SFX, "magic.wav"))
    if sr != SR:
        x = resample(x, sr / SR)
    if kind == "heal":      # 높고 부드럽게
        y = lowpass(resample(x, 1.35), SR, 5000)
        y = fade(y[: int(SR * 0.7)], SR, 0.01, 0.3)
    elif kind == "debuff":      # 낮고 어둡게
        y = lowpass(resample(x, 0.72), SR, 1800)
        y = fade(y[: int(SR * 0.9)], SR, 0.01, 0.35)
    else:      # confuse —— 높이가 흔들린다
        n = int(len(x) / 0.95)
        t = np.arange(n) / SR
        pos = np.cumsum(0.95 * (1 + 0.08 * np.sin(2 * np.pi * 6.5 * t)))
        pos = pos[pos < len(x) - 1]
        y = np.interp(pos, np.arange(len(x)), x)
        y = fade(lowpass(y, SR, 3500)[: int(SR * 0.85)], SR, 0.01, 0.3)
    return y


def make_lose():
    x, sr = load(os.path.join(SFX, "horn.wav"))
    if sr != SR:
        x = resample(x, sr / SR)
    y = lowpass(resample(x, 0.84), SR, 1400)
    return fade(y[: int(SR * 2.4)], SR, 0.01, 1.0)


MADE = {"burn.ogg": make_burn, "splash.ogg": make_splash, "heal.ogg": lambda: from_magic("heal"),
        "debuff.ogg": lambda: from_magic("debuff"), "confuse.ogg": lambda: from_magic("confuse"), "lose.ogg": make_lose}
for f, fn in MADE.items():
    y = fn()
    y = y / (np.abs(y).max() + 1e-9) * PEAK
    save(os.path.join(SFX, f), y, SR)
    print(f"만듦 {f} {len(y) / SR:.2f}초")

# ── 3) 묶음별 크기 ──
print("\n이름 · 짧은 구간 최대 RMS (dB) —— sfx.gd TUNE = 목표 실효 크기 − 이 값")
fams = {}
for f in sorted(os.listdir(SFX)):
    m = re.fullmatch(r"([a-z_]+?)(_\d+)?\.(wav|ogg)", f)
    if m:
        fams.setdefault(m[1], []).append(st_rms(*load(os.path.join(SFX, f))))
for n, v in fams.items():
    print(f"  {n:11s} {np.median(v):6.1f}")
