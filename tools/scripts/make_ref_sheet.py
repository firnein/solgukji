"""위 등급 시트에 붙여 넣을 '기본 캐릭터 참조 이미지'를 만든다 —— 기본 초상(<인물>.png)을 번호와 함께 한 장에 늘어놓는다.

실행: python -I tools/scripts/make_ref_sheet.py "관우,마초,황충" 출력.png [초상폴더]
  번호는 이름 순서(1부터) = 위 등급 프롬프트의 번호. 초상폴더 기본값 solgukji_godot/assets/portraits
  명령은 prompts/등급별/<등급>/자르기_이름.txt 에 시트마다 적혀 있다.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

names = sys.argv[1].split(",")
out = sys.argv[2]
src = sys.argv[3] if len(sys.argv) > 3 else "solgukji_godot/assets/portraits"
CELL, LABEL, GAP = 420, 80, 24
cols = min(len(names), 4)
rows = -(-len(names) // cols)
W = cols * CELL + (cols + 1) * GAP
H = rows * (CELL + LABEL) + (rows + 1) * GAP
sheet = Image.new("RGB", (W, H), (255, 255, 255))
draw = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("arial.ttf", 60)
except OSError:
    font = ImageFont.load_default(size=60)
missing = []
for i, n in enumerate(names):
    x = GAP + (i % cols) * (CELL + GAP)
    y = GAP + (i // cols) * (CELL + LABEL + GAP)
    path = os.path.join(src, n + ".png")
    if os.path.exists(path):
        im = Image.open(path).convert("RGBA")
        im = im.crop(im.getbbox() or (0, 0, im.width, im.height))
        k = min(CELL / im.width, CELL / im.height)                 # 작은 그림도 칸에 꽉 차게
        im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
        sheet.paste(im, (x + (CELL - im.width) // 2, y + (CELL - im.height) // 2), im)
    else:
        missing.append(n)
        draw.rectangle([x, y, x + CELL, y + CELL], outline=(200, 0, 0), width=4)
    t = str(i + 1)
    tw = draw.textlength(t, font=font)
    draw.text((x + (CELL - tw) / 2, y + CELL + 6), t, fill=(30, 60, 30), font=font)
os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
sheet.save(out)
print(out, "%d명" % len(names), ("· 기본 초상 없음: " + ", ".join(missing)) if missing else "")
