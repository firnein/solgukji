extends Node
## 병사 모델 굽기 (10/31 사용자: 무료 3D 에셋) —— KayKit 캐릭터(CC0, assets_src/kaykit)의 뼈대 애니메이션을
## 프레임마다 정점 위치로 구워 텍스처(VAT)에 담는다. 전장은 병사 1,000명 넘게 한 번에 그리므로(MultiMesh) 뼈대를 돌릴 수 없다.
## 실행: godot --headless --path . res://tests/bake_vat.tscn [-- --tags=창병]
## 결과: assets/models/vat/<병종>_mesh.res (메시) · _pos.res · _nrm.res (Image, 가로 = 정점 번호, 세로 = 프레임) · <병종>.json (동작 표)
## 메시는 +X 를 보고 발끝이 원점, 키 HEIGHT. 정점 색 알파 1 = 세력색으로 칠할 곳(팔레트의 빨강 칸 · 붙인 투구 술 제외).

const OUT := "res://assets/models/vat/"
const HEIGHT := 1.45
## 병종 -> 원본 · 쓸 몸 조각 · 붙일 것 · 동작
const KIT := {
	# Mixamo (10/31 사용자가 받음 —— assets_src/mixamo/<병종>/character.fbx + 동작 fbx, 원본은 깃 · APK 제외)
	"창병": {"mixamo": "창병", "weapon": "spear", "target_tris": 1600, "dye": 0.55, "bright": 1.9,
		"clips": [["idle", "idle", 6, true], ["walk", "walk", 10, true], ["attack", "attack", 8, false],
			["hit", "hit", 5, false], ["death", "death", 8, false], ["cheer", "cheer", 6, true]]},
	"창병_kaykit": {"src": "Knight", "parts": ["Knight_Body", "Knight_Head", "Knight_ArmLeft", "Knight_ArmRight", "Knight_LegLeft", "Knight_LegRight"],
		"rigid": ["Knight_Cape", "Round_Shield"], "helmet": "steel", "weapon": "spear",
		"clips": [["idle", "Idle", 4, true], ["walk", "Walking_A", 8, true], ["attack", "1H_Melee_Attack_Stab", 6, false],
			["hit", "Hit_A", 4, false], ["death", "Death_A", 6, false], ["cheer", "Cheer", 4, true]]},
}


func _ready() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for tag in str(a.get("tags", ",".join(KIT.keys()))).split(","):
		await _bake(tag, KIT[tag])
	get_tree().quit()


func _bake(tag: String, kit: Dictionary) -> void:
	var mx: String = kit.get("mixamo", "")
	var ch: Node3D
	var tex: Image
	var pieces := []          # [{arrays, kind: "skin" | "bone", mi, bone}]
	if mx != "":
		ch = (load("res://assets_src/mixamo/%s/character.fbx" % mx) as PackedScene).instantiate()
	else:
		ch = (load("res://assets_src/kaykit/%s.glb" % kit.src) as PackedScene).instantiate()
	add_child(ch)
	var sk: Skeleton3D = ch.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = ch.find_children("*", "AnimationPlayer", true, false)[0]
	if mx != "":
		# 동작 fbx 마다 애니메이션 하나 —— 인물의 플레이어에 "mx/<이름>" 으로 넣는다 (뼈 이름이 같다)
		var lib := AnimationLibrary.new()
		for clip in kit.clips:
			var a: Node = (load("res://assets_src/mixamo/%s/%s.fbx" % [mx, clip[1]]) as PackedScene).instantiate()
			var aap: AnimationPlayer = a.find_children("*", "AnimationPlayer", true, false)[0]
			var an: Animation = aap.get_animation(aap.get_animation_list()[0]).duplicate()
			an.loop_mode = Animation.LOOP_NONE
			lib.add_animation(clip[1], an)
			a.free()
		ap.add_animation_library("mx", lib)
		kit = kit.duplicate(true)
		for clip in kit.clips:
			clip[1] = "mx/" + clip[1]
		for mi in sk.find_children("*", "MeshInstance3D", true, false):
			pieces.append({"a": mi.mesh.surface_get_arrays(0), "kind": "skin", "mi": mi})
			if tex == null:
				var mat = mi.get_active_material(0)
				if mat is BaseMaterial3D and mat.albedo_texture:
					tex = mat.albedo_texture.get_image()
		if tex == null:
			tex = Image.create(4, 4, false, Image.FORMAT_RGBA8)
			tex.fill(Color(0.6, 0.6, 0.6))
	else:
		tex = (load("res://assets_src/kaykit/%s_texture.png" % kit.src.to_lower()) as Texture2D).get_image()
	tex.decompress()
	# 쓸 조각 —— 스킨 메시 · 뼈에 붙은 단단한 조각 · 우리가 붙이는 투구 · 무기
	for n in kit.get("parts", []):
		var mi: MeshInstance3D = _mesh(ch, n)
		pieces.append({"a": mi.mesh.surface_get_arrays(0), "kind": "skin", "mi": mi})
	for n in kit.get("rigid", []):
		var mi: MeshInstance3D = _mesh(ch, n)
		var ba: BoneAttachment3D = mi.get_parent()
		pieces.append({"a": mi.mesh.surface_get_arrays(0), "kind": "bone", "bone": sk.find_bone(ba.bone_name), "local": mi.transform})
	# 키를 재고(서 있기 첫 프레임) 우리 쪽 붙이는 것의 크기를 맞춘다
	ap.play(kit.clips[0][1])
	ap.seek(0.0, true)
	var lo := INF
	var hi := -INF
	for p in pieces:
		if p.kind == "skin":
			for v in _pose(p, sk):
				lo = minf(lo, v.y)
				hi = maxf(hi, v.y)
	var sc := HEIGHT / (hi - lo)
	var inv := 1.0 / sc
	if kit.get("helmet", "") != "":
		# 원래 투구 자리에 우리 투구를 씌운다 (원래 투구 메시의 상자 —— 머리 뼈 기준)
		var hm: MeshInstance3D = _mesh(ch, kit.src + "_Helmet")
		var hb: AABB = hm.transform * hm.get_aabb()
		pieces.append({"a": _arrays(_helmet(hb)), "kind": "bone", "bone": sk.find_bone("head"), "local": Transform3D(), "keep_color": true})
	if kit.get("weapon", "") == "spear":
		var m := Models.spear()
		var hand := sk.find_bone("handslot.r") if mx == "" else sk.find_bone("mixamorig_RightHand")
		pieces.append({"a": _scaled(m.surface_get_arrays(0), inv), "kind": "bone", "bone": hand, "local": Transform3D(Basis(), Vector3(0, -0.5 * inv, 0)), "keep_color": true})     # 창 자루가 손 뼈의 +Y 로 (칼과 같은 방향)
	# 정점 묶기 (조각 차례대로) —— UV · 색(알파 = 세력색)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()     # x 1 = 텍스처 색을 쓴다 (KayKit 조각), 0 = 정점 색 (우리 조각)
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for p in pieces:
		var base := verts.size()
		var pv: PackedVector3Array = p.a[Mesh.ARRAY_VERTEX]
		var puv = p.a[Mesh.ARRAY_TEX_UV]
		var pc = p.a[Mesh.ARRAY_COLOR]
		for i in pv.size():
			verts.append(pv[i])
			var uv: Vector2 = puv[i] if puv else Vector2.ZERO
			uvs.append(uv)
			if p.get("keep_color", false) and pc:
				cols.append(pc[i])              # 우리 메시: 정점 색 그대로 (알파 = 세력색)
				uv2s.append(Vector2.ZERO)
			else:
				uv2s.append(Vector2(1, 0))
				var t := tex.get_pixelv(Vector2i(clampi(int(uv.x * tex.get_width()), 0, tex.get_width() - 1), clampi(int(uv.y * tex.get_height()), 0, tex.get_height() - 1)))
				var red := t.r > 0.55 and t.r > t.g * 1.7 and t.r > t.b * 1.7
				# Mixamo 인물은 빨간 칸이 없다 —— 갑옷 전체를 진영색으로 반쯤 물들인다 (kit.dye)
				cols.append(Color(1, 1, 1, float(kit.get("dye", 1.0 if red else 0.0)) if mx != "" else (1.0 if red else 0.0)))
		var pi = p.a[Mesh.ARRAY_INDEX]
		if pi:
			for j in pi:
				idx.append(base + j)
		else:
			for j in pv.size():
				idx.append(base + j)
	# 정점 줄이기 (Mixamo 인물은 정점 9,000 넘게 —— 병사 2,000명을 그리려면 줄인다). 쓰는 정점만 남긴다
	var keep_v := PackedInt32Array()
	if kit.has("target_tris"):
		var st := SurfaceTool.new()
		var ra := []
		ra.resize(Mesh.ARRAY_MAX)
		ra[Mesh.ARRAY_VERTEX] = verts
		ra[Mesh.ARRAY_INDEX] = idx
		st.create_from_arrays(ra)
		var lod: PackedInt32Array = st.generate_lod(30.0, int(kit.target_tris) * 3)
		if lod.size() >= 3:
			idx = lod
	var remap := {}
	var new_idx := PackedInt32Array()
	for j in idx:
		if not remap.has(j):
			remap[j] = keep_v.size()
			keep_v.append(j)
		new_idx.append(remap[j])
	idx = new_idx
	var uvs2 := PackedVector2Array()
	var uv2s2 := PackedVector2Array()
	var cols2 := PackedColorArray()
	for j in keep_v:
		uvs2.append(uvs[j])
		uv2s2.append(uv2s[j])
		cols2.append(cols[j])
	uvs = uvs2
	uv2s = uv2s2
	cols = cols2
	# 프레임 굽기
	var rot := Basis(Vector3.UP, PI * 0.5)       # KayKit 은 +Z 를 본다 → +X
	var frames_pos := []
	var frames_nrm := []
	var table := {}
	for clip in kit.clips:
		var anim: Animation = ap.get_animation(clip[1])
		var n: int = clip[2]
		table[clip[0]] = [frames_pos.size(), n, clip[3]]
		for f in n:
			var t: float = anim.length * f / (n if clip[3] else maxi(1, n - 1))
			ap.play(clip[1])
			ap.seek(minf(t, anim.length - 0.001), true)
			var pos := PackedVector3Array()
			var nrm := PackedVector3Array()
			for p in pieces:
				var pp := _pose(p, sk)
				var pn := _pose(p, sk, true)
				for i in pp.size():
					pos.append(rot * Vector3(pp[i].x, pp[i].y - lo, pp[i].z) * sc)
					nrm.append((rot * pn[i]).normalized())
			# 줄인 정점만
			var pos2 := PackedVector3Array()
			var nrm2 := PackedVector3Array()
			for j in keep_v:
				pos2.append(pos[j])
				nrm2.append(nrm[j])
			pos = pos2
			nrm = nrm2
			frames_pos.append(pos)
			frames_nrm.append(nrm)
	var nv := keep_v.size()          # 줄이고 남긴 정점 수
	var img_p := Image.create(nv, frames_pos.size(), false, Image.FORMAT_RGBAF)
	var img_n := Image.create(nv, frames_pos.size(), false, Image.FORMAT_RGBAF)
	for r in frames_pos.size():
		for i in nv:
			var v: Vector3 = frames_pos[r][i]
			var nn: Vector3 = frames_nrm[r][i]
			img_p.set_pixel(i, r, Color(v.x, v.y, v.z, 1))
			img_n.set_pixel(i, r, Color(nn.x, nn.y, nn.z, 0))
	# 메시 —— 자리는 서 있기 첫 프레임 (그림자 · 가림 계산용 상자), 정점 번호가 VAT 가로
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = frames_pos[0]
	arr[Mesh.ARRAY_NORMAL] = frames_nrm[0]
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = AABB(Vector3(-1.2, -0.2, -1.2), Vector3(2.4, 2.6, 2.4))     # 동작으로 벗어나는 만큼 넉넉히
	ResourceSaver.save(mesh, OUT + tag + "_mesh.res")
	ResourceSaver.save(img_p, OUT + tag + "_pos.res")
	ResourceSaver.save(img_n, OUT + tag + "_nrm.res")
	var f := FileAccess.open(OUT + tag + ".json", FileAccess.WRITE)
	# 팔레트 텍스처는 게임 폴더로 옮긴다 (assets_src 는 APK 에서 뺀다)
	var pal: String = OUT + (tag + "_texture.png" if mx != "" else kit.src.to_lower() + "_texture.png")
	if mx != "":
		var small := tex.duplicate()
		if small.get_width() > 1024:
			small.resize(1024, 1024 * small.get_height() / small.get_width())
		small.save_png(ProjectSettings.globalize_path(pal))
	else:
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://assets_src/kaykit/%s_texture.png" % kit.src.to_lower()), ProjectSettings.globalize_path(pal))
	f.store_string(JSON.stringify({"src": kit.get("src", mx), "verts": nv, "tris": idx.size() / 3, "frames": frames_pos.size(), "clips": table, "texture": pal, "bright": kit.get("bright", 1.0)}, "\t"))
	print("구움 %s: 정점 %d · 삼각형 %d · 프레임 %d" % [tag, nv, idx.size() / 3, frames_pos.size()])
	ch.queue_free()
	await get_tree().process_frame


## 조각의 지금 자세 정점 (캐릭터 기준). normal 이면 법선
func _pose(p: Dictionary, sk: Skeleton3D, normal := false) -> PackedVector3Array:
	var out := PackedVector3Array()
	var src: PackedVector3Array = p.a[Mesh.ARRAY_NORMAL if normal else Mesh.ARRAY_VERTEX]
	var to_char: Transform3D = (sk.get_parent() as Node3D).transform * sk.transform       # Rig · Skeleton3D 의 자리 (캐릭터 뿌리 기준)
	if p.kind == "bone":
		var xf: Transform3D = to_char * sk.get_bone_global_pose(p.bone) * p.local
		for v in src:
			out.append(xf.basis * v if normal else xf * v)
		return out
	var mi: MeshInstance3D = p.mi
	var skin := mi.skin
	var mats := []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = sk.find_bone(skin.get_bind_name(b))
		mats.append(to_char * sk.get_bone_global_pose(bone) * skin.get_bind_pose(b))
	var bones: PackedInt32Array = p.a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = p.a[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / src.size()
	for i in src.size():
		var acc := Vector3.ZERO
		for k in per:
			var w := weights[i * per + k]
			if w <= 0.0:
				continue
			var m: Transform3D = mats[bones[i * per + k]]
			acc += (m.basis * src[i] if normal else m * src[i]) * w
		out.append(acc)
	return out


## 둥근 쇠 투구 + 붉은 술 —— 원래 투구 상자 hb(머리 뼈 기준)에 맞춘다
func _helmet(hb: AABB) -> ArrayMesh:
	var k := MeshKit.new()
	k.detail = 0.6
	var c := hb.get_center()
	var r := maxf(hb.size.x, hb.size.z) * 0.5
	var s := r / 0.17
	var y0 := hb.position.y + hb.size.y * 0.42
	var o := Vector3(c.x, y0, c.z)
	k.lathe(o, [Vector2(0.17 * s, 0), Vector2(0.162 * s, 0.07 * s), Vector2(0.14 * s, 0.14 * s), Vector2(0.1 * s, 0.2 * s), Vector2(0.045 * s, 0.24 * s), Vector2(0.0, 0.255 * s)], [Models.STEEL.darkened(0.15), Models.STEEL], 14)
	k.lathe(o - Vector3(0, 0.01 * s, 0), [Vector2(0.162 * s, 0), Vector2(0.19 * s, 0.015 * s), Vector2(0.185 * s, 0.03 * s)], [Models.GOLD], 14)
	k.limb(o + Vector3(0, 0.24 * s, 0), o + Vector3(0, 0.36 * s, -0.08 * s), 0.014 * s, 0.04 * s, Models.RED, 6)
	k.blob(o + Vector3(0, 0.38 * s, -0.11 * s), Vector3(0.04 * s, 0.04 * s, 0.07 * s), Models.RED, 8, 5)
	return k.mesh()


## 이름으로 메시 찾기 (뼈 붙이개가 같은 이름이라 종류로 거른다)
func _mesh(root: Node, n: String) -> MeshInstance3D:
	for m in root.find_children(n, "MeshInstance3D", true, false):
		return m
	return null


func _arrays(m: ArrayMesh) -> Array:
	return m.surface_get_arrays(0)


func _scaled(a: Array, s: float) -> Array:
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i] *= s
	a[Mesh.ARRAY_VERTEX] = v
	return a
