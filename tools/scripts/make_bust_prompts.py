"""대용량 일러스트 프롬프트(md)에서 바스트샷(가슴 위) 판 txt 를 만든다 —— 시트별 붙여넣기용.

실행: python -I tools/scripts/make_bust_prompts.py [prompts/삼국지_일러스트_프롬프트_대용량.md] [prompts/바스트샷]
  원본 블록에서 인물 크기 규칙을 바스트샷 규칙으로 바꾸고, 장수마다 SHOT 을 가슴 위 구도(각도·표정·손짓만 다름)로 바꾼다.
  SCENE · LIGHT 는 배경 분위기로만 남긴다. 자를 때 이름은 대용량 판과 같다 (prompts/대용량/자르기_이름.txt).
"""
import os
import re
import sys

src = sys.argv[1] if len(sys.argv) > 1 else "prompts/삼국지_일러스트_프롬프트_대용량.md"
dst = sys.argv[2] if len(sys.argv) > 2 else "prompts/바스트샷"
text = open(src, encoding="utf-8").read()
os.makedirs(dst, exist_ok=True)
for f in os.listdir(dst):
    if f.endswith(".txt"):
        os.remove(os.path.join(dst, f))

OLD_RULE = re.compile(r"CHARACTER FIRST:.*?The background is a supporting backdrop behind the character\.", re.S)
BUST_RULE = (
    "BUST SHOT ONLY: every panel is a chest-up portrait —— the frame cuts at the chest (just below the shoulders and collar);\n"
    "no waist, no hands below the chest, no legs, no full body. The head and face fill the upper half of the panel and are\n"
    "large, sharp and detailed; the shoulders fill the panel width. Helmets, plumes and weapon tips may stick out above the panel.\n"
    "SHOT changes only the angle, head turn, expression and what is held near the face or shoulder —— NOT the framing.\n"
    "SCENE and LIGHT are only the background mood behind the head and shoulders (a hint of the place, blurred), not an action to show in full.")

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

sections = re.split(r"^## (?=\d+\.)", text, flags=re.M)[1:]
for si, sec in enumerate(sections):
    head = sec.split("\n", 1)[0]
    num, part, tiers, k, cnt = re.match(r"(\d+)\. (\S+) \(([^)]*)\) (\d+) — (\d+)장", head).groups()
    block = re.search(r"```\n(.*?)\n```", sec, flags=re.S).group(1)
    block, n = OLD_RULE.subn(BUST_RULE, block)
    assert n == 1, head
    block = block.replace("LARGE vertical panels with a rich SCENE background inside each panel.",
                          "LARGE vertical panels, chest-up portrait with a soft SCENE background inside each panel.")
    block = block.replace("medium vertical panels, character fills most of the panel.",
                          "medium vertical panels, chest-up portrait fills the panel, soft background.")
    block = block.replace("its own SHOT (camera distance, angle, pose)", "its own SHOT (angle, head turn, expression)")
    block = block.replace("TROOP CLASS must be obvious from silhouette, pose and main prop:",
                          "TROOP CLASS must be obvious from the armor, headgear and the prop near the shoulder:")
    out, idx, used = [], 0, {"a": set(), "c": set()}
    cls = ""
    for ln in block.split("\n"):
        m = re.match(r"\d+\. \(card[^)]*\) \[([A-Z]+)\]", ln)
        if m:
            cls = m.group(1)
        if ln.startswith("   SHOT:"):
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
    name = "%02d_%s%s_%s_%s명_바스트.txt" % (int(num), part, k, tiers.replace("·", ""), cnt)
    open(os.path.join(dst, name), "w", encoding="utf-8", newline="\n").write("\n".join(out).strip() + "\n")
print("\n".join(sorted(os.listdir(dst))))
