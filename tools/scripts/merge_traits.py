"""특기 정리 (2026-10-30, 사용자 결정) —— 일반 특기 83종 → 45종 안팎.

수치만 다르고 하는 일이 같은 특기를 하나로 합친다. 고유한 장치(방진 · 분발 · 궤멸 · 철옹성 …)가 있는 특기는 그대로 둔다.
세력 · 병종 범위였던 단체 특기(고무 · 철기 · 창진 …)는 시너지를 없애는 방향에 맞춰 '아군 전원' 단체 특기로 합친다.
한 사람만 갖는 연쇄 마무리(야습 · 속사 · 집중사격)는 고유 특기로 돌린다.

합친 특기를 여럿 가졌던 인물은 하나만 받는다: 붙는 등급은 가장 이른 것, 레벨은 등급마다 가장 높은 것.
실행: python -I tools/scripts/merge_traits.py
"""
import json
from collections import OrderedDict

PATH = "solgukji_godot/data/passives.json"
P = json.load(open(PATH, encoding="utf-8"), object_pairs_hook=OrderedDict)
T = P["traits"]

# 새 특기 (또는 남는 특기의 새 정의)
NEW = OrderedDict([
    # 계열 없는 개인 8
    ("용맹", {"d": "용맹하다 —— 치명타가 잦고 매섭다", "m": {"crit": 0.1, "critd": 0.3}}),
    ("신속", {"d": "발이 빠르다 —— 속도가 오르고 첫 공격이 매섭다", "m": {"spd": 0.08, "opener": 0.4}}),
    ("금강", {"d": "갑주가 단단하다 —— 받는 물리 피해가 줄어든다", "m": {"dr": 0.15, "def": 0.04}}),
    ("불굴", {"d": "꺾이지 않는다 —— 쉽게 패주하지 않고, 아군이 쓰러지면 분노한다", "m": {"rout": 0.5, "shock": 0.4, "avenge": 0.08}}),
    ("투쟁", None), ("위압", None),
    ("귀모", {"d": "계책이 귀신같다 —— 책략이 오르고 책략에도 치명타가 나며 기술이 빨리 찬다", "m": {"int": 0.08, "icrit": 0.1, "rate": 0.03}}),
    ("명경", {"d": "마음이 맑다 —— 상태이상과 책략에 강하고 쉽게 흔들리지 않는다", "m": {"stres": 0.4, "rout": 0.15, "idr": 0.06}}),
    # 계열 없는 단체 6 (아군 전원 · 적 전원)
    ("공세", {"d": "아군 전원 —— 공격과 책략이 오른다 · 군령 「돌격」이 세진다", "m": {"atk": 0.08, "int": 0.08}, "scope": "all", "cmd": {"assault": 0.5}}),
    ("결속", {"d": "아군 전원 —— 방어가 오르고 아군 이탈에 덜 흔들린다 · 군령 「방진」이 세진다", "m": {"def": 0.1, "rout": 0.15, "rout_loss": 0.3}, "scope": "all", "cmd": {"phalanx": 0.33}}),
    ("후원", {"d": "아군 전원 —— 책략과 책략방어가 오르고 기술이 빨리 찬다 · 군령 포인트 1을 들고 시작한다", "m": {"int": 0.06, "res": 0.08, "rate": 0.03}, "scope": "all", "cmd": {"pts_start": 1.0}}),
    ("보급", {"d": "아군 전원 —— 병력이 늘고 턴마다 조금씩 회복된다", "m": {"troop": 0.03, "regen": 0.02}, "scope": "all"}),
    ("군주", {"d": "아군 전원 —— 시작 사기가 오르고 쉽게 패주하지 않는다 · 군령 「재정비」가 세지고 군령 포인트가 빨리 찬다", "m": {"morale": 10, "rout": 0.1}, "scope": "all", "cmd": {"rally": 0.6, "pts_rate": 0.35}}),
    ("위풍", None),
    # 화공
    ("점화", {"d": "맞힐 때 확률로 불을 붙인다", "m": {"ignite": 0.35}, "attr": "화공"}),
    ("화공", {"d": "불타는 적에게 피해가 오르고, 건 화상이 더 뜨겁다", "m": {"fire_amp": 0.3, "burn_amp": 0.3}, "attr": "화공"}),
    ("화염일격", None),
    ("천우", {"d": "화상을 덜 받는다", "m": {"fire_res": 0.5}, "attr": "화공"}),
    # 수공
    ("침수", {"d": "맞힐 때 확률로 물에 잠기게 한다", "m": {"soak": 0.3}, "attr": "수공"}),
    ("수계", {"d": "물에 잠긴 적에게 피해가 오른다", "m": {"water_amp": 0.35}, "attr": "수공"}),
    ("수격", None), ("제방", None),
    # 돌파
    ("충파", None), ("짓밟기", None), ("충돌", None), ("궤멸", None), ("호위", None),
    # 표적
    ("조준", None), ("명중", None), ("관통", None), ("은폐", None),
])
# 옛 특기 -> 새 특기
MAP = {
    "용장": "용맹", "맹장": "용맹", "궁신": "용맹",
    "기신": "신속", "강행": "신속",
    "철벽": "금강",
    "비장": "불굴",
    "돌격": "투쟁", "창신": "투쟁",
    "백출": "귀모", "신산": "귀모", "후방": "귀모",
    "심지": "명경",
    "고무": "공세", "철기": "공세", "맹진": "공세", "습격": "공세", "연사": "공세", "선봉": "공세", "명성": "공세",
    "창진": "결속", "비호": "결속",
    "군략": "후원", "요술": "후원", "반계": "후원",
    "교화": "보급", "인덕": "보급",
    "통솔": "군주",
    "연환": "점화", "화선": "점화",
    "연소": "화공", "겁화": "화공", "연영": "화공",
    "우중": "천우",
    "물길": "침수", "격류": "침수",
    "수군": "수계",
    "기세": "충파",
    "연노": "조준",
}
TO_UNIQUE = ["야습", "속사", "집중사격"]

# 1) 정의 바꾸기
for n, v in NEW.items():
    if v is not None:
        T[n] = OrderedDict(v)
for n in TO_UNIQUE:
    T[n]["unique"] = True
for old in MAP:
    if old in T and old not in NEW:
        del T[old]

# 2) 사다리 · 레벨 옮기기
L, LV = P["ladder"], P["level"]
log = []
for p, rows in L.items():
    merged = OrderedDict()
    for r in rows:
        n = MAP.get(r[0], r[0])
        hi = r[2] if len(r) > 2 else None
        if n in merged:
            m = merged[n]
            m[1] = min(m[1], r[1])
            m[2] = None if (m[2] is None or hi is None) else max(m[2], hi)
            log.append("%s: %s → %s (겹침)" % (p, r[0], n))
        else:
            merged[n] = [n, r[1], hi]
            if n != r[0]:
                log.append("%s: %s → %s" % (p, r[0], n))
    L[p] = [[a, b] + ([c] if c is not None else []) for a, b, c in merged.values()]
    old = LV.get(p, {})
    new = OrderedDict()
    for on, per in old.items():
        n = MAP.get(on, on)
        tgt = new.setdefault(n, OrderedDict())
        for t, v in per.items():
            tgt[t] = max(tgt.get(t, 0), v)
    LV[p] = new

for n in T:
    assert all(MAP.get(n) is None for _ in [0]), n
used = {r[0] for rows in L.values() for r in rows}
gen = [n for n in T if n in used and not T[n].get("unique")]
uni = [n for n in T if n in used and T[n].get("unique")]
open(PATH, "w", encoding="utf-8", newline="\n").write(json.dumps(P, ensure_ascii=False, indent=1) + "\n")
print("일반 %d · 고유 %d · 옮김 %d줄" % (len(gen), len(uni), len(log)))
print(" ".join(gen))
