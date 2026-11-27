extends RefCounted
## 11/27 장수 키트 Q · W · E · R · P 발동 표시 (삽화 화면) —— 사용자: 「아 쟤가 q 스킬이 발동이 됐구나, e 가 발동이 됐구나를 알 수 있어야 함」.
## 실제 플레이에서 일반 기술 · 도발이 발동해도 "썼다 · 당했다"를 아무도 알아채지 못했다 (이름 현판은 일부 장수만, 색 · 모양 구분 없음).
## 엔진 사건만 보고 그린다 —— 판정 · 수치와 무관한 화면 연출. 노드를 만들지 않고 WarPainting 의 위층(TopEffects._draw)에 얹는다.
##
## 칸마다 색(Kit.SLOT_COL)과 모양이 다르다 (색맹 · 작은 화면에서도 갈리게):
##   Q 파랑 —— 한 줄 베기 자국        W 초록 —— 두 겹 고리        E 보라 —— 세모
##   R 금   —— 햇살 눈금 고리 · 여덟 갈래 별        P 주황 —— 마름모
##   시전: 장수 발밑에서 칸 색 붓 고리가 퍼지고 몸에서 번쩍 + 칸 모양.   맞은 부대: 시전자에게서 짧은 빛줄기 → 머리 위 칸 모양 표식 + 발밑 고리
##   맞은 표식의 받침은 아군이 쓴 것이면 먹빛, 적이 쓴 것(당했다)이면 검붉다
##
## 강화 (11/27 저녁 새 방식 —— 칸마다 그 장수 고유의 효과 하나 · 장수당 최대 2칸. scripts/kit.gd 「새 방식」 · data/kit.json)
##   사건의 "up": true = 강화된 칸의 발동 —— 고리가 더 크고 바깥에 한 겹 더, 번쩍임에 여덟 갈래 섬광, 맞은 표식에 가는 테 (딱지에는 겹테두리 + ◆)
##   사건의 "kup": 강화 이름 = 강화 효과가 실제로 발동 —— 받은 부대에서 칸 색 두 겹 고리 · 큰 번쩍임 · 도는 별 (add_burst). 이름 글씨는 HUD 가 띄운다
##
## 상태 (11/27 —— 삽화 화면에는 메달 아래 상태 딱지 줄이 없어 아래 상태가 전장에서 보이지 않았다):
##   봉인(seal) 자물쇠 · 도발(taunted) 성난 표시 · 불사(undying) 금빛 심장 + 발밑 금 고리 —— 머리 오른쪽에 작은 기호로
##   출혈(bleed) 몸에 붉은 할퀸 자국 + 떨어지는 핏방울 · 역병(plague) 떠오르는 풀빛 거품 · 은신(stealth · hide) 발밑 먹 구름 (그늘은 WarPainting._cover_step)
##   밀려남(add_shove) —— 밀린 쪽 반대로 흙먼지와 속도선 셋, 병사 · 장수는 돌아서지 않고 움찔하며 밀린다
##
## 그림 자산 (docs/코덱스_요청_키트.md) —— res://assets/kit/ 에 파일이 있으면 코드 그림 대신 그것을 쓴다 (없으면 코드 그림 · 넣기만 하면 바뀐다):
##   slot_<칸>.png 칸 문장 · cast_<칸>.png 시전 이펙트(가로 띠 시트) · hit_<칸>.png 맞은 표식(한 장 또는 가로 띠)
##   up.png 「강화됨」 표식(흰 그림 —— 칸 색을 입힌다) · kup.png 강화 효과 발동 이펙트(흰 가로 띠 시트 —— 칸 색을 입힌다. kup_<칸>.png 가 있으면 그 색 그대로)
##
## 머리 위 딱지(글자 + 기술 이름 + ◆)와 강화 이름 글씨는 HUD 가 그린다 (battle_view.gd Hud.kit_tag · kit_pop) —— 여기의 baked · draw_pill · draw_chip · draw_up 을 같이 쓴다.
##
## 프레임 부담 (11/27 실측: 신화 11명이 초당 6번 넘게 쓰는 판에서 처음 구현은 그리기 명령을 만드는 데만 프레임당 1.6ms 를 썼다 ——
##   둥근 상자(StyleBoxFlat) · 다각형 삼각 분할 · 안티에일리어싱 꺾은선 · 원은 명령마다 정점 버퍼를 새로 만든다):
##   고리는 붓 원상 그림(assets/fx/ink/enso) 한 장을 눌러 그리고, 받침 · 작은 고리는 구운 그림(baked), 나머지는 선 · 세모 · 네모 기본 도형만 쓴다 (다각형 명령 없음).
##   그릴 것을 그림별로 모았다가 한꺼번에 낸다(_flush) —— 같은 그림의 네모는 렌더러가 한 번에 그린다.
##   한 화면에 고리 MAX_CASTS · 표식 MAX_MARKS 까지. 부하 조절 2단계부터 빛줄기 · 발밑 고리 · 먹 밑그림을 빼고 표식은 여덟, 3단계부터 넷.

const Kit := preload("res://scripts/kit.gd")

var p                       # WarPainting
var casts: Array = []       # {key, slot, up, start, hit, end, col, dsts: [부대 key], sd}
var bursts: Array = []      # 강화 효과 발동 {key(받은 부대), src(시전 부대), slot, col, start, sd}
var shoves: Array = []      # 밀려남 {key, dir(전장 방향), start}
var stats := {"cast": 0, "hit": 0, "skip": 0, "peak": 0, "by": {}, "burst": 0, "shove": 0, "state": {}}      # 점검용 (tests/kit_fx_shot)
var draw_us := 0            # 점검용 —— 그리기에 쓴 시간 합(µs) · 그린 횟수
var draw_n := 0
var count_states := false   # 점검용 —— 상태 기호를 그린 횟수를 stats.state 에 센다
var _marks := 0             # 이번 그리기에서 그린 맞은 표식 수
var _queued := false        # 이번 그리기에 모은 것이 있다
var _q_tex := {}            # 그림 이름 -> [가운데, 크기, 색, 돌림, 늘림, 땅에 눕힘] 을 이어 붙인 배열 (한 프레임 모았다가 _flush)
var _q_line: Array = []     # [a, b, 색, 굵기, 안티에일리어싱] 이어 붙임
var _q_prim: Array = []     # [점들(셋 · 넷), 색] 이어 붙임
var _q_sheet: Array = []    # [그림(assets/kit), 가운데, 크기, 진행 0~1, 색] 이어 붙임

const MAX_CASTS := 10
const MAX_DSTS := 9
const MAX_LINKS := 5
const MAX_MARKS := 7        # 한 화면에 그리는 맞은 표식 (새 발동부터 센다)
const MAX_BURSTS := 6
const MAX_SHOVES := 8
const CAST_LIFE := 0.9       # 시전 고리 · 번쩍임 · 칸 모양 (전장 초) —— 11/27 저녁: 발동이 드물어져(재사용 대기 5 ~ 13초) 하나하나를 더 길고 크게
const HIT_LIFE := 0.9        # 맞은 표식
const BURST_LIFE := 0.95     # 강화 효과 발동
const SHOVE_LIFE := 0.5      # 밀려남 (길 기록 한 칸 0.4초 동안 미끄러진다)
const LINK_TRAVEL := 0.18    # 시전자 → 대상 빛줄기가 닿는 시간 (맞는 순간에 닿는다)
const HIT_STAGGER := 0.04    # 대상마다 조금씩 늦게
const INK := Color("#29271f")
const ENSO_FILL := 0.78      # 원상 그림에서 고리가 차지하는 폭 (그림 한 변 대비)
## 은신으로 읽는 상태 이름 (엔진이 사건 스냅숏의 상태 목록에 넣어 주면 뜬다)
const STEALTH_KEYS := ["stealth", "hide"]
const ICON_D := 20.0         # 상태 기호(봉인 · 도발 · 불사) 받침 지름 (화면 px)

const ASSET_DIR := "res://assets/kit/"
## 둥근 받침 그림 (머리 위 딱지) —— 3배로 굽고 1/3 로 그린다 (휴대폰 고해상도에서도 모서리가 또렷하게)
const PILL_N := 48
const PILL_R := 18.0         # 모서리 반지름 (그림 px —— 화면에서는 6)
const PILL_B := 6.0          # 테두리 굵기 (그림 px —— 화면에서는 2)
const PILL_K := 3.0
## 모아 그리는 차례 (아래 → 위): 땅의 구름 · 고리 → 땅의 별 → 받침 → 작은 고리 · 네모 · 붓 획 · 할퀸 자국 · 별 → (assets/kit 그림 · 세모 · 네모 · 선) → 불꽃
const TEX_UNDER := ["cloud", "enso_0", "enso_1", "gstar", "disc", "ring", "fill", "brush_0", "claw", "star"]
const TEX_OVER := ["dot"]

static var _tex := {}
static var _pill: Array = []
static var _no_uv := PackedVector2Array()


func _init(painter) -> void:
	p = painter


func reset() -> void:
	casts.clear()
	bursts.clear()
	shoves.clear()
	stats = {"cast": 0, "hit": 0, "skip": 0, "peak": 0, "by": {}, "burst": 0, "shove": 0, "state": {}}
	draw_us = 0
	draw_n = 0


func prune(clock: float) -> void:
	if not casts.is_empty():
		casts = casts.filter(func(c): return clock < float(c.end) and clock >= float(c.start) - 5.0)
		stats.peak = maxi(int(stats.peak), casts.size())
	if not bursts.is_empty():
		bursts = bursts.filter(func(b): return clock < float(b.start) + BURST_LIFE and clock >= float(b.start) - 1.0)
	if not shoves.is_empty():
		shoves = shoves.filter(func(s): return clock < float(s.start) + SHOVE_LIFE and clock >= float(s.start) - 1.0)


# ───────── 함께 쓰는 것 (HUD · 삽화 · 점검) ─────────

## assets/kit/<이름>.png —— 있으면 그림, 없으면 null (한 번만 찾는다)
static func tex(nm: String) -> Texture2D:
	if not _tex.has(nm):
		var path := ASSET_DIR + nm + ".png"
		_tex[nm] = load(path) if ResourceLoader.exists(path) else null
	return _tex[nm]


static func slot_col(slot: String) -> Color:
	return Color(str(Kit.SLOT_COL.get(slot, "#ffe9a8")))


## 그 사건이 어느 칸의 발동인가 —— {slot, up(강화된 칸인가), name} · 아니면 빈 사전. cid = 그 사건을 일으킨 부대의 카드 id
## 사건에 "slot" 이 있으면 그대로 (엔진 약속 —— scripts/kit.gd 「새 방식」). 없으면(옛 서버 결과) 대비책:
##   키트 장수의 기술 이름이 Kit.cell(카드, q · w · e).n 과 같으면 그 칸 (옛 결과는 카드 기술 sks 이름으로도 맞춰 본다), 고유기(ult · ult_warn · ult_join)면 r, 개성 말풍선(sig)이면 p
## 강화: "up": true. 단 buff · debuff 사건의 up 은 예전부터 「올림 / 깎음」 뜻이라 읽지 않는다 —— 그런 사건(개성 말풍선 = P)은 명단의 강화 칸으로 판단한다 (BattleView._kit_of).
##   낮 방식의 "augs"(강화 id 배열)가 남은 결과는 비어 있지 않으면 강화로 본다
static func resolve(e: Dictionary, cid: String) -> Dictionary:
	var slot := str(e.get("slot", ""))
	var fx := str(e.get("fx", ""))
	var nm := str(e.get("name", ""))
	var known := DB.C.has(cid)
	var up: bool = (e.get("up") is bool and bool(e.up) and not (fx in ["buff", "debuff"])) or (e.get("augs") is Array and not (e.augs as Array).is_empty())
	if Kit.SLOT_N.has(slot):
		if known:
			var cn := str(Kit.cell(cid, slot).get("n", ""))
			if slot == "p":
				nm = cn if cn != "" else (Kit.p_name(cid) if Kit.p_name(cid) != "" else nm)
			elif nm == "":
				nm = cn
		return {"slot": slot, "up": up, "name": nm}
	if not known or not Kit.on(cid):
		return {}
	match fx:
		"skill":
			if nm != "":
				for s in ["q", "w", "e"]:
					if str(Kit.cell(cid, s).get("n", "")) == nm:
						return {"slot": s, "up": up, "name": nm}
				for s in ["q", "w", "e"]:
					if str(Kit.slot_def(cid, s).get("name", "")) == nm:
						return {"slot": s, "up": up, "name": nm}
			return {}
		"ult", "ult_warn", "ult_join":
			return {"slot": "r", "up": up, "name": nm}
	if bool(e.get("sig", false)):
		var pn := str(Kit.cell(cid, "p").get("n", ""))
		if pn == "":
			pn = Kit.p_name(cid)
		if pn == "":
			var head := str(e.get("t", "")).split(" ——")[0]
			if head.find("의 ") >= 0:
				pn = head.substr(head.rfind("의 ") + 2)
		if pn != "":
			return {"slot": "p", "up": up, "name": pn}
	return {}


## 강화 이름(kup)이 그 카드의 어느 칸 것인가 ("" = 그 카드에 없다)
static func up_slot(cid: String, kup: String) -> String:
	if kup == "":
		return ""
	for s in Kit.SLOTS:
		var u = Kit.cell(cid, s).get("up")
		if u is Dictionary and str(u.get("n", "")) == kup:
			return s
	return ""


## 그 강화가 적을 밀어내는 것인가 —— 자료의 설명 글로 본다 (엔진이 사건에 "push": true 를 주면 그쪽이 먼저)
static func up_pushes(cid: String, slot: String) -> bool:
	var u = Kit.cell(cid, slot).get("up")
	if not (u is Dictionary):
		return false
	var d := str(u.get("d", ""))
	return d.contains("밀어") or d.contains("밀쳐")


## 전투 기록 머리 —— "[Q] " (RichTextLabel 용 BBCode · 대괄호는 [lb] [rb] 로)
static func log_head(slot: String) -> String:
	if not Kit.SLOT_N.has(slot):
		return ""
	return "[color=%s][b][lb]%s[rb][/b][/color] " % [str(Kit.SLOT_COL[slot]), str(Kit.SLOT_N[slot])]


## 구운 그림 넷 [둥근 네모 면, 둥근 네모 테두리, 동그라미, 가는 고리] (흰 그림 —— 색은 그릴 때 곱한다). 처음 한 번만 굽는다
static func baked() -> Array:
	if _pill.is_empty():
		var fill := Image.create(PILL_N, PILL_N, false, Image.FORMAT_RGBA8)
		var edge := Image.create(PILL_N, PILL_N, false, Image.FORMAT_RGBA8)
		var disc := Image.create(PILL_N, PILL_N, false, Image.FORMAT_RGBA8)
		var ring := Image.create(PILL_N, PILL_N, false, Image.FORMAT_RGBA8)
		var half := PILL_N * 0.5
		for y in PILL_N:
			for x in PILL_N:
				var qx := absf(x + 0.5 - half) - (half - PILL_R)
				var qy := absf(y + 0.5 - half) - (half - PILL_R)
				var d := Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length() + minf(maxf(qx, qy), 0.0) - PILL_R      # 둥근 네모까지의 거리 (안쪽이 −)
				var inside := clampf(0.5 - d, 0.0, 1.0)
				fill.set_pixel(x, y, Color(1, 1, 1, inside))
				edge.set_pixel(x, y, Color(1, 1, 1, inside * clampf(d + PILL_B + 0.5, 0.0, 1.0)))
				var rr := Vector2(x + 0.5 - half, y + 0.5 - half).length()
				disc.set_pixel(x, y, Color(1, 1, 1, clampf(half - 1.0 - rr, 0.0, 1.0)))
				ring.set_pixel(x, y, Color(1, 1, 1, clampf(3.2 - absf(rr - (half - 5.0)), 0.0, 1.0)))
		_pill = [ImageTexture.create_from_image(fill), ImageTexture.create_from_image(edge), ImageTexture.create_from_image(disc), ImageTexture.create_from_image(ring)]
	return _pill


## 둥근 받침 한 장을 아홉 조각으로 늘려 그린다 (그리기 명령 하나 · 다각형 계산 없음). which 0 면 · 1 테두리
## r 은 그림 px 단위 —— 부르는 쪽이 변환에 1/PILL_K 배율을 걸어 둔다 (Hud._draw_kit_tags)
static func draw_pill(ci: CanvasItem, which: int, r: Rect2, col: Color) -> void:
	var t: Texture2D = baked()[which]
	RenderingServer.canvas_item_add_nine_patch(ci.get_canvas_item(), r, Rect2(0, 0, PILL_N, PILL_N), t.get_rid(),
		Vector2(PILL_R, PILL_R), Vector2(PILL_R, PILL_R), RenderingServer.NINE_PATCH_STRETCH, RenderingServer.NINE_PATCH_STRETCH, true, col)


## 칸 딱지 —— 칸 색 바탕에 글자 (assets/kit/slot_<칸>.png 가 있으면 그 그림). c 가운데 · d 한 변 · flash 0~1 흰 번쩍
## 모양도 조금 다르다: Q · W · E 둥근 네모, R 은 밝은 금테, P 는 동그라미. 컷인 · 말풍선 · 기 모으기 줄에 쓴다
## (머리 위 딱지는 같은 구운 그림을 아홉 조각으로 늘려 그린다 —— Hud._draw_kit_tags)
static func draw_chip(ci: CanvasItem, c: Vector2, d: float, slot: String, a := 1.0, flash := 0.0) -> void:
	if a <= 0.01 or d < 2.0:
		return
	var r := Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d))
	var art := tex("slot_" + slot)
	if art != null:
		ci.draw_texture_rect(art, r.grow(d * 0.08), false, Color(1, 1, 1, a))
		if flash > 0.01:
			ci.draw_texture_rect(baked()[2], r, false, Color(1, 1, 1, 0.6 * flash * a))
		return
	var col := slot_col(slot)
	var shape: Texture2D = baked()[2 if slot == "p" else 0]      # P 는 동그라미, 나머지는 둥근 네모
	var rim := maxf(1.0, d * 0.07)
	if slot == "r":      # 금테 밖에 먹 테 한 겹 더 (밝은 땅 · 밝은 컷인 위에서도 떨어져 보이게)
		ci.draw_texture_rect(shape, r.grow(rim + 1.2), false, Color(0.06, 0.05, 0.04, 0.9 * a))
	ci.draw_texture_rect(shape, r.grow(rim), false, Color(1.0, 0.96, 0.75, a) if slot == "r" else Color(0.06, 0.05, 0.04, 0.9 * a))
	ci.draw_texture_rect(shape, r, false, Color(col.lerp(Color.WHITE, 0.85 * clampf(flash, 0.0, 1.0)), a))
	var fs := maxi(8, roundi(d * 0.74))
	ci.draw_string(DB.font_bold, Vector2(r.position.x, c.y + fs * 0.36), str(Kit.SLOT_N.get(slot, "?")), HORIZONTAL_ALIGNMENT_CENTER, d, fs, Color(0.07, 0.06, 0.04, a))


## 「강화됨」 표식 하나 —— 칸 색을 밝힌 ◆ (assets/kit/up.png 가 있으면 그 흰 그림에 칸 색을 입힌다). c 가운데 · sz 한 변
## ◆ 는 글꼴의 글자 (나눔고딕에 있다) —— 다각형을 만들지 않는다. outline 은 밝은 바탕(초상 위)에서만
static func draw_up(ci: CanvasItem, c: Vector2, sz: float, slot: String, a := 1.0, outline := false) -> void:
	if a <= 0.01 or sz < 2.0:
		return
	var col := slot_col(slot).lightened(0.45)
	var art := tex("up")
	if art != null:
		ci.draw_texture_rect(art, Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(col, a))
		return
	var fs := roundi(sz + 2.0)
	var q := Vector2(c.x - sz * 0.5 - 1.0, c.y + fs * 0.36)
	if outline:
		ci.draw_string_outline(DB.font_bold, q, "◆", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0.05, 0.04, 0.03, 0.9 * a))
	ci.draw_string(DB.font_bold, q, "◆", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, a))


# ───────── 사건 받기 (battle_view 가 기술 묶음 · 고유기를 시작할 때 · 사건을 적용할 때) ─────────

## key 가 slot 칸을 썼다 —— up 이면 강화된 칸, dsts 는 맞을(받을) 부대들, delay 는 맞는 순간까지 (근접 0.1 · 화살 0.55 · 책략 0.45 · 고유기 ULT_DELAY),
## wait 는 뜨기까지 (개전 P 알림을 차례로)
func add(key: String, slot: String, up: bool, dsts: Array, delay: float, wait := 0.0) -> void:
	var sq: Squad = p.v.field.squads.get(key)
	if sq == null or not Kit.SLOT_N.has(slot):
		return
	var now := float(p.v.field.clock) + maxf(0.0, wait)
	for c: Dictionary in casts:      # 같은 부대 · 같은 칸이 0.5초 안에 또 오면 겹쳐 그리지 않는다
		if c.key == key and c.slot == slot and absf(now - float(c.start)) < 0.5:
			stats.skip += 1
			return
	var d := []
	for k in dsts:
		var ks := str(k)
		if ks != key and not d.has(ks) and p.v.field.squads.has(ks):
			d.append(ks)
			if d.size() >= MAX_DSTS:
				break
	var hit := now + maxf(0.0, delay)
	casts.append({"key": key, "slot": slot, "up": up, "start": now, "hit": hit,
		"end": maxf(now + CAST_LIFE, hit + HIT_LIFE + HIT_STAGGER * d.size()), "col": slot_col(slot), "dsts": d,
		"sd": float(absi(hash(key + slot)) % 628) * 0.01})
	stats.cast += 1
	stats.hit += d.size()
	stats.by[slot] = int(stats.by.get(slot, 0)) + 1
	while casts.size() > MAX_CASTS:
		casts.pop_front()


## 강화 효과가 발동했다 —— key 는 그 효과를 받은 부대(없으면 시전 부대), src 는 시전 부대, slot 은 칸 색 ("" 이면 미색)
func add_burst(key: String, slot: String, src := "") -> void:
	if not p.v.field.squads.has(key):
		return
	bursts.append({"key": key, "src": src, "slot": slot, "col": slot_col(slot), "start": float(p.v.field.clock),
		"sd": float(absi(hash(key + slot + str(bursts.size()))) % 628) * 0.01})
	stats.burst += 1
	while bursts.size() > MAX_BURSTS:
		bursts.pop_front()


## 부대가 밀려났다 —— dir 은 밀린 쪽(전장 방향). 병사 · 장수는 돌아서 걷지 않고 그대로 선 채 움찔하며 밀린다 (FormationMotion.shove_until)
func add_shove(key: String, dir: Vector2) -> void:
	var sq: Squad = p.v.field.squads.get(key)
	if sq == null or not sq.alive or dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var form = p.formations.get(key)
	if form != null:
		form.shove_until = form.motion_clock + SHOVE_LIFE
		form.receive_impact(form.center - dir * 20.0, dir, 1.4)
		if p._shows_hero(sq):
			form.hero_hurt_at = p.visual_time
			form.hero_hurt_power = 1.2
			form.hero_hurt_dir = dir
			form.hero_hurt_mirror = not form.facing_right
	shoves.append({"key": key, "dir": dir, "start": float(p.v.field.clock)})
	stats.shove += 1
	while shoves.size() > MAX_SHOVES:
		shoves.pop_front()


# ───────── 위층 그리기 (TopEffects) ─────────

func draw(ci: CanvasItem) -> void:
	var t0 := Time.get_ticks_usec()
	var clock := float(p.last_clock)
	var lv := int(p.v.load_lv) if p.v.get("load_lv") != null else 0
	_queued = false
	_draw_states(lv)
	for s: Dictionary in shoves:
		_draw_shove(s, clock - float(s.start))
	_marks = 0
	for i in range(casts.size() - 1, -1, -1):      # 새 발동부터 —— 표식 상한(MAX_MARKS)은 새것이 먼저 쓴다
		var c: Dictionary = casts[i]
		_draw_cast(ci, c, clock - float(c.start), lv)
		if not (c.dsts as Array).is_empty():
			_draw_hits(c, clock - float(c.hit), lv)
	for b: Dictionary in bursts:
		_draw_burst(ci, b, clock - float(b.start), lv)
	if _queued:
		_flush(ci)
		draw_us += Time.get_ticks_usec() - t0
		draw_n += 1


## 그림 한 장을 모음에 넣는다 —— nm 그림 이름 · c 가운데 · sz 긴 변 · st 늘림 · ground 면 땅에 눕힌다(st.y = 눌림)
func _t(nm: String, c: Vector2, sz: float, col: Color, rot := 0.0, st := Vector2.ONE, ground := false) -> void:
	if col.a <= 0.02 or sz < 2.0:
		return
	var q = _q_tex.get(nm)
	if q == null:
		q = []
		_q_tex[nm] = q
	q.append(c)
	q.append(sz)
	q.append(col)
	q.append(rot)
	q.append(st)
	q.append(ground)
	_queued = true


func _l(a: Vector2, b: Vector2, col: Color, w: float, aa := false) -> void:
	_q_line.append(a)
	_q_line.append(b)
	_q_line.append(col)
	_q_line.append(w)
	_q_line.append(aa)
	_queued = true


func _prim(pts: PackedVector2Array, col: Color) -> void:
	_q_prim.append(pts)
	_q_prim.append(col)
	_queued = true


func _texture(nm: String) -> Texture2D:
	match nm:
		"fill": return baked()[0]
		"disc", "dot": return baked()[2]
		"ring": return baked()[3]
		"gstar": return p._ink_get("star")
	return p._ink_get(nm)


func _flush_tex(ci: CanvasItem, names: Array) -> void:
	for nm in names:
		var q = _q_tex.get(nm)
		if q == null or (q as Array).is_empty():
			continue
		var t := _texture(nm)
		if t != null:
			var ts := t.get_size()
			var unit := ts / maxf(ts.x, ts.y) * 0.5
			var i := 0
			while i < q.size():
				var rot: float = q[i + 3]
				var st: Vector2 = q[i + 4]
				if q[i + 5]:
					ci.draw_set_transform_matrix(Transform2D(Vector2(cos(rot), sin(rot) * st.y), Vector2(-sin(rot), cos(rot) * st.y), q[i]))
				else:
					ci.draw_set_transform(q[i], rot, st)
				var half: Vector2 = unit * float(q[i + 1])
				ci.draw_texture_rect(t, Rect2(-half, half * 2.0), false, q[i + 2])
				i += 6
		q.clear()


## 모아 둔 것을 차례대로 낸다 —— 그림(아래) → assets/kit 그림 → 세모 · 네모 → 선 → 방울
func _flush(ci: CanvasItem) -> void:
	_flush_tex(ci, TEX_UNDER)
	ci.draw_set_transform(Vector2.ZERO)
	var i := 0
	while i < _q_sheet.size():
		var art: Texture2D = _q_sheet[i]
		var ts := art.get_size()
		var n := maxi(1, roundi(ts.x / maxf(1.0, ts.y)))
		var fw := ts.x / n
		var sz: float = _q_sheet[i + 2]
		ci.draw_texture_rect_region(art, Rect2(_q_sheet[i + 1] - Vector2(sz, sz) * 0.5, Vector2(sz, sz)),
			Rect2(fw * clampi(int(float(_q_sheet[i + 3]) * n), 0, n - 1), 0.0, fw, ts.y), _q_sheet[i + 4])
		i += 5
	_q_sheet.clear()
	i = 0
	while i < _q_prim.size():
		ci.draw_primitive(_q_prim[i], PackedColorArray([_q_prim[i + 1]]), _no_uv)
		i += 2
	_q_prim.clear()
	i = 0
	while i < _q_line.size():
		ci.draw_line(_q_line[i], _q_line[i + 1], _q_line[i + 2], _q_line[i + 3], _q_line[i + 4])
		i += 5
	_q_line.clear()
	_flush_tex(ci, TEX_OVER)
	ci.draw_set_transform(Vector2.ZERO)


## 발 화면 자리 (장수 인형이 있으면 그 발)
func _feet(sq: Squad) -> Vector2:
	if p.hero_feet.has(sq.key):
		return p.hero_feet[sq.key]
	var form = p.formations.get(sq.key)
	return p.v.map(form.center if form != null else sq.pos)


## 시전 고리의 바탕 반지름 (화면 px) —— 장수 인형 키에 맞춘다 (없으면 부대 반폭)
func _radius(sq: Squad) -> float:
	var hh := float(p.hero_h.get(sq.key, 0.0))
	if hh > 1.0:
		return clampf(hh * 0.62, 16.0, 34.0)
	return clampf(p.caster._half_width_px(sq), 16.0, 34.0)


## 땅에 누운 붓 고리 (원상 그림 한 장) —— 먹 밑그림 + 칸 색. rx 가로 반지름 · rot 붓 시작 자리
func _ring(c: Vector2, rx: float, col: Color, a: float, ink: bool, rot: float, nm := 0) -> void:
	if a <= 0.02 or rx < 2.0:
		return
	var sz := rx * 2.0 / ENSO_FILL
	var art := "enso_1" if nm == 1 else "enso_0"
	if ink:
		_t(art, c + Vector2(0, 1.5), sz * 1.07, Color(INK, 0.6 * a), rot, Vector2(1.0, 0.46), true)
	_t(art, c, sz, Color(col, a), rot, Vector2(1.0, 0.46), true)


## 닫힌 꺾은선 (세모 · 마름모) —— 먹 밑줄 + 색 (선 하나씩: 다각형 명령을 만들지 않는다)
func _outline(pts: PackedVector2Array, col: Color, w: float, a: float, aa: bool, ink: bool) -> void:
	var n := pts.size()
	if ink:
		for k in n:
			_l(pts[k], pts[(k + 1) % n], Color(INK, 0.55 * a), w + 2.4)
	for k in n:
		_l(pts[k], pts[(k + 1) % n], Color(col, a), w, aa)


## assets/kit 의 그림 한 칸을 모음에 넣는다 —— 가로 띠 시트면 칸 수 = 폭 ÷ 높이, u 0~1 진행에 맞는 칸 (한 장이면 그 한 장). col 은 곱할 색
func _sheet(art: Texture2D, c: Vector2, sz: float, u: float, col: Color) -> void:
	_q_sheet.append(art)
	_q_sheet.append(c)
	_q_sheet.append(sz)
	_q_sheet.append(u)
	_q_sheet.append(col)
	_queued = true


func _draw_cast(ci: CanvasItem, c: Dictionary, age: float, lv: int) -> void:
	if age < 0.0 or age > CAST_LIFE:
		return
	var sq: Squad = p.v.field.squads.get(c.key)
	if sq == null or sq.fade <= 0.01 or sq.state == "gone":
		return
	var feet := _feet(sq)
	var R := _radius(sq)
	var hh := float(p.hero_h.get(sq.key, R * 1.6))
	var body := feet - Vector2(0, hh * 0.5)
	var col: Color = c.col
	var slot := str(c.slot)
	var up := bool(c.up)
	var aa := lv < 2
	var ink := lv < 2
	var sd := float(c.sd)
	var t := age / CAST_LIFE
	var a := (1.0 - smoothstep(0.55, 1.0, t)) * sq.fade
	var u := clampf(age / 0.55, 0.0, 1.0)
	var grow := 0.45 + 1.0 * ease(u, 0.45)
	var big := (1.05 if up else 1.0) * (0.85 if slot == "r" else 0.62)
	var rx := R * grow * big
	var w := 3.2 if up else 2.6
	# 번쩍임 —— 몸에서 칸 색 빛 + 흰 심 (강화된 칸이면 더 크고 길게 + 여덟 갈래 섬광)
	var fl := 1.0 - clampf(age / (0.4 if up else 0.3), 0.0, 1.0)
	if fl > 0.0:
		p._spr(ci, "light_02", body, R * (4.8 if up else 3.8) * big, Color(col, 0.36 * fl * sq.fade))
		_t("disc", body, R * 0.7 * fl + 4.0, Color(1, 1, 1, 0.6 * fl * sq.fade))
		if slot == "r" and up and lv < 3:
			_t("star", body, R * (2.0 + 2.2 * (1.0 - fl)), Color(1, 1, 1, 0.9 * fl * sq.fade), age * 2.5)
	var sheet := tex("cast_" + slot)
	if sheet != null:      # 그림 시트가 있으면 바탕 고리 · 칸 모양 대신 그것을 (장수 몸 가운데에 겹친다 —— 번쩍임 · 강화 덧고리는 그대로 얹는다)
		_sheet(sheet, body, R * 4.6 * big, t, Color(1, 1, 1, sq.fade))
	else:      # 바탕 고리 —— 모든 칸이 같다 (누가 썼나)
		_ring(feet, rx, col, a, ink, sd + age * 1.4)
	if up and lv < 3:      # 강화된 칸 —— 바깥에 밝은 고리 한 겹 더, 조금 늦게
		var u2 := clampf((age - 0.1) / 0.55, 0.0, 1.0)
		if u2 > 0.0:
			_ring(feet, R * (0.6 + 1.35 * ease(u2, 0.45)) * big, col.lightened(0.4), a * 0.85, false, -sd - age, 1)
	if sheet != null:
		return
	# 칸 모양
	match slot:
		"q":      # 한 줄 베기 자국 —— 붓 한 획이 왼쪽 아래에서 오른쪽 위로 그어지고, 흰 날이 먼저 번쩍인다
			var k := clampf(age / 0.12, 0.15, 1.0)
			var ln := R * 3.5 * big
			var rot := -0.61
			var d := Vector2.from_angle(rot)
			if ink:
				_t("brush_0", body + Vector2(0, 1.5), ln * 1.05, Color(INK, 0.55 * a), rot, Vector2(k, 1.5))
			_t("brush_0", body, ln, Color(col, a), rot, Vector2(k, 1.3))
			var kf := 1.0 - clampf((age - 0.1) / 0.25, 0.0, 1.0)
			if kf > 0.0:
				_l(body - d * ln * 0.42 * k, body + d * ln * 0.42 * k, Color(1, 1, 1, 0.95 * kf * sq.fade), 2.0, aa)
		"w":      # 두 겹 고리 —— 안쪽 고리가 조금 늦게, 거꾸로 돌며 뒤따른다
			var uw := clampf((age - 0.12) / 0.55, 0.0, 1.0)
			if uw > 0.0:
				_ring(feet, R * (0.45 + 1.0 * ease(uw, 0.45)) * 0.62 * big, col.lightened(0.2), a, ink, -sd - age * 1.8, 1)
		"e":      # 세모 —— 몸 둘레에 선 세모가 커지며 사라진다
			var re := R * (0.6 + 0.55 * ease(u, 0.45)) * big
			_outline(PackedVector2Array([body + Vector2(0, -re), body + Vector2(re * 0.866, re * 0.5), body + Vector2(-re * 0.866, re * 0.5)]), col, w, a, aa, ink)
		"r":      # 햇살 —— 고리 밑에 여덟 갈래 금빛 별이 땅에 깔려 천천히 돈다
			if lv < 3:
				_t("gstar", feet, rx * 3.3, Color(col.lightened(0.2), 0.9 * a), sd + age * 0.9, Vector2(1.0, 0.46), true)
		"p":      # 마름모 —— 몸 둘레에서 두 번 맥박친다
			var pu := fposmod(age / 0.42, 1.0) if age < 0.84 else 1.0
			var rp := R * (0.75 + 0.5 * ease(pu, 0.5)) * big
			_outline(PackedVector2Array([body + Vector2(0, -rp * 1.15), body + Vector2(rp * 0.8, 0), body + Vector2(0, rp * 1.15), body + Vector2(-rp * 0.8, 0)]),
				col, w, a * (1.0 - 0.6 * pu), aa, ink)


func _draw_hits(c: Dictionary, age: float, lv: int) -> void:
	if age < -LINK_TRAVEL:
		return
	var src: Squad = p.v.field.squads.get(c.key)
	var col: Color = c.col
	var slot := str(c.slot)
	var up := bool(c.up)
	var aa := lv < 2
	var dsts: Array = c.dsts
	var mark := tex("hit_" + slot)
	var foe_cast := str(c.key).begins_with("B")
	var sz := 9.0 if up else 8.0
	var cap := 4 if lv >= 3 else (8 if lv >= 2 else MAX_MARKS)
	for j in dsts.size():
		if _marks >= cap:
			break
		var dst: Squad = p.v.field.squads.get(dsts[j])
		if dst == null or dst.fade <= 0.01 or dst.state == "gone":
			continue
		var aj := age - j * HIT_STAGGER
		if aj > HIT_LIFE:
			continue
		var at: Vector2 = p.caster._anchor(dst, 24.0)
		# 빛줄기 —— 시전자 몸에서 대상으로, 맞는 순간에 닿는다
		if lv < 2 and j < MAX_LINKS and src != null and src != dst and src.fade > 0.01:
			var q := (aj + LINK_TRAVEL) / LINK_TRAVEL      # 0 떠남 → 1 닿음 → 1.4 꼬리까지 들어감 (짧은 살별 —— 긴 줄이 화면을 가르지 않게)
			if q >= 0.0 and q < 1.4:
				var from := _feet(src) - Vector2(0, float(p.hero_h.get(src.key, 30.0)) * 0.5)
				var l0 := from.lerp(at, clampf(q - 0.4, 0.0, 1.0))
				var l1 := from.lerp(at, minf(q, 1.0))
				_l(l0, l1, Color(INK, 0.35), 3.6)
				_l(l0, l1, Color(col.lightened(0.2), 0.95), 1.8, true)
		if aj < 0.0:
			continue
		_marks += 1
		var t := aj / HIT_LIFE
		var a := (1.0 - smoothstep(0.6, 1.0, t)) * dst.fade
		var pop := 0.6 + 0.4 * smoothstep(0.0, 0.08, aj) + 0.25 * (1.0 - smoothstep(0.08, 0.22, aj)) * smoothstep(0.0, 0.08, aj)
		var s := sz * pop
		var m := at - Vector2(0, 5.0 * t)
		# 발밑 고리 —— 맞은 부대 둘레에서 한 번 퍼진다
		if lv < 2 and aj < 0.35:
			var gu := aj / 0.35
			_ring(p.caster._anchor(dst, -2.0), clampf(p.caster._half_width_px(dst), 14.0, 40.0) * (0.6 + 0.6 * gu) * (1.15 if up else 1.0),
				col, (1.0 - gu) * dst.fade, false, float(c.sd) + j)
		# 받침 —— 아군이 쓴 것은 먹빛, 적이 쓴 것(당했다)은 검붉게. 강화된 칸이면 칸 색 가는 테를 두른다
		_t("disc", m, s * 3.1, Color(0.45, 0.07, 0.05, 0.66 * a) if foe_cast else Color(INK, 0.46 * a))
		if up:
			_t("ring", m, s * 3.9, Color(col.lightened(0.35), 0.9 * a))
		if mark != null:      # 그림이 있으면 칸 모양 대신 그것을 (받침 위에 —— 그림은 모양만 담는다)
			_sheet(mark, m, s * 3.0, t, Color(1, 1, 1, a))
			continue
		match slot:
			"q":      # 베기 자국 한 줄
				var d := Vector2(0.78, -0.62) * s * 1.2
				_l(m - d, m + d, Color(INK, a), 5.4)
				_l(m - d, m + d, Color(col, a), 3.4, aa)
				_l(m - d * 0.7, m + d * 0.7, Color(1, 1, 1, 0.9 * a), 1.2)
			"w":      # 두 겹 고리
				_t("ring", m, s * 2.7, Color(col, a))
				_t("ring", m, s * 1.3, Color(col.lightened(0.3), a))
			"e":      # 세모
				var tri := PackedVector2Array([m + Vector2(0, -s), m + Vector2(s, s * 0.73), m + Vector2(-s, s * 0.73)])
				_prim(tri, Color(col, 0.95 * a))
				for k in 3:
					_l(tri[k], tri[(k + 1) % 3], Color(INK, a), 1.5)
			"r":      # 여덟 갈래 별 (먹 테가 있는 붓 별 그림)
				_t("star", m, s * 3.6, Color(col.lightened(0.15), a), aj * 1.5)
			_:        # P —— 마름모
				var dia := PackedVector2Array([m + Vector2(0, -s * 1.2), m + Vector2(s * 0.85, 0), m + Vector2(0, s * 1.2), m + Vector2(-s * 0.85, 0)])
				_prim(dia, Color(col, 0.95 * a))
				for k in 4:
					_l(dia[k], dia[(k + 1) % 4], Color(INK, a), 1.5)


## 강화 효과 발동 —— 받은 부대에서 큰 번쩍임 · 칸 색 두 겹 고리 · 맥박치며 도는 칸 색 별, 시전 부대에서 굵은 빛줄기 (기술 표시보다 한 단계 세게)
func _draw_burst(ci: CanvasItem, b: Dictionary, age: float, lv: int) -> void:
	if age < 0.0 or age > BURST_LIFE:
		return
	var sq: Squad = p.v.field.squads.get(b.key)
	if sq == null or sq.fade <= 0.01 or sq.state == "gone":
		return
	var feet := _feet(sq)
	var R := _radius(sq)
	var body := feet - Vector2(0, float(p.hero_h.get(sq.key, R * 1.6)) * 0.5)
	var col: Color = b.col
	var t := age / BURST_LIFE
	var a := (1.0 - smoothstep(0.55, 1.0, t)) * sq.fade
	var sd := float(b.sd)
	var fl := 1.0 - clampf(age / 0.32, 0.0, 1.0)
	if fl > 0.0:
		p._spr(ci, "light_02", body, R * 5.6, Color(col, fl * sq.fade))
		_t("disc", body, R * 1.1 * fl + 4.0, Color(1, 1, 1, 0.7 * fl * sq.fade))
		_t("star", body, R * (1.8 + 2.8 * (1.0 - fl)), Color(1, 1, 1, 0.95 * fl * sq.fade), age * 3.0)
	var src: Squad = p.v.field.squads.get(str(b.src))
	if lv < 3 and src != null and src != sq and src.fade > 0.01 and age < 0.16:      # 시전 부대에서 굵은 빛줄기가 꽂힌다
		var from := _feet(src) - Vector2(0, float(p.hero_h.get(src.key, 30.0)) * 0.5)
		var q := age / 0.12
		var l0 := from.lerp(body, clampf(q - 0.5, 0.0, 1.0))
		var l1 := from.lerp(body, minf(q, 1.0))
		_l(l0, l1, Color(INK, 0.45), 6.0)
		_l(l0, l1, Color(col.lightened(0.25), 1.0), 3.4, true)
	var art := tex("kup_" + str(b.slot))
	var tint := Color(1, 1, 1, sq.fade)
	if art == null:
		art = tex("kup")      # 공용 흰 그림 —— 칸 색을 입힌다
		tint = Color(col, sq.fade)
	if art != null:
		_sheet(art, body, R * 5.2, t, tint)
		return
	for k in 2:      # 두 겹 고리가 잇달아 크게 퍼진다
		var u := clampf((age - k * 0.14) / 0.6, 0.0, 1.0)
		if u > 0.0 and u < 1.0:
			_ring(feet, R * (0.5 + 1.6 * ease(u, 0.45)), col.lightened(0.3 * k), (1.0 - u * u) * sq.fade, k == 0 and lv < 2, sd + age * (1.6 if k == 0 else -1.6), k)
	_t("star", body - Vector2(0, R * 0.15), R * 1.5 * (1.0 + 0.18 * sin(age * 16.0)), Color(col.lightened(0.2), a), -age * 2.2)


## 밀려남 —— 밀린 쪽 반대편에 흙먼지 구름 + 밀린 방향으로 그어지는 속도선 셋
func _draw_shove(s: Dictionary, age: float) -> void:
	if age < 0.0 or age > SHOVE_LIFE:
		return
	var sq: Squad = p.v.field.squads.get(s.key)
	if sq == null or not sq.alive or sq.fade <= 0.01:
		return
	var feet := _feet(sq)
	var R := _radius(sq)
	var body := feet - Vector2(0, float(p.hero_h.get(sq.key, R * 1.6)) * 0.45)
	var form = p.formations.get(sq.key)
	var at: Vector2 = form.center if form != null else sq.pos
	var sdir: Vector2 = p.v.map(at + Vector2(s.dir) * 20.0) - p.v.map(at)
	if sdir.length_squared() < 0.01:
		return
	sdir = sdir.normalized()
	var side := Vector2(-sdir.y, sdir.x)
	var t := age / SHOVE_LIFE
	var a := (1.0 - smoothstep(0.4, 1.0, t)) * sq.fade
	_t("cloud", feet - sdir * R * (0.5 + 0.5 * t), R * (1.3 + 0.7 * t), Color(0.86, 0.78, 0.6, 0.75 * a), 0.0, Vector2(-1.0 if sdir.x > 0.0 else 1.0, 0.7))
	for k in 3:
		var off := side * (k - 1) * R * 0.45 - sdir * R * (0.7 + 0.25 * absf(k - 1.0))
		var l0 := body + off - sdir * R * (1.1 - 0.5 * t)
		var l1 := body + off + sdir * R * 0.1
		_l(l0, l1, Color(INK, 0.4 * a), 3.4)
		_l(l0, l1, Color(1.0, 0.97, 0.88, 0.9 * a), 1.6)


## 상태 기호 —— 봉인 · 도발 · 불사는 머리 오른쪽에 작은 기호(위에서 아래로), 출혈 · 역병 · 은신은 몸 · 발밑에 겹친다. 걸려 있는 동안 계속
func _draw_states(lv: int) -> void:
	var clock := float(p.last_clock)
	for sq: Squad in p.v.field.order:
		if sq.statuses.is_empty() or not sq.alive or sq.fade <= 0.05 or sq.state == "gone":
			continue
		var st: Array = sq.statuses
		var seal := st.has("seal")
		var taunted := st.has("taunted")
		var undying := st.has("undying")
		var bleed := st.has("bleed")
		var plague := st.has("plague")
		var stealth := st.has(STEALTH_KEYS[0]) or st.has(STEALTH_KEYS[1])
		if not (seal or taunted or undying or bleed or plague or stealth):
			continue
		var feet := _feet(sq)
		var R := _radius(sq)
		var hh := float(p.hero_h.get(sq.key, 0.0))
		var top: Vector2 = feet - Vector2(0, hh) if hh > 1.0 else p.caster._anchor(sq, 30.0)
		var body: Vector2 = feet - Vector2(0, hh * 0.5) if hh > 1.0 else p.caster._anchor(sq, 14.0)
		var a := sq.fade
		var ph := float(sq.row.slot) * 1.7
		var ic := top + Vector2(R * 0.72 + 8.0, 10.0)      # 기호 줄의 첫 자리 (머리 오른쪽 —— 머리 위는 칸 딱지 자리)
		if seal:      # 자물쇠 —— 회백색 몸통 + 고리 (기술을 쓰지 못한다)
			_t("disc", ic, ICON_D, Color(0.05, 0.05, 0.07, 0.88 * a))
			_t("ring", ic + Vector2(0, -3.0), 10.0, Color(0.88, 0.88, 0.88, a))
			_t("fill", ic + Vector2(0, 2.8), 10.6, Color(0.88, 0.88, 0.88, a), 0.0, Vector2(1.0, 0.72))
			ic.y += ICON_D
		if taunted:      # 성난 표시 —— 가운데를 비운 네 갈래 (표적이 도발한 장수로 돌려졌다)
			_t("disc", ic, ICON_D, Color(0.05, 0.05, 0.07, 0.88 * a))
			var k := 1.0 + 0.12 * sin(clock * 9.0 + ph)
			for q in 4:
				var d := Vector2(1.0 if q % 2 == 0 else -1.0, 1.0 if q < 2 else -1.0)
				var o := ic + d * 1.9 * k
				_l(o + Vector2(d.x * 5.0, 0) * k, o, Color(1.0, 0.48, 0.29, a), 2.4)
				_l(o + Vector2(0, d.y * 5.0) * k, o, Color(1.0, 0.48, 0.29, a), 2.4)
			ic.y += ICON_D
		if undying:      # 금빛 심장 + 발밑 금 고리 (쓰러지지 않는다)
			var hb := 1.0 + 0.14 * sin(clock * 7.0 + ph)
			_t("disc", ic, ICON_D, Color(0.05, 0.05, 0.07, 0.88 * a))
			_t("disc", ic + Vector2(-2.9, -1.9) * hb, 7.5 * hb, Color(1.0, 0.82, 0.34, a))
			_t("disc", ic + Vector2(2.9, -1.9) * hb, 7.5 * hb, Color(1.0, 0.82, 0.34, a))
			_prim(PackedVector2Array([ic + Vector2(-6.1, -0.2) * hb, ic + Vector2(6.1, -0.2) * hb, ic + Vector2(0, 6.8) * hb]), Color(1.0, 0.82, 0.34, a))
			if lv < 2:
				_ring(feet, R * (1.05 + 0.06 * sin(clock * 5.0 + ph)), Color(1.0, 0.82, 0.34), 0.75 * a, false, clock * 0.8 + ph)
			ic.y += ICON_D
		if bleed:      # 붉은 할퀸 자국 + 떨어지는 핏방울 둘
			_t("claw", body + Vector2(-R * 0.1, 0), R * 1.25, Color(0.88, 0.2, 0.17, 0.92 * a), -0.35)
			if lv < 3:
				for k in 2:
					var f := fposmod(clock * 0.9 + ph * 0.37 + k * 0.5, 1.0)
					_t("dot", body + Vector2((k - 0.5) * R * 0.7, R * 0.2 + f * R * 1.0), 4.6 - 1.6 * f, Color(0.85, 0.16, 0.14, (1.0 - f * f) * a))
		if plague:      # 풀빛 거품 셋이 몸에서 떠오른다
			for k in 3:
				var f := fposmod(clock * 0.55 + ph * 0.21 + k / 3.0, 1.0)
				var q := body + Vector2(sin(clock * 2.0 + ph + k * 2.1) * R * 0.5, R * 0.5 - f * R * 1.5)
				var ba := sin(PI * f) * a
				_t("dot", q, 9.5 + 3.0 * sin(f * PI), Color(0.56, 0.8, 0.36, 0.6 * ba))
				_t("ring", q, 12.0 + 3.0 * sin(f * PI), Color(0.8, 0.97, 0.52, ba))
		if stealth:      # 발밑 먹 구름 둘이 천천히 흐른다 (인형은 WarPainting._cover_step 이 그늘에 묻는다)
			for k in 2:
				var dx := sin(clock * 0.9 + ph + k * PI) * R * 0.5
				_t("cloud", feet + Vector2(dx + (k - 0.5) * R * 0.9, -R * 0.12), R * 1.7, Color(0.2, 0.22, 0.28, 0.62 * a), 0.0, Vector2(1.0 if k == 0 else -1.0, 0.6))
		if count_states:      # 점검 —— 어떤 상태를 그렸나
			for key in ["seal", "taunted", "undying", "bleed", "plague", "stealth"]:
				if st.has(key) or (key == "stealth" and stealth):
					stats.state[key] = int(stats.state.get(key, 0)) + 1
