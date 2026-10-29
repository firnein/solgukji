"""복합 병종(초월 이상) 후보와 등급별 세력 × 병종 분포 계산.

실행: python -I tools/scripts/dual_class_plan.py  →  복합병종_후보.md
  주 병종은 그대로(상성은 주 병종만), 두 번째 병종은 시너지 수에만 1 더한다 —— 초월 · 불멸 · 신화 카드에만.
  두 번째 병종은 근거 있는 것 중 이미 많은 칸(창병 등)을 피하고 빈칸을 채우는 쪽으로 골랐다.
"""
import json
from collections import Counter

# 인물 → (두 번째 병종, 근거). 근거가 약한 인물은 넣지 않았다 (단일 병종 유지).
DUAL = {
    # 촉
    "관우": ("기병", "적토마, 오관참장 · 화웅을 벤 기마 무장"),
    "장비": ("모사", "의석엄안 —— 계략으로 엄안을 사로잡음, 장판교 허장성세(말꼬리에 나뭇가지)"),
    "조운": ("창병", "장판파 단기, 창의 명수"),
    "마초": ("창병", "금마초, 장창 기마 돌격"),
    "황충": ("창병", "정군산에서 대도로 하후연을 벰"),
    "위연": ("책사", "자오곡 기책 —— 장안 기습로를 제안"),
    "마량": ("유생", "오 · 남만 사신, 백미 학자"),
    "방통": ("모사", "연환계 —— 조조를 속인 계략"),
    "강유": ("모사", "종회에게 거짓 항복해 촉 부흥을 꾀한 계략"),
    "제갈량": ("술사", "칠성단의 동남풍, 팔진도"),
    "유비": ("기병", "적로마로 단계를 뛰어넘음"),
    "법정": ("모사", "원한은 반드시 갚음, 정군산 계략"),
    "서서": ("도적", "젊은 날 격검으로 원수를 갚은 협객"),
    # 위
    "조인": ("궁병", "정사 '少好弓馬弋獵' —— 활과 사냥을 즐김"),
    "방덕": ("기병", "백마장군"),
    "장료": ("도적", "합비 —— 밤새 모은 결사대 800으로 기습"),
    "장합": ("책사", "정사 '識變數，善處營陳' —— 진형에 능함"),
    "하후연": ("기병", "三日五百 —— 질풍 기병"),
    "곽가": ("술사", "십승십패 · 손책 죽음 예언 —— 앞일을 내다봄"),
    "종회": ("모사", "필적 위조, 반란"),
    "조조": ("기병", "절영을 타고 직접 지휘, 횡삭부시"),
    "등애": ("도적", "음평 기습 —— 모포를 두르고 벼랑을 굴러 내려감"),
    # 오
    "손책": ("창병", "소패왕의 창"),
    "태사자": ("창병", "단극, 신정산 일기토"),
    "정보": ("창병", "철척사모"),
    "손권": ("기병", "소요진 —— 말을 몰아 끊긴 다리를 뛰어넘음"),
    "황개": ("모사", "고육지계"),
    "여몽": ("모사", "백의도강 —— 상인으로 위장한 기만책"),
    "감녕": ("기병", "백기겁영 —— 기병 100으로 조조 진영 야습"),
    "육손": ("모사", "이릉 —— 때를 기다린 화공, 관우를 속인 서신"),
    "주유": ("모사", "장간을 이용한 반간계"),
    "노숙": ("책사", "천하삼분책(榻上策)"),
    # 군웅
    "동탁": ("궁병", "정사 —— 활집 둘을 차고 말 위에서 좌우로 쏨"),
    "마등": ("창병", "서량 창기병"),
    "공손찬": ("궁병", "백마의종 —— 백마 기마 궁수대"),
    "여포": ("궁병", "원문사극 —— 활로 극의 가지를 맞힘"),
    "좌자": ("도적", "변신 · 둔갑으로 조조를 농락"),
    "화타": ("유생", "의술 —— 병을 고치는 인술"),
}
NAME = {("기병", "창병"): "창기병", ("기병", "궁병"): "궁기병", ("궁병", "창병"): "극궁병", ("창병", "기병"): "창기병",
        ("창병", "궁병"): "창궁병", ("궁병", "기병"): "궁기병"}

d = json.load(open("solgukji_godot/data/game.json", encoding="utf-8"))
e = json.load(open("solgukji_godot/data/cards_ext.json", encoding="utf-8"))
T = {int(k): v["n"] for k, v in d["TIER"].items()}
cards = [c for c in d["CARDDEF"] + e["cards"] if c[2] >= 3]
ORDER = ["창병", "기병", "궁병", "도적", "책사", "유생", "술사", "모사"]
F = ["촉", "위", "오", "군"]
FN = {"군": "군웅"}
person = lambda c: c[1].split(" ")[-1]
for p in DUAL:
    assert any(person(c) == p and c[2] >= 6 for c in cards), p
    assert DUAL[p][0] != next(c[3] for c in cards if person(c) == p), p


def tags(c, dual):
    t = [c[3]]
    if dual and c[2] >= 6 and person(c) in DUAL:
        t.append(DUAL[person(c)][0])
    return t


def table(t, dual):
    cs = [c for c in cards if c[2] == t]
    cnt = {f: Counter() for f in F}
    for c in cs:
        for g in tags(c, dual):
            cnt[c[4]][g] += 1
    return cnt


def stats(t, dual):
    cnt = table(t, dual)
    hot = sum(1 for f in F for o in ORDER if cnt[f][o] >= 4)
    hole = sum(1 for f in F for o in ORDER if cnt[f][o] == 0)
    reach5 = sum(1 for f in F for o in ORDER if cnt[f][o] >= 5)
    return hot, hole, reach5


L = ["# 복합 병종 후보와 분포 (초월 이상)", "",
     "`tools/scripts/dual_class_plan.py` 로 만든다. 규칙 가정:",
     "- 초월 · 불멸 · 신화 카드에만 두 번째 병종을 붙인다. 고급 · 희귀 · 전설은 그대로다.",
     "- 시너지는 두 병종 모두에 1씩 센다.",
     "- 상성은 주 병종만 쓴다.",
     "", "## 후보 (%d명)" % len(DUAL), "", "| 장수 | 세력 | 주 병종 → 복합 | 초월 이상 카드 | 근거 |", "|---|---|---|---|---|"]
for p, (g, why) in sorted(DUAL.items(), key=lambda x: (F.index(next(c[4] for c in cards if person(c) == x[0])), x[0])):
    cs = [c for c in cards if person(c) == p and c[2] >= 6]
    main = cs[0][3]
    nm = NAME.get((main, g), "")
    L.append("| %s | %s | %s → %s + %s%s | %s | %s |" % (p, FN.get(cs[0][4], cs[0][4]), main, main, g, " (%s)" % nm if nm else "",
                                                       " · ".join("%s(%s)" % (c[1], T[c[2]]) for c in sorted(cs, key=lambda c: c[2])), why))
single = sorted({person(c) for c in cards if c[2] >= 6} - set(DUAL))
L += ["", "**단일 병종으로 두는 초월 이상 장수 (%d명):** %s" % (len(single), " · ".join(single)), "",
      "## 등급별 요약 (전 → 후)", "",
      "- 쏠림: 한 세력에 같은 병종이 4장 이상인 칸 수.",
      "- 5장 이상: 같은 세력만으로 병종 시너지 최대 단계를 켤 수 있는 칸 수.",
      "- 빈칸: 0장인 세력 × 병종 칸 수 (32칸 중).", "",
      "| 등급 | 쏠림 칸 | 5장 이상 칸 | 빈칸 |", "|---|---|---|---|"]
for t in (6, 7, 8):
    a, b = stats(t, False), stats(t, True)
    L.append("| %s | %d → %d | %d → %d | %d → %d |" % (T[t], a[0], b[0], a[2], b[2], a[1], b[1]))
for t in (6, 7, 8):
    L += ["", "### %s —— 세력 × 병종 (복합 반영, 괄호 = 늘어난 수)" % T[t], "", "| 세력 | " + " | ".join(ORDER) + " |", "|---|" + "---|" * len(ORDER)]
    a, b = table(t, False), table(t, True)
    for f in F:
        cells = []
        for o in ORDER:
            n, plus = b[f][o], b[f][o] - a[f][o]
            s = ("**%d**" % n if n >= 4 else ("·" if n == 0 else str(n))) + (" (+%d)" % plus if plus else "")
            cells.append(s)
        L.append("| %s | %s |" % (FN.get(f, f), " | ".join(cells)))
open("복합병종_후보.md", "w", encoding="utf-8", newline="\n").write("\n".join(L) + "\n")
for t in (6, 7, 8):
    print(T[t], "쏠림/5장/빈칸", stats(t, False), "→", stats(t, True))
