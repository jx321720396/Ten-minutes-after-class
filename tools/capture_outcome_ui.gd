extends SceneTree
## 独立预览真实生产界面；考试／风险夹具仅存在本截图进程。

const SCREEN := "res://scenes/ui/outcome_screen.tscn"
const OUTPUT := "res://tools/out/outcome_ui"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1920, 1080)
	var core := SimCore.new(20261018, 16, ConfigLoader.new().load_all())
	var target := float(core._exam.target_mean())
	core._exam._sigma = 0.0
	core._exam._penalty = 0.0
	core._grade.fill(target + 6.5)
	core._exam.settle(8, core._grade, core._stress, core._alias_list())
	var clock := SimulationClock.new()
	root.add_child(clock)
	clock.bind_core(core)
	clock.set_process(false)
	clock._mode = SimulationClock.MODE_REPORT
	clock._ended_day = 8
	var screen: CanvasLayer = load(SCREEN).instantiate()
	root.add_child(screen)
	var report: CanvasLayer = load("res://scenes/ui/term_report.tscn").instantiate()
	root.add_child(report)
	report.bind_sources(core, clock, null, false)
	screen.bind_sources(core, clock, report)
	await _save("exam_1920")
	root.size = Vector2i(1280, 720)
	await _save("exam_1280")
	screen.show_scores()
	await _save("scores_1280")
	screen.call("_close_details")
	core._grade.fill(target - 7.4)
	core._exam.settle(8, core._grade, core._stress, core._alias_list())
	clock._mode = SimulationClock.MODE_FINISHED
	clock._failure_reason = core._failure_reason()
	screen.set(
		"_data", load("res://scripts/game/outcome_snapshot.gd").new().build(core, clock.snapshot())
	)
	screen.call("_render", "academic")
	await _save("academic_1280")
	core._risk._dropped[2] = true
	core._risk._breakdowns[2] = 4
	clock._failure_reason = core._failure_reason()
	screen.set(
		"_data", load("res://scripts/game/outcome_snapshot.gd").new().build(core, clock.snapshot())
	)
	screen.call("_render", "dropout")
	await _save("dropout_1280")
	root.size = Vector2i(960, 540)
	await _save("dropout_960")
	root.size = Vector2i(1280, 720)
	screen.show_dropout_records()
	await _save("dropout_records_1280")
	screen.call("_close_details")
	screen.show_overview()
	await _save("end_1280")
	var record: Dictionary = load("res://scripts/game/outcome_snapshot.gd").new().archive_record(
		core, screen.get("_data")
	)
	assert(report.open_record(record))
	await _save("relations_1280")
	report.call("_close_report")
	root.size = Vector2i(960, 540)
	await _save("end_960")
	quit()


func _save(label: String) -> void:
	for frame in 4:
		await process_frame
	RenderingServer.force_draw()
	var error := root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png")
	assert(error == OK)
	print("saved ", label)
