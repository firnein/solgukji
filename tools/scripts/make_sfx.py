"""효과음 · 배경 음악을 합성해 WAV 로 쓴다 (2026-10-30) —— 외부 음원이 없어 저작권 걱정이 없다. numpy 만 쓴다.

실행: python -I tools/scripts/make_sfx.py      → solgukji_godot/assets/sfx/*.wav, assets/bgm/*.wav
      python -I tools/scripts/make_sfx.py alert → 경고 비프 · 긴급 등용 함성 둘만 (alert_beep · alert_war · alert_wise, 11/10) —— 나머지 소리 파일은 건드리지 않는다
효과음 44.1kHz · 배경 음악 22.05kHz, 16비트 모노. 배경 음악은 끝이 처음으로 이어지게 만든다 (Sfx 가 반복 재생).
"""
import os
import wave

import numpy as np

OUT_SFX = "solgukji_godot/assets/sfx"
OUT_BGM = "solgukji_godot/assets/bgm"
SR = 44100
rng = np.random.default_rng(7)


def t_(dur, sr=SR):
    return np.arange(int(dur * sr)) / sr


def env(n, a=0.005, d=0.2, sr=SR):
    """빠르게 올라 지수로 줄어드는 소리 모양"""
    t = np.arange(n) / sr
    e = np.exp(-t / max(d, 1e-4))
    na = max(1, int(a * sr))
    e[:na] *= np.linspace(0, 1, na)
    return e


def lowpass(x, cutoff, sr=SR):
    """한 극 저역 통과 (cutoff 는 숫자 또는 x 와 같은 길이의 배열)"""
    c = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1 - np.exp(-2 * np.pi * c / sr)
    y = np.empty_like(x)
    s = 0.0
    for i in range(len(x)):
        s += a[i] * (x[i] - s)
        y[i] = s
    return y


def highpass(x, cutoff, sr=SR):
    return x - lowpass(x, cutoff, sr)


def bandpass(x, lo, hi, sr=SR):
    return lowpass(highpass(x, lo, sr), hi, sr)


def noise(dur, sr=SR):
    return rng.uniform(-1, 1, int(dur * sr))


def sine(f, dur, sr=SR, ph=0.0):
    t = t_(dur, sr)
    if np.ndim(f):
        return np.sin(2 * np.pi * np.cumsum(f) / sr + ph)
    return np.sin(2 * np.pi * f * t + ph)


def pluck(f, dur, sr=SR, bright=0.5, decay=0.996):
    """카플러스-스트롱 현 —— 고쟁 · 비파 비슷한 뜯는 소리"""
    n = int(dur * sr)
    p = max(2, int(sr / f))
    buf = rng.uniform(-1, 1, p)
    buf = lowpass(buf, 2000 + bright * 8000, sr) * 1.5
    out = np.empty(n)
    for i in range(n):
        j = i % p
        out[i] = buf[j]
        nxt = buf[(j + 1) % p]
        buf[j] = decay * 0.5 * (buf[j] + nxt)
    return out * env(n, 0.001, dur * 0.6, sr)


def mix(*parts):
    n = max(len(p) for p in parts)
    y = np.zeros(n)
    for p in parts:
        y[:len(p)] += p
    return y


def at(x, start, total, sr=SR):
    """x 를 start 초에 놓은 길이 total 초의 배열"""
    y = np.zeros(int(total * sr))
    s = int(start * sr)
    e = min(len(y), s + len(x))
    if s < len(y):
        y[s:e] += x[:e - s]
    return y


def reverb(x, sr=SR, mix_=0.25, room=0.82):
    """콤 필터 몇 개 —— 넓은 공간의 울림"""
    y = np.zeros(len(x) + int(sr * 1.2))
    y[:len(x)] = x
    wet = np.zeros_like(y)
    for dms, g in [(29.7, room), (37.1, room - 0.03), (41.1, room - 0.05), (43.7, room - 0.07)]:
        d = int(sr * dms / 1000)
        c = y.copy()
        for k in range(d, len(c), d):
            c[k:k + d] += g * c[k - d:k][:len(c[k:k + d])]
        wet += c
    wet = highpass(wet / 4, 150, sr)
    return (1 - mix_) * y + mix_ * wet * 0.5


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def fade(x, a=0.002, b=0.02, sr=SR):
    x = x.copy()
    na, nb = int(a * sr), int(b * sr)
    if na:
        x[:na] *= np.linspace(0, 1, na)
    if nb:
        x[-nb:] *= np.linspace(1, 0, nb)
    return x


def write(path, x, sr=SR, peak=0.9):
    x = norm(x, peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data)


def drum(f0=70, dur=0.6, sr=SR, punch=0.6):
    """태고 —— 아래로 떨어지는 사인 + 가죽 잡음"""
    t = t_(dur, sr)
    f = f0 * (1 + 1.8 * np.exp(-t / 0.03))
    body = sine(f, dur, sr) * env(len(t), 0.002, dur * 0.35, sr)
    skin = lowpass(noise(dur, sr), 1200, sr) * env(len(t), 0.001, 0.04, sr) * punch
    return body + skin


def gong(f0=110, dur=3.0, sr=SR):
    t = t_(dur, sr)
    y = np.zeros(len(t))
    for r, a, d in [(1, 1, 2.5), (1.48, 0.6, 1.8), (2.01, 0.5, 1.5), (2.92, 0.35, 1.0), (4.1, 0.25, 0.7), (5.37, 0.15, 0.5)]:
        y += a * np.sin(2 * np.pi * f0 * r * t * (1 + 0.002 * np.sin(2 * np.pi * 3 * t))) * np.exp(-t / d)
    y *= env(len(t), 0.01, 10, sr)
    return y + lowpass(noise(dur, sr), 300, sr) * env(len(t), 0.002, 0.15, sr) * 0.6


def horn(f0=146.8, dur=1.4, sr=SR):
    t = t_(dur, sr)
    f = f0 * (1 + 0.012 * np.sin(2 * np.pi * 5 * t)) * (1 - 0.04 * np.exp(-t / 0.08))
    ph = np.cumsum(f) / sr
    saw = 2 * (ph % 1) - 1
    swell = np.minimum(1, t / 0.25) * np.exp(-np.maximum(0, t - dur * 0.6) / 0.2)
    return lowpass(saw, 900, sr) * swell


PENTA = [261.63, 293.66, 329.63, 392.00, 440.00]     # 궁상각치우 (C D E G A)


def penta(i):
    return PENTA[i % 5] * (2 ** (i // 5))


# ───────── 효과음 ─────────

def make_sfx():
    os.makedirs(OUT_SFX, exist_ok=True)
    S = {}
    # 화면
    n = int(0.05 * SR)
    S["tap"] = fade(sine(1600, 0.05) * env(n, 0.001, 0.012) * 0.6 + lowpass(noise(0.05), 3000) * env(n, 0.0005, 0.004))
    d = 0.22
    sw = bandpass(noise(d), 400, np.linspace(800, 5000, int(d * SR)))
    S["open"] = fade(sw * np.sin(np.linspace(0, np.pi, int(d * SR))) * 0.8)
    d = 0.3
    S["draw"] = fade(mix(bandpass(noise(d), 1500, 6000) * env(int(d * SR), 0.01, 0.07),
                         at(lowpass(noise(0.03), 2500) * env(int(0.03 * SR), 0.001, 0.008), 0.12, d)))
    S["gain"] = reverb(mix(at(pluck(penta(5), 0.6), 0, 0.9), at(pluck(penta(7), 0.6), 0.08, 0.9), at(pluck(penta(9), 0.8), 0.16, 0.9)), mix_=0.3)
    anvil = sum(a * sine(800 * r, 1.0) * env(int(SR), 0.001, dd) for r, a, dd in [(1, 1, 0.5), (2.76, 0.5, 0.3), (5.4, 0.3, 0.15), (8.9, 0.2, 0.08)])
    S["forge"] = reverb(mix(anvil, at(pluck(penta(10), 0.8, bright=0.8), 0.15, 1.2), at(pluck(penta(12), 0.8, bright=0.8), 0.27, 1.2)), mix_=0.3)
    sq = np.sign(sine(140, 0.12)) * env(int(0.12 * SR), 0.002, 0.05)
    S["deny"] = fade(lowpass(mix(sq, at(sq, 0.13, 0.3)), 1200) * 0.6)
    # 전투
    d = 0.25
    S["hit"] = fade(mix(drum(95, d, punch=1.2) * 0.8, bandpass(noise(0.08), 300, 2500) * env(int(0.08 * SR), 0.001, 0.02)))
    clang = sum(a * sine(1300 * r, 0.6) * env(int(0.6 * SR), 0.001, dd) for r, a, dd in [(1, 1, 0.25), (1.73, 0.6, 0.18), (2.61, 0.4, 0.1)])
    S["crit"] = fade(mix(drum(70, 0.4, punch=1.5), clang * 0.5, bandpass(noise(0.12), 800, 6000) * env(int(0.12 * SR), 0.001, 0.03)))
    d = 0.45
    tt = t_(d)
    shim = sum(np.sin(2 * np.pi * (700 * k) * tt * (1 + 0.3 * tt)) / k for k in (1, 1.5, 2.25)) * env(len(tt), 0.04, 0.18)
    S["magic"] = reverb(mix(shim * 0.5, bandpass(noise(d), 1500, np.linspace(2000, 7000, len(tt))) * env(len(tt), 0.02, 0.12) * 0.6), mix_=0.35)
    d = 0.4
    tt = t_(d)
    whoosh = bandpass(noise(d), 300, np.linspace(600, 6000, len(tt))) * np.sin(np.linspace(0, np.pi, len(tt)))
    S["skill"] = reverb(mix(whoosh, sine(np.linspace(300, 900, len(tt)), d) * env(len(tt), 0.05, 0.2) * 0.3), mix_=0.25)
    S["ult"] = reverb(mix(gong(98, 3.0), drum(45, 1.2, punch=2.0) * 1.2, at(drum(55, 0.8), 0.18, 3.0) * 0.7), mix_=0.35)
    d = 1.0
    tt = t_(d)
    S["rout"] = fade(mix(drum(60, 0.6, punch=1.5), lowpass(noise(d), np.linspace(2500, 300, len(tt))) * env(len(tt), 0.02, 0.35) * 0.7))
    d = 0.7
    cr = np.zeros(int(d * SR))
    for _ in range(40):
        k = rng.integers(0, len(cr) - 400)
        cr[k:k + 400] += rng.uniform(-1, 1, 400) * np.exp(-np.arange(400) / 40)
    S["burn"] = fade(mix(cr * 0.7, lowpass(noise(d), 700) * env(len(cr), 0.05, 0.3) * 0.6))
    d = 0.5
    tt = t_(d)
    S["splash"] = fade(bandpass(noise(d), np.linspace(2500, 400, len(tt)), 7000) * env(len(tt), 0.003, 0.12))
    d = 0.55
    tt = t_(d)
    S["confuse"] = reverb(sine(600 * (1 + 0.08 * np.sin(2 * np.pi * 9 * tt)) * (1 - 0.3 * tt), d) * env(len(tt), 0.02, 0.25) * 0.6, mix_=0.3)
    S["heal"] = reverb(mix(at(pluck(penta(8), 0.7, bright=0.3, decay=0.998), 0, 1.0), at(pluck(penta(10), 0.7, bright=0.3, decay=0.998), 0.1, 1.0)) * 0.8, mix_=0.4)
    d = 0.35
    tt = t_(d)
    S["debuff"] = fade(lowpass(np.sign(sine(np.linspace(520, 240, len(tt)), d)), 1500) * env(len(tt), 0.005, 0.12) * 0.5)
    S["horn"] = reverb(mix(horn(146.8, 1.4), horn(220, 1.4) * 0.5), mix_=0.3)
    roll = np.zeros(int(2.2 * SR))
    for k, (tm, f) in enumerate([(0, 60), (0.28, 62), (0.56, 58), (0.7, 64), (0.84, 60), (1.0, 50)]):
        roll += at(drum(f, 1.0, punch=1.4) * (1.3 if k == 5 else 1.0), tm, 2.2)
    S["drums"] = reverb(roll, mix_=0.25)
    win = np.zeros(int(2.6 * SR))
    for k, i in enumerate([5, 7, 9, 10, 12]):
        win += at(pluck(penta(i), 1.2, bright=0.7), k * 0.13, 2.6)
    S["win"] = reverb(mix(win, at(gong(196, 2.0) * 0.35, 0.65, 2.6)), mix_=0.35)
    lose = np.zeros(int(2.6 * SR))
    for k, f in enumerate([329.63, 293.66, 246.94, 220.0]):
        lose += at(pluck(f, 1.2, bright=0.2, decay=0.997), k * 0.32, 2.6)
    S["lose"] = reverb(mix(lose, sine(110, 2.6) * env(int(2.6 * SR), 0.4, 1.2) * 0.25), mix_=0.4)
    for k, x in S.items():
        write(os.path.join(OUT_SFX, k + ".wav"), fade(x, 0.001, 0.03))
    return list(S)


# ───────── 경고 · 긴급 등용 (11/10) —— 22.05kHz 모노, 작은 파일 ─────────

SR2 = 22050


def resonator(x, f, bw, sr=SR2):
    """2극 공명 필터 (모음 formant) —— f 는 숫자 또는 x 와 같은 길이의 배열, bw 는 대역폭(Hz)"""
    f = np.broadcast_to(np.asarray(f, dtype=float), x.shape)
    r = np.exp(-np.pi * bw / sr)
    y = np.zeros_like(x)
    y1 = y2 = 0.0
    for i in range(len(x)):
        c = 2 * r * np.cos(2 * np.pi * f[i] / sr)
        yn = (1 - r) * x[i] + c * y1 - r * r * y2
        y2, y1 = y1, yn
        y[i] = yn
    return y


def make_alert_sfx():
    """alert_beep —— 온라인 남은 시간 5초 비프 · alert_war —— 무장 긴급 등용 함성 · alert_wise —— 지장 긴급 등용 (현 · 종 + 낮은 북)"""
    os.makedirs(OUT_SFX, exist_ok=True)
    arng = np.random.default_rng(1110)
    S = {}
    # 비프 —— 1kHz 사인 + 약한 2배음, 부드러운 어택 12ms, 0.11초
    d = 0.11
    tt = t_(d, SR2)
    e = np.minimum(1.0, tt / 0.012) * np.minimum(1.0, (d - tt) / 0.03)
    S["alert_beep"] = (np.sin(2 * np.pi * 1000 * tt) + 0.22 * np.sin(2 * np.pi * 2000 * tt)) * e
    # 무장 함성 —— 군중(떨어진 높이의 톱니파 여럿 → 'ㅏ' 모음 공명) + 거른 잡음 + 낮은 피치 하강 + 짧은 징·북. 1.5초
    d = 1.5
    n = int(d * SR2)
    tt = t_(d, SR2)
    swell = np.minimum(1.0, tt / 0.14) * np.exp(-np.maximum(0, tt - 0.55) / 0.55)
    glide = 1.0 - 0.30 * (1 - np.exp(-tt / 0.7))              # 높이가 아래로 떨어진다
    crowd = np.zeros(n)
    for _ in range(14):
        f0 = arng.uniform(88, 150)
        vib = 1 + 0.012 * np.sin(2 * np.pi * arng.uniform(4, 7) * tt + arng.uniform(0, 6.28))
        ph = np.cumsum(f0 * glide * vib) / SR2 + arng.uniform(0, 1)
        crowd += 2 * (ph % 1) - 1
    voice = resonator(crowd, 720 * glide ** 0.5, 160) + 0.8 * resonator(crowd, 1150 * glide ** 0.5, 200) + 0.35 * resonator(crowd, 2500, 400)
    air = bandpass(arng.uniform(-1, 1, n), 250, 2600, SR2)
    roar = (voice / np.max(np.abs(voice)) * 0.85 + air * 0.45) * swell
    hit = mix(drum(62, 0.7, SR2, punch=1.4) * 0.8, gong(98, 1.5, SR2) * 0.35)
    S["alert_war"] = reverb(mix(roar, hit), SR2, mix_=0.25)[:int(1.6 * SR2)]
    # 지장 —— 맑은 현(뜯는 소리) → 종 한 번 → 낮은 북. 1.9초
    wl = np.zeros(int(2.0 * SR2))
    wl += at(pluck(penta(5), 1.0, SR2, bright=0.75, decay=0.9985), 0.0, 2.0, SR2) * 0.9
    wl += at(pluck(penta(7), 1.0, SR2, bright=0.75, decay=0.9985), 0.16, 2.0, SR2) * 0.7
    bell = sum(a * np.sin(2 * np.pi * 880 * r * t_(1.4, SR2)) * np.exp(-t_(1.4, SR2) / dd)
               for r, a, dd in [(1, 1, 0.9), (2.0, 0.5, 0.6), (2.76, 0.35, 0.45), (5.4, 0.18, 0.2)])
    wl += at(bell * env(len(t_(1.4, SR2)), 0.003, 5, SR2), 0.34, 2.0, SR2) * 0.55
    wl += at(drum(52, 0.9, SR2, punch=1.5), 0.34, 2.0, SR2) * 1.0
    S["alert_wise"] = reverb(wl, SR2, mix_=0.3)[:int(1.95 * SR2)]
    for k, x in S.items():
        write(os.path.join(OUT_SFX, k + ".wav"), fade(x, 0.001, 0.04, SR2), SR2, peak=0.88)
    return list(S)


# ───────── 배경 음악 (끝이 처음으로 이어진다) ─────────

def loopify(x, sr, tail):
    """울림 꼬리를 처음에 겹쳐 반복이 매끄럽게"""
    n = len(x) - int(tail * sr)
    y = x[:n].copy()
    y[:len(x) - n] += x[n:]
    return y


def make_bgm():
    os.makedirs(OUT_BGM, exist_ok=True)
    sr = 22050
    # 메뉴 —— 낮은 드론 위에 고쟁 같은 뜯는 소리가 느긋하게 (60bpm, 32초)
    total = 32.0
    tail = 3.0
    y = np.zeros(int((total + tail) * sr))
    tt = t_(total + tail, sr)
    y += 0.10 * np.sin(2 * np.pi * 65.41 * tt) + 0.07 * np.sin(2 * np.pi * 98.0 * tt) * (0.6 + 0.4 * np.sin(2 * np.pi * tt / 16))
    melody = [7, 9, 10, 9, 7, 5, 4, 5, 7, -1, 9, 12, 10, 9, 7, -1, 5, 7, 9, 7, 5, 4, 2, 4, 5, -1, 4, 2, 0, 2, 4, -1]
    for k, i in enumerate(melody):
        if i < 0:
            continue
        y += at(pluck(penta(i), 2.0, sr, bright=0.45, decay=0.998) * 0.5, k * 1.0, total + tail, sr)
        if k % 4 == 0:
            y += at(pluck(penta(i - 5), 2.5, sr, bright=0.2, decay=0.998) * 0.35, k * 1.0 + 0.5, total + tail, sr)
    y = reverb(y, sr, mix_=0.4, room=0.85)
    write(os.path.join(OUT_BGM, "menu.wav"), loopify(y, sr, tail + 1.2), sr, peak=0.7)
    # 전투 —— 태고 리듬 · 낮은 드론 · 반복 선율 (120bpm, 24초)
    total = 24.0
    tail = 2.0
    beat = 0.5
    y = np.zeros(int((total + tail) * sr))
    tt = t_(total + tail, sr)
    y += 0.08 * np.sin(2 * np.pi * 55 * tt) + 0.05 * np.sin(2 * np.pi * 82.4 * tt)
    pattern = [1, 0, 0.5, 0, 1, 0.4, 0.6, 0.4]
    for bar in range(int(total / (beat * 8))):
        for k, v in enumerate(pattern):
            if v:
                y += at(drum(58 if v == 1 else 75, 0.6, sr, punch=1.2) * v, (bar * 8 + k) * beat, total + tail, sr)
        if bar % 2 == 1:
            y += at(drum(48, 0.8, sr, punch=1.6) * 1.1, (bar * 8 + 7.5) * beat, total + tail, sr)
    ost = [5, 7, 5, 4, 2, 4, 5, 2]
    for k in range(int(total / (beat / 2))):
        i = ost[k % 8] + (2 if (k // 16) % 3 == 2 else 0)
        y += at(pluck(penta(i), 0.5, sr, bright=0.6) * 0.22, k * beat / 2, total + tail, sr)
    for bar in (2, 5):
        y += at(horn(110, 2.2, sr) * 0.25, bar * 8 * beat, total + tail, sr)
    y = reverb(y, sr, mix_=0.25, room=0.8)
    write(os.path.join(OUT_BGM, "battle.wav"), loopify(y, sr, tail + 1.2), sr, peak=0.75)


if __name__ == "__main__":
    import sys
    if "alert" in sys.argv[1:]:
        print("경고 · 긴급 등용 소리:", " ".join(make_alert_sfx()))
        sys.exit(0)
    names = make_sfx() + make_alert_sfx()
    make_bgm()
    print("효과음 %d개 · 배경 음악 2곡" % len(names))
    print(" ".join(names))
