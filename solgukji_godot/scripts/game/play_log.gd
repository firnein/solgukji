class_name PlayLog
## 플레이 기록 (11/5 사용자: PC 로 몇 판 해 볼 테니 게임이 어디서 쉬워지는지 판단할 수 있게 로그를 남겨라)
## 판마다 user://playlog/<시작 시각>_<시드>.jsonl 에 한 줄씩 쌓는다 (이어 하기도 같은 파일에 덧붙인다).
## 분석: python tools/scripts/analyze_playlog.py  → docs/플레이_분석.html
## 한 줄 = {"ts": 유닉스 초, "ev": 종류, "day", "phase", ...}
##   start / resume   판 시작 · 이어 하기
##   act              행동 (Run.COMMANDS —— 징집 · 선택 · 조합 · 편성 …) 과 그 결과
##   page             탭 이동 (어디서 시간을 쓰는지)
##   battle_start     전투 시작 —— 내 편성 · 적 편성 · 전력 비
##   battle_end       전투 결과 —— 승패 · 잔존 병력 비 · 부대별 기록 · 개입(고유기 · 군령) · 배속
##   phase_end        페이즈 끝 —— 걸린 시간 · 보유 패 · 덱 · 선택권 · 봇 전력
##   over             판 끝

static var enabled := true
static var dir := "user://playlog"      # 봇 기준선은 user://playlog_bot (tests/play_log_bot)
static var _f: FileAccess
static var _seed := ""
static var _phase_t0 := 0.0
static var _page := ""
static var _page_t0 := 0.0
static var page_time := {}       # 이 페이즈에서 탭마다 머문 초


static func _now() -> float:
	return Time.get_unix_time_from_system()


## 판이 바뀌었으면 그 판의 파일을 연다
static func ensure(run, kind := "resume") -> bool:
	if not enabled or run == null:
		return false
	var sd := str(run.rng.seed)
	if _f != null and sd == _seed:
		return true
	DirAccess.make_dir_recursive_absolute(dir)
	var path := ""
	for fn in DirAccess.get_files_at(dir):
		if fn.ends_with("_%s.jsonl" % sd):
			path = dir + "/" + fn
	if path == "":
		var st := Time.get_datetime_dict_from_system()
		path = dir + "/%04d%02d%02d_%02d%02d%02d_%s.jsonl" % [st.year, st.month, st.day, st.hour, st.minute, st.second, sd]
	_f = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if _f == null:
		return false
	_f.seek_end()
	_seed = sd
	_phase_t0 = _now()
	page_time = {}
	_put(run, kind, {"seed": sd, "os": OS.get_name(), "ver": Changelog.version()})      # 11/9 첫 유저 기록의 ver 가 비어 있었다 (project.godot 에 version 없음) —— changelog 맨 앞 버전
	return true


static func _put(run, ev: String, data: Dictionary) -> void:
	if _f == null:
		return
	var d := {"ts": snappedf(_now(), 0.01), "ev": ev, "day": run.day, "phase": run.phase}
	d.merge(data)
	_f.store_line(JSON.stringify(d))
	_f.flush()


static func note(run, ev: String, data := {}) -> void:
	if ensure(run):
		_put(run, ev, data)


## 카드 한 장 —— [이름, 등급, 병종]
static func card(k) -> Array:
	if k == null or not DB.C.has(k):
		return []
	var c: Dictionary = DB.C[k]
	return [c.name, int(c.tier), c.tag]


static func side(cards: Array) -> Dictionary:
	var out := []
	var tr := 0
	var pv := 0
	for k in cards:
		if k == null or not DB.C.has(k):
			continue
		out.append(card(k))
		tr += int(DB.C[k].tr)
		pv += int(DB.C[k].pv)
	return {"cards": out, "tr": tr, "pv": pv}


static func new_game(run) -> void:
	_f = null
	_seed = ""
	ensure(run, "start")


static func act(run, m: String, a: Array, r) -> void:
	if not ensure(run):
		return
	_put(run, "act", act_data(m, a, r))


## act 한 줄의 내용 —— 온라인 방 기록(RoomLog)도 같은 형식을 쓴다 (11/10)
static func act_data(m: String, a: Array, r) -> Dictionary:
	var d := {"m": m, "a": a}
	match m:
		"do_draw", "random_grant":
			d["got"] = (r if r is Array else []).map(func(k): return card(k))
		"pick", "forge", "pick_unique":
			d["card"] = card(str(a[0])) if not a.is_empty() else []
			d["ok"] = bool(r)
			if m == "forge" and bool(r) and not a.is_empty():
				d["got"] = [card(str(a[0]))]      # 조합 결과 카드
		"place":
			d["card"] = card(str(a[1])) if a.size() > 1 else []
	return d


static func page(run, pg: String) -> void:
	if not enabled or _f == null or run == null or str(run.rng.seed) != _seed:      # 판을 열기 전(타이틀) 탭 이동은 적지 않는다
		return
	var t := _now()
	if _page != "":
		page_time[_page] = snappedf(float(page_time.get(_page, 0.0)) + t - _page_t0, 0.1)
	_page = pg
	_page_t0 = t
	_put(run, "page", {"to": pg})


static func battle_start(run, bt: Dictionary) -> void:
	if not ensure(run):
		return
	_put(run, "battle_start", battle_start_data(bt))


static func battle_start_data(bt: Dictionary) -> Dictionary:
	var a := side(bt.a.cards)
	var b := side(bt.b.cards)
	return {"kind": bt.kind, "title": bt.title, "seed": bt.seed,
		"me": a, "foe": b, "form": bt.a.form, "foe_form": bt.b.form, "tac": bt.a.get("tac", ""), "foe_tac": bt.b.get("tac", ""),
		"morale": bt.a.morale, "foe_morale": bt.b.morale, "equip": bt.a.equip.filter(func(x): return x != null).size(),
		"foe_equip": (bt.b.equip if bt.b.equip else []).filter(func(x): return x != null).size(),
		"tr_ratio": snappedf(float(a.tr) / maxf(1.0, float(b.tr)), 0.001)}


static func battle_end(run, bt, res: Dictionary, view_len: float, inputs: Array, speeds: Dictionary) -> void:
	if not ensure(run):
		return
	_put(run, "battle_end", battle_end_data(bt, res, view_len, inputs, speeds))


static func battle_end_data(bt, res: Dictionary, view_len: float, inputs: Array, speeds: Dictionary) -> Dictionary:
	var units := []
	var left := {"A": 0, "B": 0}
	var mx := {"A": 0, "B": 0}
	for u in res.get("roster", []):
		left[u.camp] += maxi(0, int(u.left))
		mx[u.camp] += int(u.max)
		units.append({"camp": u.camp, "name": u.name, "tier": int(u.tier), "tag": u.tag, "line": u.line,
			"dmg": int(u.dmg), "taken": int(u.get("taken", 0)), "heal": int(u.heal), "kills": int(u.kills),
			"mdmg": float(u.mdmg), "left": maxi(0, int(u.left)), "max": int(u.max), "alive": bool(u.alive)})
	var ult := 0
	var cmd := 0
	for x in inputs:
		if x is Array and x.size() > 2:
			if str(x[2]) == "ult": ult += 1
			else: cmd += 1
	return {"kind": bt.kind if bt else "", "win": bool(res.win), "draw": bool(res.draw),
		"alive": int(res.left), "foe_alive": int(res.eLeft), "troops": left.A, "foe_troops": left.B,
		"troops_max": mx.A, "foe_troops_max": mx.B,
		"left_ratio": snappedf(float(left.A) / maxf(1.0, float(mx.A)), 0.001),
		"foe_left_ratio": snappedf(float(left.B) / maxf(1.0, float(mx.B)), 0.001),
		"turns": res.get("turns", 0), "view_sec": snappedf(view_len, 0.1),
		"mvp": res.mvp.name if res.get("mvp") else "", "ult_inputs": ult, "cmd_inputs": cmd, "speeds": speeds,
		"chains": res.get("chains", {}), "units": units}


static func after_battle(run) -> void:
	if not ensure(run):
		return
	## 11/9 민심(hp) 기록 —— reward · phase_end · over
	_put(run, "reward", reward_data(run))
	if run.over != null:
		over(run)


static func reward_data(run) -> Dictionary:
	return {"strikes": run.strikes, "hp": run.hp, "hp_loss": run.last_hp_loss, "w": run.my_w, "l": run.my_l, "tickets": run.tickets.duplicate(),
		"spoil": run.last_spoil, "inv_n": _inv_n(run)}


static func _inv_n(run) -> int:
	var n := 0
	for k in run.inv:
		n += int(run.inv[k])
	return n


static func phase_end(run) -> void:
	if not ensure(run):
		return
	if _page != "":
		page_time[_page] = snappedf(float(page_time.get(_page, 0.0)) + _now() - _page_t0, 0.1)      # 지금 탭에 머문 시간까지 더한다
		_page_t0 = _now()
	var d := {"sec": snappedf(_now() - _phase_t0, 0.1), "page_sec": page_time.duplicate()}
	d.merge(phase_end_data(run))
	_put(run, "phase_end", d)
	_phase_t0 = _now()
	page_time = {}


## 페이즈 끝 스냅샷 (걸린 시간 · 탭 시간 빼고) —— 온라인 방 기록(RoomLog)도 같은 형식
static func phase_end_data(run) -> Dictionary:
	var tiers := {}
	for k in run.inv:
		var t := str(DB.C[k].tier) if DB.C.has(k) else "?"
		tiers[t] = int(tiers.get(t, 0)) + int(run.inv[k])
	var bots := []
	for b in run.bots:
		bots.append(int(b.pv))
	return {"deck": side(run.board), "form": run.form, "tac": run.tac, "my_pv": run.my_pv(), "inv_n": _inv_n(run), "inv_tiers": tiers,
		"bag_n": run.bag.values().reduce(func(s, x): return s + int(x), 0), "equip": run.equipped_count(),
		"tickets": run.tickets.duplicate(), "strikes": run.strikes, "hp": run.hp, "w": run.my_w, "l": run.my_l, "rank": run.rank(),
		"bot_pv": bots, "myth": run.myth_made}


static func over(run) -> void:
	if not ensure(run) or run.over == null:
		return
	_put(run, "over", over_data(run))


static func over_data(run) -> Dictionary:
	return {"win": bool(run.over.win), "msg": str(run.over.msg), "hp": run.hp, "w": run.my_w, "l": run.my_l,
		"rank": run.rank(), "my_pv": run.my_pv(), "deck": side(run.board),
		"tour": ("우승" if bool(run.over.win) else run.tour_rank()) if run.tour != null else ""}
