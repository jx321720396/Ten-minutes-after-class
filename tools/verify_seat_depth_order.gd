extends SceneTree


func _initialize() -> void:
	call_deferred("verify")


func verify() -> void:
	root.size = Vector2i(1440, 900)
	root.get_node("GameState").start_game(20261015, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	await process_frame
	room.get_node("Clock").hold(&"seat_order")
	for frame in range(8):
		await process_frame
	var actors = room.get_node("Actors")
	var core = root.get_node("GameState").sim_core
	var positions := {}
	room.get_node("ClassroomArt").set_camera_follow_enabled(false)
	room.get_node("TransitionOverlay").force_hide()
	for layer in room.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	for label in actors.find_children("*", "Label3D", true, false):
		label.visible = false
	var failed := false
	for index in actors._seated_poses:
		var actor = actors.actor_for(index)
		var seat = actors.seat_node_of(index)
		actor.global_position = actors._stand_position(seat)
		positions[index] = actor.global_position
		core._current_act[index] = "chat"
	actors._process(0.0)
	for index in actors._seated_poses:
		var actor = actors.actor_for(index)
		var seat = actors.seat_node_of(index)
		var chair = seat.get_node("Chair/Seat")
		var bounds: AABB = chair.global_transform * chair.get_aabb()
		if bounds.end.z >= actor.get_node("Sprite").global_position.z:
			push_error("Chair is in front of standing body: " + str(seat.name))
			failed = true
	await screenshot("standing_depth_fixed.png")
	for index in actors._seated_poses:
		core._current_act[index] = "study"
	actors._process(0.0)
	for index in actors._seated_poses:
		var seat = actors.seat_node_of(index)
		var chair = seat.get_node("Chair")
		assert(chair.position.is_equal_approx(chair.get_meta("rest_position")))
		var pose = actors._seated_poses[index]
		var settings = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/ui/student_poses.json")
		)
		var appearance = actors._appearances[str(core.character_id(index))]
		var original: Dictionary = settings.duplicate(true)
		original.merge(settings.bindings[appearance].layout, true)
		var desktop = seat.get_node("Desk/Top")
		var height: float = seat.to_local(desktop.to_global(desktop.get_aabb().end)).y
		assert(
			is_equal_approx(
				float(pose._settings.lower_height_gain),
				(
					float(original.lower_height_gain)
					+ height
					- float(settings.geometry_reference.desktop_top)
				)
			)
		)
		assert(actors.actor_for(index).global_position.is_equal_approx(positions[index]))
		assert(is_equal_approx(float(pose._settings.foreground_depth), 0.3024))
	await screenshot("study_depth_fixed.png")
	print(
		"PASS: standing chair behind body for 16 students; study restores chair and adapts desk depth"
	)
	quit(1 if failed else 0)


func screenshot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(
		(
			root.get_texture().get_image().save_png(
				"res://docs/art/concepts/ceiling_preview_20261015/compact_layout/" + filename
			)
			== OK
		)
	)
