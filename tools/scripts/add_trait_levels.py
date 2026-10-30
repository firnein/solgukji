"""특기 레벨 표를 passives.json 에 넣는다 (한 번 실행, 2026-10-30).

특기마다 레벨을 직접 적는다 —— level[인물][특기][카드 등급] = 레벨.
처음 값은 예전 등급 배율과 같도록 '카드 등급 - 2' (고급 1 ~ 신화 6) 로 채운다. 그 뒤로는 손으로 고친다.
배율은 level_scale (계열 특기는 level_scale_attr) 에서 레벨로 찾는다. 1~6 은 예전 tier_scale · attr_scale 과 같고 7~9 는 늘려 둔 것.

실행: python -I tools/scripts/add_trait_levels.py   (solgukji_godot/data/passives.json 을 고친다)
"""
import json
from collections import OrderedDict

PATH = "solgukji_godot/data/passives.json"
P = json.load(open(PATH, encoding="utf-8"), object_pairs_hook=OrderedDict)
d = json.load(open("solgukji_godot/data/game.json", encoding="utf-8"))
e = json.load(open("solgukji_godot/data/cards_ext.json", encoding="utf-8"))
tiers = {}
for c in d["CARDDEF"] + e["cards"]:
    if c[2] >= 3:
        tiers.setdefault(c[1].split(" ")[-1], set()).add(c[2])

ts, at = P["tier_scale"], P["attr_scale"]
P["level_scale"] = OrderedDict((str(lv), ts[str(lv + 2)]) for lv in range(1, 7))
P["level_scale"].update({"7": 1.3, "8": 1.45, "9": 1.6})
P["level_scale_attr"] = OrderedDict((str(lv), at[str(lv + 2)]) for lv in range(1, 7))
P["level_scale_attr"].update({"7": 1.15, "8": 1.2, "9": 1.25})

lv = OrderedDict()
for p, rows in P["ladder"].items():
    per = OrderedDict()
    for r in rows:
        hi = r[2] if len(r) > 2 else 99
        per[r[0]] = OrderedDict((str(t), t - 2) for t in sorted(tiers.get(p, ())) if r[1] <= t <= hi)
    lv[p] = per
P["level"] = lv
P["_레벨"] = ("특기 레벨 —— level[인물][특기][카드 등급] = 레벨 (화면에 '방진3' 처럼 보인다). 배율은 level_scale[레벨] "
             "(attr 가 있는 계열 특기는 level_scale_attr). 표에 없으면 '카드 등급 - 2'. 처음 값은 예전 등급 배율과 같게 채웠다.")
open(PATH, "w", encoding="utf-8", newline="\n").write(json.dumps(P, ensure_ascii=False, indent=1) + "\n")
print("인물", len(lv), "· 특기 줄", sum(len(v) for v in lv.values()))
