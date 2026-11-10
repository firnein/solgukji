extends Node
## 첫 조합 탭 진입 프레임 점검 (11/10) —— 실행(창이 있어야 그리기까지 잰다):
##   Godot --path . --resolution 720x1280 --position 495,1500 res://tests/forge_first.tscn -- [--seed=5] [--play=0] [--dwell=프레임수] [--shot=경로.png]
## 새 판 → 징집 탭을 몇 프레임 둔 뒤(첫 화면) 조합 탭으로 간다: go("forge") 가 돌아오기까지(노드 만들기) · 이어지는 프레임들의 길이(레이아웃 · 그리기 · 초상 읽기)를 잰다.
## 이어서 징집으로 갔다가 다시 조합 탭(캐시가 따뜻한 두 번째 진입)도 같은 방식으로 잰다. 초상 읽기 구간은 DB.prof (읽기 · 디코드 · 밉맵 · 텍스처 · 투명 검사).
## 인자 --nowarm 이면 초상 미리 읽기 없이 (옛 동작). --dwell=N 이면 징집 탭에서 N 프레임 머문 뒤에 들어간다 (미리 읽기가 돌 시간 —— 타이틀 · 징집에서 머무는 동안). 0 이면 곧바로.

func _ready() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	PlayLog.enabled = false
	Run.dev_immortal = true
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await get_tree().process_frame
	var r := Run.new()
	r.new_game(int(a.get("seed", "5")))
	for i in int(a.get("play", "0")):
		r.dev_autoplay()
	gs.run = r
	gs._title.visible = false
	gs.go("draw")
	for i in 20:
		await get_tree().process_frame
	gs.close_sheet()
	gs._bands.clear()
	gs._hide_band()
	var dwell := int(a.get("dwell", "0"))      # 징집 탭에 머문 프레임 수 (미리 읽기가 돌 시간)
	for i in dwell:
		await get_tree().process_frame
	print("== 징집 탭에서 %d프레임 머문 뒤 · 초상 캐시 %d장" % [dwell, DB.prof_cache_size()])
	await _enter(gs, "첫 진입")
	if a.has("shot"):
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(a.shot))
	if a.has("shot2"):      # --shot2=경로.png —— 맨 아래로 내려 「더 보기」 단추 자리를 찍는다
		gs._scroll.scroll_vertical = 99999
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(a.shot2))
	gs.go("draw")
	for i in 10:
		await get_tree().process_frame
	await _enter(gs, "두 번째 진입(따뜻)")
	if a.has("more"):      # --more=1 —— 「더 보기」 를 누른 순간(나머지를 다 펼침)도 잰다
		await _enter(gs, "더 보기 누름", func():
			for b in gs._body.find_children("*", "Button", true, false):
				if b.text.begins_with("더 보기"):
					b.pressed.emit()
					break)
	get_tree().quit()


func _enter(gs: GameScreen, label: String, act := Callable()) -> void:
	DB.prof_reset()
	var t0 := Time.get_ticks_usec()
	if act.is_valid():
		act.call()
	else:
		gs.go("forge")
	var t_build := Time.get_ticks_usec() - t0
	var n_tile := gs._body.find_children("*", "MiniTile", true, false).size()
	var n_node := gs._body.find_children("*", "", true, false).size()
	var ft: Array = []
	var last := Time.get_ticks_usec()
	for i in 16:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ft.append((now - last) / 1000.0)
		last = now
	var first_render: float = ft[0] + t_build / 1000.0
	var mx: float = 0.0
	for f in ft:
		mx = maxf(mx, f)
	n_tile = gs._body.find_children("*", "MiniTile", true, false).size()      # 지연 삭제 대기 중인 옛 타일이 섞였을 수 있으니 한 번 더
	var p: Dictionary = DB.prof
	print("[%s] go() 반환까지 %.1fms (노드 %d개 · MiniTile %d개) · 첫 프레임 %.1fms · 첫 렌더까지(go+첫 프레임) %.1fms · 최대 프레임 %.1fms" % [label, t_build / 1000.0, n_node, n_tile, ft[0], first_render, mx])
	print("    프레임 길이(ms): %s" % ", ".join(ft.map(func(f): return "%.1f" % f)))
	print("    이 구간에 초상 %d장 올림 · 메인 스레드 초상 시간 %.1fms (그중 텍스처 만들기 %.1f) · 스레드 포함 합: 디코드 %.1f · 밉맵 %.1f · 투명검사 %.1f · 내보낸앱경로 %.1f (ms) · 남은 미리읽기 %d장" % [p.n, p.main / 1000.0, p.tex / 1000.0, p.decode / 1000.0, p.mip / 1000.0, p.scan / 1000.0, p.res / 1000.0, DB.warm_pending()])
