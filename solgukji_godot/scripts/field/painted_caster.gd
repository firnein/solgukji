extends RefCounted
## 11/25 책략계 기여 표시 —— 사용자: 「책략계가 하고 있는 일들이 너무 눈에 띄지 않음」.
## 신화 제갈량 1200판 측정: 판당 약 38개 사건이 삽화에 아무것도 남기지 않았다 (버프 · 디버프 19 · 혼란 4 · 천문 4 · 기술 발동 6 …).
## 엔진 사건(buff · debuff · skill · ult_warn · ult · int)만 보고 그린다 —— 판정 · 수치와 무관한 화면 연출. 노드를 만들지 않고
## WarPainting 의 위층(TopEffects._draw) · 바닥 테두리 묶음(_mk_rim)에 얹는다. 갈래마다 상한이 있다.
##   버프 · 디버프 —— 시전 부대 → 대상 짧은 빛줄기 + 대상 위 작은 표지 (칼 공격 · 방패 방어 · 겹화살 속도 · 별 그 밖). 올림 금빛, 깎음 보랏빛 + 아래 화살
##   천문 —— 적이 기를 모으면 그 고유기가 칠 아군(ult_warn.warn)에 육각 막, 고유기가 터질 때 한 번 더
##   책략 기술 발동 —— 시전 부대 발밑 원 + 기술 이름 작게
##   책략 타격 —— 맞는 자리 별빛 반짝임
##   혼란 —— 머리 위 도는 별 셋 + 물음표 (병사 비틀거림은 WarPainting._collect_figures)
##   위세 —— 늘 켜진 진영 효과를 가진 부대 발밑에 옅은 금빛 원 + 여덟 눈금 (팔괘)

const KitFx = preload("res://scripts/field/painted_kit.gd")

var p        # WarPainting
var links: Array = []      # {src, dsts: [key], kinds: [kind], up, start}
var wards: Array = []      # {key, src, start}
var casts: Array = []      # {key, name, start, col}
var sparks: Array = []     # {at (전장), start, col}
var _omen_wait := {}       # 천문 사건 직후 —— 다음 적 기 모으기(ult_warn)에 붙인다 {src, camp, t}
var _last_warn := {}       # 가장 최근 기 모으기 {a, camp, keys, t}
var _omen_by := {}         # 기를 모으는 적 장수 key -> {src, keys} (고유기가 터질 때 막을 한 번 더)
var _aura := {}            # 부대 key -> 위세를 가졌나 (한 번만 잰다)
var stats := {"link": 0, "link_dst": 0, "ward": 0, "cast": 0, "spark": 0, "peak": 0}

const MAX_LINKS := 8
const MAX_LINK_DSTS := 5
const LINK_LIFE := 1.25
const LINK_TRAVEL := 0.3
const MAX_WARDS := 9
const WARD_LIFE := 1.5
const MAX_CASTS := 5
const CAST_LIFE := 1.15
const MAX_SPARKS := 12
const SPARK_LIFE := 0.42

const INK := Color("#29271f")
const UP_LINE := Color("#ffd98a")
const DOWN_LINE := Color("#c58bff")
const GLYPH_UP := {"atk": Color("#ffb04a"), "def": Color("#8fd0ff"), "spd": Color("#9cf0a8"), "gen": Color("#ffd257")}
const GLYPH_DOWN := Color("#c58bff")
const WARD_COL := Color(0.62, 0.86, 1.0)
const AURA_COL := Color("#ffd27a")
const CASTER_TAGS := ["책사", "유생", "모사"]


func _init(painter) -> void:
	p = painter


func reset() -> void:
	links.clear()
	wards.clear()
	casts.clear()
	sparks.clear()
	_omen_wait.clear()
	_last_warn.clear()
	_omen_by.clear()
	_aura.clear()
	for k in stats:
		stats[k] = 0


func prune(clock: float) -> void:
	if not links.is_empty():
		links = links.filter(func(l): return clock - float(l.start) < LINK_LIFE + 0.05 * MAX_LINK_DSTS)
	if not wards.is_empty():
		wards = wards.filter(func(w): return clock - float(w.start) < WARD_LIFE)
	if not casts.is_empty():
		casts = casts.filter(func(c): return clock - float(c.start) < CAST_LIFE)
	if not sparks.is_empty():
		sparks = sparks.filter(func(s): return clock - float(s.start) < SPARK_LIFE)
	stats.peak = maxi(int(stats.peak), links.size() + wards.size() + casts.size() + sparks.size())


# ───────── 사건 받기 (WarPainting.play_event · add_skill 이 넘긴다) ─────────

func on_event(e: Dictionary) -> void:
	var fx := str(e.get("fx", ""))
	match fx:
		"buff":
			var who := str(e.get("who", ""))
			var dst := str(e.get("f", ""))
			_on_buff(who if who != "" else dst, dst, bool(e.get("up", true)), _kind_of_text(str(e.get("t", ""))))
		"debuff":
			var src := str(e.get("from", e.get("a", e.get("who", ""))))
			var dst := str(e.get("f", ""))
			_on_buff(src if src != "" else dst, dst, false, _kind_of_cut(str(e.get("st", ""))))
		"skill":
			var a := str(e.get("a", ""))
			if int(e.get("ai", 0)) == 0:      # 개전 「패업 발동」 알림 —— 판 첫머리에 한꺼번에 뜨지 않게
				return
			var ksq: Squad = p.v.field.squads.get(a)
			# 11/27 키트 장수의 Q · W · E 는 칸 딱지 · 칸 색 고리가 대신한다 (같은 기술 이름이 두 번 뜨지 않게 —— painted_kit.gd)
			if ksq == null or KitFx.resolve(e, ksq.cid).is_empty():
				add_cast(a, str(e.get("name", "")))      # 묶음의 who 가 아니라 사건의 a (천문은 적 장수 차례에 적힌다)
			if str(e.get("name", "")) == "천문":
				var sq: Squad = p.v.field.squads.get(a)
				if sq != null:
					_omen_wait = {"src": a, "camp": sq.camp, "t": float(p.v.field.clock)}
					_omen_pair()
		"ult_warn":
			var caster: Squad = p.v.field.squads.get(str(e.get("a", "")))
			if caster != null:
				var keys := []
				for w in e.get("warn", []):
					if w is Dictionary and w.has("k"):
						keys.append(str(w.k))
				_last_warn = {"a": caster.key, "camp": caster.camp, "keys": keys, "t": float(p.v.field.clock)}
				_omen_pair()
		"ult":
			var a := str(e.get("a", ""))
			if _omen_by.has(a):
				_add_wards(str(_omen_by[a].src), _omen_by[a].keys)
				_omen_by.erase(a)


## 천문 사건과 적의 기 모으기(ult_warn)를 잇는다 —— 엔진에서는 같은 순간이지만 화면에서는 묶음 종류(책략 0.6초 늦춤)에 따라 어느 쪽이 먼저 올지 모른다
func _omen_pair() -> void:
	if _omen_wait.is_empty() or _last_warn.is_empty() or str(_last_warn.camp) == str(_omen_wait.camp):
		return
	if absf(float(_last_warn.t) - float(_omen_wait.t)) > 0.9:
		return
	_omen_by[str(_last_warn.a)] = {"src": _omen_wait.src, "keys": _last_warn.keys}
	_add_wards(str(_omen_wait.src), _last_warn.keys)
	_omen_wait.clear()
	_last_warn.clear()


## 버프 · 디버프 하나 —— 같은 시전 부대 · 같은 방향(올림/깎음)이 0.35초 안에 또 오면 한 줄기 묶음에 대상을 더한다
func _on_buff(src: String, dst: String, up: bool, kind: String) -> void:
	if dst == "" or not p.v.field.squads.has(dst):
		return
	var now := float(p.v.field.clock)
	for l: Dictionary in links:
		if now - float(l.start) > 0.6:
			continue
		var j: int = (l.dsts as Array).find(dst)
		if j >= 0 and l.up == up and l.kinds[j] == kind:
			return      # 같은 대상 · 같은 표지가 방금 떴다
	for l: Dictionary in links:
		if l.src == src and l.up == up and now - float(l.start) < 0.35:
			if (l.dsts as Array).size() < MAX_LINK_DSTS and not (l.dsts as Array).has(dst):
				l.dsts.append(dst)
				l.kinds.append(kind)
				stats.link_dst += 1
			return
	links.append({"src": src, "dsts": [dst], "kinds": [kind], "up": up, "start": now})
	stats.link += 1
	stats.link_dst += 1
	while links.size() > MAX_LINKS:
		links.pop_front()


func _add_wards(src: String, keys: Array) -> void:
	var now := float(p.v.field.clock)
	for k in keys:
		wards = wards.filter(func(w): return w.key != k)
		wards.append({"key": k, "src": src, "start": now})
		stats.ward += 1
	while wards.size() > MAX_WARDS:
		wards.pop_front()


## 책략 기술 발동 —— 같은 부대는 1.2초 안에 한 번 (묶음 시작 · 사건 둘 다 부른다)
func add_cast(key: String, name: String) -> void:
	var sq: Squad = p.v.field.squads.get(key)
	if sq == null or not CASTER_TAGS.has(sq.tag) or name == "":
		return
	var now := float(p.v.field.clock)
	for c: Dictionary in casts:
		if c.key == key and now - float(c.start) < 1.2:
			return
	casts.append({"key": key, "name": name, "start": now, "col": p.SPELL_COL.get(sq.tag, p.EMBER)})
	stats.cast += 1
	while casts.size() > MAX_CASTS:
		casts.pop_front()


## 책략 타격이 맞은 자리 (전장 좌표)
func add_spark(at: Vector2, tag: String) -> void:
	sparks.append({"at": at, "start": float(p.v.field.clock), "col": p.SPELL_COL.get(tag, p.EMBER)})
	stats.spark += 1
	while sparks.size() > MAX_SPARKS:
		sparks.pop_front()


static func _kind_of_text(t: String) -> String:
	var head := t.split(" ——")[0]
	if head.contains("공격") or head.contains("반격"):
		return "atk"
	if head.contains("방어") or head.contains("방진") or head.contains("막"):
		return "def"
	if head.contains("속도") or head.contains("빨라"):
		return "spd"
	return "gen"


static func _kind_of_cut(st: String) -> String:
	if st.contains("atk"):
		return "atk"
	if st.contains("def") or st.contains("res") or st.contains("int"):
		return "def"
	if st.contains("spd"):
		return "spd"
	return "gen"


# ───────── 위세 (바닥 테두리 묶음에 얹는다 —— WarPainting._draw 가 부른다) ─────────

func has_aura(sq: Squad) -> bool:
	if not _aura.has(sq.key):
		_aura[sq.key] = Battle.aura_enabled and DB.AURA.has(sq.cid) and (Battle.aura_camp == "" or sq.camp == Battle.aura_camp)
	return bool(_aura[sq.key])


## 부대 둘레 옅은 금빛 타원 + 천천히 도는 여덟 눈금 —— 선분만 앞줄 표식 묶음(_mk_ln · 먹 3px + 색 1.5px)에 보탠다 (그리기 호출이 늘지 않는다)
func aura_marks(sq: Squad, form) -> void:
	var ln: PackedVector2Array = p._mk_ln
	var ink_c: PackedColorArray = p._mk_ink
	var lc: PackedColorArray = p._mk_lc
	var fade: float = sq.fade * (1.0 - 0.8 * maxf(p.cover_of(sq), 0.0))
	if fade <= 0.02:
		return
	var facing := Vector2.from_angle(form.heading)
	var right := Vector2(-facing.y, facing.x)
	var rr: float = form.half_width + 10.0
	var rf: float = maxf(sq.hd(), 14.0) + 8.0
	var c: Vector2 = form.center
	var col := Color(AURA_COL, 0.5 * fade)
	var ink := Color(INK, 0.16 * fade)
	var spin := float(p.v.field.clock) * 0.12
	for k in 24:      # 눈금 사이가 빈 원 —— 셋 중 둘만 그어 팔괘 효(爻)처럼 끊어 보이게
		if k % 3 == 2:
			continue
		var t0 := spin + TAU * k / 24.0
		var t1 := spin + TAU * (k + 1) / 24.0
		ln.append(p._pm(c + right * cos(t0) * rr + facing * sin(t0) * rf))
		ln.append(p._pm(c + right * cos(t1) * rr + facing * sin(t1) * rf))
		ink_c.append(ink)
		lc.append(col)
	var tick := Color(AURA_COL, 0.75 * fade)
	for k in 8:
		var t := spin + TAU * (k + 0.5) / 8.0
		var d := right * cos(t) * rr + facing * sin(t) * rf
		ln.append(p._pm(c + d * 1.08))
		ln.append(p._pm(c + d * 1.22))
		ink_c.append(Color(INK, 0.3 * fade))
		lc.append(tick)
	p._mk_ln = ln
	p._mk_ink = ink_c
	p._mk_lc = lc


# ───────── 위층 그리기 (TopEffects) ─────────

func draw(ci: CanvasItem) -> void:
	var clock := float(p.last_clock)
	for w: Dictionary in wards:
		_draw_ward(ci, w, clock - float(w.start))
	for s: Dictionary in sparks:
		_draw_spark(ci, s, clock - float(s.start))
	for l: Dictionary in links:
		_draw_link(ci, l, clock - float(l.start))
	for c: Dictionary in casts:
		_draw_cast(ci, c, clock - float(c.start))


## 부대 반폭의 화면 길이 (px)
func _half_width_px(sq: Squad) -> float:
	var form = p.formations.get(sq.key)
	var at: Vector2 = form.center if form != null else sq.pos
	var hw: float = form.half_width if form != null else sq.hw
	return (p.v.map(at + sq.right() * hw) - p.v.map(at)).length()


## 부대 몸통 높이의 화면 자리 (장수 한 명으로 그리는 부대는 장수 키 절반)
func _anchor(sq: Squad, lift := 16.0) -> Vector2:
	var form = p.formations.get(sq.key)
	var at: Vector2 = form.center if form != null else sq.pos
	var ds: float = p.v.depth_scale(at)
	if p.hero_feet.has(sq.key):
		return p.hero_feet[sq.key] - Vector2(0, (lift + 12.0) * ds)
	return p.v.map(at) - Vector2(0, lift * ds)


func _draw_link(ci: CanvasItem, l: Dictionary, age: float) -> void:
	if age < 0.0:
		return
	var src: Squad = p.v.field.squads.get(l.src)
	var col := UP_LINE if l.up else DOWN_LINE
	for j in (l.dsts as Array).size():
		var dst: Squad = p.v.field.squads.get(l.dsts[j])
		if dst == null or not dst.alive or dst.fade <= 0.01:
			continue
		var aj := age - j * 0.05
		if aj < 0.0:
			continue
		var b := _anchor(dst)
		var arrive := 0.0
		if src != null and src != dst and src.alive:
			arrive = LINK_TRAVEL
			var a := _anchor(src)
			var lift := minf(36.0, a.distance_to(b) * 0.18)
			var u := clampf(aj / LINK_TRAVEL, 0.0, 1.0)
			var tail := clampf(u - 0.5, 0.0, 1.0)
			var fade := 1.0 - smoothstep(LINK_TRAVEL, LINK_TRAVEL + 0.35, aj)
			if fade > 0.0:
				var pts := PackedVector2Array()
				for k in 7:
					var s := lerpf(tail, u, k / 6.0)
					pts.append(a.lerp(b, s) - Vector2(0, sin(s * PI) * lift))
				ci.draw_polyline(pts, Color(INK, 0.35 * fade), 4.0, false)
				ci.draw_polyline(pts, Color(col, 0.9 * fade), 2.0, false)
				if u < 1.0:
					ci.draw_circle(pts[6], 3.2, Color(col, fade))
					ci.draw_circle(pts[6], 1.6, Color(1, 1, 1, fade))
		var g := aj - arrive
		if g >= 0.0:
			_glyph(ci, b, str(l.kinds[j]), bool(l.up), g, LINK_LIFE - arrive)


## 대상 위 표지 —— 톡 튀어나와 조금 떠오르다 사라진다
func _glyph(ci: CanvasItem, at: Vector2, kind: String, up: bool, age: float, life: float) -> void:
	var t := clampf(age / maxf(0.2, life), 0.0, 1.0)
	var a := 1.0 - smoothstep(0.6, 1.0, t)
	if a <= 0.0:
		return
	var pop := 0.55 + 0.45 * smoothstep(0.0, 0.1, age) + 0.18 * (1.0 - smoothstep(0.1, 0.25, age)) * smoothstep(0.0, 0.1, age)
	var s := 8.0 * pop
	var c := at - Vector2(0, 7.0 * t)
	var col: Color = GLYPH_UP.get(kind, GLYPH_UP.gen) if up else GLYPH_DOWN
	ci.draw_circle(c, s * 1.55, Color(INK, 0.38 * a))
	match kind:
		"atk":      # 칼
			ci.draw_line(c + Vector2(-0.75, 0.9) * s, c + Vector2(0.75, -1.05) * s, Color(INK, a), 4.0, false)
			ci.draw_line(c + Vector2(-0.75, 0.9) * s, c + Vector2(0.75, -1.05) * s, Color(col, a), 2.2, false)
			ci.draw_line(c + Vector2(-0.75, 0.0) * s, c + Vector2(0.15, 0.62) * s, Color(INK, a), 3.6, false)
			ci.draw_line(c + Vector2(-0.75, 0.0) * s, c + Vector2(0.15, 0.62) * s, Color(col, a), 1.8, false)
		"def":      # 방패
			var sh := PackedVector2Array()
			for q in [Vector2(-0.85, -0.95), Vector2(0.85, -0.95), Vector2(0.78, 0.2), Vector2(0.0, 1.05), Vector2(-0.78, 0.2)]:
				sh.append(c + q * s)
			ci.draw_colored_polygon(sh, Color(col, 0.85 * a))
			sh.append(sh[0])
			ci.draw_polyline(sh, Color(INK, a), 1.4, false)
		"spd":      # 겹화살
			for k in 2:
				var y := (0.25 - k * 0.7) * s
				var ch := PackedVector2Array([c + Vector2(-0.8 * s, y + 0.45 * s), c + Vector2(0, y - 0.25 * s), c + Vector2(0.8 * s, y + 0.45 * s)])
				ci.draw_polyline(ch, Color(INK, a), 3.8, false)
				ci.draw_polyline(ch, Color(col, a), 2.0, false)
		_:          # 별
			var st := PackedVector2Array()
			for k in 8:
				var r := s * (1.1 if k % 2 == 0 else 0.42)
				st.append(c + Vector2.from_angle(-PI * 0.5 + k * PI / 4.0) * r)
			ci.draw_colored_polygon(st, Color(col, 0.95 * a))
	# 올림 ▲ 금빛 · 깎음 ▼ 붉은 보랏빛 —— 표지 오른쪽 아래
	var m := c + Vector2(s * 1.25, s * 0.55)
	var tri := PackedVector2Array([m + Vector2(-3.2, 2.2), m + Vector2(3.2, 2.2), m + Vector2(0, -3.0)]) if up \
		else PackedVector2Array([m + Vector2(-3.2, -2.2), m + Vector2(3.2, -2.2), m + Vector2(0, 3.0)])
	ci.draw_colored_polygon(tri, Color(Color("#ffe27a") if up else Color("#ff6a8a"), a))


## 천문 막 —— 지켜질 아군 둘레 땅에 육각, 위로 옅은 반구. 처음 0.35초 제갈량 쪽에서 가는 빛줄기
func _draw_ward(ci: CanvasItem, w: Dictionary, age: float) -> void:
	if age < 0.0:
		return
	var sq: Squad = p.v.field.squads.get(w.key)
	if sq == null or not sq.alive or sq.fade <= 0.01:
		return
	var t := clampf(age / WARD_LIFE, 0.0, 1.0)
	var a := 1.0 - smoothstep(0.65, 1.0, t)
	var grow := 0.7 + 0.3 * smoothstep(0.0, 0.2, age)
	var g := _anchor(sq, 10.0)
	var rx := clampf(_half_width_px(sq) + 6.0, 16.0, 46.0) * grow
	var ry := rx * 0.62
	var hexp := PackedVector2Array()
	for k in 7:
		var ang := TAU * k / 6.0
		hexp.append(g + Vector2(cos(ang) * rx, sin(ang) * ry))
	var flash := 1.0 - smoothstep(0.0, 0.3, age)
	var fill := PackedVector2Array(hexp)
	fill.remove_at(6)
	ci.draw_colored_polygon(fill, Color(WARD_COL, (0.12 + 0.16 * flash) * a))
	ci.draw_polyline(hexp, Color(INK, 0.4 * a), 3.6, true)
	ci.draw_polyline(hexp, Color(WARD_COL.lightened(0.3 * flash), 0.9 * a), 1.8, true)
	# 안쪽 작은 육각 (막이 겹으로 보이게)
	var inner := PackedVector2Array()
	for k in 7:
		inner.append(g + (hexp[k] - g) * 0.55)
	ci.draw_polyline(inner, Color(WARD_COL, 0.45 * a), 1.2, true)
	# 육각 꼭짓점 반짝임 (처음만)
	if flash > 0.0:
		for k in 6:
			ci.draw_circle(hexp[k], 2.2 * flash + 0.6, Color(1, 1, 1, flash * a))
	var src: Squad = p.v.field.squads.get(w.src)
	if src != null and src.alive and src != sq and age < 0.45:
		var s0 := _anchor(src)
		var u := clampf(age / 0.3, 0.0, 1.0)
		var f2 := 1.0 - smoothstep(0.3, 0.45, age)
		ci.draw_line(s0.lerp(g, maxf(0.0, u - 0.5)), s0.lerp(g, u), Color(INK, 0.3 * f2), 3.4, true)
		ci.draw_line(s0.lerp(g, maxf(0.0, u - 0.5)), s0.lerp(g, u), Color(WARD_COL, 0.85 * f2), 1.6, true)


## 책략 타격 반짝임 —— 네 갈래 별빛 (보통 합성: 황토 땅에서도 보인다) + 더하기 빛
func _draw_spark(ci: CanvasItem, s: Dictionary, age: float) -> void:
	if age < 0.0:
		return
	var at: Vector2 = s.at
	var q: Vector2 = p.v.map(at) - Vector2(0, 9.0 * p.v.depth_scale(at))
	var t := clampf(age / SPARK_LIFE, 0.0, 1.0)
	var a := 1.0 - smoothstep(0.35, 1.0, t)
	var r := 5.0 + 7.0 * smoothstep(0.0, 0.25, t)
	var col: Color = s.col
	var st := PackedVector2Array()
	for k in 8:
		st.append(q + Vector2.from_angle(age * 2.5 + k * PI / 4.0) * (r if k % 2 == 0 else r * 0.28))
	ci.draw_colored_polygon(st, Color(col, 0.9 * a))
	ci.draw_circle(q, r * 0.22, Color(1, 1, 1, a))
	p._spr(ci, "star_06", q, r * 3.2, Color(col, 0.75 * a), age * 2.0)


## 책략 기술 발동 —— 시전 부대 발밑에서 퍼지는 원 + 기술 이름 (작은 글씨, 조금 떠오른다)
func _draw_cast(ci: CanvasItem, c: Dictionary, age: float) -> void:
	if age < 0.0:
		return
	var sq: Squad = p.v.field.squads.get(c.key)
	if sq == null or not sq.alive or sq.fade <= 0.01:
		return
	var t := clampf(age / CAST_LIFE, 0.0, 1.0)
	var col: Color = c.col
	var u := smoothstep(0.0, 0.45, age)
	if u < 1.0:
		var g := _anchor(sq, -2.0)
		var rx := clampf(_half_width_px(sq), 12.0, 40.0) * (0.55 + 0.75 * u)
		var pts := PackedVector2Array()
		for k in 21:
			var ang := TAU * k / 20.0
			pts.append(g + Vector2(cos(ang) * rx, sin(ang) * rx * 0.42))
		ci.draw_polyline(pts, Color(INK, 0.4 * (1.0 - u)), 4.4, true)
		ci.draw_polyline(pts, Color(col.lightened(0.2), 0.95 * (1.0 - u)), 2.4, true)
	var a := 1.0 - smoothstep(0.7, 1.0, t)
	var top := _anchor(sq, 26.0) - Vector2(0, 8.0 * t)
	p._spr(ci, "light_02", top + Vector2(0, 6), 40.0, Color(col, 0.55 * a * (1.0 - smoothstep(0.0, 0.5, age))))
	p._action_label(top, str(c.name), col.lightened(0.35), a * smoothstep(0.0, 0.08, age), ci)


## 혼란 —— 머리 위를 도는 별 셋 + 물음표 (예전: 반지름 7px 호 하나)
func draw_confuse(ci: CanvasItem, sq: Squad) -> void:
	var head := _anchor(sq, 30.0)
	var ds: float = clampf(p.v.depth_scale(sq.pos), 0.8, 1.25)
	var clock := float(p.v.field.clock)
	# 발밑 —— 도는 보랏빛 소용돌이 세 획 (멀리서 볼 때도 어느 부대가 묶였는지)
	var feet := _anchor(sq, -2.0)
	var wx := clampf(_half_width_px(sq) + 4.0, 14.0, 42.0)
	for k in 3:
		var a0 := -clock * 2.6 + k * TAU / 3.0
		var arc := PackedVector2Array()
		for j in 7:
			var ang := a0 + j * 0.24
			var rr := wx * (0.75 + 0.25 * j / 6.0)
			arc.append(feet + Vector2(cos(ang) * rr, sin(ang) * rr * 0.4))
		ci.draw_polyline(arc, Color(INK, 0.35), 4.0, true)
		ci.draw_polyline(arc, Color(0.8, 0.58, 1.0, 0.85), 2.0, true)
	var rx := 15.0 * ds
	var ry := 5.5 * ds
	for k in 3:
		var ang := clock * 3.4 + k * TAU / 3.0
		var q := head + Vector2(cos(ang) * rx, sin(ang) * ry)
		var front := sin(ang) > 0.0
		var r := (4.8 if front else 3.6) * ds
		var st := PackedVector2Array()
		for j in 8:
			st.append(q + Vector2.from_angle(clock * 4.0 + j * PI / 4.0) * (r if j % 2 == 0 else r * 0.38))
		ci.draw_circle(q, r * 1.15, Color(INK, 0.35))
		ci.draw_colored_polygon(st, Color("#ffe27a") if front else Color("#d6b8ff"))
	var bob := sin(clock * 5.0) * 1.5
	var fs := 17
	var qpos := head + Vector2(-4.5, -7.0 + bob) * ds
	ci.draw_string_outline(DB.font_bold, qpos, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(INK, 0.9))
	ci.draw_string(DB.font_bold, qpos, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#e8c8ff"))
