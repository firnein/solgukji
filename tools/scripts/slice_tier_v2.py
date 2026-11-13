"""등급별 v2 시트(기인 · 초월 · 불멸 · 신화)를 한꺼번에 자른다 —— 먼저 검토 폴더에 자르고, 확인한 뒤 --apply 로 게임 초상 폴더에 넣는다 (11/10).

실행: python -I tools/scripts/slice_tier_v2.py 3_불멸 [--max 640] [--apply]
      폴더 = 1_기인 · 2_초월 · 3_불멸 · 4_신화  (prompts/등급별_v2/ 아래 폴더 이름)
  시트:  references/등급별_v2_시트/<폴더>/<프롬프트 이름>.png   (예: 01_촉_위_오_군_4명.png —— prompts/등급별_v2/<폴더>/ 의 txt 와 같은 이름)
  이름:  prompts/등급별_v2/<폴더>/자르기_이름.txt 의 '자르기' 줄 (make_tier_prompts_v2.py 가 만든다)
  결과:  references/등급별_v2_시트/<폴더>/잘림/<인물>_<등급>.png + 미리보기/<시트>.png   (검토용)
  --max:  한 변 최대 픽셀. 기본 기인 · 초월 · 불멸 640, 신화 1152 (768x1152). 휴대폰 용량 때문에 줄인다 —— 줄이기만 하고 늘리지 않는다
  --apply: 잘림/ 의 PNG 를 solgukji_godot/assets/portraits 로 복사 (같은 이름은 덮어쓴다 —— 깃에 이전 그림이 남아 있다). 파일 수 · 용량 합계를 보여 준다
기인 · 초월 · 불멸은 slice_panels.py 로 패널째 잘라 바깥 연두 바탕만(가장자리 12px) 투명하게 하고 번호 도장이 덮은 아래쪽을 자르고, 신화(한 명짜리)는 그림 전체를 그대로 카드로 쓴다.
시트가 아직 없는 것은 건너뛴다 —— 그린 시트부터 먼저 잘라도 된다.
"""
import os
import re
import shutil
import subprocess
import sys

from PIL import Image

tier = sys.argv[1]
apply = "--apply" in sys.argv
DEFAULT_MAX = {"1_기인": 640, "2_초월": 600, "3_불멸": 600, "4_신화": 1152}   # 초월 · 불멸은 자르기 고침으로 패널이 넓어져 600 으로 (용량이 늘지 않게)
if tier not in DEFAULT_MAX:
    sys.exit("폴더는 1_기인 · 2_초월 · 3_불멸 · 4_신화 중 하나")
mx = int(sys.argv[sys.argv.index("--max") + 1]) if "--max" in sys.argv else DEFAULT_MAX[tier]
sheets = os.path.join("references/등급별_v2_시트", tier)
out = os.path.join(sheets, "잘림")
prev = os.path.join(sheets, "미리보기")
PORTRAITS = "solgukji_godot/assets/portraits"
# 11/10 자르기 고침 —— 패널 바깥 바탕만 지우고(가장자리 12px) · 시트의 번호 이름표가 패널 아래를 덮은 만큼 자른다.
# 이름표가 패널 밖에 있는 시트(초월 04 · 불멸 03 · 08 · 신화)는 자르지 않는다 (눈으로 확인한 목록).
RIM = 12
BOTTOM_CUT = {"1_기인": {"01": 0.12, "02": 0.12, "03": 0.12, "04": 0.12},
              "2_초월": {"01": 0.12, "02": 0.12, "03": 0.12},
              "3_불멸": {"01": 0.10, "02": 0.10, "04": 0.10, "05": 0.10, "06": 0.10, "07": 0.10}}


def shrink(path: str) -> None:
    im = Image.open(path)
    k = mx / max(im.size)
    if k < 1.0:
        im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
    im.save(path, optimize=True)


if apply:
    n, total = 0, 0
    for f in sorted(os.listdir(out)):
        if f.endswith(".png"):
            shutil.copy2(os.path.join(out, f), os.path.join(PORTRAITS, f))
            n += 1
            total += os.path.getsize(os.path.join(out, f))
    print("%d개 (합계 %.1fMB) 를 %s 에 넣었다. solgukji_godot 에서 Godot --import 를 한 번 돌린다." % (n, total / 1048576, PORTRAITS))
    sys.exit()

howto = open(os.path.join("prompts/등급별_v2", tier, "자르기_이름.txt"), encoding="utf-8").read()
plan = re.findall(r'^\[(\S+)\.txt\].*?\n(?:  참조:.*\n)?  자르기: .*? "([^"]+)"', howto, flags=re.M)
os.makedirs(out, exist_ok=True)
os.makedirs(prev, exist_ok=True)
done, missing, total = 0, [], 0
for sheet, names in plan:
    src = os.path.join(sheets, sheet + ".png")
    if not os.path.exists(src):
        missing.append(sheet)
        continue
    if "," not in names and tier in ("4_신화", "3_불멸"):        # 한 명짜리 —— 그림 전체가 카드 (11/13 불멸도 한 장에 한 명)
        im = Image.open(src).convert("RGB")
        dst = os.path.join(out, names + ".png")
        im.save(dst)
        shrink(dst)
        t = Image.open(dst)
        t.thumbnail((400, 600))
        t.save(os.path.join(prev, sheet + ".png"))
        print("[%s] %s 한 장 그대로 (%s)" % (sheet, names, "x".join(str(v) for v in Image.open(dst).size)))
    else:
        cmd = [sys.executable, "-I", "tools/scripts/slice_panels.py", src, names, out, os.path.join(prev, sheet + ".png"), "--rim", str(RIM)]
        cut = BOTTOM_CUT.get(tier, {}).get(sheet[:2])
        if cut:
            cmd += ["--bottom", str(cut)]
        r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
        print("[%s]" % sheet, (r.stdout + r.stderr).strip().replace("\n", " | "))
        if r.returncode != 0:
            continue
        for nm in names.split(","):
            shrink(os.path.join(out, nm + ".png"))
    done += 1
for f in os.listdir(out):
    total += os.path.getsize(os.path.join(out, f)) if f.endswith(".png") else 0
print("자른 시트 %d장 → %s (미리보기: %s) · 잘림 합계 %.1fMB" % (done, out, prev, total / 1048576),
      ("· 시트 없음: " + ", ".join(missing)) if missing else "")
