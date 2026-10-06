extends GutTest
## RosterSelector：绑定组成员强制纳入 + MBTI 四维极性覆盖 + 确定性（不消费随机数）。

const DIMS := ["e", "n", "f", "p"]

var _tables: Dictionary
var _seeds: Array
var _bindings: Array
var _neutral: float


func before_each() -> void:
	_tables = ConfigLoader.new().load_all()
	_seeds = _tables["characters/seeds"]["rows"]
	_bindings = _tables["characters/bindings"]["rows"]
	_neutral = float(_params(_tables, "rules/kernel_params")["mbti_neutral"])


func _select(target: int) -> Array:
	return RosterSelector.new().select(_seeds, _bindings, target, _neutral)


func test_target_count() -> void:
	assert_eq(_select(8).size(), 8, "应抽出 8 人")


func test_includes_binding_members() -> void:
	var aliases: Array = []
	for row in _select(8):
		aliases.append(str(row["alias"]))
	assert_true(aliases.has("陈阳"), "含绑定组 couple 陈阳")
	assert_true(aliases.has("林晚"), "含绑定组 couple 林晚")
	assert_true(aliases.has("佳豪"), "含绑定组 uniform 佳豪")


func test_covers_all_polarities() -> void:
	var roster := _select(8)
	for d in DIMS:
		var has_high := false
		var has_low := false
		for row in roster:
			var v := float(str(row[d]))
			if v > _neutral:
				has_high = true
			elif v < _neutral:
				has_low = true
		assert_true(has_high and has_low, "%s 维高低两侧都应覆盖" % d)


func test_deterministic() -> void:
	var a := _select(8)
	var b := _select(8)
	assert_eq(a.size(), b.size(), "两次抽取长度一致")
	for i in range(a.size()):
		assert_eq(str(a[i]["alias"]), str(b[i]["alias"]), "第 %d 位名单一致" % i)


func _params(tables: Dictionary, name: String) -> Dictionary:
	var out := {}
	for row in tables[name]["rows"]:
		out[str(row["param"])] = float(str(row["value"]))
	return out
