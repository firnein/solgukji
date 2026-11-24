extends RefCounted
## 실제 사건에서 대표 연계 하나를 고른다. 전투 수치나 출처를 새로 추정하지 않는다.
var current := {}
var burning := {}
var pulses := {}
var history: Array = []
var revision := 0
var next_start := -1.0
var fire_started := false
var roster_index := {}
var next_outcome := -1.0

func reset(roster: Array = []) -> void:
	current.clear()
	burning.clear()
	pulses.clear()
	history.clear()
	revision += 1
	next_start = -1.0
	fire_started = false
	roster_index.clear()
	for i in roster.size():
		roster_index[str(roster[i].key)] = i
	next_outcome = -1.0

func active(now: float) -> bool:
	return not current.is_empty() and now < float(current.until)

func pulse(key: String, now: float) -> bool:
	return now < float(pulses.get(key, -1.0))

func _remember(now: float) -> void:
	revision += 1
	history.append({"phase": current.phase, "provider": current.provider, "target": current.target, "time": now})
	if history.size() > 40:
		history.pop_front()
	if str(current.provider) != "":
		pulses[current.provider] = now + 0.55

func _start(kind: String, phase: String, provider: String, target: String, now: float, origin := "") -> void:
	current = {"kind": kind, "phase": phase, "provider": provider, "target": target, "origin": origin,
		"targets": [target], "born": now, "until": now + 2.3}
	next_start = now + 4.0
	_remember(now)

func _burning_now(target: String, event: Dictionary) -> bool:
	if not burning.has(target):
		return false
	var i := int(roster_index.get(target, -1))
	var state: Array = event.get("s", [])
	if i >= 0 and i < state.size() and state[i].size() > 3:
		return "burn" in state[i][3]
	return true

func observe(event: Dictionary, now: float) -> void:
	var fx := str(event.get("fx", ""))
	var target := str(event.get("f", ""))
	if fx == "status" and event.get("st") == "burn" and target != "":
		var spread := bool(event.get("spread", false))
		var provider := str(event.get("contributor", event.get("from", event.get("a", ""))))
		var origin := str(event.get("from", ""))
		burning[target] = {"provider": provider, "time": now}
		if not fire_started or (not active(now) and now >= next_start):
			_start("fire", "spread" if spread else "ignite", provider, target, now, origin)
			fire_started = true
		elif active(now) and current.kind == "fire" and not spread and provider == current.provider and now - float(current.born) <= 0.3:
			# 같은 시작 효과로 여러 부대가 탔다면 그 전열 전체를 같은 연계로 추적한다.
			if not current.targets.has(target):
				current.targets.append(target)
		elif active(now) and current.kind == "fire" and spread and current.targets.has(origin):
			if not current.targets.has(target):
				current.targets.append(target)
			if current.phase != "spread" or current.target != target:
				current.phase = "spread"
				current.provider = provider
				current.origin = origin
				current.target = target
				current.until = minf(float(current.born) + 5.0, maxf(float(current.until), now + 1.4))
				_remember(now)
		return
	if fx in ["rout", "collapse"] and now >= next_outcome and _burning_now(target, event):
		# 실제 이탈 순간에도 불타는 경우만 결과로 연결한다. 화공이 막타였다는 뜻은 아니다.
		_start("fire", "retreat" if fx == "rout" else "collapse", str(burning[target].provider), target, now)
		current.until = now + 1.8
		next_start = now + 2.5
		next_outcome = now + 3.0
		return
	if active(now) or now < next_start:
		return
	if fx in ["inyeon_fin", "inyeon_theme"]:
		_start("fin", "combine", str(event.get("a", "")), target, now)
		current.name = str(event.get("name", "합동 공격"))
		return
	for assist in event.get("assists", []):
		var provider := str(assist.get("from", ""))
		if provider != "" and provider != str(event.get("a", "")) and float(assist.get("n", 0.0)) > 0.0:
			_start("support", "followup", provider, target, now)
			current.attacker = str(event.get("a", ""))
			return
	if fx == "heal" and float(event.get("n", 0.0)) > 0.0 and str(event.get("healer", "")) != "":
		_start("heal", "recover", str(event.healer), target, now)

func accepts_fire(event: Dictionary, now: float) -> bool:
	return active(now) and current.kind == "fire" and current.targets.has(str(event.get("f", "")))

func _name(key: String, squads: Dictionary) -> String:
	var sq: Squad = squads.get(key)
	if sq == null:
		return ""
	return DB.person(sq.cid) if sq.tier > 2 else str(sq.row.name)

func caption(squads: Dictionary) -> String:
	if current.is_empty():
		return ""
	var who := _name(str(current.provider), squads)
	var victim := _name(str(current.target), squads)
	match str(current.phase):
		"ignite": return (who + " · " if who != "" else "") + "불을 붙임"
		"spread": return (who + " · " if who != "" else "") + "불길 확산"
		"retreat": return "불붙은 " + (victim + " 부대 " if victim != "" else "부대 ") + "퇴각"
		"collapse": return "불붙은 " + (victim + " 부대 " if victim != "" else "부대 ") + "붕괴"
		"followup":
			var attacker := _name(str(current.get("attacker", "")), squads)
			return who + " 약화 지원" + (" → " + attacker + " 공격" if attacker != "" else "")
		"recover": return (who + " · " if who != "" else "") + "전열 회복"
		"combine": return (who + " · " if who != "" else "") + str(current.get("name", "합동 공격"))
	return ""
