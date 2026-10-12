extends SceneTree
## Inspect a true skinned student GLB and compare its scale with the Blender desk.

const CONFIG := "res://data/ui/school_student_blender.json"
const MODEL := "res://assets/models/school_student/char_school_student_blender_v1.glb"
const DESK := "res://assets/models/school_desk/prop_school_desk_blender_v1.glb"
const OUTPUT := "res://docs/art/concepts/school_student_blender/"

var _bounds := AABB()
var _meshes: int = 0
var _bones: int = 0
var _skins: int = 0


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var settings: Dictionary = config["godot"]
	root.size = Vector2i(int(settings["resolution"][0]), int(settings["resolution"][1]))
	var student := _import(MODEL)
	if student == null:
		quit(1)
		return
	var scene: Node3D = (
		load("res://scenes/game/school_bookshelf_sample_showroom.tscn").instantiate()
	)
	var previous := scene.get_node("Sample")
	scene.remove_child(previous)
	previous.free()
	scene.add_child(student)
	student.name = "Student"
	root.add_child(scene)
	current_scene = scene
	_collect(student)
	print(
		"Student imported: ",
		_meshes,
		" meshes; ",
		_bones,
		" bones; ",
		_skins,
		" skins; bounds: ",
		_bounds
	)
	if (
		_bones != config["bones"].size()
		or _skins == 0
		or absf(_bounds.size.y - float(config["height"])) > 0.04
	):
		push_error("Character skeleton, skin, or scale validation failed")
		quit(1)
		return
	var camera := scene.get_node("Camera3D") as Camera3D
	camera.size = float(settings["camera_size"])
	camera.look_at_from_position(_v(settings["camera_position"]), _v(settings["camera_target"]))
	await _save("godot_preview")
	camera.look_at_from_position(Vector3(0, 1.1, 4), Vector3(0, 0.85, 0))
	await _save("godot_front")
	camera.look_at_from_position(Vector3(4, 1.1, 0), Vector3(0, 0.85, 0))
	await _save("godot_side")
	var desk := _import(DESK)
	if desk == null:
		quit(1)
		return
	scene.add_child(desk)
	desk.position = _v(settings["desk_position"])
	student.position = _v(settings["student_position"])
	camera.size = float(settings["comparison_camera_size"])
	camera.look_at_from_position(_v(settings["camera_position"]), _v(settings["camera_target"]))
	await _save("godot_desk_scale")
	var report := {
		"engine": Engine.get_version_info().string,
		"meshes": _meshes,
		"bones": _bones,
		"skins": _skins,
		"height": _bounds.size.y,
		"facing": "+Z",
		"animations_included": false,
	}
	var file := FileAccess.open(OUTPUT + "godot_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	current_scene = null
	scene.queue_free()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	quit()


func _import(path: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return null
	return document.generate_scene(state)


func _collect(node: Node) -> void:
	if node is Skeleton3D:
		_bones += (node as Skeleton3D).get_bone_count()
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var bounds := mesh.global_transform * mesh.get_aabb()
		_bounds = bounds if _meshes == 0 else _bounds.merge(bounds)
		_meshes += 1
		if mesh.skin != null:
			_skins += 1
	for child in node.get_children():
		_collect(child)


func _save(label: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUTPUT + label + ".png")
	print(label, ": ", error)
	if error != OK:
		quit(1)


func _v(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
