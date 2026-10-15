extends SceneTree

const OUTPUT := "res://docs/art/concepts/seated_front_20261015/"


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1100, 800)
	var state = root.get_node("GameState")
	state.start_game(20261015, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	current_scene = room
	await process_frame
	room.get_node("Clock").hold(&"capture_pose")
	for frame in range(20):
		await physics_frame
	room.get_node("TransitionOverlay").force_hide()
	room.get_node("ClassroomArt").set_camera_follow_enabled(false)
	_hide_ui(room)
	var actors = room.get_node("Actors")
	var index = actors._seated_poses.keys()[0]
	var core = state.sim_core
	var actor = actors.actor_for(index)
	var seat = actors.seat_node_of(index)
	actor.global_position = actors._stand_position(seat)
	core._current_act[index] = "study"  # capture fixture, never production state logic
	actors._process(0.0)
	await _save("runtime_classroom_study.png")
	var camera = room.get_node("Camera3D")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.6
	camera.look_at_from_position(
		seat.global_position + Vector3(0, 0.83, 0.6), seat.global_position + Vector3(0, 0.65, -0.2)
	)
	for item in room.get_node("Actors").get_children():
		if item.has_node("NameTag"):
			item.get_node("NameTag").hide()
	await _save("runtime_study_close.png")
	core._current_act[index] = "chat"
	actors._process(0.0)
	await _save("runtime_stand_close.png")
	core._current_act[index] = null
	actors._process(0.0)
	await _save("runtime_idle_close.png")
	print("Runtime pose screenshots captured")
	quit(0)


func _hide_ui(node: Node) -> void:
	if node is CanvasLayer:
		node.hide()
	for child in node.get_children():
		_hide_ui(child)


func _save(filename: String) -> void:
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var result = root.get_texture().get_image().save_png(OUTPUT + filename)
	assert(result == OK)
