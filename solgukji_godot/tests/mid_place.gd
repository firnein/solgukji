extends Node
## 11/26 원거리 가운데 배치 점검 (DB.mid_place) —— 모든 진형 × 덱에서 자동 배치(DB.auto_place)를 끔 / 켬으로 놓아 본다 (전투는 돌리지 않는다)
## 실행: godot --headless --path . res://tests/mid_place.tscn -- [--in=C:/.../real_battles.json] [--gen=40] [--dump]
##   --in  : 실제 온라인 대전 기록 정리본 (tools/scripts/real_battles.py). 없으면 봇 덱(DB.gen_board)만으로 본다
##   --gen : 봇 덱 수 (PV × 성향 × 씨앗, 기본 60)
##   --dump: 원거리 카드 세기(등급 · PV) 표를 찍는다
## 점검 (mid_place_aff 0 · 1 · 2 모두):
##   (가) 같은 줄 안에서 더 강한 원거리가 더 약한 원거리 · 빈 칸보다 바깥에 서 있으면, 그 까닭이 칸 선호(적성) 규칙이어야 한다 —— 아니면 실패
##   (나) 근접 부대의 칸이 끈 배치와 같다   (다) 모든 부대의 줄이 끈 배치와 같다   (라) 카드 묶음이 같다 · 두 번 불러도 같다 · 새로 '나쁜 자리'에 선 원거리가 없다
## 덧붙여 센다: 가장 강한 원거리가 바깥 열에 선 덱 · 전체 원거리 가운데 가장 가운데 열에 선 덱 · 선호를 잃은 / 얻은 부대
var fails := 0
var fail_msgs := []


func _ready() -> void:
	PlayLog.enabled = false
	get_tree().create_timer(500.0).timeout.connect(func(): get_tree().quit(1))
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var keep_on := DB.mid_place
	var keep_aff := DB.mid_place_aff
	if not keep_on:
		_fail("기본값: DB.mid_place 가 꺼져 있다")
	if a.has("dump"):
		_dump()
	var decks := []      # [카드 id 배열, 기록된 진형("" 이면 없음), 출처]
	var real_n := 0
	if a.has("in"):
		var idx := {}
		for k in DB.C:
			if DB.is_foe(k):
				continue
			var c: Dictionary = DB.C[k]
			var key := JSON.stringify([c.name, int(c.tier), c.tag])
			if not idx.has(key) or DB.C[idx[key]].kind == "retired":
				idx[key] = k
		var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(str(a["in"])))
		var seen := {}
		for b in rows:
			for sd in [b.me, b.foe]:
				var ids := []
				for c in sd.cards:
					var key := JSON.stringify([str(c[0]), int(c[1]), str(c[2])])
					if idx.has(key):
						ids.append(idx[key])
				if ids.is_empty():
					continue
				var fm := str(sd.form) if DB.FORM.has(str(sd.form)) else ""
				var sig := fm + JSON.stringify(ids)
				if seen.has(sig):
					continue
				seen[sig] = true
				decks.append([ids, fm, "real"])
				real_n += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 1126
	var gen_n := int(a.get("gen", "60"))
	for i in gen_n:
		var style: String = ["물리", "지략", "균형"][i % 3]
		var pv := 20.0 + 1100.0 * float(i) / float(maxi(1, gen_n - 1))
		var gb := DB.gen_board(pv, style, rng)
		decks.append([gb.cards.filter(func(k): return k != null), str(gb.form), "bot"])
	for i in 24:      # 모자란 덱 (초반 · 빈 칸) —— 봇 덱에서 몇 장 뺀다
		var gb := DB.gen_board(60.0 + 40.0 * i, ["물리", "지략", "균형"][i % 3], rng)
		var ids: Array = gb.cards.filter(func(k): return k != null)
		ids.resize(mini(ids.size(), 3 + i % 6))
		decks.append([ids, str(gb.form), "few"])
	var forms: Array = DB.FORM.keys().filter(func(k): return not str(k).begins_with(DB.HORDE_PFX))
	forms.sort()
	var horde: Array = DB.FORM.keys().filter(func(k): return str(k).begins_with(DB.HORDE_PFX))
	horde.sort()
	print("ZGL_MID 덱 %d (실제 %d · 봇 %d · 모자란 덱 24) × 진형 %d (+ 대군 %d)" % [decks.size(), real_n, gen_n, forms.size(), horde.size()])
	for aff in [0, 1, 2]:
		var tot := _stat()
		var per := {}
		for fm in forms + horde:
			var st := _stat()
			for d in decks:
				_one(d[0], fm, aff, st)
			per[fm] = st
			if not str(fm).begins_with(DB.HORDE_PFX):
				for k in tot:
					tot[k] += st[k]
		print("ZGL_MID aff=%d %s" % [aff, " (기본)" if aff == keep_aff else ""])
		print("  진형 | 덱 | 바뀐 덱 | 최강 원거리 바깥 열: 끔 → 켬 | 최강이 원거리 중 가장 가운데: 끔 → 켬 | 최강의 열 거리 평균 | 선호 잃음 · 얻음 | 선호 때문에 남은 쌍 · 나쁜 자리 때문에 남은 쌍")
		for fm in forms + ["합계"] + horde:
			var st: Dictionary = tot if fm == "합계" else per[fm]
			var n: int = maxi(1, st.n)
			print("  %s | %d | %d | %d → %d (%.1f%% → %.1f%%) | %d → %d (%.1f%% → %.1f%%) | %.2f → %.2f | %d · %d | %d · %d" % [fm, st.n, st.changed,
				st.top_out0, st.top_out1, 100.0 * st.top_out0 / n, 100.0 * st.top_out1 / n,
				st.top_mid0, st.top_mid1, 100.0 * st.top_mid0 / n, 100.0 * st.top_mid1 / n,
				float(st.cen0) / n, float(st.cen1) / n, st.aff_lost, st.aff_gain, st.keep_aff, st.keep_bad])
	# 기록된 진형 그대로 (실제 덱 + 봇 덱)
	for aff in [0, 1, 2]:
		var own := _stat()
		for d in decks:
			if str(d[1]) != "" and d[2] != "few":
				_one(d[0], str(d[1]), aff, own)
		var on: int = maxi(1, own.n)
		print("ZGL_MID 제 진형 (기록 · 봇이 고른 진형) aff=%d%s: 덱 %d · 바뀐 덱 %d · 최강 원거리 바깥 열 %d → %d (%.1f%% → %.1f%%) · 최강이 가장 가운데 %.1f%% → %.1f%% · 선호 잃음 %d · 얻음 %d · 선호 때문에 남은 쌍 %d · 나쁜 자리 때문에 남은 쌍 %d · 켠 뒤에도 바깥인 까닭: 줄에 안쪽 칸 없음 %d · 안쪽 칸이 모두 근접 %d · 그 밖 %d" % [
			aff, " (기본)" if aff == keep_aff else "", own.n, own.changed, own.top_out0, own.top_out1, 100.0 * own.top_out0 / on, 100.0 * own.top_out1 / on,
			100.0 * own.top_mid0 / on, 100.0 * own.top_mid1 / on, own.aff_lost, own.aff_gain, own.keep_aff, own.keep_bad, own.out_shape, own.out_melee, own.out_etc])
	DB.mid_place = keep_on
	DB.mid_place_aff = keep_aff
	for m in fail_msgs:
		print("  실패: ", m)
	print("ZGL_MID %s · 실패 %d" % ["통과" if fails == 0 else "실패", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _stat() -> Dictionary:
	return {"n": 0, "changed": 0, "top_out0": 0, "top_out1": 0, "top_mid0": 0, "top_mid1": 0, "cen0": 0, "cen1": 0,
		"aff_lost": 0, "aff_gain": 0, "keep_aff": 0, "keep_bad": 0, "out_shape": 0, "out_melee": 0, "out_etc": 0}


func _fail(m: String) -> void:
	fails += 1
	if fail_msgs.size() < 12:
		fail_msgs.append(m)


func _cen(fm: String, i: int) -> int:
	return absi(int(DB.FORM[fm].slots[i].col) - DB.FORM_MID)


## 가장 강한 원거리가 선 칸 (없으면 −1) —— 같은 세기면 가운데 쪽 것
func _top(cards: Array, fm: String) -> int:
	var best := -1
	for i in mini(cards.size(), DB.FORM[fm].slots.size()):
		if not DB.is_ranged(cards[i]):
			continue
		if best < 0 or DB.place_power(cards[i]) > DB.place_power(cards[best]) \
				or (DB.place_power(cards[i]) == DB.place_power(cards[best]) and _cen(fm, i) < _cen(fm, best)):
			best = i
	return best


func _one(ids: Array, fm: String, aff: int, st: Dictionary) -> void:
	var slots: Array = DB.FORM[fm].slots
	DB.mid_place = false
	var p0: Array = DB.auto_place(ids, fm)
	DB.mid_place = true
	DB.mid_place_aff = aff
	var p1: Array = DB.auto_place(ids, fm)
	var p1b: Array = DB.auto_place(ids, fm)
	var tag := "%s aff=%d %s" % [fm, aff, JSON.stringify(ids)]
	if p1 != p1b:
		_fail("두 번 부른 배치가 다르다 " + tag)
	if p0.size() != p1.size():
		_fail("배열 길이가 다르다 " + tag)
		return
	st.n += 1
	if p0 != p1:
		st.changed += 1
	# (나) 근접 · (다) 줄 · (라) 카드 묶음
	var l0 := {}
	var l1 := {}
	var all0 := []
	var all1 := []
	for i in p0.size():
		var k0 = p0[i]
		var k1 = p1[i]
		if (k0 != null and not DB.is_ranged(k0)) or (k1 != null and not DB.is_ranged(k1)):
			if k0 != k1:
				_fail("(나) 근접 부대 칸이 달라졌다 칸 %d: %s → %s · %s" % [i, str(k0), str(k1), tag])
		if i >= slots.size():
			if k0 != k1:
				_fail("진형 밖 칸이 달라졌다 " + tag)
			continue
		var ln: String = slots[i].line
		if k0 != null:
			l0[ln] = l0.get(ln, []) + [k0]
			all0.append(k0)
		if k1 != null:
			l1[ln] = l1.get(ln, []) + [k1]
			all1.append(k1)
	all0.sort()
	all1.sort()
	if all0 != all1:
		_fail("(라) 카드 묶음이 달라졌다 " + tag)
	for ln in DB.D.LINES:
		var x: Array = l0.get(ln, [])
		var y: Array = l1.get(ln, [])
		x.sort()
		y.sort()
		if x != y:
			_fail("(다) %s 줄의 부대가 달라졌다 %s" % [ln, tag])
	# 선호 변화 —— 카드별 (같은 카드가 여러 장이면 합으로)
	var r0 := 0
	var r1 := 0
	var bad0 := 0
	var bad1 := 0
	for i in mini(p0.size(), slots.size()):
		if DB.is_ranged(p0[i]):
			var z := DB._aff_rank(p0[i], slots[i])
			r0 += z
			bad0 += 1 if z < 0 else 0
		if DB.is_ranged(p1[i]):
			var z := DB._aff_rank(p1[i], slots[i])
			r1 += z
			bad1 += 1 if z < 0 else 0
	for ln in DB.D.LINES:      # 줄마다 · 카드 종류마다 옛 칸 / 새 칸의 선호를 큰 순으로 짝지어 견준다 (같은 카드가 여러 장일 수 있다)
		var o := {}
		var w := {}
		for i in mini(p0.size(), slots.size()):
			if slots[i].line != ln:
				continue
			if DB.is_ranged(p0[i]):
				o[p0[i]] = o.get(p0[i], []) + [DB._aff_rank(p0[i], slots[i])]
			if DB.is_ranged(p1[i]):
				w[p1[i]] = w.get(p1[i], []) + [DB._aff_rank(p1[i], slots[i])]
		for k in o:
			var x: Array = o[k]
			var y: Array = w.get(k, [])
			x.sort()
			y.sort()
			for i in mini(x.size(), y.size()):
				if y[i] < x[i]:
					st.aff_lost += 1
				elif y[i] > x[i]:
					st.aff_gain += 1
	if bad1 > bad0:
		_fail("(라) 나쁜 자리에 선 원거리가 늘었다 %d → %d · %s" % [bad0, bad1, tag])
	if aff == 0 and r1 < r0:
		_fail("aff=0 인데 선호 합이 줄었다 %d → %d · %s" % [r0, r1, tag])
	# (가) 같은 줄 —— 더 강한 원거리가 더 바깥이면 까닭이 있어야 한다
	for i in mini(p1.size(), slots.size()):
		if not DB.is_ranged(p1[i]):
			continue
		for j in mini(p1.size(), slots.size()):
			if j == i or slots[j].line != slots[i].line:
				continue
			var y = p1[j]
			if y != null and (not DB.is_ranged(y) or DB.place_power(y) >= DB.place_power(p1[i])):
				continue
			if _cen(fm, j) >= _cen(fm, i):
				continue
			# i 의 강한 원거리가 j(더 가운데, 약한 원거리 · 빈 칸)보다 바깥 —— 맞바꾸면 선호가 내려가야만 한다
			var xr := DB._aff_rank(p1[i], slots[j])
			var yr := 0 if y == null else DB._aff_rank(y, slots[i])
			var free: bool = xr >= DB._aff_rank(p1[i], slots[i]) and (y == null or yr >= DB._aff_rank(y, slots[j]))
			if free:
				_fail("(가) %s 줄: 칸 %d(%s)가 칸 %d(%s)보다 바깥인데 까닭이 없다 · %s" % [slots[i].line, i, str(p1[i]), j, str(y), tag])
			elif xr < 0 or yr < 0:
				st.keep_bad += 1
			elif aff == 0 or (aff == 1 and _cen(fm, i) < 2):
				st.keep_aff += 1
			else:
				# 선호를 내주고라도 옮겼어야 하는 자리 —— 다만 aff=1 에서는 선호를 지키는 안쪽 자리로 이미 나왔을 수 있다 (그때는 안쪽 → 가운데가 남는다 = 위 조건)
				_fail("(가) %s 줄: 칸 %d(%s) → 칸 %d(%s) 를 옮기지 않았다 · %s" % [slots[i].line, i, str(p1[i]), j, str(y), tag])
	# 가장 강한 원거리
	var t0 := _top(p0, fm)
	var t1 := _top(p1, fm)
	if t0 >= 0 and t1 >= 0:
		st.cen0 += _cen(fm, t0)
		st.cen1 += _cen(fm, t1)
		st.top_out0 += 1 if _cen(fm, t0) == 2 else 0
		st.top_out1 += 1 if _cen(fm, t1) == 2 else 0
		if _cen(fm, t1) == 2:      # 켠 뒤에도 바깥 열 —— 까닭: 그 줄에 안쪽 칸이 없다 / 안쪽 칸을 모두 근접이 차지 / 그 밖(세기가 같은 원거리 · 칸 선호)
			var inner := 0
			var melee := 0
			for j in mini(p1.size(), slots.size()):
				if slots[j].line == slots[t1].line and _cen(fm, j) < 2:
					inner += 1
					melee += 1 if (p1[j] != null and not DB.is_ranged(p1[j])) else 0
			st[("out_shape" if inner == 0 else ("out_melee" if melee == inner else "out_etc"))] += 1
		var m0 := 9
		var m1 := 9
		for i in mini(p0.size(), slots.size()):
			if DB.is_ranged(p0[i]):
				m0 = mini(m0, _cen(fm, i))
			if DB.is_ranged(p1[i]):
				m1 = mini(m1, _cen(fm, i))
		st.top_mid0 += 1 if _cen(fm, t0) == m0 else 0
		st.top_mid1 += 1 if _cen(fm, t1) == m1 else 0


func _dump() -> void:
	var rows := []
	for k in DB.C:
		if DB.is_foe(k) or not DB.is_ranged(k) or DB.C[k].kind == "retired":
			continue
		rows.append(k)
	rows.sort_custom(func(x, y): return DB.place_power(x) > DB.place_power(y))
	var by := {}
	for k in rows:
		var g := "기인" if DB.is_kiin(k) else str(int(DB.C[k].tier))
		by[g] = by.get(g, []) + [int(DB.C[k].pv)]
	for g in by:
		var v: Array = by[g]
		print("ZGL_MID 세기 등급 %s: %d장 PV %d ~ %d" % [g, v.size(), v.min(), v.max()])
