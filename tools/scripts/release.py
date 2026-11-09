# -*- coding: utf-8 -*-
"""버전 · 업데이트 내역 (11/7)

원본은 solgukji_godot/data/changelog.json. 이 스크립트는
  1) export_presets.cfg 의 version/name · version/code 를 맨 앞 항목에 맞추고
  2) docs/업데이트_내역.html 을 다시 만들고
  3) build/version.txt 에 버전 이름을 적는다 (build_apk.bat 이 APK 파일 이름에 쓴다)
  4) data/servers.json 의 「Dev」 서버 주소를 이 PC 의 LAN IPv4 로 고친다 (온라인 대전 접속 시트의 기본 서버.
     기본 경로 인터페이스의 주소 → 안 되면 ipconfig → 그래도 못 찾으면 그대로. 아이피가 같으면 파일을 쓰지 않고, 바뀌면 한 줄 알린다)

쓰는 법
  python tools/scripts/release.py                 동기화만
  python tools/scripts/release.py --next "제목"   다음 버전(1.0a → 1.0b … 1.0z → 1.1a) 항목을 맨 앞에 비워서 추가한 뒤 동기화
  python tools/scripts/release.py --check         changelog 가 export_presets 와 맞는지만 본다 (틀리면 종료 코드 1). servers.json 은 손대지 않는다
"""
import json, re, sys, html, pathlib, socket, subprocess, ipaddress

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")   # 윈도우 콘솔(cp949)에서 한글 · 기호 출력

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHANGELOG = ROOT / "solgukji_godot" / "data" / "changelog.json"
PRESETS = ROOT / "solgukji_godot" / "export_presets.cfg"
HTML = ROOT / "docs" / "업데이트_내역.html"
VERSION_TXT = ROOT / "build" / "version.txt"
SERVERS = ROOT / "solgukji_godot" / "data" / "servers.json"
DEV = "Dev"      # 집 PC 서버 —— 빌드할 때 이 PC 의 주소로 맞춘다


def load():
    return json.loads(CHANGELOG.read_text(encoding="utf-8"))


def save(d):
    CHANGELOG.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def next_ver(ver: str) -> str:
    m = re.fullmatch(r"(\d+)\.(\d+)([a-z])", ver)
    if not m:
        raise SystemExit(f"버전 꼴이 아니다: {ver} (예: 1.0a)")
    major, minor, letter = int(m[1]), int(m[2]), m[3]
    if letter == "z":
        return f"{major}.{minor + 1}a"
    return f"{major}.{minor}{chr(ord(letter) + 1)}"


def check(d):
    vs = d["versions"]
    if not vs:
        raise SystemExit("changelog 에 버전이 없다")
    codes = [v["code"] for v in vs]
    if codes != sorted(codes, reverse=True) or len(set(codes)) != len(codes):
        raise SystemExit(f"code 는 최신이 앞이고 서로 달라야 한다: {codes}")
    vers = [v["ver"] for v in vs]
    if len(set(vers)) != len(vers):
        raise SystemExit(f"같은 버전 이름이 두 번: {vers}")


def sync_presets(ver: str, code: int) -> bool:
    txt = PRESETS.read_text(encoding="utf-8")
    new = re.sub(r'^version/name="[^"]*"', f'version/name="{ver}"', txt, flags=re.M)
    new = re.sub(r"^version/code=\d+", f"version/code={code}", new, flags=re.M)
    if new != txt:
        PRESETS.write_text(new, encoding="utf-8", newline="\n")
        return True
    return False


def presets_match(ver: str, code: int) -> bool:
    txt = PRESETS.read_text(encoding="utf-8")
    names = set(re.findall(r'^version/name="([^"]*)"', txt, flags=re.M))
    codes = set(re.findall(r"^version/code=(\d+)", txt, flags=re.M))
    return names == {ver} and codes == {str(code)}


def write_html(d):
    vs = d["versions"]
    cur = vs[0]
    parts = []
    for i, v in enumerate(vs):
        groups = ""
        for g in v.get("groups", []):
            items = "".join(f"<li>{html.escape(it)}</li>" for it in g.get("items", []))
            groups += f"<h3>{html.escape(g.get('n', ''))}</h3><ul>{items}</ul>"
        tag = '<span class="tag now">지금 버전</span>' if i == 0 else ""
        parts.append(
            f'<section class="ver" id="v{html.escape(v["ver"])}">'
            f'<div class="head"><h2>{html.escape(v["ver"])}</h2>{tag}'
            f'<span class="date">{html.escape(v.get("date", ""))}</span>'
            f'<span class="code">code {v["code"]}</span></div>'
            f'<p class="title">{html.escape(v.get("title", ""))}</p>{groups}</section>'
        )
    toc = "".join(
        f'<a href="#v{html.escape(v["ver"])}">{html.escape(v["ver"])}</a>' for v in vs
    )
    page = f"""<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>솔국지 업데이트 내역</title>
<style>
:root{{--bg:#0f1420;--panel:#171e2e;--ink:#e8e2d2;--dim:#a99c80;--gold:#e0b45a;--jade:#7fd0bd;--seal:#e0806f;--line:#2a3348}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:15px/1.65 "Noto Sans KR","Malgun Gothic",sans-serif}}
main{{max-width:860px;margin:0 auto;padding:28px 16px 80px}}
h1{{font-size:28px;margin:0 0 4px;color:var(--gold)}}
.sub{{color:var(--dim);margin:0 0 18px}}
.toc{{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 24px}}
.toc a{{background:#222b3f;border:1px solid var(--line);border-radius:6px;padding:3px 10px;color:var(--ink);text-decoration:none;font-size:13.5px}}
.ver{{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px 18px;margin:14px 0}}
.head{{display:flex;flex-wrap:wrap;align-items:baseline;gap:10px}}
h2{{font-size:24px;margin:0;color:var(--gold)}}
.date,.code{{color:var(--dim);font-size:13px}}
.tag{{display:inline-block;font-size:12px;border-radius:4px;padding:0 7px;border:1px solid var(--jade);color:var(--jade)}}
.title{{margin:4px 0 6px;color:var(--ink);font-weight:600}}
h3{{font-size:15px;margin:14px 0 4px;color:var(--jade)}}
ul{{margin:0;padding-left:20px}}
li{{margin:2px 0}}
.foot{{color:var(--dim);font-size:13px;margin-top:30px}}
</style>
</head>
<body>
<main>
<h1>솔국지 업데이트 내역</h1>
<p class="sub">지금 버전 <b>{html.escape(cur["ver"])}</b> · {html.escape(cur.get("date", ""))} · 원본 <code>solgukji_godot/data/changelog.json</code> (게임 안 '기록 › 업데이트' 탭과 같은 내용)</p>
<nav class="toc">{toc}</nav>
{"".join(parts)}
<p class="foot">이 파일은 <code>tools/scripts/release.py</code> 가 만든다. 손으로 고치지 말고 changelog.json 을 고친 뒤 다시 돌린다.</p>
</main>
</body>
</html>
"""
    HTML.parent.mkdir(parents=True, exist_ok=True)
    HTML.write_text(page, encoding="utf-8", newline="\n")


def _usable_ip(ip: str) -> bool:
    """접속 주소로 쓸 수 있는 IPv4 —— 루프백(127.) · 링크 로컬(169.254.) · 0.0.0.0 · 멀티캐스트는 뺀다"""
    try:
        a = ipaddress.IPv4Address(ip)
    except ValueError:
        return False
    return not (a.is_loopback or a.is_link_local or a.is_unspecified or a.is_multicast)


def route_ip():
    """기본 경로(공유기로 나가는 인터페이스)의 IPv4 —— UDP 소켓을 바깥 주소로 connect 만 하면 운영체제가 경로를 골라
    내 쪽 주소가 정해진다 (UDP 의 connect 는 패킷을 보내지 않는다). 연결이 없으면 None"""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 53))
        ip = s.getsockname()[0]
    except OSError:
        return None
    finally:
        s.close()
    return ip if _usable_ip(ip) else None


def ipconfig_ip():
    """ipconfig 에서 기본 게이트웨이(IPv4)가 있는 어댑터의 IPv4 (한국어 · 영어 출력). 없으면 None"""
    try:
        raw = subprocess.run(["ipconfig"], capture_output=True, timeout=15).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    txt = None
    for enc in ("utf-8", "oem", "cp949"):      # 콘솔 코드 페이지 —— 한국어 윈도우는 cp949, chcp 65001 이면 utf-8
        try:
            txt = raw.decode(enc)
            break
        except (UnicodeDecodeError, LookupError):
            continue
    if txt is None:
        txt = raw.decode("utf-8", errors="replace")
    v4 = r"\d{1,3}(?:\.\d{1,3}){3}"
    for block in re.split(r"\r?\n(?=\S)", txt):      # 어댑터마다 —— 머리줄("이더넷 어댑터 이더넷:")만 들여쓰지 않는다
        ips = [ip for ip in re.findall(r"IPv4[^:\n]*:\s*(" + v4 + ")", block) if _usable_ip(ip)]
        lines = block.splitlines()
        gw = []
        for i, ln in enumerate(lines):
            if "게이트웨이" in ln or "Gateway" in ln:
                vals = [ln.split(":", 1)[1]] if ":" in ln else []
                for nx in lines[i + 1:]:      # IPv6 게이트웨이가 먼저 오면 IPv4 는 다음 줄에 이어진다
                    if not nx.strip() or " : " in nx or ". :" in nx:
                        break
                    vals.append(nx)
                gw = [v.strip() for v in vals if re.fullmatch(v4, v.strip())]
                break
        if ips and gw:
            return ips[0]
    return None


def sync_servers():
    """servers.json 의 Dev 주소에서 호스트만 이 PC 의 LAN IPv4 로 바꾼다 (스킴 · 포트는 그대로). 바뀐 때만 파일을 쓴다.
    돌려주는 값: 출력할 한 줄 (그대로거나 Dev 가 없으면 None)"""
    rel = SERVERS.relative_to(ROOT)
    if not SERVERS.exists():
        return f"{rel} 이 없다 —— {DEV} 서버 주소는 건너뜀"
    try:
        d = json.loads(SERVERS.read_text(encoding="utf-8"))
    except ValueError as e:
        raise SystemExit(f"{rel} 을 읽지 못했다: {e}")
    servers = d.get("servers", []) if isinstance(d, dict) else []
    dev = next((s for s in servers if isinstance(s, dict) and s.get("name") == DEV), None)
    if dev is None:
        return None
    old = str(dev.get("url", ""))
    if dev.get("lock"):      # 11/9 집 PC 서버 주소를 고정 —— 다른 PC 에서 빌드해도 덮어쓰지 않는다
        return None
    ip = route_ip() or ipconfig_ip()
    if ip is None:
        return f"{DEV} 서버 주소: 이 PC 의 IPv4 를 찾지 못해 그대로 둔다 ({old})"
    m = re.fullmatch(r"(wss?://)([^/:]+)(:\d+)?(/.*)?", old)
    new = f"{m[1]}{ip}{m[3] or ''}{m[4] or ''}" if m else f"ws://{ip}:7777"
    if new == old:
        return None
    dev["url"] = new
    SERVERS.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    return f"{DEV} 서버 주소 {old} → {new} ({rel})"


def main(argv):
    d = load()
    if "--next" in argv:
        i = argv.index("--next")
        title = argv[i + 1] if i + 1 < len(argv) else ""
        cur = d["versions"][0]
        import datetime
        d["versions"].insert(0, {
            "ver": next_ver(cur["ver"]), "code": cur["code"] + 1,
            "date": datetime.date.today().isoformat(), "title": title,
            "groups": [{"n": "변경", "items": []}],
        })
        save(d)
        print(f"새 버전 항목 {d['versions'][0]['ver']} (code {d['versions'][0]['code']}) 를 changelog.json 맨 앞에 넣었다. items 를 채워라.")
    check(d)
    cur = d["versions"][0]
    if "--check" in argv:
        ok = presets_match(cur["ver"], cur["code"])
        print(("맞음" if ok else "안 맞음") + f": changelog {cur['ver']} / code {cur['code']}")
        return 0 if ok else 1
    changed = sync_presets(cur["ver"], cur["code"])
    write_html(d)
    VERSION_TXT.parent.mkdir(parents=True, exist_ok=True)
    VERSION_TXT.write_text(cur["ver"], encoding="ascii")
    print(f"버전 {cur['ver']} (code {cur['code']}) —— export_presets.cfg {'고침' if changed else '그대로'} · {HTML.relative_to(ROOT)} 생성")
    note = sync_servers()
    if note:
        print(note)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
