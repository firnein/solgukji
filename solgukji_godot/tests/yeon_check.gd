extends Node
## 11/26 인연 점검 —— 실제 온라인 대전 기록의 덱 쌍으로 인연 규칙을 바꿔 가며 같은 시드로 다시 싸운다 (측정 전용, 기록은 읽기만). 결과 정리: docs/인연_분석_1126.md
## 입력: 기록 정리본 JSON —— python tools/scripts/real_battles.py <playlog_online 폴더> <출력 json> (tests/counter_check 와 같은 형식)
## 실행:
##   godot --headless --path . res://tests/yeon_check.tscn -- --mode=dump --out=C:/.../yeon_db.json
##       인연 · 인물 표 (인물 → 세력 · 카드 [등급, 병종, 갈래] · 전열 선호) + 카드 이름 → 인물
##   godot --headless --path . res://tests/yeon_check.tscn -- --mode=sim --in=C:/.../real_battles.json [--min=5.0] [--seeds=2] [--vars=base,offA,offB,...] [--part=1 --parts=4] --out=C:/.../x.jsonl
##       평균 등급(양쪽 카드 평균)이 --min 이상인 판마다, 시드 seed .. seed+seeds-1 로 변형(vars)마다 한 판씩 —— 한 줄씩 jsonl:
##       aw: A(기록의 내 쪽) 승 1 · 무 0.5 · 패 0 · mg A 쪽 남은 병력 몫 차(-1~1, 승패보다 촘촘) · tm 전투 길이 · ults 터진 고유기(미니 제외) · yj 연쇄(합동 2명 이상) 수 · yu 연쇄에 든 장수 수 · n2/n3/n4 인원별 · yb 기본 연쇄 · th 주제 효과
## 변형(vars):
##   base   지금 그대로                       none   인연 전부 끔 (Battle.inyeon_enabled)
##   notheme 주제 효과 · 기인 · 초월 덤 끔     offA / offB  A(또는 B) 진영만 인연 끔 (tests/yeon_bt) —— 같은 덱이 인연 덕에 얻는 승률
##   basic  (가) 두 단 연쇄 (RtBattle.yeon_basic) —— basic_offA / basic_offB: 기본 연쇄는 켠 채 그 진영만 인연 끔
##   basic2 (가) 변형 —— 기본 연쇄 2명까지 (yeon_basic_max 2)
##   all    인연 폐기 + 누구나 연쇄 (모든 인물을 한 인연으로, 주제 효과 없음 · 3~4명)
##   mix    (다) 병종 섞인 연쇄만 주제 효과 (연쇄에 물리 · 책략이 함께 끼어야 주제가 터진다) —— 이 점검에서만 (엔진 스위치 없음, tests/yeon_bt)
##   mix_offA / mix_offB
var idx := {}


func _ready() -> void:
	PlayLog.enabled = false
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if str(a.get("mode", "sim")) == "dump":
		_dump(str(a.get("out", "user://yeon_db.json")))
		get_tree().quit(0)
		return
	var part := int(a.get("part", "1"))
	var parts := int(a.get("parts", "1"))
	var mn := float(a.get("min", "5.0"))
	var seeds := int(a.get("seeds", "1"))
	var vars: Array = str(a.get("vars", "base,offA,offB,none,notheme,basic,basic_offA,basic_offB,all")).split(",")
	for k in DB.C:
		if DB.is_foe(k):
			continue
		var c: Dictionary = DB.C[k]
		var key := JSON.stringify([c.name, int(c.tier), c.tag])
		if not idx.has(key) or DB.C[idx[key]].kind == "retired":
			idx[key] = k
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(str(a.get("in", ""))))
	var sw = load("res://tests/real_myth_swap.gd").new()
	sw.idx = idx
	var BT = load("res://tests/yeon_bt.gd")
	var y0: Dictionary = DB.INYEON
	var yo0: Dictionary = DB.INYEON_OF
	var yall := _all_yeon()
	var f := FileAccess.open(str(a.get("out", "user://yeon_check_%d.jsonl" % part)), FileAccess.WRITE)
	var k := 0
	for bi in rows.size():
		var b: Dictionary = rows[bi]
		var av := (_avg(b.me) + _avg(b.foe)) / 2.0
		if av < mn:
			continue
		k += 1
		if k % parts != part - 1:
			continue
		var me: Dictionary = sw._side(b.me)
		var foe: Dictionary = sw._side(b.foe)
		if me.is_empty() or foe.is_empty():
			continue
		var plan := {}
		if not (b.me_plan as Array).is_empty() or not (b.foe_plan as Array).is_empty():
			plan = {"A": {"p": b.me_plan, "own": b.me_own, "perm": []}, "B": {"p": b.foe_plan, "own": [], "perm": []}}
		for si in seeds:
			for v in vars:
				var vs := str(v)
				var base := vs.split("_")[0]
				Battle.inyeon_enabled = base != "none"
				RtBattle.inyeon_theme = base != "notheme"
				RtBattle.yeon_basic = base.begins_with("basic")
				RtBattle.yeon_basic_max = 2 if base == "basic2" else 1
				if base == "all":
					DB.INYEON = yall[0]
					DB.INYEON_OF = yall[1]
				var bt = BT.new(int(b.seed) + si)
				bt.mix_only = base == "mix"
				if vs.ends_with("offA") or vs == "offA":
					bt.off_camp = "A"
				elif vs.ends_with("offB") or vs == "offB":
					bt.off_camp = "B"
				var r: Dictionary = sw._run_bt(bt, me, foe, plan, false)
				DB.INYEON = y0
				DB.INYEON_OF = yo0
				var ults := 0
				var tm := 0.0
				for e in r.ev:
					tm = maxf(tm, float(e.get("tm", 0.0)))
					if e.get("fx") == "ult" and not e.get("mini", false):
						ults += 1
				var aw: float = 0.5 if bool(r.draw) else (1.0 if bool(r.win) else 0.0)
				var st: Dictionary = bt.stats
				var hp := {"A": 0.0, "B": 0.0}      # 진영별 남은 병력 몫 (살아 있는 장수 병력 / 최대, 진영 장수 수로 나눔)
				var cn := {"A": 0, "B": 0}
				for u in bt.units:
					if not hp.has(u.camp):
						continue
					cn[u.camp] += 1
					if u.alive:
						hp[u.camp] += clampf(u.troops / maxf(1.0, u.max), 0.0, 1.0)
				var mg: float = hp.A / maxf(1.0, cn.A) - hp.B / maxf(1.0, cn.B)      # A 쪽 남은 병력 차 (-1 ~ 1) —— 승패보다 촘촘한 지표
				f.store_line(JSON.stringify({"bi": bi, "s": si, "v": vs, "av": snappedf(av, 0.01), "aw": aw, "mg": snappedf(mg, 0.001), "tm": snappedf(tm, 0.1), "ults": ults,
					"yj": int(st.get("inyeon_joint", 0)), "yu": int(st.get("inyeon_units", 0)), "n2": int(st.get("inyeon_n2", 0)), "n3": int(st.get("inyeon_n3", 0)),
					"n4": int(st.get("inyeon_n4", 0)), "yb": int(st.get("yeon_basic", 0)), "th": int(st.get("inyeon_theme", 0)), "mx": int(bt.mix_skip)}))
				bt.units.clear()
	f.close()
	Battle.inyeon_enabled = true
	RtBattle.inyeon_theme = true
	RtBattle.yeon_basic = false
	print("ZGL_YEON 끝 part %d" % part)
	get_tree().quit(0)


## 인연 폐기 + 누구나 연쇄 —— 고유기 카드가 있는 모든 인물을 한 인연 "누구나"로 (주제 · 인연기 없음)
func _all_yeon() -> Array:
	var ps := {}
	for k in DB.C:
		if DB.is_foe(k):
			continue
		ps[DB.person(k)] = true
	var y := {"누구나": ps.keys()}
	var yo := {}
	for p in ps:
		yo[p] = ["누구나"]
	return [y, yo]


func _dump(out: String) -> void:
	var per := {}
	var name2p := {}
	for k in DB.C:
		if DB.is_foe(k):
			continue
		var c: Dictionary = DB.C[k]
		var p := DB.person(k)
		name2p[c.name] = p
		if not per.has(p):
			per[p] = {"fac": c.fac, "cards": []}
		per[p].cards.append([int(c.tier), c.tag, c.kind, c.fac])
	var fw := {}
	for t in DB.D.FRONT_WANT:
		fw[t] = DB.D.FRONT_WANT[t]
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"inyeon": DB.INYEON, "theme": DB.INYEON_THEME, "fin": DB.INYEON_FIN, "person": per, "name2p": name2p, "front_want": fw,
		"phys": DB.PHYS_TAGS, "int": DB.INT_TAGS}))
	f.close()
	print("ZGL_YEON dump %s" % out)


func _avg(s: Dictionary) -> float:
	var t := 0.0
	for c in s.cards:
		t += float(c[1])
	return t / maxf(1.0, float(s.cards.size()))
