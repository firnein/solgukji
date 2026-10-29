"""철벽 · 계략 · 인덕 특기를 인물 사다리에 붙인다 (한 번 실행). (당시엔 카드당 4줄을 넘으면 공용 특기 줄부터 뺐다 —— 2026-10-29 제한을 없애며 되돌렸다)

실행: python -I tools/scripts/add_guard_scheme_virtue.py   (solgukji_godot/data/passives.json 을 고친다)
"""
import json
from collections import OrderedDict

PATH = "solgukji_godot/data/passives.json"
# (특기, 인물, 붙는 등급[, 마지막 등급])
ADD = [
    # 철벽
    ("방진", "조인", 6), ("방진", "서황", 4), ("방진", "악진", 3), ("방진", "우금", 3), ("방진", "주태", 4),
    ("반격", "우금", 3, 4), ("반격", "이전", 3, 4), ("반격", "요화", 3, 4),
    ("역습", "하후돈", 6), ("역습", "허저", 5), ("역습", "전위", 7),
    ("철옹성", "조인", 7), ("철옹성", "학소", 3), ("철옹성", "장소", 6),
    ("사수", "전위", 7), ("사수", "주태", 5),
    ("장판단기", "조운", 8),
    # 계략
    ("반목", "가후", 4), ("반목", "진궁", 8), ("반목", "방통", 4), ("반목", "저수", 3),
    ("교란", "마충", 3, 4), ("교란", "장연", 4, 4), ("교란", "전풍", 3, 4),
    ("허실", "곽가", 5), ("허실", "법정", 5), ("허실", "종회", 6), ("허실", "사마의", 7),
    ("반간", "주유", 6), ("반간", "정욱", 6),
    ("미인계", "초선", 7), ("폐월", "초선", 8), ("팔진화계", "제갈량", 8),
    # 인덕
    ("인술", "화타", 4), ("인술", "우길", 3), ("인술", "장각", 5), ("인술", "미축", 3),
    ("위무", "간옹", 3, 4), ("위무", "이적", 3, 4), ("위무", "마량", 3, 4),
    ("감읍", "유비", 5), ("감읍", "손권", 6), ("감읍", "노숙", 5),
    ("도원결의", "유비", 8), ("도원결의", "화타", 8),
    ("단량", "정욱", 6), ("단량", "조조", 5),
    ("인의", "유비", 8),
]
COMMON = {"신속", "용장", "맹장", "비장", "후방", "후원", "선봉"}

P = json.load(open(PATH, encoding="utf-8"), object_pairs_hook=OrderedDict)
d = json.load(open("solgukji_godot/data/game.json", encoding="utf-8"))
e = json.load(open("solgukji_godot/data/cards_ext.json", encoding="utf-8"))
tiers = {}
for c in d["CARDDEF"] + e["cards"]:
    if c[2] >= 3:
        tiers.setdefault(c[1].split(" ")[-1], set()).add(c[2])


def active(rows, t):
    return [r for r in rows if r[1] <= t <= (r[2] if len(r) > 2 else 99)]


log = []
for row in ADD:
    n, p, a = row[0], row[1], row[2]
    assert n in P["traits"], n
    rows = P["ladder"][p]
    if any(r[0] == n for r in rows):
        continue
    new = [n, a] + ([row[3]] for _ in [0] if len(row) > 3).__next__() if len(row) > 3 else [n, a]
    rows.append(new)
    for t in sorted(x for x in tiers[p] if x >= a and (len(new) < 3 or x <= new[2])):
        while len(active(rows, t)) > 4:
            com = [r for r in active(rows, t) if r[0] in COMMON]
            if not com:
                log.append("넘침 %s %d등급: %s" % (p, t, ", ".join(r[0] for r in active(rows, t))))
                break
            r = com[-1]
            if r[1] < t:
                r[2:] = [t - 1]
                log.append("%s: 공용 %s 을 %d등급까지로" % (p, r[0], t - 1))
            else:
                rows.remove(r)
                log.append("%s: 공용 %s 뺌" % (p, r[0]))
open(PATH, "w", encoding="utf-8", newline="\n").write(json.dumps(P, ensure_ascii=False, indent=1) + "\n")
print("\n".join(log) or "넘침 없음")
