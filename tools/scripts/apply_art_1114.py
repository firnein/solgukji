"""prompts/생성결과_2026-11-14 의 새 일러스트를 게임 초상으로 잘라 넣는다 (11/14).

실행 (저장소 루트에서):
  python -I -X utf8 tools/scripts/apply_art_1114.py <생성결과 폴더> <작업 폴더> [--apply] [--only base,kiin,trans,immortal,myth,faces]
    작업 폴더 아래 out/portraits · out/faces 에 결과를 만들고, --apply 면 solgukji_godot/assets 로 복사한다.

무엇을 어디서 가져오나 (뒤가 앞을 덮는다)
  기본   01_기본 18장 → 02_기본_재작업 4장 → 03_기본_추가 13장      slice_sheet.py (인물만 오려 투명 정사각, 한 변 최대 720)
  기인   04_기인 01~04 → 재작업_A · B                               slice_panels.py --rim 12 (01~04 는 --bottom 0.12), 최대 640
  초월   05_초월 01 (관평 · 방덕 · 주태 · 문추) 만                    나머지 11명은 08_초월_개별수정 이 이미 게임에 들어가 있다. 최대 600
  불멸   06_불멸 31장 (한 장에 한 명 1024x1536)                      규격(docs/일러스트_규격.md) 카드 400x520 —— 위에 붙여 덮어 자름
  신화   07_신화/최종_회화풍_얼굴 8장 (1024x1536)                    규격 컷인 512x768
         10_개별 의 유비 · 장비 · 조운 (사용자 그림 1254 정사각)       얼굴을 가운데 두고 2:3 으로 잘라 512x768. 관우는 07 최종본을 쓴다
  얼굴   새 기본 초상에서 머리를 찾아 둥근 메달 256x256                 assets/faces/<인물>.png (살색 덩어리 + 수동 보정표 FACE_FIX)
이름 순서는 prompts/등급별/…/자르기_이름.txt (시트 프롬프트와 같은 순서) 에서 읽는다.
"""
import os
import re
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
SRC, WORK = sys.argv[1], sys.argv[2]
APPLY = "--apply" in sys.argv
ONLY = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else ["base", "kiin", "trans", "immortal", "myth", "faces"]
OUT_P = os.path.join(WORK, "out", "portraits")
OUT_F = os.path.join(WORK, "out", "faces")
TMP = os.path.join(WORK, "tmp")
for d in (OUT_P, OUT_F, TMP):
    os.makedirs(d, exist_ok=True)
PY = [sys.executable, "-I", "-X", "utf8"]


def plan(path):
    t = open(path, encoding="utf-8").read()
    return re.findall(r'^\[(\S+)\.txt\].*?\n(?:  참조:.*\n)?  자르기: .*? "([^"]+)"', t, flags=re.M)


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    msg = (r.stdout + r.stderr).strip().replace("\n", " | ")
    if r.returncode != 0 or "건너뜀" in msg:
        print("  !!", msg[-600:])
    return r.returncode == 0


def shrink(path, mx):
    im = Image.open(path)
    k = mx / max(im.size)
    if k < 1.0:
        im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
    im.save(path, optimize=True)


def cover(im, tw, th, fx=0.5):
    """목표 비율로 덮어 자른다 —— 가로는 fx(얼굴 자리)를 가운데에, 세로는 위에 붙임."""
    w, h = im.size
    if w / h > tw / th:
        cw = round(h * tw / th)
        x = min(max(round(fx * w - cw / 2), 0), w - cw)
        box = (x, 0, x + cw, h)
    else:
        box = (0, 0, w, round(w * th / tw))
    return im.crop(box).resize((tw, th), Image.LANCZOS)


def do_base():
    n = {}
    for src, dst in (("등급별/1_기본", "01_기본"), ("등급별/1_기본_재작업", "02_기본_재작업"), ("등급별/1_기본_추가", "03_기본_추가")):
        for sheet, names in plan("prompts/%s/자르기_이름.txt" % src):
            d = os.path.join(TMP, "base", dst[:2] + "_" + sheet[:2])
            extra = ["--big"] if ("2명" in sheet or "재작업" in sheet) else []      # 인물이 적어 크게 그린 시트는 번호표도 크다
            ok = run(PY + ["tools/scripts/slice_sheet.py", os.path.join(SRC, dst, sheet + ".png"), names, d] + extra)
            for nm in names.split(","):
                f = os.path.join(d, nm + ".png")
                if ok and os.path.exists(f):
                    shrink(f, 720)
                    shutil.copy2(f, os.path.join(OUT_P, nm + ".png"))
                    n[nm] = dst[:2] + "/" + sheet[:2]
                else:
                    print("  없음:", dst, sheet, nm)
    print("기본 %d명" % len(n))
    return n


def do_panels(jobs, mx):
    names_all = []
    for tag, sheet, names, extra in jobs:
        d = os.path.join(TMP, "tier", tag)
        os.makedirs(d, exist_ok=True)
        ok = run(PY + ["tools/scripts/slice_panels.py", os.path.join(SRC, sheet), names, d, os.path.join(d, "_미리보기.png"), "--rim", "12"] + extra)
        for nm in names.split(","):
            f = os.path.join(d, nm + ".png")
            if ok and os.path.exists(f):
                shrink(f, mx)
                shutil.copy2(f, os.path.join(OUT_P, nm + ".png"))
                names_all.append(nm)
    return sorted(set(names_all))


def do_kiin():
    jobs = [(s, "04_기인/%s.png" % s, n, ["--bottom", "0.12"]) for s, n in plan("prompts/등급별_v2/1_기인/자르기_이름.txt") if s[:2].isdigit()]
    jobs += [("재작업_A", "04_기인/재작업_A_고순_공손찬_곽가.png", "고순_기인,공손찬_기인,곽가_기인", []),
             ("재작업_B", "04_기인/재작업_B_손상향_장합_마등.png", "손상향_기인,장합_기인,마등_기인", [])]
    print("기인 %d장" % len(do_panels(jobs, 640)))


def do_trans():
    print("초월 %d장" % len(do_panels([("초월01", "05_초월/01_촉_위_오_군_4명.png", "관평_초월,방덕_초월,주태_초월,문추_초월", ["--bottom", "0.12"])], 600)))


def do_immortal():
    d = os.path.join(SRC, "06_불멸")
    n = 0
    for f in sorted(os.listdir(d)):
        m = re.match(r"\d+_(\S+)\.png$", f)
        if m:
            cover(Image.open(os.path.join(d, f)).convert("RGB"), 400, 520).save(os.path.join(OUT_P, m.group(1) + "_불멸.png"), optimize=True)
            n += 1
    print("불멸 %d장" % n)


MYTH_USER = {"유비": ("유비_신화.png", 0.50), "장비": ("장비_신화.png", 0.52), "조운": ("조운의 용맹한 백마 전투 초상-4.png", 0.40)}   # 10_개별 —— (파일, 얼굴 가로 자리)


def do_myth():
    d = os.path.join(SRC, "07_신화", "최종_회화풍_얼굴")
    n = 0
    for f in sorted(os.listdir(d)):
        m = re.match(r"\d+_(\S+)\.png$", f)
        if m:
            cover(Image.open(os.path.join(d, f)).convert("RGB"), 512, 768).save(os.path.join(OUT_P, m.group(1) + "_신화.png"), optimize=True)
            n += 1
    for nm, (f, fx) in MYTH_USER.items():
        cover(Image.open(os.path.join(SRC, "10_개별", f)).convert("RGB"), 512, 768, fx).save(os.path.join(OUT_P, nm + "_신화.png"), optimize=True)
        n += 1
    print("신화 %d장" % n)


# ── 얼굴 메달 ────────────────────────────────────────────────────────────────
FACE = 256
PAPER = (236, 224, 196)
# 자동으로 못 찾은 얼굴 —— 이름: (가로 중심, 세로 중심, 한 변) 을 그려진 영역(bbox) 높이에 대한 비율로. 가로는 bbox 너비 비율
FACE_FIX = {"관우": (0.62, 0.33, 0.36), "서서": (0.42, 0.33, 0.36), "여포": (0.56, 0.33, 0.26), "왕쌍": (0.70, 0.36, 0.36), "장량": (0.56, 0.40, 0.32),
            "제갈근": (0.43, 0.25, 0.34), "조인": (0.50, 0.31, 0.38), "주창": (0.60, 0.37, 0.34), "화웅": (0.55, 0.26, 0.34), "황권": (0.52, 0.27, 0.34),
            "초주": (0.61, 0.31, 0.34), "여상": (0.45, 0.28, 0.38), "안량": (0.47, 0.28, 0.32), "장보": (0.54, 0.38, 0.36), "장각": (0.56, 0.36, 0.34),
            "오범": (0.40, 0.24, 0.34), "순유": (0.46, 0.27, 0.36), "진무": (0.38, 0.29, 0.36)}


def find_head(im):
    a = np.asarray(im)
    al = a[..., 3] > 128
    ys, xs = np.nonzero(al)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    h, w = y1 - y0 + 1, x1 - x0 + 1
    r, g, b = (a[..., i].astype(int) for i in range(3))
    skin = al & (r > 170) & (g > 105) & (g < 225) & (b > 70) & (b < 190) & (r - b > 35) & (r - g > 22) & (r - g < 95)
    # 살색을 조금 뭉쳐(작은 틈 메움) 가장 큰 덩어리 = 얼굴. 위쪽 60% 안에서만 찾는다 (손 · 배는 아래쪽)
    sk = Image.fromarray((skin * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    sk = np.asarray(sk) > 128
    sk[int(y0 + h * 0.62):] = False
    from collections import deque
    lab = np.zeros(sk.shape, dtype=np.int32)
    best = None
    n = 0
    for sy, sx in zip(*np.nonzero(sk)):
        if lab[sy, sx]:
            continue
        n += 1
        q = deque([(sy, sx)])
        lab[sy, sx] = n
        pts = []
        while q:
            y, x = q.popleft()
            pts.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < sk.shape[0] and 0 <= xx < sk.shape[1] and sk[yy, xx] and not lab[yy, xx]:
                    lab[yy, xx] = n
                    q.append((yy, xx))
        p = np.array(pts)
        bw, bh = p[:, 1].max() - p[:, 1].min() + 1, p[:, 0].max() - p[:, 0].min() + 1
        score = len(p) * (1.0 if 0.5 < bw / max(1, bh) < 2.4 else 0.4)      # 길쭉한 것(팔 · 창대)은 덜 친다
        score *= 1.0 - 1.2 * max(0.0, (p[:, 0].mean() - y0) / h - 0.2)       # 위쪽에 있을수록 얼굴 (손 · 지도 · 배는 아래)
        if best is None or score > best[0]:
            best = (score, p)
    box = (x0, y0, w, h)
    if best is None or len(best[1]) < 0.004 * w * h:
        return None, box
    p = best[1]
    cx, cy = (p[:, 1].min() + p[:, 1].max()) / 2, (p[:, 0].min() + p[:, 0].max()) / 2
    fw, fh = p[:, 1].max() - p[:, 1].min() + 1, p[:, 0].max() - p[:, 0].min() + 1
    side = min(max(max(fw, fh) * 1.75, h * 0.30), h * 0.46)      # 얼굴 살 폭의 1.75배 —— 머리 장식 · 수염이 조금 들어오게
    return (cx, cy - side * 0.04, side), box


def do_faces(names):
    miss = []
    for nm in sorted(names):
        im = Image.open(os.path.join(OUT_P, nm + ".png")).convert("RGBA")
        head, (x0, y0, w, h) = find_head(im)
        if nm in FACE_FIX:
            fx, fy, fs = FACE_FIX[nm]
            head = (x0 + fx * w, y0 + fy * h, fs * h)
        if head is None:      # 살색이 없는 얼굴(붉은 얼굴 · 복면) —— 게임의 얼굴 찾기와 같은 어림 (위 29% · 키의 38%)
            miss.append(nm)
            head = (x0 + w * 0.5, y0 + h * 0.29, h * 0.38)
        cx, cy, side = head
        box = [round(cx - side / 2), round(cy - side / 2)]
        box += [box[0] + round(side), box[1] + round(side)]
        S = FACE * 3
        crop = im.crop(box).resize((S, S), Image.LANCZOS)      # 그림 밖은 투명으로 채워진다
        bg = Image.new("RGBA", (S, S), PAPER + (255,))
        bg.alpha_composite(crop)
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).ellipse((3, 3, S - 4, S - 4), fill=255)
        bg.putalpha(mask)
        bg.resize((FACE, FACE), Image.LANCZOS).save(os.path.join(OUT_F, nm + ".png"), optimize=True)
    print("얼굴 %d명 (자동으로 못 찾아 어림한 얼굴: %s)" % (len(names), ", ".join(miss) or "-"))


base_names = None
if "base" in ONLY:
    base_names = do_base()
if "kiin" in ONLY:
    do_kiin()
if "trans" in ONLY:
    do_trans()
if "immortal" in ONLY:
    do_immortal()
if "myth" in ONLY:
    do_myth()
if "faces" in ONLY:
    if base_names is None:
        base_names = [f[:-4] for f in os.listdir(OUT_P) if f.endswith(".png") and "_" not in f]
    do_faces(base_names)
if APPLY:
    n = 0
    for sub, src in (("portraits", OUT_P), ("faces", OUT_F)):
        for f in sorted(os.listdir(src)):
            if f.endswith(".png"):
                shutil.copy2(os.path.join(src, f), os.path.join("solgukji_godot/assets", sub, f))
                n += 1
    print("%d개를 solgukji_godot/assets 에 넣었다 —— Godot --import 를 한 번 돌린다" % n)
