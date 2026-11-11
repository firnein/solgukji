# -*- coding: utf-8 -*-
"""인물 줄기 · 인연 조합 · 장수 고유 기술 —— data/lines.json 을 만든다 (11/2 사용자 요청).

  python tools/scripts/lines.py

1) 줄기: 최고 등급이 불멸 · 신화인 인물은 희귀(4)부터 최고 등급까지 같은 인물 카드가 끊기지 않게 한다.
   단 초월은 건너뛴다 (11/2 (5): 희귀 → 전설 → 불멸 → 신화). 줄기 인물의 원본 초월 카드는 retire (적 전용).
1-2) 초월은 위세(aura)를 가진 다른 장수 32명 (병종마다 4). 조합은 전설 2 + 희귀 2 + 기본 1 (11/9). 새 인물 14명은 NEW6 · ULT6.
1-3) 주요 장수는 전설부터 (희귀 줄기 카드는 retire). 희귀는 초월 장수들의 희귀판 (이름만) —— 희귀 → 초월.
   빈 칸은 새 카드로 채우고, 능력치는 그 인물의 가장 가까운 등급 카드 × (같은 병종 등급 평균 비)로 정한다.
2) 조합: 희귀 이상 모든 장수 =  같은 인물의 한 등급 아래 + 인연 인물 카드 + (같은 세력 · 병종 재료).
   등급별 재료 수는 예전과 같다 (희귀 4 · 전설 4 · 초월 5 · 기인 4 · 불멸 5 · 신화 4 + 유니크 아이템).
3) 기술: 희귀 이상 인물마다 고유 일반 기술 하나 (첫 기술). 수치는 신화 기준이 아니라 기술 표(SKMUL)로 등급마다 곱한다.
원본 game.json · cards_ext.json 은 그대로 두고 DB 가 불러올 때 덮어쓴다.
"""
import json, os, statistics
from collections import Counter

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "solgukji_godot", "data")
G = json.load(open(os.path.join(ROOT, "game.json"), encoding="utf-8"))
E = json.load(open(os.path.join(ROOT, "cards_ext.json"), encoding="utf-8"))

CARDS = [c for c in G["CARDDEF"] + E["cards"] if c[13] != "foe"]
BY_ID = {c[0]: c for c in CARDS}
person = lambda c: c[1].split(" ")[-1]
ORDER = ["창병", "기병", "궁병", "도적", "책사", "유생", "술사", "모사"]
BASE = {"창병": "spear", "기병": "horse", "궁병": "bow", "도적": "rogue", "책사": "strat", "유생": "schol", "술사": "occul", "모사": "schem"}

# ───────── 인연 (가까운 순) ─────────
REL = {
    "관우": "장비 유비 조운 주창 요화 마량 황충 마초 화타",
    "장비": "관우 유비 조운 마초 간옹 미축 황충 관평 간옹 미축",
    "조운": "유비 관우 장비 제갈량 마대 황충 공손찬",
    "유비": "관우 장비 제갈량 간옹 미축 법정 서서 조운 공손찬 손상향",
    "제갈량": "유비 방통 강유 서서 사마휘 마량 법정 주유 이적",
    "방통": "제갈량 사마휘 법정 유비 서서",
    "강유": "제갈량 마대 위연 종회 등애 장완 요화",
    "마초": "마대 마등 장비 방덕 조운",
    "마대": "마초 마등 위연 강유",
    "황충": "관우 위연 법정 하후연 조운",
    "위연": "황충 마대 강유 제갈량 유비",
    "법정": "유비 제갈량 방통 황충 장완 이적",
    "서서": "유비 제갈량 사마휘 방통 간옹 미축",
    "사마휘": "제갈량 방통 서서 유비 관로 마량",
    "마량": "제갈량 관우 이적 유비",
    "조조": "하후돈 하후연 순욱 곽가 전위 허저 조인 정욱 가후 사마의",
    "하후돈": "조조 하후연 조인 전위 허저 이전 우금 악진",
    "하후연": "하후돈 조조 황충 장합 하후패",
    "허저": "전위 조조 마초 하후돈 악진 우금",
    "전위": "허저 조조 하후돈 우금 악진 고순",
    "조인": "조조 하후돈 서황 우금 이전",
    "서황": "장료 조인 관우 우금 악진",
    "장료": "서황 관우 장합 악진 이전 감녕 손권 고순",
    "장합": "장료 하후연 사마의 원소 곽회 문추 안량",
    "순욱": "조조 곽가 정욱 진군 유엽",
    "곽가": "조조 순욱 정욱 가후 유엽",
    "가후": "조조 곽가 사마의 장합 정욱 전위",
    "사마의": "조조 장합 등애 제갈량 곽회",
    "정욱": "조조 순욱 곽가",
    "등애": "종회 사마의 강유",
    "종회": "등애 사마의 강유",
    "손권": "손책 주유 노숙 여몽 육손 감녕 태사자 주태",
    "손책": "주유 태사자 손권 정보 황개 대교",
    "주유": "손책 노숙 소교 황개 육손 정보 제갈량",
    "육손": "여몽 손권 주유 노숙 주환 서성 정봉",
    "여몽": "감녕 능통 손권 노숙 육손 관우",
    "감녕": "능통 여몽 손권 장료",
    "능통": "감녕 여몽 손권",
    "태사자": "손책 유비 손권 주환",
    "정보": "황개 주유 손책",
    "황개": "정보 주유 손책",
    "노숙": "주유 손권 제갈량 여몽 장소 대교",
    "대교": "소교 손책 주유",
    "소교": "대교 주유 손책",
    "주태": "손권 여몽 정봉 서성 능통",
    "정봉": "주태 서성 정보",
    "엄백호": "손책 능조",
    "장소": "손권 노숙 손책",
    "여포": "진궁 초선 동탁 장료 고순 화웅",
    "동탁": "여포 초선 원소 화웅 고순",
    "초선": "여포 동탁 화웅 고순",
    "진궁": "여포 조조 고순 원술 화웅",
    "원소": "원술 공손찬 안량 저수 심배 전풍 장합 문추",
    "원술": "원소 손책 여포",
    "공손찬": "유비 조운 원소",
    "마등": "마초 마대",
    "방덕": "마초 관우",
    "장각": "장보 장량 좌자 화타 남화노선 장연 관해",
    "좌자": "조조 우길 장각 화타 관로 남화노선",
    "화타": "관우 조조 좌자 관로 채문희",
    "우길": "손책 좌자",
    "장로": "마초 장각 장연 관로",
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

# ───────── 11/3 일반(2) 등급 삭제 · 덱 압축 (사용자) ─────────
# 일반 카드(창병대 · 극병대 …)는 적 전용으로 돌리고, 고급은 기본패 넷으로 바로 만든다: 제 병종 2 + 다른 병종 2.
# 같은 병종 고급끼리 짝(다른 병종 둘)이 겹치지 않게 —— 예전엔 우금 = 이전 같은 똑같은 조합이 있었다
T3 = {"우금": "궁병 모사", "악진": "기병 도적", "이전": "궁병 유생",
      "하후패": "궁병 도적", "곽회": "창병 책사", "안량": "창병 도적",
      "학소": "창병 책사", "여상": "기병 모사",
      "주창": "창병 유생", "요화": "기병 궁병", "관해": "술사 창병", "능조": "도적 술사", "마충": "모사 책사",
      "이적": "유생 술사", "유엽": "모사 궁병",
      "간옹": "모사 도적", "미축": "창병 술사", "진군": "책사 모사",
      "장보": "창병 도적", "장량": "기병 책사", "초주": "술사 기병", "오범": "모사 궁병",
      "심배": "기병 유생",
      # 11/5 되살린 고급 (초월 장수의 고급판 —— 고급 → 희귀 → 초월 줄기)
      "마량": "기병 창병", "우길": "궁병 유생", "저수": "창병 책사", "전풍": "궁병 도적"}
# 11/5 사용자: 고급 · 희귀 명단 정리 —— 고급이 도적 · 술사에 쏠리고(오나라 고급은 셋뿐) 조합에 같은 재료가 너무 많이 들었다.
# 고급은 세력 4 × 병종 8 격자에 한 명씩 (이 명단 밖의 고급은 적 전용, 없는 인물은 새 카드 —— 그림은 나중에 새로 그린다).
# 순서 = ORDER (창병 · 기병 · 궁병 · 도적 · 책사 · 유생 · 술사 · 모사). 능력치는 그 병종 고급 평균 (옮긴 인물은 옛 병종 평균 대비 비율)
ROSTER3 = {
    "위": "이전 하후패 여상 악진 유엽 진군 주건평 동소",
    "촉": "요화 오의 왕평 주창 이적 간옹 초주 마속",
    "오": "능조 한당 마충 장흠 감택 제갈근 오범 보즐",
    "군": "기령 안량 장임 관해 허유 진림 장보 심배"}
# 11/5 사용자: 이름값 구간 —— 고급 · 희귀는 어느 정도 알려진 장수, 전설부터는 많이 알려진 장수, 그 위(초월 · 불멸 · 신화)는 칭호판.
# 한 인물은 한 구간에만 (주태도 희귀가 있으면 안 된다)
TRANS_UP = ["황개", "방덕", "관평", "화웅", "문추", "대교", "소교", "등애", "종회", "원술", "장소", "우길"]   # 초월 장수 → 전설(이름만)부터. 희귀판 없음
TRANS_DOWN = ["마량", "정욱", "저수", "전풍", "장완", "채문희", "엄백호", "남화노선"]                    # 이름값이 애매 → 희귀 구간으로 (초월 · 위세 뺌)
NO_RARE = ["주태", "마대", "정보", "능통", "정봉"] + TRANS_UP                                            # 전설이 있으니 희귀판을 뺀다
# 희귀 비용 다양화 (11/5) —— 비용 = 기본패 환산. 고급 1장 = 기본패 4장
RARE_SHAPE = {7: (1, 3), 8: (1, 4), 9: (2, 1), 10: (2, 2), 11: (2, 3), 12: (3, 0), 13: (3, 1)}
RARE_SOLO_COSTS = [7, 8, 9, 10, 11, 12, 13]       # 줄기 없는 희귀 —— 병종마다 고르게 돈다
RARE_LINE_COSTS = [8, 9, 10, 11, 12]              # 줄기 희귀 —— 평균은 단독 희귀와 같게 (웃돈은 능력치 쪽에서 덜 오르는 것으로)
RARE_PREMIUM = 1                                  # 줄기 희귀의 재료 웃돈 (비용에는 들지만 능력치에는 들지 않는다)
RARE_SCALE = 0.4                                  # 비용 1당 능력치 · 병력 ±4% (전력은 두 배율의 곱이라 비용과 비슷하게 따라간다)
# 희귀에 더할 인물 (병종, 세력) —— 초월 장수의 희귀판이 없는 칸을 채운다. 고급에서 올라온 인물(우금 · 곽회 · 학소)은 그 능력치 비율을 잇는다
ADD4 = {"우금": ("창병", "위"), "곽회": ("기병", "위"), "학소": ("궁병", "위"), "장패": ("도적", "위"),
        "엄안": ("궁병", "촉"), "장포": ("도적", "촉"), "맹달": ("모사", "촉"),
        "반장": ("기병", "오"), "제갈각": ("책사", "오"), "우번": ("술사", "오"), "여범": ("모사", "오"),
        "고람": ("창병", "군"), "황조": ("궁병", "군"), "장만성": ("도적", "군"), "공융": ("유생", "군"),
        # 11/5 촉 희귀가 모자랐다 (7명 · 재료 자리 43 · 같은 세력 58%) —— 촉 전설이 많은 창 · 기 · 유 쪽에
        "관흥": ("창병", "촉"), "오반": ("기병", "촉"), "비의": ("유생", "촉"),
        # 11/5 이름값 구간 정리로 빠진 희귀 17명을 채운다 —— 어느 정도 알려진 장수 (황건 · 남만 · 기인 인물 제외)
        "문빙": ("창병", "위"), "주연": ("창병", "오"), "왕쌍": ("창병", "위"), "조홍": ("기병", "위"), "한수": ("기병", "군"),
        "진무": ("궁병", "오"), "하제": ("궁병", "오"), "이각": ("도적", "군"), "황권": ("책사", "촉"), "순유": ("책사", "위"),
        "도겸": ("유생", "군"), "길평": ("술사", "위"), "이의": ("술사", "촉"), "이유": ("모사", "군")}
def AU(n, to="all", ally=None, m=None, foe=None, foe_to=None, tag=None):
    return {k: v for k, v in dict(n=n, to=to, ally=ally or {}, m=m or {}, foe=foe or {}, foe_to=foe_to, tag=tag).items() if v}


# ───────── 11/3 기인 (사용자 결정) —— 한 판에 각 1장, 능력치는 전설 ×0.85, 가치는 기능 ─────────
# 그 인물의 다른 등급 카드는 모두 적 전용(retire). 조합 = 희귀 2 (pref 인물 먼저) + 고급 1 + 제 병종 기본
# 효과 = 위세 문법(to · ally · m · foe · foe_to) + kiin 키 (battle.gd 가 따로 처리하는 기능)
KIIN_MUL = 0.9
KIIN = {
    "조인": ("철벽 조인", "창병", "위", "하후돈 조조 이전 우금", AU("철통방어", "front", m={"dr": 0.2})),
    "전위": ("호위 전위", "창병", "위", "조조 허저 악진", dict(AU("주군수호", ally={"def": 0.05}), kiin="guard")),
    "고순": ("함진 고순", "창병", "군", "여포 진궁 장료", dict(AU("방패대열", "front", m={"counter": 0.2}), kiin="no_charge")),
    "공손찬": ("백마 공손찬", "기병", "군", "유비 조운 원소", AU("궁기제압", foe={"spd": -0.45, "atk": -0.1}, foe_to="tag:궁병")),
    "장합": ("교변 장합", "기병", "위", "장료 하후연 원소 사마의", dict(AU("임기응변", ally={"spd": 0.12, "atk": 0.05}), kiin="matchup_dr")),
    "마등": ("서량 마등", "기병", "군", "마초 마대 방덕", dict(AU("복파유풍", "tag", ally={"atk": 0.1}, tag="기병"), kiin="charge_up")),
    "황월영": ("기관 황월영", "궁병", "촉", "제갈량 마량 사마휘", AU("목우유마", "back", ally={"spd": 0.35})),
    "서성": ("의성 서성", "궁병", "오", "정봉 손권 주태", dict(AU("장강방벽", m={"idr": 0.08}), kiin="ult_block")),
    "주환": ("매복 주환", "도적", "오", "손권 육손 주태", dict(AU("적진교란", m={"opener": 0.2}), kiin="ult_cut")),
    "장연": ("흑산 장연", "도적", "군", "장각 관해 장보", dict(AU("군량약탈", foe={"def": -0.1}), kiin="heal_cut")),
    "손상향": ("궁요 손상향", "도적", "오", "유비 손권 손책", dict(AU("백인시비", m={"crit": 0.06}), kiin="ambush")),
    "방통": ("봉추 방통", "책사", "촉", "제갈량 사마휘 법정 마량", AU("연환", m={"cleave": 0.1})),      # 11/11 전투가 icleave 를 cleave 에 더한다(MV_ALIAS) —— 둘 다 적으면 두 번 붙는다
    "서서": ("단복 서서", "책사", "촉", "유비 제갈량 사마휘", dict(AU("피해분담", ally={"def": 0.06}), kiin="share")),
    "곽가": ("유계 곽가", "책사", "위", "조조 순욱 정욱", dict(AU("유계", ally={"int": 0.06}), kiin="death_gauge")),
    "미축": ("거상 미축", "유생", "촉", "유비 간옹 손상향", dict(AU("거상재물", ally={"def": 0.05}), kiin="ticket")),
    "사마휘": ("수경 사마휘", "유생", "군", "제갈량 방통 서서 관로", AU("인재추천", m={"rate": 0.07})),
    "노숙": ("연합 노숙", "유생", "오", "주유 손권 제갈량", dict(AU("손유동맹", ally={"def": 0.1}), kiin="aura_half")),
    "화타": ("신의 화타", "술사", "군", "관로 채문희 관우", dict(AU("기사회생"), kiin="revive")),
    "좌자": ("둔갑 좌자", "술사", "군", "우길 관로 남화노선", dict(AU("봉인부적"), kiin="seal")),
    "관로": ("점복 관로", "술사", "군", "좌자 남화노선 우길", dict(AU("점괘예견", foe={"spd": -0.1}), kiin="wind_slow")),
    "초선": ("폐월 초선", "모사", "군", "여포 동탁 화웅", dict(AU("양호상쟁", m={"turncoat": 1}), kiin="turncoat")),
    "가후": ("난무 가후", "모사", "위", "조조 장합 전풍", dict(AU("난무", m={"fear": 0.15}), kiin="morale_crash")),
}
TITLE_FIX = {"철벽 조인": "천인 조인", "호위 전위": "악래 전위", "서량 마등": "복파 마등", "기관 황월영": "목우 황월영",
             "매복 주환": "유수 주환", "흑산 장연": "비연 장연", "궁요 손상향": "궁요희 손상향", "난무 가후": "독사 가후",
             "점복 관로": "신복 관로", "거상 미축": "거부 미축", "연합 노숙": "대의 노숙", "유계 곽가": "귀재 곽가",
             "사상 장완": "대사마 장완", "강동문신 장소": "장공 장소", "하북모신 전풍": "강직 전풍"}

# 신화는 한 판에 하나 —— 군주 · 최상위 12명만 (11/3). 나머지 인물은 불멸이 끝 (신화 카드는 적 전용)
# 11/5 사용자: 신화는 늘리지 않고 장비 · 조운 · 손책을 빼고 장료 · 감녕을 넣는다 (11명 —— 위 · 촉 · 오 셋씩, 병종마다 하나 이상).
# 빠진 셋은 불멸이 마지막 단계 (불멸도 충분히 센 장수). 장료(강동의 악몽 · 위세 소아지제) · 감녕(백기겁영 · 위세 방울소리)은 원본 신화 카드를 되살린다
MYTH12 = ["유비", "조조", "손권", "제갈량", "사마의", "주유", "관우", "장료", "감녕", "여포", "장각"]
NEW_MYTH = {"사마의": ("선제 사마의", "호부", {**AU("응시호보", ally={"int": 0.08}, foe={"spd": -0.08}),
    "paeup": {"n": "후발제인", "cond": "none", "need": 0, "what": "조건 없음", "fx": "late",      # 11/9 패업 —— lines.json 에 같은 값 (battle.gd _paeup_late_tick)
              "d": "개전 12초 동안 아군이 받는 피해 -20% —— 버틴 뒤 아군 전원 공격 +15% (15초)"}})}
NEW_ITEMS = [["u01", "호부", "유니크", "모사", "int", 0.32, "def", 0.16, 7, "myth"]]

# 원래 특기 사다리가 없는 저등급 인물은 병종 다수결로 채우지 않고 인물별로 직접 배정한다.
# 순서는 카드에서 읽히는 순서이며, 세 특기는 해당 인물의 가장 낮은 플레이어 카드부터 열린다.
PERSONAL_SPECIALTIES = {
    "감택": ["귀모", "연계", "기책"], "고람": ["반격", "휩쓸기", "금강"], "공융": ["명경", "연계", "위무"],
    "관흥": ["용맹", "추격", "휩쓸기"], "기령": ["반격", "투쟁", "기세"], "길평": ["인술", "명경", "단량"],
    "도겸": ["명경", "분발", "도원결의"], "동소": ["귀모", "위축", "이간"], "마속": ["기책", "반목", "신산"],
    "맹달": ["반목", "위압", "기세"], "문빙": ["방진", "금강", "사수"], "반장": ["추격", "기세", "투쟁"],
    "보즐": ["연계", "명경", "인술"], "비의": ["연계", "명경", "위무"], "순유": ["귀모", "기책", "신산"],
    "엄안": ["용맹", "불굴", "위축"], "여범": ["귀모", "위축", "반목"], "오반": ["선봉", "추격", "용맹"],
    "오의": ["위축", "파갑", "기세"], "왕쌍": ["휩쓸기", "반격", "투쟁"], "왕평": ["명경", "위축", "불굴"],
    "우번": ["위압", "명경", "기책"], "이각": ["추격", "투쟁", "기세"], "이유": ["귀모", "이간", "반목"],
    "이의": ["명경", "반목", "위압"], "장만성": ["기세", "투쟁", "휩쓸기"], "장임": ["위축", "기선", "용맹"],
    "장패": ["추격", "휩쓸기", "불굴"], "장포": ["용맹", "기세", "추격"], "장흠": ["용맹", "기세", "선봉"],
    "제갈각": ["기책", "파상", "귀모"], "제갈근": ["연계", "명경", "위무"], "조홍": ["불굴", "투쟁", "추격"],
    "주건평": ["명경", "위압", "기책"], "주연": ["방진", "위축", "금강"], "진림": ["반목", "약점", "위압"],
    "진무": ["반격", "용맹", "추격"], "하제": ["기세", "추격", "휩쓸기"], "한당": ["용맹", "선봉", "불굴"],
    "한수": ["반목", "기세", "추격"], "허유": ["귀모", "기책", "약점"], "황권": ["기책", "명경", "위축"],
    "황조": ["위축", "산란", "투쟁"],
}

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
    "관로": ("신복 관로", "술사", "군"), "채문희": ("호가십팔박 채문희", "유생", "위"), "남화노선": ("남화노선", "술사", "군"),
    "전풍": ("하북모신 전풍", "모사", "군"),
}
# 위세 —— 살아 있는 동안. (11/2 (6) 사용자: 병종 특화만이면 재미없다 → 범위 · 효과를 장수마다 다르게)
#  to   : 아군 범위 —— all 전체 · front 진형 선봉·전군 · back 진형 중군·후군 · fac 같은 세력 · rel 인연 장수(REL 표 + 자신) · low 병력 절반 아래 · tag 그 병종
#  ally : 아군 능력치 배율 { atk def int spd }  (책략방어 res 는 11/7 방어로 합쳤다 —— 같이 있으면 큰 값 하나만)
#  m    : 아군 특수 효과 (battle.gd mv 키 —— crit 치명타 · critd 치명 피해 · dr/idr 받는 물리/책략 피해 감소 · counter 반격 ·
#         regen 병력 회복 · mregen 사기 회복 · rate 기술 발동 · rout 패주 저항 · stres 상태이상 저항 · low_atk 위기 공격 ·
#         kill_amp 격파 뒤 피해 · weak_amp 약해진 적에게 · ignite 점화 · spread 불 번짐 · st_amp 지속 피해 · opener 첫 공격 · fire_res 화공 저항)
#  foe  : 적 능력치 배율, foe_to 적 범위 (all · front · back · tag:병종)
# 11/9 초월 위세 강화 —— 초월은 팀을 받치는 위세 · 지원이라 효과 수치를 대략 1.75배로 (범위 · 조건 · 종류는 그대로, 측정 없이 한 번만)
AURA6 = {
    # 창병
    "주태": AU("충의방패", "low", m={"dr": 0.26, "rout": 0.53}),
    "방덕": AU("관을 지고", "all", m={"low_atk": 0.35}),
    "관평": AU("의리지가", "rel", ally={"atk": 0.21, "def": 0.21}),
    "고순": AU("청렴위엄", "front", m={"dr": 0.18, "counter": 0.18}),
    # 기병
    "마등": AU("복파의 후예", "tag", m={"crit": 0.18}, tag="기병"),
    "공손찬": AU("오환토벌", "tag", ally={"spd": 0.21}, foe={"atk": -0.14}, foe_to="tag:궁병", tag="기병"),
    "화웅": AU("관문의 맹위", foe={"atk": -0.14, "def": -0.088}, foe_to="front"),
    "문추": AU("명장쌍벽", "fac", m={"kill_amp": 0.53}),
    # 궁병
    "황개": AU("삼대노신", "all", m={"ignite": 0.18}),
    "정보": AU("정공의 덕망", "back", ally={"def": 0.21}),
    "서성": AU("장강수비", "all", m={"idr": 0.18}),
    "황월영": AU("기관공방", "back", ally={"atk": 0.18}, m={"rate": 0.07}),
    # 도적
    "능통": AU("충렬의 기개", "fac", m={"dr": 0.14}),
    "엄백호": AU("오군호걸", foe={"def": -0.18}, foe_to="back"),
    "주환": AU("견수불퇴", "front", m={"counter": 0.21}),
    "손상향": AU("백인시비", "all", m={"critd": 0.44}),
    # 책사
    "방통": AU("봉황지재", "all", m={"spread": 0.35}, foe={"spd": -0.088}),
    "마량": AU("형주명사", "rel", ally={"int": 0.21}, m={"rate": 0.07}),
    "종회": AU("천하야망", "all", m={"weak_amp": 0.26}),
    "저수": AU("하북지낭", "back", ally={"int": 0.18}, m={"idr": 0.14}),
    # 유생
    "대교": AU("화용월태", "all", m={"regen": 0.018}),
    "소교": AU("내조지공", "all", m={"mregen": 0.88}, foe={"int": -0.1}),
    "장소": AU("원로중신", "all", m={"stres": 0.35}),
    "장완": AU("촉한지주", "fac", ally={"def": 0.14}),
    # 술사
    "우길": AU("부수치병", "all", m={"mregen": 1.4, "fire_res": 0.53}),
    "관로": AU("명운예견", "all", m={"rate": 0.052}, foe={"spd": -0.088}),
    "채문희": AU("귀한지곡", "low", ally={"atk": 0.26, "int": 0.26}),
    "남화노선": AU("천서가호", "all", m={"st_amp": 0.35}),
    # 모사
    "정욱": AU("동아고수", "all", m={"opener": 0.26}, foe={"atk": -0.07}),
    "등애": AU("둔전부국", "all", m={"opener": 0.44}),
    "원술": AU("중가제위", "fac", ally={"atk": 0.14}),      # 11/11 int 는 atk 에 더해진다(MV_ALIAS) —— 공격 두 번 합산 제거
    "전풍": AU("충언역이", "all", m={"rout": 0.44, "stres": 0.18}),
}
# 11/10 전투 밸런스 —— 초월 위세 세기: AURA6 의 수치는 11/9 에 ×1.75 로 올린 값이다. 측정(tests/card_value duel --auraside=mine): 초월 3장 + 전설 6장 덱이 위세를 켠 쪽만 +14%p ·
# 초월 9장은 +43%p 로 너무 셌다 —— 한 단계(×1.75 → ×1.40, 값 ×0.8) 내린다. 값을 키우거나 줄이려면 이 배율만 바꾸고 lines.py 를 다시 돌린다
AURA6_SCALE = 0.8


def aura6_scaled(a):
    out = dict(a)
    for key in ("ally", "m", "foe"):
        if key in out:
            out[key] = {k: round(v * AURA6_SCALE, 4) for k, v in out[key].items()}
    return out


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
    "저수": dict(name="감군지략", shout="군을 나누어 치면 이깁니다.", vfx="aura", eff=[dict(t="foe", tgt="all", buff=dict(stat="def", amt=-0.25, dur=2)), dict(t="hit", kind="int", mult=1.0, tgt="all")]),
    "장완": dict(name="사상의 다스림", shout="나라의 근본은 백성입니다.", vfx="heal", eff=[dict(t="ally", tgt="allyAll", heal=0.2, morale=10), dict(t="ally", tgt="allyAll", buff=dict(stat="def", amt=0.2, dur=2))]),
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
    "관우": dict(n="참장돌파", k="phys", tgt="front3", mult=1.45, exec=0.15, morale=6, cond="always"),
    "장비": dict(n="사모돌격", k="phys", tgt="denseLine", mult=1.1, morale=10, spd=SPD(-0.3), cond="dense:2|front_n:2"),
    "허저": dict(n="나신돌격", k="phys", tgt="front1", mult=1.75, pierce=0.3, selfBuff=SB("def", 0.3), cond="always"),
    "서황": dict(n="포위돌파", k="phys", tgt="line:선봉+전군", mult=1.15, spd=SPD(-0.2), cond="front_n:2|always"),
    "주태": dict(n="불사신", k="phys", tgt="front1", mult=1.2, selfBuff=SB("def", 0.45), stance=SPD(0.4), cond="hurt:0.75"),
    "하후돈": dict(n="혈투돌진", k="phys", tgt="front1", mult=1.6, morale=8, selfBuff=SB("atk", 0.25), cond="always"),
    "조인": dict(n="팔문금쇄진", k="phys", tgt="denseLine", mult=1.0, allyBuff=AB("def", 0.3, "allyFront"), stance=SPD(0.35), cond="hurt:0.8|ally_hurt:0.6"),
    "전위": dict(n="호위난격", k="phys", tgt="front3", mult=1.35, selfBuff=SB("def", 0.25), stance=SPD(0.3), cond="always"),
    "방덕": dict(n="분노참격", k="phys", tgt="front1", mult=1.7, selfBuff=SB("atk", 0.3), cond="always"),
    # 기병
    "조운": dict(n="용담창술", k="phys", tgt="front1", mult=1.55, pierce=0.4, selfBuff=SB("spd", 0.3), cond="always"),
    "마초": dict(n="기마창격", k="phys", tgt="line:선봉+전군", mult=1.15, morale=8, spd=SPD(-0.3), cond="front_n:2|always"),
    "장료": dict(n="합비돌격", k="phys", tgt="back1", mult=1.7, morale=12, cond="always"),
    "손책": dict(n="강동평정", k="phys", tgt="front3", mult=1.3, morale=7, selfBuff=SB("atk", 0.2), cond="always"),
    "마대": dict(n="기습참격", k="phys", tgt="back1", mult=1.6, exec=0.2, cond="always"),
    "장합": dict(n="측면급습", k="phys", tgt="back2", mult=1.3, spd=SPD(-0.3), cond="always"),
    "동탁": dict(n="방화약탈", k="phys", tgt="denseLine", mult=1.15, morale=9, status=ST("burn", 0.08, 2), cond="dense:2|always"),
    "원소": dict(n="하북대군", k="phys", tgt="line:선봉+전군", mult=1.1, allyBuff=AB("atk", 0.15), cond="always"),
    "여포": dict(n="방천화극", k="phys", tgt="front3", mult=1.6, exec=0.2, morale=8, cond="always"),
    "마등": dict(n="강족기마", k="phys", tgt="front1", mult=1.45, spd=SPD(-0.25), cond="always"),
    "공손찬": dict(n="기마궁술", k="phys", tgt="back2", mult=1.3, pierce=0.2, cond="always"),
    # 궁병
    "황충": dict(n="정군산 일격", k="phys", tgt="back1", mult=1.85, exec=0.15, cond="always"),
    "태사자": dict(n="신궁연사", k="phys", tgt="back2", mult=1.35, pierce=0.35, cond="always"),
    "하후연": dict(n="속사난격", k="phys", tgt="denseLine", mult=1.1, spd=SPD(-0.3), selfBuff=SB("spd", 0.2), cond="dense:2|always"),
    "손권": dict(n="사호연사", k="phys", tgt="line:후군", mult=1.15, allyBuff=AB("def", 0.15), cond="always"),
    "정보": dict(n="화살비", k="phys", tgt="all", mult=0.9, morale=5, cond="foe_n:3|always"),
    "황개": dict(n="화선돌격", k="phys", tgt="denseLine", mult=1.0, status=ST("burn", 0.16, 3), cond="no_st:burn"),
    # 도적
    "여몽": dict(n="강상잠행", k="phys", tgt="line:후군", mult=1.3, status=ST("flood", 0.1, 2), cond="always"),
    "감녕": dict(n="수적약탈", k="phys", tgt="back1", mult=1.75, morale=10, spd=SPD(-0.25), cond="always"),
    "능통": dict(n="분전구주", k="phys", tgt="front1", mult=1.5, allyBuff=AB("def", 0.2, "allyFront"), cond="always"),
    "정봉": dict(n="설중분전", k="phys", tgt="front3", mult=1.25, selfBuff=SB("atk", 0.25), cond="always"),
    "위연": dict(n="단독돌진", k="phys", tgt="back2", mult=1.4, status=ST("plague", 6, 3), cond="always"),
    "엄백호": dict(n="산월약탈", k="phys", tgt="back1", mult=1.45, morale=6, cond="always"),
    "장연": dict(n="흑산유격", k="phys", tgt="back2", mult=1.25, spd=SPD(-0.25), cond="always"),
    # 책사
    "제갈량": dict(n="동남풍", k="int", tgt="all", mult=0.95, foeSpd=SPD(-0.3), allyBuff=AB("def", 0.2), cond="foe_n:3|always"),
    "방통": dict(n="철쇄지책", k="int", tgt="denseLine", mult=0.9, status=ST("burn", 0.14, 3), spd=SPD(-0.25), cond="dense:2|no_st:burn"),
    "곽가": dict(n="선견지명", k="int", tgt="line:후군", mult=1.2, defDown={"amt": -0.3, "dur": 2}, morale=8, cond="always"),
    "육손": dict(n="불길매복", k="int", tgt="denseLine", mult=0.85, status=ST("burn", 0.18, 3), cond="dense:2|no_st:burn"),
    "강유": dict(n="북벌지책", k="int", tgt="front3", mult=1.15, morale=8, allyBuff=AB("atk", 0.15, "allyFront"), cond="always"),
    "주유": dict(n="적진방화", k="int", tgt="all", mult=0.85, status=ST("burn", 0.12, 3), cond="foe_n:3|no_st:burn"),
    "마량": dict(n="남만회유", k="int", tgt="back2", mult=1.25, defDown={"amt": -0.3, "dur": 2}, cond="always"),
    "종회": dict(n="벌촉지책", k="int", tgt="line:선봉+전군", mult=1.1, morale=8, cond="always"),
    # 유생
    "유비": dict(n="백성구휼", k="int", tgt="all", mult=0.75, tHeal=0.08, cleanse=1, allyBuff=AB("def", 0.15), cond="ally_hurt:0.75|ally_st"),
    "순욱": dict(n="천하경략", k="int", tgt="all", mult=0.7, tHeal=0.06, allyBuff=AB("def", 0.2), cond="ally_hurt:0.85"),
    "노숙": dict(n="합종연횡", k="int", tgt="all", mult=0.8, heal=10, rally=True, allyBuff=AB("def", 0.2), cond="ally_morale:90|ally_hurt:0.8"),
    "법정": dict(n="기책보은", k="int", tgt="front3", mult=1.15, morale=8, allyBuff=AB("atk", 0.2, "allyFront"), cond="always"),
    "서서": dict(n="격검유협", k="int", tgt="front3", mult=1.2, allyBuff=AB("def", 0.2, "allyFront"), cond="always"),
    "사마휘": dict(n="명사담론", k="int", tgt="all", mult=0.7, heal=12, rally=True, allyBuff=AB("def", 0.25), cond="ally_morale:90|ally_hurt:0.8"),
    "대교": dict(n="자애치유", k="int", tgt="front3", mult=0.7, tHeal=0.1, allyBuff=AB("def", 0.2), cond="ally_hurt:0.75"),
    "소교": dict(n="금슬화음", k="int", tgt="all", mult=0.8, morale=10, heal=8, rally=True, cond="foe_morale|ally_morale:85"),
    "장소": dict(n="직언상소", k="int", tgt="all", mult=0.7, allyBuff=AB("def", 0.2), cleanse=1, cond="ally_st|ally_hurt:0.7"),
    # 술사
    "장각": dict(n="황건봉기", k="int", tgt="all", mult=0.85, status=ST("confuse", 1, 1), morale=8, cond="foe_n:3"),
    "좌자": dict(n="둔갑술", k="int", tgt="front3", mult=1.0, status=ST("confuse", 1, 1), foeSpd=SPD(-0.3), cond="always"),
    "화타": dict(n="마비산", k="int", tgt="front3", mult=0.85, tHeal=0.1, cleanse=2, cond="ally_hurt:0.7|ally_st"),
    "장로": dict(n="귀도주술", k="int", tgt="all", mult=0.8, status=ST("plague", 6, 3), cond="no_st:plague"),
    "우길": dict(n="강동신선", k="int", tgt="front3", mult=1.0, status=ST("confuse", 1, 1), morale=6, cond="always"),
    "관로": dict(n="주역점복", k="int", tgt="back2", mult=1.2, defDown={"amt": -0.35, "dur": 2}, cond="always"),
    # 모사
    "조조": dict(n="협천자령", k="int", tgt="all", mult=1.0, morale=9, allyBuff=AB("atk", 0.15), cond="foe_morale|foe_n:3"),
    "사마의": dict(n="인내지계", k="int", tgt="line:후군", mult=1.25, defDown={"amt": -0.3, "dur": 2}, morale=8, cond="always"),
    "가후": dict(n="완성기책", k="int", tgt="back2", mult=1.35, status=ST("plague", 8, 3), cond="always"),
    "초선": dict(n="미인계", k="int", tgt="front3", mult=0.95, status=ST("confuse", 1, 1), morale=10, cond="always"),
    "정욱": dict(n="복병기습", k="int", tgt="all", mult=1.05, foeSpd=SPD(-0.25), morale=7, cond="foe_n:3|always"),
    "등애": dict(n="산도돌파", k="int", tgt="back1", mult=1.5, morale=10, cond="always"),
    "원술": dict(n="칙령반포", k="int", tgt="all", mult=0.95, morale=7, allyBuff=AB("def", 0.1), cond="always"),
    "관평": dict(n="수호참격", k="phys", tgt="front3", mult=1.25, allyBuff=AB("def", 0.15, "allyFront"), cond="always"),
    "고순": dict(n="철갑돌진", k="phys", tgt="front1", mult=1.6, pierce=0.3, cond="always"),
    # 11/5 희귀 명단 정리로 새로 든 인물 (ADD4)
    "우금": dict(n="엄정군율", k="phys", tgt="front3", mult=1.2, allyBuff=AB("def", 0.15, "allyFront"), cond="always"),
    "곽회": dict(n="옹량방어", k="phys", tgt="front1", mult=1.4, selfBuff=SB("def", 0.2), cond="always"),
    "학소": dict(n="진창노격", k="phys", tgt="back2", mult=1.3, pierce=0.2, cond="always"),
    "장패": dict(n="태산유격", k="phys", tgt="back1", mult=1.5, morale=6, cond="always"),
    "엄안": dict(n="노장궁술", k="phys", tgt="back1", mult=1.6, exec=0.1, cond="always"),
    "장포": dict(n="부전자전", k="phys", tgt="back1", mult=1.5, spd=SPD(-0.2), cond="always"),
    "맹달": dict(n="반복지계", k="int", tgt="back2", mult=1.2, morale=8, cond="always"),
    "반장": dict(n="맥성포박", k="phys", tgt="back1", mult=1.5, spd=SPD(-0.3), cond="always"),
    "제갈각": dict(n="동흥대첩", k="int", tgt="denseLine", mult=1.0, morale=7, cond="dense:2|always"),
    "우번": dict(n="역경점술", k="int", tgt="back2", mult=1.15, defDown={"amt": -0.25, "dur": 2}, cond="always"),
    "여범": dict(n="강동재략", k="int", tgt="all", mult=0.9, morale=7, cond="foe_n:3|always"),
    "고람": dict(n="하북철벽", k="phys", tgt="front1", mult=1.4, selfBuff=SB("def", 0.25), cond="always"),
    "황조": dict(n="강하저격", k="phys", tgt="back1", mult=1.7, cond="always"),
    "장만성": dict(n="남양봉기", k="phys", tgt="back2", mult=1.3, morale=6, cond="always"),
    "관흥": dict(n="청룡계승", k="phys", tgt="front3", mult=1.25, morale=6, cond="always"),
    "오반": dict(n="촉한기병", k="phys", tgt="front1", mult=1.45, spd=SPD(-0.2), cond="always"),
    "비의": dict(n="경국안민", k="int", tgt="all", mult=0.7, tHeal=0.06, allyBuff=AB("def", 0.15), cond="ally_hurt:0.85"),
    # 11/5 이름값 구간 정리로 든 희귀 14명
    "문빙": dict(n="강릉수비", k="phys", tgt="front1", mult=1.3, selfBuff=SB("def", 0.2), cond="always"),
    "주연": dict(n="송곳대열", k="phys", tgt="front3", mult=1.15, morale=5, cond="always"),
    "왕쌍": dict(n="대가산전", k="phys", tgt="front1", mult=1.55, cond="always"),
    "조홍": dict(n="호표기돌격", k="phys", tgt="line:선봉+전군", mult=1.1, spd=SPD(-0.15), cond="front_n:2|always"),
    "한수": dict(n="서량연합", k="phys", tgt="front1", mult=1.3, allyBuff=AB("atk", 0.1), cond="always"),
    "진무": dict(n="연노난사", k="phys", tgt="back2", mult=1.2, cond="always"),
    "하제": dict(n="산월토벌", k="phys", tgt="denseLine", mult=1.05, morale=5, cond="dense:2|always"),
    "이각": dict(n="장안약탈", k="phys", tgt="back1", mult=1.4, morale=6, cond="always"),
    "황권": dict(n="익주방략", k="int", tgt="front3", mult=1.05, allyBuff=AB("def", 0.12, "allyFront"), cond="always"),
    "순유": dict(n="군사기책", k="int", tgt="back2", mult=1.2, defDown={"amt": -0.2, "dur": 2}, cond="always"),
    "도겸": dict(n="서주양보", k="int", tgt="all", mult=0.7, tHeal=0.05, allyBuff=AB("def", 0.12), cond="ally_hurt:0.85"),
    "길평": dict(n="독약처방", k="int", tgt="front3", mult=0.9, status=ST("plague", 5, 3), cond="no_st:plague"),
    "이의": dict(n="천명예언", k="int", tgt="back2", mult=1.0, defDown={"amt": -0.25, "dur": 2}, cond="always"),
    "이유": dict(n="짐독계", k="int", tgt="front3", mult=0.95, status=ST("plague", 6, 3), morale=5, cond="always"),
    "공융": dict(n="공문가훈", k="int", tgt="all", mult=0.7, tHeal=0.06, allyBuff=AB("def", 0.15), cond="ally_hurt:0.85"),
    "화웅": dict(n="일도양단", k="phys", tgt="front1", mult=1.6, morale=8, cond="always"),
    "문추": dict(n="하북돌기", k="phys", tgt="line:선봉+전군", mult=1.15, morale=6, cond="front_n:2|always"),
    "서성": dict(n="강변사격", k="phys", tgt="back2", mult=1.25, allyBuff=AB("def", 0.12), cond="always"),
    "황월영": dict(n="연노사격", k="phys", tgt="all", mult=0.85, cond="foe_n:3|always"),
    "주환": dict(n="매복기습", k="phys", tgt="back1", mult=1.6, spd=SPD(-0.2), cond="always"),
    "손상향": dict(n="쌍검난무", k="phys", tgt="back2", mult=1.35, selfBuff=SB("spd", 0.2), cond="always"),
    "저수": dict(n="분진지책", k="int", tgt="line:후군", mult=1.2, defDown={"amt": -0.25, "dur": 2}, cond="always"),
    "장완": dict(n="안민지책", k="int", tgt="all", mult=0.7, tHeal=0.06, allyBuff=AB("def", 0.15), cond="ally_hurt:0.8"),
    "채문희": dict(n="비분시", k="int", tgt="all", mult=0.75, heal=8, rally=True, morale=6, cond="ally_morale:85|foe_n:3"),
    "남화노선": dict(n="선도비술", k="int", tgt="front3", mult=1.0, status=ST("confuse", 1, 1), cond="always"),
    "전풍": dict(n="직간", k="int", tgt="back2", mult=1.3, morale=8, cond="always"),
    "진궁": dict(n="충절지책", k="int", tgt="line:선봉+전군", mult=1.2, defDown={"amt": -0.3, "dur": 2}, morale=7, cond="always"),
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
    # 고급 명단 (ROSTER3) —— 있는 카드는 병종을 맞추고, 없는 인물은 새로, 명단 밖은 적 전용
    want3 = {}
    for f_, names in ROSTER3.items():
        for i_, p_ in enumerate(names.split()):
            want3[p_] = (ORDER[i_], f_)
    std3 = (int(statistics.median([c[10] for c in CARDS if c[2] == 3])), int(statistics.median([c[11] for c in CARDS if c[2] == 3])))
    moved3, retire3, have3 = [], [], {}
    for c in CARDS:
        if c[2] != 3 or c[13] == "foe":
            continue
        p_ = person(c)
        if p_ not in want3 or p_ in have3:
            retire3.append(c[0])
            continue
        tag_, fac_ = want3[p_]
        have3[p_] = c
        if c[3] != tag_:
            a0, a1 = avg[(c[3], 3)], avg[(tag_, 3)]
            for j_ in range(4):
                c[5 + j_] = round(c[5 + j_] * a1[j_] / a0[j_]) if a0[j_] > 0 else round(a1[j_])
            c[9] = round(a1[4])
            c[3] = tag_
            moved3.append(c)
    old3 = {person(c): c for c in CARDS if c[2] == 3 and c[13] != "foe"}      # 희귀로 올리는 인물의 옛 고급 능력치
    for i_, (p_, (tag_, fac_)) in enumerate(sorted((p, v) for p, v in want3.items() if p not in have3)):
        card = ["G%02d" % (i_ + 1), p_, 3, tag_, fac_] + [round(x) for x in avg[(tag_, 3)]] + [std3[0], std3[1], {"n": "", "eff": {}, "psv": None}, "", ""]
        moved3.append(card)
        BY_ID[card[0]] = card
    new_cards = list(moved3)      # 같은 id 로 내보내 원본 카드를 덮어쓴다 (DB 는 뒤에 온 것을 쓴다)
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
    retire = [c[0] for c in CARDS if c[2] in (4, 6) and person(c) in chain] + retire3
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
        if p in have4 or p in NO_RARE:
            continue
        a0, a1 = avg[(ref[3], 6)], avg[(ref[3], 4)]
        st = [round(ref[5 + j] * a1[j] / a0[j]) if a0[j] > 0 else ref[5 + j] for j in range(5)]
        st[4] = ref[9]
        cid = "R%02d" % (i + 1)
        card = [cid, p, 4, ref[3], ref[4]] + st + [std[4][0], std[4][1], {"n": "", "eff": {}, "psv": None}, "", ""]
        new_cards.append(card)
        BY_ID[cid] = card
        # 11/5 사용자: 고급이 도적에 쏠리고 조합에 같은 재료가 너무 많이 든다 —— 예전엔 이름이 겹친다며 그 인물의 고급 카드를
        # 적 전용으로 돌렸지만(고급 모사가 심배 하나만 남았다), 이제 남겨 고급 → 희귀 → 초월 줄기로 잇는다 (기인 인물은 아래에서 뺀다)
    retire += [c[0] for c in CARDS if c[2] == 2]         # 11/3 일반 등급 삭제 —— 토벌 편성에는 남는다
    # 이름값 구간 (11/5) —— ① TRANS_UP 의 전설판 (초월 카드 × 병종 전설/초월 평균 비, 이름만)
    for i_, p_ in enumerate(TRANS_UP):
        ref = next(c for c in BY_ID.values() if c[2] == 6 and c[13] != "foe" and person(c) == p_)
        if any(c[2] == 5 and c[13] != "foe" and person(c) == p_ for c in BY_ID.values()):
            continue
        a0, a1 = avg[(ref[3], 6)], avg[(ref[3], 5)]
        st = [round(ref[5 + j] * a1[j] / a0[j]) if a0[j] > 0 else ref[5 + j] for j in range(5)]
        st[4] = ref[9]
        card = ["E%02d" % (i_ + 1), p_, 5, ref[3], ref[4]] + st + [std[5][0], std[5][1], {"n": "", "eff": {}, "psv": None}, "", ""]
        new_cards.append(card)
        BY_ID[card[0]] = card
    orig_ids = {c[0] for c in CARDS}
    def _drop(c):
        if c[0] in orig_ids:
            retire.append(c[0])
        elif c in new_cards:
            new_cards.remove(c)
        BY_ID.pop(c[0], None)
    # ② NO_RARE 의 희귀판 빼기 · ③ TRANS_DOWN 의 초월 빼기 (희귀판은 남는다)
    for c in list(BY_ID.values()):
        if c[13] == "foe":
            continue
        if c[2] == 4 and person(c) in NO_RARE:
            _drop(c)
        elif c[2] == 6 and person(c) in TRANS_DOWN:
            _drop(c)
    # 희귀 더하기 (ADD4)
    have4 = {person(c) for c in BY_ID.values() if c[2] == 4 and c[13] != "foe" and c[0] not in retire}
    for i_, (p_, (tag_, fac_)) in enumerate(ADD4.items()):
        if p_ in have4:
            continue
        a1 = avg[(tag_, 4)]
        if p_ in old3:
            o = old3[p_]
            a0 = avg[(o[3], 3)]
            st = [round(o[5 + j_] * a1[j_] / a0[j_]) if a0[j_] > 0 else round(a1[j_]) for j_ in range(4)] + [round(a1[4])]
        else:
            st = [round(x) for x in a1]
        card = ["H%02d" % (i_ + 1), p_, 4, tag_, fac_] + st + [std[4][0], std[4][1], {"n": "", "eff": {}, "psv": None}, "", ""]
        new_cards.append(card)
        BY_ID[card[0]] = card
    # 11/3 기인 —— 그 인물의 다른 카드는 모두 빼고 기인 한 장
    retire += [c[0] for c in CARDS if person(c) in KIIN]
    for c in [c for c in new_cards if person(c) in KIIN]:
        new_cards.remove(c)
        BY_ID.pop(c[0], None)
    for i, (p, (title, tag, fac, pref, _au)) in enumerate(KIIN.items()):
        st = [round(x * KIIN_MUL) for x in avg[(tag, 5)]]
        st[4] = round(avg[(tag, 5)][4])
        cid = "K%02d" % (i + 1)
        card = [cid, title, 5, tag, fac] + st + [std[5][0], std[5][1], {"n": "", "eff": {}, "psv": None}, "kiin", ""]
        new_cards.append(card)
        BY_ID[cid] = card
        REL[p] = pref.split() + [r for r in REL.get(p, []) if r not in pref.split()]
    # 신화 12명 —— 나머지 신화 카드는 적 전용, 사마의 신화는 새로
    for c in list(BY_ID.values()):
        if c[2] == 8 and person(c) not in MYTH12:
            retire.append(c[0])
            if c in new_cards:
                new_cards.remove(c)
    for p, (title, item, _au) in NEW_MYTH.items():
        ref = BY_ID[per[p][7][0]]
        a0, a1 = avg[(ref[3], 7)], avg[(ref[3], 8)]
        st = [round(ref[5 + j] * a1[j] / a0[j]) if a0[j] > 0 else ref[5 + j] for j in range(5)]
        st[4] = ref[9]
        n += 1
        cid = "L%02d" % n
        card = [cid, title, 8, ref[3], ref[4]] + st + [std[8][0], std[8][1], {"n": "", "eff": {}, "psv": None}, "myth", item]
        new_cards.append(card)
        BY_ID[cid] = card
    for k in retire:
        BY_ID.pop(k, None)
    retire.sort()

    allc = list(BY_ID.values())
    # 11/5 사용자: 희귀 조합을 획일적으로 두지 말고 다양하게 —— 비용(기본패 환산)을 희귀마다 다르게, 능력치 · 병력 · 전력값은 비용을 따라간다.
    # 줄기 희귀(같은 인물 전설 · 초월이 있음)는 재료 웃돈 RARE_PREMIUM (비싸지만 능력치는 그만큼 오르지 않는다)
    # 비용 → 모양: RARE_SHAPE (고급 수, 기본 수). 재료는 5장을 넘기지 않는다
    rare_cost = {}
    upper = {(person(x), x[2]) for x in allc if x[2] in (5, 6) and x[13] != "foe"}
    r4 = sorted([x for x in allc if x[2] == 4 and x[13] != "foe"], key=lambda x: (x[3], x[0]))
    by_tag4 = {}
    for x in r4:
        by_tag4.setdefault(x[3], []).append(x)
    for tag_, xs in by_tag4.items():
        line_ = [x for x in xs if (person(x), 5) in upper or (person(x), 6) in upper]
        solo_ = [x for x in xs if x not in line_]
        for i_, x in enumerate(line_):
            rare_cost[x[0]] = RARE_LINE_COSTS[(i_ + ORDER.index(tag_)) % len(RARE_LINE_COSTS)]
        for i_, x in enumerate(solo_):
            rare_cost[x[0]] = RARE_SOLO_COSTS[(i_ * 2 + ORDER.index(tag_)) % len(RARE_SOLO_COSTS)]
    for x in r4:
        c_ = rare_cost[x[0]]
        eff_ = c_ - (RARE_PREMIUM if x[0] in [y[0] for y in r4 if (person(y), 5) in upper or (person(y), 6) in upper] else 0)
        f_ = 1.0 + RARE_SCALE * (eff_ - 10) / 10.0
        for j_ in (5, 6, 7, 8):
            x[j_] = round(x[j_] * f_)
        x[10] = int(round(x[10] * f_ / 100.0) * 100)
        x[11] = max(1, round(x[11] * f_ * f_))
        if not any(y is x for y in new_cards):
            new_cards.append(x)
    by_pt = {}
    for c in allc:
        by_pt.setdefault((person(c), c[2]), c[0])
    used = {}
    # 11/5 사용자: 조합에 같은 재료가 너무 많이 든다 —— 재료 한 장이 그 등급 평균보다 많이 쓰이지 않게 상한 (넘으면 후보에서 뒤로)
    cap = {3: 6, 4: 6, 5: 5}
    pairs = {}          # 등급 -> 이미 쓴 재료 짝 (11/3 사용자: 조합식이 너무 겹친다 —— 진궁 · 초선이 똑같은 재료였다)

    def pick(c, t, exclude, mats):
        """c 에 넣을 t 등급 재료 하나 —— 인연 인물 > 같은 세력 같은 병종 > 같은 세력 > 같은 병종 > 그 밖.
        많이 쓰인 재료 · 같은 등급 다른 조합과 짝이 겹치는 재료는 벌점 (재료 둘이 같은 조합이 생기지 않게)"""
        p = person(c)
        rel = REL.get(p, [])
        pr = pairs.setdefault(c[2], set())
        cands = []
        for x in allc:
            if x[2] != t or x[0] in exclude or person(x) == p or x[13] in ("myth", "immortal", "kiin"):
                continue
            q = person(x)
            if q in rel:
                rank = rel.index(q) * 0.3
            elif x[4] == c[4] and x[3] == c[3]:
                rank = 2.5
            elif x[3] == c[3]:
                rank = 3
            elif x[4] == c[4]:
                rank = 3.5
            else:
                rank = 9           # 세력도 병종도 다른 재료는 맛이 없다 —— 거의 쓰지 않는다
            rank += 2.0 * used.get(x[0], 0)
            if used.get(x[0], 0) >= cap.get(t, 99):
                rank += 50
            rank += 6.0 * sum(1 for m in mats if frozenset((m, x[0])) in pr)
            cands.append((rank, x[0]))
        cands.sort()
        k = cands[0][1]
        used[k] = used.get(k, 0) + 1
        return k

    # 고급 조합 짝 (T3) —— 제 병종 2 + 다른 병종 2. 명단을 바꿔 짝이 없거나 제 병종이 끼었거나, 같은 병종 고급끼리 겹치면 고른다
    t3c = sorted([c for c in allc if c[2] == 3 and c[13] != "foe"], key=lambda c: c[0])
    pair_of, tag_use = {}, {}
    for c in t3c:
        pr_ = T3.get(person(c), "").split()
        if len(pr_) == 2 and c[3] not in pr_ and frozenset(pr_) not in {frozenset(x) for q, x in pair_of.items() if BY_ID[q][3] == c[3]}:
            pair_of[c[0]] = pr_
            for x in pr_: tag_use[x] = tag_use.get(x, 0) + 1
    for c in t3c:
        if c[0] in pair_of:
            continue
        taken = {frozenset(x) for q, x in pair_of.items() if BY_ID[q][3] == c[3]}
        best = None
        for a_ in ORDER:
            for b_ in ORDER:
                if a_ >= b_ or c[3] in (a_, b_) or frozenset((a_, b_)) in taken:
                    continue
                sc = tag_use.get(a_, 0) + tag_use.get(b_, 0)
                if best is None or sc < best[0]:
                    best = (sc, [a_, b_])
        pair_of[c[0]] = best[1]
        for x in best[1]: tag_use[x] = tag_use.get(x, 0) + 1
    for c in t3c:
        T3[person(c)] = " ".join(pair_of[c[0]])

    recipes = {}
    base_use = {}
    for c in sorted(allc, key=lambda x: (x[2], x[0])):
        t = c[2]
        if c[13] == "kiin":                  # 기인 = 희귀 2 (인연) + 고급 1 + 제 병종 기본
            mats, ex = [], {c[0]}
            for _ in range(2):
                mats.append(pick(c, 4, ex, mats)); ex.add(mats[-1])
            mats.append(pick(c, 3, ex, mats)); ex.add(mats[-1])
            recipes[c[0]] = mats + [BASE[c[3]]]
            continue
        if t == 3 and person(c) in T3:       # 고급 = 제 병종 2 + 다른 병종 2 (일반 등급 없음)
            recipes[c[0]] = [BASE[c[3]], BASE[c[3]]] + [BASE[x] for x in T3[person(c)].split()]
            continue
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
            n3, nb = RARE_SHAPE[rare_cost[c[0]]]
            while len(mats) < n3:
                mats.append(pick(c, 3, ex, mats)); ex.add(mats[-1])
            # 기본패 —— 제 병종 먼저, 나머지는 같은 병종 희귀와 재료가 거의 같아지지 않는 병종 (예전: 고급 재료의 다른 병종 → 11쌍이 3/4 겹쳤다)
            sibs = [recipes[q] for q in recipes if BY_ID[q][2] == 4 and BY_ID[q][3] == c[3]]
            bases = [base] if nb > 0 else []
            while len(bases) < nb:
                best_, bs_ = None, None
                for tg_ in ORDER:
                    cand_ = mats + bases + [BASE[tg_]]
                    clash = 0
                    for sm in sibs:
                        if len(sm) == n3 + nb:
                            share = sum((Counter(sm) & Counter(cand_)).values())
                            clash += 1 if share >= len(cand_) else 0
                    sc_ = clash * 100 + base_use.get(tg_, 0) + (50 if BASE[tg_] in bases and tg_ != c[3] else 0)
                    if bs_ is None or sc_ < bs_:
                        best_, bs_ = tg_, sc_
                bases.append(BASE[best_])
                base_use[best_] = base_use.get(best_, 0) + 1
            mats += bases
        elif t == 5:
            if not prev:
                mats.append(pick(c, 4, ex, mats)); ex.add(mats[-1])
            mats.append(pick(c, 4, ex, mats)); ex.add(mats[-1])
            while len(mats) < 4:
                mats.append(pick(c, 3, ex, mats)); ex.add(mats[-1])
        elif t == 6:         # 초월 —— 11/5 이름값 구간: 제 전설 + 전설 1 + 희귀 1 (비용은 예전 '제 희귀 + 전설 2' 와 같다)
            mats = []
            ex = {c[0]}
            own5 = by_pt.get((p, 5))
            mats.append(own5 if own5 else pick(c, 5, ex, mats)); ex.add(mats[-1])
            mats.append(pick(c, 5, ex, mats)); ex.add(mats[-1])
            mats.append(pick(c, 4, ex, mats)); ex.add(mats[-1])
        elif t == 7:         # 불멸 —— 제 전설 + 인연 전설 2 + 희귀 1 + 기본 1
            if not prev:
                mats.append(pick(c, 5, ex, mats)); ex.add(mats[-1])
            mats.append(pick(c, 5, ex, mats)); ex.add(mats[-1])
            mats.append(pick(c, 5, ex, mats)); ex.add(mats[-1])
            mats.append(pick(c, 4, ex, mats)); ex.add(mats[-1])
            mats.append(base)
        elif t == 8:
            assert prev, c
            mats.append(pick(c, 5, ex, mats)); ex.add(mats[-1])
            # 11/5 같은 기본패 둘 → 제 병종 + 함께 넣은 전설의 병종 (같으면 다음 병종)
            t2 = BY_ID[mats[-1]][3]
            mats += [base, BASE[t2 if t2 != c[3] else ORDER[(ORDER.index(c[3]) + 1) % 8]]]
        recipes[c[0]] = mats
        nb = [m for m in mats if m in BY_ID]
        for i in range(len(nb)):
            for j in range(i + 1, len(nb)):
                pairs.setdefault(t, set()).add(frozenset((nb[i], nb[j])))

    # 11/7 사용자: 초월 · 기인이 버려지고 신화 · 불멸로만 덱을 짠다 —— 같은 비용이면 불멸 쪽이 늘 이겼다 (tests/budget_mix:
    # 불멸4 + 희귀5 대 초월5 + 기인3 + 전설1 이 95%). 초월의 두 번째 재료(인연 전설)를 인연 희귀로 —— 기본패 환산 약 67 → 약 48.
    # 다른 조합을 다 만든 뒤에 바꿔서 불멸 · 신화 재료 고르기(사용 횟수)는 예전 그대로다
    for c in sorted(allc, key=lambda x: x[0]):
        if c[2] == 6 and c[13] != "kiin" and c[0] in recipes and len(recipes[c[0]]) == 3:
            mats = recipes[c[0]]
            ex = {c[0]} | set(mats)
            mats[1] = pick(c, 4, ex, [mats[0], mats[2]])
    # 11/9 사용자: 초월 · 기인 몸을 불멸 평균의 0.75 · 0.88 / 0.7 · 0.85 로 올렸다(db.gd set_branch) —— 비용도 불멸(약 95)의 약 0.8 배로.
    #   초월 = 제 전설 + 인연 전설 1 + 희귀 2 + 제 병종 기본 (약 48 → 약 77)
    #   기인 = 인연 전설 2 + 인연 희귀 2 (약 25 → 약 76, 예전 희귀 2 + 고급 1 + 기본 —— 희귀 둘은 그대로 두고 고급 · 기본을 전설로)
    # 11/7 처럼 다른 조합을 다 만든 뒤에 바꿔서 불멸 · 신화 재료 고르기(사용 횟수)는 그대로다
    for c in sorted(allc, key=lambda x: x[0]):
        if c[2] == 6 and c[13] != "kiin" and c[0] in recipes and len(recipes[c[0]]) == 3:
            mats = recipes[c[0]]
            ex = {c[0]} | set(mats)
            recipes[c[0]] = [mats[0], pick(c, 5, ex, mats), mats[1], mats[2], BASE[c[3]]]
    for c in sorted(allc, key=lambda x: x[0]):
        if c[13] == "kiin" and c[0] in recipes:
            mats = recipes[c[0]]
            ex = {c[0]} | set(mats)
            l1 = pick(c, 5, ex, mats[:2]); ex.add(l1)
            recipes[c[0]] = [l1, pick(c, 5, ex, [l1] + mats[:2])] + mats[:2]

    aura = {}
    for c in allc:
        if c[2] == 6 and c[13] != "foe":
            assert person(c) in AURA6, person(c)
            au = aura6_scaled(AURA6[person(c)])
            if au.get("to") == "rel":
                au["rel"] = [person(c)] + REL.get(person(c), [])
            aura[c[0]] = au
    for c in allc:
        if c[13] == "kiin":
            aura[c[0]] = KIIN[person(c)][4]
        if c[2] == 8 and person(c) in NEW_MYTH:
            aura[c[0]] = NEW_MYTH[person(c)][2]
    ladder = fill_ladders(allc)
    # 11/4 사용자: 전설은 네임드 장수만 있으니 접두어 없이 이름만 ('의절 관우' → '관우'). 기인은 따로 등급이라 칭호를 둔다
    rename = {c[0]: person(c) for c in allc if c[2] == 5 and c[13] != "kiin" and " " in c[1]}
    # 11/4 사용자: 칭호는 '신산 · 비장 · 호치' 처럼 짧고 그 사람을 떠올리게 하는 별명 (자는 쓰지 않는다). 밋밋한 일반 단어만 바꾼다
    for c in allc:
        if c[1] in TITLE_FIX:
            rename[c[0]] = TITLE_FIX[c[1]]
    for c in new_cards:
        if c[0] in rename:
            c[1] = rename[c[0]]
    out = {"_설명": __doc__.strip(), "cards": new_cards, "recipes": recipes, "skills": SKILL,
           "retire": retire, "aura": aura, "ults": ULT6, "ladder_from": LADDER_FROM, "ladder": ladder, "items": NEW_ITEMS, "rename": rename}
    json.dump(out, open(os.path.join(ROOT, "lines.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    # 확인용 —— 관우 줄기
    nm = lambda k: BY_ID[k][1] + str(BY_ID[k][2])
    for p_ in ["관우", "조인", "관평", "마량", "서성"]:
        for t in range(4, 9):
            k = by_pt.get((p_, t))
            if k:
                print(nm(k), "=", " + ".join(nm(m) for m in recipes[k]))
    print("위세 %d장 (초월 · 기인 · 새 신화) · 적 전용으로 돌린 원본 %d장" % (len(aura), len(retire)))
    for t in (3, 4, 5):
        xs = [c for c in allc if c[2] == t]
        print("등급 %d: %d장 —— %s" % (t, len(xs), " ".join(c[1] for c in xs)))
    print("새 카드 %d장 · 조합 %d개 · 고유 기술 %d명" % (len(new_cards), len(recipes), len(SKILL)))
    miss = sorted({person(c) for c in allc if c[2] >= 4} - set(SKILL))
    print("고유 기술 없는 인물:", miss)
    print("특기 사다리를 채운 인물 %d명" % len(out["ladder"]))
    seen = {}
    for k, v in recipes.items():
        key = tuple(sorted(v))
        if key in seen:
            print("같은 조합:", nm(k), nm(seen[key]))
        seen[key] = k


def fill_ladders(allc):
    """작성된 사다리는 보존하고, 원래 배정이 없는 저등급 인물만 직접 선별한 특기로 채운다."""
    P = json.load(open(os.path.join(ROOT, "passives.json"), encoding="utf-8"))
    T = P["traits"]
    tiers = {}
    for c in allc:
        if c[2] >= 3:
            tiers.setdefault(person(c), set()).add(c[2])
    out = {}
    for p_, ts in tiers.items():
        if p_ in P["ladder"] or p_ in LADDER_FROM:
            continue
        traits = PERSONAL_SPECIALTIES.get(p_, [])
        if not traits:
            continue
        assert len(traits) == len(set(traits)), p_
        assert all(n in T and not T[n].get("scope") and not T[n].get("unique", False) for n in traits), p_
        start = min(ts)
        out[p_] = [[n, start] for n in traits]
    return out


main()
