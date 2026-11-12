extends Control
## 멸망 · 엔딩 연출 (11/12 사용자: "최종 멸망 이후에 엔딩씬이 없다") —— 내 판이 끝났을 때 한 번 (GameScreen.show_ending).
## 멸망: 화면이 어두워지고 → 내 세력 깃발이 꺾여 부러지며 쓰러진다. 사람에게 멸망당했으면 그 전에 처형 연출
##       (내 군주 초상 위로 칼 그림자가 내리치고 · 붉은 번쩍임 · 화면 흔들림, 잔혹 묘사 없이 초상이 잿빛으로 가라앉을 뿐) + 「[유저]에게 멸망당했습니다」,
##       봇 · 토벌이면 「세력이 무너졌습니다」.
## 승리: 깃발이 아래에서 솟아올라 펄럭이고 금빛이 퍼진다 + 「천하를 얻었다」.
## 연출 뒤(또는 화면을 누르면 바로) 아래에 요약 —— 최종 순위 · 버틴 날 · 전적 · 플레이 시간 · 핵심 장수(높은 등급 순) · [처음으로] [다시 하기] (+ 온라인 관전 계속).
## 그림은 모두 코드로(외부 에셋 없음) · 효과음은 Sfx 의 기존 소리. class_name 은 만들지 않는다 —— GameScreen 이 preload 로 쓴다.
## info = {win, rank, by, by_human, days, w, l, deck, playtime, name?, glyph?, msg?, lord?, again_text?, watch?}

signal home
signal again
signal watch

const RED := Color("#ff3a2d")
const GOLD := Color("#ffd98a")

var info := {}
var gs: Control = null          # GameScreen —— 핵심 장수 타일(mtile) · 카드 정보
var t := 0.0
var _u := 1.0
var _mode := "lose"             # lose | lose_user | win
var _sum_at := 2.6              # 요약이 뜨는 시각
var _shake_t := -9.0            # 흔들림이 시작된 시각
var _flash_t := -9.0            # 붉은 번쩍임이 시작된 시각
var _summary: Control = null
var _tex: Texture2D = null
var _src := Rect2()
var _cued := {}                  # 이미 낸 효과음


static func play(host: Control, info_: Dictionary, gs_: Control = null) -> Control:
	var e = load("res://scripts/ui/ending.gd").new()
	e.info = info_
	e.gs = gs_
	host.add_child(e)
	return e


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if bool(info.get("win", false)):
		_mode = "win"
	elif bool(info.get("by_human", false)) and str(info.get("by", "")) != "":
		_mode = "lose_user"
	_sum_at = {"win": 2.7, "lose": 2.7, "lose_user": 4.3}[_mode]
	var lord := str(info.get("lord", ""))
	if lord == "" and not (info.get("deck", []) as Array).is_empty():
		lord = str(info.deck[0])
	if DB.C.has(lord):
		_tex = DB.portrait(lord)
		if _tex != null:
			_src = Rect2(Vector2.ZERO, _tex.get_size())
			var face := DB.portrait_face(lord)
			if face.has_area():
				var side := face.size.x * 1.9
				var ctr := face.get_center() + Vector2(0, face.size.y * 0.18)
				_src = Rect2(ctr - Vector2(side, side * 1.3) / 2.0, Vector2(side, side * 1.3)).intersection(_src)
	Sfx.music("win" if _mode == "win" else "lose")
	_layout()


func _layout() -> void:
	global_position = Vector2.ZERO      # 부모(GameScreen)가 크기를 갖지 않을 수 있어 화면 전체로 직접 (DeathBand 와 같다)
	size = get_viewport_rect().size
	_u = minf(size.x / 400.0, size.y / 720.0)


## 연출 중에 누르면 바로 요약으로
func _gui_input(ev: InputEvent) -> void:
	var press: bool = (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed)
	if press and t < _sum_at:
		t = _sum_at
		_cue_all()
		accept_event()


func _cue(key: String, at: float, was: float, snd: String, vib := 0) -> void:
	if was < at and t >= at and not _cued.has(key):
		_cued[key] = true
		if snd != "":
			Sfx.play(snd)
		if vib > 0 and Settings.haptics and OS.has_feature("mobile"):
			Input.vibrate_handheld(vib)


func _cue_all() -> void:      # 건너뛰면 남은 효과음은 내지 않는다
	for k in ["swing", "cut", "snap", "land", "rise"]:
		_cued[k] = true


func _process(dt: float) -> void:
	var was := t
	t += dt
	_layout()
	match _mode:
		"lose_user":
			_cue("swing", 1.45, was, "swing")
			if was < 1.68 and t >= 1.68 and not _cued.has("cut"):
				_shake_t = t
				_flash_t = t
			_cue("cut", 1.68, was, "crit", 60)
			if was < 3.0 and t >= 3.0 and not _cued.has("snap"):
				_shake_t = t
			_cue("snap", 3.0, was, "crit", 30)
			_cue("land", 3.55, was, "rout", 30)
		"lose":
			if was < 1.1 and t >= 1.1 and not _cued.has("snap"):
				_shake_t = t
			_cue("snap", 1.1, was, "crit", 40)
			_cue("land", 1.65, was, "rout", 30)
		"win":
			_cue("rise", 0.35, was, "horn")
			_cue("land", 1.3, was, "drums")
	if t >= _sum_at and _summary == null:
		_build_summary()
	queue_redraw()


# ───────── 그리기 ─────────

static func _ease_out(x: float) -> float:
	x = clampf(x, 0, 1)
	return 1.0 - pow(1.0 - x, 3)


static func _ease_in(x: float) -> float:
	x = clampf(x, 0, 1)
	return x * x * x


## 위쪽 연출 칸의 높이 —— 아래는 요약
func _stage_h() -> float:
	return size.y * 0.50


func _draw() -> void:
	var u := _u
	var w := size.x
	var H := _stage_h()
	# 어두워지는 바탕 (흔들림과 상관없이 화면 전체)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.04, 0.95 * _ease_out(t / 0.7)))
	if _mode == "win":
		_draw_rays(Vector2(w / 2.0, H * 0.30), clampf((t - 1.1) / 0.8, 0.0, 1.0))
	var sh := Vector2.ZERO
	var st := t - _shake_t
	if st >= 0.0 and st < 0.4:
		var k := (1.0 - st / 0.4) * 9.0 * u
		sh = Vector2(sin(t * 91.0) * k, cos(t * 77.0) * k * 0.7)
	draw_set_transform(sh, 0.0, Vector2.ONE)
	var ground := H * 0.70
	var ga := _ease_out((t - (2.35 if _mode == "lose_user" else 0.0)) / 0.7)
	if ga > 0.0:
		draw_line(Vector2(w * 0.18, ground), Vector2(w * 0.82, ground), Color(DB.PAL.bamboo_dim, 0.35 * ga), 2.0 * u, true)
	match _mode:
		"lose_user":
			_draw_execution(Vector2(w / 2.0, H * 0.44))
			_draw_flag_lose(Vector2(w / 2.0 - 30.0 * u, ground), 2.35, 3.0)
		"lose":
			_draw_flag_lose(Vector2(w / 2.0 - 30.0 * u, ground), 0.25, 1.1)
		"win":
			_draw_flag_win(Vector2(w / 2.0 - 30.0 * u, ground))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 붉은 번쩍임
	var ft := t - _flash_t
	if ft >= 0.0 and ft < 0.45:
		draw_rect(Rect2(Vector2.ZERO, size), Color(RED, 0.5 * (1.0 - ft / 0.45)))
	_draw_text(H)


## 글 —— 큰 한 줄 + 작은 한 줄
func _draw_text(H: float) -> void:
	var u := _u
	var w := size.x
	var at: float = {"win": 1.3, "lose": 1.5, "lose_user": 3.3}[_mode]
	var a := clampf((t - at) / 0.4, 0.0, 1.0)
	if a <= 0.0:
		return
	var l1: String
	var l2 := ""
	var col: Color
	match _mode:
		"win":
			l1 = "천하를 얻었다"
			l2 = "최후의 군주로 남았습니다"
			col = GOLD
		"lose_user":
			l1 = "%s에게 멸망당했습니다" % str(info.by)
			l2 = "군주가 칼 아래 스러지고 깃발이 꺾였다"
			col = RED.lerp(Color.WHITE, 0.15)
		_:
			l1 = "세력이 무너졌습니다"
			var by := str(info.get("by", ""))
			l2 = ("%s에게 패해 깃발이 꺾였다" % by) if by != "" else "민심이 바닥나 깃발이 꺾였다"
			col = RED.lerp(Color.WHITE, 0.15)
	var fs1 := int(34.0 * u)
	var f1 := DB.title_font(fs1)
	while fs1 > int(16.0 * u) and f1.get_string_size(l1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs1).x > w - 28.0 * u:
		fs1 -= 1
	var y1 := H * 0.70 + 54.0 * u - (1.0 - a) * 10.0 * u
	draw_string_outline(f1, Vector2(0, y1), l1, HORIZONTAL_ALIGNMENT_CENTER, w, fs1, int(7.0 * u), Color(0, 0, 0, 0.9 * a))
	draw_string(f1, Vector2(0, y1), l1, HORIZONTAL_ALIGNMENT_CENTER, w, fs1, Color(col, a))
	var fs2 := int(16.0 * u)
	var f2 := DB.title_font(fs2)
	draw_string_outline(f2, Vector2(0, y1 + 30.0 * u), l2, HORIZONTAL_ALIGNMENT_CENTER, w, fs2, int(5.0 * u), Color(0, 0, 0, 0.85 * a))
	draw_string(f2, Vector2(0, y1 + 30.0 * u), l2, HORIZONTAL_ALIGNMENT_CENTER, w, fs2, Color(DB.PAL.paper, 0.85 * a))


## 깃발 한 벌 —— origin 이 깃대 밑동, 위가 -y. from_y ~ to_y 사이의 깃대(밑동에서 잰 길이)와 꼭대기면 천을 그린다
func _flag_part(org: Vector2, rot: float, y0: float, y1: float, L: float, cloth: bool, a: float, droop: float) -> void:
	var u := _u
	draw_set_transform(org + _shake_off(), rot, Vector2.ONE)
	var pw := 7.0 * u
	draw_rect(Rect2(-pw / 2.0, -y1, pw, y1 - y0), Color(Color("#6b4a2a"), a))
	draw_rect(Rect2(-pw / 2.0, -y1, pw * 0.35, y1 - y0), Color(Color("#9a7448"), a))
	if cloth:
		# 깃대 꼭대기 장식 (창날 모양)
		draw_colored_polygon(PackedVector2Array([Vector2(-6 * u, -L), Vector2(0, -L - 18 * u), Vector2(6 * u, -L)]), Color(GOLD, a))
		var cw := L * 0.62
		var ch := L * 0.40
		var top := -L + 4.0 * u
		var n := 14
		var up := PackedVector2Array()
		var dn := PackedVector2Array()
		for i in n + 1:
			var x := cw * float(i) / n
			var q := x / cw
			var wave := sin(q * 5.5 - t * 6.0) * 7.0 * u * q * (1.0 - droop)
			var sag := droop * q * q * ch * 1.1      # 꺾이면 천이 처진다
			up.append(Vector2(pw / 2.0 + x * (1.0 - droop * 0.6), top + wave + sag))
			dn.append(Vector2(pw / 2.0 + x * (1.0 - droop * 0.6), top + ch + wave * 1.1 + sag * 1.25 - q * droop * ch * 0.2))
		var poly := up.duplicate()
		for i in range(n, -1, -1):
			poly.append(dn[i])
		var cc := DB.PAL.seal if _mode != "win" else Color("#c23b2e")
		draw_colored_polygon(poly, Color(cc.darkened(0.25 * droop), a))
		# 테두리 금줄 + 아래 술
		var ol := up.duplicate()
		ol.append_array(PackedVector2Array([dn[n]]))
		draw_polyline(ol, Color(GOLD, 0.8 * a), 2.0 * u, true)
		draw_polyline(dn, Color(GOLD, 0.8 * a), 2.0 * u, true)
		# 가운데 글자 (세력 표지)
		var gl := str(info.get("glyph", "蜀"))
		var fs := int(ch * 0.55)
		var f := DB.title_font(fs)
		var mid: Vector2 = (up[n / 2] + dn[n / 2]) / 2.0
		draw_circle(mid, ch * 0.33, Color(Color("#f3e6c4"), 0.9 * a))
		draw_string(f, mid + Vector2(-ch * 0.5, fs * 0.36), gl, HORIZONTAL_ALIGNMENT_CENTER, ch, fs, Color(cc.darkened(0.3), a))
	draw_set_transform(_shake_off(), 0.0, Vector2.ONE)


func _shake_off() -> Vector2:
	var st := t - _shake_t
	if st >= 0.0 and st < 0.4:
		var k := (1.0 - st / 0.4) * 9.0 * _u
		return Vector2(sin(t * 91.0) * k, cos(t * 77.0) * k * 0.7)
	return Vector2.ZERO


## 멸망 깃발 —— appear 에 나타나 서 있다가 snap 에 꺾여 윗동이 쓰러진다
func _draw_flag_lose(base: Vector2, appear: float, snap: float) -> void:
	var a := clampf((t - appear) / 0.35, 0.0, 1.0)
	if a <= 0.0:
		return
	var u := _u
	var L := _stage_h() * 0.52
	var brk := L * 0.42      # 꺾이는 높이
	if t < snap:
		var tremble := 0.0 if t < snap - 0.35 else sin(t * 70.0) * 0.012      # 꺾이기 직전 떨림
		_flag_part(base, tremble, 0.0, L, L, true, a, 0.0)
		return
	var f := clampf((t - snap) / 0.55, 0.0, 1.0)
	var ang := _ease_in(f) * 1.78
	if f >= 1.0:      # 땅에 닿은 뒤 작게 튕긴다
		var g := clampf((t - snap - 0.55) / 0.35, 0.0, 1.0)
		ang = 1.78 - sin(g * PI) * 0.08
	var pivot := base + Vector2(0, -brk).lerp(Vector2(L * 0.04, -L * 0.24), _ease_in(f))
	# 아랫동 (그대로 서 있다)
	_flag_part(base, 0.0, 0.0, brk, L, false, a, 0.0)
	# 부러진 자리 —— 들쭉날쭉한 나무결
	var bp := base + _shake_off() + Vector2(0, -brk)
	draw_colored_polygon(PackedVector2Array([bp + Vector2(-3.5 * u, 0), bp + Vector2(-1.5 * u, -6 * u), bp + Vector2(0.5 * u, -2 * u), bp + Vector2(2.5 * u, -8 * u), bp + Vector2(3.5 * u, 0)]), Color("#9a7448"))
	# 윗동 + 천 —— 꺾인 곳을 축으로 오른쪽으로 쓰러지며 축이 땅으로 내려온다
	draw_set_transform(_shake_off(), 0.0, Vector2.ONE)
	_flag_part(pivot + Vector2(0, brk).rotated(ang), ang, brk, L, L, true, a, clampf(f * 1.3, 0.0, 1.0))
	# 흙먼지
	if t >= snap + 0.5 and t < snap + 1.4:
		var d := clampf((t - snap - 0.5) / 0.9, 0.0, 1.0)
		for i in 7:
			var dx := (float(i) - 3.0) * 14.0 * u * (0.4 + d)
			draw_circle(base + Vector2(L * 0.55 + dx, -4.0 * u - d * 10.0 * u * (1 + i % 3)), (6.0 + i % 3 * 3.0) * u * (0.5 + d), Color(DB.PAL.bamboo_dim, 0.35 * (1.0 - d)))


## 승리 깃발 —— 아래에서 솟아올라 선다
func _draw_flag_win(base: Vector2) -> void:
	var f := clampf((t - 0.3) / 1.0, 0.0, 1.0)
	if f <= 0.0:
		return
	var L := _stage_h() * 0.52
	var rise := (1.0 - _ease_out(f)) * L * 0.9
	var a := clampf(f * 3.0, 0.0, 1.0)
	# 땅 위로 올라온 만큼만 보인다 (깃대 아랫부분은 땅에 박혀 있다)
	_flag_part(base + Vector2(0, rise), sin(t * 2.0) * 0.015, rise, L, L, true, a, 0.0)


## 금빛 햇살 (승리)
func _draw_rays(c: Vector2, a: float) -> void:
	if a <= 0.0:
		return
	var R := size.x * 0.75
	for i in 16:
		var ang := float(i) / 16.0 * TAU + t * 0.15
		var p1 := c + Vector2.from_angle(ang - 0.07) * R
		var p2 := c + Vector2.from_angle(ang + 0.07) * R
		draw_colored_polygon(PackedVector2Array([c, p1, p2]), Color(GOLD, 0.10 * a))
	draw_circle(c, 70.0 * _u, Color(GOLD, 0.10 * a))


## 처형 —— 군주 초상이 들어오고, 칼 그림자가 내리쳐 붉은 금이 그어지고, 초상이 잿빛으로 가라앉아 사라진다 (피 · 상처 묘사 없음)
func _draw_execution(c: Vector2) -> void:
	var u := _u
	if t < 0.45 or t > 2.6:
		return
	var a := clampf((t - 0.45) / 0.35, 0.0, 1.0) * (1.0 - clampf((t - 2.25) / 0.35, 0.0, 1.0))
	var pw := 128.0 * u
	var ph := pw * 1.3
	var sink := clampf((t - 1.75) / 0.6, 0.0, 1.0)
	var box := Rect2(c - Vector2(pw, ph) / 2.0 + Vector2(0, sink * sink * 26.0 * u), Vector2(pw, ph))
	draw_rect(Rect2(box.position + Vector2(5, 6) * u, box.size), Color(0, 0, 0, 0.5 * a))
	var gray := clampf((t - 1.7) / 0.3, 0.0, 1.0)
	var mod := Color(1, 1, 1, a).lerp(Color(0.42, 0.40, 0.40, a), gray)
	if _tex != null:
		draw_texture_rect_region(_tex, box, _src, mod)
	else:
		draw_rect(box, Color(DB.PAL.ink3, a))
	draw_rect(box, Color(DB.PAL.gold.lerp(Color(0.4, 0.4, 0.4), gray), a), false, 2.0 * u)
	# 이름 판
	var nm := str(info.get("name", "나"))
	var fs := int(15.0 * u)
	var f := DB.title_font(fs)
	draw_string_outline(f, Vector2(box.position.x, box.end.y + 20.0 * u), "군주 " + nm, HORIZONTAL_ALIGNMENT_CENTER, pw, fs, int(4.0 * u), Color(0, 0, 0, 0.8 * a))
	draw_string(f, Vector2(box.position.x, box.end.y + 20.0 * u), "군주 " + nm, HORIZONTAL_ALIGNMENT_CENTER, pw, fs, Color(DB.PAL.paper, a))
	# 칼 그림자 —— 화면 오른쪽 위 축에서 크게 휘둘러 내려온다 (1.40 ~ 1.70)
	var sw := clampf((t - 1.40) / 0.30, 0.0, 1.0)
	if t >= 1.15 and t < 1.95:
		var pre := clampf((t - 1.15) / 0.25, 0.0, 1.0)      # 칼이 치켜들린 그림자가 먼저 드리운다
		var fade := 1.0 - clampf((t - 1.75) / 0.2, 0.0, 1.0)
		var piv := Vector2(size.x * 1.02, c.y - ph * 1.25)
		var ang := lerpf(1.95, 2.75, _ease_in(sw))      # 아래-왼쪽으로 쓸어내림
		var dir := Vector2.from_angle(ang)
		var nrm := Vector2(-dir.y, dir.x)
		var Lb := size.x * 1.15
		var bw := 20.0 * u
		var p0 := piv + dir * Lb * 0.30
		var blade := PackedVector2Array([p0 + nrm * bw, p0 + dir * Lb * 0.66 + nrm * bw * 0.8, p0 + dir * Lb * 0.76, p0 + dir * Lb * 0.66 - nrm * bw * 0.4, p0 - nrm * bw * 0.4])
		draw_colored_polygon(blade, Color(0, 0, 0, 0.8 * pre * fade))
		draw_polyline(blade + PackedVector2Array([blade[0]]), Color(0.75, 0.78, 0.88, 0.45 * pre * fade), 1.5 * u, true)
		draw_line(p0 + nrm * bw, p0 + dir * Lb * 0.66 + nrm * bw * 0.8, Color(0.9, 0.92, 1.0, 0.6 * pre * fade), 2.5 * u, true)
		if sw > 0.0 and sw < 1.0:      # 휘두르는 자취
			for j in 3:
				var d2 := Vector2.from_angle(ang - 0.06 * (j + 1))
				draw_line(piv + d2 * Lb * 0.35, piv + d2 * Lb * 0.95, Color(1, 1, 1, 0.12 * (3 - j) * fade), 3.0 * u, true)
		# 손잡이 그림자
		draw_line(piv + dir * Lb * 0.12, p0, Color(0, 0, 0, 0.5 * pre * fade), 9.0 * u, true)
	# 붉은 칼금 (초상을 비스듬히 가로지른다) —— 내리친 순간부터 남았다가 초상과 함께 사라진다
	if t >= 1.62:
		var g := clampf((t - 1.62) / 0.1, 0.0, 1.0)
		var q0 := box.position + Vector2(box.size.x * 0.92, box.size.y * 0.10)
		var q1 := box.position + Vector2(box.size.x * 0.08, box.size.y * 0.90)
		var qq := q0.lerp(q1, g)
		draw_line(q0, qq, Color(1, 1, 1, 0.9 * a), 5.0 * u, true)
		draw_line(q0, qq, Color(RED, 0.95 * a), 2.5 * u, true)


# ───────── 요약 (최종 순위 · 버틴 날 · 전적 · 플레이 시간 · 핵심 장수 · 버튼) ─────────

static func time_text(sec: int) -> String:
	if sec <= 0:
		return "—"
	if sec >= 3600:
		return "%d시간 %d분" % [sec / 3600, (sec % 3600) / 60]
	return "%d분 %02d초" % [sec / 60, sec % 60]


static func rank_text(r) -> String:
	if r is String:
		return r if r.ends_with("위") else r + "위"
	return "%d위" % int(r) if int(r) > 0 else "—"


func _build_summary() -> void:
	var H := _stage_h()
	var pad := 16.0
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.flat(Color("#141a2b", 0.96), Color(GOLD if _mode == "win" else DB.PAL.bamboo_dim, 0.6), 1, 12, 14))
	p.position = Vector2(pad, H + 96.0 * _u)
	p.size = Vector2(size.x - pad * 2.0, size.y - p.position.y - pad)
	p.custom_minimum_size = p.size
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 6)
	for kv in [[rank_text(info.get("rank", 0)), "최종 순위"], ["%d일" % int(info.get("days", 0)), "버틴 날"],
			["%d승 %d패" % [int(info.get("w", 0)), int(info.get("l", 0))], "전적"], [time_text(int(info.get("playtime", 0))), "플레이 시간"]]:
		var s := UI.vbox(0)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vl := UI.lbl(str(kv[0]), 19, GOLD if _mode == "win" else DB.PAL.paper, true)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.add_child(vl)
		var ll := UI.lbl(str(kv[1]), 12, DB.PAL.bamboo_dim)
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.add_child(ll)
		stats.add_child(s)
	v.add_child(stats)
	v.add_child(UI.hair())
	v.add_child(UI.lbl("핵심 장수", 14, DB.PAL.bamboo, true))
	var deck: Array = info.get("deck", [])
	if deck.is_empty():
		v.add_child(UI.hint("편성된 장수가 없었다"))
	else:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.custom_minimum_size = Vector2(0, 104)
		var row := UI.hbox(6)
		sc.add_child(row)
		for k in deck:
			if not DB.C.has(str(k)):
				continue
			if gs != null and gs.has_method("mtile"):
				row.add_child(gs.mtile(str(k), -1, func(_id): pass))
			else:
				row.add_child(UI.lbl(str(DB.C[k].name), 14, DB.tier_color(str(k))))
		v.add_child(sc)
	var msg := str(info.get("msg", ""))
	if msg != "":
		var ml := UI.lbl(msg, 13, DB.PAL.bamboo_dim)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(ml)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	if bool(info.get("watch", false)):
		v.add_child(UI.btn("남은 판 관전하기", func(): watch.emit(), "ghost", 44))
	var bh := UI.hbox(8)
	var b1 := UI.btn("처음으로", func(): home.emit(), "ghost", 54)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b2 := UI.btn(str(info.get("again_text", "다시 하기")), func(): again.emit(), "pri", 54)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(b1)
	bh.add_child(b2)
	v.add_child(bh)
	_summary = p
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.35)
