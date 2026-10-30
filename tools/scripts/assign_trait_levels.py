"""특기 레벨 1~9 를 장수 특징 · 등급으로 매긴다 (2026-10-30, 사용자 지시). passives.json 의 level 을 덮어쓴다.

규칙 (카드 등급 평균이 예전 배율 '등급 - 2' 근처에 남도록):
- 바탕 = 카드 등급 - 2 (고급 1 · 희귀 2 · 전설 3 · 초월 4 · 불멸 5 · 신화 6)
- 숙련: 그 특기를 가진 지 2~3등급이면 +1, 4등급 이상이면 +2
- 갓 얻음: 전설 이상에서 이번 등급에 처음 붙은 특기면 -1
- 대표 특기 +1: 사다리 첫 특기, 또는 그 인물 혼자만 가진 특기 (수엄칠군 · 백보천양 · 일기당천 …)
- 이름난 장수(FAME)의 대표 특기는 +1 더
- MANUAL 로 몇 개는 직접 정한다. 1~9 로 자르고, 고급은 3 을 넘지 않는다.

실행: python -I tools/scripts/assign_trait_levels.py
"""
import json
from collections import OrderedDict, Counter, defaultdict

PATH = "solgukji_godot/data/passives.json"
P = json.load(open(PATH, encoding="utf-8"), object_pairs_hook=OrderedDict)
d = json.load(open("solgukji_godot/data/game.json", encoding="utf-8"))
e = json.load(open("solgukji_godot/data/cards_ext.json", encoding="utf-8"))
tiers = defaultdict(set)
for c in d["CARDDEF"] + e["cards"]:
    if c[2] >= 3:
        tiers[c[1].split(" ")[-1]].add(c[2])

FAME = {"여포", "관우", "장비", "조운", "마초", "황충", "제갈량", "유비", "조조", "사마의", "곽가", "장료", "허저", "전위",
        "하후돈", "주유", "손책", "손권", "육손", "감녕", "태사자", "여몽", "화타", "방통", "강유", "초선"}
# (인물, 특기) -> {등급: 레벨} —— 규칙으로는 안 나오는 이름난 장면
MANUAL = {
    ("여포", "일기당천"): {8: 9}, ("관우", "수엄칠군"): {7: 8, 8: 9}, ("장비", "투쟁"): {7: 8, 8: 9},
    ("조운", "장판돌파"): {8: 9}, ("조운", "장판단기"): {8: 9}, ("황충", "백보천양"): {7: 7, 8: 9},
    ("제갈량", "신산"): {8: 9}, ("주유", "적벽"): {7: 7, 8: 9}, ("유비", "도원결의"): {8: 8},
    ("장료", "합비돌격"): {8: 9}, ("화타", "인술"): {8: 9},
}

count = Counter(n for rows in P["ladder"].values() for n in {r[0] for r in rows})
lv_all = OrderedDict()
dist = defaultdict(list)
for p, rows in P["ladder"].items():
    per = OrderedDict()
    for i, r in enumerate(rows):
        hi = r[2] if len(r) > 2 else 99
        sig = i == 0 or count[r[0]] == 1
        m = OrderedDict()
        for t in sorted(tiers.get(p, ())):
            if not (r[1] <= t <= hi):
                continue
            held = t - r[1]
            v = t - 2
            v += 0 if held <= 1 else (1 if held <= 3 else 2)
            if held == 0 and t >= 5:
                v -= 1
            if sig:
                v += 1 + (1 if p in FAME else 0)
            v = MANUAL.get((p, r[0]), {}).get(t, v)
            v = max(1, min(9, v, 3 if t == 3 else 9))
            m[str(t)] = v
            dist[t].append(v)
        per[r[0]] = m
    lv_all[p] = per
P["level"] = lv_all
P["_레벨"] = ("특기 레벨 1~9 —— level[인물][특기][카드 등급] = 레벨 (화면에 '방진3' 처럼 보인다). 배율은 level_scale[레벨] "
             "(attr 가 있는 계열 특기는 level_scale_attr). 표에 없으면 '카드 등급 - 2'. 장수 특징 · 등급으로 매긴 규칙은 tools/scripts/assign_trait_levels.py")
open(PATH, "w", encoding="utf-8", newline="\n").write(json.dumps(P, ensure_ascii=False, indent=1) + "\n")
for t in sorted(dist):
    v = dist[t]
    print("등급 %d: 평균 %.2f (예전 %d) · 분포 %s" % (t, sum(v) / len(v), t - 2, dict(sorted(Counter(v).items()))))
for p in ["여포", "조운", "제갈량", "우금", "조인"]:
    print(p, {n: dict(m) for n, m in lv_all[p].items()})
