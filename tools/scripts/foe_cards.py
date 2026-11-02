"""토벌 전용 황건 카드 (2026-11-02 사용자: 황건 편성에 등급 맞는 카드가 모자라 → 황건 장수 카드 추가).

플레이어는 얻지 못한다 (kind "foe" —— 뽑기 · 상점 · 조합 · 도감 · 무작위 보드에서 빠진다, scripts/db.gd).
능력치 · PV · 병력은 같은 등급 · 같은 병종 카드의 평균 그대로. 특기는 없고 기술은 등급대로 병종 기술을 받는다.
id 는 y 로 시작 —— 원본 기술 배정(등급 · id 순서)이 밀리지 않게 맨 뒤로 간다.

실행: python -I tools/scripts/foe_cards.py   (cards_ext.json 의 cards 에 넣거나 고친다)
"""
import json
from collections import OrderedDict

d = json.load(open("solgukji_godot/data/game.json", encoding="utf-8"))
EXT = "solgukji_godot/data/cards_ext.json"
E = json.load(open(EXT, encoding="utf-8"), object_pairs_hook=OrderedDict)
base = [c for c in d["CARDDEF"] + E["cards"] if c[13] != "foe"]

TAGS = ["창병", "기병", "궁병", "도적", "술사"]
NAMES = {
    3: ["황건 창두", "황건 마적", "황건 궁두", "황건 역사", "태평도 제주"],
    4: ["황건 소방수", "황건 철기", "황건 신궁", "흑산 두령", "태평도 대제주"],
    5: ["황건 대방수", "황건 효기", "황건 사수장", "흑산 대두령", "태평도 방사"],
    6: ["황천 역사장", "황천 철기장", "황천 궁장", "황천 야차", "태평도 대현사"],
    7: ["황천 신장", "황천 신기장", "황천 신궁장", "황천 귀왕", "태평도 천사"],
}
out = []
for t, names in NAMES.items():
    for i, (tag, nm) in enumerate(zip(TAGS, names)):
        L = [c for c in base if c[2] == t and c[3] == tag]
        av = [round(sum(c[j] for c in L) / len(L)) for j in range(5, 12)]
        out.append(["y%d%d" % (t, i), nm, t, tag, "군"] + av[:5] + [L[0][10], av[6], None, "foe", ""])

E["cards"] = [c for c in E["cards"] if c[13] != "foe"] + out
open(EXT, "w", encoding="utf-8", newline="\n").write(json.dumps(E, ensure_ascii=False, indent=1) + "\n")
for c in out:
    print(c[:12])
