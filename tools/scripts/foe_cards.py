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
    1: ["황건 잡병", "황건 기마졸", "황건 활잡이", "황건 졸개", "태평도 신도"],      # 11/9 사용자: 토벌에 기본 등급 일반 부대(궁병 · 기병 …)가 나왔다 —— 잡병 · 낮은 칸도 황건으로
    2: ["황건 장창대", "황건 기마대", "황건 궁대", "황건 무뢰배", "태평도 부적사"],
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

# 11/9 사용자: 토벌이 너무 쉽다 —— 고등급 토벌 전용 정예. 같은 등급 같은 병종 평균 × ELITE_MUL (공격 · 방어 · 책략 · 지휘, 속도 · 병력 · PV 는 그대로), 특기 없음.
# id 는 y<등급><5~9>. 잡병 대군(DB.horde_rabble)이 등급이 오른 뒤 y<등급>0~9 를 섞어 쓴다
ELITE_MUL = 1.12
ELITE = {
    4: ["황건 방패장", "흑산 돌기대", "흑산 노수", "백파 자객", "태평도 법사"],
    5: ["황건 방진장", "흑산 철기대", "흑산 강궁대", "백파 결사대", "태평도 도사"],
    6: ["황천 금강역사", "황천 흑기대", "황천 뇌궁수", "황천 살수", "태평도 천관"],
    7: ["황천 호법신장", "황천 뇌기장", "황천 벽력궁", "황천 흑살귀", "태평도 대성사"],
}
for t, names in ELITE.items():
    for i, (tag, nm) in enumerate(zip(TAGS, names)):
        base_c = [c for c in out if c[0] == "y%d%d" % (t, i)][0]
        c = list(base_c)
        c[0] = "y%d%d" % (t, i + 5)
        c[1] = nm
        for j in range(5, 9):
            c[j] = round(c[j] * ELITE_MUL)
        out.append(c)

E["cards"] = [c for c in E["cards"] if c[13] != "foe"] + out
open(EXT, "w", encoding="utf-8", newline="\n").write(json.dumps(E, ensure_ascii=False, indent=1) + "\n")
for c in out:
    print(c[:12])
