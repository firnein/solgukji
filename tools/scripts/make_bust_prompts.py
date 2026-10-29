"""대용량 일러스트 프롬프트(md)에서 바스트샷(가슴 위) 판 txt 를 만든다 —— 시트별 붙여넣기용.

실행: python -I tools/scripts/make_bust_prompts.py [prompts/삼국지_일러스트_프롬프트_대용량.md]
  prompts/바스트샷/      : 원본 시트 그대로 (12 · 20명)
  prompts/바스트샷_6명/  : 6명씩 나눈 시트 (2열 × 3줄 —— 칸이 커서 얼굴이 더 또렷하다) + 자르기_이름.txt
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
