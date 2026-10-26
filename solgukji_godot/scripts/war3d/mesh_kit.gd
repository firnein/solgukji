class_name MeshKit
extends RefCounted
## 로우폴리 모델을 코드로 쌓는 도구 —— 상자·원기둥·원뿔·구를 이어 붙여 하나의 메시로 굽는다.
## 면마다 법선을 직접 계산하고 도형 중심 반대쪽을 향하게 뒤집으므로 감기 순서에 신경 쓰지 않는다.
## 정점 색의 알파는 "세력색 칠할 부분" 표시다 (soldier.gdshader 참고).

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
## 관절 —— 지금부터 쌓는 도형이 어느 부위인지(part)와 그 부위가 도는 축의 자리(pivot: 모델 x, y).
## 셰이더가 UV.x 로 부위를, UV2 로 축을 읽어 팔다리를 흔든다 (soldier.gdshader). 0 = 몸통(안 움직임)
var part := 0
var pivot := Vector2.ZERO
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()
var _parts := false


func joint(p: int, pv := Vector2.ZERO) -> void:
	part = p
	pivot = pv
	if p != 0:
		_parts = true


func tri(a: Vector3, b: Vector3, d: Vector3, col: Color, hint: Vector3) -> void:
	var nn := (b - a).cross(d - a).normalized()
	if nn.dot((a + b + d) / 3.0 - hint) < 0:
		nn = -nn
	for p in [a, b, d]:
		v.append(p)
		n.append(nn)
		c.append(col)
		uv.append(Vector2(part, 0))
		uv2.append(pivot)


func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, col: Color, hint: Vector3) -> void:
	tri(a, b, d, col, hint)
	tri(a, d, e, col, hint)


func box(center: Vector3, size: Vector3, col: Color, basis := Basis()) -> void:
	var h := size / 2
	var p := []
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				p.append(center + basis * Vector3(h.x * sx, h.y * sy, h.z * sz))
	# 꼭짓점 번호: (x,y,z) 부호 → 4x + 2y + z
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], col, center)


## a → b 축의 원기둥. r2 를 주면 원뿔대, 0 이면 원뿔.
func cyl(a: Vector3, b: Vector3, r: float, col: Color, seg := 6, r2 := -1.0, caps := true) -> void:
	if r2 < 0:
		r2 = r
	var ax := (b - a).normalized()
	var u := ax.cross(Vector3.UP if absf(ax.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var w := ax.cross(u)
	var mid := (a + b) / 2
	var ring_a := []
	var ring_b := []
	for i in seg:
		var t := TAU * i / seg
		var dir := u * cos(t) + w * sin(t)
		ring_a.append(a + dir * r)
		ring_b.append(b + dir * r2)
	for i in seg:
		var j := (i + 1) % seg
		if r2 > 0.0001:
			quad(ring_a[i], ring_a[j], ring_b[j], ring_b[i], col, mid)
		else:
			tri(ring_a[i], ring_a[j], b, col, mid)
		if caps:
			tri(a, ring_a[i], ring_a[j], col, mid)
			if r2 > 0.0001:
				tri(b, ring_b[j], ring_b[i], col, mid)


func cone(a: Vector3, b: Vector3, r: float, col: Color, seg := 6) -> void:
	cyl(a, b, r, col, seg, 0.0)


## 낮은 다면체 구. squash 로 납작하게, jitter 로 울퉁불퉁하게(바위) 만든다.
func sphere(center: Vector3, r: float, col: Color, seg := 6, rings := 4, squash := Vector3.ONE, jitter := 0.0, rng: RandomNumberGenerator = null) -> void:
	var pts := []
	for ri in rings + 1:
		var row := []
		var phi := PI * ri / rings
		for si in seg:
			var th := TAU * si / seg
			var p := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			if jitter > 0 and rng and ri > 0 and ri < rings:
				p *= 1.0 + rng.randf_range(-jitter, jitter)
			row.append(center + p * r * squash)
		pts.append(row)
	for ri in rings:
		for si in seg:
			var sj := (si + 1) % seg
			var a: Vector3 = pts[ri][si]
			var b: Vector3 = pts[ri][sj]
			var d: Vector3 = pts[ri + 1][sj]
			var e: Vector3 = pts[ri + 1][si]
			if ri == 0:
				tri(a, d, e, col, center)
			elif ri == rings - 1:
				tri(a, b, e, col, center)
			else:
				quad(a, b, d, e, col, center)


func mesh() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	if _parts:
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
