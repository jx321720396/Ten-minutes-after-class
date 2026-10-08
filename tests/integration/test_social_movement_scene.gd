extends GutTest
## 真教室、真时钟、真导航驱动推进整段课间，检查聊天成员静止与真实范围。


func test_classroom_chat_and_movement_are_mutually_exclusive() -> void:
	var state = get_node("/root/GameState")
	state.start_game(20261007, 2)
	var scene = load("res://scenes/game/classroom3D.tscn").instantiate()
	add_child_autofree(scene)
	for frame in range(20):
		await get_tree().physics_frame
	var core: SimCore = state.sim_core
	var roam = scene.get_node("Roam")
	var clock: SimulationClock = scene.get_node("Clock")
	assert_not_null(roam._clock, "真实导航与时钟完成接线")
	# 禁用自动帧推进，按固定步长调用同一生产组件，避免测试耗时等于真实课间。
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	var violations: Array = []
	var seen_sessions := {}
	var moving_frames := 0
	for step in range(1000):
		roam._process(0.1)
		for walker in roam._walkers:
			if walker != null:
				walker._process(0.1)
		roam._sync_positions_to_core()
		clock.pump(0.1)
		for i in range(core.node_count() - 1):
			if core.is_moving(i):
				moving_frames += 1
		for session in core.get_active_sessions():
			seen_sessions[session.session_id] = true
			for member in session.members:
				if roam._walkers[member].is_moving():
					violations.append("聊天成员仍在移动: %s" % member)
			for pair in session.links:
				var a: int = pair[0]
				var b: int = pair[1]
				# 独立上限：普通近距离，或原座位前后紧邻的 1.8 米例外。
				if core.distance_between(a, b) > 1.2:
					var sa: Array = core._seat_pos[core.seat_of(a)]
					var sb: Array = core._seat_pos[core.seat_of(b)]
					var ha: Vector3 = roam._point_positions[core.seat_of(a)]
					var hb: Vector3 = roam._point_positions[core.seat_of(b)]
					if not (
						sa[1] == sb[1]
						and absi(sa[0] - sb[0]) == 1
						and core.position_of(a).distance_to(Vector2(ha.x, ha.z)) <= 0.1
						and core.position_of(b).distance_to(Vector2(hb.x, hb.z)) <= 0.1
						and core.distance_between(a, b) <= 1.8
					):
						violations.append("远距离聊天: %s" % [pair])
		if not roam.is_break_phase():
			break
	assert_gt(seen_sessions.size(), 0, "确实发生聊天，不以关闭所有行为通过测试")
	assert_gt(moving_frames, 0, "确实发生走动，不以关闭移动通过测试")
	assert_eq(violations, [], "整段课间没有远程聊天或边聊边走")
	state.end_game()
