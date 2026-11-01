class_name MeshKit
extends RefCounted
## 모델을 코드로 쌓는 도구 (lathe · blob · limb 는 매끈하게) —— 상자·원기둥·원뿔·구를 이어 붙여 하나의 메시로 굽는다.
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
var detail := 1.0             # 매끈한 도형의 둘레 분할 배율 —— 병사(1,000명 넘게 그린다)는 낮추고 장수는 1


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


# ───────── 매끈한 도형 (10/31 사용자: 로우폴리보다 세련되게) —— 정점마다 법선을 주어 면이 각지지 않는다 ─────────

func _vtx(p: Vector3, nn: Vector3, col: Color) -> void:
	v.append(p)
	n.append(nn.normalized())
	c.append(col)
	uv.append(Vector2(part, 0))
	uv2.append(pivot)


## 매끈한 사각 면 하나 (꼭짓점마다 법선)
func _squad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, na: Vector3, nb: Vector3, nd: Vector3, ne: Vector3, ca: Color, cb: Color) -> void:
	# 바깥(법선 쪽)에서 볼 때 반시계가 되게 감는다
	var face := (b - a).cross(d - a)
	if face.dot(na + nb + nd + ne) < 0:
		_vtx(a, na, ca); _vtx(d, nd, cb); _vtx(b, nb, ca)
		_vtx(a, na, ca); _vtx(e, ne, cb); _vtx(d, nd, cb)
	else:
		_vtx(a, na, ca); _vtx(b, nb, ca); _vtx(d, nd, cb)
		_vtx(a, na, ca); _vtx(d, nd, cb); _vtx(e, ne, cb)


## 돌림 도형 —— prof: [Vector2(반지름, 높이)] 아래에서 위로. 축은 center 에서 +Y (basis 로 돌린다).
## cols: 고리마다 색 (모자라면 마지막 색) —— 미늘 갑옷 띠 · 도포 단 · 투구 테. squash: 단면을 x · z 로 눌러 납작하게.
## 위 · 아래 끝이 반지름 0 이 아니면 뚜껑을 닫는다.
func lathe(center: Vector3, prof: Array, cols: Array, seg := 12, squash := Vector2.ONE, basis := Basis()) -> void:
	seg = maxi(4, roundi(seg * detail))
	var rings := []
	var norms := []
	var nb := basis.inverse().transposed()      # 늘인 도형의 법선은 역전치로 돌린다 (그냥 돌리면 명암이 얼룩진다)
	for i in prof.size():
		var p: Vector2 = prof[i]
		var prv: Vector2 = prof[maxi(0, i - 1)]
		var nxt: Vector2 = prof[mini(prof.size() - 1, i + 1)]
		var tang := (nxt - prv).normalized()
		var pn := Vector2(tang.y, -tang.x)          # 단면 법선 (바깥 · 위아래)
		var row := []
		var nrow := []
		for j in seg + 1:
			var t := TAU * j / seg
			var dir := Vector3(cos(t) * squash.x, 0, sin(t) * squash.y)
			row.append(center + basis * (dir * p.x + Vector3(0, p.y, 0)))
			nrow.append((nb * (Vector3(cos(t) / maxf(0.01, squash.x), 0, sin(t) / maxf(0.01, squash.y)).normalized() * pn.x + Vector3(0, pn.y, 0))).normalized())
		rings.append(row)
		norms.append(nrow)
	for i in prof.size() - 1:
		var ca: Color = cols[mini(i, cols.size() - 1)]
		var cb: Color = cols[mini(i, cols.size() - 1)]
		for j in seg:
			_squad(rings[i][j], rings[i][j + 1], rings[i + 1][j + 1], rings[i + 1][j],
				norms[i][j], norms[i][j + 1], norms[i + 1][j + 1], norms[i + 1][j], ca, cb)
	for end in [0, prof.size() - 1]:
		var p: Vector2 = prof[end]
		if p.x > 0.002:
			var cc: Color = cols[mini(end, cols.size() - 1)]
			var ctr := center + basis * Vector3(0, p.y, 0)
			var up := (nb * Vector3(0, 1 if end > 0 else -1, 0)).normalized()
			for j in seg:
				var a: Vector3 = rings[end][j]
				var b: Vector3 = rings[end][j + 1]
				if (b - a).cross(ctr - a).dot(up) > 0:
					_vtx(a, up, cc); _vtx(b, up, cc); _vtx(ctr, up, cc)
				else:
					_vtx(a, up, cc); _vtx(ctr, up, cc); _vtx(b, up, cc)


## 매끈한 덩어리 (타원체) —— radii 로 늘이고 basis 로 돌린다
func blob(center: Vector3, radii: Vector3, col: Color, seg := 10, rings := 7, basis := Basis()) -> void:
	var prof := []
	rings = maxi(3, roundi(rings * (0.5 + detail * 0.5)))
	for i in rings + 1:
		var phi := PI * float(i) / rings
		prof.append(Vector2(sin(phi), -cos(phi)))
	var b2 := basis * Basis.from_scale(radii)
	lathe(center, prof, [col], seg, Vector2.ONE, b2)


## 팔다리 —— a 에서 b 로 가늘어지는 둥근 막대 (양 끝이 반구)
func limb(a: Vector3, b: Vector3, r1: float, r2: float, col: Color, seg := 8) -> void:
	var ax := b - a
	var ln := ax.length()
	if ln < 0.0001:
		return
	var y := ax / ln
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var bs := Basis(x, y, z)
	var prof := []
	var cap := 3 if detail >= 0.9 else 2       # 끝 반구의 단 수
	for i in cap + 1:
		var t := PI * 0.5 * (1.0 - float(i) / cap)
		prof.append(Vector2(cos(t) * r1, -sin(t) * r1))
	for i in range(1, cap + 1):
		var t := PI * 0.5 * float(i) / cap
		prof.append(Vector2(cos(t) * r2, ln + sin(t) * r2))
	prof[0] = Vector2(0, -r1)
	prof[prof.size() - 1] = Vector2(0, ln + r2)
	lathe(a, prof, [col], seg, Vector2.ONE, bs)


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
