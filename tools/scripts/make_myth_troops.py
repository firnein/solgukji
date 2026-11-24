# -*- coding: utf-8 -*-
"""신화 부대 전용 병사 시트 만들기 (11/24) —— 삽화 전투 화면.

기존 동작 시트(troops_action_blue_v1.png · troops_action_red_v1.png, 4열 × 8행, 행 = 병종, 열 = 자세)에서
같은 배치의 신화 시트(troops_myth_blue_v1.png · troops_myth_red_v1.png)를 만든다. 다시 돌리면 같은 그림이 나온다.

작은 화면(인형 키 20~45px)에서 읽히는 것은 실루엣과 색이라:
  1) 색: 밝기를 「흑칠 → 진영색(청 · 적) → 금」 다섯 단 그라데이션에 다시 입힌다 —— 흑칠 금장 갑옷, 가운데 톤이 진영색이라 청 · 적이 그대로 읽힌다
  2) 금 테두리: 실루엣을 몇 px 부풀린 금빛 띠를 인형 뒤에 깐다
  3) 실루엣: 무장(창병 · 기병 · 궁병 · 도적)은 등에 진영색 배기(靠旗) 두 장 + 투구에 긴 깃털(翎子) 두 가닥,
     책략계(책사 · 유생 · 술사 · 모사)는 머리 뒤 금빛 광배(光背) + 깃털
  4) 장식이 칸 위로 잘리지 않게 인형을 FIT 배로 줄여 발(칸 x 0.5 · y 0.97)에 맞춰 둔다 —— 게임은 신화 인형 칸을 1 / FIT 배로 그려 몸 크기를 맞춘다
     (scripts/field/painted_batch.gd MYTH_QUAD 와 같은 값)

실행:  python tools/scripts/make_myth_troops.py  [--preview 미리보기.png]
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, "solgukji_godot", "assets", "war_painting")
COLS, ROWS = 4, 8
FIT = 0.8                 # 인형을 칸의 이만큼으로 줄인다 (발 기준) —— painted_batch.gd MYTH_QUAD = 1 / FIT
FOOT = (0.5, 0.97)        # 메시 기준점 (painted_batch._grid: uv - (0.5, 0.97))
SS = 3                    # 장식은 3배로 그려 줄인다 (가장자리 매끈하게)

# 진영별 색 —— 그라데이션 (밝기 0 → 1) 과 배기 천
FACTION = {
    "blue": {
        "ramp": [(0.00, (6, 6, 12)), (0.34, (16, 24, 58)), (0.56, (40, 96, 214)), (0.77, (230, 178, 70)), (1.00, (255, 242, 196))],
        "flag": (38, 98, 228), "flag_dark": (16, 40, 120),
    },
    "red": {
        "ramp": [(0.00, (10, 6, 6)), (0.34, (56, 10, 10)), (0.56, (204, 34, 24)), (0.77, (234, 178, 68)), (1.00, (255, 240, 190))],
        "flag": (214, 38, 28), "flag_dark": (110, 14, 12),
    },
}
GOLD = (246, 196, 84)
GOLD_LIGHT = (255, 236, 160)
INK = (24, 16, 10)
KEEP_ORIGINAL = 0.18      # 원래 색을 조금 남긴다 (얼굴 · 무기 결)
SUPPORT_ROWS = (4, 5, 6, 7)


def cell_box(c, r, w, h):
    return (round(c * w / COLS), round(r * h / ROWS), round((c + 1) * w / COLS), round((r + 1) * h / ROWS))


def ramp_map(lum, stops):
    """밝기(0~1 배열) → RGB (다섯 단 선형)"""
    out = np.zeros(lum.shape + (3,), np.float32)
    xs = [s[0] for s in stops]
    for ch in range(3):
        out[..., ch] = np.interp(lum, xs, [s[1][ch] for s in stops])
    return out


def recolor(fig, faction):
    a = np.array(fig).astype(np.float32)
    rgb = a[..., :3] / 255.0
    alpha = a[..., 3]
    lum = rgb[..., 0] * 0.3 + rgb[..., 1] * 0.59 + rgb[..., 2] * 0.11
    m = alpha > 128
    if m.sum() < 50:
        return fig
    lo, hi = np.percentile(lum[m], 4), np.percentile(lum[m], 97)
    n = np.clip((lum - lo) / max(hi - lo, 1e-3), 0, 1)
    n = n ** 1.08
    mapped = ramp_map(n, FACTION[faction]["ramp"])
    out = mapped * (1 - KEEP_ORIGINAL) + rgb * 255.0 * KEEP_ORIGINAL
    res = np.dstack([np.clip(out, 0, 255), alpha]).astype(np.uint8)
    return Image.fromarray(res, "RGBA")


def head_of(alpha):
    """머리 꼭대기 (x, y) —— 몸통 띠(위 35~60%)의 무게 중심 x 근처에서, 가로로 넓은(무기 자루가 아닌) 첫 줄"""
    h, w = alpha.shape
    m = alpha > 128
    ys = np.where(m.any(1))[0]
    top, bottom = ys[0], ys[-1]
    band = m[int(top + (bottom - top) * 0.30): int(top + (bottom - top) * 0.55)]
    xs = np.where(band)[1]
    cx = int(np.median(xs)) if len(xs) else w // 2
    span = int(w * 0.16)
    for y in range(top, bottom):
        row = m[y, max(0, cx - span): cx + span]
        if row.sum() >= w * 0.07:
            xs_row = np.where(row)[0] + max(0, cx - span)
            return int(xs_row.mean()), y
    return cx, top


def draw_flag(d, base, tip, flag_len, color, dark, s):
    """등에 꽂은 배기 —— 깃대(base → tip) 끝에 뒤쪽(왼쪽)으로 날리는 삼각기 (금테)"""
    bx, by = base
    tx, ty = tip
    d.line([(bx, by), (tx, ty)], fill=INK, width=int(5 * s))
    d.line([(bx, by), (tx, ty)], fill=GOLD, width=int(3 * s))
    # 깃대 방향 단위 벡터와 뒤쪽 수직
    vx, vy = tx - bx, ty - by
    ln = math.hypot(vx, vy)
    ux, uy = vx / ln, vy / ln
    px, py = -uy, ux             # 깃대에 수직 (왼쪽 = 뒤)
    if px > 0:
        px, py = -px, -py
    a0 = (tx, ty)
    a1 = (tx - ux * flag_len * 0.62, ty - uy * flag_len * 0.62)
    far = (tx - ux * flag_len * 0.22 + px * flag_len, ty - uy * flag_len * 0.22 + py * flag_len)
    poly = [a0, far, a1]
    d.polygon(poly, fill=INK)
    inner = [(x * 0.84 + (a0[0] + far[0] + a1[0]) / 3 * 0.16, y * 0.84 + (a0[1] + far[1] + a1[1]) / 3 * 0.16) for x, y in poly]
    d.polygon(poly, fill=GOLD)
    d.polygon(inner, fill=color)
    # 천 가운데 짙은 띠 (접힌 그늘)
    mid = [(a0[0] * 0.5 + a1[0] * 0.5, a0[1] * 0.5 + a1[1] * 0.5), far]
    d.line(mid, fill=dark, width=int(3 * s))
    # 깃대 끝 금 창날
    d.polygon([(tx + ux * 9 * s, ty + uy * 9 * s), (tx + px * 4 * s, ty + py * 4 * s), (tx - px * 4 * s, ty - py * 4 * s)], fill=GOLD_LIGHT)


def draw_plume(d, root, length, lean, s, color=GOLD_LIGHT):
    """투구 깃털 (翎子) —— 머리에서 뒤(왼쪽)로 휘어 올라가는 긴 깃 한 가닥"""
    rx, ry = root
    pts = []
    for i in range(17):
        t = i / 16
        x = rx - length * (0.15 * t + lean * t * t)
        y = ry - length * (0.95 * t - 0.55 * t * t)
        pts.append((x, y))
    d.line(pts, fill=INK, width=int(10 * s), joint="curve")
    d.line(pts, fill=color, width=int(6 * s), joint="curve")
    # 끝의 흰 깃
    d.ellipse([pts[-1][0] - 5 * s, pts[-1][1] - 4 * s, pts[-1][0] + 5 * s, pts[-1][1] + 4 * s], fill=(255, 250, 235))


def draw_halo(d, center, r, s, faction):
    """책략계 광배 —— 머리 뒤 금 고리 + 옅은 빛 원판"""
    cx, cy = center
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GOLD + (110,))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=INK + (255,), width=int(8 * s))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=GOLD + (255,), width=int(5 * s))
    r2 = r * 0.72
    d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], outline=FACTION[faction]["flag"] + (255,), width=int(3 * s))


def make_cell(fig, r, faction):
    """칸 하나 —— fig 는 원래 칸 그림 (RGBA). 같은 크기의 신화 칸을 돌려준다"""
    w, h = fig.size
    col = recolor(fig, faction)
    fw, fh = max(1, round(w * FIT)), max(1, round(h * FIT))
    small = col.resize((fw, fh), Image.LANCZOS)
    ox = round(FOOT[0] * w - FOOT[0] * fw)
    oy = round(FOOT[1] * h - FOOT[1] * fh)
    body = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    body.alpha_composite(small, (ox, oy))
    alpha = np.array(body)[..., 3]
    hx, hy = head_of(alpha)

    # 뒤 장식 (몸 뒤) —— 3배로 그려 줄인다
    S = SS
    back = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(back, "RGBA")
    support = r in SUPPORT_ROWS
    cav = r == 1
    if support:
        draw_halo(bd, ((hx - 0.01 * w) * S, (hy + 0.06 * h) * S), 0.16 * w * S, S, faction)
    else:
        # 배기 두 장 —— 어깨 뒤(머리 아래 · 왼쪽)에서 위로
        sh_x, sh_y = hx - 0.07 * w, hy + (0.10 if cav else 0.13) * h
        for k, (dx, ty, fl) in enumerate([(-0.11, 0.05, 0.25), (0.03, 0.03, 0.21)]):
            base = (sh_x * S, sh_y * S)
            tip = ((sh_x + dx * w) * S, min(ty * h, hy - 0.04 * h) * S)
            draw_flag(bd, base, tip, fl * w * S, FACTION[faction]["flag"], FACTION[faction]["flag_dark"], S)
    # 깃털 두 가닥 (모두)
    for lean, ln in [(0.55, 0.24), (0.85, 0.2)]:
        draw_plume(bd, (hx * S, (hy + 0.012 * h) * S), ln * h * S, lean, S)
    back = back.resize((w, h), Image.LANCZOS)

    # 금 테두리 —— 몸 실루엣을 부풀린 띠
    a_img = Image.fromarray(alpha, "L")
    grown = a_img.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(1.2))
    rim = Image.new("RGBA", (w, h), GOLD + (0,))
    rim.putalpha(grown.point(lambda v: min(255, int(v * 1.15))))
    glow = a_img.filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.GaussianBlur(5))
    halo = Image.new("RGBA", (w, h), GOLD_LIGHT + (0,))
    halo.putalpha(glow.point(lambda v: int(v * 0.35)))

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(halo)
    out.alpha_composite(back)
    out.alpha_composite(rim)
    out.alpha_composite(body)
    return out


def make_sheet(faction):
    src = Image.open(os.path.join(ART, "troops_action_%s_v1.png" % faction)).convert("RGBA")
    W, H = src.size
    dst = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for r in range(ROWS):
        for c in range(COLS):
            box = cell_box(c, r, W, H)
            cell = src.crop(box)
            dst.alpha_composite(make_cell(cell, r, faction), (box[0], box[1]))
    return dst


def main():
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]
    sheets = {}
    for faction in ("blue", "red"):
        sheet = make_sheet(faction)
        path = os.path.join(ART, "troops_myth_%s_v1.png" % faction)
        sheet.save(path, optimize=True)
        sheets[faction] = sheet
        print("wrote", path, sheet.size)
    if preview:
        W, H = sheets["blue"].size
        cw = W // COLS
        out = Image.new("RGBA", (W, H), (200, 190, 160, 255))
        for i, f in enumerate(("blue", "red")):
            for j, c in enumerate((0, 2)):
                out.alpha_composite(sheets[f].crop((c * cw, 0, (c + 1) * cw, H)), (cw * (i * 2 + j), 0))
        out.resize((W // 2, H // 2), Image.LANCZOS).save(preview)
        print("preview", preview)


if __name__ == "__main__":
    main()
