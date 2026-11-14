"""새 일러스트를 게임 규격 크기로 맞춘다 (11/14) —— docs/일러스트_규격.md

어떤 크기 · 비율의 그림이든 받아서
  card  400×520 (10:13 —— 카드 초상. 조합 · 편성 · 상세 칸이 모두 이 비율 근처)
  cut   512×768 (2:3   —— 신화 고유기 컷인 · 장면 그림)
  face  256×256 (1:1   —— 전투 얼굴 메달)
로 만든다. 순서:
  1) 투명 배경이면 그려진 영역(알파 > 8)만 남기고 자른다 (bbox trim).
  2) 목표 비율로 '덮어' 자른다 —— 가로는 가운데(--face-x 로 옮길 수 있다), 세로는 위에 붙인다(머리 기준. 발 쪽을 자른다).
     face 는 위쪽 HEAD 띠(높이의 약 15~55%)를 정사각으로 잘라 얼굴이 가운데 오게 한다.
     그림이 목표보다 가로로 넓으면 양옆을, 세로로 길면 아래를 자른다 —— 빈 띠(레터박스)는 만들지 않는다.
  3) Lanczos 로 줄인다 (늘려야 하면 경고를 찍는다). RGBA PNG 로 저장.

이름 —— 파일 이름은 그대로 쓴다 (예: 관우_불멸.png → <out>/card/관우_불멸.png). 이름 규칙은 문서 참고.
기존 assets 는 덮어쓰지 않는다: --out 이 solgukji_godot/assets 안이면 --force 없이는 멈춘다.

쓰기:
  python -I tools/scripts/normalize_portraits.py 새그림폴더 --out 결과폴더 [--kind card,cut,face] [--face-x 0.5] [--force]
  (파일 하나만: 폴더 대신 png 경로)
"""
import argparse
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow 가 필요하다: pip install pillow")

SIZES = {"card": (400, 520), "cut": (512, 768), "face": (256, 256)}
ALPHA_MIN = 8          # 이보다 옅은 픽셀은 배경으로 본다 (가장자리 번짐)
FACE_TOP = 0.08        # face —— 정사각 위 끝을 인물 키의 이 비율 자리에 (머리 위 약간 여유)
FACE_SIDE = 0.46       # face —— 정사각 한 변 = 인물 키의 이 비율 (2~3등신 그림 기준)
EXTS = (".png", ".webp", ".jpg", ".jpeg")


def trim(im):
    """투명 배경이면 그려진 영역만 (네 귀퉁이가 모두 투명할 때만 —— 패널 그림 · 불투명 그림은 그대로)"""
    if im.mode != "RGBA":
        return im.convert("RGBA")
    a = im.getchannel("A")
    w, h = im.size
    corners = [a.getpixel((0, 0)), a.getpixel((w - 1, 0)), a.getpixel((0, h - 1)), a.getpixel((w - 1, h - 1))]
    if max(corners) > ALPHA_MIN:
        return im
    box = a.point(lambda v: 255 if v > ALPHA_MIN else 0).getbbox()
    return im.crop(box) if box else im


def cover_box(w, h, tw, th, fx=0.5):
    """(w, h) 그림에서 tw:th 비율 상자 —— 가로는 fx 기준 가운데, 세로는 위에 붙인다"""
    if w * th > h * tw:          # 그림이 더 넓다 —— 양옆을 자른다
        cw, ch = h * tw / th, h
    else:                         # 그림이 더 길다 —— 아래를 자른다 (머리 기준)
        cw, ch = w, w * th / tw
    x = min(max(fx * w - cw / 2, 0), w - cw)
    return (round(x), 0, round(x + cw), round(ch))


def face_box(w, h, fx=0.5):
    side = min(h * FACE_SIDE, w)
    x = min(max(fx * w - side / 2, 0), w - side)
    y = min(h * FACE_TOP, h - side)
    return (round(x), round(y), round(x + side), round(y + side))


def convert(path, out_dir, kinds, fx):
    im = trim(Image.open(path))
    w, h = im.size
    name = os.path.splitext(os.path.basename(path))[0] + ".png"
    for k in kinds:
        tw, th = SIZES[k]
        box = face_box(w, h, fx) if k == "face" else cover_box(w, h, tw, th, fx)
        crop = im.crop(box)
        if crop.width < tw or crop.height < th:
            print("  경고: %s (%s) 원본 영역 %dx%d 이 목표 %dx%d 보다 작다 —— 늘린다" % (name, k, crop.width, crop.height, tw, th))
        res = crop.resize((tw, th), Image.LANCZOS)
        d = os.path.join(out_dir, k)
        os.makedirs(d, exist_ok=True)
        res.save(os.path.join(d, name), optimize=True)
    print("%s  %dx%d → %s" % (name, w, h, ", ".join("%s %dx%d" % (k, *SIZES[k]) for k in kinds)))


def main():
    for st in (sys.stdout, sys.stderr):      # 윈도우 콘솔(cp949)에서 —— 같은 글자가 깨지지 않게
        try:
            st.reconfigure(encoding="utf-8", errors="replace")
        except AttributeError:
            pass
    ap = argparse.ArgumentParser(description="새 일러스트를 400×520 · 512×768 · 256×256 으로 맞춘다")
    ap.add_argument("src", help="그림 폴더 또는 그림 파일")
    ap.add_argument("--out", required=True, help="결과 폴더 (그 아래 card/ cut/ face/)")
    ap.add_argument("--kind", default="card,face", help="card,cut,face 중 쉼표로 (기본 card,face —— 신화는 card,cut,face)")
    ap.add_argument("--face-x", type=float, default=0.5, help="얼굴 가로 자리 (0~1, 기본 가운데)")
    ap.add_argument("--force", action="store_true", help="assets 폴더 안에도 쓴다 (기존 그림을 덮어쓴다)")
    a = ap.parse_args()
    kinds = [k.strip() for k in a.kind.split(",") if k.strip()]
    bad = [k for k in kinds if k not in SIZES]
    if bad:
        sys.exit("모르는 kind: %s (card · cut · face)" % ", ".join(bad))
    out = os.path.abspath(a.out)
    assets = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "solgukji_godot", "assets"))
    if (out + os.sep).startswith(assets + os.sep) and not a.force:
        sys.exit("결과 폴더가 게임 assets 안이다 —— 기존 그림을 덮어쓸 수 있어 멈춘다 (확인했으면 --force)")
    if os.path.isdir(a.src):
        files = sorted(os.path.join(a.src, f) for f in os.listdir(a.src) if f.lower().endswith(EXTS))
    else:
        files = [a.src]
    if not files:
        sys.exit("그림이 없다: %s" % a.src)
    for f in files:
        convert(f, out, kinds, a.face_x)
    print("%d장 → %s" % (len(files), out))


if __name__ == "__main__":
    main()
