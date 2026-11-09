class_name TierDeco
extends RefCounted
## 등급 장식 (11/9 사용자: 기 · 초 · 불 · 신의 프로필을 더 화려하게) —— 카드 초상 타일(CardView · MiniTile · CardTile · 편성 칸 · 전투 아래 카드)이 같이 쓴다.
## 규칙: 일반 카드(1~5등급, 기인 아닌 것)는 장식이 없다. 위 등급일수록 장식이 커진다 —— 네 단계가 서로 달라야 한다.
##   기인   고유 색(KIIN_COL) · 가는 안쪽 선 + 모서리 짧은 꺾쇠 + 윗변 작은 마름모 보석 ('역할이 있는 특수 카드')
##   초월   하늘색 · 이중 테 + 이중 꺾쇠(바깥 굵게, 안쪽 가늘게) + 아래 은빛 선 (차갑고 단정한 광택)
##   불멸   주황 · 금속 테(밝은 바깥 선 + 어두운 안쪽 선) + 안쪽 빛 + 모서리 꺾쇠에 마름모 + 윗변 불꽃
##   신화   금 · 금박 겹테 + 큰 꺾쇠(끝에 구슬 · 모서리 마름모) + 좌우 · 아래 마름모 + 윗변 왕관(붉은 보석) + 지나가는 빛줄기(Shimmer)
## 장식은 모두 선 · 다각형으로 그린다(그림 파일 없음). 정적인 장식은 (등급 · 크기 단계 · 타일 크기 · 화면 배율)마다 SubViewport 에 **한 번만 구워** 텍스처 한 장으로 찍는다
##   (선 · 호 · 다각형 100여 개를 타일마다 매 프레임 다시 보내면 신화 30장 격자가 휴대폰에서 무겁다 —— 11/9 측정은 작업현황 52). 구워지기 전 한두 프레임만 직접 그린다.
##   움직이는 것은 신화의 Shimmer 덧칸 하나뿐.
## 게임 정보를 가리지 않게 —— 장식은 테두리 띠 · 모서리 · 윗변 가운데 · 아래 가운데에만. 윗변 가운데는 갈무리 ★(MiniTile.PinFx)가 쓰면 비운다(top_free = false).

enum { NONE, KIIN, CHO, BUL, SIN }
enum { FULL, MINI, TINY }      # 타일 크기 단계 —— 큰 카드(CardView) · 작은 카드(폭 56 이상) · 아주 작은 칸(폭 56 미만 · 전투 아래 카드)

const GOLD_FOIL := Color("#fff3bf")
const GEM_RED := Color("#ff5a4a")
const SILVER := Color("#e2edf7")


## 이 카드의 장식 단계 —— 기인은 전설 값(5)이지만 따로, 초월 6 · 불멸 7 · 신화 8
static func rank(k: String) -> int:
	if not DB.C.has(k):
		return NONE
	if DB.is_kiin(k):
		return KIIN
	var t: int = DB.C[k].tier
	return NONE if t < 6 else (CHO if t == 6 else (BUL if t == 7 else SIN))


const BAKE_M := 8.0      # 구운 그림이 타일 바깥으로 삐져나올 수 있는 여백(논리 px) —— 윗변 왕관 · 불꽃 · 마름모


## 타일 위에 장식을 얹는다 (구운 텍스처 한 장 —— 아직 안 구워졌으면 직접 그리고, 구워지면 다시 그리게 한다). 인자 뜻은 paint 와 같다
static func draw(ci: CanvasItem, r: Rect2, k: String, sz := MINI, rad := 8.0, bw := 1.0, u := 1.0, top_free := true, top_cx := -1.0) -> void:
	var rk := rank(k)
	if rk == NONE or r.size.x < 8.0 or r.size.y < 8.0:
		return
	var sc := _px_scale(ci)
	var key := "%d|%d|%d|%d|%.1f|%.1f|%.2f|%d|%.1f|%.2f" % [rk, sz, ceili(r.size.x), ceili(r.size.y), rad, bw, u, int(top_free), top_cx, sc]
	var e: Baked = _baked.get(key)
	if e != null and e.ready:
		ci.draw_texture_rect(e.tex, Rect2(r.position - Vector2(BAKE_M, BAKE_M), r.size + Vector2(BAKE_M, BAKE_M) * 2.0), false)
		return
	paint(ci, r, k, sz, rad, bw, u, top_free)
	if e == null:
		e = Baked.new()
		e.key = key
		e.args = [k, sz, Vector2(ceilf(r.size.x), ceilf(r.size.y)), rad, bw, u, top_free, sc, top_cx]
		_baked[key] = e
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(e.make())
	if not e.waiters.has(ci):
		e.waiters.append(ci)


static var _baked := {}      # 키 → Baked


## 화면 배율 —— 논리 좌표 1 이 화면 몇 px 인가 (0.25 단위, 0.5 ~ 3). 구운 그림은 이 배율로 구워 1:1 로 찍는다 (battle_view 의 _px_scale 과 같은 규칙)
static func _px_scale(ci: CanvasItem) -> float:
	var vp := ci.get_viewport()
	if vp == null:
		return 1.0
	return clampf(snappedf(vp.get_final_transform().get_scale().x, 0.25), 0.5, 3.0)


## 구운 장식 한 장 —— SubViewport(투명 배경 · 한 번만 그린다) 와 그것을 쓰려고 기다리는 타일들
class Baked extends RefCounted:
	var key := ""
	var args := []
	var ready := false
	var tex: Texture2D = null
	var waiters := []

	func make() -> SubViewport:
		var sz: Vector2 = args[2]
		var sc: float = args[7]
		var sub := SubViewport.new()
		sub.size = Vector2i(ceili((sz.x + TierDeco.BAKE_M * 2.0) * sc), ceili((sz.y + TierDeco.BAKE_M * 2.0) * sc))
		sub.transparent_bg = true
		sub.disable_3d = true
		sub.gui_disable_input = true
		sub.render_target_update_mode = SubViewport.UPDATE_ONCE
		var ctl := Painter.new()
		ctl.args = args
		ctl.size = Vector2(sub.size)
		sub.add_child(ctl)
		tex = sub.get_texture()
		sub.ready.connect(_after.bind(sub), CONNECT_ONE_SHOT)
		return sub

	func _after(sub: SubViewport) -> void:
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw      # 한 번 그린 뒤부터 텍스처가 유효
		ready = true
		for w in waiters:
			if is_instance_valid(w):
				(w as CanvasItem).queue_redraw()
		waiters.clear()


## 구울 때 쓰는 그리개 —— 배율을 걸고 paint 를 그대로 부른다
class Painter extends Control:
	var args := []

	func _draw() -> void:
		var sc: float = args[7]
		var sz: Vector2 = args[2]
		draw_set_transform(Vector2(TierDeco.BAKE_M, TierDeco.BAKE_M) * sc, 0.0, Vector2(sc, sc))
		TierDeco.paint(self, Rect2(Vector2.ZERO, sz), args[0], args[1], args[3], args[4], args[5], args[6], args[8])


## 타일 위에 장식을 직접 그린다(구울 때 · 구워지기 전). r 타일 전체 · sz 크기 단계 · rad 타일 테두리 모서리 반지름 · bw 타일 테두리 두께 · u 크기 배율(큰 카드는 폭/150, 나머지 1) · top_free 윗변 가운데를 써도 되는가
static func paint(ci: CanvasItem, r: Rect2, k: String, sz := MINI, rad := 8.0, bw := 1.0, u := 1.0, top_free := true, top_cx := -1.0) -> void:
	var rk := rank(k)
	if rk == NONE or r.size.x < 8.0 or r.size.y < 8.0:
		return
	var tc := DB.tier_color(k)
	var s := u * (0.75 if sz == TINY else (1.4 if sz == FULL else 1.0))      # 큰 카드는 장식도 한 단계 크게
	var o := bw * 0.5       # 테두리 띠 가운데 선
	var tx := r.position.x + top_cx if top_cx >= 0.0 else r.get_center().x      # 윗변 장식 가운데 x (top_cx 가 없으면 타일 가운데)
	match rk:
		KIIN:
			if sz != TINY:
				_ring(ci, r, bw + 1.5 * s, rad, Color(tc, 0.55), 1)
			_corners(ci, r, o, rad, (8.0 if sz != TINY else 4.0) * s, tc.lightened(0.3), maxf(1.8, 2.4 * s))
			if top_free and sz != TINY:
				var c := Vector2(tx, r.position.y + (6.0 if sz == MINI else 2.0 * s))
				_diamond(ci, c, 4.2 * s, 6.0 * s, tc.lightened(0.15), Color(DB.PAL.ink, 0.85))
		CHO:
			if sz != TINY:
				_ring(ci, r, bw + 1.5 * s, rad, Color(tc.lightened(0.35), 0.75), 1)
			else:
				_ring(ci, r, bw + 1.0, rad, Color(tc.lightened(0.35), 0.6), 1)
			var cc := Color.WHITE.lerp(tc, 0.35)
			_corners(ci, r, o, rad, (11.0 if sz != TINY else 5.0) * s, cc, maxf(2.0, 2.6 * s))
			if sz != TINY:      # 안쪽 가는 꺾쇠 —— 이중
				_corners(ci, r.grow(-3.5 * s), o, maxf(2.0, rad - 3.5 * s), 5.5 * s, Color(cc, 0.85), maxf(1.0, 1.3 * s), false, Color(0, 0, 0, 0))
				var y := r.end.y - maxf(bw, 2.0 * s) - 1.5 * s
				var x0 := r.position.x + rad + 2.0 * s
				var x1 := r.end.x - rad - 2.0 * s
				if x1 - x0 > 16.0:      # 이름판 아래 은빛 선 —— 양끝이 옅어진다
					var pts := PackedVector2Array()
					var cols := PackedColorArray()
					for i in 9:
						var f := float(i) / 8.0
						pts.append(Vector2(lerpf(x0, x1, f), y))
						cols.append(Color(SILVER, 0.85 * sin(f * PI)))
					ci.draw_polyline_colors(pts, cols, maxf(1.0, 1.4 * s))
		BUL:
			_ring(ci, r, 0.0, rad, Color(tc.lightened(0.5), 0.9), 1)           # 금속 —— 밝은 바깥 선
			_ring(ci, r, maxf(1.0, bw - 0.5), rad, Color(tc.darkened(0.55), 0.95), 1)      # 어두운 안쪽 선
			if sz != TINY:
				_ring(ci, r, bw + 0.5 * s, rad, Color(tc.lightened(0.2), 0.24), int(maxf(2.0, 2.0 * s)))     # 안쪽 빛
				_ring(ci, r, bw + 2.5 * s, rad, Color(tc.lightened(0.2), 0.10), int(maxf(2.0, 2.0 * s)))
			var cc := tc.lightened(0.5)
			_corners(ci, r, o, rad, (13.0 if sz != TINY else 5.0) * s, cc, maxf(2.2, 3.0 * s))
			if sz != TINY:
				for q in _corner_pts(r, o, rad):
					_diamond(ci, q, 3.2 * s, 3.2 * s, cc, Color(DB.PAL.ink, 0.8))
			if top_free and sz != TINY:
				var base := Vector2(tx, r.position.y + (11.0 if sz == MINI else 8.0 * s))
				_flame(ci, base, 16.0 * s, 11.0 * s, tc.lightened(0.45), Color(DB.PAL.ink, 0.85))
		SIN:
			_ring(ci, r, 0.0, rad, Color(GOLD_FOIL, 0.95), 1)            # 금박 —— 밝은 바깥 선 · 어두운 안쪽 선 · 안쪽 가는 금선 (겹테)
			_ring(ci, r, maxf(1.0, bw - 0.5), rad, Color(tc.darkened(0.5), 0.95), 1)
			if sz != TINY:
				_ring(ci, r, bw + 1.5 * s, rad, Color(tc.lightened(0.3), 0.9), 1)
				_ring(ci, r, bw + 2.5 * s, rad, Color(tc, 0.22), int(maxf(2.0, 3.0 * s)))      # 따뜻한 안쪽 빛
			var cc := GOLD_FOIL
			_corners(ci, r, o, rad, (16.0 if sz != TINY else 6.0) * s, cc, maxf(2.4, 3.2 * s), sz != TINY)
			if sz != TINY:
				for q in _corner_pts(r, o, rad):
					_diamond(ci, q, 3.8 * s, 3.8 * s, cc, Color(tc.darkened(0.6), 0.9))
				var my := r.get_center().y
				for x in [r.position.x + o, r.end.x - o]:      # 좌우 가운데 마름모
					_diamond(ci, Vector2(x, my), 2.6 * s, 4.0 * s, cc, Color(tc.darkened(0.6), 0.9))
				_diamond(ci, Vector2(r.get_center().x, r.end.y - o), 5.0 * s, 3.0 * s, cc, Color(tc.darkened(0.6), 0.9))     # 아래 가운데
			if top_free and sz != TINY:
				var base := Vector2(tx, r.position.y + (13.0 if sz == MINI else 10.0 * s))
				_crown(ci, base, 24.0 * s, 13.0 * s, tc.lightened(0.15), Color(tc.darkened(0.65), 0.95))
			elif top_free and r.size.x >= 44.0:
				_crown(ci, Vector2(tx, r.position.y + 5.0), 10.0, 5.5, tc.lightened(0.15), Color(tc.darkened(0.65), 0.95))


## 둥근 모서리 선 —— r 을 inset 만큼 줄인 사각형의 테두리를 wd(정수) 두께로 안쪽에 그린다
static func _ring(ci: CanvasItem, r: Rect2, inset: float, rad: float, col: Color, wd: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = col
	sb.set_border_width_all(maxi(1, wd))
	sb.set_corner_radius_all(maxi(0, int(rad - inset)))
	ci.draw_style_box(sb, r.grow(-inset))


## 둥근 모서리 호의 45도 점 네 개 (왼쪽 위부터 시계 방향) —— 모서리 마름모 자리
static func _corner_pts(r: Rect2, o: float, rad: float) -> Array:
	var d := (rad - o) * 0.7071
	return [Vector2(r.position.x + rad - d, r.position.y + rad - d), Vector2(r.end.x - rad + d, r.position.y + rad - d),
		Vector2(r.end.x - rad + d, r.end.y - rad + d), Vector2(r.position.x + rad - d, r.end.y - rad + d)]


## 네 모서리 꺾쇠 —— 테두리 띠 가운데 선을 따라 호 + 양쪽으로 ext 만큼 뻗은 선. dots 면 끝에 작은 구슬
static func _corners(ci: CanvasItem, r: Rect2, o: float, rad: float, ext: float, col: Color, wd: float, dots := false, under := Color(0, 0, 0, 0.55)) -> void:
	var ar := maxf(0.5, rad - o)
	var x0 := r.position.x + o
	var y0 := r.position.y + o
	var x1 := r.end.x - o
	var y1 := r.end.y - o
	var specs := [
		[Vector2(x0 + ar, y0 + ar), PI, 1.5 * PI, Vector2(1, 1)],
		[Vector2(x1 - ar, y0 + ar), 1.5 * PI, TAU, Vector2(-1, 1)],
		[Vector2(x1 - ar, y1 - ar), 0.0, 0.5 * PI, Vector2(-1, -1)],
		[Vector2(x0 + ar, y1 - ar), 0.5 * PI, PI, Vector2(1, -1)]]
	for pass_i in 2:      # 먼저 어두운 밑선(입체감 · 테두리와 같은 색일 때도 보이게), 그 위에 본 색
		var cl := under if pass_i == 0 else col
		var w2 := wd + (1.6 if pass_i == 0 else 0.0)
		var e2 := ext + (0.8 if pass_i == 0 else 0.0)
		if cl.a <= 0.0:
			continue
		for sp in specs:
			var c: Vector2 = sp[0]
			var sg: Vector2 = sp[3]
			ci.draw_arc(c, ar, sp[1], sp[2], 8, cl, w2, true)
			var ey := c.y - sg.y * ar          # 가로 변의 y (위쪽 모서리면 y0, 아래면 y1)
			var ex := c.x - sg.x * ar          # 세로 변의 x
			ci.draw_line(Vector2(c.x, ey), Vector2(c.x + sg.x * e2, ey), cl, w2, true)
			ci.draw_line(Vector2(ex, c.y), Vector2(ex, c.y + sg.y * e2), cl, w2, true)
			if dots:
				ci.draw_circle(Vector2(c.x + sg.x * (ext + wd), ey), wd * (0.7 if pass_i == 0 else 0.55), cl)
				ci.draw_circle(Vector2(ex, c.y + sg.y * (ext + wd)), wd * (0.7 if pass_i == 0 else 0.55), cl)


static func _diamond(ci: CanvasItem, c: Vector2, rx: float, ry: float, fill: Color, line: Color) -> void:
	var p := PackedVector2Array([c + Vector2(0, -ry), c + Vector2(rx, 0), c + Vector2(0, ry), c + Vector2(-rx, 0)])
	ci.draw_colored_polygon(p, fill)
	p.append(p[0])
	ci.draw_polyline(p, line, 1.0, true)


## 불꽃 —— 밑변 가운데 base, 세 갈래 (가운데가 가장 높다)
static func _flame(ci: CanvasItem, base: Vector2, w: float, h: float, fill: Color, line: Color) -> void:
	var hw := w * 0.5
	var p := PackedVector2Array([base + Vector2(-hw, 0), base + Vector2(-hw * 0.9, -h * 0.55), base + Vector2(-hw * 0.38, -h * 0.28), base + Vector2(0, -h),
		base + Vector2(hw * 0.38, -h * 0.28), base + Vector2(hw * 0.9, -h * 0.55), base + Vector2(hw, 0)])
	ci.draw_colored_polygon(p, fill)
	p.append(p[0])
	ci.draw_polyline(p, line, 1.0, true)
	ci.draw_colored_polygon(PackedVector2Array([base + Vector2(-hw * 0.28, 0), base + Vector2(0, -h * 0.55), base + Vector2(hw * 0.28, 0)]), Color(1, 0.95, 0.75, 0.9))


## 왕관 —— 밑변 가운데 base, 뾰족 셋 + 가운데 붉은 보석
static func _crown(ci: CanvasItem, base: Vector2, w: float, h: float, fill: Color, line: Color) -> void:
	var hw := w * 0.5
	var p := PackedVector2Array([base + Vector2(-hw, 0), base + Vector2(-hw, -h * 0.62), base + Vector2(-hw * 0.5, -h * 0.28), base + Vector2(0, -h),
		base + Vector2(hw * 0.5, -h * 0.28), base + Vector2(hw, -h * 0.62), base + Vector2(hw, 0)])
	ci.draw_colored_polygon(p, fill)
	p.append(p[0])
	ci.draw_polyline(p, line, 1.0, true)
	ci.draw_line(base + Vector2(-hw, -h * 0.16), base + Vector2(hw, -h * 0.16), line, 1.0)
	ci.draw_circle(base + Vector2(0, -h * 0.5), maxf(1.4, h * 0.17), GEM_RED)


## 신화 덧칸 —— 타일 위에 얹혀 지나가는 빛줄기만 그린다. 쉬는 동안은 다시 그리지 않고, 화면 밖(스크롤에 가려진 것 포함)이면 시간만 흐른다.
## big 이면(큰 카드) 반짝이는 점과 테를 도는 빛도 (큰 카드는 몇 장 안 된다). 빛이 도는 영역은 region(콜백 —— 이 덧칸 크기를 받아 영역을 돌려준다)
class Shimmer extends Control:
	const PERIOD := 4.2         # 한 번 지나가고 쉬는 주기(초)
	const SWEEP := 1.0          # 지나가는 시간
	var region_cb := Callable()
	var big := false
	var seed_k := ""
	var _t := 0.0
	var _phase := 0.0
	var _scroll: Control = null
	var _scroll_found := false
	var _live := false           # 이번 프레임에 그려야 하나 (지나가는 중이거나 big)
	var _acc := 0.0
	var _chk := 0.0
	var _vis := false

	func _init(k := "", is_big := false, cb := Callable()) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		seed_k = k
		big = is_big
		region_cb = cb
		_phase = float(hash(k) % 1000) / 1000.0 * PERIOD      # 타일마다 어긋나게 —— 격자 전체가 한꺼번에 번쩍이지 않는다

	func _on_screen() -> bool:
		if not _scroll_found:
			_scroll_found = true
			var p := get_parent()
			while p != null:
				if p is ScrollContainer:
					_scroll = p
					break
				p = p.get_parent()
		var gr := get_global_rect()
		if _scroll != null and is_instance_valid(_scroll):
			return gr.intersects(_scroll.get_global_rect())
		return gr.intersects(get_viewport_rect())

	func _process(dt: float) -> void:
		_chk -= dt
		if _chk <= 0.0:      # 보이는지(화면 · 스크롤 안) 확인은 0.2~0.3초마다만 —— 격자 칸이 많아도 프레임마다 도는 일은 거의 없다
			_chk = 0.2 + float(_phase) * 0.02
			_vis = is_visible_in_tree() and _on_screen()
		if not _vis:
			return
		_t += dt
		var inb := fmod(_t + _phase, PERIOD) < SWEEP
		if big:
			_acc += dt
			if _acc >= 1.0 / 24.0:      # 큰 카드도 24프레임이면 충분 (느린 빛)
				_acc = 0.0
				queue_redraw()
		elif inb or _live:
			_live = inb
			queue_redraw()

	func _draw() -> void:
		if not region_cb.is_valid():
			return
		var rg: Rect2 = region_cb.call(size)
		if rg.size.x < 4.0 or rg.size.y < 4.0:
			return
		var tin := fmod(_t + _phase, PERIOD)
		if tin < SWEEP:
			var p := tin / SWEEP
			p = p * p * (3.0 - 2.0 * p)
			var slant := 0.55
			var bwid := rg.size.x * 0.30
			var travel := rg.size.x + bwid * 2.0 + rg.size.y * slant
			var cx := rg.position.x - bwid + travel * p      # 띠 가운데(아래쪽 y 에서의 x)
			var hb := bwid * 0.5
			# 두 쪽(왼쪽 0 → 가운데 진함 → 오른쪽 0)을 따로 잘라 정점 색으로 부드럽게 —— 다각형 교차 라이브러리 대신 직접 자른다(가볍게)
			for side in [-1.0, 1.0]:
				var d0: float = 0.0 if side > 0.0 else -hb
				var d1: float = hb if side > 0.0 else 0.0
				var quad := PackedVector2Array([
					Vector2(cx + d0, rg.end.y), Vector2(cx + d1, rg.end.y),
					Vector2(cx + d1 + rg.size.y * slant, rg.position.y), Vector2(cx + d0 + rg.size.y * slant, rg.position.y)])
				var poly := _clip(quad, rg)
				if poly.size() < 3:
					continue
				var cols := PackedColorArray()
				for v in poly:
					var d: float = v.x - slant * (rg.end.y - v.y) - cx
					cols.append(Color(1.0, 0.96, 0.78, 0.34 * clampf(1.0 - absf(d) / hb, 0.0, 1.0)))
				draw_polygon(poly, cols)
		if big:
			var h := hash(seed_k)
			for i in 6:      # 반짝이는 점 (예전 Art.draw_tier_fx 의 것을 이쪽으로 —— 큰 카드만 움직인다)
				var px := rg.position.x + float((h >> (i * 4)) & 15) / 15.0 * rg.size.x
				var py := rg.position.y + float((h >> (i * 4 + 2)) & 15) / 15.0 * rg.size.y * 0.8
				var a2 := 0.5 + 0.5 * sin(_t * 3.0 + i * 1.7)
				var s := (2.0 + 3.0 * a2) * (size.x / 150.0)
				var col := Color("#ffe9a8", a2 * 0.9)
				draw_line(Vector2(px - s, py), Vector2(px + s, py), col, 1.2)
				draw_line(Vector2(px, py - s), Vector2(px, py + s), col, 1.2)
			var per := (size.x + size.y) * 2.0       # 테를 따라 도는 빛
			var pt := _along(fmod(_t * 120.0 * (size.x / 150.0), per), 2.0)
			draw_circle(pt, 3.2 * size.x / 150.0, Color(1, 0.97, 0.85, 0.9))
			draw_circle(pt, 6.0 * size.x / 150.0, Color(1, 0.9, 0.6, 0.3))

	## 볼록 다각형을 사각형으로 자른다 (Sutherland–Hodgman —— 네 변을 차례로)
	static func _clip(poly: PackedVector2Array, r: Rect2) -> PackedVector2Array:
		var out := poly
		for edge in 4:
			var inp := out
			out = PackedVector2Array()
			if inp.is_empty():
				break
			var prev := inp[inp.size() - 1]
			for cur in inp:
				var cin := _inside(cur, r, edge)
				var pin := _inside(prev, r, edge)
				if cin != pin:
					out.append(_cut(prev, cur, r, edge))
				if cin:
					out.append(cur)
				prev = cur
		return out

	static func _inside(v: Vector2, r: Rect2, edge: int) -> bool:
		match edge:
			0: return v.x >= r.position.x
			1: return v.x <= r.end.x
			2: return v.y >= r.position.y
			_: return v.y <= r.end.y

	static func _cut(a: Vector2, b: Vector2, r: Rect2, edge: int) -> Vector2:
		match edge:
			0: return a + (b - a) * ((r.position.x - a.x) / (b.x - a.x))
			1: return a + (b - a) * ((r.end.x - a.x) / (b.x - a.x))
			2: return a + (b - a) * ((r.position.y - a.y) / (b.y - a.y))
			_: return a + (b - a) * ((r.end.y - a.y) / (b.y - a.y))

	## 테두리를 따라 거리 d 만큼 간 점 (왼쪽 위에서 시계 방향)
	func _along(d: float, o: float) -> Vector2:
		var w := size.x - o * 2
		var h := size.y - o * 2
		if d < w:
			return Vector2(o + d, o)
		d -= w
		if d < h:
			return Vector2(o + w, o + d)
		d -= h
		if d < w:
			return Vector2(o + w - d, o + h)
		d -= w
		return Vector2(o, o + h - minf(d, h))


## 신화면 타일에 빛줄기 덧칸을 붙인다 (이미 있으면 그대로). cb 는 덧칸 크기 → 빛이 도는 영역
static func attach_shimmer(host: Control, k: String, cb: Callable, big := false) -> void:
	var old := host.get_node_or_null("Shimmer")
	if old != null:
		old.queue_free()
	if rank(k) != SIN:
		return
	var sh := Shimmer.new(k, big, cb)
	sh.name = "Shimmer"
	host.add_child(sh)
