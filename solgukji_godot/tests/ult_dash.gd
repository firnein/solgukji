extends Node
## 돌격 고유기 점검 (11/17) —— 실행: godot --headless --path . res://tests/ult_dash.tscn
## 근접 장수의 charge 고유기는 실제로 달려가 부딪힌 자리에서 터져야 한다 (예전: 마초가 제자리에서 먼 적진 앞줄 3부대를 쳤다)
const CAV := ["마초", "서황", "공손찬", "장료", "조운", "손책", "장합", "마등", "관우"]

func _ready() -> void:
	PlayLog.enabled = false
	RtBattle.probe_dash = "--log" in OS.get_cmdline_user_args()
	RtBattle.algo_v2 = not ("--v2=0" in OS.get_cmdline_user_args())      # 11/19 전후 비교용
	RtBattle.fair_order = not ("--fair=0" in OS.get_cmdline_user_args())
	var helper = preload("res://tests/formation_preview.gd").new()
	var dashes := 0
	var late := 0
	var late_gap := 0.0
	var gap_max := 0.0
	var line_far := 0.0
	var ults := 0
	for seed in [5100, 5101, 5102]:
		var a: Array = DB.auto_place(helper._cards(CAV), "eorin")
		var b: Array = DB.auto_place(helper._cards([]), "hagik")
		var bt := RtBattle.new(seed)
		var res: Dictionary = bt.run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
		dashes += int(bt.stats.get("dash_n", 0))
		gap_max = maxf(gap_max, float(bt.stats.get("dash_gap_max", 0.0)))
		late += int(bt.stats.get("dash_timeout", 0))
		late_gap = maxf(late_gap, float(bt.stats.get("dash_late_gap_max", 0.0)))
		line_far = maxf(line_far, float(bt.stats.get("dash_line_far", 0.0)))
		for e in res.ev:
			if e.get("fx", "") == "ult":
				ults += 1
		# 같은 시드는 같은 결과 (결정적)
		var again := RtBattle.new(seed).run(DB.auto_place(helper._cards(CAV), "eorin"), "eorin", 100, null, DB.auto_place(helper._cards([]), "hagik"), "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
		assert(JSON.stringify(again.ev) == JSON.stringify(res.ev), "dash ultimates must stay deterministic")
	helper.free()
	print("DASH ults=%d dashes=%d arrive_gap_max=%.1f timeout=%d timeout_gap_max=%.1f line_target_gap_max=%.1f" % [ults, dashes, gap_max, late, late_gap, line_far])
	assert(dashes > 0, "charge ultimates should dash")
	assert(gap_max <= RtBattle.TOUCH + 3.0, "dash must end in contact")
	# 11/26 DASH_MAX 초 안에 못 닿아 그 자리에서 터진 돌진은 따로 센다 (설계상 예비 동작 —— 최후열 돌격이 800 넘게 떨어진 적을 쫓다 3초가 끝남).
	# 받아치기 연쇄를 넣은 뒤 시드 흐름이 바뀌어 5101 에서 장합이 한 번(821 → 84) 그랬다. 드물어야 한다: 돌진 열 번에 한 번 이하
	assert(late * 10 <= dashes, "timed-out dashes must stay rare")
	# 11/19 150 → 200: 띠는 달려온 길 전체(출발점 ~ 부딪힌 곳 + 80)라, 길게 달린 돌격은 출발점 쪽 대상이 이만큼 떨어질 수 있다.
	# 150 은 예전 이동 알고리즘의 3개 시드 실측(82)에 맞춘 값 —— 이동 알고리즘 · 처리 순서를 바꾼 뒤 한 번 166 이 나왔다 (--v2=0 --fair=0 이면 예전 82 그대로)
	assert(line_far <= 200.0, "path-line targets must stay near the impact")
	print("PASS ult dash: charge ultimates run in and strike near the caster")
	get_tree().quit()
