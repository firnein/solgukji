"""등급별 시트를 한꺼번에 자른다 —— 먼저 검토 폴더에 자르고, 확인한 뒤 --apply 로 게임 초상 폴더에 넣는다.

실행: python -I tools/scripts/slice_tier.py 1_기본 [--apply]
  시트:  references/등급별_시트/<등급>/<프롬프트 이름>.png   (예: 01_촉_5명.png —— prompts/등급별/<등급>/ 의 txt 와 같은 이름)
  이름:  prompts/등급별/<등급>/자르기_이름.txt 의 '자르기' 줄
  결과:  references/등급별_시트/<등급>/잘림/<인물>.png + 미리보기/<시트>.png   (검토용)
  --apply: 잘림/ 의 PNG 를 solgukji_godot/assets/portraits 로 복사 (기존 파일 덮어씀 —— 깃에 이전 그림이 남아 있다)
  기본(1_기본)은 slice_sheet.py(인물만 오려 냄), 위 등급은 slice_panels.py(패널째)로 자른다.
  촉 초록 옷이 없는 시트는 --hole=155 로 다리 · 창 사이의 갇힌 바탕까지 지운다.
"""
import os
import re
import shutil
import subprocess
import sys

tier = sys.argv[1]
apply = "--apply" in sys.argv
sheets = os.path.join("references/등급별_시트", tier)
out = os.path.join(sheets, "잘림")
prev = os.path.join(sheets, "미리보기")
PORTRAITS = "solgukji_godot/assets/portraits"

if apply:
    n = 0
    for f in sorted(os.listdir(out)):
        if f.endswith(".png"):
            shutil.copy2(os.path.join(out, f), os.path.join(PORTRAITS, f))
            n += 1
    print("%d개를 %s 에 넣었다. solgukji_godot 에서 Godot --import 를 한 번 돌린다." % (n, PORTRAITS))
    sys.exit()

howto = open(os.path.join("prompts/등급별", tier, "자르기_이름.txt"), encoding="utf-8").read()
plan = re.findall(r'^\[(\S+)\.txt\].*?\n(?:  참조:.*\n)?  자르기: .*? "([^"]+)"', howto, flags=re.M)
os.makedirs(out, exist_ok=True)
os.makedirs(prev, exist_ok=True)
tool = "tools/scripts/slice_sheet.py" if tier.startswith("1_기본") else "tools/scripts/slice_panels.py"
done, missing = 0, []
for sheet, names in plan:
    src = os.path.join(sheets, sheet + ".png")
    if not os.path.exists(src):
        missing.append(sheet)
        continue
    cmd = [sys.executable, "-I", tool, src, names, out, os.path.join(prev, sheet + ".png")]
    if tier.startswith("1_기본") and "촉" not in sheet:
        cmd.append("--hole=155")
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    print("[%s]" % sheet, (r.stdout + r.stderr).strip().replace("\n", " | "))
    done += 1
print("자른 시트 %d장 → %s (미리보기: %s)" % (done, out, prev), ("· 시트 없음: " + ", ".join(missing)) if missing else "")
