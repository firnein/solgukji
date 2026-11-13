class_name ItemArt
extends RefCounted
## 아이템 썸네일 —— assets/items/<아이템 이름>.png 이 있으면 그 그림을, 없으면 물건 모양을 선으로 그린다 (11/2 사용자: 유니크 썸네일).
## 모양은 SHAPE 표 (아이템 id → 모양). 표에 없으면 병종으로 고른다.

const SHAPE := {
	"i72": "glaive", "i73": "snake", "i74": "sword", "i75": "dao", "i76": "halberd", "i77": "flag",
	"i78": "tally", "i79": "bow", "i80": "twin", "i81": "sword", "i82": "fan", "i83": "scroll",
	"i84": "seal", "i85": "twin_sword", "i86": "seal", "i87": "book", "i88": "book", "i89": "dao",
	"i90": "zither", "i91": "pin", "i92": "sail", "i93": "robe", "i94": "map", "i95": "seal",
	"i96": "mirror", "i97": "book", "i98": "map",
}
const BY_TAG := {"창병": "glaive", "기병": "halberd", "궁병": "bow", "책사": "fan", "유생": "scroll",
	"술사": "book", "모사": "scroll", "도적": "dao"}

static var _tex := {}


static func tex(id: String) -> Texture2D:
	if not _tex.has(id):
		var p := "res://assets/items/%s.png" % DB.IT[id].name
		_tex[id] = load(p) if ResourceLoader.exists(p) else null
	return _tex[id]


## 사각 칸에 썸네일 —— 등급색 테두리 · 어두운 바탕 · 가운데 빛
static func draw_item(ci: CanvasItem, r: Rect2, id: String) -> void:
	var it: Dictionary = DB.IT[id]
	var col := UI.item_col(id)
	var sb := StyleBoxFlat.new()
	sb.bg_color = DB.PAL.ink
	sb.border_color = col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	ci.draw_style_box(sb, r)
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var t := tex(id)
	if t:
		var ir := r.grow(-3)
		ci.draw_texture_rect(t, ir, false)
		return
	for i in 6:
		ci.draw_circle(c, s * (0.46 - i * 0.06), Color(col, 0.05 + i * 0.025))
	var shape: String = SHAPE.get(id, BY_TAG.get(it.tag, "glaive"))
	_shape(ci, shape, c, s * 0.8, col.lightened(0.35), col)


static func _shape(ci: CanvasItem, shape: String, c: Vector2, s: float, hi: Color, lo: Color) -> void:
	var u := s / 24.0
	var w := maxf(1.5, 1.8 * u)
	var P := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * u
	match shape:
		"glaive":       # 언월도 —— 긴 자루 + 반달 날
			ci.draw_line(P.call(-8, 11), P.call(5, -6), lo.darkened(0.2), w * 1.2)
			ci.draw_colored_polygon(PackedVector2Array([P.call(4, -5), P.call(10, -12), P.call(11, -5), P.call(7, -1)]), hi)
			ci.draw_circle(P.call(-8, 11), 1.6 * u, hi)
		"snake":        # 장팔사모 —— 구불구불한 창날
			ci.draw_line(P.call(-9, 11), P.call(3, -3), lo.darkened(0.2), w * 1.2)
			ci.draw_polyline(PackedVector2Array([P.call(3, -3), P.call(6, -5), P.call(5, -8), P.call(8, -10), P.call(7, -13), P.call(10, -12)]), hi, w * 1.4)
		"sword":        # 곧은 검
			ci.draw_colored_polygon(PackedVector2Array([P.call(-1.5, 4), P.call(1.5, 4), P.call(1.2, -10), P.call(0, -13), P.call(-1.2, -10)]), hi)
			ci.draw_line(P.call(-6, 4), P.call(6, 4), lo, w * 1.3)
			ci.draw_line(P.call(0, 5), P.call(0, 11), lo.darkened(0.2), w * 1.4)
			ci.draw_circle(P.call(0, 12), 1.6 * u, hi)
		"twin_sword":   # 쌍고검 —— 엇갈린 두 검
			for sg in [-1.0, 1.0]:
				ci.draw_line(P.call(-9 * sg, 10), P.call(8 * sg, -11), hi, w * 1.3)
				ci.draw_line(P.call(-7 * sg + 3, 5), P.call(-7 * sg - 3, 9), lo, w * 1.3)
		"dao":          # 대도 —— 넓은 외날
			ci.draw_colored_polygon(PackedVector2Array([P.call(-2, 4), P.call(2, 4), P.call(5, -8), P.call(1, -13), P.call(-2, -9)]), hi)
			ci.draw_line(P.call(-5, 4), P.call(5, 4), lo, w * 1.3)
			ci.draw_line(P.call(0, 5), P.call(0, 11), lo.darkened(0.2), w * 1.4)
		"halberd":      # 방천화극 —— 창날 양옆 초승달
			ci.draw_line(P.call(0, 12), P.call(0, -6), lo.darkened(0.2), w * 1.2)
			ci.draw_colored_polygon(PackedVector2Array([P.call(-1.5, -6), P.call(1.5, -6), P.call(0, -13)]), hi)
			ci.draw_arc(P.call(-4, -4), 3.5 * u, PI * 0.5, PI * 1.5, 10, hi, w * 1.2)
			ci.draw_arc(P.call(4, -4), 3.5 * u, -PI * 0.5, PI * 0.5, 10, hi, w * 1.2)
		"twin":         # 쌍단극 —— 짧은 극 둘
			for sg in [-1.0, 1.0]:
				ci.draw_line(P.call(5 * sg, 11), P.call(5 * sg, -5), lo.darkened(0.2), w)
				ci.draw_colored_polygon(PackedVector2Array([P.call(5 * sg - 1.3, -5), P.call(5 * sg + 1.3, -5), P.call(5 * sg, -11)]), hi)
				ci.draw_arc(P.call(5 * sg - 3 * sg, -3), 2.5 * u, 0, TAU, 8, hi, w * 0.9)
		"bow":          # 활
			ci.draw_arc(P.call(-4, 0), 12 * u, -PI * 0.42, PI * 0.42, 16, hi, w * 1.4)
			ci.draw_line(P.call(4.8, -11), P.call(4.8, 11), lo, w * 0.6)
			ci.draw_line(P.call(-9, 0), P.call(8, 0), lo.lightened(0.2), w * 0.8)
			ci.draw_colored_polygon(PackedVector2Array([P.call(8, -1.8), P.call(12, 0), P.call(8, 1.8)]), hi)
		"flag":         # 군기
			ci.draw_line(P.call(-7, 12), P.call(-7, -12), lo.darkened(0.2), w * 1.1)
			ci.draw_colored_polygon(PackedVector2Array([P.call(-7, -11), P.call(9, -8), P.call(6, -3), P.call(9, 2), P.call(-7, 0)]), hi)
		"tally":        # 상국절 —— 술 달린 부절
			ci.draw_line(P.call(0, -12), P.call(0, 6), hi, w * 1.6)
			for y in [-8.0, -3.0, 2.0]:
				ci.draw_line(P.call(-4, y), P.call(4, y), lo, w)
			ci.draw_polyline(PackedVector2Array([P.call(0, 6), P.call(-3, 12), P.call(0, 10), P.call(3, 12), P.call(0, 6)]), lo, w)
		"seal":         # 인장 —— 손잡이 짐승 + 네모 인
			ci.draw_rect(Rect2(P.call(-8, 2), Vector2(16, 9) * u), hi)
			ci.draw_rect(Rect2(P.call(-6, 4), Vector2(12, 5) * u), lo.darkened(0.3), false, w * 0.7)
			ci.draw_circle(P.call(0, -4), 5 * u, hi)
			ci.draw_circle(P.call(0, -10), 2.6 * u, hi)
		"fan":          # 백우선 —— 깃털 부채
			for i in 7:
				var a := -PI * 0.5 + (i - 3) * 0.2
				ci.draw_line(P.call(0, 10), c + Vector2(0, 10 * u) + Vector2.from_angle(a) * 20 * u, hi, w * 1.8)
			ci.draw_line(P.call(0, 10), P.call(0, 13), lo, w * 1.4)
		"scroll":       # 두루마리
			ci.draw_rect(Rect2(P.call(-7, -9), Vector2(14, 18) * u), hi)
			ci.draw_line(P.call(-9, -9), P.call(9, -9), lo, w * 1.6)
			ci.draw_line(P.call(-9, 9), P.call(9, 9), lo, w * 1.6)
			for x in [-3.0, 0.0, 3.0]:
				ci.draw_line(P.call(x, -6), P.call(x, 6), lo.darkened(0.3), w * 0.6)
		"book":         # 비서 —— 묶은 책
			ci.draw_rect(Rect2(P.call(-8, -11), Vector2(16, 22) * u), hi)
			ci.draw_rect(Rect2(P.call(-3, -8), Vector2(7, 12) * u), lo.darkened(0.3), false, w * 0.7)
			for y in [-8.0, -2.0, 4.0, 9.0]:
				ci.draw_circle(P.call(-6, y), 0.9 * u, lo.darkened(0.4))
		"zither":       # 금(거문고)
			ci.draw_set_transform(c, -0.5)
			ci.draw_rect(Rect2(Vector2(-4, -12) * u, Vector2(8, 24) * u), hi)
			for x in [-2.0, 0.0, 2.0]:
				ci.draw_line(Vector2(x, -11) * u, Vector2(x, 11) * u, lo.darkened(0.3), w * 0.5)
			ci.draw_set_transform(Vector2.ZERO)
		"pin":          # 옥잠 —— 비녀 + 구슬
			ci.draw_line(P.call(-9, 9), P.call(6, -6), hi, w * 1.2)
			ci.draw_circle(P.call(7, -7), 3.5 * u, hi)
			ci.draw_circle(P.call(3, -10), 2 * u, lo)
			ci.draw_circle(P.call(10, -3), 2 * u, lo)
		"sail":         # 금범 —— 돛배
			ci.draw_line(P.call(0, 8), P.call(0, -12), lo.darkened(0.2), w)
			ci.draw_colored_polygon(PackedVector2Array([P.call(1, -11), P.call(10, 5), P.call(1, 5)]), hi)
			ci.draw_colored_polygon(PackedVector2Array([P.call(-1, -7), P.call(-8, 5), P.call(-1, 5)]), hi.darkened(0.15))
			ci.draw_colored_polygon(PackedVector2Array([P.call(-11, 8), P.call(11, 8), P.call(7, 12), P.call(-7, 12)]), lo)
		"robe":         # 백의
			ci.draw_colored_polygon(PackedVector2Array([P.call(-4, -11), P.call(4, -11), P.call(12, -4), P.call(8, 0), P.call(6, -3),
				P.call(7, 12), P.call(-7, 12), P.call(-6, -3), P.call(-8, 0), P.call(-12, -4)]), hi)
			ci.draw_polyline(PackedVector2Array([P.call(-4, -11), P.call(0, -4), P.call(4, -11)]), lo, w)
		"map":          # 지도 —— 접힌 종이 + 길
			ci.draw_colored_polygon(PackedVector2Array([P.call(-11, -8), P.call(-4, -10), P.call(4, -8), P.call(11, -10), P.call(11, 8), P.call(4, 10), P.call(-4, 8), P.call(-11, 10)]), hi)
			ci.draw_polyline(PackedVector2Array([P.call(-8, 6), P.call(-3, 1), P.call(2, 3), P.call(8, -6)]), lo.darkened(0.3), w * 0.9)
			ci.draw_circle(P.call(8, -6), 1.6 * u, Color("#c0392b"))
		"mirror":       # 수경 —— 물거울
			ci.draw_circle(c, 10 * u, hi)
			ci.draw_circle(c, 7.5 * u, lo.darkened(0.35))
			ci.draw_arc(c, 4.5 * u, PI * 1.1, PI * 1.7, 8, hi, w * 0.8)
			ci.draw_arc(c, 2.5 * u, PI * 0.1, PI * 0.7, 8, hi, w * 0.8)


## 썸네일 하나짜리 컨트롤
class View extends Control:
	var id := ""

	func _init(item_id := "", d := 56.0) -> void:
		id = item_id
		custom_minimum_size = Vector2(d, d)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if id != "":
			ItemArt.draw_item(self, Rect2(Vector2.ZERO, size), id)
