"""기본패 병졸 · 토벌 적 시트를 한꺼번에 자른다 —— 먼저 검토 폴더에 자르고, 확인한 뒤 --apply 로 게임 폴더에 넣는다 (11/9).

실행: python -I tools/scripts/slice_cards.py 기본패 [--apply]     기본패 병졸 카드 8종 → solgukji_godot/assets/troops/<병종>.png
      python -I tools/scripts/slice_cards.py 토벌적 [--apply]     토벌 전용 적 55장   → solgukji_godot/assets/foes/<카드 id>.png
  시트:  references/<폴더>_시트/<프롬프트 이름>.png   (예: references/토벌적_시트/01_1등급.png —— prompts/<폴더>/ 의 txt 와 같은 이름)
  이름 · 옵션:  prompts/<폴더>/자르기_이름.txt 의 '자르기' 줄 (이름 목록과 --hole · --max 를 그대로 쓴다. make_troop_foe_prompts.py 가 만든다)
  결과:  references/<폴더>_시트/잘림/<이름>.png + 미리보기/<시트>.png   (검토용)
  --apply: 잘림/ 의 PNG 를 게임 폴더로 복사 (폴더가 없으면 만든다, 같은 이름은 덮어쓴다)
시트가 아직 없는 것은 건너뛴다 —— 그린 시트부터 먼저 잘라도 된다.
"""
import os
import re
import shutil
import subprocess
import sys

kind = sys.argv[1]
apply = "--apply" in sys.argv
DEST = {"기본패": "solgukji_godot/assets/troops", "토벌적": "solgukji_godot/assets/foes"}
sheets = "references/%s_시트" % kind
out = os.path.join(sheets, "잘림")
prev = os.path.join(sheets, "미리보기")

if apply:
    dst = DEST[kind]
    os.makedirs(dst, exist_ok=True)
    n = 0
    for f in sorted(os.listdir(out)):
        if f.endswith(".png"):
            shutil.copy2(os.path.join(out, f), os.path.join(dst, f))
            n += 1
    print("%d개를 %s 에 넣었다. 그냥 두면 게임이 읽는다 (임포트 불필요 —— 휴대폰 APK 를 만들 때만 Godot --import 한 번)." % (n, dst))
    sys.exit()

howto = open(os.path.join("prompts", kind, "자르기_이름.txt"), encoding="utf-8").read()
# 줄 모양: [시트.txt] ... \n  자르기: python -I tools/scripts/slice_sheet.py 시트.png "이름,이름" 출력폴더 --hole=155 --max=512
plan = re.findall(r'^\[(\S+)\.txt\].*?\n  자르기: \S+ \S+ \S+ \S+ "([^"]+)" \S+( .*)$', howto, flags=re.M)
os.makedirs(out, exist_ok=True)
os.makedirs(prev, exist_ok=True)
done, missing = 0, []
for sheet, names, opts in plan:
    src = os.path.join(sheets, sheet + ".png")
    if not os.path.exists(src):
        missing.append(sheet)
        continue
    cmd = [sys.executable, "-I", "tools/scripts/slice_sheet.py", src, names, out, os.path.join(prev, sheet + ".png")] + opts.split()
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    print("[%s]" % sheet, (r.stdout + r.stderr).strip().replace("\n", " | "))
    done += 1
print("자른 시트 %d장 → %s (미리보기: %s)" % (done, out, prev), ("· 시트 없음: " + ", ".join(missing)) if missing else "")
