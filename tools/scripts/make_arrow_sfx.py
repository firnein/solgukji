# 궁병 사격 · 무기 휘두르기 소리 —— Still North Media "Medieval Sound Effects - Weapon Textures" (CC0,
# https://opengameart.org/content/medieval-sound-effects-weapon-textures, medieval_sfx_textures_1_of_2.7z) 에서 테이크를 잘라 섞는다.
# 실행: python tools/scripts/make_arrow_sfx.py <풀어 둔 wav 폴더>  → solgukji_godot/assets/sfx/arrow_1~3.wav, swing_1~4.wav
#   폴더에 "English Longbow Shoot.wav", "Scythian Recurve Arrow Passby.wav", "Scythian Recurve Heavy Arrow Passby.wav", "Katana Swing.wav"
# (11/4 사용자: 합성 대신 질 좋은 무료 에셋을 쓰자)
import os, sys
import numpy as np
import soundfile as sf

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "solgukji_godot", "assets", "sfx")


def load(path):
    d, sr = sf.read(path)
    if d.ndim > 1:
        d = d.mean(axis=1)
    if sr != SR:
        # 192k → 44.1k: 4배 평균(저역 통과)한 뒤 선형 보간
        k = max(1, sr // SR)
        if k > 1:
            n = len(d) // k * k
            d = d[:n].reshape(-1, k).mean(axis=1)
            sr = sr / k
        t_new = np.arange(0, len(d) / sr, 1.0 / SR)
        d = np.interp(t_new, np.arange(len(d)) / sr, d)
    return d


def takes(d, thr=0.02, gap=0.12, pre=0.01, post=0.25):
    """소리 덩어리(테이크)마다 [시작, 끝] 샘플 —— 조용한 구간으로 나눈다"""
    win = int(SR * 0.01)
    e = np.convolve(np.abs(d), np.ones(win) / win, mode="same")
    on = e > thr
    out = []
    i = 0
    g = int(SR * gap)
    while i < len(on):
        if on[i]:
            j = i
            while j < len(on) and on[j:j + g].any():
                j += 1
            out.append((max(0, i - int(SR * pre)), min(len(d), j + int(SR * post))))
            i = j
        else:
            i += 1
    return out


def fade(s, a=0.004, r=0.06):
    s = s.copy()
    na = int(SR * a)
    nr = int(SR * r)
    s[:na] *= np.linspace(0, 1, na)
    s[-nr:] *= np.linspace(1, 0, nr)
    return s


def mix(dst, src, at, gain):
    e = min(len(dst), at + len(src))
    dst[at:e] += src[: e - at] * gain


def volley(rng, shoot, passby, heavy):
    n = int(SR * 1.0)
    out = np.zeros(n)
    for j in range(5 + int(rng.integers(0, 3))):          # 시위 5~7발, 0.25초 안에 엇갈려
        s = shoot[rng.integers(len(shoot))]
        mix(out, s, int(rng.uniform(0, 0.25) * SR), rng.uniform(0.5, 1.0))
    for j in range(3 + int(rng.integers(0, 2))):          # 화살 지나가는 쉭 3~4, 조금 뒤에
        src = heavy if rng.random() < 0.35 else passby
        s = src[rng.integers(len(src))]
        mix(out, s, int(rng.uniform(0.08, 0.4) * SR), rng.uniform(0.35, 0.6))
    out /= (np.abs(out).max() + 1e-9)
    return fade(out * 0.9, 0.002, 0.15)


def write(path, s):
    sf.write(path, np.clip(s, -1, 1).astype(np.float32), SR, subtype="PCM_16")
    print(path)


if __name__ == "__main__":
    src = sys.argv[1]
    shoot_d = load(os.path.join(src, "English Longbow Shoot.wav"))
    pass_d = load(os.path.join(src, "Scythian Recurve Arrow Passby.wav"))
    heavy_d = load(os.path.join(src, "Scythian Recurve Heavy Arrow Passby.wav"))
    swing_d = load(os.path.join(src, "Katana Swing.wav"))
    shoot = [fade(shoot_d[a:b]) for a, b in takes(shoot_d)]
    passby = [fade(pass_d[a:b]) for a, b in takes(pass_d)]
    heavy = [fade(heavy_d[a:b]) for a, b in takes(heavy_d)]
    swings = [fade(swing_d[a:b], 0.004, 0.08) for a, b in takes(swing_d, post=0.2)]
    print("테이크: 시위 %d · 쉭 %d · 무거운 쉭 %d · 휘두르기 %d" % (len(shoot), len(passby), len(heavy), len(swings)))
    rng = np.random.default_rng(7)
    for i in range(1, 4):
        write(os.path.join(OUT, "arrow_%d.wav" % i), volley(rng, shoot, passby, heavy))
    for i, s in enumerate(swings[:4]):
        s = s / (np.abs(s).max() + 1e-9) * 0.9
        write(os.path.join(OUT, "swing_%d.wav" % (i + 1)), s)
