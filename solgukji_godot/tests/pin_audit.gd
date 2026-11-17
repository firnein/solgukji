extends Node
## 11/17 사용자 「도적이 돌아와 붙으면 책사가 1,000 딜도 못한다」 —— 책사가 근접 적에게 묶인(pinned) 동안 · 풀린 동안의 피해와 시간을 나눠 잰다.
## 실행: godot --headless --path . res://tests/pin_audit.tscn [-- --trials=8]
## 묶임 상성(cards_ext engage.pin_atk 0.35 · pin_taken 1.8)은 바꾸지 않는다 —— 재기만
const Audit = preload("res://tests/motion5_role_audit.gd")

class PinProbe extends Audit.Probe:
	var pin := {}      # key -> {t_pin, t_free, dmg_pin, dmg_free, taken_pin, taken_free}
	func _row2(k: String) -> Dictionary:
		if not pin.has(k):
			pin[k] = {"t_pin": 0.0, "t_free": 0.0, "dmg_pin": 0.0, "dmg_free": 0.0, "taken_pin": 0.0, "taken_free": 0.0}
		return pin[k]
	func _fire_winds() -> void:      # 틱마다 한 번 —— 묶인 시간
		super._fire_winds()
		for u in units:
			if u.alive and u.c.tag == "책사":
				var r := _row2(u.key)
				if _pinned(u): r.t_pin += TICK
				else: r.t_free += TICK
	func L(cls: String, message: String, extra: Dictionary = {}) -> void:
		super.L(cls, message, extra)
		if not extra.get("fx", "") in ["phys", "int"]:
			return
		var a: Unit = null
		var d: Unit = null
		for u in units:
			if u.key == extra.get("a", ""): a = u
			if u.key == extra.get("f", ""): d = u
		if a == null or d == null or a.camp == d.camp:
			return
		var n := float(extra.get("n", 0.0))
		if a.c.tag == "책사":
			var r := _row2(a.key)
			if _pinned(a): r.dmg_pin += n
			else: r.dmg_free += n
		if d.c.tag == "책사":
			var r2 := _row2(d.key)
			if _pinned(d): r2.taken_pin += n
			else: r2.taken_free += n

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "1"
	var trials := int(args.get("trials", "8"))
	var pool := DB.by_tier(5).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k))
	var ce := pool.filter(func(k): return DB.C[k].tag == "책사")
	var rogues := pool.filter(func(k): return DB.C[k].tag == "도적")
	var others := pool.filter(func(k): return not ["책사", "도적"].has(DB.C[k].tag))
	var helper := Audit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 93100
	var tot := {"t_pin": 0.0, "t_free": 0.0, "dmg_pin": 0.0, "dmg_free": 0.0, "taken_pin": 0.0, "taken_free": 0.0}
	var runs := 0
	for trial in trials:
		var deck: Array = helper.pick_unique(others, 7, rng) + helper.pick_unique(ce, 2, rng)
		var enemy: Array = helper.pick_unique(others.filter(func(k): return not deck.has(k)), 7, rng) + helper.pick_unique(rogues, 2, rng)
		for mirror in [false, true]:
			var bt := PinProbe.new(93100 + trial)
			var da := DB.auto_place(enemy if mirror else deck, "eorin")
			var db := DB.auto_place(deck if mirror else enemy, "eorin")
			bt.run(da, "eorin", 100, null, db, "eorin", 100, null, "", "", [], {"A": "auto", "B": "auto"})
			runs += 1
			for k in bt.pin:
				for f in tot:
					tot[f] += float(bt.pin[k][f])
	helper.free()
	var n := float(runs * 2)
	print("PIN runs=%d 책사(판당 2명) —— 묶인 시간 %.1f초 · 풀린 시간 %.1f초 (장수 1명 평균)" % [runs, tot.t_pin / n, tot.t_free / n])
	print("PIN 준 피해: 묶임 %d (초당 %.0f) · 풀림 %d (초당 %.0f)" % [roundi(tot.dmg_pin / n), tot.dmg_pin / maxf(0.01, tot.t_pin), roundi(tot.dmg_free / n), tot.dmg_free / maxf(0.01, tot.t_free)])
	print("PIN 받은 피해: 묶임 %d (초당 %.0f) · 풀림 %d (초당 %.0f)" % [roundi(tot.taken_pin / n), tot.taken_pin / maxf(0.01, tot.t_pin), roundi(tot.taken_free / n), tot.taken_free / maxf(0.01, tot.t_free)])
	get_tree().quit()
