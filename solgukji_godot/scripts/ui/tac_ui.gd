extends RefCounted
## 군략 카드 화면 부품 (11/15 1차 —— docs/군략_카드_초안.md)
##  편성 화면 「군략 1 · 2 · 3단계」 칸 줄 · 손패 시트 · 하루 끝 3택1 시트 · 머리띠 다시 열기 버튼 · 계열 기호 ·
##  전투 탭 우두머리 계획 줄 · 대전 상대 최근 계열 줄 · 전투 화면 단계 공개 연출.
##  11/21 군략 현황 —— 나 · 상대 · 같은 방의 단계 계획과 상시 효과(늘 켜짐 · 영구)를 나란히 (아래 「군략 현황」 절).
## 11/14 UI 규칙: UI 상수(SP_* · FS_* · BH_* · R) · 색은 DB.PAL(강조 금 하나) · 계열은 작은 기호 + 옅은 라벨 · 터치 48 · 빈 상태 UI.empty · 확인 한 번.
## class_name 없이 preload 로 쓴다 (낡은 .godot 캐시에서도 이름을 찾게)

const Tac := preload("res://scripts/tactics.gd")
const MATCH_HINT := "상성 —— 정면 ▸ 기동 · 원거리 / 기동 ▸ 수비 · 책략 / 수비 ▸ 정면 · 원거리 / 원거리 ▸ 기동 · 책략 / 책략 ▸ 정면 · 수비. 이기면 공격 +15%, 지면 효과 절반"
const OUT_TEXT := {"win": "상성 우세 —— 공격 +15%", "lose": "상성 열세 —— 효과 절반", "draw": "상성 비김"}


## 계열 기호 —— 정면 ▲ · 기동 » · 수비 ■(방패) · 원거리 ◎ · 책략 ◆. 계열 없음은 작은 빈 원
class Glyph extends Control:
	var fam := ""
	var col := Color.WHITE

	func _init(f := "", c := Color.WHITE, d := 14.0) -> void:
		fam = f
		col = c
		custom_minimum_size = Vector2(d, d)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size / 2.0
		var r := s * 0.42
		var w := maxf(1.4, s / 9.0)
		match fam:
			"정면":
				var p := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.95, r * 0.8), c + Vector2(-r * 0.95, r * 0.8)])
				draw_colored_polygon(p, col)
			"기동":
				for dx in [-r * 0.55, r * 0.25]:
					draw_polyline(PackedVector2Array([c + Vector2(dx - r * 0.3, -r * 0.75), c + Vector2(dx + r * 0.4, 0), c + Vector2(dx - r * 0.3, r * 0.75)]), col, w)
			"수비":
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.8), c + Vector2(r * 0.8, -r * 0.8), c + Vector2(r * 0.8, r * 0.1),
					c + Vector2(0, r), c + Vector2(-r * 0.8, r * 0.1), c + Vector2(-r * 0.8, -r * 0.8)]), col, w)
			"원거리":
				draw_arc(c, r * 0.85, 0, TAU, 20, col, w)
				draw_circle(c, r * 0.3, col)
			"책략":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.75, 0), c + Vector2(0, r), c + Vector2(-r * 0.75, 0)]), col)
			_:
				draw_arc(c, r * 0.45, 0, TAU, 14, Color(col, 0.7), w * 0.8)


## 계열 묶음 —— 기호 + 옅은 라벨 ("정면"). 둘(호표기)이면 둘 다
static func fam_tag(id: String, fs := UI.FS_CAP) -> HBoxContainer:
	var h := UI.hbox(3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs_l := Tac.fams(id)
	if fs_l.is_empty():
		fs_l = [""]
	for f in fs_l:
		var g := Glyph.new(f, DB.PAL.bamboo, fs + 1)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(g)
	var l := UI.lbl(Tac.fam_text(id) if Tac.fam_text(id) != "" else "계열 없음", fs, DB.PAL.text_dim)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	return h


## 카드 한 장 (손패 · 3택1) —— 등급색이 옅게 밴 바탕 · 위 등급색 선 · 계열 문장(기호) · 이름 · 등급 · 효과 · 상성(우세 / 열세). sel 이면 금테.
## note 는 못 놓는 까닭 같은 덧말(옅게). tall(3택1)은 문장을 가운데 크게 세운 세로 카드
## 11/16 사용자 "군략카드 폴리싱" —— 글만 있던 카드에 계열 문장 · 등급 바탕 · 상성 줄을 넣었다 (긴 상성 안내 글을 읽지 않아도 카드에서 바로 보이게)
## 11/25 vs = 이 단계 상대 카드(알면) —— 일반 상성 줄 대신 「우세 · 상대 방진」 판정 한 줄 (vs_src = "상대" | "지난 대전"). rdone = 연구 카드면 갈래 줄(초급 ▸ 중급 ▸ 고급)에 고른 단계 ✓
static func card_btn(id: String, cb: Callable, sel := false, note := "", tall := false, vs := "", vs_src := "", rdone = null) -> TouchButton:
	var P := DB.PAL
	var b := TouchButton.new()
	var econ := str(Tac.card(id).get("kind", "")) == "econ"
	var has_match := not Tac.fams(id).is_empty()
	var verdict := _verdict(id, vs)
	var chain: Array = Tac.res_chain(id) if Tac.is_res(id) else []
	b.custom_minimum_size = Vector2(0, (204 + (34 if chain.size() > 1 else 0)) if tall else ((118 if has_match else 100) + (14 if note != "" else 0)))      # 글이 짧아(효과 한두 줄) 높이를 정해 둔다 —— 줄바꿈 글의 최소 크기는 폭이 잡히기 전에 커서 못 믿는다
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gc := Tac.grade_col(id)
	var sb := UI.flat(P.ink2.lerp(gc, 0.16 if sel else 0.09), P.gold if sel else Color(gc, 0.55), 2 if sel else 1, UI.R, 0)
	sb.border_width_top = 3
	sb.border_color = P.gold if sel else Color(gc, 0.65)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	var v := UI.vbox(3 if tall else 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = UI.SP_S
	v.offset_right = -UI.SP_S
	v.offset_top = UI.SP_S
	v.offset_bottom = -UI.SP_XS
	var nl := UI.lbl(id, UI.FS_LABEL, P.gold if sel else P.paper, true)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nl.clip_text = true
	var gl := UI.lbl("능력치 · 경제" if econ and not Tac.is_res(id) else Tac.grade_name(id), UI.FS_CAP, gc.lightened(0.2))
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tall:
		# 세로 카드 —— 등급 · 문장 · 이름 · 계열을 가운데로
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(gl)
		v.add_child(_emblem(id, gc, 40.0))
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.autowrap_mode = TextServer.AUTOWRAP_OFF
		v.add_child(nl)
		if not econ:
			var fl := UI.lbl(Tac.fam_text(id) if has_match else "계열 없음", UI.FS_CAP, P.bamboo)
			fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(fl)
	else:
		var hd := UI.hbox(UI.SP_S)
		hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var em := _emblem(id, gc, 26.0)
		em.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		hd.add_child(em)
		var nv := UI.vbox(0)
		nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_child(nl)
		if not econ:
			var fl2 := UI.lbl(Tac.fam_text(id) if has_match else "계열 없음", UI.FS_CAP, P.bamboo)
			fl2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			nv.add_child(fl2)
		hd.add_child(nv)
		gl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		hd.add_child(gl)
		v.add_child(hd)
	var dl := UI.lbl(Tac.desc(id) + (("
" + note) if note != "" else ""), UI.FS_CAP, P.paper if tall else P.text_dim)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.wrap_text(dl)
	if tall:
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(dl)
	# 11/20 폴리싱: 효과 글이 세 줄이 되면(손패 시트 두 칸 격자의 「우회」) 정해 둔 높이를 넘어 상성 줄과 겹쳤다 —— 폭이 잡힌 뒤 줄 수를 세어 넘는 줄만큼만 카드를 키운다
	var base_h := b.custom_minimum_size.y
	var base_lines := 2 + (1 if note != "" else 0)
	dl.resized.connect(func():
		var extra := maxi(0, dl.get_line_count() - base_lines) * (dl.get_line_height() + dl.get_theme_constant("line_spacing"))
		if dl.size.x >= 60.0 and not is_equal_approx(b.custom_minimum_size.y, base_h + extra):      # 폭이 잡히기 전(글자마다 줄이 바뀐다)은 믿지 않는다
			b.custom_minimum_size.y = base_h + extra)
	if chain.size() > 1:
		v.add_child(_chain_row(id, chain, rdone if rdone is Dictionary else {}))
	if verdict != "":
		v.add_child(_verdict_row(verdict, vs, vs_src, tall))
	elif has_match:
		v.add_child(_match_rows(id, tall))
	b.add_child(v)
	b.clip_contents = true
	b.pressed.connect(func():
		UI.buzz()
		cb.call())
	return b


## 계열 문장 —— 등급색 얇은 테 원 안에 계열 기호 (둘이면 나란히). 계열 없음 · 능력치 카드는 작은 빈 원
static func _emblem(id: String, gc: Color, d: float) -> Control:
	var fs_l := Tac.fams(id)
	if fs_l.is_empty():
		fs_l = [""]
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := UI.flat(Color(gc, 0.14), Color(gc, 0.7), 1, int(d / 2.0), 0)
	sb.content_margin_left = d * 0.22
	sb.content_margin_right = d * 0.22
	sb.content_margin_top = d * 0.22
	sb.content_margin_bottom = d * 0.22
	pc.add_theme_stylebox_override("panel", sb)
	var h := UI.hbox(2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for f in fs_l:
		h.add_child(Glyph.new(f, gc.lightened(0.35), d * 0.56))
	pc.add_child(h)
	return pc


## 11/25 이 카드를 상대 카드 vs 에 냈을 때 —— "win" · "draw" · "lose", 어느 쪽이든 계열이 없거나 모르면 ""
static func _verdict(id: String, vs: String) -> String:
	if vs == "" or id == "" or not Tac.has(vs) or Tac.fams(vs).is_empty() or Tac.fams(id).is_empty():
		return ""
	return Tac.preview(id, vs)


const VERDICT := {"win": ["우세", "공격 +15%"], "draw": ["비김", ""], "lose": ["열세", "효과 절반"]}      # ▲ · ▼ 는 정면 계열 문장(▲)과 헷갈려 글로
static func verdict_col(o: String) -> Color:
	return DB.PAL.jade.lightened(0.25) if o == "win" else (DB.PAL.danger if o == "lose" else DB.PAL.paper)


## 판정 한 줄 —— 「우세  상대 방진 · 공격 +15%」. 지난 대전 기준(가려진 사람)이면 「지난 방진」
static func _verdict_row(o: String, vs: String, src: String, tall: bool) -> Control:
	var P := DB.PAL
	var h := UI.hbox(4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tall:
		h.alignment = BoxContainer.ALIGNMENT_CENTER
	var hl := UI.lbl(str(VERDICT[o][0]), UI.FS_TINY, verdict_col(o), true)
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(hl)
	var tail := str(VERDICT[o][1])
	var tl := UI.lbl("%s %s%s" % ["지난" if src == "지난 대전" else "상대", vs, (" · " + tail) if tail != "" else ""], UI.FS_TINY, P.text_dim)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.clip_text = true
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tl)
	return h


## 연구 갈래 줄 —— 「초급 명마 ▸ 중급 양마 번식 ▸ 고급 서량 마구」 단계색, 이 카드는 굵게, 이미 고른 단계는 ✓
static func _chain_row(id: String, chain: Array, done: Dictionary) -> Control:
	var P := DB.PAL
	var parts := []
	for x in chain:
		var sx := str(x)
		var c := Tac.res_col(sx)
		var nm := _bb(sx)
		if sx == id:
			nm = "[b]%s[/b]" % nm
		var mark := "✓" if int(done.get(sx, 0)) > 0 else ""
		parts.append("[color=#%s]%s%s[/color]" % [(c if sx == id or mark != "" else c.darkened(0.25)).to_html(false), mark, nm])
	var rl := UI.rich("[center]%s[/center]" % ("[color=#%s] ▸ [/color]" % P.text_dim.to_html(false)).join(parts), UI.FS_TINY)
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rl


## 상성 줄 —— 「우세 기동 · 원거리」(옥빛) · 「열세 수비 · 책략」(붉은빛). tall 이면 두 줄, 아니면 한 줄에 나란히
static func _match_rows(id: String, tall: bool) -> Control:
	var P := DB.PAL
	var box: BoxContainer = UI.vbox(0) if tall else UI.hbox(UI.SP_S)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for e in [["우세", Tac.strong(id), P.jade], ["열세", Tac.weak(id), P.danger]]:
		var fl: Array = e[1]
		if fl.is_empty():
			continue
		var h := UI.hbox(3)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if tall:
			h.alignment = BoxContainer.ALIGNMENT_CENTER
		var hl := UI.lbl(str(e[0]), UI.FS_TINY, (e[2] as Color).lightened(0.15), true)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(hl)
		var tl := UI.lbl(" · ".join(fl), UI.FS_TINY, P.text_dim)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tl)
		box.add_child(h)
	return box


# ───────── 편성 화면 —— 「군략 1 · 2 · 3단계」 ─────────

## 11/22 사용자: 1 · 2 · 3단계가 언제인지 모호했다 —— 전투 시간을 셋으로 나눈다 (tac_rt: 단계 길이 = RtBattle.BATTLE_SEC / 3, 3단계는 끝까지).
## 짧은 꼴(칸 · 전투 HUD)과 긴 꼴(손패 시트 머리)
const STAGE_NAME := ["개전", "중반", "후반"]
static func stage_span(i: int) -> String:
	var L := RtBattle.BATTLE_SEC / float(Tac.STAGES)
	if i <= 0:
		return "개전~%d초" % roundi(L)
	if i >= Tac.STAGES - 1:
		return "%d초~끝" % roundi(L * i)
	return "%d~%d초" % [roundi(L * i), roundi(L * (i + 1))]


static func stage_when(i: int) -> String:
	var tail := ["전투가 시작되자마자 양쪽 카드를 펴고 상성을 본다", "전투 한가운데 —— 1단계 효과가 끝나고 이 카드로 바뀐다", "전투가 끝날 때까지 이어진다 (결전도 이 단계)"]
	return "%d단계 = %s (%s) —— %s" % [i + 1, STAGE_NAME[clampi(i, 0, 2)], stage_span(i), tail[clampi(i, 0, 2)]]


## 한 줄 —— 머리 「군략」 + 세 칸. 칸을 누르면 손패 시트.
## 11/25 상대 단계 카드를 알면(우두머리 · 봇 · 공개, 가렸으면 지난 대전) 칸마다 「우세 · 비김 · 열세」 작은 표시 —— 시트를 열지 않고도 어느 칸을 고칠지 보이게
static func plan_row(gs) -> Control:
	var P := DB.PAL
	var run: Run = gs.run
	var h := UI.hbox(UI.SP_XS)
	h.add_child(_status_btn(gs))      # 11/21 「군략 / 현황 ›」 —— 누르면 나 · 상대 · 같은 방의 군략과 상시 효과 (예전 「군략」 글 자리, 폭 거의 그대로)
	var plan := Tac.norm(run.tk_plan)
	var fc := foe_cards(context(gs, false))
	for i in Tac.STAGES:
		h.add_child(_slot(gs, i, plan[i], _verdict(str(plan[i]), str(fc.ids[i]))))
	return h


static func _slot(gs, i: int, id: String, o := "") -> TouchButton:
	var P := DB.PAL
	var b := TouchButton.new()
	b.custom_minimum_size = Vector2(0, UI.HIT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var on := id != ""
	var sb := UI.flat(P.ink2.lerp(Tac.grade_col(id), 0.10) if on else Color(0, 0, 0, 0), Color(Tac.grade_col(id), 0.9) if on else Color(P.paper, 0.16), 1, UI.R, 0)
	if on:
		sb.border_width_top = 2      # 손패 카드와 같은 결 —— 위 등급색 선
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	var v := UI.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -4
	var top := UI.hbox(3)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := UI.lbl("%d단계 %s" % [i + 1, STAGE_NAME[clampi(i, 0, 2)]], UI.FS_TINY, P.text_dim)      # 11/22 언제인지 —— 「1단계 개전」
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(nl)
	if on:
		for f in (Tac.fams(id) if not Tac.fams(id).is_empty() else [""]):
			var g := Glyph.new(f, P.bamboo, 10)
			g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			top.add_child(g)
	if o != "":
		var sp := Control.new()
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(sp)
		var ol := UI.lbl(str(VERDICT[o][0]), UI.FS_TINY, verdict_col(o), true)
		ol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(ol)
		if o == "lose":
			sb.border_color = Color(P.danger, 0.85)
	v.add_child(top)
	var cl := UI.lbl(id if on else "비었음 +", UI.FS_BODY, P.paper if on else P.text_dim, on)
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.clip_text = true
	cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(cl)
	b.add_child(v)
	b.pressed.connect(func():
		UI.buzz()
		hand_sheet(gs, i))
	return b


## 손패 시트 —— i 단계에 놓을 카드. 놓인 칸이면 위에 「지금 카드 · 비우기」. 못 놓는 카드는 까닭을 옅게.
## 11/21 맨 위에 이 단계 상대 카드(foe_line), 아래에 양쪽 군략 · 효과(versus —— 늘 켜짐 · 영구 효과 수치까지) · 같은 방(room_box)
static func hand_sheet(gs, i: int) -> void:
	var run: Run = gs.run
	var b: VBoxContainer = gs.open_sheet("군략 %d단계" % (i + 1))
	var plan := Tac.norm(run.tk_plan)
	var cur: String = plan[i]
	var ctx := context(gs)      # 11/21 군략 현황 —— 상대 · 같은 방의 군략과 상시 효과
	var fc := foe_cards(ctx)      # 11/25 이 단계 상대 카드(공개 · 봇 · 우두머리, 가렸으면 지난 대전) —— 카드마다 우세 · 열세 판정
	var vs := str(fc.ids[i])
	var src := str(fc.src)
	b.add_child(UI.hint(stage_when(i)))      # 11/22 이 단계가 전투의 언제인지
	var fl := foe_line(ctx, i, func(t: String): gs.toast(t))
	if fl != null:
		b.add_child(fl)
	var cbx := counter_btn(gs, ctx, func(): hand_sheet(gs, i))      # 11/25 세 단계를 한 번에 받아치기
	if cbx != null:
		b.add_child(cbx)
	var done := func(id: String):
		gs.act("set_plan", [i, id])
		gs.close_sheet()
	if cur != "":
		b.add_child(UI.eyebrow("지금 놓인 카드"))
		var cr := UI.hbox(UI.SP_S)
		cr.add_child(card_btn(cur, func(): gs.toast(Tac.desc(cur)), true, "", false, vs, src))
		var cb := UI.btn("비우기", func(): done.call(""), "ghost", UI.BH_M)
		cb.custom_minimum_size.x = 84
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cr.add_child(cb)
		b.add_child(cr)
	var ids: Array = run.tk_hand.keys().filter(func(id): return Tac.placeable(str(id)) and str(id) != cur)
	var vr := {"win": 2, "draw": 1, "": 1, "lose": 0}
	ids.sort_custom(func(x, y):
		var ox := int(vr[_verdict(str(x), vs)])      # 11/25 상대 카드를 알면 이기는 카드가 먼저
		var oy := int(vr[_verdict(str(y), vs)])
		if ox != oy:
			return ox > oy
		var gx := int(Tac.card(x).g)
		var gy := int(Tac.card(y).g)
		return gx > gy if gx != gy else str(x) < str(y))
	b.add_child(UI.eyebrow("손패 —— 누르면 %d단계에 놓는다" % (i + 1) if cur == "" else "손패 —— 누르면 바꾼다"))
	if ids.is_empty():
		b.add_child(UI.empty("draw", "놓을 군략이 없다", "하루가 끝날 때 3택1 로 군략이 는다."))
	var gd := GridContainer.new()
	gd.columns = 2
	gd.add_theme_constant_override("h_separation", UI.SP_S)
	gd.add_theme_constant_override("v_separation", UI.SP_S)
	for id in ids:
		var why := Tac.plan_block(plan, run.tk_hand, i, str(id))
		var n := int(run.tk_hand[id])
		var note := why if why != "" else ("%d장" % n if n > 1 else "")
		var cbtn := card_btn(str(id), func(): done.call(str(id)), false, note, false, vs, src)
		if why != "":
			cbtn.modulate.a = 0.45
			cbtn.disabled = true
		gd.add_child(cbtn)
	b.add_child(gd)
	# 11/21 예전 「늘 켜짐」 글(이름만 —— 「영구 —— 명마」)을 양쪽 군략 · 효과 패널로: 내 쪽 늘 켜짐 · 영구 효과를 수치까지, 상대 쪽도 나란히
	b.add_child(versus(gs, ctx, i))
	var rb := room_box(gs, ctx)
	if rb != null:
		b.add_child(rb)
	b.add_child(UI.hint("단계 —— %s · %s · %s. 단계가 열리는 순간 양쪽 카드가 공개되고, 효과는 그 단계 동안 (‘다음 단계’ · ‘이 전투 동안’ 은 예외)." % [stage_span(0), stage_span(1), stage_span(2)]))
	b.add_child(UI.hint("같은 단계에 낸 카드끼리 상성을 본다 —— 우세면 공격 +15%, 열세면 내 카드 효과 절반."))
	b.add_child(UI.hint("기본 카드는 여러 단계에 겹쳐 놓을 수 있다 · 고급 이상은 전투당 한 번 · 전설은 한 장. 계획은 토벌 · 대전 모두에 쓴다."))


# ───────── 3택1 ─────────

## 머리띠 버튼 —— 고를 3택1 이 있을 때만 보인다. 누르면 3택1 시트
static func head_btn(gs) -> TouchButton:
	var P := DB.PAL
	var b := TouchButton.new()
	b.text = "군략 3택1"
	b.hit = Vector2(UI.HIT, UI.HIT)
	b.custom_minimum_size = Vector2(0, 20)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", UI.FS_TINY)
	for cn in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(cn, P.gold)
	var sb := UI.flat(Color(P.gold, 0.12), P.gold, 1, UI.R, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.visible = false
	b.pressed.connect(func():
		UI.buzz()
		offer_sheet(gs))
	return b


## 3택1 시트 —— 카드 세 장(군략 연구면 넷) 가로. 누르면 고르고, 아래 「이 카드로」 확인 한 번. 기책이 있으면 다시 굴리기
## 11/22 두 단계 —— ① 군략 3택1 을 고르면 ② 연구 3택1 시트가 이어 열린다 (군략이 없으면 연구부터)
static func offer_sheet(gs, sel := "") -> void:
	var run: Run = gs.run
	if run.tk_offer.is_empty() and not run.rs_offer.is_empty():
		res_sheet(gs, sel)
		return
	var b: VBoxContainer = gs.open_sheet("군략 3택1  (1/2)")
	if run.tk_offer.is_empty():
		b.add_child(UI.empty("draw", "고를 카드가 없다", "아침마다 군략 3장 중 하나, 이어서 연구 3장 중 하나를 고른다."))
		return
	b.add_child(UI.hint("오늘의 군략을 하나 고르세요. 이어서 연구를 고릅니다. 계열 카드의 세기는 덱에 그 계열 병종이 많을수록 큽니다 (×0.7 ~ ×1.3)."))
	var row: Container = UI.grid(140, UI.SP_S) if run.tk_offer.size() > 3 else UI.hbox(UI.SP_S)
	var tags := Tac.deck_tags(run.board)
	for id in run.tk_offer:
		var sid := str(id)
		var note := ""
		if not Tac.fams(sid).is_empty():      # 11/25 효과 세기는 덱 쏠림을 탄다 (0.7 ~ 1.3배) —— 고를 때 내 덱에서 몇 배인지
			note = "내 덱에서 세기 ×%.2f" % Tac.bias(Tac.fams(sid), tags)
		row.add_child(card_btn(sid, func(): offer_sheet(gs, sid), sid == sel, note, true))
	b.add_child(row)
	var actions := UI.hbox(UI.SP_S)
	var later := UI.btn("나중에", func(): gs.close_sheet(), "ghost")
	later.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(later)
	var ok := UI.btn("받기 확정", func():
		if sel == "":
			return
		var r = gs.act("pick_tac", [sel])
		gs.close_sheet()
		if r:
			gs.toast("군략 「%s」" % sel, "gold")
			if not gs.run.rs_offer.is_empty():      # 11/22 이어서 연구 3택1
				(func(): res_sheet(gs)).call_deferred(), "pri")
	ok.disabled = sel == ""
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(ok)
	b.add_child(actions)
	if run.tk_reroll > 0:
		var rb := UI.btn("다시 굴리기 (%d)" % run.tk_reroll, func():
			gs.act("reroll_tac")
			offer_sheet(gs), "ghost", UI.BH_S)
		b.add_child(rb)
	b.add_child(UI.hint("나중에 상단의 ‘군략 3택1’에서 다시 열 수 있습니다. 다음 날엔 첫 카드가 자동 지급됩니다."))


## 11/22 연구 3택1 시트 —— 군략 3택1 과 같은 꼴. 카드 아래 덧말에 갈래 · 고르면 열리는 다음 단계
static func res_sheet(gs, sel := "") -> void:
	var run: Run = gs.run
	var b: VBoxContainer = gs.open_sheet("연구 3택1  (2/2)")
	if run.rs_offer.is_empty():
		b.add_child(UI.empty("draw", "고를 연구가 없다", "아침마다 군략 다음에 연구 3장 중 하나를 고른다."))
		return
	b.add_child(UI.hint("오늘의 연구를 하나 고르세요. 초급을 고르면 중급, 중급을 고르면 고급이 후보에 오릅니다."))
	b.add_child(res_legend())
	var row: Container = UI.grid(140, UI.SP_S) if run.rs_offer.size() > 3 else UI.hbox(UI.SP_S)
	for id in run.rs_offer:
		var sid := str(id)
		var n := int(run.rs_done.get(sid, 0))
		var note := ("%d번 연구함" % n) if n > 0 else ""      # 11/25 다음 단계는 카드 아래 갈래 줄(초급 ▸ 중급 ▸ 고급)이 보인다
		row.add_child(card_btn(sid, func(): res_sheet(gs, sid), sid == sel, note, true, "", "", run.rs_done))
	b.add_child(row)
	var actions := UI.hbox(UI.SP_S)
	var later := UI.btn("나중에", func(): gs.close_sheet(), "ghost")
	later.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(later)
	var ok := UI.btn("연구 확정", func():
		if sel == "":
			return
		var r = gs.act("pick_res", [sel])
		gs.close_sheet()
		if r:
			gs.toast("연구 「%s」" % sel, "gold"), "pri")
	ok.disabled = sel == ""
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(ok)
	b.add_child(actions)
	b.add_child(UI.hint("나중에 상단의 ‘연구 3택1’에서 다시 열 수 있습니다. 다음 날엔 첫 연구가 자동으로 정해집니다."))


## 11/25 연구 단계 색 안내 —— 「● 초급 ● 중급 ● 고급」 한 줄
static func res_legend() -> Control:
	var parts := []
	for k in Tac.RES_LV_N.size():
		parts.append("[color=#%s]● %s[/color]" % [(Tac.RES_LV_C[k] as Color).to_html(false), Tac.RES_LV_N[k]])
	var rl := UI.rich("[color=#%s]연구 단계[/color]   %s" % [DB.PAL.text_dim.to_html(false), "   ".join(parts)], UI.FS_CAP)
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rl


# ───────── 전투 탭 · 대전 상대 ─────────

## 우두머리 계획 줄 —— 「군략」 + 단계마다 기호 · 카드 이름. 누르면 효과 한 줄 (cb_toast)
## 11/25 mine = 내 계획(상대 줄일 때) —— 칩 오른쪽 끝에 내 같은 단계 카드의 판정 우세 · 비김 · 열세 (칩 테두리도 우세 옥빛 · 열세 붉게)
static func plan_chips(plan: Array, cb_toast: Callable, mine := []) -> HBoxContainer:
	var P := DB.PAL
	var h := UI.hbox(UI.SP_XS)
	var hl := UI.lbl("군략", UI.FS_CAP, P.text_dim)
	hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hl)
	var p := Tac.norm(plan)
	for i in Tac.STAGES:
		var id: String = p[i]
		var b := TouchButton.new()
		b.custom_minimum_size = Vector2(0, UI.BH_XS)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := UI.flat(P.ink2, P.ink4, 1, UI.R, 0)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		var r := UI.hbox(3)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.alignment = BoxContainer.ALIGNMENT_CENTER
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		r.offset_left = 4
		r.offset_right = -4
		var nl := UI.lbl("%d" % (i + 1), UI.FS_TINY, P.text_dim)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(nl)
		var fs := Tac.fams(id) if id != "" else []
		for f in (fs if not fs.is_empty() else [""]):
			var g := Glyph.new(f, P.bamboo, 11)
			g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r.add_child(g)
		var cl := UI.lbl(id if id != "" else "없음", UI.FS_CAP, P.paper if id != "" else P.text_dim)
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var o := _verdict(str(mine[i]), id) if mine.size() > i else ""
		if o != "":      # 판정 글이 붙으면 칸이 좁다 —— 이름은 남는 폭만큼 (말줄임)
			cl.clip_text = true
			cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cl.custom_minimum_size.x = 24
		r.add_child(cl)
		if o != "":
			var ol := UI.lbl(str(VERDICT[o][0]), UI.FS_TINY, verdict_col(o), true)
			ol.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r.add_child(ol)
			if o == "lose":
				sb.border_color = Color(P.danger, 0.8)
			elif o == "win":
				sb.border_color = Color(P.jade, 0.9)
		b.add_child(r)
		b.pressed.connect(func():
			if id != "":
				var tail := ""
				if o != "":
					tail = " · 내 %d단계 %s %s" % [i + 1, str(mine[i]), str(VERDICT[o][0])]
				cb_toast.call("%s —— %s%s" % [id, Tac.desc(id), tail]))
		h.add_child(b)
	return h


## 대전 상대가 최근 두 판에 쓴 카드 계열 —— 「최근 군략」 판마다 기호 셋. 기록이 없으면 null
static func hist_line(hist) -> Control:
	if not (hist is Array) or hist.is_empty():
		return null
	var P := DB.PAL
	var h := UI.hbox(UI.SP_S)
	var hl := UI.lbl("최근 군략", UI.FS_CAP, P.text_dim)
	hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hl)
	for gi in mini(2, hist.size()):
		var game = hist[gi]
		if not (game is Array):
			continue
		var gb := UI.hbox(2)
		var names := []
		for f in game:
			var g := Glyph.new(_hist_fam(str(f)), P.bamboo, 12)      # 11/21 기록이 카드 id 가 됐다 (옛 저장 · 옛 서버는 계열 글)
			g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			gb.add_child(g)
			names.append(str(f) if str(f) != "" else "—")
		var tl := UI.lbl(" ".join(names), UI.FS_CAP, P.text_dim)
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gb.add_child(tl)
		h.add_child(gb)
		if gi == 0 and hist.size() > 1:
			h.add_child(UI.lbl("/", UI.FS_CAP, Color(P.paper, 0.25)))
	return h


# ───────── 11/21 군략 현황 —— 나 · 상대 · 같은 방 ─────────
## 사용자 "선택 중인 군략뿐만 아니라 다른 유저가 고른 군략과 버프(기병 속도 10%) 같은 정보도 나열되어야 한다".
## 보이는 곳: 손패 시트(맨 위 「이 단계 상대」 줄 · 아래 양쪽 군략 · 같은 방) · 편성 칸 줄 왼쪽 「군략 / 현황 ›」 시트 ·
## 전투 탭(토벌 우두머리 패널 · 온라인 저녁 상대 패널) · 기록 탭 군웅 줄.
## 공개 규칙(Run.tk_plan_open): 사람의 단계 계획은 동시 선택이라 대전 단계 전(아침 · 토벌 · 대전 준비)에는 가리고 상태만(고르는 중 · 선택 완료 · 토벌 중),
## 대전 단계(전투가 계산된 뒤 —— 단계마다 뒤집힌다)와 판 끝에는 내용까지. 지난 대전 계획(이미 뒤집힌 카드) · 늘 켜짐 · 영구 효과(3택1 로 고른 순간 확정)는 언제나.
## 봇 · 토벌 우두머리 계획은 그 페이즈에 이미 정해져 있어 언제나 (혼자 하기는 Run 에서 바로 계산, 온라인 봇은 서버 거울 run.bots 의 plan · own).
## 한 진영 side = {name, tag, me, plan(Array 셋 | null = 가림), state(가렸을 때 상태 글), own(늘 켜짐 id), perm(영구 효과 이름), hist(지난 대전 계획들)}

const RULE_HINT := "상대의 단계 계획은 고르는 동안 가려지고 대전이 시작되면 공개된다. 늘 켜짐 · 영구 효과와 지난 대전 계획은 언제나 보인다."
const ROOM_SHOW := 3          # 같은 방 목록을 접었을 때 보이는 수 (하나만 더 남으면 그냥 다 보인다)


## 나 —— 지금 Run (온라인이면 서버가 준 내 상태)
static func side_me(run: Run) -> Dictionary:
	var pb := run.tk_pub()
	return {"name": "나", "tag": "", "me": true, "plan": Tac.norm(run.tk_plan), "state": "",
		"own": pb.get("own", []), "perm": pb.get("perm", []), "hist": pb.get("hist", [])}


## 오늘 토벌 우두머리 —— 그날 · 페이즈로 정해진 짐 (Run.quest_load)
static func side_boss(run: Run) -> Dictionary:
	var ld := run.quest_load()
	return {"name": "토벌 우두머리", "tag": run.quest_name(), "me": false, "plan": Tac.norm(ld.get("p", [])), "state": "",
		"own": ld.get("own", []), "perm": [], "hist": []}


## 봇 —— 혼자 하기는 Run 에서 그 페이즈 계획을 바로 계산(기록 탭 GameScreen.bot_row 와 같은 식), 온라인은 서버 거울(run.bots)의 plan · own
static func side_bot(run: Run, b: Dictionary) -> Dictionary:
	var plan = b.get("plan", null)
	var own = b.get("own", [])
	if Run.tac_on and not run.mp and b.has("pv") and not bool(b.get("dead", false)):
		var ld: Dictionary = run._bot_side_of(b.duplicate(true)).get("plan", {})
		plan = ld.get("p", [])
		own = ld.get("own", [])
	var ok: bool = plan is Array and not (plan as Array).is_empty()
	return {"name": str(b.get("name", "")), "tag": "봇", "me": false, "plan": Tac.norm(plan) if ok else null, "state": "" if ok else "모름",
		"own": own if own is Array else [], "perm": [], "hist": b.get("tk_hist") if b.get("tk_hist") is Array else []}


## 온라인 다른 사람 —— 방 정보 seats[] 한 줄 또는 기록 탭 줄(Online.peer_rows). 믿지 않는다. open = 계획 공개 단계, st = 단계 이름
static func side_seat(s: Dictionary, open: bool, st: String) -> Dictionary:
	var tk = s.get("tk", {})
	if not (tk is Dictionary):
		tk = {}
	var raw = s.get("plan")
	var plan = null
	if open and raw is Array and not (raw as Array).is_empty():
		plan = Tac.norm(raw)
	var on := bool(s.get("online", true))
	var state := ""
	if plan == null:
		if not on:
			state = "끊김 · 대행"
		elif open:
			state = "모름"      # 공개 단계인데 계획이 없다 (옛 서버)
		elif st == "noon":
			state = "토벌 중"
		else:
			state = "선택 완료" if bool(s.get("ready", false)) else "고르는 중"
	return {"name": str(s.get("name", "")), "tag": "사람", "me": false, "plan": plan, "state": state,
		"own": _arr(tk.get("own")), "perm": _arr(tk.get("perm")), "hist": _arr(tk.get("hist"))}


static func _arr(x) -> Array:
	return x if x is Array else []


## 지금 화면의 나 · 다음 상대 · 같은 방(다른 세력) —— {me, foe(비면 {}), note(상대가 없을 때 글), others, online}
## 상대: 혼자 하기 = 토벌 전엔 우두머리, 토벌 뒤엔 출진 때 정해짐(봇 가운데 하나). 온라인 = 토벌 있는 날 아침엔 우두머리, 대전 준비 · 대전엔 방 정보 foe
## 11/25 others = false 면 혼자 하기의 다른 세력 계획은 계산하지 않는다 (편성 칸 줄은 상대만 필요 —— 그리기마다 봇 계획을 다시 짜지 않게)
static func context(gs, others := true) -> Dictionary:
	var run: Run = gs.run
	var ctx := {"me": side_me(run), "foe": {}, "note": "", "others": [], "online": false}
	var on = gs.online
	if on != null and on.in_game:
		ctx.online = true
		var room: Dictionary = on.room
		var st := str(room.get("stage", ""))
		var open := Run.tk_plan_open(st)
		var you := int(room.get("you", -1))
		var seats = room.get("seats", [])
		if not (seats is Array):
			seats = []
		for k in range(seats.size()):
			var s = seats[k]
			if not (s is Dictionary) or k == you or bool(s.get("dead", false)):
				continue
			if bool(s.get("human", false)):
				ctx.others.append(side_seat(s, open, st))
				continue
			var bd := {"name": str(s.get("name", ""))}
			for b in run.bots:
				if str(b.get("name", "")) == bd.name:
					bd = b
					break
			ctx.others.append(side_bot(run, bd))
		var f = room.get("foe")
		if f is Dictionary and st in ["evening_prep", "evening"]:
			for o in ctx.others:
				if o.name == str(f.get("name", "")):
					ctx.foe = o
					break
			if ctx.foe.is_empty():      # 그림자 · 유랑군 —— 자리 줄에 없다
				ctx.foe = {"name": str(f.get("name", "")), "tag": "사람" if bool(f.get("human", false)) else "봇", "me": false, "plan": null,
					"state": "대전 때 공개", "own": [], "perm": [], "hist": []}
			if _arr(ctx.foe.get("hist")).is_empty() and f.get("tac") is Array:
				ctx.foe["hist"] = f.tac
			var fo: Dictionary = ctx.foe
			ctx.others = (ctx.others as Array).filter(func(o): return not is_same(o, fo))
		elif st == "morning" and bool(room.get("noon", false)) and not run.quest_done:
			ctx.foe = side_boss(run)
		elif st == "over":
			ctx.note = "판이 끝났다"
		else:
			ctx.note = "대전 상대는 대전 준비 때 정해진다"
	else:
		if not run.quest_done:
			ctx.foe = side_boss(run)
		elif not run.pvp_done:
			ctx.note = "대전 상대는 출진 때 아래 세력 가운데 하나로 정해진다"
		else:
			ctx.note = "오늘 전투를 모두 마쳤다"
		for b in (run.bots if others else []):
			if not bool(b.get("dead", false)):
				ctx.others.append(side_bot(run, b))
	return ctx


## 11/25 상대 단계 카드 셋 —— {ids: [셋], src: "상대" | "지난 대전" | ""}. 공개 · 봇 · 우두머리 계획이면 그대로,
## 사람이라 가렸으면 지난 대전 계획을 예상으로 (같은 사람은 같은 손패라 자주 되풀이한다). 모르면 src ""
static func foe_cards(ctx: Dictionary) -> Dictionary:
	var foe: Dictionary = ctx.get("foe", {})
	var none := {"ids": ["", "", ""], "src": ""}
	if foe.is_empty():
		return none
	if foe.get("plan") is Array:
		return {"ids": Tac.norm(foe.plan), "src": "상대"}
	var hist = foe.get("hist", [])
	if hist is Array and not hist.is_empty() and hist[0] is Array:
		var ids := Tac.norm(hist[0]).map(func(x): return str(x) if Tac.has(str(x)) else "")
		if ids.any(func(x): return x != ""):
			return {"ids": ids, "src": "지난 대전"}
	return none


static func _wins(plan: Array, foe: Array) -> int:
	var n := 0
	for i in Tac.STAGES:
		if _verdict(str(plan[i]), str(foe[i])) == "win":
			n += 1
	return n


## 11/25 받아치기 배치 —— 상대 단계 카드(가렸으면 지난 대전)를 보고 손패에서 상성으로 이기는 카드를 세 단계에 한 번에 놓는다.
## 사용자 "상대 군략을 예측해서 카운터 하는 게 현재 가능한지 (멀티 기준 10초)" —— 대전 준비 10초 안에 한 번 눌러 끝나게.
## 바꿀 것이 없으면(이미 최선 · 받아칠 카드 없음 · 상대를 모름) null. after = 누른 뒤 (시트 다시 열기)
static func counter_btn(gs, ctx: Dictionary, after := Callable()) -> Control:
	var run: Run = gs.run
	var fc := foe_cards(ctx)
	if str(fc.src) == "":
		return null
	var cur := Tac.norm(run.tk_plan)
	var nxt := Tac.counter_plan(cur, run.tk_hand, fc.ids)
	if nxt == cur:
		return null
	var w0 := _wins(cur, fc.ids)
	var w1 := _wins(nxt, fc.ids)
	var v := UI.vbox(2)
	var bt := UI.btn("받아치기 배치  ·  우세 %d → %d곳" % [w0, w1], func():
		var changed := []
		for i in Tac.STAGES:
			if str(nxt[i]) != str(cur[i]):
				gs.act("set_plan", [i, str(nxt[i])])
				changed.append("%d단계 %s" % [i + 1, nxt[i]])
		gs.toast("받아치기 —— " + " · ".join(changed), "gold")
		if after.is_valid():
			after.call(), "gold", UI.BH_M)
	v.add_child(bt)
	var how := "상대 계획을 보고" if str(fc.src) == "상대" else "지난 대전 계획을 예상으로"
	var nl := UI.lbl("%s 손패에서 상성으로 이기는 카드를 단계마다 놓는다" % how, UI.FS_CAP, DB.PAL.text_dim)
	UI.wrap_text(nl)
	v.add_child(nl)
	return v


## 기록 한 칸의 계열 —— 11/21 부터 카드 id, 옛 저장 · 옛 서버는 계열 글("정면" · "정면·기동")
static func _hist_fam(x: String) -> String:
	if Tac.has(x):
		var fs := Tac.fams(x)
		return fs[0] if not fs.is_empty() else ""
	return x.split("·")[0]


## 이 카드를 받아치는(상성으로 이기는) 계열 —— 카드가 더한 규칙(원진 비김 · 십면매복 …)까지 본다
static func _counters(id: String) -> Array:
	var out := []
	if id == "" or Tac.fams(id).is_empty():
		return out
	for f in Tac.FAMS:
		if Tac.outcome([f], Tac.fams(id), {}, Tac.rules(id)) == "win":
			out.append(f)
	return out


static func _bb(t: String) -> String:
	return t.replace("[", "[lb]")      # 서버가 준 글(영구 효과 이름) —— BBCode 로 읽히지 않게


## 편성 칸 줄 왼쪽 —— 「군략」 + 작은 금색 「현황 ›」. 누르면 군략 현황 시트
static func _status_btn(gs) -> TouchButton:
	var P := DB.PAL
	var b := TouchButton.new()
	b.custom_minimum_size = Vector2(40, UI.HIT)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	var v := UI.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t := UI.lbl("군략", UI.FS_BODY, P.bamboo, true)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.lbl("현황 ›", UI.FS_TINY, P.gold)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	b.add_child(v)
	b.pressed.connect(func():
		UI.buzz()
		status_sheet(gs))
	return b


## 오른쪽 끝 작은 금색 글 버튼 「군략 현황 ›」 —— 전투 탭 패널 아래 (편성 바꾸기 › 와 같은 결)
static func status_link(gs, text := "군략 현황 ›") -> Control:
	var P := DB.PAL
	var h := UI.hbox(0)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sp)
	var b := TouchButton.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, UI.BH_XS)
	b.add_theme_font_size_override("font_size", UI.FS_CAP)
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 4
	sb.content_margin_right = 0
	UI.btn_styles(b, sb)
	b.add_theme_color_override("font_color", P.gold)
	b.add_theme_color_override("font_hover_color", P.gold.lightened(0.3))
	b.add_theme_color_override("font_pressed_color", P.paper)
	b.pressed.connect(func():
		UI.buzz()
		status_sheet(gs))
	h.add_child(b)
	return h


## 군략 현황 시트 —— 양쪽 군략 · 효과(나 | 상대) · 같은 방 · 내 편성 효과(전투 탭의 군단 효과 상자) · 공개 규칙 한 줄
static func status_sheet(gs) -> void:
	var b: VBoxContainer = gs.open_sheet("군략 현황")
	var ctx := context(gs)
	b.add_child(versus(gs, ctx))
	var rb := room_box(gs, ctx)
	if rb != null:
		b.add_child(rb)
	# 내 편성 효과 —— 단체 특기 · 위세 · 기인 (상대 편성은 보이지 않는다, 결정 ⑥). 펼치기는 이 자리에서
	var fxh := UI.vbox(0)
	var ref := {"open": false}
	ref["fill"] = func():
		for c in fxh.get_children():
			c.queue_free()
		var fx = FormationView.effects_box(gs.run.board, gs.run.form, bool(ref.open), func():
			ref["open"] = not bool(ref.open)
			ref.fill.call_deferred(), func(k): gs.card_info(k))
		if fx != null:
			fxh.add_child(fx)
	ref.fill.call()
	b.add_child(fxh)
	b.add_child(UI.hint(RULE_HINT))


## 손패 시트 맨 위 —— 이 단계 상대 카드. 공개면 이름 + 받아치는 계열, 가려졌으면 상태 + 지난 대전의 같은 단계
static func foe_line(ctx: Dictionary, i: int, toast: Callable) -> Control:
	var foe: Dictionary = ctx.foe
	if foe.is_empty():
		return null
	var P := DB.PAL
	var v := UI.vbox(2)
	var h := UI.hbox(UI.SP_XS)
	var hl := UI.lbl("%s · %d단계" % [str(foe.name), i + 1], UI.FS_CAP, P.text_dim)
	hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hl)
	if foe.plan is Array:
		var id := str(foe.plan[i])
		for f in (Tac.fams(id) if id != "" and not Tac.fams(id).is_empty() else [""]):
			var g := Glyph.new(f, P.bamboo, 13)
			g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(g)
		var nl := UI.lbl(id if id != "" else "군략 없음", UI.FS_BODY, P.paper if id != "" else P.text_dim, true)
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(nl)
		v.add_child(h)
		var cs := _counters(id)
		if not cs.is_empty():
			var cl := UI.lbl("%s 계열로 받아치면 상성 우세" % " · ".join(cs), UI.FS_CAP, P.jade.lightened(0.25))
			UI.wrap_text(cl)
			v.add_child(cl)
		if id != "":
			UI.tap(v, func(): toast.call("%s —— %s" % [id, Tac.desc(id)]))
	else:
		var st := str(foe.state)
		var sl := UI.lbl("%s —— 대전 때 공개" % st if st not in ["대전 때 공개", ""] else "대전 때 공개", UI.FS_BODY, P.gold if st == "선택 완료" else P.paper, true)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sl)
		v.add_child(h)
		var hist = foe.get("hist", [])
		if hist is Array and not hist.is_empty() and hist[0] is Array and (hist[0] as Array).size() > i and str(hist[0][i]) != "":
			var hx := str(hist[0][i])
			var hh := UI.hbox(UI.SP_XS)
			var hl2 := UI.lbl("지난 대전 %d단계" % (i + 1), UI.FS_CAP, P.text_dim)
			hh.add_child(hl2)
			var g2 := Glyph.new(_hist_fam(hx), P.bamboo, 11)
			g2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hh.add_child(g2)
			hh.add_child(UI.lbl(hx, UI.FS_CAP, P.paper))
			v.add_child(hh)
			var hcs := _counters(hx) if Tac.has(hx) else []      # 11/25 가려졌어도 지난 대전 카드를 받아치는 계열 (예상)
			if not hcs.is_empty():
				var hcl := UI.lbl("또 낸다면 %s 계열이 상성 우세" % " · ".join(hcs), UI.FS_CAP, P.jade.lightened(0.25))
				UI.wrap_text(hcl)
				v.add_child(hcl)
	var pnl := PanelContainer.new()
	var sb := UI.flat(P.ink2, Color(P.gold, 0.5), 0, UI.R, 10)
	sb.border_width_left = 3
	pnl.add_theme_stylebox_override("panel", sb)
	pnl.add_child(v)
	return pnl


## 양쪽 군략 · 효과 —— 나 | 상대 두 칸: 단계 계획(내 칸엔 같은 단계 상성 미리보기) · 상시 효과(늘 켜짐 · 영구, 수치까지). hi = 손패 시트가 고르는 단계
static func versus(gs, ctx: Dictionary, hi := -1) -> Control:
	var v := UI.vbox(UI.SP_S)
	v.add_child(UI.head("양쪽 군략 · 효과", "줄을 누르면 효과"))
	var row := UI.hbox(UI.SP_S)
	var toast := func(t: String): gs.toast(t)
	row.add_child(_col(ctx.me, ctx.foe, hi, toast, ""))
	row.add_child(UI.hair(true))
	row.add_child(_col(ctx.foe, ctx.me, hi, toast, str(ctx.note)))
	v.add_child(row)
	return UI.panel(v, 10)


static func _col(side: Dictionary, other: Dictionary, hi: int, toast: Callable, note: String) -> Control:
	var P := DB.PAL
	var v := UI.vbox(UI.SP_XS)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if side.is_empty():
		v.add_child(UI.lbl("상대", UI.FS_BODY, P.text_dim, true))
		var nl := UI.lbl(note if note != "" else "아직 정해지지 않았다", UI.FS_CAP, P.text_dim)
		UI.wrap_text(nl)
		v.add_child(nl)
		return v
	v.add_child(_name_line(side))
	if side.plan is Array:
		var op = other.get("plan") if bool(side.get("me", false)) else null
		for k in Tac.STAGES:
			v.add_child(_plan_line(k, str(side.plan[k]), str(op[k]) if op is Array else "", k == hi, toast))
	else:
		v.add_child(_hidden_box(side, hi, toast))
	v.add_child(_sub("상시 효과"))
	var rows := Tac.buff_rows(side.get("own", []), side.get("perm", []))
	if rows.is_empty():
		v.add_child(UI.lbl("없음", UI.FS_CAP, P.text_dim))
	else:
		v.add_child(_buff_text(rows, true))
	return v


static func _sub(t: String) -> Label:
	var l := UI.lbl(t, UI.FS_CAP, DB.PAL.bamboo, true)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _name_line(side: Dictionary) -> Control:
	var P := DB.PAL
	var h := UI.hbox(UI.SP_XS)
	var me := bool(side.get("me", false))
	var nl := UI.lbl(str(side.name), UI.FS_BODY, P.gold if me else P.paper, true)
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nl)
	if str(side.get("tag", "")) != "":
		var tl := UI.lbl(str(side.tag), UI.FS_TINY, P.text_dim)
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tl.clip_text = true
		tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tl.custom_minimum_size.x = minf(64.0, DB.font_body.get_string_size(str(side.tag), HORIZONTAL_ALIGNMENT_LEFT, -1, UI.FS_TINY).x + 2.0) if DB.font_body != null else 0.0
		h.add_child(tl)
	return h


## 단계 한 줄 —— 「1 ▲ 돌격 …… 우세」. oid 가 있으면(내 칸) 같은 단계 상대 카드와의 상성 미리보기. hi 면 금 왼선. 누르면 효과 한 줄
static func _plan_line(k: int, id: String, oid: String, hi: bool, toast: Callable) -> TouchButton:
	var P := DB.PAL
	var b := TouchButton.new()
	b.custom_minimum_size = Vector2(0, 26)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.hit = Vector2.ZERO      # 줄이 붙어 있다 —— 보이는 크기만
	var sb := UI.flat(P.ink3 if hi else Color(0, 0, 0, 0), P.gold, 0, UI.R, 0)
	if hi:
		sb.border_width_left = 3
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	var h := UI.hbox(3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6 if hi else 3
	h.offset_right = -3
	var nl := UI.lbl("%d" % (k + 1), UI.FS_TINY, P.gold if hi else P.text_dim)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nl)
	var known := Tac.has(id)
	var fs: Array = (Tac.fams(id) if known else ([_hist_fam(id)] if id != "" else []))
	for f in (fs if not fs.is_empty() else [""]):
		var g := Glyph.new(f, P.bamboo, 11)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(g)
	var cl := UI.lbl(id if id != "" else "없음", UI.FS_CAP, P.paper if id != "" else P.text_dim)
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cl.clip_text = true
	cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(cl)
	var o := Tac.preview(id, oid) if oid != "" else ""
	if o in ["win", "lose"]:
		var ol := UI.lbl("우세" if o == "win" else "열세", UI.FS_TINY, P.jade.lightened(0.25) if o == "win" else P.danger, true)
		ol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ol)
	b.add_child(h)
	b.pressed.connect(func():
		if known:
			toast.call("%s —— %s" % [id, Tac.desc(id)]))
	return b


## 가려진 계획 —— 「계획 비공개」 + 상태(선택 완료는 금빛) + 지난 대전 세 줄(이미 공개된 것)
static func _hidden_box(side: Dictionary, hi: int, toast: Callable) -> Control:
	var P := DB.PAL
	var v := UI.vbox(2)
	var st := str(side.get("state", ""))
	var h := UI.hbox(UI.SP_XS)
	var tl := UI.lbl("계획 비공개", UI.FS_CAP, P.paper, true)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tl)
	if st != "":
		var sl := UI.lbl(st, UI.FS_TINY, P.gold if st == "선택 완료" else P.text_dim, st == "선택 완료")
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sl)
	v.add_child(h)
	var hist = side.get("hist", [])
	if hist is Array and not hist.is_empty() and hist[0] is Array:
		var last: Array = hist[0]
		v.add_child(UI.lbl("지난 대전", UI.FS_TINY, P.text_dim))
		for k in mini(Tac.STAGES, last.size()):
			v.add_child(_plan_line(k, str(last[k]), "", k == hi, toast))
	else:
		var nl := UI.lbl("대전이 시작되면 단계마다 공개된다", UI.FS_TINY, P.text_dim)
		UI.wrap_text(nl)
		v.add_child(nl)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.flat(Color(0, 0, 0, 0), Color(P.paper, 0.16), 1, UI.R, 6))
	pc.add_child(v)
	return pc


## 상시 효과 글 —— 효과 하나에 한 덩어리: 「늘 창림 수비 계열 효과 +30% …」 · 「영구 명마 기병 이동 속도 +10%」 (종류 색 · 이름 굵게 · 효과 옅게, 단어 단위 줄바꿈).
## narrow(나 | 상대 두 칸)면 이름 줄 아래에 효과 줄 —— 좁은 칸에서 이름과 수치가 뒤섞여 끊기지 않게
static func _buff_text(rows: Array, narrow := false) -> Control:
	var P := DB.PAL
	var v := UI.vbox(3 if narrow else 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in rows:
		var kc: Color = P.jade.lightened(0.25) if str(r.kind) == "늘" else P.bamboo
		var kind := str(r.kind)
		if kind == "영구" and Tac.is_res(str(r.src)):      # 11/25 연구로 얻은 영구 효과 —— 단계 이름 · 색 (초급 · 중급 · 고급)
			kc = Tac.res_col(str(r.src))
			kind = Tac.RES_LV_N[Tac.res_level(str(r.src))]
		var head := "[color=#%s]%s[/color] [b]%s[/b]" % [kc.to_html(false), kind, _bb(str(r.src))]
		var body := "[color=#%s]%s[/color]" % [P.text_dim.to_html(false), _bb(str(r.text))]
		var rl := UI.rich((head + "\n" + body) if narrow else (head + " " + body), UI.FS_CAP)
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(rl)
	return v


## 같은 방(온라인) · 다른 세력(혼자 하기) —— 한 사람(봇)씩: 이름 · 상태, 단계 계획 칩(가렸으면 지난 대전), 상시 효과. 넷 이상이면 셋만 보이고 「더 보기」
static func room_box(gs, ctx: Dictionary) -> Control:
	var others: Array = ctx.others
	if others.is_empty():
		return null
	var box := UI.vbox(UI.SP_S)
	box.add_child(UI.head("같은 방 군웅" if bool(ctx.online) else "다른 세력", "%d" % others.size()))
	var list := UI.vbox(UI.SP_S)
	box.add_child(UI.panel(list, 10))
	var toast := func(t: String): gs.toast(t)
	var ref := {"all": false}
	ref["fill"] = func():
		for c in list.get_children():
			list.remove_child(c)
			c.queue_free()
		var all := bool(ref.all) or others.size() <= ROOM_SHOW + 1
		var n := others.size() if all else ROOM_SHOW
		for j in n:
			if j > 0:
				list.add_child(UI.hair())
			list.add_child(_room_row(others[j], toast))
		if others.size() > ROOM_SHOW + 1:
			var mb := UI.btn(("접기 ▴" if bool(ref.all) else "%d곳 더 보기 ▾" % (others.size() - n)), func():
				ref["all"] = not bool(ref.all)
				ref.fill.call_deferred(), "ghost", UI.BH_S)
			mb.add_theme_font_size_override("font_size", UI.FS_BODY)
			list.add_child(mb)
	ref.fill.call()
	return box


static func _room_row(side: Dictionary, toast: Callable) -> Control:
	var P := DB.PAL
	var v := UI.vbox(UI.SP_XS)
	var h := UI.hbox(UI.SP_XS)
	var nl := UI.lbl(str(side.name), UI.FS_BODY, P.paper, true)
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nl)
	var st := ("확정" if str(side.get("tag", "")) == "봇" else "공개") if side.plan is Array else str(side.get("state", ""))      # 봇은 그 페이즈 계획이 정해져 있다
	var stl := UI.lbl(("%s · %s" % [str(side.tag), st]) if str(side.get("tag", "")) != "" else st, UI.FS_CAP, P.gold if st == "선택 완료" else P.text_dim)
	stl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(stl)
	v.add_child(h)
	var tv = peer_body(side, toast)
	if tv != null:
		v.add_child(tv)
	return v


## 한 진영의 군략 몸통(가로 한 폭) —— 단계 계획 칩(가렸으면 「계획 비공개 · 상태」 + 지난 대전) · 상시 효과 글.
## 11/25 mine = 내 계획 (대전 상대 줄) —— 칩마다 내 같은 단계 카드의 판정
static func peer_body(side: Dictionary, toast: Callable, mine := []) -> Control:
	var P := DB.PAL
	var v := UI.vbox(UI.SP_XS)
	if side.plan is Array:
		v.add_child(plan_chips(side.plan, toast, mine))
	else:
		var h := UI.hbox(UI.SP_XS)
		var hl := UI.lbl("군략", UI.FS_CAP, P.text_dim)
		h.add_child(hl)
		var st := str(side.get("state", ""))
		h.add_child(UI.lbl("계획 비공개%s" % ((" · " + st) if st != "" else ""), UI.FS_CAP, P.gold if st == "선택 완료" else P.paper))
		v.add_child(h)
		var hist = side.get("hist", [])
		if hist is Array and not hist.is_empty() and hist[0] is Array:
			v.add_child(_last_line(hist[0], toast, mine))
	var rows := Tac.buff_rows(side.get("own", []), side.get("perm", []))
	if not rows.is_empty():
		v.add_child(_buff_text(rows))
	return v


## 지난 대전 한 줄 —— 「지난 대전 ▲돌격 ■방진 »우회」 (기록이 계열 글인 옛 저장은 계열 이름).
## 11/25 mine = 내 계획 —— 같은 계획을 또 내면 내 카드가 어떻게 되는지 우세 · 비김 · 열세
static func _last_line(last: Array, toast: Callable, mine := []) -> Control:
	var P := DB.PAL
	var fl := UI.flow(UI.SP_S)
	fl.add_child(UI.lbl("지난 대전", UI.FS_CAP, P.text_dim))
	for k in mini(Tac.STAGES, last.size()):
		var x := str(last[k])
		var h := UI.hbox(2)
		var g := Glyph.new(_hist_fam(x), P.bamboo, 11)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(g)
		h.add_child(UI.lbl(x if x != "" else "없음", UI.FS_CAP, P.paper if x != "" else P.text_dim))
		var o := _verdict(str(mine[k]), x) if mine.size() > k else ""
		if o != "":
			h.add_child(UI.lbl(str(VERDICT[o][0]), UI.FS_TINY, verdict_col(o), true))
		if Tac.has(x):
			h.mouse_filter = Control.MOUSE_FILTER_STOP
			UI.tap(h, func(): toast.call("%s —— %s" % [x, Tac.desc(x)]))
		fl.add_child(h)
	return fl


## 전투 탭 토벌 우두머리 패널의 군략 —— 계획 칩 + 우두머리 늘 켜짐 + 「군략 현황 ›」 (GameScreen.boss_panel)
static func boss_rows(gs) -> Control:
	var v := UI.vbox(UI.SP_XS)
	var bs := side_boss(gs.run)
	v.add_child(plan_chips(bs.plan, func(t: String): gs.toast(t), Tac.norm(gs.run.tk_plan)))
	var rows := Tac.buff_rows(bs.own, [])
	if not rows.is_empty():
		v.add_child(_buff_text(rows))
	var cbx := counter_btn(gs, {"foe": bs}, func(): gs.render())      # 11/25 우두머리 계획은 미리 보인다 —— 한 번에 받아치기
	if cbx != null:
		v.add_child(cbx)
	v.add_child(status_link(gs))
	return v


## 온라인 저녁 상대 패널의 군략 (Online._foe_panel) —— 단계 계획(대전 때 공개, 그 전엔 상태) · 지난 대전 · 상시 효과 · 「군략 현황 ›».
## 상대를 자리 줄에서 못 찾으면(옛 서버) 예전 「최근 군략」 줄
static func foe_block(gs) -> Control:
	var ctx := context(gs)
	var foe: Dictionary = ctx.foe
	if foe.is_empty() or bool(foe.get("boss", false)):
		var f = gs.online.room.get("foe") if gs.online != null else null
		return hist_line(f.get("tac", [])) if f is Dictionary else null
	var v := UI.vbox(UI.SP_XS)
	var tv = peer_body(foe, func(t: String): gs.toast(t), Tac.norm(gs.run.tk_plan))
	if tv != null:
		v.add_child(tv)
	var st := str(gs.online.room.get("stage", "")) if gs.online != null else ""
	if st in ["morning", "evening_prep"]:      # 11/25 계획을 고칠 수 있는 단계 —— 대전 준비 10초 안에 한 번 눌러 받아치기
		var cbx := counter_btn(gs, ctx, func(): gs.render())
		if cbx != null:
			v.add_child(cbx)
	v.add_child(status_link(gs))
	return v


## 기록 탭 군웅 줄의 군략 (Online.peer_row) —— r = 그 줄 사전 (me · bot · plan · own · tk · ready · online). 군략이 꺼져 있으면 null
static func peer_tac(scr, r: Dictionary) -> Control:
	if not Run.tac_on:
		return null
	var side: Dictionary
	if bool(r.get("me", false)):
		side = side_me(scr.run)
	elif bool(r.get("bot", false)):
		var p = r.get("plan", [])
		var ok: bool = p is Array and not (p as Array).is_empty()
		side = {"name": str(r.get("name", "")), "tag": "봇", "plan": Tac.norm(p) if ok else null, "state": "" if ok else "모름",
			"own": r.get("own", []), "perm": [], "hist": []}
	else:
		var st := ""
		if scr.online != null and scr.online.in_game:
			st = str(scr.online.room.get("stage", ""))
		side = side_seat(r, st == "" or Run.tk_plan_open(st), st)
	return peer_body(side, func(t: String): scr.toast(t))


# ───────── 전투 화면 —— 단계 공개 ─────────

## 단계 시작 사건(fx "tac") 하나 —— 위 띠 아래에 양쪽 카드가 뒤집혀 나오고 상성 한 줄, 1.2초 머물다 사라진다. A 가 나(뒤집은 결과도 A 가 나)
static func reveal(e: Dictionary, width: float) -> Control:
	var P := DB.PAL
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = Vector2(width, 84)
	var cw := minf(156.0, (width - 72.0) / 2.0)
	var ea: Dictionary = e.get("A", {})
	var eb: Dictionary = e.get("B", {})
	var ca := _rv_card(ea, cw, War3D.TEAM.A)
	var cb := _rv_card(eb, cw, War3D.TEAM.B)
	ca.position = Vector2(width / 2.0 - 30.0 - cw, 0)
	cb.position = Vector2(width / 2.0 + 30.0, 0)
	root.add_child(ca)
	root.add_child(cb)
	var vs := UI.lbl("%d단계" % int(e.get("stage", 1)), UI.FS_CAP, P.paper, true)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.position = Vector2(width / 2.0 - 30.0, 16)
	vs.size = Vector2(60, 20)
	root.add_child(vs)
	var out := str(ea.get("out", "draw"))
	var ol := UI.lbl(OUT_TEXT.get(out, ""), UI.FS_BODY, P.gold if out == "win" else (P.danger if out == "lose" else P.paper), true)
	ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ol.position = Vector2(0, 58)
	ol.size = Vector2(width, 22)
	ol.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	ol.add_theme_constant_override("outline_size", 4)
	root.add_child(ol)
	ol.modulate.a = 0.0
	# 뒤집기 —— 가로 크기 0 → 1 (A 먼저, B 0.1초 뒤), 1.2초 머문 뒤 0.25초에 사라진다
	for c in [ca, cb]:
		c.pivot_offset = Vector2(cw / 2.0, 26)
		c.scale = Vector2(0.0, 1.0)
	var delay := 1.1 if int(e.get("stage", 1)) == 1 else 0.0      # 1단계는 시작 진형 이름 띠(가운데 1초 남짓)가 걷힌 뒤에
	root.modulate.a = 0.0
	(func():
		if not is_instance_valid(root):
			return
		var t := root.create_tween()
		t.tween_interval(delay)
		t.tween_property(root, "modulate:a", 1.0, 0.06)
		t.tween_property(ca, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(cb, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(ol, "modulate:a", 1.0, 0.12)
		t.tween_interval(1.2)
		t.tween_property(root, "modulate:a", 0.0, 0.25)
		t.tween_callback(root.queue_free)).call_deferred()
	return root


static func _rv_card(ent: Dictionary, w: float, team: Color) -> Control:
	var P := DB.PAL
	var id := str(ent.get("id", ""))
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.size = Vector2(w, 52)
	pc.custom_minimum_size = Vector2(w, 52)
	var sb := UI.flat(Color(P.ink, 0.92), Color(team, 0.9), 1, UI.R, 6)
	sb.border_width_left = 3
	if id != "":
		sb.border_width_top = 2
		sb.border_color = Color(team, 0.9)
	pc.add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := id if id != "" else "군략 없음"
	if bool(ent.get("x", false)):
		nm += " (무효)"
	elif str(ent.get("via", "")) != "":
		nm = "%s ← %s" % [nm, ent.via]
	var nl := UI.lbl(nm, UI.FS_LABEL if nm.length() <= 7 else UI.FS_BODY, P.paper if id != "" else P.text_dim, true)
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	if id != "":
		var h := UI.hbox(3)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fam := str(ent.get("fam", ""))
		var g := Glyph.new(fam.split("·")[0], P.bamboo, 12)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(g)
		var fl := UI.lbl(fam if fam != "" else "계열 없음", UI.FS_CAP, P.text_dim)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(fl)
		v.add_child(h)
	pc.add_child(v)
	return pc


## 점검용 (--gtac) —— 내 손패에 늘 켜짐 · 영구 효과 · 지난 대전을 몇 장 쥐여 주고, 온라인 가짜 방(--gsheet=onwar:…)이면 다른 사람 자리에
## 계획 · 상시 효과 · 지난 대전을 서버처럼 채운다 (계획은 Run.tk_plan_open 이 아닌 단계면 비운다 —— Room.info 와 같다). 저장하지 않는다
static func dev_fill(gs) -> void:
	var run: Run = gs.run
	for id in ["서량 철기", "철기 돌격", "장벽"]:
		run.tk_hand[id] = maxi(1, int(run.tk_hand.get(id, 0)))
	run.tk_perm = {"parts": [{"k": "spd", "v": 0.1, "who": ["기병"]}, {"k": "atk", "v": 0.08, "who": ["궁병"]}, {"k": "spd", "v": 0.1, "who": ["기병"]}],
		"notes": ["명마", "병종 단련 (궁병)", "사기 진작", "명마"], "morale": 10}
	run.tk_hist = [["돌격", "방진", "우회"], ["철기 돌격", "방진", "돌격"]]
	if gs.online == null or not gs.online.in_game:
		gs.render()
		return
	var room: Dictionary = gs.online.room
	var st := str(room.get("stage", ""))
	var demo := [
		{"plan": ["철기 돌격", "우회", "방진"], "tk": {"own": ["창림"], "perm": ["철갑", "명마"], "hist": [["돌격", "장벽", "우회"]]}},
		{"plan": ["화공", "위보", "돌격"], "tk": {"own": ["신산귀모"], "perm": ["사기 진작", "군의"], "hist": [["화공", "방진", "돌격"]]}},
		{"plan": ["일제 사격", "방진", "궁진"], "tk": {"own": [], "perm": ["강궁"], "hist": []}}]
	var j := 0
	var seats: Array = room.get("seats", [])
	for k in seats.size():
		if k == int(room.get("you", -1)) or not bool(seats[k].get("human", false)):
			continue
		var d: Dictionary = demo[j % demo.size()]
		j += 1
		seats[k]["plan"] = (d.plan as Array).duplicate() if Run.tk_plan_open(st) else []
		seats[k]["tk"] = (d.tk as Dictionary).duplicate(true)
	if room.get("foe") is Dictionary:
		room.foe["tac"] = [["돌격", "장벽", "우회"]]
	gs.render()
