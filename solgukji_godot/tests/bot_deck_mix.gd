extends Node
## 11/22 봇 덱 등급 섞기 · 인연 점검 —— 실행: godot --headless --path . res://tests/bot_deck_mix.tscn [-- --games=8 --duel=30]
## ① 혼자 하기 흐름(21페이즈, bot_army 와 같은 PV 성장)을 예전(평평 · 무작위) / 새(계단 · 인연) 두 방식으로 돌려 일차별 봇 군세의 등급 분포 · 인연 수 · 쓴 PV
## ② 같은 PV 에서 새 덱 대 예전 덱 맞대결 승률 (자리 바꿔 두 번, 장비 없음 · 작전 smart) —— 50% 근처면 힘은 그대로

const TN := {1: "기본", 3: "고급", 4: "희귀", 5: "전설", 6: "초월", 7: "불멸", 8: "신화"}


var yeon_new := true      # --yeon=0 → 새 덱에서 인연 고려만 끈다 (등급 계단만의 효과)
var pvs := [60, 150, 300, 450, 600, 750, 900, 1100]


func _mode(on: bool) -> void:
	DB.bot_shape = on
	DB.bot_yeon = on and yeon_new


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "8"))
	var duel := int(args.get("duel", "30"))
	DB.bot_myth_extra = int(args.get("myth", str(DB.bot_myth_extra)))
	DB.bot_imm_extra = int(args.get("imm", str(DB.bot_imm_extra)))
	yeon_new = args.get("yeon", "1") != "0"
	if args.has("pvs"):
		pvs = Array(str(args.pvs).split(",")).map(func(x): return int(x))
	if args.get("flow", "1") == "0":
		games = 0
	for on in ([false, true] if games > 0 else []):
		_mode(on)
		_flow(games, "새(계단·인연)" if on else "예전(평평)")
	_mode(true)
	if duel > 0:
		_duel(duel)
	get_tree().quit()


func _flow(games: int, label: String) -> void:
	var st := {}      # day -> {tiers: {t: n}, decks, yeon, pv, all6}
	var step := 0
	for g in games:
		var r := Run.new()
		r.new_game(500 + g)
		for p in 21:
			r.day = p / 3
			r.phase = p % 3
			var d: int = r.day
			if not st.has(d):
				st[d] = {"tiers": {}, "decks": 0, "yeon": 0, "yeon3": 0, "pv": 0.0, "flat6": 0}
			for b in r.bots:
				var s := Run.bot_side_of(b, int(r.rng.seed), p)
				var army: Array = b.army
				var e: Dictionary = st[d]
				e.decks += 1
				var six := 0
				for k in army:
					var t := int(DB.C[k].tier)
					e.tiers[t] = int(e.tiers.get(t, 0)) + 1
					e.pv += float(DB.C[k].pv)
					if t == 6:
						six += 1
				if six == 9:
					e.flat6 += 1
				var y := DB.deck_yeon(s.cards)
				e.yeon += y.size()
				for nm in y:
					if int(y[nm]) >= 3:
						e.yeon3 += 1
			for b in r.bots:
				b.pv += Run.bot_pv_gain(r.day, r.phase) * b.skill * 1.0
				if step % 5 == 0:
					b.pv *= 0.94
				step += 1
	print("── %s %d판 ──" % [label, games])
	for d in st:
		var e: Dictionary = st[d]
		var n := float(e.decks)
		var parts := []
		for t in [8, 7, 6, 5, 4, 3, 1]:
			if e.tiers.has(t):
				parts.append("%s %.1f" % [TN[t], float(e.tiers[t]) / n])
		print("%d일차  덱당 %s | 인연 %.2f (3명+ %.2f) | 카드 PV 합 %.0f | 초월 9장 덱 %d/%d" % [
			d + 1, " · ".join(parts), e.yeon / n, e.yeon3 / n, e.pv / n, e.flat6, e.decks])


func _duel(games: int) -> void:
	var styles := ["물리", "지략", "균형"]
	print("── 같은 PV 맞대결: 새 덱 승률 (자리 바꿔 %d×2판 · 불멸 웃돈 %d · 신화 웃돈 %d · 인연 %s) ──" % [games, DB.bot_imm_extra, DB.bot_myth_extra, "켬" if yeon_new else "끔"])
	for pv in pvs:
		var rng := RandomNumberGenerator.new()
		rng.seed = 9000 + pv
		var w := 0.0
		var spent := [0.0, 0.0]
		var tiers_new := ""
		for g in games:
			var st: String = styles[rng.randi() % 3]
			var st2: String = styles[rng.randi() % 3]
			var r1 := RandomNumberGenerator.new()
			r1.seed = rng.randi()
			_mode(true)
			var nb := DB.gen_board(pv, st, r1)
			tiers_new = str(DB.board_tiers(pv))
			_mode(false)
			var ob := DB.gen_board(pv, st2, r1)
			_mode(true)
			for k in nb.cards:
				spent[0] += DB.C[k].pv
			for k in ob.cards:
				spent[1] += DB.C[k].pv
			var na := DB.auto_place(nb.cards, nb.form)
			var oa := DB.auto_place(ob.cards, ob.form)
			var sd := rng.randi() % 1000000
			var a := RtBattle.make(sd).run(na, nb.form, 100, null, oa, ob.form, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var b := RtBattle.make(sd).run(oa, ob.form, 100, null, na, nb.form, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			w += (1.0 if a.win else (0.5 if a.draw else 0.0)) + (1.0 if (not b.win and not b.draw) else (0.5 if b.draw else 0.0))
		print("PV %4d: 새 덱 승률 %3.0f%% | 카드 PV 새 %.0f / 예전 %.0f | 새 등급 %s | 예전 %s" % [
			pv, w / (games * 2.0) * 100, spent[0] / games, spent[1] / games, tiers_new, str(DB.board_tiers_flat(pv))])
