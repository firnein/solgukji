extends Node
## 토벌 고정 편성 맞추기 —— 실행: godot --headless --path . res://tests/quest_tune.tscn [-- --games=40 --target=0.75 --out=경로.json]
## 단계마다 '그 단계의 플레이어'(원본 QPV 무작위 덱, 장비 없음)와 같은 등급 분포로 황건 · 도사 장수를 채우고,
## 플레이어가 target 만큼 이길 때까지 위쪽 칸부터 한 등급씩 낮춘다. 결과를 JSON 으로 쓴다 (tools/scripts/quest_rosters.py --tuned 가 cards_ext 에 넣는다).
## 11/2: PV 만 맞추면 등급 차이(높은 등급이 늘 이김) 때문에 2~6일차는 너무 쉽고 7일차(신화 장각)는 너무 어려웠다.

const THEME := ["c22", "c20", "c21", "c32", "c33", "c31", "c69", "c58", "c72", "c70", "c73", "c107", "c110", "c108",
	"c133", "c148", "c147", "s16", "s14", "c173", "s12", "c192", "s13"]
const GEN := {1: ["occul", "rogue", "spear", "bow", "horse"], 2: ["c9", "c6", "c0", "c4", "c1", "c5", "c3", "c2"]}
var games := 40
var target := 0.75
var snaps := {}           # "일차-단계" -> [내 편성]
var day_target: Array = []


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	games = int(args.get("games", "40"))
	target = float(args.get("target", "0.75"))
	# 11/3 --snap=경로.json —— 원본 QPV 무작위 덱 대신 자동 진행이 실제로 짠 편성을 기준 플레이어로 (일반 등급 삭제 뒤 플레이어가 훨씬 세졌다)
	if args.has("snap"):
		for s in JSON.parse_string(FileAccess.open(str(args.snap), FileAccess.READ).get_as_text()):
			var key := "%d-%d" % [int(s.d), int(s.p)]
			if not snaps.has(key): snaps[key] = []
			snaps[key].append(s.a)
	# --day_target=0.92,0.88,... —— 일차마다 목표 승률
	if args.has("day_target"):
		day_target = Array(str(args.day_target).split(",")).map(func(x): return float(x))
	var out := []
	for d in DB.QUEST_ROSTERS.size():
		var row := []
		for p in 3:
			var q: Dictionary = DB.QUEST_ROSTERS[d][p]
			# --only=2-2,2-3 —— 그 단계만 다시 맞추고 나머지는 지금 편성 그대로 (11/2 자동 진행에서 2-2 가 벽이었다)
			if args.has("only") and not str(args.only).split(",").has("%d-%d" % [d + 1, p + 1]):
				row.append(q.duplicate().merged({"k": 0, "win": float(q.get("par_win", 0.0))}))
				continue
			if not day_target.is_empty():
				target = float(day_target[mini(d, day_target.size() - 1)])
			var tiers := _par_tiers(DB.D.QPV[d][p])
			var best := {}
			# ① 같은 등급 분포에서 플레이어가 target 아래로 이기면 → 위 칸부터 한 칸씩 낮춘다
			# ② 낮춘 칸 하나가 너무 크게 바뀌면(target+0.08 넘게 이기면) → 사기(황건의 광신)를 조금씩 올려 맞춘다. 장비는 쓰지 않는다
			# 0 칸에서 시작 —— 플레이어가 너무 못 이기면 위 칸부터 낮추고(k>0), 너무 잘 이기면 아래 칸부터 한 등급씩 올린다(k<0, 불멸까지)
			var mk := func(k):
				var cs := _build(tiers, q.boss, k)
				return {"name": q.name, "boss": cs[0], "form": q.form, "cards": cs, "k": k, "win": _win(cs, q.form, d, p, 100, []), "morale": 100, "equip": []}
			best = mk.call(0)
			if best.win < target:
				for k in range(1, 37):
					best = mk.call(k)
					if best.win >= target:
						break
			else:
				for k in range(-1, -28, -1):
					var nb: Dictionary = mk.call(k)
					if nb.win < target:
						break
					best = nb
					if nb.win <= target + 0.08:
						break
			if best.win > target + 0.08:
				for mo in [108, 116, 124, 132, 140, 150]:
					var w2 := _win(best.cards, q.form, d, p, mo, [])
					if w2 < target - 0.08:
						break
					best.morale = mo
					best.win = w2
					if w2 <= target + 0.08:
						break
			var pv := 0
			for c in best.cards:
				pv += int(DB.C[c].pv)
			best["pv"] = pv
			print("%d-%d %s · 낮춘 칸 %d · 사기 %d · 장비 %d · 플레이어 승 %.0f%% · PV %d · %s" % [d + 1, p + 1, q.name, best.k, best.morale,
				best.equip.filter(func(x): return x != null).size(), best.win * 100, pv,
				" ".join(best.cards.map(func(c): return DB.C[c].name))])
			row.append(best)
		out.append(row)
	var path: String = str(args.get("out", "user://quest_tuned.json"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("저장: ", ProjectSettings.globalize_path(path))
	get_tree().quit()


## DB.gen_board 와 같은 등급 분포 (높은 등급부터)
func _par_tiers(pv: float) -> Array:
	var mid := func(t): return roundi((DB.TIER[t].lo + DB.TIER[t].hi) / 2.0)
	var tiers := []
	tiers.resize(9)
	tiers.fill(1)
	var spent := 9
	for g in 400:
		var lo := 0
		for i in range(1, 9):
			if tiers[i] < tiers[lo]:
				lo = i
		var t: int = tiers[lo]
		if t >= 7:
			break
		var cost: int = mid.call(t + 1) - mid.call(t)
		if spent + cost > pv:
			break
		tiers[lo] = t + 1
		spent += cost
	tiers.sort()
	tiers.reverse()
	return tiers


## 등급 분포대로 채운다 —— 위에서 k 칸은 한 등급 낮춘다 (9칸을 넘으면 두 번째 바퀴). 우두머리는 늘 맨 위에.
## 같은 등급 칸은 이름 있는 황건 · 도사 장수(같은 인물 한 장) → 모자라면 황건 전용 카드(y<등급><병종>)로. 2등급 아래는 병졸
const FOE_TAGS := [0, 2, 4, 3, 1]      # 창 · 궁 · 술 · 도 · 기 순서로 섞는다

func _build(tiers: Array, boss: String, k: int) -> Array:
	var ts := tiers.duplicate()
	for i in maxi(k, 0):
		var j := i % ts.size()
		ts[j] = maxi(1, ts[j] - 1)
	ts.sort()
	for i in maxi(-k, 0):          # 올리기 —— 가장 낮은 칸부터 (불멸까지)
		var lo := 0
		for j in ts.size():
			if ts[j] < ts[lo]:
				lo = j
		ts[lo] = mini(7, ts[lo] + 1)
	ts.sort()
	ts.reverse()
	var used := {DB.person(boss): true}
	var out := [boss]
	var gi := 0
	var fi := 0
	for i in range(1, ts.size()):
		var t: int = ts[i]
		var pick := ""
		if t >= 3:
			var cand := THEME.filter(func(c): return DB.C[c].tier == t and not used.has(DB.person(c)))
			if not cand.is_empty():
				pick = cand[0]
				used[DB.person(pick)] = true
			else:
				pick = "y%d%d" % [mini(t, 7), FOE_TAGS[fi % FOE_TAGS.size()]]
				fi += 1
		else:
			var pool: Array = GEN[maxi(1, t)]
			pick = pool[gi % pool.size()]
			gi += 1
		out.append(pick)
	return out


func _win(cards: Array, form: String, d: int, p: int, morale: int, equip: Array) -> float:
	var styles := ["물리", "지략", "균형"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + d * 10 + p
	var w := 0.0
	var foe := DB.auto_place(cards, form)
	var sn: Array = snaps.get("%d-%d" % [d, p], [])
	for i in games:
		var me: Dictionary
		if not sn.is_empty():
			me = sn[i % sn.size()]
		else:
			var eb := DB.gen_board(DB.D.QPV[d][p], styles[i % 3], rng)
			var mine := DB.auto_place(eb.cards, eb.form)
			me = {"cards": mine, "form": eb.form, "morale": 100, "equip": [], "tac": Run.recommend_tac(mine)[0]}
		var bt := {"a": me,
			"b": {"cards": foe, "form": form, "morale": morale, "equip": equip, "tac": Run.recommend_tac(foe)[0]},
			"seed": rng.randi() % 1000000, "title": "", "foe": ""}
		var r := Run.simulate(bt, [], Run.policy_for(bt))
		w += 1.0 if r.win else (0.5 if r.draw else 0.0)
	return w / games
