"""대용량 일러스트 프롬프트(md)에 인물별 FACE 줄과 얼굴 개성 규칙을 넣는다 (이미 있으면 갱신).

실행: python -I tools/scripts/add_faces.py [prompts/삼국지_일러스트_프롬프트_대용량.md] [prompts/faces.json]
  얼굴은 prompts/faces.json (인물 이름 → 얼굴 설명) —— 같은 인물은 등급이 달라도 같은 얼굴.
  끝나면 split_prompts.py · make_bust_prompts.py 로 txt 를 다시 만든다.
"""
import json
import re
import sys

src = sys.argv[1] if len(sys.argv) > 1 else "prompts/삼국지_일러스트_프롬프트_대용량.md"
faces = json.load(open(sys.argv[2] if len(sys.argv) > 2 else "prompts/faces.json", encoding="utf-8"))
s = open(src, encoding="utf-8").read()

RULE = ("FACES MUST BE UNIQUE: never reuse one face —— no generic handsome anime face, no same-face syndrome. Draw each FACE line\n"
        "exactly and EXAGGERATE it like a caricature (face shape, eyes, brows, nose, mouth, skin, age lines, scars, expression).\n"
        "Each character must be recognizable at thumbnail size even with the costume covered. Ages really differ (smooth young skin\n"
        "vs. deep wrinkles), and not everyone is beautiful —— some are ugly, fat, gaunt or brutish.")
ANCHOR = "Personality first: each face and body language shows who they are (arrogant, gentle, crazed, sly, weary, joyful ...)."
s = re.sub(r"\nFACES MUST BE UNIQUE:.*?brutish\.", "", s, flags=re.S)
assert s.count(ANCHOR) == len(re.findall(r"^## \d+\.", s, flags=re.M))
s = s.replace(ANCHOR, ANCHOR + "\n" + RULE)

lines = s.split("\n")
out, person, miss = [], None, set()
for ln in lines:
    if ln.startswith("   FACE:"):
        continue
    m = re.match(r"\d+\. \(card: ([^)]*)\)", ln)
    if m:
        person = m.group(1).split()[-1]
    out.append(ln)
    if ln.startswith("   LOOK:") and person:
        if person in faces:
            out.append("   FACE: " + faces[person] + ".")
        else:
            miss.add(person)
s = "\n".join(out)
open(src, "w", encoding="utf-8", newline="").write(s)
print("FACE", s.count("   FACE:"), "없음:", ", ".join(sorted(miss)) or "-")
