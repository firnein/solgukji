"""토벌 고정 편성 —— 황건적 소탕 (2026-11-02 사용자: 토벌은 황건적 소탕 테마, 단계마다 유닛이 정해져 있게).

원본 game.json 의 QUESTS(단계 이름) · QPV(목표 전력)는 그대로 두고, cards_ext.json 의 quest_rosters 로 덮는다.
단계마다 이름 · 우두머리 · 이름 있는 장수 + 병졸로 채우고, PV 를 원본 QPV 에 맞춘다 (11/2 에 더했던 ×1.2 · 장비는 토벌에서 뺀다).

실행: python -I tools/scripts/quest_rosters.py   (표를 찍고 cards_ext.json 에 쓴다)
"""
import json
from collections import OrderedDict

d = json.load(open("solgukji_godot/data/game.json", encoding="utf-8"))
EXT = "solgukji_godot/data/cards_ext.json"
E = json.load(open(EXT, encoding="utf-8"), object_pairs_hook=OrderedDict)
C = {c[0]: c for c in d["CARDDEF"] + E["cards"]}
PV = {k: c[11] for k, c in C.items()}
QPV = d["QPV"]

# 병졸 —— 황건 잡병 (태평도사 · 산월도적 위주, 창 · 활 · 말을 섞는다)
GEN2 = ["c9", "c6", "c0", "c4", "c1", "c5", "c3", "c2"]       # 2등급 3 · 3 · 3 · 3 · 2 · 2 · 2 · 3
GEN1 = ["occul", "rogue", "spear", "bow", "horse"]          # 1등급 1

# (일차, 단계) -> (이름, 우두머리, [이름 있는 장수 —— 우두머리 빼고], 진형)
STAGES = [
    [("황건 잔당 출몰", "c22", [], "eorin"),
     ("관해의 무리", "c22", ["c20", "c21"], "bongsi"),
     ("장량의 요술군", "c33", ["c32", "c22"], "hagik")],
    [("광종 포위", "c33", ["c32", "c69"], "bangwon"),
     ("장보 토벌", "c32", ["c33", "c69", "c22", "c20"], "anhaeng"),
     ("하곡양 결전", "c69", ["c33", "c32", "c22", "c21", "c20"], "eorin")],
    [("청주 황건", "c58", ["c22", "c20", "c21", "c32", "c33"], "chuhaeng"),
     ("흑산적 장연", "c58", ["c69", "c32", "c33", "c22", "c21"], "jangsa"),
     ("여남 황건", "c69", ["c58", "c32", "c33", "c22", "c20"], "hagik")],
    [("백파적", "c58", ["c69", "c72", "c22", "c20", "c21"], "bongsi"),
     ("장연의 기습", "c58", ["c69", "c72", "c70", "c32", "c33"], "anhaeng"),
     ("청주병 백만", "c107", ["c58", "c69", "c22", "c20", "c21"], "eorin")],
    [("오두미도의 봉기", "c110", ["c72", "c58", "c32", "c33", "c22"], "bangwon"),
     ("태평도 부활", "c107", ["c110", "c108", "c58", "c69", "c72"], "hagik"),
     ("천공장군 장각", "c107", ["c110", "c108", "c58", "c148", "c69"], "chuhaeng")],
    [("산월의 엄백호", "c133", ["c148", "c107", "c110", "c58", "c69"], "jangsa"),
     ("요술사 좌자", "c147", ["c148", "s16", "c133", "c107", "c110"], "hagik"),
     ("황천 재림", "s14", ["c148", "c147", "c133", "c107", "c110"], "eorin")],
    [("황건 최후의 결집", "s14", ["c148", "c147", "c133", "c107", "c110"], "bongsi"),
     ("황천당립", "c192", ["s14", "c173", "c147", "c148", "c133"], "chuhaeng"),
     ("창천이사", "c192", ["s14", "c173", "c148", "c147", "c133"], "jangsa")],
]


# 황건 · 도사 계열 장수 전부 (우두머리 등급 이하에서 골라 채운다)
THEME = ["c22", "c20", "c21", "c32", "c33", "c31", "c69", "c58", "c72", "c70", "c73", "c107", "c110", "c108",
         "c133", "c148", "c147", "s16", "s14", "c173", "s12", "c192", "s13"]
# 일차별 목표 = 원본 QPV × 이 값 —— 11/2 사용자: 토벌이 너무 어려워졌다 (예전엔 ×1.2 · 장비까지).
# 자동 진행 30판 측정으로 맞춤: 6일차부터 벽이었다 (6-3 승 1/29) → 6 · 7일차를 크게 낮춘다
DIFF_DAY = [0.85, 0.85, 0.95, 0.95, 0.8, 0.62, 0.58]
DIFF = 0.85


def fill(target, named, diff=DIFF):
    """우두머리 + 정한 장수로 시작, 목표에 못 미치면 같은 계열 장수(우두머리 한 등급 위까지, 같은 인물 없이)로, 남은 칸은 병졸로"""
    target = target * diff
    cards = []
    for k in named:          # 같은 인물은 한 장만 (장각 · 황천 장각이 함께 나오던 것)
        if C[k][1].split(" ")[-1] not in [C[x][1].split(" ")[-1] for x in cards]:
            cards.append(k)
    while sum(PV[k] for k in cards) > target * 1.05 and len(cards) > 1:
        cards.pop()
    top = min(8, C[named[0]][2] + 1)      # 우두머리보다 한 등급 위까지 (목표 전력에 닿게)
    used = {C[k][1].split(" ")[-1] for k in cards}
    while len(cards) < 7:
        rest = target - sum(PV[k] for k in cards) - 3 * (9 - len(cards) - 1)
        cand = [k for k in THEME if C[k][2] <= top and C[k][1].split(" ")[-1] not in used and PV[k] <= rest]
        if not cand:
            break
        k = max(cand, key=lambda x: PV[x])
        cards.append(k)
        used.add(C[k][1].split(" ")[-1])
    for pool in (GEN2, GEN1):
        i = 0
        while len(cards) < 9:
            rest = target - sum(PV[k] for k in cards)
            cand = [k for k in pool if PV[k] <= rest]
            if not cand:
                break
            cards.append(cand[i % len(cand)])
            i += 1
    return cards


out = []
print("일차-단계  이름                PV/목표(85%%)   편성")
for di, day in enumerate(STAGES):
    row = []
    for pi, (nm, boss, named, form) in enumerate(day):
        t = QPV[di][pi]
        cards = fill(t, [boss] + named, DIFF_DAY[di])
        pv = sum(PV[k] for k in cards)
        row.append(OrderedDict(name=nm, boss=boss, form=form, cards=cards, pv=pv))
        print("%d-%d  %-14s %4d/%4d  %s" % (di + 1, pi + 1, nm, pv, round(t * DIFF_DAY[di]), " ".join(C[k][1] for k in cards)))
    out.append(row)
E["quest_rosters"] = OrderedDict(
    _설명="토벌 고정 편성 —— 황건적 소탕 (11/2). [일차][단계] 마다 이름 · 우두머리(boss) · 진형 · 카드(9장까지). PV 는 원본 QPV 에 맞췄다. 원본 QUESTS 이름 대신 이 이름을 쓴다. 만든 스크립트 tools/scripts/quest_rosters.py",
    stages=out)
open(EXT, "w", encoding="utf-8", newline="\n").write(json.dumps(E, ensure_ascii=False, indent=1) + "\n")


# ── --tuned 경로.json —— tests/quest_tune.tscn 이 맞춘 편성(등급 분포 · 사기 · 장비)으로 덮는다 (11/2)
import sys
if "--tuned" in sys.argv:
    tuned = json.load(open(sys.argv[sys.argv.index("--tuned") + 1], encoding="utf-8"))
    E = json.load(open(EXT, encoding="utf-8"), object_pairs_hook=OrderedDict)
    st = []
    for row in tuned:
        st.append([OrderedDict(name=q["name"], boss=q["boss"], form=q["form"], cards=q["cards"], pv=q["pv"],
                               morale=q["morale"], equip=q["equip"], par_win=round(q["win"], 2)) for q in row])
    E["quest_rosters"] = OrderedDict(
        _설명="토벌 고정 편성 —— 황건적 소탕 (11/2). [일차][단계] 마다 이름 · 우두머리 · 진형 · 카드 · 사기 · 장비. "
              "그 단계의 플레이어(원본 QPV 무작위 덱)와 같은 등급 분포로 황건 · 도사 장수를 채우고, 플레이어가 75% 안팎 이기게 "
              "위 칸 등급 · 사기(황건의 광신) · 장비로 맞췄다 (tests/quest_tune.tscn → tools/scripts/quest_rosters.py --tuned). par_win = 그때 플레이어 승률.",
        stages=st)
    open(EXT, "w", encoding="utf-8", newline="\n").write(json.dumps(E, ensure_ascii=False, indent=1) + "\n")
    print("tuned 적용", sum(len(r) for r in st))
