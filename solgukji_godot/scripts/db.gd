extends Node
## 게임 데이터 —— data/game.json 은 HTML 프로토타입에서 tools/scripts/extract.py 로 뽑은 것이다.
## 원본의 상수 이름(CARDDEF, FORM, AFF …)을 그대로 따라 이식 대조가 쉽도록 했다.

const PAL := {
	"ink": Color("#131A2B"), "ink2": Color("#1B2338"), "ink3": Color("#242E49"), "ink4": Color("#33405F"),
	"paper": Color("#E9E3D3"), "bamboo": Color("#C6AC7C"), "bamboo_dim": Color("#8D7B5C"),
	"seal": Color("#BE4A3C"), "jade": Color("#4F9080"), "gold": Color("#D9A64B"),
}

var D: Dictionary
var K: Dictionary
var C := {}              # 카드 id -> 카드
var IT := {}             # 아이템 id -> 아이템
var ITEM_BY_NAME := {}
var RECOF := {}          # 결과 id -> 재료 배열
var TIER := {}           # 등급(int) -> {n, c, lo, hi}
var FORM := {}           # 진형 -> {n, sil, mask, slots, grid}
var BASE: Array = []     # 기본패 8종
var POOLS := {}          # 성향 -> 등급 -> 카드 id 배열
var ICON := {}           # 병종 -> Texture2D (흰색, modulate 로 칠한다)

var font_display: Font
var font_body: Font
var font_bold: Font

var _portrait_cache := {}
var _portrait_used := {}     # 배경이 투명한 그림 -> 실제로 그려진 영역 (Rect2)
var _portrait_pick := {}     # 카드 key -> 실제로 쓰는 그림 경로 (등급 그림이 없으면 기본 그림)
var ULT: Dictionary          # data/ultimates.json —— 불멸·신화 고유기
var PSV: Dictionary          # data/passives.json —— 개인·단체 특기

const PHYS_TAGS := ["창병", "기병", "궁병", "도적"]
const INT_TAGS := ["책사", "유생", "술사", "모사"]
const STYLE_FORM := {"물리": "hagik", "지략": "bangwon", "균형": "eorin"}


func _ready() -> void:
	_load()


func _load() -> void:
	var f := FileAccess.open("res://data/game.json", FileAccess.READ)
	D = JSON.parse_string(f.get_as_text())
	K = D.K
	_build_fonts()

	for r in D.CARDDEF:
		C[r[0]] = {"id": r[0], "name": r[1], "tier": int(r[2]), "tag": r[3], "fac": r[4],
			"atk": float(r[5]), "def": float(r[6]), "int": float(r[7]), "res": float(r[8]),
			"spd": float(r[9]), "tr": int(r[10]), "pv": int(r[11]), "sk": r[12],
			"kind": r[13], "need": r[14]}
	for r in D.RECDEF:
		RECOF[r[0]] = r[1]
	for r in D.ITEMDEF:
		IT[r[0]] = {"id": r[0], "name": r[1], "grade": r[2], "tag": r[3], "pri": r[4],
			"pa": float(r[5]), "sec": r[6], "sa": float(r[7]), "rb": float(r[8]), "use": r[9]}
		ITEM_BY_NAME[r[1]] = r[0]

	for t in D.TIER:
		TIER[int(t)] = {"n": D.TIER[t].n, "c": Color(D.TIER[t].c)}
	for t in TIER:
		var pvs := []
		for k in C:
			if C[k].tier == t:
				pvs.append(C[k].pv)
		TIER[t].lo = pvs.min()
		TIER[t].hi = pvs.max()

	for k in C:
		if C[k].tier == 1:
			BASE.append(k)

	_reskill()
	ULT = JSON.parse_string(FileAccess.open("res://data/ultimates.json", FileAccess.READ).get_as_text())
	PSV = JSON.parse_string(FileAccess.open("res://data/passives.json", FileAccess.READ).get_as_text())
	_build_forms()
	_build_pools()
	_build_icons()


## 원본 reskill() —— CARDDEF 안의 스킬 정의는 버리고 SKILLPOOL 기준으로 다시 물린다. 패시브만 남긴다.
func _reskill() -> void:
	var ids: Array = C.keys()
	ids.sort_custom(func(a, b):
		if C[a].tier != C[b].tier:
			return C[a].tier < C[b].tier
		return a < b)
	var idx := {}
	for k in ids:
		var c: Dictionary = C[k]
		if c.tier < 4:
			c.sk = null
			continue
		var key: String = c.tag + str(c.tier)
		idx[key] = idx.get(key, 0)
		var psv = c.sk.get("psv") if c.sk else null
		c.sk = _build_skill(c.tag, idx[key], c.tier)
		c.sk.psv = psv
		idx[key] += 1


func _build_skill(tag: String, i: int, tier: int) -> Dictionary:
	var pool: Array = D.SKILLPOOL[tag]
	var base: Dictionary = pool[i % pool.size()]
	var m: float = D.SKMUL.get(str(tier), 1.0)
	var e := {"kind": base.k, "tgt": base.tgt}
	if base.has("mult"): e.mult = snappedf(base.mult * m, 0.001)
	if base.has("morale"): e.morale = snappedf(base.morale * m, 0.1)
	if base.has("tHeal"): e.tHeal = snappedf(base.tHeal * m, 0.0001)
	for key in ["exec", "spd", "foeSpd", "resDown", "selfBuff", "allyBuff", "cleanse", "pierce", "stance", "heal"]:
		if base.has(key):
			e[key] = base[key]
	if base.has("status"):
		var s: Dictionary = base.status
		var ratio: bool = s.k == "burn" or s.k == "flood"
		e.status = {"k": s.k,
			"val": snappedf(s.val * m, 0.001 if ratio else 0.1),
			"dur": int(s.dur) + int(D.SKDUR.get(str(tier), 0))}
	return {"n": base.n, "eff": e, "psv": null}


func _build_forms() -> void:
	for k in D.FORM:
		var f: Dictionary = D.FORM[k].duplicate(true)
		var slots := []
		var grid := []
		for ri in f.mask.size():
			var row := []
			var s: String = f.mask[ri]
			for ci in s.length():
				if s[ci] == "X":
					row.append(slots.size())
					slots.append({"line": D.LINES[ri], "row": ri, "col": ci,
						"side": "중앙" if ci == 1 else "측면"})
				else:
					row.append(-1)
			grid.append(row)
		f.slots = slots
		f.grid = grid
		FORM[k] = f


func _build_pools() -> void:
	for style in ["물리", "지략", "균형"]:
		POOLS[style] = {}
		for t in TIER:
			var arr := []
			for k in C:
				if C[k].tier != t:
					continue
				if style == "물리" and not PHYS_TAGS.has(C[k].tag): continue
				if style == "지략" and not INT_TAGS.has(C[k].tag): continue
				arr.append(k)
			POOLS[style][t] = arr


func _build_icons() -> void:
	for tag in D.TAGPATH:
		var p: Dictionary = D.TAGPATH[tag]
		var paint := ""
		if p.m == "s":
			paint = 'fill="none" stroke="#fff" stroke-width="%s" stroke-linecap="round"' % str(p.get("w", 1.8))
		else:
			paint = 'fill="#fff"' + (' fill-rule="evenodd"' if p.m == "e" else "")
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 12 12" width="12" height="12"><path %s d="%s"/></svg>' % [paint, p.d]
		var img := Image.new()
		img.load_svg_from_string(svg, 8.0)
		ICON[tag] = ImageTexture.create_from_image(img)


func _build_fonts() -> void:
	# 본문은 동봉한 나눔고딕, 제목은 나눔명조 (둘 다 OFL) —— 휴대폰에도 같은 글꼴이 나오도록 동봉한다.
	# 한자·기호처럼 나눔에 없는 글자는 시스템 글꼴로 넘긴다
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "Apple SD Gothic Neo", "Segoe UI Symbol", "Segoe UI"])
	var body: FontFile = load("res://assets/fonts/NanumGothic-Regular.ttf")
	body.fallbacks = [sys]
	font_body = body
	var bold: FontFile = load("res://assets/fonts/NanumGothic-Bold.ttf")
	bold.fallbacks = [sys]
	font_bold = bold
	var disp: FontFile = load("res://assets/fonts/NanumMyeongjo-ExtraBold.ttf")
	disp.fallbacks = [body]
	font_display = disp


# ───────── 조회 ─────────

func tier_color(k: String) -> Color:
	return Color("#ffd76e") if C[k].tier == 8 else TIER[C[k].tier].c


func fac_color(fac: String) -> Color:
	return Color(D.FAC[fac].c)


## 인물 이름 —— "의절 관우" → "관우". 같은 인물의 여러 등급 카드가 초상 한 장을 나눠 쓴다.
func person(k: String) -> String:
	var parts: PackedStringArray = C[k].name.split(" ")
	return parts[parts.size() - 1]


## 초상 —— assets/portraits/<인물>.png, 병사 카드는 assets/troops/<병종>.png 를 찾는다.
## 높은 등급 카드는 등급 그림을 먼저 찾고 없으면 한 단계씩 내려간다: 신화 → <인물>_신화 → _불멸 → _초월 → <인물>, 불멸 → _불멸 → _초월 → <인물>, 초월 → _초월 → <인물>.
## (일러스트를 등급 구간마다 따로 뽑는다 —— prompts/삼국지_일러스트_프롬프트.md)
## 없으면 null 을 돌려주고, 그리는 쪽에서 수묵 실루엣 플레이스홀더를 쓴다.
## 임포트 없이 파일을 떨궈 넣기만 하면 바뀌도록 Image 로 직접 읽는다. 파일이 없으면(내보낸 앱) 임포트된 텍스처를 쓴다.
func portrait(k: String) -> Texture2D:
	var base := portrait_base(k)
	return _portrait_cache.get(base) if base != "" else null


## 이 카드가 실제로 쓰는 그림 경로(확장자 없이). 그림이 하나도 없으면 ""
func portrait_base(k: String) -> String:
	if _portrait_pick.has(k):
		return _portrait_pick[k]
	var c: Dictionary = C[k]
	var cands: Array = []
	if c.tier <= 2:
		cands = ["res://assets/troops/%s" % c.tag]
	else:
		var p := "res://assets/portraits/%s" % person(k)
		if c.tier >= 8:
			cands.append(p + "_신화")
		if c.tier >= 7:
			cands.append(p + "_불멸")
		if c.tier >= 6:
			cands.append(p + "_초월")
		cands.append(p)
	var pick := ""
	for b in cands:
		if _load_portrait(b) != null:
			pick = b
			break
	_portrait_pick[k] = pick
	return pick


func _load_portrait(base: String) -> Texture2D:
	if _portrait_cache.has(base):
		return _portrait_cache[base]
	var tex: Texture2D = null
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var path := "%s.%s" % [base, ext]
		var img: Image = null
		if FileAccess.file_exists(path):
			img = _load_image(path)
		elif ResourceLoader.exists(path):
			# 내보낸 앱(휴대폰)에는 원본 그림 파일이 없고 임포트된 텍스처만 들어간다
			var t = load(path)
			if t is Texture2D:
				img = t.get_image()
				if img and img.is_compressed():
					img.decompress()
		if img:
			tex = ImageTexture.create_from_image(img)
			# 네 귀퉁이가 투명하면 잘라 낸 인물 그림으로 보고, 그려진 영역만 기억해 둔다
			if img.detect_alpha() != Image.ALPHA_NONE:
				var w := img.get_width() - 1
				var h := img.get_height() - 1
				if img.get_pixel(0, 0).a < 0.1 and img.get_pixel(w, 0).a < 0.1 and img.get_pixel(0, h).a < 0.1 and img.get_pixel(w, h).a < 0.1:
					_portrait_used[base] = Rect2(img.get_used_rect())
			break
	_portrait_cache[base] = tex
	return tex


## 잘라 낸 인물 그림이면 그려진 영역, 아니면 빈 Rect2
func portrait_used(k: String) -> Rect2:
	return _portrait_used.get(portrait_base(k), Rect2())


## 그림 읽기 —— 확장자가 아니라 파일 앞머리로 형식을 가린다 (JPEG 를 .png 로 저장한 경우 등)
func _load_image(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(bytes)
	if err != OK:
		push_warning("초상 그림을 읽지 못했다 (PNG·JPEG·WebP 만 된다): " + path)
		return null
	return img


## 특기 —— {self: {name, d, m}, group: {name, d, scope, scale} 또는 null}. 고급 미만은 null.
## 개인 특기 m 은 등급 배율을 곱해 둔다. 단체 특기는 엔진이 scale 을 곱해 쓴다 (겹침 판정 때문).
var _psv_cache := {}

func passives_of(k: String):
	if _psv_cache.has(k):
		return _psv_cache[k]
	var out = null
	var c: Dictionary = C[k]
	var p = PSV.persons.get(person(k)) if c.tier >= 3 else null
	if p != null:
		var sc: float = PSV.tier_scale[str(c.tier)]
		var s: Dictionary = PSV.catalog[p.self]
		var m := {}
		for key in s.m:
			m[key] = s.m[key] * (1.0 if key == "first" else sc)
		out = {"self": {"name": p.self, "d": s.d, "m": m}, "group": null}
		if c.tier >= int(PSV.group_from_tier):
			var g: Dictionary = PSV.catalog[p.group]
			out.group = {"name": p.group, "d": g.d, "scope": g.scope, "scale": sc}
	_psv_cache[k] = out
	return out


## 덱 점검용 —— 카드끼리 단체 특기가 닿는지 (진형 자리는 병종으로 짐작한다)
func passive_hits(g: Dictionary, owner_k: String, k: String) -> bool:
	var sc: String = g.scope
	if sc == "foe":
		return false
	if sc == "all":
		return true
	if sc == "fac":
		return C[k].fac == C[owner_k].fac
	if sc.begins_with("tag:"):
		return C[k].tag == sc.substr(4)
	if sc.begins_with("line:"):
		var front: bool = D.FRONT_WANT[C[k].tag] >= 1
		return front == (sc.find("선봉") >= 0)
	return false


const MOD_LABEL := {"atk": "공격", "def": "방어", "int": "책략", "res": "책략방어", "spd": "속도", "troop": "병력",
	"morale": "시작 사기", "crit": "치명타 확률", "critd": "치명타 피해", "icrit": "책략 치명타", "rate": "스킬 발동",
	"dr": "받는 물리 피해 -", "idr": "받는 책략 피해 -", "rout": "패주 확률 -", "shock": "큰 손실 충격 -",
	"counter": "반격", "stres": "상태이상 저항", "low_atk": "절반 이하 공격", "avenge": "아군 이탈마다 공격",
	"opener": "첫 공격 피해", "first": "선공", "regen": "턴마다 병력", "mregen": "턴마다 사기",
	"rout_loss": "아군 이탈 충격 -", "mshield": "받는 사기 피해 -", "mdeal": "주는 사기 피해",
	"rpierce": "적 책략방어 무시", "front_atk": "선봉·전군 공격", "back_int": "중군·후군 책략", "foe_morale": "적 시작 사기 -"}
const MOD_FLAT := ["morale", "mregen", "foe_morale"]


## 수치 요약 —— "치명타 확률 +14% · 치명타 피해 +69%"
func mods_text(m: Dictionary, scale := 1.0) -> String:
	var out := []
	for k in m:
		if k == "first":
			out.append("선공")
			continue
		var v: float = m[k] * scale
		var lb: String = MOD_LABEL.get(k, k)
		var sign := "" if lb.ends_with("-") else "+"
		if k in MOD_FLAT:
			out.append("%s%s%.0f" % [lb, sign, v])
		else:
			out.append("%s%s%.0f%%" % [lb, sign, v * 100])
	return " · ".join(out)


func passive_text(k: String) -> String:
	var ps = passives_of(k)
	if ps == null:
		return ""
	var s := "개인 『%s』 %s\n   %s" % [ps.self.name, ps.self.d, mods_text(ps.self.m)]
	if ps.group:
		s += "\n단체 『%s』 %s\n   %s" % [ps.group.name, ps.group.d, mods_text(PSV.catalog[ps.group.name].m, ps.group.scale)]
	return s


## 고유기 —— 신화 기준 수치를 불멸 카드에는 tier7_scale 배로 줄여 준다
func ult_of(k: String):
	var base = ULT.list.get(person(k))
	if base == null:
		return null
	var u: Dictionary = base.duplicate(true)
	u.first = u.get("first", ULT.first[str(C[k].tier)])
	u.cd = u.get("cd", ULT.cd)
	if C[k].tier == 7:
		var s: float = ULT.tier7_scale
		for comp in u.eff:
			for key in ["mult", "heal", "morale"]:
				if comp.has(key):
					comp[key] = comp[key] * s
			if comp.has("buff"):
				comp.buff.amt = comp.buff.amt * s
			if comp.has("status") and comp.status.k in ["burn", "bleed", "flood", "plague"]:
				comp.status.val = comp.status.val * s
	return u


func by_tier(t: int) -> Array:
	var order: Array = D.TAGORDER
	var out := []
	for k in C:
		if C[k].tier == t:
			out.append(k)
	out.sort_custom(func(a, b):
		var ta := order.find(C[a].tag)
		var tb := order.find(C[b].tag)
		if ta != tb:
			return ta < tb
		return C[a].name < C[b].name)
	return out


func aff_of(tag: String, line: String, side: String) -> String:
	var a: Dictionary = D.AFF.get(tag, {})
	if a.is_empty():
		return ""
	for z in a.pref:
		if z[0] == line and z[1] == side:
			return "pref"
	if a.bad[0] == line and a.bad[1] == side:
		return "bad"
	return ""


# ───────── 보드 생성 (원본 genBoard / autoPlace) ─────────

func gen_board(pv: float, style: String, rng: RandomNumberGenerator) -> Dictionary:
	var mid := func(t): return roundi((TIER[t].lo + TIER[t].hi) / 2.0)
	var tiers := []
	tiers.resize(9)
	tiers.fill(1)
	var spent := 9
	for g in 400:
		var lo := 0
		for i in range(1, 9):
			if tiers[i] < tiers[lo]:
				lo = i
		var t: int = tiers[lo]
		if t >= 7:
			break
		var cost: int = mid.call(t + 1) - mid.call(t)
		if spent + cost > pv:
			break
		tiers[lo] = t + 1
		spent += cost
	var cards := []
	for t in tiers:
		var src: Array = POOLS[style].get(t, [])
		if src.is_empty():
			src = POOLS["균형"][t]
		var ok := src.filter(func(k): return C[k].tier < 8)
		if ok.is_empty():
			ok = src
		cards.append(ok[rng.randi() % ok.size()])
	return {"cards": cards, "form": STYLE_FORM[style]}


func auto_place(cards: Array, form: String) -> Array:
	var f: Dictionary = FORM[form]
	var fw: Dictionary = D.FRONT_WANT
	var order := cards.filter(func(k): return k != null)
	order.sort_custom(func(a, b):
		if C[a].tier != C[b].tier:
			return C[a].tier > C[b].tier
		return fw[C[a].tag] > fw[C[b].tag])
	var out := []
	out.resize(9)
	var used := []
	used.resize(9)
	used.fill(false)
	for k in order:
		var best := -1
		var bs := -1e9
		for i in f.slots.size():
			if used[i]:
				continue
			var s: Dictionary = f.slots[i]
			var z := aff_of(C[k].tag, s.line, s.side)
			var v: float = (6.0 if z == "pref" else -4.0 if z == "bad" else 0.0) \
				- absf(D.LINE[s.line].pri - (4 - fw[C[k].tag])) * 0.6
			if v > bs:
				bs = v
				best = i
		if best >= 0:
			used[best] = true
			out[best] = k
	return out


# ───────── 설명문 (원본 skillDesc) ─────────

func tgt_name(t: String) -> String:
	if D.TGTNM.has(t):
		return D.TGTNM[t]
	if t.begins_with("line:"):
		return t.substr(5).replace("+", "·") + " 전체"
	return t


func skill_desc(c: Dictionary) -> String:
	if c.sk == null:
		return ""
	var e: Dictionary = c.sk.eff
	var p := []
	var pct := func(v): return "%d%%" % roundi(v * 100)
	match e.kind:
		"phys": p.append("적 %s에 물리 %s" % [tgt_name(e.tgt), pct.call(e.mult)])
		"int": p.append("적 %s에 책략 %s" % [tgt_name(e.tgt), pct.call(e.mult)])
	if e.has("morale"): p.append("사기 −%d" % roundi(e.morale))
	if e.has("pierce"): p.append("방어 %s 무시" % pct.call(e.pierce))
	if e.has("exec"): p.append("병력 %s 이하면 즉시 이탈" % pct.call(e.exec))
	if e.has("stance"): p.append("자신 반격 %s · %d턴" % [pct.call(e.stance.amt), e.stance.dur])
	if e.has("status"): p.append("『%s』 %d턴" % [D.STATUS[e.status.k].n, e.status.dur])
	if e.has("tHeal"): p.append("아군 병력 %s 회복" % pct.call(e.tHeal))
	if e.has("heal"): p.append("아군 사기 +%d" % roundi(e.heal))
	if e.has("cleanse"): p.append("아군 상태이상 %d종 해제" % e.cleanse)
	if e.has("spd"): p.append("대상 속도 %s" % pct.call(e.spd.amt))
	if e.has("foeSpd"): p.append("대상 속도 %s" % pct.call(e.foeSpd.amt))
	if e.has("resDown"): p.append("대상 책략방어 %s" % pct.call(e.resDown.amt))
	if e.has("selfBuff"): p.append("자신 %s %s" % [D.STATNM[e.selfBuff.stat], pct.call(e.selfBuff.amt)])
	if e.has("allyBuff"): p.append("%s %s %s" % [tgt_name(e.allyBuff.tgt), D.STATNM[e.allyBuff.stat], pct.call(e.allyBuff.amt)])
	return " · ".join(p)


func psv_text(p) -> String:
	if p == null:
		return ""
	return "%s — %s" % [D.PSVTITLE.get(p, p), D.PSVNM.get(p, p)]
