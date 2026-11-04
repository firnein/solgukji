class_name Models
extends RefCounted
## 병사·말·무기·풍경 모델 —— 전부 코드로 만든 로우폴리다. 모델은 +X 를 바라보고 발끝이 원점이다.
## 정점 색 알파 1 = 세력색으로 칠할 옷감, 0 = 고유색(피부·쇠·나무). 알파 1 인 곳의 rgb 는 명암만 준다.
## 팔다리는 MeshKit.joint 로 부위를 표시해 두고 셰이더가 걸음·공격 박자에 맞춰 흔든다.
##   1 왼다리 · 2 오른다리 · 3 왼팔 · 4 무기 든 오른팔(공격 때만) · 5·6 말 다리(대각선 짝) · 7 빈 오른팔(걸음에 흔듦)

const SKIN := Color(0.86, 0.70, 0.55, 0)
const DARK := Color(0.14, 0.14, 0.16, 0)
const LEATHER := Color(0.36, 0.25, 0.16, 0)
const STEEL := Color(0.66, 0.68, 0.72, 0)
const GOLD := Color(0.85, 0.66, 0.30, 0)
const WOOD := Color(0.45, 0.33, 0.20, 0)
const PAPER := Color(0.93, 0.89, 0.78, 0)
const HORSE := Color(0.42, 0.28, 0.17, 0)
const HORSE2 := Color(0.22, 0.15, 0.10, 0)
const RED := Color(0.78, 0.16, 0.12, 0)
const HIP := Vector2(0, 0.48)
const SHOULDER := Vector2(0.02, 0.95)
const R_SHOULDER := Vector2(0.0, 1.9)     # 말 탄 사람의 어깨


static func team(shade := 1.0) -> Color:
	return Color(shade, shade, shade, 1)


## 병종별 몸통 (무기 제외 —— 무기는 따로 움직인다)
static func body(tag: String) -> ArrayMesh:
	var k := MeshKit.new()
	match tag:
		"기병":
			_horse(k)
			_rider(k)
		"책사", "유생", "술사", "모사":
			_robe(k, tag)
		_:
			_infantry(k, tag)
	return k.mesh()


static func _infantry(k: MeshKit, tag: String) -> void:
	var rogue := tag == "도적"
	for z in [-0.09, 0.09]:
		k.joint(1 if z < 0 else 2, HIP)
		k.box(Vector3(0, 0.24, z), Vector3(0.13, 0.48, 0.12), DARK)
		k.box(Vector3(0.03, 0.03, z), Vector3(0.2, 0.06, 0.12), LEATHER)
	k.joint(0)
	k.box(Vector3(0, 0.55, 0), Vector3(0.24, 0.18, 0.36), DARK if rogue else team(0.78))
	k.box(Vector3(0, 0.79, 0), Vector3(0.22, 0.38, 0.34), DARK if rogue else team())
	k.box(Vector3(0, 0.63, 0), Vector3(0.25, 0.05, 0.37), team(0.9) if rogue else LEATHER)
	for z in [-0.215, 0.215]:
		k.joint(3 if z < 0 else (7 if tag == "궁병" else 4), SHOULDER)
		k.box(Vector3(0.02, 0.78, z), Vector3(0.1, 0.36, 0.09), DARK if rogue else team(0.85))
		k.box(Vector3(0.02, 0.93, z * 1.05), Vector3(0.14, 0.07, 0.12), STEEL if not rogue else LEATHER)   # 어깨받이
		k.sphere(Vector3(0.03, 0.58, z), 0.05, SKIN, 4, 3)
	k.joint(0)
	k.sphere(Vector3(0, 1.08, 0), 0.12, SKIN, 6, 4)
	match tag:
		"창병":
			k.cone(Vector3(0, 1.1, 0), Vector3(0, 1.36, 0), 0.155, STEEL, 7)
			k.box(Vector3(0, 1.12, 0), Vector3(0.27, 0.04, 0.3), STEEL)
			k.cyl(Vector3(0, 1.36, 0), Vector3(-0.04, 1.46, 0), 0.03, RED, 4, 0.05)    # 투구 술
			# 왼팔 방패
			k.joint(3, SHOULDER)
			k.box(Vector3(0.14, 0.78, -0.27), Vector3(0.05, 0.5, 0.34), team(0.6))
			k.box(Vector3(0.17, 0.78, -0.27), Vector3(0.02, 0.12, 0.12), GOLD)
			k.joint(0)
		"궁병":
			k.cyl(Vector3(0, 1.12, 0), Vector3(0, 1.22, 0), 0.13, LEATHER, 7, 0.1)
			k.cyl(Vector3(-0.15, 0.62, 0.08), Vector3(-0.17, 1.02, 0.05), 0.06, LEATHER, 5)
			# 활 —— 앞으로 든 곡선 (오른팔과 함께 흔든다)
			k.joint(7, SHOULDER)
			var prev := Vector3.ZERO
			for i in 7:
				var t := lerpf(-1.15, 1.15, i / 6.0)
				var p := Vector3(0.24 + cos(t) * 0.12, 0.85 + sin(t) * 0.5, 0.2)
				if i > 0:
					k.cyl(prev, p, 0.018, WOOD, 4)
				prev = p
			k.joint(0)
		"도적":
			k.sphere(Vector3(-0.01, 1.11, 0), 0.13, DARK, 6, 3, Vector3(1, 0.9, 1))
			k.box(Vector3(0.1, 1.06, 0), Vector3(0.05, 0.05, 0.25), team(0.9))


static func _robe(k: MeshKit, tag: String) -> void:
	k.cyl(Vector3(0, 0.0, 0), Vector3(0, 0.98, 0), 0.3, team(), 8, 0.17)
	k.cyl(Vector3(0, 0.02, 0), Vector3(0, 0.12, 0), 0.305, team(0.6), 8, 0.3, false)
	k.box(Vector3(0.0, 0.62, 0), Vector3(0.3, 0.06, 0.4), PAPER)
	for z in [-0.22, 0.22]:
		k.joint(3 if z < 0 else 7, SHOULDER)
		k.cyl(Vector3(0, 0.95, z), Vector3(0.1, 0.62, z * 1.15), 0.075, team(0.8), 5, 0.11)
		k.sphere(Vector3(0.11, 0.6, z * 1.15), 0.045, SKIN, 4, 3)
	k.joint(0)
	k.box(Vector3(0.05, 0.96, 0), Vector3(0.16, 0.05, 0.22), PAPER)
	k.sphere(Vector3(0, 1.12, 0), 0.12, SKIN, 6, 4)
	match tag:
		"책사":
			k.box(Vector3(0, 1.32, 0), Vector3(0.15, 0.2, 0.15), DARK)
			k.box(Vector3(0, 1.23, 0), Vector3(0.36, 0.025, 0.36), DARK)
			k.joint(7, SHOULDER)
			k.tri(Vector3(0.22, 0.66, 0.2), Vector3(0.42, 0.98, 0.12), Vector3(0.46, 0.8, 0.34), PAPER, Vector3(0.3, 0.7, 0))
			k.joint(0)
		"유생":
			k.cyl(Vector3(0, 1.2, 0), Vector3(0, 1.36, 0), 0.1, DARK, 6, 0.09)
			k.cyl(Vector3(0, 1.2, 0), Vector3(0, 1.22, 0), 0.26, DARK, 8)
			k.box(Vector3(0.24, 0.66, 0.16), Vector3(0.16, 0.04, 0.22), PAPER)
		"술사":
			k.cone(Vector3(0, 1.17, 0), Vector3(-0.05, 1.55, 0), 0.17, DARK, 6)
			k.cyl(Vector3(0.24, 0.0, 0.22), Vector3(0.24, 1.75, 0.22), 0.025, WOOD, 4)
			k.sphere(Vector3(0.24, 1.8, 0.22), 0.07, Color(1.0, 0.62, 0.25, 0), 5, 3)
		"모사":
			k.box(Vector3(0, 1.28, 0), Vector3(0.2, 0.12, 0.17), DARK)
			k.box(Vector3(-0.02, 1.36, 0), Vector3(0.08, 0.06, 0.24), DARK)
			k.joint(7, SHOULDER)
			k.cyl(Vector3(0.24, 0.7, 0.06), Vector3(0.24, 0.7, 0.34), 0.045, PAPER, 6)
			k.joint(0)


static func _horse(k: MeshKit) -> void:
	for p in [Vector3(-0.55, 0, -0.15), Vector3(-0.55, 0, 0.15), Vector3(0.5, 0, -0.15), Vector3(0.5, 0, 0.15)]:
		k.joint(5 if (p.x > 0) == (p.z < 0) else 6, Vector2(p.x, 0.95))
		k.cyl(p + Vector3(0, 0.95, 0), p + Vector3(0, 0.02, 0), 0.065, HORSE2, 5, 0.045)
		k.box(p + Vector3(0.02, 0.04, 0), Vector3(0.12, 0.08, 0.1), DARK)       # 발굽
	k.joint(0)
	k.box(Vector3(0, 1.18, 0), Vector3(1.45, 0.52, 0.46), HORSE)
	k.box(Vector3(0.62, 1.22, 0), Vector3(0.32, 0.5, 0.42), HORSE)
	k.cyl(Vector3(0.62, 1.32, 0), Vector3(0.92, 1.82, 0), 0.15, HORSE, 6, 0.11)
	k.box(Vector3(1.04, 1.8, 0), Vector3(0.46, 0.2, 0.2), HORSE, Basis(Vector3.BACK, -0.45))
	k.box(Vector3(0.82, 1.92, 0), Vector3(0.28, 0.06, 0.04), HORSE2)
	k.cyl(Vector3(-0.72, 1.32, 0), Vector3(-0.95, 0.75, 0), 0.06, HORSE2, 5, 0.03)
	# 안장 깔개 —— 세력색
	k.box(Vector3(-0.05, 1.46, 0), Vector3(0.55, 0.05, 0.52), team(0.7))
	k.box(Vector3(-0.05, 1.3, 0), Vector3(0.5, 0.3, 0.48), team(0.55))


static func _rider(k: MeshKit) -> void:
	for z in [-0.17, 0.17]:
		k.box(Vector3(0.05, 1.38, z), Vector3(0.14, 0.42, 0.11), DARK)
	k.box(Vector3(-0.04, 1.72, 0), Vector3(0.22, 0.42, 0.32), team())
	for z in [-0.2, 0.2]:
		k.joint(3 if z < 0 else 4, R_SHOULDER)
		k.box(Vector3(0.02, 1.72, z), Vector3(0.1, 0.34, 0.08), team(0.85))
		k.sphere(Vector3(0.03, 1.53, z), 0.045, SKIN, 4, 3)
	k.joint(0)
	k.sphere(Vector3(-0.03, 2.03, 0), 0.115, SKIN, 6, 4)
	k.cone(Vector3(-0.03, 2.05, 0), Vector3(-0.03, 2.3, 0), 0.15, STEEL, 7)


## 무기 —— 손잡이가 원점, 위(+Y)로 뻗는다. 자세는 회전으로 바꾼다.
static func spear() -> ArrayMesh:
	var k := MeshKit.new()
	k.cyl(Vector3(0, -0.6, 0), Vector3(0, 2.2, 0), 0.022, WOOD, 4)
	k.cone(Vector3(0, 2.2, 0), Vector3(0, 2.48, 0), 0.045, STEEL, 4)
	k.box(Vector3(0, 2.12, 0), Vector3(0.03, 0.12, 0.09), team(0.9))
	return k.mesh()


static func sword() -> ArrayMesh:
	var k := MeshKit.new()
	k.box(Vector3(0, 0.38, 0), Vector3(0.025, 0.62, 0.07), STEEL)
	k.box(Vector3(0, 0.05, 0), Vector3(0.06, 0.03, 0.16), GOLD)
	k.cyl(Vector3(0, -0.1, 0), Vector3(0, 0.04, 0), 0.025, LEATHER, 4)
	return k.mesh()


## 활 —— 손잡이가 원점, 활대는 ±Y, 시위는 -X 쪽 (구운 궁병의 왼손에 붙인다)
static func bow() -> ArrayMesh:
	var k := MeshKit.new()
	var prev := Vector3.ZERO
	for i in 9:
		var a := lerpf(-1.2, 1.2, i / 8.0)
		var q := Vector3(cos(a) * 0.22 - 0.22, sin(a) * 0.62, 0)
		if i > 0:
			k.cyl(prev, q, 0.02, WOOD.darkened(0.2), 4)
		prev = q
	k.cyl(Vector3(cos(1.2) * 0.22 - 0.22, sin(1.2) * 0.62, 0), Vector3(cos(1.2) * 0.22 - 0.22, -sin(1.2) * 0.62, 0), 0.006, PAPER, 3)
	k.cyl(Vector3(0, -0.06, 0), Vector3(0, 0.06, 0), 0.028, LEATHER, 4)
	return k.mesh()


static func lance() -> ArrayMesh:
	var k := MeshKit.new()
	k.cyl(Vector3(0, -0.9, 0), Vector3(0, 2.9, 0), 0.026, WOOD, 4)
	k.cone(Vector3(0, 2.9, 0), Vector3(0, 3.25, 0), 0.05, STEEL, 4)
	k.box(Vector3(0, 2.75, 0.06), Vector3(0.02, 0.22, 0.14), team())
	return k.mesh()


## 장수 망토 —— 등 뒤로 늘어진 삼각 천
static func cape() -> ArrayMesh:
	var k := MeshKit.new()
	var c := Color(1, 1, 1, 0)
	k.quad(Vector3(-0.12, 0.98, -0.18), Vector3(-0.12, 0.98, 0.18), Vector3(-0.42, 0.25, 0.26), Vector3(-0.42, 0.25, -0.26), c, Vector3(0.2, 0.6, 0))
	return k.mesh()


static func arrow() -> ArrayMesh:
	var k := MeshKit.new()
	k.cyl(Vector3(0, 0, 0.45), Vector3(0, 0, -0.45), 0.012, WOOD, 3)
	k.cone(Vector3(0, 0, -0.45), Vector3(0, 0, -0.56), 0.025, STEEL, 3)
	k.box(Vector3(0, 0, 0.4), Vector3(0.005, 0.06, 0.12), PAPER)
	return k.mesh()


static func pine(rng: RandomNumberGenerator) -> ArrayMesh:
	var k := MeshKit.new()
	k.cyl(Vector3.ZERO, Vector3(0, 2.2, 0), 0.22, Color(0.3, 0.22, 0.15), 5, 0.14)
	var g := Color(0.16, 0.26, 0.17).lerp(Color(0.2, 0.3, 0.16), rng.randf())
	for i in 4:
		var y := 1.4 + i * 1.55
		k.cone(Vector3(0, y, 0), Vector3(0, y + 2.6, 0), 2.1 - i * 0.42, g.lightened(i * 0.04), 7)
	return k.mesh()


static func broadleaf(rng: RandomNumberGenerator) -> ArrayMesh:
	var k := MeshKit.new()
	k.cyl(Vector3.ZERO, Vector3(0, 2.8, 0), 0.25, Color(0.32, 0.24, 0.16), 5, 0.16)
	var g := Color(0.28, 0.36, 0.18).lerp(Color(0.38, 0.38, 0.17), rng.randf())
	k.sphere(Vector3(0, 3.6, 0), 1.9, g, 7, 5, Vector3(1, 0.85, 1), 0.12, rng)
	k.sphere(Vector3(0.9, 3.0, 0.5), 1.2, g.darkened(0.08), 6, 4, Vector3.ONE, 0.12, rng)
	k.sphere(Vector3(-0.8, 3.1, -0.6), 1.3, g.lightened(0.05), 6, 4, Vector3.ONE, 0.12, rng)
	return k.mesh()


static func rock(rng: RandomNumberGenerator) -> ArrayMesh:
	var k := MeshKit.new()
	k.sphere(Vector3(0, 0.15, 0), 1.0, Color(0.42, 0.41, 0.38), 7, 5, Vector3(1.3, 0.7, 1.0), 0.22, rng)
	return k.mesh()


static func grass(rng: RandomNumberGenerator) -> ArrayMesh:
	var k := MeshKit.new()
	for i in 5:
		var a := rng.randf() * TAU
		var o := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.12)
		var h := rng.randf_range(0.18, 0.38)
		var lean := Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))
		var side := Vector3(-sin(a), 0, cos(a)) * 0.03
		var col := Color(0.26, 0.33, 0.14).lerp(Color(0.42, 0.44, 0.22), rng.randf())
		k.tri(o - side, o + side, o + lean + Vector3(0, h, 0), col, o + Vector3(cos(a), 0, sin(a)))
	return k.mesh()


static func mountain(rng: RandomNumberGenerator, r: float, h: float) -> ArrayMesh:
	var k := MeshKit.new()
	var col := Color(0.36, 0.40, 0.42)
	var seg := 9
	var peak := Vector3(rng.randf_range(-0.2, 0.2) * r, h, rng.randf_range(-0.2, 0.2) * r)
	var mid := []
	var base := []
	for i in seg:
		var t := TAU * i / seg
		var d := Vector3(cos(t), 0, sin(t))
		base.append(d * r * rng.randf_range(0.85, 1.15) + Vector3(0, -12, 0))
		mid.append(d * r * rng.randf_range(0.45, 0.6) + Vector3(0, h * rng.randf_range(0.45, 0.6), 0))
	for i in seg:
		var j := (i + 1) % seg
		k.quad(base[i], base[j], mid[j], mid[i], col.darkened(rng.randf() * 0.1), Vector3(0, h * 0.3, 0))
		k.tri(mid[i], mid[j], peak, col.lightened(0.05 + rng.randf() * 0.08), Vector3(0, h * 0.3, 0))
	return k.mesh()


# ───────── 장수 —— 갑옷 입힌 군마 위의 장수. 병종마다 무기가 다르다 ─────────
##   창병 → 청룡언월도 · 도적 → 대도 · 기병 → 장팔사모 · 궁병 → 큰 활(몸에 붙임) · 지략 → 깃털 부채(몸에 붙임)
## 무기가 따로 있으면(general_weapon) 오른손 자리 G_HAND 에 붙여 따로 움직인다.
const G_HAND := Vector3(0.18, 1.58, 0.3)


static func general_weapon(tag: String) -> String:
	match tag:
		"창병": return "g_glaive"
		"도적": return "g_saber"
		"기병": return "g_lance"
	return ""


static func general(tag: String, with_horse := true) -> ArrayMesh:
	var k := MeshKit.new()
	if with_horse:
		_warhorse(k)      # 11/4 저녁: 구운 군마(assets/models/vat/군마)가 있으면 War3D 가 말을 따로 겹쳐 그린다
	var caster: bool = Squad.CLS.get(tag, "") == "caster"
	# 다리 —— 등자에 건 채로 움직이지 않는다
	for z in [-0.2, 0.2]:
		k.box(Vector3(0.08, 1.42, z), Vector3(0.16, 0.4, 0.13), DARK)
		k.box(Vector3(0.14, 1.2, z * 1.1), Vector3(0.22, 0.08, 0.13), LEATHER)
	# 몸통 —— 비늘 갑옷 · 허리띠 · 가슴 호심경
	if caster:
		k.cyl(Vector3(-0.04, 1.5, 0), Vector3(-0.04, 2.02, 0), 0.24, team(), 8, 0.17)
		k.box(Vector3(0.0, 1.62, 0), Vector3(0.36, 0.06, 0.44), PAPER)
	else:
		k.box(Vector3(-0.04, 1.78, 0), Vector3(0.26, 0.48, 0.38), team())
		for i in 4:
			k.box(Vector3(0.1, 1.62 + i * 0.09, 0), Vector3(0.04, 0.05, 0.36), STEEL.darkened(0.1 * (i % 2)))
		k.cyl(Vector3(0.11, 1.84, 0), Vector3(0.13, 1.84, 0), 0.09, GOLD, 8)
		k.box(Vector3(-0.04, 1.56, 0), Vector3(0.29, 0.07, 0.41), GOLD)
		# 어깨 갑옷 —— 금빛 짐승 머리 견갑
		for z in [-0.23, 0.23]:
			k.sphere(Vector3(-0.02, 1.98, z), 0.12, GOLD, 6, 4, Vector3(1.1, 0.7, 1.0))
	# 망토 —— 등 뒤로 늘어진 세력색 천
	k.quad(Vector3(-0.18, 2.0, -0.22), Vector3(-0.18, 2.0, 0.22), Vector3(-0.62, 1.2, 0.34), Vector3(-0.62, 1.2, -0.34), team(0.7), Vector3(0.2, 1.6, 0))
	# 팔 —— 오른팔은 무기를 들고 공격 때 휘두른다
	for z in [-0.24, 0.24]:
		var weapon_arm: bool = z > 0 and general_weapon(tag) != ""
		k.joint(3 if z < 0 else (4 if weapon_arm else 7), R_SHOULDER)
		k.box(Vector3(0.02, 1.74, z), Vector3(0.12, 0.36, 0.1), team(0.85) if caster else STEEL)
		k.sphere(Vector3(0.05, 1.53, z), 0.055, SKIN, 4, 3)
		if z < 0 and tag == "궁병":
			# 큰 활 —— 왼손에 세워 든다
			var prev := Vector3.ZERO
			for i in 9:
				var t := lerpf(-1.2, 1.2, i / 8.0)
				var q := Vector3(0.12 + cos(t) * 0.16, 1.55 + sin(t) * 0.75, z - 0.04)
				if i > 0:
					k.cyl(prev, q, 0.025, WOOD.darkened(0.2), 4)
				prev = q
			k.cyl(Vector3(0.12 + cos(1.2) * 0.16, 1.55 + sin(1.2) * 0.75, z - 0.04), Vector3(0.12 + cos(1.2) * 0.16, 1.55 - sin(1.2) * 0.75, z - 0.04), 0.006, PAPER, 3)
		if z > 0 and caster:
			# 깃털 부채
			k.cyl(Vector3(0.07, 1.52, z), Vector3(0.18, 1.62, z), 0.02, WOOD, 4)
			k.tri(Vector3(0.18, 1.62, z), Vector3(0.36, 1.98, z - 0.12), Vector3(0.46, 1.78, z + 0.14), PAPER, Vector3(0.2, 1.6, z))
			k.tri(Vector3(0.18, 1.62, z), Vector3(0.46, 1.78, z + 0.14), Vector3(0.3, 1.95, z + 0.05), Color(0.85, 0.82, 0.74, 0), Vector3(0.2, 1.6, z))
	k.joint(0)
	# 머리 —— 얼굴 · 수염 · 투구(금테 · 붉은 술) 또는 관
	k.sphere(Vector3(-0.02, 2.14, 0), 0.13, SKIN, 7, 5)
	k.box(Vector3(0.09, 2.04, 0), Vector3(0.06, 0.12, 0.12), DARK)
	if caster:
		k.cyl(Vector3(-0.03, 2.22, 0), Vector3(-0.03, 2.42, 0), 0.11, DARK, 6, 0.09)
		k.box(Vector3(-0.03, 2.42, 0), Vector3(0.3, 0.03, 0.12), DARK)
	else:
		k.cone(Vector3(-0.03, 2.16, 0), Vector3(-0.03, 2.46, 0), 0.17, STEEL, 8)
		k.cyl(Vector3(-0.03, 2.17, 0), Vector3(-0.03, 2.21, 0), 0.175, GOLD, 8)
		k.cyl(Vector3(-0.03, 2.46, 0), Vector3(-0.1, 2.68, 0), 0.025, RED, 5, 0.08)
		k.box(Vector3(0.05, 2.33, 0), Vector3(0.03, 0.14, 0.2), GOLD)          # 이마 장식
	# 등 뒤 깃발(장수기)은 10/31 사용자 요청으로 뺐다
	return k.mesh()


## 군마 —— 굵은 몸통 · 들린 목 · 갈기 · 세력색 마갑과 금테
static func _warhorse(k: MeshKit) -> void:
	for p in [Vector3(-0.62, 0, -0.17), Vector3(-0.62, 0, 0.17), Vector3(0.56, 0, -0.17), Vector3(0.56, 0, 0.17)]:
		k.joint(5 if (p.x > 0) == (p.z < 0) else 6, Vector2(p.x, 1.05))
		k.cyl(p + Vector3(0, 1.05, 0), p + Vector3(0.02, 0.5, 0), 0.085, HORSE, 5, 0.06)
		k.cyl(p + Vector3(0.02, 0.5, 0), p + Vector3(0, 0.06, 0), 0.055, HORSE2, 5, 0.05)
		k.box(p + Vector3(0.03, 0.04, 0), Vector3(0.14, 0.08, 0.12), DARK)
	k.joint(0)
	k.box(Vector3(0, 1.28, 0), Vector3(1.6, 0.58, 0.52), HORSE)
	k.sphere(Vector3(0.68, 1.32, 0), 0.32, HORSE, 6, 4, Vector3(1, 1, 0.85))
	k.sphere(Vector3(-0.72, 1.3, 0), 0.3, HORSE, 6, 4, Vector3(1, 1, 0.9))
	k.cyl(Vector3(0.7, 1.45, 0), Vector3(1.02, 2.02, 0), 0.17, HORSE, 6, 0.12)
	k.box(Vector3(1.15, 2.0, 0), Vector3(0.5, 0.22, 0.22), HORSE, Basis(Vector3.BACK, -0.5))
	for z in [-0.06, 0.06]:
		k.cone(Vector3(1.0, 2.12, z), Vector3(0.98, 2.26, z), 0.04, HORSE2, 4)
	k.box(Vector3(0.84, 1.82, 0), Vector3(0.42, 0.5, 0.06), HORSE2, Basis(Vector3.BACK, -1.0))   # 갈기
	k.cyl(Vector3(-0.82, 1.45, 0), Vector3(-1.12, 0.8, 0), 0.08, HORSE2, 5, 0.03)
	# 마갑 —— 세력색 천과 금테, 얼굴 가리개
	k.box(Vector3(-0.02, 1.2, 0), Vector3(1.5, 0.42, 0.56), team(0.75))
	k.box(Vector3(-0.02, 1.0, 0), Vector3(1.5, 0.05, 0.57), GOLD)
	k.box(Vector3(0.66, 1.3, 0), Vector3(0.3, 0.5, 0.5), team(0.6))
	k.box(Vector3(1.22, 2.02, 0), Vector3(0.32, 0.06, 0.23), STEEL, Basis(Vector3.BACK, -0.5))
	# 안장
	k.box(Vector3(-0.02, 1.6, 0), Vector3(0.5, 0.1, 0.5), LEATHER)
	k.box(Vector3(0.2, 1.68, 0), Vector3(0.08, 0.14, 0.3), LEATHER)


## 청룡언월도 —— 긴 자루 끝의 넓은 초승달 날과 붉은 술
static func glaive() -> ArrayMesh:
	var k := MeshKit.new()
	k.cyl(Vector3(0, -1.0, 0), Vector3(0, 2.3, 0), 0.032, WOOD.darkened(0.25), 5)
	k.cyl(Vector3(0, -1.0, 0), Vector3(0, -1.15, 0), 0.04, GOLD, 5, 0.01)
	k.cyl(Vector3(0, 2.2, 0), Vector3(0, 2.28, 0), 0.05, GOLD, 6)
	var prev := Vector3(0, 2.25, 0)
	for i in 6:
		var u := (i + 1) / 6.0
		var q := Vector3(0.05 + sin(u * 1.4) * 0.28, 2.25 + u * 0.75, 0)
		k.box((prev + q) / 2 + Vector3(0.06, 0, 0), Vector3(0.16 + 0.1 * sin(u * PI), (q - prev).length() + 0.02, 0.025), STEEL, Basis(Vector3.BACK, -atan2(q.x - prev.x, q.y - prev.y)))
		prev = q
	k.cone(Vector3(0, 2.2, 0), Vector3(-0.08, 1.95, 0), 0.08, RED, 5)
	return k.mesh()


## 대도 —— 넓고 휜 외날
static func saber() -> ArrayMesh:
	var k := MeshKit.new()
	k.cyl(Vector3(0, -0.22, 0), Vector3(0, 0.06, 0), 0.03, LEATHER, 5)
	k.box(Vector3(0, 0.08, 0), Vector3(0.09, 0.04, 0.2), GOLD)
	var prev := Vector3(0, 0.1, 0)
	for i in 5:
		var u := (i + 1) / 5.0
		var q := Vector3(sin(u * 0.9) * 0.18, 0.1 + u * 0.95, 0)
		k.box((prev + q) / 2, Vector3(0.11 - u * 0.03, (q - prev).length() + 0.02, 0.03), STEEL, Basis(Vector3.BACK, -atan2(q.x - prev.x, q.y - prev.y)))
		prev = q
	return k.mesh()


## 장팔사모 —— 뱀처럼 굽은 창날
static func snake_lance() -> ArrayMesh:
	var k := MeshKit.new()
	k.cyl(Vector3(0, -1.1, 0), Vector3(0, 3.0, 0), 0.03, DARK, 5)
	k.cyl(Vector3(0, 2.92, 0), Vector3(0, 3.0, 0), 0.05, GOLD, 6)
	var prev := Vector3(0, 3.0, 0)
	for i in 6:
		var u := (i + 1) / 6.0
		var q := Vector3(sin(u * TAU) * 0.06, 3.0 + u * 0.55, 0)
		k.cyl(prev, q, 0.055 * (1.0 - u * 0.8), STEEL, 4)
		prev = q
	k.cone(Vector3(0, 2.9, 0), Vector3(0, 2.62, 0), 0.07, RED, 5)
	return k.mesh()
