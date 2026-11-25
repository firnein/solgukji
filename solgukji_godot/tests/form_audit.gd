extends Node
## 11/26 진형 분석 (docs/진형_분석_1126.md) —— 실제 온라인 대전 기록의 덱 · 진형 · 배치 그대로 다시 돌려 칸 위치별로 잰다 (측정 전용, 기록은 읽기만)
## 입력: 기록 정리본 JSON (tests/real_myth_swap.gd 와 같은 형식 —— 9장이면 기록 순서가 곧 진형 칸 순서, 모자라면 줄 이름 · 자동 배치)
## 실행: godot --headless --path . res://tests/form_audit.tscn -- --in=C:/.../real_battles.json --out=C:/.../x.jsonl [--part=1 --parts=4]
##        [--sw=rear_guard,intercept,form_guard,spear_rear_ok] [--place=spear_rear|rear_front --only_place=1] [--place_check=spear_rear|rear_front]
##   --place=rear_front : 후군 원거리(가운데 쪽) 하나와 전열 근접(가장 뒤 · 낮은 등급) 하나를 맞바꾼다 —— 후열 배치의 값
##   --auto=A|B : 그 진영만 자동 배치(DB.auto_place)로 다시 놓는다 —— --sw=outer_guard_place 켬/끔 비교 (라)
##   --place_check=모드 : 바꾸지 않고 그 모드로 바꿀 수 있는 판만 돈다 (같은 판 기준선)
##   --sw         : 진형 분석 스위치를 켠다 (RtBattle.rear_guard · intercept · form_guard, DB.spear_rear_ok)
##   --place=spear_rear : 창병이 있고 후군 줄에 원거리가 둘 이상인 쪽마다, 가장 뒤쪽 창병과 후군 줄의 원거리 하나(가운데 쪽부터)를 맞바꾼다
##                        —— 창병이 후열 측면 원거리 옆에 선다. --only_place=1 이면 바꿀 수 있는 판만 돈다 (켬/끔 같은 판 비교)
## 판마다 한 줄: {bi, fa, fb, win(A 승 1 · 0.5 · 0), len, st(가로막기 통계), pl(바꾼 쪽), u: [[진영, 칸, 행, 열, 병종, 등급, 원거리,
##   처음 맞닿음, 도적 맞닿음, 근접 맞닿음, 도적에게 노려짐, 무너짐, 맞닿기 전 피해 · 기술 · 고유기, 처음 닿은 적 병종, 준 피해, 받은 피해, 최대 병력, 살았나, 고유기 수]]}
## 시각이 없으면 −1 (끝까지 그런 일이 없었다)


func _ready() -> void:
	PlayLog.enabled = false
	get_tree().create_timer(7000.0).timeout.connect(func(): get_tree().quit(1))
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var part := int(a.get("part", "1"))
	var parts := int(a.get("parts", "1"))
	var sws: Array = Array(str(a.get("sw", "")).split(",", false))
	RtBattle.rear_guard = sws.has("rear_guard")
	RtBattle.intercept = sws.has("intercept")
	RtBattle.form_guard = sws.has("form_guard")
	DB.spear_rear_ok = sws.has("spear_rear_ok")
	DB.outer_guard_place = sws.has("outer_guard_place")
	RtBattle.probe_back_basic = not sws.has("no_back_basic")      # (라) 도적 평타가 적진 가장 뒤 부대 대신 맞닿은 적에게 (기존 점검 스위치)
	var auto_cp := str(a.get("auto", ""))      # --auto=A|B : 그 진영을 DB.auto_place 로 다시 놓는다 (outer_guard_place 켬/끔 비교)
	RtBattle.probe_form = true
	var place := str(a.get("place", ""))
	var only_place := a.has("only_place")
	var idx := {}
	for k in DB.C:
		if DB.is_foe(k):
			continue
		var c: Dictionary = DB.C[k]
		var key := JSON.stringify([c.name, int(c.tier), c.tag])
		if not idx.has(key) or DB.C[idx[key]].kind == "retired":
			idx[key] = k
	var sw = load("res://tests/real_myth_swap.gd").new()
	sw.idx = idx
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(str(a.get("in", ""))))
	var f := FileAccess.open(str(a.get("out", "user://form_audit_%d.jsonl" % part)), FileAccess.WRITE)
	var n := 0
	for bi in rows.size():
		if bi % parts != part - 1:
			continue
		var b: Dictionary = rows[bi]
		var me: Dictionary = sw._side(b.me)
		var foe: Dictionary = sw._side(b.foe)
		if me.is_empty() or foe.is_empty():
			continue
		var pl := []
		if auto_cp != "":
			_reauto(me if auto_cp == "A" else foe)
			pl.append(auto_cp)
		var pm := place if place != "" else str(a.get("place_check", ""))      # --place_check=모드 : 바꾸지 않고 그 모드로 바꿀 수 있는 판만 (기준선)
		if pm != "":
			for pair in [["A", me], ["B", foe]]:
				var S: Dictionary = pair[1] if place != "" else (pair[1] as Dictionary).duplicate(true)
				if (_spear_rear(S) if pm == "spear_rear" else _rear_front(S)):
					pl.append(pair[0])
			if (only_place or place == "") and pl.is_empty():
				continue
		var plan := {}
		if not (b.me_plan as Array).is_empty() or not (b.foe_plan as Array).is_empty():
			plan = {"A": {"p": b.me_plan, "own": b.me_own, "perm": []}, "B": {"p": b.foe_plan, "own": [], "perm": []}}
		var bt := RtBattle.new(int(b.seed))
		var r: Dictionary = sw._run_bt(bt, me, foe, plan, false)
		var us := []
		for u in bt.units:
			var p: Dictionary = bt.fprobe.get(u, {})
			var fm: String = me.form if u.camp == "A" else foe.form
			var sl: Dictionary = DB.FORM[fm].slots[u.slot] if u.slot < DB.FORM[fm].slots.size() else {"row": -1, "col": -1}
			us.append([u.camp, u.slot, int(sl.row), int(sl.col), u.c.tag, int(u.c.tier), u.ranged,
				_t(p, "t_touch"), _t(p, "t_rogue"), _t(p, "t_melee"), _t(p, "t_aimed"), _t(p, "t_out"),
				roundi(float(p.get("pre_dmg", u.dmg))), int(p.get("pre_sk", -1)), int(p.get("pre_ult", -1)), str(p.get("by", "")),
				roundi(u.dmg - u.over), roundi(u.taken), roundi(u.max), u.alive, u.ult_n])
		var st := {}
		for k in ["rogue_held", "escort", "rescue", "escape", "intercept"]:
			st[k] = int(bt.stats.get(k, 0))
		var w := 0.5 if bool(r.draw) else (1.0 if bool(r.win) else 0.0)
		f.store_line(JSON.stringify({"bi": bi, "day": b.day, "fa": me.form, "fb": foe.form, "win": w, "len": float(r.len), "st": st, "pl": pl, "u": us}))
		bt.units.clear()
		n += 1
	f.close()
	print("ZGL_FORM done part=%d/%d n=%d sw=%s place=%s" % [part, parts, n, JSON.stringify(sws), place])
	get_tree().quit(0)


## 자동 배치로 다시 놓기 —— 장비는 카드를 따라간다
func _reauto(S: Dictionary) -> void:
	var ids := []
	var eq := {}
	for i in S.cards.size():
		if S.cards[i] != null:
			ids.append(S.cards[i])
			eq[S.cards[i]] = S.equip[i]
	var cards := DB.auto_place(ids, S.form)
	var equip := []
	equip.resize(cards.size())
	for i in cards.size():
		if cards[i] != null:
			equip[i] = eq.get(cards[i])
	S.cards = cards
	S.equip = equip


func _t(p: Dictionary, k: String) -> float:
	return snappedf(float(p[k]), 0.1) if p.has(k) else -1.0


## 후열의 값 —— 후군 줄 원거리 가운데 가운데 열에 가장 가까운 것과, 전열(선봉 · 전군) 근접 가운데 가장 뒤쪽 · 낮은 등급을 맞바꾼다. 바꿨으면 true
func _rear_front(S: Dictionary) -> bool:
	var slots: Array = DB.FORM[S.form].slots
	var r := -1
	var m := -1
	for i in S.cards.size():
		var k = S.cards[i]
		if k == null or i >= slots.size():
			continue
		var c: Dictionary = DB.C[k]
		var row := int(slots[i].row)
		if row == 3 and Battle.is_caster(c) or row == 3 and c.tag == "궁병":
			if r < 0 or absi(int(slots[i].col) - 2) < absi(int(slots[r].col) - 2):
				r = i
		elif row <= 1 and c.tag in ["창병", "기병"]:
			if m < 0 or row > int(slots[m].row) or (row == int(slots[m].row) and int(c.tier) < int(DB.C[S.cards[m]].tier)):
				m = i
	if r < 0 or m < 0:
		return false
	var tmp = S.cards[r]
	S.cards[r] = S.cards[m]
	S.cards[m] = tmp
	var te = S.equip[r]
	S.equip[r] = S.equip[m]
	S.equip[m] = te
	return true


## (가) 배치 바꾸기 —— 후군 줄 원거리가 둘 이상이고 그 줄 밖에 창병이 있으면, 가장 뒤쪽(같으면 낮은 등급) 창병과
## 후군 줄 원거리 가운데 가운데 열에 가장 가까운 것을 맞바꾼다 (장비도 함께). 바꿨으면 true
func _spear_rear(S: Dictionary) -> bool:
	var slots: Array = DB.FORM[S.form].slots
	var rear := []
	var sp := -1
	for i in S.cards.size():
		var k = S.cards[i]
		if k == null or i >= slots.size():
			continue
		var c: Dictionary = DB.C[k]
		if int(slots[i].row) == 3:
			if c.tag == "창병":
				return false      # 이미 후군에 창병이 있다
			if c.tag in ["궁병", "책사", "유생", "술사", "모사"]:
				rear.append(i)
		elif c.tag == "창병":
			if sp < 0 or int(slots[i].row) > int(slots[sp].row) or (int(slots[i].row) == int(slots[sp].row) and int(c.tier) < int(DB.C[S.cards[sp]].tier)):
				sp = i
	if sp < 0 or rear.size() < 2:
		return false
	rear.sort_custom(func(x, y): return absi(int(slots[x].col) - 2) < absi(int(slots[y].col) - 2))
	var q: int = rear[0]
	var tmp = S.cards[q]
	S.cards[q] = S.cards[sp]
	S.cards[sp] = tmp
	var te = S.equip[q]
	S.equip[q] = S.equip[sp]
	S.equip[sp] = te
	return true
