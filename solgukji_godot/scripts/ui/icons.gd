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
		# 11/9 능력 종류 기호 (색 카드 대신 기호로 가른다) —— 고유 특기 인장 · 위세 깃발 · 패업 관 · 고유기 터짐
		"seal":      # 인장 —— 네모 테두리, 안쪽 작은 네모
			ci.draw_rect(Rect2(c - Vector2(8, 8) * u, Vector2(16, 16) * u), col, false, w)
			ci.draw_rect(Rect2(c - Vector2(3.2, 3.2) * u, Vector2(6.4, 6.4) * u), col)
		"banner":    # 깃발 —— 깃대와 늘어진 깃
			ci.draw_line(c + Vector2(-6, -9) * u, c + Vector2(-6, 9) * u, col, w)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-6, -8) * u, c + Vector2(8, -8) * u, c + Vector2(4, -3) * u, c + Vector2(8, 2) * u,
				c + Vector2(-6, 2) * u]), col, w)
		"crown":     # 관 —— 뾰족 셋
			ci.draw_polyline(PackedVector2Array([c + Vector2(-8, 6) * u, c + Vector2(-8, -4) * u, c + Vector2(-3.5, 1) * u, c + Vector2(0, -7) * u,
				c + Vector2(3.5, 1) * u, c + Vector2(8, -4) * u, c + Vector2(8, 6) * u, c + Vector2(-8, 6) * u]), col, w)
		"burst":     # 터짐 —— 여덟 뾰족 별
			var bp := PackedVector2Array()
			for i in 16:
				var br := (10.0 if i % 2 == 0 else 4.2) * u
				bp.append(c + Vector2.from_angle(-PI / 2 + i * PI / 8) * br)
			bp.append(bp[0])
			ci.draw_polyline(bp, col, w * 0.9)
		"heart":     # 민심(마음) —— 아래가 뾰족한 하트 한 줄 (11/10 머리띠 민심 게이지)
			var hrt := PackedVector2Array()
			for i in 25:
				var ht := TAU * i / 24.0
				hrt.append(c + Vector2(16.0 * pow(sin(ht), 3.0), -2.5 - (13.0 * cos(ht) - 5.0 * cos(2.0 * ht) - 2.0 * cos(3.0 * ht) - cos(4.0 * ht))) * 0.56 * u)
			ci.draw_polyline(hrt, col, w)
		# 11/7 고유기 기질 기호 (디테일창 · 전투장수창 · 보급 팝업의 기질 칸) —— 맹장 칼 · 수호 방패 · 저격 과녁 · 분노 불꽃 (지략은 두루마리 "news")
		"blade":     # 칼 —— 날은 왼쪽 아래에서 오른쪽 위로, 코등이 · 자루
			ci.draw_line(c + Vector2(-3, 3) * u, c + Vector2(8, -8) * u, col, w * 1.4)
			ci.draw_line(c + Vector2(-7, -1) * u, c + Vector2(-1, 5) * u, col, w)
			ci.draw_line(c + Vector2(-4, 4) * u, c + Vector2(-8, 8) * u, col, w * 1.2)
		"shield":    # 방패 —— 위가 평평하고 아래가 뾰족한 모양, 가운데 세로줄
			ci.draw_polyline(PackedVector2Array([c + Vector2(-8, -7) * u, c + Vector2(8, -7) * u, c + Vector2(8, 0) * u, c + Vector2(0, 9) * u,
				c + Vector2(-8, 0) * u, c + Vector2(-8, -7) * u]), col, w)
			ci.draw_line(c + Vector2(0, -5) * u, c + Vector2(0, 6) * u, col, w * 0.8)
		"boot":      # 신발(속도) —— 옆에서 본 부츠: 목 · 발등 · 앞코는 오른쪽, 꽉 찬 밑창 (작은 크기에서 'ㄴ' 자로 뭉개지지 않게)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-6, -9) * u, c + Vector2(1.5, -9) * u, c + Vector2(1.5, -2.5) * u, c + Vector2(6, -0.5) * u,
				c + Vector2(9.5, 2) * u, c + Vector2(9.5, 4.5) * u]), col, w)
			ci.draw_line(c + Vector2(-6, -9) * u, c + Vector2(-6, 4.5) * u, col, w)
			ci.draw_line(c + Vector2(-6, -4.5) * u, c + Vector2(1.5, -4.5) * u, col, w * 0.7)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-8, 4) * u, c + Vector2(10.5, 4) * u, c + Vector2(10.5, 9) * u, c + Vector2(-8, 9) * u]), col)
		"target":    # 과녁 —— 큰 원 · 작은 원 · 십자
			ci.draw_arc(c, 8 * u, 0, TAU, 20, col, w)
			ci.draw_arc(c, 3.2 * u, 0, TAU, 12, col, w * 0.9)
			ci.draw_line(c + Vector2(-10, 0) * u, c + Vector2(-5.5, 0) * u, col, w * 0.8)
			ci.draw_line(c + Vector2(5.5, 0) * u, c + Vector2(10, 0) * u, col, w * 0.8)
			ci.draw_line(c + Vector2(0, -10) * u, c + Vector2(0, -5.5) * u, col, w * 0.8)
			ci.draw_line(c + Vector2(0, 5.5) * u, c + Vector2(0, 10) * u, col, w * 0.8)
		"flame":     # 불꽃 —— 바깥 불길 한 줄, 안쪽 작은 불길
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -9) * u, c + Vector2(5, -3) * u, c + Vector2(7, 3) * u, c + Vector2(4, 8) * u,
				c + Vector2(0, 9) * u, c + Vector2(-4, 8) * u, c + Vector2(-7, 3) * u, c + Vector2(-5, -3) * u, c + Vector2(-2, -1) * u, c + Vector2(0, -9) * u]), col, w)
			ci.draw_arc(c + Vector2(0, 4) * u, 3 * u, PI * 0.1, PI * 0.9, 8, col, w * 0.8)


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
