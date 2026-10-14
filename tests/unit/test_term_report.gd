extends GutTest


func _core() -> SimCore:
	return SimCore.new(12345, 16, ConfigLoader.new().load_all())


func test_five_icons_preserve_partial_fill() -> void:
	var script = load("res://scripts/ui/emotion_meter.gd")
	assert_not_null(script, "期末五格图标组件应存在")
	if script == null:
		return
	var meter = script.new()
	add_child_autofree(meter)
	meter.set_emotion("affinity", 61.0)
	assert_eq(meter.fills().size(), 5)
	assert_almost_eq(meter.fills()[0], 1.0, 0.001)
	assert_almost_eq(meter.fills()[2], 1.0, 0.001)
	assert_almost_eq(meter.fills()[3], 0.05, 0.001)
	assert_eq(meter.fills()[4], 0.0)
	meter.set_emotion("hostility", 100.0, 1)
	assert_eq(meter.fills(), [1.0, 1.0, 1.0, 1.0, 1.0])
	assert_eq(meter.change_direction(), 1, "敌对增加也是上箭头")
	meter.set_emotion("trust", 0.0)
	assert_eq(meter.fills(), [0.0, 0.0, 0.0, 0.0, 0.0])
	assert_eq(meter.change_direction(), 0)


func test_recording_captures_actual_changes_and_is_readonly() -> void:
	var core := _core()
	assert_true(core.has_method("term_record"), "内核应提供只读期末记录")
	if not core.has_method("term_record"):
		return
	var before := core.affinity(0, 1)
	var rng_before: Variant = [core._rng._mt.duplicate(), core._rng._mti]
	core._apply_event(0, 1, "topic_affinity")
	var history: Dictionary = core.call("term_record")
	assert_gt(history.frames.size(), 0)
	assert_eq([core._rng._mt, core._rng._mti], rng_before, "采集不得消耗随机数")
	var change: Array = history.frames[-1].changes[0]
	assert_eq(int(change[1]), 1, "平铺下标对应0→1")
	assert_eq(float(change[2]), before)
	assert_eq(float(change[3]), core.affinity(0, 1))
	var count: int = history.frames.size()
	core._apply_event(0, 1, "topic_affinity")
	assert_eq(core.call("term_record").frames.size(), count, "去重事件不重复记录")
	history.baseline[0][1] = -1.0
	assert_ne(core.call("term_record").baseline[0][1], -1.0, "导出不允许改记录")


func test_player_completion_is_not_global_or_per_target() -> void:
	var core := _core()
	assert_true(core.has_method("term_record"))
	if not core.has_method("term_record"):
		return
	var me := core.node_count() - 1
	core._do_chat(0, 1)
	assert_eq(core.call("term_record").actions.get("chat", {}).get("completed", 0), 0)
	core._do_chat(me, 2)
	core._global_tick = core._busy_until[me]
	core._settle_finished_actions()
	core._settle_finished_actions()
	assert_eq(core.call("term_record").actions.chat.completed, 1)
	assert_eq(core.call("term_record").actions.chat.initiated, 1)


func test_playback_keeps_each_event_and_seek_does_not_accumulate() -> void:
	var script = load("res://scripts/game/term_replay.gd")
	assert_not_null(script)
	if script == null:
		return
	var replay = script.new()
	var history := {
		"count": 2,
		"baseline": [[0.0, 60.0, 10.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]],
		"frames":
		[
			{"tick": 1, "day": 1, "cause": "chat", "changes": [[0, 1, 60.0, 61.0]]},
			{"tick": 1, "day": 1, "cause": "reject", "changes": [[0, 1, 61.0, 59.0]]},
		],
		"checkpoints": [],
	}
	replay.configure(history)
	replay.step()
	assert_eq(replay.value(0, 0, 1), 61.0)
	assert_eq(replay.direction(0, 0, 1), 1)
	replay.step()
	assert_eq(replay.value(0, 0, 1), 59.0)
	assert_eq(replay.direction(0, 0, 1), -1)
	replay.seek_tick(1)
	assert_eq(replay.value(0, 0, 1), 59.0)
	assert_eq(replay.direction(0, 0, 1), 0, "拖动不带旧箭头")
	replay.restart()
	assert_eq(replay.value(0, 0, 1), 60.0)


func test_finished_report_is_automatic_and_world_stays_frozen() -> void:
	var script = load("res://scripts/ui/term_report.gd")
	assert_not_null(script, "期末界面应存在")
	if script == null:
		return
	var tables := ConfigLoader.new().load_all()
	for row in tables["rules/time_runtime"].rows:
		if row.key == "term_days":
			row.value = "1"
	var core := SimCore.new(12345, 16, tables)
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	clock.set_process(false)
	assert_true(clock.bind_core(core, tables))
	var report = script.new()
	add_child_autofree(report)
	report.bind_sources(core, clock)
	assert_false(report.visible, "局内不展示隐藏真值")
	while core.day() == 1:
		clock.pump(1.0)
	assert_true(report.visible)
	assert_true(report.record().finished)
	var tick := core.global_tick()
	report.seek_tick(0)
	report.advance_replay()
	clock.pump(100.0)
	assert_eq(core.global_tick(), tick, "回放与期末界面不得推进世界")
	assert_false(clock.continue_after_report())
	report.show_matrix(2)
	assert_eq(report.matrix_cell_count(), 272, "17节点排除17个对角线")


func test_completed_term_replays_to_true_final_matrices() -> void:
	var core := _core()
	core.run_day()
	var replay = load("res://scripts/game/term_replay.gd").new()
	var history := core.term_record()
	replay.configure(history)
	replay.seek_tick(replay.last_tick())
	for i in core.node_count():
		for j in core.node_count():
			assert_eq(replay.value(0, i, j), core.affinity(i, j))
			assert_eq(replay.value(1, i, j), core.hostility(i, j))


func test_rejection_interruption_and_invitation_counts_are_separate() -> void:
	var core := _core()
	var me := core.node_count() - 1
	core._occupy(me, 0, "chat", true)
	core._emit("event_happened", {"kind": "chat", "i": me, "accepted": false})
	core._global_tick = core._busy_until[me]
	core._settle_finished_actions()
	assert_eq(core.term_record().actions.chat.rejected, 1)
	assert_eq(core.term_record().actions.chat.completed, 0)
	core._occupy(me, me, "listen_music")
	core._check_interrupt()
	core._cleanup_phase()
	assert_eq(core.term_record().actions.listen_music.interrupted, 1)
	assert_eq(core.term_record().actions.listen_music.completed, 0)
	core._do_chat(1, me)
	var invitation: Dictionary = core.get_player_invitation()
	assert_false(invitation.is_empty())
	core.respond_player_invitation(int(invitation.id), true)
	core._global_tick = core._busy_until[me]
	core._settle_finished_actions()
	assert_eq(core.term_record().actions.chat.completed, 1)
	assert_eq(core.term_record().actions.chat.invited, 1)
	assert_eq(core.term_record().actions.chat.initiated, 0)
