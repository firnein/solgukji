class_name ForgeFanfare
extends Control
## 히든(불멸) 이상 조합 완성 연출 (11/3 사용자 —— 원랜디 히든 · 신화 완성처럼).
## 어둠 → 등급색 빛줄기가 돌며 퍼지고 → 초상이 크게 다가오며 내려앉고 → 등급 글 · 이름이 찍힌다 → 금가루가 흩날린다.
## 화면 아무 곳이나 누르면 닫힌다 (4.2초 뒤 저절로). 배경 그림 assets/fx/forge_<등급>.png 가 있으면 빛줄기 뒤에 깐다
## (프롬프트 prompts/조합연출/). 신화는 고유기 컷인 그림(<인물>_신화.png)이 있으면 그것을 쓴다.

const DUR := 4.2
const RAYS := 18

var k := ""
var t := 0.0
var tier := 7
var col := Color.WHITE
var art: Texture2D = null
var art_used := Rect2()
var bg: Texture2D = null
var sparks := []             # [위치, 속도, 크기, 수명]
var _rng := RandomNumberGenerator.new()


static func play(host: Control, card: String) -> void:
	var f := ForgeFanfare.new()
	f.k = card
	host.add_child(f)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	tier = DB.C[k].tier
	col = DB.tier_color(k)
	art = DB.myth_art(k) if tier >= 8 else null
	if art == null:
		art = DB.portrait(k)
		art_used = DB.portrait_used(k)
	var bp := "res://assets/fx/forge_%d.png" % tier
	if ResourceLoader.exists(bp):
		bg = load(bp)
	_rng.seed = hash(k)
	Sfx.play("ult")
	if Settings.haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(60 if tier >= 8 else 35)


func _gui_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed and t > 0.6:
		accept_event()
		_close()


var _closing := false
func _close() -> void:
	if _closing:
		return
	_closing = true                 # 11/4 점검: 예전엔 t >= DUR 이면 돌아가 버려 저절로도, 눌러도 닫히지 않았다 (화면 입력이 영구히 막힘)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	t = maxf(t, DUR)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)


func _process(dt: float) -> void:
	t += dt
	global_position = Vector2.ZERO          # 부모(GameScreen)가 크기를 갖지 않아 앵커가 듣지 않는다 —— 화면 전체로 직접
	size = get_viewport_rect().size
	if t >= DUR:
		_close()
	# 금가루 —— 초상이 내려앉은 뒤부터 위로 흩날린다
	if t > 0.9 and t < DUR - 0.6:
		for i in (3 if tier >= 8 else 2):
			var c := size * Vector2(0.5, 0.48)
			sparks.append([c + Vector2(_rng.randf_range(-160, 160), _rng.randf_range(40, 200)),
				Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-170, -60)), _rng.randf_range(1.5, 3.8), _rng.randf_range(0.8, 1.8)])
	for s in sparks:
		s[0] += s[1] * dt
		s[1].y += 25 * dt
		s[3] -= dt
	sparks = sparks.filter(func(s): return s[3] > 0)
	queue_redraw()


func _ease_out(x: float) -> float:
	x = clampf(x, 0, 1)
	return 1.0 - pow(1.0 - x, 3)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var c := Vector2(w * 0.5, h * 0.42)
	# ① 어둠
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.04, 0.88 * _ease_out(t / 0.35)))
	if bg:
		var a := _ease_out((t - 0.2) / 0.6) * 0.75
		var ts := bg.get_size()
		var sc := maxf(w / ts.x, h / ts.y)
		draw_texture_rect(bg, Rect2(c - ts * sc / 2, ts * sc), false, Color(1, 1, 1, a))
	# ② 빛줄기 —— 등급색, 천천히 돈다. 신화는 두 겹
	var ray_a := _ease_out((t - 0.15) / 0.5)
	var R := maxf(w, h) * 1.1
	for layer in (2 if tier >= 8 else 1):
		var rot := t * (0.35 if layer == 0 else -0.22)
		for i in RAYS:
			var a0 := TAU * i / RAYS + rot
			var hw := 0.06 if layer == 0 else 0.035
			var pts := PackedVector2Array([c, c + Vector2.from_angle(a0 - hw) * R, c + Vector2.from_angle(a0 + hw) * R])
			var cc := Color(col.lightened(0.2 * layer), 0.16 * ray_a)
			draw_polygon(pts, PackedColorArray([Color(cc, 0.26 * ray_a), Color(cc, 0.0), Color(cc, 0.0)]))
	# 가운데 후광
	for i in 6:
		draw_circle(c, (220.0 - i * 30) * _ease_out((t - 0.3) / 0.5), Color(col, 0.05 * ray_a))
	# ③ 초상 —— 크게(1.6배)에서 1배로 내려앉고, 내려앉는 순간 흰 번쩍임
	var land := _ease_out((t - 0.35) / 0.5)
	if art and t > 0.35:
		var box := Vector2(minf(w * 0.78, 330), minf(h * 0.5, 420))
		var sc := lerpf(1.6, 1.0, land)
		var src := art_used if art_used.has_area() else Rect2(Vector2.ZERO, art.get_size())
		var fit := minf(box.x / src.size.x, box.y / src.size.y) * sc
		var ds := src.size * fit
		draw_texture_rect_region(art, Rect2(c - ds / 2, ds), src, Color(1, 1, 1, land))
	var flash := 1.0 - clampf((t - 0.85) / 0.35, 0, 1) if t > 0.85 else 0.0
	if flash > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.55 * flash))
	# ④ 글 —— 「불멸 완성」 · 「신화 강림」 + 이름
	if t > 0.9:
		var ta := _ease_out((t - 0.9) / 0.3)
		var head := "신 화 강 림" if tier >= 8 else "불 멸 완 성"
		var hf: Font = DB.tier_font(tier)
		var hs := 30 if tier >= 8 else 26
		var hy := h * 0.42 + minf(h * 0.25, 210) + 46
		var ty := hy + 44
		var off := (1.0 - ta) * 18
		draw_string_outline(hf, Vector2(0, hy + off), head, HORIZONTAL_ALIGNMENT_CENTER, w, hs, 6, Color(0, 0, 0, 0.8 * ta))
		draw_string(hf, Vector2(0, hy + off), head, HORIZONTAL_ALIGNMENT_CENTER, w, hs, Color(col.lightened(0.25), ta))
		var nm: String = DB.C[k].name
		draw_string_outline(DB.font_display, Vector2(0, ty + off), nm, HORIZONTAL_ALIGNMENT_CENTER, w, 34, 7, Color(0, 0, 0, 0.85 * ta))
		draw_string(DB.font_display, Vector2(0, ty + off), nm, HORIZONTAL_ALIGNMENT_CENTER, w, 34, Color(1, 0.97, 0.9, ta))
		if t > 1.6:
			var la := _ease_out((t - 1.6) / 0.4) * 0.7
			draw_string(DB.font_body, Vector2(0, h - 60), "누르면 닫기", HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(1, 1, 1, la))
	# ⑤ 금가루
	for s in sparks:
		draw_circle(s[0], s[2], Color(col.lightened(0.4), clampf(s[3], 0, 1)))
