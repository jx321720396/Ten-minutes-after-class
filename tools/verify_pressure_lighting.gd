extends SceneTree
## 真实教室的压力光照集成验证；仅在独立实例中注入压力夹具。


func _initialize() -> void:
	call_deferred("verify")


func verify() -> void:
	root.size = Vector2i(1280, 720)
	var state = root.get_node("GameState")
	state.start_game(20261015, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	current_scene = room
	for frame in range(12):
		await process_frame
	room.get_node("Clock").hold(&"pressure_capture")
	room.get_node("OfficeHub").set_mode("monitor")
	room.get_node("TransitionOverlay").force_hide()
	var art = room.get_node("ClassroomArt")
	art.set_camera_follow_enabled(false)
	var core = state.sim_core
	var environment: Environment = room.get_node("WorldEnvironment").environment
	var colors: Array[Color] = []
	var output := "res://tools/out/pressure_lighting/"
	DirAccess.make_dir_recursive_absolute(output)
	for pressure in [0.0, 50.0, 100.0]:
		for index in range(core.node_count()):
			core._stress[index] = pressure
		var before: PackedFloat64Array = core._stress.duplicate()
		var previous := environment.ambient_light_color
		art._process(0.1)
		var transition := environment.ambient_light_color
		art._process(100.0)
		colors.append(environment.ambient_light_color)
		if pressure > 0.0:
			assert(transition.g < previous.g)
			assert(transition.g > environment.ambient_light_color.g)
		assert(core._stress == before)
		for frame in range(3):
			await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png(output + str(pressure) + ".png") == OK)
	assert(colors[0].g > colors[1].g and colors[1].g > colors[2].g)
	assert(colors[0].is_equal_approx(Color("#fff4e5")))
	print("PASS: pressure lighting, smoothing, fixed camera, player exclusion, read-only stress")
	quit(0)
