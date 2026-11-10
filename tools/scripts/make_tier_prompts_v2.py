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
PER = {"kiin": 6, 6: 4, 7: 4, 8: 1}            # 한 장 인원 —— 많으면 모델이 인물별 지시를 섞는다. 4~6 이 안전하고 신화는 한 명씩
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
- Nothing important within 8% of the left and right edges or in the bottom 20% (the card cuts those). Plumes and flag tips may rise above the head.
- The face is always clearly lit and never covered by a hand, a weapon, a fan, hair or an effect."""

REFERENCE = """REFERENCE (attached image): a numbered sheet of the BASE chibi designs of these characters —— character #k in the reference = panel #k here.
Keep each PERSON exactly: the same face shape, eyes, brows, nose, mouth, age, facial hair, hairstyle and headwear, skin tone,
body build, cloth colors and signature weapon or item (see each LOOK, FACE, SIGNATURE and COLORS line).
Take NOTHING else from the reference: its small standing pose, flat light and green blot are replaced by the RANK RULES below.
COLORS give the CLOTH and ARMOR colors only (ignore the word \"gold\" there) —— the color of metal trim, the light and the background come from the RANK RULES."""

SOLO_REFERENCE = REFERENCE.replace("a numbered sheet of the BASE chibi designs of these characters —— character #k in the reference = panel #k here.",
                                   "the BASE chibi design of this general (one character).")

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
- PROPORTIONS AND LINE: refined semi-chibi, about 3.5 heads tall, fine clean ink lines, soft cel shading with airy highlights.
- OUTFIT: the base design made noble —— engraved SILVER and white-steel plates, silver filigree, pale silk over the faction-colored cloth
  (the cloth muted and a little desaturated), a white or pale-blue plume or tassels, plain silver clasps. NO GOLD anywhere.
- LIGHT: cold, bright and even, from the upper front-left, a thin white rim, soft pale blue-grey shadows. HIGH-KEY: the whole picture is light.
- COLOR: silver, white and pale sky-blue (#cfe6ff); the faction color only in the cloth. A cool temperature everywhere.
- BACKGROUND: pale blue-white mist fading to white at the bottom, and ONE tall faction war banner (blank cloth in the faction color, no lettering)
  standing far behind on one side, slightly out of focus. Nothing else: no crowd, no dramatic sky.
- EFFECTS: none, except a few tiny silver light motes. No fire, no lightning, no glowing aura.
- EXPRESSION: composed dignity, the eyes level, a restrained look.
- NEVER: gold or orange, fire or lightning, a dark background, a dynamic pose, crowds, a cape blowing in the wind.""",
    7: """RANK: IMMORTAL —— blazing gold.
RANK LOOK IN ONE LINE: blazing, warm and in motion, a golden-hour war portrait with an army behind it. At thumbnail size it must read
"gold, orange, sparks and banners".

RANK RULES (checklist —— every panel must obey all of these):
- CAMERA AND POSE: LOW camera angle, the body turned 3/4 and leaning 15 to 25 degrees on a strong diagonal, CHEST-TO-WAIST crop with the head
  still at the top center. Dynamic: mid-stride or mid-shout, the weapon crossing the picture diagonally, the cape, ribbons and plumes whipping
  across the frame, a little wide-angle foreshortening on the weapon.
- PROPORTIONS AND LINE: polished anime game illustration, about 4 heads tall, dense fine linework, an expressive face.
- OUTFIT: lavish GOLD —— gilded armor plates, gold filigree and embossed dragon / phoenix / tiger motifs, a big flowing cape or sash in a saturated
  version of the faction color lined with red-orange silk, tall feathers or plumes, jeweled clasps.
- LIGHT: strong warm backlight (a low sun behind), a hot orange-gold rim along the hair, shoulder and weapon, the face lit warmly from the front-low side.
- COLOR: gold, amber and orange-red with warm brown shadows, very saturated. A warm temperature everywhere.
- BACKGROUND: a marching army in depth —— a sea of spears and many war banners (blank cloth, no lettering) rising toward a blazing orange sunset sky
  with smoke; the army fills the lower background and recedes into haze. The STORY DETAIL of each character appears small in that background.
- EFFECTS: drifting embers and sparks, golden dust, trailing ribbons; fire only as sparks and small flames in the background. No lightning.
- EXPRESSION: bold and charismatic —— a battle cry or a fierce grin.
- NEVER: silver-blue or cold light, an empty misty backdrop, a still symmetrical pose, a black background, a close-up face filling the picture.""",
    8: """RANK: MYTHIC —— a killing stare out of the dark.
RANK LOOK IN ONE LINE: a near-black picture with ONE hot color and ONE legendary effect, the eyes the brightest point. At thumbnail size it must read
"black, with crimson / white-hot / violet fire or lightning". One look should make the viewer feel this person is about to KILL THEM.

RANK RULES (checklist —— obey all of these):
- FRAMING: a tight BUST in realistic-leaning anime proportions (NOT chibi, about 7.5 heads tall). The head is about 35 to 40% of the picture height:
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
- NEVER: chibi, a bright or pastel background, crowds, mist, a silver-blue palette, a gold-orange sunset palette, jade, a card frame or border.""",
}

STYLE_LINE = {
    "kiin": "Calm flat SD role-card illustrations for a mobile card game (the KIIN cards: one irreplaceable role per card).",
    6: "Refined, cold, silver TRANSCENDENT card illustrations for a mobile card game.",
    7: "Blazing, golden, dynamic IMMORTAL card illustrations for a mobile card game.",
    8: "ONE MYTHIC card illustration of a single Three Kingdoms general for a mobile card game —— the rarest, most intimidating art in the game.",
}

MOUNT_RULE = {
    "kiin": "waist-up rider on a calm standing horse; the horse's head and neck form a quiet base at the bottom (chibi, not rearing).",
    6: "rider chest-to-waist facing nearly front; the horse's armored head and neck rise from the bottom edge in front of him, standing calmly.",
    7: "rider and horse together in a diagonal charge, the horse rearing or at full gallop with its chest and head big in the lower half; the rider's face stays at the top center, the cape streaming.",
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


def entry(i, person, ent, key, roles, hints):
    lines = identity_lines(i, ent, key, solo=(key == 8))
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
            lines.append("   STORY DETAIL (small, in the army background; ignore any lightning, aura or spirit beast in it —— the rank rules win): " + story)
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


def sheet_text(key, chunk, ident, roles, hints):
    n = len(chunk)
    solo = key == 8
    unit = "picture" if solo else "panel"
    z0, z1 = (10, 46) if solo else (8, 47)
    women = [en_head(ident[c["person"]])[0] for c in chunk if is_woman(ident[c["person"]])]
    head = STYLE_LINE[key]
    if not solo:
        head = "A sheet of %d Three Kingdoms (late Han dynasty China) characters. " % n + head
    parts = [head, "", SOLO_REFERENCE if solo else REFERENCE, "", RANK[key], "",
             HEAD_ZONE.format(z0=z0, z1=z1, unit=unit), "", DISTINCT, gender_line(women), "",
             SOLO_LAYOUT if solo else layout(n, PER[key]), "", "CHARACTERS"]
    ents = [entry(i + 1, c["person"], ident[c["person"]], key, roles, hints) for i, c in enumerate(chunk)]
    return "\n".join(parts) + "\n" + "\n".join(ents) + "\n"


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
             ""]
    pos, no, total_len = 0, 0, []
    sizes = sizes_for(len(seq), per)
    for n in sizes:
        chunk = seq[pos:pos + n]
        pos += n
        no += 1
        text = sheet_text(key, chunk, ident, roles, hints)
        if key == 8:
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
        howto.append('  참조:   python -I tools/scripts/make_ref_sheet.py "%s" %s/참조_%02d.png' % (",".join(names), folder.replace("\\", "/"), no))
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
