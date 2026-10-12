extends SceneTree
## 实际 Godot 渲染的桌椅对照与单独小样；不用生成图代替模型验收。

const SHOWROOM := "res://scenes/game/school_bookshelf_sample_showroom.tscn"
const OUTPUT := "res://tools/out/school_bookshelf_sample/"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1600, 1000)
	var scene: Node3D = load(SHOWROOM).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.0).timeout
	await _save("sample")
	var sample := scene.get_node("Sample") as Node3D
	var camera := scene.get_node("Camera3D") as Camera3D
	camera.look_at_from_position(Vector3(0, 1.1, -4), Vector3(0, .95, 0))
	await _save("front")
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	var error := document.append_from_scene(sample, state)
	if error == OK:
		error = document.write_to_filesystem(
			state, "res://assets/models/bookshelf/prop_bookshelf_sample.glb"
		)
	print("GLB export: ", error)
	current_scene = null
	scene.queue_free()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	quit()


func _save(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var error := root.get_texture().get_image().save_png(OUTPUT + label + ".png")
	print("saved ", label, ": ", error)
