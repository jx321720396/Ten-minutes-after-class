extends GutTest
## 回归重点：方向/逐轴时间/未知/只读；模型仅接收已获得历史，不接收SimCore。

const MODEL_PATH := "res://scripts/ui/npc_profile_data.gd"


func _clue(id: int, source: int, subject: int, axis: String, value: Variant) -> Dictionary:
	return {
		"clue_id": id,
		"request_id": id,
		"source": source,
		"subject": subject,
		"axis": axis,
		"value": value,
		"day": id,
		"phase_id": "morning_break",
		"global_tick": id * 100,
	}


func test_latest_is_directional_per_axis_and_does_not_mutate_history() -> void:
	assert_true(ResourceLoader.exists(MODEL_PATH), "档案只读适配器应存在")
	if not ResourceLoader.exists(MODEL_PATH):
		return
	var model = load(MODEL_PATH).new()
	var history := [
		_clue(3, 0, 1, "trust", 80.0),
		_clue(1, 0, 1, "affinity", 0.0),
		_clue(4, 1, 0, "hostility", 95.0),
		_clue(2, 0, 1, "trust", 20.0),
		_clue(5, 0, 2, "hostility", 90.0),
	]
	var before := history.duplicate(true)
	var result: Dictionary = model.build(history, 0, 1)
	assert_eq(result.latest.trust.value, 80.0)
	assert_eq(result.latest.trust.day, 3)
	assert_eq(result.latest.affinity.value, 0.0, "已知零值不能显示为未知")
	assert_eq(result.latest.affinity.day, 1, "逐轴保留不同获知时间")
	assert_false(result.latest.has("hostility"), "不能泄露反方向或其他对象的信息")
	assert_eq(result.history.size(), 3)
	assert_eq(history, before)
	result.latest.trust.value = 1.0
	assert_eq(history, before, "返回深拷贝")


func test_unknown_duplicates_and_shared_chat_request() -> void:
	assert_true(ResourceLoader.exists(MODEL_PATH))
	if not ResourceLoader.exists(MODEL_PATH):
		return
	var model = load(MODEL_PATH).new()
	var a := _clue(1, 0, 1, "trust", 70.0)
	var b := _clue(2, 0, 2, "affinity", 30.0)
	b.request_id = 1
	var result: Dictionary = model.build(
		[a, a.duplicate(), b, _clue(3, 0, 1, "hostility", null)], 0, 1
	)
	assert_eq(result.history.size(), 1, "重复与无值记录不作为已知关系")
	assert_eq(result.encounters.size(), 1, "同次闲聊的两条线索只记一次交集")
	assert_eq(result.encounters[0].count, 2)
	assert_false(result.latest.has("hostility"))
	assert_true(model.build([], 0, 1).latest.is_empty())


func test_profile_pause_empty_state_switch_and_escape() -> void:
	var path := "res://scenes/ui/npc_profile.tscn"
	assert_true(ResourceLoader.exists(path), "应有可复用的原生UI场景")
	if not ResourceLoader.exists(path):
		return
	var profile = load(path).instantiate()
	add_child_autofree(profile)
	var core := SimCore.new(12345, 1)
	profile.bind_sources(core, null, null)
	var before := core.get_player_intel()
	profile.open_profile(0)
	assert_true(profile.is_open())
	assert_true(get_tree().paused)
	assert_eq(profile.get_node("%TrustValue").text, "未知")
	assert_eq(profile.get_node("%PersonName").text, core.alias(0))
	profile.open_profile(1)
	assert_eq(profile.get_node("%PersonName").text, core.alias(1))
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	profile._input(escape)
	assert_false(profile.is_open())
	assert_false(get_tree().paused)
	assert_eq(core.get_player_intel(), before)
	get_tree().paused = true
	profile.open_profile(0)
	profile.close()
	assert_true(get_tree().paused, "不能释放其他界面持有的暂停")
	get_tree().paused = false


func test_profile_uses_snapshot_even_after_live_relationship_changes() -> void:
	var profile = load("res://scenes/ui/npc_profile.tscn").instantiate()
	add_child_autofree(profile)
	var core := SimCore.new(12345, 1)
	(
		core
		. _intel
		. record(
			1,
			1,
			0,
			1,
			"affinity",
			0.0,
			{
				"day": 1,
				"phase_id": "morning_break",
				"global_tick": 1,
			}
		)
	)
	profile.bind_sources(core, null, null)
	profile.open_profile(0)
	assert_eq(profile.get_node("%AffinityValue").text, "较低")
	assert_eq(profile.get_node("%HostilityValue").text, "未知")
	var before := core.get_player_intel()
	core._a[1] = 100.0  # 测试夹具：后台已变化，但玩家没有获取新线索。
	profile.close()
	profile.open_profile(0)
	assert_eq(core.affinity(0, 1), 100.0)
	assert_eq(profile.get_node("%AffinityValue").text, "较低")
	assert_eq(core.get_player_intel(), before)
	assert_eq(profile.get_node("%StaleNote").text, "此后关系可能变化")
	profile.close()


func after_each() -> void:
	get_tree().paused = false
