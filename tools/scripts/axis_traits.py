"""특기 개편 —— 조건 × 효과, 축: 도트 · 물리 · 책략 · 공깎 · 책략깎 · 방깎 · 책방깎 · 둔화 · 혼란 + 철벽 · 인덕 · 공통 · 단체 (2026-10-30, docs/특기_조건효과_설계.md 4판).

- 일반 특기를 새 목록으로 바꾸고(traits), 인물 사다리의 옛 특기를 새 특기로 옮긴다 (MAP). 겹치면 하나로 (가장 이른 등급 · 높은 레벨).
- 병종 성격대로 새 축 특기를 하나씩 더 붙인다 (CLASS_ADD, 전설 이상에 오르는 인물만) + 몇 명은 직접 (MANUAL_ADD).
- 표적 · 와해를 쓰던 고유 특기를 다시 적는다 (GOLD_FIX).
- attr 는 이제 계열이 아니라 축 이름 (특기판 색 · 점검 스위치).

실행: python -I tools/scripts/axis_traits.py
"""
import json
from collections import OrderedDict, defaultdict

PATH = "solgukji_godot/data/passives.json"
P = json.load(open(PATH, encoding="utf-8"), object_pairs_hook=OrderedDict)
d = json.load(open("solgukji_godot/data/game.json", encoding="utf-8"))
e = json.load(open("solgukji_godot/data/cards_ext.json", encoding="utf-8"))
tiers, tag = defaultdict(set), {}
for c in d["CARDDEF"] + e["cards"]:
    if c[2] >= 3:
        p = c[1].split(" ")[-1]
        tiers[p].add(c[2])
        tag[p] = c[3]

T = P["traits"]
KEEP_GROUP = ["공세", "결속", "후원", "보급", "군주"]
KEEP = ["방진", "반격", "역습", "철옹성", "사수", "인술", "위무", "분발", "도원결의", "단량"]


def tr(desc, attr, m):
    return OrderedDict([("d", desc), ("m", m), ("attr", attr)])


NEW = OrderedDict([
    # 도트
    ("점화", tr("공격이 맞을 때 확률로 화상", "도트", {"ignite": 0.35})),
    ("화계", tr("전투가 시작되면 적 맨 앞 열에 화상", "도트", {"kindle": 1})),
    ("연소", tr("내가 건 화상이 더 뜨겁다", "도트", {"burn_amp": 0.5})),
    ("연환", tr("내가 건 화상이 탈 때 확률로 같은 열 이웃에게 번진다", "도트", {"spread": 0.4})),
    # 물리
    ("선봉", tr("첫 공격 피해가 커진다", "물리", {"opener": 0.4})),
    ("용맹", tr("치명타 확률과 피해가 오른다", "물리", {"crit": 0.1, "critd": 0.3})),
    ("투쟁", tr("병력이 절반 아래면 공격이 오른다", "물리", {"low_atk": 0.25})),
    ("기세", tr("적을 무너뜨리면 다음 공격 피해가 커진다", "물리", {"kill_amp": 0.5})),
    ("추격", tr("적을 무너뜨리면 바로 한 번 더 공격한다 (차례마다 한 번)", "물리", {"chase": 1})),
    ("휩쓸기", tr("물리 공격이 맞으면 같은 열 이웃에게도 피해", "물리", {"cleave": 0.3})),
    # 책략
    ("귀모", tr("책략 치명타 확률과 피해가 오른다", "책략", {"icrit": 0.12, "critd": 0.3})),
    ("기책", tr("병력이 절반 아래인 적에게 책략 피해가 커진다", "책략", {"int_low": 0.3})),
    ("신산", tr("기술의 책략 피해가 커진다", "책략", {"sk_amp": 0.3})),
    ("파상", tr("책략이 맞으면 같은 열 이웃에게도 피해", "책략", {"icleave": 0.25})),
    ("연계", tr("아군이 기술을 쓰면 내 기술 충전이 찬다", "책략", {"ally_sk": 0.25})),
    # 공깎 · 책략깎 · 방깎 · 책방깎 (수치, 맞힐 때마다 쌓임 —— 깎는 양 = 값 × 자기 공격(또는 책략))
    ("위축", tr("공격이 맞을 때마다 적 공격을 깎는다 (쌓임)", "공깎", {"cut_atk": 0.06})),
    ("기선", tr("전투가 시작되면 적 맨 앞 열의 공격을 크게 깎는다", "공깎", {"open_cut_atk": 0.2})),
    ("산란", tr("책략이 맞을 때마다 적 책략을 깎는다 (쌓임)", "책략깎", {"cut_int": 0.06})),
    ("이간", tr("전투가 시작되면 적 후군의 책략을 크게 깎는다", "책략깎", {"open_cut_int": 0.2})),
    ("파갑", tr("물리 공격이 맞을 때마다 적 방어를 깎는다 (쌓임)", "방깎", {"cut_def": 0.06})),
    ("쇄갑", tr("첫 물리 공격이 적 방어를 크게 깎는다", "방깎", {"first_cut": 0.2})),
    ("현혹", tr("책략이 맞을 때마다 적 책략방어를 깎는다 (쌓임)", "책방깎", {"cut_res": 0.06})),
    ("요언", tr("전투가 시작되면 적 전원의 책략방어를 깎는다", "책방깎", {"open_cut_res": 0.12})),
    # 둔화 · 혼란
    ("침수", tr("공격이 맞을 때 확률로 둔화", "둔화", {"soak": 0.3})),
    ("수계", tr("전투가 시작되면 적 전원 둔화 (1턴)", "둔화", {"open_slow": 1})),
    ("반목", tr("책략이 맞을 때 확률로 혼란", "혼란", {"sow": 0.25})),
    ("위압", tr("사기가 꺾인(60 이하) 적을 치면 확률로 혼란", "혼란", {"awe": 0.3})),
    ("반간", tr("적의 혼란이 풀릴 때 같은 열 이웃에게 한 번 옮겨 간다", "혼란", {"confuse_pass": 1})),
    # 공통
    ("약점", tr("디버프(화상 · 둔화 · 혼란 · 깎인 수치)에 걸린 적에게 피해가 커진다", "", {"weak_amp": 0.25})),
    ("명경", tr("디버프를 확률로 막아 낸다", "", {"stres": 0.35})),
    ("불굴", tr("쉽게 패주하지 않고 큰 손실에도 덜 흔들린다", "", {"rout": 0.5, "shock": 0.4})),
    # 철벽에 하나 더
    ("금강", tr("받는 물리 피해가 줄어든다", "철벽", {"dr": 0.12})),
])
MAP = {
    "화공": "연소", "화염일격": "화계", "천우": "명경",
    "수계": "약점", "수격": "수계", "제방": "명경",
    "충파": "파갑", "짓밟기": "약점", "충돌": "쇄갑", "궤멸": "기세", "호위": "명경",
    "조준": "위축", "명중": "약점", "관통": "용맹", "은폐": "명경", "연노": "위축",
    "교란": "산란", "허실": "현혹",
    "신속": "선봉", "위풍": "기선",
}
CLASS_ADD = {"창병": "휩쓸기", "기병": "추격", "궁병": "용맹", "도적": "기세",
             "책사": "파상", "유생": "연계", "술사": "요언", "모사": "이간"}
MANUAL_ADD = [("여포", "휩쓸기", 8), ("장비", "위압", 4), ("관우", "휩쓸기", 4), ("제갈량", "신산", 5), ("곽가", "기책", 5),
              ("사마의", "이간", 5), ("가후", "산란", 4), ("조조", "신산", 5), ("허저", "투쟁", 4), ("전위", "금강", 5),
              ("주유", "연환", 5), ("육손", "연환", 5), ("감녕", "기세", 5), ("하후연", "선봉", 4), ("황충", "파갑", 5)]

GOLD_FIX = {
    "손권": ("벽안", "강동을 지킨 벽안아 —— 아군 전원의 방어 · 책략방어가 오르고, 자신은 맞힐 때마다 적 공격을 깎는다",
           "공깎", "all", {"def": 0.06, "res": 0.06}, {"cut_atk": 0.06}),
    "하후연": ("질풍", "사흘에 오백 리 —— 속도가 오르고 첫 공격이 매서우며, 적을 무너뜨리면 몰아친다", "물리", None,
            {"spd": 0.1, "opener": 0.25, "chase": 1}),
    "황충": ("확삭", "늙어도 꺾이지 않는다 —— 병력이 줄수록 매섭고, 화살이 갑옷을 꿰뚫는다", "방깎", None,
           {"low_atk": 0.25, "crit": 0.08, "cut_def": 0.07}),
    "태사자": ("신의", "신의를 지킨 명궁 —— 치명타가 잦고, 적을 무너뜨리면 다음 화살이 매섭다", "물리", None,
            {"crit": 0.12, "kill_amp": 0.5}),
    "여포": ("비장", "인중여포 —— 휩쓸어 베고 갑옷을 깨뜨리며, 방어가 깎인 적은 병력 40% 아래면 베어 넘긴다", "물리", None,
           {"exec_break": 0.4, "cut_def": 0.06, "cleave": 0.3, "crit": 0.1}),
    "마초": ("금마초", "서량의 비단 마초 —— 공격 · 치명타가 오르고 맞힐 때마다 적 방어를 깎는다", "방깎", None,
           {"atk": 0.08, "crit": 0.1, "cut_def": 0.08}),
    "조운": ("일신시담", "온몸이 담덩어리 —— 첫 공격이 적 방어를 크게 깎고, 방진 중 되받아치면 또 깎으며 쉽게 꺾이지 않는다", "방깎", None,
           {"first_cut": 0.3, "opener": 0.25, "phalanx_break": 1, "phalanx": 0.15, "rout": 0.4}),
    "장료": ("위진", "위명이 강동을 떨게 했다 —— 전투가 시작되면 적 선봉의 방어를 크게 깎고 적 전원의 사기를 꺾는다", "방깎", "foe",
           {"foe_morale": 10}, {"rush": 1}),
    "초선": ("경국", "나라를 기울게 하는 미모 —— 혼란한 적이 제 편을 치고, 혼란한 적을 칠 때마다 방어를 깎는다", "혼란", "foe",
           {"foe_morale": 8}, {"turncoat": 1, "confuse_break": 1}),
}
ATTR_GOLD = {"화공": "도트", "수공": "둔화", "돌파": "방깎", "표적": "물리", "계략": "혼란"}

# 1) 일반 특기 정의 바꾸기
old_general = [n for n, t in T.items() if not t.get("unique")]
for n in old_general:
    if n not in KEEP and n not in KEEP_GROUP:
        del T[n]
for n, v in NEW.items():
    T[n] = v
for n in KEEP:
    a = T[n].get("attr", "")
    T[n]["attr"] = a  # 철벽 · 인덕 그대로
for n in KEEP_GROUP:
    T[n].pop("attr", None)

# 2) 고유 특기 축 이름 · 고치기
for n, t in T.items():
    if t.get("unique") and t.get("attr") in ATTR_GOLD:
        t["attr"] = ATTR_GOLD[t["attr"]]
gname = {}
for p, rows in P["ladder"].items():
    for r in rows:
        if T.get(r[0], {}).get("unique"):
            gname[p] = r[0]
for p, (n, desc, attr, scope, m, *rest) in GOLD_FIX.items():
    old = gname[p]
    t = OrderedDict([("d", desc)])
    if scope:
        t["m"] = m
        t["scope"] = scope
        t["self"] = rest[0]
    else:
        t["m"] = m
    t["attr"] = attr
    t["unique"] = True
    del T[old]
    T[n] = t

# 3) 사다리 옮기기
L, LV = P["ladder"], P["level"]
log = []


def add_row(p, n, frm):
    rows = L[p]
    if any(r[0] == n for r in rows):
        return False
    t_ok = [t for t in sorted(tiers[p]) if t >= frm]
    if not t_ok:
        return False
    rows.append([n, t_ok[0]])
    LV.setdefault(p, OrderedDict())[n] = OrderedDict((str(t), max(1, t - 2)) for t in t_ok)
    return True


for p, rows in L.items():
    merged = OrderedDict()
    lvl = OrderedDict()
    for r in rows:
        n = MAP.get(r[0], r[0])
        assert n in T, (p, r[0], n)
        hi = r[2] if len(r) > 2 else None
        if n in merged:
            m = merged[n]
            m[1] = min(m[1], r[1])
            m[2] = None if (m[2] is None or hi is None) else max(m[2], hi)
        else:
            merged[n] = [n, r[1], hi]
        tgt = lvl.setdefault(n, OrderedDict())
        for t, v in LV.get(p, {}).get(r[0], {}).items():
            tgt[t] = max(tgt.get(t, 0), v)
    L[p] = [[a, b] + ([c] if c is not None else []) for a, b, c in merged.values()]
    LV[p] = lvl
for p in L:
    if max(tiers[p]) >= 5 and add_row(p, CLASS_ADD[tag[p]], 4):
        log.append("%s +%s" % (p, CLASS_ADD[tag[p]]))
for p, n, frm in MANUAL_ADD:
    if add_row(p, n, frm):
        log.append("%s +%s (직접)" % (p, n))

flags = set(P["flags"])
flags -= {"focus", "spot", "chain_mark", "mark_break", "collapse", "first_break"}
flags |= {"chase", "open_slow"}
P["flags"] = sorted(flags)
for k in ["aim"]:
    P.pop(k, None)
P["dash"]["_설명"] = "(2026-10-30 와해를 파갑으로 바꿨다 —— 이 수치는 더 쓰지 않는다)"

used = {r[0] for rows in L.values() for r in rows}
for n in list(T):
    if n not in used:
        del T[n]
gen = [n for n in T if not T[n].get("unique")]
open(PATH, "w", encoding="utf-8", newline="\n").write(json.dumps(P, ensure_ascii=False, indent=1) + "\n")
print("일반 %d · 고유 %d · 더함 %d" % (len(gen), len(T) - len(gen), len(log)))
print(" ".join(gen))
print("\n".join(log[:12]), "…")
