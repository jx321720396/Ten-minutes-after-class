extends SceneTree
## Compare the imported Blender desk in a showroom and a disposable classroom instance.

const CONFIG := "res://data/ui/school_desk_blender.json"
const MODEL := "res://assets/models/school_desk/prop_school_desk_blender_v1.glb"
const OUTPUT := "res://docs/art/concepts/classroom_blender_rollout/01_desk/"

var _config: Dictionary
var _template: Node3D
var _mesh_count: int = 0
var _bounds := AABB()


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(MODEL, state) != OK:
		quit(1)
		return
	_template = document.generate_scene(state)
	if _template == null:
		quit(1)
		return
	var scene: Node3D = load("res://scenes/game/school_desk_sample_showroom.tscn").instantiate()
	var previous := scene.get_node("Sample")
	scene.remove_child(previous)
	previous.free()
	var sample := _template.duplicate() as Node3D
	sample.name = "BlenderDesk"
	scene.add_child(sample)
	root.add_child(scene)
	current_scene = scene
	_verify_meshes(sample)
	if _mesh_count != 4 or absf(_bounds.end.y - 0.761) > 0.005:
		push_error("Unexpected exported desk mesh count or height")
		quit(1)
		return
	var settings: Dictionary = _config["godot"]
	root.size = Vector2i(int(settings["resolution"][0]), int(settings["resolution"][1]))
	var original := scene.get_node("Original") as Node3D
	original.get_node("Chair").visible = false
	original.position = Vector3(-float(settings["comparison_offset"]), 0, 0)
	sample.position = Vector3(float(settings["comparison_offset"]), 0, 0)
	var camera := scene.get_node("Camera3D") as Camera3D
	camera.size = float(settings["comparison_camera_size"])
	camera.look_at_from_position(
		_v(settings["comparison_camera_position"]), _v(settings["camera_target"])
	)
	await _save("godot_comparison")
	original.visible = false
	sample.position = Vector3.ZERO
	camera.size = float(settings["camera_size"])
	camera.look_at_from_position(_v(settings["camera_position"]), _v(settings["camera_target"]))
	await _save("godot_preview")
	current_scene = null
	scene.queue_free()
	await process_frame
	await _classroom()
	_template.free()
	quit()


func _classroom() -> void:
	var settings: Dictionary = _config["classroom_capture"]
	root.size = Vector2i(1920, 1080)
	root.get_node("GameState").start_game(int(settings["seed"]), int(settings["npc_count"]))
	var scene: Node = load("res://scenes/game/classroom3D.tscn").instantiate()
	scene.get_node("Roam").enabled = false
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.get_node("Clock").hold(&"desk_blender_capture")
	for frame in range(int(settings["warmup_frames"])):
		await process_frame
	scene.get_node("TransitionOverlay").force_hide()
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for child in scene.get_children():
		if child is Control:
			(child as Control).visible = false
	for label in scene.get_node("Actors").find_children("*", "Label3D", true, false):
		(label as Label3D).visible = false
	await _save("classroom_before")
	var replaced := 0
	var preserved: Array = []
	for seat in scene.get_node("Seats").get_children():
		var original := seat.get_node_or_null("Desk") as Node3D
		if original == null:
			continue
		(
			preserved
			. append(
				[
					seat,
					seat.get_node("StandSpot").transform,
					seat.get_node("SitPoint").transform,
					seat.get_node("NavBlocker/Blocker").transform,
					seat.get_node("NavBlocker/Blocker").shape,
				]
			)
		)
		original.visible = false
		var desk := _template.duplicate() as Node3D
		desk.name = "BlenderDeskPreview"
		seat.add_child(desk)
		replaced += 1
	for entry in preserved:
		var seat: Node = entry[0]
		assert(seat.get_node("StandSpot").transform == entry[1])
		assert(seat.get_node("SitPoint").transform == entry[2])
		assert(seat.get_node("NavBlocker/Blocker").transform == entry[3])
		assert(seat.get_node("NavBlocker/Blocker").shape == entry[4])
	await _save("classroom_after")
	print("classroom preview replaced desks: ", replaced, "; markers and physics kept intact")
	var report := {
		"engine": Engine.get_version_info().string,
		"seed": settings["seed"],
		"npc_count": settings["npc_count"],
		"replaced_desks": replaced,
		"mesh_count_per_desk": _mesh_count,
		"markers_and_collision_unchanged": true,
		"production_scene_saved": false,
	}
	var file := FileAccess.open(OUTPUT + "godot_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	current_scene = null
	scene.queue_free()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _verify_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		var bounds := instance.global_transform * instance.get_aabb()
		_bounds = bounds if _mesh_count == 0 else _bounds.merge(bounds)
		_mesh_count += 1
		for index in range(instance.mesh.get_surface_count()):
			var material := instance.get_active_material(index) as BaseMaterial3D
			if material != null:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for child in node.get_children():
		_verify_meshes(child)
	if node.name == "BlenderDesk":
		print("desk GLB validated: ", _mesh_count, " meshes; bounds: ", _bounds)


func _save(label: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUTPUT + label + ".png")
	print(label, " capture: ", error)
	if error != OK:
		quit(1)


func _v(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
