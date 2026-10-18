extends GutTest
## 真实考试／风险结果的展示与继续权限，不修改玩法判据。

const MODEL_PATH := "res://scripts/game/outcome_snapshot.gd"
const SCREEN_PATH := "res://scripts/ui/outcome_screen.gd"
const ARCHIVE_PATH := "user://last_term_report.dat"
var _archive_existed := false
var _archive_bytes := PackedByteArray()


func before_all() -> void:
	_archive_existed = FileAccess.file_exists(ARCHIVE_PATH)
	if _archive_existed:
		_archive_bytes = FileAccess.get_file_as_bytes(ARCHIVE_PATH)


func after_all() -> void:
	if _archive_existed:
		var file := FileAccess.open(ARCHIVE_PATH, FileAccess.WRITE)
		file.store_buffer(_archive_bytes)
	else:
		DirAccess.remove_absolute(ARCHIVE_PATH)


func _model() -> RefCounted:
	assert_true(ResourceLoader.exists(MODEL_PATH), "结算展示模型应存在")
	if not ResourceLoader.exists(MODEL_PATH):
		return null
	return load(MODEL_PATH).new()


func _core() -> SimCore:
	return SimCore.new(20261018, 16, ConfigLoader.new().load_all())


func test_exam_uses_settled_scores_and_only_exam_can_continue() -> void:
	var model := _model()
	if model == null:
		return
	var core := _core()
	if "_target_means" in core._exam:
		core._exam._target_means.clear()
	core._exam._target_mean = 0.0
	core._exam.settle(8, core._grade, core._stress, core._alias_list())
	var data: Dictionary = model.build(core, {"ended_day": 8, "mode": "report"})
	assert_eq(data.kind, "exam")
	assert_almost_eq(float(data.mean), core._exam.mean_of(8), 0.00001)
	assert_eq(data.students.size(), 16)
	assert_true(data.can_continue)
	assert_eq(model.build(core, {"ended_day": 7, "mode": "report"}), {})


func test_failed_exam_and_dropout_have_distinct_real_evidence() -> void:
	var model := _model()
	if model == null:
		return
	var core := _core()
	if "_target_means" in core._exam:
		core._exam._target_means.clear()
	core._exam._target_mean = 750.0
	core._exam.settle(8, core._grade, core._stress, core._alias_list())
	var data: Dictionary = model.build(core, {"ended_day": 8, "mode": "finished"})
	assert_eq(data.kind, "academic")
	assert_false(data.can_continue)
	core._risk._dropped[2] = true
	core._risk._breakdowns[2] = 4
	data = model.build(core, {"ended_day": 8, "mode": "finished"})
	assert_eq(data.kind, "dropout", "退学证据优先，不用分数覆盖")
	assert_eq(data.dropouts[0].name, core.alias(2))
	assert_eq(data.dropouts[0].breakdowns, 4)
	assert_false(data.can_continue)


func test_observation_does_not_change_core_or_random_sequence() -> void:
	var model := _model()
	if model == null:
		return
	var core := _core()
	var before := var_to_bytes(core.term_record())
	var rng_state := var_to_bytes([core._rng._mt, core._rng._mti])
	for i in 3:
		model.build(core, {"ended_day": 30, "mode": "finished"})
	assert_eq(var_to_bytes(core.term_record()), before)
	assert_eq(var_to_bytes([core._rng._mt, core._rng._mti]), rng_state)


func test_open_exam_holds_clock_until_explicit_continue() -> void:
	assert_true(ResourceLoader.exists(SCREEN_PATH), "可操作结算界面应存在")
	if not ResourceLoader.exists(SCREEN_PATH):
		return
	var core := _core()
	if "_target_means" in core._exam:
		core._exam._target_means.clear()
	core._exam._target_mean = 0.0
	core._exam.settle(8, core._grade, core._stress, core._alias_list())
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	clock.bind_core(core)
	clock._mode = SimulationClock.MODE_REPORT
	clock._ended_day = 8
	var screen: CanvasLayer = load(SCREEN_PATH).new()
	add_child_autofree(screen)
	screen.bind_sources(core, clock)
	assert_true(screen.visible)
	assert_true(clock.is_held_by(&"outcome_screen"))
	assert_false(clock.continue_after_report(), "其他入口不能绕过考试确认")
	var next: Array = []
	screen.continue_requested.connect(func() -> void: next.append(true))
	var hud := TimeHUD.new()
	add_child_autofree(hud)
	hud.bind_clock(clock)
	assert_false(hud.tick_report_hold(1000.0), "考试页打开时日末自动倒计时不能越过确认")
	screen.continue_exam()
	assert_false(clock.is_held_by(&"outcome_screen"))
	assert_false(screen.visible)
	assert_eq(next.size(), 1)
	assert_true(clock.continue_after_report())
	screen.continue_exam()
	assert_eq(next.size(), 1, "重复点击不重复继续")


func test_failure_never_releases_clock_via_continue() -> void:
	if not ResourceLoader.exists(SCREEN_PATH):
		assert_true(false, "可操作结算界面应存在")
		return
	var core := _core()
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	clock.bind_core(core)
	clock._mode = SimulationClock.MODE_FINISHED
	var screen: CanvasLayer = load(SCREEN_PATH).new()
	add_child_autofree(screen)
	screen.bind_sources(core, clock)
	var next: Array = []
	screen.continue_requested.connect(func() -> void: next.append(true))
	screen.continue_exam()
	assert_true(clock.is_held_by(&"outcome_screen"))
	assert_false(clock.continue_after_report())
	assert_eq(next.size(), 0)


func test_teacher_archive_preserves_every_student_name_without_changing_history() -> void:
	var model := _model()
	if model == null:
		return
	assert_true(model.has_method("archive_record"), "老师回顾应修复旧历史的姓名副本")
	if not model.has_method("archive_record"):
		return
	var core := _core()
	var before := var_to_bytes(core.term_record())
	var data: Dictionary = model.build(core, {"ended_day": 5, "mode": "finished"})
	var record: Dictionary = model.archive_record(core, data)
	var ARCHIVE := preload("res://scripts/game/term_archive.gd")
	var path := "user://outcome_name_test.dat"
	assert_eq(ARCHIVE.write(record, path), OK)
	var saved := ARCHIVE.read(path)
	for i in core.node_count():
		assert_eq(record.names[i], core.alias(i))
		assert_eq(saved.names[i], core.alias(i))
	assert_eq(var_to_bytes(core.term_record()), before)
	DirAccess.remove_absolute(path)
