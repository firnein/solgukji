# 11/26 진형 분석 집계 (docs/진형_분석_1126.md) —— tests/form_audit.gd 출력(jsonl)을 읽는다
# 쓰는 법: PYTHONIOENCODING=utf-8 python tests/form_audit_ana.py table <폴더>        —— fa_base_*.jsonl 칸 위치별 현황표
#          PYTHONIOENCODING=utf-8 python tests/form_audit_ana.py final <폴더>        —— 안별 비교표 (fa_<이름>_*.jsonl, 이름은 문서의 재현 절 참고)
#          PYTHONIOENCODING=utf-8 python tests/form_audit_ana.py mid <폴더> [0|1|2]  —— 11/26 원거리 가운데 배치 전/후 (fa_oo · fa_nn<n> · fa_no<n> · fa_on<n> · fa_base, --mid 로 만든 것)
import os,sys
import json,glob,sys,statistics as stt,collections
RANGED={"궁병","책사","유생","모사"}
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


# ───── 11/26 원거리 가운데 배치 (DB.mid_place) 전/후 ─────
def _top(b, cp):
    sl=b['top'][0 if cp=='A' else 1]
    if sl<0: return None
    for d in units(b):
        if d['camp']==cp and d['slot']==sl: return d
    return None
def _side_rows(B, cps):
    """판 · 진영마다 한 줄: 승 · 가장 강한 원거리의 값"""
    out={}
    for b in B:
        U=list(units(b)); tot={'A':0,'B':0}
        for d in U: tot[d['camp']]+=max(0,d['dmg'])
        for cp in cps:
            foe='B' if cp=='A' else 'A'
            t=_top(b,cp)
            R=[d for d in U if d['camp']==cp and d['ranged']]
            out[(b['bi'],cp)]=dict(win=b['win'] if cp=='A' else 1-b['win'], fr=sum(1 for e in U if e['camp']==foe and e['tag']=='도적'), top=t,
                share=(max(0,t['dmg'])/max(1,tot[cp])) if t else None, sig=sorted((d['slot'],d['tag'],d['tier'],d['max']) for d in U if d['camp']==cp),
                rn=len(R), rbite=sum(1 for d in R if d['tr']>=0), rdead=sum(1 for d in R if not d['alive']), rdmg=sum(max(0,d['dmg']) for d in R), tot=tot[cp], len=b['len'])
    return out
def _fmt(rows, keys=None):
    L=[rows[k] for k in (keys if keys is not None else rows)]
    T=[r for r in L if r['top']]
    RG=[r for r in T if r['fr']>0]
    bite=sum(1 for r in RG if r['top']['tr']>=0)/max(1,len(RG))
    out=sum(1 for r in T if r['top']['col'] in (0,4))/max(1,len(T))
    alive=sum(1 for r in T if r['top']['alive'])/max(1,len(T))
    dmg=sum(max(0,r['top']['dmg']) for r in T)/max(1,len(T))
    share=sum(r['share'] for r in T)/max(1,len(T))
    taken=sum(r['top']['taken']/max(1,r['top']['max']) for r in T)/max(1,len(T))
    RA=[r for r in L if r['fr']>0]
    rb=sum(r['rbite'] for r in RA)/max(1,sum(r['rn'] for r in RA))
    win=sum(r['win'] for r in L)/max(1,len(L))
    return f"{len(L)}|{out:.1%}|{bite:.1%} ({len(RG)})|{alive:.1%}|{taken:.2f}|{dmg:.0f}|{share:.1%}|{rb:.1%}|{sum(r['rdmg'] for r in L)/max(1,len(L)):.0f}|{win:.3f}"
def _paired(new, old, keys):
    d=[new[k]['win']-old[k]['win'] for k in keys]
    if len(d)<2: return '-'
    m=sum(d)/len(d); sd=stt.pstdev(d)
    return f"{m*100:+.1f}pt ±{1.96*sd/len(d)**0.5*100:.1f} (바뀐 승패 {sum(1 for x in d if x!=0)})"
def mid(n):
    H='|조건|진영 수|최강 원거리 바깥 열|최강 원거리 도적 물림 (상대 도적 있는 진영 수)|최강 생존|최강 받은 피해/최대|최강 준 피해|최강 피해 몫|원거리 전체 도적 물림|원거리 전체 준 피해(진영)|승률|'
    print(H); print('|'+'---|'*11)
    oo=_side_rows(L('oo'),['A','B']); nn=_side_rows(L(f'nn{n}'),['A','B'])
    noA=_side_rows(L(f'no{n}'),['A']); onB=_side_rows(L(f'on{n}'),['B'])
    noB=_side_rows(L(f'no{n}'),['B']); onA=_side_rows(L(f'on{n}'),['A'])
    one=dict(noA); one.update(onB)       # 새 배치인 쪽 (상대는 옛 배치)
    oth=dict(noB); oth.update(onA)       # 옛 배치인 쪽 (상대가 새 배치)
    base=L('base')
    if base: print('|기록 그대로 (사람이 놓은 편성 포함)|'+_fmt(_side_rows(base,['A','B']))+'|')
    print('|옛 자동 배치끼리 (기준선)|'+_fmt(oo)+'|')
    print(f'|새 배치끼리 (aff={n})|'+_fmt(nn)+'|')
    print('|한쪽만 새 배치 —— 새 배치 쪽|'+_fmt(one)+'|')
    print('|한쪽만 새 배치 —— 옛 배치 쪽(상대)|'+_fmt(oth)+'|')
    ch=[k for k in one if one[k]['sig']!=oo[k]['sig']]      # 배치가 실제로 달라진 진영
    print(f'|배치가 달라진 진영만: 옛 배치(기준선)|'+_fmt(oo,ch)+'|')
    print(f'|배치가 달라진 진영만: 새 배치 (상대는 옛 배치)|'+_fmt(one,ch)+'|')
    mv=[k for k in ch if one[k]['top'] and oo[k]['top'] and one[k]['top']['slot']!=oo[k]['top']['slot']]
    print(f'|최강 원거리가 옮겨진 진영만: 옛 배치|'+_fmt(oo,mv)+'|')
    print(f'|최강 원거리가 옮겨진 진영만: 새 배치|'+_fmt(one,mv)+'|')
    ob=[k for k in mv if oo[k]['top']['col'] in (0,4)]
    print(f'|최강이 바깥 열에서 나온 진영만: 옛 배치|'+_fmt(oo,ob)+'|')
    print(f'|최강이 바깥 열에서 나온 진영만: 새 배치|'+_fmt(one,ob)+'|')
    print()
    print('승률 차 (같은 판 · 같은 씨앗 짝, 새 배치 쪽 − 기준선 같은 쪽):')
    print('  한쪽만 새 배치, 모든 진영:', _paired(one,oo,list(one)))
    print('  한쪽만 새 배치, 배치가 달라진 진영:', _paired(one,oo,ch))
    print('  한쪽만 새 배치, 최강이 옮겨진 진영:', _paired(one,oo,mv))
    print('  한쪽만 새 배치, 최강이 바깥 열에서 나온 진영:', _paired(one,oo,ob))
    kA=[k for k in oo if k[1]=='A']
    print('  새 배치끼리 − 옛 배치끼리 (A 쪽 = 기록의 내 쪽):', _paired(nn,oo,kA), '· A 승률 %.3f → %.3f'%(sum(oo[k]['win'] for k in kA)/len(kA), sum(nn[k]['win'] for k in kA)/len(kA)))
    print('  판 길이: 옛 %.1f → 새 %.1f초'%(sum(oo[k]['len'] for k in kA)/len(kA), sum(nn[k]['len'] for k in kA)/len(kA)))


if __name__=='__main__':
    D=sys.argv[2]
    if sys.argv[1]=='table': table(load(os.path.join(D,'fa_base_*.jsonl')))
    elif sys.argv[1]=='mid': mid(sys.argv[3] if len(sys.argv)>3 else '1')
    else: final()
