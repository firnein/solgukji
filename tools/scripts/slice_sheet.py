"""장수 일러스트 시트를 한 명씩 잘라 투명 배경 PNG 로 저장한다.

방법
  1. 바깥 테두리에서 시작해 '연두 배경'(밝은 바탕 + 캐릭터 뒤 짙은 얼룩)을 넘쳐 채운다.
     캐릭터의 검은 외곽선이 벽 역할을 하므로 초록 옷은 배경으로 잡히지 않는다.
  2. 남은 덩어리를 연결 성분으로 나눈다. 짙은 초록 이름표는 따로 골라내 위치만 쓴다.
  3. 각 덩어리를 가장 가까운 이름표의 캐릭터에게 준다 → 이웃 캐릭터의 창·망토가 섞이지 않는다.
  4. 캐릭터마다 정사각 캔버스에 여백을 넉넉히 두고 바닥 쪽에 맞춰 놓는다.

실행: python -I slice_sheet.py 시트.png "주창,요화,..." 출력폴더 [미리보기.png]
이름은 시트의 읽는 순서(위 줄부터, 왼쪽부터)로 준다.
"""
import sys
from collections import deque

import numpy as np
from PIL import Image


def flood_background(rgb: np.ndarray) -> np.ndarray:
    r, g, b = (rgb[..., i].astype(int) for i in range(3))
    cand = (g > r + 12) & (g > b + 25) & (g > 110)          # 연두 바탕 + 짙은 얼룩
    h, w = cand.shape
    bg = np.zeros_like(cand)
    bg[0, :] = cand[0, :]
    bg[-1, :] = cand[-1, :]
    bg[:, 0] |= cand[:, 0]
    bg[:, -1] |= cand[:, -1]
    while True:
        grow = bg.copy()
        grow[1:, :] |= bg[:-1, :]
        grow[:-1, :] |= bg[1:, :]
        grow[:, 1:] |= bg[:, :-1]
        grow[:, :-1] |= bg[:, 1:]
        grow &= cand
        if (grow == bg).all():
            return bg
        bg = grow


def components(mask: np.ndarray):
    h, w = mask.shape
    lab = np.zeros((h, w), dtype=np.int32)
    comps = []
    n = 0
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if lab[y0, x0]:
            continue
        n += 1
        q = deque([(y0, x0)])
        lab[y0, x0] = n
        pix = []
        while q:
            y, x = q.popleft()
            pix.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not lab[yy, xx]:
                    lab[yy, xx] = n
                    q.append((yy, xx))
        p = np.array(pix)
        comps.append({"id": n, "n": len(p), "y0": p[:, 0].min(), "y1": p[:, 0].max(),
                      "x0": p[:, 1].min(), "x1": p[:, 1].max(), "cy": p[:, 0].mean(), "cx": p[:, 1].mean()})
    return lab, comps


def main():
    src, names, out = sys.argv[1], sys.argv[2].split(","), sys.argv[3]
    preview = sys.argv[4] if len(sys.argv) > 4 else None
    im = Image.open(src).convert("RGB")
    rgb = np.asarray(im)
    bg = flood_background(rgb)
    # 갇힌 바탕 —— 활과 시위 사이처럼 사방이 막힌 곳. 바탕 얼룩처럼 밝은 초록(g≥168)이 넓게 고이면 바탕으로 친다.
    # 초록 옷은 이보다 어둡다(g≤161 로 측정).
    r, g, b = (rgb[..., i].astype(int) for i in range(3))
    cand = (g > r + 12) & (g > b + 25) & (g > 110) & ~bg
    hlab, holes = components(cand)
    for c in holes:
        if c["n"] >= 150 and rgb[hlab == c["id"]][:, 1].mean() >= 168:
            bg |= hlab == c["id"]
    fg = ~bg
    # 이름표 —— 짙은 초록 판 + 안쪽 흰 글씨. 발끝과 붙어 있을 수 있어 색으로 따로 찾는다
    r, g, bb = (rgb[..., i].astype(int) for i in range(3))
    plate = (g < 105) & (g > r + 5) & (g > bb + 5) & (r > 25)
    plab, pcomps = components(plate)
    labels = []
    for c in pcomps:
        hh, ww = c["y1"] - c["y0"] + 1, c["x1"] - c["x0"] + 1
        if 16 <= hh <= 45 and 50 <= ww <= 160 and ww > hh * 2:
            region = rgb[c["y0"]:c["y1"] + 1, c["x0"]:c["x1"] + 1].reshape(-1, 3).astype(int)
            text = (region.min(axis=1) > 190).mean()
            if 0.03 < text < 0.4:
                labels.append(c)
    # 이름표 자리는 캐릭터에서 뺀다
    for c in labels:
        fg[c["y0"]:c["y1"] + 1, max(0, c["x0"] - 2):c["x1"] + 3] = False
    lab, comps = components(fg)
    # 읽는 순서 —— 줄(세로 60px 안쪽)끼리 묶고 왼쪽부터
    labels.sort(key=lambda c: c["cy"])
    rows, cur = [], [labels[0]]
    for c in labels[1:]:
        if abs(c["cy"] - cur[-1]["cy"]) < 60:
            cur.append(c)
        else:
            rows.append(cur)
            cur = [c]
    rows.append(cur)
    ordered = [c for row in rows for c in sorted(row, key=lambda c: c["cx"])]
    anchors = np.array([(c["y0"] - 85.0, c["cx"]) for c in ordered])   # 캐릭터 몸통 쯤
    label_ids = set()
    owner = np.zeros(len(comps) + 1, dtype=np.int32) - 1
    for c in comps:
        if c["id"] in label_ids or c["n"] < 25:
            continue
        # 덩어리 아래쪽에 이름표가 있는 캐릭터를 우선 —— 몸통 중심과 이름표 위 지점 사이 거리
        d = np.hypot(anchors[:, 0] - c["cy"], (anchors[:, 1] - c["cx"]) * 1.0)
        owner[c["id"]] = int(np.argmin(d))
    alpha_all = np.zeros(lab.shape, dtype=np.uint8)
    tiles = []
    for i, nm in enumerate(names):
        ids = np.nonzero(owner == i)[0]
        mask = np.isin(lab, ids)
        # 외곽선 바깥 1px 까지 포함해 가장자리가 깎이지 않게
        m2 = mask.copy()
        m2[1:, :] |= mask[:-1, :]
        m2[:-1, :] |= mask[1:, :]
        m2[:, 1:] |= mask[:, :-1]
        m2[:, :-1] |= mask[:, 1:]
        ys, xs = np.nonzero(m2)
        y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
        rgba = np.zeros((y1 - y0 + 1, x1 - x0 + 1, 4), dtype=np.uint8)
        rgba[..., :3] = rgb[y0:y1 + 1, x0:x1 + 1]
        rgba[..., 3] = np.where(m2[y0:y1 + 1, x0:x1 + 1], 255, 0)
        fig = Image.fromarray(rgba, "RGBA")
        # 정사각 캔버스 —— 여백 12%, 바닥 쪽에 붙인다
        side = int(max(fig.width, fig.height) * 1.24)
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(fig, ((side - fig.width) // 2, side - fig.height - int(side * 0.04)), fig)
        canvas.save(f"{out}/{nm}.png")
        tiles.append((nm, canvas))
        print(f"{nm}: 덩어리 {len(ids)}개 · {fig.width}x{fig.height} → {side}x{side}")
    if preview:
        t = 220
        cols = 5
        sheet = Image.new("RGB", (cols * t, ((len(tiles) + cols - 1) // cols) * (t + 22)), (40, 44, 60))
        from PIL import ImageDraw
        dr = ImageDraw.Draw(sheet)
        for i, (nm, cv) in enumerate(tiles):
            x, y = (i % cols) * t, (i // cols) * (t + 22)
            bgc = Image.new("RGBA", (t, t), (230, 225, 210, 255))
            cv2 = cv.resize((t, t))
            bgc.alpha_composite(cv2)
            sheet.paste(bgc.convert("RGB"), (x, y))
            dr.text((x + 6, y + t + 4), str(i + 1), fill=(255, 255, 255))
        sheet.save(preview)


main()
