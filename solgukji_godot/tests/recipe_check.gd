extends Node
## 조합식 점검 (11/5 사용자: 조합식이 올바른지, 왜 고급 도적만 많은지)
## 실행: godot --headless --path . res://tests/recipe_check.tscn
## 출력: 등급 × 병종 장수 수 · 잘못된 조합식(없는 재료 · 같거나 높은 등급 재료 · 은퇴/적 전용 재료 · 재료 없음 · 순환) ·
##       재료로 쓰이는 횟수 · 어디에도 안 쓰이는 카드 · 얻을 길이 없는 카드

func _ready() -> void:
	var tags: Array = DB.D.TAGORDER
	var play := DB.C.keys().filter(func(k): return not DB.is_foe(k) and DB.C[k].kind != "retired")
	print("== 등급 × 병종 (플레이어 카드, 기인 제외) ==")
	print("등급     " + "  ".join(tags.map(func(t): return "%s" % t)) + "   합")
	for t in range(1, 9):
		var row := []
		var tot := 0
		for tg in tags:
			var n := play.filter(func(k): return DB.C[k].tier == t and DB.C[k].tag == tg and not DB.is_kiin(k)).size()
			row.append("%4d" % n)
			tot += n
		if tot > 0:
			print("%d %s  %s   %d" % [t, DB.TIER[t].n, "  ".join(row), tot])
	print("\n== 잘못된 조합식 ==")
	var bad := 0
	var used := {}
	var used_by := {}
	for out in DB.RECOF:
		var mats: Array = DB.RECOF[out]
		if not DB.C.has(out):
			print("  [결과 없음] ", out); bad += 1; continue
		var c: Dictionary = DB.C[out]
		if mats.is_empty():
			print("  [재료 없음] %s (%d)" % [c.name, c.tier]); bad += 1
		for m in mats:
			var mk := str(m)
			if not DB.C.has(mk):
				if not DB.IT.has(mk):
					print("  [없는 재료] %s ← %s" % [c.name, mk]); bad += 1
				continue
			var mc: Dictionary = DB.C[mk]
			used[mk] = int(used.get(mk, 0)) + 1
			if not used_by.has(mk): used_by[mk] = []
			used_by[mk].append(out)
			if mc.tier >= c.tier:
				print("  [등급 역전] %s(%d %s) ← %s(%d %s)" % [c.name, c.tier, c.tag, mc.name, mc.tier, mc.tag]); bad += 1
			if mc.kind == "retired":
				print("  [은퇴 재료] %s ← %s" % [c.name, mc.name]); bad += 1
			if DB.is_foe(mk):
				print("  [적 전용 재료] %s ← %s" % [c.name, mc.name]); bad += 1
			if mk == out:
				print("  [자기 자신] %s" % c.name); bad += 1
	print("  → %d건" % bad)
	print("\n== 등급별 조합 재료 구성 (결과 등급 ← 재료 병종 분포 · 재료 등급) ==")
	for t in range(2, 9):
		var tagc := {}
		var tierc := {}
		var outs := 0
		var nmat := []
		for out in DB.RECOF:
			if not DB.C.has(out) or DB.C[out].tier != t or DB.is_foe(out): continue
			outs += 1
			nmat.append(DB.RECOF[out].size())
			for m in DB.RECOF[out]:
				var mk := str(m)
				if not DB.C.has(mk): continue
				tagc[DB.C[mk].tag] = int(tagc.get(DB.C[mk].tag, 0)) + 1
				tierc[DB.C[mk].tier] = int(tierc.get(DB.C[mk].tier, 0)) + 1
		if outs == 0: continue
		print("%d %s 조합 %d개 · 재료 수 %s" % [t, DB.TIER[t].n, outs, str(_hist(nmat))])
		print("    재료 등급 ", tierc, "   재료 병종 ", tagc)
	print("\n== 재료로 많이 쓰이는 카드 (상위 25) ==")
	var ks := used.keys()
	ks.sort_custom(func(a, b): return used[a] > used[b])
	for k in ks.slice(0, 25):
		print("  %-8s %d %s  %d번  ← %s" % [DB.C[k].name, DB.C[k].tier, DB.C[k].tag, used[k],
			", ".join(used_by[k].slice(0, 6).map(func(o): return DB.C[o].name))])
	print("\n== 등급 3(고급) 카드: 병종별 수 · 재료로 쓰이는 총 횟수 ==")
	for tg in tags:
		var cs := play.filter(func(k): return DB.C[k].tier == 3 and DB.C[k].tag == tg and not DB.is_kiin(k))
		var u := 0
		for k in cs: u += int(used.get(k, 0))
		print("  %s %d장 · 재료 %d번 · 한 장 평균 %.1f" % [tg, cs.size(), u, float(u) / maxf(1, cs.size())])
	print("\n== 어디에도 재료로 안 쓰이는 카드 (신화 아래) ==")
	for t in range(1, 8):
		var dead := play.filter(func(k): return DB.C[k].tier == t and not used.has(k) and not DB.is_kiin(k))
		if not dead.is_empty():
			print("  %d %s: %s" % [t, DB.TIER[t].n, ", ".join(dead.map(func(k): return "%s(%s)" % [DB.C[k].name, DB.C[k].tag]))])
	print("\n== 얻을 길이 없는 카드 (조합식 없고, 무상 지급 등급 %d 초과) ==" % Run.FREE_TIER_CAP)
	for k in play:
		if DB.C[k].tier > Run.FREE_TIER_CAP and not DB.RECOF.has(k) and not DB.is_kiin(k):
			print("  ", DB.C[k].name, " ", DB.C[k].tier, " ", DB.C[k].tag)
	print("\n== 순환 조합 ==")
	for out in DB.RECOF:
		if _cyc(out, out, {}): print("  순환: ", DB.C[out].name if DB.C.has(out) else out)
	get_tree().quit()


func _hist(a: Array) -> Dictionary:
	var h := {}
	for x in a: h[x] = int(h.get(x, 0)) + 1
	return h


func _cyc(root: String, k: String, seen: Dictionary) -> bool:
	for m in DB.RECOF.get(k, []):
		var mk := str(m)
		if mk == root: return true
		if seen.has(mk): continue
		seen[mk] = true
		if _cyc(root, mk, seen): return true
	return false
