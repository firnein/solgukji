class_name Changelog
extends RefCounted
## 버전 · 업데이트 내역 (11/7) —— data/changelog.json 이 원본. 맨 앞 항목이 지금 빌드 버전.
## 새 빌드: python tools/scripts/release.py --next "제목" 으로 항목을 만들고 items 를 채운 뒤 build_apk.bat.
## release.py 가 같은 파일에서 export_presets.cfg 의 version/name · version/code 와 docs/업데이트_내역.html 을 만든다.

const PATH := "res://data/changelog.json"

static var _d: Dictionary = {}


static func _load() -> void:
	if not _d.is_empty():
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		_d = {"versions": []}
		return
	var p = JSON.parse_string(f.get_as_text())
	_d = p if p is Dictionary else {"versions": []}


## 지금 버전 이름 (예: "1.0a")
static func version() -> String:
	_load()
	var vs: Array = _d.get("versions", [])
	return str(vs[0].get("ver", "?")) if not vs.is_empty() else "?"


## 모든 버전 (최신이 앞) —— [{ver, code, date, title, groups:[{n, items:[...]}]}]
static func versions() -> Array:
	_load()
	return _d.get("versions", [])


## 한 버전을 bbcode 로 —— 묶음 이름은 금빛, 항목은 '·' 로 시작
static func bb(v: Dictionary) -> String:
	var out := ""
	for g in v.get("groups", []):
		out += "[color=#D9A64B]%s[/color]\n" % str(g.get("n", ""))
		for it in g.get("items", []):
			out += "· %s\n" % str(it)
		out += "\n"
	return out.strip_edges()
