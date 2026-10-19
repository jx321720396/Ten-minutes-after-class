extends GutTest


func test_cancel_mediate_keeps_relations_and_clears_pending_effect() -> void:
	var core := SimCore.new(20261019, 16, ConfigLoader.new().load_all())
	var commands = core.teacher_commands()
	assert_true(commands.mediate(core, 0, 1))
	var before := core.hostility(0, 1)
	assert_true(commands.has_method("cancel_intervention"))
	if not commands.has_method("cancel_intervention"):
		return
	assert_true(commands.cancel_intervention())
	for tick in range(25):
		commands.tick(core)
	assert_eq(commands.current_command(), "")
	assert_eq(core.hostility(0, 1), before)


func test_voice_meter_is_embedded_and_follows_state() -> void:
	var view = load("res://scripts/ui/teacher_interlude.gd").new()
	add_child_autofree(view)
	view.refresh(
		SimCore.new(20261019, 16, ConfigLoader.new().load_all()),
		{"command": "office_chat", "chat_kind": "scold", "called": 0, "remaining_seconds": 20}
	)
	view.set_voice_state(
		{"active": true, "tier": 3, "intensity": 42.0, "preview": "训斥 · 提高", "warning": ""}
	)
	assert_true(view._voice_meter.visible, "演出弹窗内应显示声量条")
	view.set_voice_state({})
	assert_false(view._voice_meter.visible, "无声量窗口时隐藏声量条")
