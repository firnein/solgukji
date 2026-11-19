class_name TouchButton
extends Button
## 누르는 범위만 넓힌 버튼 (11/14 UI 감사 #6) —— 보이는 크기는 그대로, 손가락이 닿는 범위는 최소 UI.HIT(48 논리).
## 모자란 만큼 위아래(옆) 바깥으로 늘린다. 형제 버튼과 겹치면 나중에 그려지는(위에 있는) 쪽이 이긴다 —— 붙어 있는 줄에서는 hit_dir 로 한쪽만.

var hit := Vector2(UI.HIT, UI.HIT)
var hit_dir := 0      # 0 위아래 고르게 · -1 위로만 · 1 아래로만


func _has_point(p: Vector2) -> bool:
	var gx := maxf(0.0, hit.x - size.x) * 0.5
	var gy := maxf(0.0, hit.y - size.y)
	var top := gy * 0.5 if hit_dir == 0 else (gy if hit_dir < 0 else 0.0)
	return Rect2(Vector2.ZERO, size).grow_individual(gx, top, gx, gy - top).has_point(p)

var press_fx := true      # 눌림 반응 —— 누르는 동안 살짝 작아졌다가 떼면 돌아온다 (11/14 UI 다듬기 4단계, 모바일 공통 손맛)
var _tw: Tween


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE      # 11/20 조작: 누른 버튼에 포커스가 남아 스페이스 · 엔터가 그 버튼을 다시 눌렀다 (전투 일시정지 대신)
	button_down.connect(_press.bind(true))
	button_up.connect(_press.bind(false))
	if OS.has_feature("mobile"):
		_no_sticky_hover()


## 휴대폰에서는 터치가 마우스를 흉내 내 손을 뗀 뒤에도 마지막 버튼이 '올림(hover)' 색으로 남는다 ——
## 올림 모양을 평소 모양과 같게 (눌림 · 고름 표시는 그대로). 만든 뒤 평소 모양을 바꾸는 버튼은 이 함수를 다시 부른다
func _no_sticky_hover() -> void:
	add_theme_stylebox_override("hover", get_theme_stylebox("normal"))
	add_theme_stylebox_override("hover_pressed", get_theme_stylebox("pressed"))
	add_theme_color_override("font_hover_color", get_theme_color("font_color"))
	add_theme_color_override("font_hover_pressed_color", get_theme_color("font_pressed_color"))
	add_theme_color_override("icon_hover_color", get_theme_color("icon_normal_color"))


func _press(down: bool) -> void:
	if not press_fx or (down and disabled):
		return
	pivot_offset = size * 0.5
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	if down:
		_tw.tween_property(self, "scale", Vector2.ONE * 0.95, 0.05)
	else:
		_tw.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
