extends SceneTree
## 真实主场景与生产时钟信号的接线验收。夹具仅用于此独立进程，保留玩家归档。

const ARCHIVE := "user://last_term_report.dat"
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state := root.get_node("GameState")
	state.start_game(20261018, 16)
	state.tutorial_pending = false
	var scene_resource: PackedScene = load("res://scenes/game/classroom3D.tscn")
	var scene: Node = scene_resource.instantiate()
	root.add_child(scene)
	current_scene = scene
	var clock: SimulationClock = scene.get_node("Clock")
	var core: Variant = state.sim_core
	for frame in 120:
		await process_frame
		if scene.get_node_or_null("OutcomeScreen") != null:
			clock.hold(&"outcome_smoke")
			break
	for frame in 8:
		await process_frame
	var screen: CanvasLayer = scene.get_node_or_null("OutcomeScreen")
	_check(screen != null, "真实教室创建 OutcomeScreen")
	if screen == null:
		quit(1)
		return
	var target := float(core._exam.target_mean())
	var exam_day := int(core._exam._days[0])
	core._exam._sigma = 0.0
	core._exam._penalty = 0.0
	core._grade.fill(target + 6.5)
	core._exam.settle(exam_day, core._grade, core._stress, core._alias_list())
	_boundary(clock, exam_day)
	_check(not paused, "考试结算释放全树暂停")
	_check(screen.visible and str(screen.get("_data").kind) == "exam", "考试信号打开达标页")
	_check(not clock.continue_after_report(), "考试未确认时阻止其他继续入口")
	_press(screen, "继续带班")
	_check(not screen.visible and str(clock.snapshot().mode) == "running", "原生继续按钮接回真实主场景")
	_check(not paused and not clock.is_held_by(&"outcome_screen"), "考试确认后解除结算冻结")
	core._grade.fill(target - 7.4)
	core._exam.settle(exam_day, core._grade, core._stress, core._alias_list())
	_boundary(clock, exam_day)
	_check(screen.visible and str(screen.get("_data").kind) == "academic", "成绩不达标打开专用辞退页")
	_check(not paused, "失败时不保留暂停")
	_check(not clock.continue_after_report(), "辞退后不能继续")
	_press(screen, "查看本局回顾")
	_check(
		(
			screen.find_children("StudentMemory*", "TextureRect", true, false).size()
			== int(core.node_count())
		),
		"结束回忆区覆盖本局全体学生"
	)
	_press(screen, "成绩回顾")
	_check(screen.get("_details") != null, "成绩回顾打开真实明细")
	_press(screen, "返回结算")
	_press(screen, "关系与事件")
	var report: CanvasLayer = scene.get_node("TermReport")
	_check(report.visible, "关系按钮打开真实历史回放")
	report.call("_close_report")
	core._risk._dropped[2] = true
	core._risk._breakdowns[2] = 4
	_boundary(clock, exam_day)
	_check(screen.visible and str(screen.get("_data").kind) == "dropout", "退学信号打开离校记录页")
	_press(screen, "查看退学记录")
	_check(screen.get("_details") != null, "退学记录按钮可用")
	_press(screen, "返回结算")
	var before: int = core.global_tick()
	clock.pump(100.0)
	_check(int(core.global_tick()) == before, "失败后世界保持终止")
	core._risk._breakdowns[2] = 2
	core._risk._triggered_kind[2] = "bully"
	_boundary(clock, exam_day)
	var risk_cause := false
	for label in screen.find_children("*", "Label", true, false):
		if str(label.text).contains("霸凌后再次崩溃"):
			risk_cause = true
	_check(risk_cause, "正式风险后崩溃的退学路径使用对应原因文案")
	core._risk._dropped.fill(false)
	var term_day := int(clock.snapshot().term_days)
	var term_target: float = (
		core._exam.target_mean_for(term_day)
		if core._exam.has_method("target_mean_for")
		else core._exam.target_mean()
	)
	core._grade.fill(term_target + 6.5)
	core._exam.settle(term_day, core._grade, core._stress, core._alias_list())
	clock._failure_reason = ""
	_boundary(clock, term_day)
	_check(str(screen.get("_data").kind) == "end", "正常学期终点打开中性结束页")
	var rng_state := var_to_bytes([core._rng._mt, core._rng._mti])
	screen.show_overview()
	_check(var_to_bytes([core._rng._mt, core._rng._mti]) == rng_state, "结束页重绘不消费内核随机数")
	_press(screen, "重新开始")
	var restarted := false
	var restart_started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - restart_started < 30000:
		await create_timer(0.1).timeout
		if (
			current_scene == null
			or current_scene.scene_file_path != "res://scenes/game/classroom3D.tscn"
		):
			continue
		if state.sim_core != core and current_scene.get_node_or_null("OpeningComic") != null:
			restarted = true
			break
	_check(restarted, "重新开始按钮创建新的本局内核并进入教室")
	if not restarted:
		print("OUTCOME LIVE FLOW: FAIL failures=", _failures)
		quit(1)
		return
	if restarted:
		clock = current_scene.get_node("Clock")
		clock.hold(&"outcome_smoke")
		current_scene.get_node("OpeningComic").skip()
		core = state.sim_core
		core._exam._sigma = 0.0
		core._exam._penalty = 0.0
		core._grade.fill(0.0)
		exam_day = int(core._exam._days[0])
		core._exam.settle(exam_day, core._grade, core._stress, core._alias_list())
		_boundary(clock, exam_day)
		screen = current_scene.get_node("OutcomeScreen")
		_press(screen, "查看本局回顾")
	_press(screen, "返回主菜单")
	for frame in 4:
		await process_frame
	_check(
		current_scene != null and current_scene.scene_file_path == "res://scenes/ui/main_menu.tscn",
		"回主菜单真实场景切换"
	)
	_check(state.sim_core == null, "离开结算后清理本局内核")
	for frame in 120:
		if AssetPreloader.scene("res://scenes/game/classroom3D.tscn") != null:
			break
		await process_frame
	print("OUTCOME LIVE FLOW: ", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	quit(0 if _failures == 0 else 1)


func _boundary(clock: SimulationClock, day: int) -> void:
	var existed := FileAccess.file_exists(ARCHIVE)
	var bytes := FileAccess.get_file_as_bytes(ARCHIVE) if existed else PackedByteArray()
	clock._ended_day = day
	clock.call("_enter_report")
	if existed:
		var file := FileAccess.open(ARCHIVE, FileAccess.WRITE)
		file.store_buffer(bytes)
	else:
		DirAccess.remove_absolute(ARCHIVE)


func _press(screen: Node, fragment: String) -> void:
	for node in screen.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and str(node.text).contains(fragment):
			node.pressed.emit()
			return
	_check(false, "找不到按钮：" + fragment)


func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		_failures += 1
