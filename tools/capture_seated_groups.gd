extends "res://tools/capture_group_facing.gd"
## 验证真实导航靠近与前后桌在座转身；夹具不进入正式游戏。


func _capture() -> void:
	if OS.get_cmdline_user_args().has("seated_catalog"):
		await _catalog()
		quit()
		return
	root.size = Vector2i(1280, 720)
	var state: Variant = root.get_node("GameState")
	state.start_game(20261018, 16)
	var room: Node3D = load("res://scenes/game/classroom3D.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	for frame in range(180):
		if room.has_node("GroupFacing"):
			break
		await process_frame
	assert(room.has_node("GroupFacing"))
	if room.has_node("OfficeHub"):
		room.get_node("OfficeHub").set_mode("monitor")
	room.get_node("TransitionOverlay").force_hide()
	room.get_node("TransitionOverlay").visible = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	var core: SimCore = state.sim_core
	var actors: Node3D = room.get_node("Actors")
	var roam: Node = room.get_node("Roam")
	var facing: Node = room.get_node("GroupFacing")
	core._sessions.clear()
	for index in range(16):
		core._current_act[index] = "chat"
	roam.snap_to_seats()
	# 在真实开阔过道中从原 1.2 米通过生产导航走近。
	var positions: Array[Vector2] = []
	var nav_map := room.get_world_3d().navigation_map
	# 用真实几何寻找一段 1.2m 的合法走廊；不把人物注入家具或网格外。
	for z_step in range(30, -50, -2):
		for x_step in range(-28, 29, 2):
			var anchor := Vector2(x_step * 0.1, z_step * 0.1)
			var start := anchor - Vector2(0, 1.2)
			var target := anchor - Vector2(0, roam._group_distance)
			if not core._space.valid_position_for(start, [anchor], 1.3, core.range_step()):
				continue
			var valid := true
			for point in [anchor, start, target]:
				var closest := NavigationServer3D.map_get_closest_point(
					nav_map, Vector3(point.x, 0, point.y)
				)
				if Vector2(closest.x, closest.z).distance_to(point) > 0.03:
					valid = false
					break
				for index in range(2, 16):
					var other: Vector3 = actors.actor_for(index).global_position
					if point.distance_to(Vector2(other.x, other.z)) < roam._minimum_gap:
						valid = false
			if valid:
				positions = [anchor, start]
				break
		if not positions.is_empty():
			break
	assert(positions.size() == 2, "找到安全演示位置")
	print("legal corridor: ", positions)
	for index in range(2):
		var actor: Node3D = actors.actor_for(index)
		actor.global_position = Vector3(
			positions[index].x, actor.global_position.y, positions[index].y
		)
		core.set_position(index, positions[index].x, positions[index].y)
	core._sessions.begin("chat", [0, 1], 100)
	actors._process(0.0)
	roam._group_spacing.update(
		core, roam._actors, roam._walkers, roam, roam._group_distance, roam._minimum_gap
	)
	var walker: Node = actors.actor_for(1).get_node("Walker")
	assert(walker.is_moving(), "靠近必须实际通过导航启动")
	walker._time_flow = null
	for frame in range(240):
		walker._process(1.0 / 60.0)
		if not walker.is_moving():
			break
		await process_frame
	assert(not walker.is_moving(), "靠近应完成")
	var gap: float = actors.actor_for(0).global_position.distance_to(
		actors.actor_for(1).global_position
	)
	print(
		"spacing result: ",
		gap,
		" ",
		actors.actor_for(0).global_position,
		" ",
		actors.actor_for(1).global_position
	)
	assert(absf(gap - roam._group_distance) <= 0.03, "真实间距应接近配置")
	roam._sync_positions_to_core()
	actors._process(0.0)
	facing.refresh()
	room.get_node("Rings").refresh()
	print("standing group distance: ", gap)
	await _save("standing_close.png")
	# 回真实座位，选择同列相邻的前后桌，不挪桌椅。
	core._sessions.clear()
	roam.snap_to_seats()
	actors._process(0.0)
	var pair: Array = []
	var best_score := -INF
	for first in range(16):
		for second in range(first + 1, 16):
			if core.chat_pair_in_range(first, second):
				var center: Vector3 = (
					(actors.sit_position_of(first) + actors.sit_position_of(second)) * 0.5
				)
				var score: float = center.z - absf(center.x)
				if score > best_score:
					best_score = score
					pair = [first, second]
	assert(pair.size() == 2, "应找到真实前后桌聊天组合")
	var a: int = pair[0]
	var b: int = pair[1]
	if actors.sit_position_of(a).z < actors.sit_position_of(b).z:
		pair.reverse()
	a = pair[0]
	b = pair[1]
	var before_a: Vector3 = actors.actor_for(a).global_position
	var before_b: Vector3 = actors.actor_for(b).global_position
	core._sessions.begin("chat", pair, 100)
	for index in range(16):
		var pose: Node = actors._seated_poses[index]
		var key: String = str(actors.actor_for(index).get_meta("appearance_sprite"))
		assert(actors._pose_settings.bindings[key].has("idle_back"))
		pose.show_pose("idle", false)
		actors.actor_for(index).get_node("Sprite").hide()
	facing.refresh()
	# 测试使用阻塞纹理读取，生产仍为后台预载。
	actors._seated_poses[a].show_pose("idle", false)
	assert(actors._seated_poses[a]._pose == "idle_back", "前桌坐姿调用背影")
	assert(actors._seated_poses[b]._pose == "idle", "后桌坐姿保持正面")
	roam._group_spacing.update(
		core, roam._actors, roam._walkers, roam, roam._group_distance, roam._minimum_gap
	)
	assert(
		(
			actors.actor_for(a).global_position == before_a
			and actors.actor_for(b).global_position == before_b
		),
		"在座聊天不得离座靠近"
	)
	assert(not actors.actor_for(a).get_node("Walker").is_moving())
	room.get_node("Rings").refresh()
	await _save("seated_chat_active.png")
	var camera := room.get_node("Camera3D") as Camera3D
	var saved_transform := camera.global_transform
	var saved_projection := camera.projection
	var saved_size := camera.size
	var saved_fov := camera.fov
	var center: Vector3 = (actors.sit_position_of(a) + actors.sit_position_of(b)) * 0.5
	var overlays: Array[CanvasLayer] = []
	for child in room.get_children():
		if child is CanvasLayer and child.visible:
			overlays.append(child)
			child.hide()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 45
	camera.look_at_from_position(center + Vector3(0.4, 1.8, 3.5), center + Vector3(0, 0.8, 0))
	await _save("seated_chat_detail.png")
	camera.global_transform = saved_transform
	camera.projection = saved_projection
	camera.size = saved_size
	camera.fov = saved_fov
	for overlay in overlays:
		overlay.show()
	core._sessions.clear()
	facing.refresh()
	actors._seated_poses[a].show_pose("idle", false)
	assert(actors._seated_poses[a]._pose == "idle", "结束恢复正面坐姿")
	room.get_node("Rings").refresh()
	await _save("seated_chat_ended.png")
	current_scene = null
	room.queue_free()
	state.end_game()
	await process_frame
	quit()
