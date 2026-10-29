"""대용량 일러스트 프롬프트(md)에서 바스트샷(가슴 위) 판 txt 를 만든다 —— 시트별 붙여넣기용.

실행: python -I tools/scripts/make_bust_prompts.py [prompts/삼국지_일러스트_프롬프트_대용량.md]
  prompts/바스트샷/      : 원본 시트 그대로 (12 · 20명)
  prompts/바스트샷_6명/  : 6명씩 나눈 시트 (2열 × 3줄 —— 칸이 커서 얼굴이 더 또렷하다) + 자르기_이름.txt
  prompts/레오나르도_5천자/ : 프롬프트 5000자 제한용 —— 공통 문구 압축 + 장수 3명 이하 + 자르기_이름.txt
  prompts/실사풍_바스트/    : 5000자 · 3명 이하, 치비 대신 반실사 초상화(references/style_ref_realistic_bust.png), 배경은 거의 빈 단색
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


# ── 레오나르도 5천자 판 —— 공통 문구를 압축하고(그 시트에 나오는 병종·화려함만), 장수 줄을 합쳐 5000자 안에 3명 ──
LIMIT = 4950
CLASS_HINT = {
    "SPEARMAN": "SPEARMAN heavy armor, helmet, long polearm on the shoulder",
    "CAVALRY": "CAVALRY rider is the subject, only the horse's head or mane peeks in at the edge",
    "ARCHER": "ARCHER bow held near the shoulder, quiver on the back",
    "ROGUE": "ROGUE light armor, headband or scarf, short blade near the face",
    "STRATEGIST": "STRATEGIST flowing robe, white crane-feather fan",
    "SCHOLAR": "SCHOLAR scholar robe and hat, book, bamboo slips or court tablet, no weapon",
    "SORCERER": "SORCERER Taoist robe, staff or talismans, faint glowing magic",
    "SCHEMER": "SCHEMER dark robe with hood or high collar, scroll, vial or chess piece",
}
SPLENDOR_HINT = {
    "PLAIN": "PLAIN worn practical gear, muted, no glow",
    "FINE": "FINE polished officer gear, a few gold accents",
    "ORNATE": "ORNATE gold filigree, embroidered silk, flowing cape, light glints",
    "MYTHIC": "MYTHIC gilded armor with dragon or phoenix motifs, golden aura and sparkles, panel edged in faint gold",
}
LEO_COMMON = (
    "Chibi Three Kingdoms (ancient China) character sheet: super-deformed bodies (2.5-3 heads tall) but mature, characterful faces.\n"
    "Very detailed ink line art with fine hatching, rich watercolor and colored-pencil texture, intricate armor and costume patterns, one consistent style.\n"
    "LAYOUT: image 1024x1536 portrait. {n} LARGE vertical rounded-rectangle panels, {cols} columns x {rows} rows (short last row centered), "
    "wide gaps, on flat light green paper (#9BCF88); nothing touches the neighboring panels. Under each panel a dark green brush-stroke "
    "banner with ONLY its number (1-{n}) in big white digits. No other text, no names, no watermark.\n"
    "BUST SHOT ONLY: chest-up portraits cut at the chest, no waist, legs or full body. The face fills the upper half of the panel, "
    "large, sharp and detailed. Helmets, plumes and weapon tips may stick out above the panel.\n"
    "EVERY PANEL IS A DIFFERENT ILLUSTRATION: its own angle, head turn and expression (SHOT) and its own time, weather and background "
    "colors (LIGHT, never the faction color). Never repeat a front-facing centered template.\n"
    "FACES MUST BE UNIQUE: draw each FACE exactly and EXAGGERATE it like a caricature (shape, eyes, brows, nose, mouth, skin, age lines, "
    "scars, expression). No generic handsome anime face; recognizable at thumbnail size; ages really differ; not everyone is beautiful.\n"
    "IMPACT BY RANK: MYTHIC and ORNATE show their most famous moment (SCENE) at full drama inside the bust frame: intense expression, "
    "hands and signature props come up into the frame, effects (fire, flood, storm, aura, light) swirl around the head and shoulders and "
    "may burst out of the panel. FINE: moderate drama. PLAIN: quiet portrait with a soft hint of the place.\n"
    "★ = famous traditional look and signature weapon come first, class is only a small hint. CLASS: {classes}.\n"
    "SPLENDOR (card rank): {splendor}.\n"
    "Do not draw tags, ★ or line labels as text.\n")


def leo_entry(e: str, i: int) -> str:
    L = e.split("\n")
    m = re.match(r"\d+\. \(card[^)]*\) (\[[A-Z]+\]) (★ICONIC )?(.*)", L[0])
    out = ["%d. %s%s %s" % (i, m.group(1), "★" if m.group(2) else "", m.group(3))]
    look = face = ""
    for ln in L[1:]:
        k, _, v = ln.strip().partition(": ")
        if k == "FACTION":
            out.append("   COLORS: " + v.replace(" colors:", ":").replace("independent warlord, own colors.", "own warlord colors."))
        elif k == "LOOK":
            look = v.rstrip(".")
        elif k == "FACE":
            face = v.rstrip(".")
        elif k == "SHOT":
            if "most iconic moment" not in v:
                out.append("   SHOT: " + v.replace("BUST (chest-up), ", ""))
        else:
            out.append(ln)
    first = [p.strip() for p in look.split(",") if p.strip()]          # 나이 · 머리 · 투구 먼저, 그 뒤 얼굴 생김새
    rest = [p.strip() for p in face.split(",") if p.strip() and p.strip() not in first]
    out.insert(2, "   FACE: " + ", ".join(first + rest) + ".")
    return "\n".join(out)


REAL_COMMON = (
    "Semi-realistic historical portrait paintings of Three Kingdoms (ancient China) figures, in the style of polished official character "
    "portraits from a modern historical strategy game: realistic adult anatomy and proportions (NOT chibi, NOT anime, NOT cartoon), "
    "painterly digital painting with lifelike skin texture, realistic hair strands, finely embroidered silk and brocade patterns, "
    "detailed lacquered and metal armor, soft diffused studio light from the front-left, gentle rim light, sharp focus on the face.\n"
    "LAYOUT: image 1024x1536 portrait. {n} LARGE vertical rounded-rectangle panels, {cols} columns x {rows} rows (short last row centered), "
    "wide gaps, on flat light green paper (#9BCF88); nothing touches the neighboring panels. Under each panel a dark green brush-stroke "
    "banner with ONLY its number (1-{n}) in big white digits. No other text, no names, no watermark.\n"
    "BUST PORTRAIT: head, shoulders and upper chest only; the face large in the upper half of the panel, front or 3/4 view, "
    "shoulders and collar filling the panel width. Headgear may reach the top edge.\n"
    "BACKGROUND: plain and quiet —— a soft off-white to pale warm-grey gradient, at most a faint blurred wisp (mist, smoke, glow) "
    "behind the shoulders. No scenery, no battlefield, no buildings, no crowds, no other people. All attention on the character.\n"
    "FACES MUST BE UNIQUE: realistic yet distinctive faces —— follow FACE exactly (age, bone structure, eyes, brows, nose, mouth, "
    "facial hair, skin, scars, expression). Ages clearly differ, not everyone is handsome; recognizable at thumbnail size.\n"
    "RANK shows in the costume and a subtle touch, not in scenery. MOMENT (MYTHIC and ORNATE only): a small hint of their legend —— "
    "translate it into ONE signature prop or gesture near the face or shoulder and a faint effect behind them "
    "(e.g. a glint of lightning on the blade, a wisp of flame); never paint the place, armies or other people.\n"
    "★ = famous traditional look and signature weapon come first, class is only a small hint. CLASS: {classes}.\n"
    "SPLENDOR (card rank): {splendor}.\n"
    "Do not draw tags, ★ or line labels as text.\n")
REAL_SPLENDOR = {
    "PLAIN": "PLAIN simple cloth or worn leather and iron, muted colors",
    "FINE": "FINE fine officer robe or polished armor, a few gold accents",
    "ORNATE": "ORNATE rich brocade, gold embroidery, jeweled clasps",
    "MYTHIC": "MYTHIC the most splendid gilded armor or imperial silk with dragon or phoenix motifs, a faint golden glow behind the head",
}


def real_entry(e: str, i: int) -> str:
    L = leo_entry(e, i).split("\n")
    rank = next((l for l in L if l.strip().startswith("SPLENDOR:")), "")
    high = "MYTHIC" in rank or "ORNATE" in rank
    out = []
    for ln in L:
        k = ln.strip().split(":")[0]
        if k == "LIGHT":
            continue
        if k == "SCENE":
            if high:
                out.append("   MOMENT (hint only, no scenery): " + ln.split(": ", 1)[1])
            continue
        out.append(ln)
    return "\n".join(out)


def write_sheets(dst, label, common_tpl, splendor_hint, entry_fn):
    reset(dst)
    lines = ["%s 시트를 뽑은 뒤 D:\\Sol 에서 자르기 (이름 순서 = 이름표 번호 순서). 자른 뒤 solgukji_godot 에서 Godot --import 를 한 번 돌린다.\n" % label]
    no, sizes = 0, []

    def text_of(chunk):
        n = len(chunk)
        cols, rows = (2, (n + 1) // 2) if n > 2 else (n, 1)
        cls, spl = [], []
        for e in chunk:
            c = re.match(r"\d+\. \(card[^)]*\) \[([A-Z]+)\]", e).group(1)
            r = re.search(r"SPLENDOR: ([A-Z]+)", e).group(1)
            cls += [c] if c not in cls else []
            spl += [r] if r not in spl else []
        head = common_tpl.format(n=n, cols=cols, rows=rows, classes=" / ".join(CLASS_HINT[c] for c in cls),
                                 splendor=" / ".join(splendor_hint[r] for r in ["PLAIN", "FINE", "ORNATE", "MYTHIC"] if r in spl))
        return head + "\n" + "\n".join(entry_fn(e, i + 1) for i, e in enumerate(chunk)) + "\n"

    for si, sec in enumerate(sections):
        head = sec.split("\n", 1)[0]
        num, part, tiers, k, cnt = re.match(r"(\d+)\. (\S+) \(([^)]*)\) (\d+) — (\d+)장", head).groups()
        block = bustify(re.search(r"```\n(.*?)\n```", sec, flags=re.S).group(1), si)
        entries = re.split(r"\n(?=\d+\. \(card)", block.split("\nImage size", 1)[1].split("\n\n", 1)[1].strip())
        names = re.search(r"자르기 이름 목록: `([^`]*)`", sec).group(1).split(",")
        # 3명까지 (한 장에 인물이 적을수록 얼굴이 또렷하다), 5000자를 넘는 묶음이 있으면 한 명씩 줄인다 —— 고르게 나눈다
        for per in (3, 2, 1):
            groups = -(-len(entries) // per)
            bounds = [round(len(entries) * g / groups) for g in range(groups + 1)]
            texts = [text_of(entries[bounds[g]:bounds[g + 1]]) for g in range(groups)]
            if all(len(t) <= LIMIT for t in texts):
                break
        for g, t in enumerate(texts):
            no += 1
            fname = "%02d_%s%s-%d_%d명.txt" % (no, part, k, g + 1, bounds[g + 1] - bounds[g])
            open(os.path.join(dst, fname), "w", encoding="utf-8", newline="\n").write(t)
            sizes.append(len(t))
            lines.append("[%s] %d자" % (fname, len(t)))
            lines.append('  python -I tools/scripts/slice_panels.py 시트.png "%s" solgukji_godot/assets/portraits' % ",".join(names[bounds[g]:bounds[g + 1]]))
            lines.append("")
    open(os.path.join(dst, "자르기_이름.txt"), "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print(dst, no, "시트 · 글자 수 %d ~ %d" % (min(sizes), max(sizes)))


write_sheets("prompts/레오나르도_5천자", "레오나르도 5천자", LEO_COMMON, SPLENDOR_HINT, leo_entry)
write_sheets("prompts/실사풍_바스트", "실사풍 바스트", REAL_COMMON, REAL_SPLENDOR, real_entry)
