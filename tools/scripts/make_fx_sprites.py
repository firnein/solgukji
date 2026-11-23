"""11/23 기술 · 잔기술 이펙트용 Kenney CC0 그림 가져오기.

원본: cache/fx_dl (Kenney Particle Pack 1.1 · Smoke Particles —— OpenGameArt 에서 내려받아 푼 것)
  kenney_particle/PNG/*.png  —— 검은 바탕 회색 (더하기 합성용) → RGB=밝기, 알파=밝기×0.86 (기존 assets/fx/kenney 와 같은 변환)
  kenney_smoke/PNG/<종류>/*.png —— 색 있는 반투명 연기 (보통 합성) → 그대로 줄이기만
결과: solgukji_godot/assets/fx/kenney/<이름>.png (256px)
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "cache", "fx_dl")
DST = os.path.join(ROOT, "solgukji_godot", "assets", "fx", "kenney")
SIZE = 256

GLOW = ["spark_05", "spark_06", "star_04", "star_07", "star_08", "scratch_01", "slash_04", "trace_02", "trace_04",
        "twirl_02", "twirl_03", "circle_02", "light_01", "light_03", "magic_02", "magic_04", "muzzle_01", "muzzle_03"]
SMOKE = {"Explosion": ["explosion00", "explosion02", "explosion04", "explosion06"],
         "Fart": ["fart00", "fart02", "fart04", "fart06"],
         "Flash": ["flash00", "flash02", "flash04", "flash06"],
         "White puff": ["whitePuff00", "whitePuff03", "whitePuff06", "whitePuff09"],
         "Black smoke": ["blackSmoke00", "blackSmoke03", "blackSmoke06", "blackSmoke09"]}


def fit(im: Image.Image) -> Image.Image:
    """가운데 맞춰 정사각 SIZE 로 (비율 유지 · 남는 곳은 투명)"""
    im.thumbnail((SIZE, SIZE), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(im, ((SIZE - im.width) // 2, (SIZE - im.height) // 2), im)
    return out


def main() -> None:
    os.makedirs(DST, exist_ok=True)
    for nm in GLOW:
        g = Image.open(os.path.join(SRC, "kenney_particle", "PNG", nm + ".png")).convert("L").resize((SIZE, SIZE), Image.LANCZOS)
        a = g.point(lambda v: int(v * 0.86))
        Image.merge("RGBA", (g, g, g, a)).save(os.path.join(DST, nm + ".png"), optimize=True)
    for folder, names in SMOKE.items():
        for nm in names:
            im = Image.open(os.path.join(SRC, "kenney_smoke", "PNG", folder, nm + ".png")).convert("RGBA")
            fit(im).save(os.path.join(DST, nm + ".png"), optimize=True)
    print("ok", len(GLOW) + sum(len(v) for v in SMOKE.values()))


if __name__ == "__main__":
    main()
