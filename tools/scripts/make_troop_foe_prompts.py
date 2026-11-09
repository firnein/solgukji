"""기본패 병졸 카드 8종 + 토벌 전용 적 55장의 카드 초상 프롬프트 (11/9 사용자: 미비 일러스트).

실행: python -I tools/scripts/make_troop_foe_prompts.py
  → prompts/기본패/   병졸 카드 8종 (창병 · 기병 · 궁병 · 도적 · 책사 · 모사 · 술사 · 유생) —— 시트 2장 (4명씩, 2x2)
  → prompts/토벌적/   토벌 적 55장 (kind "foe", id y10~y79) —— 시트 11장 (5명씩 5x1: 창병 · 기병 · 궁병 · 도적 · 술사)
       01~07  1~7등급 일반 (id y<등급>0~4)        08~11  4~7등급 정예 (id y<등급>5~9)
  각 폴더의 자르기_이름.txt —— 시트 → 파일 이름 대응. 자르기: python -I tools/scripts/slice_cards.py 기본패|토벌적 [--apply]

카드 이름 · 병종 · 등급은 solgukji_godot/data/cards_ext.json 의 foe 카드에서 읽는다 (foe_cards.py 가 만든다) —— 손으로 옮기지 않는다.
카드마다 그림 설명(DESIGN · FACE · SIGNATURE)은 아래 FOE 표에 id 로 적는다. 표에 없는 id 가 있거나 표에만 있는 id 가 있으면 멈춘다
(카드가 늘면 foe_cards.py 를 돌린 뒤 이 표에 한 줄을 더하고 다시 실행).
화풍은 prompts/등급별/1_기본 (SD 치비 전신 · 초록 번짐 · 번호 이름표) 과 같고, 병종 차림은 prompts/병사_스프라이트 와 어긋나지 않게 맞췄다.
"""
import json
import os

D = json.load(open("solgukji_godot/data/game.json", encoding="utf-8"))
E = json.load(open("solgukji_godot/data/cards_ext.json", encoding="utf-8"))
CARDS = {c[0]: c for c in D["CARDDEF"] + E["cards"]}          # [id, name, tier, tag, fac, ... , kind(13)]
CLASS_EN = {"창병": "SPEARMAN", "기병": "CAVALRY", "궁병": "ARCHER", "도적": "ROGUE", "술사": "SORCERER",
            "책사": "STRATEGIST", "모사": "SCHEMER", "유생": "SCHOLAR"}
MAX_SIDE = {"기본패": 640, "토벌적": 512}                     # 잘린 그림 한 변 상한 (px) —— 휴대폰 용량. 기존 장수 초상은 550~750
TAGS = ["창병", "기병", "궁병", "도적", "술사"]               # foe_cards.py 의 슬롯 순서 —— 한 시트의 1~5번

LAYOUT = """LAYOUT:
- Image {size}. ALWAYS a fixed grid of {cols} columns x {rows} rows = {n} equal slots, reading order left to right, top to bottom.
- Natural proportions in every slot: never stretch, squash or shorten a character to fit the slot; leave empty background instead.
- Characters 1 to {n} fill the {n} slots in order.
- Flat light green paper background (#9BCF88) over the whole sheet. Wide even gaps between panels; nothing crosses into a neighbor.
- Under each panel a dark green brush-stroke banner with ONLY its number (1 to {n}) in big white digits.
- No other text anywhere: no names, no ids, no titles, no captions, no signature, no watermark. Do not draw the line labels as text."""

STYLE = """STYLE:
- Cute SD chibi, about 2.5 heads tall: big head, small body, short limbs, FULL BODY from head to feet, standing on the ground.
- Clean dark-brown ink outlines, flat soft colors with simple two-tone cel shading, light paper texture. Gentle and readable,
  like a hand-drawn sticker. Not glossy, not painterly, not detailed. (Same hand as our Three Kingdoms general portraits.)
- Small calm-to-lively poses: standing, holding the weapon or item, a slight turn or a small gesture.
- Each character stands on a soft round blot of darker green watercolor (its panel), slightly bigger than the character.
  The blot is the only background: no scenery, no ground details, no props besides the character's own items.
- CAVALRY are ALWAYS on horseback (see MOUNTED), never on foot. Their panel may be a little wider.
- NO GREEN on the characters themselves (no green cloth, trims or items) —— green is the background and gets erased by the cutting tool.
- All characters are adult MEN (or monsters). No famous generals' features: these are nameless soldiers."""

DISTINCT = """EVERY CHARACTER LOOKS DIFFERENT: on one sheet no two characters share the same headgear, hairstyle or facial hair ——
follow each SIGNATURE line exactly (HEAD, FACIAL HAIR, MARK). Draw each FACE exactly and exaggerate it a little, like a caricature
(face shape, eyes, brows, nose, mouth, age). Follow BUILD. No same-face syndrome, no generic cute face.
Only characters with a MOUNTED line ride a horse; everyone else is ON FOOT."""


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8", newline="\n").write(text.rstrip("\n") + "\n")


# ════════════════════ 기본패 (병졸 카드 8종) ════════════════════
# (병종, DESIGN, FACE, BUILD, HEAD, FACIAL HAIR, MARK, MOUNTED 또는 None)
BASIC = {
    "창병": ("an anonymous foot soldier of the spear corps: round iron helmet with a small red horsehair tassel, dull iron lamellar vest over a padded "
             "coat, dark trousers, leather boots, a LONG spear (about twice his height) held upright with both hands, a small oval wooden shield on the left arm",
             "plain honest round face, small steady eyes, short thick eyebrows, snub nose, closed firm mouth, tanned skin",
             "sturdy, solid, medium height",
             "round iron helmet with a small red horsehair tassel", "clean-shaven",
             "very long spear taller than twice his height, small oval shield on the left arm", None),
    "기병": ("an anonymous cavalry trooper: round iron helmet with a small tassel, lamellar vest, boots in the stirrups, a long lance held upright "
             "in one hand, riding a brown war horse",
             "lean weathered face, sharp narrow eyes, straight nose, a small confident smile, windburned cheeks",
             "athletic rider build",
             "round iron helmet with a small tassel and cheek flaps", "faint stubble on the chin",
             "long lance with a small pennant, brown war horse with a plain saddle blanket",
             "riding a brown war horse —— a small chubby chibi horse, rider AND whole horse visible from ears to hooves, both standing on the blot."),
    "궁병": ("an anonymous archer: soft leather cap with a cloth headband, light padded coat, leather belt, a quiver of arrows on his back, boots, "
             "a recurve bow held lowered in the left hand and one arrow in the right",
             "narrow alert face, keen slightly squinting eyes, thin straight nose, relaxed half-smile, sun-browned skin",
             "lean archer build, a bit tall",
             "soft leather cap with a cloth headband", "thin short mustache",
             "recurve bow, quiver of arrows with feathered ends over the shoulder", None),
    "도적": ("an anonymous bandit-raider: dark hood and a cloth face mask covering mouth and nose, eyes visible, light dark-grey clothes, leather "
             "bracers, soft boots, a single broad curved saber (dao) in the right hand and a short dagger tucked in the belt, crouched and ready",
             "only the eyes show: narrow wary eyes with thin eyebrows, a small scar across one brow, tanned skin",
             "lean, agile, slightly crouched",
             "dark hood pulled low", "hidden behind the cloth mask",
             "face mask, curved dao saber in hand, dagger in the belt, leather arm bracers", None),
    "책사": ("an anonymous staff officer: wide-sleeved scholar robe reaching the ground, cloth belt, a tall black official cap, a white feather "
             "fan held in the right hand at the chest",
             "slim calm face, long narrow eyes, high forehead, composed small smile, pale skin",
             "slim, upright, medium height",
             "tall black official cap", "small neat mustache",
             "white feather fan, wide sleeves, long robe to the ground", None),
    "모사": ("an anonymous court plotter: dark-trimmed robe with a short cape over the shoulders, a small black court cap, a rolled paper scroll "
             "in the right hand held to the chest, glancing sideways",
             "sly face, narrow sideways-glancing eyes, thin arched eyebrows, small crooked smirk, pale skin",
             "slim, a little stooped",
             "small black court cap", "small pointed goatee",
             "short shoulder cape, rolled paper scroll held to the chest", None),
    "술사": ("an anonymous Taoist mystic: loose plain robe, a dark pointed hood, a cord belt with a small gourd, bare ankles and straw sandals, "
             "a tall wooden staff with a small glowing-orange orb on top in the right hand and a yellowed talisman paper held up in the left hand",
             "thin old face, deep-set calm eyes with long drooping eyebrows, hollow cheeks, faint knowing smile, ruddy skin",
             "thin and slightly hunched",
             "dark pointed hood", "thin long grey beard",
             "tall staff with an orange orb (orange, not magenta), talisman paper in the other hand, gourd on the belt", None),
    "유생": ("an anonymous Confucian student: long plain robe, cloth belt, a soft black scholar cap, a bamboo scroll held open in both hands, "
             "reciting with his mouth slightly open",
             "young smooth earnest face, round bright eyes, soft eyebrows, small nose, clean skin",
             "young and slim, a little short",
             "soft black scholar cap", "clean-shaven",
             "open bamboo scroll in both hands, plain long robe", None),
}
BASIC_SHEETS = [("01_군사_4명.txt", ["창병", "기병", "궁병", "도적"]), ("02_문관_4명.txt", ["책사", "모사", "술사", "유생"])]
BASIC_COLORS = "natural dull colors only: iron grey, leather brown, undyed cloth, dark navy or maroon cloth, skin. A different main cloth color for each character on the sheet."

BASIC_HEAD = """A character design sheet of {n} nameless "rank-and-file" soldiers of the Three Kingdoms era (late Han dynasty China) for a mobile
card game. They are the plain starter cards, drawn the same way as our general portraits but ANONYMOUS: ordinary faces, no famous features.
Each one is the clear, simple, instantly readable picture of its TROOP TYPE; it must match the soldier sprites of the same type
(same helmet, weapon and clothes as described).

{style}

OUTFIT LEVEL (BASE): plain practical clothes and simple gear, no gold ornaments, no capes (unless named), no glowing effects
(except the small orange orb of the Taoist's staff). Colors: {colors}

{distinct}

{layout}

CHARACTERS
"""


def basic_sheet(fname, tags):
    out = [BASIC_HEAD.format(n=len(tags), style=STYLE, colors=BASIC_COLORS, distinct=DISTINCT,
                             layout=LAYOUT.format(size="1536x1024 landscape", cols=2, rows=2, n=len(tags)))]
    for i, t in enumerate(tags, 1):
        des, face, build, head, hair, mark, mount = BASIC[t]
        out.append("%d. Nameless %s  [%s, card troop \"%s\"]" % (i, CLASS_EN[t].title(), CLASS_EN[t], t))
        out.append("   DESIGN: " + des + ".")
        out.append("   FACE: " + face + ".")
        out.append("   BUILD: " + build + ".")
        out.append("   SIGNATURE (unique on this sheet): HEAD %s; FACIAL HAIR %s; MARK %s." % (head, hair, mark))
        out.append("   COLORS: " + BASIC_COLORS)
        if mount:
            out.append("   MOUNTED: " + mount)
    write("prompts/기본패/" + fname, "\n".join(out))


def basic_howto():
    s = ["기본패 병졸 카드 8종 —— 이름 순서 = 이름표 번호 순서. 시트는 references/기본패_시트/<txt 와 같은 이름>.png 로 두고 D:\\Sol 에서",
         "  python -I tools/scripts/slice_cards.py 기본패   → references/기본패_시트/잘림/ · 미리보기/ 확인 →   python -I tools/scripts/slice_cards.py 기본패 --apply",
         "  (--apply 는 solgukji_godot/assets/troops/<병종>.png 로 복사한다. 폴더가 없으면 만든다.) 한 장씩 자를 때는 아래 명령.",
         "  자를 때 한 변 %d px 로 줄인다 (--max). 크기를 바꾸려면 make_troop_foe_prompts.py 의 MAX_SIDE 를 고치고 다시 실행." % MAX_SIDE["기본패"],
         ""]
    for fname, tags in BASIC_SHEETS:
        s.append("[%s]  %s" % (fname, " · ".join("%d %s" % (i, t) for i, t in enumerate(tags, 1))))
        s.append('  자르기: python -I tools/scripts/slice_sheet.py 시트.png "%s" solgukji_godot/assets/troops --hole=155 --max=%d' % (",".join(tags), MAX_SIDE["기본패"]))
        s.append("")
    write("prompts/기본패/자르기_이름.txt", "\n".join(s))


# ════════════════════ 토벌 적 55장 ════════════════════
# 등급이 오를수록 세력 느낌이 커진다 —— 황건 (노란 두건 · 누런 천 · 조잡한 무기) → 갑옷 · 부적 · 귀기 (황천)
LEVEL = {
    1: ("RABBLE", "ragged peasant rebels",
        "undyed hemp rags and patched brown tunics, a plain yellow cloth strip tied on the head or arm as the ONLY uniform, bare feet or straw sandals, "
        "farm tools and sharpened bamboo as weapons, NO armor, NO metal helmets. Thin, hungry, scared-but-shouting.",
        "undyed hemp, dirty brown, faded yellow cloth", "scrawny and small, a bit smaller than a trained soldier"),
    2: ("MILITIA", "rough Yellow Turban militia",
        "yellow headband and rough yellow-dyed tunic, scraps of leather or straw armor, a crude wooden shield, cheap iron weapon tips, patched cloth. "
        "Still clearly peasants, but now organized.",
        "yellow-dyed cloth, brown leather, plank wood, dull cheap iron", "ordinary build"),
    3: ("VETERAN", "veteran rebels and small captains",
        "yellow headscarf over a crude patchwork leather-and-iron vest, a simple iron cap wrapped in yellow cloth, proper weapons, a small talisman paper "
        "strip tied on the clothes. Tougher and cleaner than level 2, and some of them are bigger brutes.",
        "yellow cloth, dull iron, leather, a touch of dark brown", "sturdy, broader than level 2"),
    4: ("ARMY", "the organized rebel army",
        "yellow-dyed cloth over REAL lamellar armor, iron helmets with a yellow cloth crest, talisman paper tags on the armor, banner poles on the back. "
        "Black Mountain bandits (Heishan) wear black fur and dark leather instead of yellow; White Wave bandits (Baipo) wear white and pale grey.",
        "yellow and iron grey; black fur for Heishan; white for Baipo", "solid soldier build"),
    5: ("HEAVY", "heavy troops of the cult and the bandit kings",
        "heavy thick armor with shoulder guards, yellow cloaks and mantles, painted yellow face markings (Taiping sigils), many talismans, tall banners. "
        "The first hint of the uncanny: a talisman that glows faintly yellow.",
        "deep yellow-gold, dark iron, black leather, bone", "big and broad"),
    6: ("UNDERWORLD", "Yellow Springs (the underworld) spirit warriors",
        "UNCANNY: pale ashen skin with dark cracks, blackened iron armor with yellow-gold sigils glowing through the seams, hollow glowing yellow eyes, "
        "small flat yellow spirit-flame wisps, long tattered yellow sashes floating, skull and bone ornaments. Scary, but still a cute flat-colored chibi.",
        "blackened iron, ash grey, ochre yellow glow", "very large and heavy, clearly bigger than level 5"),
    7: ("DEMON GENERAL", "underworld demon generals and Taiping sages",
        "GRAND AND TERRIFYING: giant looming figures, much bigger than anything else on the sheet, ornate gold-and-black armor, horned or winged helmets or "
        "demon-face breastplates, spirit-flame aura, floating talisman discs behind them like a halo. Still a flat-colored sticker-style chibi, never realistic.",
        "gold and black, bright yellow flame, ash grey", "giant, the tallest and widest figure on any sheet"),
}

# id → (DESIGN, FACE, HEAD, FACIAL HAIR, MARK, BUILD [, HORSE])   ——  이름 · 병종 · 등급은 cards_ext.json 에서 읽는다
FOE = {
    # ── 1등급 ──
    "y10": ("a scrawny peasant rebel drafted into the Yellow Turban uprising, holding a sharpened bamboo pole spear in both hands, ragged brown hemp tunic, bare feet in straw sandals, no armor, no shield, scared and shouting",
            "thin sunburnt face, wide scared round eyes, big open shouting mouth, big ears, patchy cheeks",
            "plain yellow cloth strip tied round the forehead over messy sticking-up hair", "bare chin with a few patchy hairs",
            "sharpened bamboo spear, ragged hemp tunic with one torn sleeve", "thin, small and bony", None),
    "y11": ("a peasant rider bareback on a scrawny plow horse with a rope halter, a wooden pole with an iron point tied on as a spear, yellow cloth strip round his head, ragged tunic",
            "round freckled face, buck teeth, nervous grin, small eyes",
            "yellow headband plus a straw hat hanging down his back", "no beard",
            "a patched yellow rag tied to the spear pole as a flag, rope halter", "small and skinny",
            "a skinny dun plow horse with visible ribs and a rope halter, no saddle"),
    "y12": ("a poor hunter-turned-rebel with a short plain wooden hunting bow, a few arrows stuffed in a straw quiver on his hip, a yellow armband, a vest of animal skin over a ragged shirt",
            "narrow squinting eyes, long thin nose, scraggly sideburns, one eye shut as if aiming",
            "bare head, messy hair tied in a short topknot with a yellow rag", "sparse tuft on the chin",
            "short wooden hunting bow, straw quiver on the hip, animal-skin vest", "thin and wiry", None),
    "y13": ("a village ruffian following the rebels, a yellow rag tied over his nose and mouth as a mask, a rusty kitchen cleaver in one hand and a stolen sack over the shoulder, crouched and grinning",
            "narrow cunning eyes above the mask, a scar through one thin eyebrow",
            "crooked dirty yellow headcloth knotted at the back", "hidden behind the yellow rag mask",
            "rusty cleaver, sack over the shoulder, yellow rag mask", "small and hunched", None),
    "y14": ("a devout lay follower of the Taiping Way: barefoot in a plain hemp robe, eyes shut in prayer, a yellow talisman paper held up in the left hand, a crooked wooden walking staff with a yellow rag tied on in the right hand, a string of wooden beads",
            "round soft face, eyes closed in rapture, serene happy smile",
            "yellow headband with a single red ink dot in the middle", "bare chin",
            "paper talisman held up, crooked staff with a yellow rag, bead string", "small and plump", None),
    # ── 2등급 ──
    "y20": ("a rebel spearman of the yellow militia: long spear with a crude iron head, a small round plank shield painted with a yellow circle on the left arm, yellow-dyed tunic with a rough leather chest guard",
            "broad flat face, small determined eyes, thick eyebrows, set jaw",
            "yellow headband tied with long tails over a messy topknot", "short stubble",
            "plank shield with a yellow circle, long spear, leather chest guard", "stocky", None),
    "y21": ("a yellow militia rider on a lean brown horse with a cheap saddle, holding a spear with an iron head and a yellow pennant, a yellow cloth sash across the chest",
            "square tanned face, stubble, narrow eyes, confident smirk",
            "round leather cap with a yellow band", "short stubble",
            "yellow sash across the chest, spear with a yellow pennant", "wiry rider",
            "a lean chestnut horse with a cheap leather saddle and a yellow saddle cloth"),
    "y22": ("a yellow militia archer: quiver of arrows on his back, a simple recurve bow drawn, a yellow-dyed padded jerkin, a leather bracer on the left arm",
            "long face, sharp nose, keen narrow eyes, thin lips",
            "yellow headband tied under a wide-brim straw hat", "thin long mustache",
            "recurve bow drawn, quiver of arrows, leather arm bracer", "lean and tall", None),
    "y23": ("a yellow militia ruffian with a bare scarred shoulder, a short dao saber in hand and a dagger in the belt, a yellow neckerchief pulled up over his nose",
            "heavy brow, crooked broken nose, sneering grin missing a tooth",
            "shaved head with a yellow headband", "bristly stubble beard below the neckerchief",
            "dao saber, dagger at the belt, scarred bare shoulder", "stocky and slouching", None),
    "y24": ("a Taiping Way talisman-maker in a yellow hemp robe, holding up a long yellow talisman paper with red scribbles in one hand and a short wooden staff in the other, a bundle of talisman strips at the belt",
            "thin face, drooping eyes, long sad eyebrows",
            "short cone-shaped yellow cloth cap", "thin wispy mustache and goatee",
            "long talisman paper with red scribbles, bundle of strips at the belt", "thin", None),
    # ── 3등급 ──
    "y30": ("a Yellow Turban spear captain: crude patchwork leather-and-iron vest, an iron skullcap wrapped in yellow cloth, a proper iron-headed spear with a small yellow pennant, a round iron-studded shield",
            "hard weathered face, deep frown, heavy jaw, a scar over one cheek",
            "iron skullcap wrapped in yellow cloth with tails hanging behind", "thick short black beard",
            "spear with a yellow pennant, iron-studded round shield", "broad and sturdy", None),
    "y31": ("a Yellow Turban horse-bandit raider: fur-trimmed leather vest, a yellow cloth wrapped as a high turban, a curved saber raised, loot bundles and a stolen bell tied on the saddle",
            "lean sun-darkened face, hooked nose, wild grin",
            "yellow turban wrapped high with a tail flying", "thin drooping mustache",
            "curved saber raised, loot bundles and a bell on the saddle", "lean and wild",
            "a dark brown horse with a mismatched stolen saddle and yellow tassels"),
    "y32": ("a Yellow Turban archer captain: leather-and-iron vest, a yellow-wrapped iron cap with a short feather, a strong recurve bow and a full quiver, a talisman strip tied to the sleeve",
            "narrow cold eyes, sharp cheekbones, expressionless",
            "iron cap wrapped in yellow cloth with a short feather", "long thin goatee",
            "big recurve bow, full quiver with yellow-fletched arrows, talisman strip on the sleeve", "tall and lean", None),
    "y33": ("a Yellow Turban brute (the strongman of the band): bare muscular upper body with a yellow sash across it, an enormous broad-bladed cleaver on the shoulder, iron wrist bands",
            "huge square jaw, small beady eyes, thick neck, wide grin",
            "bald head with a yellow headband and a tattooed sun disc on the scalp", "none, bare chin",
            "massive cleaver, iron wristbands, yellow sash across the bare chest", "huge, thick and tall for this sheet", None),
    "y34": ("a Taiping Way libation priest in a yellow robe with a black sash, holding a staff topped by a small bronze bell in one hand and a bowl of 'holy water' in the other, talisman strips tied to the staff",
            "calm round face, half-lidded eyes, small smile, plump cheeks",
            "yellow cloth hood with a small round paper talisman stuck on the forehead", "short grey goatee",
            "bell staff, holy water bowl, fluttering talisman strips", "plump", None),
    # ── 4등급 ──
    "y40": ("a Yellow Turban small-banner leader: yellow-dyed lamellar armor over a yellow tunic, an iron helmet with a short yellow cloth crest, a long iron-bladed spear, a small yellow banner on a pole tied to his back, talisman tags on the chest plate",
            "disciplined stern face, firm mouth, thin eyebrows, clear eyes",
            "iron helmet with a short yellow cloth crest", "short trimmed mustache",
            "yellow banner pole on the back, spear, talisman tags on the chest", "tall and upright", None),
    "y41": ("a Yellow Turban iron cavalryman on a horse armored with iron barding on head and chest under a yellow caparison, yellow lamellar armor, an iron helmet with a yellow plume, a long lance",
            "broad stern face, thick dark brows, steady eyes",
            "iron helmet with a yellow horsehair plume and a face guard", "none, clean-shaven",
            "lance with a yellow pennant, horse barding with yellow cloth", "broad rider",
            "a black horse in iron barding with a yellow cloth caparison"),
    "y42": ("a Yellow Turban master archer: light yellow lamellar vest, a yellow cloth hood tied under the chin with a small iron cap on top, a long composite bow with an arrow nocked, a quiver with yellow-fletched arrows, a thumb ring",
            "calm sharp eyes with a catchlight, small smile, high cheekbones",
            "yellow cloth hood tied under the chin with an iron cap on top", "thin long mustache",
            "long composite bow, thumb ring, yellow-fletched arrows", "slim and graceful", None),
    "y43": ("a Black Mountain bandit chief: black wolf-fur mantle over dark leather armor, two short curved sabers crossed at the chest, a bone-and-tooth necklace. NO yellow on him: black, dark brown and bone only",
            "wild scarred face with a long scar from brow to cheek, fierce glare, bared teeth",
            "black bandana with a wolf tail hanging from it", "wild bushy black beard",
            "wolf-fur mantle, two short sabers, bone necklace", "big, hunched and wolfish", None),
    "y44": ("a Taiping Way chief libation priest: a long yellow robe with a black-trimmed cape and a wide sash covered in talisman paper, holding a staff topped by a bronze ring with small bells and a talisman in the other hand, a small flat talisman floating beside him",
            "serene stern face, narrow raised eyes, long nose",
            "tall yellow ceremonial cap with a black rim", "long thin grey beard",
            "ring-and-bells staff, talisman fluttering beside him, talisman-covered sash", "tall and thin", None),
    # ── 5등급 ──
    "y50": ("a Yellow Turban great-banner leader: thick yellow-dyed lamellar armor with big shoulder guards, an iron helmet with a tall yellow crest, a long yellow cloak, a long halberd with a crescent blade, a large rectangular shield painted with a yellow Taiping sun sigil",
            "grim heavy face, thick brows, set jaw, bristling look",
            "iron helmet with a tall yellow crest and a neck guard", "thick black square beard",
            "tall yellow cloak, sigil shield, crescent-blade halberd", "big and broad", None),
    "y51": ("a Yellow Turban fierce rider on a horse in iron barding with a horned chamfron, yellow-gold lamellar armor, a yellow cape flying, a long lance, yellow sigil lines painted on the cheeks",
            "fierce glaring eyes, painted yellow sigil lines on the cheeks, snarling mouth",
            "iron helmet with two long yellow cloth streamers", "none, clean-shaven",
            "lance, flying yellow cape, horse with a tall horn on its armored head", "broad and fierce",
            "a dark grey warhorse in iron barding with a spiked horn on the head and a yellow caparison with a sigil"),
    "y52": ("a Yellow Turban archer commander: heavy yellow lamellar armor with a yellow cape, a big bow and quiver, and across the chest a bandolier of talisman arrows with paper tags that glow faintly yellow (flat color, no gradient)",
            "stern long face, deep lines beside the mouth, one raised brow",
            "iron helmet with yellow cloth flaps and a talisman paper tucked in the band", "long grey mustache",
            "bandolier of talisman arrows, big bow, yellow cape", "tall and heavy", None),
    "y53": ("the Black Mountain great chief: black iron armor plates over a bear-fur cloak, a skull-decorated shoulder guard, a huge broad-bladed saber held on the shoulder, bone and tooth necklaces. NO yellow on him: black, dark brown, bone",
            "brutal scarred face, flat broken nose, small black eyes, snarl",
            "black iron skullcap ringed with bear claws", "huge bushy black beard braided with bones",
            "bear-fur cloak, skull shoulder guard, huge broad saber", "huge and bulky", None),
    "y54": ("a Taiping Way alchemist-sorcerer: a yellow and black robe with a high collar, a peach-wood staff in one hand, flicking a burning talisman with the other, small flat yellow spirit flames orbiting him, an elixir gourd at the hip",
            "angular face, arched thin eyebrows, uncanny smile",
            "yellow hat with a tall peak and a small yin-yang disc", "long thin black goatee",
            "burning talisman, peach-wood staff, elixir gourd", "tall and slender", None),
    # ── 6등급 ──
    "y60": ("an underworld strongman captain: pale ashen skin with dark cracks, heavy blackened iron armor with yellow-gold sigils glowing through the seams, small yellow spirit flames burning on the shoulders, a long spear with a skull ornament, tattered yellow sashes floating",
            "hollow glowing yellow eyes with no pupils, grim bare-teeth grin, ashen skin",
            "iron helmet with a flame-shaped crest of yellow cloth", "none",
            "glowing sigil seams, skull-decorated spear, small spirit flames at the shoulders", "very big and broad", None),
    "y61": ("an underworld cavalry commander on a gaunt black warhorse with glowing yellow eyes and a mane of flat yellow flame, blackened iron armor with gold sigils, a long tattered yellow cloak streaming, a lance with a yellow flame pennant",
            "ashen face, hollow glowing eyes, long fangs",
            "iron helm with a tall crest of yellow flame cloth", "none",
            "flame-maned horse, tattered cloak, lance with a flame pennant", "tall rider",
            "a gaunt black horse with glowing yellow eyes, flat yellow flames for mane and tail, iron barding with sigils"),
    "y62": ("an underworld archer commander in a long tattered yellow-brown hooded cloak, ashen skin, a bow of dark wood and bone with a glowing yellow string, an arrow of yellow flame nocked, a quiver of bone arrows",
            "sunken hollow glowing eyes, long hooked nose, grim set mouth",
            "deep hood with a half skull-mask pushed up on the forehead", "none visible",
            "bone bow with a glowing string, flame arrow, cloak tatters", "tall and gaunt", None),
    "y63": ("an underworld yaksha demon-bandit: ash-grey skin, small horns on the forehead, a tattered yellow loincloth over black leather armor, two curved short blades trailing yellow flame, crouched in a predator pose, wild hair",
            "yellow glowing slit eyes, sharp fangs in a wide grin, pointed ears",
            "two short curved horns in wild flame-like grey hair", "no beard",
            "twin curved blades with yellow flame, tattered sashes", "lean, long-limbed, crouching", None),
    "y64": ("a Taiping Way grand mystic: a long yellow robe embroidered with black sigils, a high yellow-and-black crown hat with hanging bead strings, a tall staff with a floating yellow orb, a ring of floating talisman papers circling him, glowing eyes",
            "pale solemn face, glowing yellow eyes, serene",
            "tall yellow-and-black crown hat with hanging bead strings", "long thin white beard",
            "floating orb staff, ring of orbiting talismans, glowing sigil robe", "tall and thin", None),
    # ── 7등급 ──
    "y70": ("an underworld divine general, a GIANT in gold-and-black ornate heavy armor with a demon-face breastplate, a towering horned helmet, a huge halberd, hovering yellow spirit flames, floating talisman discs behind his back like a halo",
            "stern hollow-eyed ashen face with glowing yellow eyes, thunder-god fierce, fangs",
            "horned golden helmet with a tall flame crest", "none",
            "demon-face breastplate, huge halberd, halo of talisman discs", "giant, taller than every other figure on the sheet", None),
    "y71": ("an underworld divine cavalry general on a giant armored horse with horns and flaming hooves, gold-and-black demon armor, a wide tattered banner of yellow flame, a burning lance",
            "half of the face is a gold demon mask, the other half ashen with one glowing eye",
            "winged golden helmet with long yellow streamers", "none",
            "flaming hooves, burning lance, half gold demon mask", "giant rider",
            "a giant black horse in gold-and-black demon barding, horned, flaming hooves, a halo of floating talisman discs"),
    "y72": ("an underworld divine archer general, gold-and-black armor with long flowing sleeves, a giant bow shaped like a pair of horns, an arrow of golden yellow flame nocked, a ring of floating bone arrows around him",
            "calm cold ashen face, glowing eyes, sharp chin, eerie smile",
            "tall gold crown with a flame jewel and a black veil", "none",
            "giant horn-shaped bow, flame arrow, ring of floating arrows", "very tall and slender", None),
    "y73": ("the underworld ghost king, a huge demon-king in a black-and-gold robe-armor, a crown of horns, a floating ring of skulls and talisman discs, two huge cleaving sabers wreathed in yellow spirit fire, a ghostly flaming aura trailing behind",
            "terrifying grin with big fangs, glowing slit eyes, ashen skin",
            "horned crown with hanging beads over long wild flaming hair", "none",
            "two huge flaming sabers, ring of skulls, black-and-gold robe-armor", "giant and wide", None),
    "y74": ("a Taiping Way heavenly master: a long flowing yellow-and-white robe with giant gold sigils and wide floating sleeves, a tall golden crown-hat, one hand raised holding a glowing talisman, a huge golden sun-disc halo behind the head, a ring of floating talismans, hovering a little above the ground",
            "serene wise old face, eyes shut, a glowing yellow dot on the forehead",
            "tall golden crown-hat with a sun disc", "long thin white beard",
            "sun-disc halo, ring of floating talismans, hovers above the ground", "tall and majestic", None),
    # ── 정예: 4등급 ──
    "y45": ("a Yellow Turban shield captain crouched behind a huge rectangular wooden tower shield painted with a yellow sun sigil and studded with iron nails, a short spear sticking out over its top, lamellar armor",
            "determined face, teeth gritted, eyes glaring over the shield rim",
            "iron helmet with a yellow cloth neck flap", "thick black mustache",
            "man-tall painted tower shield, short spear over its top", "stocky, crouched", None),
    "y46": ("a Black Mountain bandit charge rider on a shaggy dark horse, black leather armor with a fur collar, a heavy long spear, black-and-red tassels. NO yellow on him",
            "long lean face, sunken cheeks, sharp predatory eyes",
            "black cloth wrapped round the head with one crow feather", "long drooping mustache",
            "fur collar, heavy spear with black-red tassels", "lean and rangy",
            "a shaggy black mountain pony with a red saddle cloth"),
    "y47": ("a Black Mountain crossbowman with a heavy crossbow aimed, a bag of bolts at the hip, a fur vest over black leather, black headband",
            "round hard face, thick brows, a squint",
            "black headband under a fur-flap hat", "full bushy brown beard",
            "heavy crossbow, bolt bag, fur vest", "thick and sturdy", None),
    "y48": ("a White Wave bandit assassin, all in white and pale grey cloth with a white hood and face wrap, twin short daggers held in reverse grip, crouched low, a white cloth belt trailing behind",
            "only the eyes show: cold narrow slits, one eyebrow cut by a scar",
            "white hood with a long tail", "hidden by the white face wrap",
            "reverse-grip twin daggers, trailing white sash", "lean, low and quick", None),
    "y49": ("a Taiping Way ritual master: a yellow robe with a black sash and a big rope-bead necklace, one hand holding a peach-wood sword and the other holding a talisman between two fingers, barefoot, a small yellow spirit flame by his shoulder",
            "sharp narrow face, thin brows, intense eyes",
            "high topknot with a long golden hairpin", "thin short beard",
            "peach-wood sword, talisman between two fingers, bead necklace", "slender", None),
    # ── 정예: 5등급 ──
    "y55": ("a Yellow Turban formation captain with a long pike held at a slant and a big round shield painted with a sigil, thick yellow-lacquered lamellar armor, a banner with a sigil on the back",
            "grizzled heavily wrinkled face, tight lips",
            "bare shaved head with a thick yellow band bearing a talisman strip", "short white stubble",
            "long pike, round sigil shield, back banner", "thick and heavy", None),
    "y56": ("a heavy Black Mountain cavalryman: black iron full lamellar armor with horn-shaped shoulder guards, a bearskin cape, a spear with a black pennant, a skull tied on the saddle. NO yellow on him",
            "brutal heavy face, small deep-set eyes",
            "black iron helmet with wolf-fur trim and a short black plume", "bushy black beard",
            "horn-shaped shoulder guards, bearskin cape, skull on the saddle", "huge rider",
            "a huge black warhorse in black iron barding with studded spikes"),
    "y57": ("a Black Mountain heavy-bow archer with a huge bow taller than himself, black leather armor with bone plates, a fur cloak, fingerless gloves, arrows as long as spears. NO yellow on him",
            "huge brow, deep-set eyes, wide jaw",
            "bearskin hood with the bear's ears", "braided beard",
            "huge bow, very long arrows, bone plate armor", "tall and hulking", None),
    "y58": ("a White Wave sworn-death warrior: a white mourning robe over leather armor, a white headband with black brush strokes, two white-wrapped sabers, white cloth wraps on the arms, a fanatic ready to die",
            "fanatic wide eyes, wild grin",
            "white headband with black brush strokes over long loose hair", "none",
            "mourning-white robe, twin white-wrapped sabers, white arm wraps", "wiry and lean", None),
    "y59": ("a Taiping Way Daoist: a long yellow-and-white robe with cloud embroidery, a horsetail fly-whisk in one hand and a small bronze bagua mirror in the other, a flat circle of floating talismans behind him",
            "wise calm face, long straight nose, closed-mouth smile",
            "high topknot with a golden hairpin", "long two-pronged beard",
            "horsetail whisk, bagua mirror, floating talisman circle", "tall and graceful", None),
    # ── 정예: 6등급 ──
    "y65": ("an underworld vajra guardian: a giant muscular ashen-skinned body, bare chest with golden sigil tattoos glowing, a crown of flat golden flame, a giant spiked iron club, small yellow flames at the feet, beads round the neck",
            "huge round angry eyes, flared nostrils, open roaring mouth",
            "flame crown over a topknot", "none",
            "giant spiked club, glowing chest tattoos, giant fists", "gigantic and thick", None),
    "y66": ("an underworld black-banner cavalry rider: all-black armor and cloth, a long black banner on his back with a golden sigil, a skull-shaped face plate, a long lance, riding a ghostly horse with bone armor",
            "hidden behind a skull faceplate with two glowing yellow eyes",
            "black iron helm with a black horsehair plume and a skull faceplate", "none visible",
            "long black banner with a gold sigil on his back, skull faceplate", "tall and dark",
            "a skeletal black horse with exposed rib armor plates and glowing yellow eyes"),
    "y67": ("an underworld thunder archer: crackling flat yellow-white lightning zigzags coil around his bow, a tattered storm-cloud cloak, an arrow made of lightning, ashen face, hair standing on end",
            "wild glowing eyes, manic grin",
            "wild upright flame-like hair with a metal circlet", "none",
            "lightning-wrapped bow, lightning arrow, storm cloak", "lean and wired", None),
    "y68": ("an underworld assassin-reaper: a hooded black cloak with torn edges, a half-face skull mask, a long curved reaper blade, trailing yellow ghost-fire footprints, drifting low over the ground",
            "skull half-mask with one glowing yellow eye",
            "deep black hood with a thin gold chain", "none",
            "long curved reaper blade, ghost-fire footprints, torn cloak", "slender and low", None),
    "y69": ("a Taiping Way celestial official: a long ceremonial robe of yellow and black with a court tablet held before the chest, a tall official hat with two flame-shaped wings, a floating scroll of decrees beside him, eerie glowing eyes",
            "gaunt grey face, hollow glowing eyes",
            "tall court hat with two flame-shaped wings", "long thin white mustache",
            "court tablet, floating decree scroll, robe with glowing sigils", "tall and gaunt", None),
    # ── 정예: 7등급 ──
    "y75": ("a giant underworld dharma-guardian general: gold-and-black armor with a lion-head belt and lion shoulder guards, a towering winged helmet, a giant halberd held up, a golden halo of flames behind him",
            "a stone-like golden mask face with glowing eyes and a stern mouth",
            "winged golden helmet", "none",
            "lion shoulder guards, giant halberd, flame halo", "giant and massive", None),
    "y76": ("an underworld thunder cavalry general on a lightning-wreathed giant black horse whose hooves leave yellow lightning, yellow-white lightning coils around the lance, gold-and-black armor with thunder-drum emblems, a long cape of storm cloud",
            "grinning with glowing eyes and fangs",
            "helmet with a tall lightning-bolt crest", "none",
            "lightning lance, lightning-wreathed horse, storm cape", "giant rider",
            "a giant black horse wreathed in yellow lightning, hooves crackling"),
    "y77": ("an underworld thunderbolt archer-lord: a giant gold bow whose string is a bolt of yellow lightning, a ring of floating thunder drums behind him, gold-and-black armor, hair floating like ghost fire",
            "cold glowing eyes, calm face",
            "floating flame-like hair held by a gold crown", "none",
            "lightning-string bow, ring of thunder drums", "tall and elegant", None),
    "y78": ("a black killing ghost: a tall dark shape in tattered black-and-gold robes, faceless with only two glowing yellow eyes inside a deep black hood, long claws, a curved blade, many floating torn talismans, ghost fire trailing like long hair",
            "faceless: a black void with two glowing slit eyes",
            "tattered hood with long flame hair", "none",
            "claws, curved blade, floating torn talismans", "very tall and wispy", None),
    "y79": ("a Taiping Way great sage-master hovering above the ground: a layered nine-fold yellow-and-gold robe with giant sigils and wide floating sleeves, long white hair flowing upward, a tall nine-pointed crown, a golden thunder seal held high in one hand and a thunder talisman in the other, a halo made of two overlapping golden rings",
            "ageless solemn face, glowing eyes, calm severe mouth",
            "tall nine-pointed crown over upward-flowing white hair", "long flowing white beard",
            "golden thunder seal, double-ring halo, nine-fold robe", "tall and imposing", None),
}

FOE_HEAD = """A character design sheet of 5 NAMELESS enemy soldiers for a mobile Three Kingdoms (late Han dynasty China) card game. They are the
Yellow Turban rebels and their allies that the player fights in the "subjugation" mode: a ladder of 7 levels that must visibly GROW in
gear, size and menace, from ragged peasants to underworld demon generals.
{this}

{style}

THE 7-LEVEL LADDER (this sheet is level {lv}):
{ladder}
Slot order on EVERY sheet is the same troop types: 1 SPEARMAN, 2 CAVALRY, 3 ARCHER, 4 ROGUE, 5 SORCERER.

OUTFIT LEVEL (THIS SHEET, level {lv} {lname}): {outfit}
Colors: {colors}. Size: {build}. {extra}

{ref}

{distinct}

{layout}

CHARACTERS
"""

REF_NEXT = """OPTIONAL REFERENCE: if an image is attached, it is the sheet of the previous level ({prev}): slot k there is the same troop type as slot k here.
Make this level a clear step up in gear and menace, but every character here is a NEW individual, not the same person."""
REF_ELITE = """OPTIONAL REFERENCE: if an image is attached, it is the REGULAR level-{lv} sheet: slot k there is the same troop type as slot k here.
These are the ELITE versions: tougher and bigger than the regulars, clearly different people with different headgear and weapons, but the
same side and level of gear."""


def foe_sheet(fname, ids, lv, elite):
    ladder = "\n".join("  Level %d %s —— %s: %s" % (l, v[0], v[1], v[2]) for l, v in LEVEL.items())
    L = LEVEL[lv]
    this = ("THIS SHEET: the ELITE troops of level %d (%s)." % (lv, L[0])) if elite else ("THIS SHEET: the regular troops of level %d (%s)." % (lv, L[0]))
    extra = "These are ELITES: noticeably tougher and more imposing than the regular level-%d troops." % lv if elite else ""
    ref = (REF_ELITE.format(lv=lv) if elite else (REF_NEXT.format(prev="level %d" % (lv - 1)) if lv > 1 else
           "This is the first level: there is no reference, define the look of the ragged rebels."))
    out = [FOE_HEAD.format(this=this, style=STYLE, lv=lv, ladder=ladder, lname=L[0], outfit=L[2], colors=L[3], build=L[4], extra=extra,
                           ref=ref, distinct=DISTINCT, layout=LAYOUT.format(size="1536x1024 landscape", cols=5, rows=1, n=len(ids)))]
    for i, k in enumerate(ids, 1):
        c = CARDS[k]
        tag = c[3]
        des, face, head, hair, mark, build, horse = FOE[k]
        out.append("%d. %s (%s)  [%s, level %d%s]" % (i, c[1], k, CLASS_EN[tag], c[2], " ELITE" if elite else ""))
        out.append("   DESIGN: " + des + ".")
        out.append("   FACE: " + face + ".")
        out.append("   BUILD: " + build + ".")
        out.append("   SIGNATURE (unique on this sheet): HEAD %s; FACIAL HAIR %s; MARK %s." % (head, hair, mark))
        out.append("   COLORS: " + L[3] + ".")
        if tag == "기병":
            out.append("   MOUNTED: riding %s —— a small chubby chibi horse, rider AND whole horse visible from ears to hooves, both standing on the blot." % (horse or "a war horse"))
    write("prompts/토벌적/" + fname, "\n".join(out))


def foe_plan():
    """시트 계획 [(파일, [id 5개], 등급, 정예?)] —— 카드 id 는 cards_ext.json 의 foe 카드에서 읽는다"""
    foes = {k: c for k, c in CARDS.items() if c[13] == "foe"}
    tiers = sorted({c[2] for c in foes.values()})
    plan = []
    for t in tiers:
        row = sorted([k for k, c in foes.items() if c[2] == t and int(k[2]) < 5], key=lambda k: k[2:])
        plan.append(("%02d_%d등급.txt" % (len(plan) + 1, t), row, t, False))
    for t in tiers:
        row = sorted([k for k, c in foes.items() if c[2] == t and int(k[2]) >= 5], key=lambda k: k[2:])
        if row:
            plan.append(("%02d_%d등급_정예.txt" % (len(plan) + 1, t), row, t, True))
    for _, row, t, _e in plan:
        assert len(row) == 5, (t, row)
        for k, tag in zip(row, TAGS):
            assert CARDS[k][3] == tag, (k, CARDS[k][3], tag)      # 슬롯 순서 = 창병 · 기병 · 궁병 · 도적 · 술사
    return plan, foes


def foe_howto(plan):
    s = ["토벌 적 55장 —— 이름 순서 = 이름표 번호 순서. 시트는 references/토벌적_시트/<txt 와 같은 이름>.png 로 두고 D:\\Sol 에서",
         "  python -I tools/scripts/slice_cards.py 토벌적   → references/토벌적_시트/잘림/ · 미리보기/ 확인 →   python -I tools/scripts/slice_cards.py 토벌적 --apply",
         "  (--apply 는 solgukji_godot/assets/foes/<카드 id>.png 로 복사한다. 폴더가 없으면 만든다.) 한 장씩 자를 때는 아래 명령.",
         "  자를 때 한 변 %d px 로 줄인다 (--max). 크기를 바꾸려면 make_troop_foe_prompts.py 의 MAX_SIDE 를 고치고 다시 실행." % MAX_SIDE["토벌적"],
         "  그리는 순서: 01 → 07 (일반, 앞 등급 시트를 참조로 붙이면 등급 차이가 이어진다) → 08 ~ 11 (정예, 같은 등급 일반 시트를 참조로).",
         ""]
    for fname, ids, lv, elite in plan:
        s.append("[%s]  %s" % (fname, " · ".join("%d %s(%s)" % (i, CARDS[k][1], k) for i, k in enumerate(ids, 1))))
        s.append('  자르기: python -I tools/scripts/slice_sheet.py 시트.png "%s" solgukji_godot/assets/foes --hole=155 --max=%d' % (",".join(ids), MAX_SIDE["토벌적"]))
        s.append("")
    write("prompts/토벌적/자르기_이름.txt", "\n".join(s))


def main():
    for fname, tags in BASIC_SHEETS:
        basic_sheet(fname, tags)
    basic_howto()
    plan, foes = foe_plan()
    missing = sorted(set(foes) - set(FOE))
    extra = sorted(set(FOE) - set(foes))
    if missing or extra:
        raise SystemExit("FOE 표에 없는 카드: %s / 카드에 없는 표 항목: %s" % (missing, extra))
    for fname, ids, lv, elite in plan:
        foe_sheet(fname, ids, lv, elite)
    foe_howto(plan)
    print("기본패 시트 %d장(카드 %d종) · 토벌 적 시트 %d장(카드 %d장)" % (len(BASIC_SHEETS), len(BASIC), len(plan), len(foes)))


main()
