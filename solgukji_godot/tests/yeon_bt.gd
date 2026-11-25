extends RtBattle
## 11/26 인연 점검(tests/yeon_check) 전용 —— 한 진영만 인연을 끈다 (같은 덱 · 같은 시드에서 "인연 덕에 얻는 승률"을 재려고). 엔진은 건드리지 않는다.
## off_camp 진영: 인연 짝 모으기 · 초월 게이지 가속을 하지 않는다. RtBattle.yeon_basic 이 켜져 있으면 그 진영도 기본 연쇄는 한다 ("인연을 안 맞춘 덱"과 같은 처지).
var off_camp := ""
var mix_only := false      # (다) 병종 섞인 연쇄만 주제 효과 —— 연쇄에 물리(창 · 기 · 궁 · 도적) · 책략(책사 · 유생 · 술사 · 모사)이 함께 껴야 주제가 터진다
var mix_skip := 0          # 섞이지 않아 주제를 건너뛴 연쇄 수


func _inyeon_recruit(u: Unit, wait: float, cap := 0) -> void:
	if u.camp == off_camp:
		if yeon_basic and not bool(u.ult.get("mini", false)) and not (tac != null and tac.yeon_cut(u.camp)):
			_yeon_basic_recruit(u, wait, cap)
		return
	super(u, wait, cap)


func _yeon_up_setup() -> void:
	super()
	for u in _gain_up.keys():
		if u.camp == off_camp:
			_gain_up.erase(u)


func _inyeon_theme_fire(grp: Dictionary) -> void:
	if mix_only:
		var ms: Array = grp.members.duplicate()
		if grp.has("head") and not ms.has(grp.head):
			ms.append(grp.head)
		if not grp.lead in ms:
			ms.append(grp.lead)
		var ph := ms.any(func(o): return DB.PHYS_TAGS.has(str(o.c.tag)))
		var it := ms.any(func(o): return DB.INT_TAGS.has(str(o.c.tag)))
		if not (ph and it):
			mix_skip += 1
			return
	super(grp)
