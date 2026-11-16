extends Control
## Painted representatives follow replay positions. No battle rules or random state are changed.
var v
var atlas: Texture2D
var cells: Array[AtlasTexture] = []
var ratios := {}
var last_clock := -1.0
const INK := Color("#29271f")
const PAPER := Color("#e3cfa1")
const BLUE := Color("#405c7c")
const RED := Color("#934a3b")
const TAGS := ["창병", "기병", "궁병", "도적", "책사", "유생", "술사", "모사"]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	atlas = load("res://assets/war_painting/troops_01.png")
	var cell := atlas.get_size() / 4.0
	for i in 16:
		var t := AtlasTexture.new()
		t.atlas = atlas
		t.region = Rect2(Vector2(i % 4, i / 4) * cell, cell)
		t.filter_clip = true
		cells.append(t)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func reset() -> void:
	ratios.clear()
	last_clock = -1.0

func _process(_dt: float) -> void:
	if not is_visible_in_tree() or v == null or v.field == null:
		return
	var elapsed := 0.0 if last_clock < 0 else clampf(float(v.field.clock) - last_clock, 0.0, 0.25)
	last_clock = v.field.clock
	for sq: Squad in v.field.order:
		var goal := clampf(sq.troops / maxf(1.0, sq.max), 0.0, 1.0)
		# Freeze with the replay; transition troop losses instead of popping bodies.
		ratios[sq.key] = move_toward(float(ratios.get(sq.key, 1.0)), goal, elapsed * 1.8)
	queue_redraw()

func _draw() -> void:
	if v == null or v.field == null or cells.is_empty():
		return
	var groups: Array = v.field.order.duplicate()
	groups.sort_custom(func(a, b): return v.map(a.pos).y < v.map(b.pos).y)
	var figures: Array = []
	for sq: Squad in groups:
		if sq.state == "gone" or sq.fade <= 0.01:
			continue
		var tag := maxi(0, TAGS.find(sq.tag))
		var team := BLUE if sq.camp == "A" else RED
		var ratio: float = ratios.get(sq.key, 1.0)
		var cavalry := tag == 1
		var support := tag >= 4
		var cols := 3 if cavalry or support else 4
		var ranks := 3 if cavalry else (1 if support else 2)
		var width := minf(sq.hw * 1.65, 155.0)
		var depth := minf(sq.hd0 * 1.55, 125.0)
		var perspective: float = v.depth_scale(sq.pos)
		var h := clampf(95.0 * v._scale, 32.0, 64.0) * perspective * (1.15 if cavalry else 1.0)
		var hit := maxf(0.0, 1.0 - (v.field.clock - sq.hurt_at) / 0.3)
		var weak := clampf((50.0 - sq.morale) / 50.0, 0.0, 1.0)
		var slots := 6 if cavalry else cols * ranks
		var alive_slots := maxi(0, ceili(ratio * slots))
		var n := 0
		for row in ranks:
			var row_cols := row + 1 if cavalry else cols
			for col in row_cols:
				# Deterministic ordering leaves irregular holes in the FRONT first.
				var loss_order := (ranks - 1 - row) * cols + ((col + row) % cols)
				if cavalry:
					loss_order = n
				var alive := loss_order < alive_slots
				var lateral := (float(col) - float(row_cols - 1) * 0.5) * width / float(cols - 1)
				var forward := (float(ranks - 1) * 0.5 - row) * depth / maxf(1.0, float(ranks - 1))
				# A hit buckles the shield wall; low morale opens the formation.
				forward -= hit * (12.0 if row == 0 else 4.0) * (0.6 + 0.4 * sin(col * 1.7))
				lateral *= 1.0 + weak * 0.25
				var at := sq.pos + sq.right() * lateral + sq.fwd * forward
				var p: Vector2 = v.map(at)
				var phase := float(n) * 1.7 + float(sq.row.slot)
				if sq.state == "flee":
					p += Vector2(sin(phase), cos(phase)) * (8.0 + weak * 6.0)
				elif sq.moving:
					p.y -= absf(sin(v.field.clock * 7.0 + phase)) * 1.2
				var attack := clampf((v.field.clock - sq.act_t) / 0.45, 0.0, 1.0)
				if sq.contact and alive:
					p += (v.map(sq.pos + sq.fwd * 8.0) - v.map(sq.pos)) * sin(attack * PI)
				figures.append({"p": p, "h": h, "cell": tag + (0 if sq.camp == "A" else 8), "fade": sq.fade, "alive": alive, "phase": phase, "hurt": hit})
				n += 1
		_draw_dust(sq, width, team)
		figures.append({"p": v.map(sq.pos - sq.fwd * (sq.hd0 * 0.65)), "sq": sq, "kind": "standard"})
	# Global depth order is important where two formations meet.
	v.drawn_figs = figures.size() - groups.size()
	figures.sort_custom(func(a, b): return a.p.y < b.p.y)
	for f in figures:
		if f.has("sq"):
			_draw_standard(f.sq)
			continue
		var p: Vector2 = f.p
		var h: float = f.h
		if not f.alive:
			# A subdued ground silhouette marks a gap; no spinning or airborne body.
			draw_set_transform(p, 0.25 * sin(f.phase), Vector2(1.0, 0.28))
			draw_texture_rect(cells[f.cell], Rect2(-h * 0.5, -h * 0.5, h, h), false, Color(0.28, 0.25, 0.22, f.fade * 0.25))
			draw_set_transform(Vector2.ZERO)
			continue
		draw_set_transform(p + Vector2(0, -1), 0, Vector2(1.0, 0.28))
		draw_circle(Vector2.ZERO, h * 0.20, Color(0.12, 0.1, 0.07, 0.20 * f.fade))
		draw_set_transform(Vector2.ZERO)
		draw_texture_rect(cells[f.cell], Rect2(p - Vector2(h * 0.5, h * 0.85), Vector2(h, h)), false, Color(1.0, 1.0 - f.hurt * 0.12, 1.0 - f.hurt * 0.15, f.fade))
	for sq: Squad in groups:
		if sq.state != "gone" and sq.fade > 0.01:
			_draw_status(sq)
			_draw_volley(sq)
	_draw_links()

func _draw_links() -> void:
	if v.view == null or v.view.hud == null:
		return
	for e in v.view.hud._deck_links:
		var a: Squad = v.field.squads.get(e.a)
		var b: Squad = v.field.squads.get(e.b)
		if a == null or b == null or not a.alive or not b.alive:
			continue
		var t := clampf((float(v.view.clock) - float(e.t)) / 0.85, 0.0, 1.0)
		for j in 3:
			var u := clampf(t * 1.3 - j * 0.06, 0.0, 1.0)
			var world: Vector2 = a.pos.lerp(b.pos, u)
			var at: Vector2 = v.map(world) + Vector2(0, -sin(u * PI) * 15.0 * v.depth_scale(world))
			draw_circle(at, 2.5 - j * 0.5, Color(e.col, (1.0 - t) * 0.85))

func _draw_dust(sq: Squad, width: float, _team: Color) -> void:
	if not sq.contact and not sq.moving:
		return
	for j in 3:
		var phase := fposmod(v.field.clock * 0.8 + j * 0.33, 1.0)
		var at: Vector2 = sq.pos + sq.right() * (j - 1) * width * 0.3
		if sq.contact:
			at += sq.fwd * sq.hd()
		else:
			at -= sq.fwd * sq.hd()
		draw_circle(v.map(at), (4.0 + phase * 7.0) * v.depth_scale(at), Color(0.72, 0.64, 0.46, sin(phase * PI) * 0.13 * sq.fade))

func _draw_standard(sq: Squad) -> void:
	var team := BLUE if sq.camp == "A" else RED
	var p: Vector2 = v.map(sq.pos - sq.fwd * (sq.hd0 * 0.65))
	var perspective: float = v.depth_scale(sq.pos)
	p.x -= 14.0 * perspective
	var fallen := not sq.alive or sq.state == "flee"
	var h := 42.0 * perspective
	var top := p + (Vector2(23, -8) * perspective if fallen else Vector2(0, -h))
	var a := sq.fade
	draw_line(p, top, Color(INK, a), 2.0, true)
	var wave := sin(v.field.clock * 2.5 + sq.row.slot) * 1.5
	var corners := PackedVector2Array([top, top + Vector2(17, 2 + wave) * perspective, top + Vector2(15, 16 + wave) * perspective, top + Vector2(0, 14) * perspective])
	draw_colored_polygon(corners, Color(team, a))
	corners.append(corners[0])
	draw_polyline(corners, Color(PAPER.darkened(0.25), a), 1.0, true)
	var name_: String = DB.person(sq.cid) if sq.tier > 2 else sq.row.name
	draw_string(DB.font_bold, top + Vector2(1, 11) * perspective, name_.left(1), HORIZONTAL_ALIGNMENT_CENTER, 14 * perspective, maxi(8, roundi(10 * perspective)), Color(PAPER, a))
	# Compact identity at the standard replaces a floating portrait and health plate.
	var text_: String = name_ if sq == v.field.follow else name_.left(3)
	var w := DB.font_bold.get_string_size(text_, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 6.0
	var box := Rect2(p + Vector2(-w * 0.5 + 5, 3), Vector2(w, 13))
	draw_rect(box, Color(INK, a * 0.78))
	draw_string(DB.font_bold, box.position + Vector2(0, 10), text_, HORIZONTAL_ALIGNMENT_CENTER, w, 10, Color(PAPER, a))
	if sq == v.field.follow:
		draw_rect(box, Color(PAPER, a), false, 1.0)

func _draw_status(sq: Squad) -> void:
	if not sq.alive:
		return
	var p: Vector2 = v.map(sq.pos)
	var perspective: float = v.depth_scale(sq.pos)
	if sq.statuses.has("burn"):
		for j in 4:
			var phase: float = v.field.clock * 5.0 + j * 1.7
			var base: Vector2 = v.map(sq.pos + sq.right() * (j - 1.5) * sq.hw * 0.5)
			var h := (13.0 + 5.0 * sin(phase)) * perspective
			v._spr_at(self, "flame_02", base + Vector2(0, -h * 0.45), h * 2.0, Color(1.0, 0.62, 0.20, 0.85), sin(phase) * 0.12, Vector2(0.65, 1.0))
	if sq.statuses.has("cut_def") or sq.statuses.has("cut_res"):
		var q := p + Vector2(14, -22) * perspective
		draw_set_transform(q, 0, Vector2.ONE * perspective)
		q = Vector2.ZERO
		var shield := PackedVector2Array([q + Vector2(-6, -7), q + Vector2(6, -7), q + Vector2(5, 2), q + Vector2(0, 7), q + Vector2(-5, 2), q + Vector2(-6, -7)])
		draw_polyline(shield, Color("#e6bd79"), 1.5, true)
		draw_polyline(PackedVector2Array([q + Vector2(1, -7), q + Vector2(-2, -1), q + Vector2(2, 1), q + Vector2(0, 7)]), INK, 2.5, true)
		draw_set_transform(Vector2.ZERO)
	if sq.statuses.has("flood"):
		for j in 2:
			draw_arc(p + Vector2(0, j * 3) * perspective, (13 + j * 2) * perspective, 0.1, PI - 0.1, 12, Color(0.35, 0.65, 0.75, 0.7), 1.3, true)
	if sq.statuses.has("confuse"):
		draw_arc(p + Vector2(0, -17) * perspective, 7 * perspective, v.field.clock, v.field.clock + PI * 1.6, 12, Color("#be9aca"), 1.7, true)

func _draw_volley(sq: Squad) -> void:
	if not sq.alive or sq.act_tgt == null or sq.act_kind not in ["shoot", "cast"]:
		return
	var t: float = (v.field.clock - sq.act_t) / 0.65
	if t < 0 or t > 1:
		return
	var world: Vector2 = sq.pos.lerp(sq.act_tgt.pos, t)
	var perspective: float = v.depth_scale(world)
	for j in (3 if sq.act_kind == "shoot" else 1):
		var offset := Vector2((j - 1) * 5.0 * perspective, 0)
		var at: Vector2 = v.map(world) + Vector2(0, -sin(t * PI) * 22.0 * perspective) + offset
		var prev_t := maxf(0.0, t - 0.05)
		var prev: Vector2 = v.map(sq.pos.lerp(sq.act_tgt.pos, prev_t)) + Vector2(0, -sin(prev_t * PI) * 22.0 * perspective) + offset
		draw_line(prev, at, Color("#e3c78f") if sq.act_kind == "shoot" else Color("#de7f3f"), 1.4, true)
