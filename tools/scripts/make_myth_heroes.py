"""신화 장수 인형 시트 (11/24) —— 고른 그림(hero_gen.py 결과)을 같은 크기 칸에 맞춰 한 장으로 묶는다.

실행 (D:\\solgukji-wt-hero 에서)
  python -I tools/scripts/make_myth_heroes.py [prompts/comfy/장수인형_고름.json]
읽는 것: 고름.json 의 items —— {"name", "spec", "variant", "seed", "flip"}
         그림은 prompts/comfy/out/장수인형/<name>/<variant>_<seed>_cut.png (없으면 hero_gen.py 로 그 시드를 다시 뽑는다:
         python -I tools/scripts/hero_gen.py <spec> <name> -v <variant> -n 1 --seed <seed>)
만드는 것: solgukji_godot/assets/war_painting/myth_heroes_v1.png (grid 열 × 행, 칸 cell px)
           solgukji_godot/data/myth_heroes.json (인물 -> 칸 번호 i · fill = 인형 키 / 칸 키 · mounted)
칸 맞춤: 투명 테두리를 자르고, 아래 35% (다리 · 말발굽) 의 알파 무게중심을 칸 가운데(0.5)에, 맨 아래(발)를 칸의 foot(0.97)에 둔다.
         키는 칸의 body 배까지, 무기 · 말이 옆으로 넘치면 그만큼 줄인다 (줄인 만큼 fill 이 작아지고 게임이 칸을 키워 몸 키를 맞춘다).
"""
import json
import os
import sys

import numpy as np
from PIL import Image

OUT_DIR = "prompts/comfy/out/장수인형"
SHEET = "solgukji_godot/assets/war_painting/myth_heroes_v1.png"
DATA = "solgukji_godot/data/myth_heroes.json"


def load_cut(it):
    p = os.path.join(OUT_DIR, it["name"], f"{it['variant']}_{it['seed']}_cut.png")
    im = Image.open(p).convert("RGBA")
    a = np.asarray(im).copy()
    a[..., 3] = np.where(a[..., 3] < 16, 0, a[..., 3])      # 배경 지운 뒤 남은 옅은 안개
    im = Image.fromarray(a, "RGBA")
    im = im.crop(im.getchannel("A").getbbox())
    if it.get("flip"):
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    return im


def main():
    pick = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "prompts/comfy/장수인형_고름.json", encoding="utf-8"))
    cell, (gc, gr) = int(pick["cell"]), pick["grid"]
    foot, body, margin = float(pick["foot"]), float(pick["body"]), float(pick.get("margin", 0.015))
    assert len(pick["items"]) <= gc * gr <= 32
    sheet = Image.new("RGBA", (cell * gc, cell * gr), (0, 0, 0, 0))
    cells = {}
    for i, it in enumerate(pick["items"]):
        im = load_cut(it)
        w, h = im.size
        a = np.asarray(im.getchannel("A")).astype(np.float64)
        low = a[int(h * 0.65):]
        ax = float((low.sum(axis=0) * np.arange(w)).sum() / max(low.sum(), 1.0))      # 다리 쪽 무게중심
        half = (0.5 - margin) * cell
        s = min(body * cell / h, (foot - margin) * cell / h, half / max(ax, 1.0), half / max(w - ax, 1.0))
        tw, th = max(1, round(w * s)), max(1, round(h * s))
        small = im.convert("RGBa").resize((tw, th), Image.LANCZOS).convert("RGBA")      # 곧은 알파 가장자리가 검게 번지지 않게
        cx, cy = (i % gc) * cell, (i // gc) * cell
        sheet.alpha_composite(small, (cx + round(cell * 0.5 - ax * s), cy + round(cell * foot) - th))
        cells[it["name"]] = {"i": i, "fill": round(th / cell, 4), "mounted": bool(it.get("mounted", False))}
        print(f"{i:2d} {it['name']} {it['variant']}_{it['seed']} 키 {th / cell:.3f} 폭 {tw / cell:.3f}")
    sheet.save(SHEET, optimize=True)
    data = {"_설명": "신화 장수 인형 시트 칸 표 (tools/scripts/make_myth_heroes.py 가 만든다 —— 손으로 고치지 말 것). "
                     "i = 칸 번호 (왼쪽 위부터 가로로), fill = 인형 키 / 칸 키 (발은 칸의 foot), war_painting._collect_hero 가 읽는다",
            "sheet": "res://assets/war_painting/myth_heroes_v1.png", "grid": [gc, gr], "cell": cell, "foot": foot, "cells": cells}
    with open(DATA, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(SHEET, sheet.size, DATA)


if __name__ == "__main__":
    main()
