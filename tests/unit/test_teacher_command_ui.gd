extends GutTest


func test_office_command_lifecycle_blocks_early_chat_and_duplicate_summons() -> void:
	var core := SimCore.new(20261016, 16, ConfigLoader.new().load_all())
	core._begin_phase_state()
	var commands := core.teacher_commands()
	assert_true(commands.summon(core, 0))
	assert_true(core._is_in_office(0), "召唤即时到达：学生立刻在办公室")
	assert_true(commands.office_chat(core, "scold"), "到达后可以立即谈话")
	assert_false(commands.summon(core, 1), "Arrived student still occupies office")
	assert_false(commands.office_chat(core, "scold"), "Do not reset an active conversation")
	for tick in range(20):
		commands.tick(core)
	assert_true(commands.send_back(core), "Can send back a waiting student after conversation")
	for tick in range(10):
		commands.tick(core)
	assert_eq(commands.called_index(), -1)
	assert_true(core.is_present(0))


func test_real_ui_summons_displays_all_students_and_returns_them() -> void:
	var state = get_node("/root/GameState")
	state.start_game(20261016, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	add_child_autofree(room)
	for frame in range(180):
		if room.has_node("OfficeHub"):
			break
		await get_tree().physics_frame
	room.get_node("Clock").hold(&"command_ui_test")
	var hub = room.get_node("OfficeHub")
	hub.set_mode("office")
	hub.open_tool("summon")
	assert_false(get_tree().paused, "Student selector must not freeze classroom")
	hub.select_student(0)
	var core = state.sim_core
	var commands = core.teacher_commands()
	# 2026-10-16 裁定：召唤即时到达，不再有 10 秒等待期。
	assert_eq(commands.current_command(), "", "召唤当场完成")
	assert_true(core._is_in_office(0), "被召唤的学生立刻在办公室")
	assert_false(hub.picker_visible())
	hub._process(0.0)
	room.get_node("Actors")._process(0.0)
	assert_false(room.get_node("Actors").actor_for(0).visible)
	assert_true(hub.office_view().meeting_visible())
	for index in range(16):
		hub.office_view().show_student(core, index)
		assert_eq(
			hub.office_view().meeting_texture().resource_path,
			room.get_node("Actors")._seated_poses[index]._binding.idle,
			"Office sprite must match each student's identity"
		)
	hub.office_view().action_requested.emit("scold")
	assert_eq(commands.current_command(), "office_chat")
	for tick in range(20):
		commands.tick(core)
	hub.office_view().action_requested.emit("send_back")
	assert_eq(commands.current_command(), "send_back")
	for tick in range(10):
		commands.tick(core)
	hub._process(0.0)
	room.get_node("Actors")._process(0.0)
	assert_false(hub.office_view().meeting_visible())
	assert_true(room.get_node("Actors").actor_for(0).visible)
	# The pair picker must submit real seat changes and update the rendered seats.
	hub.set_mode("classroom")
	var seat_before: String = str(core.seat_of(0))
	hub._on_teacher_action("seats")
	hub.select_student(0)
	hub.select_student(1)
	assert_eq(commands.current_command(), "seat_change")
	for tick in range(10):
		commands.tick(core)
	room.get_node("Actors")._process(0.0)
	assert_ne(str(core.seat_of(0)), seat_before)
	assert_eq(str(room.get_node("Actors").seat_node_of(0).name), str(core.seat_of(0)))
	assert_true(core._at_own_seat(0), "New visual and core seat anchors must agree")
	core._h[1] = 60.0
	hub._on_teacher_action("mediate")
	hub.select_student(0)
	hub.select_student(1)
	assert_eq(commands.current_command(), "mediate")
	for tick in range(20):
		commands.tick(core)
	assert_almost_eq(core.hostility(0, 1), 55.0, 0.001)
	# Upheld commands resume without displaying the student in both rooms.
	hub.set_mode("office")
	hub.open_tool("summon")
	hub.select_student(0)
	commands.begin_class(core)
	var remaining: int = commands.remaining_seconds()
	commands.tick(core)
	hub._process(0.0)
	assert_false(hub.office_view().meeting_visible())
	assert_true(core.is_present(0))
	assert_eq(commands.remaining_seconds(), remaining)
	commands.begin_break()
	for tick in range(remaining):
		commands.tick(core)
	hub._process(0.0)
	assert_true(hub.office_view().meeting_visible())
	await get_tree().process_frame
	state.end_game()


func test_exports_include_office_command_and_portrait_configuration() -> void:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK)
	for section in presets.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			var includes := str(presets.get_value(section, "include_filter", ""))
			for path in [
				"data/ui/office_hub.json",
				"data/ui/teacher_classroom.json",
				"data/ui/student_poses.json"
			]:
				assert_true(includes.contains(path), "Office flow must survive mobile export")
