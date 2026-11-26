extends RtBattle
## 11/26 기인 값어치 점검(tests/kiin_value) 전용 —— 한 진영만 기인 연쇄 수치(마무리 배율 · 합동 상한 배수)를 바꾼다. 엔진 기본값은 건드리지 않는다.
## role: 진영 → {fin: 마무리 배율, cap: 합동 상한 배수, all: 연쇄 전원 배율(없으면 1)}. 없는 진영은 지금 그대로 (RtBattle.yeon_kiin_fin_mul · yeon_kiin_cap_mul)
var role := {}


func _inyeon_fire_setup(u: Unit, grp: Dictionary) -> void:
	if not role.has(u.camp):
		super(u, grp)
		return
	var f0 := RtBattle.yeon_kiin_fin_mul
	var c0 := RtBattle.yeon_kiin_cap_mul
	RtBattle.yeon_kiin_fin_mul = float(role[u.camp].fin)
	RtBattle.yeon_kiin_cap_mul = float(role[u.camp].cap)
	super(u, grp)
	RtBattle.yeon_kiin_fin_mul = f0
	RtBattle.yeon_kiin_cap_mul = c0
	var al := float(role[u.camp].get("all", 1.0))      # 기인이 연 연쇄에 든 장수 모두(마무리 장수는 fin 그대로)의 고유기 피해 배율 —— 구조를 바꾼 안의 시험
	if al != 1.0 and grp.get("fired", false) and grp.get("kiin_open", false) and not _ult_extra.get("finish", false):
		_ult_amp_x *= al
