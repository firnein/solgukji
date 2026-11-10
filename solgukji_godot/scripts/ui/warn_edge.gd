extends Control
## 남은 시간 경고 (11/10 사용자) —— 온라인 시간제 단계에서 5초부터 화면 가장자리가 붉게 맥동한다 (안쪽은 투명, 입력은 막지 않는다).
## Online 이 매 프레임 phase(0 = 막 비프가 울린 순간 → 1 = 다음 비프 직전)를 넘겨 준다. 1초 주기: 비프와 함께 확 붉어지고 다음 초까지 사그라든다.
## class_name 은 만들지 않는다 (낡은 .godot 캐시) —— Online 이 preload 로 쓴다.

const RED := Color("#e02a1c")

var phase := 0.0          # 0..1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 40
	visible = false


func show_phase(p: float) -> void:
	phase = p
	if not visible:
		visible = true
	queue_redraw()


func hide_now() -> void:
	if visible:
		visible = false


func _process(_dt: float) -> void:
	if visible:
		global_position = Vector2.ZERO          # 부모(GameScreen)가 크기를 갖지 않아 앵커가 듣지 않는다 (ForgeFanfare 와 같다)
		size = get_viewport_rect().size


func _draw() -> void:
	var w := size.x
	var h := size.y
	var a := 0.14 + 0.52 * pow(1.0 - phase, 2.0)      # 비프 순간 0.66 → 다음 비프 직전 0.14
	var d := minf(w, h) * 0.22                        # 안쪽으로 번지는 깊이
	var s := Color(RED, a)
	var z := Color(RED, 0.0)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, d), Vector2(0, d)]), PackedColorArray([s, s, z, z]))
	draw_polygon(PackedVector2Array([Vector2(0, h), Vector2(w, h), Vector2(w, h - d), Vector2(0, h - d)]), PackedColorArray([s, s, z, z]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(d, 0), Vector2(d, h), Vector2(0, h)]), PackedColorArray([s, z, z, s]))
	draw_polygon(PackedVector2Array([Vector2(w, 0), Vector2(w - d, 0), Vector2(w - d, h), Vector2(w, h)]), PackedColorArray([s, z, z, s]))
