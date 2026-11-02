# -*- coding: utf-8 -*-
"""인물 줄기 · 인연 조합 · 장수 고유 기술 —— data/lines.json 을 만든다 (11/2 사용자 요청).

  python tools/scripts/lines.py

1) 줄기: 최고 등급이 불멸 · 신화인 인물은 희귀(4)부터 최고 등급까지 같은 인물 카드가 끊기지 않게 한다.
   단 초월은 건너뛴다 (11/2 (5): 희귀 → 전설 → 불멸 → 신화). 줄기 인물의 원본 초월 카드는 retire (적 전용).
1-2) 초월은 위세(aura)를 가진 다른 장수 32명 (병종마다 4). 조합은 전설 2 + 희귀 1. 새 인물 14명은 NEW6 · ULT6.
1-3) 주요 장수는 전설부터 (희귀 줄기 카드는 retire). 희귀는 초월 장수들의 희귀판 (이름만) —— 희귀 → 초월.
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
    "관로": "조조 좌자 화타 남화노선",
    "장연": "장각",
    # 11/2 (5) 초월 위세 장수 —— 새 인물
    "관평": "관우 주창 요화 마량",
    "고순": "여포 진궁 장료",
    "화웅": "동탁 여포 원소",
    "문추": "원소 장합 공손찬 전풍",
    "서성": "정봉 손권 주태 정보",
    "황월영": "제갈량 마량 사마휘",
    "주환": "손권 육손 주태 서성",
    "손상향": "유비 손권 손책 조운",
    "저수": "원소 전풍 장합",
    "장완": "제갈량 마량 강유 유비",
    "채문희": "조조 순욱 화타",
    "남화노선": "장각 좌자 우길",
    "전풍": "원소 저수 장합",
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

# ───────── 초월 위세 장수 (11/2 (5) 사용자: 줄기는 전설 → 불멸 → 신화, 초월은 위세를 가진 다른 장수들) ─────────
# 새 인물: (칭호 이름, 병종, 세력)
NEW6 = {
    "관평": ("충효 관평", "창병", "촉"), "고순": ("함진영 고순", "창병", "군"),
    "화웅": ("효기교위 화웅", "기병", "군"), "문추": ("하북명장 문추", "기병", "군"),
    "서성": ("강동궁장 서성", "궁병", "오"), "황월영": ("연노 황월영", "궁병", "촉"),
    "주환": ("유수독 주환", "도적", "오"), "손상향": ("궁요희 손상향", "도적", "오"),
    "저수": ("감군 저수", "책사", "군"), "장완": ("사상 장완", "유생", "촉"),
    "관로": ("신복 관로", "술사", "군"), "채문희": ("호가십팔박 채문희", "술사", "위"), "남화노선": ("남화노선", "술사", "군"),
    "전풍": ("하북모신 전풍", "모사", "군"),
}
# 위세 —— 살아 있는 동안. (11/2 (6) 사용자: 병종 특화만이면 재미없다 → 범위 · 효과를 장수마다 다르게)
#  to   : 아군 범위 —— all 전체 · front 진형 선봉·전군 · back 진형 중군·후군 · fac 같은 세력 · rel 인연 장수(REL 표 + 자신) · low 병력 절반 아래 · tag 그 병종
#  ally : 아군 능력치 배율 { atk def int res spd }
#  m    : 아군 특수 효과 (battle.gd mv 키 —— crit 치명타 · critd 치명 피해 · dr/idr 받는 물리/책략 피해 감소 · counter 반격 ·
#         regen 병력 회복 · mregen 사기 회복 · rate 기술 발동 · rout 패주 저항 · stres 상태이상 저항 · low_atk 위기 공격 ·
#         kill_amp 격파 뒤 피해 · weak_amp 약해진 적에게 · ignite 점화 · spread 불 번짐 · st_amp 지속 피해 · opener 첫 공격 · fire_res 화공 저항)
#  foe  : 적 능력치 배율, foe_to 적 범위 (all · front · back · tag:병종)
def AU(n, to="all", ally=None, m=None, foe=None, foe_to=None, tag=None):
    return {k: v for k, v in dict(n=n, to=to, ally=ally or {}, m=m or {}, foe=foe or {}, foe_to=foe_to, tag=tag).items() if v}
AURA6 = {
    # 창병
    "주태": AU("십이창흔", "low", m={"dr": 0.15, "rout": 0.3}),
    "방덕": AU("관을 지고", "all", m={"low_atk": 0.2}),
    "관평": AU("부자동심", "rel", ally={"atk": 0.12, "def": 0.12}),
    "고순": AU("함진영", "front", m={"dr": 0.1, "counter": 0.1}),
    # 기병
    "마등": AU("서량의 피", "tag", m={"crit": 0.1}, tag="기병"),
    "공손찬": AU("백마의종", "tag", ally={"spd": 0.12}, foe={"atk": -0.08}, foe_to="tag:궁병", tag="기병"),
    "화웅": AU("사수관", foe={"atk": -0.08, "def": -0.05}, foe_to="front"),
    "문추": AU("하북쌍벽", "fac", m={"kill_amp": 0.3}),
    # 궁병
    "황개": AU("고육계", "all", m={"ignite": 0.1}),
    "정보": AU("강동노장", "back", ally={"def": 0.12, "res": 0.08}),
    "서성": AU("의성의 장벽", "all", m={"idr": 0.1}),
    "황월영": AU("연노", "back", ally={"atk": 0.1}, m={"rate": 0.04}),
    # 도적
    "능통": AU("결사호위", "fac", m={"dr": 0.08}),
    "엄백호": AU("산월", foe={"def": -0.1}, foe_to="back"),
    "주환": AU("유수 방위", "front", m={"counter": 0.12}),
    "손상향": AU("궁요희", "all", m={"critd": 0.25}),
    # 책사
    "방통": AU("연환", "all", m={"spread": 0.2}, foe={"spd": -0.05}),
    "마량": AU("백미", "rel", ally={"int": 0.12}, m={"rate": 0.04}),
    "종회": AU("벌촉", "all", m={"weak_amp": 0.15}),
    "저수": AU("감군", "back", ally={"int": 0.1}, m={"idr": 0.08}),
    # 유생
    "대교": AU("강동이교", "all", m={"regen": 0.01}),
    "소교": AU("경국지색", "all", m={"mregen": 0.5}, foe={"int": -0.06}),
    "장소": AU("강동문신", "all", m={"stres": 0.2}),
    "장완": AU("사상", "fac", ally={"def": 0.08, "res": 0.08}),
    # 술사
    "우길": AU("청우", "all", m={"mregen": 0.8, "fire_res": 0.3}),
    "관로": AU("천기", "all", m={"rate": 0.03}, foe={"spd": -0.05}),
    "채문희": AU("호가", "low", ally={"atk": 0.15, "int": 0.15}),
    "남화노선": AU("태평비전", "all", m={"st_amp": 0.2}),
    # 모사
    "정욱": AU("십면매복", "all", m={"opener": 0.15}, foe={"atk": -0.04}),
    "등애": AU("음평", "all", m={"opener": 0.25}),
    "원술": AU("옥새", "fac", ally={"atk": 0.08, "int": 0.08}),
    "전풍": AU("강직", "all", m={"rout": 0.25, "stres": 0.1}),
}
# 새 인물 특기 —— 성향이 닮은 인물의 특기 사다리(passives.json ladder · level)를 빌린다
LADDER_FROM = {"관평": "관우", "고순": "전위", "화웅": "마등", "문추": "공손찬", "황월영": "태사자", "주환": "정봉",
               "손상향": "능통", "장완": "장소", "채문희": "대교", "남화노선": "장각"}
# 새 인물 고유기 (ultimates.json 형식, 신화 기준 수치 —— 초월은 tier6_scale 배)
ULT6 = {
    "관평": dict(name="부자동진", shout="아버님의 뒤는 제가 지킵니다!", vfx="roar", eff=[dict(t="ally", tgt="allyFront", buff=dict(stat="def", amt=0.35, dur=2)), dict(t="hit", kind="phys", mult=1.6, tgt="front3")]),
    "고순": dict(name="함진돌파", shout="함진영, 앞으로!", vfx="roar", eff=[dict(t="hit", kind="phys", mult=1.9, tgt="front1", pierce=0.4), dict(t="foe", tgt="front3", morale=12)]),
    "화웅": dict(name="사수관 효기", shout="나와 겨룰 자 누구냐!", vfx="roar", eff=[dict(t="hit", kind="phys", mult=1.7, tgt="front3"), dict(t="ally", tgt="self", buff=dict(stat="atk", amt=0.3, dur=2))]),
    "문추": dict(name="연진돌격", shout="하북의 창끝을 받아라!", vfx="charge", eff=[dict(t="hit", kind="phys", mult=1.5, tgt="line:선봉+전군"), dict(t="foe", tgt="front3", morale=10)]),
    "서성": dict(name="의성 가성", shout="강변에 성벽을 세워라!", vfx="aura", eff=[dict(t="ally", tgt="allyAll", buff=dict(stat="def", amt=0.3, dur=2)), dict(t="hit", kind="phys", mult=0.9, tgt="all")]),
    "황월영": dict(name="원융노", shout="열 발이 한 번에 나갑니다.", vfx="arrowstorm", eff=[dict(t="hit", kind="phys", mult=1.1, tgt="all"), dict(t="hit", kind="phys", mult=0.8, tgt="back2")]),
    "주환": dict(name="유수 역습", shout="물러서는 척하다 친다!", vfx="charge", eff=[dict(t="hit", kind="phys", mult=1.8, tgt="back1"), dict(t="ally", tgt="self", buff=dict(stat="def", amt=0.3, dur=2))]),
    "손상향": dict(name="궁요희의 칼춤", shout="여인이라 얕보지 마라!", vfx="charge", eff=[dict(t="hit", kind="phys", mult=1.6, tgt="back2"), dict(t="ally", tgt="self", buff=dict(stat="spd", amt=0.3, dur=2))]),
    "저수": dict(name="감군지략", shout="군을 나누어 치면 이깁니다.", vfx="aura", eff=[dict(t="foe", tgt="all", buff=dict(stat="res", amt=-0.25, dur=2)), dict(t="hit", kind="int", mult=1.0, tgt="all")]),
    "장완": dict(name="사상의 다스림", shout="나라의 근본은 백성입니다.", vfx="heal", eff=[dict(t="ally", tgt="allyAll", heal=0.2, morale=10), dict(t="ally", tgt="allyAll", buff=dict(stat="res", amt=0.2, dur=2))]),
    "관로": dict(name="천기누설", shout="그대의 운은 오늘 다했소.", vfx="aura", eff=[dict(t="foe", tgt="all", morale=12, buff=dict(stat="spd", amt=-0.25, dur=2)), dict(t="hit", kind="int", mult=0.9, tgt="back2")]),
    "채문희": dict(name="호가십팔박", shout="슬픈 곡조가 전장에 퍼집니다.", vfx="aura", eff=[dict(t="ally", tgt="allyAll", heal=0.15, morale=12), dict(t="foe", tgt="all", morale=8)]),
    "남화노선": dict(name="태평요술 전수", shout="하늘의 책을 펼치노라.", vfx="aura", eff=[dict(t="hit", kind="int", mult=1.1, tgt="all"), dict(t="foe", tgt="front3", status=dict(k="confuse", val=1, dur=1))]),
    "전풍": dict(name="강직한 간언", shout="지금 치지 않으면 후회합니다!", vfx="aura", eff=[dict(t="hit", kind="int", mult=1.3, tgt="back2"), dict(t="foe", tgt="all", buff=dict(stat="atk", amt=-0.2, dur=2))]),
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
    "관평": dict(n="부자동진", k="phys", tgt="front3", mult=1.25, allyBuff=AB("def", 0.15, "allyFront"), cond="always"),
    "고순": dict(n="함진영", k="phys", tgt="front1", mult=1.6, pierce=0.3, cond="always"),
    "화웅": dict(n="사수관 일격", k="phys", tgt="front1", mult=1.6, morale=8, cond="always"),
    "문추": dict(n="하북돌기", k="phys", tgt="line:선봉+전군", mult=1.15, morale=6, cond="front_n:2|always"),
    "서성": dict(n="강변사격", k="phys", tgt="back2", mult=1.25, allyBuff=AB("def", 0.12), cond="always"),
    "황월영": dict(n="연노사격", k="phys", tgt="all", mult=0.85, cond="foe_n:3|always"),
    "주환": dict(n="유수매복", k="phys", tgt="back1", mult=1.6, spd=SPD(-0.2), cond="always"),
    "손상향": dict(n="궁요검무", k="phys", tgt="back2", mult=1.35, selfBuff=SB("spd", 0.2), cond="always"),
    "저수": dict(n="감군지책", k="int", tgt="line:후군", mult=1.2, resDown={"amt": -0.25, "dur": 2}, cond="always"),
    "장완": dict(n="안민지책", k="int", tgt="all", mult=0.7, tHeal=0.06, allyBuff=AB("res", 0.15), cond="ally_hurt:0.8"),
    "채문희": dict(n="비분시", k="int", tgt="all", mult=0.75, heal=8, rally=True, morale=6, cond="ally_morale:85|foe_n:3"),
    "남화노선": dict(n="태평비술", k="int", tgt="front3", mult=1.0, status=ST("confuse", 1, 1), cond="always"),
    "전풍": dict(n="직간", k="int", tgt="back2", mult=1.3, morale=8, cond="always"),
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

    # 11/2 (5) 줄기 인물(관우 · 장비 같은 주요 장수)은 전설부터 나오고 초월을 건너뛴다: 전설 → 불멸 → 신화.
    # 희귀 · 초월 줄기 카드는 만들되(뒤 카드 능력치 기준 · 번호 유지) 내보내지 않고, 원본 희귀 · 초월 카드는 적 전용으로 돌린다
    # (토벌 편성이 쓰는 것이 있다). 새로 만든 전설 카드는 칭호 없이 이름만 (「자효 조인」 같은 맛없는 접두를 피한다)
    chain = {p for p, ts in per.items() if max(ts) >= 7}
    retire = [c[0] for c in CARDS if c[2] in (4, 6) and person(c) in chain]
    for c in [c for c in new_cards if c[2] in (4, 6)]:
        new_cards.remove(c)
        del BY_ID[c[0]]
    for c in new_cards:
        if c[2] == 5:
            c[1] = person(c)
    # 초월 위세 장수 —— 새 인물 (같은 병종 초월 평균 능력치)
    psv_of = {}
    for c in CARDS:
        if c[2] == 6 and person(c) not in chain and isinstance(c[12], dict) and c[12].get("psv"):
            psv_of.setdefault(c[3], c[12]["psv"])
    for i, (p, (title, tag, fac)) in enumerate(NEW6.items()):
        a = avg[(tag, 6)]
        st = [round(x) for x in a]
        cid = "N%02d" % (i + 1)
        card = [cid, title, 6, tag, fac] + st + [std[6][0], std[6][1], {"n": "", "eff": {}, "psv": psv_of.get(tag)}, "", ""]
        new_cards.append(card)
        BY_ID[cid] = card
    # 희귀 = 초월 위세 장수의 희귀판 (희귀 → 초월 작은 줄기). 없으면 이름만인 새 카드 (초월 카드 × 병종 희귀/초월 평균 비).
    # 같은 인물의 고급 카드가 있으면 이름이 겹치므로 그 고급 카드는 적 전용으로
    six = [c for c in BY_ID.values() if c[2] == 6 and c[13] != "foe" and person(c) not in chain]
    have4 = {person(c) for c in BY_ID.values() if c[2] == 4 and c[13] != "foe"}
    for i, ref in enumerate(sorted(six, key=lambda c: c[0])):
        p = person(ref)
        if p in have4:
            continue
        a0, a1 = avg[(ref[3], 6)], avg[(ref[3], 4)]
        st = [round(ref[5 + j] * a1[j] / a0[j]) if a0[j] > 0 else ref[5 + j] for j in range(5)]
        st[4] = ref[9]
        cid = "R%02d" % (i + 1)
        card = [cid, p, 4, ref[3], ref[4]] + st + [std[4][0], std[4][1], {"n": "", "eff": {}, "psv": None}, "", ""]
        new_cards.append(card)
        BY_ID[cid] = card
        retire += [c[0] for c in CARDS if c[2] == 3 and person(c) == p]
    for k in retire:
        BY_ID.pop(k, None)
    retire.sort()

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
        prev = by_pt.get((p, 5 if t == 7 else t - 1))
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
        elif t == 6:         # 초월 —— 제 희귀 + 전설 2 (원랜디 초월처럼). 제 전설이 있으면 그것부터
            mats = []
            ex = {c[0]}
            own4, own5 = by_pt.get((p, 4)), by_pt.get((p, 5))
            mats.append(own4 if own4 else pick(c, 4, ex)); ex.add(mats[-1])
            if own5:
                mats.append(own5); ex.add(own5)
            while len(mats) < 3:
                mats.append(pick(c, 5, ex)); ex.add(mats[-1])
        elif t == 7:         # 불멸 —— 제 전설 + 인연 전설 2 + 희귀 1 + 기본 1
            if not prev:
                mats.append(pick(c, 5, ex)); ex.add(mats[-1])
            mats.append(pick(c, 5, ex)); ex.add(mats[-1])
            mats.append(pick(c, 5, ex)); ex.add(mats[-1])
            mats.append(pick(c, 4, ex)); ex.add(mats[-1])
            mats.append(base)
        elif t == 8:
            assert prev, c
            mats.append(pick(c, 5, ex)); ex.add(mats[-1])
            mats += [base, base]
        recipes[c[0]] = mats

    aura = {}
    for c in allc:
        if c[2] == 6 and c[13] != "foe":
            assert person(c) in AURA6, person(c)
            au = dict(AURA6[person(c)])
            if au.get("to") == "rel":
                au["rel"] = [person(c)] + REL.get(person(c), [])
            aura[c[0]] = au
    out = {"_설명": __doc__.strip(), "cards": new_cards, "recipes": recipes, "skills": SKILL,
           "retire": retire, "aura": aura, "ults": ULT6, "ladder_from": LADDER_FROM}
    json.dump(out, open(os.path.join(ROOT, "lines.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    # 확인용 —— 관우 줄기
    nm = lambda k: BY_ID[k][1] + str(BY_ID[k][2])
    for p_ in ["관우", "조인", "관평", "마량", "서성"]:
        for t in range(4, 9):
            k = by_pt.get((p_, t))
            if k:
                print(nm(k), "=", " + ".join(nm(m) for m in recipes[k]))
    print("초월 %d명 · 적 전용으로 돌린 원본 %d장" % (len(aura), len(retire)))
    for t in (3, 4, 5):
        xs = [c for c in allc if c[2] == t]
        print("등급 %d: %d장 —— %s" % (t, len(xs), " ".join(c[1] for c in xs)))
    print("새 카드 %d장 · 조합 %d개 · 고유 기술 %d명" % (len(new_cards), len(recipes), len(SKILL)))
    miss = sorted({person(c) for c in allc if c[2] >= 4} - set(SKILL))
    print("고유 기술 없는 인물:", miss)


main()
