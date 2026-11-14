class_name Coach
extends Control
## 첫 판 안내 말풍선 (11/9) —— 탭바 바로 위에 뜨는 한 장, 가리키는 탭을 향한 작은 화살표.
## 막지 않는다(바깥 터치는 그대로 아래로). 단계 글 · 다음 · 건너뛰기만. 색은 먹 + 종이 + 금 1px (UI 규칙 ㊽).

signal next
signal skip

var _panel: PanelContainer
var _arrow: Control
var aim := Vector2.ZERO      # 가리키는 탭 가운데 x · 탭바 윗변 y (전역)
var _w := 340.0
var below := false      # 11/14 true 면 화면 안 행동 버튼(aim = 그 버튼 아래 가운데) 바로 아래에 뜨고 꼬리가 위를 가리킨다


## head 는 작은 머리글(금), body 는 본문. last 면 [다음] 대신 [확인], skippable 이면 [건너뛰기]
static func make(head: String, body: String, aim_g: Vector2, last: bool, skippable: bool, width: float, under := false) -> Coach:
	var c := Coach.new()
	c.aim = aim_g
	c.below = under
	c._w = width
	c._build(head, body, last, skippable)
	return c


func _build(head: String, body: String, last: bool, skippable: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.flat(DB.PAL.ink2, Color(DB.PAL.gold, 0.85), 1, UI.R, 12))
	var v := UI.vbox(UI.SP_S)
	_panel.add_child(v)
	v.add_child(UI.lbl(head, UI.FS_BODY, DB.PAL.gold, true))
	var bl := UI.lbl(body, UI.FS_BODY, DB.PAL.paper)
	UI.wrap_text(bl)
	bl.custom_minimum_size.x = _w - 26.0
	v.add_child(bl)
	var row := UI.hbox(UI.SP_S)
	if skippable:
		var sk := UI.btn("건너뛰기", func(): skip.emit(), "ghost", UI.BH_S)
		sk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sk)
	var nb := UI.btn("확인" if last else "다음", func(): next.emit(), "pri", UI.BH_S)
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nb)
	v.add_child(row)
	add_child(_panel)
	_arrow = Control.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(func():
		var tip := -10.0 if below else 10.0
		var pts := PackedVector2Array([Vector2(-9, 0), Vector2(0, tip), Vector2(9, 0)])
		_arrow.draw_colored_polygon(pts, DB.PAL.ink2)
		_arrow.draw_polyline(pts, Color(DB.PAL.gold, 0.85), 1.0))
	add_child(_arrow)
	_panel.resized.connect(_place)
	_panel.reset_size()
	_place.call_deferred()


## 탭바 위, 가리키는 탭 위로 —— 가로는 화면 안으로 눌러 담는다
func _place() -> void:
	if _panel == null or not is_inside_tree():
		return
	var h := _panel.get_combined_minimum_size().y
	var org := global_position
	var sw := get_parent_area_size().x
	var x := clampf(aim.x - org.x - _w / 2.0, 12.0, maxf(12.0, sw - _w - 12.0))
	var y := (aim.y - org.y + 14.0) if below else (aim.y - org.y - 14.0 - h)
	_panel.size = Vector2(_w, h)
	_panel.position = Vector2(x, y)
	_arrow.position = Vector2(clampf(aim.x - org.x, x + 16.0, x + _w - 16.0), (y + 1.0) if below else (y + h - 1.0))
	_arrow.queue_redraw()
