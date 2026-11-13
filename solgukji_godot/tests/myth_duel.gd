extends Node
## 11/14 신화 한 장 대결 —— 덱 = 신화 1 + 불멸 3 + 전설 2 + 희귀 2. 양쪽 보조 7장이 같고 신화만 다르다 (상대 = 비장 여포 c181)
## 10판 × 자리 바꿔 2번 = 20전, 출력 = 상대 신화에게 이긴 수 (10 = 반반). 결과 docs/신화_보정_1114.md
## 실행: godot --headless --path . res://tests/myth_duel.tscn -- --part=1   (4개 프로세스로 --part=1~4 를 함께 돌리면 빠르다)
## 인자 (-- 뒤): --part=N (1~4) · --only=c186,c188 · --seed=4242 · --games=10 · --vs=c177 (상대 신화, 기본 여포 c181)
##   --adj=c186:1.2,c188:1.3 (data/cards_ext.json card_adjust 값을 이 실행에서만 바꿔 본다 —— c186:st=1.2/tr=1.1/psv=1.5 꼴로 갈래별도)
##   --aura=c193.def:0.1,c198.m.rout:0.3 (data/myth_aura.json 위세 값을 이 실행에서만 —— 점 하나면 ally, 둘이면 그 묶음)


func _ready() -> void:
	var part := 0
	var only: Array = []
	var seed_v := 4242
	var games := 10
	var vs := "c181"
	for s in OS.get_cmdline_user_args():
		if s.begins_with("--part="): part = int(s.substr(7))
		elif s.begins_with("--only="): only = Array(s.substr(7).split(",", false))
		elif s.begins_with("--seed="): seed_v = int(s.substr(7))
		elif s.begins_with("--games="): games = int(s.substr(8))
		elif s.begins_with("--vs="): vs = s.substr(5)
		elif s.begins_with("--adj="):
			for kv in s.substr(6).split(",", false):
				var p: PackedStringArray = kv.split(":")
				if p[1].contains("="):      # c186:st=1.2/tr=1.1/psv=1.5 —— 갈래별 배율
					var d := {}
					for e in p[1].split("/"):
						d[e.get_slice("=", 0)] = float(e.get_slice("=", 1))
					DB.CARD_ADJ[p[0]] = d
				else:
					DB.CARD_ADJ[p[0]] = float(p[1])
			DB.apply_card_adjust()
		elif s.begins_with("--aura="):      # --aura=c193.def:0.1,c193.atk:0.06 —— 아군 위세(data/myth_aura.json ally) 값을 이 실행에서만 바꿔 본다
			for kv in s.substr(7).split(",", false):
				var p: PackedStringArray = kv.split(":")
				var ks: PackedStringArray = p[0].split(".")
				var a: Dictionary = DB.AURA[ks[0]]
				var grp := "ally" if ks.size() == 2 else ks[1]      # c198.m.rout:0.3 —— 특수 효과(m) · foe 도 같은 꼴로
				if not a.has(grp): a[grp] = {}
				a[grp][ks[ks.size() - 1]] = float(p[1])
	var by := {}
	var myth: Array = []
	for k in DB.C:
		var t: int = DB.C[k].tier
		if t == 8 and k != vs: myth.append(k)
		if not by.has(t): by[t] = []
		by[t].append(k)
	if not only.is_empty():
		myth = myth.filter(func(x): return only.has(x))
	if part > 0:
		var sel: Array = []
		for i in myth.size():
			if i % 4 == part - 1: sel.append(myth[i])
		myth = sel
	for m in myth:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		var w := 0.0
		for g in games:
			var s: Array = []
			for p in [[7, 3], [5, 2], [4, 2]]:
				var n := 0
				while n < p[1]:
					var k = by[p[0]][rng.randi() % by[p[0]].size()]
					var pk = DB.person(k)
					if pk == DB.person(vs) or pk == DB.person(m): continue
					if not s.any(func(x): return DB.person(x) == pk):
						s.append(k)
						n += 1
			var a := DB.auto_place([vs] + s, "eorin")
			var b := DB.auto_place([m] + s, "eorin")
			var sd := rng.randi() % 1000000
			var r1 := RtBattle.make(sd).run(a, "eorin", 100, null, b, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var r2 := RtBattle.make(sd).run(b, "eorin", 100, null, a, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			w += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
		print("결과\t%s\t%s\t%s\t%.1f" % [m, DB.C[m]["name"], DB.C[m].tag, 2.0 * games - w])
	get_tree().quit()
