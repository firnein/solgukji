# 실제 온라인 대전 기록 → 재현용 전투 목록 (기록은 읽기만)
# playlog_online/*.jsonl 의 pvp battle_start 와 같은 ts 의 battle_end 를 묶는다. 사람끼리 대전은 양쪽에 두 번 남으니 (씨앗 + 양쪽 카드) 로 하나만.
# 카드는 [이름, 등급, 병종] 그대로 · 줄(line) · 장비(items, 11/22 이후 기록)는 battle_end units 에서. tests/real_myth_swap.gd 가 이것을 읽는다.
# 실행: python tools/scripts/real_battles.py "%APPDATA%/Godot/app_userdata/솔국지/playlog_online" C:/tmp/real_battles.json
import json, glob, os, sys, collections
src, dst = sys.argv[1], sys.argv[2]
out = []
seen = set()
stat = collections.Counter()
for f in sorted(glob.glob(os.path.join(src, '*.jsonl'))):
    lines = []
    for l in open(f, encoding='utf-8', errors='ignore'):
        try:
            lines.append(json.loads(l))
        except Exception:
            stat['bad_line'] += 1
    for i, d in enumerate(lines):
        if d.get('ev') != 'battle_start' or d.get('kind') != 'pvp':
            continue
        stat['pvp'] += 1
        if 'foe' not in d or not d['foe'].get('cards'):
            stat['no_foe'] += 1
            continue
        end = None
        for d2 in lines[i + 1:i + 40]:
            if d2.get('ev') == 'battle_end' and d2.get('ts') == d.get('ts'):
                end = d2
                break
            if d2.get('ev') == 'battle_start':
                break
        if end is None:
            stat['no_end'] += 1
            continue
        me = [tuple(c) for c in d['me']['cards']]
        foe = [tuple(c) for c in d['foe']['cards']]
        key = (d['seed'], frozenset([tuple(sorted(me)), tuple(sorted(foe))]))
        if key in seen:
            stat['dup'] += 1
            continue
        seen.add(key)
        units = end.get('units', [])
        ua = [u for u in units if u.get('camp') == 'A']
        ub = [u for u in units if u.get('camp') == 'B']
        def side(cards, us, form, morale, tac):
            return {'cards': [list(c) for c in cards], 'lines': [u.get('line', '') for u in us] if len(us) == len(cards) else [],
                    'items': [u.get('items', []) for u in us] if len(us) == len(cards) and any('items' in u for u in us) else [],
                    'form': form, 'morale': morale, 'tac': tac}
        b = {'file': os.path.basename(f), 'seed': d['seed'], 'day': d.get('day', 0), 'phase': d.get('phase', 0), 'foe_human': d.get('foe_human', False),
             'me': side(me, ua, d.get('form', 'eorin'), d.get('morale', 100), d.get('tac', '')),
             'foe': side(foe, ub, d.get('foe_form', 'eorin'), d.get('foe_morale', 100), d.get('foe_tac', '')),
             'me_plan': (d.get('tk') or {}).get('plan', []), 'me_own': (d.get('tk') or {}).get('own', []), 'foe_plan': d.get('foe_plan', []),
             'win': bool(end.get('win', False)), 'draw': bool(end.get('draw', False)),
             'left': end.get('troops', 0), 'foe_left': end.get('foe_troops', 0)}
        out.append(b)
json.dump(out, open(dst, 'w', encoding='utf-8'), ensure_ascii=False)
print(dict(stat), 'battles', len(out))
myth_days = collections.Counter()
for b in out:
    for s in ('me', 'foe'):
        if any(int(c[1]) == 8 for c in b[s]['cards']):
            myth_days[b['day']] += 1
print('myth sides by day', sorted(myth_days.items()), 'total', sum(myth_days.values()))
print('with items', sum(1 for b in out if b['me']['items']), 'with lines', sum(1 for b in out if b['me']['lines']), 'with plan', sum(1 for b in out if b['me_plan'] or b['foe_plan']))
print('full 9', sum(1 for b in out for s in ('me', 'foe') if len(b[s]['cards']) == 9), 'sides', 2 * len(out))
