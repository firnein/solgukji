extends Control
## 한마디 구름 말풍선 (11/12 사용자: "한마디 텍스트의 위치도 이모티콘 구름 메시지로") —— 받은 한마디(글 · 이모티콘 모두)를 구름 모양 말풍선으로 잠깐.
## 보낸 사람의 유저 칸(전투 탭의 자리 줄 · 기록 탭의 군웅 칸 · 대기실 줄 —— Online.anchor_of)이 화면에 보이면 그 칸 위에 꼬리를 그 이름 쪽으로 내려 붙이고,
## 안 보이면(다른 탭 · 전투 재생 중 · 스크롤 밖) 화면 위쪽 1/3 아래(옛 이모티콘 팝업 자리, 긴급 띠 아래) 가운데 줄에 이름과 함께 띄운다.
## 같은 사람의 새 말풍선은 옛 것을 바꾼다. 입력은 막지 않는다. z_index 44 —— 시트 · 대기실 · 전투판 위, 긴급 띠(45) 아래.
## 이전(11/9~11/10): 글은 알림 줄(전투 중이면 전장 위 줄), 이모티콘은 위쪽 가운데 카드(EmotePop) —— 이 층 하나로 합쳤다.
## class_name 은 만들지 않는다(낡은 .godot 캐시에서 'not declared') —— GameScreen 이 preload 로 쓴다.

const LIFE_TEXT := 3.2
const LIFE_EMOTE := 2.0
const MAXN := 6
const TOP := 0.335              # 떠 있는 줄의 높이 (화면 높이 비율) —— 긴급 띠 아래 끝 ≈ 31.5% 를 피한다
const FS := 15                  # 글 크기
const NAME_FS := 12

var items := []                 # [{who, text, k, anchor, t, life}]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 44


## who = 보낸 사람 · text = 한마디 글("" 이면 이모티콘) · k = 이모티콘 번호(Icons.EMOTES, 글이면 -1) · anchor = 그 사람의 유저 칸(없으면 null)
func add(who: String, text: String, k: int, anchor: Control = null) -> void:
	if text == "" and (k < 0 or k >= Icons.EMOTES.size()):
		return
	items = items.filter(func(it): return it.who != who)
	items.append({"who": who, "text": text, "k": k, "anchor": weakref(anchor) if anchor != null else null, "t": 0.0,
		"life": LIFE_TEXT if text != "" else LIFE_EMOTE})
	while items.size() > MAXN:
		items.pop_front()
	queue_redraw()


func _process(dt: float) -> void:
	global_position = Vector2.ZERO      # 부모(GameScreen)가 크기를 갖지 않아 앵커가 듣지 않는다 (UrgentBand 와 같다)
	size = get_viewport_rect().size
	if items.is_empty():
		return
	for it in items:
		it.t += dt
	items = items.filter(func(it): return it.t < it.life)
	queue_redraw()


## 그 칸이 지금 화면에 보이나 —— 보이면 칸의 화면 사각형, 아니면 빈 사각형
func _anchor_rect(it: Dictionary) -> Rect2:
	if it.anchor == null:
		return Rect2()
	var a = it.anchor.get_ref()
	if a == null or not is_instance_valid(a) or not (a as Control).is_visible_in_tree():
		return Rect2()
	var r: Rect2 = (a as Control).get_global_rect()
	var clip := _clip_rect(a)
	if not clip.has_area() or not clip.intersects(r) or r.position.y < clip.position.y - 4.0 or r.position.y > clip.end.y - 16.0:
		return Rect2()
	return r


## 칸을 감싼 스크롤 상자(있으면)와 화면의 겹친 부분 —— 스크롤 밖으로 나간 칸에는 붙이지 않는다
func _clip_rect(a: Control) -> Rect2:
	var vr := Rect2(Vector2.ZERO, size)
	var p := a.get_parent()
	while p != null:
		if p is ScrollContainer:
			return vr.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return vr


func _body_size(it: Dictionary, with_name: bool) -> Vector2:
	var f: Font = DB.font_body
	if it.text == "":
		return Vector2(66.0, 58.0 + (16.0 if with_name else 0.0))
	var tw := f.get_string_size(_fit_text(it.text), HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
	var nw := f.get_string_size(it.who, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FS).x if with_name else 0.0
	return Vector2(clampf(maxf(tw, nw) + 30.0, 70.0, size.x * 0.72), 38.0 + (16.0 if with_name else 0.0))


func _fit_text(tx: String) -> String:
	var f: Font = DB.font_body
	var lim := size.x * 0.72 - 30.0
	var out := tx
	while out.length() > 2 and f.get_string_size(out, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x > lim:
		out = out.substr(0, out.length() - 2) + "…"
	return out


func _draw() -> void:
	var floating := []
	for it in items:
		var ar := _anchor_rect(it)
		if ar.has_area():
			var bs := _body_size(it, false)
			# 칸의 이름 쪽(왼쪽) 위 —— 꼬리는 아래로 이름을 가리킨다. 위가 모자라면 칸 안 오른쪽으로
			var pos := Vector2(ar.position.x + 34.0, ar.position.y - bs.y + 6.0)
			var tip := Vector2(ar.position.x + 26.0, ar.position.y + 12.0)
			if pos.y < 4.0:
				pos = Vector2(ar.end.x - bs.x - 8.0, ar.position.y + (minf(ar.size.y, 64.0) - bs.y) / 2.0)
				tip = Vector2(pos.x - 10.0, pos.y + bs.y * 0.6)
			pos.x = clampf(pos.x, 6.0, size.x - bs.x - 6.0)
			_cloud(it, Rect2(pos, bs), tip, false)
		else:
			floating.append(it)
	if floating.is_empty():
		return
	var sizes := floating.map(func(it): return _body_size(it, true))
	var total := 0.0
	for s in sizes:
		total += (s as Vector2).x + 10.0
	var x := maxf(6.0, (size.x - total + 10.0) / 2.0)
	var y := size.y * TOP
	for i in floating.size():
		var bs: Vector2 = sizes[i]
		if x + bs.x > size.x - 6.0 and x > 6.0:      # 넘치면 다음 줄
			x = 6.0
			y += 92.0
		_cloud(floating[i], Rect2(Vector2(x, y), bs), Vector2(x + bs.x * 0.3, y + bs.y + 16.0), true)
		x += bs.x + 10.0


## 구름 하나 —— 둥근 면 + 위아래 둘레에 작은 원들(뭉게) + 꼬리 쪽으로 작아지는 원 둘. 그림자 → 면 → 글/기호 순
func _cloud(it: Dictionary, r: Rect2, tip: Vector2, with_name: bool) -> void:
	var t: float = it.t
	var pop := clampf(t / 0.16, 0.0, 1.0)
	var sc := 0.6 + 0.4 * (1.0 + 2.2 * pow(pop - 1.0, 3) + 1.2 * pow(pop - 1.0, 2))      # 튀어나오는 back-out
	var a := clampf((it.life - t) / 0.35, 0.0, 1.0) * clampf(t / 0.08, 0.0, 1.0)
	var c := r.get_center()
	draw_set_transform(c - c * sc + Vector2(0, -6.0 * clampf(t / it.life, 0.0, 1.0)), 0.0, Vector2(sc, sc))
	var body: Color = Color(DB.PAL.paper, 0.97 * a)
	var shade := Color(0, 0, 0, 0.35 * a)
	for pass_i in 2:
		var off := Vector2(2, 3) if pass_i == 0 else Vector2.ZERO
		var col: Color = shade if pass_i == 0 else body
		_blob(r, off, col)
		# 꼬리 —— 몸에서 tip 쪽으로 작아지는 원 두 개 (생각 구름)
		var from := Vector2(clampf(tip.x, r.position.x + 12.0, r.end.x - 12.0), r.end.y if tip.y > r.end.y else (r.position.y if tip.y < r.position.y else c.y))
		if tip.x < r.position.x:
			from = Vector2(r.position.x + 4.0, clampf(tip.y, r.position.y + 8.0, r.end.y - 8.0))
		draw_circle(from.lerp(tip, 0.45) + off, 5.0, col)
		draw_circle(from.lerp(tip, 0.85) + off, 3.0, col)
	var ink: Color = Color(DB.PAL.ink, a)
	var f: Font = DB.font_body
	var y0 := r.position.y
	if with_name:
		var nm: String = it.who
		var nw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FS).x
		while nm.length() > 2 and nw > r.size.x - 16.0:
			nm = nm.substr(0, nm.length() - 2) + "…"
			nw = f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FS).x
		draw_string(f, Vector2(c.x - nw / 2.0, y0 + 15.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FS, Color(DB.PAL.seal, a))
		y0 += 14.0
	if it.text == "":
		Icons.draw(self, Icons.EMOTES[it.k], Vector2(c.x, y0 + 29.0), 40.0, Color(DB.PAL.ink, a))
	else:
		var tx := _fit_text(it.text)
		var tw := f.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		draw_string(f, Vector2(c.x - tw / 2.0, y0 + 25.0), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, ink)
	draw_set_transform(Vector2.ZERO)


## 구름 몸 —— 둥근 사각형 면 + 위 · 아래 둘레의 뭉게(원)
func _blob(r: Rect2, off: Vector2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(minf(r.size.y / 2.0, 18.0)))
	draw_style_box(sb, Rect2(r.position + off, r.size))
	var n := maxi(2, int(r.size.x / 20.0))
	for i in n:
		var px := r.position.x + 16.0 + (r.size.x - 32.0) * float(i) / float(n - 1)
		var rr := 6.5 + 1.5 * float((i * 7) % 3)
		draw_circle(Vector2(px, r.position.y + 4.0) + off, rr, col)
		if i % 2 == 1:
			draw_circle(Vector2(px, r.end.y - 4.0) + off, rr - 1.5, col)
