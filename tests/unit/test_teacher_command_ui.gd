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
	assert_eq(commands.current_command(), "", "送回教室当场完成")
	assert_eq(commands.called_index(), -1)
	assert_true(core.is_present(0))


func test_office_comfort_lowers_stress_and_linked_vitality() -> void:
	var core := SimCore.new(20261016, 16, ConfigLoader.new().load_all())
	core._begin_phase_state()
	core._stress[0] = 60.0
	core._vitality[0] = 60.0
	var commands := core.teacher_commands()
	assert_true(commands.summon(core, 0))
	assert_true(commands.office_chat(core, "comfort"), "安抚走办公室聊天，20 秒")
	assert_eq(str(commands.snapshot().get("chat_kind", "")), "comfort")
	for tick in range(19):
		commands.tick(core)
	assert_almost_eq(core.stress(0), 60.0, 0.001, "未满 20 秒不结算")
	commands.tick(core)
	assert_eq(commands.current_command(), "", "安抚满 20 秒完成")
	assert_almost_eq(core.stress(0), 40.0, 0.001, "安抚减压 20")
	assert_almost_eq(core.vitality(0), 40.0, 0.001, "减压按一般规则联动动力")
	assert_true(commands.send_back(core), "安抚后可送回教室")


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
	# 行为按钮多于一屏：安抚 / 表扬 / 训斥 / 送回 / 打听 / 鼓励，全部落在可滚动区内。
	# office.gd 持有 office_meeting 实例，按钮与滚动容器都在那一层。
	var meeting: Control = hub.office_view()._meeting
	var buttons: Dictionary = meeting.get("_buttons")
	var scroll: Control = meeting.get("_scroll")
	assert_true(buttons.has("comfort"), "行为按钮含安抚")
	assert_true(scroll != null, "行为按钮区使用滚动容器")
	assert_true(
		scroll.get_child_count() == 1 and scroll.get_child(0).get_child_count() == buttons.size(),
		"六个行为按钮都在滚动区内"
	)
	core._stress[0] = 60.0
	core._vitality[0] = 60.0
	buttons["comfort"].pressed.emit()
	assert_eq(commands.current_command(), "office_chat")
	assert_eq(str(commands.snapshot().get("chat_kind", "")), "comfort")
	for tick in range(20):
		commands.tick(core)
	assert_almost_eq(core.stress(0), 40.0, 0.001, "安抚减压 20")
	buttons["scold"].pressed.emit()
	assert_eq(commands.current_command(), "office_chat")
	for tick in range(20):
		commands.tick(core)
	buttons["send_back"].pressed.emit()
	assert_eq(commands.current_command(), "", "送回教室当场完成")
	assert_eq(commands.called_index(), -1)
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
