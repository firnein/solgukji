"""등급별 일러스트 프롬프트 v2 —— 기인 · 초월 · 불멸 · 신화를 한눈에 다르게 읽히도록 규칙으로 갈라 새로 쓴다 (11/10 사용자: "기인 초월 불멸 신화 일러스트 프롬프트 다시 작성해줘").

실행: python -I tools/scripts/make_tier_prompts_v2.py   →  prompts/등급별_v2/{1_기인,2_초월,3_불멸,4_신화}/  (이 네 폴더만 비우고 다시 쓴다. prompts/등급별 은 건드리지 않는다)

등급마다 구도 · 의상 금속 · 빛 · 색 온도 · 배경 · 효과가 다르다 (RANK 표 —— 아래 RANK 상수):
  기인  역할 카드  옥색 포인트 · 먹청색 평면 배경 · 허리 위 정면 · 역할 소품이 한가운데        <인물>_기인.png
  초월  차가운 은빛  연한 하늘색 안개 · 정면 정지 · 은 세공 · 하이키                         <인물>_초월.png
  불멸  화려한 금빛  황금빛 역광 · 비스듬한 역동 포즈 · 금 세공 · 뒤에 군세 · 불씨           <인물>_불멸.png
  신화  어둠 속 살기  검은 바탕 + 인물별 한 가지 강한 색 + 효과 한 가지 · 얼굴 위주 흉상       <인물>_신화.png

만들 대상 = 게임에서 실제로 쓰는 카드 (lines.json 의 retire 로 은퇴한 적 전용 카드는 뺀다): 기인 22 · 초월 15 · 불멸 31 · 신화 11.
FACE · SIGNATURE · LOOK · BUILD · COLORS · MOUNTED(말) 는 손으로 옮겨 쓰지 않고 기존 프롬프트 파일에서 읽는다:
  인물 정체성  prompts/등급별/1_기본 → 1_기본_추가 → 1_기본_재작업 (뒤 폴더 · 뒤 번호가 앞을 덮는다 —— 다시 그린 인물이 이긴다)
  장면 힌트    2_초월 (POSE AND SOFT BACKGROUND HINT) · 3_불멸 (MOMENT) · 4_신화 (SCENE · MOOD)
카드 이름 · 등급 · 병종 · 세력은 data/game.json · cards_ext.json · lines.json 에서, 기인 역할은 data/passives.json 의 role.kiin 에서 읽는다.
손으로 쓴 것은 등급 규칙(RANK) · 기인 소품(KIIN_PROP) · 신화 구도 · 효과 · 표정(MYTH) 뿐이다 —— 대상 인물이 이 표에 없으면 멈춘다.
"""
import json
import os
import re
import sys
from collections import defaultdict

sys.stdout.reconfigure(encoding="utf-8")

SRC = "prompts/등급별"
OUT = "prompts/등급별_v2"
DIRS = {"kiin": "1_기인", 6: "2_초월", 7: "3_불멸", 8: "4_신화"}
SUFFIX = {"kiin": "_기인", 6: "_초월", 7: "_불멸", 8: "_신화"}
LABEL = {"kiin": "기인", 6: "초월", 7: "불멸", 8: "신화"}
PER = {"kiin": 6, 6: 4, 7: 1, 8: 1}            # 한 장 인원 —— 많으면 모델이 인물별 지시를 섞는다. 4~6 이 안전하고 신화는 한 명씩
FAC_ORDER = ["촉", "위", "오", "군"]
CLASS_ORDER = ["창병", "기병", "궁병", "도적", "책사", "유생", "술사", "모사"]

# ── 카드 · 역할 읽기 ──────────────────────────────────────────────────────────

def load_targets():
    d = json.load(open("solgukji_godot/data/game.json", encoding="utf-8"))
    e = json.load(open("solgukji_godot/data/cards_ext.json", encoding="utf-8"))
    lines = json.load(open("solgukji_godot/data/lines.json", encoding="utf-8"))
    retire = set(lines["retire"])
    rename = lines.get("rename", {})
    out = {"kiin": [], 6: [], 7: [], 8: []}
    for c in d["CARDDEF"] + e["cards"] + lines["cards"]:
        if c[0] in retire or c[13] == "foe":
            continue
        name = rename.get(c[0], c[1])
        card = {"id": c[0], "name": name, "person": name.split(" ")[-1], "tier": c[2], "cls": c[3], "fac": c[4]}
        if c[13] == "kiin":
            out["kiin"].append(card)
        elif c[2] in (6, 7, 8) and c[13] in ("", "immortal", "myth"):
            out[c[2]].append(card)
    for k, v in out.items():
        names = [c["person"] for c in v]
        assert len(names) == len(set(names)), "한 등급에 같은 인물 카드가 둘: %s" % k
    return out


def load_roles():
    p = json.load(open("solgukji_godot/data/passives.json", encoding="utf-8"))
    return {person: v[2] for person, v in p["role"]["kiin"].items()}


# ── 기존 프롬프트 파일에서 인물 정체성 읽기 ───────────────────────────────────────

def sheet_names(folder):
    """자르기_이름.txt 의 '자르기' 줄에서 {시트 txt: [인물 …]}"""
    txt = open(os.path.join(SRC, folder, "자르기_이름.txt"), encoding="utf-8").read()
    out, cur = {}, None
    for ln in txt.split("\n"):
        m = re.match(r"^\[(\S+\.txt)\]", ln)
        if m:
            cur = m.group(1)
            continue
        m = re.match(r'^  자르기: .*? "([^"]+)"', ln)
        if m and cur:
            out[cur] = m.group(1).split(",")
            cur = None
    return out


def parse_sheet(path):
    body = open(path, encoding="utf-8").read().split("CHARACTERS\n", 1)[1]
    res = []
    for ent in re.split(r"\n(?=\d+\. \S)", body.strip()):
        lines = ent.split("\n")
        d = {"head": lines[0]}
        for ln in lines[1:]:
            ln = ln.strip()
            key, _, val = ln.partition(": ")
            d.setdefault(key.split(" (")[0], val)       # 'SIGNATURE (unique to him ...)' → SIGNATURE (첫 줄만)
            if key.startswith("SIGNATURE"):
                d["SIGNATURE_RAW"] = ln
        res.append(d)
    return res


def load_identity():
    ident = {}
    for folder in ("1_기본", "1_기본_추가", "1_기본_재작업"):
        names = sheet_names(folder)
        for fn in sorted(names):
            ents = parse_sheet(os.path.join(SRC, folder, fn))
            assert len(ents) == len(names[fn]), (folder, fn)
            for person, ent in zip(names[fn], ents):
                ident[person] = ent
    return ident


def load_hints():
    """등급별 장면 힌트 {6|7|8: {인물: 글}} —— 이전 프롬프트에 있던 그 인물의 이야기 한 줄"""
    hints = {6: {}, 7: {}, 8: {}}
    for tier, folder, keys in ((6, "2_초월", ("POSE AND SOFT BACKGROUND HINT",)), (7, "3_불멸", ("MOMENT",))):
        names = sheet_names(folder)
        for fn in sorted(names):
            ents = parse_sheet(os.path.join(SRC, folder, fn))
            for person, ent in zip(names[fn], ents):
                person = person.split("_")[0]           # 위 등급 시트의 자르기 이름은 '관우_불멸'
                for k in keys:
                    if k in ent:
                        hints[tier][person] = ent[k]
    for fn in sorted(os.listdir(os.path.join(SRC, "4_신화"))):
        m = re.match(r"^\d+_(.+)\.txt$", fn)
        if not m:
            continue
        ent = parse_sheet(os.path.join(SRC, "4_신화", fn))[0]
        for k in ("SCENE", "MOOD"):
            if k in ent:
                hints[8][m.group(1)] = ent[k]
                break
    return hints


# ── 등급 규칙 (손으로 쓴 부분 1) ────────────────────────────────────────────────

HEAD_ZONE = """GAME CROP SAFETY (the game cuts the face out of the top center of each picture for the card and for the small round battle medal):
- The whole HEAD (top of the hair or helmet down to the chin) sits in the TOP-CENTER zone: between {z0}% and {z1}% of the {unit} height, horizontally centered, never off to a side.
- Nothing important within {side}% of the left and right edges or in the bottom 20% (the card cuts those). Plumes and flag tips may rise above the head.
- The face is always clearly lit and never covered by a hand, a weapon, a fan, hair or an effect."""

REFERENCE = """REFERENCE (attached image): a numbered sheet of the BASE chibi designs of these characters —— character #k in the reference = panel #k here.
Keep each PERSON exactly: the same face shape, eyes, brows, nose, mouth, age, facial hair, hairstyle and headwear, skin tone,
body build, cloth colors and signature weapon or item (see each LOOK, FACE, SIGNATURE and COLORS line).
Take NOTHING else from the reference: its small standing pose, flat light and green blot are replaced by the RANK RULES below.
COLORS give the CLOTH and ARMOR colors only (ignore the word \"gold\" there) —— the color of metal trim, the light and the background come from the RANK RULES.
If NO image is attached, build each person from the LOOK, FACE, BUILD, SIGNATURE and COLORS lines alone —— they describe the same design."""

SOLO_REFERENCE = REFERENCE.replace("a numbered sheet of the BASE chibi designs of these characters —— character #k in the reference = panel #k here.",
                                   "the BASE chibi design of this general (one character).")

# 11/13 사용자: 기인 → 초월 → 불멸 → 신화 순으로 점점 실사풍. 불멸에도 신화 하후돈 · 하후연(이전 세대 신화 그림)의 느낌, 신화의 치비 · 애니풍은 없앤다.
# 기본 초상(치비)을 참조로 붙이기 때문에 얼굴까지 치비로 끌려갔다 —— 참조에서는 '누구인지'만 가져오고 그리는 방식은 등급의 REALISM 을 따르게 한다.
REALISM = {
    6: """REALISM LEVEL 2 of 4 (KIIN chibi < TRANSCENDENT < IMMORTAL < MYTHIC): the reference is a chibi cartoon —— do NOT copy its drawing style.
Redraw each person as a NON-CHIBI stylized adult: keep WHO they are (headwear, hairstyle, facial hair, age, build, colors, weapon), but give them
adult body proportions and an adult face. No big head, no big round eyes, no button nose, no stubby limbs.""",
    7: """STYLE LEVEL 3 of 4 (KIIN chibi < TRANSCENDENT < IMMORTAL < MYTHIC —— only MYTHIC is realistic): the reference is a chibi cartoon —— do NOT copy
its proportions. Redraw each person as a HANDSOME, HEROIC ADULT in a polished anime illustration: keep WHO they are (headwear, hairstyle, facial
hair, age, build, colors, weapon), with a normal-size head, adult eyes and a strong clean face. This rank is NOT realistic and NOT chibi:
no photo-real skin, no pores, wrinkles, grime or sweat, no ugly or grotesque faces.""",
    8: """REALISM LEVEL 4 of 4 —— the MOST REALISTIC art in the game (KIIN chibi < TRANSCENDENT < IMMORTAL < MYTHIC): the reference is a chibi cartoon ——
do NOT copy its drawing style. Paint this person as a REAL human being in a cinematic realistic digital painting: keep WHO they are (headwear, hairstyle,
facial hair, age, build, colors, weapon), nothing of the cartoon. No chibi, no anime, no manga line art, no cel shading, no big or glossy anime eyes,
no smooth pretty-boy face.
STYLE REFERENCE (a second attached image, if present —— an older mythic portrait of another general): match its level of painted realism (real facial
anatomy, pores and scars, individually painted hair, heavy scratched metal). Do NOT take its person or its gold card frame.""",
}

DISTINCT = """EVERY CHARACTER LOOKS DIFFERENT: no two characters on a sheet share the same headgear, hairstyle or facial hair ——
follow each SIGNATURE line exactly (HEAD, FACIAL HAIR, MARK). All panels share the RANK LOOK (that is the point), but each person keeps their own
face, body, headwear and weapon, and their own pose within the rank's pose rule —— never clones in different clothes.
STRATEGISTS AND OFFICIALS ESPECIALLY: never default to "narrow slit eyes + long thin beard + tall black official hat" —— follow each FACE
and SIGNATURE exactly; their eye shapes (round, droopy, bulging, narrow), beards (none, stubble, goatee, short, long) and headwear must differ."""

RANK = {
    "kiin": """RANK: KIIN —— the ROLE card (jade).
A KIIN card is an irreplaceable ROLE, not a legend: the picture shows what this person is FOR. The two things to read at thumbnail size are
the ROLE PROP in the middle of the picture and the one bright jade accent. Everything else is calm, tidy and flat.

RANK RULES (checklist —— every panel must obey all of these):
- CAMERA AND POSE: eye-level, front view or a slight 3/4 turn, HIPS-UP half body, perfectly stable, no motion. The head is top-center, the
  ROLE PROP is the second biggest shape: held at chest height in the center of the picture, large and readable at a glance.
- PROPORTIONS AND LINE: the same chibi family as the reference (about 3 heads tall), clean dark-brown ink outlines, flat soft colors with
  simple two-tone cel shading —— a slightly more polished version of the reference, not more detailed.
- OUTFIT: exactly the base outfit (practical cloth and simple armor, NO gold and NO silver ornaments, no cape unless the base design has one)
  PLUS the jade accent: a jade-green (#2ee6c0) cord, tassel, ribbon or pendant on the outfit, and the key part of the ROLE PROP tinted jade.
- LIGHT: flat, even, soft; low contrast; no rim light, no glow, only a soft contact shadow.
- COLOR: the person's own colors on a muted DUSTY TEAL-GREY background (#5f8a8c). Jade #2ee6c0 is the ONLY bright accent in the picture.
- BACKGROUND: flat dusty teal-grey with a very soft vignette, plus ONE thin flat jade ring (a seal-like circle about 70% of the panel width,
  thin line, centered behind the head and shoulders) that stays completely inside the panel and never touches its edge.
  No scenery, no crowd, no banners.
- EFFECTS: none, except small jade shards, ripples or sparks that belong to the ROLE PROP (see each ROLE line).
- EXPRESSION: calm, professional, focused on the job.
- NEVER: gold or silver trim, dramatic light, scenery, armies, fire or lightning, a tilted dynamic pose, a close-up face.""",
    6: """RANK: TRANSCENDENT —— cold silver dignity.
RANK LOOK IN ONE LINE: calm, cold and formal, a silver-white portrait in still air. At thumbnail size it must read "silver and pale sky-blue,
quiet and noble".

RANK RULES (checklist —— every panel must obey all of these):
- CAMERA AND POSE: eye-level, CHEST-TO-WAIST crop. The body faces the front or turns at most 30 degrees, shoulders level, the pose still and
  symmetrical, the weapon or item held VERTICALLY at one side (a tall quiet line). No diagonal action, no foreshortening, no wide-angle.
- PROPORTIONS AND RENDERING: stylized anime-style game illustration with ADULT proportions, about 5.5 to 6 heads tall (NOT chibi, NOT semi-chibi):
  a normal-size head on broad shoulders, adult faces with normal-size eyes, a drawn nose bridge, a defined jaw and cheekbones. Fine clean ink
  lines, soft cel shading with a little painted gradation and airy highlights. Every panel on the sheet uses the SAME proportions and rendering.
- OUTFIT: the base design made noble —— engraved SILVER and white-steel plates, silver filigree, pale silk over the faction-colored cloth
  (the cloth muted and a little desaturated), a white or pale-blue plume or tassels, plain silver clasps. NO GOLD anywhere.
- LIGHT: cold, bright and even, from the upper front-left, a thin white rim, soft pale blue-grey shadows. HIGH-KEY: the whole picture is light.
- COLOR: silver, white and pale sky-blue (#cfe6ff); the faction color only in the cloth. A cool temperature everywhere.
- BACKGROUND: pale blue-white mist fading to white at the bottom, and ONE tall faction war banner (blank cloth in the faction color, no lettering)
  standing far behind on one side, slightly out of focus. Nothing else: no crowd, no dramatic sky.
- EFFECTS: none, except a few tiny silver light motes. No fire, no lightning, no glowing aura.
- EXPRESSION: composed dignity, the eyes level, a restrained look.
- NEVER: chibi or super-deformed proportions, big heads, big round eyes, a jade ring or circle behind the head (that is the KIIN mark),
  gold or orange, fire or lightning, a dark background, a dynamic pose, crowds, a cape blowing in the wind.""",
    7: """RANK: IMMORTAL —— a legend in his own scene.
RANK LOOK IN ONE LINE: ONE legendary general, big and unmistakable, in the place, weather and light of HIS OWN story. Every IMMORTAL picture has a
different time of day and a different color palette; what they share is the big face, the rich finish and the cinematic depth —— NOT a color.

RANK RULES (checklist —— every panel must obey all of these):
- FACE FIRST: a tight BUST portrait —— head and shoulders, nothing below the chest. The HEAD is about 40 to 45% of the picture height: top of the
  hair or helmet at about 8%, eyes at about 30%, chin at about 50%, horizontally centered. The FACE is the picture: the sharpest, brightest,
  highest-contrast area. Shoulders, collar and cape fill the lower part; weapon, horse and hands appear only as cut-off shapes at the edges.
- COMPOSITION: follow the COMPOSITION line EXACTLY —— the camera height, the direction the head and body face, and the expression are the point
  of this picture and differ for every general in the game. Do NOT fall back to the default "three-quarter view from a low angle, shouting,
  weapon raised on the left".
- SEPARATION FROM THE BACKGROUND: the background is clearly DARKER (about two stops), less saturated and soft-focus behind a layer of smoke and
  haze, like a telephoto photograph. A thin bright rim light in the color of the scene's light source (moon, fire, sun, lantern, snow glare) runs
  around the silhouette. The area directly behind the head is plain sky, mist or smoke —— no banner, spear, roof or soldier touches or crosses the head.
- PROPORTIONS AND RENDERING: a polished ANIME game illustration (top-rarity card art of a mobile RPG), adult heroic proportions about 6.5 to 7
  heads tall. Clean confident line art, rich cel shading with smooth painted gradients and crisp highlights on metal, cloth and hair.
  Faces are stylized, clean and ATTRACTIVE: clear expressive anime eyes of adult size, a simple clean nose and mouth, smooth skin, a firm jaw ——
  cool, dignified and charismatic even on old, fat or villainous characters (their age, weight and nature are shown by shape and expression,
  never by realistic wrinkles, pores, sagging skin, grime or sweat). Mouths are drawn simply; no detailed teeth or gums.
  Every panel on the sheet uses the SAME style.
- OUTFIT: the base design made magnificent, in the person's OWN colors: the faction-colored cloth (cape, robe, sash, headscarf) is big, saturated
  and dominant on the figure, so that the panels differ in color at a glance (green, navy, crimson, purple, yellow ...). Gold is the TRIM only ——
  gilded edges, clasps, embossed dragon / phoenix / tiger motifs —— over dark steel, lacquer or silk. Never an all-gold figure.
- LIGHT AND COLOR: taken from the SETTING AND LIGHT line —— it decides the time of day, the weather and the whole palette of this picture. The face
  is always lit clearly with true skin tone. Value plan: bright face and rim > saturated faction cloth > dark armor > dimmer background.
- BACKGROUND: the place of the SETTING AND LIGHT line (and the STORY BACKGROUND line), small, dim and out of focus. An army or banners appear only
  where the story has them, far away and low in the picture.
- EFFECTS: only what the setting gives (rain, snow, mist, dust, sparks, petals, blown leaves), a few particles in front of the shoulders, never over
  the face. No lightning, no spirit beasts, no glowing aura.
- EXPRESSION: each person's own (see each COMPOSITION line), stylized and cool; at most ONE open-mouthed shout on the whole sheet.
- NEVER: a waist-up or full-body view, a small head on a huge torso, a busy bright background that swallows the figure, a wall of soldiers right
  behind the shoulders, the generic "golden sunset battlefield with orange sky and embers" (unless the SETTING line says fire or sunset),
  an all-gold or all-orange picture, chibi, big heads on small bodies, photorealism, realistic skin texture, pores,
  wrinkles, sweat, grime, detailed teeth, grotesque or ugly faces, a flat empty or pure black background.""",
    8: """RANK: MYTHIC —— a killing stare out of the dark.
RANK LOOK IN ONE LINE: a near-black picture with ONE hot color and ONE legendary effect, the eyes the brightest point. At thumbnail size it must read
"black, with crimson / white-hot / violet fire or lightning". One look should make the viewer feel this person is about to KILL THEM.

RANK RULES (checklist —— obey all of these):
- RENDERING: a cinematic REALISTIC digital painting (dark historical fantasy key art) —— NOT anime, NOT manga, NOT chibi. Real human facial anatomy
  for the person's age: realistic eyes with small irises, heavy lids and brow bone, a real nose, lips, cheekbones and jaw; skin with pores, scars, sweat and
  grime; hair, brows and beard painted strand by strand; heavy scratched metal, worn leather, thick embroidered cloth. No ink outlines, no cel shading.
- FRAMING: a tight BUST in real human proportions (about 7.5 to 8 heads tall). The head is about 35 to 40% of the picture height:
  top of the head at about 10%, eyes at about 30%, chin at about 46%, horizontally centered. The shoulders, armor, a weapon edge and the effect
  fill the lower half. Follow each COMPOSITION line for the head turn and the camera.
- OUTFIT: heavy engraved armor or silks, worn and battle-scarred, in the person's own colors. Gold here is dull, old and scratched, never bright.
- LIGHT: ONE hard key light from the side (or from below); the far side of the face and body fall into deep black; a thin hot rim in the ACCENT color
  along the hair, cheek and shoulder; a sharp catchlight in the near eye. The face stays readable with true skin tone.
- COLOR: a near-black ground (#0a0a10) plus the ACCENT color of the EFFECT line, plus true skin and outfit colors. No pastel, no bright sky, no daylight.
- BACKGROUND: darkness; at most a dim out-of-focus silhouette hint of the story setting inside the black. No army, no banners, no mist, no frame.
- EFFECTS: exactly ONE legendary effect per picture (see the EFFECT line), bursting around the shoulders, the weapon and the background ——
  never across the face. Tiny sparks only otherwise. No guardian beasts or giant spirit animals.
- EXPRESSION: killing intent aimed at the VIEWER, the eyes meeting the camera even in profile (see each EXPRESSION line); each person is dangerous
  in their OWN way, never the same generic angry face.
- HANDS: out of the frame unless the COMPOSITION needs them; a natural relaxed grip with five correct fingers, never crowding the face.
- NEVER: chibi, anime or manga style, line art, cel shading, big or glossy eyes, a smooth youthful idol face, a bright or pastel background, crowds, mist, a silver-blue palette, a gold-orange sunset palette, jade, a card frame or border.""",
}

STYLE_LINE = {
    "kiin": "Calm flat SD role-card illustrations for a mobile card game (the KIIN cards: one irreplaceable role per card).",
    6: "Refined, cold, silver TRANSCENDENT card illustrations for a mobile card game —— stylized adult anime proportions, not chibi.",
    7: "IMMORTAL card illustrations for a mobile card game —— polished anime hero portraits with adult proportions: not chibi and not realistic.",
    8: "ONE MYTHIC card illustration of a single Three Kingdoms general for a mobile card game —— the rarest, most intimidating and most REALISTIC art in the game (a cinematic realistic painting, never anime).",
}

MOUNT_RULE = {
    "kiin": "waist-up rider on a calm standing horse; the horse's head and neck form a quiet base at the bottom (chibi, not rearing).",
    6: "rider chest-to-waist facing nearly front; the horse's armored head and neck rise from the bottom edge in front of him, standing calmly.",
    7: "he is ON this horse, but this is a face portrait: the horse is only a glimpse of ears, mane or the top of its head at one bottom corner.",
    8: "the rider's face and shoulders are the subject; the armored horse is only a dark glimpse of head, neck or mane at the lower edge of the picture.",
}

# ── 기인: 역할 읽는 법 + 인물별 소품 (손으로 쓴 부분 2) ──────────────────────────────

ROLE = {   # passives.json role.kiin[인물][2] → (영문 이름, 하는 일, 그림이 말하는 것)
    "철벽": ("BULWARK", "takes the hits for the allies", "a big flat guarding shape (a shield or crossed weapons) planted at the front center, an immovable wide stance"),
    "방깎": ("ARMOR-BREAKER", "strips the enemy's armor so that allies hit harder", "a weapon tip or a bolt punching through a cracked metal plate, flying metal shards"),
    "결계 깨기": ("WARD-BREAKER", "shatters magic barriers so that stratagems land", "a pale glowing barrier lattice of hexagon tiles cracking at the point of a brush, a finger or a talisman"),
    "기절": ("STUNNER", "knocks enemies senseless and breaks their rhythm", "a sharp white impact flash with a few small dizzy stars, something has just been knocked or cut"),
    "둔화": ("SLOWER", "floods the field and slows the enemy", "water: ripple rings and curling currents around the prop, droplets hanging motionless in the air"),
    "공깎": ("WEAKENER", "saps the enemy's attack", "something sagging or wilting: a limp drooping flag, a bent blade, a coiled snake —— slack, downward shapes"),
    "도트": ("BURNER", "sets enemies burning (damage over time)", "a small flame crawling along a chain or a fuse, drifting embers"),
    "치료": ("HEALER", "heals and supplies the allies", "soft green-white light flowing from the hands or an instrument, herbs, needles, grain"),
    "지원": ("SUPPORT", "lifts the allies (recommends talent, adds power)", "an open scroll or mirror, a pointing hand, soft jade light rising upward"),
}
ROLE_ORDER = ["철벽", "방깎", "결계 깨기", "기절", "둔화", "공깎", "도트", "치료", "지원"]

KIIN_PROP = {
    "조인": "braced behind his man-tall tower shield planted in the center of the picture, both gauntlets pressed flat on its top edge, three arrows stuck in its face, jade cord tassels hanging from its top corners; only the helmet, the eyes, the beard and the shoulders show over the rim.",
    "전위": "arms wide and braced, his two heavy iron halberds crossed in front of his chest like a barrier with jade cords tied at the crossing, an arrow stuck in his shoulder plate and he does not flinch —— the man who takes the blow for his lord.",
    "고순": "a tall rectangular iron shield planted in the center in front of him with a jade-green edge trim, the short halberd levelled over its top edge, a snapped cavalry lance splintered against the shield face —— a gate that cannot be charged through.",
    "서성": "a big round wooden shield with a jade rim on his left arm held at chest height in the center, the long glaive planted beside him, a wall of tall river reeds standing behind him (the false wall of reeds on the river), the bow slung on his back.",
    "공손찬": "riding the white horse, his long spear levelled forward and its point has just punched through a round bronze shield, which cracks open with a few jade-tinted shards flying; the horse's head and neck are the calm base at the bottom.",
    "황월영": "her wooden repeating crossbow levelled to the left, a bolt just fired through a steel breastplate on a wooden stand at the right, the breastplate cracked like a spiderweb with jade-tinted shards flying; gears and tools at her belt.",
    "장연": "a knife in each hand, the right knife punched through the middle of an iron breastplate that hangs from the left knife, the plate cracked in a star with jade-tinted shards flying.",
    "곽가": "the short calligraphy brush flicking forward, and a pale-blue octagonal barrier of light hanging in front of him is shattering into hexagon tiles around the brush tip; the loose hair stirring, the wine gourd at his hip.",
    "서서": "his mother's letter in one hand, two fingers of the other hand pressed on a pale-blue octagonal lattice of light (the Eight Gates ward) that cracks outward from his fingertips; the sword at his hip.",
    "좌자": "leaning on his limping staff, one hand holding a peeled tangerine, a paper talisman stuck to a pale-blue glowing bubble-ward that is cracking, one crane feather floating beside it.",
    "손상향": "her two short swords crossed in front of her chest, and the pommel of one has just knocked an enemy helmet spinning out of the corner of the picture with a white impact flash and a few small stars; the red ribbons flying.",
    "주환": "crouched in a half-turn, the short sword just swung through a glowing orb of gathering energy and cut it into two fizzling halves, a white slash flash across it.",
    "초선": "the folded fan raised beside her face and above her open palm two tiny rival warrior figures (like chess pieces) glaring at each other, linked by a thin chain-link ribbon, a few dizzy stars above them.",
    "장합": "riding the dapple-grey horse through rising floodwater, blue ripple rings and curling currents around the horse's legs and the lower part of the picture, the long spear held upright; the armor split yellow and blue.",
    "관로": "the turtle shell with trigram symbols held in both hands at chest height, a ripple ring expanding from it, droplets hanging motionless in the air around him (time slowing), a small pool of water curling at the bottom.",
    "가후": "a small poison vial in one hand, the other hand cupped beside his mouth as if whispering, a thin black snake coiled around his forearm; at the bottom edge a limp drooping enemy banner.",
    "노숙": "one open palm held out in a calm peaceful offer, the rolled map in the other hand, and in the lower corner an enemy sword blade sagging limply, bent like a wilted stalk.",
    "마등": "riding the shaggy horse, his own banner held upright in one hand while a captured enemy banner droops limp over the horse's shoulder.",
    "방통": "a lit torch in one hand and an iron chain in the other, a small line of flame crawling along the chain links toward the edge of the picture, embers drifting; the chain-link scroll at his belt.",
    "화타": "a long glowing acupuncture needle held between two fingers, the blue cloth medicine bag on his arm, soft green-white healing light flowing from his other palm.",
    "미축": "an open grain sack and a long string of coins held up in his hands, a jade glow on the coins, the account book at his belt.",
    "사마휘": "the round jade mirror disk in one hand with a soft jade light rising from it, the other hand pointing off to the upper side as if recommending a talent.",
}

# ── 신화: 인물별 구도 · 효과 · 표정 (손으로 쓴 부분 3) ──────────────────────────────

MYTH = {
    "관우": dict(
        comp="calm near-frontal bust, the head tilted back a few degrees so that he looks down his nose, the long black beard flowing down over the chest; the crescent blade of the Green Dragon glaive rises from the lower right corner, its edge glowing white-hot",
        effect="ONE blood-red lightning bolt forking down through the black behind his left shoulder, lighting the glaive blade and the tips of his beard crimson; a few red embers",
        accent="crimson",
        expr="majestic cold dignity, the narrow phoenix eyes opening slowly to stare at you, utterly silent menace"),
    "여포": dict(
        comp="three-quarter bust, the head snapping toward the viewer in a predator's grin; the two long pheasant feathers of the crown sweep back; the crescent blade of the halberd slashes diagonally across the lower left",
        effect="ONE surge of black-red hellfire rising from the bottom edge, its flames shaped like a streaming mane, red sparks",
        accent="crimson",
        expr="arrogant savage pride, a predator's grin, utterly fearless"),
    "장료": dict(
        comp="HIGH angle, the head lowered, glaring UP at the viewer through the brows; the purple-black plume of the helmet soaked by rain; heavy rain streaks slanting across the picture",
        effect="ONE white-hot lightning flash behind him in a black rain storm, the rain streaks and the scar on his cheek lit white",
        accent="white-hot",
        expr="grim, scarred, the terrifying calm of the man who charged an army of a hundred thousand with eight hundred riders"),
    "손권": dict(
        comp="front-facing bust, the chin slightly raised, absolutely symmetrical and still like a ruler; the heavy collar and shoulder plates fill the lower half; at the bottom edge the dark silhouette of rolling river waves",
        effect="ONE web of violet lightning arcing inside black storm clouds on both sides of the head, mirrored in the black water at the bottom; a violet rim along the cheek",
        accent="violet",
        expr="cold calm authority, the striking green-blue eyes fixed on you without blinking"),
    "제갈량": dict(
        comp="profile turned to the left, then the eyes alone snapping to the viewer; the white crane-feather fan held low at the bottom edge below the chin, never covering the face; the black scholar's cap sharp against the dark",
        effect="ONE white lightning bolt drawing straight lines in the geometry of an eight-trigrams formation across the black sky behind him, the fan's feathers lifted by the wind",
        accent="white-hot",
        expr="serene, all-knowing, a faint smile —— the calm of someone who planned your death long ago"),
    "유비": dict(
        comp="slightly low front bust, the eyes brimming with held-back tears, the long earlobes clearly visible; one of the twin swords drawn so that its edge crosses the bottom of the picture",
        effect="ONE shaft of pure white light breaking through black storm clouds from the upper left onto his shoulder and the side of his face, white petals and ash drifting in it (a soft beam, not a bolt)",
        accent="white light",
        expr="sorrowful righteous resolve, tears held back, a gaze that commands loyalty"),
    "장각": dict(
        comp="front bust, the head thrown slightly back and staring wide-eyed down at the viewer, wild hair and the yellow sleeves of both arms rising at the edges of the picture, the head of the nine-knot staff at the lower right",
        effect="ONE violet lightning bolt striking down through black clouds into the head of the staff, burning yellow paper talismans swirling around the shoulders",
        accent="violet",
        expr="a feverish zealot's wide-eyed glare, chanting, possessed by heaven's mandate"),
    "조조": dict(
        comp="slightly low three-quarter bust, the head turned over the shoulder toward the viewer with a sly smirk and one brow raised; the hilt of the Yitian sword visible at the shoulder; the heavy dark cape collar",
        effect="ONE band of dark crimson fire glow along the far horizon with a few crows as black shapes, sparks drifting past the cape",
        accent="crimson",
        expr="a sly knowing smirk, eyes that read your every thought —— the hero of chaos amused by you"),
    "주유": dict(
        comp="front bust, the head tilted a little with the chin up; the long hair and the cape blowing sideways across the lower part of the picture; hands out of the frame",
        effect="ONE wall of crimson fire on black water far behind him, sparks streaming horizontally past his head (never over the face)",
        accent="crimson",
        expr="elegant proud disdain, a faint cool smile, a beautiful but merciless gaze"),
    "감녕": dict(
        comp="tight bust from BELOW, the head pushed slightly forward in a savage snarl with the teeth bared; the red bandana tails flying; the rope with the iron grappling hook over the shoulder and the brass bells at the collar",
        effect="ONE white-hot lightning flash revealing the silhouettes of a river fleet's sails and sheets of rain, the rain streaks lit white",
        accent="white-hot",
        expr="a savage pirate snarl, teeth bared, eyes wide with bloodlust"),
    "사마의": dict(
        comp="front bust seen from slightly BELOW, the chin raised and the narrow wolf-like eyes looking down at the viewer; the white cloak's collar around the neck; the folded arms cut off below the frame",
        effect="ONE slow coil of violet-black mist at the bottom and a single thin violet lightning hairline cracking the black sky behind him, a cold point of white light in each eye",
        accent="violet",
        expr="cold supreme contempt, a faint cunning smile —— the quiet of the man who will outlive everyone"),
}


# ── 불멸: 구도 풀 (11/13 사용자: "너무 다 똑같은 구도이면서 인물이 돋보이지 않음") ─────────────────────
# 예전 규칙은 모든 패널에 "낮은 앵글 · 대각선 · 함성" 하나를 줬다. 병종 묶음마다 구도 여러 개를 두고, 한 장 안에서 겹치지 않게 돌려 준다.
IMMORTAL_SCENE = {   # 인물별 장면의 시간 · 날씨 · 색 (이야기 힌트에 맞춰 손으로 씀) —— 같은 색이 이어지지 않게
    "관우": "a storm over the flooding Han river —— heavy grey rain clouds, cold daylight, churning teal-green water; palette storm grey, teal and his deep green",
    "서황": "a cold dawn over siege trenches and earthworks —— blue-grey morning mist, a pale white sun low on the horizon; palette slate blue, steel and pale cream",
    "손책": "a bright clear noon over the wide Yangtze —— a vivid blue sky with tall white clouds, sparkling water, red banners; palette sky blue, white and crimson",
    "동탁": "a palace hall at night —— red paper lanterns and candles, black lacquer pillars, heaps of looted treasure glinting in the dark; palette crimson, black and candle amber",
    "장비": "an overcast autumn afternoon at a wooden bridge over a river, dust rising from the forest behind —— palette grey sky, russet leaves, dark green and brown",
    "하후돈": "a dusty battlefield at harsh midday —— a white sun through ochre dust haze, broken arrows in the ground; palette ochre, bone white and navy",
    "손권": "sunrise on the great river —— a pale rose and light blue sky, the sails of a fleet, glittering water; palette rose, pale blue and crimson",
    "여포": "the stone gate of a mountain pass on a dark thunder-blue evening, torches along the walls —— palette deep indigo, cold stone grey and blood red",
    "마초": "a western desert pass on a cold bright winter day —— a pale blue sky, yellow sand, snow-capped mountains far away; palette sand, ice blue and silver-white",
    "허저": "a muddy duelling ground just after summer rain —— wet earth, low grey clouds breaking, steam in the humid air; palette wet brown, grey and navy",
    "태사자": "green spring hills in clear afternoon light —— fresh grass, blue distance, white blossom on the wind; palette spring green, sky blue and red",
    "원소": "a great altar on a clear morning with the many-colored banners of the allied lords —— white-gold daylight; palette ivory, yellow and many small banner colors",
    "조운": "an open plain at blue-violet twilight, a full moon rising through battle dust —— palette violet-blue, moon silver and white",
    "장료": "a river crossing in cold dawn mist, a broken bridge fading into the fog —— palette blue-white mist, steel and purple-black",
    "감녕": "a night raid on the river under a bright moon —— deep indigo water, ship lanterns, patterned brocade sails; palette indigo, moon white and red",
    "장각": "night, a sea of torches below an altar, greenish incense smoke under a starless sky —— palette black-green, torch amber and yellow cloth",
    "황충": "a crisp mountain morning among pines high on a ridge —— cool blue shadows, a clear warm sun, far valleys in haze; palette pine green, cool blue and warm white",
    "하후연": "a wind-swept grassland under fast grey clouds, long grass bending —— palette steel blue, grey and dry straw",
    "여몽": "a river at misty daybreak, plain merchant boats sliding through thick white fog —— palette pearl white, pale grey and soft red",
    "장로": "a mountain temple at night, rows of warm paper lanterns in blue mist —— palette night blue, lantern amber and pale yellow",
    "위연": "a narrow mountain gorge, deep green shadow between cliffs with one shaft of sunlight falling into it —— palette dark moss green, rock grey and one warm beam",
    "순욱": "a quiet study in late afternoon —— soft window light across a wooden lattice, thin incense smoke; palette muted blue-grey, warm wood and ivory",
    "육손": "a forest valley at dusk with a long chain of camps on fire —— black tree silhouettes against orange flames; palette fire orange, black and red",
    "진궁": "a white stone gate tower in a rainstorm, torn banners snapping —— palette rain grey, wet white stone and dark red",
    "강유": "a high northern mountain pass in wind-driven snow, green banners straining —— palette snow white, cold blue and green",
    "사마의": "a moonlit winter night, bare black trees and low mist —— palette violet-blue, moon white and black",
    "주유": "night on the great river, a burning fleet far behind mirrored in black water —— palette black, crimson and ember red",
    "제갈량": "an altar under a deep-blue starry night sky, lamps flickering in a rising east wind —— palette midnight blue, star white and jade green",
    "조조": "a cliff edge at a bleak grey dawn, crows wheeling, thin smoke far below —— palette steel grey, navy and cold white",
    "법정": "a mountain peak above a sea of clouds at clear high noon —— palette bright sky blue, cloud white and green",
    "유비": "a snowy winter day at a thatched cottage among bamboo —— soft white daylight, falling snow; palette snow white, bamboo green and warm straw",
}

IMMORTAL_COMP = [
    "STRAIGHT-ON close bust at eye level, shoulders square to the viewer, the chin slightly lowered and the eyes locked on the viewer from under the brows. Expression: a calm, immovable stare, mouth closed",
    "LOW camera, the body turned three-quarters toward the {a}, the chin lifted so that the eyes look DOWN at the viewer. Expression: a confident smirk, one corner of the mouth raised",
    "OVER THE SHOULDER: the back and {a} shoulder are toward the viewer and the head is turned back over that shoulder, the face in three-quarter view. Expression: a hard sideways glare, mouth closed",
    "HIGH camera looking down from the front; the head is bowed a little and the eyes look UP at the viewer through the brows. Expression: a slow dangerous smile",
    "PURE PROFILE facing {b}, only the eye sliding sideways to meet the viewer, hair, ribbons or plume blowing forward past the face (never over it). Expression: cold and composed, lips closed",
    "TILTED camera (about 15 degrees), the body leaning toward the viewer so the face comes close, the shoulders rising behind it. Expression: a fierce battle shout",
    "EYE-LEVEL three-quarter view toward the {b}, the head thrown back a little. Expression: a bold open laugh or wide grin, eyes narrowed with delight",
    "LOW camera straight from the front, the figure looming over the viewer, the upper face half in shadow under the helmet, hat or hair with a bright rim of light around the head. Expression: a grim scowl, jaw clenched",
]
IMMORTAL_EDGE = {
    "mount": "At the edges: a glimpse of the horse's ears and mane at the lower {b} corner, the weapon shaft cut off along the {a} edge",
    "melee": "At the edges: the head or blade of the signature weapon rises along the {a} edge, partly cut off by the frame, catching the light",
    "archer": "At the edges: the upper limb of the bow and the fletching of one arrow along the {a} edge, the quiver behind the shoulder",
    "mind": "At the edges: the signature item (fan, scroll, staff or book) held low at the bottom {a} corner, well below the chin, never covering the face",
}
_GROUP = {"SPEARMAN": "melee", "ROGUE": "melee", "CAVALRY": "melee", "ARCHER": "archer"}


def immortal_comps(chunk, ident, sheet_no):
    """인물별 구도 —— 전체 순서(sheet_no)대로 8가지 카메라를 돌려 쓰고 좌우를 번갈아. 이웃한 번호끼리는 늘 다른 구도"""
    out = []
    for i, c in enumerate(chunk):
        ent = ident[c["person"]]
        g = "mount" if horse_of(ent) else _GROUP.get(en_head(ent)[1], "mind")
        n = sheet_no + i - 1
        k = (n * 3) % len(IMMORTAL_COMP)            # 3칸씩 건너뛰어 같은 병종 · 세력 줄에서 비슷한 구도가 이어지지 않게
        a, b = ("left", "right") if (n // len(IMMORTAL_COMP) + n) % 2 == 0 else ("right", "left")
        out.append((IMMORTAL_COMP[k] + ". " + IMMORTAL_EDGE[g]).format(a=a, b=b))
    return out


# ── 시트 짜기 ──────────────────────────────────────────────────────────────────

def en_head(ent):
    m = re.match(r"^\d+\. (.+?)  \[([A-Z]+), (\w+)\]", ent["head"])
    return m.group(1), m.group(2), m.group(3)


def is_woman(ent):
    return bool(re.search(r"woman|girl|maiden|unique to her", ent.get("BUILD", "") + ent.get("SIGNATURE_RAW", "")))


def horse_of(ent):
    m = re.search(r"riding (.+?) ——", ent.get("MOUNTED", ""))
    return m.group(1) if m else None


def sig_parts(ent):
    s = ent["SIGNATURE"]
    m = re.match(r"HEAD (.*?); FACIAL HAIR (.*?); MARK (.*)\.$", s)
    if m:
        return m.groups()
    m = re.match(r"HAIR (.*?); MARK (.*)\.$", s)
    return (m.group(1), "her face", m.group(2))


def identity_lines(i, ent, key, solo=False):
    name, cls, fac = en_head(ent)
    ref = "" if solo else " —— same person as reference #%d" % i
    lines = ["%d. %s  [%s, %s]%s" % (i, name, cls, fac, ref),
             "   LOOK: " + ent["LOOK"],
             "   FACE: " + ent["FACE"],
             "   BUILD: " + ent["BUILD"],
             "   " + ent["SIGNATURE_RAW"],
             "   COLORS: " + ent["COLORS"]]
    horse = horse_of(ent)
    if horse:
        lines.append("   MOUNTED: riding %s —— %s" % (horse, MOUNT_RULE[key]))
    return lines


def entry(i, person, ent, key, roles, hints, comp=None):
    lines = identity_lines(i, ent, key, solo=(PER[key] == 1))
    if key == "kiin":
        role = roles[person]
        en, does, reads = ROLE[role]
        lines.append("   ROLE: %s —— %s. The picture says it with: %s." % (en, does, reads))
        lines.append("   POSE AND PROP (the ROLE PROP is the star): " + KIIN_PROP[person])
    elif key == 6:
        if person in hints[6]:
            lines.append("   STORY HINT (tiny and optional, only a faint shape in the mist or the thing he or she holds; the calm pose rule wins): " + hints[6][person])
    elif key == 7:
        story = hints[7].get(person) or hints[8].get(person)        # 불멸 힌트가 없는 신화 인물은 신화 장면 한 줄로 대신
        if story:
            lines.append("   STORY BACKGROUND (the place behind this person —— dim, small and out of focus; take only the setting, ignore any pose, lightning, aura or spirit beast in it): " + story)
        if person in IMMORTAL_SCENE:
            lines.append("   SETTING AND LIGHT (decides the time of day, the weather and the whole color palette): " + IMMORTAL_SCENE[person] + ".")
        if comp:
            lines.append("   COMPOSITION: " + comp + ". The head stays big in the top-center zone.")
    else:
        t = MYTH[person]
        if person in hints[8]:
            lines.append("   SCENE (only a dim out-of-focus silhouette hint inside the black, nothing bright): " + hints[8][person])
        lines.append("   COMPOSITION: " + t["comp"] + ".")
        lines.append("   EFFECT (the ONE legendary effect; the ACCENT color is %s): %s." % (t["accent"], t["effect"]))
        lines.append("   EXPRESSION: " + t["expr"] + ".")
        h, f, m = sig_parts(ent)
        lines.append("   MUST SHOW (clearly, large and well lit): %s; %s; and if they fit the composition: %s." % (h, f, m))
    return "\n".join(lines)


STYLE_REF_NOTE = {
    8: "화풍 참조(두 번째 첨부, 11/13): solgukji_godot/assets/portraits/하후돈_신화.png (또는 하후연_신화.png) 를 참조 이미지와 같이 붙인다 —— 사실감 기준. 금색 테두리는 따라 그리지 않는다.",
}

GRID = {1: (1, 1, False), 2: (2, 1, True), 3: (3, 1, True), 4: (2, 2, False), 6: (2, 3, False)}


def grid_for(n, per):
    if per == 6 and n in (4,):
        return 2, 3, False            # 6칸 판에 4명 —— 마지막 줄 전체를 비운다 (한 줄에 한 칸만 비면 자르기가 패널을 못 찾는다)
    return GRID[n]


def sizes_for(total, per):
    """한 장 인원 목록 —— per 씩 채우고 남는 수는 한 장으로 (자를 수 있는 칸 구성만 쓴다)"""
    out = []
    while total >= per:
        out.append(per)
        total -= per
    if total == 5:
        out += [3, 2]
    elif total:
        out.append(total)
    return out


def layout(n, per):
    cols, rows, land = grid_for(n, per)
    slots = cols * rows
    size = "1536x1024 landscape" if land else "1024x1536 portrait"
    empty = ""
    if n < slots:
        empty = ("\n- The last %d slot%s (%s) stay EMPTY: plain light green background only, no panel, no banner, no number.\n"
                 "  Do not enlarge or re-space the panels to fill the space —— every slot keeps the same size as on a full sheet."
                 % (slots - n, "s" if slots - n > 1 else "", ", ".join(str(k) for k in range(n + 1, slots + 1))))
    return """LAYOUT:
- Image {size}. ALWAYS a fixed grid of {cols} columns x {rows} rows = {slots} equal slots, reading order left to right, top to bottom.
- Characters 1 to {n} fill the first {n} slots in order.{empty}
- Each slot holds ONE tall rounded-rectangle PANEL whose picture runs all the way to the panel edge: no inner border, no frame, no white margin.
- Natural proportions: never stretch, squash or shorten a character to fit a panel.
- Flat light green paper background (#9BCF88) around the panels, NARROW even gaps between them (about 3% of the image width).
  Nothing crosses into a neighbor: no plume, banner, weapon or effect leaves its own panel.
- Under each panel a dark green brush-stroke banner with ONLY its number (1 to {n}) in big white digits.
- No other text anywhere: no names, no titles, no captions, no signature, no watermark. Do not draw the line labels as text.""".format(
        size=size, cols=cols, rows=rows, slots=slots, n=n, empty=empty)


SOLO_LAYOUT = """LAYOUT:
- Image 1024x1536 portrait. ONE single illustration filling the whole image right to the edges: no card frame, no border, no margin.
- No text anywhere: no name, no title, no number, no banner, no caption, no signature, no watermark."""


def gender_line(women):
    base = "GENDER: every character is an adult MAN"
    if women:
        return base + ", except " + ", ".join(women) + (" (women)" if len(women) > 1 else " (a woman)") + ". Men read as men at a glance —— masculine jaw and brow, thicker neck, broad shoulders, male hairstyles and headwear; no long eyelashes, no blush, no rosy lips, no soft baby face on men."
    return base + ". Men read as men at a glance —— masculine jaw and brow, thicker neck, broad shoulders, male hairstyles and headwear; young men are young MEN, never girls: no long eyelashes, no blush, no rosy lips, no soft baby face."


def sheet_text(key, chunk, ident, roles, hints, sheet_no=0):
    n = len(chunk)
    solo = PER[key] == 1
    unit = "picture" if solo else "panel"
    z0, z1 = (8, 54) if key == 7 else (10, 46) if solo else (8, 47)
    women = [en_head(ident[c["person"]])[0] for c in chunk if is_woman(ident[c["person"]])]
    head = STYLE_LINE[key]
    if not solo:
        cols, rows, land = grid_for(n, PER[key])
        head = ("A sheet of %d Three Kingdoms (late Han dynasty China) characters. " % n + head
                + "\nFORMAT (strict, see LAYOUT): a %s image, %d columns x %d rows of TALL portrait panels separated by light green gaps, a number banner under each panel."
                % ("1536x1024 LANDSCAPE" if land else "1024x1536 PORTRAIT (taller than wide)", cols, rows))
    ref = SOLO_REFERENCE if solo else REFERENCE
    if key in REALISM:
        ref += "\n" + REALISM[key]
    parts = [head, "", ref, "", RANK[key], "",
             HEAD_ZONE.format(z0=z0, z1=z1, unit=unit, side=12 if key == "kiin" else 8), "", DISTINCT, gender_line(women), "",
             SOLO_LAYOUT if solo else layout(n, PER[key]), "", "CHARACTERS"]
    comps = immortal_comps(chunk, ident, sheet_no) if key == 7 else [None] * n
    ents = [entry(i + 1, c["person"], ident[c["person"]], key, roles, hints, comps[i]) for i, c in enumerate(chunk)]
    text = "\n".join(parts) + "\n" + "\n".join(ents) + "\n"
    if solo and key == 7:
        text = (text.replace("every panel must obey all of these", "obey all of these").replace("Every panel on the sheet uses the SAME style.", "")
                .replace("so that the panels differ in color at a glance", "so that the generals differ in color at a glance")
                .replace("Each panel has a different place behind the person.", "").replace("; at most ONE open-mouthed shout on the whole sheet", "").replace("the panel", "the picture"))
    return text


def interleave(groups):
    """그룹별 목록을 번갈아 한 줄로 —— 한 장 안에 같은 세력 · 같은 역할이 몰리지 않게"""
    out, i = [], 0
    while any(groups):
        for g in groups:
            if i < len(g):
                out.append(g[i])
        i += 1
        if i > 200:
            break
    return out


def ordered(key, cards, roles):
    cards = sorted(cards, key=lambda c: (CLASS_ORDER.index(c["cls"]), c["person"]))
    if key == "kiin":
        by = defaultdict(list)
        for c in cards:
            by[roles[c["person"]]].append(c)
        return interleave([by[r] for r in ROLE_ORDER])
    by = defaultdict(list)
    for c in cards:
        by[c["fac"]].append(c)
    return interleave([by[f] for f in FAC_ORDER])


def reset(d):
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        p = os.path.join(d, f)
        if os.path.isfile(p) and f.endswith(".txt"):
            os.remove(p)


def write_tier(key, cards, ident, roles, hints):
    folder = os.path.join(OUT, DIRS[key])
    reset(folder)
    seq = ordered(key, cards, roles)
    per = PER[key]
    howto = ["%s —— 이름 순서 = 이름표 번호 순서. 시트는 references/등급별_v2_시트/%s/<txt 와 같은 이름>.png 로 두고 D:\\Sol 에서" % (LABEL[key], DIRS[key]),
             "  python -I tools/scripts/slice_tier_v2.py %s   → 잘림/ · 미리보기/ 확인 →   python -I tools/scripts/slice_tier_v2.py %s --apply" % (DIRS[key], DIRS[key]),
             "  다 넣으면 solgukji_godot 에서 Godot --import 한 번. (한 장씩 자를 때는 아래 명령)",
             "먼저 기본 캐릭터(assets/portraits/<인물>.png)가 있어야 한다. 시트마다 참조 이미지를 만들어 프롬프트와 함께 붙여 넣는다.",
             STYLE_REF_NOTE.get(key, ""),
             ""]
    pos, no, total_len = 0, 0, []
    sizes = sizes_for(len(seq), per)
    for n in sizes:
        chunk = seq[pos:pos + n]
        pos += n
        no += 1
        text = sheet_text(key, chunk, ident, roles, hints, no)
        if PER[key] == 1:
            fname = "%02d_%s.txt" % (no, chunk[0]["person"])
        elif key == "kiin":
            fname = "%02d_기인_%d명.txt" % (no, n)
        else:
            facs = "_".join(dict.fromkeys(c["fac"] for c in chunk))
            fname = "%02d_%s_%d명.txt" % (no, facs, n)
        open(os.path.join(folder, fname), "w", encoding="utf-8", newline="\n").write(text)
        total_len.append(len(text))
        names = [c["person"] for c in chunk]
        howto.append("[%s]  %s" % (fname, " · ".join("%d %s" % (j + 1, c["name"]) for j, c in enumerate(chunk))))
        howto.append('  참조:   python -I tools/scripts/make_ref_sheet.py "%s" %s/%s' % (",".join(names), folder.replace("\\", "/"), (fname[:-4] + "_base.png") if key == 7 else "참조_%02d.png" % no))
        howto.append('  자르기: python -I tools/scripts/slice_panels.py 시트.png "%s" solgukji_godot/assets/portraits' % ",".join(p + SUFFIX[key] for p in names))
        howto.append("")
    open(os.path.join(folder, "자르기_이름.txt"), "w", encoding="utf-8", newline="\n").write("\n".join(howto))
    print("%s  %d장 · 시트 %d장 (%s명) · 글자 수 %d ~ %d" % (folder, len(seq), len(sizes), "+".join(str(s) for s in sizes), min(total_len), max(total_len)))


def main():
    targets = load_targets()
    roles = load_roles()
    ident = load_identity()
    hints = load_hints()
    # 빠뜨림 점검 —— 표에 없는 인물이 있으면 멈춘다
    for c in targets["kiin"]:
        assert c["person"] in ident, "기본 프롬프트에 없는 인물: " + c["person"]
        assert c["person"] in roles and roles[c["person"]] in ROLE, "passives.json 기인 역할 없음: " + c["person"]
        assert c["person"] in KIIN_PROP, "KIIN_PROP 에 없음: " + c["person"]
    for c in targets[7]:
        assert c["person"] in IMMORTAL_SCENE, "IMMORTAL_SCENE 에 없음: " + c["person"]
    for c in targets[8]:
        assert c["person"] in MYTH, "MYTH 에 없음: " + c["person"]
    for key in (6, 7, 8):
        for c in targets[key]:
            assert c["person"] in ident, "기본 프롬프트에 없는 인물: " + c["person"]
    for key in ("kiin", 6, 7, 8):
        write_tier(key, targets[key], ident, roles, hints)
    miss = [(LABEL[k], c["person"]) for k in (6, 7, 8) for c in targets[k]
            if c["person"] not in hints[k] and not (k == 7 and c["person"] in hints[8])]
    if miss:
        print("장면 힌트가 없는 인물 (프롬프트에서 STORY 줄이 빠진다):", ", ".join("%s %s" % m for m in miss))


main()
