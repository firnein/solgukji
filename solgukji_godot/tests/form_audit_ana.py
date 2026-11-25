# 11/26 진형 분석 집계 (docs/진형_분석_1126.md) —— tests/form_audit.gd 출력(jsonl)을 읽는다
# 쓰는 법: PYTHONIOENCODING=utf-8 python tests/form_audit_ana.py table <폴더>        —— fa_base_*.jsonl 칸 위치별 현황표
#          PYTHONIOENCODING=utf-8 python tests/form_audit_ana.py final <폴더>        —— 안별 비교표 (fa_<이름>_*.jsonl, 이름은 문서의 재현 절 참고)
import os,sys
import json,glob,sys,statistics as stt,collections
RANGED={"궁병","책사","유생","술사","모사"}
def load(pat):
    out=[]
    for f in sorted(glob.glob(pat)):
        for l in open(f,encoding='utf-8'):
            if l.strip(): out.append(json.loads(l))
    return out
def units(b):
    for x in b['u']:
        d=dict(zip(['camp','slot','row','col','tag','tier','ranged','tt','tr','tm','ta','to','pd','ps','pu','by','dmg','taken','max','alive','ult'],x))
        if not d['alive'] and d['to']<0: d['to']=b['len']
        yield d
def pos(d):
    r=d['row']; ln='전열' if r<=1 else ('중열' if r==2 else '후열')
    return ln+('·가운데' if d['col']==2 else '·측면')
def med(a): return round(stt.median(a),1) if a else '-'
def mean(a): return round(sum(a)/len(a),2) if a else '-'
def summarize(B, filt=lambda b,d:True, key=pos):
    g=collections.defaultdict(list)
    for b in B:
        tot={'A':0,'B':0}; rog={'A':0,'B':0}
        for d in units(b): tot[d['camp']]+=max(0,d['dmg']); rog[d['camp']]+= d['tag']=='도적'
        for d in units(b):
            if not filt(b,d): continue
            d['share']=d['dmg']/max(1,tot[d['camp']]); d['len']=b['len']; d['foe_rog']=rog['B' if d['camp']=='A' else 'A']
            g[key(d)].append(d)
    rows=[]
    for k in sorted(g):
        L=g[k]; n=len(L)
        tch=[d['tt'] for d in L if d['tt']>=0]
        RL=[d for d in L if d['foe_rog']>0]
        rt=[d['tr'] for d in RL if d['tr']>=0]
        surv=[(d['to'] if d['to']>=0 else d['len'])/max(0.1,d['len']) for d in L]
        pre=[d['pd']/max(1,d['dmg']) for d in L if d['tt']>=0 and d['dmg']>0]
        rows.append(dict(k=k,n=n,touch=round(len(tch)/n,2),t_touch=med(tch),rog_n=len(RL),rog_bite=round(len(rt)/max(1,len(RL)),2),t_rog=med(rt),
            dead=round(sum(1 for d in L if not d['alive'])/n,2),surv=mean(surv),taken=mean([d['taken']/max(1,d['max']) for d in L]),
            share=mean([d['share'] for d in L]),pre=mean(pre),len=mean([d['len'] for d in L])))
    return rows
def pr(rows,cols):
    print('|'+'|'.join(cols)+'|'); 
    for r in rows: print('|'+'|'.join(str(r[c]) for c in cols)+'|')

def table(B):
    
    def cls(d):
        r=d['row']; ln='전열' if r<=1 else ('중열' if r==2 else '후열')
        c='가운데' if d['col']==2 else ('바깥' if d['col'] in (0,4) else '안쪽')
        return ln+'·'+c
    for title,flt in [('원거리·책략',lambda d:d['ranged']),('근접',lambda d:not d['ranged'])]:
        g=collections.defaultdict(list)
        for b in B:
            U=list(units(b)); tot={'A':0,'B':0}
            for d in U: tot[d['camp']]+=max(0,d['dmg'])
            for d in U:
                if not flt(d): continue
                d['fr']=sum(1 for e in U if e['camp']!=d['camp'] and e['tag']=='도적'); d['len']=b['len']; d['share']=d['dmg']/max(1,tot[d['camp']])
                g[cls(d)].append(d)
        print('##',title)
        print('|칸|부대 수|맞닿음 비율|첫 맞닿음(초, 중앙값)|그때까지 기술|그때까지 고유기|그때까지 피해 몫|도적 물림(상대 도적 있는 판)|도적 첫 물림(초)|버틴 시간(판 길이 대비)|받은 피해/최대 병력|진영 피해 몫|')
        order=['전열·가운데','전열·안쪽','전열·바깥','중열·가운데','중열·안쪽','중열·바깥','후열·가운데','후열·안쪽','후열·바깥']
        for k in order:
            L=g.get(k,[])
            if len(L)<20: continue
            T=[d for d in L if d['tt']>=0]; R=[d for d in L if d['fr']>0]; rt=[d['tr'] for d in R if d['tr']>=0]
            print(f"|{k}|{len(L)}|{len(T)/len(L):.0%}|{med([d['tt'] for d in T])}|{mean([d['ps'] for d in T])}|{mean([d['pu'] for d in T])}|{mean([d['pd']/max(1,d['dmg']) for d in T if d['dmg']>0]) if T else '-'}|{len(rt)/max(1,len(R)):.0%}|{med(rt)}|{mean([(d['to'] if d['to']>=0 else d['len'])/d['len'] for d in L])}|{mean([d['taken']/max(1,d['max']) for d in L])}|{mean([d['share'] for d in L])}|")

def stat(B, sides=None):
    # sides: dict bi -> list of camps to look at (None = both)
    R=[];W=[];RW=[];NW=[]
    for b in B:
        U=list(units(b)); cps=sides.get(b['bi'],[]) if sides is not None else ['A','B']
        for cp in cps:
            w=b['win'] if cp=='A' else 1-b['win']; W.append(w)
            if any(e['camp']==cp and e['tag']=='도적' for e in U): RW.append(w)
            fr=sum(1 for e in U if e['camp']!=cp and e['tag']=='도적')
            if fr:
                R+= [d for d in U if d['camp']==cp and d['ranged'] and d['row']>=2 and d['col']!=2]
    rt=[d['tr'] for d in R if d['tr']>=0]
    return f"{len(rt)/len(R):.1%}|{med(rt)}|{sum(not d['alive'] for d in R)/len(R):.0%}|{mean([(d['to'] if d['to']>=0 else 0) for d in R if not d['alive']])}|{mean([d['dmg'] for d in R]):.0f}|{mean(RW):.3f}|{mean([b['len'] for b in B])}"

def L(n): return load(os.path.join(D, f'fa_{n}_*.jsonl'))
def pls(n): return {b['bi']:b['pl'] for b in L(n)}

def final():
    print('|안|판|중·후열 측면 원거리 도적 물림|첫 물림(초)|무너짐|무너진 시각(초)|평균 준 피해|도적 든 진영 승률|판 길이|')
    print('|기준|650|'+stat(L('base'))+'|')
    print('|(나) intercept|650|'+stat(L('icpt'))+'|')
    print('|(다) form_guard|650|'+stat(L('fg'))+'|')
    print('|참고 no_back_basic|650|'+stat(L('nbb'))+'|')
    s=pls('spg'); print('|(가) 기준(같은 판)|%d|'%len(s)+stat(L('spb'),s)+'|'); print('|(가) 창병 후군 배치만|%d|'%len(s)+stat(L('spp'),s)+'|'); print('|(가) 배치+spear_rear_ok+rear_guard|%d|'%len(s)+stat(L('spg'),s)+'|')
    a0={b['bi']:['A'] for b in L('auA0')}; b0={b['bi']:['B'] for b in L('auB0')}
    def cat(x,y): return [dict(b,bi=('A',b['bi'])) for b in L(x)]+[dict(b,bi=('B',b['bi'])) for b in L(y)]
    sd={('A',k):['A'] for k in a0}; sd.update({('B',k):['B'] for k in b0})
    print('|(라) 자동 배치 기준|1300|'+stat(cat('auA0','auB0'),sd)+'|'); print('|(라) 자동 배치+outer_guard_place|1300|'+stat(cat('auA1','auB1'),sd)+'|')
    s=pls('rfp'); print('|후열↔전열 맞바꾸기 기준|%d|'%len(s)+stat(L('rfb'),s)+'|'); print('|후열 원거리를 전열로|%d|'%len(s)+stat(L('rfp'),s)+'|')


if __name__=='__main__':
    D=sys.argv[2]
    if sys.argv[1]=='table': table(load(os.path.join(D,'fa_base_*.jsonl')))
    else: final()
