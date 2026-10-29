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
PER = {"base": 15, 6: 12, 7: 6, 8: 4}            # 한 장 최대 인원 (고르게 나눈다)
GRID = {15: (5, 3), 12: (4, 3), 6: (3, 2), 4: (2, 2)}
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
    "동탁": "obese, round barrel body, short legs", "관해": "giant brute, thick limbs", "주창": "short and very muscular, thick arms",
    "장비": "big and burly, barrel chest", "관우": "very tall and dignified, long legs, upright", "조인": "massive and square, like a wall",
    "악진": "small and short, the shortest soldier, oversized helmet", "조조": "short and wiry, but commanding posture",
    "하후돈": "big, broad-shouldered", "황충": "lean old body with sinewy muscular arms", "정보": "tall old man, upright",
    "여포": "tall, long-limbed, heroic proportions", "마초": "slim and athletic, broad shoulders", "조운": "tall and balanced, athletic",
    "미축": "plump", "노숙": "chubby and round", "원술": "plump, soft belly", "간옹": "slouching, lanky",
    "가후": "hunched old man", "좌자": "thin very old man, slight limp", "화타": "small round old man, energetic",
    "방통": "short, scruffy, slightly hunched", "제갈량": "tall and slender", "사마의": "tall and gaunt, long neck",
    "곽가": "slender and loose-limbed", "정욱": "very tall and thin old man", "등애": "stocky and rugged",
    "여몽": "stocky, thick neck", "주태": "solid, broad, covered in bandages", "감녕": "lean and muscular, tattooed arms",
    "능통": "lean and agile", "장연": "lean and agile", "요화": "thin and wiry", "마충": "thin and sneaky",
    "엄백호": "burly, slightly fat", "위연": "broad and heavy, hunched forward", "방덕": "solid and broad",
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
person_cards = defaultdict(list)
for c in cards:
    person_cards[c[1].split(" ")[-1]].append(c)
for p in person_cards:
    person_cards[p].sort(key=lambda c: c[2])


def person_info(p):
    cs = person_cards[p]
    src = next(ent[c[1]] for c in cs if c[1] in ent)        # 가장 낮은 등급 설명 = 기본 디자인
    desc = src["desc"]
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
            "look": src.get("LOOK", ""), "face": faces.get(p, ""), "build": BUILD.get(p) or DEF_BUILD[cs[0][3]],
            "color": color}


INFO = {p: person_info(p) for p in person_cards}

GENDER = """GENDER: every character is an adult MAN, except the women Diaochan, Da Qiao and Xiao Qiao. Men read as men at a glance ——
masculine jaw and brow, thicker neck, broad shoulders, male hairstyles and headwear. Young men are young MEN, never girls:
no long eyelashes, no blush, no rosy lips, no soft baby face."""

LAYOUT = """LAYOUT:
- Image {size}. {n} characters in {cols} columns x {rows} rows (a short last row is centered), reading order left to right, top to bottom.
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

OUTFIT LEVEL (BASE): plain practical clothes and simple armor in the character's colors —— cloth, leather, dull iron,
simple trims, no gold ornaments, no capes, no glowing effects. Iconic features (beards, eyepatch, headbands, signature
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

TIER_COMMON = {
    6: """The SAME {n} Three Kingdoms generals as numbered in the attached reference image, redrawn one level fancier for a
mobile card game's higher-rank card art (rank 1 upgrade).

REFERENCE (attached image): character #k in the reference = panel #k here. Keep each identity EXACTLY: the same face, eye
shape, brows, facial hair, hairstyle and headwear, skin tone, age, body build, main colors and signature weapon or item.
Only the drawing finish, outfit richness and pose change. Someone must recognize them instantly from the reference.

STYLE:
- Detailed chibi, about 3 heads tall, drawn larger: KNEE-UP to WAIST-UP framing, the character fills most of the panel.
- Crisp ink lines with fine detail, richer cel shading with highlights, textured materials (lamellar plates, rivets,
  stitched leather, layered cloth, wood grain on shafts, steel shine on blades).
- Confident poses that show personality: weapon raised, braced, aimed or held across the body; fierce, calm, sly or
  joyful expressions as fits the character.
- Each panel is a vertical rounded rectangle filled with a soft painted green foliage / watercolor texture. No scenery,
  no buildings, no other people, no animals except a cavalry horse's head when CLASS is CAVALRY.

OUTFIT LEVEL (RANK 1): the same base outfit upgraded —— engraved armor plates with metal edge trims, a few silver or
bronze accents, better cloth with simple woven patterns, belts and pouches. No heavy gold, no glow, no aura yet.
{gender}

{layout}

CHARACTERS
""",
    7: """The SAME {n} Three Kingdoms generals as numbered in the attached reference image, redrawn as splendid high-rank
card art (rank 2 upgrade) for a mobile card game.

REFERENCE (attached image): character #k in the reference = panel #k here. Keep each identity EXACTLY: the same face, eye
shape, brows, facial hair, hairstyle and headwear, skin tone, age, body build, main colors and signature weapon or item.
The outfit becomes grander, but the person is unmistakably the same.

STYLE:
- Rich detailed chibi, about 3 to 3.5 heads tall, WAIST-UP or chest-up, large and close in the panel, slightly low angle.
- Fine ink lines, deep shading with strong highlights, lavish material detail: gilded lamellar, embossed dragon/tiger/
  phoenix motifs, fur collars, jeweled clasps, silk capes and sashes, tall plumes and crests.
- CAVALRY ride their warhorse: the rider is the subject, with the horse's armored head, neck and mane in the lower part.
  Others hold their signature weapon or item in a strong, characterful pose.
- Panel background: a vertical rounded rectangle, a soft painted field with a few hints of the setting behind the character
  —— a faction banner, distant soldiers' silhouettes, smoke, mist or sparks —— kept soft and low-detail so the character pops.

OUTFIT LEVEL (RANK 2): ornate —— gold trims and engraved gilded plates, rich brocade, fur, jewels, capes and plumes, much
more splendid than rank 1, while keeping the character's main colors and signature items.
{gender}

{layout}

CHARACTERS
""",
    8: """The SAME {n} Three Kingdoms generals as numbered in the attached reference image, painted as MYTHIC top-rank
card illustrations for a mobile card game —— the most impressive art in the game.

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
- CAVALRY ride their warhorse, rider as the clear subject.

OUTFIT LEVEL (MYTHIC): the most splendid version —— gilded armor or imperial silk covered in dragon, phoenix or tiger
motifs, luminous gold details, flowing capes and ribbons, a faint golden glow, while keeping main colors and signature items.
{gender}

{layout}

CHARACTERS
""",
}


def base_entry(i, x):
    lines = ["%d. %s  [%s, %s]%s" % (i, x["en"], x["cls"], FAC_EN[x["fac"]], "  ★ICONIC: draw the famous traditional look exactly" if x["iconic"] else ""),
             "   DESIGN: " + x["desc"],
             "   LOOK: " + x["look"],
             "   FACE: " + x["face"] + ".",
             "   BUILD: " + x["build"] + ".",
             "   COLORS: " + x["color"] + "."]
    return "\n".join(lines)


def tier_entry(i, x, card, tier):
    e = ent.get(card[1], {})
    lines = ["%d. %s  [%s, %s] —— same person as reference #%d" % (i, x["en"], x["cls"], FAC_EN[x["fac"]], i),
             "   IDENTITY: " + x["look"] + " FACE: " + x["face"] + ". BUILD: " + x["build"] + ".",
             "   COLORS: " + x["color"] + "."]
    d = e.get("desc", "").replace("★ICONIC ", "")
    if d and d != x["desc"]:
        lines.append("   THIS RANK'S LOOK: " + d)
    scene = e.get("SCENE", "")
    if tier == 6 and scene:
        lines.append("   POSE (no scenery, only the pose and expression of): " + scene)
    elif tier == 7 and scene:
        lines.append("   POSE AND SOFT BACKGROUND HINT: " + scene)
    elif tier == 8 and scene:
        lines.append("   MOMENT (paint this scene): " + scene)
    return "\n".join(lines)


def split(items, per):
    groups = -(-len(items) // per)
    b = [round(len(items) * g / groups) for g in range(groups + 1)]
    return [items[b[g]:b[g + 1]] for g in range(groups)]


def layout(n, per, portrait):
    cols, rows = GRID[per]
    if n <= cols * (rows - 1):
        rows = -(-n // cols)
    size = "1024x1536 portrait" if portrait else "1536x1024 landscape"
    return LAYOUT.format(size=size, n=n, cols=cols, rows=rows)


def reset(d):
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        os.remove(os.path.join(d, f))


def write_sheets(key, folder, groups, label):
    """groups: [(faction, [(person, card)])]"""
    dst = os.path.join(OUT, folder)
    reset(dst)
    per = PER[key]
    howto = ["%s —— 이름 순서 = 이름표 번호 순서. 시트를 뽑은 뒤 D:\\Sol 에서 자르기, 다 자르면 solgukji_godot 에서 Godot --import 한 번." % label]
    if key != "base":
        howto.append("위 등급은 먼저 참조 이미지를 만들어 프롬프트와 함께 붙여 넣는다 (1_기본 을 다 자른 뒤에).")
    howto.append("")
    no, sizes = 0, []
    for fac, items in groups:
        for chunk in split(items, per):
            no += 1
            n = len(chunk)
            if key == "base":
                text = BASE_COMMON.format(n=n, gender=GENDER, layout=layout(n, per, False))
                text += "\n".join(base_entry(j + 1, INFO[p]) for j, (p, _) in enumerate(chunk)) + "\n"
            else:
                text = TIER_COMMON[key].format(n=n, gender=GENDER, layout=layout(n, per, True))
                text += "\n".join(tier_entry(j + 1, INFO[p], c, key) for j, (p, c) in enumerate(chunk)) + "\n"
            fname = "%02d_%s_%d명.txt" % (no, fac, n)
            open(os.path.join(dst, fname), "w", encoding="utf-8", newline="\n").write(text)
            sizes.append(len(text))
            suf = SUFFIX.get(key, "")
            names = ",".join(p + suf for p, _ in chunk)
            howto.append("[%s]  %s" % (fname, " · ".join("%d %s" % (j + 1, c[1]) for j, (p, c) in enumerate(chunk))))
            if key != "base":
                howto.append('  참조:   python -I tools/scripts/make_ref_sheet.py "%s" %s/참조_%02d.png' % (",".join(p for p, _ in chunk), dst.replace("\\", "/"), no))
            howto.append('  자르기: python -I tools/scripts/slice_panels.py 시트.png "%s" solgukji_godot/assets/portraits' % names)
            howto.append("")
    open(os.path.join(dst, "자르기_이름.txt"), "w", encoding="utf-8", newline="\n").write("\n".join(howto))
    print(dst, no, "시트,", sum(len(g[1]) for g in groups), "명, 글자 수 %d ~ %d" % (min(sizes), max(sizes)))


def by_faction(pairs):
    g = defaultdict(list)
    for p, c in pairs:
        g[c[4]].append((p, c))
    cls_order = list(CLASS_EN)
    return [(f, sorted(g[f], key=lambda pc: (cls_order.index(pc[1][3]), pc[0]))) for f in FAC_ORDER if g[f]]


os.makedirs(OUT, exist_ok=True)
write_sheets("base", "1_기본", by_faction([(p, cs[0]) for p, cs in person_cards.items()]), "기본 캐릭터")
for t in (6, 7, 8):
    write_sheets(t, TIER_DIR[t], by_faction([(p, c) for p, cs in person_cards.items() for c in cs if c[2] == t]), TIER_DIR[t][2:])
