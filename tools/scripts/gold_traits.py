"""금색(고유) 특기 —— 인물 정체성 위주, 인물마다 최대 1개 (2026-10-30, 사용자 결정. 삼국지14 금색 개성 참고).

- 불멸 · 신화에 오르는 인물 42명 + 방통이 금색 특기 하나씩을 갖는다.
- 예전 고유 특기(수엄칠군 · 칠진칠출 · 적벽 …)의 장치는 그 인물의 금색 특기 안으로 들어간다 (self).
- 단체(아군 전원 · 적 전원) 효과가 있는 금색은 scope + m, 주인에게만 붙는 장치는 self.
- 붙는 등급: 예전 고유 특기의 가장 이른 등급, 없으면 불멸(불멸 카드가 없으면 신화). 레벨: 전설 4 · 초월 5 · 불멸 7 · 신화 9.

실행: python -I tools/scripts/gold_traits.py
"""
import json
from collections import OrderedDict, defaultdict

PATH = "solgukji_godot/data/passives.json"
P = json.load(open(PATH, encoding="utf-8"), object_pairs_hook=OrderedDict)
d = json.load(open("solgukji_godot/data/game.json", encoding="utf-8"))
e = json.load(open("solgukji_godot/data/cards_ext.json", encoding="utf-8"))
tiers = defaultdict(set)
for c in d["CARDDEF"] + e["cards"]:
    if c[2] >= 3:
        tiers[c[1].split(" ")[-1]].add(c[2])

# 인물: (이름, 설명, 계열, scope 또는 None, m(단체 또는 개인), self(주인 장치) 또는 None)
G = {
    "관우": ("무성", "무신이라 불린 위엄 —— 아군 전원의 공격 · 방어가 오르고, 자신의 수공은 칠군을 잠근다", "수공", "all", {"atk": 0.08, "def": 0.08}, {"drown": 1, "crit": 0.08}),
    "장비": ("만인적", "장판교의 일갈 —— 적 전원의 시작 사기가 꺾이고, 자신은 치명타가 잦고 쉽게 물러서지 않는다", "", "foe", {"foe_morale": 15}, {"crit": 0.1, "rout": 0.4}),
    "조운": ("일신시담", "온몸이 담덩어리 —— 첫 공격은 반드시 와해, 방진 중 되받아치면 적이 와해되고 쉽게 꺾이지 않는다", "돌파", None, {"first_break": 1, "opener": 0.25, "phalanx_break": 1, "phalanx": 0.15, "rout": 0.4}, None),
    "여포": ("비장", "인중여포 —— 와해된 적을 베어 넘기고, 원문에 꽂힌 화극을 맞히듯 표식된 적을 와해시킨다", "돌파", None, {"exec_break": 0.4, "mark_break": 1, "aim": 0.15, "crit": 0.1, "spd": 0.06}, None),
    "제갈량": ("와룡", "와룡의 지략 —— 아군의 불길이 거세지고 오래 타며, 자신은 박망파의 불을 놓고 혼란한 적을 불태운다", "화공", "all", {"ignite": 0.08, "burn_dur": 1}, {"kindle": 1, "confuse_burn": 1, "st_amp": 0.25, "stres": 0.4}),
    "주유": ("화신", "적벽의 화신 —— 아군이 불타는 적에게 더 큰 피해를 주고 불에 강하며, 자신은 화선으로 불을 지르고 물과 불을 함께 쓴다", "화공", "all", {"fire_amp": 0.15, "fire_res": 0.3}, {"kindle": 1, "steam": 1}),
    "조조": ("간웅", "치세의 능신, 난세의 간웅 —— 아군 전원의 공격 · 책략 · 방어가 오르고, 자신은 오소의 군량을 불태운다", "화공", "all", {"atk": 0.06, "int": 0.06, "def": 0.05}, {"scorch": 1}),
    "유비": ("인의", "인덕의 군주 —— 아군 전원의 사기와 병력이 턴마다 회복되고, 분발한 아군은 방진을 친다", "인덕", "all", {"mregen": 1.5, "regen": 0.01}, {"moved_phalanx": 1}),
    "손권": ("벽안", "강동을 지킨 벽안아 —— 아군이 표식된 적에게 더 큰 피해를 주고, 아군의 원거리 공격이 표식된 적을 노린다", "표적", "all", {"mark_amp": 0.12, "morale": 5}, {"focus": 1}),
    "손책": ("소패왕", "강동의 소패왕 —— 공격과 치명타가 오르고 첫 공격이 매섭다", "", None, {"atk": 0.1, "crit": 0.1, "opener": 0.3}, None),
    "장료": ("위진", "위명이 강동을 떨게 했다 —— 적 전원의 시작 사기가 꺾이고, 전투가 시작되면 적 선봉 전체를 와해시킨다", "돌파", "foe", {"foe_morale": 10}, {"rush": 1}),
    "감녕": ("금범적", "비단 돛의 수적 —— 밤을 틈타 기습하고 첫 공격이 매섭다", "화공", None, {"night": 1, "opener": 0.3, "spd": 0.06}, None),
    "여몽": ("괄목", "괄목상대 —— 흰옷으로 강을 건너 적을 물에 잠그고, 책략이 오른다", "수공", None, {"tide": 1, "int": 0.06, "atk": 0.06}, None),
    "육손": ("서생", "백면서생의 대도독 —— 칠백 리 영채를 불태우고 책략이 오른다", "화공", None, {"blaze": 1, "int": 0.08}, None),
    "하후연": ("질풍", "사흘에 오백 리 —— 속도가 오르고, 적 후군을 먼저 표식한다", "표적", None, {"spot": 1, "spd": 0.1}, None),
    "황충": ("확삭", "늙어도 꺾이지 않는다 —— 백 보 밖을 꿰뚫어 표식이 이어지고, 병력이 줄수록 매섭다", "표적", None, {"chain_mark": 1, "low_atk": 0.25, "crit": 0.06}, None),
    "초선": ("경국", "나라를 기울게 하는 미모 —— 적 전원의 시작 사기가 꺾이고, 혼란한 적이 제 편을 치며 혼란이 방어를 무너뜨린다", "계략", "foe", {"foe_morale": 8}, {"turncoat": 1, "confuse_break": 1}),
    "방통": ("봉추", "봉추의 연환 —— 아군이 건 화상이 이웃 부대로 번지고, 자신은 책략이 오른다", "화공", "all", {"spread": 0.3}, {"int": 0.06}),
    "하후돈": ("독안", "눈알을 삼킨 맹장 —— 쉽게 꺾이지 않고 큰 손실에도 흔들리지 않으며 방어가 오른다", "", None, {"rout": 0.5, "shock": 0.5, "def": 0.08}, None),
    "사마의": ("낭고", "이리처럼 돌아보는 자 —— 상태이상과 책략에 강하고 책략이 오른다", "", None, {"stres": 0.4, "idr": 0.1, "int": 0.06}, None),
    "곽가": ("귀재", "하늘이 낸 기재 —— 기술이 빨리 차고 책략 치명타가 잦다", "", None, {"rate": 0.06, "icrit": 0.12}, None),
    "가후": ("독사", "한 마디로 나라를 뒤집는 독계 —— 거는 상태이상이 세지고 적 책략방어를 무시한다", "", None, {"st_amp": 0.3, "rpierce": 0.1}, None),
    "강유": ("담대", "담이 달걀만 했다 —— 병력이 줄수록 매섭고 책략이 오른다", "", None, {"low_atk": 0.25, "int": 0.08}, None),
    "노숙": ("대의", "천하삼분을 먼저 본 대의 —— 아군 전원의 책략방어와 사기가 오른다", "", "all", {"res": 0.08, "morale": 8}, None),
    "동탁": ("폭군", "낙양을 불태운 폭정 —— 적 전원의 시작 사기가 크게 꺾이고, 자신은 공격이 오른다", "", "foe", {"foe_morale": 12}, {"atk": 0.1}),
    "마초": ("금마초", "서량의 비단 마초 —— 공격 · 치명타가 오르고 확률로 적을 와해시킨다", "돌파", None, {"atk": 0.08, "crit": 0.1, "shatter": 0.12}, None),
    "법정": ("정군", "정군산의 계책 —— 책략 치명타가 잦고 적 책략방어를 무시한다", "", None, {"icrit": 0.15, "rpierce": 0.15}, None),
    "사마휘": ("수경", "인재를 알아보는 거울 —— 아군 전원의 책략과 책략방어가 오른다", "", "all", {"int": 0.08, "res": 0.06}, None),
    "서서": ("간파", "팔문금쇄를 꿰뚫어 본 눈 —— 아군 전원이 상태이상에 강해지고 책략방어가 오른다", "", "all", {"stres": 0.25, "res": 0.05}, None),
    "서황": ("엄정", "주아부의 군율 —— 공격 · 방어가 오르고 쉽게 패주하지 않는다", "", None, {"atk": 0.06, "def": 0.08, "rout": 0.3}, None),
    "순욱": ("왕좌", "왕을 보좌할 재목 —— 아군 전원의 책략 · 책략방어가 오르고 기술이 빨리 찬다", "", "all", {"int": 0.06, "res": 0.06, "rate": 0.02}, None),
    "원소": ("명문", "사세삼공의 명문 —— 아군 전원의 병력과 시작 사기가 오른다", "", "all", {"troop": 0.04, "morale": 6}, None),
    "위연": ("반골", "뒤통수에 반골 —— 첫 공격이 매섭고 치명타가 잦다", "", None, {"opener": 0.4, "crit": 0.08}, None),
    "장각": ("황천", "황천의 도 —— 아군 전원의 병력과 사기가 턴마다 회복된다", "", "all", {"regen": 0.02, "mregen": 1.0}, {"st_amp": 0.2}),
    "장로": ("오두미", "오두미도의 교주 —— 아군 전원의 병력이 턴마다 조금씩 회복되고 책략방어가 오른다", "", "all", {"regen": 0.015, "res": 0.05}, None),
    "장합": ("교변", "임기응변의 명장 —— 속도가 오르고 받는 물리 피해가 줄며 첫 공격이 매섭다", "", None, {"spd": 0.08, "dr": 0.08, "opener": 0.2}, None),
    "전위": ("악래", "고대의 악래 —— 받는 물리 피해가 줄고 자주 되받아친다", "철벽", None, {"dr": 0.12, "counter": 0.2}, None),
    "조인": ("번성", "번성을 지킨 장수 —— 받는 물리 피해가 줄고 방진을 자주 친다", "철벽", None, {"dr": 0.1, "phalanx": 0.2}, None),
    "좌자": ("선술", "신선의 술법 —— 혼란 · 봉인된 적에게 피해가 오르고 거는 상태이상이 세진다", "계략", None, {"confuse_amp": 0.3, "st_amp": 0.2}, None),
    "진궁": ("백문", "백문루의 결의 —— 확률로 적을 혼란에 빠뜨리고 상태이상에 강하다", "계략", None, {"sow": 0.2, "stres": 0.3}, None),
    "태사자": ("신의", "신의를 지킨 명궁 —— 치명타가 잦고 확률로 표식을 건다", "표적", None, {"crit": 0.12, "aim": 0.12}, None),
    "허저": ("호치", "호랑이 같은 바보 —— 병력이 줄수록 매섭고 받는 물리 피해가 준다", "", None, {"low_atk": 0.3, "dr": 0.08}, None),
    "화타": ("청낭", "청낭서의 의술 —— 아군 전원의 병력이 턴마다 회복되고, 자신은 가장 지친 아군을 치료한다", "인덕", "all", {"regen": 0.02}, {"mend": 0.1}),
}

T, L, LV = P["traits"], P["ladder"], P["level"]
old_unique = {n for n, t in T.items() if t.get("unique")}
for n in list(old_unique):
    del T[n]
names = set()
for p, (n, desc, attr, scope, m, self_) in G.items():
    assert n not in T and n not in names, (p, n)
    names.add(n)
    t = OrderedDict([("d", desc), ("m", m)])
    if attr:
        t["attr"] = attr
    if scope:
        t["scope"] = scope
    if self_:
        t["self"] = self_
    t["unique"] = True
    T[n] = t
LVMAP = {3: 2, 4: 3, 5: 4, 6: 5, 7: 7, 8: 9}
for p, rows in L.items():
    olds = [r for r in rows if r[0] in old_unique]
    L[p] = [r for r in rows if r[0] not in old_unique]
    for on in [r[0] for r in olds]:
        LV.get(p, {}).pop(on, None)
    if p not in G:
        assert not olds, p
        continue
    n = G[p][0]
    frm = min([r[1] for r in olds] + [7 if 7 in tiers[p] else 8])
    L[p].append([n, frm])
    LV.setdefault(p, OrderedDict())[n] = OrderedDict((str(t), LVMAP[t]) for t in sorted(tiers[p]) if t >= frm)
for p in G:
    assert p in L, p
P["_고유"] = ("traits 의 unique: true = 금색(고유) 특기 —— 인물 정체성 위주, 인물마다 최대 1개 (삼국지14 금색 개성 참고). "
             "scope 가 있으면 m 은 단체 효과, self 는 주인에게만 붙는 장치. 나머지는 일반 특기 —— 특기판에는 일반 특기만 모두 늘어놓는다.")
open(PATH, "w", encoding="utf-8", newline="\n").write(json.dumps(P, ensure_ascii=False, indent=1) + "\n")
print("금색", len(G), "· 지운 예전 고유", len(old_unique))
