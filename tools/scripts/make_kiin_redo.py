# -*- coding: utf-8 -*-
"""기인 시트 01 재작업 —— 11/10 에 그려진 기인 01(고순 · 공손찬 · 곽가 · 손상향 · 장합 · 마등) 이 참조와 다른 인물로 나와 보류했다.
한 장 6명은 모델이 지시를 섞으므로 **3명씩 두 장**으로 다시 쓴다 + 인물마다 '이것만은 지켜라' 줄을 붙인다.
실행: python -I tools/scripts/make_kiin_redo.py   →  prompts/등급별_v2/1_기인/재작업_A_*.txt · 재작업_B_*.txt + 참조_재작업_A/B.png
(make_tier_prompts_v2.py 의 함수를 그대로 쓰되 main() 은 부르지 않는다 —— 기존 프롬프트 파일을 건드리지 않는다)
"""
import os, subprocess, sys

SRC = open("tools/scripts/make_tier_prompts_v2.py", encoding="utf-8").read()
assert SRC.rstrip().endswith("main()")
NS = {"__name__": "mtp_v2"}
exec(compile(SRC.rstrip()[:-len("main()")], "make_tier_prompts_v2.py", "exec"), NS)

MUST = {
    "고순": "Gao Shun: a stern bearded general in a dark iron helmet with a RED plume, holding a tall spear and a LARGE rectangular iron shield (the shield is his signature: it must be clearly visible). Heavy red-and-black lamellar armor. NOT a young man, NOT a scholar.",
    "공손찬": "Gongsun Zan: silver-WHITE armor and a silver helmet with a tall WHITE plume, riding a WHITE horse, holding a spear; a lean, stern, thin-mustached commander. The white color scheme is essential.",
    "곽가": "Guo Jia: a SLIM young SCHOLAR, not a warrior: long messy dark hair, a sly half-smile with half-closed eyes, a loose blue-grey robe, holding a calligraphy BRUSH and a small gourd at the waist. No armor, no helmet, no big beard, no weapon. Looks clever and sickly-thin, not muscular.",
    "손상향": "Sun Shangxiang: a YOUNG WOMAN with two hair buns tied with RED ribbons, a bold teasing smile, holding two short daggers, red-and-black light armor with a red sash. She must read as a woman at a glance; not a bearded man.",
    "장합": "Zhang He: a refined commander in a GOLD-and-BLUE helmet with a blue and yellow plume, a thin goatee, gold and blue armor, riding a GREY horse with a spear. Elegant and cunning, not a bulky brute.",
    "마등": "Ma Teng: an older Liang (western frontier) warlord in a FUR hat and a fur-trimmed brown coat, a thick GREY beard, weathered face, riding a brown shaggy horse. Not a young warrior, no club or mace.",
}
NOTE = ("REDRAW NOTE: a first attempt of this sheet drew WRONG people (the strategist became a bearded fighter, the woman became a man, "
        "the white-armored rider disappeared). Panel k MUST be the character numbered k in the attached reference image, "
        "exactly as below. If a panel does not match the reference, it is wrong.\n" + "\n".join("- " + v for v in MUST.values() if False))

targets = NS["load_targets"]()
roles = NS["load_roles"]()
ident = NS["load_identity"]()
hints = NS["load_hints"]()
cards = {c["person"]: c for c in targets["kiin"]}
GROUPS = [("A", ["고순", "공손찬", "곽가"]), ("B", ["손상향", "장합", "마등"])]
out = "prompts/등급별_v2/1_기인"
for tag, names in GROUPS:
    chunk = [cards[n] for n in names]
    text = NS["sheet_text"]("kiin", chunk, ident, roles, hints)
    must = "\n".join("- Panel %d — %s" % (i + 1, MUST[n]) for i, n in enumerate(names))
    block = ("REDRAW NOTE: a first attempt drew WRONG people (the young strategist became a bearded fighter, the woman became a man, "
             "the white-armored rider disappeared). Panel k MUST be exactly the character numbered k in the attached reference image. "
             "The most important identity points (override anything vague above):\n" + must + "\n")
    # LAYOUT 앞에 끼운다
    i = text.index("LAYOUT:")
    text = text[:i] + block + "\n" + text[i:]
    fn = "%s/재작업_%s_%s.txt" % (out, tag, "_".join(names))
    open(fn, "w", encoding="utf-8", newline="\n").write(text)
    ref = "%s/참조_재작업_%s.png" % (out, tag)
    subprocess.run([sys.executable, "-I", "tools/scripts/make_ref_sheet.py", ",".join(names), ref], check=True)
    print(fn, "·", ref, "·", len(text), "자")
