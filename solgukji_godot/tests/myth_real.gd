extends Node
## 실행: godot --headless --path . res://tests/myth_real.tscn [-- --n=40] —— 11/23 사용자: 같은 등급 9장 · 무작위 불멸 8장 금지, 실제 덱 모양으로
## 신화별 승률 —— 온라인 플레이 기록의 실제 후반 덱 모양 (11/9 · 11/11 기록):
##   A 5~6일차 토벌 [신화 1 · 불멸 3 · 초월 1 · 전설 4]   B 6일차 대회 [신화 1 · 불멸 5 · 초월 1 · 전설 2]
## 신화를 먼저 넣고 나머지는 봇 덱 고르기(_army_pick: 인연 맞춤 · 병종 섞기)로. 상대는 같은 모양에 다른 무작위 신화. 진영 바꿔 두 번
const SHAPES := [[8, 7, 7, 7, 6, 5, 5, 5, 5], [8, 7, 7, 7, 7, 7, 6, 5, 5]]
var myths: Array

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var n := int(a[0].trim_prefix("--n=")) if a.size() > 0 else 30
	myths = DB.by_tier(8).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k))
	var rows := []
	for m in myths:
		var w := [0.0, 0.0]
		var cnt := [0, 0]
		var yeon := 0.0
		var st := [0.0, 0.0, 0.0, 0.0]
		for i in n:
			var rng := RandomNumberGenerator.new()
			rng.seed = 71000 + i
			var sh := i % 2
			var fm: String = myths[rng.randi_range(0, myths.size() - 1)]
			while DB.person(fm) == DB.person(m):
				fm = myths[rng.randi_range(0, myths.size() - 1)]
			var foe := _deck(fm, SHAPES[sh], rng)
			var mine := _deck(m, SHAPES[sh], rng)
			yeon += DB.deck_yeon(mine).size()
			for side in 2:
				var bt := RtBattle.new(71000 + i * 2 + side)
				var r: Dictionary
				if side == 0:
					r = bt.run(DB.auto_place(mine, "eorin"), "eorin", 100, null, DB.auto_place(foe, "eorin"), "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
				else:
					r = bt.run(DB.auto_place(foe, "eorin"), "eorin", 100, null, DB.auto_place(mine, "eorin"), "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
				var me := "A" if side == 0 else "B"
				w[sh] += 0.5 if r.draw else (1.0 if bool(r.win) == (side == 0) else 0.0)
				cnt[sh] += 1
				for u in bt.units:
					if u.c.id == m and u.camp == me:
						st[0] += u.dmg; st[1] += u.mdmg; st[2] += u.ult_n; st[3] += 1.0 if u.alive else 0.0
		var tot: float = cnt[0] + cnt[1]
		rows.append([m, 100.0 * (w[0] + w[1]) / tot, 100.0 * w[0] / cnt[0], 100.0 * w[1] / cnt[1], st[0] / tot, st[1] / tot, st[2] / tot, 100.0 * st[3] / tot, yeon / n, tot])
		print("… %s %.0f%%" % [DB.C[m].name, rows[-1][1]])
	rows.sort_custom(func(x, y): return x[1] > y[1])
	for i in rows.size():
		var r = rows[i]
		print("%2d %s %s(%s) 승률 %.0f%% (토벌형 %.0f · 대회형 %.0f) · 피해 %d · 사기 %d · 고유기 %.2f · 생존 %d%% · 인연 %.1f (%d판)" % [i + 1, r[0], DB.C[r[0]].name, DB.C[r[0]].tag, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]])
	get_tree().quit()

func _deck(m: String, shape: Array, rng: RandomNumberGenerator) -> Array:
	var tags: Array = DB._mix_tags("균형", rng)
	tags.erase(DB.C[m].tag)
	var out := [m]
	for j in range(1, shape.size()):
		out.append(DB._army_pick(int(shape[j]), str(tags[j - 1]) if j - 1 < tags.size() else "", out, rng.randi(), "균형"))
	return out
