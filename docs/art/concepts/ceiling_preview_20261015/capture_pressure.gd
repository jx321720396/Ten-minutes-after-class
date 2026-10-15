extends SceneTree
## Temporary runtime preview: Blender ceiling + unchanged production pressure light.
const OUT = "res://docs/art/concepts/ceiling_preview_20261015/"

func _initialize():
	call_deferred("capture")

func capture():
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440, 900)
	var state = root.get_node("GameState")
	state.start_game(20261015, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	current_scene = room
	await process_frame
	room.get_node("Clock").hold(&"ceiling_pressure_preview")
	var art = room.get_node("ClassroomArt")
	art.set_camera_follow_enabled(false)
	for frame in range(12):
		await process_frame
	room.get_node("TransitionOverlay").force_hide()
	for layer in room.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	for control in room.find_children("*", "Control", true, false):
		control.visible = false
	for label in room.find_children("*", "Label3D", true, false):
		label.visible = false
	var document = GLTFDocument.new()
	var gltf = GLTFState.new()
	assert(document.append_from_file(OUT + "ceiling_proposal.glb", gltf) == OK)
	var ceiling = document.generate_scene(gltf)
	room.add_child(ceiling)
	var camera = room.get_node("Camera3D")
	camera.fov = 62.0
	camera.look_at_from_position(Vector3(-0.6, 2.05, 5.7), Vector3(0.1, 1.95, -1.0))
	var core = state.sim_core
	var report = []
	for pressure in [0.0, 50.0, 100.0]:
		for index in range(core.node_count()):
			if not core.is_player(index):
				core._stress[index] = pressure
		var before = core._stress.duplicate()
		art._process(100.0)
		assert(core._stress == before)
		for frame in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(OUT + "pressure_" + str(int(pressure)) + ".png") == OK)
		var environment = room.get_node("WorldEnvironment").environment
		report.append({"pressure": pressure, "ambient_color": environment.ambient_light_color.to_html(), "ambient_energy": environment.ambient_light_energy})
	var file = FileAccess.open(OUT + "pressure_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("PASS: Blender ceiling + production pressure lighting; screenshots 0/50/100; read-only stress check")
	quit(0)
