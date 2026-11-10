extends Control
## 긴급 등용 띠 (11/10 사용자) —— 다른 사람이 기인 이상(기인 · 초월 · 불멸 · 신화)을 등용하면 화면 위쪽 1/3 에 만화 같은 띠.
## 띠가 좌우에서 쾅 들어오고(0.2초, 조금 흔들림) · 띠 뒤로 장수 얼굴에서 퍼지는 집중선(몇 프레임마다 살짝 떨림) · 띠 안에 장수 얼굴이 크게 튀어나오고 ·
## 「[긴급!]」(붉은 큰 글씨) + 「유저가 장수를 등용」(유저 금색 · 장수 등급색, 길면 줄여 맞춘다) —— 약 2.5초 머문 뒤 위로 빠진다.
## 입력은 막지 않는다(mouse_filter IGNORE). 함성은 병종으로: 책략계(DB.INT_TAGS) = 지장(alert_wise), 물리계 = 무장(alert_war).
## class_name 은 만들지 않는다(낡은 .godot 캐시에서 'not declared') —— GameScreen 이 preload 로 쓴다.

signal done

const IN := 0.2           # 띠가 정착하는 시간
const HOLD := 2.7         # 이 시각까지 머문다 (IN 포함)
const OUT := 0.35         # 위로 빠지는 시간
const RED := Color("#ff3a2d")
const LINES := 54         # 집중선 수

var who := ""
var unit := ""
var t := 0.0
var _u := 1.0             # 화면 너비 / 400 —— 모든 길이가 이 배율을 따른다
var _fx_back: Control     # 띠 뒤 집중선 (띠 위아래로만 보이게 잘라 그린다)
var _fx_in: Control       # 띠 안의 옅은 집중선 (띠 바탕 위, 얼굴 · 글 아래)
var _top: Control         # 얼굴 · 글 (집중선 위에 그려야 해서 따로 —— 자식은 부모의 _draw 뒤에 그려진다)
var _cy := 200.0
var _off := Vector2.ZERO
var _tex: Texture2D = null
var _src := Rect2()
var _col := Color.WHITE
var _wise := false


static func play(host: Control, who_: String, unit_: String) -> Control:
	var b = load("res://scripts/ui/urgent_band.gd").new()
	b.who = who_
	b.unit = unit_
	host.add_child(b)
	return b


## 한글 받침이 있나 (한글이 아니면 없는 것으로)
static func batchim(s: String) -> bool:
	if s == "":
		return false
	var c := s.unicode_at(s.length() - 1)
	return c >= 0xAC00 and c <= 0xD7A3 and (c - 0xAC00) % 28 != 0


## 병종이 책략계면 지장, 아니면 무장
static func is_wise(k: String) -> bool:
	return DB.C.has(k) and DB.INT_TAGS.has(DB.C[k].tag)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 45
	_col = DB.tier_color(unit) if DB.C.has(unit) else DB.PAL.gold
	_wise = is_wise(unit)
	_tex = DB.portrait(unit) if DB.C.has(unit) else null
	if _tex != null:
		_src = _crop(unit, _tex)
	for n in ["_fx_back", "_fx_in", "_top"]:      # 그리는 차례: _fx_back(뒤) → 부모의 띠 바탕 → _fx_in → _top
		var c := Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.clip_contents = n != "_top"
		add_child(c)
		set(n, c)
	_fx_back.show_behind_parent = true
	_fx_back.draw.connect(_draw_back)
	_fx_in.draw.connect(_draw_in)
	_top.draw.connect(_draw_top)
	_top.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS      # 큰 그림을 줄여 그릴 때 선명하게 (Art._mip 와 같다)
	_layout()
	Sfx.play("alert_wise" if _wise else "alert_war", 0.0, 0.03)
	if Settings.haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(50)


## 얼굴(정사각형)을 1.8배로 넓혀 어깨까지, 그림 밖은 잘라 낸다
static func _crop(k: String, tex: Texture2D) -> Rect2:
	var face := DB.portrait_face(k)
	var ts := tex.get_size()
	if not face.has_area():
		return Rect2(Vector2.ZERO, ts)
	var side := face.size.x * 1.8
	var c := face.get_center() + Vector2(0, face.size.y * 0.16)
	var r := Rect2(c - Vector2(side, side) / 2.0, Vector2(side, side))
	r.position.x = clampf(r.position.x, 0.0, maxf(0.0, ts.x - side))
	r.position.y = clampf(r.position.y, 0.0, maxf(0.0, ts.y - side))
	return r.intersection(Rect2(Vector2.ZERO, ts))


func _layout() -> void:
	global_position = Vector2.ZERO          # 부모(GameScreen)가 크기를 갖지 않아 앵커가 듣지 않는다 —— 화면 전체로 직접 (ForgeFanfare 와 같다)
	size = get_viewport_rect().size
	_u = size.x / 400.0
	_cy = size.y * 0.235


func _process(dt: float) -> void:
	t += dt
	_layout()
	if t >= HOLD + OUT:
		done.emit()
		queue_free()
		return
	# 흔들림 —— 정착한 직후 0.3초
	var sh := clampf(1.0 - (t - IN) / 0.3, 0.0, 1.0) if t >= IN else 0.0
	_off = Vector2(sin(t * 95.0), cos(t * 71.0)) * 5.0 * _u * sh
	if t > HOLD:
		var q := (t - HOLD) / OUT
		_off.y -= q * q * 150.0 * _u
		modulate.a = 1.0 - q
	var h := 104.0 * _u
	var rh := h + 190.0 * _u            # 집중선이 보이는 높이 (띠 위아래로 95 씩)
	_fx_back.position = Vector2(0, _cy - rh / 2.0) + _off
	_fx_back.size = Vector2(size.x, rh)
	_fx_in.position = Vector2(0, _cy - h / 2.0) + _off
	_fx_in.size = Vector2(size.x, h)
	_top.position = Vector2.ZERO
	_top.size = size
	_top.queue_redraw()
	queue_redraw()
	_fx_back.queue_redraw()
	_fx_in.queue_redraw()


func _ease_out(x: float) -> float:
	x = clampf(x, 0, 1)
	return 1.0 - pow(1.0 - x, 3)


func _back_out(x: float) -> float:
	x = clampf(x, 0, 1)
	var c1 := 1.9
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3) + c1 * pow(x - 1.0, 2)


func _hash(a: int, b: int) -> float:
	var v := sin(float(a) * 12.9898 + float(b) * 78.233) * 43758.5453
	return v - floor(v)


## 집중선 —— 얼굴 자리(c)에서 퍼진다. 끝이 뾰족한 가는 쐐기를 바깥으로. 3프레임쯤마다(약 14번/초) 각도 · 안쪽 반지름이 살짝 떤다
func _lines(ci: Control, c: Vector2, col: Color, a_in: float, a_out: float, reach: float) -> void:
	var limit_y := minf(c.y, ci.size.y - c.y)      # 얼굴 자리에서 위/아래 가장자리까지의 짧은 쪽
	var fr := int(t * 14.0)
	for i in LINES:
		var ang := TAU * (float(i) + _hash(i, 7) * 0.8) / LINES + (_hash(i, fr) - 0.5) * 0.03
		var hw := (0.010 + _hash(i, 3) * 0.030) * (1.0 if i % 3 != 0 else 1.6)
		var r0 := (62.0 + _hash(i, 5) * 70.0 + (_hash(i, fr + 50) - 0.5) * 26.0) * _u
		var dl := Vector2.from_angle(ang - hw)
		var dr := Vector2.from_angle(ang + hw)
		var dm := Vector2.from_angle(ang)
		var rr := reach * (0.75 + _hash(i, 9) * 0.25)
		var sy := absf(sin(ang))
		if sy > 0.001:
			rr = minf(rr, (limit_y - 4.0 * _u) / sy)      # 잘리는 가장자리에 닿기 전에 끝난다 (딱딱한 가로 절단선이 안 보이게)
		ci.draw_polygon(PackedVector2Array([c + dm * r0, c + dl * rr, c + dr * rr]),
			PackedColorArray([Color(col, a_in), Color(col, a_out), Color(col, a_out)]))


func _face_c() -> Vector2:
	return Vector2(12.0 * _u + 59.0 * _u, _cy)


func _draw_back() -> void:
	var a := _ease_out(t / 0.12)
	var w := size.x
	var rh := _fx_back.size.y
	# 바탕 —— 가운데는 어둡게, 위아래 가장자리로 갈수록 투명
	var d := Color(0, 0, 0, 0.42 * a)
	var z := Color(0, 0, 0, 0.0)
	_fx_back.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, rh / 2), Vector2(0, rh / 2)]), PackedColorArray([z, z, d, d]))
	_fx_back.draw_polygon(PackedVector2Array([Vector2(0, rh / 2), Vector2(w, rh / 2), Vector2(w, rh), Vector2(0, rh)]), PackedColorArray([d, d, z, z]))
	var c := _face_c() - _fx_back.position + _off
	_lines(_fx_back, c, Color(1.0, 0.93, 0.85), 0.42 * a, 0.05 * a, 520.0 * _u)


func _draw_in() -> void:
	var a := _ease_out(t / 0.15)
	var c := _face_c() - _fx_in.position + _off
	_lines(_fx_in, c, Color(1.0, 0.55, 0.45), 0.34 * a, 0.12 * a, 460.0 * _u)


func _draw() -> void:
	var w := size.x
	var u := _u
	var h := 104.0 * u
	var e := _ease_out(t / IN)
	var top := _cy - h / 2.0
	draw_set_transform(_off, 0.0, Vector2.ONE)
	# ① 띠 —— 왼쪽 반은 왼쪽에서, 오른쪽 반은 오른쪽에서 들어와 가운데서 만난다
	var half := w / 2.0 + 2.0
	var bg_t := Color("#3b0c0f")
	var bg_b := Color("#16050a")
	for side in 2:
		var x0 := (-w / 2.0) * (1.0 - e) if side == 0 else w / 2.0 + (w / 2.0) * (1.0 - e)
		draw_polygon(PackedVector2Array([Vector2(x0, top), Vector2(x0 + half, top), Vector2(x0 + half, top + h), Vector2(x0, top + h)]),
			PackedColorArray([bg_t, bg_t, bg_b, bg_b]))
		draw_rect(Rect2(x0, top, half, 3.0 * u), RED)
		draw_rect(Rect2(x0, top + h - 3.0 * u, half, 3.0 * u), RED)
		draw_rect(Rect2(x0, top + 5.0 * u, half, 1.0 * u), Color(DB.PAL.gold, 0.55))
		draw_rect(Rect2(x0, top + h - 6.0 * u, half, 1.0 * u), Color(DB.PAL.gold, 0.55))

## 얼굴 · 글 · 쾅 번쩍임 —— 집중선보다 위
func _draw_top() -> void:
	var c := _top
	var w := size.x
	var u := _u
	var h := 104.0 * u
	var top := _cy - h / 2.0
	c.draw_set_transform(_off, 0.0, Vector2.ONE)
	# 쾅 —— 만나는 순간 흰 번쩍임
	if t >= IN * 0.9 and t < IN + 0.14:
		var f := 1.0 - (t - IN * 0.9) / (0.14 + IN * 0.1)
		c.draw_rect(Rect2(0, top, w, h), Color(1, 1, 1, 0.55 * clampf(f, 0.0, 1.0)))
	if t < 0.06:
		return
	# ② 장수 얼굴 —— 크게(2.4배)에서 1배로 쾅, 조금 기운 액자
	var pa := _back_out((t - 0.1) / 0.3)
	var ps := lerpf(2.4, 1.0, pa)
	var pal := clampf((t - 0.1) / 0.08, 0.0, 1.0)
	var P := 118.0 * u
	var pc := _face_c()
	c.draw_set_transform(_off + pc, deg_to_rad(-3.0), Vector2(ps, ps))
	var box := Rect2(-P / 2.0, -P / 2.0, P, P)
	c.draw_rect(Rect2(box.position + Vector2(4, 5) * u, box.size), Color(0, 0, 0, 0.5 * pal))
	c.draw_rect(box.grow(3.0 * u), Color(_col, pal))
	if _tex != null:
		c.draw_texture_rect_region(_tex, box, _src, Color(1, 1, 1, pal))
	else:
		c.draw_rect(box, Color(DB.PAL.ink3, pal))
		var ch := (DB.person(unit) if DB.C.has(unit) else "?").substr(0, 1)
		c.draw_string(DB.font_display, Vector2(box.position.x, box.position.y + P * 0.72), ch, HORIZONTAL_ALIGNMENT_CENTER, P, int(P * 0.62), Color(_col, pal))
	c.draw_rect(box.grow(3.0 * u), Color(0, 0, 0, 0.7 * pal), false, 1.0)
	c.draw_set_transform(_off, 0.0, Vector2.ONE)
	# ③ 글 —— 「[긴급!]」 붉은 큰 글씨 + 윤곽, 아래 한 줄
	var ta := _ease_out((t - 0.18) / 0.22)
	if ta <= 0.0:
		return
	var tx := 12.0 * u + P + 14.0 * u + (1.0 - ta) * 36.0 * u
	var avail := w - (12.0 * u + P + 14.0 * u) - 10.0 * u      # 슬라이드 중에도 같은 너비로 맞춘다 (줄 바꿈이 깜빡이지 않게)
	var lay := _fit(avail)
	var stack: bool = lay.stack
	var fs1 := int((26.0 if stack else 34.0) * u)
	var f1 := DB.title_font(fs1)
	var y1 := _cy + (-16.0 if stack else -4.0) * u
	var pulse := 0.5 + 0.5 * sin(t * 16.0)
	var rc := RED.lerp(Color("#ff8a70"), pulse * 0.35)
	var sc1 := 1.0 + 0.04 * pulse
	c.draw_set_transform(_off + Vector2(tx, y1), 0.0, Vector2(sc1, sc1))
	c.draw_string_outline(f1, Vector2.ZERO, "[긴급!]", HORIZONTAL_ALIGNMENT_LEFT, -1, fs1, int(7.0 * u), Color(0, 0, 0, 0.9 * ta))
	c.draw_string(f1, Vector2.ZERO, "[긴급!]", HORIZONTAL_ALIGNMENT_LEFT, -1, fs1, Color(rc, ta))
	c.draw_set_transform(_off, 0.0, Vector2.ONE)
	var rows: Array = lay.rows
	for ri in rows.size():
		_draw_row(c, Vector2(tx, _cy + (float(lay.ys[ri])) * u), rows[ri], int(lay.fs[ri]), ta)


## 둘째 줄 글을 조각(유저 · 조사 · 장수 · 조사)으로 —— 유저 금색 · 장수 등급색 · 나머지 종이색. 한 줄에 너비를 맞춰 글자를 줄이고,
## 16(화면 400 기준) 밑으로 내려가야 하면 두 줄(유저가 / 장수를 등용)로 쪼갠다 [긴급!] 도 작게 위로. 두 줄로도 길면 유저 이름을 …로 줄인다
func _fit(avail: float) -> Dictionary:
	var nm: String = DB.C[unit].name if DB.C.has(unit) else unit
	var u := _u
	var gold: Color = DB.PAL.gold.lightened(0.15)
	var nc: Color = _col.lightened(0.28)
	var j1 := "이" if batchim(who) else "가"
	var j2 := ("을" if batchim(nm) else "를") + " 등용"
	# 한 줄
	var one := [[who, gold], [j1 + " ", DB.PAL.paper], [nm, nc], [j2, DB.PAL.paper]]
	var fs := int(22.0 * u)
	var fmin := int(16.0 * u)
	while fs > fmin and _row_w(one, fs) > avail:
		fs -= 1
	if _row_w(one, fs) <= avail:
		return {"stack": false, "rows": [one], "fs": [fs], "ys": [30.0]}
	# 두 줄
	var shown := who
	var r1 := []
	var r2 := [[nm, nc], [j2, DB.PAL.paper]]
	var f1 := int(19.0 * u)
	var f2 := int(19.0 * u)
	var f3 := int(13.0 * u)
	while true:
		r1 = [[shown, gold], [("이" if batchim(shown) else "가"), DB.PAL.paper]]
		while f1 > f3 and _row_w(r1, f1) > avail:
			f1 -= 1
		if _row_w(r1, f1) <= avail or shown.length() <= 2:
			break
		shown = shown.substr(0, shown.length() - 2) + "…"
	while f2 > f3 and _row_w(r2, f2) > avail:
		f2 -= 1
	return {"stack": true, "rows": [r1, r2], "fs": [f1, f2], "ys": [10.0, 34.0]}


func _row_w(pieces: Array, fs: int) -> float:
	var f := DB.title_font(fs)
	var w := 0.0
	for p in pieces:
		w += f.get_string_size(p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return w


func _draw_row(c: Control, pos: Vector2, pieces: Array, fs: int, a: float) -> void:
	var u := _u
	var f := DB.title_font(fs)
	var x := pos.x
	for p in pieces:
		c.draw_string_outline(f, Vector2(x, pos.y), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(5.0 * u), Color(0, 0, 0, 0.85 * a))
		c.draw_string(f, Vector2(x, pos.y), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(p[1], a))
		x += f.get_string_size(p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
