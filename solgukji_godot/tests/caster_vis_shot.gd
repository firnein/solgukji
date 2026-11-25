extends Control
## 11/25 책략계 기여 표시 점검 (삽화 화면) —— 실제 온라인 대전 기록의 덱으로 전투를 틀고, 책략계 사건 직후 장면을 찍는다. 창이 뜬다:
##   godot --path . --resolution 540x1200 res://tests/caster_vis_shot.tscn -- --log=<playlog_online/….jsonl> --day=3 --ph=2 [--side=me] [--out=폴더] [--tag=after]
##   기록의 battle_start(kind pvp) 줄에서 me / foe 카드(이름 · 등급 · 병종 → DB id) · 진형 · 군략 · 사기 · 시드를 그대로 쓴다 (장비는 개수만 남아 빈 채로).
##   찍는 장면 (그 판에 있으면): spell(책략 평타 투사체) · buff(버프 · 디버프 연결) · confuse(혼란) · omen(천문 막) · cast(책략 기술 발동) · ult(신화 제갈량 고유기 직후)
##   찍을 때마다 노드 수 · 삽화 위층 그리기 누적 시간을 적고, 끝에 판 전체 최고 노드 수와 결과가 그리는 동안 바뀌지 않았는지(JSON 비교)를 적는다.
## 저장 · 기록을 만들지 않는다 (PlayLog 끔 · 설정 저장 안 함).

var _args := {}
const CASTER_TAGS := ["책사", "유생", "술사", "모사"]


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = true
	Settings.cam_fx = 0
	Settings.apply()
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bt := _battle_from_log(str(_args.get("log", "")), int(_args.get("day", "3")), int(_args.get("ph", "2")), str(_args.get("side", "me")))
	if bt.is_empty():
		print("CASTERVIS|기록에서 전투를 찾지 못함")
		get_tree().quit(1)
		return
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	Settings.apply_port(view.port)
	await view.play(bt, false)
	view._set_speed(1.0)
	var wp = view.type2.painting if view.type2 != null else null
	if wp == null:
		print("CASTERVIS|삽화 화면이 아님")
		get_tree().quit(1)
		return
	var source := JSON.stringify(view.res)
	var out := str(_args.get("out", "user://"))
	var tag := str(_args.get("tag", "shot"))
	var shots := _pick_moments(view)
	print("CASTERVIS|장면 %s" % JSON.stringify(shots.map(func(s): return [s[0], snappedf(s[1], 0.01)])))
	var peak_nodes := 0
	var base_nodes := get_tree().get_node_count()
	for s in shots:
		var at: float = s[1]
		if view.clock < at - 2.0:
			view.fast_to(at - 1.6)
		while view.clock < at and not view.finished:
			await get_tree().process_frame
			peak_nodes = maxi(peak_nodes, get_tree().get_node_count())
			_sample(view)
		if view.finished:
			break
		await RenderingServer.frame_post_draw
		var path := "%s/%s_%s.png" % [out, tag, s[0]]
		get_viewport().get_texture().get_image().save_png(path)
		var prof: Dictionary = view.field.prof if view.field != null else {}
		var sq: Squad = view.field.squads.get(s[3])
		var scr: Vector2 = wp.get_global_transform_with_canvas() * wp.v.map(sq.pos) if sq != null else Vector2(-1, -1)
		print("CASTERVIS|찍음 %s|시각 %.2f|노드 %d|위층 누적 %.1fms|%s|화면 %d,%d" % [s[0], view.clock, get_tree().get_node_count(),
			float(prof.get("삽화 위층", 0)) / 1000.0, s[2], roundi(scr.x), roundi(scr.y)])
	# 판 끝까지 1배속으로 보며 노드 수 · 그리기 시간 최고치
	var t_end: float = view.clock + float(_args.get("tail", "0"))
	while view.clock < t_end and not view.finished:
		await get_tree().process_frame
		peak_nodes = maxi(peak_nodes, get_tree().get_node_count())
		_sample(view)
	print("CASTERVIS|노드 시작 %d · 최고 %d" % [base_nodes, peak_nodes])
	for k in _cost:
		var c: Array = _cost[k]
		print("CASTERVIS|그리기 %s: 프레임 %d · 평균 %.3fms · 최고 %.2fms" % [k, int(c[2]), float(c[0]) / maxf(1.0, float(c[2])) / 1000.0, float(c[1]) / 1000.0])
	if wp.get("caster_stats") != null:
		print("CASTERVIS|그린 것 %s" % JSON.stringify(wp.caster_stats))
	assert(JSON.stringify(view.res) == source, "그리기가 전투 결과를 바꾸면 안 된다")
	print("CASTERVIS|결과 불변 OK")
	get_tree().quit()


## 프레임마다 삽화 그리기 시간 (War3D.prof 누적의 차) —— [합, 최고, 프레임 수]
var _cost := {"삽화 위층": [0, 0, 0], "삽화 그리기": [0, 0, 0]}
var _last := {}
func _sample(view) -> void:
	if view.field == null:
		return
	var prof: Dictionary = view.field.prof
	for k in _cost:
		var now := int(prof.get(k, 0))
		var d := now - int(_last.get(k, now))
		_last[k] = now
		if d > 0:
			_cost[k][0] += d
			_cost[k][1] = maxi(_cost[k][1], d)
			_cost[k][2] += 1


## 기록 한 줄 → bt
func _battle_from_log(path: String, day: int, ph: int, side: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	while not f.eof_reached():
		var line := f.get_line()
		if not line.contains("\"battle_start\""):
			continue
		var d = JSON.parse_string(line)
		if not d is Dictionary or d.get("ev") != "battle_start" or d.get("kind") != "pvp" or int(d.get("day", -1)) != day or int(d.get("phase", -1)) != ph:
			continue
		var mine: Dictionary = d.me if side == "me" else d.foe
		var foe: Dictionary = d.foe if side == "me" else d.me
		var fa := str(d.form if side == "me" else d.foe_form)
		var fb := str(d.foe_form if side == "me" else d.form)
		var a := {"cards": DB.auto_place(_ids(mine.cards), fa), "form": fa, "morale": float(d.morale if side == "me" else d.foe_morale),
			"tac": str(d.tac if side == "me" else d.foe_tac), "equip": []}
		var b := {"cards": DB.auto_place(_ids(foe.cards), fb), "form": fb, "morale": float(d.foe_morale if side == "me" else d.morale),
			"tac": str(d.foe_tac if side == "me" else d.tac), "equip": []}
		print("CASTERVIS|기록 %s %d일차 %d단계 시드 %s|아군 %s|적 %s" % [path.get_file(), day, ph, str(d.seed),
			", ".join(mine.cards.map(func(c): return str(c[0]))), ", ".join(foe.cards.map(func(c): return str(c[0])))])
		return {"kind": "pvp", "a": a, "b": b, "seed": int(d.seed), "title": "책략계 표시 점검", "foe": "기록 상대", "inputs": []}
	return {}


func _ids(cards: Array) -> Array:
	var out := []
	for c in cards:
		for k in DB.C:
			if str(DB.C[k].name) == str(c[0]) and int(DB.C[k].tier) == int(c[1]) and str(DB.C[k].tag) == str(c[2]):
				out.append(k)
				break
	return out


## 책략계 사건마다 첫 장면 (화면 시각 = OPEN_RT + 엔진 시각)
func _pick_moments(view) -> Array:
	var res: Dictionary = view.res
	var tag_of := {}
	var zhuge := ""
	for u in res.roster:
		tag_of[u.key] = str(u.tag)
		if str(u.get("id", "")) == "c187":
			zhuge = u.key
	var want := {}
	var omen_t := -1.0
	for e: Dictionary in res.ev:
		var tm := BattleView.OPEN_RT + float(e.get("tm", 0.0))
		if tm < 4.0:
			continue
		var fx := str(e.get("fx", ""))
		var who := str(e.get("who", ""))
		var caster := CASTER_TAGS.has(str(tag_of.get(who, "")))
		if fx == "int" and str(e.get("a", "")) == (zhuge if zhuge != "" else str(e.get("a", ""))) and not want.has("spell"):
			want["spell"] = [tm + 0.3, "책략 평타 날아가는 중", str(e.get("f", ""))]
		elif fx == "buff" and caster and str(e.get("f", "")) != who and not want.has("buff"):
			want["buff"] = [tm + 0.4, "버프/디버프 연결 %s→%s" % [who, e.get("f", "")], str(e.get("f", ""))]
		elif fx == "debuff" and caster and not want.has("buff"):
			want["buff"] = [tm + 0.4, "디버프 연결 %s→%s" % [who, e.get("f", "")], str(e.get("f", ""))]
		elif fx == "status" and str(e.get("st", "")) == "confuse" and not want.has("confuse"):
			want["confuse"] = [tm + 0.5, "혼란 %s" % e.get("f", ""), str(e.get("f", ""))]
		elif fx == "skill" and str(e.get("name", "")) == "천문":
			omen_t = tm
		elif fx == "ult_warn" and omen_t >= 0.0 and absf(tm - omen_t) < 0.5 and not want.has("omen"):
			var wk: Array = e.get("warn", [])
			want["omen"] = [tm + 0.9, "천문 막 (%s 기 모으기)" % e.get("a", ""), str(wk[0].k) if not wk.is_empty() else ""]
		elif fx == "skill" and caster and str(e.get("a", "")) == who and not want.has("cast"):
			want["cast"] = [tm + 0.3, "책략 기술 %s" % e.get("name", ""), who]
		elif fx == "ult" and zhuge != "" and str(e.get("a", "")) == zhuge and not want.has("ult"):
			want["ult"] = [tm + 0.9, "제갈량 고유기 직후", zhuge]
	var shots := []
	for k in want:
		shots.append([k, float(want[k][0]), str(want[k][1]), str(want[k][2])])
	shots.sort_custom(func(x, y): return x[1] < y[1])
	return shots
