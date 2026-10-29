"""대용량 일러스트 프롬프트(md)를 시트별 txt 로 나눈다 —— 파일을 열어 전체 복사해 붙여넣기만 하면 된다.

실행: python -I tools/scripts/split_prompts.py [prompts/삼국지_일러스트_프롬프트_대용량.md] [prompts/대용량]
  NN_<시트 이름>.txt : 그 시트의 프롬프트 블록만 (그대로 붙여넣기)
  자르기_이름.txt    : 시트마다 자를 때 쓸 이름 목록과 명령
"""
import os
import re
import sys

src = sys.argv[1] if len(sys.argv) > 1 else "prompts/삼국지_일러스트_프롬프트_대용량.md"
dst = sys.argv[2] if len(sys.argv) > 2 else "prompts/대용량"
text = open(src, encoding="utf-8").read()
os.makedirs(dst, exist_ok=True)
for f in os.listdir(dst):
    if f.endswith(".txt"):
        os.remove(os.path.join(dst, f))

sections = re.split(r"^## (?=\d+\.)", text, flags=re.M)[1:]
cut = ["시트를 뽑은 뒤 D:\\Sol 에서 자르기 (이름 순서 = 이름표 번호 순서). 자른 뒤 solgukji_godot 에서 Godot --import 를 한 번 돌린다.\n"]
for sec in sections:
    head = sec.split("\n", 1)[0]
    m = re.match(r"(\d+)\. (\S+) \(([^)]*)\) (\d+) — (\d+)장", head)
    num, part, tiers, k, cnt = m.groups()
    block = re.search(r"```\n(.*?)\n```", sec, flags=re.S).group(1)
    name = "%02d_%s%s_%s_%s명.txt" % (int(num), part, k, tiers.replace("·", ""), cnt)
    open(os.path.join(dst, name), "w", encoding="utf-8", newline="\n").write(block.strip() + "\n")
    names = re.search(r"자르기 이름 목록: `([^`]*)`", sec)
    hole = "" if "--hole` 없이" in head else " --hole=155"
    cut.append("[%s] %s" % (name, head))
    if names:
        cut.append('  python -I tools/scripts/slice_panels.py 시트.png "%s" solgukji_godot/assets/portraits' % names.group(1))
        cut.append('  (칸 안이 배경 없이 인물만 오려진 모양이면) python -I tools/scripts/slice_sheet.py 시트.png "%s" solgukji_godot/assets/portraits%s'
                   % (names.group(1), hole))
    cut.append("")
open(os.path.join(dst, "자르기_이름.txt"), "w", encoding="utf-8", newline="\n").write("\n".join(cut))
print("\n".join(sorted(os.listdir(dst))))
