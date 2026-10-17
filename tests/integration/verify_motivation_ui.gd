extends SceneTree
## 真实内核到档案与班级概况的接入回归。
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
	for i in range(16):
		core._vitality[i] = 40.0
		core._gain_today[i] = -2.0
	core._grade[0] = 350.0
	var before := [
		core._a.duplicate(), core._h.duplicate(), core._rng._mt.duplicate(), core._rng._mti
	]
	var profile: Node = load("res://scenes/ui/npc_profile.tscn").instantiate()
	root.add_child(profile)
	profile.bind_sources(core, null, null)
	profile.open_profile(0)
	check(not paused, "打开档案不暂停世界")
	check(profile.get_node("%MotivationBar").visible, "真实动力条可见")
	check(profile.get_node("%MotivationValue").text == "40 / 100", "显示真实动力")
	check(profile.get_node("%GainValue").text == "-2 分", "负收益不能钳制为零")
	check("348" in profile.get_node("%Settlement").text, "预览真实收益计入成绩")
	var clock := SimulationClock.new()
	root.add_child(clock)
	clock.bind_core(core)
	clock.set_process(false)
	var snap := clock.snapshot()
	check(snap.get("class_average_motivation") == 40.0, "班级动力为真实均值")
	check(snap.get("class_average_academic_gain") == -2.0, "班级平均收益保留负号")
	core.add_vitality(0, 15.0)
	core._gain_today[0] = 3.0
	await process_frame
	await process_frame
	check(profile.get_node("%MotivationValue").text == "55 / 100", "档案打开时动力实时刷新")
	check(profile.get_node("%GainValue").text == "+3 分", "档案打开时收益实时刷新")
	check("353" in profile.get_node("%Settlement").text, "结算预览同步刷新")
	check([core._a, core._h, core._rng._mt, core._rng._mti] == before, "界面不修改矩阵或随机序列")
	var tick_before := int(core.time_snapshot().global_tick)
	clock.pump(1.0)
	await process_frame
	await process_frame
	check(int(core.time_snapshot().global_tick) > tick_before, "档案打开时模拟仍推进")
	profile.close()
	paused = true
	profile.open_profile(0)
	profile.close()
	check(paused, "保留其他窗口的暂停")
	paused = false
	profile.queue_free()
	clock.queue_free()
	state.end_game()
	await process_frame
	print(
		"MOTIVATION_UI: ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size()
	)
	quit(0 if failures.is_empty() else 1)
