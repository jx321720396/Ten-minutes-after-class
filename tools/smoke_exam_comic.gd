extends SceneTree
## 考试漫画到真实成绩页的独立集成验收，不写玩家存档。
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1


func _run() -> void:
	if "--live" in OS.get_cmdline_user_args():
		await _live()
		return
	var core := SimCore.new(20261018, 16, ConfigLoader.new().load_all())
	var clock := SimulationClock.new()
	root.add_child(clock)
	clock.bind_core(core)
	clock.set_process(false)
	check(clock.has_method("complete_exam_day"), "时钟提供考试专用完成入口")
	if not clock.has_method("complete_exam_day"):
		quit(1)
		return
	check(not clock.call("complete_exam_day"), "普通日拒绝考试完成")
	core._day = int(core._exam._days[0])
	core._grade.fill(core._exam.target_mean() + 20.0)
	var screen: CanvasLayer = load("res://scripts/ui/outcome_screen.gd").new()
	root.add_child(screen)
	screen.bind_sources(core, clock)
	var comic: CanvasLayer = load("res://scripts/ui/exam_comic.gd").new()
	root.add_child(comic)
	comic.bind_sources(core, clock)
	check(comic.visible and not screen.visible, "考试日先展示漫画，成绩页尚未出现")
	var before := core.global_tick()
	clock.pump(100.0)
	check(core.global_tick() == before, "漫画期间世界冻结")
	var reference := SimCore.new(20261018, 16, ConfigLoader.new().load_all())
	reference._day = int(reference._exam._days[0])
	reference._grade.fill(reference._exam.target_mean() + 20.0)
	while int(reference.time_snapshot().day) == int(reference._exam._days[0]):
		reference.advance_tick()
		reference.finish_time_boundary()
	if "--capture" in OS.get_cmdline_user_args():
		comic.set_process(false)
		root.size = Vector2i(1280, 720)
		for index in 3:
			await create_timer(0.6).timeout
			await _capture("panel_%d" % index)
			if index < 2:
				comic.advance()
	comic.call("_process", 100.0)
	if "--capture" in OS.get_cmdline_user_args():
		await _capture("scores")
	check(not comic.visible and screen.visible, "漫画自动播完直接打开成绩UI")
	check(int(screen.get("_data").day) == int(core._exam._days[0]), "展示当天真实考试结果")
	check(str(screen.get("_data").kind) == "exam", "达标结果使用现有考试UI")
	check(core._exam.export_state() == reference._exam.export_state(), "演出结果与原始tick结算一致")
	check(core._a == reference._a and core._h == reference._h, "漫画不额外改变关系矩阵")
	check(
		(
			var_to_bytes([core._rng._mt, core._rng._mti])
			== var_to_bytes([reference._rng._mt, reference._rng._mti])
		),
		"漫画不额外消费内核随机数"
	)
	var report := core.exam_report(int(core._exam._days[0]))
	check(not clock.call("complete_exam_day"), "重复结束不重复结算")
	check(report == core.exam_report(int(core._exam._days[0])), "成绩记录保持不变")
	check(not clock.continue_after_report(), "成绩未确认不能越过结果页")
	screen.continue_exam()
	check(clock.continue_after_report(), "确认成绩后可进入次日")
	comic.bind_sources(core, clock)
	check(not comic.visible, "普通日不重播考试漫画")
	# 使用新的低分考试验证漫画结束后的辞退 UI，并还原临时归档。
	var archive := "user://last_term_report.dat"
	var existed := FileAccess.file_exists(archive)
	var saved := FileAccess.get_file_as_bytes(archive) if existed else PackedByteArray()
	core._day = int(core._exam._days[0])
	core._grade.fill(0.0)
	clock._mode = SimulationClock.MODE_RUNNING
	clock._ended_day = 0
	clock.time_updated.emit(clock.snapshot())
	check(comic.visible, "新的考试运行状态重新触发演出")
	for index in 3:
		comic.advance()
	check(not comic.visible and screen.visible, "点击播完也直接进入结果页")
	check(str(screen.get("_data").kind) == "academic", "未达标展示现有成绩辞退UI")
	check(not clock.continue_after_report(), "未达标后不能继续带班")
	if existed:
		var file := FileAccess.open(archive, FileAccess.WRITE)
		file.store_buffer(saved)
	else:
		DirAccess.remove_absolute(archive)
	screen.free()
	comic.free()
	clock.free()
	print("EXAM COMIC FLOW: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)


func _live() -> void:
	var state := root.get_node("GameState")
	state.start_game(20261018, 16)
	state.tutorial_pending = false
	var core: Variant = state.sim_core
	core._day = int(core._exam._days[0])
	core._grade.fill(core._exam.target_mean() + 20.0)
	var scene: Node = load("res://scenes/game/classroom3D.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 120:
		await process_frame
		if scene.get_node_or_null("ExamComic") != null:
			break
	var comic: CanvasLayer = scene.get_node_or_null("ExamComic")
	check(comic != null and comic.visible, "真实教室考试日自动打开漫画")
	if comic == null:
		quit(1)
		return
	comic.set_process(false)
	var clock: SimulationClock = scene.get_node("Clock")
	# 夹具不覆盖玩家的真实自动存档。
	clock.report_ready.disconnect(scene._on_report_ready)
	check(clock.is_held_by(&"exam_comic"), "真实教室漫画持有冻结")
	check(not scene.get_node("TransitionOverlay").visible, "考试日不显示普通上下课转场")
	for index in 3:
		comic.advance()
	var screen: CanvasLayer = scene.get_node("OutcomeScreen")
	check(screen.visible and not comic.visible, "真实教室漫画结束接成绩页")
	screen.continue_exam()
	check(str(clock.snapshot().mode) == "running", "真实继续带班按钮进入次日")
	check(not comic.visible, "次日不重复播放考试漫画")
	clock.hold(&"exam_smoke_end")
	print("EXAM COMIC LIVE: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)


func _capture(label: String) -> void:
	var folder := "res://tools/out/exam_comic"
	DirAccess.make_dir_recursive_absolute(folder)
	await process_frame
	RenderingServer.force_draw()
	var error := root.get_texture().get_image().save_png(folder + "/" + label + ".png")
	check(error == OK, "保存截图 " + label)
