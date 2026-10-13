extends SceneTree

const SCENE := "res://scenes/game/normal_student_motion_sample.tscn"
const OUTPUT := "res://docs/art/concepts/normal_student_motion_sample/"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene: Node3D = load(SCENE).instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.automatic = false
	root.size = Vector2i(scene.settings["capture_size"][0], scene.settings["capture_size"][1])
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var idle := float(scene.settings["idle_duration"])
	var walk := float(scene.settings["walk_duration"])
	var chat := float(scene.settings["chat_duration"])
	var samples := {
		"idle": 0.0,
		"walk": idle + walk * 0.5,
		"chat": idle + walk + chat * 0.5,
		"sit": scene.duration() - 0.1
	}
	for pose: String in samples:
		scene.seek(samples[pose])
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(OUTPUT + "godot_" + pose + ".png")
		if error != OK:
			push_error("Capture failed: %s" % error)
			quit(1)
			return
	print("Captured idle, walk, chat and front sitting from Godot viewport")
	quit(0)
