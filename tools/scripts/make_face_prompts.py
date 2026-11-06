"""전투용 원형 얼굴 썸네일 프롬프트 —— 완성된 기본 캐릭터(assets/portraits/<인물>.png)를 참조해 얼굴 메달을 그린다 (11/3 사용자).

실행: python -I tools/scripts/make_face_prompts.py  →  prompts/얼굴썸네일/
  NN_6명.txt      : 시트마다 6명 (3열 × 2줄). 참조 이미지(참조_NN.png)를 함께 붙여 넣는다 —— 번호 k = 참조의 k 번 인물
  자르기_이름.txt : 참조 만들기 · 자르기 명령. 잘린 그림은 solgukji_godot/assets/faces/<인물>.png
  인물 설명은 prompts/등급별/1_기본 · 1_기본_재작업 · 1_기본_추가 의 FACE · SIGNATURE 줄을 그대로 쓴다 (뒤 폴더가 앞을 덮는다).
게임은 assets/faces/<인물>.png 가 있으면 전투 머리표 · 장수 토큰에 그 그림을, 없으면 지금처럼 초상에서 얼굴을 찾아 자른다.
"""
import os
import re
import sys

SRC = ["prompts/등급별/1_기본", "prompts/등급별/1_기본_재작업", "prompts/등급별/1_기본_추가"]
OUT = "prompts/얼굴썸네일"
PORTRAITS = "solgukji_godot/assets/portraits"
PER = 6
FAC_ORDER = {"Shu": 0, "Wei": 1, "Wu": 2, "Independent": 3}

HEAD = """A sheet of 6 round FACE MEDALLIONS of Three Kingdoms (late Han dynasty China) characters for the battle screen of a mobile
card game. In battle each medallion is shown very small (about 48 pixels) as the unit's token, so the face must read instantly.

REFERENCE (attached image): numbered portraits of the SAME characters. Medallion k is the character numbered k in the reference.
Keep each identity EXACTLY as in the reference: the same face shape, eye shape, brows, nose, mouth, facial hair, skin tone,
age, hairstyle and headwear, main colors. Do not redesign, beautify or age them. Only the crop changes.

STYLE (same as the reference): cute SD chibi drawing, clean dark-brown ink outlines, flat soft colors with simple two-tone cel
shading, light paper texture. Not glossy, not painterly, not realistic.

MEDALLION:
- Each character is drawn inside ONE solid round medallion: a filled circle of flat warm paper color (#E9E3D3) with NO border
  ring, no frame, no rim, no shadow. Everything of the character stays INSIDE the circle; nothing pokes out of it.
- HEAD-AND-SHOULDERS ONLY: the head is big and centered, the face (brows to chin) fills about the middle half of the circle,
  the top of the shoulders and the collar show at the bottom edge. No hands, no weapons, no props in front of the face.
- Tall helmets, crowns, plumes and hair buns are allowed but are cut by the circle edge at the top —— keep the eyes and the
  mouth well inside, a little above the circle center.
- FRONT VIEW or a slight 3/4 turn, eyes looking at the viewer, a calm battle-ready expression that fits the character
  (fierce, cold, cheerful, sly, serene). Clear eyes with a catchlight; the expression must read at a tiny size.
- Strong readable silhouette: the headwear and facial hair from the SIGNATURE line are the first thing you see.
EVERY CHARACTER LOOKS DIFFERENT: no two medallions share the same headgear, hairstyle or facial hair —— follow each
SIGNATURE line exactly. Same faction colors must never make them look like twins.
GENDER: follow the reference exactly. Women stay women, men stay men; young men are young MEN, never girls.

LAYOUT:
- Image 1536x1024 landscape. A fixed grid of 3 columns x 2 rows = 6 equal slots, reading order left to right, top to bottom.
- Medallions 1 to 6 fill the first 6 slots in order; leave any remaining slot empty.
- One medallion per slot, all medallions the SAME size (about 400 pixels across), centered in the slot.
- Flat light green paper background (#9BCF88) over the whole sheet outside the medallions. Wide even gaps between medallions.
- Under each medallion a dark green brush-stroke banner with ONLY its number (1 to 6) in big white digits.
- No other text anywhere: no names, no titles, no captions, no signature, no watermark.

CHARACTERS
"""


def blocks(path):
    """시트 txt 의 인물 블록 —— [(번호, 머리줄, {키: 값})]"""
    s = open(path, encoding="utf-8").read()
    if "CHARACTERS" not in s:
        return []
    s = s[s.index("CHARACTERS") + len("CHARACTERS"):]
    out = []
    for m in re.finditer(r"^(\d+)\. (.+?)\n((?:   .*\n?)*)", s, re.M):
        kv = {}
        for line in m.group(3).splitlines():
            mm = re.match(r"\s+([A-Z][A-Z ]*(?: \([^)]*\))?): (.*)", line)
            if mm:
                kv[mm.group(1).strip()] = mm.group(2).strip()
        out.append((int(m.group(1)), m.group(2).strip(), kv))
    return out


def names_of(folder):
    """자르기_이름.txt —— 시트 txt -> 인물 이름 순서 (자르기 명령의 따옴표 안)"""
    p = os.path.join(folder, "자르기_이름.txt")
    if not os.path.exists(p):
        return {}
    out = {}
    cur = None
    for line in open(p, encoding="utf-8"):
        m = re.match(r"\[(.+?\.txt)\]", line)
        if m:
            cur = m.group(1)
        m = re.search(r'slice_sheet\.py 시트\.png "([^"]+)"', line)
        if m and cur:
            out[cur] = m.group(1).split(",")
    return out


def main():
    info = {}
    for folder in SRC:
        nm = names_of(folder)
        for f in sorted(os.listdir(folder)):
            if not f.endswith(".txt") or f not in nm:
                continue
            for i, head, kv in blocks(os.path.join(folder, f)):
                if i - 1 < len(nm[f]):
                    info[nm[f][i - 1]] = (head, kv)
    have = {f[:-4] for f in os.listdir(PORTRAITS) if f.endswith(".png") and "_" not in f}
    people = sorted([p for p in info if p in have],
                    key=lambda p: (FAC_ORDER.get(re.search(r", (\w+)\]", info[p][0]).group(1) if re.search(r", (\w+)\]", info[p][0]) else "", 9), p))
    missing = sorted(have - set(people))
    os.makedirs(OUT, exist_ok=True)
    # --missing (11/7): 얼굴 그림(assets/faces/<인물>.png)이 아직 없는 인물만, 기존 시트 번호 뒤에 이어서 (이미 뽑은 시트 · 안내는 그대로 두고 덧붙인다)
    only_new = "--missing" in sys.argv
    start = 0
    if only_new:
        faces_have = {f[:-4] for f in os.listdir("solgukji_godot/assets/faces") if f.endswith(".png")}
        also = []      # --also=악진,요화 —— 얼굴은 있지만 초상을 다시 그린 인물 (얼굴도 다시)
        for a in sys.argv:
            if a.startswith("--also="):
                also = a.split("=", 1)[1].split(",")
        people = [p for p in people if p not in faces_have or p in also]
        nums = [int(f[:2]) for f in os.listdir(OUT) if re.match(r"\d\d_\d명\.txt", f)]
        start = max(nums) if nums else 0
    else:
        for f in os.listdir(OUT):
            if re.match(r"\d\d_\d명\.txt", f):
                os.remove(os.path.join(OUT, f))
    guide = ["얼굴 썸네일 —— 이름 순서 = 이름표 번호 순서. D:\\Sol 에서 시트마다:",
             "  1. 참조 이미지를 만든다 (아래 '참조' 명령) → 프롬프트 txt 와 함께 붙여 넣어 뽑는다",
             "  2. 시트를 references/얼굴썸네일/<txt 와 같은 이름>.png 로 두고 '자르기' 명령 → solgukji_godot/assets/faces/",
             "  3. solgukji_godot 에서 Godot --import 한 번. 게임은 faces 그림이 있으면 전투 머리표에 그것을 쓴다.", ""]
    for n in range(0, len(people), PER):
        grp = people[n:n + PER]
        k = n // PER + 1 + start
        fn = "%02d_%d명.txt" % (k, len(grp))
        n_ = len(grp)
        lines = [HEAD.replace("6 round", "%d round" % n_).replace("(1 to 6)", "(1 to %d)" % n_)
                 .replace("Medallions 1 to 6 fill the first 6", "Medallions 1 to %d fill the first %d" % (n_, n_)).rstrip("\n")]
        for i, p in enumerate(grp):
            head, kv = info[p]
            lines.append("%d. %s —— same person as reference #%d" % (i + 1, head.replace("★ICONIC: draw the famous traditional look exactly", "").strip(), i + 1))
            if "FACE" in kv:
                lines.append("   FACE: " + kv["FACE"])
            for key, v in kv.items():
                if key.startswith("SIGNATURE"):
                    lines.append("   SIGNATURE: " + v)
            if "COLORS" in kv:
                lines.append("   COLORS: " + kv["COLORS"])
        open(os.path.join(OUT, fn), "w", encoding="utf-8").write("\n".join(lines) + "\n")
        guide.append("[%s]  %s" % (fn, " · ".join("%d %s" % (i + 1, p) for i, p in enumerate(grp))))
        guide.append('  참조:   python -I tools/scripts/make_ref_sheet.py "%s" prompts/얼굴썸네일/참조_%02d.png' % (",".join(grp), k))
        guide.append('  자르기: python -I tools/scripts/slice_sheet.py references/얼굴썸네일/%s "%s" solgukji_godot/assets/faces' % (fn.replace(".txt", ".png"), ",".join(grp)))
        guide.append("")
    if missing:
        guide.append("설명 줄을 찾지 못해 뺀 인물: " + " ".join(missing))
    if only_new and os.path.exists(os.path.join(OUT, "자르기_이름.txt")):
        old = open(os.path.join(OUT, "자르기_이름.txt"), encoding="utf-8").read().rstrip("\n")
        guide = [old, "", "# ── 11/7 새 인물 (1_기본_추가 04~13) —— make_face_prompts.py --missing 으로 이어 붙임"] + guide[5:]
    open(os.path.join(OUT, "자르기_이름.txt"), "w", encoding="utf-8").write("\n".join(guide) + "\n")
    print("%d명 · 시트 %d장 → %s" % (len(people), -(-len(people) // PER), OUT))
    if missing:
        print("설명 없음:", missing)


main()
