extends Control
## 온라인 재생의 「묶음 줄 막힘」 측정 (11/26 사용자: "응답 못 받는 것처럼 이동만 하다가 받는 순간 와라라라 진행")
## 재생은 묶음을 시각 순서로 하나씩 꺼내는데, 맨 앞이 고유기 묶음이고 컷인 · 슬로모션 · 받아치기 간격에 걸리면 그 뒤의 평범한 공격 묶음도 같이 기다린다.
## 그동안 부대는 기록된 길을 계속 간다 → 이동만 하다가 풀리는 순간 밀린 묶음이 한꺼번에 터진다.
## 실행 (화면 없이 · 기록은 사본으로 · 로그는 데이터 폴더 밖으로):
##   godot --headless --fixed-fps 60 --log-file <밖>/q.log --path . res://tests/queue_lag.tscn -- --log=<playlog 사본.jsonl> [--from=2] [--arms=on,off] [--max=12]
## 전투마다: 막힌 시간(실제 초) = 느린 화면 중 / 제 속도 중(컷인 탓 · 받아치기 간격 탓) · 제 속도로 이어서 막힌 가장 긴 구간 · 가장 크게 밀린 전장 시간 · 한꺼번에 밀려 있던 묶음 수
## off = 받아치기 간격(_clash_gap_until)을 매 프레임 지운 것 (1.2n 까지의 동작에 가깝다)


func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	get_tree().create_timer(900.0).timeout.connect(func(): get_tree().quit(1))
	PlayLog.enabled = false
	Settings.type2 = true
	Settings.war_painting = true
	Settings.ult_fx = 2
	theme = UI.theme()
	var fa := FileAccess.open(str(args.get("log", "")), FileAccess.READ)
	if fa == null:
		print("기록을 열 수 없다 —— --log=경로.jsonl")
		get_tree().quit(1)
		return
	var pairs := []
	var st = null
	while not fa.eof_reached():
		var ln := fa.get_line().strip_edges()
		if ln == "":
			continue
		var e = JSON.parse_string(ln)
		if not (e is Dictionary):
			continue
		if str(e.get("ev", "")) == "battle_start":
			st = e
		elif str(e.get("ev", "")) == "battle_end" and st != null:
			pairs.append([st, e])
			st = null
	var from := int(args.get("from", "0"))
	var arms: Array = Array(str(args.get("arms", "on,off")).split(",", false))
	var left := int(args.get("max", "99"))
	var tot := {}
	for p in pairs:
		if int(p[0].day) < from or left <= 0:
			continue
		left -= 1
		for arm in arms:
			var r: Dictionary = await _one(p[0], p[1], str(arm))
			if r.is_empty():
				continue
			print("QL %s | %d일차 %s %s | 재생 %.0f초 · 고유기 묶음 %d(받아치기 %d) | 막힘: 느린 화면 %.1f초 · 제 속도 %.1f초(컷인 %.1f · 간격 %.1f) | 제 속도 최장 %.1f초 · 최대 밀림 %.2f전장초 · 밀린 묶음 최대 %d" % [
				arm, int(p[0].day) + 1, str(p[0].kind), str(p[1].get("foe_name", "")), r.real, r.ults, r.clash, r.slow, r.fast, r.fast_cut, r.fast_gap, r.run, r.lag, r.burst])
			print("QG %s |   행동 없는 가장 긴 구간: 엔진 %.1f전장초(전투 %.0f초 무렵) · 화면 %.1f초(그중 제 속도 %.1f초 · 화면 시계 %.0f초 무렵) · 그 뒤 1초에 터진 묶음 %d" % [arm, r.eng_gap, r.eng_at, r.view_gap, r.view_gap_fast, r.view_at, r.after])
			if not tot.has(arm):
				tot[arm] = {"n": 0, "real": 0.0, "slow": 0.0, "fast": 0.0, "fast_cut": 0.0, "fast_gap": 0.0, "run": 0.0, "lag": 0.0, "burst": 0, "over2": 0}
			var t: Dictionary = tot[arm]
			t.n += 1
			for k in ["real", "slow", "fast", "fast_cut", "fast_gap"]:
				t[k] += float(r[k])
			t.run = maxf(t.run, r.run)
			t.lag = maxf(t.lag, r.lag)
			t.burst = maxi(t.burst, r.burst)
			t.over2 += 1 if r.run >= 2.0 else 0
	for arm in tot:
		var t: Dictionary = tot[arm]
		print("QLSUM %s | 전투 %d · 재생 합 %.0f초 | 막힘: 느린 화면 %.1f초 · 제 속도 %.1f초(컷인 %.1f · 간격 %.1f) | 제 속도로 2초 넘게 이어 막힌 전투 %d · 최장 %.1f초 · 최대 밀림 %.2f전장초 · 밀린 묶음 최대 %d" % [
			arm, t.n, t.real, t.slow, t.fast, t.fast_cut, t.fast_gap, t.over2, t.run, t.lag, t.burst])
	get_tree().quit(0)


func _one(s: Dictionary, e: Dictionary, arm: String) -> Dictionary:
	var a := []
	var b := []
	for u in e.get("units", []):
		var id := str(u.get("id", ""))
		if not DB.C.has(id):
			continue
		if str(u.get("camp", "")) == "A":
			a.append(id)
		else:
			b.append(id)
	if a.is_empty() or b.is_empty():
		return {}
	var fa := str(s.get("form", "eorin"))
	var fb := str(s.get("foe_form", "eorin"))
	if not DB.FORM.has(fa) or not DB.FORM.has(fb):
		return {}
	var quest := str(s.kind) == "quest"
	var ca: Array = DB.auto_place(a, fa)
	var cb: Array = b if quest else DB.auto_place(b, fb)      # 토벌 적은 기록 순서 그대로 (잡병이 뒤에 붙는다)
	var res = RtBattle.make(int(s.seed)).run(ca, fa, float(s.get("morale", 100)), null, cb, fb, float(s.get("foe_morale", 100)), null, "", "", [], {"A": "smart", "B": "smart"})
	if not (res is Dictionary):
		return {}
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	view.play_res(res, str(s.kind))
	var out := {"real": 0.0, "slow": 0.0, "fast": 0.0, "fast_cut": 0.0, "fast_gap": 0.0, "run": 0.0, "lag": 0.0, "burst": 0, "ults": 0, "clash": 0}
	for g in view.groups:
		if g.ult != null:
			out.ults += 1
			out.clash += 1 if bool(g.ult.get("clash", false)) else 0
	# 엔진 쪽: 이어진 두 묶음 사이의 가장 긴 공백 (첫 묶음 뒤부터) —— 엔진이 원래 그만큼 아무도 치지 않았다
	out["eng_gap"] = 0.0
	out["eng_at"] = 0.0
	for i in range(1, view.groups.size()):
		var gp: float = float(view.groups[i].t) - float(view.groups[i - 1].t)
		if gp > out.eng_gap:
			out.eng_gap = gp
			out.eng_at = float(view.groups[i - 1].t)
	out["view_gap"] = 0.0
	out["view_gap_fast"] = 0.0
	out["view_at"] = 0.0
	out["after"] = 0
	var dt := 1.0 / 60.0
	var run_n := 0
	var frames := 0
	var last_gi := 0
	var idle := 0          # 묶음이 하나도 시작되지 않은 프레임 수 (첫 묶음 뒤)
	var idle_fast := 0
	var best_end := -1     # 가장 긴 공백이 끝난 프레임
	var gi_at_end := 0
	var hist := []         # [프레임, gi]
	while not view.finished and frames < 60 * 300:
		await get_tree().process_frame
		frames += 1
		if view.gi != last_gi:
			if last_gi > 0 and idle * dt > out.view_gap:
				out.view_gap = idle * dt
				out.view_gap_fast = idle_fast * dt
				out.view_at = view.clock
				best_end = frames
				gi_at_end = last_gi
			last_gi = view.gi
			idle = 0
			idle_fast = 0
		elif last_gi > 0 and view.gi < view.groups.size():
			idle += 1
			idle_fast += 1 if view.slow_t <= 0 else 0
		if best_end >= 0 and frames == best_end + 60:
			out.after = view.gi - gi_at_end
		if arm == "off":
			view._clash_gap_until = -99.0
		var n: int = view.groups.size()
		var blocked: bool = view.running and view.gi < n and float(view.groups[view.gi].t) <= view.clock
		if not blocked:
			run_n = 0
			continue
		var wait := 0
		for i in range(view.gi, n):
			if float(view.groups[i].t) > view.clock:
				break
			wait += 0 if view._ahead.has(i) else 1
		out.burst = maxi(out.burst, wait)
		out.lag = maxf(out.lag, view.clock - float(view.groups[view.gi].t))
		if view.slow_t > 0:
			out.slow += dt
			run_n = 0
		else:
			out.fast += dt
			if view.hud != null and view.hud.cut != null:
				out.fast_cut += dt
			else:
				out.fast_gap += dt
			run_n += 1
			out.run = maxf(out.run, run_n * dt)
	out.real = frames * dt
	view.queue_free()
	await get_tree().process_frame
	return out
