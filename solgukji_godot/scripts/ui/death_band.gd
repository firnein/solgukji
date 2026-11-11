extends Control
## 장수 사망 연출 (11/12 사용자: 온라인 장수 사망룰) —— 1일차 첫 아침에 사망 장수마다 하나씩.
## 초상이 가운데로 커지며 들어오고(트윈) · 붉은 칼금이 대각선으로 그어지고 · 초상이 그 선을 따라 두 조각으로 갈라져 벌어지며 떨어진다 ·
## 「[장수] 사망 —— 이번 판 등용 불가」 글이 남았다가 사라진다. 입력은 막지 않는다(mouse_filter IGNORE).
## class_name 은 만들지 않는다(낡은 .godot 캐시에서 'not declared') —— GameScreen 이 preload 로 쓴다.

signal done

const IN := 0.4           # 초상이 들어와 자리잡는 시간
const CUT := 0.85         # 칼금이 그어지기 시작하는 시각
const SPLIT := 1.0        # 두 조각으로 갈라지기 시작하는 시각
const FALL := 1.0         # 조각이 떨어지는 시간
const END := 2.9          # 끝 (글이 사라지는 시각)
const RED := Color("#ff3a2d")

var unit := ""
var t := 0.0
var _u := 1.0
var _tex: Texture2D = null
var _src := Rect2()
var _col := Color.WHITE


static func play(host: Control, unit_: String) -> Control:
	var b = load("res://scripts/ui/death_band.gd").new()
	b.unit = unit_
	host.add_child(b)
	return b


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 45
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_col = DB.tier_color(unit) if DB.C.has(unit) else DB.PAL.gold
	_tex = DB.portrait(unit) if DB.C.has(unit) else null
	if _tex != null:
		_src = Rect2(Vector2.ZERO, _tex.get_size())
		var face := DB.portrait_face(unit)
		if face.has_area():      # 얼굴을 1.9배로 넓힌 정사각형 (그림 밖은 자른다)
			var side := face.size.x * 1.9
			var c := face.get_center() + Vector2(0, face.size.y * 0.18)
			var r := Rect2(c - Vector2(side, side * 1.3) / 2.0, Vector2(side, side * 1.3))
			_src = r.intersection(_src)
	_layout()


func _layout() -> void:
	global_position = Vector2.ZERO      # 부모(GameScreen)가 크기를 갖지 않아 앵커가 듣지 않는다 —— 화면 전체로 직접 (UrgentBand 와 같다)
	size = get_viewport_rect().size
	_u = size.x / 400.0


func _process(dt: float) -> void:
	var was := t
	t += dt
	_layout()
	if was < CUT and t >= CUT:
		Sfx.play("crit")
	if was < SPLIT and t >= SPLIT and Settings.haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(40)
	if t >= END:
		done.emit()
		queue_free()
		return
	queue_redraw()


static func _ease_out(x: float) -> float:
	x = clampf(x, 0, 1)
	return 1.0 - pow(1.0 - x, 3)


static func _back_out(x: float) -> float:
	x = clampf(x, 0, 1)
	var c1 := 1.7
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3) + c1 * pow(x - 1.0, 2)


## 초상 사각형(가운데 기준 로컬 좌표) 안의 한 조각 —— pts 는 로컬 좌표, uv 는 그림 안 위치로 바꿔 그린다
func _piece(pts: PackedVector2Array, box: Rect2, off: Vector2, rot: float, a: float) -> void:
	var tp := PackedVector2Array()
	var uvs := PackedVector2Array()
	var ts := _tex.get_size() if _tex != null else Vector2.ONE
	var piv := box.get_center()
	for p in pts:
		var q := (p - box.position) / box.size
		uvs.append((_src.position + q * _src.size) / ts)
		tp.append(piv + (p - piv).rotated(rot) + off)
	if _tex != null:
		draw_colored_polygon(tp, Color(1, 1, 1, a), uvs, _tex)
	else:
		draw_colored_polygon(tp, Color(DB.PAL.ink3, a))
	var ol := tp.duplicate()
	ol.append(tp[0])
	draw_polyline(ol, Color(_col, a), 2.0 * _u, true)


func _draw() -> void:
	var u := _u
	var w := size.x
	var cy := size.y * 0.38
	# 어두운 바탕 —— 들어올 때 짙어지고 끝에 옅어진다
	var bg := _ease_out(t / 0.25) * (1.0 - clampf((t - (END - 0.4)) / 0.4, 0.0, 1.0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5 * bg))
	var pw := 150.0 * u
	var ph := pw * 1.3
	var sc := lerpf(1.8, 1.0, _back_out(t / IN))
	var pa := clampf(t / 0.15, 0.0, 1.0)
	var c := Vector2(w / 2.0, cy)
	var box := Rect2(c - Vector2(pw, ph) * sc / 2.0, Vector2(pw, ph) * sc)
	# 대각선 칼금 —— 왼쪽 위에서 오른쪽 아래로 (조금 비스듬히)
	var p0 := box.position + Vector2(box.size.x * 0.08, box.size.y * 0.18)
	var p1 := box.position + Vector2(box.size.x * 0.92, box.size.y * 0.82)
	var dir := (p1 - p0).normalized()
	var nrm := Vector2(dir.y, -dir.x)      # 칼금의 위쪽(오른쪽 위 조각) 방향
	# 칼금을 사각형 가장자리까지 늘린 두 점
	var e0 := p0 - dir * 400.0 * u
	var e1 := p1 + dir * 400.0 * u
	var a_pts := _clip_side(box, e0, e1, true)
	var b_pts := _clip_side(box, e0, e1, false)
	if t < SPLIT:
		# 하나의 초상
		draw_rect(Rect2(box.position + Vector2(5, 6) * u, box.size), Color(0, 0, 0, 0.45 * pa))
		_piece(PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]), box, Vector2.ZERO, 0.0, pa)
	else:
		var f := clampf((t - SPLIT) / FALL, 0.0, 1.0)
		var a := 1.0 - clampf((f - 0.55) / 0.45, 0.0, 1.0)
		var sep := _ease_out(f) * 26.0 * u
		var drop := f * f * 260.0 * u
		_piece(a_pts, box, nrm * sep + Vector2(10.0 * u * f, drop * 0.85), -0.35 * f * f, a)
		_piece(b_pts, box, -nrm * sep + Vector2(-10.0 * u * f, drop), 0.45 * f * f, a)
	# 칼금 —— CUT 에서 SPLIT 사이에 그어지고, 갈라진 뒤 잠깐 남아 사라진다
	if t >= CUT and t < SPLIT + 0.3:
		var g := clampf((t - CUT) / (SPLIT - CUT), 0.0, 1.0)
		var fade := 1.0 - clampf((t - SPLIT) / 0.3, 0.0, 1.0)
		var q0 := p0 - dir * 30.0 * u
		var q1 := q0.lerp(p1 + dir * 30.0 * u, g)
		draw_line(q0, q1, Color(1, 1, 1, 0.95 * fade), 5.0 * u, true)
		draw_line(q0, q1, Color(RED, 0.9 * fade), 2.0 * u, true)
	# 글 —— 「장수 사망」 큰 붉은 글 + 「이번 판 등용 불가」
	var ta := clampf((t - SPLIT) / 0.25, 0.0, 1.0) * (1.0 - clampf((t - (END - 0.35)) / 0.35, 0.0, 1.0))
	if ta > 0.0:
		var nm: String = DB.C[unit].name if DB.C.has(unit) else unit
		var l1 := "%s 사망" % nm
		var fs1 := int(30.0 * u)
		var f1 := DB.title_font(fs1)
		while fs1 > int(16.0 * u) and f1.get_string_size(l1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs1).x > w - 24.0 * u:
			fs1 -= 1
		var y1 := cy + ph / 2.0 + 44.0 * u
		draw_string_outline(f1, Vector2(0, y1), l1, HORIZONTAL_ALIGNMENT_CENTER, w, fs1, int(6.0 * u), Color(0, 0, 0, 0.9 * ta))
		draw_string(f1, Vector2(0, y1), l1, HORIZONTAL_ALIGNMENT_CENTER, w, fs1, Color(RED.lerp(Color.WHITE, 0.15), ta))
		var fs2 := int(18.0 * u)
		var f2 := DB.title_font(fs2)
		draw_string_outline(f2, Vector2(0, y1 + 30.0 * u), "이번 판 등용 불가", HORIZONTAL_ALIGNMENT_CENTER, w, fs2, int(5.0 * u), Color(0, 0, 0, 0.85 * ta))
		draw_string(f2, Vector2(0, y1 + 30.0 * u), "이번 판 등용 불가", HORIZONTAL_ALIGNMENT_CENTER, w, fs2, Color(DB.PAL.paper, ta))


## 사각형을 직선(e0 → e1)으로 자른 한쪽 다각형 —— upper 면 법선(오른쪽 위) 쪽
static func _clip_side(box: Rect2, e0: Vector2, e1: Vector2, upper: bool) -> PackedVector2Array:
	var poly := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	var d := e1 - e0
	var side := func(p: Vector2) -> float:
		var s := d.x * (p.y - e0.y) - d.y * (p.x - e0.x)
		return -s if upper else s
	var out := PackedVector2Array()
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var sa: float = side.call(a)
		var sb: float = side.call(b)
		if sa >= 0.0:
			out.append(a)
		if (sa >= 0.0) != (sb >= 0.0):
			out.append(a.lerp(b, sa / (sa - sb)))
	return out
