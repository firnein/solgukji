# -*- coding: utf-8 -*-
"""11/26 기인 값어치 집계 —— tests/kiin_value.tscn 의 출력(jsonl)을 표로 만든다. 결과 정리: docs/기인_값어치_1126.md
쓰기: python tests/kiin_value.py <kiin_db.json> <real_battles.json> <sim jsonl ...> [--ins <ins jsonl ...>]
  kiin_db.json : --mode=dump 출력 · sim jsonl : --mode=sim 출력(갈래 여러 개) · ins jsonl : --mode=ins 출력
승률 차는 모두 "같은 판 · 같은 시드의 기준(base) 대비" 짝 비교. ± 는 (판 · 쪽) 묶음 평균의 표준오차."""
import json, sys, math, collections

def load(paths):
    R = []
    for p in paths:
        with open(p, encoding='utf-8') as f:
            for l in f:
                l = l.strip()
                if l:
                    R.append(json.loads(l))
    return R

def mse(xs):
    n = len(xs)
    if n == 0:
        return (0.0, 0.0, 0)
    m = sum(xs) / n
    if n < 2:
        return (m, 0.0, n)
    v = sum((x - m) ** 2 for x in xs) / (n - 1)
    return (m, math.sqrt(v / n), n)

def clus(rows, key, val):
    """묶음(key)마다 val 평균 → 묶음 평균 목록"""
    d = collections.defaultdict(list)
    for r in rows:
        d[key(r)].append(val(r))
    return [sum(v) / len(v) for v in d.values()]

def pp(x):
    return '%+.1f ±%.1f (n%d)' % (100 * x[0], 100 * x[1], x[2])

def main():
    a = sys.argv[1:]
    ins_paths = []
    if '--ins' in a:
        i = a.index('--ins')
        ins_paths = a[i + 1:]
        a = a[:i]
    db = json.load(open(a[0], encoding='utf-8'))
    C = db['cards']
    real = json.load(open(a[1], encoding='utf-8'))
    R = load(a[2:])
    kiin = sorted(k for k in C if C[k]['kind'] == 'kiin')
    nm = lambda k: C[k]['name']

    def grp(k):
        c = C.get(k)
        if c is None:
            return None
        return 'K' if c['kind'] == 'kiin' else str(c['tier'])
    GN = {'3': '고급', '4': '희귀', '5': '전설', 'K': '기인', '6': '초월', '7': '불멸', '8': '신화'}

    # ── 1. 값 · 능력치 · 재현 기여 ──
    print('## 1. 값 대 세기 (재현: 기인이 든 판의 기준 실행, 같은 판 안의 다른 등급 포함)')
    st = collections.defaultdict(lambda: [0, 0.0, 0.0, 0.0, 0.0])      # n · 피해 · 받은 피해 · 처치 · 생존
    team = collections.defaultdict(lambda: [0, 0.0])      # 팀 피해 몫
    nbase = 0
    for r in R:
        if r['v'] != 'base' or 'ros' not in r:
            continue
        nbase += 1
        tot = collections.Counter()
        for u in r['ros']:
            tot[u[0]] += max(0, u[2])
        for u in r['ros']:
            g = grp(u[1])
            if g is None:
                continue
            for key in ([g, u[1]] if g == 'K' else [g]):
                s = st[key]
                s[0] += 1; s[1] += u[2]; s[2] += u[3]; s[3] += u[4]; s[4] += u[5]
                t = team[key]
                t[0] += 1; t[1] += max(0, u[2]) / max(1, tot[u[0]])
    print('기준 실행 %d판' % nbase)
    print('| 대상 | 값 | 병력 | 공격 | 방어 | 인연 | 재현 부대 수 | 피해 | 받은 피해 | 처치 | 생존 | 팀 피해 몫 | 값 1당 피해 |')
    def stat_row(label, ids, key):
        n = len(ids)
        cost = sum(C[k]['cost'] for k in ids) / n
        s = st.get(key, [0, 0, 0, 0, 0])
        t = team.get(key, [0, 0])
        if s[0]:
            tail = '%d | %.1f천 | %.1f천 | %.2f | %d%% | %.0f%% | %.0f' % (s[0], s[1] / s[0] / 1000, s[2] / s[0] / 1000, s[3] / s[0], 100 * s[4] / s[0], 100 * t[1] / t[0], s[1] / s[0] / cost)
        else:
            tail = '0 | - | - | - | - | - | -'
        print('| %s | %.0f | %.1f천 | %.0f | %.0f | %.1f | %s |' % (label, cost, sum(C[k]['tr'] for k in ids) / n / 1000, sum(C[k]['atk'] for k in ids) / n, sum(C[k]['def'] for k in ids) / n,
            sum(len(C[k]['yeon']) for k in ids) / n, tail))
    for g in ['5', 'K', '6', '7', '8']:
        ids = [k for k in C if grp(k) == g]
        stat_row(GN[g] + ' 평균 (%d명)' % len(ids), ids, g)
    for k in kiin:
        stat_row('%s (%s%s)' % (nm(k), C[k]['tag'], '' if C[k]['kiin'] else ' · 기능 없음'), [k], k)

    # ── 2. 연쇄 역할 ──
    print('\n## 2. 기인 연쇄 역할')
    base = {}
    for r in R:
        if r['v'] == 'base':
            base[(r['bi'], r['s'], r['side'])] = r
    def has_k(r):
        return r['nk'][0 if r['side'] == 'A' else 1] > 0
    kb = [r for r in base.values() if has_k(r)]
    n = len(kb)
    opened = sum(1 for r in kb if r['ch'][1] > 0)
    print('기인이 든 쪽 %d (판 · 시드 · 쪽) —— 기준 승률 %.1f%%' % (n, 100 * sum(r['w'] for r in kb) / n))
    a0 = [r for r in base.values() if r['side'] == 'A' and r['s'] == 0 and 'rec' in r]
    recw = []
    for r in kb:
        if r['s'] != 0:
            continue
        b = real[r['bi']]
        rw = 0.5 if b['draw'] else (1.0 if b['win'] else 0.0)
        recw.append(rw if r['side'] == 'A' else 1.0 - rw)
    print('기록과 재현의 승패 일치 %.1f%% (n%d, 시드 0) · 기인 쪽의 기록 승률 %.1f%% (n%d) · 기인이 한쪽에만 든 판의 기인 쪽 재현 승률 %.1f%%' % (
        100 * sum(1 for r in a0 if r['w'] == r['rec']) / max(1, len(a0)), len(a0), 100 * sum(recw) / max(1, len(recw)), len(recw),
        100 * sum(r['w'] for r in kb if min(r['nk']) == 0) / max(1, sum(1 for r in kb if min(r['nk']) == 0))))
    print('연쇄(2명 이상) 판당 %.2f · 기인이 연 연쇄 판당 %.2f (한 번이라도 연 판 %.1f%% = %.1f판에 한 번) · 기인 마무리 판당 %.2f · 고유기 판당 %.1f (기인 %.2f)' % (
        sum(r['ch'][0] for r in kb) / n, sum(r['ch'][1] for r in kb) / n, 100 * opened / n, n / max(1, opened), sum(r['ch'][2] for r in kb) / n,
        sum(r['ch'][3] for r in kb) / n, sum(r['ch'][4] for r in kb) / n))
    # 덱 안에 같은 인연 짝(고유기 장수)이 있는가 —— 기록 덱 기준
    name2 = {}
    for k, c in C.items():
        name2[(c['name'], c['tier'], c['tag'])] = k
    side_n = mate_n = 0
    per_k = collections.defaultdict(lambda: [0, 0])
    for b in real:
        for sd in ('me', 'foe'):
            ids = [name2.get((c[0], int(c[1]), c[2])) for c in b[sd]['cards']]
            ids = [k for k in ids if k]
            for k in ids:
                if C[k]['kind'] != 'kiin':
                    continue
                side_n += 1
                my = set(C[k]['yeon'])
                mate = any(o != k and C[o]['ult'] and C[o]['tier'] >= 5 and my & set(C[o]['yeon']) for o in ids)
                mate_n += 1 if mate else 0
                per_k[k][0] += 1
                per_k[k][1] += 1 if mate else 0
    print('기록 덱의 기인 %d장 가운데 같은 인연 짝(전설 이상 고유기 장수)이 덱에 있는 장: %d (%.0f%%)' % (side_n, mate_n, 100 * mate_n / max(1, side_n)))
    print('  ' + ' · '.join('%s %d/%d' % (nm(k), per_k[k][1], per_k[k][0]) for k in sorted(per_k, key=lambda k: -per_k[k][0])))
    print('인연 0인 기인: ' + ' · '.join(nm(k) for k in kiin if not C[k]['yeon']))

    def delta(v, filt=lambda r: True, slot_avg=False):
        rows = [r for r in R if r['v'] == v and has_k(r) and filt(r)]
        if not rows:
            return None
        if slot_avg:      # 바꿔 끼운 카드 여럿 → (판 · 시드 · 쪽 · 칸) 평균 먼저
            d = collections.defaultdict(list)
            for r in rows:
                d[(r['bi'], r['s'], r['side'], r['slot'])].append(r)
            rows = [dict(v_[0], w=sum(x['w'] for x in v_) / len(v_), mg=sum(x['mg'] for x in v_) / len(v_)) for v_ in d.values()]
        key = lambda r: (r['bi'], r['side'], r.get('slot', -1))
        dw = clus(rows, key, lambda r: r['w'] - base[(r['bi'], r['s'], r['side'])]['w'])
        dm = clus(rows, key, lambda r: r['mg'] - base[(r['bi'], r['s'], r['side'])]['mg'])
        bw = clus(rows, key, lambda r: base[(r['bi'], r['s'], r['side'])]['w'])
        flip = sum(1 for r in rows if r['w'] != base[(r['bi'], r['s'], r['side'])]['w']) / len(rows)
        return (mse(bw), mse(dw), mse(dm), flip, len(rows))

    def line(label, v, filt=lambda r: True, slot_avg=False):
        d = delta(v, filt, slot_avg)
        if d is None:
            print('| %s | - | - | - | - |' % label)
            return
        print('| %s | %.1f%% | %s | %s | %.1f%% |' % (label, 100 * d[0][0], pp(d[1]), pp(d[2]), 100 * d[3]))

    opened_keys = set((r['bi'], r['s'], r['side']) for r in kb if r['ch'][1] > 0)
    print('| 변형 (그 쪽만) | 기준 승률 | 승률 변화 %p | 남은 병력 몫 변화 %p | 승패가 바뀐 판 |')
    for v, label in [('r_fc', '마무리 ×1.0 · 상한 보통 (먼저 터짐은 유지)'), ('r_off', '연쇄 역할 전부 끔 (먼저 터짐도)'), ('r_fin15', '마무리 ×1.5'), ('r_fin15cap22', '마무리 ×1.5 · 상한 ×2.2'), ('r_fin20', '마무리 ×2.0 · 상한 ×2.5'),
            ('r_all13', '(구조 변경) 기인이 연 연쇄 전원 ×1.3'), ('r_all15', '(구조 변경) 전원 ×1.5 · 상한 ×2.5')]:
        if delta(v) is None:
            continue
        line(label, v)
        line('  └ 기준에서 기인이 연쇄를 연 판만', v, lambda r: (r['bi'], r['s'], r['side']) in opened_keys)

    # ── 3. 자리 값 ──
    print('\n## 3. 자리 값 (그 칸만 바꿈)')
    print('| 변형 | 기준 승률 | 승률 변화 %p | 남은 병력 몫 변화 %p | 승패가 바뀐 판 |')
    SL = [('fx1', '기인 기능만 끔'), ('fx2', '기능 + 위세 끔'), ('unL1', '재료 전설 1장만 (값 28)'), ('unL2', '재료 전설 2장 (값 56)'), ('unAll', '재료 전부 그대로 (값 76)'), ('up', '초월 평균 (값 76)'), ('imm', '불멸 평균 (값 95)')]
    for v, label in SL:
        line(label, v, slot_avg=v in ('up', 'imm'))
    puts = collections.Counter((r['v'], r['put']) for r in R if r['v'] in ('unL2', 'unAll'))
    print('재료를 실제로 깐 장 수 —— ' + ' · '.join('%s %d장: %d' % (k[0], k[1], puts[k]) for k in sorted(puts)))
    same_tag = lambda r: C[r['m']]['tag'] == C[r['k']]['tag']
    line('불멸 (같은 병종만)', 'imm', same_tag, True)
    line('초월 (같은 병종만)', 'up', same_tag, True)
    nokey = set(k for k in kiin if not C[k]['kiin'])
    print('\n### 기인별 (실제 덱에 든 칸, 승률 변화 %p · 괄호는 묶음 수)')
    print('| 기인 | 칸 수 | 기준 승률 | 기능 끔 | 위세까지 끔 | 전설 1장 | 재료 전부 | 초월 | 불멸 |')
    cnt = collections.Counter()
    for r in R:
        if r['v'] == 'fx1':
            cnt[r['k']] += 1
    def cell(v, k, slot_avg=False):
        d = delta(v, lambda r: r.get('k') == k, slot_avg)
        return '-' if d is None else '%+.1f ±%.1f' % (100 * d[1][0], 100 * d[1][1])
    for k in sorted(cnt, key=lambda k: -cnt[k]):
        d = delta('fx1', lambda r: r.get('k') == k)
        print('| %s | %d | %.0f%% | %s | %s | %s | %s | %s | %s |' % (nm(k), d[1][2], 100 * d[0][0], '(기능 없음)' if k in nokey else cell('fx1', k), cell('fx2', k), cell('unL1', k), cell('unAll', k), cell('up', k, True), cell('imm', k, True)))
    for label, ks in [('기능 없는 다섯', nokey), ('기능 있는 열일곱', set(kiin) - nokey)]:
        f = lambda r: r.get('k') in ks
        d = delta('fx2', f)
        if d:
            print('| **%s** | %d | %.0f%% | %s | %s | %s | %s | %s | %s |' % (label, d[1][2], 100 * d[0][0], '-' if ks is nokey else pp(delta('fx1', f)[1]), pp(d[1]), pp(delta('unL1', f)[1]), pp(delta('unAll', f)[1]), pp(delta('up', f, True)[1]), pp(delta('imm', f, True)[1])))

    # ── 3-1. 접전 판만 (기준 실행에서 남은 병력 몫 차가 ±0.3 안) —— 기인 쪽이 크게 이기는 판은 무엇을 바꿔도 승패가 안 변한다 ──
    close = lambda r: abs(base[(r['bi'], r['s'], r['side'])]['mg']) < 0.3
    print()
    print('### 접전 판만 (기준에서 남은 병력 몫 차 ±0.3 안)')
    print('| 변형 | 기준 승률 | 승률 변화 %p | 남은 병력 몫 변화 %p | 승패가 바뀐 판 |')
    for v, label, sa in [('r_fc', '연쇄: 마무리 ×1.0 · 상한 보통', False), ('r_off', '연쇄 역할 전부 끔', False), ('r_fin15', '연쇄: 마무리 ×1.5', False), ('r_fin20', '연쇄: 마무리 ×2.0 · 상한 ×2.5', False),
            ('fx1', '기인 기능만 끔', False), ('fx2', '기능 + 위세 끔', False), ('unL1', '재료 전설 1장만', False), ('unAll', '재료 전부 그대로', False), ('up', '초월 평균', True), ('imm', '불멸 평균', True),
            ('b80', '몸: 병력 0.8', False), ('b80s90', '몸: 병력 0.8 · 능력치 0.9', False), ('b100', '몸: 1.0 · 1.0', False)]:
        line(label, v, close, sa)

    # ── 4. 몸 배율 ──
    print('\n## 4. 기인 몸 배율 (양쪽 기인 모두 바뀜)')
    print('| 변형 | 기준 승률 | 승률 변화 %p | 남은 병력 몫 변화 %p | 승패가 바뀐 판 |')
    one = lambda r: r['nk'][0] == 0 or r['nk'][1] == 0
    for v, label in [('b80', '병력 0.7 → 0.8'), ('b80s90', '병력 0.8 · 능력치 0.85 → 0.9'), ('b100', '병력 · 능력치 1.0 (불멸 평균 몸)')]:
        line(label + ' —— 기인이 한쪽에만 든 판', v, one)
        line(label + ' —— 기인 쪽 전체', v)
    for label, ks in [('기능 없는 다섯만 든 쪽', nokey), ('기능 있는 기인만 든 쪽', set(kiin) - nokey)]:
        sides = set()
        for r in R:
            if r['v'] == 'fx2':
                sides.add((r['bi'], r['side']))
        only = collections.defaultdict(set)
        for r in R:
            if r['v'] == 'fx2':
                only[(r['bi'], r['side'])].add(r['k'])
        ok = set(s for s in only if only[s] <= ks)
        line('병력 0.8 —— ' + label + ' (한쪽만)', 'b80', lambda r: one(r) and (r['bi'], r['side']) in ok)
        line('병력 0.8 · 능력치 0.9 —— ' + label + ' (한쪽만)', 'b80s90', lambda r: one(r) and (r['bi'], r['side']) in ok)

    # ── 5. 보조: 바꿔 넣기 ──
    if ins_paths:
        I = load(ins_paths)
        ib = {}
        for r in I:
            if r['v'] == 'base':
                ib[(r['bi'], r['s'], r['side'])] = r
        print('\n## 5. (보조) 같은 값 자리에 기인 22명을 바꿔 넣기 —— 자리 %d (판 · 시드 · 쪽), 원래 덱 승률 %.1f%%' % (len(ib), 100 * sum(r['w'] for r in ib.values()) / max(1, len(ib))))
        orig = collections.Counter(grp(r['k']) for r in ib.values())
        print('원래 그 칸: 기인 %d · 초월 %d' % (orig['K'], orig['6']))
        def idelta(v, m=None):
            rows = [r for r in I if r['v'] == v and (m is None or r['m'] == m)]
            if not rows:
                return None
            if m is None:
                d = collections.defaultdict(list)
                for r in rows:
                    d[(r['bi'], r['s'], r['side'])].append(r)
                rows = [dict(v_[0], w=sum(x['w'] for x in v_) / len(v_), mg=sum(x['mg'] for x in v_) / len(v_)) for v_ in d.values()]
            key = lambda r: (r['bi'], r['side'])
            return (mse(clus(rows, key, lambda r: r['w'])), mse(clus(rows, key, lambda r: r['w'] - ib[(r['bi'], r['s'], r['side'])]['w'])), mse(clus(rows, key, lambda r: r['mg'] - ib[(r['bi'], r['s'], r['side'])]['mg'])))
        has1 = any(r['v'] == 'ins1' for r in I)
        print('| 넣은 카드 | 승률 | 원래 덱 대비 %p | 남은 병력 몫 %p |' + (' 기능 값 (기능만 끔 대비) %p |' if has1 else '') + ' 효과 값 (기능 + 위세 끔 대비) %p |')
        tail = ' - | - |' if has1 else ' - |'
        d = idelta('imm')
        print('| 불멸 평균 | %.1f%% | %s | %s |' % (100 * d[0][0], pp(d[1]), pp(d[2])) + tail)
        d = idelta('ins0')
        print('| 기인 22명 평균 | %.1f%% | %s | %s |' % (100 * d[0][0], pp(d[1]), pp(d[2])) + tail)
        per = collections.defaultdict(lambda: collections.defaultdict(list))
        for r in I:
            per[(r['bi'], r['side'])][r['v']].append(r['w'])
        for a_, b_, label in [('imm', 'ins0', '불멸 평균 − 기인 평균'), ('ins0', 'ins2', '기인 효과(기능 + 위세) 값 평균')]:
            x = mse([sum(v_[a_]) / len(v_[a_]) - sum(v_[b_]) / len(v_[b_]) for v_ in per.values() if v_[a_] and v_[b_]])
            print('  %s: %s' % (label, pp(x)))
        out = []
        for k in kiin:
            d0 = idelta('ins0', k)
            if d0 is None:
                continue
            def fxv(v):
                rows = {(r['bi'], r['s'], r['side']): r for r in I if r['v'] == v and r['m'] == k}
                on = {(r['bi'], r['s'], r['side']): r for r in I if r['v'] == 'ins0' and r['m'] == k}
                if not rows:
                    return None
                dd = collections.defaultdict(list)
                for kk_, r in rows.items():
                    dd[(kk_[0], kk_[2])].append(on[kk_]['w'] - r['w'])
                return mse([sum(v_) / len(v_) for v_ in dd.values()])
            f1 = fxv('ins1')
            f2 = fxv('ins2')
            cells = [nm(k) + ' (%s%s)' % (C[k]['tag'], '' if C[k]['kiin'] else ' · 기능 없음'), '%.1f%%' % (100 * d0[0][0]), pp(d0[1]), pp(d0[2])]
            if has1:
                cells.append('-' if f1 is None else '%+.1f ±%.1f' % (100 * f1[0], 100 * f1[1]))
            cells.append('-' if f2 is None else '%+.1f ±%.1f' % (100 * f2[0], 100 * f2[1]))
            out.append((d0[1][0], '| ' + ' | '.join(cells) + ' |'))
        for _, l in sorted(out, key=lambda x: -x[0]):
            print(l)

if __name__ == '__main__':
    main()
