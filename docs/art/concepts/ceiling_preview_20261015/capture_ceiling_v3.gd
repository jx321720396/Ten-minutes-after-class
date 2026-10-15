extends SceneTree
const OUT = "res://docs/art/concepts/ceiling_preview_20261015/"
var room: Node3D
var ceiling: Node3D
var camera: Camera3D
var report = {}

func _initialize():
	call_deferred("capture")

func capture():
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440, 900)
	var state = root.get_node("GameState")
	state.start_game(20261015, 16)
	room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	current_scene = room
	await process_frame
	room.get_node("Clock").hold(&"ceiling_v3_preview")
	var art = room.get_node("ClassroomArt")
	art.set_camera_follow_enabled(false)
	for frame in range(12):
		await process_frame
	room.get_node("TransitionOverlay").force_hide()
	for node in room.find_children("*", "CanvasLayer", true, false):
		node.visible = false
	for node in room.find_children("*", "Control", true, false):
		node.visible = false
	for node in room.find_children("*", "Label3D", true, false):
		node.visible = false
	camera = room.get_node("Camera3D")
	var original_transform = camera.global_transform
	var original_fov = camera.fov
	var core = state.sim_core
	for index in range(core.node_count()):
		if not core.is_player(index):
			core._stress[index] = 0.0
	art._process(100.0)
	await save_image("v3_original_without_ceiling.png")
	var config = JSON.parse_string(FileAccess.get_file_as_string(OUT + "ceiling_v3.json"))
	var style = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/classroom_art.json"))
	var document = GLTFDocument.new()
	var gltf = GLTFState.new()
	assert(document.append_from_file(OUT + "ceiling_proposal_v3.glb", gltf) == OK)
	ceiling = document.generate_scene(gltf)
	room.add_child(ceiling)
	var old_lights = room.get_node("Room/CeilingFixtures").get_children()
	var total_energy = 0.0
	for light in old_lights:
		if light is OmniLight3D:
			total_energy += light.light_energy
			light.light_energy = 0.0
	var lights = []
	var distances = []
	for col in range(config.columns_x.size()):
		for row_index in range(config.rows_godot_z.size()):
			var light = OmniLight3D.new()
			light.name = "AlignedLamp_C%d_R%d" % [col, row_index]
			ceiling.add_child(light)
			light.position = Vector3(config.columns_x[col], config.light_center_y, config.rows_godot_z[row_index])
			light.light_energy = total_energy / float(config.columns_x.size() * config.rows_godot_z.size())
			light.omni_range = old_lights[0].omni_range
			lights.append(light)
			var diffuser = ceiling.find_child("LampDiffuser_C%d_R%d" % [col, row_index], true, false)
			assert(diffuser != null)
			var distance = light.global_position.distance_to(diffuser.global_position)
			assert(distance < float(config.alignment_tolerance))
			distances.append(distance)
	var rays = 0
	var blocked = []
	var actors = room.get_node("Actors")
	for offset in [0.0, float(style.camera.follow.max_offset)]:
		var origin = original_transform.origin + Vector3.RIGHT * offset
		for actor in actors.get_children():
			if not actor is Node3D:
				continue
			for height in config.person_sample_heights:
				var target = actor.global_position + Vector3.UP * float(height)
				rays += 1
				for mesh in ceiling.find_children("*", "MeshInstance3D", true, false):
					var hit = mesh.get_aabb().intersects_segment(mesh.to_local(origin), mesh.to_local(target))
					if hit != null:
						blocked.append({"actor": actor.name, "height": height, "camera_offset": offset, "mesh": mesh.name})
	report = {"camera_position": [original_transform.origin.x, original_transform.origin.y, original_transform.origin.z], "camera_fov": original_fov, "lamp_count": lights.size(), "lamp_alignment_distances": distances, "total_lamp_energy_before": total_energy, "total_lamp_energy_after": total_energy, "checked_rays": rays, "blocked_rays": blocked, "production_scene_modified": false}
	for pressure in [0.0, 50.0, 100.0]:
		for index in range(core.node_count()):
			if not core.is_player(index):
				core._stress[index] = pressure
		art._process(100.0)
		for light in lights:
			light.light_color = old_lights[0].light_color
		camera.global_transform = original_transform
		camera.fov = original_fov
		await save_image("v3_original_pressure_%d.png" % int(pressure))
		camera.fov = config.interior_camera_fov
		camera.look_at_from_position(Vector3(config.interior_camera_position[0], config.interior_camera_position[1], config.interior_camera_position[2]), Vector3(config.interior_camera_target[0], config.interior_camera_target[1], config.interior_camera_target[2]))
		await save_image("v3_interior_pressure_%d.png" % int(pressure))
	camera.global_transform = original_transform
	camera.global_position.x += float(style.camera.follow.max_offset)
	camera.fov = original_fov
	await save_image("v3_original_follow_right.png")
	var file = FileAccess.open(OUT + "ceiling_v3_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0)

func save_image(filename):
	for frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT + filename) == OK)
