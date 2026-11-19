class_name MiniTile
extends Control
## 초상 위주의 작은 카드 —— 휴대폰 세로에서 한 줄에 4장. 보유 카드·조합 격자·재료에 쓴다.
## 위: 초상(등급색 테두리 · 세력 점 · 장수 배지) / 아래: 이름. 왼쪽 아래 알약 배지(조합 · -2 · 2/3 …).
## 짧게 누르면 tapped, 끌면 목록이 스크롤된다.

signal tapped(k: String)

var k := ""
var qty := -1
var badge := ""             # 왼쪽 아래 알약 글씨
var badge_col := Color.TRANSPARENT
var badge_quiet := false     # 11/14 편성 표시처럼 상태만 알리는 배지 —— 각진 작은 표 · 금 글자 (색으로 뜻을 전하는 −N · 조합 배지는 그대로)
var lit := false          # 금빛 테두리 (지금 조합 가능)
var up := false             # 오른쪽 위 ▲ —— 지금 조합 가능한 상위 카드의 재료
var dim := false            # 흐리게 (없는 카드)
var _press := Vector2.INF
var drag_data = null        # 있으면 길게 눌러(0.35초) 끌 수 있다 (편성 손패, 11/4)
var on_hold := Callable()   # 11/13 끌기가 없는 타일을 꾹 누르면(CardTile.HOLD) 부른다 (징집 보유 카드 —— 판매 시트). 그때는 tapped 를 보내지 않는다
var show_role := true       # 11/20 인연 타일은 구성원 확인용이라 역할 칩을 뺀다 (얼굴 · 이름만)
var short_name := false     # 11/11 인연 타일 —— 이름 줄에 칭호 없이 인물 이름만 (60폭에 '난세간웅 조조' 가 잘렸다)
var mark := ""              # "sel" —— 고른 카드 (금테)
var star := false           # 11/7 갈무리 표시 —— 12시 방향 노란 ★ (갈무리한 장수 · 그 재료)
var ring := false           # 11/7 갈무리 표시 —— 테두리가 빠르게 깜빡이는 금빛 하이라이트 (아직 더 모아야 하는 재료)
var _fx: PinFx = null       # ★ · 깜빡이는 테를 그리는 덧칸
var _held := 0.0
var _dragging := false
## 11/12 온라인 장수 선점제 · 사망룰 —— 지금 판의 Run.locked (GameScreen.render 가 넣는다). 여기 있는 장수(가지지 않은 것)는
## 회색 + 「정지 세력이 등용」 · 「사망」 띠, 누를 수 없다
static var locked := {}


func setup(id: String, n := -1) -> MiniTile:
	k = id
	qty = n
	custom_minimum_size = UI.TILE_M      # 11/7 사용자: 카드 축소 (78×112 → 66×96, 한 줄 5장)
	mouse_filter = Control.MOUSE_FILTER_PASS
	return self


## 11/7 사용자: '갈무리된 재료' 표현 통일 —— 창마다 다르던 금색 · 옥빛 테두리 · "갈무리" 뱃지 대신 카드 12시 방향 노란 ★ 과
## 테두리가 깜빡이는 금빛 하이라이트. 그리기는 작은 덧칸(PinFx)이 맡아 타일 본체(초상)는 매 프레임 다시 그리지 않는다
func set_pin(s: bool, r: bool) -> void:
	star = s
	ring = r
	if not s and not r:
		if _fx != null:
			_fx.queue_free()
			_fx = null
		return
	if _fx == null:
		_fx = PinFx.new()
		add_child(_fx)
	_fx.setup(s, r)


## 갈무리 덧칸 —— 타일 위에 얹혀 ★ 과 깜빡이는 테두리만 그린다. 많은 칸에 얹혀도 가볍게: 점 29개짜리 선 하나 + 별 하나
class PinFx extends Control:
	const BLINK_SEC := 0.6      # 깜빡임 한 주기(초) —— 11/9 사용자: 도는 빛(한 바퀴 10초) 대신 빠른 깜빡임
	const STAR_COL := Color("#FFD94A")
	var star := true
	var ring := true
	var col: Color = DB.PAL.gold
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func setup(s: bool, r: bool) -> void:
		star = s
		ring = r
		set_process(r)
		queue_redraw()

	func _process(dt: float) -> void:
		if not is_visible_in_tree():
			return
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 2.0 or h < 2.0:
			return
		if ring:
			# 11/9 사용자: 도는 빛 대신 빠르게 깜빡이는 금빛 테두리 —— 한 주기 약 0.6초, 진했다(밝은 금빛 · 굵게) 옅어졌다
			var inset := 1.5
			var rad := maxf(1.0, (8.0 if w >= 56.0 else 5.0) - inset)      # 타일의 모서리 반지름(8 · 작은 칸 5)에 맞춘다
			var rect := Rect2(inset, inset, w - inset * 2.0, h - inset * 2.0)
			var corners := [Vector2(rect.end.x - rad, rect.position.y + rad), Vector2(rect.end.x - rad, rect.end.y - rad),
				Vector2(rect.position.x + rad, rect.end.y - rad), Vector2(rect.position.x + rad, rect.position.y + rad)]
			var pts := PackedVector2Array()
			for ci in 4:
				var a0 := -PI / 2.0 + ci * PI / 2.0
				for j in 7:
					pts.append(corners[ci] + Vector2.from_angle(a0 + j * (PI / 2.0) / 6.0) * rad)
			pts.append(pts[0])
			var b := 0.5 - 0.5 * cos(_t * TAU / BLINK_SEC)      # 0 ~ 1
			draw_polyline(pts, Color(col.lightened(0.4 * b), 0.12 + 0.88 * b), 2.0 + 1.5 * b, true)
		if star:
			# 12시 방향 노란 별 —— 테두리 위에 걸치게, 어두운 윤곽선
			var c := Vector2(w / 2.0, 1.0)
			var sp := PackedVector2Array()
			for i in 10:
				sp.append(c + Vector2.from_angle(-PI / 2.0 + i * PI / 5.0) * (7.0 if i % 2 == 0 else 3.0))
			draw_colored_polygon(sp, STAR_COL)
			sp.append(sp[0])
			draw_polyline(sp, Color("#4A3608"), 1.2, true)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press = e.position
			_held = 0.0
			_dragging = false
			set_process(drag_data != null or on_hold.is_valid())      # 꾹 누르기를 재는 동안만 (끝나면 _process 가 스스로 끈다)
		else:
			if _press != Vector2.INF and not _dragging and e.position.distance_to(_press) < 14 and not _is_locked():
				UI.buzz()
				tapped.emit(k)
			_press = Vector2.INF
	elif e is InputEventMouseMotion and _press != Vector2.INF and e.position.distance_to(_press) >= 14:
		_press = Vector2.INF


## 11/15 성능 —— ① 매 프레임 _process 는 누르고 있는 동안만 (목록의 타일 190장이 가만히 있을 때도 프레임마다 불렸다)
## ② 화면 밖 타일은 그리지 않고, 자리가 바뀌어 화면에 들어오면 그때 그린다 (UI.off_screen)
var _skipped := false       # 화면 밖이라 그리기를 건너뛰었다


func _ready() -> void:
	set_process(false)
	set_notify_transform(true)
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_wake):
		vp.size_changed.connect(_wake)      # 창 크기가 바뀌면 화면 안팎이 달라진다


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _skipped:
		_wake()


func _wake() -> void:
	if _skipped and is_inside_tree() and not UI.off_screen(self):
		_skipped = false
		queue_redraw()


func _process(dt: float) -> void:
	if _press == Vector2.INF or _dragging:
		set_process(false)
		return
	if drag_data == null:
		if on_hold.is_valid():
			_held += dt
			if _held >= CardTile.HOLD + 0.1:
				_dragging = true      # 손을 뗄 때 tapped 를 보내지 않게
				_press = Vector2.INF
				UI.buzz()
				on_hold.call(k)
		return
	_held += dt
	if _held >= CardTile.HOLD:
		_dragging = true
		_press = Vector2.INF
		var pv := MiniTile.new().setup(k, -1)
		pv.size = size
		pv.modulate = Color(1, 1, 1, 0.85)
		var holder := Control.new()
		holder.add_child(pv)
		pv.position = -size / 2
		force_drag(drag_data, holder)


func _draw() -> void:
	if k == "":
		return
	if UI.off_screen(self):
		_skipped = true
		return
	_skipped = false
	var c: Dictionary = DB.C[k]
	var tc := DB.tier_color(k)
	var w := size.x
	var h := size.y
	if w < 56:
		_draw_compact(c, tc, w, h)
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = DB.PAL.ink2
	var on := lit or mark == "sel"
	sb.border_color = DB.PAL.gold if on else tc.darkened(0.15)
	sb.set_border_width_all(2 if on else 1)
	sb.border_width_top = 3
	sb.set_corner_radius_all(8)
	if on:
		sb.shadow_color = Color(DB.PAL.gold, 0.35)
		sb.shadow_size = 4
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var pr := Rect2(4, 5, w - 8, h - 27)
	Art.draw_portrait(self, pr, k)
	if c.tier > 2:
		draw_circle(pr.position + Vector2(8, 8), 8, DB.fac_color(c.fac))
		draw_string(DB.title_font(UI.FS_TINY), pr.position + Vector2(0, 11.5), c.fac, HORIZONTAL_ALIGNMENT_CENTER, 16, UI.FS_TINY, Color.WHITE)
	var has_role := show_role and not DB.role_chip(k).is_empty()
	# 11/20 폴리싱: 낮은 칸(징집 보유 6열 84 · 갈무리 재료 78 · 편성 손패 80)은 초상이 57px 아래인데 수량 · 배지 · 병종 기호 · 역할 칩이 큰 칸과 같은 크기라 얼굴이 다 가렸다 —— 낮은 칸에서는 덧붙는 것들을 작은 칸(_draw_compact) 크기로
	var small := pr.size.y < 60.0
	var cfs := UI.FS_TINY if small else UI.FS_CAP      # 수량 · 배지 글씨
	var bh := 14.0 if small else 17.0                  # 수량 · 배지 높이
	var tr := 6.0 if small else 8.0                    # 병종 기호 반지름 (작은 칸과 같은 6)
	var tag_c := pr.end - Vector2(tr + 2.0, (16.0 if has_role else 0.0) + tr + 2.0)
	_tag_icon(c, tag_c, tr)      # 11/6 사용자: 그림에 병종 심볼 (11/19 역할 칩이 있으면 그 위로)
	if has_role:
		CardTile.draw_role_chip(self, k, Vector2(pr.position.x, pr.end.y - 15), UI.FS_TINY, pr.size.x, true)      # 11/19 장수 역할 칩 —— 초상 아래 폭 전체 (11/20 fill: 타일마다 같은 폭 · 높이)
	var fd := DB.tier_font(c.tier, 13)
	var nm: String = DB.person(k) if short_name and c.tier > 2 else c.name
	var fs := UI.fit_fs(fd, nm, 13, UI.FS_TINY, w - 6)      # 11/14 감사 #10: 아무리 길어도 FS_TINY 아래로는 줄이지 않는다
	if fs == UI.FS_TINY and c.tier > 2 and fd.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 6:
		nm = DB.person(k)      # 그래도 넘치면 칭호를 떼고 인물 이름만
		fs = UI.fit_fs(fd, nm, 13, UI.FS_TINY, w - 6)
	draw_string(fd, Vector2(3, h - 8), nm, HORIZONTAL_ALIGNMENT_CENTER, w - 6, fs, tc.lightened(0.15) if c.tier >= 3 else tc)
	var q_left := w - 3.0      # 수량 배지 왼끝 (없으면 타일 오른끝)
	if qty > 0:
		var s := "×%d" % qty
		var qw := DB.font_body.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x + (6 if small else 8)
		var qr := Rect2(w - qw - 3, 4, qw, bh)
		q_left = qr.position.x
		var qb := StyleBoxFlat.new()
		qb.bg_color = Color(DB.PAL.gold, 0.92)
		qb.set_corner_radius_all(8)
		draw_style_box(qb, qr)
		draw_string(DB.font_body, qr.position + Vector2(0, bh - 4.0 + (0.5 if small else 0.0)), s, HORIZONTAL_ALIGNMENT_CENTER, qw, cfs, Color("#1A1508"))
	if up:
		var us := 12.0 if small else 16.0
		var ur := Rect2(w - us - 3, (4.5 if small else 5.0) + bh if qty > 0 else 4.0, us, us)
		# 11/20 2차: 오른쪽에 ×N · ▲ · 병종 기호가 세로로 쌓인다 —— 낮은 칸에서 ▲ 가 병종 기호를 덮었다. 자리가 모자라면 ▲ 를 줄이고(9 까지), 그래도 안 되면 ×N 왼쪽으로
		var room := tag_c.y - tr - 1.5 - ur.position.y
		if room < us and room >= 9.0:
			us = floorf(room)
			ur = Rect2(w - us - 3, ur.position.y, us, us)
		elif room < us and qty > 0:
			ur = Rect2(q_left - us - 1.0, 4.0 + (bh - us) * 0.5, us, us)
		var ub := StyleBoxFlat.new()
		ub.bg_color = Color(DB.PAL.jade, 0.95)
		ub.set_corner_radius_all(8)
		draw_style_box(ub, ur)
		Icons.draw(self, "up", ur.get_center(), us - 2.0, Color.WHITE)
	# 11/20 2차: 좁은 칸(6열 57px)에서 왼쪽 배지("편성 2" · "조합")가 오른쪽 병종 기호를 덮었다 —— 기호 앞까지만 쓴다: 넘치면 첫 낱말만("편성"), 그래도 넘치면 글씨를 한 단계 작게
	var b_txt := badge
	var b_fs := UI.FS_TINY if badge_quiet else cfs
	var b_pad := 8.0 if badge_quiet or small else 10.0
	if badge != "":
		var b_room := tag_c.x - tr - 2.5 - 4.0
		var b_w := DB.font_body.get_string_size(b_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, b_fs).x
		if b_w + b_pad > b_room and b_txt.contains(" "):
			b_txt = b_txt.get_slice(" ", 0)
			b_w = DB.font_body.get_string_size(b_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, b_fs).x
		if b_w + b_pad > b_room and b_fs > UI.FS_TINY:
			b_fs = UI.FS_TINY
			b_pad = 6.0
	if badge != "" and not badge_quiet:
		var bw0 := DB.font_body.get_string_size(b_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, b_fs).x + b_pad
		var br0 := Rect2(4, pr.end.y - 2.0 - bh - (15 if has_role else 0), bw0, bh)      # 11/19 역할 칩 위로
		var bb0 := StyleBoxFlat.new()
		bb0.bg_color = badge_col if badge_col.a > 0 else Color(DB.PAL.ink, 0.85)
		bb0.set_corner_radius_all(UI.R)      # 11/14 알약 → 모서리 규칙 R
		draw_style_box(bb0, br0)
		draw_string(DB.font_body, br0.position + Vector2(0, (bh + b_fs * 0.72) * 0.5), b_txt, HORIZONTAL_ALIGNMENT_CENTER, bw0, b_fs, Color.WHITE)
	elif badge != "":
		# 11/14 UI 4단계 (감사 06-4): 흰 글자 둥근 알약이 초상을 가리고 다른 배지 셋과 다퉜다 —— 각진 작은 표(R) · 금 글자 · 한 단계 작은 글자로 무게를 낮춘다
		var bw := DB.font_body.get_string_size(b_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.FS_TINY).x + 8
		var br := Rect2(4, pr.end.y - 15.0 - (15 if has_role else 0), bw, 14)      # 11/19 역할 칩 위로 (11/20 왼쪽 끝을 초상 · 칩에 맞춤 3 → 4)
		var bb := StyleBoxFlat.new()
		bb.bg_color = Color(DB.PAL.ink, 0.88)
		bb.border_color = Color(DB.PAL.gold, 0.7)
		bb.set_border_width_all(1)
		bb.set_corner_radius_all(UI.R / 2)
		draw_style_box(bb, br)
		draw_string(DB.font_body, br.position + Vector2(0, 11), b_txt, HORIZONTAL_ALIGNMENT_CENTER, bw, UI.FS_TINY, DB.PAL.gold)
	if dim:
		draw_rect(Rect2(Vector2.ZERO, size), Color(DB.PAL.ink, 0.5))
	if _is_locked():
		_draw_lock(w, h)


func _is_locked() -> bool:
	return qty <= 0 and locked.has(k)


## 잠긴 장수 —— 회색으로 덮고 가운데에 까닭 띠 (11/12)
func _draw_lock(w: float, h: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.16, 0.17, 0.72))
	var e = locked[k]
	var dead: bool = not (e is Dictionary and e.has("by"))
	var tx := "사망" if dead else "%s 세력이 등용" % str(e.by)
	var fs := UI.fit_fs(DB.font_body, tx, UI.FS_CAP if w >= 56 else UI.FS_TINY, UI.FS_TINY, w - 4)
	if DB.font_body.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 4:
		tx = "사망" if dead else "등용"      # 11/14 감사 #10: 글자를 FS_TINY 아래로 줄이는 대신 짧게
	var bh := fs + 8.0
	var by := h * 0.42 - bh / 2.0
	draw_rect(Rect2(0, by, w, bh), Color(DB.PAL.seal, 0.9) if dead else Color(0.1, 0.1, 0.12, 0.92))
	draw_string(DB.font_body, Vector2(2, by + bh - 4.0 - (fs * 0.1)), tx, HORIZONTAL_ALIGNMENT_CENTER, w - 4, fs, Color.WHITE if dead else Color(0.82, 0.82, 0.82))


## 작은 칸 (폭 56 아래 —— 징집 화면 보유 패 8열, 11/2) —— 초상 · 짧은 이름 · 수량 · ▲ 만. 편성 중이면 왼쪽 아래 옥색 점
## 병종 심볼 —— 그림 오른쪽 아래 먹색 원 안에 (11/6 사용자)
func _tag_icon(c: Dictionary, p: Vector2, r: float) -> void:
	var ic: Texture2D = DB.ICON.get(c.tag)
	if ic == null:
		return
	draw_circle(p, r + 1.5, DB.kind_col(c.tag))      # 11/9 피해 종류 —— 테두리 색 (물리 주황 · 책략 파랑)
	draw_circle(p, r, Color(DB.PAL.ink, 0.92))
	var s := r * 1.5
	draw_texture_rect(ic, Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), false, DB.PAL.paper)


func _draw_compact(c: Dictionary, tc: Color, w: float, h: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = DB.PAL.ink2
	sb.border_color = DB.PAL.gold if lit or mark == "sel" else tc.darkened(0.1)
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.set_corner_radius_all(5)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var pr := Rect2(2, 3, w - 4, h - 17)
	Art.draw_portrait(self, pr, k)
	_tag_icon(c, pr.end - Vector2(7, 7), 6.0)
	var fd := DB.tier_font(c.tier, UI.FS_TINY)
	# 11/3 사용자: 칭호를 떼고 "손권" 만 보이면 다른 카드(벽안 손권)로 오해한다 —— 칭호까지 보이고, 안 들어가면 칭호를 이름 위 작은 줄로
	var nm: String = c.name
	var nc := tc.lightened(0.15) if c.tier >= 3 else tc
	var fs := UI.FS_TINY      # 11/14 감사 #10: 작은 칸 글자도 FS_TINY 아래로는 줄이지 않는다 —— 넘치면 칭호를 위 줄로 · 그래도 넘치면 … 으로
	if c.tier > 2 and nm.contains(" ") and fd.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 2:
		var per := DB.person(k)
		var title := nm.substr(0, nm.length() - per.length()).strip_edges()
		var ts := UI.FS_TINY
		title = UI.ellipsize(DB.font_body, title, ts, w - 2)
		draw_rect(Rect2(1, h - 27, w - 2, 12), Color(DB.PAL.ink2, 0.8))
		draw_string(DB.font_body, Vector2(1, h - 17), title, HORIZONTAL_ALIGNMENT_CENTER, w - 2, ts, Color(nc, 0.85))
		nm = per
	nm = UI.ellipsize(fd, nm, fs, w - 2)
	draw_string(fd, Vector2(1, h - 4), nm, HORIZONTAL_ALIGNMENT_CENTER, w - 2, fs, nc)
	if qty > 1:
		var s := "%d" % qty
		var qw := DB.font_body.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.FS_TINY).x + 6
		var qr := Rect2(w - qw - 1, 1, qw, 13)
		var qb := StyleBoxFlat.new()
		qb.bg_color = Color(DB.PAL.gold, 0.92)
		qb.set_corner_radius_all(6)
		draw_style_box(qb, qr)
		draw_string(DB.font_body, qr.position + Vector2(0, 10.5), s, HORIZONTAL_ALIGNMENT_CENTER, qw, UI.FS_TINY, Color("#1A1508"))
	if up:
		var ur := Rect2(w - 13, 14 if qty > 1 else 1, 12, 12)
		var ub := StyleBoxFlat.new()
		ub.bg_color = Color(DB.PAL.jade, 0.95)
		ub.set_corner_radius_all(6)
		draw_style_box(ub, ur)
		Icons.draw(self, "up", ur.get_center(), 10, Color.WHITE)
	if badge != "":
		draw_circle(Vector2(6, h - 19), 4, Color(DB.PAL.jade, 0.95))
	if dim:
		draw_rect(Rect2(Vector2.ZERO, size), Color(DB.PAL.ink, 0.5))
	if _is_locked():
		_draw_lock(w, h)
