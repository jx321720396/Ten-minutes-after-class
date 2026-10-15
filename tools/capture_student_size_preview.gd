extends SceneTree

const OUTPUT := "res://docs/art/concepts/seated_front_20261015/"


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 900)
	var state = root.get_node("GameState")
	state.start_game(20261015, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	current_scene = room
	await process_frame
	room.get_node("Clock").hold(&"capture_size")
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
	core._current_act[index] = "study"
	actors._process(0.0)
	actors.set_process(false)
	var pose = actor.get_node("SeatedPose")
	var camera = room.get_node("Camera3D")
	camera.fov = 30.0
	var focus = seat.global_position + Vector3(0.6, 0.6, 0)
	camera.look_at_from_position(focus + Vector3(2.4, 2.3, 6.8), focus)
	await _save("size_preview_before.png")
	# Preview only: enlarge upper body again, anchoring hands at notebook height.
	var enlarged: Dictionary = pose._settings.duplicate(true)
	var factor = 1.15 * 1.15
	var old_pixel = float(enlarged["pixel_size"])
	var split = float(enlarged["split_y"])
	var height = float(pose._textures["study"].get_height())
	var upper_step = (split * old_pixel + float(enlarged["upper_height_gain"])) / split
	var anchor = 680.0
	var shift = (split - anchor) * upper_step * (factor - 1.0)
	enlarged["pixel_size"] = old_pixel * factor
	enlarged["upper_height_gain"] = float(enlarged["upper_height_gain"]) * factor
	enlarged["lower_height_gain"] = (
		float(enlarged["lower_height_gain"]) - (height - split) * old_pixel * (factor - 1.0) - shift
	)
	pose.configure(enlarged, enlarged["bindings"].values()[0])
	pose._pose = "stand"
	pose.show_pose("study")
	await _save("size_preview_larger_32pct.png")
	# Standing preview uses the same enlargement, feet remain on the ground.
	pose.show_pose("stand")
	var standing = actor.get_node("Sprite")
	standing.show()
	standing.scale = Vector3.ONE * factor
	standing.position.y = actors.character_height * factor * 0.5
	actor.global_position = seat.global_position + Vector3(0.8, actors.foot_offset, -0.3)
	actor.get_node("NameTag").position.y = actors.character_height * factor + actors.name_gap
	await _save("size_preview_standing_32pct.png")
	print("Standing classroom preview captured; runtime configuration unchanged")
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
	assert(root.get_texture().get_image().save_png(OUTPUT + filename) == OK)
