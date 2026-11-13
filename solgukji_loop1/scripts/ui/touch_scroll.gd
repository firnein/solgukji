extends Node
## 손가락 스크롤 (autoload TouchScroll) —— 버튼·카드·패널 위에서 끌어도 목록이 스크롤된다.
##
## Godot 의 ScrollContainer 는 손가락이 처음 닿은 컨트롤이 입력을 삼키면(버튼·패널은 기본이 STOP)
## 끌기를 받지 못한다. 그래서 화면 전체 입력을 먼저(_input) 본다:
##   누름 → 그 자리의 스크롤 상자 후보를 기억 (누름 자체는 그대로 흘려 보내 버튼이 눌린 모양은 난다)
##   SLOP 넘게 움직임 → 방향(가로·세로)에 맞는 상자를 고르고, 밑의 버튼 누름은 화면 밖 '떼기'로 취소
##   그 뒤 움직임은 삼켜서 직접 스크롤 · 떼면 관성
## 스크롤 상자는 'touch_scroll' 그룹, 그 위를 덮는 막(시트 가림막·전투 화면 등)은 'touch_block' 그룹.
## UI.scroll() 로 만들면 알아서 들어간다. RichTextLabel 도 그룹에 넣으면 같은 식으로 끈다.

const SLOP := 10.0          # 이만큼 움직여야 스크롤로 본다 (그 전에는 탭)
const FRICTION := 4.0       # 관성 감쇠 (1/초)
const OFF := Vector2(-99999, -99999)

var _cands: Array = []      # 누른 자리의 스크롤 후보 (위에 그려지는 것부터)
var _press := Vector2.INF
var _target: Control = null
var _axis := Vector2.ZERO   # (1,0) 가로 · (0,1) 세로
var _vel := 0.0
var _last_t := 0
var _fling: Control = null
var _fling_axis := Vector2.ZERO
var _fling_v := 0.0
var _acc := 0.0             # 소수점 이하 스크롤 누적 (정수 스크롤)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index != MOUSE_BUTTON_LEFT:
			return
		if e.position.x < -1000.0:
			return                      # 우리가 넣은 취소용 떼기 (화면 배율이 곱해져 들어온다)
		if e.pressed:
			_fling = null
			_target = null
			_press = e.position
			_cands = _find(e.position)
			_vel = 0.0
			_acc = 0.0
			_last_t = Time.get_ticks_msec()
		else:
			if _target != null:
				get_viewport().set_input_as_handled()
				if Time.get_ticks_msec() - _last_t > 90:
					_vel = 0.0              # 멈췄다가 뗐다 —— 관성 없음
				if absf(_vel) > 60.0:
					_fling = _target
					_fling_axis = _axis
					_fling_v = clampf(_vel, -6000.0, 6000.0)
			_target = null
			_press = Vector2.INF
			_cands = []
	elif e is InputEventMouseMotion:
		if e.position.x < -1000.0 or _press == Vector2.INF:
			return
		if _target == null:
			if _cands.is_empty() or get_viewport().gui_is_dragging():
				return
			var d: Vector2 = e.position - _press
			if d.length() < SLOP:
				return
			var axis := Vector2(1, 0) if absf(d.x) > absf(d.y) else Vector2(0, 1)
			for c in _cands:
				if is_instance_valid(c) and _can(c, axis):
					_target = c
					_axis = axis
					break
			if _target == null:
				_press = Vector2.INF        # 이 방향으로는 스크롤할 것이 없다 —— 손대지 않는다
				_cands = []
				return
			_cancel_press()
			_vel = 0.0
			_last_t = Time.get_ticks_msec()
			_scroll(_target, _axis, -(d.dot(_axis)) + (SLOP if d.dot(_axis) > 0 else -SLOP))
			get_viewport().set_input_as_handled()
			return
		if _target != null:
			get_viewport().set_input_as_handled()
			if not is_instance_valid(_target):
				_target = null
				return
			var delta: float = -e.relative.dot(_axis)
			_scroll(_target, _axis, delta)
			var now := Time.get_ticks_msec()
			var dt := maxf(0.001, (now - _last_t) / 1000.0)
			_last_t = now
			_vel = lerpf(_vel, delta / dt, 0.5) if dt < 0.1 else delta / dt


func _process(dt: float) -> void:
	if _fling == null:
		return
	if not is_instance_valid(_fling) or not _fling.is_visible_in_tree():
		_fling = null
		return
	var moved := _scroll(_fling, _fling_axis, _fling_v * dt)
	_fling_v *= exp(-FRICTION * dt)
	if absf(_fling_v) < 20.0 or not moved:
		_fling = null


## 눌린 버튼·카드의 누름을 취소한다 —— 손가락이 화면 밖으로 나갔다가 떼어진 것으로 친다
## (버튼은 밖으로 끌려 나간 뒤 떼면 눌리지 않는다)
func _cancel_press() -> void:
	var mv := InputEventMouseMotion.new()
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	mv.position = OFF
	mv.global_position = OFF
	Input.parse_input_event(mv)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = OFF
	up.global_position = OFF
	Input.parse_input_event(up)


## 그 자리의 스크롤 상자들 —— 위에 그려지는 것부터. 막(touch_block)에 가려진 것은 뺀다
func _find(p: Vector2) -> Array:
	var out := []
	var blocks := []
	for b in get_tree().get_nodes_in_group("touch_block"):
		if b is Control and b.is_visible_in_tree() and b.get_global_rect().has_point(p):
			blocks.append(b)
	for c in get_tree().get_nodes_in_group("touch_scroll"):
		if not (c is Control) or not c.is_visible_in_tree() or not c.get_global_rect().has_point(p):
			continue
		var hidden := false
		for b in blocks:
			if b != c and not b.is_ancestor_of(c) and b.is_greater_than(c):
				hidden = true
				break
		if not hidden:
			out.append(c)
	out.sort_custom(func(a, b): return a.is_greater_than(b))
	return out


func _bar(c: Control, axis: Vector2) -> ScrollBar:
	if c is ScrollContainer:
		return c.get_h_scroll_bar() if axis.x > 0 else c.get_v_scroll_bar()
	if c is RichTextLabel and axis.y > 0:
		return c.get_v_scroll_bar()
	return null


func _can(c: Control, axis: Vector2) -> bool:
	if c is ScrollContainer:
		var mode: int = c.horizontal_scroll_mode if axis.x > 0 else c.vertical_scroll_mode
		if mode == ScrollContainer.SCROLL_MODE_DISABLED:
			return false
	var b := _bar(c, axis)
	return b != null and b.max_value - b.page > 0.5


## 스크롤하고, 실제로 움직였는지 돌려준다
func _scroll(c: Control, axis: Vector2, amount: float) -> bool:
	var b := _bar(c, axis)
	if b == null:
		return false
	_acc += amount
	var step := roundf(_acc)
	_acc -= step
	var before := b.value
	b.value = clampf(b.value + step, b.min_value, b.max_value - b.page)
	return b.value != before or step == 0.0


## 스크롤 상자 등록 —— 내장 끌기는 끈다 (둘이 같이 움직이면 튄다)
static func add(c: Control) -> void:
	c.add_to_group("touch_scroll")
	if c is ScrollContainer:
		c.scroll_deadzone = 100000


static func block(c: Control) -> void:
	c.add_to_group("touch_block")
