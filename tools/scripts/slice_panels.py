"""배경까지 그려진 패널 시트(신화·불멸 등 큰 그림)를 패널째 잘라 PNG 로 저장한다.

slice_sheet.py 는 인물만 오려 내는데, 패널 안이 배경 그림으로 꽉 찬 시트는 패널 속 초록(촉 옷·숲)까지
바탕으로 먹어 버린다. 여기서는 패널 사각형을 통째로 떼고, 패널 바깥 테두리의 연두 바탕만 투명하게 한다.

방법
  1. 연두 바탕(시트 네 귀 색)과 다른 화소를 '그림'으로 본다.
  2. 줄마다 그림 화소 수를 세어 긴 덩어리(패널)와 짧은 덩어리(이름표)를 가른다. 패널 줄 띠마다 열도 같은 식으로 가른다.
  3. 패널 사각형을 잘라, 가장자리에서 시작해 바탕색과 닿아 있는 화소만 넘쳐 채워 투명하게 한다 (패널 속 초록은 남는다).

실행: python -I slice_panels.py 시트.png "이름,이름,..." 출력폴더 [미리보기.png] [--rim N] [--bottom F]
이름은 읽는 순서(위 줄부터, 왼쪽부터).

옵션 (11/10 —— v2 시트 자르기 고침. 없으면 예전 동작 그대로)
  --rim N     바탕으로 지우는 범위를 패널 가장자리 N픽셀 안쪽으로 한정한다 (권장 12). 연한 하늘 · 안개가 시트의 연두 바탕과 닮으면
              넘쳐 채우기가 가장자리에서 그림 속까지 파 먹어 투명 구멍이 났다 (초월 시트).
  --bottom F  패널 높이의 F 비율(0~1)을 아래에서 잘라 낸다. 시트의 번호 이름표(붓질 도장)가 패널 아래쪽 그림을 덮는 시트용
              (기인 · 초월은 약 0.12, 불멸은 약 0.10). 이름표가 패널 밖에 있는 시트(초월 04 · 불멸 03 · 08 · 신화)에는 쓰지 않는다.
"""
import sys

import numpy as np
from PIL import Image


def runs(v: np.ndarray, min_len: int):
    """참인 구간 [시작, 끝) 목록 —— 짧은 틈(8px 이하)은 잇고, min_len 보다 짧은 구간은 버린다."""
    out = []
    i, n = 0, len(v)
    while i < n:
        if not v[i]:
            i += 1
            continue
        j = i
        while j < n and (v[j] or (j + 8 < n and v[j:j + 9].any())):
            j += 1
        if j - i >= min_len:
            out.append((i, j))
        i = j
    return out


def opt(name):
    """--name 값 (없으면 None)"""
    if name not in sys.argv:
        return None
    return float(sys.argv[sys.argv.index(name) + 1])


def main():
    args = [a for i, a in enumerate(sys.argv[1:], 1) if not a.startswith("--") and not (i > 1 and sys.argv[i - 1] in ("--rim", "--bottom"))]
    src, names, out = args[0], args[1].split(","), args[2]
    preview = args[3] if len(args) > 3 else None
    rim_n, bottom_f = opt("--rim"), opt("--bottom")
    rgb = np.asarray(Image.open(src).convert("RGB")).astype(int)
    h, w, _ = rgb.shape
    corners = np.array([rgb[4, 4], rgb[4, w - 5], rgb[h - 5, 4], rgb[h - 5, w - 5]])
    bgc = np.median(corners, axis=0)
    diff = np.abs(rgb - bgc).sum(axis=2)
    art = diff > 60
    # 이름표(짙은 초록 붓질)는 패널이 아니다
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    plate = (g < 110) & (g > r + 5) & (g > b + 5)
    art &= ~plate | (diff > 200)

    panels = []
    row_cnt = art.sum(axis=1)
    bg_cnt = (diff <= 60).sum(axis=1)
    # 패널 줄은 바탕이 양옆·사이 여백뿐(너비의 12% 안팎)이다. 이름표 줄은 이름표가 아주 넓어도 바탕이 20% 넘게 보인다
    empty = bg_cnt > w * 0.97          # 거의 바탕뿐인 줄 —— 패널과 이름표 사이 틈
    for y0, y1 in runs(bg_cnt < w * 0.18, h // 6):
        # 패널 위로 솟은 창끝·깃, 들쭉날쭉한 가장자리까지 —— 빈 줄을 만날 때까지 넓힌다
        while y0 > 0 and not empty[y0 - 1]:
            y0 -= 1
        while y1 < h and not empty[y1] and plate[y1].sum() < w * 0.1:
            y1 += 1
        col_cnt = art[y0:y1].sum(axis=0)
        for x0, x1 in runs(col_cnt > (y1 - y0) * 0.5, w // 6):
            panels.append((y0, y1, x0, x1))
    if len(panels) != len(names):
        for p in panels:
            print("  패널", p)
        sys.exit(f"패널 {len(panels)}개 / 이름 {len(names)}개 —— 시트를 확인한다")

    tiles = []
    for nm, (y0, y1, x0, x1) in zip(names, panels):
        pad = 6
        y0, x0 = max(0, y0 - pad), max(0, x0 - pad)
        y1, x1 = min(h, y1 + pad), min(w, x1 + pad)
        crop = rgb[y0:y1, x0:x1]
        d = np.abs(crop - bgc).sum(axis=2)
        cand = (d < 90) | ((crop[..., 1] > crop[..., 0] + 15) & (crop[..., 1] > crop[..., 2] + 30) & (crop[..., 1] > 170))   # 바탕 + 패널 둘레 연두 번짐
        if rim_n:      # 가장자리 띠 안쪽만 바탕 후보 —— 그림 속 연한 하늘이 번지지 않게
            n = int(rim_n)
            rim = np.zeros_like(cand)
            rim[:n, :], rim[-n:, :], rim[:, :n], rim[:, -n:] = True, True, True, True
            cand &= rim
        # 가장자리에서 넘쳐 채운다 —— 패널 바깥 바탕만 투명
        bg = np.zeros_like(cand)
        bg[0, :], bg[-1, :], bg[:, 0], bg[:, -1] = cand[0, :], cand[-1, :], cand[:, 0], cand[:, -1]
        while True:
            grow = bg.copy()
            grow[1:, :] |= bg[:-1, :]
            grow[:-1, :] |= bg[1:, :]
            grow[:, 1:] |= bg[:, :-1]
            grow[:, :-1] |= bg[:, 1:]
            grow &= cand
            if (grow == bg).all():
                break
            bg = grow
        rgba = np.zeros(crop.shape[:2] + (4,), dtype=np.uint8)
        rgba[..., :3] = crop
        rgba[..., 3] = np.where(bg, 0, 255)
        # 맨 아래에 묻어 온 이름표 윗부분(짙은 초록) 지우기
        pl = plate[y0:y1, x0:x1]
        for yy in range(rgba.shape[0] - 1, max(0, rgba.shape[0] - 16), -1):
            if pl[yy].mean() > 0.05 or rgba[yy, :, 3].mean() < 60:
                rgba[yy, :, 3] = 0
            else:
                break
        ys = np.nonzero(rgba[..., 3].max(axis=1))[0]
        rgba = rgba[: ys.max() + 1]
        if bottom_f:      # 번호 도장이 그림 아래를 덮은 만큼 자른다
            rgba = rgba[: int(rgba.shape[0] * (1.0 - bottom_f))]
        im = Image.fromarray(rgba, "RGBA")
        im.save(f"{out}/{nm}.png")
        tiles.append((nm, im))
        print(f"{nm}: {x1 - x0}x{y1 - y0}")
    if preview:
        t = 260
        sheet = Image.new("RGB", (len(tiles) * t, t), (40, 44, 60))
        for i, (nm, im) in enumerate(tiles):
            c = im.copy()
            c.thumbnail((t - 10, t - 10))
            sheet.paste(c, (i * t + 5, 5), c)
        sheet.save(preview)


main()
