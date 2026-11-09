class_name FormationView
extends Control
## 전투 탭의 내 진영 미리 보기 (11/4 사용자: 남는 공간에 지금 배치된 병종을 그린다) ——
## 진형 칸 자리대로 장수 얼굴 메달 · 이름. 위쪽이 적 방향.
## 11/7 사용자: 군단 효과(진형 · 단체 특기 · 위세 · 기인)는 이 그림 안에 그리지 않는다 —— 효과가 많은 덱(11줄)에서 표가 그림을 다 먹어
##   메달 줄이 서로 겹쳤고, RichTextLabel [table] 은 오른쪽이 잘렸다. 대신 effects_box() 가 칩 흐름(HFlowContainer, 접으면 몇 개만 + '+N')
##   · 펼치면 컨테이너 2열 표를 만들어 전투 탭이 그림 위에 따로 놓는다. 어떤 덱이든 줄바꿈될 뿐 무너지지 않는다.

const COLS := 5      # 11/6 진형 4행 5열
const FX_SHOW := 6   # 접었을 때 보이는 효과 칩 수 (540 폭에서 두 줄쯤)
var cards: Array = []        # 9칸 카드 id (null 은 빈칸)
var form := ""
var t := 0.0
var _sprites := {}
var _mat: ShaderMaterial
var on_medal := Callable()     # 11/5 사용자: 메달을 누르면 그 장수 상세 —— 카드 id 를 넘긴다

const SHADER := """
shader_type canvas_item;
uniform vec4 team : source_color = vec4(0.25, 0.45, 0.9, 1.0);
void fragment() {
	// COLOR = 텍스처색 × 정점색 (그림 없는 땅 · 선은 정점색 그대로) —— 그림의 자홍(진영색 자리)만 진영색으로
	vec4 c = COLOR;
	float m = smoothstep(0.18, 0.32, min(c.r, c.b) - c.g) * step(0.3, c.b);
	COLOR.rgb = mix(c.rgb, team.rgb * (0.6 + 0.6 * c.b), m);
}
"""


func setup(board: Array, form_key: String) -> FormationView:
	cards = board
	form = form_key
	custom_minimum_size.y = min_h()
	return self


## 메달 줄이 겹치지 않는 높이 —— 줄마다 92(메달 · 이름 · 다음 줄 우대 표) + 위 '▲ 적' 표시 여백 (효과 표는 밖에 있으니 늘 같은 높이)
func min_h() -> float:
	return _rows() * 92.0 + 36.0


func _gui_input(e: InputEvent) -> void:
	if not on_medal.is_valid() or not (e is InputEventMouseButton) or e.button_index != MOUSE_BUTTON_LEFT or e.pressed:
		return
	for m in layout():
		var r := clampf(float(m[2]) * 0.3, 18.0, 34.0)
		if e.position.distance_to(m[0] + Vector2(0, -8.0)) <= r + 10.0:
			UI.buzz()
			on_medal.call(m[1])
			accept_event()
			return


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS if on_medal.is_valid() else Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("team", Color("#4f8be0"))
	material = _mat
	var ov := Medals.new()
	ov.fv = self
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.use_parent_material = false
	add_child(ov)


# ───────── 군단 효과 (11/7) ─────────

## 진영이 받는 효과 줄 —— 진형 우대가 맨 앞, 그 뒤 단체 특기 · 위세 · 기인 (team_buffs 순서).
## [{kind, name, text(자세히), brief(칩 한 토막), who, k(부여 장수, 진형은 ""), col}]
static func effect_rows(board: Array, form_key: String) -> Array:
	var rows := []
	var bn = DB.D.FORMBOON.get(form_key)
	if bn != null and DB.FORM.has(form_key):
		var who := []
		for k in board:
			if k != null and bn.tags.has(DB.C[k].tag):
				who.append(DB.person(k) if DB.C[k].tier > 2 else DB.C[k].name)
		if not who.is_empty():
			var stat: String = DB.D.STATNM.get(bn.stat, "스킬 발동")
			var val := "+%d%%" % roundi(float(bn.v) * 100)
			rows.append({"kind": "진형", "name": DB.FORM[form_key].n, "text": "%s %s %s" % [" · ".join(bn.tags), stat, val],
				"brief": "%s %s" % [stat, val], "who": ", ".join(who), "k": "", "col": DB.PAL.gold})
	for b in team_buffs(board):
		rows.append({"kind": b.kind, "name": b.name, "text": b.text, "brief": _brief(b.text), "who": b.who, "k": b.k, "col": DB.tier_color(b.k)})
	return rows


## 칩에 넣을 한 토막 —— 첫 항목만 ("아군 방어 +5% / 병력 70% 아래 …" → "아군 방어 +5%")
static func _brief(text: String) -> String:
	var s := text.get_slice(" / ", 0).get_slice(" · ", 0).strip_edges()
	return s if s != "" else text


## 군단 효과 상자 —— 머리줄(개수 · 펼치기/접기) + 접으면 칩 흐름(FX_SHOW 개 + '+N 더'), 펼치면 장수 | 효과 2열 표.
## on_toggle 은 펼침 상태를 바꾸는 쪽(전투 탭 _open), on_card 는 칩 · 줄을 누르면 부여 장수 상세. 효과가 없으면 null
static func effects_box(board: Array, form_key: String, open: bool, on_toggle: Callable, on_card: Callable) -> Control:
	var rows := effect_rows(board, form_key)
	if rows.is_empty():
		return null
	var P := DB.PAL
	var v := UI.vbox(6)
	var head := UI.hbox(8)
	var title := UI.lbl("군단 효과 %d" % rows.size(), 14, P.bamboo, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	var tg := Button.new()
	tg.text = "접기 ▴" if open else "펼치기 ▾"
	tg.custom_minimum_size = Vector2(0, 28)
	tg.add_theme_font_size_override("font_size", 12)
	tg.add_theme_color_override("font_color", P.bamboo)
	tg.add_theme_stylebox_override("normal", UI.flat(Color(0, 0, 0, 0), Color(P.paper, 0.16), 1, UI.R, 0))
	tg.add_theme_stylebox_override("hover", UI.flat(P.ink3, Color(P.paper, 0.28), 1, UI.R, 0))
	tg.add_theme_stylebox_override("pressed", UI.flat(P.ink4, P.gold, 1, UI.R, 0))
	_pad(tg, 10, 3)
	tg.pressed.connect(func():
		UI.buzz()
		on_toggle.call())
	head.add_child(tg)
	v.add_child(head)
	if open:
		var tbl := UI.vbox(0)
		for i in rows.size():
			if i > 0:
				tbl.add_child(UI.hair())      # 11/9 줄 사이는 구분선
			tbl.add_child(_row(rows[i], on_card))
		v.add_child(tbl)
	else:
		var flow := UI.flow(6)
		var n_show := rows.size() if rows.size() <= FX_SHOW + 1 else FX_SHOW      # 하나만 남으면 '+1 더' 대신 그냥 보여 준다
		for i in n_show:
			flow.add_child(_chip(rows[i], on_card))
		if rows.size() > n_show:
			var more := Button.new()
			more.text = "+%d 더" % (rows.size() - n_show)
			more.custom_minimum_size = Vector2(0, 28)
			more.add_theme_font_size_override("font_size", 12)
			more.add_theme_color_override("font_color", P.bamboo)
			more.add_theme_stylebox_override("normal", UI.flat(P.ink3, Color(0, 0, 0, 0), 0, UI.R, 0))
			more.add_theme_stylebox_override("hover", UI.flat(P.ink4, Color(0, 0, 0, 0), 0, UI.R, 0))
			more.add_theme_stylebox_override("pressed", UI.flat(P.ink4, P.gold, 1, UI.R, 0))
			_pad(more, 10, 3)
			more.pressed.connect(func():
				UI.buzz()
				on_toggle.call())
			flow.add_child(more)
		v.add_child(flow)
	return UI.panel(v, 10)


## 효과 칩 —— 『이름』 한 토막. 11/9: 부여 장수 등급색 테두리 칩 줄(무지개)을 걷고 한 가지 먹색 칩 + 종이색 글 (진형만 금 글자) · 길면 … (한 칩은 폭 230 까지)
static func _chip(r: Dictionary, on_card: Callable) -> Button:
	var P := DB.PAL
	var b := Button.new()
	var txt: String = "%s『%s』 %s" % ["진형" if r.kind == "진형" else "", r.name, r.brief]
	b.text = txt
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var tw: float = DB.font_body.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	b.custom_minimum_size = Vector2(minf(tw + 22.0, 230.0), 28)
	b.add_theme_font_size_override("font_size", 12)
	var fc: Color = P.gold if r.kind == "진형" else P.paper
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
	b.add_theme_stylebox_override("normal", UI.flat(P.ink3, Color(0, 0, 0, 0), 0, UI.R, 0))
	b.add_theme_stylebox_override("hover", UI.flat(P.ink4, Color(0, 0, 0, 0), 0, UI.R, 0))
	b.add_theme_stylebox_override("pressed", UI.flat(P.ink4, P.gold, 1, UI.R, 0))
	_pad(b, 10, 3)
	var k: String = r.k
	b.pressed.connect(func():
		if k != "" and on_card.is_valid():
			UI.buzz()
			on_card.call(k))
	return b


## 펼친 표의 한 줄 —— 왼쪽 부여 장수(등급색 바탕, 고정 폭) · 오른쪽 『이름』 효과 (남는 폭, 줄바꿈)
static func _row(r: Dictionary, on_card: Callable) -> Control:
	var col: Color = r.col
	var h := UI.hbox(0)
	var left := PanelContainer.new()
	left.custom_minimum_size.x = 118
	left.add_theme_stylebox_override("panel", UI.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0))
	_pad(left, 2, 6)
	var who := UI.lbl(r.who, 12, DB.PAL.gold if r.kind == "진형" else col.lightened(0.3))      # 부여 장수는 등급색 글자 (바탕 덩어리는 걷음)
	who.add_theme_font_override("font", DB.font_bold)
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(who)
	h.add_child(left)
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel", UI.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0))
	_pad(right, 6, 6)
	var bb: String
	if r.kind == "진형":
		bb = "[color=#E8C25A][b]진형『%s』[/b][/color] [color=#8FD4C2]%s[/color]" % [r.name, r.text]
	else:
		bb = "[color=#E8D9B5]『%s』[/color] [color=#8FD4C2]%s[/color]%s" % [r.name, r.text, "" if r.kind == "단체" else " [color=#8D7B5C](%s)[/color]" % r.kind]
	var txt := UI.rich(bb, 12)
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(txt)
	h.add_child(right)
	if r.k != "" and on_card.is_valid():
		var k: String = r.k
		for p in [left, right]:
			var pc: Control = p
			pc.gui_input.connect(func(e: InputEvent):
				# 칸 안에서 뗐을 때만 —— 끌어 내리면 TouchScroll 이 화면 밖 '떼기'를 넣어 취소한다
				if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed and Rect2(Vector2.ZERO, pc.size).has_point(e.position):
					UI.buzz()
					on_card.call(k))
	return h


static func _pad(c: Control, x: int, y: int) -> void:
	for st in ["normal", "hover", "pressed", "panel"]:
		if c.has_theme_stylebox_override(st):
			var sb: StyleBoxFlat = c.get_theme_stylebox(st)
			sb.content_margin_left = x
			sb.content_margin_right = x
			sb.content_margin_top = y
			sb.content_margin_bottom = y


## 진영 전체가 받는 버프 —— 단체 특기(같은 이름은 센 것 + 두 번째 절반, 전투와 같다) · 위세 · 기인.
## [{kind, name, text, who, col, k}] (11/5 사용자: 전투 탭 위에 버프 목록 · 수치 · 부여 장수명)
static func team_buffs(board: Array) -> Array:
	var ks: Array = board.filter(func(x): return x != null)
	var groups := {}         # 이름 -> [[배율, 카드], …]
	var order := []
	for k in ks:
		var ps = DB.passives_of(k)
		if ps == null:
			continue
		for g in ps.groups:
			if g.scope != "foe" and not ks.any(func(t): return DB.passive_hits(g, k, t)):
				continue
			if not groups.has(g.name):
				groups[g.name] = []
				order.append(g.name)
			groups[g.name].append([float(g.scale), k])
	var out := []
	for nm in order:
		var l: Array = groups[nm]
		l.sort_custom(func(a, b): return a[0] > b[0])
		var total: float = l[0][0] + (l[1][0] * 0.5 if l.size() > 1 else 0.0)
		var who := []
		for e in l.slice(0, 2):
			who.append(DB.person(e[1]) if DB.C[e[1]].tier > 2 else DB.C[e[1]].name)
		var k0: String = l[0][1]
		var txt := DB.mods_text(DB.group_def(nm).m, total, DB.C[l[0][1]].tier)
		if txt == "":
			txt = str(DB.group_def(nm).get("d", "")).get_slice(" —— ", 0)
		out.append({"kind": "적에게" if DB.group_def(nm).get("scope", "") == "foe" else "단체", "name": nm, "text": txt, "who": " · ".join(who), "col": DB.TRAIT_COL["단체"], "k": k0})
	for k in ks:
		if DB.AURA.has(k):
			out.append({"kind": "기인" if DB.is_kiin(k) else "위세", "name": DB.AURA[k].n, "text": DB.aura_effect(k), "who": DB.person(k), "col": DB.tier_color(k), "k": k})
	return out


func _sprite(tag: String) -> Texture2D:
	if not _sprites.has(tag):
		_sprites[tag] = DB._load_portrait("res://assets/troops_sprite/" + tag)
	return _sprites[tag]


func _process(dt: float) -> void:
	if is_visible_in_tree():
		t += dt
		queue_redraw()
		for ch in get_children():
			ch.queue_redraw()


func _draw() -> void:
	var sz := size
	if sz.x < 10 or sz.y < 10:
		return
	# 땅 —— 어두운 풀빛 그라데이션 + 옅은 줄
	var top := Color("#1d2a22")
	var bot := Color("#121a16")
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)]), PackedColorArray([top, top, bot, bot]))
	for i in 6:
		var y := sz.y * (i + 0.5) / 6.0
		draw_line(Vector2(0, y), Vector2(sz.x, y), Color(1, 1, 1, 0.025), 1.0)
	var y0 := _rows_top()
	draw_string(DB.font_bold, Vector2(0, y0 - 22), "▲ 적", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 11, Color(DB.PAL.seal, 0.8))
	pass      # 11/4 사용자: 병졸 그림은 그리지 않고 장수 원형 얼굴만 (Medals)


## 칸마다 [중심, 카드, 칸 크기, 번호] —— 뒤 줄부터 (앞 줄이 위에 겹치게)
func layout() -> Array:
	var out := []
	if form == "" or not DB.FORM.has(form):
		return out
	var sz := size
	var slots: Array = DB.FORM[form].slots
	var rows := 1
	for s in slots:
		rows = maxi(rows, int(s.row) + 1)
	var cw := sz.x / COLS
	var rh := _row_h(rows)
	var top := _rows_top()
	var order := range(slots.size())
	order.sort_custom(func(a, b): return int(slots[a].row) < int(slots[b].row))
	for i in order:
		if i >= cards.size() or cards[i] == null:
			continue
		var s: Dictionary = slots[i]
		out.append([Vector2(cw * (int(s.col) + 0.5), top + rh * (int(s.row) + 0.5)), cards[i], minf(cw, rh), i])
	return out


## 메달 줄 —— 효과 표가 밖으로 나간 뒤(11/7)는 남는 높이 가운데에 (11/5 에는 위 버프 표 아래 촘촘히 두었다)
func _rows() -> int:
	var rows := 1
	if DB.FORM.has(form):
		for s in DB.FORM[form].slots:
			rows = maxi(rows, int(s.row) + 1)
	return rows


func _row_h(rows: int) -> float:
	return clampf((size.y - 36.0) / rows, 40.0, 92.0)


func _rows_top() -> float:
	var rows := _rows()
	return maxf(36.0, (size.y - _row_h(rows) * rows) * 0.5 + 10.0)


func _squad(c: Vector2, k: String, cell: float, seed_: int) -> void:
	var tex := _sprite(DB.C[k].tag)
	var fw := 256.0
	var fh := 256.0
	var h := cell * 0.8          # 그림 칸(256px)에서 병사는 가운데 1/3 정도 —— 칸을 크게 잡는다
	var w := h * fw / fh
	if tex:
		var n := 5 if DB.C[k].tier < 6 else 7
		for j in n:
			var row := j / 4
			var col := j % 4
			var off := Vector2((col - 1.5) * w * 0.16 + (row * w * 0.08), row * h * 0.07)
			var bob := sin(t * 2.2 + seed_ * 1.3 + j) * 1.2
			var p := c + off + Vector2(-w / 2.0, -h * 0.62 + bob)
			draw_texture_rect_region(tex, Rect2(p, Vector2(w, h)), Rect2(0, 0, fw, fh))


## 장수 메달 · 이름 —— 병사 무리 위 (병사 셰이더가 메달 테 색을 바꾸지 않게 따로 그린다)
class Medals extends Control:
	var fv: FormationView

	func _draw() -> void:
		for e in fv.layout():
			var c: Vector2 = e[0]
			var k: String = e[1]
			var cell: float = e[2]
			var r := clampf(cell * 0.3, 18.0, 34.0)
			var mc := c + Vector2(0, -8.0)
			var bn = DB.D.FORMBOON.get(fv.form)
			var pref: bool = bn != null and bn.tags.has(DB.C[k].tag)
			if pref:      # 11/5 사용자: 진형 우대(어린진 → 창병 · 유생 방어 +14%) 받는 장수를 눈에 띄게 —— 금빛 고리가 숨쉬듯
				var pa := 0.45 + 0.25 * sin(fv.t * 3.0 + e[3])
				draw_circle(mc, r + 9.0, Color(DB.PAL.gold, pa * 0.35))
				draw_arc(mc, r + 6.0, 0, TAU, 40, Color(DB.PAL.gold, 0.6 + pa * 0.4), 2.5, true)
			draw_circle(mc, r + 3.0, Color(0, 0, 0, 0.55))
			draw_circle(mc, r + 2.0, DB.tier_color(k))
			draw_circle(mc, r + 0.6, Color("#4f8be0"))
			Art.draw_face_circle(self, mc, r, k)
			var nm: String = DB.person(k) if DB.C[k].tier > 2 else DB.C[k].name
			var f: Font = DB.font_bold
			draw_string_outline(f, Vector2(mc.x - 60, mc.y + r + 17), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(mc.x - 60, mc.y + r + 17), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, DB.tier_color(k).lightened(0.3))
			if pref:
				var txt := "%s+%d%%" % [DB.D.STATNM.get(bn.stat, "발동"), roundi(float(bn.v) * 100)]
				var tw := DB.font_bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 8
				var tr := Rect2(mc.x + r * 0.3, mc.y - r - 2, tw, 14)      # 11/7 메달 위 테두리에 걸치게 —— 윗줄 이름과 겹치지 않게
				draw_style_box(UI.flat(DB.PAL.gold, DB.PAL.gold, 0, 7, 0), tr)
				draw_string(DB.font_bold, tr.position + Vector2(0, 11), txt, HORIZONTAL_ALIGNMENT_CENTER, tw, 10, Color("#1A1508"))
