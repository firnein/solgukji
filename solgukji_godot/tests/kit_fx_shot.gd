extends Control
## 11/27 장수 키트 Q · W · E · R · P 발동 표시 점검 · 캡처 (삽화 화면) —— 사용자: 「쟤가 q 스킬이 발동됐구나, e 가 발동됐구나를 알 수 있어야 함」
## 화면 없이 (스크립트 오류 · 칸 풀이 · 표시 대기열이 만들어지는가):
##   godot --headless --path . res://tests/kit_fx_shot.tscn
## 캡처 (창이 뜬다 · 휴대폰 세로 540x1200):
##   godot --path . --resolution 540x1200 res://tests/kit_fx_shot.tscn -- --png [--out=D:/solgukji-main/captures/kit] [--seed=5100] [--cut] [--perf]
##
## 하는 일
##   0) 칸 풀이(KitFx.resolve) 검사 —— 사건에 slot 이 있을 때 · 없을 때(대비책: 기술 이름 → q · w · e, 고유기 → r, 개성 말풍선 → p) · 키트가 아닌 장수
##   1) 대비책 판 —— 신화 장수 덱으로 전투를 돌려 그대로 재생 (엔진이 slot 을 주지 않는 지금 결과). Q · W · E · R · P 표시가 뜬 순간을 한 장씩 (kitfx_q.png …)
##   2) slot 판 —— 같은 결과의 사건(res.ev)에 "slot" · "augs" 를 직접 넣어 재생. 강화 표시(★ · 화공 불빛 · 확산 · 강격) 한 장 (kitfx_aug.png)
##   --cut  : R 의 큰 컷인도 한 장 (kitfx_r_cut.png —— 고유기 연출 「모두 크게」로 한 번 더 돈다)
##   --perf : 같은 판을 키트 표시 끄고 · 켜고 세 번씩 돌려 프레임 시간과 그리기 명령을 만드는 데 쓴 시간(딱지 · 삽화)을 적는다
##            (수직동기 끔 —— PC 수치, 휴대폰 실측 아님. --perf=2 는 한 번씩만)
## 판마다 띄운 딱지 수(칸별) · 삽화 고리 수 · 맞은 표식 수 · 겹침 생략 · 동시에 떠 있던 최대 수를 적는다. 저장 · 기록을 만들지 않는다.

const Kit := preload("res://scripts/kit.gd")
const KitFx := preload("res://scripts/field/painted_kit.gd")
const A_DECK := ["c181", "c177", "c197", "c186", "c190", "c192", "c187"]      # 여포 · 관우 · 감녕 · 손권 · 유비 · 장각 · 제갈량
const B_DECK := ["c194", "L50", "c182", "c195"]                               # 조조 · 사마의 · 장료 · 주유
const AUGS := {"q": ["dmg", "fire"], "w": ["wide"], "e": ["slow", "awe", "quick"], "r": ["fire", "wide", "dmg"], "p": ["amp", "amp"]}

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
	Settings.ult_fx = 2      # 간단히 —— 컷인 · 슬로모션 없이 (말풍선에 R 딱지). 큰 컷인은 --cut
	Settings.apply()
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _args.has("png"):
		DirAccess.make_dir_recursive_absolute(_out)
	_check_resolve()
	var a: Array = DB.auto_place(_deck(A_DECK), "eorin")
	var b: Array = DB.auto_place(_deck(B_DECK), "hagik")
	var result: Dictionary = RtBattle.new(int(_args.get("seed", "5100"))).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	var had_slot := 0
	for e in result.ev:
		if e.has("slot"):
			had_slot += 1
	print("KITFX|전투 사건 %d개 · 엔진이 붙인 slot %d개 (%s)" % [result.ev.size(), had_slot, "엔진 병합 전 —— 대비책으로 본다" if had_slot == 0 else "엔진이 slot 을 준다"])
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	Settings.apply_port(view.port)
	if headless:
		Engine.time_scale = 6.0      # 화면 없이는 빨리 돌린다 (표시 대기열만 본다)
	if _args.has("perf"):
		await _perf(view, result)
		get_tree().quit(1 if _fail > 0 else 0)
		return
	# 1) 대비책 판
	await _play(view, result.duplicate(true), "대비책", ["p", "q", "w", "e", "r"], "")
	# 2) slot 판 —— 사건에 slot · augs 를 직접 넣는다
	var with_slot: Dictionary = result.duplicate(true)
	var injected := _inject(with_slot)
	print("KITFX|slot · augs 를 넣은 사건 %s" % JSON.stringify(injected))
	await _play(view, with_slot, "slot", [], "aug")
	if _args.has("cut"):
		Settings.ult_fx = 0
		await _play(view, with_slot.duplicate(true), "큰 컷인", [], "cut")
	print("KITFX|끝 · 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _deck(base: Array) -> Array:
	var cards := []
	for k in base:
		if DB.C.has(k) and not cards.has(k):
			cards.append(k)
	for k in DB.by_tier(7):      # 나머지는 불멸로 채운다 (키트가 아닌 장수 —— 표시가 뜨지 않아야 한다)
		if cards.size() >= 9:
			break
		if not cards.has(k):
			cards.append(k)
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
		for s in ["q", "w", "e"]:
			var sd: Dictionary = Kit.slot_def(k, s)
			if sd.is_empty():
				continue
			var r: Dictionary = KitFx.resolve({"fx": "skill", "name": sd.name}, k)
			_expect(str(r.get("slot", "")) == s, "%s 의 %s 칸 대비책 (%s)" % [k, s, sd.name])
			n += 1
		_expect(str(KitFx.resolve({"fx": "ult", "name": "x"}, k).get("slot", "")) == "r", "%s 고유기 → r" % k)
		_expect(str(KitFx.resolve({"fx": "ult_warn", "name": "x"}, k).get("slot", "")) == "r", "%s 예고 → r" % k)
		var p: Dictionary = KitFx.resolve({"fx": "buff", "sig": true, "t": "%s의 %s —— 시험" % [DB.C[k].name, Kit.p_name(k)]}, k)
		_expect(str(p.get("slot", "")) == "p" and str(p.get("name", "")) == Kit.p_name(k), "%s 개성 말풍선 → p" % k)
		_expect(KitFx.resolve({"fx": "skill", "name": "없는 기술"}, k).is_empty(), "%s 모르는 기술 이름은 칸이 없다" % k)
		n += 4
	var low: String = DB.by_tier(7)[0]
	_expect(KitFx.resolve({"fx": "skill", "name": str(DB.C[low].sks[0].n) if not DB.C[low].get("sks", []).is_empty() else "x"}, low).is_empty(), "키트가 아닌 장수(%s)는 표시가 없다" % low)
	var ex: Dictionary = KitFx.resolve({"fx": "skill", "name": "아무 이름", "slot": "e", "augs": ["fire", "wide"]}, low)
	_expect(str(ex.get("slot", "")) == "e" and ex.get("augs", []) == ["fire", "wide"], "사건의 slot · augs 를 그대로 읽는다")
	_expect(KitFx.log_head("q").contains("[lb]Q[rb]") and KitFx.log_head("") == "", "전투 기록 머리")
	n += 3
	print("KITFX|칸 풀이 검사 %d건 · 신화 키트 장수 %d명 · 실패 %d" % [n, myths.size(), _fail])


## 결과의 사건에 slot · augs 를 직접 넣는다 (엔진이 붙일 모양) —— 칸마다 넣은 수
func _inject(r: Dictionary) -> Dictionary:
	var cid_of := {}
	for row in r.roster:
		cid_of[str(row.key)] = str(row.id)
	var n := {}
	for e: Dictionary in r.ev:
		var fx := str(e.get("fx", ""))
		var key := str(e.get("a", ""))
		if bool(e.get("sig", false)) and (fx != "debuff" or key == ""):
			key = str(e.get("healer", e.get("f", ""))) if fx == "heal" else str(e.get("f", ""))
		if not (fx in ["skill", "ult", "ult_warn"] or bool(e.get("sig", false))) or not cid_of.has(key):
			continue
		var k: Dictionary = KitFx.resolve(e, str(cid_of[key]))
		if k.is_empty():
			continue
		e["slot"] = k.slot
		e["augs"] = (AUGS[k.slot] as Array).duplicate()
		n[k.slot] = int(n.get(k.slot, 0)) + 1
	return n


## 한 판을 재생하며 want 의 칸마다 표시가 뜬 순간을 찍는다 (extra: "aug" 강화 표시 한 장 · "cut" 큰 컷인 한 장)
func _play(view: BattleView, r: Dictionary, label: String, want: Array, extra: String) -> void:
	view.play_res(r, "pvp")
	var wp = view.type2.painting
	var hud := view.hud
	var todo := want.duplicate()
	var peak_tags := 0
	var peak_casts := 0
	var over_n := 0
	var over_max := 0.0
	var aug_tags := 0
	var seen_tags := {}
	var need_extra := extra != ""
	var frames := 0
	var t_end := Time.get_ticks_msec() + 150000
	while not view.finished and Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		frames += 1
		var live := hud.kit_tags.filter(func(n): return float(n.age) >= 0.0)
		peak_tags = maxi(peak_tags, live.size())
		peak_casts = maxi(peak_casts, wp.kit.casts.size())
		for n: Dictionary in live:
			if not seen_tags.has(n.id) and not (n.augs as Array).is_empty():
				aug_tags += 1
			seen_tags[n.id] = true
		# 딱지끼리 겹친 넓이 (자리 잡기 점검)
		for i in live.size():
			for j in range(i + 1, live.size()):
				var x: Rect2 = (live[i].want as Rect2).intersection(live[j].want)
				if x.size.x > 2.0 and x.size.y > 2.0:
					over_n += 1
					over_max = maxf(over_max, x.get_area())
		for s in todo.duplicate():
			if _ready_shot(view, s):
				todo.erase(s)
				await _shot("kitfx_%s" % s, view, s)
		if need_extra and extra == "aug" and _ready_aug(view):
			need_extra = false
			await _shot("kitfx_aug", view, "강화")
		if need_extra and extra == "cut" and hud.cut != null and not hud.cut.has("clash") and not (hud.cut.get("kit", {}) as Dictionary).is_empty() and float(hud.cut.t) > 0.9:
			need_extra = false
			await _shot("kitfx_r_cut", view, "큰 컷인 R")
		if want.is_empty() and not need_extra and extra != "" and _args.has("png") and view.clock > 12.0:
			break      # 찍을 것을 다 찍었다
	var st: Dictionary = wp.kit.stats
	var log_txt: String = view.log_box.get_parsed_text()
	var heads := []
	for s in Kit.SLOTS:
		heads.append("[%s] %d" % [Kit.SLOT_N[s], log_txt.count("[%s] " % Kit.SLOT_N[s])])
	print("KITFX|%s 판 —— 전투 %.1f초 · 프레임 %d · 칸별 표시 %s · 머리 위 딱지 %d (강화 ★ 붙은 것 %d) · 삽화 고리 %d · 맞은 표식 %d · 겹침 생략 %d" % [
		label, view.clock, frames, JSON.stringify(view.kit_seen), hud.kit_tag_n, aug_tags, int(st.cast), int(st.hit), int(st.skip)])
	print("KITFX|%s 판 —— 동시에 뜬 딱지 최대 %d (상한 %d) · 동시 고리 최대 %d (상한 %d) · 자리 잡기가 겹치게 놓은 쌍 · 프레임 %d (가장 넓게 %.0f px²) · 기록 머리 %s" % [
		label, peak_tags, hud.KIT_TAG_MAX, peak_casts, wp.kit.MAX_CASTS, over_n, over_max, " ".join(heads)])
	if not want.is_empty():
		for s in ["q", "w", "e", "r", "p"]:
			_expect(int(view.kit_seen.get(s, 0)) > 0, "%s 판에서 %s 칸 표시가 한 번도 뜨지 않았다" % [label, Kit.SLOT_N[s]])
		_expect(todo.is_empty() or not _args.has("png"), "찍지 못한 칸 %s" % str(todo))
	if extra == "aug":
		_expect(aug_tags > 0, "slot 판에서 강화 ★ 가 붙은 딱지가 없다")
	_expect(peak_tags <= hud.KIT_TAG_MAX and peak_casts <= wp.kit.MAX_CASTS, "상한을 넘었다")


## 그 칸의 표시가 "보기 좋게" 떠 있는 순간인가
func _ready_shot(view: BattleView, slot: String) -> bool:
	var hud := view.hud
	var wp = view.type2.painting
	match slot:
		"p":      # 개전 알림 —— P 딱지가 여럿 떠 있을 때
			return hud.kit_tags.filter(func(n): return n.slot == "p" and float(n.age) > 0.2 and float(n.age) < 1.2).size() >= 4
		"r":      # 말풍선에 R 딱지 + 삽화의 금빛 고리 · 맞은 표식
			for c: Dictionary in wp.kit.casts:
				if c.slot == "r" and not (c.dsts as Array).is_empty() and view.clock - float(c.hit) > 0.1 and view.clock - float(c.hit) < 0.35:
					for camp in ["A", "B"]:
						for n: Dictionary in hud.ult_notices[camp]:
							if n.key == c.key and not (n.get("kit", {}) as Dictionary).is_empty():
								_pick = "%s 의 %s → %s" % [_who(view, str(c.key)), n.skill, ", ".join((c.dsts as Array).map(func(k): return _who(view, str(k))))]
								return true
			return false
	if view.clock < 5.0:
		return false
	for c: Dictionary in wp.kit.casts:      # 맞은 표식이 막 뜬 때 + 머리 위 딱지가 아직 또렷할 때 (아군이 쓴 것을 먼저)
		if c.slot != slot or (c.dsts as Array).is_empty() or not str(c.key).begins_with("A"):
			continue
		var since := view.clock - float(c.hit)
		if since < 0.08 or since > 0.3:
			continue
		for n: Dictionary in hud.kit_tags:
			if n.key == c.key and n.slot == slot and float(n.age) > 0.15 and float(n.age) < float(n.life) - 0.35:
				_pick = "%s 의 %s → %s" % [_who(view, str(c.key)), n.name, ", ".join((c.dsts as Array).map(func(k): return _who(view, str(k))))]
				return true
	return false


func _who(view: BattleView, key: String) -> String:
	var sq: Squad = view.field.squads.get(key)
	return ("%s(%s)" % [DB.person(sq.cid), "아군" if sq.camp == "A" else "적"]) if sq != null else key


## 강화 표시가 잘 보이는 순간 —— 화공 · 강격이 붙은 Q 가 맞은 직후 (없으면 강화가 붙은 아무 칸)
func _ready_aug(view: BattleView) -> bool:
	if view.clock < 5.0:
		return false
	var wp = view.type2.painting
	for c: Dictionary in wp.kit.casts:
		if (c.augs as Array).is_empty() or (c.dsts as Array).is_empty() or not str(c.key).begins_with("A"):
			continue
		if c.slot != "q" and view.clock < 25.0:
			continue
		var since := view.clock - float(c.hit)
		if since >= 0.06 and since <= 0.25 and view.clock - float(c.start) < 0.55:
			for n: Dictionary in view.hud.kit_tags:
				if n.key == c.key and n.slot == c.slot and float(n.age) > 0.15:
					_pick = "%s 의 %s %s → %s" % [_who(view, str(c.key)), n.name, str(c.augs), ", ".join((c.dsts as Array).map(func(k): return _who(view, str(k))))]
					return true
	return false


func _shot(nm: String, view: BattleView, what: String) -> void:
	var hud := view.hud
	var tags := hud.kit_tags.filter(func(n): return float(n.age) >= 0.0).map(func(n): return "%s %s%s" % [Kit.SLOT_N[n.slot], n.name, "★".repeat((n.augs as Array).size())])
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
func _perf(view: BattleView, r: Dictionary) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var with_slot: Dictionary = r.duplicate(true)
	_inject(with_slot)
	var sum := {"끔": [0.0, 0.0, 0], "켬": [0.0, 0.0, 0]}
	var modes := ["끔", "켬", "켬", "끔", "끔", "켬"] if str(_args.get("perf", "1")) != "2" else ["끔", "켬"]
	for mode in modes:      # 첫 판은 데우기 (그림 · 글리프를 처음 올린다) —— 합계에서 뺀다
		Kit.enabled = mode == "켬"
		view.play_res(with_slot.duplicate(true) if Kit.enabled else r.duplicate(true), "pvp")
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
		print("KITFX|성능 —— 그리기 명령을 만드는 데 쓴 시간: 딱지 %.0fµs/회 (%d회) · 삽화 고리 · 표식 %.0fµs/회 (%d회) · 전체 프레임당 %.0fµs" % [
			view.hud.kit_draw_us / maxf(1, view.hud.kit_draw_n), view.hud.kit_draw_n, kd.draw_us / maxf(1, kd.draw_n), kd.draw_n,
			(view.hud.kit_draw_us + kd.draw_us) / maxf(1, frames.size())])
		if sum[mode][2] > 0 or mode == "켬":
			sum[mode][0] += mean
			sum[mode][1] += p95
		sum[mode][2] += 1
	Kit.enabled = true
	print("KITFX|성능 합계 —— 끔 평균 %.2fms · 95%% %.2fms / 켬 평균 %.2fms · 95%% %.2fms (끔은 첫 판을 뺀 둘, 켬은 셋의 평균)" % [
		sum["끔"][0] / 2.0, sum["끔"][1] / 2.0, sum["켬"][0] / 3.0, sum["켬"][1] / 3.0])
