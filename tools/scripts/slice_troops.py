"""병사 스프라이트 시트(4칸 x 2줄, 연두 배경)를 잘라 게임용 묶음 그림으로 만든다 (10/31).

실행 (solgukji-main 에서): python -I tools/scripts/slice_troops.py 시트.png 병종 [--cols=4 --rows=2 --fill=0.84]
결과: solgukji_godot/assets/troops_sprite/<병종>.png  —— 4 x 2 칸, 칸마다 256 x 256, 투명 배경
      references/병사/<병종>_미리보기.png —— 바둑판 바탕 · 칸 경계 · 발 자리 선 (확인용, 게임은 안 쓴다)

방법
  1. 연두 기운이 있는 픽셀은 모두 배경으로 지운다 (병사 옷에 초록을 쓰지 않게 프롬프트로 막았다). 가장자리는 초록을 걷어 낸다.
  2. 칸마다 남은 그림의 테두리 상자를 잰다. 칸마다 크기가 다르게 나와도 서 있는 동작들의 키 중앙값으로 한 배율을 정해 모두 같게 줄인다.
  3. 서 있는 동작은 발(아래 12%)의 가운데를, 쓰러진 동작(7)은 상자 가운데를 칸 가운데에 맞추고, 아래 끝을 칸 바닥에 붙인다.
     게임은 칸 아래 가운데를 병사의 발 자리로 쓴다 (War3D.SPRITE_H · soldier_sprite.gdshader).
"""
import sys

import numpy as np
from PIL import Image, ImageDraw

CELL = 256
FALLEN = 6          # 0 부터 센 칸 번호 —— 7번 쓰러짐


def key_out(rgb: np.ndarray) -> np.ndarray:
    """연두 배경 → 알파 0. 가장자리는 초록 정도만큼 반투명."""
    r, g, b = (rgb[..., i].astype(float) for i in range(3))
    green = g - np.maximum(r, b)
    alpha = np.clip(1.0 - (green - 6.0) / 22.0, 0.0, 1.0)
    alpha[(g > 110) & (green > 28)] = 0.0
    return alpha


def despill(rgb: np.ndarray) -> np.ndarray:
    out = rgb.astype(float)
    cap = np.maximum(out[..., 0], out[..., 2])
    out[..., 1] = np.minimum(out[..., 1], cap + 8)
    return out


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    src, tag = args[0], args[1]
    cols = int(opts.get("cols", 4))
    rows = int(opts.get("rows", 2))
    fill = float(opts.get("fill", 0.9 if tag == "기병" else 0.84))
    img = Image.open(src).convert("RGB")
    rgb = np.asarray(img)
    alpha = key_out(rgb)
    clean = despill(rgb)
    h, w = alpha.shape
    cw, ch = w / cols, h / rows
    frames = []
    for k in range(cols * rows):
        x0, y0 = int((k % cols) * cw), int((k // cols) * ch)
        x1, y1 = int(x0 + cw), int(y0 + ch)
        a = alpha[y0:y1, x0:x1].copy()
        # 칸 가장자리 몇 줄은 이웃 칸의 넘침일 수 있어 비운다
        a[:3, :] = 0
        a[-3:, :] = 0
        a[:, :3] = 0
        a[:, -3:] = 0
        ys, xs = np.nonzero(a > 0.5)
        if len(xs) == 0:
            frames.append(None)
            continue
        bx0, bx1, by0, by1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        rgba = np.dstack([clean[y0:y1, x0:x1], a * 255.0]).clip(0, 255).astype(np.uint8)
        if k == FALLEN:
            anchor = (bx0 + bx1) / 2
        else:
            foot = a[int(by1 - (by1 - by0) * 0.12):by1, :]
            fx = np.nonzero(foot > 0.5)[1]
            anchor = fx.mean() if len(fx) else (bx0 + bx1) / 2
        frames.append({"img": Image.fromarray(rgba, "RGBA"), "box": (bx0, by0, bx1, by1), "anchor": anchor})
    heights = [f["box"][3] - f["box"][1] for i, f in enumerate(frames) if f and i != FALLEN]
    if not heights:
        print("그림을 찾지 못했다 —— 배경이 연두(#9BCF88)인지 확인")
        sys.exit(1)
    scale = CELL * fill / float(np.median(heights))
    atlas = Image.new("RGBA", (CELL * cols, CELL * rows), (0, 0, 0, 0))
    for k, f in enumerate(frames):
        if f is None:
            print(f"  칸 {k + 1}: 비었음")
            continue
        im = f["img"].resize((max(1, round(f["img"].width * scale)), max(1, round(f["img"].height * scale))), Image.LANCZOS)
        bx0, by0, bx1, by1 = (v * scale for v in f["box"])
        ox = (k % cols) * CELL + CELL / 2 - f["anchor"] * scale
        oy = (k // cols) * CELL + CELL - 3 - by1
        atlas.alpha_composite(im, (round(ox), round(oy)))
        if bx1 - bx0 > CELL or by1 - by0 > CELL:
            print(f"  칸 {k + 1}: 칸보다 커서 잘린다 —— --fill 을 줄여 보자")
    out = f"solgukji_godot/assets/troops_sprite/{tag}.png"
    atlas.save(out)
    prev = Image.new("RGBA", atlas.size, (0, 0, 0, 255))
    d = ImageDraw.Draw(prev)
    for y in range(0, atlas.height, 16):
        for x in range(0, atlas.width, 16):
            if (x // 16 + y // 16) % 2 == 0:
                d.rectangle([x, y, x + 15, y + 15], fill=(60, 60, 60, 255))
    prev.alpha_composite(atlas)
    d = ImageDraw.Draw(prev)
    for k in range(cols * rows):
        x, y = (k % cols) * CELL, (k // cols) * CELL
        d.rectangle([x, y, x + CELL - 1, y + CELL - 1], outline=(255, 210, 80, 255))
        d.line([x + CELL / 2 - 20, y + CELL - 3, x + CELL / 2 + 20, y + CELL - 3], fill=(80, 220, 255, 255), width=2)
    import os
    os.makedirs("references/병사", exist_ok=True)
    prev.save(f"references/병사/{tag}_미리보기.png")
    print(f"{tag}: 배율 {scale:.3f} → {out}")


if __name__ == "__main__":
    main()
