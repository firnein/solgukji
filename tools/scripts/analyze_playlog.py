# 플레이 기록 분석 (11/5 사용자: 게임이 어디서 쉬워지는지 판단할 수 있게)
# 게임(PlayLog, scripts/game/play_log.gd)이 남긴 user://playlog/*.jsonl 을 읽어 HTML 보고서를 만든다.
# 봇 기준선(tests/play_log_bot.tscn → user://playlog_bot)이 있으면 나란히 비교한다.
# 실행: python tools/scripts/analyze_playlog.py [--logs 폴더] [--bot 폴더] [--out build/플레이_분석.html]
import argparse, glob, html, json, os, statistics as st
from collections import Counter, defaultdict

APP = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "솔국지")
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PHASE = ["오전", "오후", "저녁"]
DAY = ["월", "화", "수", "목", "금", "토", "일"]
TIER = {1: "기본", 2: "일반", 3: "희귀", 4: "영웅", 5: "전설", 6: "초월", 7: "불멸", 8: "신화"}
KIND = {"quest": "토벌", "pvp": "대전", "tour": "토너먼트"}
TOUR_ROUND = ["8강", "4강", "결승"]

# 판정 기준 —— 이긴 전투의 '여유' = 내 잔존 병력비 − 적 잔존 병력비
EASY = 0.55       # 이만큼 여유 있게 이기면 '압승'
CLOSE = 0.2       # 이 아래 여유로 이기면 '신승'


def load(folder):
    games = []
    for path in sorted(glob.glob(os.path.join(folder, "*.jsonl"))):
        evs = []
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        evs.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
        if evs:
            games.append({"file": os.path.basename(path), "ev": evs})
    return games


def slot(e):
    return int(e.get("day", 0)) * 3 + int(e.get("phase", 0))


def slot_name(s):
    return "%s %s" % (DAY[min(6, s // 3)], PHASE[s % 3])


def battles(game):
    """battle_start 와 battle_end 를 짝지어 전투 목록으로"""
    out = []
    cur = None
    tour_i = 0
    for e in game["ev"]:
        if e["ev"] == "battle_start":
            cur = e
        elif e["ev"] == "battle_end":
            b = dict(e)
            if cur is not None:
                b["start"] = cur
            if b.get("kind") == "tour":
                b["round"] = tour_i
                tour_i += 1
            b["margin"] = float(e.get("left_ratio", 0)) - float(e.get("foe_left_ratio", 0))
            b["tr_ratio"] = float(cur.get("tr_ratio", 0)) if cur else 0.0
            out.append(b)
            cur = None
    return out


def grade(b):
    if b.get("draw"):
        return "무"
    if not b.get("win"):
        return "패"
    if b["margin"] >= EASY:
        return "압승"
    if b["margin"] < CLOSE:
        return "신승"
    return "승"


def summary(games):
    rows = []
    for g in games:
        evs = g["ev"]
        over = next((e for e in reversed(evs) if e["ev"] == "over"), None)
        bs = battles(g)
        t0 = evs[0]["ts"]
        t1 = evs[-1]["ts"]
        play = sum(float(e.get("sec", 0)) for e in evs if e["ev"] == "phase_end")
        rows.append({"file": g["file"], "seed": evs[0].get("seed", ""), "end": slot_name(slot(evs[-1])),
                     "result": ("승리 · " if over and over.get("win") else "패배 · ") + (over.get("msg", "") if over else "진행 중"),
                     "w": sum(1 for b in bs if b.get("win")), "l": sum(1 for b in bs if not b.get("win")),
                     "min": (play or (t1 - t0)) / 60.0, "battles": len(bs)})
    return rows


def per_slot(games):
    """일차 · 페이즈 · 전투 종류마다 모은다"""
    acc = defaultdict(list)
    for g in games:
        for b in battles(g):
            k = b.get("kind", "")
            key = (slot(b), k if k != "tour" else "tour")
            acc[key].append(b)
    return acc


def easy_point(acc, kind):
    """이 지점부터 끝까지 이 종류 전투를 (거의) 다 이기고, 여유도 크면 '쉬워진 지점'"""
    slots = sorted(s for (s, k) in acc if k == kind)
    for i, s in enumerate(slots):
        rest = [b for t in slots[i:] for b in acc[(t, kind)]]
        if len(rest) < 3:
            break
        wr = sum(1 for b in rest if b.get("win")) / len(rest)
        mg = st.mean(b["margin"] for b in rest if b.get("win")) if any(b.get("win") for b in rest) else 0
        if wr >= 0.9 and mg >= 0.45:
            return s, wr, mg
    return None


def fmt_pct(x):
    return "%d%%" % round(x * 100)


def cell_color(wr, mg):
    if wr is None:
        return "#1b2233"
    if wr >= 0.9 and mg >= EASY:
        return "#1f5d43"     # 쉬움
    if wr >= 0.7:
        return "#2a4a3a"
    if wr >= 0.4:
        return "#4a4426"
    return "#5a2a2a"         # 어려움


def svg_lines(series, w=640, h=220, ymax=None, label_y="", ref=None):
    """series: [(이름, 색, [(x, y)…])] —— x 는 슬롯 번호 0~20"""
    pts = [p for _, _, s in series for p in s]
    if not pts:
        return "<p class=dim>자료 없음</p>"
    ymax = ymax or max(1e-9, max(y for _, y in pts)) * 1.1
    pad_l, pad_b = 46, 26
    X = lambda x: pad_l + (w - pad_l - 10) * x / 20.0
    Y = lambda y: (h - pad_b) - (h - pad_b - 8) * min(y, ymax) / ymax
    out = ['<svg viewBox="0 0 %d %d" class="chart">' % (w, h)]
    for i in range(5):
        yv = ymax * i / 4
        out.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" class="grid"/>' % (pad_l, w - 10, Y(yv), Y(yv)))
        out.append('<text x="%d" y="%.1f" class="ax" text-anchor="end">%s</text>' % (pad_l - 4, Y(yv) + 4, ("%.2f" % yv) if ymax < 10 else "{:,}".format(int(yv))))
    for d in range(7):
        out.append('<text x="%.1f" y="%d" class="ax" text-anchor="middle">%s</text>' % (X(d * 3 + 1), h - 6, DAY[d]))
    if ref is not None:
        out.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" class="ref"/>' % (pad_l, w - 10, Y(ref), Y(ref)))
    for name, col, s in series:
        s = sorted(s)
        if len(s) > 1:
            out.append('<polyline fill="none" stroke="%s" stroke-width="2.2" points="%s"/>' % (col, " ".join("%.1f,%.1f" % (X(x), Y(y)) for x, y in s)))
        for x, y in s:
            out.append('<circle cx="%.1f" cy="%.1f" r="3" fill="%s"><title>%s %s: %.2f</title></circle>' % (X(x), Y(y), col, name, slot_name(x), y))
    out.append('<text x="%d" y="12" class="ax">%s</text>' % (pad_l, html.escape(label_y)))
    out.append("</svg>")
    leg = " ".join('<span class="leg" style="--c:%s">%s</span>' % (c, html.escape(n)) for n, c, _ in series)
    return "".join(out) + '<div class="legend">%s</div>' % leg


def mean_by_slot(acc, kind, f):
    pts = []
    for (s, k), bs in acc.items():
        if k == kind and bs:
            vals = [f(b) for b in bs]
            pts.append((s, st.mean(vals)))
    return pts


def deck_stats(games):
    """덱 등급 · 병종 구성 (페이즈 끝 기준) · 병종별 피해 몫 · 병종별 MVP"""
    tier_by_slot = defaultdict(Counter)
    tag_total = Counter()
    gen_use = Counter()
    for g in games:
        for e in g["ev"]:
            if e["ev"] == "phase_end":
                for c in e.get("deck", {}).get("cards", []):
                    if len(c) >= 3:
                        tier_by_slot[slot(e)][int(c[1])] += 1
                        tag_total[c[2]] += 1
                        gen_use[c[0]] += 1
    dmg_tag = Counter()
    taken_tag = Counter()
    n_tag = Counter()
    for g in games:
        for b in battles(g):
            for u in b.get("units", []):
                if u.get("camp") == "A":
                    dmg_tag[u["tag"]] += u.get("dmg", 0)
                    taken_tag[u["tag"]] += u.get("taken", 0)
                    n_tag[u["tag"]] += 1
    return tier_by_slot, tag_total, gen_use, dmg_tag, taken_tag, n_tag


def first_tier_slot(games, tier):
    """덱에 그 등급이 처음 들어간 페이즈 (판마다)"""
    out = []
    for g in games:
        for e in g["ev"]:
            if e["ev"] == "phase_end" and any(len(c) >= 2 and int(c[1]) >= tier for c in e.get("deck", {}).get("cards", [])):
                out.append(slot(e))
                break
    return out


def time_stats(games):
    page = Counter()
    phase_sec = defaultdict(list)
    speed = Counter()
    ult = cmd = nb = 0
    acts = defaultdict(Counter)
    for g in games:
        for e in g["ev"]:
            if e["ev"] == "phase_end":
                phase_sec[slot(e)].append(float(e.get("sec", 0)))
                for k, v in (e.get("page_sec") or {}).items():
                    page[k] += float(v)
            elif e["ev"] == "battle_end":
                nb += 1
                ult += int(e.get("ult_inputs", 0))
                cmd += int(e.get("cmd_inputs", 0))
                for k, v in (e.get("speeds") or {}).items():
                    speed[k] += float(v)
            elif e["ev"] == "act":
                acts[slot(e)][e.get("m", "")] += 1
    return page, phase_sec, speed, ult, cmd, nb, acts


def section_slots(acc, acc_bot, title):
    kinds = ["quest", "pvp"]
    rows = []
    for s in range(21):
        tds = ['<td class="sl">%s</td>' % slot_name(s)]
        for k in kinds:
            for src in (acc, acc_bot):
                bs = src.get((s, k), [])
                if not bs:
                    tds.append('<td class="c" style="background:#141a28">—</td>')
                    continue
                wr = sum(1 for b in bs if b.get("win")) / len(bs)
                wins = [b["margin"] for b in bs if b.get("win")]
                mg = st.mean(wins) if wins else 0.0
                trr = st.mean(b["tr_ratio"] for b in bs)
                g = Counter(grade(b) for b in bs)
                tip = " · ".join("%s %d" % (x, n) for x, n in g.most_common())
                tds.append('<td class="c" style="background:%s" title="%s"><b>%s</b> <span class=dim>%d판</span><br>여유 %s · 전력비 %.2f</td>'
                           % (cell_color(wr, mg), tip, fmt_pct(wr), len(bs), fmt_pct(mg), trr))
        rows.append("<tr>%s</tr>" % "".join(tds))
    head = ('<tr><th rowspan=2>시점</th><th colspan=2>토벌</th><th colspan=2>대전</th></tr>'
            '<tr><th>나</th><th>봇</th><th>나</th><th>봇</th></tr>')
    return "<h2>%s</h2><p class=dim>칸 = 승률 · 이긴 판의 평균 여유(내 잔존 병력비 − 적 잔존 병력비) · 평균 전력비(내 병력 ÷ 적 병력). "\
           "초록이 짙을수록 쉽다(승률 90%%↑ · 여유 %d%%↑), 붉을수록 어렵다. 칸에 마우스를 올리면 압승 · 승 · 신승 · 패 수.</p>"\
           "<table class=grid>%s%s</table>" % (title, EASY * 100, head, "".join(rows))


def battle_list(games):
    rows = []
    for g in games:
        for b in battles(g):
            stt = b.get("start", {})
            me = stt.get("me", {})
            foe = stt.get("foe", {})
            tiers = Counter(int(c[1]) for c in me.get("cards", []) if len(c) >= 2)
            top = " ".join("%s%d" % (TIER.get(t, t)[0], n) for t, n in sorted(tiers.items(), reverse=True))
            kind = KIND.get(b.get("kind", ""), b.get("kind", ""))
            if b.get("kind") == "tour":
                kind += " " + TOUR_ROUND[min(2, b.get("round", 0))]
            gr = grade(b)
            rows.append("<tr class='%s'><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%.2f</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%d · %d</td><td>%s</td></tr>" % (
                {"압승": "easy", "패": "lose", "신승": "close"}.get(gr, ""), g["file"][:15], slot_name(slot(b)), kind,
                html.escape(stt.get("title", "")), gr, b["tr_ratio"], fmt_pct(b.get("left_ratio", 0)), fmt_pct(b.get("foe_left_ratio", 0)),
                html.escape(top), html.escape(stt.get("tac", "")), b.get("ult_inputs", 0), b.get("cmd_inputs", 0), html.escape(b.get("mvp", ""))))
    return ("<h2>전투 목록</h2><table class=list><tr><th>판</th><th>시점</th><th>종류</th><th>상대</th><th>결과</th><th>전력비</th>"
            "<th>내 잔존</th><th>적 잔존</th><th>내 덱 등급</th><th>작전</th><th>고유기·군령</th><th>MVP</th></tr>%s</table>" % "".join(rows))


def findings(acc, acc_bot, games, bots):
    out = []
    for kind in ("quest", "pvp"):
        ep = easy_point(acc, kind)
        nm = KIND[kind]
        if ep:
            out.append("<b>%s</b>은 <b>%s</b>부터 쉬워진다 —— 그 뒤 승률 %s · 이긴 판 평균 여유 %s." % (nm, slot_name(ep[0]), fmt_pct(ep[1]), fmt_pct(ep[2])))
        else:
            out.append("<b>%s</b>은 끝까지 '쉬워지는 지점'이 없다 (그 뒤로 승률 90%%↑ · 여유 45%%↑ 가 이어지는 구간이 없다)." % nm)
        epb = easy_point(acc_bot, kind)
        if epb and ep:
            d = ep[0] - epb[0]
            out.append("&nbsp;&nbsp;봇은 %s부터 —— 사람이 %s." % (slot_name(epb[0]), "%d페이즈 늦다" % d if d > 0 else ("%d페이즈 빠르다" % -d if d < 0 else "같다")))
    # 패배가 몰린 시점
    loss = Counter()
    for (s, k), bs in acc.items():
        if k in ("quest", "pvp"):
            loss[s] += sum(1 for b in bs if not b.get("win"))
    if loss and max(loss.values()) > 0:
        s, n = loss.most_common(1)[0]
        out.append("패배가 가장 많이 몰린 시점: <b>%s</b> (%d번)." % (slot_name(s), n))
    # 높은 등급이 처음 덱에 들어간 시점과 그 뒤 승률
    for t in (6, 7, 8):
        fs = first_tier_slot(games, t)
        if fs:
            out.append("%s 첫 편성: 평균 %s (판 %d개 중 %d개)." % (TIER[t], slot_name(round(st.mean(fs))), len(games), len(fs)))
    # 토너먼트
    tw = Counter()
    for g in games:
        for b in battles(g):
            if b.get("kind") == "tour":
                tw[(b.get("round", 0), bool(b.get("win")))] += 1
    if tw:
        out.append("토너먼트: " + " · ".join("%s %d승 %d패" % (TOUR_ROUND[r], tw[(r, True)], tw[(r, False)]) for r in range(3) if tw[(r, True)] + tw[(r, False)]))
    return "<ul class=find>%s</ul>" % "".join("<li>%s</li>" % x for x in out)


def build(games, bots):
    acc = per_slot(games)
    acc_bot = per_slot(bots)
    css = """
    :root{--bg:#0d111b;--fg:#e6e2d6;--dim:#8b93a6;--line:#2a3247;--gold:#d8b56a}
    body{background:var(--bg);color:var(--fg);font:14px/1.5 'Malgun Gothic',sans-serif;margin:0;padding:20px 16px 60px;max-width:1100px;margin:auto}
    h1{color:var(--gold);font-size:22px}h2{color:var(--gold);font-size:17px;margin-top:34px;border-bottom:1px solid var(--line);padding-bottom:4px}
    .dim{color:var(--dim);font-size:12px}table{border-collapse:collapse;width:100%;font-size:12.5px}
    th,td{border:1px solid var(--line);padding:4px 6px;text-align:left}th{background:#18203a}
    table.grid td.c{text-align:center;min-width:110px}td.sl{white-space:nowrap}
    tr.easy td{background:#14301f}tr.lose td{background:#341818}tr.close td{background:#302c14}
    .chart{width:100%;max-width:700px;background:#111728;border:1px solid var(--line);border-radius:6px}
    .grid line,.chart .grid{stroke:#232b40}.chart .ref{stroke:#d8b56a;stroke-dasharray:4 4}.chart .ax{fill:#8b93a6;font-size:10px}
    .legend{margin:4px 0 10px}.leg{margin-right:14px;font-size:12px}.leg:before{content:'';display:inline-block;width:10px;height:10px;background:var(--c);margin-right:5px;border-radius:2px}
    ul.find li{margin:4px 0}.bar{display:inline-block;height:10px;background:var(--gold);vertical-align:middle;border-radius:2px}
    .scroll{overflow-x:auto}
    """
    h = ["<!doctype html><html lang=ko><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>",
         "<title>플레이 분석</title><style>%s</style></head><body>" % css,
         "<h1>솔국지 플레이 분석</h1><p class=dim>사람 판 %d개 · 봇 기준선 %d개. 기록: user://playlog (사람) · user://playlog_bot (봇, tests/play_log_bot.tscn)</p>" % (len(games), len(bots))]
    if not games:
        h.append("<p>사람 플레이 기록이 아직 없다. PC 에서 한 판 하고 다시 돌리면 된다.</p>")
    # 판 요약
    rows = "".join("<tr><td>%s</td><td>%s</td><td>%s</td><td>%d승 %d패</td><td>%.0f분</td><td>%s</td></tr>" % (
        r["file"], r["seed"], r["end"], r["w"], r["l"], r["min"], html.escape(r["result"])) for r in summary(games))
    h.append("<h2>판 요약</h2><table class=list><tr><th>파일</th><th>시드</th><th>끝난 시점</th><th>전투</th><th>플레이 시간</th><th>결과</th></tr>%s</table>" % rows)
    h.append("<h2>한눈에</h2>" + findings(acc, acc_bot, games, bots))
    h.append('<div class=scroll>%s</div>' % section_slots(acc, acc_bot, "시점별 난이도"))
    # 곡선
    h.append("<h2>전력비 · 여유 곡선</h2><p class=dim>전력비 = 내 편성 병력 ÷ 적 편성 병력 (1.0 = 같다). 여유 = 내 잔존 병력비 − 적 잔존 병력비 (−1 ~ 1, 크게 이길수록 1).</p>")
    h.append(svg_lines([("토벌 · 나", "#6fd39a", mean_by_slot(acc, "quest", lambda b: b["tr_ratio"])),
                        ("대전 · 나", "#6aa8ff", mean_by_slot(acc, "pvp", lambda b: b["tr_ratio"])),
                        ("토벌 · 봇", "#3b7656", mean_by_slot(acc_bot, "quest", lambda b: b["tr_ratio"])),
                        ("대전 · 봇", "#3b5c8c", mean_by_slot(acc_bot, "pvp", lambda b: b["tr_ratio"]))],
                       label_y="전력비", ref=1.0))
    h.append(svg_lines([("토벌 · 나", "#6fd39a", mean_by_slot(acc, "quest", lambda b: b["margin"] + 1)),
                        ("대전 · 나", "#6aa8ff", mean_by_slot(acc, "pvp", lambda b: b["margin"] + 1)),
                        ("토벌 · 봇", "#3b7656", mean_by_slot(acc_bot, "quest", lambda b: b["margin"] + 1)),
                        ("대전 · 봇", "#3b5c8c", mean_by_slot(acc_bot, "pvp", lambda b: b["margin"] + 1))],
                       ymax=2.0, label_y="여유 + 1 (1 = 비김, 2 = 전멸 없이 압승)", ref=1.0 + EASY))
    # 덱
    tier_by_slot, tag_total, gen_use, dmg_tag, taken_tag, n_tag = deck_stats(games)
    if tier_by_slot:
        rows = []
        for s in sorted(tier_by_slot):
            c = tier_by_slot[s]
            tot = sum(c.values()) or 1
            rows.append("<tr><td>%s</td>%s</tr>" % (slot_name(s), "".join(
                "<td>%s</td>" % (("%.1f" % (c[t] / max(1, len([1 for g in games if any(e['ev'] == 'phase_end' and slot(e) == s for e in g['ev'])])))) if c[t] else "") for t in range(8, 0, -1))))
        h.append("<h2>덱 등급 구성 (페이즈 끝, 판 평균 장수)</h2><table class=list><tr><th>시점</th>%s</tr>%s</table>"
                 % ("".join("<th>%s</th>" % TIER[t] for t in range(8, 0, -1)), "".join(rows)))
    if n_tag:
        tot_d = sum(dmg_tag.values()) or 1
        tot_n = sum(n_tag.values()) or 1
        rows = []
        for tag, n in n_tag.most_common():
            share_d = dmg_tag[tag] / tot_d
            share_n = n / tot_n
            rows.append("<tr><td>%s</td><td>%s</td><td><span class=bar style='width:%dpx'></span> %s</td><td>%.2f</td><td>{:,}</td></tr>".format(int(taken_tag[tag] / n))
                        % (tag, fmt_pct(share_n), int(share_d * 300), fmt_pct(share_d), share_d / max(1e-9, share_n)))
        h.append("<h2>내 병종이 한 일</h2><p class=dim>피해 효율 = 피해 몫 ÷ 출전 몫 (1.0 = 제 몫). 받은 피해는 출전 한 번 평균.</p>"
                 "<table class=list><tr><th>병종</th><th>출전 몫</th><th>준 피해 몫</th><th>피해 효율</th><th>받은 피해</th></tr>%s</table>" % "".join(rows))
    if gen_use:
        h.append("<h2>자주 쓴 장수 (페이즈 끝 편성 횟수)</h2><p>%s</p>" % " · ".join("%s %d" % (html.escape(k), n) for k, n in gen_use.most_common(24)))
    # 시간 · 행동
    page, phase_sec, speed, ult, cmd, nb, acts = time_stats(games)
    if phase_sec:
        h.append(svg_lines([("페이즈 시간 (초)", "#d8b56a", [(s, st.mean(v)) for s, v in phase_sec.items()])], label_y="페이즈마다 걸린 초 (판 평균)"))
    if page:
        tot = sum(page.values()) or 1
        h.append("<h2>탭에 머문 시간</h2><p>%s</p>" % " · ".join("%s %s" % (k, fmt_pct(v / tot)) for k, v in page.most_common()))
    if speed:
        tot = sum(speed.values()) or 1
        h.append("<h2>전투 배속</h2><p>%s · 전투 %d번에 고유기 직접 발동 %d번 · 군령 %d번</p>" % (
            " · ".join("%s배속 %s" % (k.rstrip("0").rstrip(".") if "." in k else k, fmt_pct(v / tot)) for k, v in speed.most_common()), nb, ult, cmd))
    if acts:
        names = ["do_draw", "pick", "random_grant", "forge", "pick_unique", "place", "unplace", "swap", "auto_deploy", "set_form", "set_tac", "set_equip"]
        kor = {"do_draw": "징집", "pick": "선택", "random_grant": "보급", "forge": "조합", "pick_unique": "유니크", "place": "배치", "unplace": "빼기",
               "swap": "자리바꿈", "auto_deploy": "자동편성", "set_form": "진형", "set_tac": "작전", "set_equip": "장비"}
        n_games = max(1, len(games))
        rows = "".join("<tr><td>%s</td>%s</tr>" % (slot_name(s), "".join("<td>%s</td>" % (("%.1f" % (acts[s][m] / n_games)) if acts[s][m] else "") for m in names)) for s in sorted(acts))
        h.append("<h2>행동 (판 평균 횟수)</h2><div class=scroll><table class=list><tr><th>시점</th>%s</tr>%s</table></div>" % ("".join("<th>%s</th>" % kor[m] for m in names), rows))
    h.append(battle_list(games))
    h.append("</body></html>")
    return "".join(h)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--logs", default=os.path.join(APP, "playlog"))
    ap.add_argument("--bot", default=os.path.join(APP, "playlog_bot"))
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "플레이_분석.html"))
    a = ap.parse_args()
    games = load(a.logs)
    bots = load(a.bot)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        f.write(build(games, bots))
    print("사람 %d판 · 봇 %d판 → %s" % (len(games), len(bots), a.out))
