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
