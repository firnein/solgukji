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
## 강화(augs) 덧표현: 화공 = 불빛 테두리 · 불꽃,  확산 = 고리가 더 크게 + 바깥 고리 한 겹,  강격 = 번쩍임이 더 세게 (나머지는 딱지 옆 ★ 색으로만)
##
## 그림 자산 (docs/코덱스_요청_키트.md) —— res://assets/kit/ 에 파일이 있으면 코드 그림 대신 그것을 쓴다 (없으면 코드 그림 · 넣기만 하면 바뀐다):
##   slot_<칸>.png 칸 문장 · cast_<칸>.png 시전 이펙트(가로 띠 시트) · hit_<칸>.png 맞은 표식(한 장 또는 가로 띠) · aug_<강화 id>.png 강화 아이콘
##
## 머리 위 딱지(글자 + 기술 이름 + ★)는 HUD 가 그린다 (battle_view.gd Hud.kit_tag) —— 여기의 pill · draw_chip · draw_augs 를 같이 쓴다.
##
## 프레임 부담 (11/27 실측: 신화 11명이 초당 6번 넘게 쓰는 판에서 처음 구현은 그리기 명령을 만드는 데만 프레임당 1.6ms 를 썼다 ——
##   둥근 상자(StyleBoxFlat) · 다각형 삼각 분할 · 안티에일리어싱 꺾은선 · 원은 명령마다 정점 버퍼를 새로 만든다):
##   고리는 붓 원상 그림(assets/fx/ink/enso) 한 장을 눌러 그리고, 받침 · 작은 고리는 구운 그림(baked), 나머지는 선 · 세모 · 네모 기본 도형만 쓴다 (다각형 명령 없음).
##   그릴 것을 그림별로 모았다가 한꺼번에 낸다(_flush) —— 같은 그림의 네모는 렌더러가 한 번에 그린다.
##   한 화면에 고리 MAX_CASTS · 표식 MAX_MARKS 까지. 부하 조절 2단계부터 빛줄기 · 발밑 고리 · 먹 밑그림을 빼고 표식은 여덟, 3단계부터 넷.

const Kit := preload("res://scripts/kit.gd")

var p                       # WarPainting
var casts: Array = []       # {key, slot, augs, start, hit, end, col, dsts: [부대 key], wide, fire, dmg, sd}
var stats := {"cast": 0, "hit": 0, "skip": 0, "peak": 0, "by": {}}      # 점검용 (tests/kit_fx_shot)
var draw_us := 0            # 점검용 —— 그리기에 쓴 시간 합(µs) · 그린 횟수
var draw_n := 0
var _marks := 0             # 이번 그리기에서 그린 맞은 표식 수
var _q_tex := {}            # 그림 이름 -> [가운데, 크기, 색, 돌림, 늘림, 땅에 눕힘] 을 이어 붙인 배열 (한 프레임 모았다가 _flush)
var _q_line: Array = []     # [a, b, 색, 굵기, 안티에일리어싱] 이어 붙임
var _q_prim: Array = []     # [점들(셋 · 넷), 색] 이어 붙임
var _q_sheet: Array = []    # [그림(assets/kit), 가운데, 크기, 진행 0~1, 투명] 이어 붙임

const MAX_CASTS := 10
const MAX_DSTS := 9
const MAX_LINKS := 5
const MAX_MARKS := 14        # 한 화면에 그리는 맞은 표식 (새 발동부터 센다)
const CAST_LIFE := 0.75      # 시전 고리 · 번쩍임 · 칸 모양 (전장 초)
const HIT_LIFE := 0.75       # 맞은 표식
const LINK_TRAVEL := 0.18    # 시전자 → 대상 빛줄기가 닿는 시간 (맞는 순간에 닿는다)
const HIT_STAGGER := 0.04    # 대상마다 조금씩 늦게
const INK := Color("#29271f")
const EMBER := Color("#ff8a2a")
const ENSO_FILL := 0.78      # 원상 그림에서 고리가 차지하는 폭 (그림 한 변 대비)

const ASSET_DIR := "res://assets/kit/"
## 강화 종류 색 —— 딱지 옆 ★ (그림 aug_<id>.png 가 없을 때)
const AUG_COL := {"dmg": "#ff5a4a", "wide": "#6fe0ff", "fire": "#ff9b45", "slow": "#7fb8ff", "awe": "#c58bff", "quick": "#d8f06a", "cheer": "#7fe6a4", "amp": "#ffd257"}
## 둥근 받침 그림 (머리 위 딱지) —— 3배로 굽고 1/3 로 그린다 (휴대폰 고해상도에서도 모서리가 또렷하게)
const PILL_N := 48
const PILL_R := 18.0         # 모서리 반지름 (그림 px —— 화면에서는 6)
const PILL_B := 6.0          # 테두리 굵기 (그림 px —— 화면에서는 2)
const PILL_K := 3.0
## 모아 그리는 차례 (아래 → 위): 땅의 고리 → 땅의 별 → 받침 → 작은 고리 · 붓 획 · 별 → (세모 · 네모 · 선) → 불꽃
const TEX_UNDER := ["enso_0", "enso_1", "gstar", "disc", "ring", "brush_0", "star"]
const TEX_OVER := ["flame_0", "flame_1"]

static var _tex := {}
static var _pill: Array = []
static var _no_uv := PackedVector2Array()


func _init(painter) -> void:
	p = painter


func reset() -> void:
	casts.clear()
	stats = {"cast": 0, "hit": 0, "skip": 0, "peak": 0, "by": {}}
	draw_us = 0
	draw_n = 0


func prune(clock: float) -> void:
	if casts.is_empty():
		return
	casts = casts.filter(func(c): return clock < float(c.end) and clock >= float(c.start) - 5.0)
	stats.peak = maxi(int(stats.peak), casts.size())


# ───────── 함께 쓰는 것 (HUD · 삽화 · 점검) ─────────

## assets/kit/<이름>.png —— 있으면 그림, 없으면 null (한 번만 찾는다)
static func tex(nm: String) -> Texture2D:
	if not _tex.has(nm):
		var path := ASSET_DIR + nm + ".png"
		_tex[nm] = load(path) if ResourceLoader.exists(path) else null
	return _tex[nm]


static func slot_col(slot: String) -> Color:
	return Color(str(Kit.SLOT_COL.get(slot, "#ffffff")))


static func aug_col(aug: String) -> Color:
	return Color(str(AUG_COL.get(aug, "#ffd257")))


## 그 사건이 어느 칸의 발동인가 —— {slot, augs, name} · 아니면 빈 사전. cid = 그 사건을 일으킨 부대의 카드 id
## 사건에 "slot" 이 있으면 그대로 (엔진 약속 —— scripts/kit.gd 머리말). 없으면(옛 서버 결과 · 엔진 병합 전) 대비책:
##   키트 장수의 기술 이름이 Kit.slot_def 의 q · w · e 이름과 같으면 그 칸, 고유기(ult · ult_warn)면 r, 개성 말풍선(sig)이면 p
static func resolve(e: Dictionary, cid: String) -> Dictionary:
	var slot := str(e.get("slot", ""))
	var augs: Array = []
	if e.get("augs") is Array:
		for a in e.augs:
			augs.append(str(a))
	var nm := str(e.get("name", ""))
	var known := DB.C.has(cid)
	if Kit.SLOT_N.has(slot):
		if slot == "p" and known and Kit.p_name(cid) != "":
			nm = Kit.p_name(cid)
		return {"slot": slot, "augs": augs, "name": nm}
	if not known or not Kit.on(cid):
		return {}
	match str(e.get("fx", "")):
		"skill":
			if nm != "":
				for s in ["q", "w", "e"]:
					if str(Kit.slot_def(cid, s).get("name", "")) == nm:
						return {"slot": s, "augs": augs, "name": nm}
			return {}
		"ult", "ult_warn":
			return {"slot": "r", "augs": augs, "name": nm}
	if bool(e.get("sig", false)):
		var pn := Kit.p_name(cid)
		if pn == "":
			var head := str(e.get("t", "")).split(" ——")[0]
			if head.find("의 ") >= 0:
				pn = head.substr(head.rfind("의 ") + 2)
		if pn != "":
			return {"slot": "p", "augs": augs, "name": pn}
	return {}


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


static func augs_w(augs: Array, sz: float) -> float:
	return augs.size() * (sz + 1.0)


## 강화 표시 —— 강화마다 ★ 하나 (강화 종류 색 · assets/kit/aug_<id>.png 가 있으면 그 그림). at = 왼쪽 가운데, 오른쪽으로 놓는다. 쓴 폭을 돌려준다
## ★ 는 글꼴의 글자 (나눔고딕에 있다) —— 다각형을 만들지 않는다. outline 은 밝은 바탕(초상 위) 에서만
static func draw_augs(ci: CanvasItem, at: Vector2, augs: Array, sz: float, a := 1.0, outline := false) -> float:
	if a <= 0.01 or sz < 2.0:
		return augs_w(augs, sz)
	var x := at.x
	var fs := roundi(sz + 2.0)
	for aug in augs:
		var art := tex("aug_" + str(aug))
		if art != null:
			ci.draw_texture_rect(art, Rect2(x, at.y - sz * 0.5, sz, sz), false, Color(1, 1, 1, a))
		else:
			var q := Vector2(x - 1.0, at.y + fs * 0.36)
			if outline:
				ci.draw_string_outline(DB.font_bold, q, "★", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0.05, 0.04, 0.03, 0.9 * a))
			ci.draw_string(DB.font_bold, q, "★", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(aug_col(str(aug)), a))
		x += sz + 1.0
	return x - at.x


# ───────── 사건 받기 (battle_view 가 기술 묶음 · 고유기를 시작할 때) ─────────

## key 가 slot 칸을 썼다 —— dsts 는 맞을(받을) 부대들, delay 는 맞는 순간까지 (근접 0.1 · 화살 0.55 · 책략 0.45 · 고유기 ULT_DELAY),
## wait 는 뜨기까지 (개전 P 알림을 차례로)
func add(key: String, slot: String, augs: Array, dsts: Array, delay: float, wait := 0.0) -> void:
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
	casts.append({"key": key, "slot": slot, "augs": augs, "start": now, "hit": hit,
		"end": maxf(now + CAST_LIFE, hit + HIT_LIFE + HIT_STAGGER * d.size()), "col": slot_col(slot), "dsts": d,
		"wide": augs.has("wide"), "fire": augs.has("fire"), "dmg": augs.has("dmg"), "sd": float(absi(hash(key + slot)) % 628) * 0.01})
	stats.cast += 1
	stats.hit += d.size()
	stats.by[slot] = int(stats.by.get(slot, 0)) + 1
	while casts.size() > MAX_CASTS:
		casts.pop_front()


# ───────── 위층 그리기 (TopEffects) ─────────

func draw(ci: CanvasItem) -> void:
	if casts.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var clock := float(p.last_clock)
	var lv := int(p.v.load_lv) if p.v.get("load_lv") != null else 0
	_marks = 0
	for i in range(casts.size() - 1, -1, -1):      # 새 발동부터 —— 표식 상한(MAX_MARKS)은 새것이 먼저 쓴다
		var c: Dictionary = casts[i]
		_draw_cast(ci, c, clock - float(c.start), lv)
		if not (c.dsts as Array).is_empty():
			_draw_hits(ci, c, clock - float(c.hit), lv)
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


func _l(a: Vector2, b: Vector2, col: Color, w: float, aa := false) -> void:
	_q_line.append(a)
	_q_line.append(b)
	_q_line.append(col)
	_q_line.append(w)
	_q_line.append(aa)


func _texture(nm: String) -> Texture2D:
	match nm:
		"disc": return baked()[2]
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


## 모아 둔 것을 차례대로 낸다 —— 그림(아래) → assets/kit 그림 → 세모 · 네모 → 선 → 불꽃
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
			Rect2(fw * clampi(int(float(_q_sheet[i + 3]) * n), 0, n - 1), 0.0, fw, ts.y), Color(1, 1, 1, _q_sheet[i + 4]))
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


## assets/kit 의 그림 한 칸을 모음에 넣는다 —— 가로 띠 시트면 칸 수 = 폭 ÷ 높이, u 0~1 진행에 맞는 칸 (한 장이면 그 한 장)
func _sheet(art: Texture2D, c: Vector2, sz: float, u: float, a: float) -> void:
	_q_sheet.append(art)
	_q_sheet.append(c)
	_q_sheet.append(sz)
	_q_sheet.append(u)
	_q_sheet.append(a)


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
	var aa := lv < 2
	var ink := lv < 2
	var sd := float(c.sd)
	var t := age / CAST_LIFE
	var a := (1.0 - smoothstep(0.55, 1.0, t)) * sq.fade
	var u := clampf(age / 0.5, 0.0, 1.0)
	var grow := 0.4 + 0.85 * ease(u, 0.45)
	var big := 1.35 if bool(c.wide) else 1.0
	var rx := R * grow * big
	var w := 3.2 if bool(c.dmg) else 2.4
	# 번쩍임 —— 몸에서 칸 색 빛 + 흰 심 (강격이면 더 크고 길게 + 여덟 갈래 섬광)
	var fl := 1.0 - clampf(age / (0.36 if bool(c.dmg) else 0.26), 0.0, 1.0)
	if fl > 0.0:
		p._spr(ci, "light_02", body, R * (4.6 if bool(c.dmg) else 3.4), Color(col, 0.9 * fl * sq.fade))
		_t("disc", body, R * 0.7 * fl + 4.0, Color(1, 1, 1, 0.6 * fl * sq.fade))
		if bool(c.dmg) and lv < 3:
			_t("star", body, R * (2.0 + 2.2 * (1.0 - fl)), Color(1, 1, 1, 0.9 * fl * sq.fade), age * 2.5)
	var sheet := tex("cast_" + slot)
	if sheet != null:      # 그림 시트가 있으면 바탕 고리 · 칸 모양 대신 그것을 (장수 몸 가운데에 겹친다 —— 번쩍임 · 확산 · 화공 덧표현은 그대로 얹는다)
		_sheet(sheet, body, R * 4.2 * big, t, sq.fade)
	else:      # 바탕 고리 —— 모든 칸이 같다 (누가 썼나)
		_ring(feet, rx, col, a, ink, sd + age * 1.4)
	if bool(c.wide) and lv < 3:      # 확산 —— 바깥에 한 겹 더, 조금 늦게
		var u2 := clampf((age - 0.1) / 0.5, 0.0, 1.0)
		if u2 > 0.0:
			_ring(feet, R * (0.55 + 1.2 * ease(u2, 0.45)) * big, col.lightened(0.35), a * 0.8, false, -sd - age, 1)
	if bool(c.fire):      # 화공 —— 불빛 테두리 + 고리 위 작은 불꽃
		_ring(feet, rx * 1.13, EMBER, a * (0.75 + 0.25 * sin(age * 31.0)), false, -sd - age * 2.0, 1)
		if lv < 3:
			for k in 4:
				var ang := TAU * (k + 0.5) / 4.0 + 0.4
				var fs := R * (0.5 + 0.12 * sin(age * 17.0 + k * 2.1))
				_t("flame_%d" % (k % 2), feet + Vector2(cos(ang) * rx * 1.13, sin(ang) * rx * 0.52 - fs * 0.35), fs, Color(1, 1, 1, a))
	if sheet != null:
		return
	# 칸 모양
	match slot:
		"q":      # 한 줄 베기 자국 —— 붓 한 획이 왼쪽 아래에서 오른쪽 위로 그어지고, 흰 날이 먼저 번쩍인다
			var k := clampf(age / 0.12, 0.15, 1.0)
			var ln := R * 3.3 * big
			var rot := -0.61
			var d := Vector2.from_angle(rot)
			if ink:
				_t("brush_0", body + Vector2(0, 1.5), ln * 1.05, Color(INK, 0.55 * a), rot, Vector2(k, 1.5))
			_t("brush_0", body, ln, Color(col, a), rot, Vector2(k, 1.3))
			var kf := 1.0 - clampf((age - 0.1) / 0.25, 0.0, 1.0)
			if kf > 0.0:
				_l(body - d * ln * 0.42 * k, body + d * ln * 0.42 * k, Color(1, 1, 1, 0.95 * kf * sq.fade), 2.0, aa)
		"w":      # 두 겹 고리 —— 안쪽 고리가 조금 늦게, 거꾸로 돌며 뒤따른다
			var uw := clampf((age - 0.12) / 0.5, 0.0, 1.0)
			if uw > 0.0:
				_ring(feet, R * (0.4 + 0.85 * ease(uw, 0.45)) * 0.62 * big, col.lightened(0.2), a, ink, -sd - age * 1.8, 1)
		"e":      # 세모 —— 몸 둘레에 선 세모가 커지며 사라진다
			var re := R * (0.55 + 0.5 * ease(u, 0.45)) * big
			_outline(PackedVector2Array([body + Vector2(0, -re), body + Vector2(re * 0.866, re * 0.5), body + Vector2(-re * 0.866, re * 0.5)]), col, w, a, aa, ink)
		"r":      # 햇살 —— 고리 밑에 여덟 갈래 금빛 별이 땅에 깔려 천천히 돈다
			if lv < 3:
				_t("gstar", feet, rx * 3.3, Color(col.lightened(0.2), 0.9 * a), sd + age * 0.9, Vector2(1.0, 0.46), true)
		"p":      # 마름모 —— 몸 둘레에서 두 번 맥박친다
			var pu := fposmod(age / 0.36, 1.0) if age < 0.72 else 1.0
			var rp := R * (0.75 + 0.5 * ease(pu, 0.5)) * big
			_outline(PackedVector2Array([body + Vector2(0, -rp * 1.15), body + Vector2(rp * 0.8, 0), body + Vector2(0, rp * 1.15), body + Vector2(-rp * 0.8, 0)]),
				col, w, a * (1.0 - 0.6 * pu), aa, ink)


func _draw_hits(ci: CanvasItem, c: Dictionary, age: float, lv: int) -> void:
	if age < -LINK_TRAVEL:
		return
	var src: Squad = p.v.field.squads.get(c.key)
	var col: Color = c.col
	var slot := str(c.slot)
	var aa := lv < 2
	var dsts: Array = c.dsts
	var mark := tex("hit_" + slot)
	var foe_cast := str(c.key).begins_with("B")
	var sz := 11.0 if bool(c.wide) else 9.0
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
			_ring(p.caster._anchor(dst, -2.0), clampf(p.caster._half_width_px(dst), 14.0, 40.0) * (0.6 + 0.6 * gu) * (1.2 if bool(c.wide) else 1.0),
				col, (1.0 - gu) * dst.fade, false, float(c.sd) + j)
		# 받침 —— 아군이 쓴 것은 먹빛, 적이 쓴 것(당했다)은 검붉게
		_t("disc", m, s * 3.1, Color(0.45, 0.07, 0.05, 0.66 * a) if foe_cast else Color(INK, 0.46 * a))
		if bool(c.fire):      # 화공 —— 표식 둘레 불빛 + 작은 불꽃
			_t("ring", m, s * 3.9, Color(EMBER, (0.7 + 0.3 * sin(aj * 29.0)) * a))
			if lv < 3:
				_t("flame_0", m + Vector2(s * 1.3, s * 0.4), s * 1.5, Color(1, 1, 1, a))
		if mark != null:      # 그림이 있으면 칸 모양 대신 그것을 (받침 위에 —— 그림은 모양만 담는다)
			_sheet(mark, m, s * 3.0, t, a)
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
				_q_prim.append(tri)
				_q_prim.append(Color(col, 0.95 * a))
				for k in 3:
					_l(tri[k], tri[(k + 1) % 3], Color(INK, a), 1.5)
			"r":      # 여덟 갈래 별 (먹 테가 있는 붓 별 그림)
				_t("star", m, s * 3.6, Color(col.lightened(0.15), a), aj * 1.5)
			_:        # P —— 마름모
				var dia := PackedVector2Array([m + Vector2(0, -s * 1.2), m + Vector2(s * 0.85, 0), m + Vector2(0, s * 1.2), m + Vector2(-s * 0.85, 0)])
				_q_prim.append(dia)
				_q_prim.append(Color(col, 0.95 * a))
				for k in 4:
					_l(dia[k], dia[(k + 1) % 4], Color(INK, a), 1.5)
