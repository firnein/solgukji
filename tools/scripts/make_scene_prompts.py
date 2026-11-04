"""prompts/등급별/4_신화 의 프롬프트로 '한 단계 낮아 보이는 같은 장면' 프롬프트를 만든다 → prompts/등급별/5_장면
(11/5 사용자: 전설 이상 ~ 불멸 카드가 신화 그림을 쓰는 곳에 쓸, 비슷하지만 낮은 등급처럼 보이는 일러스트)
실행: python -I tools/scripts/make_scene_prompts.py   (저장소 맨 위에서)"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "prompts", "등급별", "4_신화")
DST = os.path.join(ROOT, "prompts", "등급별", "5_장면")

HEAD = """ONE card illustration of a single Three Kingdoms general for a mobile card game —— a LOWER-RARITY (Legendary / Transcendent tier)
version of the attached MYTHIC illustration. It must clearly read as the SAME person in the SAME scene, but visibly less
splendid, so players feel "this is the same hero, but not yet at their peak".

REFERENCE (attached image): the attached image is this general's MYTHIC card. Keep EXACTLY: the face, eye shape, brows,
facial hair, hairstyle and headwear, skin tone, age, body build, main colors and signature weapon or item.
Keep ROUGHLY: the camera angle, head direction, crop and weapon placement (a similar composition, not a copy) ——
the camera may sit a little farther back (chest-up to waist-up) so the face dominates a bit less.

WHAT MAKES IT LOWER TIER (apply all):
- ARMOR AND GEAR: a plainer, earlier version of the same outfit —— lacquered leather, iron scales and cloth instead of
  heavy gilded engraved plate; little or no gold, no fur collar, no gems; worn but clean, fewer layers.
- EFFECTS: NO legendary effects at all —— no lightning, no magic fire aura, no glowing eyes, no spirit dragons or beasts,
  no floating embers swarm. Only natural light, a little dust or smoke at most.
- EXPRESSION: still determined and dangerous, but restrained —— a focused stare rather than an overwhelming killing roar.
- LIGHT AND COLOR: softer, lower-contrast lighting with the same color family as the LIGHT line but less saturated;
  no burning rim light, the background a simple muted gradient or soft blurred battlefield.
- FRAME: a thin plain bronze/silver card frame (NOT dark gold, no ornaments).

STYLE: premium anime card illustration, realistic-leaning proportions (not chibi), clean sharp face, same rendering
quality as the reference —— lower rarity comes from the gear, effects and lighting, NOT from worse drawing.
GENDER: every character is an adult MAN, except the women Diaochan, Da Qiao and Xiao Qiao (same rules as the reference).

LAYOUT:
- Image 1024x1536 portrait. ONE single card illustration filling the whole image inside the card frame.
- No text anywhere: no name, no title, no number, no banner, no caption, no signature, no watermark.

SAVE AS: solgukji_godot/assets/portraits/{name}_장면.png   (the game uses it automatically for cards below Mythic)

CHARACTERS
"""


def main() -> None:
    os.makedirs(DST, exist_ok=True)
    n = 0
    for fn in sorted(os.listdir(SRC)):
        if not fn.endswith(".txt"):
            continue
        src = open(os.path.join(SRC, fn), encoding="utf-8").read()
        i = src.find("CHARACTERS\n")
        if i < 0:
            continue
        chars = src[i + len("CHARACTERS\n"):]
        chars = chars.replace("same person as reference #1", "same person as the attached mythic image")
        # 신화 장면의 영수 · 전설 효과 묘사는 지운다 (MOOD 줄에서 'a ... spirit ...' 같은 구절)
        chars = re.sub(r",\s*a [^,.]*?(spirit|aura|lightning|phantom|ghost)[^.]*", "", chars)
        chars = chars.replace("MOOD (only a dark blurred hint of this moment behind them, no guardian beasts)",
                              "MOOD (an earlier, humbler moment of the same story, only a soft blurred hint behind them)")
        name = re.sub(r"^\d+_", "", fn[:-4])
        open(os.path.join(DST, fn), "w", encoding="utf-8").write(HEAD.replace("{name}", name) + chars)
        n += 1
    open(os.path.join(DST, "사용법.txt"), "w", encoding="utf-8").write(
        "낮은 등급 장면 일러스트 —— 신화 그림(<인물>_신화.png)이 쓰이는 곳(고유기 컷인 · 조합 시트 배경 · 카드 상세)에서\n"
        "신화 아래 카드(고급 ~ 불멸)는 <인물>_장면.png 를 먼저 쓴다. 없으면 신화 그림 그대로.\n\n"
        "1. NN_<인물>.txt 프롬프트와 그 인물의 assets/portraits/<인물>_신화.png 를 함께 넣어 뽑는다.\n"
        "2. 결과를 solgukji_godot/assets/portraits/<인물>_장면.png 로 저장 (1024x1536, 자르기 없음).\n"
        "3. solgukji_godot 에서 Godot --headless --import 를 한 번 돌린다 (APK 에 들어가게).\n"
        "다시 만들기: python -I tools/scripts/make_scene_prompts.py\n")
    print("장면 프롬프트 %d개 → %s" % (n, DST))


if __name__ == "__main__":
    main()
