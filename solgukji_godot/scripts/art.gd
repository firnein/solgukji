class_name Art
extends RefCounted
## 초상 그리기 —— 실제 그림(assets/…png)이 있으면 그것을, 없으면 수묵 실루엣 플레이스홀더를 그린다.
## 플레이스홀더는 세력색 배경 + 성씨 한 글자 + 병종별 머리 장식·소품으로 인물마다 조금씩 다르게 보인다.

const INK := Color("#0a0e18")


static func draw_portrait(ci: CanvasItem, r: Rect2, k: String, t := 0.0) -> void:
	# 넓이가 없거나(접히는 중인 칸) 화면에서 아주 먼 곳(달아난 부대의 머리표)은 그리지 않는다 —— 좌표가 크면 다각형 분할이 실패한다
	if r.size.x < 1.0 or r.size.y < 1.0 or absf(r.position.x) > 20000.0 or absf(r.position.y) > 20000.0:
		return
	var c: Dictionary = DB.C[k]
	var tex := DB.portrait(k)
	var fc := DB.fac_color(c.fac)
	var tc := DB.tier_color(k)
	var top := fc.darkened(0.62) if c.tier > 2 else DB.PAL.ink3
	var bot: Color = DB.PAL.ink
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top.lerp(bot, 0.3), bot, bot]))
	# 먹 번짐 —— 등급색을 옅게 깐다
	ci.draw_circle(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.45), minf(r.size.x, r.size.y) * 0.42, Color(tc, 0.09))
	# 실제 그림 —— 배경이 투명한 그림도 세력색 바탕 위에 얹힌다
	if tex:
		var used := DB.portrait_used(k)
		if used.has_area() and DB.portrait_panel(k):
			_draw_panel(ci, r, tex, used)
		elif used.has_area():
			_draw_fit(ci, r, tex, used)
		else:
			_draw_cover(ci, r, tex)
		return

	if c.tier <= 2:
		_troops(ci, r, c)
		return
	# 성씨 한 글자 —— 배경 낙관처럼 크게
	var ch: String = DB.person(k).substr(0, 1)
	var fs := int(r.size.y * 0.58)
	var f := DB.font_display
	var sz := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	ci.draw_string(f, Vector2(r.end.x - sz.x - r.size.x * 0.03, r.position.y + fs * 0.92), ch,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(fc.lightened(0.35), 0.17))
	_silhouette(ci, r, c, tc)


static func _silhouette(ci: CanvasItem, r: Rect2, c: Dictionary, tc: Color) -> void:
	var w := r.size.x
	var h := r.size.y
	var cx := r.position.x + w * 0.46
	var base := r.end.y
	var hr := minf(w, h) * 0.12
	var head := Vector2(cx, r.position.y + h * 0.40)
	var phys: bool = DB.PHYS_TAGS.has(c.tag)
	var prop := Color(DB.PAL.paper, 0.55)

	# 소품 —— 몸 뒤에 먼저 그린다
	match c.tag:
		"창병":
			var a := Vector2(cx + w * 0.30, base)
			var b := Vector2(cx + w * 0.20, r.position.y + h * 0.10)
			ci.draw_line(a, b, Color(INK, 0.95), maxf(2.0, w * 0.025))
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x)
			ci.draw_colored_polygon(PackedVector2Array([b + d * h * 0.12, b + n * w * 0.035, b - n * w * 0.035]), prop)
		"궁병":
			ci.draw_arc(Vector2(cx - w * 0.16, r.position.y + h * 0.58), h * 0.30, -1.2, 1.2, 18, Color(INK, 0.95), maxf(2.0, w * 0.022))
			ci.draw_line(Vector2(cx - w * 0.16 + cos(-1.2) * h * 0.30, r.position.y + h * 0.58 + sin(-1.2) * h * 0.30),
				Vector2(cx - w * 0.16 + cos(1.2) * h * 0.30, r.position.y + h * 0.58 + sin(1.2) * h * 0.30), prop, 1.0)
		"기병":
			var a := Vector2(cx - w * 0.34, base - h * 0.05)
			var b := Vector2(cx - w * 0.18, r.position.y + h * 0.14)
			ci.draw_line(a, b, Color(INK, 0.95), maxf(2.0, w * 0.025))
			ci.draw_arc(b + Vector2(w * 0.03, h * 0.05), w * 0.07, -2.4, 0.6, 10, prop, maxf(2.0, w * 0.02))

	# 어깨와 몸
	var body := PackedVector2Array()
	var rx := w * 0.44
	var ry := h * 0.40
	var bc := Vector2(cx, base + h * 0.12)
	for i in 21:
		var ang := PI + PI * i / 20.0
		var p := bc + Vector2(cos(ang) * rx, sin(ang) * ry)
		p.y = minf(p.y, base)
		body.append(p)
	ci.draw_colored_polygon(body, Color(INK, 0.93))
	# 목
	ci.draw_rect(Rect2(cx - hr * 0.42, head.y + hr * 0.5, hr * 0.84, hr * 1.6), Color(INK, 0.93))
	# 머리
	ci.draw_circle(head, hr, Color(INK, 0.96))
	# 테두리광 —— 등급색
	ci.draw_arc(head, hr + 1.0, -PI * 0.95, -PI * 0.05, 16, Color(tc, 0.55), 1.5)
	ci.draw_polyline(body.slice(2, 19), Color(tc, 0.28), 1.2)

	# 머리 장식 —— 무장은 투구와 술, 문관은 높은 관
	if phys:
		ci.draw_arc(head, hr * 1.08, PI, TAU, 14, Color(INK, 1.0), hr * 0.28)
		ci.draw_colored_polygon(PackedVector2Array([head + Vector2(-hr * 0.22, -hr * 1.05),
			head + Vector2(hr * 0.22, -hr * 1.05), head + Vector2(0, -hr * 1.9)]), Color(tc, 0.85))
	else:
		ci.draw_rect(Rect2(head.x - hr * 0.55, head.y - hr * 1.75, hr * 1.1, hr * 0.95), Color(INK, 1.0))
		ci.draw_line(head + Vector2(-hr * 1.2, -hr * 0.82), head + Vector2(hr * 1.2, -hr * 0.82), Color(INK, 1.0), maxf(2.0, hr * 0.2))
		ci.draw_line(head + Vector2(-hr * 0.55, -hr * 1.75), head + Vector2(hr * 0.55, -hr * 1.75), Color(tc, 0.6), 1.5)
		# 지략 계열 소품은 병종 아이콘을 손에 쥐여준다
		var ic: Texture2D = DB.ICON[c.tag]
		var s := minf(w, h) * 0.26
		ci.draw_texture_rect(ic, Rect2(cx + w * 0.16, base - s * 1.25, s, s), false, prop)
	if c.tag == "도적":
		ci.draw_rect(Rect2(head.x - hr, head.y - hr * 0.15, hr * 2, hr * 0.42), Color(DB.PAL.seal, 0.75))


static func _troops(ci: CanvasItem, r: Rect2, c: Dictionary) -> void:
	# 병사 카드 —— 병종 실루엣 셋을 대열로 세운다
	var ic: Texture2D = DB.ICON[c.tag]
	var col: Color = DB.TIER[c.tier].c.lightened(0.25)
	var s := minf(r.size.x, r.size.y) * 0.42
	var cx := r.position.x + r.size.x * 0.5
	var cy := r.position.y + r.size.y * 0.52
	for i in [-1, 1]:
		ci.draw_texture_rect(ic, Rect2(cx + i * s * 0.62 - s * 0.35, cy - s * 0.25, s * 0.7, s * 0.7), false, Color(col, 0.35))
	ci.draw_texture_rect(ic, Rect2(cx - s * 0.5, cy - s * 0.55, s, s), false, Color(col, 0.9))


## 패널 그림 —— 칸 너비에 맞추고 아래를 잘라 칸을 꽉 채운다 (머리·투구 깃은 남긴다)
static func _draw_panel(ci: CanvasItem, r: Rect2, tex: Texture2D, used: Rect2) -> void:
	var area := r.grow(-minf(r.size.x, r.size.y) * 0.03)
	var src := used
	var want_h := used.size.x * area.size.y / area.size.x
	if want_h < used.size.y:
		src.size.y = want_h
		ci.draw_texture_rect_region(tex, area, src)
		return
	# 칸이 그림보다 세로로 길면 높이에 맞추고 양옆을 자른다
	var want_w := used.size.y * area.size.x / area.size.y
	src.position.x += (used.size.x - want_w) / 2
	src.size.x = want_w
	ci.draw_texture_rect_region(tex, area, src)


## 패널 그림을 칸 밖으로 튀어나오게 —— 패널은 칸 너비를 꽉 채우고(아래는 자름), 패널 위로 솟은 깃·무기는
## 칸 위로 최대 pop 만큼 넘쳐 그린다. 테두리 뒤에 불러 테두리를 덮게 한다. 패널 그림이 아니면 false.
static func draw_panel_pop(ci: CanvasItem, r: Rect2, k: String, pop: float) -> bool:
	if not DB.portrait_panel(k):
		return false
	var tex := DB.portrait(k)
	var used := DB.portrait_used(k)
	var top := DB.portrait_panel_top(k)
	var s := r.size.x / used.size.x
	# 그림 맨 위를 칸 위 above 에 둔다 —— 깃·무기가 납작하게 잘리지 않고 통째로 솟는다 (그만큼 아래를 더 자른다)
	var above := minf((top - used.position.y) * s, pop)
	var src := Rect2(used.position, Vector2(used.size.x, minf((r.size.y + above) / s, used.size.y)))
	ci.draw_texture_rect_region(tex, Rect2(r.position.x, r.position.y - above, r.size.x, src.size.y * s), src)
	return true


## 잘라 낸 인물 —— 그려진 영역 전체가 들어오게 줄이고, 아래쪽 띠(칸 높이의 15%) 위에 발을 붙여 가운데 둔다
static func _draw_fit(ci: CanvasItem, r: Rect2, tex: Texture2D, used: Rect2) -> void:
	var area := Rect2(r.position + Vector2(r.size.x * 0.05, r.size.y * 0.05), Vector2(r.size.x * 0.9, r.size.y * 0.80))
	var sc := minf(area.size.x / used.size.x, area.size.y / used.size.y)
	var sz := used.size * sc
	var pos := Vector2(area.position.x + (area.size.x - sz.x) / 2, area.end.y - sz.y)
	ci.draw_texture_rect_region(tex, Rect2(pos, sz), used)


static func _draw_cover(ci: CanvasItem, r: Rect2, tex: Texture2D) -> void:
	var ts := tex.get_size()
	var scale := maxf(r.size.x / ts.x, r.size.y / ts.y)
	var src_size := r.size / scale
	var src := Rect2((ts - src_size) * Vector2(0.5, 0.25), src_size)
	ci.draw_texture_rect_region(tex, r, src)


## 고등급 장식 —— 불멸은 빗살 문양, 신화는 반짝이는 금박
static func draw_tier_fx(ci: CanvasItem, r: Rect2, k: String, t: float) -> void:
	var tier: int = DB.C[k].tier
	var tc := DB.tier_color(k)
	if tier >= 7:
		var poly := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		var step := 10.0
		var x := r.position.x - r.size.y
		while x < r.end.x:
			var line := PackedVector2Array([Vector2(x, r.end.y), Vector2(x + r.size.y, r.position.y)])
			for seg in Geometry2D.intersect_polyline_with_polygon(line, poly):
				ci.draw_polyline(seg, Color(tc, 0.07), 1.0)
			x += step
	if tier >= 8:
		var h := hash(k)
		for i in 6:
			var px := r.position.x + float((h >> (i * 4)) & 15) / 15.0 * r.size.x
			var py := r.position.y + float((h >> (i * 4 + 2)) & 15) / 15.0 * r.size.y * 0.8
			var a := 0.5 + 0.5 * sin(t * 3.0 + i * 1.7)
			var s := 2.0 + 3.0 * a
			var col := Color("#ffe9a8", a * 0.9)
			ci.draw_line(Vector2(px - s, py), Vector2(px + s, py), col, 1.2)
			ci.draw_line(Vector2(px, py - s), Vector2(px, py + s), col, 1.2)
