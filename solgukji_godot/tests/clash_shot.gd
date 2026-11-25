extends Control
## 11/25 고유기 받아치기 사선 컷인 캡처 —— 실행 (창이 뜬다 · 휴대폰 세로 540x1200):
##   godot --path . --resolution 540x1200 res://tests/clash_shot.tscn -- --in=C:/.../real_battles.json [--bi=146] [--at=0.75] [--out=폴더]
## 실제 대전 기록 한 판(--bi)을 받아치기 켜고 돌린 뒤 BattleView(삽화)로 틀고, 첫 받아치기 사건(ult_clash)의 컷인을 바로 띄워 --at 초에 저장한다 (clash_cut.png)

var _args := {}


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.cam_fx = 0
	Settings.apply()
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sw = load("res://tests/real_myth_swap.gd").new()
	for k in DB.C:
		if DB.is_foe(k):
			continue
		var c: Dictionary = DB.C[k]
		var key := JSON.stringify([c.name, int(c.tier), c.tag])
		if not sw.idx.has(key) or DB.C[sw.idx[key]].kind == "retired":
			sw.idx[key] = k
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(str(_args.get("in", ""))))
	var b: Dictionary = rows[int(_args.get("bi", "146"))]
	var me: Dictionary = sw._side(b.me)
	var foe: Dictionary = sw._side(b.foe)
	var bt := RtBattle.new(int(b.seed))
	var r: Dictionary = sw._run_bt(bt, me, foe, {}, false)
	var ce = null
	var want_chain := _args.has("chain")      # 11/26 --chain : 받아치기 연쇄(짝이 붙은 받아치기)가 나오는 판을 찾아 그 컷인을 찍는다
	var bi := int(_args.get("bi", "146"))
	for tries in (rows.size() if want_chain else 1):
		for e in r.ev:
			if e.get("fx") == "ult_clash" and (not want_chain or (e.get("chain", {}) as Dictionary).size() >= int(_args.get("chain", "1"))):
				ce = e
				break
		if ce != null or not want_chain:
			break
		bi = (bi + 1) % rows.size()
		b = rows[bi]
		if float(b.get("av", 6.0)) < 5.5 and b.has("av"):
			continue
		me = sw._side(b.me)
		foe = sw._side(b.foe)
		bt = RtBattle.new(int(b.seed))
		r = sw._run_bt(bt, me, foe, {}, false)
	print("판 %d" % bi)
	print("받아치기 %d번 · 첫 사건 %s" % [r.ev.filter(func(e): return e.get("fx") == "ult_clash").size(), str(ce.t) if ce != null else "없음"])
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	Settings.apply_port(view.port)
	view.play_res(r, "pvp", {"a": me.cards, "fa": me.form, "ma": me.morale, "ea": me.equip, "b": foe.cards, "fb": foe.form, "mb": foe.morale, "eb": foe.equip,
		"seed": int(b.seed), "title": "받아치기 점검", "foe": "적군", "policy": {}})
	for i in 30:
		await get_tree().process_frame
	if ce == null:
		get_tree().quit()
		return
	if _args.has("fake"):      # 11/26 --fake=N : 양쪽 N명 연쇄 받아치기를 꾸며 컷인만 본다 (배치 확인용 —— 실제 사건이 아니다)
		var pick := func(names: Array) -> Array:
			var out := []
			for nm in names:
				var best := ""
				for k in DB.C:
					if DB.is_foe(k) or DB.person(k) != nm or not DB.has_ult(k):
						continue
					if best == "" or int(DB.C[k].tier) > int(DB.C[best].tier):
						best = k
				if best != "":
					out.append({"k": best, "who": str(DB.C[best].name), "name": str(DB.ult_of(best).name), "tier": int(DB.C[best].tier), "first": out.is_empty(),
						"say": BattleView.Hud.short_shout(nm, str(DB.ult_of(best).get("shout", "")))})
			return out
		var n := int(_args.get("fake", "4"))
		view.hud.clash_cutin(pick.call(["유비", "관우", "장비", "조운", "황충"].slice(0, n)), pick.call(["조조", "하후돈", "하후연", "조인", "장료"].slice(0, n)), false, {"A": "오호대장", "B": "조씨 일족"})
	else:
		view._ult_clash(ce)
	var at := float(_args.get("at", "0.75"))
	var out := str(_args.get("out", "user://"))
	var t_end := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var cut = view.hud.cut
		if cut != null and cut.has("clash") and cut.t >= at:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/clash_cut.png" % out)
			print("캡처 cut.t=%.2f 크기 %s" % [cut.t, str(get_viewport().get_visible_rect().size)])
			break
	get_tree().quit()
