extends GutTest

const PROFILE = preload("res://scenes/ui/npc_profile.tscn")
const MODEL = preload("res://scripts/ui/npc_profile_data.gd")


func test_teacher_targets_exclude_player_and_switch_without_effects() -> void:
	var profile = PROFILE.instantiate()
	add_child_autofree(profile)
	var core := SimCore.new(12345, 16)
	profile.bind_sources(core, null, null)
	var before := [core._a.duplicate(), core._h.duplicate(), core._rng._mti]
	profile.open_profile(0)
	var targets: OptionButton = profile.get_node("%Targets")
	assert_gte(targets.get_item_index(core.node_count() - 1), 0, "位次下拉框包含全部 16 名学生")
	assert_eq(targets.item_count, 15, "下拉框排除当前打开的这位学生本人")
	assert_null(profile.get_node_or_null("%TrustValue"))
	assert_false(get_tree().paused, "档案不暂停世界")
	profile.open_profile(1)
	profile.close()
	assert_false(get_tree().paused)
	assert_eq([core._a, core._h, core._rng._mti], before)


func test_manual_axis_and_new_intel_override_only_corresponding_direction() -> void:
	var model = MODEL.new()
	assert_true(model.has_method("mark"), "应支持玩家观察标注")
	if not model.has_method("mark"):
		return
	model.mark(0, 1, "affinity", "band_high", {"day": 1, "phase_id": "morning_break"})
	model.mark(0, 1, "hostility", "band_high", {"day": 1, "phase_id": "morning_break"})
	var clue := {
		"clue_id": 1,
		"source": 0,
		"subject": 1,
		"axis": "affinity",
		"value": 0.0,
		"day": 2,
		"phase_id": "lunch_break",
		"global_tick": 100
	}
	var input := [clue]
	var before := input.duplicate(true)
	var result: Dictionary = model.build(input, 0, 1)
	assert_eq(result.latest.affinity.origin, "known")
	assert_eq(result.latest.affinity.value, 0.0)
	assert_eq(result.latest.hostility.band, "band_high")
	assert_true(model.build(input, 1, 0).latest.is_empty())
	model.mark(0, 1, "affinity", "band_medium", {"day": 2, "phase_id": "lunch_break"})
	assert_eq(model.build(input, 0, 1).latest.affinity.origin, "guess", "重复旧消息不能覆盖后来的推测")
	model.mark(0, 1, "hostility", "unknown", {"day": 2, "phase_id": "lunch_break"})
	assert_false(model.build(input, 0, 1).latest.has("hostility"))
	assert_eq(input, before)
	var restored = MODEL.new()
	restored.state = JSON.parse_string(JSON.stringify(model.state))
	assert_eq(restored.build(input, 0, 1).latest.affinity.band, "band_medium")
	assert_eq(restored.build(input, 0, 1).history.size(), 5)


func test_teacher_metrics_read_live_core() -> void:
	var profile = PROFILE.instantiate()
	add_child_autofree(profile)
	var core := SimCore.new(12345, 16)
	core._vitality[0] = 42.0
	core._gain_today[0] = -3.0
	profile.bind_sources(core, null, null)
	profile.open_profile(0)
	assert_not_null(profile.get_node_or_null("%MotivationValue"))
	if profile.get_node_or_null("%MotivationValue") == null:
		return
	assert_eq(profile.get_node("%MotivationValue").text, "42 / 100")
	assert_eq(profile.get_node("%GainValue").text, "-3 分")
	assert_true(profile.get_node("%GradeValue").text.contains(str(roundi(core.grade(0)))))
	profile.close()


func test_individual_grade_and_settlement_display_whole_points() -> void:
	var profile = PROFILE.instantiate()
	add_child_autofree(profile)
	var core := SimCore.new(12345, 16)
	profile.bind_sources(core, null, null)
	profile.open_profile(0)
	core._gain_today[0] = 1.2
	profile.update_student_snapshot(0, {"grade": 474.6})
	assert_eq(profile.get_node("%GradeValue").text, "475 / 750")
	assert_true(profile.get_node("%Settlement").text.contains("476分"))
	core._gain_today[0] = -0.8
	profile.update_student_snapshot(0, {"grade": 474.3})
	assert_eq(profile.get_node("%GradeValue").text, "474 / 750")
	assert_true(profile.get_node("%Settlement").text.contains("474分"))
	profile.close()


func after_each() -> void:
	get_tree().paused = false


# ------------------------------------------------------------------ 公开专属被动（主文档 §10）
func _passive_copy() -> Dictionary:
	return JSON.parse_string(
		FileAccess.get_file_as_string("res://data/localization/passives.json")
	)


func test_passive_card_shows_name_and_effect_from_data() -> void:
	var profile = PROFILE.instantiate()
	add_child_autofree(profile)
	var core := SimCore.new(12345, 16)
	profile.bind_sources(core, null, null)
	profile.open_profile(0)
	var copy := _passive_copy()
	var passive_id := core.passive_id_of(0)
	assert_ne(passive_id, "", "0 号学生有公开专属被动")
	assert_eq(
		str(profile.get_node("%Passive").text),
		"%s\n%s" % [str(copy[passive_id]["name"]), str(copy[passive_id]["effect"])],
		"档案的被动卡显示配置里的名称与效果"
	)
	profile.close()


func test_team_spirit_profile_reveals_incoming_affinity_only() -> void:
	var profile = PROFILE.instantiate()
	add_child_autofree(profile)
	var core := SimCore.new(12345, 16)
	profile.bind_sources(core, null, null)
	var index := -1
	for i in range(core.node_count()):
		if core.passive_id_of(i) == "team_spirit":
			index = i
	if index < 0:
		fail_test("本局没有分配到群策群力的学生")
		return
	var heading := str(_passive_copy().get("reveal_heading", ""))
	var other := 0 if index != 0 else 1
	profile.open_profile(index)
	profile._show_page(true)
	var details := str(profile.get_node("%StatusDetails").text)
	assert_true(details.contains(heading), "群策群力：档案列出他人对本人好感")
	assert_true(details.contains(str(core.alias(other))), "列表里出现其他同学")
	profile.open_profile(other)
	profile._show_page(true)
	assert_false(
		str(profile.get_node("%StatusDetails").text).contains(heading), "其他被动没有这项可见性"
	)
	profile.close()
