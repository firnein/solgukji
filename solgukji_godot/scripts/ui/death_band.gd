extends Control
## 장수 사망 연출 (11/12 사용자: 온라인 장수 사망룰) —— 1일차 첫 아침에 사망 장수마다 하나씩.
## 초상이 가운데로 커지며 들어오고(트윈) · 붉은 칼금이 대각선으로 그어지고 · 초상이 그 선을 따라 두 조각으로 갈라져 벌어지며 떨어진다 ·
## 「[장수] 사망 —— 이번 판 등용 불가」 글이 남았다가 사라진다.
## 11/12 사용자 ① 신화 하위 불멸이 죽으면 신화 카드도 같이 —— myth 가 있으면 불멸 카드 뒤 위쪽에 신화 카드가 살짝 얹혀 나오고, 하나의 칼금이 두 카드를 함께 가른다.
## ② 연출이 너무 길다 —— 한 장 약 1.15초(전엔 2.9초), 끝나기 OVERLAP 초 전에 next 를 내 다음 카드가 겹쳐 들어온다 (10명 약 8초). 시간 상수는 맨 위.
## ③ 화면을 누르면 spd 가 빨라지고(GameScreen 이 정한다) 두 번 누르면 나머지를 건너뛴다 —— 누른 입력은 아래 화면으로 가지 않는다 (tapped).
## class_name 은 만들지 않는다(낡은 .godot 캐시에서 'not declared') —— GameScreen 이 preload 로 쓴다.

signal done
signal next          # 끝나기 OVERLAP 초 전 —— 다음 사망 카드를 시작해도 된다 (연출이 겹친다)
signal tapped

const IN := 0.28          # 초상이 들어와 자리잡는 시간
const CUT := 0.40         # 칼금이 그어지기 시작하는 시각
const SPLIT := 0.50       # 두 조각으로 갈라지기 시작하는 시각
const FALL := 0.55        # 조각이 떨어지는 시간
const END := 1.15         # 끝 (글이 사라지는 시각)
const OVERLAP := 0.40     # 끝나기 이만큼 전에 다음 카드가 시작된다 (한 장 간격 = END - OVERLAP = 0.75초)
const TEXT_FADE := 0.25   # 글이 나타나는 / 사라지는 시간
const MYTH_UP := 0.27     # 신화 카드가 불멸 카드보다 위로 얹히는 정도 (카드 높이 비)
const MYTH_SCALE := 0.94  # 신화 카드 크기 (불멸 카드 대비)
const RED := Color("#ff3a2d")

var unit := ""
var myth := ""            # 있으면 이 신화 카드가 뒤 위쪽에 같이 나와 함께 찢어진다
var spd := 1.0            # 재생 배율 —— 화면을 누르면 GameScreen 이 올린다
var hint := false         # 아래에 「화면을 누르면 빠르게」 안내 (사망 장수가 여럿일 때)
var t := 0.0
var _u := 1.0
var _cards := []          # [{tex, src, col}] —— 뒤(신화) → 앞(불멸) 순서로 그린다
var _next_sent := false
var _tap_t := -1.0


static func play(host: Control, unit_: String, myth_ := "", spd_ := 1.0, hint_ := false) -> Control:
	var b = load("res://scripts/ui/death_band.gd").new()
	b.unit = unit_
	b.myth = myth_
	b.spd = spd_
	b.hint = hint_
	host.add_child(b)
	return b


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 45
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if myth != "" and DB.C.has(myth):
		_cards.append(_card_of(myth))
	_cards.append(_card_of(unit))
	_layout()


## 카드 한 장의 그림 · 잘라 쓸 부분(얼굴을 1.9배로 넓힌 사각형) · 테두리색
func _card_of(k: String) -> Dictionary:
	var c := {"tex": null, "src": Rect2(), "col": DB.tier_color(k) if DB.C.has(k) else DB.PAL.gold}
	var tex: Texture2D = DB.portrait(k) if DB.C.has(k) else null
	c.tex = tex
	if tex != null:
		var src := Rect2(Vector2.ZERO, tex.get_size())
		var face := DB.portrait_face(k)
		if face.has_area():      # 얼굴을 1.9배로 넓힌 정사각형 (그림 밖은 자른다)
			var side := face.size.x * 1.9
			var ctr := face.get_center() + Vector2(0, face.size.y * 0.18)
			var r := Rect2(ctr - Vector2(side, side * 1.3) / 2.0, Vector2(side, side * 1.3))
			src = r.intersection(src)
		c.src = src
	return c


func _layout() -> void:
	global_position = Vector2.ZERO      # 부모(GameScreen)가 크기를 갖지 않아 앵커가 듣지 않는다 —— 화면 전체로 직접 (UrgentBand 와 같다)
	size = get_viewport_rect().size
	_u = size.x / 400.0


## 누르면 tapped —— 눌린 입력은 여기서 삼킨다 (아래 버튼이 눌리지 않게). 터치와 에뮬레이션된 마우스가 겹치니 0.15초 안의 두 번째는 무시
func _input(ev: InputEvent) -> void:
	var press := (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed)
	if not press:
		return
	get_viewport().set_input_as_handled()
	var now_ := Time.get_ticks_msec() / 1000.0
	if now_ - _tap_t < 0.15:
		return
	_tap_t = now_
	tapped.emit()


func _process(dt: float) -> void:
	var was := t
	t += dt * spd
	_layout()
	if was < CUT and t >= CUT:
		Sfx.play("crit")
	if was < SPLIT and t >= SPLIT and Settings.haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(40)
	if not _next_sent and t >= END - OVERLAP:
		_next_sent = true
		next.emit()
	if t >= END:
		done.emit()
		queue_free()
		return
	queue_redraw()


## 바로 지운다 (두 번째 누름 —— 나머지 건너뛰기)
func finish() -> void:
	if not _next_sent:
		_next_sent = true
	done.emit()
	queue_free()


static func _ease_out(x: float) -> float:
	x = clampf(x, 0, 1)
	return 1.0 - pow(1.0 - x, 3)


static func _back_out(x: float) -> float:
	x = clampf(x, 0, 1)
	var c1 := 1.7
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3) + c1 * pow(x - 1.0, 2)


## 초상 사각형(box) 안의 한 조각 —— pts 는 화면 좌표(회전 전), uv 는 그 카드의 그림 안 위치로 바꿔 그린다
func _piece(card: Dictionary, pts: PackedVector2Array, box: Rect2, off: Vector2, rot: float, a: float) -> void:
	if pts.size() < 3:
		return
	var tp := PackedVector2Array()
	var uvs := PackedVector2Array()
	var tex = card.tex
	var src: Rect2 = card.src
	var ts: Vector2 = tex.get_size() if tex != null else Vector2.ONE
	var piv := box.get_center()
	for p in pts:
		var q := (p - box.position) / box.size
		uvs.append((src.position + q * src.size) / ts)
		tp.append(piv + (p - piv).rotated(rot) + off)
	if tex != null:
		draw_colored_polygon(tp, Color(1, 1, 1, a), uvs, tex)
	else:
		draw_colored_polygon(tp, Color(DB.PAL.ink3, a))
	var ol := tp.duplicate()
	ol.append(tp[0])
	draw_polyline(ol, Color(card.col, a), 2.0 * _u, true)


func _draw() -> void:
	var u := _u
	var w := size.x
	var pair := _cards.size() > 1
	var pw := 150.0 * u
	var ph := pw * 1.3
	var cy := size.y * 0.38 + (ph * 0.12 if pair else 0.0)
	# 어두운 바탕 —— 들어올 때 짙어지고 끝에 옅어진다
	var bg := _ease_out(t / 0.2) * (1.0 - clampf((t - (END - 0.35)) / 0.35, 0.0, 1.0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5 * bg))
	var sc := lerpf(1.8, 1.0, _back_out(t / IN))
	var pa := clampf(t / 0.12, 0.0, 1.0)
	var g := Vector2(w / 2.0, cy)      # 카드 무리의 중심 —— 이 점을 기준으로 커지며 들어온다
	# 카드 상자 —— 앞(불멸)은 가운데, 신화는 뒤 위쪽에 살짝 얹힌다
	var boxes := []
	var union := Rect2()
	for i in _cards.size():
		var front := i == _cards.size() - 1
		var csz := Vector2(pw, ph) * (1.0 if front else MYTH_SCALE)
		var rel := Vector2.ZERO if front else Vector2(-0.03 * pw, -MYTH_UP * ph)
		var bx := Rect2(g + rel * sc - csz * sc / 2.0, csz * sc)
		boxes.append(bx)
		union = bx if i == 0 else union.merge(bx)
	# 대각선 칼금 —— 왼쪽 위에서 오른쪽 아래로 (조금 비스듬히), 무리 전체를 한 줄로
	var p0 := union.position + Vector2(union.size.x * 0.06, union.size.y * 0.16)
	var p1 := union.position + Vector2(union.size.x * 0.94, union.size.y * 0.84)
	var dir := (p1 - p0).normalized()
	var nrm := Vector2(dir.y, -dir.x)      # 칼금의 위쪽(오른쪽 위 조각) 방향
	var e0 := p0 - dir * 400.0 * u
	var e1 := p1 + dir * 400.0 * u
	if t < SPLIT:
		# 하나의 초상(들) —— 뒤 카드부터
		for i in _cards.size():
			var bx: Rect2 = boxes[i]
			draw_rect(Rect2(bx.position + Vector2(5, 6) * u, bx.size), Color(0, 0, 0, 0.45 * pa))
			_piece(_cards[i], PackedVector2Array([bx.position, Vector2(bx.end.x, bx.position.y), bx.end, Vector2(bx.position.x, bx.end.y)]), bx, Vector2.ZERO, 0.0, pa)
	else:
		var f := clampf((t - SPLIT) / FALL, 0.0, 1.0)
		var a := 1.0 - clampf((f - 0.55) / 0.45, 0.0, 1.0)
		var sep := _ease_out(f) * 26.0 * u
		var drop := f * f * 260.0 * u
		for i in _cards.size():
			var bx: Rect2 = boxes[i]
			var a_pts := _clip_side(bx, e0, e1, true)
			var b_pts := _clip_side(bx, e0, e1, false)
			_piece(_cards[i], a_pts, bx, nrm * sep + Vector2(10.0 * u * f, drop * 0.85), -0.35 * f * f, a)
			_piece(_cards[i], b_pts, bx, -nrm * sep + Vector2(-10.0 * u * f, drop), 0.45 * f * f, a)
	# 칼금 —— CUT 에서 SPLIT 사이에 그어지고, 갈라진 뒤 잠깐 남아 사라진다
	if t >= CUT and t < SPLIT + 0.2:
		var gg := clampf((t - CUT) / (SPLIT - CUT), 0.0, 1.0)
		var fade := 1.0 - clampf((t - SPLIT) / 0.2, 0.0, 1.0)
		var q0 := p0 - dir * 30.0 * u
		var q1 := q0.lerp(p1 + dir * 30.0 * u, gg)
		draw_line(q0, q1, Color(1, 1, 1, 0.95 * fade), 5.0 * u, true)
		draw_line(q0, q1, Color(RED, 0.9 * fade), 2.0 * u, true)
	# 글 —— 「장수 사망」 큰 붉은 글 + 「이번 판 등용 불가」 (신화가 같이면 한 줄 더)
	var ta := clampf((t - SPLIT) / TEXT_FADE, 0.0, 1.0) * (1.0 - clampf((t - (END - TEXT_FADE)) / TEXT_FADE, 0.0, 1.0))
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
		if pair:
			var l3 := "하위 불멸이 사망해 신화 %s 도 함께" % str(DB.C[myth].name)
			var fs3 := int(15.0 * u)
			var f3 := DB.title_font(fs3)
			while fs3 > int(10.0 * u) and f3.get_string_size(l3, HORIZONTAL_ALIGNMENT_LEFT, -1, fs3).x > w - 24.0 * u:
				fs3 -= 1
			draw_string_outline(f3, Vector2(0, y1 + 56.0 * u), l3, HORIZONTAL_ALIGNMENT_CENTER, w, fs3, int(4.0 * u), Color(0, 0, 0, 0.85 * ta))
			draw_string(f3, Vector2(0, y1 + 56.0 * u), l3, HORIZONTAL_ALIGNMENT_CENTER, w, fs3, Color(DB.tier_color(myth), ta))
	if hint:
		var fh := DB.title_font(int(13.0 * u))
		var hy := size.y - 56.0 * u
		var txt := "화면을 누르면 빨리 넘어갑니다 (두 번 누르면 건너뜀)"
		draw_string_outline(fh, Vector2(0, hy), txt, HORIZONTAL_ALIGNMENT_CENTER, w, int(13.0 * u), int(4.0 * u), Color(0, 0, 0, 0.8 * bg))
		draw_string(fh, Vector2(0, hy), txt, HORIZONTAL_ALIGNMENT_CENTER, w, int(13.0 * u), Color(DB.PAL.paper, 0.75 * bg))


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
