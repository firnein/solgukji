"""특기 수치 전수 조사 (11/13, 사용자: "특기 수치가 3,3,3,3 같이 성의 없게 되어 있는 것들").

입력은 Godot 덤프 (카드마다 화면에 보이는 특기 이름 · 레벨 · 수치 문구 mt · 위세 문구):
  godot --headless --path solgukji_godot res://tests/trait_values.tscn -- --out=D:/x.json
  python -I tools/scripts/trait_value_audit.py D:/x.json            (표를 마크다운으로 찍는다)

찾는 것
 1) 한 카드 안에서 일반 특기 셋 이상이 같은 레벨 (화면 '귀모3 후원3 반목3 이간3')
 2) 같은 인물 · 같은 특기가 등급(레벨)이 올라도 화면 수치가 그대로 (예: 결사 사기+24 → +24)
 3) 여러 특기의 정의 수치 m 이 통째로 같다 (복붙)
 4) 위세 · 고유 특기의 수치 문구가 다른 장수와 통째로 같다
"""
import json
import sys
from collections import Counter, defaultdict

PSV = json.load(open("solgukji_godot/data/passives.json", encoding="utf-8"))


def load(path):
    return json.load(open(path, encoding="utf-8"))


def same_level_cards(cards, need=3):
    """[(카드, 레벨, 그 레벨인 특기들)] —— 일반(비고유) 특기 need 개 이상이 같은 레벨"""
    out = []
    for c in cards:
        tl = [t for t in c["traits"] if not t["unique"]]
        cnt = Counter(t["lv"] for t in tl)
        for lv, n in cnt.items():
            if n >= need:
                out.append((c, lv, [t["name"] for t in tl if t["lv"] == lv]))
    return out


def flat_across_tiers(cards):
    """같은 인물 · 같은 특기의 화면 수치가 등급 둘 이상에서 똑같은 것 (수치 문구가 빈 특기는 뺀다)"""
    by = defaultdict(list)
    for c in cards:
        for t in c["traits"]:
            if t["mt"]:
                by[(c["person"], t["name"])].append((c["tier"], t["lv"], t["mt"]))
    out = []
    for k, v in sorted(by.items()):
        v.sort()
        if len(v) >= 2 and len({x[2] for x in v}) == 1 and len({x[1] for x in v}) > 1:
            out.append((k, v))
    return out


def copied_defs():
    """정의 수치 m(+ self) 가 통째로 같은 특기 묶음"""
    by = defaultdict(list)
    for n, t in PSV["traits"].items():
        key = json.dumps([t["m"], t.get("self", {})], sort_keys=True)
        by[key].append(n)
    return [v for v in by.values() if len(v) > 1]


def copied_text(cards):
    """위세 · 고유 특기 문구가 다른 장수와 같은 것"""
    au = defaultdict(set)
    un = defaultdict(set)
    for c in cards:
        if c["aura"]:
            au[c["aura"].split(": ", 1)[-1]].add(c["name"])
        for t in c["traits"]:
            if t["unique"] and t["mt"]:
                un[t["mt"]].add(c["person"] + "·" + t["name"])
    return [(k, sorted(v)) for k, v in au.items() if len(v) > 1], [(k, sorted(v)) for k, v in un.items() if len({x.split("·")[1] for x in v}) > 1]


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    cards = load(sys.argv[1])
    cards.sort(key=lambda c: (c["tier"], c["person"]))
    sl = same_level_cards(cards)
    print("## 1) 한 카드에 같은 레벨 일반 특기 셋 이상 —— %d곳 / 카드 %d장\n" % (len(sl), len(cards)))
    print("| 등급 | 카드 | 레벨 | 특기 |\n|---|---|---|---|")
    for c, lv, ns in sl:
        print("| %d | %s | %d | %s |" % (c["tier"], c["name"], lv, " · ".join(ns)))
    fl = flat_across_tiers(cards)
    print("\n## 2) 레벨이 올라도 화면 수치 그대로 —— %d건\n" % len(fl))
    print("| 인물 | 특기 | 등급:레벨 | 수치 |\n|---|---|---|---|")
    for (p, n), v in fl:
        print("| %s | %s | %s | %s |" % (p, n, " · ".join("%d:%d" % (x[0], x[1]) for x in v), v[0][2]))
    cd = copied_defs()
    print("\n## 3) 정의 수치가 통째로 같은 특기 —— %d묶음\n" % len(cd))
    for v in cd:
        print("- " + " · ".join(v) + " : " + json.dumps(PSV["traits"][v[0]]["m"], ensure_ascii=False))
    au, un = copied_text(cards)
    print("\n## 4) 위세 문구가 같은 카드 %d묶음 · 다른 고유 특기끼리 문구가 같은 것 %d묶음\n" % (len(au), len(un)))
    for k, v in au + un:
        print("- %s : %s" % (k, " · ".join(v)))


if __name__ == "__main__":
    main()
