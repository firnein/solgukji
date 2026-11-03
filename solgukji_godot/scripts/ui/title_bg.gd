class_name TitleBG
extends Control
## 타이틀 배경 (11/3 사용자: 타이틀을 이쁘게) —— 신화 일러스트가 천천히 다가오며(켄 번스) 넘어가고,
## 위아래 먹빛 그라데이션 · 가장자리 어둡게 · 금빛 불씨가 피어오른다. 그림은 얼굴이 있는 위쪽을 기준으로 꽉 채운다.

const HOLD := 6.5          # 한 장을 보여 주는 시간 (초)
const FADE := 1.6          # 다음 그림으로 넘어가는 시간
const ZOOM := 0.07         # 한 장 동안 다가가는 정도
const INK := Color("#0b0f1a")
const ORDER := ["관우", "조조", "여포", "제갈량", "손권", "조운", "장비", "주유", "유비", "사마의", "장료", "손책",
	"하후돈", "장각", "감녕", "곽가", "태사자", "동탁", "하후연", "위연", "순욱"]

var arts: Array[Texture2D] = []
var idx := 0
var t := 0.0
var embers := []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_rng.seed = Time.get_ticks_usec()
	for p in ORDER:
		var tex: Texture2D = DB._load_portrait("res://assets/portraits/%s_신화" % p)
		if tex:
			arts.append(tex)
	idx = _rng.randi() % maxi(1, arts.size())
	for i in 46:
		embers.append(_ember(true))


func _ember(anywhere: bool) -> Dictionary:
	return {"x": _rng.randf(), "y": _rng.randf() if anywhere else 1.05, "v": _rng.randf_range(0.012, 0.04),
		"r": _rng.randf_range(0.8, 2.4), "ph": _rng.randf() * TAU, "w": _rng.randf_range(0.3, 1.2)}


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	t += dt
	if t >= HOLD + FADE:
		t -= HOLD + FADE
		idx = (idx + 1) % maxi(1, arts.size())
	for e in embers:
		e.y -= e.v * dt
		e.ph += dt * e.w * 3.0
		if e.y < -0.05:
			e.merge(_ember(false), true)
	queue_redraw()


func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), INK)
	if not arts.is_empty():
		var a0 := clampf((t - HOLD) / FADE, 0.0, 1.0)
		_art(arts[idx], t / (HOLD + FADE), 1.0)
		if a0 > 0.0:
			_art(arts[(idx + 1) % arts.size()], 0.0, a0)
	# 위 · 아래 먹빛 —— 로고와 버튼이 읽히게
	draw_rect(Rect2(0, 0, sz.x, sz.y * 0.2), INK)      # 그림 맨 위 카드 틀(금선)을 가린다
	_vgrad(0.2, 0.44, INK, Color(INK, 0.0))
	_vgrad(0.5, 0.72, Color(INK, 0.0), Color(INK, 0.86))
	draw_rect(Rect2(0, sz.y * 0.72, sz.x, sz.y * 0.28), Color(INK, 0.86))
	# 양옆 가장자리
	var side := minf(70.0, sz.x * 0.16)
	_hgrad(0.0, side, Color(INK, 0.7), Color(INK, 0.0))
	_hgrad(sz.x - side, sz.x, Color(INK, 0.0), Color(INK, 0.7))
	# 금빛 불씨
	for e in embers:
		var p := Vector2(e.x * sz.x + sin(e.ph) * 6.0, e.y * sz.y)
		var fl := 0.55 + 0.45 * sin(e.ph * 1.7)
		draw_circle(p, e.r * 2.6, Color(1.0, 0.62, 0.22, 0.10 * fl))
		draw_circle(p, e.r, Color(1.0, 0.86, 0.5, 0.75 * fl))


## 그림을 화면에 꽉 (가운데 가로 · 위쪽 기준 세로), u(0~1) 만큼 다가가며
func _art(tex: Texture2D, u: float, alpha: float) -> void:
	var ts := tex.get_size()
	var sz := size
	var sc := maxf(sz.x / ts.x, sz.y / ts.y) * (1.12 + ZOOM * u)      # 1.12 —— 그림 가장자리의 카드 틀을 밖으로
	var dw := ts.x * sc
	var dh := ts.y * sc
	var pos := Vector2((sz.x - dw) / 2.0, sz.y * 0.16 - (dh - sz.y) * 0.04)      # 얼굴이 로고 아래(화면 가운데쯤)에 오게 내린다
	draw_texture_rect(tex, Rect2(pos, Vector2(dw, dh)), false, Color(1, 1, 1, alpha))


func _vgrad(y0: float, y1: float, c0: Color, c1: Color) -> void:
	var w := size.x
	var a := size.y * y0
	var b := size.y * y1
	draw_polygon(PackedVector2Array([Vector2(0, a), Vector2(w, a), Vector2(w, b), Vector2(0, b)]), PackedColorArray([c0, c0, c1, c1]))


func _hgrad(x0: float, x1: float, c0: Color, c1: Color) -> void:
	var h := size.y
	draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, h), Vector2(x0, h)]), PackedColorArray([c0, c1, c1, c0]))


## 붉은 낙관 —— 로고 옆 「天下」
class Seal extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(38, 38)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		draw_set_transform(c, deg_to_rad(-6.0), Vector2.ONE)
		var r := Rect2(-size / 2.0, size)
		draw_rect(r, Color("#b5322a"))
		draw_rect(r.grow(-2.5), Color("#f4e6d0"), false, 1.2)
		var f := DB.font_display
		draw_string(f, Vector2(-size.x / 2.0, -2), "天", HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color("#f4e6d0"))
		draw_string(f, Vector2(-size.x / 2.0, 14), "下", HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color("#f4e6d0"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
