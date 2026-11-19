extends Node
## 11/19 조합 미리 보기 · 추천 이유 점검 —— 실행: godot --headless --path . res://tests/forge_preview.tscn [-- --runs=4]
##   ① forge_preview / goal_reason 은 Run 을 바꾸지 않는다 (to_dict 같음)
##   ② 미리 보기의 '출전 소모'가 실제 forge() 뒤 편성판에서 빠진 카드와 같다 (자동 진행 중 지금 되는 조합마다)
##   ③ 손패 여분으로 되는 조합은 출전 소모를 띄우지 않는다
##   ④ 끊긴다고 한 인연 · 역할이 실제 forge() 뒤 편성판에서 없어졌다

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var runs := int(args.get("runs", "4"))
	var fails := 0
	var checked := 0
	var with_loss := 0
	var reasons := {}
	var roles := {"치료": 0, "깎기": 0}
	for k in DB.C:
		for r in Run.card_roles(k):
			roles[r] += 1
	for n in runs:
		var r := Run.new()
		r.new_game(700 + n)
		var guard := 0
		while r.over == null and guard < 60:
			guard += 1
			for rec in DB.D.RECDEF:
				var out: String = rec[0]
				if not r.can_forge(out):
					continue
				var before := JSON.stringify(r.to_dict())
				var pv := r.forge_preview(out)
				var why := r.goal_reason(out)
				if JSON.stringify(r.to_dict()) != before:
					print("FAIL 미리 보기가 Run 을 바꿨다 ", out)
					fails += 1
				reasons[why] = int(reasons.get(why, 0)) + 1
				var trial := Run.new()
				trial.from_dict(JSON.parse_string(JSON.stringify(r.to_dict(), "", false, true)))
				var b0: Array = trial.board.duplicate()
				var links0 := {}
				for l in DB.inyeon_links(b0.filter(func(k): return k != null)):
					links0[l.n] = true
				trial.forge(out)
				var lost := []
				for i in 9:
					if b0[i] != null and trial.board[i] == null:
						lost.append(b0[i])
				lost.sort()
				var said: Array = pv.board_lost.duplicate()
				said.sort()
				if lost != said:
					print("FAIL 출전 소모 불일치 %s: 미리 %s / 실제 %s" % [out, said, lost])
					fails += 1
				var links1 := {}
				for l in DB.inyeon_links(trial.board.filter(func(k): return k != null)):
					links1[l.n] = true
				for nm in pv.bonds_lost:
					if links1.has(nm) or not links0.has(nm):
						print("FAIL 인연 끊김 오보 ", out, " ", nm)
						fails += 1
				var roles1 := Run.deck_roles(trial.board)
				for rl in pv.roles_lost:
					if roles1.has(rl):
						print("FAIL 역할 없어짐 오보 ", out, " ", rl)
						fails += 1
				checked += 1
				if not said.is_empty():
					with_loss += 1
			r.dev_autoplay()
	print("ROLES ", roles, "  REASONS ", reasons)
	if fails == 0 and checked > 0:
		print("PASS forge preview: %d forges checked (%d use deployed cards) · no mutation · board/bond/role match" % [checked, with_loss])
	else:
		print("FAIL forge preview: fails=%d checked=%d" % [fails, checked])
	get_tree().quit(1 if fails > 0 or checked == 0 else 0)
