extends Node
## 실제 온라인 대전 기록으로 재현 · 신화 바꿔 끼우기 (측정 전용, 기록은 읽기만)
## 입력: 기록 정리본 JSON —— python tools/scripts/real_battles.py <playlog_online 폴더> <출력 json> (pvp battle_start + battle_end 묶음, 양쪽 기록 중복 제거)
## 실행: godot --headless --path . res://tests/real_myth_swap.tscn -- --in=C:/.../real_battles.json --mode=repro|swap|swap7 --part=1 --parts=4 --seeds=1 --days=2,3,4,5,6 --out=C:/.../x.jsonl [--old] [--only=c187,c194] [--resume=앞 출력]
##   repro : 기록 그대로 (내 쪽 A, 사람 상대면 뒤집은 쪽도) —— 기록 결과와 승패 일치율
##   swap  : 신화가 든 쪽마다 그 신화 칸에 신화 11장 + 불멸 제갈량(L12)을 바꿔 끼운다 (같은 인물이 다른 칸에 있으면 건너뜀). 상대 · 진형 · 장비 · 사기 · 군략은 기록 그대로
##   swap7 : 불멸이 든 쪽마다 첫 불멸 칸에 불멸 전부를 바꿔 끼운다 (책략 · 정면 불멸 비교)
## --old : 책략계 기술 완화(11/25)를 끈다 —— 기준선
var idx := {}
var miss := {}


func _ready() -> void:
	PlayLog.enabled = false
	get_tree().create_timer(7000.0).timeout.connect(func(): get_tree().quit(1))
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if a.has("old"):
		DB.caster_skill_on = false
		DB._reskill()
		RtBattle.caster_idle_charge = 0.0
	var mode := str(a.get("mode", "repro"))
	var part := int(a.get("part", "1"))
	var parts := int(a.get("parts", "1"))
	var nseed := int(a.get("seeds", "2"))
	var only_days: Array = Array(str(a.get("days", "1,2,3,4,5,6,7")).split(",")).map(func(x): return int(x))
	for k in DB.C:
		if DB.is_foe(k):
			continue
		var c: Dictionary = DB.C[k]
		var key := JSON.stringify([c.name, int(c.tier), c.tag])
		if not idx.has(key) or DB.C[idx[key]].kind == "retired":
			idx[key] = k
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(str(a.get("in", ""))))
	var myths: Array = DB.by_tier(8).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k) and DB.C[k].kind != "retired")
	myths.sort()
	var feats8: Array = myths + ["L12"]
	if a.has("only"):
		var only: Array = Array(str(a.only).split(",", false))
		feats8 = feats8.filter(func(k): return only.has(k))
	var feats7: Array = DB.by_tier(7).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k) and DB.C[k].kind != "retired")
	feats7.sort()
	var done := {}      # --resume=앞 출력 파일 —— 이미 잰 (판 · 쪽 · 신화 · 씨앗) 은 건너뛴다
	if a.has("resume") and FileAccess.file_exists(str(a.resume)):
		for line in FileAccess.get_file_as_string(str(a.resume)).split("
", false):
			var o = JSON.parse_string(line)
			if o is Dictionary:
				done["%d|%s|%s|%d" % [int(o.bi), str(o.side), str(o.m), int(o.seed)]] = true
	var f := FileAccess.open(str(a.get("out", "user://real_myth_swap.jsonl")), FileAccess.WRITE)
	var skipped := 0
	for bi in rows.size():
		if bi % parts != part - 1:
			continue
		var b: Dictionary = rows[bi]
		if int(b.day) not in only_days:
			continue
		var me := _side(b.me)
		var foe := _side(b.foe)
		if me.is_empty() or foe.is_empty():
			skipped += 1
			continue
		var plan := {}
		if not (b.me_plan as Array).is_empty() or not (b.foe_plan as Array).is_empty():
			plan = {"A": {"p": b.me_plan, "own": b.me_own, "perm": []}, "B": {"p": b.foe_plan, "own": [], "perm": []}}
		if mode == "repro":
			for flip in ([false, true] if bool(b.foe_human) else [false]):
				var r := _run(me, foe, plan, int(b.seed), flip)
				var mine := "B" if flip else "A"
				var left := 0.0
				var fl := 0.0
				for u in r.roster:
					if u.camp == mine: left += maxf(0.0, float(u.left))
					else: fl += maxf(0.0, float(u.left))
				var w: bool = bool(r.win) != flip and not bool(r.draw)
				f.store_line(JSON.stringify({"bi": bi, "day": b.day, "flip": flip, "win": w, "draw": bool(r.draw), "left": left, "foe_left": fl,
					"rec_win": b.win, "rec_draw": b.draw, "rec_left": b.left, "rec_foe_left": b.foe_left, "items": not (b.me.items as Array).is_empty()}))
			continue
		for sname in ["me", "foe"]:
			var S: Dictionary = me if sname == "me" else foe
			var O: Dictionary = foe if sname == "me" else me
			var want := 8 if mode == "swap" else 7
			var slot := -1
			for i in S.cards.size():
				if S.cards[i] != null and int(DB.C[S.cards[i]].tier) == want and not DB.is_kiin(S.cards[i]):
					slot = i
					break
			if slot < 0:
				continue
			var orig: String = S.cards[slot]
			var others := {}
			for i in S.cards.size():
				if i != slot and S.cards[i] != null:
					others[DB.person(S.cards[i])] = true
			for ft in (feats8 if mode == "swap" else feats7):
				if others.has(DB.person(ft)):
					continue
				var S2: Dictionary = S.duplicate(true)
				S2.cards[slot] = ft
				var inn = DB.ITEM_BY_NAME.get(DB.C[orig].need) if str(DB.C[orig].need) != "" else null
				if S2.equip[slot] is Array:
					S2.equip[slot] = (S2.equip[slot] as Array).filter(func(x): return x != inn)
				for si in nseed:
					if done.has("%d|%s|%s|%d" % [bi, sname, ft, si]):
						continue
					var sd := int(b.seed) + si * 7919
					var r: Dictionary
					var bt: RtBattle
					var cp := "A" if sname == "me" else "B"
					if sname == "me":
						bt = RtBattle.new(sd)
						r = _run_bt(bt, S2, O, plan, false)
					else:
						bt = RtBattle.new(sd)
						r = _run_bt(bt, O, S2, plan, false)
					var won: float = 0.5 if bool(r.draw) else (1.0 if bool(r.win) == (cp == "A") else 0.0)
					var tot := 0.0
					var mine := 0.0
					var alive := false
					for u in r.roster:
						if u.camp == cp:
							tot += float(u.dmg) - float(u.over)
							if int(u.slot) == slot:
								mine = float(u.dmg) - float(u.over)
								alive = bool(u.alive)
					var fires := 0
					var ultn := 0
					for u in bt.units:
						if u.camp == cp and u.slot == slot:
							for j in u.sk_cnt:
								fires += int(u.sk_cnt[j])
							ultn = u.ult_n
					bt.units.clear()
					f.store_line(JSON.stringify({"bi": bi, "day": b.day, "side": sname, "orig": orig, "m": ft, "seed": si, "w": won, "tag": DB.C[ft].tag, "caster": Battle.is_caster(DB.C[ft]),
						"share": mine / maxf(1.0, tot), "fires": fires, "ult": ultn, "alive": alive}))
	f.close()
	print("ZGL_REAL done mode=%s part=%d/%d skipped=%d miss=%s" % [mode, part, parts, skipped, JSON.stringify(miss.keys().slice(0, 10))])
	get_tree().quit(0)


## 기록 한 쪽 → {cards: 칸 배열(9), equip: 칸별 [아이템 id …], form, morale, tac}. 이름 · 등급 · 병종으로 카드 id 를 찾는다 (못 찾으면 빈 사전)
func _side(s: Dictionary) -> Dictionary:
	var ids := []
	for c in s.cards:
		var key := JSON.stringify([str(c[0]), int(c[1]), str(c[2])])
		if not idx.has(key):
			miss[key] = true
			return {}
		ids.append(idx[key])
	var form: String = str(s.form) if DB.FORM.has(str(s.form)) else "eorin"
	var slots: Array = DB.FORM[form].slots
	var cards := []
	cards.resize(slots.size())
	var equip := []
	equip.resize(slots.size())
	var items: Array = s.get("items", [])
	var lines: Array = s.get("lines", [])
	if ids.size() == slots.size():
		for i in ids.size():
			cards[i] = ids[i]
			equip[i] = _items(items, i)
	elif lines.size() == ids.size():
		var at := -1
		for i in ids.size():
			var put := -1
			for j in range(at + 1, slots.size()):
				if slots[j].line == lines[i]:
					put = j
					break
			if put < 0:
				return _auto(ids, items, form, s)
			cards[put] = ids[i]
			equip[put] = _items(items, i)
			at = put
	else:
		return _auto(ids, items, form, s)
	return {"cards": cards, "equip": equip, "form": form, "morale": float(s.morale), "tac": str(s.tac)}


func _auto(ids: Array, items: Array, form: String, s: Dictionary) -> Dictionary:
	var cards := DB.auto_place(ids, form)
	var equip := []
	equip.resize(cards.size())
	for i in cards.size():
		if cards[i] != null:
			equip[i] = _items(items, ids.find(cards[i]))
	return {"cards": cards, "equip": equip, "form": form, "morale": float(s.morale), "tac": str(s.tac)}


func _items(items: Array, i: int):
	if i < 0 or i >= items.size():
		return null
	var out := []
	for nm in items[i]:
		if DB.ITEM_BY_NAME.has(str(nm)):
			out.append(DB.ITEM_BY_NAME[str(nm)])
	return out if not out.is_empty() else null


func _run(me: Dictionary, foe: Dictionary, plan: Dictionary, seed_v: int, flip: bool) -> Dictionary:
	var bt := RtBattle.new(seed_v)
	var r := _run_bt(bt, foe if flip else me, me if flip else foe, plan, flip)
	bt.units.clear()
	return r


func _run_bt(bt: RtBattle, A: Dictionary, B: Dictionary, plan: Dictionary, flip: bool) -> Dictionary:
	var pol := {"A": Run.side_pol({"tac": A.tac}), "B": Run.side_pol({"tac": B.tac})}
	if not plan.is_empty():
		pol["plan"] = {"A": plan.B, "B": plan.A} if flip else plan
	return bt.run(A.cards, A.form, A.morale, A.equip, B.cards, B.form, B.morale, B.equip, "", "", [], pol)
