extends GutTest
## RosterSelector：绑定组成员强制纳入 + 确定性（不消费随机数）。
## 2026-10-12：角色池 = 16 人 = 一局人数，抽取因此退化为「顺序 + 绑定组优先」；算法行为仍逐条钉住。
## 2026-10-14：老师版删除 MBTI 四维极性覆盖，只保留绑定组成员强制纳入。

var _tables: Dictionary
var _seeds: Array
var _bindings: Array


func before_each() -> void:
	_tables = ConfigLoader.new().load_all()
	_seeds = _tables["characters/seeds"]["rows"]
	_bindings = _tables["characters/bindings"]["rows"]


func _select(target: int) -> Array:
	return RosterSelector.new().select(_seeds, _bindings, target, 0.0)


func test_target_count() -> void:
	assert_eq(_select(16).size(), 16, "一局 = 全池 16 人")


func test_includes_binding_members() -> void:
	var aliases: Array = []
	for row in _select(16):
		aliases.append(str(row["alias"]))
	assert_true(aliases.has("陈阳"), "含绑定组 couple 陈阳")
	assert_true(aliases.has("林晚"), "含绑定组 couple 林晚")
	assert_true(aliases.has("佳豪"), "含绑定组 uniform 佳豪")


func test_deterministic() -> void:
	var a := _select(16)
	var b := _select(16)
	assert_eq(a.size(), b.size(), "两次抽取长度一致")
	for i in range(a.size()):
		assert_eq(str(a[i]["alias"]), str(b[i]["alias"]), "第 %d 位名单一致" % i)
