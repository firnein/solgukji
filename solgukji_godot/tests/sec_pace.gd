extends Node
## 11/23 정산 간격 1초 고정(RtBattle.sec_fixed) 전후 —— 실제 덱 모양(초반 · 중반 · 후반 · 신화)에서 판 길이 · 시간 끝 비율
## 실행: godot --headless --path . res://tests/sec_pace.tscn [-- --old]
const SHAPES := {"초반": [4, 4, 3, 3, 3, 3, 3, 3, 3], "중반": [5, 5, 5, 4, 4, 4, 4, 3, 3], "후반": [7, 7, 6, 6, 6, 5, 5, 5, 5], "신화": [8, 7, 7, 7, 6, 5, 5, 5, 5]}
func _ready() -> void:
	for x in OS.get_cmdline_user_args():
		if x == "--old": RtBattle.sec_fixed = false
	var myths: Array = DB.by_tier(8).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k))
	for nm in SHAPES:
		var sh: Array = SHAPES[nm]
		var ln := 0.0; var cap := 0; var n := 24
		for i in n:
			var rng := RandomNumberGenerator.new(); rng.seed = 91000 + i
			var a := _deck(sh, myths, rng); var b := _deck(sh, myths, rng)
			var r: Dictionary = RtBattle.new(91000 + i).run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "eorin"), "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			ln += float(r.len)
			if r.draw: cap += 1
		print("%s 판 길이 %.1f초 · 무승부 %d/%d" % [nm, ln / n, cap, n])
	get_tree().quit()
func _deck(shape: Array, myths: Array, rng: RandomNumberGenerator) -> Array:
	var tags: Array = DB._mix_tags("균형", rng)
	var out := []
	if int(shape[0]) == 8:
		var m: String = myths[rng.randi_range(0, myths.size() - 1)]
		out.append(m)
		tags.erase(DB.C[m].tag)
	for j in range(out.size(), shape.size()):
		out.append(DB._army_pick(int(shape[j]), str(tags[j - (1 if int(shape[0]) == 8 else 0)]) if j < tags.size() + 1 else "", out, rng.randi(), "균형"))
	return out
