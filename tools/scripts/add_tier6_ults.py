"""초월 고유기 (2026-10-30) —— 초월부터 고유기를 쓴다. 고유기가 없던 초월 인물 18명의 것을 새로 넣는다.
수치는 다른 고유기처럼 신화 기준이고, 초월 카드는 tier6_scale 배로 쓴다 (불멸 tier7_scale).

실행: python -I tools/scripts/add_tier6_ults.py   (solgukji_godot/data/ultimates.json 을 고친다)
"""
import json
from collections import OrderedDict

PATH = "solgukji_godot/data/ultimates.json"
U = json.load(open(PATH, encoding="utf-8"), object_pairs_hook=OrderedDict)


def hit(kind, mult, tgt, **kw):
    return dict(t="hit", kind=kind, mult=mult, tgt=tgt, **kw)


def ally(tgt, **kw):
    return dict(t="ally", tgt=tgt, **kw)


def foe(tgt, **kw):
    return dict(t="foe", tgt=tgt, **kw)


def buff(stat, amt, dur=2):
    return dict(stat=stat, amt=amt, dur=dur)


def st(k, val, dur):
    return dict(k=k, val=val, dur=dur)


NEW = {
    "공손찬": ("백마의종", "백마의종이여, 오랑캐를 짓밟아라!", "charge",
            [hit("phys", 2.2, "line:선봉+전군", morale=12), foe("line:선봉+전군", buff=buff("spd", -0.25))]),
    "마등": ("서량의 기치", "서량의 철기여, 나를 따르라!", "charge",
           [hit("phys", 2.0, "front3"), ally("allyAll", buff=buff("spd", 0.25))]),
    "주태": ("십이창흔", "이 몸의 상처가 곧 주군을 지킨 증표다!", "roar",
           [ally("self", heal=0.35), ally("allyFront", buff=buff("def", 0.4)), hit("phys", 1.8, "front3")]),
    "방덕": ("대관결사", "관을 지고 왔다. 오늘 살아 돌아갈 생각은 없다!", "slash",
           [hit("phys", 3.8, "front1", exec=0.3), ally("self", buff=buff("def", 0.3))]),
    "황개": ("고육지계", "늙은 몸을 태워 적벽을 밝히리라!", "firestorm",
           [hit("phys", 1.5, "denseLine", status=st("burn", 0.15, 3)), ally("self", heal=0.15)]),
    "정보": ("노장의 화선", "강동 삼대를 모신 늙은 창이다!", "firestorm",
           [hit("phys", 1.6, "front3", status=st("burn", 0.12, 3)), ally("allyFront", buff=buff("def", 0.2))]),
    "능통": ("결사보주", "주군께서는 먼저 강을 건너십시오!", "slash",
           [hit("phys", 2.4, "front3", morale=10), ally("allyAll", buff=buff("def", 0.25))]),
    "엄백호": ("동오덕왕", "강동의 산은 우리 것이다!", "shadow",
            [hit("phys", 2.6, "back2", status=st("bleed", 0.1, 3))]),
    "방통": ("봉추연환", "배를 잇고, 불을 놓아라.", "firestorm",
           [hit("int", 1.5, "all", status=st("burn", 0.12, 3)), foe("all", buff=buff("spd", -0.3))]),
    "마량": ("백미의 지략", "마씨 오상 가운데 백미가 가장 낫다 했지요.", "aura",
           [ally("allyAll", buff=buff("int", 0.3), morale=15), ally("allyAll", buff=buff("res", 0.25)), hit("int", 1.0, "all")]),
    "종회": ("사도의 대군", "촉은 이미 내 손 안에 있다.", "illusion",
           [hit("int", 1.8, "all", morale=12), foe("back1", status=st("seal", 1, 2))]),
    "대교": ("국색천향", "부디 다치지 마세요.", "heal",
           [ally("allyAll", heal=0.22, morale=15), foe("front3", morale=10)]),
    "소교": ("청아지음", "공근께서 곡을 틀리시면 돌아보시지요.", "aura",
           [ally("allyAll", buff=buff("int", 0.3), morale=15), hit("int", 0.8, "all")]),
    "장소": ("보국지책", "나라를 지키는 것은 칼이 아니라 계책이오.", "aura",
           [ally("allyAll", buff=buff("res", 0.35), morale=15), ally("allyAll", buff=buff("def", 0.2))]),
    "우길": ("청우강림", "하늘이여, 비를 내리소서.", "heal",
           [ally("allyAll", heal=0.25, cleanse=1), foe("all", status=st("flood", 0.1, 2))]),
    "정욱": ("십면매복", "사방이 모두 우리 군사다.", "illusion",
           [hit("int", 1.3, "all"), foe("all", buff=buff("atk", -0.25))]),
    "등애": ("음평기습", "길이 없으면 굴러서라도 넘는다!", "shadow",
           [hit("int", 3.2, "back1", exec=0.3), foe("all", morale=15)]),
    "원술": ("옥새칭제", "천명은 원씨에게 있다! 짐이 황제다!", "aura",
           [ally("allyAll", buff=buff("atk", 0.3), morale=20), hit("int", 1.0, "all")]),
}

for p, (n, shout, vfx, eff) in NEW.items():
    assert p not in U["list"], p
    U["list"][p] = OrderedDict(name=n, shout=shout, vfx=vfx, eff=eff)
U["tier6_scale"] = 0.65
U["first"]["6"] = 4
U["_설명"] = U["_설명"].replace("불멸·신화 장수의 고유기.", "초월·불멸·신화 장수의 고유기 (초월은 2026-10-30 부터).").replace(
    "불멸 카드는 mult·heal·morale·amt 를 tier7_scale 배로 쓴다.", "불멸 카드는 mult·heal·morale·amt 를 tier7_scale 배, 초월 카드는 tier6_scale 배로 쓴다.")
open(PATH, "w", encoding="utf-8", newline="\n").write(json.dumps(U, ensure_ascii=False, indent=1) + "\n")
print("고유기", len(U["list"]))
