"""신화 장수 인형(전투 화면 삽화용) 후보를 로컬 ComfyUI(127.0.0.1:8188)로 뽑는다 (11/24).

tools/scripts/comfy_gen.py(초상 1인 1장)를 장수 인형용으로 고친 것:
  - 갈래(variant)마다 참조 그림 여러 개를 IP-Adapter 로 겹쳐 건다 (초상 = 복색 · 색, 병사 시트 = 작은 삽화 화풍).
  - 단색 바탕에 전신을 그린 뒤 BiRefNet 으로 배경을 지워 투명 PNG (투명 테두리 자르기 · 발 아래 맞춤).
  - flip: 화면 오른쪽을 보게 좌우 뒤집기 (병사 시트처럼 오른쪽을 본다).

실행 (D:\\solgukji-wt-hero 에서, 프로젝트 그림은 solgukji_godot/assets 아래)
  python -I tools/scripts/hero_gen.py prompts/comfy/장수인형_샘플.json                 # 전부
  python -I tools/scripts/hero_gen.py prompts/comfy/장수인형_샘플.json 관우 -v A -n 3 --seed 5100
결과: prompts/comfy/out/장수인형/<이름>/<갈래>_<시드>.png (원본) · <갈래>_<시드>_cut.png (투명) · 모음.png

JSON 형식:
  {"model": "...", "common": {"positive", "negative"},
   "refs": {"병사": {"sheet": "solgukji_godot/assets/war_painting/troops_action_blue_v1.png", "grid": [4, 8], "cells": [[0,0],[0,3],[0,5],[0,6]]}},
   "variants": {"A": {"desc": "...", "positive": "...", "negative": "...", "w": 832, "h": 1216,
                      "ip": [{"ref": "초상", "weight": 0.8, "type": "style transfer precise", "end_at": 1.0}]}},
   "items": [{"name": "관우", "portrait": "관우_신화", "positive": "...", "variants": {"A": {"positive": "..."}}}]}
  ip.ref: "초상" = 그 인물의 assets/portraits/<portrait>.png, 그 밖은 refs 의 이름.
"""
import argparse
import io
import json
import os
import random
import time
import urllib.parse
import urllib.request

import numpy as np
from PIL import Image

HOST = "http://127.0.0.1:8188"
PORTRAITS = "solgukji_godot/assets/portraits"
_uploaded = {}


def call(path, data=None):
    req = urllib.request.Request(HOST + path, data=json.dumps(data).encode() if data is not None else None,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def cover(im, size):
    tw, th = size
    s = max(tw / im.width, th / im.height)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    l, t = (im.width - tw) // 2, (im.height - th) // 4      # 위쪽을 남긴다 (얼굴이 위 가운데)
    return im.crop((l, t, l + tw, t + th))


def upload(key, im):
    """그림을 ComfyUI input 에 올리고 파일 이름을 돌려준다 (같은 key 는 한 번만)."""
    if key in _uploaded:
        return _uploaded[key]
    buf = io.BytesIO()
    im.save(buf, "PNG")
    fname = "solgukji_hero_" + key.encode().hex()[:28] + ".png"
    bnd = "----solgukji" + str(random.randrange(1 << 30))
    crlf = "\r\n"
    head = (f"--{bnd}{crlf}Content-Disposition: form-data; name=\"image\"; filename=\"{fname}\"{crlf}"
            f"Content-Type: image/png{crlf}{crlf}")
    tail = f"{crlf}--{bnd}{crlf}Content-Disposition: form-data; name=\"overwrite\"{crlf}{crlf}true{crlf}--{bnd}--{crlf}"
    body = head.encode() + buf.getvalue() + tail.encode()
    req = urllib.request.Request(HOST + "/upload/image", data=body,
                                 headers={"Content-Type": f"multipart/form-data; boundary={bnd}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        _uploaded[key] = json.loads(r.read())["name"]
    return _uploaded[key]


def portrait_ref(name):
    im = Image.open(os.path.join(PORTRAITS, name + ".png")).convert("RGBA")
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
    bg.alpha_composite(im)
    return upload("p_" + name, cover(bg.convert("RGB"), (512, 512)))


def sheet_ref(key, spec):
    """병사 시트에서 칸 몇 개를 흰 바탕 512 정사각 격자로 모아 화풍 참조로 쓴다."""
    sheets = [Image.open(f).convert("RGBA") for f in spec.get("sheets", [spec.get("sheet")])]
    gc, gr = spec["grid"]
    cells = spec["cells"]      # [열, 행] 또는 [시트 번호, 열, 행] (청 · 적 시트를 섞어 색 치우침을 없앤다)
    n = int(np.ceil(np.sqrt(len(cells))))
    side = 512 // n
    out = Image.new("RGBA", (512, 512), (255, 255, 255, 255))
    for i, cell in enumerate(cells):
        si, c, r = cell if len(cell) == 3 else (0, *cell)
        sh = sheets[si]
        cw, ch = sh.width / gc, sh.height / gr
        im = sh.crop((round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch))).resize((side, side), Image.LANCZOS)
        out.alpha_composite(im, ((i % n) * side, (i // n) * side))
    return upload("s_" + key, out.convert("RGB"))


def workflow(model, pos, neg, w, h, seed, steps, cfg, ips):
    wf = {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": model}},
        "2": {"class_type": "CLIPTextEncode", "inputs": {"text": pos, "clip": ["1", 1]}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"text": neg, "clip": ["1", 1]}},
        "4": {"class_type": "EmptyLatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "5": {"class_type": "KSampler", "inputs": {"model": ["1", 0], "positive": ["2", 0], "negative": ["3", 0],
                                                    "latent_image": ["4", 0], "seed": seed, "steps": steps, "cfg": cfg,
                                                    "sampler_name": "euler_ancestral", "scheduler": "normal", "denoise": 1.0}},
        "6": {"class_type": "VAEDecode", "inputs": {"samples": ["5", 0], "vae": ["1", 2]}},
        "7": {"class_type": "SaveImage", "inputs": {"images": ["6", 0], "filename_prefix": "solgukji/hero"}},
        "8": {"class_type": "LoadBackgroundRemovalModel", "inputs": {"bg_removal_name": "birefnet.safetensors"}},
        "9": {"class_type": "RemoveBackground", "inputs": {"bg_removal_model": ["8", 0], "image": ["6", 0]}},
        "10": {"class_type": "MaskToImage", "inputs": {"mask": ["9", 0]}},
        "11": {"class_type": "SaveImage", "inputs": {"images": ["10", 0], "filename_prefix": "solgukji/heromask"}},
    }
    if ips:
        wf["20"] = {"class_type": "IPAdapterModelLoader", "inputs": {"ipadapter_file": "ip-adapter-plus_sdxl_vit-h.safetensors"}}
        wf["21"] = {"class_type": "CLIPVisionLoader", "inputs": {"clip_name": "CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors"}}
        prev = ["1", 0]
        for i, (fn, ip) in enumerate(ips):
            wf[f"3{i}"] = {"class_type": "LoadImage", "inputs": {"image": fn}}
            wf[f"4{i}"] = {"class_type": "IPAdapterAdvanced", "inputs": {
                "model": prev, "ipadapter": ["20", 0], "clip_vision": ["21", 0], "image": [f"3{i}", 0],
                "weight": ip["weight"], "weight_type": ip.get("type", "style transfer"), "combine_embeds": "average",
                "start_at": ip.get("start_at", 0.0), "end_at": ip.get("end_at", 1.0), "embeds_scaling": "V only"}}
            prev = [f"4{i}", 0]
        wf["5"]["inputs"]["model"] = prev
    return wf


def generate(wf):
    pid = json.loads(call("/prompt", {"prompt": wf}))["prompt_id"]
    while True:
        hist = json.loads(call(f"/history/{pid}"))
        if pid in hist:
            st = hist[pid].get("status", {})
            if st.get("status_str") == "error":
                raise RuntimeError(json.dumps(st.get("messages", []), ensure_ascii=False)[:800])
            got = {}
            for nid, node in hist[pid]["outputs"].items():
                for im in node.get("images", []):
                    q = urllib.parse.urlencode({"filename": im["filename"], "subfolder": im["subfolder"], "type": im["type"]})
                    got[nid] = Image.open(io.BytesIO(call(f"/view?{q}")))
            return got["7"].convert("RGB"), got["11"].convert("L")
        time.sleep(1)


def cutout(im, mask, flip=False):
    """배경을 지우고 투명 테두리를 잘라 발(맨 아래)을 바닥에 둔다."""
    a = np.asarray(mask).astype(np.float32)
    a = np.clip((a - 40) * 255 / 175, 0, 255).astype(np.uint8)      # 옅은 그림자 · 가장자리 안개는 버린다
    out = Image.fromarray(np.dstack([np.asarray(im), a]), "RGBA")
    box = out.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    if box:
        out = out.crop(box)
    if flip:
        out = out.transpose(Image.FLIP_LEFT_RIGHT)
    return out


def contact(paths, dst, ground=(200, 182, 140, 255)):
    ims = [Image.open(p).convert("RGBA") for p in paths]
    th = 300
    ims = [i.resize((max(1, round(i.width * th / i.height)), th), Image.LANCZOS) for i in ims]
    sheet = Image.new("RGBA", (sum(i.width for i in ims) + 8 * (len(ims) + 1), th + 16), ground)
    x = 8
    for i in ims:
        sheet.alpha_composite(i, (x, 8))
        x += i.width + 8
    sheet.convert("RGB").save(dst)


def join(*parts):
    return ", ".join(p.strip().strip(",") for p in parts if p and p.strip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("names", nargs="*", help="이 인물만 (없으면 전부)")
    ap.add_argument("-v", "--variants", default="", help="이 갈래만 (쉼표, 예: A,B)")
    ap.add_argument("-n", type=int, default=3, help="갈래당 장 수")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--steps", type=int, default=28)
    ap.add_argument("--cfg", type=float, default=5.0)
    ap.add_argument("--out", default="prompts/comfy/out/장수인형")
    a = ap.parse_args()

    spec = json.load(open(a.spec, encoding="utf-8"))
    common, variants, refs = spec.get("common", {}), spec["variants"], spec.get("refs", {})
    want = [v for v in a.variants.split(",") if v]
    items = [it for it in spec["items"] if not a.names or it["name"] in a.names]
    base_seed = a.seed if a.seed is not None else random.randrange(1 << 31)
    log = []
    for it in items:
        d = os.path.join(a.out, it["name"])
        os.makedirs(d, exist_ok=True)
        cuts = []
        for vk, vr in variants.items():
            if want and vk not in want:
                continue
            iv = it.get("variants", {}).get(vk, {})
            if iv.get("skip"):
                continue
            pos = join(iv.get("lead", it.get("lead", vr.get("lead", ""))), iv.get("positive", it["positive"]), vr.get("positive", ""), common.get("positive", ""))
            neg = join(iv.get("negative", it.get("negative", "")), vr.get("negative", ""), common.get("negative", ""))
            ips = []
            for ip in iv.get("ip", vr.get("ip", [])):
                fn = portrait_ref(it["portrait"]) if ip["ref"] == "초상" else sheet_ref(ip["ref"], refs[ip["ref"]])
                ips.append((fn, ip))
            w, h = iv.get("w", vr.get("w", 832)), iv.get("h", vr.get("h", 1216))
            for k in range(a.n):
                seed = base_seed + k
                t0 = time.time()
                im, mask = generate(workflow(spec["model"], pos, neg, w, h, seed, a.steps, a.cfg, ips))
                raw = os.path.join(d, f"{vk}_{seed}.png")
                im.save(raw)
                cp = raw[:-4] + "_cut.png"
                cutout(im, mask).save(cp)
                cuts.append(cp)
                print(f"{it['name']} {vk} 시드 {seed} · {time.time() - t0:.0f}초", flush=True)
            log.append({"name": it["name"], "variant": vk, "seeds": [base_seed + k for k in range(a.n)], "w": w, "h": h,
                        "positive": pos, "negative": neg,
                        "ip": [{k2: v2 for k2, v2 in ip.items()} for _, ip in ips], "steps": a.steps, "cfg": a.cfg})
        if cuts:
            contact(cuts, os.path.join(d, "모음.png"))
    with open(os.path.join(a.out, f"기록_{base_seed}.json"), "w", encoding="utf-8") as f:
        json.dump({"model": spec["model"], "runs": log}, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
