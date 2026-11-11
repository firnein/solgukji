extends Node
## 소리 (autoload Sfx) —— 효과음 · 배경 음악. 소리 파일은 tools/scripts/make_sfx.py 로 합성했다 (assets/sfx, assets/bgm).
## 효과음: Sfx.play("hit") —— 같은 소리가 너무 잦으면(gap 초 안) 건너뛰고, 높이를 조금씩 흔들어 단조롭지 않게.
## 배경 음악: Sfx.music("battle") 처럼 장면 이름으로 —— 바뀔 때 0.6초 동안 엇갈려 넘어간다.
## 버스 Music · SFX 를 만들어 Settings.bgm_vol · sfx_vol 로 크기를 맞춘다.

const SFX_NAMES := ["tap", "open", "draw", "gain", "forge", "deny", "hit", "crit", "magic", "skill", "ult", "rout",
	"burn", "splash", "confuse", "heal", "debuff", "horn", "drums", "win", "lose", "clash", "arrow", "swing",
	"alert_beep", "alert_war", "alert_wise"]      # 11/5 shout(함성) 삭제 —— 불쾌하다
## 소리마다 기본 크기(dB)와 최소 간격(초)
const TUNE := {"tap": [-16.0, 0.05], "open": [-16.0, 0.1], "draw": [-10.0, 0.06], "deny": [-14.0, 0.2], "gain": [-10.0, 0.12],
	"forge": [-8.0, 0.2], "hit": [-15.0, 0.09], "crit": [-10.0, 0.12], "magic": [-13.0, 0.1], "skill": [-9.0, 0.15],
	"ult": [-6.0, 0.3], "clash": [-12.0, 0.11], "arrow": [-10.0, 0.35], "swing": [-7.0, 0.1], "rout": [-10.0, 0.2], "horn": [-8.0, 0.8], "drums": [-6.0, 1.0], "win": [-5.0, 1.0],
	"alert_beep": [-9.0, 0.3], "alert_war": [-5.0, 1.0], "alert_wise": [-5.0, 1.0]}      # 11/10 5초 비프 · 긴급 등용 함성 (무장 · 지장)     # 10/31 녹음 소리에 맞춘 크기 (dB) · 최소 간격 (초)
const POOL := 12
const ENABLED := true      # 10/31 사용자: 유치하지 않은 소리로 바꿔 다시 켠다 (CC0 녹음 —— assets/sfx/_licenses/출처.txt)

var _s := {}
var _pool: Array[AudioStreamPlayer] = []
var _last := {}
var _bgm_a: AudioStreamPlayer
var _bgm_b: AudioStreamPlayer
var _bgm_name := ""
var _bgm_last := ""      # 바로 전에 튼 곡 경로
var _resume := ""        # win · lose 가 끝나면 돌아갈 장면
var _bgm_rng := RandomNumberGenerator.new()      # 곡 고르기 전용 —— 전투 판정 RNG 가 아니다


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	# 이름마다 변형 여럿 —— <이름>.wav|ogg, <이름>_2 … 또는 <이름>_1 … (칼 부딪침 10종 등). 없으면 그 소리는 나지 않는다
	for n in SFX_NAMES:
		var vs := []
		for suf in [""] + range(1, 11).map(func(i): return "_%d" % i):
			for ext in ["wav", "ogg"]:
				var path := "res://assets/sfx/%s%s.%s" % [n, suf, ext]
				if ResourceLoader.exists(path):
					vs.append(load(path))
		if not vs.is_empty():
			_s[n] = vs
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_bgm_a = AudioStreamPlayer.new()
	_bgm_b = AudioStreamPlayer.new()
	for p in [_bgm_a, _bgm_b]:
		p.bus = "Music"
		add_child(p)
	_bgm_rng.randomize()
	Settings.load_cfg()
	apply_volume()


## 설정의 크기를 버스에 건다 (0 이면 끈다)
func apply_volume() -> void:
	for pair in [["Music", Settings.bgm_vol], ["SFX", Settings.sfx_vol]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i < 0:
			continue
		var v: float = pair[1]
		AudioServer.set_bus_mute(i, v <= 0.001)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


func play(n: String, vol_db := 0.0, pitch_var := 0.06) -> void:
	if not ENABLED or not _s.has(n):
		return
	var tune: Array = TUNE.get(n, [-6.0, 0.05])
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(n, -9.0)) < float(tune[1]):
		return
	_last[n] = now
	var best: AudioStreamPlayer = null
	for p in _pool:
		if not p.playing:
			best = p
			break
	if best == null:
		best = _pool[0]
		_pool.erase(best)
		_pool.append(best)
	best.stream = _s[n][randi() % _s[n].size()]
	best.volume_db = float(tune[0]) + vol_db
	best.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	best.play()


## 배경 음악 —— 장면 이름으로 부른다: "title"(제목 · 온라인 대기실) · "prep"(준비) · "battle"(토벌 · 대전) · "final"(토너먼트 결승) · "" 끄기.
## assets/bgm/<장면>_<번호>.ogg 중 하나를 고른다 (바로 전에 튼 곡은 피한다). 이미 그 장면이면 그대로. "menu" 는 "prep" 로 본다.
## "win" · "lose" 는 짧은 마무리 —— 한 번 틀고 끝나면 부르기 전 장면의 곡으로 돌아간다. 고르기는 소리 전용 RNG (전투 판정 RNG 와 무관).
func music(n: String) -> void:
	if not ENABLED:
		return
	if n == "menu":
		n = "prep"
	if n == _bgm_name:
		return
	if n == "win" or n == "lose":
		if _bgm_name != "win" and _bgm_name != "lose":
			_resume = _bgm_name
		_play_bgm(n, _bgm_path(n), false)
		return
	_resume = ""
	if n == "":
		_play_bgm("", "", true)
		return
	var tracks := bgm_tracks(n)
	if tracks.is_empty():
		_play_bgm(n, "", true)
		return
	var pool := tracks.filter(func(t): return t != _bgm_last)
	if pool.is_empty():
		pool = tracks
	_play_bgm(n, pool[_bgm_rng.randi() % pool.size()], true)


## 그 장면의 곡 경로들 (assets/bgm/<장면>_<번호>.ogg)
func bgm_tracks(scene: String) -> Array:
	var out := []
	for i in range(1, 10):
		var path := "res://assets/bgm/%s_%d.ogg" % [scene, i]
		if ResourceLoader.exists(path):
			out.append(path)
	return out


func _bgm_path(n: String) -> String:
	var path := "res://assets/bgm/%s.ogg" % n
	return path if ResourceLoader.exists(path) else ""


func _play_bgm(n: String, path: String, loop: bool) -> void:
	_bgm_name = n
	var old := _bgm_a if _bgm_a.playing else _bgm_b
	var nw := _bgm_b if old == _bgm_a else _bgm_a
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -40.0, 0.6)
		tw.tween_callback(old.stop)
	if path == "":
		return
	var st = load(path)
	if st == null:
		return
	if st is AudioStreamOggVorbis:
		st.loop = loop
	if loop:
		_bgm_last = path
	for p in [_bgm_a, _bgm_b]:
		if p.finished.is_connected(_on_jingle_done):
			p.finished.disconnect(_on_jingle_done)
	nw.stream = st
	nw.volume_db = -40.0
	nw.play()
	if not loop:
		nw.finished.connect(_on_jingle_done, CONNECT_ONE_SHOT)
	var tw2 := create_tween()
	tw2.tween_property(nw, "volume_db", -13.0, 0.6)      # 10/31 오케스트라 곡은 효과음 밑에 깔리게


func _on_jingle_done() -> void:
	if _bgm_name == "win" or _bgm_name == "lose":
		var back := _resume
		_resume = ""
		_bgm_name = "~"      # 같은 이름 건너뛰기 방지
		music(back)
