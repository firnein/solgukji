"""대용량 일러스트 프롬프트(md)에서 바스트샷(가슴 위) 판 txt 를 만든다 —— 시트별 붙여넣기용.

실행: python -I tools/scripts/make_bust_prompts.py [prompts/삼국지_일러스트_프롬프트_대용량.md]
  prompts/바스트샷/      : 원본 시트 그대로 (12 · 20명)
  prompts/바스트샷_6명/  : 6명씩 나눈 시트 (2열 × 3줄 —— 칸이 커서 얼굴이 더 또렷하다) + 자르기_이름.txt
  prompts/치비_깔끔배경/  : 치비 그림체 + 바스트 + 배경은 단순한 수채 워시, 자세한 판 · 상위 4명 / 하위 6명
  원본 블록에서 인물 크기 규칙을 바스트샷 규칙으로 바꾼다. SHOT 은
    MYTHIC · ORNATE (높은 등급) —— SCENE 의 가장 상징적인 순간에 맞춘 표정·손짓 (손과 소품이 화면 안으로 올라와도 된다)
    FINE · PLAIN               —— 가슴 위 구도 목록에서 칸마다 다른 각도·표정
"""
import os
import re
import sys

src = sys.argv[1] if len(sys.argv) > 1 else "prompts/삼국지_일러스트_프롬프트_대용량.md"
text = open(src, encoding="utf-8").read()

OLD_RULE = re.compile(r"CHARACTER FIRST:.*?The background is a supporting backdrop behind the character\.", re.S)
BUST_RULE = (
    "BUST SHOT ONLY: every panel is a chest-up portrait —— the frame cuts at the chest (just below the shoulders and collar);\n"
    "no waist, no legs, no full body. The head and face fill the upper half of the panel and are large, sharp and detailed;\n"
    "the shoulders fill the panel width. Helmets, plumes and weapon tips may stick out above the panel.\n"
    "SHOT changes only the angle, head turn, expression and gesture —— NOT the framing.\n"
    "MYTHIC and ORNATE: the iconic moment of SCENE is shown INSIDE the bust frame —— hands and signature props come up into the\n"
    "frame (an arrow pulled from the eye, a fan sweeping, a cup raised), and the SCENE's effects (fire, flood, storm, aura, light)\n"
    "swirl around the head and shoulders and may burst out of the panel. FINE and PLAIN: SCENE and LIGHT are only a soft background.")

ACTION = [
    "front view, chin raised, fierce confident gaze straight at the viewer",
    "slight low angle, looking down at the viewer, weapon shaft resting on the shoulder",
    "3/4 view, shouting a battle cry, hair and plume blown back by wind",
    "head turned sharply back toward the viewer over the shoulder, motion in the hair",
    "slight high angle, glaring up at the viewer, weapon blade crossing in front of the chest, cut by the panel edge",
    "side profile, gritted teeth, eyes on a distant target",
    "3/4 view, wild grin, one hand gripping the weapon near the shoulder",
    "front view, half the face in shadow, eyes narrowed, cold stare",
]
CALM = [
    "3/4 view, gentle smile, eyes toward the viewer",
    "side profile, looking into the distance, calm",
    "front view, head slightly tilted, hand near the face (stroking the beard, holding a fan or a brush)",
    "slight high angle, looking up at the viewer with a knowing smile",
    "3/4 view, eyes half-closed in thought, a scroll or fan near the chin",
    "head turned back toward the viewer over the shoulder, sly side glance",
    "front view, half the face lit by warm light, half in shadow, serious",
    "slight low angle, composed, looking down at the viewer, robe collar framing the face",
]
CALM_CLASS = {"SCHOLAR", "STRATEGIST", "SORCERER", "SCHEMER"}
ICONIC_SHOT = ("   SHOT: BUST (chest-up), the most iconic moment of SCENE at full drama —— the expression, gesture and camera angle "
               "that fit it; hands and signature props come up into the frame.")


def bustify(block: str, si: int) -> str:
    block, n = OLD_RULE.subn(BUST_RULE, block)
    assert n == 1
    block = block.replace("LARGE vertical panels with a rich SCENE background inside each panel.",
                          "LARGE vertical panels, chest-up portrait with a SCENE background inside each panel.")
    block = block.replace("medium vertical panels, character fills most of the panel.",
                          "medium vertical panels, chest-up portrait fills the panel, soft background.")
    block = block.replace("its own SHOT (camera distance, angle, pose)", "its own SHOT (angle, head turn, expression)")
    block = block.replace("TROOP CLASS must be obvious from silhouette, pose and main prop:",
                          "TROOP CLASS must be obvious from the armor, headgear and the prop near the shoulder:")
    out, idx, used = [], 0, {"a": set(), "c": set()}
    cls, splendor = "", ""
    for ln in block.split("\n"):
        m = re.match(r"\d+\. \(card[^)]*\) \[([A-Z]+)\]", ln)
        if m:
            cls, splendor = m.group(1), ""
        if ln.startswith("   SPLENDOR:"):
            splendor = ln
        if ln.startswith("   SHOT:"):
            if "MYTHIC" in splendor or "ORNATE" in splendor:
                ln = ICONIC_SHOT
            else:
                key, pool = ("c", CALM) if cls in CALM_CLASS else ("a", ACTION)
                if len(used[key]) >= len(pool):
                    used[key].clear()
                j = (idx * 3 + si) % len(pool)
                while j in used[key]:
                    j = (j + 1) % len(pool)
                used[key].add(j)
                ln = "   SHOT: BUST (chest-up), " + pool[j] + "."
            idx += 1
        out.append(ln)
    return "\n".join(out).strip() + "\n"


def reset(d):
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        if f.endswith(".txt"):
            os.remove(os.path.join(d, f))


D_FULL, D_SIX = "prompts/바스트샷", "prompts/바스트샷_6명"
reset(D_FULL)
reset(D_SIX)
cut = ["6명 시트를 뽑은 뒤 D:\\Sol 에서 자르기 (이름 순서 = 이름표 번호 순서). 자른 뒤 solgukji_godot 에서 Godot --import 를 한 번 돌린다.\n"]
six_no = 0
sections = re.split(r"^## (?=\d+\.)", text, flags=re.M)[1:]
for si, sec in enumerate(sections):
    head = sec.split("\n", 1)[0]
    num, part, tiers, k, cnt = re.match(r"(\d+)\. (\S+) \(([^)]*)\) (\d+) — (\d+)장", head).groups()
    block = bustify(re.search(r"```\n(.*?)\n```", sec, flags=re.S).group(1), si)
    name = "%02d_%s%s_%s_%s명_바스트.txt" % (int(num), part, k, tiers.replace("·", ""), cnt)
    open(os.path.join(D_FULL, name), "w", encoding="utf-8", newline="\n").write(block)

    # 6명씩 —— 공통 문구 + 장수 6명 (번호 1~6 으로 다시 매김)
    common, rest = block.split("\nImage size", 1)
    entries = re.split(r"\n(?=\d+\. \(card)", rest.split("\n\n", 1)[1].strip())
    names = re.search(r"자르기 이름 목록: `([^`]*)`", sec).group(1).split(",")
    assert len(names) == len(entries), head
    groups = -(-len(entries) // 6)                      # 6명 이하로 고르게 (20 → 5·5·5·5, 9 → 5·4)
    bounds = [round(len(entries) * g / groups) for g in range(groups + 1)]
    for g in range(groups):
        c = bounds[g]
        chunk = entries[c:bounds[g + 1]]
        six_no += 1
        n = len(chunk)
        cols, rows = (2, (n + 1) // 2) if n > 2 else (n, 1)
        body = [re.sub(r"^\d+\.", "%d." % (i + 1), e, count=1) for i, e in enumerate(chunk)]
        tail = ("Image size 1024x1536 portrait. Grid of %d characters: %d columns x %d rows (a short last row is centered). "
                "LARGE vertical panels, chest-up portrait with a SCENE background inside each panel.\n"
                "Banner under each panel: only its number.\n\n" % (n, cols, rows))
        fname = "%02d_%s%s-%d_%d명.txt" % (six_no, part, k, g + 1, n)
        open(os.path.join(D_SIX, fname), "w", encoding="utf-8", newline="\n").write(
            common.replace("like 12 key arts", "like separate key arts") + "\n" + tail + "\n".join(body) + "\n")
        cut.append("[%s]" % fname)
        cut.append('  python -I tools/scripts/slice_panels.py 시트.png "%s" solgukji_godot/assets/portraits' % ",".join(names[c:bounds[g + 1]]))
        cut.append("")
open(os.path.join(D_SIX, "자르기_이름.txt"), "w", encoding="utf-8", newline="\n").write("\n".join(cut))
print(len(os.listdir(D_FULL)), "시트 /", six_no, "개 6명 시트")




# ── 치비 깔끔배경 판 —— 기존 치비 그림체 + 바스트 + 배경은 단순한 수채 워시 (자세한 판) ──
#    글자 수 제한 없이 자세하게. 한 장 인원: 상위(신화·불멸) 4명 2×2 · 하위(초월·기본) 6명 2×3 (고르게 나눈다)
CLEAN_PER = {"상위": 4, "하위": 6}
CLEAN_COMMON = """A character sheet of {n} chibi Three Kingdoms (ancient China, late Han dynasty) character PORTRAITS.

STYLE (if an earlier sheet of this series is attached, copy only its drawing style, not its compositions or faces):
- Chibi / super-deformed proportions (about 2.5 to 3 heads tall) but MATURE, characterful faces —— not babyish, not cute-generic.
- Very detailed ink line art with fine hatching, rich watercolor and colored-pencil texture, warm and consistent across the sheet.
- Costume drawn with great care: layered Han-dynasty robes with crossed collars, embroidered silk and brocade with cloud, dragon,
  phoenix or geometric patterns, belts and jade ornaments, guan crowns, scholar caps, headscarves and helmets of the era;
  armor as lamellar plates, scale or lacquered leather with bronze, iron or gilded fittings, all with intricate patterns.
- Clear readable shapes, expressive eyes and brows, crisp outlines that separate the character from the background.

LAYOUT:
- Image 1024x1536 portrait. {n} LARGE vertical rounded-rectangle panels, {cols} columns x {rows} rows (a short last row is centered).
- Wide, even gaps on flat light green paper (#9BCF88) around the panels. Nothing crosses into a neighboring panel.
- Under each panel a dark green brush-stroke banner with ONLY its number (1 to {n}) in big white digits.
- No other text anywhere: no names, no titles, no captions, no signature, no watermark.

PORTRAIT FRAMING (every panel):
- Bust portrait: the big chibi head, shoulders and upper chest only, cut at the chest. No waist, no legs, no full body, no horse body.
- The face is large and sits in the upper half of the panel; shoulders and collar fill the panel width.
- Headgear, plumes and the tip of a signature weapon may reach or slightly break the top edge.
- Each panel follows its own POSE line (head turn, gaze, expression, gesture) —— no two panels share the same pose.

BACKGROUND (every panel) —— CLEAN:
- A simple, quiet watercolor wash: soft cream paper tone fading into a pale tint of the PORTRAIT LIGHT color, a little paper grain.
- At most a faint, blurred wisp behind the shoulders (thin mist, smoke, a soft glow, a few petals or sparks).
- No scenery, no landscape, no battlefield, no buildings, no furniture, no banners, no crowds, no other people, no animals except
  where CLASS says a horse's head may peek in at the edge. All attention on the character.

FACES MUST BE UNIQUE:
- Strongly distinctive faces even in chibi style. Follow LOOK and FACE exactly and EXAGGERATE them like a caricature: age, face
  shape, cheekbones, eye shape and size, brows, nose, mouth, facial hair, hairline, skin tone, wrinkles, scars, usual expression.
- Ages must clearly differ (smooth young faces vs. deep wrinkles). Not everyone is handsome: some are plain, ugly, fat, gaunt or
  brutish exactly as written. Each must be recognizable at thumbnail size, even with the costume covered.
- No generic handsome anime face, no same-face syndrome.

RANK (SPLENDOR) shows in the costume and a subtle touch, never in scenery:
{splendor}

MOMENT (only on MYTHIC and ORNATE characters): a small hint of their legend inside the portrait —— translate it into ONE signature
prop or gesture near the face or shoulder (a cup, a fan, a blade, an arrow, a scroll) plus a faint effect behind them (a glint of
lightning, a wisp of flame, drifting petals, a soft aura). Never paint the place, armies or other people from the MOMENT text.

TROOP CLASS is a small hint from armor, headgear and the prop near the shoulder:
{classes}
★ICONIC characters: their famous traditional look and signature weapon come FIRST and are drawn exactly as described;
the class hint is secondary.

AVOID: realistic or photographic rendering, plain generic anime style, babyish faces, identical faces, busy backgrounds, scenery,
extra people, cropped faces, text or labels, modern clothing, fantasy-western armor, Japanese samurai armor or kimono.
Do not draw the tags, ★ marks or line labels as text.

CHARACTERS
"""
CLEAN_SPLENDOR = {
    "PLAIN": "- PLAIN: practical worn gear —— plain cloth, faded dye, leather and dull iron, simple hair ties, no gold, muted colors.",
    "FINE": "- FINE: a proper officer —— good silk robe or polished lamellar armor, engraved trims, a few silver or gold accents, a neat belt ornament.",
    "ORNATE": "- ORNATE: richly decorated —— heavy brocade with gold embroidery, jeweled clasps and jade, gilded edges on the armor, a fine cape or sash.",
    "MYTHIC": "- MYTHIC: the most splendid —— gilded armor or imperial silk covered in dragon, phoenix or tiger motifs, luminous gold details, a faint golden glow behind the head, and the panel edged in faint gold.",
}
CLEAN_CLASS = {
    "SPEARMAN": "- SPEARMAN: heavy lamellar armor and a helmet with neck guard; the shaft of a long polearm rests on the shoulder.",
    "CAVALRY": "- CAVALRY: riding armor with a short cape; the rider is the subject —— at most the horse's head or mane peeks in at the edge.",
    "ARCHER": "- ARCHER: lighter armor or bracers, the upper limb of a bow and arrow fletchings visible over the shoulder.",
    "ROGUE": "- ROGUE: light leather or cloth armor, a headband or scarf, a short blade or dagger held near the face, alert eyes.",
    "STRATEGIST": "- STRATEGIST: flowing layered robe and a guan or scholar cap, a white crane-feather fan held near the chin.",
    "SCHOLAR": "- SCHOLAR: Confucian scholar robe and hat, holding bamboo slips, a book or a court tablet, no weapon.",
    "SORCERER": "- SORCERER: Taoist robe and crown, a staff, prayer beads or paper talismans, faint glowing sparks near the hand.",
    "SCHEMER": "- SCHEMER: dark muted robe with a high collar or hood, a sly look, holding a scroll, a vial or a go stone.",
}
PORTRAIT_LIGHT = {
    "raging fire": "warm ember-orange rim light from behind, flickering warm key light, wash faintly tinted orange",
    "moonlit night": "cool silver-blue moonlight rim, soft cool key light, wash faintly tinted blue-grey",
    "river spray": "cool blue-green reflected light from below, wash faintly tinted sea-green",
    "falling snow": "cold soft white light, pale icy shadows, wash faintly tinted icy blue",
    "lamp-lit interior": "warm amber lamp light from one side, deep soft shadows on the other side",
    "golden autumn": "warm golden afternoon light, wash faintly tinted ochre",
    "spring peach": "soft warm daylight with a pink tint, wash faintly tinted blush pink",
    "misty mountains": "soft diffuse grey light, low contrast, background faintly misty grey",
    "blazing sunset": "golden-orange backlight rim, warm shadows, wash faintly tinted amber",
    "mystic glow": "faint violet-and-gold glow behind the head, cool key light",
    "pale dawn": "pale cool dawn light, soft pink highlights, wash faintly tinted lavender-grey",
    "harsh noon": "bright high sunlight, crisp shadows under the brow, wash faintly tinted sand",
    "crisp clear": "clean neutral daylight, crisp and bright, wash faintly tinted sky blue",
    "heavy rain": "cool overcast light, wet sheen on armor and hair, wash faintly tinted teal-grey",
}
POSE_HIGH = "the expression and gesture of the MOMENT, front or 3/4 view, intense and characterful"


def clean_entry(e: str, i: int) -> str:
    L = e.split("\n")
    m = re.match(r"\d+\. \(card[^)]*\) (.*)", L[0])
    out = ["%d. %s" % (i, m.group(1))]
    rank = next((l for l in L if l.startswith("   SPLENDOR:")), "")
    high = "MYTHIC" in rank or "ORNATE" in rank
    scene = light = shot = ""
    for ln in L[1:]:
        k, _, v = ln.strip().partition(": ")
        if k == "FACTION":
            out.append("   COSTUME COLORS: " + v.replace("independent warlord, own colors.", "his own warlord colors."))
        elif k in ("LOOK", "FACE", "SPLENDOR"):
            out.append(ln)
        elif k == "SCENE":
            scene = v
        elif k == "LIGHT":
            light = v
        elif k == "SHOT":
            shot = v
    if high or "most iconic moment" in shot:
        out.append("   POSE: " + POSE_HIGH + ".")
    else:
        out.append("   POSE: " + shot.replace("BUST (chest-up), ", ""))
    tone = next((t for key, t in PORTRAIT_LIGHT.items() if light.startswith(key)), "soft neutral studio light")
    out.append("   PORTRAIT LIGHT: " + tone + ".")
    if high and scene:
        out.append("   MOMENT (hint only, no scenery): " + scene)
    return "\n".join(out)


def write_clean(dst, label):
    reset(dst)
    for f in os.listdir(dst):
        os.remove(os.path.join(dst, f))
    lines = ["%s 시트를 뽑은 뒤 D:\\Sol 에서 자르기 (이름 순서 = 이름표 번호 순서). 자른 뒤 solgukji_godot 에서 Godot --import 를 한 번 돌린다.\n" % label]
    no, sizes = 0, []
    for si, sec in enumerate(sections):
        head = sec.split("\n", 1)[0]
        num, part, tiers, k, cnt = re.match(r"(\d+)\. (\S+) \(([^)]*)\) (\d+) — (\d+)장", head).groups()
        block = bustify(re.search(r"```\n(.*?)\n```", sec, flags=re.S).group(1), si)
        entries = re.split(r"\n(?=\d+\. \(card)", block.split("\nImage size", 1)[1].split("\n\n", 1)[1].strip())
        names = re.search(r"자르기 이름 목록: `([^`]*)`", sec).group(1).split(",")
        per = CLEAN_PER[part]
        groups = -(-len(entries) // per)                  # per 명 이하로 고르게
        bounds = [round(len(entries) * g / groups) for g in range(groups + 1)]
        for g in range(groups):
            chunk = entries[bounds[g]:bounds[g + 1]]
            n = len(chunk)
            cols, rows = (2, (n + 1) // 2) if n > 2 else (n, 1)
            cls, spl = [], []
            for e in chunk:
                c = re.match(r"\d+\. \(card[^)]*\) \[([A-Z]+)\]", e).group(1)
                r = re.search(r"SPLENDOR: ([A-Z]+)", e).group(1)
                cls += [c] if c not in cls else []
                spl += [r] if r not in spl else []
            text = CLEAN_COMMON.format(
                n=n, cols=cols, rows=rows,
                classes="\n".join(CLEAN_CLASS[c] for c in cls),
                splendor="\n".join(CLEAN_SPLENDOR[r] for r in ["PLAIN", "FINE", "ORNATE", "MYTHIC"] if r in spl))
            text += "\n".join(clean_entry(e, j + 1) for j, e in enumerate(chunk)) + "\n"
            no += 1
            fname = "%02d_%s%s-%d_%d명.txt" % (no, part, k, g + 1, n)
            open(os.path.join(dst, fname), "w", encoding="utf-8", newline="\n").write(text)
            sizes.append(len(text))
            lines.append("[%s]" % fname)
            lines.append('  python -I tools/scripts/slice_panels.py 시트.png "%s" solgukji_godot/assets/portraits' % ",".join(names[bounds[g]:bounds[g + 1]]))
            lines.append("")
    open(os.path.join(dst, "자르기_이름.txt"), "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print(dst, no, "시트 · 글자 수 %d ~ %d" % (min(sizes), max(sizes)))


write_clean("prompts/치비_깔끔배경", "치비 깔끔배경")
