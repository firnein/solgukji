extends Node
## 인연 합동 멘트 서사 점검 (11/12) —— 실행: godot --headless --path . res://tests/inyeon_lines.tscn
## (a) data/inyeon_lines.json 의 pairs ("합류자>대표") —— 두 사람이 어떤 인연에서 함께 든 사이 · 한 줄 18자 이하 · 이모지 · 꾸밈 없음 · 같은 짝 안에서 같은 말 없음
## (b) by_inyeon(인연 이야기 멘트) —— 인연 이름이 inyeon.json 에 있음 · 18자 이하 · 겹침 없음 · 모든 인연에 이야기 멘트나 짝 멘트가 하나 이상
## (c) 인연마다 짝 멘트 수 · 이야기 멘트 수 출력 (짝 3줄 이상 또는 이야기 2줄 이상)
## (d) 고르는 규칙 BattleView.yeon_choose —— 짝 멘트가 있으면 늘(확률 1) 짝 · 없으면 인연 이야기 · 둘 다 없으면 말투 풀 · 같은 시드 같은 결과 · 합동 안에서 겹침 없음 · 합류자 둘이 따로

const MAX_LEN := 18
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		print("  실패: ", msg)


func _clean(s: String) -> bool:      # 한글 · 공백 · 쉼표 마침표 느낌표 물음표 말고는 안 쓴다 (이모지 · 꾸밈 방지)
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 0xAC00 and c <= 0xD7A3) or " ,.!?".contains(String.chr(c))):
			return false
	return true


func _ready() -> void:
	var f := FileAccess.open("res://data/inyeon_lines.json", FileAccess.READ)
	var tbl = JSON.parse_string(f.get_as_text())
	_ok(tbl is Dictionary, "inyeon_lines.json 읽기")
	var inv: Dictionary = JSON.parse_string(FileAccess.open("res://data/inyeon.json", FileAccess.READ).get_as_text()).list
	var people := {}
	for n in inv:
		for p in inv[n]:
			people[p] = true
	_ok(tbl.get("bold", []).size() > 0 and tbl.get("polite", []).size() > 0, "옛 말투 풀(bold · polite) 유지")

	# (a) 짝 멘트
	var pairs: Dictionary = tbl.get("pairs", {})
	var n_pair_lines := 0
	var longest := 0
	var long14 := 0
	for k in pairs:
		var ab: PackedStringArray = str(k).split(">")
		_ok(ab.size() == 2 and ab[0] != "" and ab[1] != "" and ab[0] != ab[1], "짝 키 모양 '%s'" % k)
		if ab.size() != 2:
			continue
		_ok(people.has(ab[0]) and people.has(ab[1]), "짝 키 '%s' —— 인연에 없는 인물" % k)
		var together := false
		for n in inv:
			if inv[n].has(ab[0]) and inv[n].has(ab[1]):
				together = true
				break
		_ok(together, "짝 '%s' —— 함께 든 인연이 없다(합류할 수 없는 짝)" % k)
		var lines: Array = pairs[k]
		_ok(lines.size() >= 1 and lines.size() <= 3, "짝 '%s' 멘트 수 %d (1~3)" % [k, lines.size()])
		var seen := {}
		for s in lines:
			var t := str(s)
			n_pair_lines += 1
			longest = maxi(longest, t.length())
			if t.length() > 14:
				long14 += 1
			_ok(t != "" and t.length() <= MAX_LEN, "'%s' 의 '%s' %d자" % [k, t, t.length()])
			_ok(_clean(t), "'%s' 의 '%s' —— 한글 · 쉼표 · 마침표 · 느낌표 · 물음표 밖의 글자" % [k, t])
			_ok(not seen.has(t), "'%s' 에서 같은 말 겹침 '%s'" % [k, t])
			seen[t] = true

	# (b) 인연 이야기 멘트
	var story: Dictionary = tbl.get("by_inyeon", {})
	var n_story_lines := 0
	for n in story:
		_ok(inv.has(n), "by_inyeon '%s' —— inyeon.json 에 없는 인연" % n)
		var seen := {}
		_ok(story[n].size() >= 1 and story[n].size() <= 4, "이야기 '%s' 멘트 수 %d (1~4)" % [n, story[n].size()])
		for s in story[n]:
			var t := str(s)
			n_story_lines += 1
			longest = maxi(longest, t.length())
			_ok(t != "" and t.length() <= MAX_LEN, "이야기 '%s' 의 '%s' %d자" % [n, t, t.length()])
			_ok(_clean(t), "이야기 '%s' 의 '%s' —— 허용되지 않는 글자" % [n, t])
			_ok(not seen.has(t), "이야기 '%s' 에서 같은 말 겹침 '%s'" % [n, t])
			seen[t] = true

	# (c) 인연별 개수
	print("(a)(b) 짝 키 %d · 짝 멘트 %d줄 · 이야기 멘트 %d줄 (%d개 인연) · 가장 긴 글 %d자 · 14자 넘는 짝 멘트 %d줄" % [pairs.size(), n_pair_lines, n_story_lines, story.size(), longest, long14])
	var rows := []
	for n in inv:
		var pk := 0
		var pl := 0
		var ms: Array = inv[n]
		for a in ms:
			for b in ms:
				if a != b and pairs.has("%s>%s" % [a, b]):
					pk += 1
					pl += pairs["%s>%s" % [a, b]].size()
		var sl: int = story.get(n, []).size()
		_ok(pk + sl > 0, "인연 '%s' —— 짝 멘트도 이야기 멘트도 없다" % n)
		_ok(pk >= 3 or sl >= 2, "인연 '%s' —— 짝 키 %d(3↑) · 이야기 %d(2↑) 모자람" % [n, pk, sl])
		rows.append([n, pk, pl, sl])
	print("(c) 인연 · 짝 키 · 짝 줄 · 이야기 줄")
	for r in rows:
		print("    %s  짝 %d키 %d줄 · 이야기 %d줄" % [r[0], r[1], r[2], r[3]])

	# (d) 고르는 규칙
	var tt := {"bold": ["호방1", "호방2"], "polite": ["정중1"], "by_inyeon": {"호뢰관": ["호뢰관 이야기"]},
		"pairs": {"장비>관우": ["둘째 형님", "형님 앞은"], "관우>유비": ["형님 청룡도"]}}
	var all_pair := true
	for sd in 40:
		var r: Array = BattleView.yeon_choose(tt, sd, "A1", "A2", "장비", "관우", "호뢰관", 0, [])
		if r[2] != "pair" or not tt.pairs["장비>관우"].has(r[0]):
			all_pair = false
	_ok(all_pair, "짝 멘트가 있으면 시드와 상관없이 늘 짝 멘트(확률 1)")
	var r1: Array = BattleView.yeon_choose(tt, 5, "A1", "A2", "장비", "관우", "호뢰관", 0, [])
	var r2: Array = BattleView.yeon_choose(tt, 5, "A1", "A2", "장비", "관우", "호뢰관", 0, [])
	_ok(r1 == r2, "같은 시드 · 대표 · 합류자는 같은 말")
	var seen_both := {}
	for sd in 40:
		seen_both[BattleView.yeon_choose(tt, sd, "A1", "A2", "장비", "관우", "호뢰관", 0, [])[0]] = true
	_ok(seen_both.size() == 2, "시드가 바뀌면 후보 둘이 다 나온다 (%d)" % seen_both.size())
	var st: Array = BattleView.yeon_choose(tt, 3, "A1", "A2", "여포", "유비", "호뢰관", 0, [])
	_ok(st[2] == "story" and st[0] == "호뢰관 이야기", "짝 멘트가 없으면 인연 이야기 멘트")
	var tn: Array = BattleView.yeon_choose(tt, 3, "A1", "A2", "여포", "유비", "없는 인연", 1, [])
	_ok(tn[2] == "tone" and tn[0] == "정중1" and tn[1] == 1, "둘 다 없으면 말투 풀(정중)")
	var tb: Array = BattleView.yeon_choose(tt, 3, "A1", "A2", "", "", "", 0, [])
	_ok(tb[2] == "tone" and ["호방1", "호방2"].has(tb[0]), "인물을 모르면 말투 풀(호방)")
	# 합류자 둘 —— 각자 자기 짝으로, 서로 겹치지 않게 (대표 유비 · 합류 관우 · 장비)
	var used := []
	var ja: Array = BattleView.yeon_choose(tt, 9, "A1", "A2", "관우", "유비", "호뢰관", 0, used)
	used.append(ja[0])
	var jb: Array = BattleView.yeon_choose(tt, 9, "A1", "A3", "장비", "유비", "호뢰관", 0, used)
	_ok(ja[2] == "pair" and ja[0] == "형님 청룡도", "합류자 A 는 자기 짝 멘트")
	_ok(jb[2] == "story" and jb[0] == "호뢰관 이야기", "합류자 B 는 짝이 없어 이야기 멘트")
	# 짝 멘트가 이미 다 쓰였으면 다음 단계로
	var used2 := ["둘째 형님", "형님 앞은"]
	var jc: Array = BattleView.yeon_choose(tt, 1, "A1", "A2", "장비", "관우", "호뢰관", 0, used2)
	_ok(jc[2] == "story" and not used2.has(jc[0]), "짝 멘트가 다 쓰였으면 인연 이야기 멘트로 (겹침 없음)")
	# 실제 표로 —— 모든 짝이 짝 멘트로 나온다
	var real_ok := true
	for k in pairs:
		var ab: PackedStringArray = str(k).split(">")
		for sd in 3:
			var rr: Array = BattleView.yeon_choose(tbl, sd, "L", "J", ab[0], ab[1], "", 0, [])
			if rr[2] != "pair" or not pairs[k].has(rr[0]):
				real_ok = false
	_ok(real_ok, "실제 표의 모든 짝이 짝 멘트로 나온다")

	print("(d) 고르는 규칙 점검 끝")
	print("--- 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
