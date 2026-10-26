class_name Icons
extends RefCounted
## 작은 그림 기호 —— 글꼴에 없는 기호도 휴대폰에서 똑같이 보이게 선으로 그린다.
## draw(그릴 곳, 이름, 가운데, 크기(지름), 색)

static func draw(ci: CanvasItem, name: String, c: Vector2, s: float, col: Color) -> void:
	var u := s / 24.0        # 24 칸 기준 좌표
	var w := maxf(1.6, 2.2 * u)
	match name:
		"draw":      # 겹친 카드 두 장
			ci.draw_set_transform(c + Vector2(-3, 1) * u, -0.22)
			ci.draw_rect(Rect2(Vector2(-6, -9) * u, Vector2(12, 17) * u), col, false, w)
			ci.draw_set_transform(c + Vector2(4, 0) * u, 0.18)
			ci.draw_rect(Rect2(Vector2(-6, -9) * u, Vector2(12, 17) * u), col, false, w)
			ci.draw_line(Vector2(-2, -3) * u, Vector2(2, -3) * u, col, w)
			ci.draw_set_transform(Vector2.ZERO)
		"pick":      # 별
			var pts := PackedVector2Array()
			for i in 10:
				var r := (10.0 if i % 2 == 0 else 4.3) * u
				pts.append(c + Vector2.from_angle(-PI / 2 + i * PI / 5) * r)
			pts.append(pts[0])
			ci.draw_polyline(pts, col, w)
		"grant":     # 주사위
			ci.draw_rect(Rect2(c - Vector2(8, 8) * u, Vector2(16, 16) * u), col, false, w)
			for p in [Vector2(-4, -4), Vector2(0, 0), Vector2(4, 4)]:
				ci.draw_circle(c + p * u, 1.6 * u, col)
		"gift":      # 보상 상자
			ci.draw_rect(Rect2(c + Vector2(-8, -3) * u, Vector2(16, 12) * u), col, false, w)
			ci.draw_rect(Rect2(c + Vector2(-9, -7) * u, Vector2(18, 4) * u), col, false, w)
			ci.draw_line(c + Vector2(0, -7) * u, c + Vector2(0, 9) * u, col, w)
			ci.draw_arc(c + Vector2(-3, -9) * u, 3 * u, 0, TAU, 10, col, w * 0.8)
			ci.draw_arc(c + Vector2(3, -9) * u, 3 * u, 0, TAU, 10, col, w * 0.8)
		"item":      # 보석(마름모)
			var d := PackedVector2Array([c + Vector2(0, -9) * u, c + Vector2(8, -2) * u, c + Vector2(0, 9) * u, c + Vector2(-8, -2) * u, c + Vector2(0, -9) * u])
			ci.draw_polyline(d, col, w)
			ci.draw_line(c + Vector2(-8, -2) * u, c + Vector2(8, -2) * u, col, w * 0.8)
		"news":      # 두루마리
			ci.draw_rect(Rect2(c + Vector2(-7, -8) * u, Vector2(14, 16) * u), col, false, w)
			for y in [-3.0, 1.0, 5.0]:
				ci.draw_line(c + Vector2(-4, y) * u, c + Vector2(4, y) * u, col, w * 0.7)
		"forge":     # 망치
			ci.draw_set_transform(c, -0.7)
			ci.draw_rect(Rect2(Vector2(-1.5, -4) * u, Vector2(3, 16) * u), col)
			ci.draw_rect(Rect2(Vector2(-8, -10) * u, Vector2(16, 7) * u), col)
			ci.draw_set_transform(Vector2.ZERO)
		"trade":     # 맞바꾸기 화살표
			ci.draw_line(c + Vector2(-8, -4) * u, c + Vector2(8, -4) * u, col, w)
			ci.draw_line(c + Vector2(8, -4) * u, c + Vector2(4, -8) * u, col, w)
			ci.draw_line(c + Vector2(8, 4) * u, c + Vector2(-8, 4) * u, col, w)
			ci.draw_line(c + Vector2(-8, 4) * u, c + Vector2(-4, 8) * u, col, w)
		"check":     # ✔
			ci.draw_polyline(PackedVector2Array([c + Vector2(-8, 0) * u, c + Vector2(-2, 6) * u, c + Vector2(9, -7) * u]), col, w * 1.2)
		"up":        # 위로 (상위 조합 재료)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-6, 3) * u, c + Vector2(0, -4) * u, c + Vector2(6, 3) * u]), col, w * 1.2)


## 기호 하나짜리 컨트롤 —— 버튼·칩 안에 넣는다
class View extends Control:
	var icon := ""
	var col := Color.WHITE
	var dia := 22.0

	func _init(n := "", c := Color.WHITE, d := 22.0) -> void:
		icon = n
		col = c
		dia = d
		custom_minimum_size = Vector2(d, d)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Icons.draw(self, icon, size / 2, dia, col)
