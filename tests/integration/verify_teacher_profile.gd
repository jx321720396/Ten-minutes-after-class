extends SceneTree
## 独立老师档案回归，不依赖 GUT 版本，失败返回非零。
const PROFILE_SCENE_PATH := "res://scenes/ui/npc_profile.tscn"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_verify")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _verify() -> void:
	var state := root.get_node("GameState")
	state.start_game(12345, 16)
	var core: SimCore = state.sim_core
	var profile: Node = load(PROFILE_SCENE_PATH).instantiate()
	root.add_child(profile)
	profile.bind_sources(core, null, null)
	var before := [
		core._a.duplicate(), core._h.duplicate(), core._rng._mt.duplicate(), core._rng._mti
	]
	profile.open_profile(0)
	await process_frame
	await process_frame
	var targets: OptionButton = profile.get_node("%Targets")
	check(targets.item_count == 15 and targets.get_item_index(16) == -1, "关系对象必须排除自己与老师")
	check(profile.get_node_or_null("%TrustValue") == null, "不得恢复信任轴")
	check(profile.get_node("%MotivationValue").text == "—", "无动力不得推算")
	check(profile.get_node("%GainValue").text == "—", "无收益不得推算")
	var item := targets.get_item_index(1)
	targets.select(item)
	profile._on_target_selected(item)
	profile.get_node("%AffinityBandHigh").pressed.emit()
	profile.get_node("%HostilityBandHigh").pressed.emit()
	check(
		(
			profile.get_node("%AffinityValue").text == "较高"
			and profile.get_node("%HostilityValue").text == "较高"
		),
		"两轴可同时较高"
	)
	profile.get_node("%Reverse").pressed.emit()
	check(profile.get_node("%AffinityValue").text == "未判断", "反方向独立")
	profile.get_node("%Reverse").pressed.emit()
	core._intel.record(
		1, 1, 0, 1, "affinity", 0.0, {"day": 2, "phase_id": "lunch_break", "global_tick": 100}
	)
	profile._refresh_records()
	check(profile.get_node("%AffinityValue").text == "较低", "真实消息覆盖对应轴")
	check(profile.get_node("%HostilityValue").text == "较高", "真实消息不得覆盖另一轴")
	profile.get_node("%AffinityBandMedium").pressed.emit()
	profile.close()
	profile.open_profile(0)
	check(profile.get_node("%AffinityValue").text == "一般", "旧消息不重复覆盖后来的手动标注")
	profile.update_student_snapshot(0, {"motivation": 40, "academic_gain": -5})
	check(profile.get_node("%MotivationValue").text == "40 / 100", "动力来自明确快照")
	check(profile.get_node("%GainValue").text == "-5 分", "负收益不能钳制成零")
	profile.get_node("%StatusTab").pressed.emit()
	check(
		profile.get_node("%StatusPage").visible and not profile.get_node("%RelationsPage").visible,
		"状态页可切换"
	)
	profile.close()
	check(not paused, "档案关闭释放自己的暂停")
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	var history_scroll: ScrollContainer = profile.get_node("%HistoryScroll")
	touch.position = history_scroll.get_global_rect().get_center()
	history_scroll._input(touch)
	check(not history_scroll._touch_active, "关闭档案后的滚动区不能捕获教室触摸")
	check([core._a, core._h, core._rng._mt, core._rng._mti] == before, "标注不得修改矩阵或随机序列")
	profile.queue_free()
	await process_frame
	var reopened: Node = load(PROFILE_SCENE_PATH).instantiate()
	root.add_child(reopened)
	reopened.bind_sources(core, null, null)
	reopened.open_profile(0)
	var reopened_targets: OptionButton = reopened.get_node("%Targets")
	reopened_targets.select(reopened_targets.get_item_index(1))
	reopened._on_target_selected(reopened_targets.get_item_index(1))
	check(reopened.get_node("%AffinityValue").text == "一般", "档案重建仍保留本局笔记")
	reopened.close()
	paused = true
	reopened.open_profile(0)
	reopened.close()
	check(paused, "不能释放其他窗口的暂停")
	paused = false
	reopened.queue_free()
	state.end_game()
	await process_frame
	print(
		"TEACHER_PROFILE: ",
		"PASS" if failures.is_empty() else "FAIL",
		" failures=",
		failures.size()
	)
	quit(0 if failures.is_empty() else 1)
