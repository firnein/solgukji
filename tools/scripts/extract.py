"""HTML 프로토타입의 데이터 상수를 JSON으로 뽑는다. 책략방어(res)는 방어로 옮긴다 (drop_res, 11/7).

실행: python -I tools/scripts/extract.py solgukji-9.html solgukji_godot/data/game.json
"""
import json, re, sys

src = open(sys.argv[1], encoding='utf-8').read() if __name__ == '__main__' else ''
NAMES = ['TIER','RATE','FAC','SYN','TAGSYN','TAGSYN_STEP','SYN_STEP','STATUS','K',
         'CARDDEF','RECDEF','ITEMDEF','SKILLPOOL','SKMUL','SKDUR','PSVTITLE','PSVNM',
         'FORM','FORMBOON','LINE','AFF','FRONT_WANT','LINES','TAGORDER','IGRADE','STATNM',
         'QPV','QUESTS','QUEST_BASE','DRAWS','PICKS','QUEST_REWARD','RANDOM_GRANT',
         'BOTNAME','STYLES','DROP','UNIQUE_PHASES','PVP_BASE','TGTNM','TAGPATH']

def grab(name):
    m = re.search(r'const\s+' + name + r'\s*=\s*', src)
    i = m.end(); open_ch = src[i]; close_ch = {'[':']','{':'}'}[open_ch]
    depth, j, q = 0, i, None
    while True:
        ch = src[j]
        if q:
            if ch == q: q = None
        elif ch in "'\"": q = ch
        elif src.startswith('/*', j): j = src.index('*/', j) + 1
        elif ch == open_ch: depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth == 0: return src[i:j+1]
        j += 1

def to_json(js):
    js = re.sub(r'/\*.*?\*/', '', js, flags=re.S)
    js = re.sub(r"'\s*\+\s*'", '', js)          # 'a' + 'b' 문자열 이어붙이기
    out = []
    # 문자열 밖에서만 변환한다 (원본 문자열에 이스케이프는 없다)
    parts = re.split(r"('[^']*')", js)
    for k, p in enumerate(parts):
        if k % 2:
            out.append(json.dumps(p[1:-1], ensure_ascii=False))
        else:
            p = re.sub(r'([{,]\s*)([A-Za-z_][\w]*)\s*:', r'\1"\2":', p)
            p = re.sub(r'([{,]\s*)(\d+)\s*:', r'\1"\2":', p)
            p = re.sub(r'(?<![\w.])(-?)\.(\d)', r'\g<1>0.\2', p)
            p = re.sub(r',(\s*[\]}])', r'\1', p)
            out.append(p)
    return json.loads(''.join(out))

# ───────── 책략방어(res) 정리 (11/7) ─────────
# 11/6 사용자 결정 #15 "마법 개념 삭제 · 모두 그냥 피해로 통일 · 책략 / 책략방어 제거" —— 원본 HTML 의 책략방어를 방어로 옮긴다.
# 한 효과(아이템 · 기술)에 방어와 책략방어가 같이 있으면 큰 값 하나만 방어로 남긴다 (오왕검 방어 0.3 · 책략방어 0.18 → 방어 0.3).
# 카드 능력치 칸(CARDDEF 8번 '책방')은 그대로 둔다 —— DB.merge_stats 가 방어에 합친다.
REN_KEY = {'resDown': 'defDown'}                              # 기술 효과 —— 책략방어 깎기 → 방어 깎기
REN_PSV = {'allyRes': 'allyDef', 'resBreak': 'defBreak'}       # 원본 패시브 이름 (PSVNM · 카드의 psv —— 지금 게임은 쓰지 않는다)


def _fix_skill(x):
    """기술 정의(SKILLPOOL · 카드 안의 기술) —— resDown 키 · 버프 stat 과 kind 의 'res' · 원본 패시브 이름"""
    if isinstance(x, list):
        return [_fix_skill(v) for v in x]
    if not isinstance(x, dict):
        return x
    assert not ('resDown' in x and 'defDown' in x), x
    out = {}
    for k, v in x.items():
        k = REN_KEY.get(k, k)
        if k in ('stat', 'kind') and v == 'res':      # 버프 능력치 · 원본 '교란'(kind res = 책략방어 깎기)
            v = 'def'
        elif k == 'psv' and v in REN_PSV:
            v = REN_PSV[v]
        else:
            v = _fix_skill(v)
        out[k] = v
    return out


def drop_res(data):
    for r in data['ITEMDEF']:      # [id, 이름, 등급, 병종, 주 능력치, 값, 보조 능력치, 값, 발동, 쓰임]
        if 'res' not in (r[4], r[6]):
            continue
        if {r[4], r[6]} == {'res', 'def'}:      # 방어 · 책략방어가 같이 —— 큰 값 하나만 방어로, 보조 칸은 비운다
            r[4], r[5], r[6], r[7] = 'def', max(r[5], r[7]), '', 0.0
        else:
            r[4], r[6] = ('def' if r[4] == 'res' else r[4]), ('def' if r[6] == 'res' else r[6])
    data['SKILLPOOL'] = {t: _fix_skill(p) for t, p in data['SKILLPOOL'].items()}
    for r in data['CARDDEF']:
        r[12] = _fix_skill(r[12])
    for t in data['TAGSYN'].values():
        if t['stat'] == 'res':
            t['stat'] = 'def'
        t['d'] = t['d'].replace('책략방어', '방어')
    for a in data['AFF'].values():
        for side in ('b', 'p'):
            if 'res' in a[side]:
                assert 'def' not in a[side], a
                a[side] = {('def' if k == 'res' else k): v for k, v in a[side].items()}
    for f in data['FORMBOON'].values():
        if f['stat'] == 'res':
            f['stat'] = 'def'
    data['STATNM'].pop('res', None)
    for nm in ('PSVNM', 'PSVTITLE'):
        data[nm] = {REN_PSV.get(k, k): v.replace('책략방어', '방어') for k, v in data[nm].items()}
    left = json.dumps(data, ensure_ascii=False)
    for w in ('"res"', 'resDown', 'allyRes', 'resBreak', '책략방어'):
        assert w not in left, w
    return data


if __name__ == '__main__':
    data = {n: to_json(grab(n)) for n in NAMES}
    drop_res(data)
    json.dump(data, open(sys.argv[2], 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print({n: len(v) for n, v in data.items()})
