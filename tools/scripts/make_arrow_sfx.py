# 궁병 사격 소리 합성 (11/4 사용자: 궁병에게 화살 소리) —— 시위 튕김(짧은 퉁) + 화살 여럿이 날아가는 쉭 소리
# 실행: python tools/scripts/make_arrow_sfx.py  → solgukji_godot/assets/sfx/arrow_1~3.wav
import os, wave, struct
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "solgukji_godot", "assets", "sfx")


def env(n, a, d):
    t = np.arange(n) / SR
    return np.minimum(t / a, 1.0) * np.exp(-np.maximum(t - a, 0) / d)


def twang(rng, f0=160.0, dur=0.14):
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = f0 * (1.0 + 0.4 * np.exp(-t * 60))          # 처음 조금 높았다가 내려온다
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) + 0.45 * np.sin(2 * ph) * np.exp(-t * 30) + 0.2 * np.sin(3 * ph) * np.exp(-t * 50)
    return s * env(n, 0.002, 0.03) * 0.8


def whoosh(rng, dur=0.32, lo=1400.0, hi=5200.0):
    n = int(SR * dur)
    x = rng.standard_normal(n)
    # 대역 통과 —— 한 극 저역 두 번(고역 끊기) 뺀 저역(저역 끊기), 가운데 주파수가 시간에 따라 내려온다 (멀어지는 화살)
    t = np.arange(n) / SR
    fc = hi * np.exp(-t * 4.0) + lo
    y = np.zeros(n)
    z1 = z2 = 0.0
    for i in range(n):
        a = min(1.0, 2 * np.pi * fc[i] / SR)
        z1 += a * (x[i] - z1)
        z2 += a * (z1 - z2)
        y[i] = z2
    # 저역 끊기 —— 느린 저역 평균을 뺀다
    low = np.zeros(n)
    z = 0.0
    a = 2 * np.pi * 700.0 / SR
    for i in range(n):
        z += a * (y[i] - z)
        low[i] = z
    y = y - low
    y /= (np.abs(y).max() + 1e-9)
    return y * env(n, 0.03, 0.09)


def volley(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * 0.75)
    out = np.zeros(n)
    k = 5 + int(rng.integers(0, 3))
    for j in range(k):
        st = int(rng.uniform(0.0, 0.22) * SR)
        tw = twang(rng, 150 + rng.uniform(-25, 40)) * rng.uniform(0.5, 1.0)
        wh = whoosh(rng, 0.28 + rng.uniform(0, 0.1), 1200 + rng.uniform(-200, 300), 4800 + rng.uniform(-800, 800)) * rng.uniform(0.6, 1.0)
        for s in (tw, wh):
            e = min(n, st + len(s))
            out[st:e] += s[: e - st]
    out /= (np.abs(out).max() + 1e-9)
    return out * 0.85


def write(path, s):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(struct.pack("<%dh" % len(s), *(np.clip(s, -1, 1) * 32767).astype(np.int16)))


if __name__ == "__main__":
    for i in range(1, 4):
        p = os.path.join(OUT, "arrow_%d.wav" % i)
        write(p, volley(100 + i))
        print(p)
