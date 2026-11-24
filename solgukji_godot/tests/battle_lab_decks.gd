extends RefCounted
## 실험실 편성 도구. 온라인 기록은 실제 카드만 복원하며 누락 카드를 임의 대체하지 않는다.
const ARCHIVE := "res://tests/data/battle_lab_online.json"
const ONLINE_DIR := "user://playlog_online"
const GRADES := [8, 7, 6, 99, 5, 4, 3, 2, 1]
const PRESETS := [
	{"name": "혼합 예시 · 신1 불3 초1 기1 전2 희1", "counts": [1, 3, 1, 1, 2, 1, 0, 0, 0]},
	{"name": "혼합 예시 · 신1 불1 초2 기1 전3 희1", "counts": [1, 1, 2, 1, 3, 1, 0, 0, 0]},
	{"name": "혼합 예시 · 불2 초2 기1 전3 희1", "counts": [0, 2, 2, 1, 3, 1, 0, 0, 0]},
	{"name": "혼합 예시 · 초1 기1 전3 희4", "counts": [0, 0, 1, 1, 3, 4, 0, 0, 0]},
	{"name": "혼합 예시 · 전4 희5", "counts": [0, 0, 0, 0, 4, 5, 0, 0, 0]},
]

static func grade(k: String) -> int:
	return 99 if DB.is_kiin(k) else int(DB.C[k].tier)

static func counts_of(deck: Array) -> Array:
	var counts := [0, 0, 0, 0, 0, 0, 0, 0, 0]
	for k in deck:
		var i := GRADES.find(grade(k))
		if i >= 0:
			counts[i] += 1
	return counts

static func summary(deck: Array) -> String:
	var parts := PackedStringArray()
	var counts := counts_of(deck)
	for i in GRADES.size():
		if counts[i] > 0:
			parts.append("%s %d" % ["기인" if GRADES[i] == 99 else DB.TIER[GRADES[i]].n, counts[i]])
	return " · ".join(parts)

static func pv(deck: Array) -> int:
	var total := 0
	for k in deck:
		total += int(DB.C[k].pv)
	return total

static func _shuffle(cards: Array, rng: RandomNumberGenerator) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var previous = cards[i]
		cards[i] = cards[j]
		cards[j] = previous

static func make_mix(counts: Array, rng: RandomNumberGenerator, target_pv := -1) -> Array:
	if counts.size() != GRADES.size():
		return []
	var total := 0
	var pools := []
	for i in GRADES.size():
		if int(counts[i]) < 0:
			return []
		total += int(counts[i])
		var pool := DB.C.keys().filter(func(k): return not DB.is_foe(k) and DB.C[k].kind != "retired" and grade(k) == GRADES[i])
		pool.sort()
		if pool.size() < int(counts[i]):
			return []
		pools.append(pool)
	if total < 1 or total > 9:
		return []
	var best := []
	var best_gap := INF
	for attempt in (48 if target_pv >= 0 else 1):
		var deck := []
		for i in GRADES.size():
			var pool: Array = pools[i].duplicate()
			_shuffle(pool, rng)
			deck.append_array(pool.slice(0, int(counts[i])))
		var gap := absf(pv(deck) - target_pv)
		if gap < best_gap:
			best_gap = gap
			best = deck
		if target_pv < 0 or gap == 0.0:
			break
	return best

static func _card_index() -> Dictionary:
	var index := {}
	for k in DB.C:
		var c: Dictionary = DB.C[k]
		if DB.is_foe(k) or c.kind == "retired":
			continue
		index[JSON.stringify([c.name, int(c.tier), c.tag])] = k
	return index

static func _restore(raw: Dictionary, index: Dictionary) -> Dictionary:
	var cards = raw.get("cards", [])
	if not cards is Array or cards.is_empty() or cards.size() > 9:
		return {}
	var deck := []
	for row in cards:
		if not row is Array or row.size() != 3:
			return {}
		var key := JSON.stringify([str(row[0]), int(row[1]), str(row[2])])
		if not index.has(key):
			return {}
		deck.append(index[key])
	var form := str(raw.get("form", "eorin"))
	var tac := str(raw.get("tac", "균형"))
	return {"deck": deck, "form": form if DB.FORM.has(form) else "eorin",
		"tac": tac if tac in Run.TACS else "균형", "morale": clampi(int(raw.get("morale", 100)), 10, 150),
		"equip": int(raw.get("equip", 0)) > 0, "day": int(raw.get("day", 0)), "origin": str(raw.get("origin", "온라인 기록"))}

static func _append(raw: Dictionary, records: Array, seen: Dictionary, index: Dictionary) -> bool:
	var record := _restore(raw, index)
	if record.is_empty():
		return false
	var signature := JSON.stringify([record.deck, record.form, record.tac, record.morale, record.equip])
	if not seen.has(signature):
		seen[signature] = true
		records.append(record)
	return true

static func load_online(folder := ONLINE_DIR, use_archive := true) -> Dictionary:
	var records := []
	var index := _card_index()
	var seen := {}
	var files := 0
	var skipped := 0
	var dir := DirAccess.open(folder)
	if dir != null:
		var names := dir.get_files()
		names.sort()
		for name_ in names:
			if not name_.ends_with(".jsonl"):
				continue
			var file := FileAccess.open(folder.path_join(name_), FileAccess.READ)
			if file == null:
				continue
			files += 1
			while not file.eof_reached():
				var line := file.get_line().strip_edges()
				if line.is_empty():
					continue
				var parser := JSON.new()
				if parser.parse(line) != OK or not parser.data is Dictionary:
					skipped += 1
					continue
				var event: Dictionary = parser.data
				if event.get("ev") != "battle_start" or event.get("kind") not in ["pvp", "tour"]:
					continue
				for side in ["me", "foe"]:
					if side == "foe" and bool(event.get("foe_hidden", false)):
						continue
					var raw = event.get(side)
					if not raw is Dictionary:
						continue
					var snapshot: Dictionary = raw.duplicate(true)
					var prefix := "foe_" if side == "foe" else ""
					for property in ["form", "tac", "morale", "equip"]:
						snapshot[property] = event.get(prefix + property, 100 if property == "morale" else (0 if property == "equip" else ""))
					snapshot["day"] = event.get("day", 0)
					if not _append(snapshot, records, seen, index):
						skipped += 1
	var archived := false
	if records.is_empty() and use_archive:
		var archive = JSON.parse_string(FileAccess.get_file_as_string(ARCHIVE))
		if archive is Dictionary:
			for raw in archive.get("decks", []):
				if raw is Dictionary:
					_append(raw, records, seen, index)
			archived = not records.is_empty()
	records.sort_custom(func(a, b): return pv(a.deck) > pv(b.deck))
	return {"records": records, "files": files, "skipped": skipped, "archived": archived}

static func match_online(records: Array, rng: RandomNumberGenerator, anchor := -1) -> Array:
	var pairs := []
	for i in records.size():
		if records[i].deck.size() != 9 or (anchor >= 0 and i != anchor):
			continue
		var own: Array = records[i].deck.duplicate()
		own.sort()
		for j in records.size():
			if j == i or records[j].deck.size() != 9 or records[i].deck == records[j].deck:
				continue
			var other: Array = records[j].deck.duplicate()
			other.sort()
			if own == other:
				continue
			var a := pv(records[i].deck)
			var b := pv(records[j].deck)
			if absf(a - b) / maxf(1.0, maxf(a, b)) <= 0.10:
				pairs.append([i, j])
	if pairs.is_empty():
		return []
	return pairs[rng.randi_range(0, pairs.size() - 1)]
