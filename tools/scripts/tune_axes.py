"""축 특기 수치 조정 (2026-10-30 밸런스) —— 값을 한곳에 모아 passives.json 에 덮어쓴다. 여러 번 돌려도 같은 결과.

실행: python -I tools/scripts/tune_axes.py
측정: tests/attr.tscn --attr=<축> (축 끄기는 점검하는 덱 쪽만, 목표 켬 − 끔 +10~15%p)
"""
import json
from collections import OrderedDict

PATH = "solgukji_godot/data/passives.json"
P = json.load(open(PATH, encoding="utf-8"), object_pairs_hook=OrderedDict)
T = P["traits"]

TRAIT_M = {
    # 책략 (1회차 +20~45 → 2회차 +17~29 → 더 낮춤)
    "귀모": {"icrit": 0.04, "critd": 0.1},
    "기책": {"int_low": 0.1},
    "신산": {"sk_amp": 0.1},
    "파상": {"icleave": 0.08},
    "연계": {"ally_sk": 0.05},
    # 도트
    "점화": {"ignite": 0.18},
    "연소": {"burn_amp": 0.2},
    "연환": {"spread": 0.15},
    # 혼란 (+16~22 → 낮춤)
    "반목": {"sow": 0.08},
    "위압": {"awe": 0.12},
    # 인덕 (불멸 +33 → 낮춤)
    "인술": {"mend": 0.06},
    "위무": {"cheer_hit": 0.05},
    # 수치 깎기 (턴 배율로 나누지 않음) —— 공깎은 세고 방깎은 약했다
    "위축": {"cut_atk": 0.025},
    "산란": {"cut_int": 0.04},
    "파갑": {"cut_def": 0.1},
    "현혹": {"cut_res": 0.04},
    "쇄갑": {"first_cut": 0.5},
    "기선": {"open_cut_atk": 0.15},
    "이간": {"open_cut_int": 0.3},
    "요언": {"open_cut_res": 0.2},
    # 둔화
    "침수": {"soak": 0.35},
    # 철벽 —— 고급 +34 (반격이 원래 창병 되받아치기에 얹혀 셌다)
    "반격": {"counter": 0.12, "counter_hit": 0.4},
    # 사기
    "함성": {"rally_kill": 12},
    "독전": {"cheer_turn": 10},
    "결사": {"resolve": 25},
    "진정": {"steady": 35},
    "고무": {"ult_rally": 15},
}
# 고유 특기 축 —— 주 효과가 능력치인 것은 축 없음 (간웅이 도트로 잡혀 신화 도트가 부풀었다)
GOLD_ATTR = {"간웅": "", "서생": "도트", "괄목": "둔화", "무성": ""}
GOLD_M = {"백문": {"sow": 0.12, "stres": 0.3}, "인의": {"mregen": 1.0, "regen": 0.006}, "청낭": {"regen": 0.012}}
GOLD_SELF = {"청낭": {"mend": 0.06}}
GOLD_M["선술"] = {"confuse_amp": 0.2, "st_amp": 0.15}
TRAIT_M["방진"] = {"phalanx": 0.45}
for n, m in TRAIT_M.items():
    T[n]["m"] = OrderedDict(m)

for n, a in GOLD_ATTR.items():
    if a:
        T[n]["attr"] = a
    else:
        T[n].pop("attr", None)
for n, m in GOLD_M.items():
    T[n]["m"] = OrderedDict(m)
for n, m in GOLD_SELF.items():
    T[n]["self"] = OrderedDict(m)
P["virtue"]["moved"] = 0.15           # 분발 +50% → +15%
P["virtue"]["oath"] = 0.2             # 도원결의 일으키는 병력 30% → 20%
P["fire"]["burn"]["val"] = OrderedDict([("3", 0.16), ("4", 0.14), ("5", 0.085), ("6", 0.065), ("7", 0.065), ("8", 0.06)])
P["guard"]["dr"] = 0.35               # 방진 받는 물리 피해 −30% → −35%
P["water"]["weak"] = 0.2              # 둔화된 적이 받는 피해 + (새 값)
open(PATH, "w", encoding="utf-8", newline="\n").write(json.dumps(P, ensure_ascii=False, indent=1) + "\n")
print("ok")
