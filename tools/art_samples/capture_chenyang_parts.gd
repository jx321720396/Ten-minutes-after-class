extends SceneTree
## Reproducible isolated art sample. Does not replace production actors.

const OUTPUT := "res://docs/art/concepts/modular_student_sample_20261015/"
const FRAMES := "res://tools/out/modular_student_sample_frames/"
const RIG := preload("res://tools/art_samples/chenyang_parts.gd")
var samples: Array[Node3D] = []


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1200, 760)
	var world = load("res://scenes/game/school_student_sample_showroom.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.get_node("Student").hide()
	world.get_node("Sample").hide()
	world.get_node("Original").hide()
	var camera: Camera3D = world.get_node("Camera3D")
	camera.size = 2.3
	camera.look_at_from_position(Vector3(0, 2.5, 5), Vector3(0, .85, 0))
	var titles := ["自然站立 · 轻微呼吸", "聊天 · 肩肘联动", "迈步 · 分件运动测试"]
	for index in range(3):
		var rig := RIG.new()
		world.add_child(rig)
		rig.position.x = (index - 1) * 1.13
		samples.append(rig)
		_add_title(titles[index], index)
	for frame in range(5):
		await process_frame
	_set_poses(.65)
	await _save("parts_assembled_sample.png")
	DirAccess.make_dir_recursive_absolute(FRAMES)
	for frame in range(72):
		_set_poses(float(frame) / 24.0)
		await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(FRAMES + "%03d.png" % frame) == OK)
	world.queue_free()
	await process_frame
	await _classroom_capture()
	print("MODULAR_SAMPLE: PASS 15 separate parts; idle/chat/walk; classroom capture")
	quit(0)


func _set_poses(time: float) -> void:
	for index in range(samples.size()):
		samples[index].set_sample_pose(["idle", "chat", "walk"][index], time)


func _add_title(text: String, index: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = Vector2(index * 400, 24)
	label.size = Vector2(400, 45)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_color_override("font_color", Color("24434a"))
	current_scene.add_child(label)


func _classroom_capture() -> void:
	var state = root.get_node("GameState")
	state.start_game(20261015, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	current_scene = room
	for frame in range(60):
		await physics_frame
	room.get_node("Clock").hold(&"modular_sample")
	room.get_node("OfficeHub").set_mode("monitor")
	room.get_node("ClassroomArt").set_camera_follow_enabled(false)
	var actors = room.get_node("Actors")
	for index in actors._seated_poses:
		state.sim_core._current_act[index] = "chat"
	actors._process(0.0)
	# Select Chen Yang by asset binding only in this offline art fixture.
	var selected := -1
	for index in actors._seated_poses:
		if actors._seated_poses[index]._binding.standing.ends_with("char_01_body_base_v1.png"):
			selected = index
	assert(selected >= 0)
	actors.set_process(false)
	var actor = actors.actor_for(selected)
	actor.get_node("Sprite").hide()
	var rig := RIG.new()
	room.add_child(rig)
	rig.global_position = actor.global_position
	rig.set_sample_pose("idle", .6)
	room.get_node("TransitionOverlay").force_hide()
	room.get_node("TransitionOverlay").hide()
	await _save("classroom_sample.png")
	for child in room.find_children("*", "CanvasLayer", true, false):
		child.hide()
	for other in actors.get_children():
		if other is Node3D:
			other.hide()
	var camera: Camera3D = room.get_node("Camera3D")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.15
	camera.look_at_from_position(
		rig.global_position + Vector3(0, 2.0, 4), rig.global_position + Vector3(0, .85, 0)
	)
	await _save("classroom_sample_close.png")


func _save(filename: String) -> void:
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + filename) == OK)
