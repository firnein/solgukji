"""얼굴 썸네일 시트(원형 메달 · 연두 바탕)를 한 명씩 잘라 둥근 투명 PNG 로 저장한다 (11/3).

실행: python -I tools/scripts/slice_faces.py 시트.png "마량,요화,..." 출력폴더 [미리보기.png]
  이름은 시트의 읽는 순서(위 줄부터, 왼쪽부터). 메달 수와 이름 수가 다르면 멈춘다.
방법: 연두 바탕 · 짙은 초록 이름표가 아닌 픽셀(메달)을 가로 · 세로로 투영해 줄과 칸을 찾고,
      칸마다 테두리 상자의 중심 · 짧은 변으로 원을 잡아 원 밖을 투명하게 (가장자리 2px 부드럽게). SIZE 정사각으로 줄인다.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

SIZE = 384


def runs(v, thr, min_len):
    out, s = [], None
    for i, x in enumerate(list(v) + [0]):
        if x > thr and s is None:
            s = i
        elif x <= thr and s is not None:
            if i - s >= min_len:
                out.append((s, i))
            s = None
    return out


def main():
    src, names, out = sys.argv[1], sys.argv[2].split(","), sys.argv[3]
    prev = sys.argv[4] if len(sys.argv) > 4 else None
    im = Image.open(src).convert("RGB")
    a = np.asarray(im).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    green = (g > r + 12) & (g > b + 12)              # 연두 바탕 + 짙은 초록 이름표
    mask = ~green
    h, w = mask.shape
    rows = runs(mask.sum(axis=1), w * 0.04, h * 0.12)
    boxes = []
    for y0, y1 in rows:
        cols = runs(mask[y0:y1].sum(axis=0), (y1 - y0) * 0.15, w * 0.08)
        for x0, x1 in cols:
            sub = mask[y0:y1, x0:x1]
            ys = np.where(sub.sum(axis=1) > (x1 - x0) * 0.05)[0]
            boxes.append((x0, y0 + ys.min(), x1, y0 + ys.max() + 1))
    if len(boxes) != len(names):
        for bx in boxes:
            print("  메달", bx)
        sys.exit("메달 %d개 / 이름 %d개 —— 시트를 확인한다" % (len(boxes), len(names)))
    os.makedirs(out, exist_ok=True)
    tiles = []
    for nm, (x0, y0, x1, y1) in zip(names, boxes):
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        rad = min(x1 - x0, y1 - y0) / 2 - 1
        crop = im.crop((round(cx - rad), round(cy - rad), round(cx + rad), round(cy + rad))).resize((SIZE, SIZE), Image.LANCZOS)
        big = Image.new("L", (SIZE * 4, SIZE * 4), 0)
        ImageDraw.Draw(big).ellipse((4, 4, SIZE * 4 - 5, SIZE * 4 - 5), fill=255)
        alpha = big.resize((SIZE, SIZE), Image.LANCZOS)
        crop.putalpha(alpha)
        crop.save(os.path.join(out, nm + ".png"))
        tiles.append(crop)
        print("%s: %dx%d" % (nm, x1 - x0, y1 - y0), end=" | ")
    print()
    if prev:
        t = 160
        sheet = Image.new("RGBA", (t * len(tiles) + 8 * (len(tiles) + 1), t + 16), (40, 46, 70, 255))
        for i, c in enumerate(tiles):
            sheet.alpha_composite(c.resize((t, t), Image.LANCZOS), (8 + i * (t + 8), 8))
        os.makedirs(os.path.dirname(prev) or ".", exist_ok=True)
        sheet.save(prev)


main()
