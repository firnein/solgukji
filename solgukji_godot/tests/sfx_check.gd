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
