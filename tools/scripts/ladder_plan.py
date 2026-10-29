"""특기 사다리 개편안 —— 전법 배정안(attr_plan.py)의 전법을 실제 특기 줄로 채운다. 데이터는 바꾸지 않는다.

실행: python -I tools/scripts/ladder_plan.py  →  특기_사다리_개편안.md
규칙
  - 지금 사다리 줄은 그대로 둔다 (설계된 것).
  - 전법이 열리는 등급: 주 전법 = 그 장수의 가장 낮은 등급, 둘째 = 전설, 셋째 = 불멸, 넷째 = 신화
    (그 등급 카드가 없으면 그 장수에게 있는 다음 등급, 그것도 없으면 가장 높은 등급). 다섯째부터는 붙이지 않는다.
  - 없는 전법은 전법별 기본 특기로 한 줄 더한다: 낮은 등급(고급 · 희귀)은 거는 특기, 전설부터는 키우는 특기.
    철벽 · 계략은 무력 병종과 책략 병종에 맞는 특기를 고른다.
  - 카드당 줄 상한 4줄 (지금 규칙). 넘치면 그 등급에 걸린 공용 특기 줄을 먼저 뺀다.
    그래도 넘치면 그 전법은 다음 등급으로 미룬다.
  - 카드의 전법 = 그 카드 등급에서 켜진 특기들의 전법 (맞수 특기 제외).
"""
import io
import contextlib
import json
import runpy
from collections import Counter, defaultdict

with contextlib.redirect_stdout(io.StringIO()):
    G = runpy.run_path("tools/scripts/attr_plan.py")
P, A, T, cards, person, trait_attr, FROM_LADDER = G["P"], G["A"], G["T"], G["cards"], G["person"], G["trait_attr"], G["FROM_LADDER"]
PSV = json.load(open("solgukji_godot/data/passives.json", encoding="utf-8"))
COMMON = {k for k, v in G["TRAIT_ATTR"].items() if v is None}
INT_TAGS = {"책사", "유생", "술사", "모사"}
CAP = {3: 4, 4: 4, 5: 4, 6: 4, 7: 4, 8: 4}            # 지금 규칙 그대로 —— 카드당 최대 4줄
UNLOCK = [None, 5, 7, 8]
# 전법별 기본 특기: (낮은 등급 —— 거는 것, 전설부터 —— 키우는 것). 철벽 · 계략은 (무력용, 책략용)
POOL = {
    "화공": ("점화", "화공"), "수공": ("침수", "수계"), "돌파": ("충파", "짓밟기"), "표적": ("조준", "명중"),
    "인덕": ("명경", "명경"),
}
POOL_BY_KIND = {"철벽": ("철벽", "심지"), "계략": ("위압", "귀모")}

tiers_of = defaultdict(set)
tag_of = {}
for c in cards:
    tiers_of[person(c)].add(c[2])
    tag_of[person(c)] = c[3]


def active(rows, t):
    return [r for r in rows if r[1] <= t <= (r[2] if len(r) > 2 else 99)]


def pick(attr, p, t):
    if attr in POOL_BY_KIND:
        return POOL_BY_KIND[attr][1 if tag_of[p] in INT_TAGS else 0]
    low, high = POOL[attr]
    return low if t <= 4 else high


def first_tier_at_least(p, t):
    ts = sorted(tiers_of[p])
    return next((x for x in ts if x >= t), ts[-1])


plan, added, removed, dropped = {}, defaultdict(list), defaultdict(list), defaultdict(list)
for p, (attrs, _) in P.items():
    rows = [list(r) for r in PSV["ladder"].get(p, [])]
    have = lambda t: {trait_attr(r[0]) for r in active(rows, t)} - {None}
    for i, a in enumerate(attrs):
        if i >= 4:
            dropped[p].append(a)
            continue
        start = min(tiers_of[p]) if i == 0 else first_tier_at_least(p, UNLOCK[i])
        ok = False
        for t in sorted(x for x in tiers_of[p] if x >= start):
            if a in have(t):
                ok = True
                break
            act = active(rows, t)
            if len(act) >= CAP[t]:
                com = [r for r in act if r[0] in COMMON]
                if not com:
                    continue                      # 이 등급은 꽉 찼다 —— 다음 등급으로 미룬다
                r = com[-1]
                if r[1] < t:
                    r.append(t - 1) if len(r) == 2 else None
                    r[2] = t - 1
                else:
                    rows.remove(r)
                removed[p].append("%s(%s~)" % (r[0], T[t]))
            n = pick(a, p, t)
            new = [n, t]
            for x in sorted(y for y in tiers_of[p] if y > t):      # 위 등급에서 4줄을 넘으면 공용 특기를 빼고, 없으면 거기서 끊는다
                act = active(rows, x)
                if len(act) < CAP[x]:
                    continue
                com = [r for r in act if r[0] in COMMON]
                if com:
                    r = com[-1]
                    if r[1] < x:
                        r[2:] = [x - 1]
                    else:
                        rows.remove(r)
                    removed[p].append("%s(%s~)" % (r[0], T[x]))
                else:
                    new.append(x - 1)
                    break
            rows.append(new)
            added[p].append("%s %s(%s~%s)" % (a, n, T[t], T[new[2]] if len(new) > 2 else ""))
            ok = True
            break
        if not ok:
            dropped[p].append(a)
    plan[p] = rows


def card_attrs(c, rows):
    return {trait_attr(r[0]) for r in active(rows, c[2])} - {None}


L = ["# 특기 사다리 개편안", "", "`tools/scripts/ladder_plan.py` 로 만든다 (데이터는 아직 안 바꿈). 규칙은 스크립트 머리말.", "",
     "## 등급별 전법 카드 수 (그 카드 등급에서 실제로 켜진 전법만)", "",
     "| 등급 | 카드 | " + " | ".join(A) + " |", "|---|---|" + "---|" * len(A)]
for label, use in (("지금", lambda p: PSV["ladder"].get(p, [])), ("개편 후", lambda p: plan[p])):
    for t in range(3, 9):
        cnt = Counter()
        cs = [c for c in cards if c[2] == t]
        for c in cs:
            for a in card_attrs(c, use(person(c))):
                cnt[a] += 1
        L.append("| %s %s | %d | %s |" % (label, T[t], len(cs), " | ".join(("**%d**" % cnt[a]) if cnt[a] < 6 else str(cnt[a]) for a in A)))
lines = Counter()
for c in cards:
    lines[(c[2], len(active(plan[person(c)], c[2])))] += 1
L += ["", "카드당 특기 줄 수 (개편 후): " + " · ".join("%s %s" % (T[t], "/".join("%d줄 %d장" % (n, lines[(t, n)]) for n in range(1, 5) if lines[(t, n)])) for t in range(3, 9)), "",
      "## 장수별 변경 (%d명, 더한 줄 %d · 뺀 공용 특기 %d)" % (len(added), sum(map(len, added.values())), sum(map(len, removed.values()))), "",
      "| 장수 | 병종 | 전법 | 더한 특기 | 뺀 · 줄인 공용 특기 | 못 붙인 전법 |", "|---|---|---|---|---|---|"]
for p in sorted(P, key=lambda p: (-len(added[p]), p)):
    if added[p] or removed[p] or dropped[p]:
        L.append("| %s | %s | %s | %s | %s | %s |" % (p, tag_of[p], " · ".join(P[p][0]), " · ".join(added[p]) or "-",
                                                      " · ".join(removed[p]) or "-", " · ".join(dropped[p]) or "-"))
L += ["", "## 개편 후 사다리 전체", "", "| 장수 | 사다리 [특기 (전법) 등급~] |", "|---|---|"]
for p in sorted(P):
    L.append("| %s | %s |" % (p, " · ".join("%s(%s) %s~%s" % (r[0], trait_attr(r[0]) or ("맞수" if r[0] in G["COUNTER"] else "공용"), T[r[1]], T[r[2]] if len(r) > 2 else "") for r in plan[p])))
open("특기_사다리_개편안.md", "w", encoding="utf-8", newline="\n").write("\n".join(L) + "\n")
print("\n".join(l for l in L if l.startswith("| 지금") or l.startswith("| 개편")))
print(L[L.index("## 등급별 전법 카드 수 (그 카드 등급에서 실제로 켜진 전법만)") + 17] if False else "")
print("더한 줄", sum(map(len, added.values())), "뺀 공용", sum(map(len, removed.values())), "못 붙인", {p: v for p, v in dropped.items() if v})
