extends Node
## 11/27 장수 키트 Q · W · E · R · P —— 실제 온라인 대전 기록(정리본)으로 세기를 잰다 (측정 전용, 기록은 읽기만)
## 입력: tests/real_myth_swap.gd 와 같은 기록 정리본 JSON. 덱 · 진형 · 장비 · 사기 · 군략은 기록 그대로 (내 쪽 A)
## 실행: godot --headless --path . res://tests/kit_measure.tscn -- --in=C:/.../real_battles.json --out=C:/.../x.jsonl [--part=1 --parts=4]
##   --kit=off|on        : Kit.enabled (off = 예전 그대로 —— 일반 특기까지 다 쓴다)
##   --up=none|q|q,w|<카드>:q,w;<카드>:r   : A 진영 키트 장수가 강화한 칸 (칸 목록이면 A 의 키트 장수 모두 · 카드를 적으면 그 장수만)
##   --upb=…             : B 진영 키트 장수에게 (기본 none)
##   --only=myth|mythA   : 신화가 든 판만 / A 에 신화가 든 판만
##   --swap7=A|B|AB      : 그 진영에 신화가 없으면 가장 앞 칸의 불멸(7성) 한 장을 같은 병종의 신화로 바꿔 끼운다 (표본 늘리기 —— 같은 인물이 덱에 있으면 건너뜀)
##   --reseed=n          : 기록 씨앗에 n × 7919 를 더한다 (되풀이 표본)
##   --base_sk= --base_ult= --base_p= --base_sup=   : Kit 바탕 배율을 바꿔 본다 (맞추기용 —— 기술 피해 · 고유기 타격 · 고유 특기 · 아군 회복/강화)
## 읽는 법: 같은 판(bi) · 같은 씨앗의 --kit=off 출력과 짝지어 ① 신화가 든 쪽의 승(k 의 진영 기준) ② k[3]/k[4] = 신화 부대의 진영 피해 몫을 비교한다.
##   양쪽에 신화가 든 판은 신화 쪽 승률이 늘 50% 라 승률은 한쪽에만 신화가 든 판으로도 따로 본다. fp 가 같으면 그 판은 사건까지 같다 (kit=off 는 바꾸기 전과 650판 모두 같았다)
##   --fp                : 사건 지문(결정성 · 전후 비교)만 —— 판마다 {bi, win, len, fp}
## 판마다 한 줄: {bi, day, win(A 승 1 · 0.5 · 0), len, fp, mg(남은 병력 비의 차 A − B), kup{"진영:카드:칸": 강화가 일한 횟수}, k: [[진영, 칸, 카드, 준 피해, 진영 피해 합, 살았나, 기술 수, 고유기 수, 받은 피해, 최대 병력, 치료, 사기 피해]]}
const Kit := preload("res://scripts/kit.gd")


func _ready() -> void:
	PlayLog.enabled = false
	get_tree().create_timer(7000.0).timeout.connect(func(): get_tree().quit(1))
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var part := int(a.get("part", "1"))
	var parts := int(a.get("parts", "1"))
	var reseed := int(a.get("reseed", "0"))
	var only := str(a.get("only", ""))
	var swap7 := str(a.get("swap7", ""))
	var fp_only := a.has("fp")
	Kit.enabled = str(a.get("kit", "on")) != "off"
	if a.has("base_sk"):
		Kit.base_sk = float(a.base_sk)
	if a.has("base_ult"):
		Kit.base_ult = float(a.base_ult)
	if a.has("base_p"):
		Kit.base_p = float(a.base_p)
	if a.has("base_sup"):
		Kit.base_sup = float(a.base_sup)
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
	var myth_by_tag := {}      # 병종 -> 신화 카드들 (바꿔 끼우기용)
	for k in DB.by_tier(8):
		if DB.is_foe(k) or DB.is_kiin(k) or DB.C[k].kind == "retired" or not DB.has_ult(k):
			continue
		if not myth_by_tag.has(DB.C[k].tag):
			myth_by_tag[DB.C[k].tag] = []
		myth_by_tag[DB.C[k].tag].append(k)
	for t in myth_by_tag:
		myth_by_tag[t].sort()
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(str(a.get("in", ""))))
	var f := FileAccess.open(str(a.get("out", "user://kit_measure_%d.jsonl" % part)), FileAccess.WRITE)
	var n := 0
	for bi in rows.size():
		if bi % parts != part - 1:
			continue
		var b: Dictionary = rows[bi]
		var me: Dictionary = sw._side(b.me)
		var foe: Dictionary = sw._side(b.foe)
		if me.is_empty() or foe.is_empty():
			continue
		var swapped := []
		for pair in [["A", me], ["B", foe]]:
			if swap7.contains(pair[0]) and _myths(pair[1]).is_empty():
				var to := _swap7(pair[1], myth_by_tag, bi)
				if to != "":
					swapped.append([pair[0], to])
		var ma := _myths(me)
		var mb := _myths(foe)
		if only == "myth" and ma.is_empty() and mb.is_empty():
			continue
		if only == "mythA" and ma.is_empty():
			continue
		if a.has("has"):      # --has=c186,c194 : 그 카드가 든 판만 (장수별 수치 맞추기)
			var want: Array = Array(str(a.has).split(",", false))
			if not (ma + mb).any(func(x): return want.has(x)):
				continue
		var plan := {}
		if not (b.me_plan as Array).is_empty() or not (b.foe_plan as Array).is_empty():
			plan = {"A": {"p": b.me_plan, "own": b.me_own, "perm": []}, "B": {"p": b.foe_plan, "own": [], "perm": []}}
		var pol := {"A": Run.side_pol({"tac": me.tac}), "B": Run.side_pol({"tac": foe.tac})}
		if not plan.is_empty():
			pol["plan"] = plan
		var ka := _ups(ma, str(a.get("up", "none")))
		var kb := _ups(mb, str(a.get("upb", "none")))
		if not ka.is_empty() or not kb.is_empty():
			pol["kit"] = {"A": ka, "B": kb}
		var bt := RtBattle.new(int(b.seed) + reseed * 7919)
		var r: Dictionary = bt.run(me.cards, me.form, me.morale, me.equip, foe.cards, foe.form, foe.morale, foe.equip, "", "", [], pol)
		var w := 0.5 if bool(r.draw) else (1.0 if bool(r.win) else 0.0)
		var h := 0
		for e in r.ev:
			h = hash([h, e.get("t"), e.get("fx"), e.get("a"), e.get("f"), e.get("n"), e.get("m")])
		for u in r.roster:
			h = hash([h, u.key, u.left, u.dmg, u.taken, u.alive])
		if fp_only:
			f.store_line(JSON.stringify({"bi": bi, "win": w, "len": float(r.len), "fp": h, "nev": r.ev.size()}))
		else:
			var tot := {"A": 0.0, "B": 0.0}
			for u in r.roster:
				tot[u.camp] += float(u.dmg) - float(u.over)
			var ks := []
			var kups := {}      # 강화 효과가 일한 횟수 {"카드:칸": n}
			for sk in bt.stats:
				if str(sk).begins_with("kup:"):
					kups[str(sk).substr(4)] = int(bt.stats[sk])
			for u in bt.units:
				if int(u.c.tier) < 8 or u.ult == null:
					continue
				var fires := 0
				for j in u.sk_cnt:
					fires += int(u.sk_cnt[j])
				ks.append([u.camp, u.slot, u.c.id, roundi(u.dmg - u.over), roundi(tot[u.camp]), u.alive, fires, u.ult_n, roundi(u.taken), roundi(u.max), roundi(u.htr), snappedf(u.mdmg, 0.1)])
			var left := {"A": 0.0, "B": 0.0}
			var mx := {"A": 0.0, "B": 0.0}
			for u in r.roster:
				left[u.camp] += maxf(0.0, float(u.left)) if bool(u.alive) else 0.0
				mx[u.camp] += float(u.max)
			var mg := snappedf(left.A / maxf(1.0, mx.A) - left.B / maxf(1.0, mx.B), 0.0001)      # 남은 병력 비의 차 (A − B) —— 승패보다 촘촘한 세기 척도
			f.store_line(JSON.stringify({"bi": bi, "day": b.day, "win": w, "len": float(r.len), "fp": h, "mg": mg, "k": ks, "sw": swapped,
				"st": {"burn": roundi(float(bt.stats.burn)), "sk_n": int(bt.stats.sk_n)}, "kup": kups}))
		bt.units.clear()
		n += 1
	f.close()
	print("KIT_MEASURE done part=%d/%d n=%d kit=%s up=%s" % [part, parts, n, Kit.enabled, str(a.get("up", "none"))])
	get_tree().quit(0)


## 그 진영의 신화(고유기 있는 8성) 카드 id 들
func _myths(S: Dictionary) -> Array:
	var out := []
	for k in S.cards:
		if k != null and int(DB.C[k].tier) >= 8 and DB.has_ult(k) and not DB.is_foe(k):
			out.append(k)
	return out


## 가장 앞 칸의 불멸 한 장을 같은 병종 신화로 (없으면 "") —— 여럿이면 판 번호로 돌려 가며. 그 불멸의 전용 장비는 뺀다
func _swap7(S: Dictionary, by_tag: Dictionary, bi: int) -> String:
	var people := {}
	for k in S.cards:
		if k != null:
			people[DB.person(k)] = true
	for i in S.cards.size():
		var k = S.cards[i]
		if k == null or int(DB.C[k].tier) != 7 or DB.is_kiin(k):
			continue
		var cand: Array = (by_tag.get(DB.C[k].tag, []) as Array).filter(func(m): return not people.has(DB.person(m)) or DB.person(m) == DB.person(k))
		if cand.is_empty():
			continue
		var to: String = cand[bi % cand.size()]
		var inn = DB.ITEM_BY_NAME.get(DB.C[k].need) if str(DB.C[k].need) != "" else null
		if S.equip[i] is Array:
			S.equip[i] = (S.equip[i] as Array).filter(func(x): return x != inn)
		S.cards[i] = to
		return to
	return ""


## 강화 상태 —— none · "q,w"(그 진영 키트 장수 모두) · "c177:q,w;c190:r"(그 장수만). 규칙에 안 맞는 것은 엔진이 Kit.norm 으로 거른다
func _ups(ids: Array, spec: String) -> Dictionary:
	var out := {}
	if spec == "none" or spec == "":
		return out
	if spec.contains(":"):
		for one in spec.split(";", false):
			var kv := one.split(":")
			if kv.size() == 2 and ids.has(kv[0]):
				out[kv[0]] = Array(kv[1].split(",", false))
		return out
	for k in ids:
		out[k] = Array(spec.split(",", false))
	return out
