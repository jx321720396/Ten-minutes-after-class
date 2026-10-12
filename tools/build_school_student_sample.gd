extends SceneTree
## 把生成的站姿立绘接入独立 Sprite3D 组件和桌椅同框展示，不替换现有角色。

const CONFIG := "res://data/ui/school_student_sample.json"
const ACTOR := "res://scenes/characters/school_student_sample.tscn"
const SHOWROOM := "res://scenes/game/school_student_sample_showroom.tscn"
const OUTPUT := "res://tools/out/school_student_sample/"


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var actor := Node3D.new()
	actor.name = "SchoolStudentSample"
	var atlas := AtlasTexture.new()
	atlas.atlas = load(str(data["texture"]))
	var region: Array = data["image_region"]
	atlas.region = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = atlas
	sprite.pixel_size = float(data["height"]) / float(region[3])
	sprite.position.y = float(data["height"]) * 0.5
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = float(data["alpha_threshold"])
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actor.add_child(sprite)
	_add_shadow(actor, data["shadow"])
	for child in actor.get_children():
		child.owner = actor
	if _save(actor, ACTOR) != OK:
		actor.free()
		quit(1)
		return
	actor.free()
	var scene: Node3D = load("res://scenes/game/school_desk_sample_showroom.tscn").instantiate()
	scene.name = "SchoolStudentSampleShowroom"
	scene.get_node("Original").visible = false
	scene.get_node("Sample").position = _v(data["showroom"]["desk_position"])
	var student: Node3D = load(ACTOR).instantiate()
	student.name = "Student"
	student.position = _v(data["showroom"]["student_position"])
	scene.add_child(student)
	student.owner = scene
	var camera := scene.get_node("Camera3D") as Camera3D
	camera.size = float(data["showroom"]["camera_size"])
	camera.look_at_from_position(
		_v(data["showroom"]["camera_position"]), _v(data["showroom"]["camera_target"])
	)
	if _save(scene, SHOWROOM) != OK:
		scene.free()
		quit(1)
		return
	print("saved ", ACTOR, " and ", SHOWROOM)
	if DisplayServer.get_name() == "headless":
		scene.free()
		quit()
		return
	root.size = Vector2i(1600, 1000)
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var error := root.get_texture().get_image().save_png(OUTPUT + "standing.png")
	print("screenshot: ", error)
	current_scene = null
	scene.queue_free()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	quit(error)


func _add_shadow(actor: Node3D, definition: Dictionary) -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/classroom_contact_shadow.gdshader")
	material.set_shader_parameter("shadow_color", Color(str(definition["color"])))
	material.set_shader_parameter("softness", float(definition["softness"]))
	material.set_shader_parameter("floor_height", float(definition["height"]))
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(float(definition["size"][0]), float(definition["size"][1]))
	mesh.material = material
	var shadow := MeshInstance3D.new()
	shadow.name = "ContactShadow"
	shadow.mesh = mesh
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actor.add_child(shadow)


func _save(node: Node, path: String) -> Error:
	var packed := PackedScene.new()
	var error := packed.pack(node)
	if error != OK:
		return error
	return ResourceSaver.save(packed, path)


func _v(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
