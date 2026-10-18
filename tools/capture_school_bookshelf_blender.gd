extends SceneTree
## Import the Blender GLB directly, verify its bounds, then capture in Godot.

const CONFIG := "res://data/ui/school_bookshelf_blender.json"
const MODEL := "res://assets/models/bookshelf/prop_bookshelf_blender_v2.glb"
const OUTPUT := "res://docs/art/concepts/school_bookshelf_blender/godot_preview.webp"

var _meshes: int = 0
var _bounds := AABB()


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var settings: Dictionary = config["godot"]
	root.size = Vector2i(int(settings["resolution"][0]), int(settings["resolution"][1]))
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(MODEL, state)
	if error != OK:
		push_error("GLB import failed: %d" % error)
		quit(1)
		return
	var model := document.generate_scene(state)
	if model == null:
		quit(1)
		return
	var scene: Node3D = (
		load("res://scenes/game/school_bookshelf_sample_showroom.tscn").instantiate()
	)
	var previous := scene.get_node("Sample")
	scene.remove_child(previous)
	previous.free()
	model.name = "BlenderBookshelf"
	scene.add_child(model)
	root.add_child(scene)
	current_scene = scene
	_collect(model)
	print("GLB imported: ", _meshes, " meshes; bounds: ", _bounds)
	if _meshes == 0 or absf(_bounds.size.x - float(config["width"])) > 0.02:
		push_error("Unexpected model bounds")
		quit(1)
		return
	var camera := scene.get_node("Camera3D") as Camera3D
	camera.size = float(settings["camera_size"])
	camera.look_at_from_position(_v(settings["camera_position"]), _v(settings["camera_target"]))
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	error = root.get_texture().get_image().save_png(OUTPUT)
	print("Godot capture: ", error)
	current_scene = null
	scene.queue_free()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	quit(0 if error == OK else 1)


func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var bounds := mesh.global_transform * mesh.get_aabb()
		_bounds = bounds if _meshes == 0 else _bounds.merge(bounds)
		_meshes += 1
		if mesh.material_override is BaseMaterial3D:
			mesh.material_override.texture_filter = (
				BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			)
		for index in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(index) as BaseMaterial3D
			if material != null:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for child in node.get_children():
		_collect(child)


func _v(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
