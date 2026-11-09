"""장수 일러스트 시트를 한 명씩 잘라 투명 배경 PNG 로 저장한다.

방법
  1. 바깥 테두리에서 시작해 '연두 배경'(밝은 바탕 + 캐릭터 뒤 짙은 얼룩)을 넘쳐 채운다.
     캐릭터의 검은 외곽선이 벽 역할을 하므로 초록 옷은 배경으로 잡히지 않는다.
  2. 남은 덩어리를 연결 성분으로 나눈다. 짙은 초록 이름표는 따로 골라내 위치만 쓴다.
  3. 각 덩어리를 가장 가까운 이름표의 캐릭터에게 준다 → 이웃 캐릭터의 창·망토가 섞이지 않는다.
  4. 캐릭터마다 정사각 캔버스에 여백을 넉넉히 두고 바닥 쪽에 맞춰 놓는다.

실행: python -I slice_sheet.py 시트.png "주창,요화,..." 출력폴더 [미리보기.png] [--hole=168]
이름은 시트의 읽는 순서(위 줄부터, 왼쪽부터)로 준다.
--max=N: 잘린 정사각 그림의 한 변이 N 을 넘으면 N 으로 줄인다 (휴대폰 용량 —— 병졸 · 토벌 적은 512 권장, 11/9). 기본은 줄이지 않는다.
--hole: 사방이 막힌 초록(무기와 몸 사이 등)을 바탕으로 칠 밝기(g 평균). 기본 168 —— 촉 시트의 초록 옷(g≤161)을 지키는 값.
        초록 옷이 없는 시트(위·오)는 155 로 낮추면 다리·창 사이에 갇힌 얼룩까지 지운다.
"""
import os
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
    opts = [a for a in sys.argv[1:] if a.startswith("--")]
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    hole_g = 168
    plate_g = 105      # 이름표 판 초록의 밝기 상한 (11/7 1_기본_추가 04~13 시트는 판이 밝아 g≈123 —— --plate=140)
    for o in opts:
        if o.startswith("--hole="):
            hole_g = int(o.split("=", 1)[1])
        if o.startswith("--plate="):
            plate_g = int(o.split("=", 1)[1])
    max_side = 0
    for o in opts:
        if o.startswith("--max="):
            max_side = int(o.split("=", 1)[1])
    big = 2.2 if "--big" in opts else 1.0      # 11/7 인물이 적어 크게 그린 시트(13_새인물_2명) —— 이름표도 크다
    src, names, out = args[0], args[1].split(","), args[2]
    os.makedirs(out, exist_ok=True)
    preview = args[3] if len(args) > 3 else None
    im = Image.open(src).convert("RGB")
    rgb = np.asarray(im)
    bg = flood_background(rgb)
    # 갇힌 바탕 —— 활과 시위 사이처럼 사방이 막힌 곳. 바탕 얼룩처럼 밝은 초록(g≥168)이 넓게 고이면 바탕으로 친다.
    # 초록 옷은 이보다 어둡다(g≤161 로 측정).
    r, g, b = (rgb[..., i].astype(int) for i in range(3))
    cand = (g > r + 12) & (g > b + 25) & (g > 110) & ~bg
    hlab, holes = components(cand)
    for c in holes:
        if c["n"] >= 60 and rgb[hlab == c["id"]][:, 1].mean() >= hole_g:     # 60px —— 투석기 틀 안처럼 작은 구멍도
            bg |= hlab == c["id"]
    fg = ~bg
    # 이름표 —— 짙은 초록 판 + 안쪽 흰 글씨. 발끝과 붙어 있을 수 있어 색으로 따로 찾는다
    r, g, bb = (rgb[..., i].astype(int) for i in range(3))
    plate = (g < plate_g) & (g > r + 5) & (g > bb + 5) & (r > 25)
    plab, pcomps = components(plate)
    # 이름표 조각 —— 짙은 초록 판 안에 흰 글씨. 글자가 판을 가로질러 하나가 두 조각으로 갈라지는 일이 있어
    # 먼저 느슨하게 조각을 모아 같은 높이에서 겹치거나 맞붙은 것을 합친 뒤, 합친 판의 크기로 이름표를 가린다.
    pieces = []
    for c in pcomps:
        hh, ww = c["y1"] - c["y0"] + 1, c["x1"] - c["x0"] + 1
        if 16 <= hh <= 90 * big and 30 <= ww <= 320 * big:
            region = rgb[c["y0"]:c["y1"] + 1, c["x0"]:c["x1"] + 1].reshape(-1, 3).astype(int)
            text = (region.min(axis=1) > 190).mean()
            if 0.01 < text < 0.4:      # 번호만 쓴 이름표(대용량 시트)는 흰 글씨가 적다
                pieces.append(c)
    pieces.sort(key=lambda c: c["x0"])
    merged = []
    for c in pieces:
        m = next((o for o in merged if min(o["y1"], c["y1"]) - max(o["y0"], c["y0"]) > 0.5 * min(o["y1"] - o["y0"], c["y1"] - c["y0"])
                  and c["x0"] <= o["x1"] + 15), None)
        if m is None:
            merged.append(dict(c))
        else:
            for k, f in (("y0", min), ("x0", min), ("y1", max), ("x1", max)):
                m[k] = f(m[k], c[k])
            m["cy"] = (m["y0"] + m["y1"]) / 2
            m["cx"] = (m["x0"] + m["x1"]) / 2
            m["n"] += c["n"]
    # 촉 시트는 높이 16~45 · 너비 50~160, Gemini 1024px 시트는 50×150 안팎 —— 시트마다 조금씩 달라 넉넉히 잡는다
    labels = [m for m in merged if 50 <= m["x1"] - m["x0"] + 1 <= 320 * big and m["x1"] - m["x0"] + 1 > (m["y1"] - m["y0"] + 1) * 2]
    # 옷의 짙은 초록 조각이 이름표처럼 잡히는 일이 있다 —— 이름표 너비 중앙값의 절반이 안 되면 버린다
    if labels:
        mw = float(np.median([m["x1"] - m["x0"] + 1 for m in labels]))
        labels = [m for m in labels if m["x1"] - m["x0"] + 1 >= mw * 0.5]
    if len(labels) != len(names):
        for c in labels: print("  이름표", int(c["x0"]), int(c["y0"]), int(c["x1"] - c["x0"] + 1), "x", int(c["y1"] - c["y0"] + 1))
        sys.exit(f"이름표 {len(labels)}개 / 이름 {len(names)}개 — 인물 수가 다르다. 시트를 다시 만들거나 이름 목록을 확인한다")
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
    # 11/7 이웃끼리 맞붙은 덩어리(기병 말 · 창이 옆 인물에 닿음) —— 같은 줄 두 이름표 사이 경계선 양쪽에 3000px 넘게 걸치면 경계선에서 나눈다
    next_id = lab.max() + 1
    split_any = False
    for row in rows:
        row_s = sorted(row, key=lambda c: c["cx"])
        top = max(0, int(min(c["y0"] for c in row_s)) - 700)
        bot = int(max(c["y1"] for c in row_s))
        for a, b in zip(row_s, row_s[1:]):
            mid = int((a["x1"] + b["x0"]) / 2)
            band = lab[top:bot + 1]
            for cid in np.unique(band[:, max(0, mid - 1):mid + 1]):
                if cid == 0:
                    continue
                m = band == cid
                left = m[:, :mid].sum()
                right = m[:, mid:].sum()
                if left > 3000 and right > 3000:
                    sub = band[:, mid:]
                    sub[sub == cid] = next_id
                    next_id += 1
                    split_any = True
    if split_any:
        lab_new = lab
        comps = []
        for cid in np.unique(lab_new):
            if cid == 0:
                continue
            ys, xs = np.nonzero(lab_new == cid)
            comps.append({"id": int(cid), "n": len(ys), "y0": ys.min(), "y1": ys.max(), "x0": xs.min(), "x1": xs.max(), "cy": ys.mean(), "cx": xs.mean()})
    anchors = np.array([(c["y0"] - 85.0, c["cx"]) for c in ordered])   # 캐릭터 몸통 쯤
    label_ids = set()
    owner = np.zeros(int(lab.max()) + 2, dtype=np.int32) - 1
    for c in comps:
        if c["id"] in label_ids or c["n"] < 25:
            continue
        # 이름표 붓질 조각 —— 짙은 초록이 절반을 넘는 덩어리는 버린다
        if c["n"] < 3000 and plate[lab == c["id"]].mean() > 0.5:
            continue
        # 덩어리 아래쪽에 이름표가 있는 캐릭터를 우선 —— 몸통 중심과 이름표 위 지점 사이 거리
        d = np.hypot(anchors[:, 0] - c["cy"], (anchors[:, 1] - c["cx"]) * 1.0)
        owner[c["id"]] = int(np.argmin(d))
    alpha_all = np.zeros(lab.shape, dtype=np.uint8)
    tiles = []
    for i, nm in enumerate(names):
        ids = np.nonzero(owner == i)[0]
        # 본체(가장 큰 덩어리)에서 40px 넘게 떨어진 작은 조각은 버린다 —— 패널 밖 먼지가 캔버스를 키우지 않게
        cs = {c["id"]: c for c in comps}
        if len(ids) == 0:      # 11/7 덩어리를 하나도 못 받은 인물 —— 멈추지 않고 알린다
            print(f"{nm}: 덩어리 없음 - 건너뜀")
            continue
        main_c = max((cs[k] for k in ids), key=lambda c: c["n"])
        ids = [k for k in ids if cs[k]["n"] >= 3000 or (cs[k]["y0"] <= main_c["y1"] + 40 and cs[k]["y1"] >= main_c["y0"] - 40
                                                      and cs[k]["x0"] <= main_c["x1"] + 40 and cs[k]["x1"] >= main_c["x0"] - 40)]
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
        if max_side and side > max_side:
            canvas = canvas.resize((max_side, max_side), Image.LANCZOS)
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
