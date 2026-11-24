"""11/24 삽화 화면 기술 · 고유기 이펙트용 먹 그림풍 스프라이트 생성 (외부 에셋 없이 이 스크립트가 직접 그린다 —— 프로젝트 자체 제작물).

사용자: 「이펙트는 에셋을 사든 뭔가 좀 다양하게」 —— Kenney 그림(회색 빛 · 연기)만으로는 갈래가 다 비슷해 보였다.
삽화(먹 선 + 채색) 화풍에 맞춰 먹 번짐 · 붓 획 · 원상 · 부적 · 인장 · 꽃잎 · 얼음 조각 · 불꽃 · 파도 · 구름 · 별 · 귀갑 · 발톱 자국을 만든다.
결과: solgukji_godot/assets/fx/ink/<이름>.png —— war_painting.gd 의 _ink() 가 보통 합성으로 그린다.
  흰 가면 (색을 곱해 쓴다 · 먹이면 INK 를 곱한다): ink_splash_0~2 · ink_wash_0~1 · brush_0~1 · enso_0~1 · petal · ember · claw
  흰 채움 + 먹 테두리 (색을 곱하면 채움만 물들고 테두리는 먹으로 남는다): cloud · star · ice · shell
  제 색 그대로: flame_0~1 · wave · talisman · seal
실행: python tools/scripts/make_ink_fx.py  (그 뒤 godot --headless --path solgukji_godot --import)
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DST = os.path.join(ROOT, "solgukji_godot", "assets", "fx", "ink")
SS = 2      # 크게 그려 줄인다 (가장자리 부드럽게)
INK = (0.16, 0.15, 0.12)


# ── 도구 ──
def vnoise(h, w, cells, seed):
    r = np.random.default_rng(seed)
    g = r.random((cells + 1, cells + 1)).astype(np.float32)
    im = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(im, np.float32) / 255.0


def fbm(h, w, seed, base=4, octaves=4):
    s = np.zeros((h, w), np.float32)
    a, tot = 1.0, 0.0
    for o in range(octaves):
        s += vnoise(h, w, base * 2 ** o, seed * 31 + o) * a
        tot += a
        a *= 0.5
    return s / tot


def noise1d(n, cells, seed):
    r = np.random.default_rng(seed)
    g = r.random(cells + 3)
    x = np.linspace(0, cells, n)
    i = np.floor(x).astype(int)
    f = x - i
    f = f * f * (3 - 2 * f)
    return g[i] * (1 - f) + g[i + 1] * f


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def blur(a, r):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r)), np.float32) / 255.0


def dilate(a, px):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    k = px * 2 + 1
    while k > 9:      # MaxFilter 는 큰 크기가 느리다 —— 여러 번 나눠서
        im = im.filter(ImageFilter.MaxFilter(9))
        k -= 8
    if k >= 3:
        im = im.filter(ImageFilter.MaxFilter(k if k % 2 else k + 1))
    return np.asarray(im, np.float32) / 255.0


def mask_of(size, draw_fn):
    im = Image.new("L", size, 0)
    draw_fn(ImageDraw.Draw(im))
    return np.asarray(im, np.float32) / 255.0


def save(name, rgb, a, out_size):
    """rgb: HxWx3 (0~1), a: HxW (0~1) —— 크게 그린 것을 out_size 로 줄여 저장"""
    h, w = a.shape
    if rgb.ndim == 2:
        rgb = np.dstack([rgb, rgb, rgb])
    arr = np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)[..., None]])
    im = Image.fromarray((arr * 255 + 0.5).astype(np.uint8), "RGBA")
    rgb_im = im.convert("RGB").resize(out_size, Image.LANCZOS)
    a_im = im.getchannel("A").resize(out_size, Image.LANCZOS)
    out = rgb_im.convert("RGBA")
    out.putalpha(a_im)
    out.save(os.path.join(DST, name + ".png"), optimize=True)
    print("ok", name, out_size)


def outlined(fill_rgb, m, px, ink_a=0.92):
    """채움 m 둘레에 먹 테두리 px —— (rgb, a)"""
    d = dilate(m, px)
    ol = np.clip(d - m, 0, 1)
    a = np.maximum(m, ol * ink_a)
    rgb = fill_rgb * m[..., None] + np.array(INK, np.float32) * (1 - m[..., None])
    return rgb, a


def polar(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    c = (n - 1) / 2.0
    return x - c, y - c


# ── 흰 가면 ──
def ink_splash(seed):
    n = 256 * SS
    r = np.random.default_rng(seed)
    x, y = polar(n)
    th = np.arctan2(y, x)
    rr = np.hypot(x, y)
    # 가운데 덩이 —— 각마다 반지름이 들쭉날쭉
    k = noise1d(720, 9, seed)
    idx = ((th + math.pi) / (2 * math.pi) * 719).astype(int)
    m = (rr < n * 0.2 * (0.75 + 0.5 * k[idx])).astype(np.float32)
    im = Image.fromarray((m * 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    for _ in range(r.integers(3, 6)):      # 곁 덩이
        a = r.random() * math.tau
        dist = n * (0.12 + r.random() * 0.12)
        rad = n * (0.05 + r.random() * 0.07)
        cx, cy = n / 2 + math.cos(a) * dist, n / 2 + math.sin(a) * dist
        d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=255)
    for _ in range(r.integers(6, 10)):      # 튀어 나간 줄기 (점점 가늘게) + 끝 방울
        a = r.random() * math.tau
        l0, l1 = n * 0.15, n * (0.28 + r.random() * 0.13)
        w0 = n * (0.02 + r.random() * 0.025)
        steps = 14
        for s in range(steps):
            u = s / (steps - 1)
            dist = l0 + (l1 - l0) * u
            rad = w0 * (1 - u * 0.8)
            cx, cy = n / 2 + math.cos(a) * dist, n / 2 + math.sin(a) * dist
            d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=255)
        rad = w0 * (0.6 + r.random() * 0.6)
        dist = l1 + rad * 2.2
        cx, cy = n / 2 + math.cos(a) * dist, n / 2 + math.sin(a) * dist
        d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=255)
    for _ in range(r.integers(16, 28)):      # 흩어진 방울
        a = r.random() * math.tau
        dist = n * (0.26 + r.random() * 0.16)
        rad = n * (0.004 + r.random() ** 2 * 0.022)
        cx, cy = n / 2 + math.cos(a) * dist, n / 2 + math.sin(a) * dist
        d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=255)
    m = np.asarray(im, np.float32) / 255.0
    g = fbm(n, n, seed + 7, 6, 4)
    m = smooth(0.45, 0.55, blur(m, 2.5 * SS) + (g - 0.5) * 0.35)      # 가장자리 번짐
    pool = np.clip(m - blur(m, 5 * SS), 0, 1)      # 가장자리에 먹이 고인다
    gran = fbm(n, n, seed + 11, 24, 3)
    a = m * (0.78 + 0.22 * gran) + pool * 0.5
    save("ink_splash_%d" % seed, np.ones((n, n), np.float32) * (0.85 + 0.15 * gran), a, (256, 256))


def ink_wash(seed):
    n = 256 * SS
    x, y = polar(n)
    rr = np.hypot(x, y) / (n * 0.45)
    g = fbm(n, n, seed + 3, 3, 5)
    v = g * 0.7 + (1 - rr) * 0.75
    m = smooth(0.5, 0.72, v)
    pool = np.clip(m - blur(m, 8 * SS), 0, 1) * 1.6
    gran = fbm(n, n, seed + 9, 32, 3)
    a = (m * 0.6 + pool) * (0.75 + 0.25 * gran)
    save("ink_wash_%d" % seed, np.ones((n, n), np.float32), a, (256, 256))


def bristle_alpha(s, v, seed, dry=1.0, lanes=56):
    """붓 획 —— s 획 길이 방향(0~1), v 폭 방향(-1~1). 털마다 먹 양이 달라 끝으로 갈수록 갈라진다 (비백)"""
    r = np.random.default_rng(seed)
    ink = r.random(lanes)
    lane = np.clip(np.nan_to_num((v + 1) / 2 * lanes).astype(int), 0, lanes - 1)
    along = np.zeros_like(s)
    for i in range(lanes):
        sel = lane == i
        if not sel.any():
            continue
        nz = noise1d(2048, 40, seed * 100 + i)
        along[sel] = nz[np.clip((s[sel] * 2047).astype(int), 0, 2047)]
    end = 0.5 + 0.5 * ink[lane]      # 털마다 마르는 곳
    edge_dry = np.abs(v) ** 2 * 0.35       # 가장자리 털이 먼저 마른다
    keep = (s < end - edge_dry + (along - 0.5) * 0.25) | (along > 0.35 + 0.6 * smooth(0.25, 1.0, s) * dry)
    keep &= ~((s > 0.3) & (along < 0.18 * dry * s))
    return keep.astype(np.float32)


def brush(seed):
    w, h = 512 * SS, 128 * SS
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.random.default_rng(seed)
    x0, x1 = w * 0.04, w * 0.96
    s = (x - x0) / (x1 - x0)
    bend = (0.08 + r.random() * 0.08) * (1 if seed % 2 == 0 else -1)
    yc = h / 2 + np.sin(np.clip(s, 0, 1) * math.pi) * h * bend
    prof = smooth(0.0, 0.06, s) * np.clip(1 - s, 0, 1) ** 0.65 * (1 + 0.18 * np.exp(-((s - 0.12) / 0.08) ** 2))
    wob = noise1d(w, 18, seed + 5)[x.astype(int)]
    hw = h * 0.36 * prof * (0.9 + 0.2 * wob)
    v = (y - yc) / np.maximum(hw, 1e-3)
    inside = (np.abs(v) < 1) & (s >= 0) & (s <= 1)
    head = ((x - x0 - h * 0.12) ** 2 + (y - h / 2) ** 2) < (h * 0.3) ** 2      # 붓을 누른 머리
    keep = bristle_alpha(np.clip(s, 0, 1), np.clip(v, -1, 1), seed + 40, dry=1.0)
    m = np.where(inside, keep, 0.0)
    m = np.maximum(m, head.astype(np.float32) * (s < 0.12))
    m = blur(m, 0.8 * SS)
    gran = fbm(h, w, seed + 13, 20, 3)
    save("brush_%d" % seed, np.ones((h, w), np.float32) * (0.85 + 0.15 * gran), m * (0.85 + 0.15 * gran), (256, 64))


def enso(seed):
    n = 256 * SS
    x, y = polar(n)
    r = np.random.default_rng(seed)
    th0 = r.random() * math.tau
    span = math.tau * (0.86 + r.random() * 0.06)
    th = np.arctan2(y, x)
    s = np.mod(th - th0, math.tau) / span
    R = n * 0.38 * (1 - 0.05 * s) * (1 + 0.025 * np.sin(s * 9 + seed))
    prof = smooth(0.0, 0.04, s) * np.clip(1 - s, 0, 1) ** 0.55 * (1 + 0.25 * np.exp(-((s - 0.08) / 0.07) ** 2))
    hw = n * 0.065 * prof
    v = (np.hypot(x, y) - R) / np.maximum(hw, 1e-3)
    inside = (np.abs(v) < 1) & (s <= 1)
    keep = bristle_alpha(np.clip(s, 0, 1), np.clip(v, -1, 1), seed + 70, dry=1.1, lanes=44)
    m = np.where(inside, keep, 0.0)
    sx, sy = math.cos(th0) * n * 0.38, math.sin(th0) * n * 0.38      # 시작점 붓 머리
    m = np.maximum(m, (((x - sx) ** 2 + (y - sy) ** 2) < (n * 0.07) ** 2).astype(np.float32))
    m = blur(m, 0.8 * SS)
    gran = fbm(n, n, seed + 17, 20, 3)
    save("enso_%d" % seed, np.ones((n, n), np.float32) * (0.85 + 0.15 * gran), m * (0.85 + 0.15 * gran), (256, 256))


def petal():
    n = 64 * SS * 2
    def dr(d):
        c = n / 2
        d.ellipse([c - n * 0.3, n * 0.08, c + n * 0.02, n * 0.5], fill=255)      # 끝이 갈라진 두 둥근 귀
        d.ellipse([c - n * 0.02, n * 0.08, c + n * 0.3, n * 0.5], fill=255)
        d.polygon([(c - n * 0.32, n * 0.32), (c + n * 0.32, n * 0.32), (c, n * 0.92)], fill=255)
    m = blur(mask_of((n, n), dr), 1.5 * SS)
    notch = mask_of((n, n), lambda d: d.polygon([(n / 2 - n * 0.05, n * 0.06), (n / 2 + n * 0.05, n * 0.06), (n / 2, n * 0.2)], fill=255))
    m = np.clip(m - blur(notch, 1.0), 0, 1)
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    shade = 1.0 - 0.18 * (y / n)
    edge = np.clip(m - blur(m, 2.5 * SS), 0, 1)
    vein = np.exp(-((x - n / 2) / (n * 0.015)) ** 2) * smooth(0.35, 0.85, y / n) * 0.25
    rgb = np.clip(shade - edge * 1.5 - vein, 0.35, 1)
    save("petal", rgb, smooth(0.25, 0.6, m) * 0.97, (64, 64))


def ember():
    n = 64 * SS * 2
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    cx, cy = n / 2, n * 0.58
    dx, dy = (x - cx) / (n * 0.14), (y - cy) / (n * 0.34)
    dy = np.where(dy < 0, dy * 0.75, dy * 1.6)      # 위로 꼬리
    d = np.hypot(dx, dy)
    a = np.clip(1.2 - d, 0, 1) ** 0.7
    rgb = np.clip(1.25 - d * 0.9, 0.35, 1)       # 가운데 밝고 가장자리는 짙게 (밝은 땅에서도 읽히게)
    save("ember", rgb, a, (64, 64))


def claw():
    n = 128 * SS * 2
    m = np.zeros((n, n), np.float32)
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    for i, off in enumerate((-0.22, 0.0, 0.22)):
        s = (y - n * 0.08) / (n * 0.84)
        xc = n / 2 + off * n + np.sin(np.clip(s, 0, 1) * math.pi) * n * 0.08 - s * n * 0.12
        hw = n * 0.055 * np.clip(np.sin(np.clip(s, 0, 1) * math.pi), 0, 1) ** 0.7 * (1.0 if i == 1 else 0.82)
        v = (x - xc) / np.maximum(hw, 1e-3)
        inside = (np.abs(v) < 1) & (s >= 0) & (s <= 1)
        keep = bristle_alpha(np.clip(s, 0, 1), np.clip(v, -1, 1), 300 + i, dry=0.6, lanes=16)
        m = np.maximum(m, np.where(inside, keep, 0.0))
    m = blur(m, 1.0 * SS)
    save("claw", np.ones((n, n), np.float32), m, (128, 128))


# ── 흰 채움 + 먹 테두리 ──
def cloud():
    n = 256 * SS
    lobes = [(0.42, 0.5, 0.16), (0.6, 0.42, 0.14), (0.72, 0.56, 0.12), (0.54, 0.6, 0.13), (0.28, 0.6, 0.09)]
    def dr(d):
        for cx, cy, r in lobes:
            d.ellipse([(cx - r) * n, (cy - r) * n, (cx + r) * n, (cy + r) * n], fill=255)
        pts = []      # 꼬리 —— 왼쪽으로 가늘게 끌리다 말린다
        for k in range(30):
            u = k / 29
            pts.append(((0.3 - u * 0.24) * n, (0.64 + math.sin(u * math.pi) * 0.05) * n, 0.07 * (1 - u) * n + 2))
        for px, py, r in pts:
            d.ellipse([px - r, py - r, px + r, py + r], fill=255)
    m = mask_of((n, n), dr)
    line = Image.new("L", (n, n), 0)
    ld = ImageDraw.Draw(line)
    for cx, cy, r in lobes[:4]:      # 덩이마다 안쪽으로 말리는 소용돌이
        pts = []
        for k in range(60):
            t = k / 59 * math.pi * 2.6
            rad = r * n * 0.78 * (1 - t / (math.pi * 3.0))
            pts.append((cx * n + math.cos(t + cx * 9) * rad, cy * n + math.sin(t + cx * 9) * rad))
        ld.line(pts, fill=255, width=int(3.2 * SS), joint="curve")
    lm = np.asarray(line, np.float32) / 255.0
    y, _ = np.mgrid[0:n, 0:n].astype(np.float32)
    fill = np.clip(1.05 - 0.2 * (y / n), 0, 1)
    rgb, a = outlined(np.dstack([fill] * 3), m, int(3 * SS))
    rgb = rgb * (1 - lm[..., None] * m[..., None]) + np.array(INK, np.float32) * lm[..., None] * m[..., None]
    save("cloud", rgb, a, (256, 256))


def star():
    n = 128 * SS * 2
    c = n / 2
    pts = []
    for k in range(16):
        ang = k * math.tau / 16 - math.pi / 2
        r = [0.47, 0.1, 0.27, 0.1][k % 4] * n
        pts.append((c + math.cos(ang) * r, c + math.sin(ang) * r))
    m = mask_of((n, n), lambda d: d.polygon(pts, fill=255))
    x, y = polar(n)
    fill = np.clip(1.15 - np.hypot(x, y) / (n * 0.5) * 0.35, 0, 1)
    rgb, a = outlined(np.dstack([fill] * 3), m, int(3 * SS * 2))
    save("star", rgb, a, (128, 128))


def ice():
    n = 128 * SS * 2
    pts = [(0.5, 0.04), (0.66, 0.3), (0.62, 0.78), (0.5, 0.96), (0.36, 0.74), (0.33, 0.34)]
    P = [(px * n, py * n) for px, py in pts]
    ridge = (0.49 * n, 0.5 * n)
    faces = Image.new("L", (n, n), 0)
    fd = ImageDraw.Draw(faces)
    tones = [255, 205, 170, 225, 190, 240]
    for i in range(len(P)):
        fd.polygon([ridge, P[i], P[(i + 1) % len(P)]], fill=tones[i])
    f = np.asarray(faces, np.float32) / 255.0
    m = (f > 0).astype(np.float32)
    lines = Image.new("L", (n, n), 0)
    ld = ImageDraw.Draw(lines)
    for p in P:
        ld.line([ridge, p], fill=255, width=int(1.6 * SS * 2))
    lm = np.asarray(lines, np.float32) / 255.0 * 0.6
    hi = mask_of((n, n), lambda d: d.line([(0.47 * n, 0.12 * n), (0.42 * n, 0.45 * n)], fill=255, width=int(3 * SS * 2)))
    fill = np.clip(f * (1 - lm) + hi, 0, 1)
    rgb, a = outlined(np.dstack([fill] * 3), m, int(2.5 * SS * 2))
    save("ice", rgb, a, (128, 128))


def shell():
    n = 256 * SS
    c = n / 2
    R = n * 0.45
    line = Image.new("L", (n, n), 0)
    ld = ImageDraw.Draw(line)
    hs = n * 0.085      # 육각 한 변
    for row in range(-7, 8):
        for col in range(-7, 8):
            cx = c + col * hs * 1.5
            cy = c + row * hs * math.sqrt(3) + (hs * math.sqrt(3) / 2 if col % 2 else 0)
            hexp = [(cx + math.cos(k * math.pi / 3) * hs, cy + math.sin(k * math.pi / 3) * hs) for k in range(7)]
            ld.line(hexp, fill=255, width=int(2.6 * SS), joint="curve")
    ld.ellipse([c - R, c - R, c + R, c + R], outline=255, width=int(5 * SS))
    lm = np.asarray(line, np.float32) / 255.0
    x, y = polar(n)
    rr = np.hypot(x, y)
    disc = (rr < R + 3 * SS).astype(np.float32)
    lm *= disc
    rgb, a = outlined(np.ones((n, n, 3), np.float32), lm, int(2 * SS))
    a = a * disc + (rr < R).astype(np.float32) * 0.16 * (1 - a)      # 얇은 막
    a *= 0.55 + 0.45 * smooth(0.0, 1.0, rr / R)      # 가운데는 옅게
    save("shell", rgb, a, (256, 256))


# ── 제 색 ──
def tongue(d, base, h, w, curl, phase, n_pts=40):
    left, right = [], []
    for k in range(n_pts):
        s = k / (n_pts - 1)
        cx = base[0] + curl * math.sin(s * math.pi * 0.9 + phase) * s * h * 0.35
        cy = base[1] - s * h
        ww = w * (1 - s) ** 0.85 * (0.55 + 0.45 * math.sin(min(1.0, s * 1.6) * math.pi * 0.5 + 0.6))
        left.append((cx - ww, cy))
        right.append((cx + ww, cy))
    d.polygon(left + right[::-1], fill=255)


def flame(seed):
    n = 256 * SS
    r = np.random.default_rng(seed)
    def body(d):
        sgn = 1.0 if seed == 0 else -1.0
        tongue(d, (n * 0.33, n * 0.93), n * (0.42 + r.random() * 0.1), n * 0.12, -0.8 * sgn, 0.0)
        tongue(d, (n * 0.67, n * 0.93), n * (0.5 + r.random() * 0.1), n * 0.12, 0.8 * sgn, 0.4)
        tongue(d, (n * 0.5, n * 0.95), n * 0.9, n * 0.24, 0.55 * sgn, -0.3)
        d.ellipse([n * 0.24, n * 0.78, n * 0.76, n * 0.98], fill=255)
    m = mask_of((n, n), body)
    core = mask_of((n, n), lambda d: tongue(d, (n * 0.5, n * 0.95), n * 0.55, n * 0.12, 0.45 if seed == 0 else -0.45, -0.3))
    core = blur(core, 2 * SS)
    y, _ = np.mgrid[0:n, 0:n].astype(np.float32)
    k = np.clip((n * 0.95 - y) / (n * 0.85), 0, 1)[..., None]
    red = np.array([0.78, 0.14, 0.05], np.float32)
    ora = np.array([0.98, 0.5, 0.12], np.float32)
    yel = np.array([1.0, 0.85, 0.32], np.float32)
    fill = np.where(k < 0.45, red + (ora - red) * (k / 0.45), ora + (yel - ora) * ((k - 0.45) / 0.55))
    fill = fill * (1 - core[..., None]) + np.array([1.0, 0.95, 0.7], np.float32) * core[..., None]
    rgb, a = outlined(fill, m, int(3 * SS))
    save("flame_%d" % seed, rgb, a, (256, 256))


def wave():
    n = 256 * SS
    pts = []      # 물마루 가운데 줄기 —— 왼쪽 아래에서 솟아 오른쪽으로 말려 든다
    for k in range(80):
        u = k / 79
        if u < 0.55:
            q = u / 0.55
            px = 0.06 + q * 0.5
            py = 0.9 - math.sin(q * math.pi * 0.5) * 0.6
        else:
            q = (u - 0.55) / 0.45
            ang = -math.pi * 0.5 + q * math.pi * 1.55
            rad = 0.2 * (1 - q * 0.75)
            px = 0.56 + math.cos(ang) * rad - 0.0
            py = 0.5 + math.sin(ang) * rad
        pts.append((px * n, py * n, (0.13 * (1 - u) ** 0.8 + 0.012) * n))
    m = mask_of((n, n), lambda d: [d.ellipse([x - r, y - r, x + r, y + r], fill=255) for x, y, r in pts])
    base = mask_of((n, n), lambda d: d.polygon([(0.0, n * 0.98), (n * 0.04, n * 0.82), (n * 0.45, n * 0.62), (n * 0.75, n * 0.8), (n, n * 0.98)], fill=255))
    m = np.maximum(m, base)
    bands = Image.new("L", (n, n), 0)
    bd = ImageDraw.Draw(bands)
    for off in (-0.45, 0.0, 0.45):      # 물결 무늬 —— 줄기를 따라 밝은 띠
        bd.line([(x + off * r * 0.0, y + off * r) for x, y, r in pts[4:60]], fill=255, width=int(2.4 * SS), joint="curve")
    bm = np.asarray(bands, np.float32) / 255.0 * m
    deep = np.array([0.16, 0.36, 0.62], np.float32)
    light = np.array([0.55, 0.78, 0.95], np.float32)
    fill = deep + (light - deep) * bm[..., None]
    foam = Image.new("L", (n, n), 0)      # 물마루 끝 거품 —— 손톱 같은 흰 방울
    fd = ImageDraw.Draw(foam)
    for k in range(9):
        u = 0.45 + k * 0.045
        i = min(79, int(u * 79))
        x, y, r = pts[i]
        out = -1.0
        fr = n * (0.03 - k * 0.0015)
        fd.ellipse([x - fr, y - r + out * fr * 0.6 - fr, x + fr, y - r + out * fr * 0.6 + fr], fill=255)
    fm = np.asarray(foam, np.float32) / 255.0
    allm = np.maximum(m, fm)
    fill = fill * (1 - fm[..., None]) + np.array([0.97, 0.97, 0.93], np.float32) * fm[..., None]
    fill = fill * (1 - np.clip(dilate(fm, int(1.5 * SS)) - fm, 0, 1)[..., None] * 0.7)
    rgb, a = outlined(fill, allm, int(3 * SS))
    save("wave", rgb, a, (256, 256))


def talisman():
    w, h = 128 * SS * 2, 320 * SS * 2
    r = np.random.default_rng(42)
    g = fbm(h, w, 5, 6, 4)
    fib = fbm(h, w, 6, 40, 2)
    edge = noise1d(h, 30, 8)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    m = ((x > w * 0.06 + edge[y.astype(int)] * w * 0.03) & (x < w * 0.94 - edge[::-1][y.astype(int)] * w * 0.03)
         & (y > h * 0.02) & (y < h * 0.98)).astype(np.float32)
    paper = np.array([0.93, 0.79, 0.36], np.float32) * (0.88 + 0.12 * g[..., None]) * (0.95 + 0.05 * fib[..., None])
    glyph = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(glyph)
    lw = int(w * 0.055)
    cx = w / 2
    for k in range(3):      # 부두(符頭) —— 세 가로획
        yy = h * (0.08 + k * 0.035)
        d.line([(cx - w * 0.28, yy), (cx + w * 0.28, yy)], fill=255, width=lw)
    d.ellipse([cx - w * 0.16, h * 0.2, cx + w * 0.16, h * 0.2 + w * 0.32], outline=255, width=lw)
    spine = []
    for k in range(120):      # 가운데 줄기 —— 구불구불 내려가며 고리 셋
        u = k / 119
        yy = h * (0.36 + u * 0.52)
        xx = cx + math.sin(u * math.pi * 7) * w * 0.17 * (1 - u * 0.3)
        spine.append((xx, yy))
    d.line(spine, fill=255, width=lw, joint="curve")
    for k in range(3):
        yy = h * (0.42 + k * 0.15)
        d.line([(cx - w * 0.3, yy + w * 0.08), (cx + w * 0.3, yy - w * 0.08)], fill=255, width=int(lw * 0.8))
    d.rectangle([cx - w * 0.22, h * 0.88, cx + w * 0.22, h * 0.94], outline=255, width=int(lw * 0.8))
    gm = blur(np.asarray(glyph, np.float32) / 255.0, 1.2 * SS)
    gm *= 0.8 + 0.2 * g
    border = ((np.abs(x - w * 0.12) < w * 0.012) | (np.abs(x - w * 0.88) < w * 0.012)).astype(np.float32) * 0.5
    red = np.array([0.74, 0.12, 0.08], np.float32)
    rgb = paper * (1 - gm[..., None]) + red * gm[..., None]
    rgb = rgb * (1 - border[..., None] * 0.4)
    shade = np.clip(m - blur(m, 3 * SS), 0, 1)[..., None]      # 가장자리 그늘
    rgb = rgb * (1 - shade * 0.5)
    save("talisman", rgb, m * 0.98, (128, 320))


def seal():
    n = 128 * SS * 2
    r = np.random.default_rng(9)
    g = fbm(n, n, 21, 8, 4)
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    pad = n * 0.08
    m = ((x > pad) & (x < n - pad) & (y > pad) & (y < n - pad)).astype(np.float32)
    m = smooth(0.45, 0.55, blur(m, 2 * SS) + (g - 0.5) * 0.25)      # 찍힌 가장자리 —— 거칠게
    carve = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(carve)
    fr = n * 0.15
    d.rectangle([fr, fr, n - fr, n - fr], outline=255, width=int(n * 0.03))      # 안쪽 테
    cells = 4      # 전서(篆書) 같은 각진 획 —— 칸 격자를 따라 구불구불
    cs = (n - 2 * fr - n * 0.12) / cells
    ox = fr + n * 0.06
    for col in range(2):
        cx0 = ox + col * cs * 2
        x0, y0 = cx0 + cs * 0.5, ox + cs * 0.5
        path = [(x0, y0)]
        cxp, cyp = 0, 0
        for step in range(9):
            if step % 2 == 0:
                cxp = 1 - cxp
            else:
                cyp = min(cells - 1, cyp + 1)
            path.append((cx0 + cs * (0.5 + cxp), ox + cs * (0.5 + cyp)))
        d.line(path, fill=255, width=int(n * 0.045), joint="curve")
        d.line([(cx0 + cs * 0.2, ox + cs * 1.0), (cx0 + cs * 1.8, ox + cs * 1.0)], fill=255, width=int(n * 0.04))
        if r.random() < 0.7:
            d.line([(cx0 + cs * 1.0, ox + cs * 2.0), (cx0 + cs * 1.0, ox + cs * 3.6)], fill=255, width=int(n * 0.04))
    cm = blur(np.asarray(carve, np.float32) / 255.0, 1.0 * SS)
    speck = (fbm(n, n, 33, 30, 2) > 0.72).astype(np.float32) * 0.5      # 인주가 덜 묻은 곳
    red = np.array([0.76, 0.13, 0.1], np.float32) * (0.85 + 0.15 * g[..., None])
    paper = np.array([0.96, 0.9, 0.78], np.float32)
    rgb = red * (1 - cm[..., None]) + paper * cm[..., None]
    a = m * (1 - speck * (1 - cm)) * 0.97
    save("seal", rgb, a, (128, 128))


def main():
    os.makedirs(DST, exist_ok=True)
    for s in range(3):
        ink_splash(s)
    for s in range(2):
        ink_wash(s)
        brush(s)
        enso(s)
        flame(s)
    petal()
    ember()
    claw()
    cloud()
    star()
    ice()
    shell()
    wave()
    talisman()
    seal()


if __name__ == "__main__":
    main()
