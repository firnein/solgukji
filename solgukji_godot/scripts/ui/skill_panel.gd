extends PanelContainer
## 세 장수 정보창이 공유하는 기술 목록. 이름·주기 / 효과 / 조건의 순서로 읽는다.
const SS := preload("res://scripts/ui/sheet_style.gd")
var entries := []
var rows := {}

class RuntimeRow extends MarginContainer:
	var pulse := 0.0
	func set_pulse(value: float) -> void:
		if is_equal_approx(pulse, value):
			return
		pulse = value
		queue_redraw()
	func _draw() -> void:
		if pulse <= 0.0:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.56, 0.83, 0.76, pulse * 0.09))
		draw_line(Vector2(1, 3), Vector2(1, size.y - 3), Color(0.56, 0.83, 0.76, pulse * 0.8), 2.0)

static func escape_spec(k: String) -> Dictionary:
	var ps = DB.passives_of(k)
	var blink: bool = ps != null and ps.traits.any(func(t): return float(t.m.get("blink", 0.0)) > 0.0)
	if blink:
		return {"name": "선술", "cd": preload("res://scripts/sig_rt.gd").BLINK_CD, "effect": "홀연히 뒤로 이동해 붙잡은 적에게서 벗어남"}
	var info: Dictionary = RtBattle.ESCAPE.get(DB.C[k].tag, {})
	if info.is_empty():
		return {}
	var effect := "뒤로 이동해 붙잡은 적에게서 벗어남"
	if info.has("push"):
		effect = "붙은 적을 밀쳐냄 · 적 행동 %s 지연" % DB.sec_str(float(info.delay))
	elif info.has("confuse"):
		effect = "붙잡은 근접 적에게 혼란"
	elif info.has("wide"):
		effect = "뒤로 이동 · %s 동안 아군 구원 범위 확대" % DB.sec_str(float(info.wide))
	return {"name": info.n, "cd": RtBattle.ESCAPE_CD, "effect": effect}

static func escape_event(event: Dictionary, key: String, spec: Dictionary) -> Dictionary:
	if str(event.get("f", "")) != key:
		return {}
	if event.has("escape"):
		return {"name": str(event.escape), "cd": float(event.get("escape_cd", spec.get("cd", RtBattle.ESCAPE_CD))), "approx": false}
	# 과거 기록은 이름만 있었으므로 정확한 발동 문장만 받아 현재 규칙으로 대기 시간을 추정한다.
	if not spec.is_empty() and event.get("sig", false) and event.get("fx") == "buff":
		if str(event.get("t", "")).get_slice(" —— ", 0).ends_with("의 " + str(spec.name)):
			return {"name": spec.name, "cd": spec.cd, "approx": true}
	return {}

func enable_runtime() -> void:
	for entry in entries:
		if entry.kind != "escape":
			continue
		var row: Dictionary = rows[entry.id]
		row.live.visible = true
		row.status.text = "조건 대기"
		row.count.text = "0회 발동"
		row.progress.visible = true
		row.progress.value = 1.0

func setup(items: Array, compact := false) -> Control:
	name = "CombatSkills"
	entries = items.duplicate(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", UI.flat(SS.WELL, SS.LINE, 1, 6, 0))
	var stack := UI.vbox(0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	for i in entries.size():
		if i > 0:
			var line := MarginContainer.new()
			line.add_theme_constant_override("margin_left", 10)
			line.add_theme_constant_override("margin_right", 10)
			line.add_child(UI.hair())
			stack.add_child(line)
		var entry: Dictionary = entries[i]
		var margin := RuntimeRow.new()
		for edge in ["left", "right"]:
			margin.add_theme_constant_override("margin_" + edge, 10)
		for edge in ["top", "bottom"]:
			margin.add_theme_constant_override("margin_" + edge, 5)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(margin)
		var body := UI.vbox(2)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(body)
		var header := UI.hbox(6)
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var color: Color = SS.VAL if entry.kind == "escape" else (SS.ATK if entry.damage == "phys" else SS.ATK_INT)
		var symbol := Icons.View.new("boot" if entry.kind == "escape" else ("blade" if entry.damage == "phys" else "news"), color, 15)
		symbol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(symbol)
		var title := UI.lbl(entry.name, 14, SS.TEXT, true)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.wrap_text(title)
		header.add_child(title)
		var period := SS.chip(entry.period, color, "well")
		period.visible = entry.period != ""
		header.add_child(period)
		body.add_child(header)
		if compact:
			var effect := UI.lbl(entry.effect, 12, SS.DIM)
			effect.clip_text = true
			effect.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			effect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			body.add_child(effect)
		else:
			var effect := UI.rich(entry.effect_bb, 13)
			effect.add_theme_color_override("default_color", SS.TEXT)
			effect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			body.add_child(effect)
		var footer := UI.hbox(5)
		footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var category := UI.lbl("이탈" if entry.kind == "escape" else ("연계" if entry.kind == "minor" else "발동"), 10, color)
		category.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		footer.add_child(category)
		var condition := UI.lbl(entry.condition, 11 if compact else 12, SS.DIM)
		condition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.wrap_text(condition)
		footer.add_child(condition)
		footer.visible = entry.condition != "" and not compact
		body.add_child(footer)
		var live := UI.hbox(5)
		live.visible = false
		var status := UI.lbl("", 11, SS.VAL, true)
		live.add_child(status)
		var count := UI.lbl("", 10, SS.DIM)
		count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		live.add_child(count)
		body.add_child(live)
		var progress := ProgressBar.new()
		progress.show_percentage = false
		progress.max_value = 1.0
		progress.custom_minimum_size.y = 2
		progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		progress.add_theme_stylebox_override("background", UI.flat(Color(color, 0.10), Color.TRANSPARENT, 0, 1, 0))
		progress.add_theme_stylebox_override("fill", UI.flat(color, Color.TRANSPARENT, 0, 1, 0))
		progress.visible = false
		body.add_child(progress)
		rows[entry.id] = {"root": margin, "live": live, "status": status, "count": count, "progress": progress, "period": period, "key": ""}
	return self

func update_runtime(states: Dictionary, now: float, alive: bool, done: bool) -> void:
	for entry in entries:
		var row: Dictionary = rows[entry.id]
		var state: Dictionary = states.get(entry.id, {})
		if state.is_empty():
			if entry.kind == "escape":
				row.status.text = "전투 종료" if done else ("전투 불가" if not alive else "조건 대기")
				row.progress.visible = alive and not done
			continue
		var used := int(state.get("n", 0))
		var age := maxf(0.0, now - float(state.tm))
		var cooldown := float(state.get("cd", 0.0))
		var left := maxf(0.0, cooldown - age)
		var remaining := ("약 " if state.get("approx", false) else "") + "%.1f초" % left
		var text := "방금 발동" if age < 1.2 else ("재사용 " + remaining if left > 0.0 else "조건 대기")
		if done or not alive:
			text = "전투 종료" if done else "전투 불가"
		elif entry.kind != "escape" and age >= 1.2:
			text = "최근 발동"
		var key := "%s|%d" % [text, used]
		if row.key != key:
			row.key = key
			row.live.visible = true
			row.status.text = text
			row.count.text = "%d회 발동" % used
			row.status.modulate = SS.VAL if age < 1.2 or left <= 0.0 else SS.DIM
		row.progress.visible = entry.kind == "escape" and not done and alive and cooldown > 0.0
		if row.progress.visible:
			row.progress.value = clampf(age / cooldown, 0.0, 1.0)
		row.root.set_pulse(0.0 if done or not alive else clampf(1.0 - age / 1.2, 0.0, 1.0))
