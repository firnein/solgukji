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
	"창병_mixamo": {"mixamo": "창병", "weapon": "spear", "target_tris": 1600, "dye": 0.55, "bright": 1.9,
		"clips": [["idle", "idle", 6, true], ["walk", "walk", 10, true], ["attack", "attack", 8, false],
			["hit", "hit", 5, false], ["death", "death", 8, false], ["cheer", "cheer", 6, true]]},
	# Quaternius "Ultimate Animated Animal Pack" 말 (CC0, assets_src/quaternius/Horse.glb —— poly.pizza 에서 받음, 11/4 저녁 사용자: 무료 모델 에셋)
	# 재질이 색만 있는 모델 —— 정점 색으로 굽고, 코드 기수(Models._rider) · 안장을 등뼈(Torso2)에 붙인다. GPU 병사 셰이더(soldier_gpu)의 VAT 모드로 그린다
	"기병": {"glb": "res://assets_src/quaternius/Horse.glb", "height": 2.05, "yaw": PI * 0.5, "target_tris": 1100,
		"rider_bone": "Torso2", "rider_dy": -0.12, "ride_scale": 1.0, "color_mul": 0.8,
		"clips": [["idle", "Idle", 6, true], ["walk", "Gallop", 8, true], ["attack", "Attack_Headbutt", 6, false],
			["hit", "Idle_HitReact_Left", 4, false], ["death", "Death", 6, false], ["cheer", "Idle_2", 6, true]]},
	# ── 11/4 저녁 사용자 "2 적용": 보병 몸통을 KayKit(CC0) 사람으로 —— GPU 병사 셰이더 VAT 모드(soldier_gpu use_vat).
	# bake_colors: 팔레트 색을 정점 색으로 굽고 UV 는 비운다(셰이더가 COLOR 만 쓴다). 투구 · 삿갓 · 관 · 무기는 코드 조각을 뼈에 붙인다
	# (고대 중국풍: 둥근 쇠투구+붉은 술, 삿갓, 관모). 책사 굽기 하나를 책사 · 모사 · 술사 · 유생이 같이 쓴다 (War3D.GPU_VAT_MAP)
	"창병": {"src": "Knight", "parts": ["Knight_Body", "Knight_Head", "Knight_ArmLeft", "Knight_ArmRight", "Knight_LegLeft", "Knight_LegRight"],
		"helmet": "steel", "weapon": "spear", "bake_colors": true, "dye_rest": 0.75, "target_tris": 1500,
		"clips": [["idle", "Idle", 4, true], ["walk", "Walking_A", 8, true], ["attack", "1H_Melee_Attack_Stab", 6, false],
			["hit", "Hit_A", 4, false], ["death", "Death_A", 6, false], ["cheer", "Cheer", 4, true]]},
	"도적": {"src": "Rogue_Hooded", "tex": "rogue", "parts": ["Rogue_Body", "Rogue_Head_Hooded", "Rogue_ArmLeft", "Rogue_ArmRight", "Rogue_LegLeft", "Rogue_LegRight"],
		"weapon": "sword", "bake_colors": true, "dye_rest": 0.65, "target_tris": 1500,
		"clips": [["idle", "Idle", 4, true], ["walk", "Walking_A", 8, true], ["attack", "1H_Melee_Attack_Slice_Diagonal", 6, false],
			["hit", "Hit_A", 4, false], ["death", "Death_A", 6, false], ["cheer", "Cheer", 4, true]]},
	"궁병": {"src": "Rogue", "tex": "rogue", "parts": ["Rogue_Body", "Rogue_Head", "Rogue_ArmLeft", "Rogue_ArmRight", "Rogue_LegLeft", "Rogue_LegRight"],
		"hat": "satgat", "hat_mesh": "Rogue_Head", "weapon": "bow", "bake_colors": true, "dye_rest": 0.65, "target_tris": 1500,
		"clips": [["idle", "Idle", 4, true], ["walk", "Walking_A", 8, true], ["attack", "2H_Ranged_Shoot", 6, false],
			["hit", "Hit_A", 4, false], ["death", "Death_A", 6, false], ["cheer", "Cheer", 4, true]]},
	"책사": {"src": "Mage", "parts": ["Mage_Body", "Mage_Head", "Mage_ArmLeft", "Mage_ArmRight", "Mage_LegLeft", "Mage_LegRight"],
		"hat": "gwan", "hat_mesh": "Mage_Head", "bake_colors": true, "dye_rest": 0.7, "target_tris": 1500,
		"clips": [["idle", "Idle", 4, true], ["walk", "Walking_A", 8, true], ["attack", "Spellcast_Shoot", 6, false],
			["hit", "Hit_A", 4, false], ["death", "Death_A", 6, false], ["cheer", "Cheer", 4, true]]},
	# 장수 군마 —— 기수 없이 안장만 (장수 인형은 코드 모델, War3D 가 같은 자리에 겹쳐 그린다)
	"군마": {"glb": "res://assets_src/quaternius/Horse.glb", "height": 2.25, "yaw": PI * 0.5, "target_tris": 1100, "saddle": false, "color_mul": 0.75,      # 안장은 장수 인형의 다리와 겹쳐 번쩍였다(z-fight) —— 뺀다
		"clips": [["idle", "Idle", 6, true], ["walk", "Gallop", 8, true], ["attack", "Idle", 2, false],
			["hit", "Idle_HitReact_Left", 4, false], ["death", "Death", 6, false], ["cheer", "Idle_2", 6, true]]},
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
	var glb: String = kit.get("glb", "")
	if mx != "":
		ch = (load("res://assets_src/mixamo/%s/character.fbx" % mx) as PackedScene).instantiate()
	elif glb != "":
		ch = (load(glb) as PackedScene).instantiate()
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
	elif glb != "":
		# 재질마다 면이 나뉘어 있고 색만 있다 —— 면마다 조각, 정점 색 = 재질 albedo (알파 0: 진영색 안 입힘)
		tex = Image.create(4, 4, false, Image.FORMAT_RGBA8)
		tex.fill(Color(0.6, 0.6, 0.6))
		for mi in sk.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(s)
				var mat = mi.get_active_material(s)
				var col := Color(0.6, 0.6, 0.6, 0)
				if mat is BaseMaterial3D:
					var cm: float = float(kit.get("color_mul", 1.0))
					col = Color(mat.albedo_color.r * cm, mat.albedo_color.g * cm, mat.albedo_color.b * cm, 0.0)
				var pc := PackedColorArray()
				pc.resize(arr[Mesh.ARRAY_VERTEX].size())
				pc.fill(col)
				arr[Mesh.ARRAY_COLOR] = pc
				arr[Mesh.ARRAY_TEX_UV] = null      # 팔레트 안 씀 (CPU 쓰러짐 셰이더의 부위 번호 0 = 몸통)
				pieces.append({"a": arr, "kind": "skin", "mi": mi, "keep_color": true})
	else:
		tex = (load("res://assets_src/kaykit/%s_texture.png" % kit.get("tex", kit.src.to_lower())) as Texture2D).get_image()
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
	var sc: float = float(kit.get("height", HEIGHT)) / (hi - lo)
	var inv := 1.0 / sc
	if kit.get("helmet", "") != "":
		# 원래 투구 자리에 우리 투구를 씌운다 (원래 투구 메시의 상자 —— 머리 뼈 기준)
		var hm: MeshInstance3D = _mesh(ch, kit.src + "_Helmet")
		var hb: AABB = hm.transform * hm.get_aabb()
		pieces.append({"a": _arrays(_helmet(hb)), "kind": "bone", "bone": sk.find_bone("head"), "local": Transform3D(), "keep_color": true})
	if kit.get("hat", "") != "":
		# 삿갓(궁병) · 관모(책사) —— 머리 조각 상자(머리 뼈 기준)에 맞춘다
		var hm: MeshInstance3D = _mesh(ch, kit.hat_mesh)
		var hb: AABB = hm.get_aabb()      # 스킨 머리 조각의 상자 —— 뼈대(캐릭터) 좌표
		var ha: Array = _arrays(_hat(kit.hat, hb))
		var hinv: Transform3D = sk.get_bone_global_pose(sk.find_bone("head")).affine_inverse()      # 서 있기 첫 프레임 머리 뼈 기준으로
		var hv: PackedVector3Array = ha[Mesh.ARRAY_VERTEX]
		var hn: PackedVector3Array = ha[Mesh.ARRAY_NORMAL]
		for i in hv.size():
			hv[i] = hinv * hv[i]
			hn[i] = (hinv.basis * hn[i]).normalized()
		ha[Mesh.ARRAY_VERTEX] = hv
		ha[Mesh.ARRAY_NORMAL] = hn
		pieces.append({"a": ha, "kind": "bone", "bone": sk.find_bone("head"), "local": Transform3D(), "keep_color": true})
	var wpn: String = kit.get("weapon", "")
	if wpn != "":
		var m: ArrayMesh
		var off := 0.0
		match wpn:
			"spear":
				m = Models.spear()
				off = -0.5      # 창 자루가 손 뼈의 +Y 로 (칼과 같은 방향)
			"sword":
				m = Models.sword()
			"bow":
				m = Models.bow()
		var hand := sk.find_bone("handslot.l" if wpn == "bow" else "handslot.r") if mx == "" else sk.find_bone("mixamorig_RightHand")
		pieces.append({"a": _scaled(m.surface_get_arrays(0), inv), "kind": "bone", "bone": hand, "local": Transform3D(Basis(), Vector3(0, off * inv, 0)), "keep_color": true})
	if kit.get("saddle", false):
		var sk2 := MeshKit.new()
		sk2.box(Vector3(-0.05, 1.56, 0), Vector3(0.6, 0.05, 0.56), Models.team(0.7))
		sk2.box(Vector3(-0.05, 1.4, 0), Vector3(0.55, 0.3, 0.52), Models.team(0.55))
		_attach_design(pieces, sk2.mesh().surface_get_arrays(0), sk, ap, kit, sk.find_bone("Torso2"), sc, lo)
	if kit.has("rider_bone"):
		# 코드 기수 + 안장 (Models._rider · _horse 의 안장) —— 완성 좌표(미터, +X 앞, 발끝 원점)로 그려 둔 것을
		# 서 있기 첫 프레임의 등뼈 자세로 역변환해 붙인다. 그러면 달릴 때 등을 따라 들썩인다
		var rk := MeshKit.new()
		var dy: float = float(kit.get("rider_dy", 0.0))
		var rs: float = float(kit.get("ride_scale", 1.0))
		rk.box(Vector3(-0.05, 1.46 + dy, 0), Vector3(0.55, 0.05, 0.52) * rs, Models.team(0.7))
		rk.box(Vector3(-0.05, 1.3 + dy, 0), Vector3(0.5, 0.3, 0.48) * rs, Models.team(0.55))
		Models._rider(rk)
		var ra: Array = rk.mesh().surface_get_arrays(0)
		var rv: PackedVector3Array = ra[Mesh.ARRAY_VERTEX]
		var rn: PackedVector3Array = ra[Mesh.ARRAY_NORMAL]
		var bone_i := sk.find_bone(kit.rider_bone)
		ap.play(kit.clips[0][1])
		ap.seek(0.0, true)
		var to_char: Transform3D = (sk.get_parent() as Node3D).transform * sk.transform
		var xf0: Transform3D = to_char * sk.get_bone_global_pose(bone_i)
		var rot0 := Basis(Vector3.UP, float(kit.get("yaw", PI * 0.5)))
		var inv0 := xf0.affine_inverse()
		for i in rv.size():
			var vv: Vector3 = rv[i]
			# 완성 좌표 → 굽기 전 좌표: rot⁻¹ · /sc · +lo → 뼈 로컬
			var pre := rot0.inverse() * vv / sc + Vector3(0, lo, 0)
			rv[i] = inv0 * pre
			rn[i] = (inv0.basis * (rot0.inverse() * rn[i])).normalized()
		ra[Mesh.ARRAY_VERTEX] = rv
		ra[Mesh.ARRAY_NORMAL] = rn
		ra[Mesh.ARRAY_TEX_UV] = null
		ra[Mesh.ARRAY_TEX_UV2] = null
		pieces.append({"a": ra, "kind": "bone", "bone": bone_i, "local": Transform3D(), "keep_color": true})
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
				var t := tex.get_pixelv(Vector2i(clampi(int(uv.x * tex.get_width()), 0, tex.get_width() - 1), clampi(int(uv.y * tex.get_height()), 0, tex.get_height() - 1)))
				var red := t.r > 0.55 and t.r > t.g * 1.7 and t.r > t.b * 1.7
				var dye_a: float = float(kit.get("dye", 1.0 if red else 0.0)) if mx != "" else (1.0 if red else 0.0)
				if kit.get("bake_colors", false):
					# GPU VAT: 팔레트 색을 정점 색으로 (UV 는 비운다 —— soldier_gpu 는 COLOR 만 쓰고, CPU 쓰러짐 셰이더의 부위 번호 0)
					uv2s.append(Vector2.ZERO)
					uvs[uvs.size() - 1] = Vector2.ZERO
					# 빨간 칸(옷)은 진영색으로, 나머지(갑옷 · 두건 · 로브)도 kit.dye_rest 만큼 물들인다 —— 멀리서 아군 · 적이 갈리게 (11/4 저녁: 은빛 갑옷이 양쪽 다 하얬다)
					cols.append(Color(t.r, t.g, t.b, maxf(dye_a, float(kit.get("dye_rest", 0.0)))))
				else:
					uv2s.append(Vector2(1, 0))
					# Mixamo 인물은 빨간 칸이 없다 —— 갑옷 전체를 진영색으로 반쯤 물들인다 (kit.dye)
					cols.append(Color(1, 1, 1, dye_a))
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
	var rot := Basis(Vector3.UP, float(kit.get("yaw", PI * 0.5)))       # KayKit 은 +Z 를 본다 → +X (kit.yaw 로 바꿀 수 있다)
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
	# 11/4 저녁: 반정밀(RGBAH) —— 2m 안에서 1mm 정밀도면 충분, 파일이 반으로 (기병 2.8MB → 1.4MB)
	var img_p := Image.create(nv, frames_pos.size(), false, Image.FORMAT_RGBAH)
	var img_n := Image.create(nv, frames_pos.size(), false, Image.FORMAT_RGBAH)
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
	var pal: String = OUT + (tag + "_texture.png" if mx != "" else (kit.get("src", "none").to_lower() + "_texture.png"))
	if glb != "" or kit.get("bake_colors", false):
		pal = ""
	elif mx != "":
		var small := tex.duplicate()
		if small.get_width() > 1024:
			small.resize(1024, 1024 * small.get_height() / small.get_width())
		small.save_png(ProjectSettings.globalize_path(pal))
	else:
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://assets_src/kaykit/%s_texture.png" % kit.src.to_lower()), ProjectSettings.globalize_path(pal))
	f.store_string(JSON.stringify({"src": kit.get("src", mx if mx != "" else glb), "verts": nv, "tris": idx.size() / 3, "frames": frames_pos.size(), "clips": table, "texture": pal, "bright": kit.get("bright", 1.0)}, "\t"))
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


## 완성 좌표(미터, +X 앞, 발끝 원점)로 그린 조각을 서 있기 첫 프레임의 뼈 자세로 역변환해 붙인다 —— 그 뼈를 따라 움직인다
func _attach_design(pieces: Array, ra: Array, sk: Skeleton3D, ap: AnimationPlayer, kit: Dictionary, bone_i: int, sc: float, lo: float) -> void:
	var rv: PackedVector3Array = ra[Mesh.ARRAY_VERTEX]
	var rn: PackedVector3Array = ra[Mesh.ARRAY_NORMAL]
	ap.play(kit.clips[0][1])
	ap.seek(0.0, true)
	var to_char: Transform3D = (sk.get_parent() as Node3D).transform * sk.transform
	var inv0: Transform3D = (to_char * sk.get_bone_global_pose(bone_i)).affine_inverse()
	var rot0 := Basis(Vector3.UP, float(kit.get("yaw", PI * 0.5)))
	for i in rv.size():
		rv[i] = inv0 * (rot0.inverse() * rv[i] / sc + Vector3(0, lo, 0))
		rn[i] = (inv0.basis * (rot0.inverse() * rn[i])).normalized()
	ra[Mesh.ARRAY_VERTEX] = rv
	ra[Mesh.ARRAY_NORMAL] = rn
	ra[Mesh.ARRAY_TEX_UV] = null
	ra[Mesh.ARRAY_TEX_UV2] = null
	pieces.append({"a": ra, "kind": "bone", "bone": bone_i, "local": Transform3D(), "keep_color": true})


## 삿갓(satgat) · 관모(gwan) —— 머리 조각 상자 hb(머리 뼈 기준)에 맞춘다
func _hat(kind: String, hb: AABB) -> ArrayMesh:
	var k := MeshKit.new()
	k.detail = 0.6
	var c := hb.get_center()
	var r := maxf(hb.size.x, hb.size.z) * 0.5
	var top := hb.position.y + hb.size.y
	match kind:
		"satgat":
			# 넓은 삿갓 —— 머리 위 낮은 원뿔, 짚색
			var o := Vector3(c.x, top - hb.size.y * 0.2, c.z)
			k.cone(o, o + Vector3(0, r * 0.75, 0), r * 1.45, Color(0.72, 0.6, 0.36, 0.4), 12)      # 알파 0.4: 짚색에 진영색을 조금 (위에서 봐도 아군 · 적이 갈리게)      # 처음 2.2r 은 위에서 보면 원반이 병사를 다 덮었다
			k.cone(o + Vector3(0, -0.01, 0), o + Vector3(0, r * 0.04, 0), r * 1.5, Color(0.5, 0.4, 0.22, 0), 12)
		"gwan":
			# 관모 —— 머리 위 검은 통 + 가로 날개
			var o := Vector3(c.x, top - hb.size.y * 0.15, c.z)
			k.cyl(o, o + Vector3(0, r * 0.85, 0), r * 0.6, Models.DARK, 8, r * 0.5)      # 통은 낮게 (처음 1.3 은 실크해트 같았다)
			k.box(o + Vector3(0, r * 0.85, 0), Vector3(r * 1.7, r * 0.14, r * 0.6), Models.DARK)
			k.cyl(o, o + Vector3(0, r * 0.12, 0), r * 0.95, Models.DARK, 8)
	return k.mesh()


## 둥근 쇠 투구 + 붉은 술 —— 원래 투구 상자 hb(머리 뼈 기준)에 맞춘다
func _helmet(hb: AABB) -> ArrayMesh:
	var k := MeshKit.new()
	k.detail = 0.6
	var c := hb.get_center()
	var r := maxf(hb.size.x, hb.size.z) * 0.5
	var s := r / 0.17
	var y0 := hb.position.y + hb.size.y * 0.42
	var o := Vector3(c.x, y0, c.z)
	k.lathe(o, [Vector2(0.17 * s, 0), Vector2(0.162 * s, 0.07 * s), Vector2(0.14 * s, 0.14 * s), Vector2(0.1 * s, 0.2 * s), Vector2(0.045 * s, 0.24 * s), Vector2(0.0, 0.255 * s)], [Models.team(0.62), Models.team(0.85)], 14)      # 11/4 저녁: 투구를 진영색으로 —— 위에서 보면 투구가 병사의 전부라 은빛이면 아군 · 적이 안 갈렸다
	k.lathe(o - Vector3(0, 0.01 * s, 0), [Vector2(0.162 * s, 0), Vector2(0.19 * s, 0.015 * s), Vector2(0.185 * s, 0.03 * s)], [Models.GOLD], 14)
	# 붉은 술은 뺐다 (11/4 저녁 사용자: "빨간 깔때기") —— 꼭지에 작은 쇠 장식만
	k.lathe(o + Vector3(0, 0.25 * s, 0), [Vector2(0.03 * s, 0), Vector2(0.02 * s, 0.03 * s), Vector2(0.0, 0.045 * s)], [Models.GOLD], 8)
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
