"""등급별 일러스트 프롬프트 —— 기본 캐릭터를 먼저 정하고, 위 등급은 그 그림을 참조해 점점 꾸민다.

실행: python -I tools/scripts/make_tier_prompts.py  →  prompts/등급별/
  1_기본  모든 장수 90명의 기본 캐릭터(=캐릭터 디자인). 게임에선 고급·희귀·전설 카드가 쓴다 (<인물>.png).
  2_초월  1단계 상위 —— 기본과 같은 사람, 갑옷 · 옷을 한 단계 정교하게 (<인물>_초월.png).
  3_불멸  2단계 상위 —— 화려한 장식, 기병은 말, 배경에 깃발 · 군세 조금 (<인물>_불멸.png).
  4_신화  신화 —— 상징 장면 한 장면의 일러스트 (<인물>_신화.png).
  위 등급 시트는 make_ref_sheet.py 로 만든 '기본 캐릭터 참조 이미지'를 함께 붙여 넣는다 (번호 = 프롬프트 번호).

자료: game.json · cards_ext.json (카드), 대용량 · 원본 md (인물 설명 · LOOK · SCENE), faces.json (얼굴).
"""
import json
import os
import re
from collections import defaultdict

OUT = "prompts/등급별"
TIER_DIR = {6: "2_초월", 7: "3_불멸", 8: "4_신화"}
SUFFIX = {6: "_초월", 7: "_불멸", 8: "_신화"}
PER = {"base": 5, 6: 6, 7: 6, 8: 1}               # 신화는 한 장에 한 명 (10/30 —— 4명을 한 장에 그리면 구도 · 얼굴이 다 같아졌다)              # 한 장 인원 —— 많으면 모델이 인물별 지시를 섞거나 빠뜨린다 (기본 10명 · 초월 12명에서 실패)
GRID = {5: (5, 1), 6: (3, 2), 4: (2, 2), 1: (1, 1)}
FAC_EN = {"촉": "Shu", "위": "Wei", "오": "Wu", "군": "Independent"}
FAC_ORDER = ["촉", "위", "오", "군"]
CLASS_EN = {"창병": "SPEARMAN", "기병": "CAVALRY", "궁병": "ARCHER", "도적": "ROGUE",
            "책사": "STRATEGIST", "유생": "SCHOLAR", "술사": "SORCERER", "모사": "SCHEMER"}
FAC_COLOR = {"촉": "Shu green: green, jade and earthy gold",
             "위": "Wei blue: navy, deep blue and steel with silver",
             "오": "Wu red: crimson, red, orange and gold"}

# 실루엣 —— 얼굴만으로 부족해서 체격 · 키를 따로 못박는다 (없으면 병종 기본값)
BUILD = {
    "허저": "huge and fat, the widest body on any sheet, big round belly", "전위": "giant, towering, ape-like long arms",
    "동탁": "obese, round barrel body, short legs", "관해": "giant brute, thick limbs", "주창": "tall dark-skinned giant, thick arms",
    "장비": "big and burly, barrel chest", "관우": "very tall and dignified, long legs, upright", "조인": "massive and square, like a wall",
    "악진": "small and short, the shortest soldier, oversized helmet", "조조": "short and wiry, but commanding posture",
    "하후돈": "big, broad-shouldered", "황충": "lean old body with sinewy muscular arms", "정보": "tall old man, upright",
    "여포": "tall, long-limbed, heroic proportions", "마초": "slim, lean and sharp, wiry", "조운": "tall, broad-chested and solid",
    "미축": "plump", "노숙": "chubby and round", "원술": "plump, soft belly", "간옹": "slouching, lanky",
    "가후": "hunched old man", "좌자": "thin very old man, slight limp", "화타": "small round old man, energetic",
    "방통": "short, scruffy, slightly hunched", "제갈량": "tall and slender", "사마의": "tall and gaunt, long neck",
    "곽가": "slender and loose-limbed", "정욱": "very tall and thin old man", "등애": "stocky and rugged",
    "여몽": "stocky, thick neck", "주태": "solid, broad, covered in bandages", "감녕": "lean and muscular, tattooed arms",
    "능통": "lean and agile", "장연": "lean and agile", "요화": "thin and wiry", "마충": "thin and sneaky",
    "엄백호": "burly, slightly fat", "위연": "medium height, broad, hunched forward like a wolf", "방덕": "solid and broad",
    "서황": "solid and square", "장료": "lean and hard, tall", "하후연": "lean and long-limbed", "태사자": "tall and athletic",
    "손책": "athletic, broad shoulders", "손권": "broad and sturdy", "유비": "medium height, gentle stance, long arms",
    "장각": "skeletal and gaunt", "초선": "slender woman", "대교": "slender graceful woman", "소교": "petite young woman",
    "하후패": "teenage, short and wiry", "여상": "young, slim", "안량": "big and brutish", "마등": "big, broad old man",
    "원소": "tall and stately", "공손찬": "tall and lean", "황개": "stocky old man, battle-worn", "전풍": "stiff and square",
    "심배": "rigid and thin", "저수": "gaunt", "진궁": "lean and upright", "장소": "thin old man, very upright",
    "사마휘": "thin old hermit, relaxed", "우길": "thin old man, light as a feather", "초주": "thin old man, stooped",
    "오범": "thin old man", "장보": "sturdy", "장량": "wiry", "장로": "medium build, calm", "관로": "short with a big head",
    "강유": "athletic young soldier", "육손": "slim but broad-shouldered", "주유": "tall and graceful", "종회": "slim, chin raised",
    "순욱": "tall and upright", "법정": "thin", "서서": "lean swordsman build", "장합": "slender but broad-shouldered",
    "곽회": "sturdy", "학소": "stocky", "이전": "medium build, soft", "우금": "upright and rigid", "능조": "stocky sailor",
    "서성": "steady medium build", "정봉": "short and tough old man", "마대": "sturdy", "마량": "slim", "이적": "round and small",
    "유엽": "slim young man", "진군": "neat and thin",
}
DEF_BUILD = {"창병": "sturdy soldier build", "기병": "athletic rider build", "궁병": "lean archer build", "도적": "lean agile build",
             "책사": "slim scholar build", "유생": "slim scholar build", "술사": "thin build", "모사": "slim build"}


# 기병은 모든 등급에서 말을 탄다 —— 같은 인물은 같은 말
HORSE = {"여포": "Red Hare, a fiery red-chestnut warhorse with a flame-like mane", "조운": "a pure white horse with a green saddle cloth",
         "공손찬": "a pure white horse (the White Horse General)", "마초": "a black Xiliang warhorse",
         "마등": "a shaggy brown Xiliang steppe horse", "동탁": "a sturdy black horse straining under his weight",
         "원소": "a white horse in gold barding", "장료": "a black warhorse", "손책": "a chestnut horse",
         "마대": "a bay horse", "장합": "a dapple-grey horse", "하후패": "a small bay pony-like horse",
         "곽회": "a shaggy dun frontier horse", "안량": "a big dark brown warhorse"}
# 기병이 아니어도 원전에서 말이 상징인 인물 —— 하후연(三日五百 기병), 방덕(白馬將軍)
HORSE_EXTRA = {"하후연": "a lean fast horse at full gallop"}     # 방덕은 창병이라 말에서 내린다 (10/30 사용자)
MOUNT = {"base": "MOUNTED: riding %s —— a small chubby chibi horse, rider AND whole horse visible from ears to hooves, both standing on the blot.",
         6: "MOUNTED: riding %s —— rider waist-up, the horse's armored head, neck and mane in front of him.",
         7: "MOUNTED: riding %s —— rider and horse together in the scene, the horse charging or rearing.",
         8: "MOUNTED: the rider's face and upper body are the subject —— the armored horse only as a glimpse of head, neck or mane at the panel edge (%s)."}


def mount(x, key):
    if x["cls"] != "CAVALRY" and x["p"] not in HORSE_EXTRA:
        return []
    return ["   " + MOUNT[key] % (HORSE.get(x["p"]) or HORSE_EXTRA.get(x["p"]) or "a warhorse")]


def load_cards():
    d = json.load(open("solgukji_godot/data/game.json", encoding="utf-8"))
    e = json.load(open("solgukji_godot/data/cards_ext.json", encoding="utf-8"))
    return [c for c in d["CARDDEF"] + e["cards"] if c[2] >= 3]


def load_entries():
    """카드 이름 → {desc, LOOK, SCENE, ...}. 대용량 md 를 먼저, 없으면 원본 md."""
    ent = {}
    srcs = [("prompts/삼국지_일러스트_프롬프트_대용량.md", r"^\d+\. \(card: ([^)]*)\) (.*)\n((?:   .*\n)+)"),
            ("prompts/삼국지_일러스트_프롬프트.md", r'^\d+\. "([^"]+)" — (.*)\n((?:   .*\n)+)')]
    for fn, pat in srcs:
        for title, desc, body in re.findall(pat, open(fn, encoding="utf-8").read(), flags=re.M):
            if title in ent:
                continue
            f = {"desc": re.sub(r"^\[[A-Z]+\] ", "", desc).strip()}
            for ln in body.split("\n"):
                k, _, v = ln.strip().partition(": ")
                if k.isupper() and v:
                    f[k] = v
            ent[title] = f
    return ent


cards = load_cards()
ent = load_entries()
faces = json.load(open("prompts/faces.json", encoding="utf-8"))
SIG = json.load(open("prompts/signatures.json", encoding="utf-8"))
# md 의 LOOK · 설명을 덮어쓴다 —— 다른 인물과 겹치거나(장료 · 하후연 쌍둥이) 원전과 어긋나는 것 (prompts/장수_고증_조사.md 1 · 2장)
LOOK_FIX = {
    "장료": "40s, grim veteran cavalry commander, dark steel helmet with cheek guards and a tall purple-black plume, square-cut short black beard, scar across the left cheek.",
    "하후연": "40s, lean wild archer-rider, NO helmet, shaggy shoulder-length hair under a blue cloth headband, long thin drooping mustache and goatee, gaunt cheeks, huge grin.",
    "위연": "40s, deep date-red face, glaring star-like eyes, thin twisted mustache, bare chin, iron demon mask pushed up on his head, bony bump at the BACK of the head, sneer.",
    "화타": "very old but with a youthful glowing face, short white beard, square cloth cap.",
    "유비": "30s, earlobes reaching his shoulders, very long arms, kind gentle eyes, clean-shaven or a faint thin mustache, simple topknot crown.",
    "방통": "plain ugly face, upturned snub nose, thick brows, dark swarthy face, short scruffy beard, messy hair.",
    "조운": "late 20s, broad face with a full heavy jaw, thick brows, large calm eyes, clean-shaven, NO helmet, neat topknot with a white-and-green headband, gentle confident smile.",
    "마초": "early 20s young man, narrow jade-white face, fierce slanted shooting-star eyes, thin sharp mustache, scowl, silver lion-head helmet with a tall white plume.",
    "태사자": "30s, long tied-back hair, strong jaw, long handsome beard, long ape-like arms.",
    "방덕": "40s, hard square jaw, full black beard, thick eyebrows, fierce unblinking eyes.",
    "등애": "about 66, old rugged face, grey-white rough stubble, deep wrinkles, windburned cheeks.",
    "우길": "very old, white topknot, long flowing white beard, gentle smile.",
    "안량": "40s, broad fierce face, thick single unibrow, thick full black beard, gold-crested helmet.",
    "주창": "tall giant, near-black skin, wild curly hair, huge curly black beard down to his chest, very muscular, honest loyal face.",
    "조인": "square face with a broad greying beard, heavy round helmet with the visor raised.",
    "하후돈": "black eyepatch, wild long black hair, short thick black beard.",
    "학소": "40s, heavy battered full helmet, stern square face, thick black mustache only.",
    "종회": "young man, sharp arrogant face, clean-shaven, high topknot in a gold hair crown.",
    "악진": "small and short, faint stubble, big determined eyes, oversized plumed helmet.",
    "하후패": "late teens, short spiky hair, no beard, eager wide eyes.",
    "능조": "sun-tanned sailor, high topknot with a sea-blue bandana, short grizzled beard.",
    "육손": "youthful man, red scholar's cap, very faint mustache line.",
    "장량": "younger, clean-shaven, smirking, iron helmet wrapped in yellow cloth.",
}
DESC_FIX = {
    "장료": [("long hair tied back, blue-purple armor", "helmeted, blue-purple armor")],
    "위연": [("bold glaring face with a prominent bony forehead", "deep date-red face, star-like eyes, an iron demon mask pushed up on his head"), ("swinging a big broad-bladed glaive", "swinging a huge two-handed broad-bladed saber")],
    "화타": [("medicine box on his back", "a blue cloth medicine bag hanging on his arm")],
    "태사자": [("a short halberd in each hand (his famous twin halberds)", "a short halberd in one hand and Sun Ce's captured helmet in the other")],
    "우길": [("horsetail whisk raised, a gourd on his belt", "crane-feather cloak, goosefoot staff raised"), ("horsetail whisk raised, gourd on his belt", "crane-feather cloak, goosefoot staff raised")],
    "안량": [("fierce general in gold-and-brown armor.", "fierce general in an embroidered robe over gold armor, with a big blade.")],
    "주창": [("crouching with a heavy curved saber", "holding Guan Yu's Green Dragon glaive upright for his lord")],
    "정보": [("holding a longbow with an arrow nocked, quiver on back", "holding a snake-headed serpent spear, bow and quiver on his back")],
    "서성": [("aiming a longbow, quiver on back", "holding a long glaive, bow and quiver on his back")],
    "육손": [("white feather fan in hand", "twin swords in hand")],
    "대교": [("red-pink hanfu dress", "blue-teal hanfu dress, folding fan")],
    "장량": [("a fan of glowing paper talismans spread in his hand", "yellow-trimmed armor, spear and a yellow war banner, a few talismans tied to the spear")],
    "장각": [("staff raised", "nine-knot staff raised")],
}


def fix_desc(p, d):
    for a, b in DESC_FIX.get(p, []):
        d = d.replace(a, b)
    return d


person_cards = defaultdict(list)
for c in cards:
    person_cards[c[1].split(" ")[-1]].append(c)
for p in person_cards:
    person_cards[p].sort(key=lambda c: c[2])


def person_info(p):
    cs = person_cards[p]
    src = next(ent[c[1]] for c in cs if c[1] in ent)        # 가장 낮은 등급 설명 = 기본 디자인
    desc = fix_desc(p, src["desc"])
    iconic = desc.startswith("★ICONIC")
    desc = desc.replace("★ICONIC ", "")
    en = desc.split(",")[0].replace('the classic ', "")
    fac = cs[0][4]
    if fac == "군":
        color = "his own colors as described (independent)" if "hermit" not in src.get("FACTION", "") else "white, pale blue and silver (hermit)"
    else:
        color = FAC_COLOR[fac]
    if p in ("초선", "대교", "소교"):
        color = color.replace("his own", "her own")
    return {"p": p, "en": en, "desc": desc, "iconic": iconic, "fac": fac, "cls": CLASS_EN[cs[0][3]],
            "look": LOOK_FIX.get(p, src.get("LOOK", "")), "face": faces.get(p, ""), "build": BUILD.get(p) or DEF_BUILD[cs[0][3]],
            "color": color}


INFO = {p: person_info(p) for p in person_cards}

# 기본 그림 다시 그리기 (2026-10-30 사용자 수정 요청) —— INFO · SIG 를 덮어쓴다. 1_기본 프롬프트에도 같이 들어간다.
YUAN = "Yuan clan army colors: yellow and gold robes or armor with dark brown trims (the Yuan banner color)"
REDO = {
    "감녕": dict(desc="Gan Ning, fearsome river PIRATE captain of the Brocade Sails, bare muscular tattooed arms, red brocade sash, a broad curved pirate saber in one hand and a coiled rope with an iron grappling hook over his shoulder, brass bells on his belt",
               look="30s, menacing pirate chief, NO feathers, scar across the brow, scary glare.",
               face="lean hard face, fierce glaring narrowed eyes under a heavy scarred brow, broken flat nose, sun-tanned skin, tattooed neck, bared-teeth snarl, menacing and scary, NOT playful",
               sig=["red brocade pirate bandana knotted at the back with long tails", "rough short stubble", "grappling hook rope, brass bells on his belt, tattoos"]),
    "강유": dict(desc="Jiang Wei, young strategist-general in green armor with a WHITE cloth hood over his head, a spear in one hand and a rolled military map in the other, thoughtful sharp eyes",
               look="young man in his 20s, intelligent determined face, white hood over green armor.",
               sig=["white cloth hood", "short sideburns and a faint chin stubble", "green armor, spear and a rolled military map"]),
    "곽가": dict(desc="Guo Jia, very young brilliant strategist who died young, slender and pale in a loose blue-grey robe, holding a SHORT CALLIGRAPHY BRUSH (no fan), a wine gourd at his hip",
               look="early 20s, smooth youthful face, clean-shaven.",
               face="slender pale young MAN in his early 20s, smooth CLEAN-SHAVEN face (no beard, no stubble), angular sharp jaw, flushed sickly cheeks, sleepy half-lidded smug eyes, thin nose, crooked playful smirk, loose messy hair",
               sig=["no hat, loose untied hair", "clean-shaven, no beard at all", "short calligraphy brush in hand, wine gourd, flushed cheeks"]),
    "방덕": dict(desc="Pang De, grim loyal SPEARMAN standing ON FOOT (no horse), dark iron armor, a BLUE cloth headscarf, a long spear held UPRIGHT in one hand, and a SMALL wooden coffin standing on end right behind his back, pulled on a short rope over his shoulder (he brought his own coffin to battle). Keep him and the coffin COMPACT inside his own slot: the coffin is no wider than his body and does not stick out to the sides",
               sig=["blue cloth headscarf (no helmet)", "full black beard", "small upright wooden coffin on a short rope behind his back, upright long spear"]),
    "사마의": dict(desc="Sima Yi, the cold supreme schemer who came to rule Wei: deep blue robes with a WHITE CLOAK over his shoulders, ARMS FOLDED across his chest, chin raised, looking down with absolute authority",
                look="50s, imposing tall figure, long thin beard, aura of the most powerful man in the realm.",
                face="long gaunt face, sunken cheeks, narrow wolf-like eyes looking down coldly, long thin nose, thin lips in a faint cunning smile, pale skin, overwhelming quiet authority",
                sig=["tall black official crown", "long thin beard", "white cloak over deep blue robes, arms folded"]),
    "심배": dict(color=YUAN, desc="Shen Pei, stubborn hot-tempered official of Yuan Shao in a YELLOW-GOLD high-collared robe, gripping a sealed order scroll in a fist, glaring",
               look="60s, stocky old man, bald crown with a grey topknot, short bristly grey goatee, bulging glaring eyes.",
               face="broad ruddy square face, thick bushy GREY eyebrows, big round BULGING glaring eyes (not narrow), wide flat nose, short bristly grey goatee only (no long beard), deep frown lines, stubborn clenched jaw",
               build="short and stocky, barrel-shaped",
               sig=["bald crown with a small grey topknot tied in a yellow cloth (no hat)", "short bristly grey goatee", "high collar, sealed scroll gripped in a fist"]),
    "안량": dict(color=YUAN),
    "우금": dict(desc="Yu Jin, strict disciplinarian general with long UNBOUND messy hair falling loose, a BLUE cape, plain iron armor, a war banner pole on his back",
               sig=["no cap, long loose disheveled hair", "neat pencil mustache only", "blue cape, war banner pole on his back"]),
    "육손": dict(desc="Lu Xun, young grand commander of Wu in a general's red-and-dark lamellar ARMOR, holding ONE straight commander's sword raised to direct the troops (a single sword, not two)",
               sig=["red scholar's cap", "very faint mustache line", "general's armor, ONE commander's sword raised"]),
    "장합": dict(desc="Zhang He, elegant cavalry general whose ARMOR IS SPLIT IN TWO COLORS: the left half YELLOW (his old lord Yuan Shao) and the right half BLUE (his new lord Cao Cao), helmet split yellow and blue the same way, holding a LONG SPEAR",
               look="elegant handsome man, refined long face, thin neat mustache.",
               sig=["helmet split half yellow and half blue", "thin neat mustache", "armor split yellow and blue, long spear"],
               color="split in two: left half yellow-gold (Yuan Shao), right half Wei blue (Cao Cao)"),
    "조인": dict(desc="Cao Ren, master of holding a fortress: CROUCHED in a guarding stance BEHIND a huge tower shield AS TALL AS A MAN, braced against it, only his helmeted head and fierce eyes showing over the top",
               sig=["heavy round helmet with the visor raised", "broad greying beard", "man-tall tower shield, crouched guarding stance"]),
    "하후돈": dict(look="black eyepatch, NEATLY tied hair in a tidy topknot, short thick black beard.",
                desc="Xiahou Dun, fierce one-eyed general in dark blue armor, hair neatly tied in a tidy topknot, holding a heavy SINGLE-EDGED blade (one cutting edge only, like a heavy dao)",
                sig=["neat tidy topknot", "short thick black beard", "black eyepatch over the LEFT eye, single-edged heavy blade"]),
    "저수": dict(color=YUAN, desc="Ju Shou, loyal worried strategist of Yuan Shao in a plain yellow-brown robe, hunched forward, clutching a secret plan scroll to his chest",
               face="thin pale face, worried knitted brow, droopy sad eyes with dark bags, small sparse moustache and a thin wispy chin beard, anxious open mouth",
               build="thin and hunched", look="50s, thin worried man, wispy little beard.", sig=["small soft black scholar cap", "sparse wispy moustache and thin chin beard", "secret plan scroll hugged to his chest, hunched worry"]),
    "전풍": dict(color=YUAN, desc="Tian Feng, blunt fearless advisor of Yuan Shao in a stiff yellow-gold robe, standing square and pointing at a written memorial while scolding",
               face="broad square face, thick black frowning eyebrows, wide fierce eyes, broad nose, thick black square-cut beard, open scolding mouth",
               build="tall, stiff and square-shouldered", look="40s, stern square-faced man, thick square black beard.", sig=["square black official hat with flaps", "thick black square-cut beard", "pointing finger and a written memorial"]),
    "진궁": dict(desc="Chen Gong, defiant strategist of Lü Bu captured at White Gate Tower: crimson-and-black robe, a plain black headscarf, a straight sword at his hip, a CUT ROPE still tied around one wrist, chin raised in proud defiance",
               look="40s, lean proud face, neat long black beard, piercing stare, unbowed even as a captive.",
               face="lean long face, prominent cheekbones, piercing defiant eyes, straight nose, thin firm lips, pale stern skin, proud raised chin",
               sig=["plain black headscarf", "neat long black beard", "cut rope tied around one wrist, sword at the hip, crimson-black robe"],
               color="crimson red and black"),
}
for _p, _o in REDO.items():
    for _k in ("desc", "look", "face", "color", "build"):
        if _k in _o:
            INFO[_p][_k] = _o[_k]
    if "sig" in _o:
        SIG[_p] = _o["sig"]

DISTINCT = """EVERY CHARACTER LOOKS DIFFERENT: on one sheet no two characters share the same headgear, hairstyle or facial hair ——
follow each SIGNATURE line exactly (HEAD, FACIAL HAIR, MARK). Same faction colors must never make them look like twins: vary
the armor shape, helmet, cape and silhouette. Only characters with a MOUNTED line ride a horse; everyone else is ON FOOT.
STRATEGISTS AND OFFICIALS ESPECIALLY: never default to "narrow slit eyes + long thin beard + tall black official hat" —— follow each FACE
and SIGNATURE exactly; their eye shapes (round, droopy, bulging, narrow), beards (none, stubble, goatee, short, long) and headwear must differ.
"""
GENDER = DISTINCT + """GENDER: every character is an adult MAN, except the women Diaochan, Da Qiao and Xiao Qiao. Men read as men at a glance ——
masculine jaw and brow, thicker neck, broad shoulders, male hairstyles and headwear. Young men are young MEN, never girls:
no long eyelashes, no blush, no rosy lips, no soft baby face."""

LAYOUT = """LAYOUT:
- Image {size}. ALWAYS a fixed grid of {cols} columns x {rows} rows = {slots} equal slots, reading order left to right, top to bottom.
- Natural proportions in every slot: never stretch, squash or shorten a character to fit the slot; leave empty background instead.
- Characters 1 to {n} fill the first {n} slots in order.{empty}
- Flat light green paper background (#9BCF88) over the whole sheet. Wide even gaps between panels; nothing crosses into a neighbor.
- Under each panel a dark green brush-stroke banner with ONLY its number (1 to {n}) in big white digits.
- No other text anywhere: no names, no titles, no captions, no signature, no watermark. Do not draw the line labels as text."""

# ── 기본: 그림 1 (작은 SD 전신, 단순) ──
BASE_COMMON = """A character design sheet of {n} Three Kingdoms (late Han dynasty China) generals for a mobile card game.
These are the BASE designs: every later, fancier version of each character will be copied from this sheet, so each
character must be clear, simple and instantly recognizable.

STYLE:
- Cute SD chibi, about 2.5 heads tall: big head, small body, short limbs, FULL BODY from head to feet, standing on the ground.
- Clean dark-brown ink outlines, flat soft colors with simple two-tone cel shading, light paper texture. Gentle and readable,
  like a hand-drawn sticker. Not glossy, not painterly, not detailed.
- Small calm-to-lively poses: standing, holding the signature weapon or item, a slight turn or a small gesture.
- Each character stands on a soft round blot of darker green watercolor (its panel), slightly bigger than the character.
  The blot is the only background: no scenery, no ground details, no props besides the character's own items.
- CAVALRY characters are ALWAYS on horseback (see MOUNTED), never standing on foot. Their panel may be a little wider.

OUTFIT LEVEL (BASE): plain practical clothes and simple armor in the character's colors —— cloth, leather, dull iron,
simple trims, no gold ornaments, no capes (unless the character's own DESIGN names a cape or cloak), no glowing effects. Iconic features (beards, eyepatch, headbands, signature
weapons, hats) are ALREADY present here, because later versions must keep them.

FACES AND SILHOUETTES MUST ALL DIFFER:
- Draw FACE exactly and exaggerate it a little, like a caricature: face shape, eyes, brows, nose, mouth, facial hair, age.
- Follow BUILD: heights and body shapes really differ (giant, fat, tiny, hunched, slender). Ages really differ (smooth young
  vs. wrinkled old). Not everyone is handsome. No same-face syndrome, no generic cute face.
- The signature weapon or item and the hairstyle/headwear make each silhouette unique even as a black shape.
{gender}

{layout}

CHARACTERS
"""

# 10/30 사용자: 초월 · 불멸도 고티어인데 평범했다 —— 한 칸씩 올린다. 초월 = 예전 불멸, 불멸 = 예전 신화, 신화 = 더 화려한 새 단계
TIER_COMMON = {
    6: """The SAME {n} Three Kingdoms generals as numbered in the attached reference image, redrawn as splendid high-rank
card art (TRANSCENDENT rank) for a mobile card game.

REFERENCE (attached image): character #k in the reference = panel #k here. Keep each identity EXACTLY: the same face, eye
shape, brows, facial hair, hairstyle and headwear, skin tone, age, body build, main colors and signature weapon or item.
The outfit becomes grander, but the person is unmistakably the same.

STYLE:
- Rich detailed chibi, about 3 to 3.5 heads tall, WAIST-UP or chest-up, large and close in the panel, slightly low angle.
- Fine ink lines, deep shading with strong highlights, lavish material detail: gilded lamellar, embossed dragon/tiger/
  phoenix motifs, fur collars, jeweled clasps, silk capes and sashes, tall plumes and crests.
- CAVALRY are ALWAYS on horseback (see MOUNTED), never on foot: the rider is the subject, with the horse's armored head, neck and mane in the lower part.
  Others hold their signature weapon or item in a strong, characterful pose.
- Panel background: a vertical rounded rectangle, a soft painted field with a few hints of the setting behind the character
  —— a faction banner, distant soldiers' silhouettes, smoke, mist or sparks —— kept soft and low-detail so the character pops.

OUTFIT LEVEL (TRANSCENDENT): ornate —— gold trims and engraved gilded plates, rich brocade, fur, jewels, capes and plumes,
far more splendid than the base design, while keeping the character's main colors and signature items.
{gender}

{layout}

CHARACTERS
""",
    7: """The SAME {n} Three Kingdoms generals as numbered in the attached reference image, painted as IMMORTAL-rank
card illustrations for a mobile card game —— top-tier art, each one a small famous scene.

REFERENCE (attached image): character #k in the reference = panel #k here. Keep each identity EXACTLY: the same face, eye
shape, brows, facial hair, hairstyle and headwear, skin tone, age, body build, main colors and signature weapon or item.
Even in the grandest scene the person is unmistakably the same.

STYLE:
- Polished anime game illustration with slightly chibi proportions (about 4 heads tall), large expressive face, dynamic
  pose, WAIST-UP to three-quarter body, the character large and in front, a little foreshortening.
- Dense fine linework, dramatic lighting with strong rim light, vivid saturated colors, glowing particles and energy.
- Each panel is ONE full illustration of the character's MOMENT (their most famous scene): a painted background inside
  the panel —— battlefield, river, palace, burning sky, banners with the faction character —— plus ONE legendary effect
  (lightning, flames, a roaring spirit animal, a dragon of mist, swirling petals, golden light) wrapping around them.
- CAVALRY are ALWAYS on horseback (see MOUNTED), never on foot, rider as the clear subject.

OUTFIT LEVEL (IMMORTAL): a very splendid version —— gilded armor or imperial silk covered in dragon, phoenix or tiger
motifs, luminous gold details, flowing capes and ribbons, a faint golden glow, while keeping main colors and signature items.
{gender}

{layout}

CHARACTERS
""",
    8: """ONE MYTHIC card illustration of a single Three Kingdoms general for a mobile card game —— the rarest, most
intimidating art in the game. One look at the card should make the viewer feel this person is about to KILL THEM right now.

REFERENCE (attached image): the general shown in the reference is THIS person. Keep the identity EXACTLY: the same face,
eye shape, brows, facial hair, hairstyle and headwear, skin tone, age, body build, main colors and signature weapon or item.
Do not turn them into a generic handsome warrior —— the face must clearly be the reference face, only realistic and terrifying.

IDENTITY FIRST: a fan must name this general at a glance from the face, headwear, facial hair, outfit colors and weapon.
Everything in the MUST SHOW line has to be clearly visible and well lit. Their own outfit colors stay true and readable ——
never tint the whole picture one color, never let light or effects wash out the face or the costume.

FRAMING —— THIS IS THE MOST IMPORTANT PART:
- CLOSE and IMPACTFUL: the face and upper body dominate the panel (from an extreme face close-up to at most waist-up),
  shoulders, weapons and hair may run off the panel edges.
- Follow the COMPOSITION line exactly (camera angle, head direction, crop, weapon placement) and the LIGHT line exactly
  (color of the light and the background). These differ for every general, so the cards in the game never look alike.
- The threat is aimed at the VIEWER: the eyes meet the camera (even from a profile or over the shoulder). Follow the
  EXPRESSION line —— each general is dangerous in their OWN way (a roar, a sly smile, cold contempt, serene certainty,
  drunken madness, a seductive smile), never the same generic angry face.

STYLE:
- Premium anime card illustration, realistic-leaning proportions (not chibi), very sharp detailed face: intense eyes with
  a sharp catchlight, deep shadows under the brow, sweat, battle grime, scars and blood specks where they fit.
- LIGHTING: clear and natural on the character —— the face evenly lit with true skin tone, readable details, a soft rim
  light only to separate them from the background. No blinding glow, no heavy colored light on the face, no lens flare.
- BACKGROUND: the setting of the SCENE line, painted softly and slightly out of focus behind them so each card has its own
  place and color (a palace, a river fleet, a mountain path, a burning camp ...). It must not be brighter than the face.
  Do NOT add guardian beasts or giant spirit animals.
- A thin ornate dark-gold card frame around the edge of the image.

OUTFIT LEVEL (MYTHIC): the most splendid version of their gear, seen close up —— heavy gilded and engraved armor, worn and
battle-scarred, rich silk and fur at the collar, while keeping the character's main colors and signature items.
{gender}

{layout}

CHARACTERS
""",
}


def sig(x):
    h, f, m = SIG[x["p"]]
    return "   SIGNATURE (unique to him on this sheet): HEAD %s; FACIAL HAIR %s; MARK %s." % (h, f, m) if f != "-" else         "   SIGNATURE (unique to her on this sheet): HAIR %s; MARK %s." % (h, m)


def base_entry(i, x):
    lines = ["%d. %s  [%s, %s]%s" % (i, x["en"], x["cls"], FAC_EN[x["fac"]], "  ★ICONIC: draw the famous traditional look exactly" if x["iconic"] else ""),
             "   DESIGN: " + x["desc"],
             "   LOOK: " + x["look"],
             "   FACE: " + x["face"] + ".",
             "   BUILD: " + x["build"] + ".",
             sig(x),
             "   COLORS: " + x["color"] + "."] + mount(x, "base")
    return "\n".join(lines)


def tier_entry(i, x, card, tier):
    e = ent.get(card[1], {})
    lines = ["%d. %s  [%s, %s] —— same person as reference #%d" % (i, x["en"], x["cls"], FAC_EN[x["fac"]], i),
             "   IDENTITY: " + x["look"] + " FACE: " + x["face"] + ". BUILD: " + x["build"] + ".",
             sig(x),
             "   COLORS: " + x["color"] + "."] + mount(x, tier)
    d = fix_desc(x["p"], e.get("desc", "")).replace("★ICONIC ", "")
    if d and d != x["desc"]:
        lines.append("   THIS RANK'S LOOK: " + d)
    scene = e.get("SCENE", "")
    if tier == 6 and scene:
        lines.append("   POSE AND SOFT BACKGROUND HINT: " + scene)
    elif tier == 7 and scene:
        lines.append("   MOMENT (paint this scene): " + scene)
    elif tier == 8 and scene:
        lines.append("   SCENE (paint this setting softly behind them, the character in front and naturally lit, no guardian beasts): " + scene)
    if tier == 8:
        lines.append("   COMPOSITION: " + COMP.get(x["p"], COMPS[0]) + ".")
        if x["p"] in LIGHT:
            lines.append("   BACKGROUND COLOR: " + LIGHT[x["p"]] + " (only behind them, the character stays naturally lit).")
        lines.append("   EXPRESSION: " + EXPR.get(x["p"], "a cold murderous glare straight at the viewer") + ".")
        h, f, m = SIG[x["p"]]
        lines.append("   MUST SHOW (clearly, large and well lit): %s; %s; %s." % (h, f if f != "-" else "her face", m))
    return "\n".join(lines)


# 신화 구도 —— 한 장 안에서 겹치지 않게 돌려 쓴다. 인물에 맞는 구도가 있으면 그것부터 (10/30 사용자: 구도가 다 똑같다)
COMPS = [
    "extreme close-up of the face filling the panel, cut off at the chin and forehead, eyes burning straight into the viewer, the weapon's edge slicing diagonally across the lower corner",
    "three-quarter view, LOW angle from below, looming over the viewer, chin raised, looking down with contempt, the weapon resting on the shoulder",
    "PROFILE turned to the side, the head snapping toward the viewer so only the eyes look into the camera, weapon held upright beside the face",
    "seen from BEHIND over the shoulder, turning back to glare at the viewer, the back armor and cape in the foreground",
    "HIGH angle, leaning forward toward the camera as if about to lunge, face very close and slightly distorted by the wide lens",
    "the weapon's point thrust straight AT the viewer in sharp perspective, the face behind it, half in focus, between the blade and the frame",
    "mid-ROAR, mouth wide open shouting, hair and cloth whipped back by wind, a tilted (dutch) angle, sparks flying past the face",
    "face HALF IN SHADOW, only one eye and half the mouth lit by firelight, a dead-calm cruel smile, everything else sinking into darkness",
    "mid-SWING, the weapon blurred in a wide arc across the panel, the body twisted, the eyes locked on the viewer through the motion",
    "waist-up, arms crossed or one hand raised in a command, standing still and enormous, the quiet before killing, the camera slightly below",
]
COMP_PREF = {"장비": 6, "여포": 8, "관우": 1, "조운": 5, "마초": 8, "황충": 5, "하후돈": 0, "하후연": 5, "태사자": 5,
             "제갈량": 7, "사마의": 3, "조조": 9, "주유": 2, "육손": 2, "초선": 7, "곽가": 7, "가후": 7, "장료": 4, "허저": 6,
             "전위": 1, "손책": 6, "감녕": 4, "여몽": 3, "유비": 9, "손권": 9, "동탁": 1, "원소": 9, "장각": 6, "화타": 2,
             "좌자": 3, "진궁": 0, "사마휘": 7, "순욱": 2, "위연": 0, "강유": 5, "법정": 7, "노숙": 9}
COMP = {}


def assign_comps(names):
    used = set()
    for p in names:
        c = COMP_PREF.get(p)
        if c is None or c in used:
            c = next(k for k in range(len(COMPS)) if k not in used)
        used.add(c)
        COMP[p] = COMPS[c]


LIGHTS = [
    "background in a red sunset haze",
    "background in blue night rain",
    "background under grey storm clouds",
    "background in a lantern-lit palace hall",
    "background with a burning camp far behind",
    "background in violet dusk mist",
    "background in cold misty dawn",
    "background in warm incense smoke",
    "background in a dark green forest gloom",
    "background in a dusty yellow battlefield haze",
]
LIGHT_PREF = {"관우": 3, "장비": 2, "조운": 1, "제갈량": 5, "주유": 4, "육손": 4, "조조": 7, "사마의": 6, "여포": 9, "초선": 5,
              "화타": 7, "장각": 2, "가후": 8, "곽가": 5, "손권": 1, "유비": 7, "황충": 0, "하후돈": 9, "장료": 6, "손책": 0}


def assign_solo(names):  # noqa
    """한 명씩 그리는 신화 —— 인물에 맞는 구도 · 조명부터, 없으면 가장 덜 쓴 것"""
    cu, lu = [0] * len(COMPS), [0] * len(LIGHTS)
    for p in names:
        c = COMP_PREF.get(p)
        if c is None or cu[c] >= 3:
            c = min(range(len(COMPS)), key=lambda k: cu[k])
        lt = LIGHT_PREF.get(p)
        if lt is None or lu[lt] >= 3:
            lt = min(range(len(LIGHTS)), key=lambda k: lu[k])
        cu[c] += 1
        lu[lt] += 1
        COMP[p] = COMPS[c]
        LIGHT[p] = LIGHTS[lt]


LIGHT = {}
# 신화 표정 —— 장수마다 다른 위협 (10/30 사용자: 다 비슷하다)
EXPR = {
    "순욱": "serene, perfectly composed noble calm, eyes half-lidded in quiet judgment —— elegance that is somehow frightening",
    "조조": "a sly knowing smirk, one brow raised, eyes that read your every thought —— the hero of chaos amused by you",
    "손권": "cold calm authority, chin slightly raised, the striking green-blue eyes fixed on you without blinking",
    "손책": "a wild fierce grin full of teeth, eager to charge, youthful reckless fury",
    "태사자": "grim honorable resolve, jaw set, the look of a man who keeps his word even unto death",
    "감녕": "a savage pirate snarl, teeth bared, eyes wide with bloodlust",
    "여몽": "a quiet scholar's stare that suddenly turns deadly, a faint cold smile",
    "육손": "young calm cold calculation, the look of a commander who has already won",
    "주유": "elegant proud disdain, a faint cool smile, a beautiful but merciless gaze",
    "동탁": "a gluttonous tyrant's cruel leer, heavy-lidded eyes, a greedy grin",
    "여포": "arrogant savage pride, a predator's grin, utterly fearless",
    "사마휘": "a gentle old sage's mysterious smile, eyes that see through everything",
    "장각": "a feverish zealot's wide-eyed glare, chanting, possessed by heaven's mandate",
    "좌자": "an eerie playful smirk of a wizard, the blind milky eye glowing faintly",
    "화타": "stern focused intensity of a master physician, calm but unyielding",
    "진궁": "unbowed defiance, chin raised, contempt for death",
    "초선": "a seductive dangerous smile behind the fan, eyes that charm and kill",
    "관우": "majestic cold dignity, narrowed phoenix eyes, utterly silent menace",
    "장비": "a thundering roar, eyes bulging, veins standing out",
    "조운": "calm fearless focus, quietly confident, a hero's steady gaze",
    "제갈량": "serene, all-knowing, a faint smile —— the calm of someone who planned your death long ago",
    "유비": "sorrowful righteous resolve, tears held back, a gaze that commands loyalty",
}


def split(items, per):
    """앞에서부터 per 명씩 꽉 채운다 —— 모자라는 마지막 장은 빈칸을 남긴다 (칸 수를 줄이면 비율이 깨진다)."""
    return [items[i:i + per] for i in range(0, len(items), per)]


SOLO_LAYOUT = """LAYOUT:
- Image 1024x1536 portrait. ONE single card illustration filling the whole image inside the card frame.
- No text anywhere: no name, no title, no number, no banner, no caption, no signature, no watermark."""


def layout(n, per, portrait):
    cols, rows = GRID[per]
    size = "1024x1536 portrait" if portrait else "1536x1024 landscape"
    slots = cols * rows
    empty = "" if n == slots else (
        "\n- The last %d slot%s (%s) stay EMPTY: plain background only, no character, no panel, no banner, no number.\n"
        "  Do not enlarge, stretch or re-space the characters to fill the space —— every slot keeps the same size as on a full sheet."
        % (slots - n, "s" if slots - n > 1 else "", ", ".join(str(k) for k in range(n + 1, slots + 1))))
    return LAYOUT.format(size=size, n=n, cols=cols, rows=rows, slots=slots, empty=empty)


def reset(d):
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        os.remove(os.path.join(d, f))


def write_sheets(key, folder, groups, label, start=0):
    """groups: [(faction, [(person, card)])]. start > 0 이면 폴더를 비우지 않고 start 번부터 새 시트만 더한다 (이미 쓴 시트 프롬프트는 그대로)"""
    dst = os.path.join(OUT, folder)
    if start == 0:
        reset(dst)
    per = PER[key]
    howto = ["%s —— 이름 순서 = 이름표 번호 순서. 시트는 references/등급별_시트/%s/<txt 와 같은 이름>.png 로 두고 D:\\Sol 에서" % (label, folder),
             "  python -I tools/scripts/slice_tier.py %s   → 잘림/ · 미리보기/ 확인 →   python -I tools/scripts/slice_tier.py %s --apply" % (folder, folder),
             "  다 넣으면 solgukji_godot 에서 Godot --import 한 번. (한 장씩 자를 때는 아래 명령)"]
    if key != "base":
        howto.append("위 등급은 먼저 참조 이미지를 만들어 프롬프트와 함께 붙여 넣는다 (1_기본 을 다 자른 뒤에).")
    howto.append("")
    no, sizes = max(0, start - 1), []
    # 세력 순서대로 이어 붙여 꽉 채운다 —— 세력 경계에서 끊으면 1~2명짜리 시트가 생긴다
    allp = [pc for _, items in groups for pc in items]
    if key == 8 and per == 1:
        assign_solo([p for p, _ in allp])
    for chunk in split(allp, per):
        fac = "_".join(dict.fromkeys(c[4] for _, c in chunk))
        no += 1
        n = len(chunk)
        if key == "base":
            text = BASE_COMMON.format(n=n, gender=GENDER, layout=layout(n, per, False))
            text += "\n".join(base_entry(j + 1, INFO[p]) for j, (p, _) in enumerate(chunk)) + "\n"
        else:
            if key == 8 and per > 1:
                assign_comps([p for p, _ in chunk])
            text = TIER_COMMON[key].format(n=n, gender=GENDER, layout=SOLO_LAYOUT if per == 1 else layout(n, per, True))
            text += "\n".join(tier_entry(j + 1, INFO[p], c, key) for j, (p, c) in enumerate(chunk)) + "\n"
        fname = ("%02d_%s.txt" % (no, chunk[0][0])) if per == 1 else ("%02d_%s_%d명.txt" % (no, fac, n))
        open(os.path.join(dst, fname), "w", encoding="utf-8", newline="\n").write(text)
        sizes.append(len(text))
        suf = SUFFIX.get(key, "")
        names = ",".join(p + suf for p, _ in chunk)
        howto.append("[%s]  %s" % (fname, " · ".join("%d %s" % (j + 1, c[1]) for j, (p, c) in enumerate(chunk))))
        if key != "base":
            howto.append('  참조:   python -I tools/scripts/make_ref_sheet.py "%s" %s/참조_%02d.png' % (",".join(p for p, _ in chunk), dst.replace("\\", "/"), no))
        tool = "slice_sheet.py" if key == "base" else "slice_panels.py"     # 기본은 인물만 오려 내고, 위 등급은 패널째
        howto.append('  자르기: python -I tools/scripts/%s 시트.png "%s" solgukji_godot/assets/portraits' % (tool, names))
        howto.append("")
    hp = os.path.join(dst, "자르기_이름.txt")
    if start > 0 and os.path.exists(hp):
        old = open(hp, encoding="utf-8").read()
        blocks = "\n".join(howto[howto.index("") + 1:]).split("\n\n")
        new = [b for b in blocks if b.strip() and b.split("]")[0] + "]" not in old]
        if new:
            open(hp, "w", encoding="utf-8", newline="\n").write(old.rstrip("\n") + "\n\n" + "\n\n".join(new).strip("\n") + "\n")
    else:
        open(hp, "w", encoding="utf-8", newline="\n").write("\n".join(howto))
    print(dst, no, "시트,", sum(len(g[1]) for g in groups), "명, 글자 수 %d ~ %d" % (min(sizes), max(sizes)))


def by_faction(pairs):
    g = defaultdict(list)
    for p, c in pairs:
        g[c[4]].append((p, c))
    cls_order = list(CLASS_EN)
    return [(f, sorted(g[f], key=lambda pc: (cls_order.index(pc[1][3]), pc[0]))) for f in FAC_ORDER if g[f]]


os.makedirs(OUT, exist_ok=True)
write_sheets("base", "1_기본", by_faction([(p, cs[0]) for p, cs in person_cards.items()]), "기본 캐릭터")
# 다시 그릴 인물만 (5명씩) —— 같은 세력 · 비슷한 차림이 한 장에 몰리지 않게 섞었다
# 01~03 은 10/30 에 그림으로 뽑았다 —— 프롬프트를 다시 쓰지 않는다 (깃 5c26048 그대로).
# 04 (10/30): 01 에서 사마의 · 심배 얼굴이 겹치고 방덕 관이 칸을 넘어서 다시 —— 얼굴을 새로 쓴 저수 · 전풍도 함께
REDO_04 = ["사마의", "방덕", "심배", "저수", "전풍"]
write_sheets("base", "1_기본_재작업", [("", [(p, person_cards[p][0]) for p in REDO_04])], "기본 캐릭터 다시 그리기", start=4)
for t in (6, 7, 8):
    write_sheets(t, TIER_DIR[t], by_faction([(p, c) for p, cs in person_cards.items() for c in cs if c[2] == t]), TIER_DIR[t][2:])
