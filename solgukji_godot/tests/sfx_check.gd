extends Node
## 11/21 사운드 폴리싱 점검 —— 효과음 이름마다 파일이 실제로 실렸는지, 덕킹이 내려갔다가 돌아오는지 숫자로 찍는다
## godot --headless --path . res://tests/sfx_check.tscn

func _ready() -> void:
	var miss := []
	for n in Sfx.SFX_NAMES:
		if not Sfx._s.has(n):
			miss.append(n)
		elif not Sfx.TUNE.has(n):
			print("크기 미지정 ", n)
	print("효과음 ", Sfx.SFX_NAMES.size(), "종 · 빠진 것 ", miss)
	for c in Sfx.SIG_CUES:      # 개성 말풍선 소리 —— 고른 소리가 실제로 있어야 한다
		if not Sfx._s.has(c[1]):
			miss.append("sig:" + str(c[1]))
	Sfx.sig_cue("도발 —— 주변 적이 나를 친다")
	var t0: float = Sfx._sig_last.get("horn", -1.0)
	Sfx.sig_cue("일갈 —— 또")      # 간격 안이라 건너뛴다
	print("개성 소리 간격 ", "지킴" if Sfx._sig_last.get("horn", -1.0) == t0 and t0 > 0.0 else "안 지킴", " · 덕킹 안 함 ", not Sfx.is_processing())
	var mi := AudioServer.get_bus_index("Music")
	var base := AudioServer.get_bus_volume_db(mi)
	Sfx.play("ult")
	var low := 0.0
	for i in 60:      # 1초
		await get_tree().process_frame
		low = minf(low, AudioServer.get_bus_volume_db(mi) - base)
	await get_tree().create_timer(2.6).timeout
	var back := AudioServer.get_bus_volume_db(mi) - base
	print("덕킹 최저 %.1f dB · 2.6초 뒤 %.2f dB · 처리 %s" % [low, back, Sfx.is_processing()])
	print("결과 ", "통과" if miss.is_empty() and low < -5.0 and absf(back) < 0.05 and not Sfx.is_processing() else "실패")
	get_tree().quit()
