"""HTML 프로토타입의 데이터 상수를 JSON으로 뽑는다."""
import json, re, sys

src = open(sys.argv[1], encoding='utf-8').read()
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

data = {n: to_json(grab(n)) for n in NAMES}
json.dump(data, open(sys.argv[2], 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print({n: len(v) for n, v in data.items()})
