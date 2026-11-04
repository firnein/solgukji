extends Node
## 소리 (autoload Sfx) —— 효과음 · 배경 음악. 소리 파일은 tools/scripts/make_sfx.py 로 합성했다 (assets/sfx, assets/bgm).
## 효과음: Sfx.play("hit") —— 같은 소리가 너무 잦으면(gap 초 안) 건너뛰고, 높이를 조금씩 흔들어 단조롭지 않게.
## 배경 음악: Sfx.music("battle") / Sfx.music("") 끄기 —— 바뀔 때 0.6초 동안 엇갈려 넘어간다.
## 버스 Music · SFX 를 만들어 Settings.bgm_vol · sfx_vol 로 크기를 맞춘다.

const SFX_NAMES := ["tap", "open", "draw", "gain", "forge", "deny", "hit", "crit", "magic", "skill", "ult", "rout",
	"burn", "splash", "confuse", "heal", "debuff", "horn", "drums", "win", "lose", "clash", "shout"]
## 소리마다 기본 크기(dB)와 최소 간격(초)
const TUNE := {"tap": [-16.0, 0.05], "open": [-16.0, 0.1], "draw": [-10.0, 0.06], "deny": [-14.0, 0.2], "gain": [-10.0, 0.12],
	"forge": [-8.0, 0.2], "hit": [-15.0, 0.09], "crit": [-10.0, 0.12], "magic": [-13.0, 0.1], "skill": [-9.0, 0.15],
	"ult": [-6.0, 0.3], "clash": [-12.0, 0.11], "shout": [-9.0, 2.5], "rout": [-10.0, 0.2], "horn": [-8.0, 0.8], "drums": [-6.0, 1.0], "win": [-5.0, 1.0]}     # 10/31 녹음 소리에 맞춘 크기 (dB) · 최소 간격 (초)
const POOL := 12
const ENABLED := true      # 10/31 사용자: 유치하지 않은 소리로 바꿔 다시 켠다 (CC0 녹음 —— assets/sfx/_licenses/출처.txt)

var _s := {}
var _pool: Array[AudioStreamPlayer] = []
var _last := {}
var _bgm_a: AudioStreamPlayer
var _bgm_b: AudioStreamPlayer
var _bgm_name := ""


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


## 배경 음악 —— 같은 곡이면 그대로, "" 이면 끈다
func music(n: String) -> void:
	if not ENABLED or n == _bgm_name:
		return
	_bgm_name = n
	var old := _bgm_a if _bgm_a.playing else _bgm_b
	var nw := _bgm_b if old == _bgm_a else _bgm_a
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -40.0, 0.6)
		tw.tween_callback(old.stop)
	if n == "":
		return
	var st = null
	for ext in ["ogg", "wav"]:
		if ResourceLoader.exists("res://assets/bgm/%s.%s" % [n, ext]):
			st = load("res://assets/bgm/%s.%s" % [n, ext])
			break
	if st == null:
		return
	if st is AudioStreamOggVorbis:
		st.loop = true
	elif st is AudioStreamWAV:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * st.mix_rate)
	nw.stream = st
	nw.volume_db = -40.0
	nw.play()
	var tw2 := create_tween()
	tw2.tween_property(nw, "volume_db", -13.0, 0.6)      # 10/31 오케스트라 곡은 효과음 밑에 깔리게
