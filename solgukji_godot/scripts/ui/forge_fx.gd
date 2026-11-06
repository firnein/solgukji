class_name ForgeFx
extends Control
## 조합 완성 연출 (11/6 사용자 #17: 선택권 획득과 다른 모양 —— 선택권은 '한 장이 날아옴', 조합은 '여럿이 하나로').
##  ▸ play_one : 재료 카드들이 가운데로 모여 겹치고 → 빛 → 결과 카드가 뒤집혀 나온다 (약 1.1초)
##  ▸ play_chain : 모두 조합 —— 결과 카드 묶음이 셔플되듯 섞이고, 한 장씩 위로 쌓이며 마지막(가장 높은 등급)이 크게 공개 (2초 이내)
## 어디든 누르면 바로 끝난다. 불멸 이상은 ForgeFanfare 가 따로 맡는다 (이 연출은 그 앞에 짧게).
## 등급별 무게: 고급 · 희귀는 빛만, 전설 이상은 금빛 후광

const CARD := Vector2(96, 136)
var _tw: Tween
var _done := false
var _on_done := Callable()
var _glow := 0.0
var _glow_col := Color.WHITE


static func play_one(host: Control, out: String, mats: Array, then := Callable()) -> ForgeFx:
	var f := ForgeFx.new()
	f._on_done = then
	host.add_child(f)
	f._one(out, mats)
	return f


static func play_chain(host: Control, made: Array, then := Callable()) -> ForgeFx:
	var f := ForgeFx.new()
	f._on_done = then
	host.add_child(f)
	f._chain(made)
	return f


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40


func _process(_dt: float) -> void:
	global_position = Vector2.ZERO
	size = get_viewport_rect().size
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
		accept_event()
		_finish()


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.02, 0.04, 0.55 * clampf(_glow * 3.0, 0.0, 1.0)))
	if _glow > 0.01:
		var c := vs * Vector2(0.5, 0.42)
		for i in 5:
			draw_circle(c, (90.0 + i * 36.0) * _glow, Color(_glow_col, 0.09 * _glow))


func _card(k: String, p: Vector2, sc := 1.0) -> CardView:
	var cv := CardView.new().setup(k, CARD)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.size = CARD
	cv.pivot_offset = CARD / 2.0
	cv.position = p - CARD / 2.0
	cv.scale = Vector2.ONE * sc
	add_child(cv)
	return cv


func _finish() -> void:
	if _done:
		return
	_done = true
	if _tw:
		_tw.kill()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.15)
	t.tween_callback(func():
		if _on_done.is_valid():
			_on_done.call()
		queue_free())


## 재료가 모여 하나가 된다
func _one(out: String, mats: Array) -> void:
	var vs := get_viewport_rect().size
	var c := vs * Vector2(0.5, 0.42)
	var tier: int = DB.C[out].tier
	_glow_col = DB.tier_color(out)
	var cards := []
	var n := mats.size()
	for i in n:
		var ang := -PI / 2.0 + TAU * i / maxf(1.0, n)
		var p := c + Vector2.from_angle(ang) * 150.0
		cards.append(_card(str(mats[i]), p, 0.55))
	Sfx.play("forge")
	_tw = create_tween()
	_tw.set_parallel(true)
	for cv in cards:
		_tw.tween_property(cv, "position", c - CARD / 2.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tw.tween_property(cv, "scale", Vector2(0.25, 0.25), 0.32).set_ease(Tween.EASE_IN)
		_tw.tween_property(cv, "modulate:a", 0.0, 0.1).set_delay(0.3)
	_tw.tween_property(self, "_glow", 1.0, 0.18).set_delay(0.28)
	_tw.set_parallel(false)
	_tw.tween_callback(func():
		for cv in cards:
			cv.queue_free()
		var res := _card(out, c, 0.2)
		res.scale = Vector2(0.0, 1.0)      # 뒤집히듯
		var t2 := create_tween()
		t2.tween_property(res, "scale", Vector2(1.18, 1.18), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t2.tween_property(res, "scale", Vector2.ONE, 0.1)
		if tier >= 5:
			Sfx.play("gain", 2.0))
	_tw.tween_property(self, "_glow", 0.0, 0.5).set_delay(0.3)
	_tw.tween_interval(0.25)
	_tw.tween_callback(_finish)


## 모두 조합 —— 셔플 뒤 한 장씩, 마지막은 크게
func _chain(made: Array) -> void:
	var vs := get_viewport_rect().size
	var c := vs * Vector2(0.5, 0.42)
	var top: String = made[made.size() - 1]
	_glow_col = DB.tier_color(top)
	var cards := []
	for i in made.size():
		var cv := _card(str(made[i]), c + Vector2(0, 160.0), 0.75)
		cv.rotation = randf_range(-0.18, 0.18)
		cards.append(cv)
	Sfx.play("draw")
	_tw = create_tween()
	# ① 셔플 —— 0.45초 동안 좌우로 흩어졌다 모인다
	_tw.set_parallel(true)
	for i in cards.size():
		var cv: CardView = cards[i]
		var off := Vector2(randf_range(-110, 110), randf_range(-30, 30))
		_tw.tween_property(cv, "position", c + Vector2(0, 160.0) + off - CARD / 2.0, 0.22).set_trans(Tween.TRANS_SINE)
		_tw.tween_property(cv, "position", c + Vector2(0, 160.0) - CARD / 2.0, 0.22).set_delay(0.22).set_trans(Tween.TRANS_SINE)
	_tw.set_parallel(false)
	# ② 한 장씩 위로 —— 장수가 많을수록 빠르게 (전체 2초 안)
	var per := clampf(1.1 / maxf(1.0, cards.size()), 0.12, 0.3)
	for i in cards.size():
		var cv: CardView = cards[i]
		var last: bool = i == cards.size() - 1
		var dst := c + Vector2(-70.0 + 140.0 * i / maxf(1.0, cards.size() - 1), -40.0) if not last else c
		_tw.tween_callback(func():
			Sfx.play("gain", 0.0 if not last else 3.0)
			var t2 := create_tween()
			t2.set_parallel(true)
			t2.tween_property(cv, "position", dst - CARD / 2.0, per * 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t2.tween_property(cv, "rotation", 0.0, per * 0.9)
			t2.tween_property(cv, "scale", Vector2.ONE * (0.72 if not last else 1.25), per * 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if last:
				t2.tween_property(self, "_glow", 1.0, 0.2)
				for o in cards:
					if o != cv:
						t2.tween_property(o, "modulate:a", 0.45, 0.2))
		_tw.tween_interval(per)
	_tw.tween_property(self, "_glow", 0.0, 0.45).set_delay(0.2)
	_tw.tween_interval(0.2)
	_tw.tween_callback(_finish)
