# 11/26 인연 점검 정리 —— tests/yeon_check.gd 의 dump · sim 결과와 실제 온라인 대전 기록(정리본)을 읽어 표를 찍는다 (docs/인연_분석_1126.md)
# 실행: PYTHONIOENCODING=utf-8 python tests/yeon_check.py <yeon_db.json> <real_battles.json> [sim jsonl ...] [--min=5.0]
import json, sys, collections, statistics, itertools

args = [a for a in sys.argv[1:] if not a.startswith("--")]
opt = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
MN = float(opt.get("min", "5.0"))
db = json.load(open(args[0], encoding="utf-8"))
rows = json.load(open(args[1], encoding="utf-8"))
sims = args[2:]
Y = db["inyeon"]
P = db["person"]
N2P = db["name2p"]
PHYS, INT = set(db["phys"]), set(db["int"])
FRONT = {"창병", "기병"}


def tag_of(p):      # 인물의 병종 —— 카드가 여럿이면 가장 많은 병종 (같으면 높은 등급 카드)
    cs = P[p]["cards"]
    c = collections.Counter(x[1] for x in cs)
    best = max(cs, key=lambda x: (c[x[1]], x[0]))
    return best[1]


def cls(t):
    return "물리" if t in PHYS else "책략"


def pct(x):
    return "%.1f%%" % (100 * x)


# ───── 1. 인연별 구성 ─────
print("## 1. 인연별 구성 (병종 · 물리/책략 · 세력 · 전열)")
skew = []
for n, mem in Y.items():
    tags = [tag_of(p) for p in mem]
    tc = collections.Counter(tags)
    cc = collections.Counter(cls(t) for t in tags)
    fc = collections.Counter(P[p]["fac"] for p in mem)
    top = tc.most_common(1)[0]
    fr = sum(t in FRONT for t in tags)
    skew.append((top[1] / len(mem), n, mem, tags, tc, cc, fc, fr))
skew.sort(key=lambda x: (-x[0], -max(x[5].values())))
n60 = sum(s[0] >= 0.6 for s in skew)
n2 = sum(len(s[4]) <= 2 for s in skew)
pure = sum(len(s[5]) == 1 for s in skew)
allfac = sum(len(s[6]) == 1 for s in skew)
nofront = sum(s[7] == 0 for s in skew)
allfront = sum(s[7] == len(s[2]) for s in skew)
print(f"인연 {len(Y)} · 한 병종 60% 이상 {n60} · 병종 2종 이하 {n2} · 물리만/책략만 {pure} · 한 세력 {allfac} · 전열(창·기) 0명 {nofront} · 전원 전열 {allfront}")
pcount = collections.Counter(p for m in Y.values() for p in m)
print("인물당 인연 수 분포:", dict(sorted(collections.Counter(pcount.values()).items())), "· 소속 인물", len(pcount))
print("| 인연 | 구성원(병종) | 최다 병종 | 물리:책략 | 세력 | 전열 |")
for s in skew:
    sh, n, mem, tags, tc, cc, fc, fr = s
    print(f"| {n} | {' · '.join(f'{p}({t})' for p, t in zip(mem, tags))} | {tc.most_common(1)[0][0]} {pct(sh)} | {cc['물리']}:{cc['책략']} | {'/'.join(f'{k}{v}' for k, v in fc.most_common())} | {fr}/{len(mem)} |")
# 같은 병종 쏠림 쌍: 인연 안에서 같은 병종끼리 짝 비율 (무작위로 섞었을 때 기대값과 비교)
allp = list(pcount)
alltags = [tag_of(p) for p in allp]
tcnt = collections.Counter(alltags)
tot = len(alltags)
exp_same = sum(v * (v - 1) for v in tcnt.values()) / (tot * (tot - 1))
pairs = [(tag_of(a), tag_of(b)) for m in Y.values() for a, b in itertools.combinations(m, 2)]
obs = sum(a == b for a, b in pairs) / len(pairs)
obs_c = sum(cls(a) == cls(b) for a, b in pairs) / len(pairs)
ccnt = collections.Counter(cls(t) for t in alltags)
exp_c = sum(v * (v - 1) for v in ccnt.values()) / (tot * (tot - 1))
fac = [P[p]["fac"] for p in allp]
fcnt = collections.Counter(fac)
exp_f = sum(v * (v - 1) for v in fcnt.values()) / (tot * (tot - 1))
obs_f = sum(P[a]["fac"] == P[b]["fac"] for m in Y.values() for a, b in itertools.combinations(m, 2)) / len(pairs)
print(f"인연 안 두 사람이 같은 병종 {pct(obs)} (무작위 기대 {pct(exp_same)}) · 같은 갈래(물리/책략) {pct(obs_c)} (기대 {pct(exp_c)}) · 같은 세력 {pct(obs_f)} (기대 {pct(exp_f)})")
print("인물 병종 분포:", dict(tcnt.most_common()))

# ───── 실제 덱 ─────
def deck(s):
    ps = []
    for c in s["cards"]:
        p = N2P.get(c[0], c[0])
        ps.append((p, int(c[1]), c[2]))
    return ps


def bonds(ps):      # 인연마다 덱에 든 인물 수 (고유기 카드 = 3등급 이상만)
    have = {p for p, t, g in ps if t >= 3}
    return {n: len(have & set(m)) for n, m in Y.items()}


def avg(s):
    return sum(c[1] for c in s["cards"]) / max(1, len(s["cards"]))


decks = []      # (bi, side, ps, win, av)
for bi, b in enumerate(rows):
    av = (avg(b["me"]) + avg(b["foe"])) / 2
    if av < MN:
        continue
    w = 0.5 if b["draw"] else (1.0 if b["win"] else 0.0)
    decks.append((bi, "A", deck(b["me"]), w, av))
    decks.append((bi, "B", deck(b["foe"]), 1 - w, av))
print(f"\n## 2. 실제 덱 (평균 등급 {MN} 이상 {len(decks) // 2}판 · {len(decks)}덱, 기록 승패)")


def mb(ps):
    return max(bonds(ps).values())


def size_bucket(m):
    return "≤2" if m <= 2 else ("3" if m == 3 else "≥4")


def tier_avg(ps):
    return sum(t for p, t, g in ps) / len(ps)


g = collections.defaultdict(list)
for d in decks:
    g[size_bucket(mb(d[2]))].append(d)
print("| 가장 큰 인연 묶음 | 덱 | 기록 승률 | 평균 등급 | 책략 비율 |")
for k in ["≤2", "3", "≥4"]:
    L = g[k]
    if not L:
        continue
    ia = statistics.mean(sum(cls(t) == "책략" for p, tr, t in d[2] if tr >= 3) / max(1, sum(tr >= 3 for p, tr, t in d[2])) for d in L)
    print(f"| {k} | {len(L)} | {pct(statistics.mean(d[3] for d in L))} | {statistics.mean(tier_avg(d[2]) for d in L):.2f} | {pct(ia)} |")
# 등급 통제 —— 두 덱 평균 등급 차가 작은 판에서 묶음이 더 큰 쪽의 기록 승률
for lim in (0.25, 9.0):
    cmp_ = []
    for i in range(0, len(decks), 2):
        a, b = decks[i], decks[i + 1]
        ma, mb_ = mb(a[2]), mb(b[2])
        if ma == mb_ or abs(tier_avg(a[2]) - tier_avg(b[2])) > lim:
            continue
        cmp_.append(a[3] if ma > mb_ else b[3])
    if cmp_:
        print(f"평균 등급 차 ≤{lim}: 묶음이 더 큰 쪽 기록 승률 {pct(statistics.mean(cmp_))} (n{len(cmp_)})")
# 책략 쏠림 덱
print("책략(책사·유생·술사·모사) 장수 수별 —— 덱 · 기록 승률 · 가장 큰 인연 묶음 평균")
gi = collections.defaultdict(list)
for d in decks:
    k = sum(cls(t) == "책략" for p, tr, t in d[2] if tr >= 3)
    gi[min(k, 5)].append(d)
for k in sorted(gi):
    L = gi[k]
    print(f"  책략 {k}{'+' if k == 5 else ''}: {len(L)}덱 · 승률 {pct(statistics.mean(d[3] for d in L))} · 묶음 {statistics.mean(mb(d[2]) for d in L):.2f}")
# 쓰인 인연 · 인물 쏠림
use = collections.Counter()
for d in decks:
    for n, c in bonds(d[2]).items():
        if c >= 3:
            use[n] += 1
print(f"3명 이상 모인 인연: {len(use)}/{len(Y)}종 쓰임 · 상위:", ", ".join(f"{n} {pct(c / len(decks))}" for n, c in use.most_common(6)))
top3 = sum(c for n, c in use.most_common(3)) / max(1, sum(use.values()))
print(f"  3명 이상 묶음 가운데 상위 3 인연 몫 {pct(top3)} · 상위 5 {pct(sum(c for n, c in use.most_common(5)) / max(1, sum(use.values())))}")
pu = collections.Counter(p for d in decks for p in {p for p, t, g_ in d[2] if t >= 3})
print(f"고유기 인물 {len(pu)}명 쓰임 · 상위 10명이 덱 자리의 {pct(sum(c for p, c in pu.most_common(10)) / sum(pu.values()))} · 상위:", ", ".join(f"{p} {pct(c / len(decks))}" for p, c in pu.most_common(8)))
# 덱 유사도 —— 두 덱의 인물 자카드 평균
sets = [frozenset(p for p, t, g_ in d[2] if t >= 3) for d in decks]
js = [len(a & b) / max(1, len(a | b)) for a, b in itertools.combinations(sets, 2)]
print(f"덱 두 개의 고유기 인물 겹침(자카드) 평균 {statistics.mean(js):.3f} · 0.5 이상 쌍 {pct(sum(j >= 0.5 for j in js) / len(js))}")
inn = [sum(p in pcount for p, t, g_ in d[2] if t >= 3) / max(1, sum(t >= 3 for p, t, g_ in d[2])) for d in decks]
print(f"덱의 고유기 장수 가운데 인연 소속 비율 평균 {pct(statistics.mean(inn))} (인연 소속 인물 {len(pcount)}명)")
# 인연을 맞춘 덱의 병종 구성 —— 가장 큰 인연 묶음 안 장수들의 병종 쏠림 · 덱 전체 병종 종류 수 · 최다 병종 몫
print("묶음 크기별 덱 병종 —— | 묶음 | 덱 | 덱 병종 종류 | 덱 최다 병종 몫 | 묶음 안 최다 병종 몫 | 묶음이 물리만/책략만 |")
for k in ["≤2", "3", "≥4"]:
    L = g[k]
    kinds, tops, inner, pure_ = [], [], [], []
    for d in L:
        gs = [t for p, tr, t in d[2] if tr >= 3]
        c = collections.Counter(gs)
        kinds.append(len(c))
        tops.append(c.most_common(1)[0][1] / len(gs))
        if k == "≤2":
            continue
        bd = bonds(d[2])
        n = max(bd, key=bd.get)
        have = {p: t for p, tr, t in d[2] if tr >= 3}
        it = [have[p] for p in Y[n] if p in have]
        ci = collections.Counter(it)
        inner.append(ci.most_common(1)[0][1] / len(it))
        pure_.append(len({cls(t) for t in it}) == 1)
    print(f"| {k} | {len(L)} | {statistics.mean(kinds):.2f} | {pct(statistics.mean(tops))} | {pct(statistics.mean(inner)) if inner else '-'} | {pct(statistics.mean(pure_)) if pure_ else '-'} |")

# ───── (나) 인연 재구성 후보 —— 데이터는 바꾸지 않고, 바꾸면 지표가 어떻게 달라지는지만 ─────
# (인연, 뺄 인물, 넣을 인물, 서사 근거). 넣을 인물 가운데 인연이 없던 장수를 먼저 (인물당 인연 수가 늘지 않게)
SWAP = [
    ("번성 전투", "서황", "사마의", "손권과 손잡아 번성을 구하자는 계책 (모사)"),
    ("번성 전투", "관평", "여몽", "관우가 비운 강릉을 백의도강으로 친다 (도적)"),
    ("태평도", "좌자", "장만성", "황건 장수 (도적)"),
    ("태평도", "장로", "관해", "황건 잔당, 북해 포위 (도적)"),
    ("반동탁 연합", "마등", "공융", "연의 18제후의 북해태수 (유생)"),
    ("반동탁 연합", "공손찬", "도겸", "연의 18제후의 서주자사 (유생)"),
    ("안량과 문추", "장료", "안량", "인연 이름의 주인공이 빠져 있다 (기병)"),
    ("안량과 문추", "서황", "관우", "백마에서 안량을 벤 장수 (창병)"),
    ("안량과 문추", "원소", "저수", "안량 단독 기용을 말린 감군 (책사)"),
    ("항전과 투항", "순욱", "손권", "책상 모서리를 베어 항전을 정한다 (궁병)"),
    ("하비 포위", "초선", "고순", "하비에서 여포와 함께 사로잡힌 함진영 (창병)"),
    ("하후와 전위", "허저", "정욱", "연주를 지킨 하후돈 · 순욱 곁 모사 (모사)"),
    ("서량 기병", "방덕", "이유", "동탁의 서량군 책사 (모사)"),
]
NEW = {      # 병종 교차 새 인연 후보
    "장판파": (["조운", "장비", "간옹", "미축", "문빙"], "당양 장판 —— 조운 단기 · 장비 다리 · 피난길의 간옹 · 미축, 뒤쫓은 문빙"),
    "관도의 결단": (["허유", "조홍", "장합", "고람", "저수"], "오소 —— 허유 투항, 조홍이 본진을 지키고 장합 · 고람 투항, 저수 사로잡힘"),
    "이릉대전": (["유비", "육손", "황권", "주연", "감녕"], "이릉 —— 유비 동정, 육손 화공, 황권 북안 고립, 주연 · 감녕"),
}


def yeon_stats(Yd):
    rs = []
    for n, mem in Yd.items():
        tags = [tag_of(p) for p in mem]
        tc = collections.Counter(tags)
        rs.append((tc.most_common(1)[0][1] / len(mem), len(tc), len({cls(t) for t in tags})))
    pr = [(tag_of(a), tag_of(b)) for m in Yd.values() for a, b in itertools.combinations(m, 2)]
    pc = collections.Counter(p for m in Yd.values() for p in m)
    return (len(Yd), sum(r[0] >= 0.6 for r in rs), sum(r[1] <= 2 for r in rs), sum(r[2] == 1 for r in rs),
            sum(a == b for a, b in pr) / len(pr), len(pc), max(pc.values()))


Y2 = {n: list(m) for n, m in Y.items()}
for n, out_, in_, why in SWAP:
    if n in Y2 and out_ in Y2[n] and in_ in P and in_ not in Y2[n]:
        Y2[n][Y2[n].index(out_)] = in_
Y3 = dict(Y2)
for n, (m, why) in NEW.items():
    Y3[n] = [p for p in m if p in P]
print("\n## (나) 인연 재구성 후보")
print("| 인연 | 빼기 → 넣기 | 근거 |")
for n, out_, in_, why in SWAP:
    print(f"| {n} | {out_}({tag_of(out_)}) → {in_}({tag_of(in_) if in_ in P else '?'}) | {why} |")
for n, (m, why) in NEW.items():
    print(f"| {n} (새) | {' · '.join(f'{p}({tag_of(p)})' for p in m if p in P)} | {why} |")
print("| 지표 | 인연 수 | 한 병종 60%↑ | 병종 2종↓ | 물리만/책략만 | 인연 안 같은 병종 짝 | 소속 인물 | 인물당 최대 인연 |")
for lab, Yd in (("지금", Y), ("교체 후", Y2), ("교체 + 새 인연", Y3)):
    s = yeon_stats(Yd)
    print(f"| {lab} | {s[0]} | {s[1]} | {s[2]} | {s[3]} | {pct(s[4])} | {s[5]} | {s[6]} |")

if not sims:
    sys.exit()

# ───── 3. 시뮬 ─────
R = collections.defaultdict(dict)      # (bi, s) -> v -> row
for fn in sims:
    for ln in open(fn, encoding="utf-8"):
        try:
            r = json.loads(ln)
        except ValueError:      # 아직 쓰는 중인 줄
            continue
        R[(r["bi"], r["s"])][r["v"]] = r
keys = sorted(R)
print(f"\n## 3. 같은 덱 · 같은 시드 다시 싸우기 ({len(keys)}판 = 기록 {len({k[0] for k in keys})}판 × 시드)")
mbA = {}
for bi in {k[0] for k in keys}:
    b = rows[bi]
    mbA[bi] = (mb(deck(b["me"])), mb(deck(b["foe"])))


def gain(v, off, key="aw"):      # 진영 하나만 인연 끔 → 그 덱이 인연 덕에 얻는 몫 (덱 묶음 크기별) —— aw 승률 · mg 남은 병력 차
    out = collections.defaultdict(list)
    for k in keys:
        r = R[k]
        if v not in r:
            continue
        for side, o in (("A", off + "A"), ("B", off + "B")):
            if o not in r or key not in r[v]:
                continue
            sg = 1 if side == "A" else -1
            if key == "aw":
                wa = r[v]["aw"] if side == "A" else 1 - r[v]["aw"]
                wo = r[o]["aw"] if side == "A" else 1 - r[o]["aw"]
            else:
                wa, wo = sg * r[v][key], sg * r[o][key]
            m = mbA[k[0]][0 if side == "A" else 1]
            out[size_bucket(m)].append(wa - wo)
            if m >= 3:
                out["≥3"].append(wa - wo)
            out["전체"].append(wa - wo)
    return out


def ms(L, mul=100):
    if len(L) < 2:
        return "-"
    return f"{mul * statistics.mean(L):+.1f} ±{mul * statistics.stdev(L) / len(L) ** 0.5:.1f}"


print("인연 덕 (같은 덱 · 시드, 그 덱만 인연 끔과 비교) —— 승률 %p (± 표준오차) / 남은 병력 차 %p")
print("| 변형 | 비교 | 묶음 ≤2 | 3 | ≥4 | ≥3 전체 | 판 바뀜(≥3) |")
for v, off in (("base", "off"), ("basic", "basic_off"), ("basic2", "basic2_off"), ("mix", "mix_off")):
    o = gain(v, off)
    if not o:
        continue
    om = gain(v, off, "mg")
    flip = sum(x != 0 for x in o["≥3"]) / max(1, len(o["≥3"]))
    print(f"| {v} | 승률 | {ms(o['≤2'])} | {ms(o['3'])} | {ms(o['≥4'])} | {ms(o['≥3'])} (n{len(o['≥3'])}) | {pct(flip)} |")
    print(f"| {v} | 병력 | {ms(om['≤2'])} | {ms(om['3'])} | {ms(om['≥4'])} | {ms(om['≥3'])} | |")


def wr_by(v):
    out = collections.defaultdict(list)
    for k in keys:
        r = R[k].get(v)
        if r is None:
            continue
        a, b = mbA[k[0]]
        out[size_bucket(a)].append(r["aw"])
        out[size_bucket(b)].append(1 - r["aw"])
    return out


print("변형별 —— 묶음 ≤2 덱 · ≥4 덱 승률 · 차 · 연쇄 있는 판 · 판당 연쇄 · 연쇄 장수 · 길이 · 고유기")
print("| 변형 | ≤2 덱 승률 | 3 덱 | ≥4 덱 승률 | ≥4 − ≤2 | 연쇄 판 | 판당 연쇄(인연+기본) | 4명 연쇄 | 길이(초) | 판당 고유기 | 주제 효과 |")
for v in ["base", "none", "notheme", "basic", "basic2", "mix", "all"]:
    L = [R[k][v] for k in keys if v in R[k]]
    if not L:
        continue
    o = wr_by(v)
    m = lambda k: statistics.mean(o[k]) if o[k] else float("nan")
    ch = statistics.mean((r["yj"]) > 0 for r in L)
    print(f"| {v} | {pct(m('≤2'))} | {pct(m('3'))} | {pct(m('≥4'))} | {100 * (m('≥4') - m('≤2')):+.1f}%p | {pct(ch)} | {statistics.mean(r['yj'] for r in L):.2f} ({statistics.mean(r['yj'] - r['yb'] for r in L):.2f}+{statistics.mean(r['yb'] for r in L):.2f}) | {statistics.mean(r['n4'] for r in L):.2f} | {statistics.mean(r['tm'] for r in L):.1f} | {statistics.mean(r['ults'] for r in L):.1f} | {statistics.mean(r['th'] for r in L):.2f} |")
# 기록 승패 일치 (base)
agree = statistics.mean((R[k]["base"]["aw"] == (0.5 if rows[k[0]]["draw"] else (1.0 if rows[k[0]]["win"] else 0.0))) for k in keys if "base" in R[k])
print(f"base 다시 싸우기와 기록 승패 일치 {pct(agree)}")
print("(none 행의 ≥4 − ≤2 = 인연을 다 꺼도 남는 덱 세기 차. base 와 none 의 차가 인연 몫)")
