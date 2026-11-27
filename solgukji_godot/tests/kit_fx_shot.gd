extends Control
## 11/27 장수 키트 Q · W · E · R · P 발동 표시 점검 · 캡처 (삽화 화면) —— 사용자: 「쟤가 q 스킬이 발동됐구나, e 가 발동됐구나를 알 수 있어야 함」
## 화면 없이 (스크립트 오류 · 칸 풀이 · 표시 대기열이 만들어지는가):
##   godot --headless --path . res://tests/kit_fx_shot.tscn
## 캡처 (창이 뜬다 · 휴대폰 세로 540x1200):
##   godot --path . --resolution 540x1200 res://tests/kit_fx_shot.tscn -- --png [--out=D:/solgukji-main/captures/kit] [--seed=5100] [--states=폴더] [--perf]
##
## 하는 일 (11/27 저녁 새 방식 —— 칸마다 고유 강화 하나 · 사건 필드 "slot" · "up" · "kup")
##   0) 칸 풀이(KitFx.resolve) 검사 —— slot 이 있을 때 · 없을 때(대비책: 기술 이름 = Kit.cell(카드, 칸).n · 옛 카드 기술 이름, 고유기 → r, 개성 말풍선 → p),
##      up 읽기(buff 꼴의 up 은 읽지 않는다 · 옛 augs), 강화 이름 → 칸(up_slot), 밀어내는 강화(up_pushes), 키트가 아닌 장수
##   1) 보통 덱 판 —— 신화 1 ~ 2명 + 나머지는 7성 이하. 엔진 결과를 그대로 재생. Q 가 발동한 순간 한 장 (kitfx2_q.png)
##   2) 강화 판 —— 같은 결과에 새 필드를 직접 넣는다(엔진 갈래 병합 전): 명단의 "kit": [강화한 칸 …] · 그 칸 사건에 "up": true ·
##      그 기술이 맞힌 첫 사건에 "kup": 강화 이름. 강화된 발동 한 장 (kitfx2_up.png) · 강화 이름이 뜬 순간 한 장 (kitfx2_kup.png)
##   --states=폴더 : 상태 기호(봉인 · 도발 · 불사 · 출혈 · 역병 · 은신)를 몇 부대에 넣어 한 장 더 (그 폴더에 kitfx2_state.png —— 확인용)
##   --perf : 강화 판을 키트 표시 끄고 · 켜고 세 번씩 돌려 프레임 시간과 그리기 명령을 만드는 데 쓴 시간(딱지 · 삽화)을 적는다
##            (수직동기 끔 —— PC 수치, 휴대폰 실측 아님. --perf=2 는 한 번씩만)
## 판마다 띄운 딱지 수(칸별 · 강화 · 강화 이름 · 밀려남) · 삽화 고리 수 · 맞은 표식 수 · 동시에 떠 있던 최대 수를 적는다. 저장 · 기록을 만들지 않는다.

const Kit := preload("res://scripts/kit.gd")
const KitFx := preload("res://scripts/field/painted_kit.gd")
const A_MYTH := ["c177", "c197"]      # 관우 · 감녕 —— 내 덱의 신화 둘
const B_MYTH := ["c181"]              # 여포 —— 적 덱의 신화 하나
const UPS := {"c177": ["q", "w"]}     # 강화 판에서 강화한 칸 (관우 Q 「연참」 · W 「격퇴」) —— 감녕 · 여포는 강화 없음

var _args := {}
var _out := "D:/solgukji-main/captures/kit"
var _fail := 0
var _pick := ""      # 방금 고른 장면 (누가 무엇을 누구에게)


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	get_tree().create_timer(540.0, true, false, true).timeout.connect(func(): get_tree().quit(1))
	_out = str(_args.get("out", _out))
	var headless := DisplayServer.get_name() == "headless"
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = true
	Settings.cam_fx = 0
	Settings.ult_fx = 2      # 간단히 —— 컷인 · 슬로모션 없이 (말풍선에 R 딱지)
	Settings.apply()
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _args.has("png"):
		DirAccess.make_dir_recursive_absolute(_out)
	_check_resolve()
	var a: Array = DB.auto_place(_deck(A_MYTH, 0), "eorin")
	var b: Array = DB.auto_place(_deck(B_MYTH, 3), "hagik")
	print("KITFX|내 덱 %s" % str(a.map(func(k): return "%s%d" % [DB.person(str(k)), int(DB.C[str(k)].tier)] if k != null else "-")))
	print("KITFX|적 덱 %s" % str(b.map(func(k): return "%s%d" % [DB.person(str(k)), int(DB.C[str(k)].tier)] if k != null else "-")))
	var result: Dictionary = RtBattle.new(int(_args.get("seed", "5100"))).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	var n_slot := 0
	var n_up := 0
	var n_kup := 0
	for e in result.ev:
		n_slot += 1 if e.has("slot") else 0
		n_up += 1 if e.has("slot") and e.get("up") is bool and bool(e.up) and not (str(e.get("fx", "")) in ["buff", "debuff"]) else 0
		n_kup += 1 if e.has("kup") else 0
	print("KITFX|전투 사건 %d개 · 엔진이 붙인 slot %d · up %d · kup %d (%s)" % [result.ev.size(), n_slot, n_up, n_kup,
		"엔진이 새 필드를 준다" if n_kup > 0 else "up · kup 은 엔진 갈래 병합 전 —— 강화 판에서 직접 넣어 본다"])
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	Settings.apply_port(view.port)
	if headless:
		Engine.time_scale = 6.0      # 화면 없이는 빨리 돌린다 (표시 대기열만 본다)
	var with_up: Dictionary = result.duplicate(true)
	if _args.has("real"):      # 11/27 엔진 병합 뒤 —— 직접 넣지 않고 엔진이 강화(관우 Q·W · 감녕 W·R)로 계산한 결과 그대로
		var pol := {"A": "auto", "B": "auto", "kit": {"A": {"c177": ["q", "w"], "c197": ["w", "r"]}, "B": {}}}
		with_up = RtBattle.new(int(_args.get("seed", "5100"))).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], pol)
		var kn := {}
		for e in with_up.ev:
			if e.has("kup"):
				kn[str(e.kup)] = int(kn.get(str(e.kup), 0)) + 1
		print("KITFX|엔진 강화 판 —— 일한 강화 %s" % JSON.stringify(kn))
		_expect(not kn.is_empty(), "엔진이 강화 효과 사건(kup)을 내지 않았다")
	else:
		print("KITFX|강화 판에 넣은 것 %s" % JSON.stringify(_inject(with_up)))
	if _args.has("perf"):
		await _perf(view, result, with_up)
		get_tree().quit(1 if _fail > 0 else 0)
		return
	# 1) 보통 덱 판 —— 엔진 결과 그대로
	await _play(view, result.duplicate(true), "보통 덱", ["q"])
	# 2) 강화 판 —— up · kup 을 넣은 결과
	await _play(view, with_up.duplicate(true), "강화", ["up", "kup"])
	if _args.has("states"):
		var st: Dictionary = with_up.duplicate(true)
		print("KITFX|상태를 넣은 부대 %s" % JSON.stringify(_inject_states(st)))
		_out = str(_args.states)
		DirAccess.make_dir_recursive_absolute(_out)
		await _play(view, st, "상태", ["state"])
	print("KITFX|끝 · 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 신화 몇 + 나머지는 7성 이하 (7성 둘 · 6성 둘 · 나머지 5성) —— 실제 판처럼. skip 은 등급 목록에서 건너뛸 수 (양쪽 덱이 겹치지 않게)
func _deck(myths: Array, skip: int) -> Array:
	var cards := []
	for k in myths:
		if DB.C.has(k):
			cards.append(k)
	for tier_n in [[7, 2], [6, 2], [5, 9]]:
		var pool: Array = DB.by_tier(int(tier_n[0])).filter(func(k): return not DB.is_foe(str(k)) and str(DB.C[str(k)].get("kind", "")) != "retired")
		var took := 0
		for i in pool.size():
			if cards.size() >= 9 or took >= int(tier_n[1]):
				break
			var k = pool[(i + skip * 5) % pool.size()]
			if not cards.has(k) and not cards.any(func(c): return DB.person(str(c)) == DB.person(str(k))):
				cards.append(k)
				took += 1
	return cards


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail += 1
		print("KITFX|실패 —— %s" % what)


## 0) 칸 풀이 검사
func _check_resolve() -> void:
	var n := 0
	var myths: Array = DB.by_tier(8).filter(func(k): return Kit.on(k))
	for k in myths:
		var cell_names := []
		for s in ["q", "w", "e"]:
			cell_names.append(str(Kit.cell(k, s).get("n", "")))
		for s in ["q", "w", "e"]:
			var cn := str(Kit.cell(k, s).get("n", ""))
			_expect(cn != "", "%s 의 %s 칸 자료(data/kit.json)가 없다" % [k, s])
			_expect(str(KitFx.resolve({"fx": "skill", "name": cn}, k).get("slot", "")) == s, "%s 의 %s 칸 대비책 (%s)" % [k, s, cn])
			var old := str(Kit.slot_def(k, s).get("name", ""))
			if old != "" and not cell_names.has(old):      # 옛 결과 —— 카드 기술(sks) 이름으로도
				_expect(str(KitFx.resolve({"fx": "skill", "name": old}, k).get("slot", "")) == s, "%s 의 %s 칸 옛 이름 (%s)" % [k, s, old])
			n += 3
		_expect(str(KitFx.resolve({"fx": "ult", "name": "x"}, k).get("slot", "")) == "r", "%s 고유기 → r" % k)
		_expect(str(KitFx.resolve({"fx": "ult_warn", "name": "x"}, k).get("slot", "")) == "r", "%s 예고 → r" % k)
		var p: Dictionary = KitFx.resolve({"fx": "buff", "sig": true, "up": true, "t": "%s의 %s —— 시험" % [DB.C[k].name, Kit.p_name(k)]}, k)
		_expect(str(p.get("slot", "")) == "p" and str(p.get("name", "")) == str(Kit.cell(k, "p").get("n", "")), "%s 개성 말풍선 → p" % k)
		_expect(not bool(p.get("up", true)), "%s buff 꼴 사건의 up(올림)은 강화로 읽지 않는다" % k)
		_expect(KitFx.resolve({"fx": "skill", "name": "없는 기술"}, k).is_empty(), "%s 모르는 기술 이름은 칸이 없다" % k)
		for s in Kit.SLOTS:
			var un := str((Kit.cell(k, s).get("up", {}) as Dictionary).get("n", ""))
			_expect(un != "" and KitFx.up_slot(k, un) == s, "%s 의 강화 이름 %s → %s 칸" % [k, un, s])
		n += 10
	var low: String = DB.by_tier(7)[0]
	_expect(KitFx.resolve({"fx": "skill", "name": str(DB.C[low].sks[0].n) if not DB.C[low].get("sks", []).is_empty() else "x"}, low).is_empty(), "키트가 아닌 장수(%s)는 표시가 없다" % low)
	var ex: Dictionary = KitFx.resolve({"fx": "skill", "name": "아무 이름", "slot": "e", "up": true}, low)
	_expect(str(ex.get("slot", "")) == "e" and bool(ex.get("up", false)), "사건의 slot · up 을 그대로 읽는다")
	_expect(not bool(KitFx.resolve({"fx": "skill", "slot": "q", "augs": []}, "c177").up) and bool(KitFx.resolve({"fx": "skill", "slot": "q", "augs": ["dmg"]}, "c177").up), "옛 augs —— 비어 있지 않으면 강화")
	_expect(str(KitFx.resolve({"fx": "skill", "slot": "w"}, "c177").name) == str(Kit.cell("c177", "w").n), "이름이 없는 사건은 칸 자료의 이름")
	_expect(KitFx.up_slot("c177", "연참") == "q" and KitFx.up_slot("c177", "없는 강화") == "", "강화 이름 → 칸")
	_expect(KitFx.up_pushes("c177", "w") and not KitFx.up_pushes("c177", "q"), "밀어내는 강화 가리기 (격퇴는 밀고 연참은 아니다)")
	_expect(KitFx.log_head("q").contains("[lb]Q[rb]") and KitFx.log_head("") == "", "전투 기록 머리")
	n += 7
	print("KITFX|칸 풀이 검사 %d건 · 신화 키트 장수 %d명 · 실패 %d" % [n, myths.size(), _fail])


## 결과에 새 필드를 직접 넣는다 (엔진 갈래가 붙일 모양) —— 명단 "kit": [칸 …] · 그 칸 사건에 "up": true · 그 기술이 맞힌 첫 사건에 "kup": 강화 이름
func _inject(r: Dictionary) -> Dictionary:
	var cid_of := {}
	for row in r.roster:
		cid_of[str(row.key)] = str(row.id)
		if str(row.camp) == "A" and UPS.has(str(row.id)):
			row["kit"] = (UPS[str(row.id)] as Array).duplicate()
		elif row.has("kit"):
			row["kit"] = []
	var n := {"up": 0, "kup": 0}
	var ev: Array = r.ev
	for i in ev.size():
		var e: Dictionary = ev[i]
		e.erase("augs")
		var key := str(e.get("a", ""))
		if not e.has("slot") or not key.begins_with("A") or not UPS.has(str(cid_of.get(key, ""))):
			continue
		var slot := str(e.slot)
		if not (UPS[cid_of[key]] as Array).has(slot) or str(e.get("fx", "")) in ["buff", "debuff"]:
			continue
		e["up"] = true
		n.up += 1
		if str(e.get("fx", "")) != "skill":
			continue
		for j in range(i + 1, mini(ev.size(), i + 12)):      # 그 기술이 맞힌 첫 사건 —— 강화 효과가 발동한 사건으로
			var h: Dictionary = ev[j]
			if int(h.get("ai", -1)) != int(e.get("ai", -2)):
				break
			if str(h.get("fx", "")) in ["phys", "int"] and str(h.get("a", "")) == key and str(h.get("f", "")) != "":
				h["kup"] = str(Kit.cell(cid_of[key], slot).up.n)
				n.kup += 1
				break
	return n


## 상태 기호 확인용 —— 전투 5 ~ 20초 사이의 스냅숏에 상태 이름을 넣는다 (엔진이 줄 모양: 사건의 s[부대][3])
func _inject_states(r: Dictionary) -> Dictionary:
	var plan := {}      # 명단 번호 -> 넣을 상태들
	var names := {}
	var ai := 0
	var bi := 0
	for u in r.roster.size():
		var row: Dictionary = r.roster[u]
		var add: Array = []
		if str(row.camp) == "B":
			add = [["seal"], ["bleed", "plague"], ["taunted"], ["seal", "taunted"]][bi] if bi < 4 else []
			bi += 1
		else:
			add = [["undying", "plague"], ["stealth"], ["bleed"], ["plague"]][ai] if ai < 4 else []
			ai += 1
		if not add.is_empty():
			plan[u] = add
			names[str(row.name)] = add
	for e: Dictionary in r.ev:
		var tm := float(e.get("tm", 0.0))
		if tm < 5.0 or tm > 20.0:
			continue
		for u in plan:
			var st: Array = e.s[u][3]
			for k in plan[u]:
				if not st.has(k):
					st.append(k)
	return names


## 한 판을 재생하며 want 의 장면마다 한 장씩 찍는다 —— "q" 보통 Q 발동 · "up" 강화된 발동 · "kup" 강화 이름 · "state" 상태 기호
func _play(view: BattleView, r: Dictionary, label: String, want: Array) -> void:
	view.play_res(r, "pvp")
	var wp = view.type2.painting
	wp.kit.count_states = true
	var hud := view.hud
	var todo := want.duplicate()
	var peak_tags := 0
	var peak_casts := 0
	var over_n := 0
	var frames := 0
	var t_end := Time.get_ticks_msec() + 150000
	while not view.finished and Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		frames += 1
		var live := hud._visible_kit_tags()
		peak_tags = maxi(peak_tags, live.size())
		peak_casts = maxi(peak_casts, wp.kit.casts.size())
		for i in live.size():      # 자리 잡기가 겹치게 놓은 쌍
			for j in range(i + 1, live.size()):
				var x: Rect2 = (live[i].want as Rect2).intersection(live[j].want)
				if x.size.x > 2.0 and x.size.y > 2.0:
					over_n += 1
		for s in todo.duplicate():
			if _ready_shot(view, s):
				todo.erase(s)
				await _shot("kitfx2_%s" % s, view, s)
		if todo.is_empty() and _args.has("png") and view.clock > 14.0:
			break      # 찍을 것을 다 찍었다
	var st: Dictionary = wp.kit.stats
	var log_txt: String = view.log_box.get_parsed_text()
	var heads := []
	for s in Kit.SLOTS:
		heads.append("[%s] %d" % [Kit.SLOT_N[s], log_txt.count("[%s] " % Kit.SLOT_N[s])])
	print("KITFX|%s 판 —— 전투 %.1f초 · 프레임 %d · 칸별 표시 %s · 머리 위 딱지 %d · 삽화 고리 %d · 맞은 표식 %d · 강화 번쩍임 %d · 밀려남 %d · 상태 기호 %s" % [
		label, view.clock, frames, JSON.stringify(view.kit_seen), hud.kit_tag_n, int(st.cast), int(st.hit), int(st.burst), int(st.shove), JSON.stringify(st.state)])
	print("KITFX|%s 판 —— 동시에 뜬 딱지 최대 %d (상한 %d) · 동시 고리 최대 %d (상한 %d) · 자리 잡기가 겹치게 놓은 쌍 · 프레임 %d · 기록 머리 %s" % [
		label, peak_tags, hud.KIT_TAG_VISIBLE_MAX, peak_casts, wp.kit.MAX_CASTS, over_n, " ".join(heads)])
	_expect(todo.is_empty() or not _args.has("png"), "%s 판에서 찍지 못한 장면 %s" % [label, str(todo)])
	_expect(int(view.kit_seen.get("q", 0)) > 0, "%s 판에서 Q 표시가 한 번도 뜨지 않았다" % label)
	if want.has("up"):
		_expect(int(view.kit_seen.get("up", 0)) > 0, "강화된 발동(up) 표시가 없다")
		_expect(int(view.kit_seen.get("kup", 0)) > 0 and int(st.burst) > 0, "강화 이름(kup) 표시가 없다")
		_expect(int(view.kit_seen.get("shove", 0)) > 0, "밀어내는 강화(격퇴)의 밀려남 연출이 없다")
	if want.has("state"):
		for k in ["seal", "taunted", "undying", "bleed", "plague", "stealth"]:
			_expect(int(st.state.get(k, 0)) > 0, "상태 기호 %s 를 그리지 않았다" % k)
	_expect(peak_tags <= hud.KIT_TAG_VISIBLE_MAX and peak_casts <= wp.kit.MAX_CASTS, "상한을 넘었다")


## 그 장면이 "보기 좋게" 떠 있는 순간인가
func _ready_shot(view: BattleView, what: String) -> bool:
	var hud := view.hud
	var wp = view.type2.painting
	if view.clock < 4.0:
		return false
	match what:
		"kup":      # 강화 이름이 막 튀어나와 자리를 잡은 때
			for n: Dictionary in hud.kit_tags:
				if bool(n.pop) and float(n.age) > 0.3 and float(n.age) < 0.7:
					_pick = "%s 위에 %s" % [_who(view, str(n.key)), n.name]
					return true
			return false
		"state":      # 상태 기호가 여럿 떠 있을 때
			return view.clock > 9.0 and view.field.order.filter(func(sq): return sq.alive and (sq.statuses.has("seal") or sq.statuses.has("undying") or sq.statuses.has("plague"))).size() >= 3
	var need_up := what == "up"
	for c: Dictionary in wp.kit.casts:      # 맞은 표식이 막 뜬 때 + 머리 위 딱지가 아직 또렷할 때 (아군이 쓴 것)
		if (c.dsts as Array).is_empty() or not str(c.key).begins_with("A") or bool(c.up) != need_up or (not need_up and c.slot != what):
			continue
		var since := view.clock - float(c.hit)
		if since < 0.08 or since > 0.3:
			continue
		for n: Dictionary in hud.kit_tags:
			if not bool(n.pop) and n.key == c.key and n.slot == c.slot and float(n.age) > 0.15 and float(n.age) < float(n.life) - 0.4:
				_pick = "%s 의 %s%s → %s" % [_who(view, str(c.key)), n.name, " (강화)" if bool(c.up) else "", ", ".join((c.dsts as Array).map(func(k): return _who(view, str(k))))]
				return true
	return false


func _who(view: BattleView, key: String) -> String:
	var sq: Squad = view.field.squads.get(key)
	return ("%s(%s)" % [DB.person(sq.cid), "아군" if sq.camp == "A" else "적"]) if sq != null else key


func _shot(nm: String, view: BattleView, what: String) -> void:
	var hud := view.hud
	var tags := hud._visible_kit_tags().map(func(n):
		return ("◆%s" % n.name) if bool(n.pop) else "%s %s%s" % [Kit.SLOT_N[n.slot], n.name, "◆" if bool(n.up) else ""])
	print("KITFX|장면 %s —— 전투 %.2f초 · %s · 떠 있는 딱지 %s" % [what, view.clock, _pick, JSON.stringify(tags)])
	_pick = ""
	if not _args.has("png"):
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, nm]
	img.save_png(path)
	print("KITFX|캡처 %s (%dx%d)" % [path, img.get_width(), img.get_height()])


## 프레임 시간 견주기 —— 같은 판을 키트 표시 켜고 · 끄고 (수직동기 끔)
func _perf(view: BattleView, r: Dictionary, with_up: Dictionary) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var sum := {"끔": [0.0, 0.0, 0], "켬": [0.0, 0.0, 0]}
	var modes := ["끔", "켬", "켬", "끔", "끔", "켬"] if str(_args.get("perf", "1")) != "2" else ["끔", "켬"]
	var bare: Dictionary = r.duplicate(true)      # 끈 판 —— 사건의 칸 표시까지 지운다 (엔진이 slot 을 주면 Kit.enabled 와 무관하게 표시가 뜬다)
	for e: Dictionary in bare.ev:
		e.erase("slot")
		e.erase("kup")
	for mode in modes:      # 첫 판은 데우기 (그림 · 글리프를 처음 올린다) —— 합계에서 뺀다
		Kit.enabled = mode == "켬"
		view.play_res(with_up.duplicate(true) if Kit.enabled else bare.duplicate(true), "pvp")
		view.hud.kit_draw_us = 0
		view.hud.kit_draw_n = 0
		view.type2.painting.kit.draw_us = 0
		view.type2.painting.kit.draw_n = 0
		var frames := []
		var last := Time.get_ticks_usec()
		while view.clock < 26.0 and not view.finished:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			if view.clock > 4.0:
				frames.append((now - last) / 1000.0)
			last = now
		var tot := 0.0
		for f in frames:
			tot += f
		frames.sort()
		var mean := tot / maxf(1, frames.size())
		var p95: float = frames[int(frames.size() * 0.95)] if not frames.is_empty() else 0.0
		print("KITFX|성능 키트 표시 %s —— 프레임 %d · 평균 %.2fms · 95%% %.2fms · 최대 %.2fms · 딱지 %d · 고리 %d" % [mode, frames.size(), mean,
			p95, frames[-1] if not frames.is_empty() else 0.0, view.hud.kit_tag_n, int(view.type2.painting.kit.stats.cast)])
		var kd = view.type2.painting.kit
		print("KITFX|성능 —— 그리기 명령을 만드는 데 쓴 시간: 딱지 %.0fµs/회 (%d회) · 삽화 고리 · 표식 · 상태 %.0fµs/회 (%d회) · 전체 프레임당 %.0fµs" % [
			view.hud.kit_draw_us / maxf(1, view.hud.kit_draw_n), view.hud.kit_draw_n, kd.draw_us / maxf(1, kd.draw_n), kd.draw_n,
			(view.hud.kit_draw_us + kd.draw_us) / maxf(1, frames.size())])
		if sum[mode][2] > 0 or mode == "켬":
			sum[mode][0] += mean
			sum[mode][1] += p95
		sum[mode][2] += 1
	Kit.enabled = true
	if modes.size() > 2:
		print("KITFX|성능 합계 —— 끔 평균 %.2fms · 95%% %.2fms / 켬 평균 %.2fms · 95%% %.2fms (끔은 첫 판을 뺀 둘, 켬은 셋의 평균)" % [
			sum["끔"][0] / 2.0, sum["끔"][1] / 2.0, sum["켬"][0] / 3.0, sum["켬"][1] / 3.0])
