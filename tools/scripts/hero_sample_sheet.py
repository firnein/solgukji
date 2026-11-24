"""장수 인형 모음 그림 (11/24) —— 후보마다 번호 · 짧은 설명 + 실제 화면 크기(60px · 40px)로 줄인 것.

실행 (D:\\solgukji-wt-hero 에서)
  python -I tools/scripts/hero_sample_sheet.py <목록.json> <저장.png> [한 줄 칸 수, 기본 6]
목록.json: [{"no": 1, "who": "관우", "desc": "...", "path": ".../A_5100_cut.png", "flip": false}, ...]
           또는 장수인형_고름.json (items 의 name · variant · seed · flip 으로 prompts/comfy/out/장수인형 의 그림을 찾는다)
아래 줄: 같은 후보를 키 60px · 40px 로 줄인 것 (전투 화면 크기) 옆에 같은 비율의 병사(장수 키의 1/1.75)를 세워 크기를 비교.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

GROUND = (200, 182, 140, 255)      # 삽화 바닥 모래빛 쯤
INK = (40, 34, 26, 255)
SOLDIER = "solgukji_godot/assets/war_painting/troops_action_blue_v1.png"
OUT_DIR = "prompts/comfy/out/장수인형"
HERO_FIG = 1.75                    # 장수 키 = 병사 키 × 이 값 (war_painting.HERO_FIG)
BIG_H = 300


def font(sz):
    try:
        return ImageFont.truetype("C:/Windows/Fonts/malgunbd.ttf", sz)
    except OSError:
        return ImageFont.load_default()


def fit_h(im, h):
    return im.resize((max(1, round(im.width * h / im.height)), h), Image.LANCZOS)


def soldier(row):
    sh = Image.open(SOLDIER).convert("RGBA")
    cw, ch = sh.width / 4, sh.height / 8
    c = sh.crop((0, round(row * ch), round(cw), round((row + 1) * ch)))
    return c.crop(c.getchannel("A").getbbox())


def load_items(path):
    d = json.load(open(path, encoding="utf-8"))
    if isinstance(d, list):
        return d
    out = []
    for n, it in enumerate(d["items"]):
        out.append({"no": n + 1, "who": it["name"], "desc": it.get("desc", f"{it['variant']} 시드 {it['seed']}"),
                    "path": os.path.join(OUT_DIR, it["name"], f"{it['variant']}_{it['seed']}_cut.png"), "flip": it.get("flip", False)})
    return out


def tile(it, im, sol, f1, f2, f3):
    cw = max(fit_h(im, BIG_H).width, 200) + 16
    rows_y = [40 + BIG_H + 64, 40 + BIG_H + 64 + 60 * 2 + 28]      # 60px 줄 · 40px 줄 위쪽 (×2 확대가 들어갈 높이)
    th = rows_y[1] + 40 * 2 + 28
    t = Image.new("RGBA", (cw, th), GROUND)
    d = ImageDraw.Draw(t)
    d.text((0, 8), f"{it['no']}. {it['who']}", fill=INK, font=f1)
    b = fit_h(im, BIG_H)
    t.alpha_composite(b, ((cw - 16 - b.width) // 2, 40))
    words, lines, cur = it["desc"].split(" "), [], ""
    for w in words:
        if d.textlength(cur + " " + w, font=f2) > cw - 20 and cur:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    lines.append(cur)
    for k, ln in enumerate(lines[:3]):
        d.text((0, 40 + BIG_H + 6 + k * 18), ln, fill=INK, font=f2)
    for r, px in enumerate((60, 40)):
        hero = fit_h(im, px)
        s = fit_h(sol, round(px / HERO_FIG))
        base = rows_y[r] + px * 2
        t.alpha_composite(s, (0, base - s.height))
        t.alpha_composite(hero, (s.width + 2, base - hero.height))
        z = hero.resize((hero.width * 2, hero.height * 2), Image.NEAREST)      # ×2 확대 (보기용)
        zx = s.width + hero.width + 14
        if zx + z.width <= cw:
            t.alpha_composite(z, (zx, base - z.height))
        d.text((0, base + 4), f"{px}px (+병사 · ×2)", fill=INK, font=f3)
    return t


def main():
    items = load_items(sys.argv[1])
    dst = sys.argv[2]
    per_row = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    f1, f2, f3 = font(22), font(14), font(13)
    sol = soldier(0)
    tiles = []
    for it in items:
        im = Image.open(it["path"]).convert("RGBA")
        if it.get("flip"):
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        tiles.append(tile(it, im, sol, f1, f2, f3))
    rows = [tiles[i:i + per_row] for i in range(0, len(tiles), per_row)]
    W = max(sum(t.width for t in r) for r in rows) + 32
    H = sum(max(t.height for t in r) for r in rows) + 40
    sheet = Image.new("RGBA", (W, H), GROUND)
    y = 8
    for r in rows:
        x = 16
        for t in r:
            sheet.alpha_composite(t, (x, y))
            x += t.width
        y += max(t.height for t in r)
    ImageDraw.Draw(sheet).text((16, H - 26), f"아래 두 줄: 장수 키 60px · 40px (전투 화면 크기), 왼쪽 작은 인형은 같은 비율의 청군 창병 (장수 = 병사 × {HERO_FIG}), 오른쪽은 ×2 확대",
                               fill=INK, font=f3)
    sheet.convert("RGB").save(dst)
    print(dst, sheet.size)


if __name__ == "__main__":
    main()
