extends GutTest


func test_teacher_back_only_in_classroom_and_stays_out_of_student_roster() -> void:
	var state = get_node("/root/GameState")
	state.start_game(20261016, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	add_child_autofree(room)
	for frame in range(180):
		if room.has_node("OfficeHub"):
			break
		await get_tree().physics_frame
	room.get_node("Clock").hold(&"teacher_presence_test")
	var hub = room.get_node("OfficeHub")
	var back = room.get_node_or_null("TeacherPresence")
	assert_not_null(back, "Classroom must install the teacher back sprite")
	if back == null:
		state.end_game()
		return
	assert_false(back.visible, "Initial monitor hides teacher")
	var fixed_position: Vector3 = back.global_position
	var tick = state.sim_core.time_snapshot().global_tick
	for mode in ["classroom", "monitor", "office", "classroom"]:
		hub.set_mode(mode)
		assert_eq(back.visible, mode == "classroom")
		assert_eq(back.global_position, fixed_position, "View changes never move teacher")
	assert_eq(state.sim_core.node_count(), 16, "Teacher never enters student matrix")
	assert_eq(room.get_node("Actors").actor_count(), 16)
	assert_eq(state.sim_core.time_snapshot().global_tick, tick)
	assert_false(back.has_node("Walker"))
	assert_false(back.has_node("PickBody"))
	assert_not_null(back.get_node("Sprite").texture)
	state.end_game()
