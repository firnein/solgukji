class_name Models
extends RefCounted
## 병사·말·무기·풍경 모델 —— 전부 코드로 만든 로우폴리다. 모델은 +X 를 바라보고 발끝이 원점이다.
## 정점 색 알파 1 = 세력색으로 칠할 옷감, 0 = 고유색(피부·쇠·나무). 알파 1 인 곳의 rgb 는 명암만 준다.

const SKIN := Color(0.86, 0.70, 0.55, 0)
const DARK := Color(0.14, 0.14, 0.16, 0)
const LEATHER := Color(0.36, 0.25, 0.16, 0)
const STEEL := Color(0.66, 0.68, 0.72, 0)
const GOLD := Color(0.85, 0.66, 0.30, 0)
const WOOD := Color(0.45, 0.33, 0.20, 0)
const PAPER := Color(0.93, 0.89, 0.78, 0)
const HORSE := Color(0.42, 0.28, 0.17, 0)
const HORSE2 := Color(0.22, 0.15, 0.10, 0)


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
		k.box(Vector3(0, 0.24, z), Vector3(0.13, 0.48, 0.12), DARK)
		k.box(Vector3(0.03, 0.03, z), Vector3(0.2, 0.06, 0.12), LEATHER)
	k.box(Vector3(0, 0.55, 0), Vector3(0.24, 0.18, 0.36), DARK if rogue else team(0.78))
	k.box(Vector3(0, 0.79, 0), Vector3(0.22, 0.38, 0.34), DARK if rogue else team())
	k.box(Vector3(0, 0.63, 0), Vector3(0.25, 0.05, 0.37), team(0.9) if rogue else LEATHER)
	for z in [-0.215, 0.215]:
		k.box(Vector3(0.02, 0.78, z), Vector3(0.1, 0.36, 0.09), DARK if rogue else team(0.85))
	k.sphere(Vector3(0, 1.08, 0), 0.12, SKIN, 6, 4)
	match tag:
		"창병":
			k.cone(Vector3(0, 1.1, 0), Vector3(0, 1.36, 0), 0.155, STEEL, 7)
			k.box(Vector3(0, 1.12, 0), Vector3(0.27, 0.04, 0.3), STEEL)
			# 왼팔 방패
			k.box(Vector3(0.14, 0.78, -0.27), Vector3(0.05, 0.5, 0.34), team(0.6))
			k.box(Vector3(0.17, 0.78, -0.27), Vector3(0.02, 0.12, 0.12), GOLD)
		"궁병":
			k.cyl(Vector3(0, 1.12, 0), Vector3(0, 1.22, 0), 0.13, LEATHER, 7, 0.1)
			k.cyl(Vector3(-0.15, 0.62, 0.08), Vector3(-0.17, 1.02, 0.05), 0.06, LEATHER, 5)
			# 활 —— 앞으로 든 곡선
			var prev := Vector3.ZERO
			for i in 7:
				var t := lerpf(-1.15, 1.15, i / 6.0)
				var p := Vector3(0.24 + cos(t) * 0.12, 0.85 + sin(t) * 0.5, 0.2)
				if i > 0:
					k.cyl(prev, p, 0.018, WOOD, 4)
				prev = p
		"도적":
			k.sphere(Vector3(-0.01, 1.11, 0), 0.13, DARK, 6, 3, Vector3(1, 0.9, 1))
			k.box(Vector3(0.1, 1.06, 0), Vector3(0.05, 0.05, 0.25), team(0.9))


static func _robe(k: MeshKit, tag: String) -> void:
	k.cyl(Vector3(0, 0.0, 0), Vector3(0, 0.98, 0), 0.3, team(), 8, 0.17)
	k.cyl(Vector3(0, 0.02, 0), Vector3(0, 0.12, 0), 0.305, team(0.6), 8, 0.3, false)
	k.box(Vector3(0.0, 0.62, 0), Vector3(0.3, 0.06, 0.4), PAPER)
	for z in [-0.22, 0.22]:
		k.cyl(Vector3(0, 0.95, z), Vector3(0.1, 0.62, z * 1.15), 0.075, team(0.8), 5, 0.11)
	k.box(Vector3(0.05, 0.96, 0), Vector3(0.16, 0.05, 0.22), PAPER)
	k.sphere(Vector3(0, 1.12, 0), 0.12, SKIN, 6, 4)
	match tag:
		"책사":
			k.box(Vector3(0, 1.32, 0), Vector3(0.15, 0.2, 0.15), DARK)
			k.box(Vector3(0, 1.23, 0), Vector3(0.36, 0.025, 0.36), DARK)
			k.tri(Vector3(0.22, 0.66, 0.2), Vector3(0.42, 0.98, 0.12), Vector3(0.46, 0.8, 0.34), PAPER, Vector3(0.3, 0.7, 0))
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
			k.cyl(Vector3(0.24, 0.7, 0.06), Vector3(0.24, 0.7, 0.34), 0.045, PAPER, 6)


static func _horse(k: MeshKit) -> void:
	for p in [Vector3(-0.55, 0, -0.15), Vector3(-0.55, 0, 0.15), Vector3(0.5, 0, -0.15), Vector3(0.5, 0, 0.15)]:
		k.cyl(p + Vector3(0, 0.95, 0), p + Vector3(0, 0.02, 0), 0.065, HORSE2, 5, 0.045)
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
		k.box(Vector3(0.02, 1.72, z), Vector3(0.1, 0.34, 0.08), team(0.85))
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
