class_name FormationView
extends Control
## 전투 탭의 내 진영 미리 보기 (11/4 사용자: 남는 공간에 지금 배치된 병종을 그린다) ——
## 진형 칸 자리대로 병종 병사 그림(assets/troops_sprite, 첫 칸 = 서 있는 모습) 몇 명 + 장수 얼굴 메달 · 이름. 위쪽이 적 방향.

const COLS := 5      # 11/6 진형 4행 5열
var cards: Array = []        # 9칸 카드 id (null 은 빈칸)
var form := ""
var t := 0.0
var _sprites := {}
var _mat: ShaderMaterial
var on_medal := Callable()     # 11/5 사용자: 메달을 누르면 그 장수 상세 —— 카드 id 를 넘긴다
var _buf_lbl: RichTextLabel     # 11/5 사용자: 위쪽에 지금 받는 버프 목록 · 수치 · (부여 장수)

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
	return self


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
	# 11/6 사용자: 버프 설명창 —— 장수와 효과를 셀로 나눠 눈에 잘 띄게 (2열 표: 왼쪽 장수 · 오른쪽 『특기』 효과)
	var rows := []      # [왼쪽 BBCode, 오른쪽 BBCode, 왼쪽 바탕색]
	var bn = DB.D.FORMBOON.get(form)
	if bn != null and DB.FORM.has(form):
		var who := []
		for k in cards:
			if k != null and bn.tags.has(DB.C[k].tag):
				who.append(DB.person(k) if DB.C[k].tier > 2 else DB.C[k].name)
		if not who.is_empty():
			rows.append(["[color=#1A1508][b]%s[/b][/color]" % ", ".join(who),
				"[color=#E8C25A][b]진형『%s』[/b][/color] [color=#8FD4C2]%s %s +%d%%[/color]" % [DB.FORM[form].n, " · ".join(bn.tags), DB.D.STATNM.get(bn.stat, "스킬 발동"), roundi(float(bn.v) * 100)],
				Color("#C9A246")])
	for b in team_buffs(cards):
		var tc: Color = DB.tier_color(b.k)
		rows.append(["[color=#F4EBD6][b]%s[/b][/color]" % b.who,
			"[color=#E8D9B5]『%s』[/color] [color=#8FD4C2]%s[/color]%s" % [b.name, b.text, "" if b.kind == "단체" else " [color=#8D7B5C](%s)[/color]" % b.kind],
			tc.darkened(0.45)])
	if not rows.is_empty():
		var bb := "[table=2]"
		for r in rows:
			bb += "[cell bg=#%s border=#2a3348 padding=6,3,6,3]%s[/cell][cell bg=#151b29 border=#2a3348 padding=6,3,6,3]%s[/cell]" % [(r[2] as Color).to_html(false), r[0], r[1]]
		bb += "[/table]"
		_buf_lbl = UI.rich("", 13)
		_buf_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_buf_lbl.position = Vector2(8, 6)
		_buf_lbl.append_text("[color=#3F9A94][b]군단 효과[/b][/color]
" + bb)
		add_child(_buf_lbl)
	resized.connect(func():
		if _buf_lbl != null:
			_buf_lbl.size.x = size.x - 16)


## 진영 전체가 받는 버프 —— 단체 특기(같은 이름은 센 것 + 두 번째 절반, 전투와 같다) · 위세 · 기인.
## [{kind, name, text, who, col}] (11/5 사용자: 전투 탭 위에 버프 목록 · 수치 · 부여 장수명)
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
	draw_string(DB.font_bold, Vector2(0, y0 - 6), "▲ 적", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 11, Color(DB.PAL.seal, 0.8))
	if _buf_lbl != null:
		draw_line(Vector2(8, _buf_h() + 4), Vector2(sz.x - 8, _buf_h() + 4), Color(1, 1, 1, 0.06), 1.0)
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


## 메달 줄 —— 아래쪽에 촘촘히 (11/5 사용자), 위는 버프 목록
func _rows() -> int:
	var rows := 1
	if DB.FORM.has(form):
		for s in DB.FORM[form].slots:
			rows = maxi(rows, int(s.row) + 1)
	return rows


func _buf_h() -> float:
	return _buf_lbl.get_content_height() + 6.0 if _buf_lbl != null else 0.0


func _row_h(rows: int) -> float:
	return clampf((size.y - _buf_h() - 24.0) / rows, 40.0, 74.0)


func _rows_top() -> float:
	var rows := _rows()
	return maxf(_buf_h() + 20.0, size.y - _row_h(rows) * rows - 4.0)


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
				var tr := Rect2(mc.x + r * 0.3, mc.y - r - 6, tw, 14)
				draw_style_box(UI.flat(DB.PAL.gold, DB.PAL.gold, 0, 7, 0), tr)
				draw_string(DB.font_bold, tr.position + Vector2(0, 11), txt, HORIZONTAL_ALIGNMENT_CENTER, tw, 10, Color("#1A1508"))
