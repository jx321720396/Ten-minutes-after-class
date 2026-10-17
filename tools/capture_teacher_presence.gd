extends SceneTree

const OUTPUT := "res://docs/art/concepts/teacher_back_20261016/"


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").start_game(20261016, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	current_scene = room
	room.get_node("Clock").hold(&"capture_teacher_presence")
	for frame in range(180):
		if room.has_node("OfficeHub"):
			break
		await physics_frame
	room.get_node("TransitionOverlay").force_hide()
	room.get_node("ClassroomArt").set_camera_follow_enabled(false)
	var hub = room.get_node("OfficeHub")
	for mode in ["classroom", "monitor", "office"]:
		hub.set_mode(mode)
		assert(room.get_node("TeacherPresence").visible == (mode == "classroom"))
		for frame in range(6):
			await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(OUTPUT + mode + ".png") == OK)
	print("TEACHER_PRESENCE: classroom/monitor/office screenshots passed")
	quit(0)
