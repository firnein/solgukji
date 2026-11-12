"""특기 레벨 · 계열 레벨 곡선 재조정 (11/13, 사용자: "특기 수치가 3,3,3,3 같이 성의 없게 되어 있는 것들 —— 한번 재조정").

전수 조사(tools/scripts/trait_value_audit.py)에서 나온 두 원인을 고친다.
 1) 한 카드에 일반 특기 셋 이상이 같은 레벨 ('귀모3 후원3 반목3 이간3') —— 207장 중 125곳.
    assign_trait_levels.py 의 '바탕 = 등급 - 2' 가 대표 특기 말고는 거의 다 같은 값을 주고, 표에 없는 인물(lines.json 사다리 43명 ·
    ladder_from 새 인물)은 전부 기본값이라 생겼다.
    → 같은 레벨에 셋 이상 몰린 묶음에서 '먼저 익힌 · 드문 · 사다리 앞' 특기를 한 칸 올리고 반대 끝을 한 칸 내린다 (레벨 합은 그대로,
      한 레벨에 둘까지). 고급(3)은 3을 넘지 않고 1 아래로 못 내려가니 그때만 올리기만 한다.
 2) 계열 특기 레벨 곡선 level_scale_attr 가 0.88 ~ 1.12 로 거의 평평해서 레벨이 2~3 올라도 화면 수치가 그대로 (결사 사기+24 → +24).
    → 일반 특기 곡선 level_scale 과 같은 모양(5 = 1.0 으로 나눔 —— 0.65 · 0.74 · 0.82 · 0.91 · 1 · 1.08 · 1.18 · 1.29 · 1.47)으로. 등급 전체 세기는 축 × 등급 배율 axis_tier_mul 에서 되돌린다:
      (축, 등급)마다 실제 카드들의 '옛 레벨 × 옛 곡선' 평균 / '새 레벨 × 새 곡선' 평균을 곱한다 —— 등급 평균 세기는 그대로, 등급 안에서
      레벨 차이만 커진다. 특기에 tier_mul 이 있으면(현혹 · 요언) 그 표를 같은 방식으로.

입력은 고치기 전 덤프 (tests/trait_values.tscn). 한 번만 돌린다 (곡선이 이미 바뀌었으면 2) 는 건너뛴다).
  godot --headless --path solgukji_godot res://tests/trait_values.tscn -- --out=D:/before.json
  python -I tools/scripts/spread_trait_levels.py D:/before.json
"""
import json
import sys
from collections import OrderedDict, defaultdict, Counter

PATH = "solgukji_godot/data/passives.json"
P = json.load(open(PATH, encoding="utf-8"), object_pairs_hook=OrderedDict)
LINES = json.load(open("solgukji_godot/data/lines.json", encoding="utf-8"))
OLD_ATTR = {int(k): v for k, v in P["level_scale_attr"].items()}
LV_SCALE = {int(k): v for k, v in P["level_scale"].items()}
NEW_ATTR = {lv: round(LV_SCALE[lv] / LV_SCALE[5], 3) for lv in range(1, 10)}      # 일반 특기 곡선과 같은 모양 (5 = 1.0)


def rank_info(cards):
    """(인물, 특기) -> 처음 붙는 등급 · 특기 -> 가진 인물 수 · (인물, 특기) -> 등급별 레벨"""
    start = {}
    holders = defaultdict(set)
    by_tier = defaultdict(dict)      # (인물, 특기) -> {등급: 레벨}
    for c in cards:
        for t in c["traits"]:
            key = (c["person"], t["name"])
            start[key] = min(start.get(key, 99), c["tier"])
            holders[t["name"]].add(c["person"])
            by_tier[key][c["tier"]] = t["lv"]
    return start, {n: len(v) for n, v in holders.items()}, by_tier


def spread(c, start, nhold, by_tier):
    """카드 하나 —— {특기: 새 레벨} (바뀐 것만). 같은 인물의 아래 등급보다 낮아지거나 위 등급보다 높아지게는 옮기지 않는다"""
    tl = [t for t in c["traits"] if not t["unique"]]
    if len(tl) < 3:
        return {}
    order = {t["name"]: i for i, t in enumerate(tl)}
    # 대표성: 먼저 익힘 → 드묾 → 사다리 앞
    rank = sorted(order, key=lambda n: (start[(c["person"], n)], nhold[n], order[n]))
    pos = {n: i for i, n in enumerate(rank)}
    lv = {t["name"]: t["lv"] for t in tl}
    cap = 3 if c["tier"] == 3 else 9
    for _ in range(40):
        cnt = Counter(lv.values())
        crowd = [v for v, n in cnt.items() if n >= 3]
        if not crowd:
            break
        v = max(crowd, key=lambda x: (cnt[x], -x))
        at = sorted([n for n in lv if lv[n] == v], key=lambda n: pos[n])
        up = v + 1 <= cap and cnt.get(v + 1, 0) < 2
        dn = v - 1 >= 1 and cnt.get(v - 1, 0) < 2
        if not up and not dn:      # 이웃 레벨도 찼다 —— 이웃이 비게 바깥으로 밀 수 있으면 다음 바퀴에, 아니면 그만
            up = v + 1 <= cap
            dn = v - 1 >= 1
            if not (up and dn):
                break
        bt = lambda n: by_tier[(c["person"], n)]
        ups = [n for n in at if v + 1 <= min([x for t2, x in bt(n).items() if t2 > c["tier"]] or [9])]
        dns = [n for n in at if v - 1 >= max([x for t2, x in bt(n).items() if t2 < c["tier"]] or [1])]
        if up and ups:
            lv[ups[0]] = v + 1
        if dn and dns and lv[dns[-1]] == v:      # 방금 올린 특기는 다시 내리지 않는다
            lv[dns[-1]] = v - 1
        if not (up and ups) and not (dn and dns):
            break
    return {n: lv[n] for n in lv if lv[n] != {t["name"]: t["lv"] for t in tl}[n]}


def write_key(c, name):
    """레벨을 적을 자리 —— 불멸 역할 재배치로 붙은 특기는 뺀 특기의 '7' 칸을 쓴다 (db._apply_roles)"""
    p = c["person"]
    if c["tier"] == 7:
        for drop, add in P.get("role", {}).get("immortal_drop", {}).get(p, []):
            if add == name:
                return p, drop
    return p, name


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    cards = json.load(open(sys.argv[1], encoding="utf-8"))
    start, nhold, by_tier = rank_info(cards)
    new_lv = {}      # (카드 id, 특기) -> 새 레벨
    changed = []
    for c in sorted(cards, key=lambda c: (c["tier"], c["person"])):
        for n, v in spread(c, start, nhold, by_tier).items():
            new_lv[(c["id"], n)] = v
            old = next(t["lv"] for t in c["traits"] if t["name"] == n)
            p, key = write_key(c, n)
            P["level"].setdefault(p, OrderedDict()).setdefault(key, OrderedDict())[str(c["tier"])] = v
            changed.append((c, n, old, v))
    # ladder_from 새 인물은 원래 인물 표를 함께 쓴다 —— 원래 인물 칸을 고친 것이 번지지 않게 카드의 레벨을 모두 자기 표에 적는다
    # (자기 표가 있으면 db.gd 가 원래 인물 표 위에 덮는다, 11/13)
    for c in cards:
        if c["person"] not in LINES.get("ladder_from", {}):
            continue
        for t in c["traits"]:
            if t["unique"]:
                continue
            p, key = write_key(c, t["name"])
            P["level"].setdefault(p, OrderedDict()).setdefault(key, OrderedDict())[str(c["tier"])] = new_lv.get((c["id"], t["name"]), t["lv"])

    # 같은 인물 · 같은 특기 레벨이 등급이 올라 줄면 알린다
    eff = defaultdict(dict)
    for c in cards:
        for t in c["traits"]:
            if not t["unique"]:
                eff[(c["person"], t["name"])][c["tier"]] = new_lv.get((c["id"], t["name"]), t["lv"])
    bad = [(k, v) for k, v in eff.items() if any(v[a] > v[b] for a in v for b in v if a < b)]

    # 2) 계열 곡선 + 축 × 등급 배율 되돌리기
    comp = []
    if abs(OLD_ATTR[1] - NEW_ATTR[1]) > 1e-6:
        so = defaultdict(float)
        sn = defaultdict(float)
        for c in cards:
            for t in c["traits"]:
                if not t["attr"]:
                    continue
                tdef = P["traits"][t["name"]]
                key = ("tm:" + t["name"]) if "tier_mul" in tdef else t["attr"]
                nl = new_lv.get((c["id"], t["name"]), t["lv"])
                so[(key, c["tier"])] += OLD_ATTR[t["lv"]]
                sn[(key, c["tier"])] += NEW_ATTR[nl]
        new_axis = {key for key, _ in so if not key.startswith("tm:") and key not in P["axis_tier_mul"]}
        g_axis = {key: sum(o for (k2, _), o in so.items() if k2 == key) / sum(n for (k2, _), n in sn.items() if k2 == key) for key in new_axis}
        for (key, tier), o in sorted(so.items()):
            f = o / sn[(key, tier)]
            if key in new_axis:      # 등급 표가 없던 축(사기)은 레벨만으로 등급이 커지던 축 —— 등급마다 다 되돌리면 등급 사이 성장이 사라진다(함성3 → 함성5 가 +12 → +12). 축 전체 배율과 반씩(기하평균)
                f = (f * g_axis[key]) ** 0.5
            if key.startswith("tm:"):
                tab = P["traits"][key[3:]]["tier_mul"]
            else:
                tab = P["axis_tier_mul"].setdefault(key, OrderedDict((str(x), 1.0) for x in range(3, 9)))
            before = float(tab.get(str(tier), 1.0))
            tab[str(tier)] = round(before * f, 3)
            comp.append((key, tier, before, tab[str(tier)]))
        P["level_scale_attr"] = OrderedDict((str(lv), NEW_ATTR[lv]) for lv in range(1, 10))
        P["_axis_tier_mul"] = P["_axis_tier_mul"].rstrip() + (" 11/13 계열 레벨 곡선을 일반 특기 곡선과 같은 모양으로 가파르게 하며 (축, 등급)마다 실제 카드 평균 세기가 그대로이게 이 배율을 되돌려 곱했다"
                                                            " (tools/scripts/spread_trait_levels.py, 사기 축은 이때 새로 생김).")

    P["_레벨"] = P["_레벨"].rstrip() + (" 11/13 한 카드에 같은 레벨이 셋 이상 몰린 묶음을 한 칸씩 벌렸다 (레벨 합 그대로, tools/scripts/spread_trait_levels.py)."
                                      " ladder_from 인물은 자기 표가 있으면 원래 인물 표 위에 덮는다.")
    open(PATH, "w", encoding="utf-8", newline="\n").write(json.dumps(P, ensure_ascii=False, indent=1) + "\n")

    # 보고 —— 마크다운 조각 (docs/특기_수치_1113.md 에 붙인다)
    print("CHANGED %d (카드 %d장)" % (len(changed), len({c["id"] for c, *_ in changed})))
    for c, n, o, v in changed:
        print("L\t%d\t%s\t%s\t%d\t%d" % (c["tier"], c["name"], n, o, v))
    for key, tier, b, a in comp:
        print("A\t%s\t%d\t%.3f\t%.3f" % (key, tier, b, a))
    for k, v in bad:
        print("BAD\t%s\t%s\t%s" % (k[0], k[1], dict(sorted(v.items()))))
    # 레벨 평균 (계열 없는 특기는 level_scale 그대로라 세기 변화를 따로 본다)
    for tier in range(3, 9):
        o = n_ = 0.0
        cnt = 0
        for c in cards:
            if c["tier"] != tier:
                continue
            for t in c["traits"]:
                if t["attr"] or t["unique"]:
                    continue
                o += LV_SCALE[t["lv"]]
                n_ += LV_SCALE[new_lv.get((c["id"], t["name"]), t["lv"])]
                cnt += 1
        if cnt:
            print("N\t%d\t%d\t%.4f\t%.4f" % (tier, cnt, o / cnt, n_ / cnt))


if __name__ == "__main__":
    main()
