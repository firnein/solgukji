# -*- coding: utf-8 -*-
"""인물 줄기 · 인연 조합 · 장수 고유 기술 —— data/lines.json 을 만든다 (11/2 사용자 요청).

  python tools/scripts/lines.py

1) 줄기: 최고 등급이 불멸 · 신화인 인물은 희귀(4)부터 최고 등급까지 같은 인물 카드가 끊기지 않게 한다.
   빈 칸은 새 카드로 채우고, 능력치는 그 인물의 가장 가까운 등급 카드 × (같은 병종 등급 평균 비)로 정한다.
2) 조합: 희귀 이상 모든 장수 =  같은 인물의 한 등급 아래 + 인연 인물 카드 + (같은 세력 · 병종 재료).
   등급별 재료 수는 예전과 같다 (희귀 4 · 전설 4 · 초월 3 · 불멸 5 · 신화 4 + 유니크 아이템).
3) 기술: 희귀 이상 인물마다 고유 일반 기술 하나 (첫 기술). 수치는 신화 기준이 아니라 기술 표(SKMUL)로 등급마다 곱한다.
원본 game.json · cards_ext.json 은 그대로 두고 DB 가 불러올 때 덮어쓴다.
"""
import json, os, statistics

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "solgukji_godot", "data")
G = json.load(open(os.path.join(ROOT, "game.json"), encoding="utf-8"))
E = json.load(open(os.path.join(ROOT, "cards_ext.json"), encoding="utf-8"))

CARDS = [c for c in G["CARDDEF"] + E["cards"] if c[13] != "foe"]
BY_ID = {c[0]: c for c in CARDS}
person = lambda c: c[1].split(" ")[-1]
BASE = {"창병": "spear", "기병": "horse", "궁병": "bow", "도적": "rogue", "책사": "strat", "유생": "schol", "술사": "occul", "모사": "schem"}
T2 = {}
for c in CARDS:
    if c[2] == 2:
        T2.setdefault(c[3], []).append(c[0])

# ───────── 인연 (가까운 순) ─────────
REL = {
    "관우": "장비 유비 조운 주창 요화 마량 황충 마초 화타",
    "장비": "관우 유비 조운 마초 간옹 미축 황충",
    "조운": "유비 관우 장비 제갈량 마대 황충 공손찬",
    "유비": "관우 장비 제갈량 간옹 미축 법정 서서 조운 공손찬",
    "제갈량": "유비 방통 강유 서서 사마휘 마량 법정 주유 이적",
    "방통": "제갈량 사마휘 법정 유비 서서",
    "강유": "제갈량 마대 위연 종회 등애",
    "마초": "마대 마등 장비 방덕 조운",
    "마대": "마초 마등 위연 강유",
    "황충": "관우 위연 법정 하후연 조운",
    "위연": "황충 마대 강유 제갈량 유비",
    "법정": "유비 제갈량 방통 황충",
    "서서": "유비 제갈량 사마휘 방통",
    "사마휘": "제갈량 방통 서서 유비",
    "마량": "제갈량 관우 이적 유비",
    "조조": "하후돈 하후연 순욱 곽가 전위 허저 조인 정욱 가후 사마의",
    "하후돈": "조조 하후연 조인 전위 허저 이전",
    "하후연": "하후돈 조조 황충 장합 하후패",
    "허저": "전위 조조 마초 하후돈",
    "전위": "허저 조조 하후돈",
    "조인": "조조 하후돈 서황 우금 이전",
    "서황": "장료 조인 관우 우금 악진",
    "장료": "서황 관우 장합 악진 이전 감녕 손권",
    "장합": "장료 하후연 사마의 원소 곽회",
    "순욱": "조조 곽가 정욱 진군 유엽",
    "곽가": "조조 순욱 정욱 가후 유엽",
    "가후": "조조 곽가 사마의 장합",
    "사마의": "조조 장합 등애 제갈량 곽회",
    "정욱": "조조 순욱 곽가",
    "등애": "종회 사마의 강유",
    "종회": "등애 사마의 강유",
    "손권": "손책 주유 노숙 여몽 육손 감녕 태사자 주태",
    "손책": "주유 태사자 손권 정보 황개 대교",
    "주유": "손책 노숙 소교 황개 육손 정보 제갈량",
    "육손": "여몽 손권 주유 노숙",
    "여몽": "감녕 능통 손권 노숙 육손 관우",
    "감녕": "능통 여몽 손권 장료",
    "능통": "감녕 여몽 손권",
    "태사자": "손책 유비 손권",
    "정보": "황개 주유 손책",
    "황개": "정보 주유 손책",
    "노숙": "주유 손권 제갈량 여몽",
    "대교": "소교 손책 주유",
    "소교": "대교 주유 손책",
    "주태": "손권 여몽 정봉",
    "정봉": "주태 서성 정보",
    "엄백호": "손책 능조",
    "장소": "손권 노숙 손책",
    "여포": "진궁 초선 동탁 장료",
    "동탁": "여포 초선 원소",
    "초선": "여포 동탁",
    "진궁": "여포 조조",
    "원소": "원술 공손찬 안량 저수 심배 전풍 장합",
    "원술": "원소 손책 여포",
    "공손찬": "유비 조운 원소",
    "마등": "마초 마대",
    "방덕": "마초 관우",
    "장각": "장보 장량 좌자 화타",
    "좌자": "조조 우길 장각 화타",
    "화타": "관우 조조 좌자",
    "우길": "손책 좌자",
    "장로": "마초 장각",
    "관로": "조조",
    "장연": "장각",
}
REL = {k: v.split() for k, v in REL.items()}

# ───────── 줄기 빈 칸 칭호 ─────────
TITLE = {
    ("장비", 6): "연인 장비", ("장비", 7): "당양교 장비",
    ("조운", 6): "익군장군 조운", ("조운", 7): "단기구주 조운",
    ("손책", 6): "강동평정 손책", ("손책", 7): "회계태수 손책",
    ("감녕", 6): "절충장군 감녕",
    ("제갈량", 6): "융중대 제갈량", ("제갈량", 7): "출사표 제갈량",
    ("유비", 6): "한중왕 유비",
    ("장각", 6): "태평교주 장각",
    ("화타", 6): "마비산 화타",
    ("조조", 6): "연주목 조조", ("조조", 7): "위왕 조조",
    ("하후돈", 4): "하후돈", ("하후돈", 5): "맹장 하후돈",
    ("동탁", 4): "동탁", ("동탁", 5): "서량자사 동탁",
    ("위연", 4): "위연", ("위연", 5): "용장 위연",
    ("여포", 4): "여포", ("여포", 5): "효용 여포", ("여포", 6): "원문사극 여포", ("여포", 7): "호뢰관 여포",
    ("사마휘", 4): "사마휘", ("사마휘", 5): "은사 사마휘", ("사마휘", 6): "호호선생 사마휘", ("사마휘", 7): "명사 사마휘",
    ("진궁", 4): "진궁", ("진궁", 5): "중모현령 진궁", ("진궁", 6): "연주모사 진궁", ("진궁", 7): "하비충절 진궁",
    ("허저", 6): "호후 허저",
    ("마초", 6): "위진서량 마초",
    ("황충", 6): "후장군 황충",
    ("사마의", 6): "도독 사마의",
    ("가후", 6): "완성모주 가후",
    ("조인", 4): "조인", ("조인", 5): "자효 조인",
    ("장합", 4): "장합", ("장합", 5): "하간 장합",
    ("원소", 4): "원소", ("원소", 5): "발해태수 원소",
    ("전위", 4): "전위", ("전위", 5): "호위 전위", ("전위", 6): "쌍극 전위",
    ("서서", 4): "서서", ("서서", 5): "단복 서서", ("서서", 6): "격검 서서",
}

# ───────── 장수 고유 기술 (기준 수치 —— 등급마다 SKMUL 을 곱한다) ─────────
# k: phys / int, tgt: front1 · back1 · back2 · front3 · all · denseLine · line:후군 · line:선봉+전군
SPD = lambda a, d=2: {"amt": a, "dur": d}
AB = lambda st, a, tg="allyAll", d=2: {"stat": st, "amt": a, "dur": d, "tgt": tg}
SB = lambda st, a, d=2: {"stat": st, "amt": a, "dur": d}
ST = lambda k, v, d: {"k": k, "val": v, "dur": d}
SKILL = {
    # 창병
    "관우": dict(n="청룡언월", k="phys", tgt="front3", mult=1.45, exec=0.15, morale=6, cond="always"),
    "장비": dict(n="장판교 일갈", k="phys", tgt="denseLine", mult=1.1, morale=10, spd=SPD(-0.3), cond="dense:2|front_n:2"),
    "허저": dict(n="나신돌격", k="phys", tgt="front1", mult=1.75, pierce=0.3, selfBuff=SB("def", 0.3), cond="always"),
    "서황": dict(n="포위돌파", k="phys", tgt="line:선봉+전군", mult=1.15, spd=SPD(-0.2), cond="front_n:2|always"),
    "주태": dict(n="불사신", k="phys", tgt="front1", mult=1.2, selfBuff=SB("def", 0.45), stance=SPD(0.4), cond="hurt:0.75"),
    "하후돈": dict(n="발시담정", k="phys", tgt="front1", mult=1.6, morale=8, selfBuff=SB("atk", 0.25), cond="always"),
    "조인": dict(n="팔문금쇄진", k="phys", tgt="denseLine", mult=1.0, allyBuff=AB("def", 0.3, "allyFront"), stance=SPD(0.35), cond="hurt:0.8|ally_hurt:0.6"),
    "전위": dict(n="쌍철극", k="phys", tgt="front3", mult=1.35, selfBuff=SB("def", 0.25), stance=SPD(0.3), cond="always"),
    "방덕": dict(n="결사항전", k="phys", tgt="front1", mult=1.7, selfBuff=SB("atk", 0.3), cond="always"),
    # 기병
    "조운": dict(n="단기구주", k="phys", tgt="front1", mult=1.55, pierce=0.4, selfBuff=SB("spd", 0.3), cond="always"),
    "마초": dict(n="서량철기", k="phys", tgt="line:선봉+전군", mult=1.15, morale=8, spd=SPD(-0.3), cond="front_n:2|always"),
    "장료": dict(n="합비돌격", k="phys", tgt="back1", mult=1.7, morale=12, cond="always"),
    "손책": dict(n="강동평정", k="phys", tgt="front3", mult=1.3, morale=7, selfBuff=SB("atk", 0.2), cond="always"),
    "마대": dict(n="기습참격", k="phys", tgt="back1", mult=1.6, exec=0.2, cond="always"),
    "장합": dict(n="교변", k="phys", tgt="back2", mult=1.3, spd=SPD(-0.3), cond="always"),
    "동탁": dict(n="낙양방화", k="phys", tgt="denseLine", mult=1.15, morale=9, status=ST("burn", 0.08, 2), cond="dense:2|always"),
    "원소": dict(n="하북대군", k="phys", tgt="line:선봉+전군", mult=1.1, allyBuff=AB("atk", 0.15), cond="always"),
    "여포": dict(n="방천화극", k="phys", tgt="front3", mult=1.6, exec=0.2, morale=8, cond="always"),
    "마등": dict(n="서량기병", k="phys", tgt="front1", mult=1.45, spd=SPD(-0.25), cond="always"),
    "공손찬": dict(n="백마의종", k="phys", tgt="back2", mult=1.3, pierce=0.2, cond="always"),
    # 궁병
    "황충": dict(n="정군산 일격", k="phys", tgt="back1", mult=1.85, exec=0.15, cond="always"),
    "태사자": dict(n="신궁연사", k="phys", tgt="back2", mult=1.35, pierce=0.35, cond="always"),
    "하후연": dict(n="질풍사격", k="phys", tgt="denseLine", mult=1.1, spd=SPD(-0.3), selfBuff=SB("spd", 0.2), cond="dense:2|always"),
    "손권": dict(n="강동의 활", k="phys", tgt="line:후군", mult=1.15, allyBuff=AB("def", 0.15), cond="always"),
    "정보": dict(n="화살비", k="phys", tgt="all", mult=0.9, morale=5, cond="foe_n:3|always"),
    "황개": dict(n="고육화선", k="phys", tgt="denseLine", mult=1.0, status=ST("burn", 0.16, 3), cond="no_st:burn"),
    # 도적
    "여몽": dict(n="백의도강", k="phys", tgt="line:후군", mult=1.3, status=ST("flood", 0.1, 2), cond="always"),
    "감녕": dict(n="백기겁영", k="phys", tgt="back1", mult=1.75, morale=10, spd=SPD(-0.25), cond="always"),
    "능통": dict(n="결사호위", k="phys", tgt="front1", mult=1.5, allyBuff=AB("def", 0.2, "allyFront"), cond="always"),
    "정봉": dict(n="설중분전", k="phys", tgt="front3", mult=1.25, selfBuff=SB("atk", 0.25), cond="always"),
    "위연": dict(n="자오곡 기습", k="phys", tgt="back2", mult=1.4, status=ST("plague", 6, 3), cond="always"),
    "엄백호": dict(n="산월약탈", k="phys", tgt="back1", mult=1.45, morale=6, cond="always"),
    "장연": dict(n="흑산유격", k="phys", tgt="back2", mult=1.25, spd=SPD(-0.25), cond="always"),
    # 책사
    "제갈량": dict(n="팔진도", k="int", tgt="all", mult=0.95, foeSpd=SPD(-0.3), allyBuff=AB("res", 0.2), cond="foe_n:3|always"),
    "방통": dict(n="연환계", k="int", tgt="denseLine", mult=0.9, status=ST("burn", 0.14, 3), spd=SPD(-0.25), cond="dense:2|no_st:burn"),
    "곽가": dict(n="십승십패", k="int", tgt="line:후군", mult=1.2, resDown={"amt": -0.3, "dur": 2}, morale=8, cond="always"),
    "육손": dict(n="이릉화공", k="int", tgt="denseLine", mult=0.85, status=ST("burn", 0.18, 3), cond="dense:2|no_st:burn"),
    "강유": dict(n="구벌중원", k="int", tgt="front3", mult=1.15, morale=8, allyBuff=AB("atk", 0.15, "allyFront"), cond="always"),
    "주유": dict(n="적벽화공", k="int", tgt="all", mult=0.85, status=ST("burn", 0.12, 3), cond="foe_n:3|no_st:burn"),
    "마량": dict(n="백미지책", k="int", tgt="back2", mult=1.25, resDown={"amt": -0.3, "dur": 2}, cond="always"),
    "종회": dict(n="벌촉지책", k="int", tgt="line:선봉+전군", mult=1.1, morale=8, cond="always"),
    # 유생
    "유비": dict(n="인덕지치", k="int", tgt="all", mult=0.75, tHeal=0.08, cleanse=1, allyBuff=AB("res", 0.15), cond="ally_hurt:0.75|ally_st"),
    "순욱": dict(n="왕좌지재", k="int", tgt="all", mult=0.7, tHeal=0.06, allyBuff=AB("def", 0.2), cond="ally_hurt:0.85"),
    "노숙": dict(n="합종연횡", k="int", tgt="all", mult=0.8, heal=10, rally=True, allyBuff=AB("res", 0.2), cond="ally_morale:90|ally_hurt:0.8"),
    "법정": dict(n="기책보은", k="int", tgt="front3", mult=1.15, morale=8, allyBuff=AB("atk", 0.2, "allyFront"), cond="always"),
    "서서": dict(n="격검유협", k="int", tgt="front3", mult=1.2, allyBuff=AB("def", 0.2, "allyFront"), cond="always"),
    "사마휘": dict(n="수경천거", k="int", tgt="all", mult=0.7, heal=12, rally=True, allyBuff=AB("res", 0.25), cond="ally_morale:90|ally_hurt:0.8"),
    "대교": dict(n="강동이교", k="int", tgt="front3", mult=0.7, tHeal=0.1, allyBuff=AB("res", 0.2), cond="ally_hurt:0.75"),
    "소교": dict(n="경국지색", k="int", tgt="all", mult=0.8, morale=10, heal=8, rally=True, cond="foe_morale|ally_morale:85"),
    "장소": dict(n="강동문신", k="int", tgt="all", mult=0.7, allyBuff=AB("def", 0.2), cleanse=1, cond="ally_st|ally_hurt:0.7"),
    # 술사
    "장각": dict(n="황천당립", k="int", tgt="all", mult=0.85, status=ST("confuse", 1, 1), morale=8, cond="foe_n:3"),
    "좌자": dict(n="둔갑술", k="int", tgt="front3", mult=1.0, status=ST("confuse", 1, 1), foeSpd=SPD(-0.3), cond="always"),
    "화타": dict(n="청낭서", k="int", tgt="front3", mult=0.85, tHeal=0.1, cleanse=2, cond="ally_hurt:0.7|ally_st"),
    "장로": dict(n="오두미도", k="int", tgt="all", mult=0.8, status=ST("plague", 6, 3), cond="no_st:plague"),
    "우길": dict(n="강동신선", k="int", tgt="front3", mult=1.0, status=ST("confuse", 1, 1), morale=6, cond="always"),
    "관로": dict(n="천기점괘", k="int", tgt="back2", mult=1.2, resDown={"amt": -0.35, "dur": 2}, cond="always"),
    # 모사
    "조조": dict(n="간웅지략", k="int", tgt="all", mult=1.0, morale=9, allyBuff=AB("atk", 0.15), cond="foe_morale|foe_n:3"),
    "사마의": dict(n="낭고지계", k="int", tgt="line:후군", mult=1.25, resDown={"amt": -0.3, "dur": 2}, morale=8, cond="always"),
    "가후": dict(n="독사지계", k="int", tgt="back2", mult=1.35, status=ST("plague", 8, 3), cond="always"),
    "초선": dict(n="미인계", k="int", tgt="front3", mult=0.95, status=ST("confuse", 1, 1), morale=10, cond="always"),
    "정욱": dict(n="십면매복", k="int", tgt="all", mult=1.05, foeSpd=SPD(-0.25), morale=7, cond="foe_n:3|always"),
    "등애": dict(n="음평기습", k="int", tgt="back1", mult=1.5, morale=10, cond="always"),
    "원술": dict(n="전국옥새", k="int", tgt="all", mult=0.95, morale=7, allyBuff=AB("def", 0.1), cond="always"),
    "진궁": dict(n="충절지책", k="int", tgt="line:선봉+전군", mult=1.2, resDown={"amt": -0.3, "dur": 2}, morale=7, cond="always"),
}


def main():
    per = {}
    for c in CARDS:
        if c[2] >= 3:
            per.setdefault(person(c), {}).setdefault(c[2], []).append(c[0])
    # 같은 병종 · 등급 평균 능력치
    avg = {}
    for c in CARDS:
        avg.setdefault((c[3], c[2]), []).append(c[5:10])
    avg = {k: [statistics.mean(x[i] for x in v) for i in range(5)] for k, v in avg.items()}
    std = {t: (int(statistics.median([c[10] for c in CARDS if c[2] == t])), int(statistics.median([c[11] for c in CARDS if c[2] == t]))) for t in range(4, 9)}

    new_cards = []
    n = 0
    for p, ts in per.items():
        top = max(ts)
        if top < 7:
            continue
        for t in range(4, top + 1):
            if t in ts:
                continue
            assert (p, t) in TITLE, (p, t)
            ref_t = min((x for x in ts if x >= 4), key=lambda x: (abs(x - t), -x))
            ref = BY_ID[ts[ref_t][0]]
            a0, a1 = avg[(ref[3], ref_t)], avg[(ref[3], t)]
            st = [round(ref[5 + i] * a1[i] / a0[i]) if a0[i] > 0 else ref[5 + i] for i in range(5)]
            st[4] = ref[9]       # 속도는 등급으로 크게 바뀌지 않는다 —— 그 인물 그대로
            n += 1
            cid = "L%02d" % n
            psv = (ref[12] or {}).get("psv") if isinstance(ref[12], dict) else None
            card = [cid, TITLE[(p, t)], t, ref[3], ref[4]] + st + [std[t][0], std[t][1], {"n": "", "eff": {}, "psv": psv},
                    "immortal" if t == 7 else ("myth" if t == 8 else ""), ""]
            new_cards.append(card)
            BY_ID[cid] = card
            ts[t] = [cid]

    allc = list(BY_ID.values())
    by_pt = {}
    for c in allc:
        by_pt.setdefault((person(c), c[2]), c[0])
    used = {}

    def pick(c, t, exclude):
        """c 에 넣을 t 등급 재료 하나 —— 인연 인물 > 같은 세력 같은 병종 > 같은 세력 > 같은 병종 (덜 쓰인 것 먼저)"""
        p = person(c)
        cands = []
        for i, r in enumerate(REL.get(p, [])):
            k = by_pt.get((r, t))
            if k and k not in exclude:
                cands.append((0, i + 1.5 * used.get(k, 0), k))      # 인연 순서가 먼저, 너무 겹치면 다음 인연으로
        if not cands:
            for x in allc:
                if x[2] != t or x[0] in exclude or person(x) == p or x[13] in ("myth", "immortal"):
                    continue
                rank = 1 if (x[4] == c[4] and x[3] == c[3]) else (2 if x[4] == c[4] else (3 if x[3] == c[3] else 9))
                if rank < 9:
                    cands.append((rank, used.get(x[0], 0), x[0]))
        cands.sort()
        k = cands[0][2]
        used[k] = used.get(k, 0) + 1
        return k

    recipes = {}
    for c in sorted(allc, key=lambda x: (x[2], x[0])):
        t = c[2]
        if t < 4:
            continue
        p = person(c)
        prev = by_pt.get((p, t - 1))
        if prev == c[0]:
            prev = None
        mats = []
        ex = {c[0]}
        if prev:
            mats.append(prev)
            ex.add(prev)
        base = BASE[c[3]]
        if t == 4:
            while len(mats) < 2:
                mats.append(pick(c, 3, ex)); ex.add(mats[-1])
            mats += [T2[c[3]][len(recipes) % len(T2[c[3]])], base]
        elif t == 5:
            if not prev:
                mats.append(pick(c, 4, ex)); ex.add(mats[-1])
            mats.append(pick(c, 4, ex)); ex.add(mats[-1])
            while len(mats) < 4:
                mats.append(pick(c, 3, ex)); ex.add(mats[-1])
        elif t == 6:
            if not prev:
                mats.append(pick(c, 5, ex)); ex.add(mats[-1])
            mats.append(pick(c, 5, ex)); ex.add(mats[-1])
            mats.append(pick(c, 4, ex)); ex.add(mats[-1])
        elif t == 7:
            if not prev:
                mats.append(pick(c, 6, ex)); ex.add(mats[-1])
            mats.append(pick(c, 4, ex)); ex.add(mats[-1])
            mats.append(pick(c, 4, ex)); ex.add(mats[-1])
            mats += [base, base]
        elif t == 8:
            assert prev, c
            mats.append(pick(c, 5, ex)); ex.add(mats[-1])
            mats += [base, base]
        recipes[c[0]] = mats

    out = {"_설명": __doc__.strip(), "cards": new_cards, "recipes": recipes, "skills": SKILL}
    json.dump(out, open(os.path.join(ROOT, "lines.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    # 확인용 —— 관우 줄기
    nm = lambda k: BY_ID[k][1] + str(BY_ID[k][2])
    for t in range(4, 9):
        k = by_pt.get(("관우", t))
        print(nm(k), "=", " + ".join(nm(m) for m in recipes[k]))
    print("새 카드 %d장 · 조합 %d개 · 고유 기술 %d명" % (len(new_cards), len(recipes), len(SKILL)))
    miss = sorted({person(c) for c in allc if c[2] >= 4} - set(SKILL))
    print("고유 기술 없는 인물:", miss)


main()
